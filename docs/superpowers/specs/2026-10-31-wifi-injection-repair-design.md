# PathChanger — Wi-Fi Injection Repair Program (Design Spec)

- **Date:** 2026-10-31
- **Status:** Draft for owner review
- **Evidence basis:** Live supervised session, 2026-10-31 (owner present; phone iOS 27.2, iPhone16,2, UDID `00008130-…9A001C`; app built fresh from `main` @ `f631141`, artifact sha256 `5b603c8ea7e07fdd…`)
- **Author:** ZCode session (lead engineer protocol)

## 1. Problem statement

The product's five modes do not work end-to-end. The user's experience: unstable USB/Wi-Fi behavior, unreliable tunnel start, and no mode ever visibly spoofs the device. Live testing on 2026-10-31 root-caused this to **twelve stacked defects**, one of which is the deepest root cause (Developer Disk Image never mounted) and one of which is a hard protocol seam failure (Swift/Python acknowledgement key mismatch). Independently, the correct device recipe for this phone/OS was discovered and proven live (map movement observed by the owner).

## 2. Live-proven facts (2026-10-31 session)

Each item below was verified live during the supervised session, not inferred:

1. **Developer Disk Image (DDI) was not mounted** on the phone (`mounter list` → `[]`). DVT services connected but every location `set()` silently did not apply. After `mounter auto-mount` (cryptex download + Apple personalization + mount, ~30 s): **the same injection moved the map** (owner observed).
2. **Held-session permanence**: a held `developer dvt simulate-location set` session kept the pin at the target for **3 minutes** (owner observed), snapping back only when the hold ended — confirming the held-session persistence model.
3. **Wi-Fi + VPN coexistence**: with a phone-side VPN active, a session **established and held for 60 s** over direct `--udid` (auto no-root userspace tunnel) — pin moved and stayed (owner observed). Toggling the VPN **mid-session** kills the underlying connection → iOS snaps back (unavoidable platform behavior; the app must auto-re-pin on channel rebuild).
4. **The working recipe** (proven end to end): phone awake + Auto-Lock off → usbmux `ConnectionType: Network` visibility (Wi-Fi) → direct `--udid` → pymobiledevice3's built-in no-root userspace tunnel fallback → held DVT session → **DDI mounted** → **pymobiledevice3 11.49.1**.
5. The **native RSD tunnel** (`remote start-tunnel --native`) is unreliable for DVT on this device: DVT service ports refused immediately/briefly-usable/refused again across three tunnel instances; in its two "successful" `set()` windows the phone did not move. RSD listener itself stayed green throughout (why the GUI said "Tunnel live").
6. The **userspace `remote start-tunnel`** variant requires root (collides with locked decision #6: never execute user-writable Python as root). Not viable unprivileged. The CLI's **internal no-root userspace fallback** (pytcp) is the viable mechanism.
7. Swift/Python seam: Python emits `actual_channel`; Swift decodes `channel` → every successful socket response fails acknowledgement (`PersistentBridgeWireResponse.acknowledgement()` requires `channel`).
8. Device discovery/selection **loses the device mid-session** while `remote browse` still reports it authenticated+connected and the tunnel serves it.
9. **Reconnect** rebuilds the tunnel **without `--udid`** (degenerate argv) because it lost the device.
10. **Tunnel adoption on relaunch fails**: fresh app launch shows "Start tunnel" (idle) while a live tunnel process with valid RSD runs.
11. **App bootstrap argv stale**: `lockdown wifi-connections --state on` — `--state` no longer exists in pymobiledevice3 ≥ 11.4x (correct form: positional `on`). The rolling-latest policy has a real cost: CLI argv drift.
12. **Truth-chrome invisible to accessibility** (Connection/Application/Movement expose no AX values); **FileLogger silent** (zero bytes across launch/discovery/tunnel/injection); AX `setValue` does not reach SwiftUI bindings; `DeviceManager.runPython` leaks pipe fds on timeout/launch-failure paths (regression of the `feb2f45` class).

## 3. Owner requirements (verbatim-derived, binding)

- R1: A spoof **persists as long as the user wants**; only the user's Clear (or app exit with their choice) ends it.
- R2: The connection/tunnel **must not break on its own**; the user kills it manually or on app exit.
- R3: **All five modes work over Wi-Fi**, and the app is verified mode-by-mode through the GUI.
- R4: **Phone VPN coexistence**: VPN on must not block spoofing; a VPN toggle mid-session results in brief revert → automatic re-pin.
- R5: "Everything works together, not against each other" — one truth per layer; honest state everywhere.

## 4. Architecture

### Layer 0 — Device preparation gains DDI mounting (root-cause fix)
- On device-ready (and before any injection), the app checks DDI mount status and, if absent, downloads + mounts the personalized image via the `mounter auto-mount` mechanism through the persistent helper (service-level API, not CLI parsing where a service API exists).
- GUI shows honest progress: "Preparing device — mounting developer image…". Injection is blocked with a truthful reason until the mount succeeds.
- DDI status participates in the three-dimensional state model (device readiness dimension), not a collapsed Boolean.

### Layer 1 — Injection lane rewired to the proven recipe
- `PersistentLocationBridge`/`location_bridge.py` create DVT sessions via **direct `--udid` (usbmux, USB and Network/Wi-Fi) with pymobiledevice3's internal no-root userspace tunnel fallback** — the mechanism proven live. The helper's cached-service model (repeated `set()` at 10–20 ms) is retained; it is what all five modes need.
- The native RSD tunnel is **demoted out of the injection path**. It remains available for discovery/monitoring and for devices where direct-udid is unavailable, but injection must not depend on it.
- RSD endpoint state is **tied to tunnel generation** — never reused across tunnel instances (kills the stale-RSD dialing observed live).
- Held-session semantics preserved: helper process holds the session; terminating it is the real Clear; app exit offers Clear/Preserve/Cancel (existing flow).

### Layer 2 — The twelve documented defects (TDD, failing-test-first each)
| # | Defect | Fix target |
|---|---|---|
| 1 | Ack-key mismatch (`channel` vs `actual_channel`) | `PersistentBridgeWireResponse` CodingKey + fixture; **golden-fixture contract test** pinning the real Python response shape both directions |
| 2 | Device vanishes mid-session | `DeviceManager` discovery merge/prune: RemotePairing-connected devices persist; known-pairing-record devices survive poll failures |
| 3 | Reconnect drops `--udid` | `TunneldManager.reconnectNow`/`restartTunnel` rebuild argv from the tracked session identity, not from lost UI state |
| 4 | Adoption fails on relaunch | `adoptRunningTunnelIfPresent`: verify against `tunnel.log` freshness + `isUsable`; add start-request-while-adoptable case |
| 5 | Stale RSD reuse | tunnel-generation-keyed endpoint cache (see Layer 1) |
| 6 | Bootstrap argv stale | `DevicePreparationPlanner.wifiBootstrapCommands` → positional `on`; add a CLI-argv smoke test against the managed runtime (catches future drift) |
| 7 | Truth-chrome AX-invisible | `LocationStatusPresentation` exposes discrete, labeled AX values |
| 8 | Silent FileLogger | `FileLogger` flush/write verification at startup; launch/discovery/tunnel/injection events must land in `~/Library/Logs/PathChanger/` |
| 9 | fd-leak regression | `DeviceManager.runPython` drain+close on timeout and catch paths (mirror `runCommand`) |
| 10 | Start-from-`.error` dead-end | `(.error, .startRequested)` transition via stop→idle→start; keep lastError visible until success |
| 11 | DDI never mounted | Layer 0 |
| 12 | Native-RSD lane unreliability | Layer 1 (lane demotion) |

### Layer 3 — Lifecycle and honest state (owner requirements)
- Spoof persists until explicit Clear or app exit (existing dialog). No other path clears.
- Connection loss (VPN toggle, phone lock, Wi-Fi drop) → status shows **Uncertain/Lost** honestly, movement pauses, and **automatic recovery re-pins the last desired coordinate** once the channel rebuilds and a fresh applied receipt lands (existing recovery flow; now actually reachable because the lane works).
- The GUI's connection-of-record is the held session (helper), not the native tunnel.

## 5. Verification plan

- Repo protocol: FlowDeck Debug + Release builds green; full suite green in ReleaseTesting (no unexplained count decrease); generated project matches `project.yml`; GUI path verified for user-visible behavior.
- New automated tests: golden-fixture protocol contract; DDI-preparation (fake mounter); lane selection (usbmux-first, RSD fallback only when usbmux absent); tunnel-generation-keyed RSD cache; reconnect argv identity; discovery persistence; mounter-argv smoke against the managed runtime; fd-stability loop.
- **Live acceptance (owner-supervised, per session)**: (1) Teleport end-to-end through GUI on Wi-Fi → map moves and holds ≥ 3 min; (2) Clear through GUI → returns to real GPS; (3) VPN toggle mid-spoof → honest revert + automatic re-pin; (4) all five modes over Wi-Fi; (5) app relaunch during an active spoof → adoption/preservation path; (6) fd count stable across a long session.
- Device tests remain opt-in (`PATHCHANGER_RUN_DEVICE_TESTS=1`) only under the supervised-session protocol.

## 6. Delivery stages (Wi-Fi-first)

- **Stage 1 — One working end-to-end path (highest value):** Defects 1 (ack-key + fixture), 11 (DDI mount), 12/5 (lane rewiring + generation-keyed RSD). Gate: Teleport through the GUI on Wi-Fi moves and holds the map (owner-watched), Clear works, all gates green.
- **Stage 2 — Stable lifecycle:** Defects 2, 3, 4, 6, 10. Gate: discovery survives navigation and refresh cycles; reconnect preserves identity; relaunch adopts; bootstrap argv correct; recovery re-pins after VPN toggle (R4).
- **Stage 3 — Five modes + hardening:** Defects 7, 8, 9; five-mode GUI acceptance walk; VPN coexistence verification; long-session fd check. Gate: full acceptance matrix; owner's personal Task-17 matrix on the repaired product.

## 7. Constraints and governance

- No implementation on `main`; new branch off `main` in the plan-required worktree root (`$HOME/.config/superpowers/worktrees/PathChanger/`).
- Commits, pushes, and remote writes require explicit owner approval; documentation commits separate from product commits.
- Privilege unchanged: unprivileged discovery/preparation; no elevation introduced (no-root userspace tunnel only). Never accept authorization prompts.
- pymobiledevice3 stays rolling-latest; the runtime was already upgraded 11.43.1 → 11.49.1 during the live session (managed venv; helper respawned). Diagnostic floor decision: bump `pymobiledevice3MinimumVersion` guidance to a version with current mounter/fallback behavior (≥ 11.49.1 recommended) — diagnostic floor only, not a pin.
- Stale `AGENTS.md` open items and the docs-gap from the unrecorded 2026-10-25 merge are documentation work, separate from product commits.

## 8. Open questions

- None blocking. VPN recovery cadence (immediate vs. debounced re-pin) is an implementation detail settled in Stage 2 with a test.
