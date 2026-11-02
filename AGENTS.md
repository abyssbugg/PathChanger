# PathChanger — Project Rules (ALWAYS LOAD)

You are working in the **PathChanger** project. This file is the canonical continuity contract for every coding-agent session started in this directory, whatever the agent. It holds **WHAT is true**: project identity, non-negotiable locked decisions, the product model, the docs map, the gotcha ledger, and current open items. **`CLAUDE.md` holds the binding operating protocol (HOW to work). Read both together before acting.** Do not invent conflicting decisions.

**CRITICAL: You must open and read the contents of `CLAUDE.md` before writing any code.**

> Provenance: this file was created 2026-10-23 by owner direction, adopting the two-file WHAT/HOW contract pattern (and the gotcha-ledger discipline) from the WeAnime project. Completed entries retire to `docs/archive/AGENT_LOG.md`; this file stays lean.

---

## Project identity

| Field | Value |
|---|---|
| **Name** | **PathChanger** |
| **What it is** | macOS 14+ SwiftUI application that simulates GPS location on trusted iOS 17+ devices via `pymobiledevice3` (teleport, jump, two-spot, multi-spot/route, joystick) |
| **Local checkout** | `/Users/datamatics/dev/PathChanger` — **documentation/recovery checkout only**; no product implementation on `main` |
| **Implementation worktree** | `/Users/datamatics/dev/PathChanger.worktrees/five-mode-reliability` (branch `feature/five-mode-reliability`) — observed 2026-10-23; the five-mode plan names `$HOME/.config/superpowers/worktrees/PathChanger/` as the required root. **Reconcile this path discrepancy before relying on either location.** |
| **Remote** | `github.com/abyssbugg/PathChanger` |
| **Origin** | Clean renamed recovery of `abyssbugg/LocationSpoofer` @ `e8aa39f2` (MIT retained; see `NOTICE.md`) |
| **Stack** | Swift 5.9, SwiftUI, macOS 14+ · Python 3.9+ with `pymobiledevice3` ≥ 6.1.5 · SwiftPM (Sparkle pinned `exact: "2.8.1"`) + XcodeGen-generated Xcode wrapper · FlowDeck for all Apple tooling |
| **Phase** | Five-mode persistence & reliability program in progress (plan: `docs/superpowers/plans/2026-09-12-five-mode-persistence-reliability.md`). Stage 0 and Stage 1 closed; canonical Stage 2 unauthorized. |
| **Owner intent** | Reliable, honest, integrated location-spoofing product — the GUI is the contract; priority order: reliability → correct functionality → truthful state synchronization → connection stability → GUI consistency |

---

## Non-negotiable decisions (LOCKED)

1. **Five user modes, exactly**: Teleport, Jump Teleport, Two-Spot, Multi-Spot, Joystick (`PRODUCT_REQUIREMENTS.md` §2.1). Shared engines are allowed; separate behavior contracts and end-to-end tests are not negotiable.
2. **The GUI is the contract.** A service- or script-only success is insufficient when the user workflow is GUI-driven (`CLAUDE.md` §8, invariant 1).
3. **A successfully applied spoof persists until explicit Clear/Reset** or an honestly-reported unavoidable external loss (`PRODUCT_REQUIREMENTS.md` §1). Pause/stop/completion/mode-change/cooldown must never clear location.
4. **State truth is three-dimensional**: connection, location-application, and movement are separate dimensions; never collapse them into one Boolean (`PRODUCT_REQUIREMENTS.md` §4).
5. **One tunnel lifecycle owner**: `TunneldManager.shared`. One canonical device identity (deduplicated). One geodesy source (`Geo`). `AppState` is the composition boundary.
6. **Privilege is explicit and centralized**: all elevation flows through `PrivilegedTunnelCommand` (exact-argv allowlist, quoting, HOME preservation, PID validation), gated by `TunnelStartPolicy` — only explicit user action may elevate. Never execute user-writable Python/packages as root. Discovery, install, and device listing stay unprivileged.
7. **FlowDeck only** for Apple build/test/run/UI/simulator/device work. Raw `xcodebuild`/`xcrun`/`simctl`/`devicectl`/`xcode-select`/`instruments` are prohibited. Never hand-edit `project.pbxproj`; change `project.yml` and regenerate, then run `scripts/validate-xcode-wrapper.py`.
8. **`Package.swift` is the SwiftPM source of truth**; Sparkle stays pinned exactly (a `from:` range once drifted between SwiftPM and Xcode lockfiles).
9. **Device- and privilege-dependent tests are opt-in** via `PATHCHANGER_RUN_DEVICE_TESTS=1`; never set it, accept an admin prompt, or touch a physical device without explicit owner authorization and an approved plan.
10. **Prohibited packaging scripts**: do not execute `build-app-bundle.sh`, `build.sh`, or `install.sh` while they remain fail-open/destructive (`CLAUDE.md` §10). Known hazards include suppressed signing failures and direct `/Applications` mutation.
11. **Git discipline**: no implementation on `main`; work in the authorized worktree; Stage 0/1 tags and accepted commits immutable (no rebase/squash/amend); fast-forward-only promotions; commits/pushes/tags need explicit approval; documentation commits stay separate from product commits.
12. **Stage 0 and Stage 1 are closed** (evidence tags in the private `abyssbugg/PathChanger-Evidence` repository). **Canonical Stage 2 remains unauthorized.** The five-mode plan is owner-authorized for its named Git operations only.
13. **Canonical dependency name** is `pymobiledevice3` — use that name in source, docs, logs, and tests (`PRODUCT_REQUIREMENTS.md` §2.2).
14. **iOS 18+ is allowed** (through iOS 27) with caution UI (`needsModernIOSCaution`); do not re-add the old hard rejection.
15. **Python dependency policy (owner, 2026-10-23): rolling latest, pyenv authority.** No exact pins and no hash locks for pymobiledevice3; the managed runtime venv is built from the newest pyenv Python ≥ 3.13 (Homebrew python is fallback bootstrap only); installs are `pip install -U pymobiledevice3`; the six-capability probe is the compatibility gate; `pymobiledevice3MinimumVersion` (11.12.5) is a diagnostic floor, not a pin. Swift-side pinning (Sparkle exact) is unchanged.
15. **The binding product contract is `PRODUCT_REQUIREMENTS.md`**; the binding operating protocol is `CLAUDE.md`. This file registers decisions already made there and observations from repository evidence — it does not create new authority.

---

## Operating protocol (HOW to work — BINDING, lives in `CLAUDE.md`)

The full operating protocol lives in **`CLAUDE.md`** and is binding for every session: sequential-thinking decomposition before code, deliberate tool selection, comprehension before change, no bug-on-bug patching (`TEMPORARY:` markers with reason and removal condition), phases sequential with subagent-parallel work inside a phase, the standing verification gate, honest reporting (confirmed / documented-but-asserted / suspected / unknown), and flagging request gaps instead of assuming.

**CRITICAL: You must open and read the contents of `CLAUDE.md` before writing any code.** This file (AGENTS.md) is the WHAT — locked facts, gotchas, open items; CLAUDE.md is the HOW.

---

## Product model (what we build)

```
User → SwiftUI GUI → AppState (composition root) / domain state managers
    → DevLocationBridge / PersistentLocationBridge (pymobiledevice3 adapter)
    → TunneldManager tunnel lifecycle (USB lockdown / Wi-Fi remote / daemon)
    → iOS device DVT simulate-location service → spoofed location
```

- **Five modes**: Teleport (1 hop), Jump (≤12 ordered hops, index advances only on acknowledged injection), Two-Spot (traverse between two endpoints), Multi-Spot (≤24-waypoint interpolated route, optional loop), Joystick (real-time steering, latest-wins queue).
- **Tunnel modes**: Auto (USB→Wi-Fi→daemon fallback), USB (lockdown start-tunnel), Wi-Fi (remote start-tunnel -t wifi), Daemon (remote tunneld; per-device RSD via its HTTP API on 127.0.0.1:49151).
- **Held-session semantics**: pymobiledevice3 10.x `simulate-location set` applies the pin then blocks; the process must stay running or iOS snaps back to real GPS. Terminating the held session *is* the real clear.
- **Persistent bridge**: `scripts/location_bridge.py` — one long-lived Python process speaking newline-delimited JSON over stdio (~10–20 ms/update vs ~100 ms subprocess), caching DVT services per `udid:rsd` with invalidation-on-error.
- **Companion target**: `PathChangerCompanion` — separate iOS 17 Swift package (MultipeerConnectivity) for live status + emergency stop; a separate integration boundary, not part of the macOS target.

---

## Continuity rules for every new session in this folder

When the user says "continue PathChanger" / resumes work here:

1. **Assume this AGENTS.md + `CLAUDE.md` + `PRODUCT_REQUIREMENTS.md` + `docs/` are ground truth.** Verify current Git/worktree/process state fresh — do not copy facts from prose.
2. Restate locked decisions briefly only if the user seems lost — do not re-litigate them.
3. Do not implement on `main`, do not execute prohibited packaging scripts, do not run raw Apple CLIs, and do not start tunnels or touch devices without authorization.
4. Check the implementation worktree and the five-mode plan status before claiming what is or is not done; the plan file on `main` can lag behind worktree branches (see open items).
5. Keep this file current: when decisions change, update it; when work completes, retire its entry to `docs/archive/AGENT_LOG.md`; promote any new durable gotcha into the ledger below. Never delete history silently.
6. Report using the acceptance language from `CLAUDE.md` §2 (Confirmed / Documented-but-asserted / Suspected / Unknown); never report fixed/passing/complete without fresh evidence.

Resume = open an agent in `/Users/datamatics/dev/PathChanger` (or the implementation worktree for product work) and say "continue PathChanger". Inspect branch, HEAD, worktrees, and status before acting.

---

## Docs map (in-repo)

| Area | Files |
|---|---|
| **Binding contracts** | `CLAUDE.md` (operating protocol, HOW) · `PRODUCT_REQUIREMENTS.md` (product contract, WHAT the product must do) · this file (project rules, WHAT is true) |
| **Active plan** | `docs/superpowers/plans/2026-09-12-five-mode-persistence-reliability.md` (owner-authorized; tasks, branches, gates, stop conditions) · `docs/superpowers/plans/2026-08-16-pctnhc-in-place-port.md` (historical port plan) |
| **ADRs** | `docs/adr/001-python-bridge-architecture.md` (hybrid bridge) · `docs/adr/002-actor-based-caching.md` · `docs/adr/003-state-machine-tunnel-management.md` |
| **Historical audit baseline (Aug 23, 2026)** | `Consolidated-Source-Of-Truth-Aug-23-2026.md` (reconciled baseline — start here) · `Architecture-Note` · `Tunnel-Lifecycle-Architecture` · `Tunnel-Functional-Modules-Data-Flows` · `Tunnel-Dependencies-Integrations-Audit` · `Tunnel-Security-Reliability-Audit` · `PathChanger-Tunnel-Lifecycle-Final-Assessment` · `Final-Report-Completion` · `Final-Coverage-Ledger-and-Audit-Conclusion` · `Stage-0-Verification-and-Acceptance-Brief` (all `-Aug-23-2026.md` at repo root) · `Todo-aug-23-2026.md` / `todo-aug-11-2026.md` (historical roadmaps) |
| **Deployment (pre-audit, Dec 2025 — superseded in part by the Aug-2026 audit lineage)** | `DEPLOYMENT/README.md` · `01_PRE_DEPLOYMENT_VERIFICATION.sh` · `02_CODE_SIGNING_PROCEDURES.md` · `03_SECURITY_VERIFICATION_CHECKLIST.md` · `04_PERFORMANCE_BASELINE.md` · `05_UAT_SIGN_OFF.md` · `TUNNEL_MODES.md` |
| **Human-facing** | `README.md` (partially stale — see open items) · `CHANGELOG.md` (dates predate the recovery; treat with caution) · `NOTICE.md` (LocationSpoofer provenance) · `CONTRIBUTING.md` |
| **Evidence** | Private `abyssbugg/PathChanger-Evidence` repository — authoritative for governed-run acceptance records, completion tags, and cleanup receipts |

---

## Gotcha ledger (read before touching the matching area)

Every entry below was paid for — in code comments, audit findings, or live incidents. Cite and verify against current source before relying on a line number.

### Toolchain & build

- **`swift test` requires full Xcode.** Apple Command Line Tools alone provide no `xctest`/`XCTest.framework`; CI is the XCTest source of truth on CLT-only machines (README §Testing).
- **The scheme's test action runs the `ReleaseTesting` configuration** — release-derived with testability and DEBUG-only hooks, *not* shipping Release. Always state this caveat when reporting "Release tests" (`CLAUDE.md` §9).
- **Two project definitions, one truth**: `Package.swift` is the SwiftPM source; `PathChanger.xcodeproj` is an XcodeGen wrapper generated from `project.yml`. Never hand-edit `project.pbxproj`; run `scripts/validate-xcode-wrapper.py` after every `project.yml` change and before committing regenerated files.
- **Sparkle must stay `exact:`-pinned** — a `from:` range once drifted between SwiftPM and Xcode lockfiles (`Package.swift` comment).
- **`scripts/test.sh` exists because of two local-environment traps**: (1) iCloud/file-provider-synced checkouts re-stamp xattrs and break codesign — build under `~/Library/Caches/PathChanger/build` via `--scratch-path`, `xattr -cr`, retry once; (2) the test bundle's `@rpath` needs the Sparkle.framework symlink into `PackageFrameworks/`. It never sets `PATHCHANGER_RUN_DEVICE_TESTS`.
- **Python policy (owner, 2026-10-23): rolling latest, pyenv authority.** The app executes only its managed venv (`~/Library/Application Support/PathChanger/runtime/location`), now built from the newest pyenv Python ≥ 3.13 with `pip install -U pymobiledevice3` (11.43.1 as of 2026-10-25; previous 11.12.5 runtime preserved at `runtime/location.rollback`). Homebrew Python is fallback bootstrap only; system Pythons are irrelevant to the app. `pymobiledevice3MinimumVersion` (11.12.5) is a diagnostic floor, not a pin (`Core/PythonPathResolver.swift`).
- **`.env.example` is unrelated leftover boilerplate** (AI-provider API keys from another project) — do not wire it into anything.
- **`Package.resolved` exists in two copies** (root and the Xcode wrapper's shared workspace data) — lockfile changes require explicit ownership and reconciliation of both.

### Governance & process

- **Hosted tests once triggered an administrator prompt** because app launch auto-started the privileged tunnel under `swift test`. `AppRuntimeEnvironment.allowsAutomaticStartup` now blocks startup under test hosts via `NSClassFromString("XCTestCase")` plus an env-prefix check (SwiftPM's `swiftpm-testing-helper` sets no XCTest vars). Never bypass this (`Core/ProcessEnvironment.swift`).
- **`CLAUDE.md` and `PRODUCT_REQUIREMENTS.md` SHA-256 hashes are recorded in the five-mode plan** (Task 1). Any edit desyncs the record — recompute and record the change per the plan's own convention. (This file's creation on 2026-10-23 and the same-day `CLAUDE.md` adoption edits are the current desync source; re-record before the next governed gate.)
- **Temporary iteration files use the `tmp_rovodev_` prefix** and are removed before completion; evidence staging lives outside the audited repository (`CLAUDE.md` §7).
- **Never mix documentation, generated-project, domain-state, transport, mode-behavior, and GUI changes in one commit** (plan execution principle 7). Documentation commits are atomic and separate.
- **Older status documents overstate maturity**: `CHANGELOG.md` ("1.0.0", 2024-12-12) and `DEPLOYMENT/` ("Ready for Production Release", Dec 2025) predate the Aug-2026 audit lineage, which rates production release confidence "not acceptable" (`Consolidated-Source-Of-Truth-Aug-23-2026.md` §A). Treat the later audit lineage as authoritative.
- **The plan-vs-worktree discrepancy is real**: plan checkboxes on `main` show Tasks 2+ open, while `feature/five-mode-reliability` carries task-shaped commits (see open items). Verify branch state before claiming plan status; the plan file can lag the worktree.

### Device & tunnel semantics (the expensive lessons)

- **An idle Wi-Fi phone drops out of usbmux for seconds to minutes even unlocked, and fully while locked (live 2026-11-01).** An open helper connection keeps it visible and survives a lock (54/54 probes through a lock; owner confirmed the location held through lock and VPN). Start therefore waits for the phone (up to 150 s, cancellable) instead of failing on one miss (`9c16e17`).
- **The Developer Disk Image status check costs ~1.2 s** (`mounter list`); it is cached once mounted and forgotten on device loss (`2bfb5f5`).
- **usbmux can stop listing a Wi-Fi phone for minutes while Bonjour still reaches it (live 2026-11-01, 3.5 min).** Every helper lane used to go through usbmuxd, so Start waited and gave up while the GUI still listed the phone. The helper's lane 4 opens the same userspace tunnel over a paired mobdev2 TCP lockdown (`mobdev2RSD`, Network requests only, proven live read-only in 2.9 s), and the DDI gate retries `mounter list/auto-mount --mobdev2` (not in USB-only mode). Map movement over lane 4 and `auto-mount --mobdev2` are still unproven (owner GUI gate).
- **A cleaner (Mole, `mo clean`) empties `~/Library/Logs`** — keep diagnostics that must survive elsewhere; the unified log keeps only error-level lines.
- **Relative `pgrep` never runs** from the app (`Process` resolves it against the working directory `/`); use `/usr/bin/pgrep`. Only a live `remote tunneld` daemon counts as a tunnel; a stray `start-tunnel` from an older build is not one.
- **A process probe is not a connection, and adoption follows the user.** Once the probe really ran, the 5 s status poll re-adopted a daemon right after Stop and adopted it in helper modes. Only Background Daemon mode adopts, Stop latches adoption off until an explicit Start, and readiness comes from `TunneldManager.state`, never from `pgrep` (`56976d0`).

- **`developer dvt simulate-location set` must stay running or iOS snaps back to real GPS** (pymobiledevice3 10.x behavior). Hence the held-session design: `DevLocationBridge` keeps the process alive in `heldSimulationProcess` via `runPython(..., keepAlive: true)`. **Terminating the held session is the real clear**; the `simulate-location clear` subcommand is only the fallback when no session was held (`Device/DevLocationBridge.swift`).
- **The tunnel subprocess is root-owned and outlives the app.** After relaunch, adopt the running tunnel (`adoptRunningTunnelIfPresent` / `.externalTunnelDetected`) instead of starting a second one (`Device/TunneldManager.swift`).
- **`kill(pid, 0)` returning `EPERM` means the process is alive** — root-owned helpers deny the signal-permission check; only a real error means dead (`TunneldManager.isProcessRunning`).
- **AppleScript `do shell script … with administrator privileges` runs with `HOME=/var/root`** — Python's `Path.home()` then hides `~/.pymobiledevice3` pairing records and Wi-Fi `remote start-tunnel` loops on "No tunnel services discovered". The elevated command must prefix `HOME='<user home>'` (`Device/PrivilegedTunnelCommand.swift`).
- **A manufactured `127.0.0.1:0` RSD endpoint once faked a "Tunnel live" UI** when parsing failed. `TunnelInfo.isUsable` now requires a valid address and port; never report a tunnel live without a usable RSD endpoint (`TunneldManager`).
- **No automatic recovery from tunnel `.error`**: relaunching a tunnel is privileged and may only follow explicit user action; auto-recovery caused a permanent "Connecting…" loop. Recovery is user-driven (`recoveryAttempted`, max 3, 1/2/4 s backoff) (`Device/TunnelStateMachine.swift` transition-table comments).
- **Health checks are real 2-second liveness pings** (`/bin/ps -p <pid>`) in `TunnelHealthMonitor`; an earlier parallel task logged fake pass messages. Three consecutive failures → `.healthCheckFailed`.
- **A Wi-Fi-prepared phone appears as ConnectionType "Network" through usbmux, and DVT works over `--udid` for it** — do not hard-block Wi-Fi devices from the direct path; a failed reachability probe is not a Developer-Mode verdict (`DevLocationBridge.performPreflight`, `DeviceManager.checkDeveloperMode`).
- **Lifecycle is not readiness.** FlowDeck/CoreDevice visibility does not establish visibility through pymobiledevice3 usbmux, mobdev2, or RemotePairing — verify each discovery source independently (`CLAUDE.md` invariant 2). The two original visible failures (readiness text squatting the tunnel button; one phone appearing as four rows) came from exactly this collapse (`Consolidated-Source-Of-Truth` §A).
- **Five discovery sources must deduplicate to one canonical device**: usbmux list, mobdev2 Bonjour, `remote_*.plist` filenames, the tunneld HTTP API, and `remote browse` can each surface the same phone. Merge by UDID + endpoint aliasing with a physical fingerprint (`DeviceManager.deduplicatePhysicalDevices`).
- **Pairing-record discovery reads `remote_<UDID>.plist` filenames only** — pairing secrets never leave the record (`DeviceManager.discoverKnownRemotePairingDevices`).
- **Wi-Fi bootstrap is two unprivileged commands on trusted USB**: `lockdown wifi-connections --state on` then `lockdown remotepairing --pair` (`DevicePreparationPlanner.wifiBootstrapCommands`) — the record this creates is what Wi-Fi `start-tunnel` later consumes.

### iOS versions

- **The old code rejected iOS 18+ (silent DVT failures, upstream pymobiledevice3 issue #1387); current code deliberately allows iOS 18–27** with caution UI only (`IOSVersionHelper.needsModernIOSCaution`; commit "fix(ios): allow location injection on iOS 18–27"). The README's iOS 18 troubleshooting section predates this — stale; do not re-add a hard rejection from it.

### State truth (why the five-mode program exists)

- **Two generation counters must agree (live 2026-11-01).** Swift asks the helper over `--udid` (`.direct`), but the helper's userspace tunnel acknowledges `remoteServiceDiscovery`. The bridge tracker treated that as an endpoint change and minted a new generation every apply, so the app rejected every hop after the first as stale while the phone applied it (Jump/Two-Spot/Multi-Spot/Joystick "active but idle"). The tracker now separates requested and acknowledged class, requests carry the coordinator generation as a floor, and the coordinator adopts a newer bridge generation (Clear advances it). Recovery and restored sessions start `.unresolved` (the helper picks its lane) (`2bfb5f5`, `d43cc08`).
- **The helper-record restore is for relaunch/Preserve only.** Run on every discovery sync it wiped the in-flight hop and set Movement to Idle; it now runs only when this session owns no location operation (`2bfb5f5`).
- **Movement steps are not "Applying" in the GUI.** Each step sets `.applying`; the coordinator records the receipt active when the step began (`heldWhileApplying`) and the GUI keeps it as held. After a failure/loss nothing is held; a cancelled application restores the phase it began from (`d43cc08`).
- **An applied receipt is device truth.** The helper finishes a command already sent, so a receipt arriving after Stop is committed as held; only Clear discards it.
- **A confirmed Clear is device truth too (live 2026-11-01).** The helper cleared the phone (`clear_location ok` in `helper.json` `recent_results`) but the coordinator returned `staleGeneration` because the phase left `.clearing` during the await; AppState stored `unresolvedClearSession`, and every retry died in the tracker's `beginClear` (`record.lost` from `completeClear`) before reaching the helper. Move stayed disabled in every mode until relaunch, mislabeled "Wait for the selected device to become ready", and nothing was logged. Now: a Clear the injector confirmed commits idle (connection dimension untouched), a retry after a cleared session reaches the helper again, and the Move card names an in-progress or unconfirmed Clear.
- **`helper.json` `recent_results` is the ground truth for what reached the phone** (every `set_location`/`clear_location` with success, error, generation, lane). Read it (never the token) before theorizing from the GUI.

- **Cooldown could reject a teleport *after* higher-level state already announced it** — false-active defect (`SimulationStateManager.setLocation` ordering; documented with exact line refs in `PRODUCT_REQUIREMENTS.md` §13).
- **`stopSimulation()` calling `clearLocation()` cleared the spoof on ordinary stop** — unintended-clear defect (same §13 references). The five-mode branch replaces stop with movement-stop-that-holds.
- **Movement and spoof persistence are separate dimensions**; collapse them and you get both defects above. Never report spoofing active before injection succeeds, or after the retained session is lost.

### Security boundaries

- **Subprocess environment is hardened**: PATH restricted to six system directories (user-writable `~/.local/bin` excluded to prevent escalation); `PYTHONPATH`/`PYTHONHOME`/`VIRTUAL_ENV`/`PIP_*` stripped (`Core/ProcessEnvironment.swift`).
- **All elevation flows through `PrivilegedTunnelCommand`**: exact-argv allowlist built from `TunnelMode` commands, Python-path allowlist, POSIX single-quoting (rejects embedded `'`), HOME preservation, PID > 1 validation; stop commands kill only our tracked PIDs (SIGTERM → 0.2 s → SIGKILL), never pattern-matched (`Device/PrivilegedTunnelCommand.swift`, `TunneldManager.killTrackedTunnelProcesses`).
- **Untrusted subprocess output is capped at 1 MB** (DoS prevention) in both `DevLocationBridge.runPython` and `TunneldManager.runCommand`; logs live under `~/Library/Logs/PathChanger/`, not `/tmp`; `[SECURITY]` audit lines are logged under the `.security` category.
- **GPX parsing disables external entities** (XXE prevention) and streams via `XMLParserDelegate` (`GPX/GPXParser.swift`).
- **Ad-hoc local signing proves nothing about Team ID, notarization, or Gatekeeper** — never make release claims from a development artifact (`CLAUDE.md` §10).

### Packaging (currently prohibited — fail-open)

- **Do not execute `build-app-bundle.sh`, `build.sh`, or `install.sh`** while they remain fail-open/destructive: suppressed signing failures, non-fatal verification, false success reporting, direct `/Applications` mutation — and `build-app-bundle.sh` Step 12 **deletes and reinstalls `/Applications/PathChanger.app` and sweeps the author's FlowDeck DerivedData** (`CLAUDE.md` §10).
- **CI (`ci.yml`) still invokes the unsafe bundler and contains legacy raw Apple commands** — do not copy CI commands into an agent workflow or treat a green CI job as authoritative without inspecting its checks.
- **`release-validation.yml` references `scripts/validate-release-config.sh` and `validate-w1-convergence-lock.sh`, which are missing from `scripts/`** — the manual release drill cannot run as written.
- The five-mode branch carries Task-18 packaging work (`requirements-location.in/.lock` via `uv pip compile --generate-hashes`, fail-closed bundler changes) — unmerged; verify before relying on it.

### Python bridge

- **pymobiledevice3 DVT moved upstream**: the capability probe and bridge use the NEW layout — `pymobiledevice3.services.dvt.instruments.dvt_provider` / `.location_simulation`, `pymobiledevice3.remote.rsd_tunnel.PreferredRsdTunnel` (`PythonPathResolver.checkPymobiledevice3Installation`). The old `services.dvt.dvt_secure_socket_proxy` / `services.dvt.location_simulation` paths do not exist in ≥ 11.4x — do not "fix" probes back to them. Verified 2026-10-23: 11.43.1 passes all six probes.
- **Homebrew Python is PEP 668 externally-managed**: pip install/uninstall into `/opt/homebrew` pythons needs `--break-system-packages` (or a venv). An uninstall silently fails without it.
- **`scripts/location_bridge.py` is the persistent-mode protocol server only**: allowlisted JSON commands (`set_location`, `clear_location`, `ping`, `quit`), bounded coordinates, cached DVT services keyed by `udid:rsd_address:rsd_port`, evicted on error so the next command reconnects. It has **no daemon `--tunnel` path** — usbmux or RSD only. Never execute it as a substitute for GUI verification.
- Swift/Python protocol parity (request IDs, session generation) is a review gate; check both sides before changing either.
- `PersistentLocationBridge.start()` waits ~500 ms and assumes ready — a known lenient-readiness weakness the five-mode plan's Task 8 replaces with waiting for the real `{"ready": true}` response.

### Architecture lessons

- **An earlier AppState decomposition drifted**: parallel unwired managers diverged from the running code. The accepted pattern is behavior-preserving extraction of the code that actually runs, with **exactly one playback loop in the codebase at any time** (StateManager headers, ARCH-002 lineage).
- **`SimulationEngine` + `MovementPhysics` are a parallel, tested-but-not-live engine**; live UI paths run `SimulationPlanner` + AppState's Task loops. Know which lane you are in before building on either.
- **`Geo` exists because haversine was duplicated six times with different Earth radii** — all geodesy goes through it (`Core/Geo.swift`).
- Known placeholders — do not mistake for shipped behavior: synchronized multi-device routes (`MultiDeviceCoordinator`), Mapbox provider (`MapService.MapboxService`), CloudSync (simulated network), `SidebarView`/`InspectorPanel`/`OrganicRail` (unmounted legacy UI).

### Subagents & long-running work

- Treat subagent output as untrusted until checked against files, diffs, tests, and process state; a fresh review agent must not repair the work it reviews; **always inspect a silent or dead agent's lane (git status, surviving processes) before redispatching** — the lane may hold complete but unreported work (`CLAUDE.md` §2).
- Long-running local work is killed by session interruptions and laptop sleep — build scripts cursor/resume-safe; DB/derived counts are the truth, not logs.

---

## Current open items

- [ ] **Stop-by-stop + real-road program (owner-approved 2026-11-02; PRODUCT_REQUIREMENTS §3.2–3.6) — Phases 1–3 MERGED, owner GUI test pending.** On `main` (`525a229`…`121940c`, pushed): shared stop engine for Jump/Two-Spot/Multi-Spot with per-mode settings (Getting there, Jump timing, At each stop 0–60 s, Go through, Repeat) and Pause/Resume; `MapKitRoadRouter` (MKDirections, 10 s timeout, 64-leg cache, failed legs remembered 120 s, straight-line fallback + note; custom speeds pick directions by m/s); app wiring through `AppState(roadRouter:)` (nil in tests/previews); mode-card controls, live readout and Pause/Resume. Fresh review (`semantic-review/2026-11-02-081004-review.md`) findings 1–8 fixed in `2bee683`/`121940c`. Gates at `121940c`: 1400 / 1390 passed / 0 failed / 10 skipped (one earlier run hit the `FileDescriptorLeakTests` 9-pipe variance; isolated reruns green), Debug + Release build. **Unverified:** GUI layout/VoiceOver of the STOPS block. **Owner questions open:** Realistic wait = hold + trip time (vs trip only); Fixed jump with 0 s hold = back-to-back jumps; a finished one-way one-per-Move run restarts at stop 1; after Clear the stop index is kept (next Move places that stop). Known behaviour: dragging the At each stop slider mid-run ends the run on its first tick (card says so). Suspected: Teleport/Joystick do not await an unwinding stop run. **Phases 2–3 merged (`4f70268`…`7aa94e1`, pushed 2026-11-02):** Joystick keeps the last acknowledged heading after release (until the next Move or a confirmed Clear) and uses its own persisted speed (`joystickSpeedMps`, 1–30 m/s, default 5; travel modes no longer apply); the map recenters only when the applied dot leaves the middle half of the view and keeps the user's zoom; a throttled `PlaceNameResolver` (CLGeocoder, ≤1 lookup/4 s, 30 m, 64-cell cache, no coordinates logged) shows the place/street name in the map footer; a confirmed Clear stages the last spoofed point (dashed marker, nothing sent until Move; an uncertain held point has its own marker); automatic reconnect (`Core/AutoReconnect.swift`): after a loss the user did not cause, waits for the phone (usbmux/Bonjour visibility or a 60 s→5 min fallback timer) and runs bounded recovery bursts (≥20 s apart, backoff to 5 min) through the helper's unprivileged path with the DDI mount before the reapply; never starts/restarts a tunnel or elevates, never in daemon mode; latched by Stop Tunnel and Clear until Start/Move/Reconnect; Reconnect reapplies only a held location (never a staged one); chip reads Reconnecting while waiting; recovery leaves Movement idle (the old "moving with no engine" defect is fixed). Fresh review `semantic-review/2026-11-02-135207-review.md`: findings 1–13 fixed in `7fa08d5`/`7aa94e1`. Gates at `7aa94e1`: 1494 / 1484 passed / 0 failed / 10 skipped, Debug + Release build, wrapper parity passed. **Not fixed (owner decision):** Clear stays disabled for a held spoof the app never adopted after a relaunch (enabling it would recreate the 2026-11-01 unresolved-Clear wedge; Clear and Quit ends it). **Owner questions:** after Clear while the phone is unreachable, Clear only stops reconnecting (the phone may keep the spoof until it reconnects or restarts); a point picked but not applied before Clear is replaced by the last spoofed point. **Unverified:** all new GUI (STOPS block, joystick card, staged/uncertain markers, place-name label, reconnect notice) and live reconnect on the phone.
- [ ] **Watch: `FileDescriptorLeakTests.testFileDescriptorCountStability` variance is rising** — 9 leaked pipes vs limit 5 in 2 of ~5 full runs during Phase 1 (2026-11-02), green in isolation. Suspected: other app-hosted tests' pipes landing inside the measurement window, not a product leak. Investigate before it masks a real leak.
- [ ] **Wi-Fi mode + five modes over Wi-Fi (2026-11-01, owner-ordered) — ACTIVE.** Landed on `main`: `a29483f` quit teardown/single health monitor; `cf103ec` Option A (the managed helper owns the only device connection; no `--native` tunnel); `9c16e17` Start waits for the phone; `2bfb5f5` every hop acknowledged (generation agreement, restore guard, DDI cache, joystick single-flight, Two-Spot two endpoints); `d43cc08` held state while moving, true travel speed, Auto jump, one Move at a time, 10 Hz limiter; `6b64f11` PRODUCT_REQUIREMENTS 3.2 Auto jump amendment. Owner GUI evidence: Wi-Fi Start, Teleport hold through phone lock and VPN. Remaining: owner GUI retest of Jump/Auto jump, Two-Spot, Multi-Spot, Joystick and travel modes after each merge; joystick disengage still drops a late receipt (one step). **Resolved (2026-11-01, `5c1006c`): the Two-Spot report was the Clear wedge.** UI-event timing shows the Two-Spot Move came after the wedging Clear; an AppState test of Jump+Auto jump → Two-Spot sends the traversal. Suspected trigger of the wedge: discovery dropped and re-selected the Wi-Fi phone during the ~1 s Clear; a loss during Clear now fails only the connection. Open-items round (`fix/open-items`, 2026-11-01): `53a62d7` over-long routes refused instead of sped up; `9e4ee58` a point applied after Stop shows held, nothing sent after Stop during the DDI check; `56976d0` daemon adopted only in daemon mode and never after Stop (latch until explicit Start; readiness from the tunnel manager); `1eb8416` the tunneld probe really runs (absolute `/usr/bin/pgrep`). The Stop latch is in memory only: after a relaunch in daemon mode the poll re-adopts a surviving daemon (PRODUCT_REQUIREMENTS permits relaunch adoption) — owner decision whether Stop should persist across launches.
- [ ] **Process:** implementation runs worktree-per-unit with parallel subagents (`CLAUDE.md` §2). Lane worktrees under `$HOME/.config/superpowers/worktrees/PathChanger/` are removed once merged (owner, 2026-11-02: do not wait for approval); uncommitted leftovers are archived first to `~/.local/state/pathchanger/worktree-archive/<date>/`. Fresh-session review files accumulate untracked in `semantic-review/` at the repository root.

- [ ] **Wi-Fi injection repair program (2026-10-31, owner-ordered) — ACTIVE.** Live supervised session root-caused the "nothing works" state: **the personalized Developer Disk Image was never mounted** (`mounter list` → `[]`) — every DVT injection silently no-opped on the iOS 27.2 phone — plus 11 further live-proven defects: ack-key `channel` vs `actual_channel` seam, mid-session device loss, Reconnect dropping `--udid`, failed tunnel adoption, stale RSD reuse, stale bootstrap argv (`wifi-connections --state on`), AX-invisible truth chrome, silent FileLogger, `DeviceManager.runPython` pipe-leak regression, Start-from-`.error` dead-end, native-RSD lane unreliability. **Proven working recipe (owner observed map movement):** phone awake + DDI mounted → usbmux Network visibility → direct `--udid` → pymobiledevice3 internal no-root userspace tunnel → held DVT session; 3-minute permanence and 60-second under-phone-VPN holds confirmed. Spec: `docs/superpowers/specs/2026-10-31-wifi-injection-repair-design.md`; Stage-1 plan: `docs/superpowers/plans/2026-10-31-wifi-injection-repair-stage1.md`. Branch `fix/wifi-injection-repair` (worktree `$HOME/.config/superpowers/worktrees/PathChanger/wifi-injection-repair`): ack-key+golden fixture `f309e0f`, helper lane chain `84b4f78`, DDI preparer `168c31a`, usbmuxDirect channel + stale-RSD guard `5932607`; suite 1083 / 0 failed / 10 skipped. Remaining: Debug+Release+full-suite gates at final HEAD, owner-supervised GUI acceptance (Teleport holds ≥3 min, Clear), then Stages 2–3. Managed runtime upgraded 11.43.1 → 11.49.1 during the session (rolling-latest policy).
- [x] **Five-mode plan execution — MERGED (2026-10-25, `f631141`).** The 36-commit `feature/five-mode-reliability` branch (Tasks 2–16, 18 + completion units) is merged to `main`; both branch tips are ancestors of `main` and pushed. Plan checkboxes on `main` show Tasks 0–15 + 18 checked; Task 16 partially env-blocked (`flowdeck ui mac` permission gap); **Task 17 (physical-device matrix) remains THE single owner hardware gate**; Task 19 post-merge bookkeeping (verification pass, evidence tag, cleanup receipts) pending. Merge authorization deviation recorded in `docs/requirements-ledger-2026-10-25.md`.
- [x] **Test-host fd ceiling — ROOT-CAUSED AND FIXED (2026-10-25)**: every subprocess path (`DeviceManager.runPython`/`runCommand`, `DevLocationBridge.runPython` ×2, `TunneldManager.runCommand`) drained its Pipe()s but never closed the read-ends; the usbmux discovery poller alone leaked thousands of pipe fds (measured: 4,810 open PIPEs in the test host). All sites now drain + close on every path (`feb2f45`); the immortal-monitor strong-self Task was also fixed (`ca57da6`). Gates after the fix: 1073 tests, green on the final runs. Residual: rare single-test EMFILE variance on `testGracefulTerminationStrategy` (2-of-3 gates fully green, both including the final); watch item, not a blocker.
- [x] **Completion program (2026-10-25, owner order)**: fix lane merged to `feature/five-mode-reliability` (`e1f8da5`); completion units landed — README truth (`a0cd9b3`), CI bundler removal + both missing release validators (`649ee8b`), receipt-return binding (`da106ea`), accessibility fixes (`63c015e`), subprocess pipe-close root-cause fix (`feb2f45`); docs gate (`7a4b45e`: requirements ledger, plan checkbox sync with Task 16/17 annotations, CHANGELOG/DEPLOYMENT maturity corrections). 1073 tests / 0 failed on final gates; device-free launch verified (process-stable 10s+). Task 17 (physical matrix) remains THE single owner gate — owner will test personally; Task-19 merge authorized by owner instruction 2026-10-25 despite Task 17 pending (deviation recorded in docs/requirements-ledger-2026-10-25.md).
- [ ] **Canonical Stage 2 remains unauthorized** — do not start it.
- [ ] **Packaging fail-open remediation — PARTIALLY DONE.** `ci.yml` bundler invocation removed (`649ee8b`); both referenced validators now exist in `scripts/` and fail closed. **Remaining:** `release.yml:72-73` and `release-validation.yml:160-162` still execute the prohibited bundler; `REQUIRE_PRODUCTION_SIGNING=1` (release-validation.yml:162) is a no-op — the script never reads it; `install.sh` still deletes/reinstalls `/Applications/PathChanger.app` and suppresses all build output; all three scripts remain fail-open — the CLAUDE.md §10 execution prohibition stays warranted.
- [x] **README staleness — largely fixed (`a0cd9b3`, 2026-10-25).** Five modes, iOS 17–27 caution-only, honest "30+ suites / 1000+ tests" (actual: 50 files / 1075 `func test`), no placeholder screenshot. Residual: README:39 instructs `./build-app-bundle.sh` without noting the CLAUDE.md §10 prohibition; README:42's "never modifies /Applications" is true of the bundler but `install.sh` still mutates /Applications.
- [x] **`CLAUDE.md` SHA-256 desync — re-recorded 2026-11-01** in the five-mode plan (Task 1 Step 1 successor record) after the `CLAUDE.md` §2 subagent rule and the `PRODUCT_REQUIREMENTS.md` §3.2 Auto jump amendment. Re-record again whenever either file changes.
- [ ] **Worktree path discrepancy**: plan requires `$HOME/.config/superpowers/worktrees/PathChanger/`; observed worktree is `/Users/datamatics/dev/PathChanger.worktrees/five-mode-reliability`. Reconcile.
- [ ] **Watch**: `CHANGELOG.md`/`DEPLOYMENT/` maturity claims vs the Aug-2026 audit verdict; Sparkle feed/keys still in the `abyssbugg` namespace; app is ad-hoc signed (notarization only exercised in the manual release-validation workflow).
- [x] **FlowDeck license — RENEWED (owner, 2026-10-31).** Build/test gates operational again.
- [ ] **GUI automation blocked in agent sessions (2026-10-23)**: `flowdeck ui mac session start` creates no captures and element finds return empty — Accessibility/Screen-Recording permission gap for the recorder in this context. Fix before relying on Task 16 GUI gates; `flowdeck run` + process-level launch verification still work.
- [ ] **Six call sites discard `setLocation` receipt returns** (build warnings in MultiDeviceCoordinator, SimulationEngine ×2, SimulationStateManager, DevLocationBridge ×2 — legacy/non-live paths). The five-mode contract makes receipts the truth source; consume or explicitly discard them on the five-mode lane.
- [ ] **Memory layer switched 2026-10-23**: ByteRover → Mem0 (store, user `datamatics`/agent `rovodev`) + Supermemory (recall); CLAUDE.md updated accordingly.
- [ ] **Tunnel endpoint health ≠ process health (found 2026-10-24, live)**: with `--native`, the pymobiledevice3 tunnel **process stays alive after the underlying Apple/remotepairingd tunnel dies** (phone locked/dropped Wi-Fi) — the app showed Running while the RSD endpoint was unroutable (`No route to host`, `usbmux list` → `[]`) and every five-mode injection failed. `TunnelHealthMonitor` pings process liveness (`ps -p`) only. Work item: probe RSD reachability (or classify no-route injection errors as connection-lost → uncertain) per PRODUCT_REQUIREMENTS §4.2 / invariant 5. Verified working 2026-10-24: tunnel start with corrected argv (owner-confirmed); injection argv itself is correct — it fails only when the endpoint is dead.
- [x] **--rsd DVT-port refusal — CONFIRMED live (2026-10-31, phone awake), ROOT-CAUSED, lane retired from the injection path.** Across three separate `--native` tunnels the RSD-allocated DVT ports were refused immediately/briefly-usable/refused again, and even the two `set()` completions that "succeeded" never applied on the device (root cause: DDI never mounted). The repair program rewires injection to the proven direct-`--udid` lane with the CLI-equivalent no-root userspace-tunnel fallback (commit `84b4f78`); the native tunnel stays out of the injection path. Physical-test protocol unchanged: phone unlocked, Auto-Lock → Never, same Wi-Fi; usbmux Network visibility vanishes on lock.
- [ ] **iPhone visibility requires the phone awake**: usbmux Network visibility and the native tunnel disappear when the device locks/sleeps or leaves Wi-Fi; physical-device test sessions must keep the phone unlocked and on the same network, and expect tunnel restarts after drops.
- [x] **Un-pin policy — COMMITTED (merged via `f631141` lineage).** Rolling-latest pymobiledevice3, pyenv-first bootstrap, lock files removed, install = `pip install -U`. Managed runtime now **Python 3.13.14 + pymobiledevice3 11.49.1** (upgraded in-session 2026-10-31 from 11.43.1; previous runtime preserved at `runtime/location.rollback`). Lesson now proven twice: rolling-latest means CLI argv drift breaks the app's constructed commands (the `wifi-connections --state on` bootstrap silently rotted) — command-shape smoke tests are part of the repair program. `daytona`'s aiofiles pin conflict during the pyenv upgrade — owner's env, watch if daytona misbehaves.
- [ ] **Debug monitor (LaunchAgent, outside the repo, 2026-11-01)**: `~/.config/pathchanger/monitor/pc-monitor` (`install|uninstall|status|tail|errors|last|selftest`), agent `com.datamatics.pathchanger-monitor`. Read-only toward the device. It streams the unified log for `com.pathchanger.app` at debug level (survives relaunch; test hosts filtered), follows `helper.json` `recent_results` and `location-helper-stderr.txt`, records process start/exit, and samples phone reachability per source (usbmux list, mobdev2 and RemotePairing Bonjour, ping), logging every change. Output in `~/.local/state/pathchanger/monitor/` (moved out of `~/Library/Logs`: the Mole cleaner wiped it on 2026-11-01), with `shots/` window captures on error and a throttled notification. The app's FileLogger stays disabled by decision.
- [ ] **Dev watch-rebuild-relaunch loop live**: `~/.config/pathchanger/dev-reload.sh` (outside the repo) — watches sources, incremental FlowDeck build, relaunches the app pinned to its Space. It sets `autoStartTunneld=false` for the watched session; restore with `defaults write com.pathchanger.app autoStartTunneld -bool true`. Stop with `pkill -f dev-reload.sh`. Requires FlowDeck license (expires 2026-10-26).
- [ ] **UI/UX review 2026-10-23 (device-free, computer-use + window capture)** — confirmed findings: (1) `ModeContextCard.swift:202` and `:471` expose raw accessibility identifiers as accessible labels (VoiceOver reads `location.teleport.emptyTarget` / `location.action.disabledReason` aloud) — pair identifiers with human labels; (2) map buttons carry symbol-derived labels ("Dot In A Viewfinder Frame", "this button also has an action to zoom the window"); (3) Jump/Two-Spot/Multi-Spot cards merge helper text, section headers, and values into single run-on AX text elements; (4) Joystick's "Stop movement" is enabled with no movement running and no start location (gating inconsistency vs Move); (5) map attribution is one giant AX text blob; (6) "Download" icon-button in ROUTE header is ambiguous. Positives: three-status truth chrome (Connection/Application/Movement) is live; Clear correctly disabled with no active spoof; mode buttons announce Selected/Not-selected; Move gating with disabled-reason helper is good.

---

## First response pattern when user continues

If the user says continue / resume / pick up PathChanger:

1. Confirm: **PathChanger** — macOS GPS-spoofing GUI over `pymobiledevice3`; five modes; GUI is the contract; priority order reliability → functionality → state truth → stability → GUI consistency; spoof persists until explicit Clear.
2. Check state fresh: `main` (documentation/recovery baseline), the implementation worktree branch, and the five-mode plan status — do not trust prose, including this file's open items, over live `git` output.
3. Point to open items and the owner-gated boundaries (physical-device matrix, final merge, privilege, Stage 2) — no product lectures.
4. Proceed engineering within authorized scope; the owner owns scope, acceptance, and all reserved human gates.
