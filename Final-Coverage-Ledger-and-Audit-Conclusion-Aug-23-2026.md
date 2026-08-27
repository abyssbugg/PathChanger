# Final Coverage Ledger and Audit Conclusion

## Consolidated document verification

`Consolidated-Source-Of-Truth-Aug-23-2026.md` was independently checked.

- **SHA-256:** `8fddcb28c622f51a497106040ac9d85d549a97a3c72cd43108e64c8720ab009b`
- **Line count:** 398
- **Sections:** A–J, each exactly once and in order
- **Stages:** 0–8 all present
- **Source documents:** all eight original sources exist and are referenced; this file is registered separately as the ninth post-consolidation verification appendix
- **Draft placeholders:** none; the only `TODO` match is a legitimate reference to `Todo-aug-23-2026.md`
- **Repository:** still dirty with the existing code changes and untracked audit documents
- **Changes made during this verification:** the ten pre-authorization documentation revisions were retained; Decision 11 records the Stage-0-only single-maintainer waiver; private repository `abyssbugg/PathChanger-Evidence` was provisioned with admin-enforced linear history and force-push/deletion disabled; external RovoDev staging/checkout paths and governance commit `1913b180ac595634db81e285be40a46f621ddd3b` were verified; Stage 0 execution is authorized without changing product verification status or the Stage 0–8 dependency order

The consolidation accurately distinguishes documented evidence from verification performed during the reconciliation itself.

---

# Final coverage ledger

## 1. Documentation coverage

| Area | Coverage | Result |
|---|---|---|
| Original requirements and acceptance intent | Complete | `Todo-aug-23-2026.md` |
| Active GUI and architecture | Complete for tunnel-related scope | `Architecture-Note-Aug-23-2026.md` |
| Tunnel lifecycle and target state | Complete | `Tunnel-Lifecycle-Architecture-Aug-23-2026.md` |
| Dependencies and integrations | Complete for tunnel scope | `Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md` |
| Functional modules and data flows | Complete | M1–M13 and flows A–I |
| Security and reliability | Complete static/runtime audit | 12 security and 19 reliability findings |
| Executive assessment | Complete | Release posture established |
| Coverage and remediation plan | Complete | Stage 0–8 with gates |
| Contradiction reconciliation | Complete | 15 entries resolved |
| Decision register | Complete | 11 approved decisions (10 minimum product/policy decisions plus Stage 0 governance/storage waiver); 4 later-stage unresolved questions |
**Documentation conclusion:** complete for this audit cycle.

---

## 2. Static source-review coverage

### Fully inspected tunnel core

- `PathChanger/Device/TunneldManager.swift`
- `PathChanger/Device/TunnelStateMachine.swift`
- `PathChanger/Device/TunnelHealthMonitor.swift`
- `PathChanger/Device/PrivilegedTunnelCommand.swift`
- `PathChanger/Device/PersistentLocationBridge.swift`
- `PathChanger/Device/LocationConnectionArguments.swift`
- `PathChanger/Device/DevicePreparationPlanner.swift`
- `scripts/location_bridge.py`
- `PathChanger/Core/PythonPathResolver.swift`
- `PathChanger/Core/ProcessEnvironment.swift`

### Tunnel-relevant paths inspected

- `PathChanger/Device/DeviceManager.swift`
- `PathChanger/Device/DevLocationBridge.swift`
- `PathChanger/Core/DependencyValidator.swift`
- `PathChanger/Core/StateManagers/DeviceStateManager.swift`
- `PathChanger/Core/StateManagers/SimulationStateManager.swift`
- `PathChanger/Core/ReliabilityManager.swift`
- `PathChanger/PathChangerApp.swift`
- `PathChanger/Models/Device.swift`

### GUI paths inspected

- `PathChanger/UI/ContentView.swift`
- `PathChanger/UI/OrganicChrome.swift`
- `PathChanger/UI/ModeContextCard.swift`
- `PathChanger/UI/SimulationView.swift`
- `PathChanger/UI/JoystickControlView.swift`
- `PathChanger/UI/OrganicSettingsSheet.swift`
- `PathChanger/UI/SettingsView.swift`
- `PathChanger/UI/DiagnosticsView.swift`
- `PathChanger/UI/ErrorDialogView.swift`
- `PathChanger/UI/OnboardingView.swift`
- `PathChanger/UI/DeviceListView.swift`
- `PathChanger/UI/SidebarView.swift`
- `PathChanger/UI/InspectorPanel.swift`
- `PathChanger/UI/FloatingControlPanel.swift`

### Build and deployment paths inspected

- `Package.swift`
- `project.yml`
- `Resources/Info.plist`
- `Resources/PathChanger.entitlements`
- `build-app-bundle.sh`
- `scripts/test.sh`

**Static-review confidence:** high for the tunnel lifecycle scope.

---

## 3. Automated-test coverage

### Latest recorded complete run

- **857 tests executed**
- **0 failures**
- **10 expected skips**
- Release build passed

### Focused suites

- `TunnelStateMachineTests`: 34 passed
- `TunneldManagerTests`: 38 executed, 1 skipped, 0 failed
- `AppStateSimulationTests`: 14 passed
- `DeviceManagerDeduplicationTests`: 2 passed
- Privileged command validation tests passed
- Location command security tests passed

### Historical coverage measurement

- Last recorded project-wide line coverage: **21.78%**
- This is a historical Stage 0 baseline, not a current tunnel-specific result.

### Critical paths not adequately tested

- Persistent bridge exact-once readiness
- Real concurrent bridge requests
- Stale lifecycle callback rejection
- Serialized effect ordering
- Root-output symlink protection
- PID reuse/process identity
- Foreign-process adoption
- Daemon-specific success
- Endpoint/DVT health
- Complete teardown and leak detection
- Userspace GUI injection
- Hardware failover
- Five-mode device-side behavior

**Automated-test confidence:** medium. The suite is broad but does not cover the highest-risk boundaries.

---

## 4. Live GUI/runtime evidence

### Previously observed and recorded

- Fresh dev app launched without overwriting the installed app
- `/Applications/PathChanger.app` timestamp remained unchanged
- Phone was visible through Network/CoreDevice tooling
- Bonjour mobdev2 discovery worked
- RemotePairing Bonjour discovery worked
- Four raw device records collapsed to one canonical GUI entry
- Tunnel button displayed **Start Tunnel**
- Administrator prompt appeared for Wi‑Fi start
- Tunnel process launched and produced a PID
- Failed startup ended in stable **Tunnel Error**
- No automatic return to Connecting was observed for more than 85 seconds

### Observed Wi‑Fi failure evidence

Tunnel output included:

- `No tunnel services discovered, trying again`
- `Device is not connected`

No usable RSD endpoint was produced.

### Not live-certified

- Successful Wi‑Fi RSD tunnel
- Successful USB tunnel
- Successful daemon tunnel
- Direct userspace injection through the GUI
- Persistent bridge against the physical device
- Relaunch adoption of a valid owned session
- Verified clean teardown
- Same-network detection
- Either failover direction
- All five spoofing modes
- Safe mode or cooldown behavior
- Two physical devices

**Live functional confidence:** low.

---

## 5. Dependency/runtime coverage

| Dependency fact | Status |
|---|---|
| Resolver-selected Python 3.13.15 | Verified during prior audit |
| pymobiledevice3 10.7.4 | Verified |
| Homebrew package path | Verified |
| Default TCP protocol | Verified from CLI |
| USB/Wi‑Fi/daemon command schemas | Verified from installed CLI |
| `--script-mode` support | Verified |
| Daemon API default `127.0.0.1:49151` | Verified |
| RemotePairing records present | Verified by filename |
| Pairing-record contents | Intentionally not inspected |
| Pairing permissions `0755/0644` | Verified |
| User-owned Homebrew runtime | Verified |
| Locked dependency graph | Absent |
| Supported version range | Undefined |
| Production helper/runtime | Not implemented |
**Dependency confidence:** high for the observed machine, low for reproducibility across machines/releases.

---

## 6. Security coverage

### Confirmed critical findings

1. User-owned Homebrew Python/package code is elevated to root.
2. Root output redirection uses a user-controlled path.
3. PID-only root termination lacks process identity verification.
4. Runtime-installed dependencies can enter privileged execution without a release.

### Confirmed high findings

- Pairing records are broadly readable.
- Broad `pgrep` adoption can detect foreign processes.
- User `HOME` is exposed to elevated Python.
- Dependency graph is unpinned.
- Sensitive identifiers/coordinates may be logged.

### Verification gaps

- No symlink/canary exploit regression
- No PID-reuse regression
- No foreign-process adoption test
- No signed-helper authorization test
- No dependency hash verification
- No privacy-redaction test

**Security conclusion:** privileged tunneling is not production-safe.

---

## 7. Reliability coverage

### Confirmed critical findings

- Persistent ready continuation can resume twice.
- Concurrent bridge requests can overwrite the single pending continuation.

### Confirmed high findings

- Lifecycle effects are not serialized.
- No attempt/session generation ID exists.
- Pipe-buffer deadlock is possible before output limits.
- Health measures process lookup rather than tunnel/DVT health.
- Degraded/reconnecting are incomplete.
- Daemon and one-shot modes use incompatible success models.
- Adoption depends on duplicate process detection and shared logs.
- Tests do not cover critical failure paths.

### Verification gaps

- No exact-once stress test
- No real concurrent request-correlation test
- No rapid start/stop stale-event test
- No process-alive/endpoint-dead test
- No teardown leak test
- No app-termination idempotency test

**Reliability conclusion:** not ready for failover or five-mode certification.

---

## 8. Functional coverage by scenario

| Scenario | Static understanding | Automated | Live | Final status |
|---|---:|---:|---:|---|
| Device discovery | High | Yes | Yes | Partially verified |
| Device deduplication | High | Yes | Yes | Verified for one device |
| Tunnel-button state | High | Partial | Yes | Current symptom fixed |
| Failed Wi‑Fi startup | High | Partial | Yes | Stable error verified |
| Successful Wi‑Fi tunnel | High | No | No | Unverified |
| Successful USB tunnel | High | No | No | Unverified |
| Daemon tunnel | High | Partial | No | Incomplete |
| Userspace route | High | No | No | Unverified |
| Persistent bridge | High | Shallow | No | Critical defects |
| Relaunch adoption | High | Partial | No | Unverified |
| Health/degradation | High | Partial | No valid session | Incorrect/incomplete |
| Stop/teardown | High | Partial | No proof | Unverified |
| USB→Wi‑Fi failover | Designed | No | No | Not implemented |
| Wi‑Fi→USB recovery | Designed | No | No | Not implemented |
| Teleport | Mapped | Partial | No | Unverified |
| Jump | Mapped | Partial | No | Definition unresolved |
| Two-Spot | Mapped | Partial | No | Unverified |
| Multi-Spot | Mapped | Partial | No | Unverified |
| Joystick | Mapped | Partial | No | Unverified |
---

# Audit conclusion

## Documentation status

The documentation audit is complete.

`Consolidated-Source-Of-Truth-Aug-23-2026.md` is suitable as the canonical index and decision/status document. The five specialist audit documents should remain immutable appendices, while the earlier TODO and “Final” reports should be treated as historical/superseded planning artifacts.

## Product status

PathChanger is:

- architecturally understood,
- buildable,
- testable,
- partially stabilized,
- suitable for structured remediation.

PathChanger is not yet:

- production-safe,
- privileged-path secure,
- deterministic under concurrent bridge activity,
- proven over USB,
- proven over Wi‑Fi,
- capable of certified failover,
- certified across all five modes,
- release-ready.

## Final go/no-go decision

- **Continue remediation:** yes
- **Begin unrestricted implementation:** no
- **Perform more privileged tunnel testing:** not before P0 containment
- **Ship or distribute as complete:** no
- **Treat the GUI fixes as full architectural completion:** no

## Authoritative next action

The ten minimum prerequisite product/policy decisions and Decision 11 governance/storage waiver are recorded in `Consolidated-Source-Of-Truth-Aug-23-2026.md`, **J.1**:

1. Stage 0 planning only,
2. no-root plus a signed typed helper,
3. no-root discovery/preparation/supported one-shot GUI operations,
4. a managed exactly locked runtime,
5. healthy-USB preference with bounded Wi-Fi failover and stable recovery,
6. a 1–3 second failover interruption gate,
7. enforced per-mode safety and cooldown,
8. strictly serialized persistent-bridge requests initially,
9. certification across the declared support matrix, and
10. a private tamper-evident GitHub evidence repository with protected history, fresh-checkout verification, and minimum 365-day retention policy, and
11. Shigeo as operator/product owner/accountable later-session approver, with Oz as the automated reviewer and explicit acknowledgement that no independent second human exists.

`Stage-0-Verification-and-Acceptance-Brief-Aug-23-2026.md` is approved and **Stage 0 execution is authorized exactly as written**, beginning with packet 0.1. Collection must stop after bounded cleanup, evidence upload, fresh-checkout hash verification, and Oz’s archived report; final acceptance occurs only in the required separate session through a commit GitHub reports as verified. The waiver is invalid for Stage 1 and release/security gates. No code change, privileged tunnel testing, hardware mutation, location injection, or unrestricted implementation is authorized.