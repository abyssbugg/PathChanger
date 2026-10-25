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

- [ ] **Five-mode plan execution — partially complete, unmerged.** Confirmed: Tasks 0–1 complete on `main` (Stage 1 closed; baseline normalized to `ea5a3b5a`). Confirmed (live Git 2026-10-25): branch `feature/five-mode-reliability` carries **36 commits** (33 from 2026-09-12→09-15 covering Tasks 4–16 + part of 18, plus three 2026-10-24 commits: rolling-latest pymobiledevice3 from pyenv `ca75b4f`, native Wi-Fi tunnel argv `81f8f56`, direct-udid routing `c6a8dc7`), all committed and pushed. Not done: plan checkboxes on `main` still show only Tasks 0–1; branch not merged; **Task 17 physical-device matrix and Task 19 final merge are owner-gated and not run**. Device-free verification 2026-10-24: FlowDeck Debug + ReleaseTesting builds green; full suite 1035/1045, 0 failed, 10 skipped (device-gated); managed runtime Python 3.13.14 + pymobiledevice3 11.43.1; device integration tests 14/14 (real injections) with the gate enabled.
- [ ] **Test-host fd ceiling (2026-10-25, live)**: under full-suite ordering the test host hits EMFILE (`Code 24`) on source-reading tests around `TunneldManagerTests` — passes with a raised fd limit, fails 1–2 tests without; partly pre-existing fd debt (FileDescriptorLeakTests flaked before this lane), amplified by concurrent monitor activity. The unbounded component was fixed (`fix(health)` weak-self monitor task — immortal monitors retained forever), the borderline remainder is registered here. Interim: run the full suite from a shell with `ulimit -n 10240`. Deep fix: identify the remaining fd holders (`lsof` on the host mid-suite).
- [ ] **Fix-lane commits (2026-10-25, local, unpushed)**: `e5aaa80` connection-loss classification, `ca57da6` endpoint-health probing + weak-self monitor fix + cadence bound, `cead924` transport-visibility cadence, `0088255` one-tap reconnect, `207e3c6` wrapper regen — all on `fix/wifi-connection-truth`; 1069 tests, behavior green, fd-EMFILE environment flake documented above. Next gates: owner GUI Teleport test with phone awake → merge lane back per plan, then five-mode × two-transport matrix.
- [ ] **Canonical Stage 2 remains unauthorized** — do not start it.
- [ ] **Packaging fail-open remediation** (prohibited scripts; CI bundler) — Task 18 work exists on the branch, unmerged and unverified on `main`.
- [ ] **README staleness**: iOS 18 troubleshooting section contradicts current code; test-suite list (7 suites) vs actual 38 suites / ~857 tests; placeholder screenshot; performance figures are upstream targets pending revalidation.
- [ ] **`release-validation.yml` references missing scripts** (`scripts/validate-release-config.sh`, `validate-w1-convergence-lock.sh`).
- [ ] **`CLAUDE.md` SHA-256 desync**: the 2026-10-23 adoption edits (and this file's creation) postdate the hashes recorded in the five-mode plan — recompute and record per plan convention before the next governed gate.
- [ ] **Worktree path discrepancy**: plan requires `$HOME/.config/superpowers/worktrees/PathChanger/`; observed worktree is `/Users/datamatics/dev/PathChanger.worktrees/five-mode-reliability`. Reconcile.
- [ ] **Watch**: `CHANGELOG.md`/`DEPLOYMENT/` maturity claims vs the Aug-2026 audit verdict; Sparkle feed/keys still in the `abyssbugg` namespace; app is ad-hoc signed (notarization only exercised in the manual release-validation workflow).
- [ ] **FlowDeck license expires 2026-10-26T14:09Z** (owner renewal — payment is a human gate). All FlowDeck build/test gates fail without it.
- [ ] **GUI automation blocked in agent sessions (2026-10-23)**: `flowdeck ui mac session start` creates no captures and element finds return empty — Accessibility/Screen-Recording permission gap for the recorder in this context. Fix before relying on Task 16 GUI gates; `flowdeck run` + process-level launch verification still work.
- [ ] **Six call sites discard `setLocation` receipt returns** (build warnings in MultiDeviceCoordinator, SimulationEngine ×2, SimulationStateManager, DevLocationBridge ×2 — legacy/non-live paths). The five-mode contract makes receipts the truth source; consume or explicitly discard them on the five-mode lane.
- [ ] **Memory layer switched 2026-10-23**: ByteRover → Mem0 (store, user `datamatics`/agent `rovodev`) + Supermemory (recall); CLAUDE.md updated accordingly.
- [ ] **Tunnel endpoint health ≠ process health (found 2026-10-24, live)**: with `--native`, the pymobiledevice3 tunnel **process stays alive after the underlying Apple/remotepairingd tunnel dies** (phone locked/dropped Wi-Fi) — the app showed Running while the RSD endpoint was unroutable (`No route to host`, `usbmux list` → `[]`) and every five-mode injection failed. `TunnelHealthMonitor` pings process liveness (`ps -p`) only. Work item: probe RSD reachability (or classify no-route injection errors as connection-lost → uncertain) per PRODUCT_REQUIREMENTS §4.2 / invariant 5. Verified working 2026-10-24: tunnel start with corrected argv (owner-confirmed); injection argv itself is correct — it fails only when the endpoint is dead.
- [ ] **--rsd DVT-port refusal: Suspected, not Confirmed (corrected 2026-10-24)**: the single observed `ConnectionRefusedError` on an RSD-allocated DVT port occurred at 03:47, possibly with the phone already suspending — it has not been retested with the phone freshly awake. What IS Confirmed: direct `--udid` injection works whenever the phone is usbmux-visible (held session, 03:47; device integration tests 14/14 at 04:0x), and the owner's failed GUI session (~10:00) ran entirely during a usbmux-invisible window (phone asleep), where no path can inject. Retest `--rsd` with the phone awake before treating native-RSD DVT as permanently broken. Physical-test protocol: keep the phone unlocked (Settings → Display & Brightness → Auto-Lock → Never during sessions), same Wi-Fi, expect usbmux visibility to vanish on lock.
- [ ] **iPhone visibility requires the phone awake**: usbmux Network visibility and the native tunnel disappear when the device locks/sleeps or leaves Wi-Fi; physical-device test sessions must keep the phone unlocked and on the same network, and expect tunnel restarts after drops.
- [ ] **Un-pin policy implemented on the branch (2026-10-23, uncommitted)**: rolling-latest pymobiledevice3, pyenv-first bootstrap, lock files removed, install = `pip install -U`; TDD'd (DependencyLockTests/PythonPathResolverTests rewritten); full suite 1046 tests / 0 failed. Managed runtime rebuilt from pyenv 3.13.14 with pymobiledevice3 11.43.1 (previous 11.12.5 runtime preserved at `runtime/location.rollback`). Homebrew 11.43.1 removed; pyenv 3.12.11 CLI upgraded to 11.43.1. Awaiting commit approval. `daytona`'s aiofiles pin conflicted during the pyenv upgrade — owner's env, watch if daytona misbehaves.
- [ ] **Dev watch-rebuild-relaunch loop live**: `~/.config/pathchanger/dev-reload.sh` (outside the repo) — watches sources, incremental FlowDeck build, relaunches the app pinned to its Space. It sets `autoStartTunneld=false` for the watched session; restore with `defaults write com.pathchanger.app autoStartTunneld -bool true`. Stop with `pkill -f dev-reload.sh`. Requires FlowDeck license (expires 2026-10-26).
- [ ] **UI/UX review 2026-10-23 (device-free, computer-use + window capture)** — confirmed findings: (1) `ModeContextCard.swift:202` and `:471` expose raw accessibility identifiers as accessible labels (VoiceOver reads `location.teleport.emptyTarget` / `location.action.disabledReason` aloud) — pair identifiers with human labels; (2) map buttons carry symbol-derived labels ("Dot In A Viewfinder Frame", "this button also has an action to zoom the window"); (3) Jump/Two-Spot/Multi-Spot cards merge helper text, section headers, and values into single run-on AX text elements; (4) Joystick's "Stop movement" is enabled with no movement running and no start location (gating inconsistency vs Move); (5) map attribution is one giant AX text blob; (6) "Download" icon-button in ROUTE header is ambiguous. Positives: three-status truth chrome (Connection/Application/Movement) is live; Clear correctly disabled with no active spoof; mode buttons announce Selected/Not-selected; Move gating with disabled-reason helper is good.

---

## First response pattern when user continues

If the user says continue / resume / pick up PathChanger:

1. Confirm: **PathChanger** — macOS GPS-spoofing GUI over `pymobiledevice3`; five modes; GUI is the contract; priority order reliability → functionality → state truth → stability → GUI consistency; spoof persists until explicit Clear.
2. Check state fresh: `main` (documentation/recovery baseline), the implementation worktree branch, and the five-mode plan status — do not trust prose, including this file's open items, over live `git` output.
3. Point to open items and the owner-gated boundaries (physical-device matrix, final merge, privilege, Stage 2) — no product lectures.
4. Proceed engineering within authorized scope; the owner owns scope, acceptance, and all reserved human gates.
