# Device Tunnel Security and Code-Integrity Audit

## 1. Executive summary
PathChanger is a local macOS controller that launches `pymobiledevice3`, establishes privileged iOS tunnels, and sends location-simulation commands to a paired device (`PathChanger/Device/TunneldManager+LaunchExecution.swift:31-59`, `PathChanger/Device/DevLocationBridge.swift:636-678`).
Overall risk posture for this scope: **High**, driven by one local privilege-escalation boundary defect.
Finding count: **1 High, 4 Medium, 0 Low, 1 Info; 0 Critical**.
Top risk: current-user-owned Python/module and pairing-script files are accepted and later executed with administrator privileges (`PathChanger/Core/PrivilegedPathSecurity.swift:106-160`, `PathChanger/Core/PrivilegedPathSecurity.swift:489-524`).
The exact `pymobiledevice3` pin is checked for privileged launch, but version identity does not establish file integrity, ownership of the imported module tree, or immutability through the administrator prompt (`PathChanger/Device/TunneldManager+LaunchExecution.swift:31-44`, `PathChanger/Core/PythonPathResolver.swift:232-259`).
The privileged AppleScript timeout resolves only the Swift continuation; it does not cancel the underlying authorization/execution operation, and Wi-Fi pairing has no end-to-end completion deadline (`PathChanger/Device/TunneldManager+LaunchExecution.swift:156-203`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:469-528`).
Daemon RSD records are merged rather than replaced, allowing disconnected-device endpoints to remain eligible for commands and health decisions (`PathChanger/Device/TunneldManager+RSDResolution.swift:242-292`, `PathChanger/Device/TunneldManager+ProcessManagement.swift:119-146`).
Two subprocess runners wait for exit before draining pipes; their output caps therefore do not prevent pipe backpressure and their timeouts do not guarantee process death (`PathChanger/Device/DeviceManager+CommandExecution.swift:23-57`, `PathChanger/Device/DevLocationBridge.swift:1129-1187`).
The runtime pin check is not an atomic execution gate: `DeviceManager` starts discovery during initialization while dependency validation begins later from view appearance (`PathChanger/Device/DeviceManager.swift:478-491`, `PathChanger/PathChangerApp.swift:17-42`).
No repository-level `0.0.0.0` bind was found; the configured tunneld consumer endpoint is loopback HTTP at `127.0.0.1:49151` (`PathChanger/Core/Constants.swift:119-126`).
Immediate 48-hour action: stop elevating any user-owned interpreter, Python package tree, or script.
Within 7 days: replace AppleScript authorization with a narrow signed helper or add durable late-completion cleanup; make the pin gate precede all process-capable object initialization.
Within 30 days: centralize streaming subprocess execution, atomically refresh per-device RSD state, and remove or securely redesign dormant companion networking.

## 2. Threat model

### System summary
The reviewed subsystem discovers trusted iOS devices, performs Bonjour-assisted remote pairing, creates USB/Wi-Fi/daemon tunnels through `pymobiledevice3`, caches RSD addresses, monitors process health, and drives location simulation (`PathChanger/Device/TunneldManager.swift:19-72`, `PathChanger/Device/DeviceManager+Discovery.swift:9-76`, `PathChanger/Device/DevLocationBridge.swift:286-327`).

Primary assets are administrator/root authority used to create tunnel interfaces, integrity of the selected iOS device and simulated location, device pairing/trust records managed by `pymobiledevice3`, RSD endpoint ownership, device identifiers, and availability of tunnel/location workflows (`PathChanger/Device/TunneldManager+LaunchExecution.swift:110-119`, `PathChanger/Device/TunneldManager+RSDResolution.swift:227-301`).

Actors considered are the local interactive user; a malicious process already running as that user; a nearby same-network Bonjour peer; a connected or paired iOS device; an external manually started `pymobiledevice3` process; and a compromised or incorrect Python dependency. This is a single-user local desktop deployment, not a multi-tenant or internet-facing service.

Data classes are local configuration, device UDIDs, location coordinates/status, privileged process/log metadata, and dependency/pairing state. The scoped Swift code does not directly parse or persist pairing-record secrets; that behavior is delegated to the pinned Python package and `scripts/pair_wifi.py` (`PathChanger/Device/TunneldManager+LaunchExecution.swift:345-367`, `scripts/pair_wifi.py:105-123`).

### Entry points
- SwiftUI lifecycle and user actions that trigger device refresh, tunnel start/stop, mode changes, pairing, and location commands (`PathChanger/PathChangerApp.swift:30-44`, `PathChanger/Device/TunneldManager+Lifecycle.swift:22-39`).
- Device and Bonjour output parsed from `pymobiledevice3` subprocesses (`PathChanger/Device/TunneldManager+ModeSelection.swift:12-58`, `PathChanger/Device/DeviceManager+RemoteBrowse.swift:10-31`).
- The loopback tunneld HTTP response used to populate device and RSD state (`PathChanger/Device/TunneldManager+RSDResolution.swift:227-292`, `PathChanger/Device/DeviceManager+Discovery.swift:218-239`).
- Administrator authorization through `NSAppleScript` for tunnel and pairing execution (`PathChanger/Device/TunneldManager+LaunchExecution.swift:110-203`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:464-528`).
- Persistent NDJSON communication with `scripts/location_bridge.py` (`PathChanger/Device/LocationBridge.swift:346-393`, `PathChanger/Device/LocationBridge.swift:643-696`).
- A currently unreferenced MultipeerConnectivity companion service (`PathChanger/Device/CompanionHostService.swift:47-68`, `PathChanger/Device/CompanionHostService.swift:193-216`).

### Trust boundaries map
1. **App → administrator authorization → root Python**: a Swift-built command crosses from the user process into root execution (`PathChanger/Device/TunneldManager+LaunchExecution.swift:82-119`).
2. **App → local Python/pymobiledevice3 subprocess**: argv and environment cross into third-party Python code (`PathChanger/Device/TunneldCommandExecutionState.swift:49-61`, `PathChanger/Device/DevLocationBridge.swift:1116-1125`).
3. **App ↔ iOS device**: USB lockdown, RemoteXPC/RSD, and remote-pairing channels rely on the device trust relationship (`PathChanger/Device/DeviceManager+Connection.swift:10-40`, `PathChanger/Device/TunneldManager+ModeSelection.swift:80-99`).
4. **LAN/Bonjour → pairing selection**: service advertisements supply names, addresses, and ports to the pairing helper (`scripts/pair_wifi.py:81-104`, `scripts/pair_wifi.py:105-123`).
5. **Root tunneld → loopback HTTP → app cache**: unauthenticated local JSON becomes per-device RSD routing state (`PathChanger/Core/Constants.swift:119-126`, `PathChanger/Device/TunneldManager+RSDResolution.swift:227-292`).
6. **App ↔ persistent location bridge**: NDJSON request IDs correlate commands and responses from a long-lived Python process (`PathChanger/Device/LocationBridge.swift:31-50`, `PathChanger/Device/LocationBridge.swift:643-696`).

### Abuse cases
1. A same-UID process modifies an accepted Homebrew Python, its `pymobiledevice3` module tree, or the user-owned bundle pairing script before administrator execution; user approval then runs modified code as root. Detection is low because the prompt names the app command, not the final inode (`PathChanger/Core/PrivilegedPathSecurity.swift:125-160`, `PathChanger/Core/PrivilegedPathSecurity.swift:489-524`).
2. The administrator prompt outlives the Swift timeout; approval after timeout starts a root tunnel after the state machine has declared failure. Detection is moderate through process/log traces but the late result is discarded (`PathChanger/Device/TunneldManager+LaunchExecution.swift:144-203`).
3. A faulty or adversarial Bonjour endpoint completes discovery but stalls pairing; `wifiPairingInProgress` remains set until the unbounded AppleScript/helper returns (`PathChanger/Device/TunneldManager+LaunchExecution.swift:415-419`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:469-528`).
4. A device disappears from the daemon API; its old RSD entry survives the next successful refresh and remains routable (`PathChanger/Device/TunneldManager+RSDResolution.swift:242-301`).
5. A subprocess emits enough stdout/stderr to fill a pipe or ignores termination; a discovery or preflight task remains blocked beyond the advertised timeout (`PathChanger/Device/DeviceManager+CommandExecution.swift:31-57`, `PathChanger/Device/DevLocationBridge.swift:1140-1187`).
6. An unapproved `pymobiledevice3` build is installed; initialization-triggered discovery invokes it before validation changes the UI to invalid (`PathChanger/Device/DeviceManager.swift:478-491`, `PathChanger/PathChangerApp.swift:22-42`).
7. A nearby peer would be auto-invited/accepted by the dormant companion service and could receive location/status or send emergency-stop if that unreferenced class is re-enabled (`PathChanger/Device/CompanionHostService.swift:93-128`, `PathChanger/Device/CompanionHostService.swift:193-216`).
8. An external tunnel process is observed and may be attached to or later managed based on command-line matching rather than an app-issued capability (`PathChanger/Device/TunneldManager+ModeSelection.swift:145-166`, `PathChanger/Device/TunneldManager+ProcessValidation.swift:207-255`).

## 3. Methodology notes
All 28 files under `PathChanger/Device` were opened and reviewed in full. Related enforcement and intent were checked in `PathChanger/Core/PythonPathResolver.swift`, `PathChanger/Core/PrivilegedPathSecurity.swift`, `PathChanger/Core/SubprocessPolicy.swift`, `PathChanger/Core/DependencyValidator.swift`, `PathChanger/Core/Constants.swift`, `PathChanger/PathChangerApp.swift`, `scripts/pair_wifi.py`, `requirements-pathchanger.txt`, `Tests/PathChangerTests/Pymobiledevice3PinTests.swift`, `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift`, `Tests/PathChangerTests/DevLocationBridgeSecurityTests.swift`, and relevant ranges of `Tests/PathChangerTests/TunneldManagerTests.swift`.

Passes A-K were applied. Pass A mapped root authorization, subprocess, device, LAN, loopback HTTP, and persistent bridge boundaries. Pass B reviewed local/device pairing trust and the root transition. Pass C traced all scoped `Process.arguments` and privileged shell construction; fixed argument arrays and UDID/value validation materially reduce direct command injection (`PathChanger/Device/TunneldManager+LaunchExecution.swift:46-80`, `PathChanger/Device/TunneldManager+ModeSelection.swift:69-74`). Pass D reviewed pin enforcement, file provenance, pairing-secret delegation, and local HTTP/TLS assumptions. Pass E reviewed local log and device-identifier flow. Pass F produced three lifecycle/reliability findings. Pass G reviewed the exact direct pin and its enforcement timing. Pass H confirmed the configured API consumer is loopback, not `0.0.0.0` (`PathChanger/Core/Constants.swift:119-126`). Pass I used repository-wide exact-symbol searches to classify dead surfaces. Pass J analyzed the same-UID-to-root chain. Pass K specifies regression tests and invariants below.

This was a strictly read-only diagnostic review. Per instruction, no build, test, dependency installation, process launch, device operation, or live pairing was run. The only project write is this report. Runtime behaviors that require an actual authorization dialog, paired device, or adversarial Bonjour peer remain conditions-based.

The working tree was reviewed as-is on `feat/ui-redesign`; `TunneldManager.swift`, `TunneldManager+LaunchExecution.swift`, the pin tests, and supporting security files include uncommitted content. Conclusions apply to those exact local files.

## 4. Critical & High findings

### [HIGH] User-owned Python and pairing files cross the administrator boundary as root
- **ID**: VULN-001
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-269 Improper Privilege Management; CWE-367 Time-of-check Time-of-use Race Condition; CWE-829 Inclusion of Functionality from Untrusted Control Sphere
- **Location**: `PathChanger/Device/TunneldManager+LaunchExecution.swift:L31-L97`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L345-L408`; `PathChanger/Core/PrivilegedPathSecurity.swift:L106-L160`; `PathChanger/Core/PrivilegedPathSecurity.swift:L489-L524`; `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L125-L142`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    guard let privilegedPython = PrivilegedPathSecurity.resolvePrivilegedPythonPath(
        preferredUserPath: python3Path
    ) else { ... }
    ```

    ```swift
    let selfUID = getuid()
    if info.st_uid != 0 && info.st_uid != selfUID { ... }
    ```

    The test suite explicitly requires a user-owned, owner-writable mode `0644` bundle `pair_wifi.py` to be accepted (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:125-142`).
  - Data flow: `PythonPathResolver.path` or bundle `pair_wifi.py` → path/version/mode checks → shell command construction → `do shell script ... with administrator privileges` → root interpreter imports and executes the accepted Python/module/script (`PathChanger/Device/TunneldManager+LaunchExecution.swift:31-97`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:464-477`).
  - Control flow / auth decision points: the resolver prefers the caller's path whenever it passes the pin probe, before considering a root-owned alternative (`PathChanger/Core/PrivilegedPathSecurity.swift:125-160`). Symlink targets, current-user-owned regular files, and current-user-owned bundle scripts are accepted if they are not group/other-writable; owner-writability is not rejected (`PathChanger/Core/PrivilegedPathSecurity.swift:489-524`).
- **Description**: The privileged boundary treats “owned by the current user” as acceptable provenance for code that will execute as root. This does not defend against the relevant escalation actor: a process already running as that user can modify an owner-writable Homebrew interpreter, its imported `pymobiledevice3` package files, or the accepted bundle script. The version probe only proves that invoking the current path reports `9.12.0`; it does not authenticate the module bytes or freeze the inode through the later administrator prompt (`PathChanger/Core/PythonPathResolver.swift:232-259`). The code also accepts symlinked Python paths after validating only the current target, leaving a replacement window (`PathChanger/Core/PrivilegedPathSecurity.swift:474-487`).
- **Preconditions**: An attacker already has code execution as the logged-in user or write access to the selected interpreter/module/script; the user subsequently initiates tunnel start or Wi-Fi pairing and approves the administrator prompt. Root-owned immutable Python plus root-owned immutable site-packages would block the interpreter branch, but the pairing-script policy still intentionally accepts user-owned bundle content.
- **Impact**: Local privilege escalation from the interactive user to root. Root code can affect system integrity and confidentiality beyond PathChanger, create persistent privileged processes/interfaces, and access pairing or device material available to root. Blast radius is the Mac host, not other tenants.
- **Exploitability analysis**: A same-UID process needs only preserve the expected filename and, for the interpreter branch, make the pin probe return the approved version. It can modify accepted code before the check, between check and authorization, or in the imported package tree. The user must approve a legitimate-looking PathChanger administrator request, which lowers exploitability from Critical but remains a realistic interaction for the product's normal tunnel workflow.
- **Why scanners may miss this**: Each local check looks security-positive—absolute allowlisted path, safe owner, no group/other write, exact version, and shell quoting. The weakness appears only when the checks are composed with a later root execution and the attacker model includes same-UID owner write and mutable Python imports.
- **Chaining**: BUG-002 lengthens the check-to-use window because the administrator operation can continue after Swift marks it timed out. VULN-005 allows unapproved Python to execute before the general startup gate, although privileged tunnel launch separately performs its own pin probe.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: remove direct root execution of Python and bundle scripts. Install a signed, root-owned `SMAppService`/privileged XPC helper with a narrow operation enum and validated scalar inputs; the helper, not the UI process, should own tunnel lifecycle and authorization.
  - Interim code-level control: require every privileged executable, script, package directory, and imported module file to be root-owned and not owner/group/other-writable; resolve and validate every path component; reject symlinks; verify code/hash provenance inside the privileged helper immediately before use. Do not prefer `preferredUserPath` merely because it reports the pin.
  - Config / platform control: verify the app/helper code signature and designated requirement; store any approved helper payload in a root-owned immutable location rather than a drag-and-drop user-owned bundle resource.
  - Least privilege: expose only start/stop/status operations; do not accept an arbitrary command string, executable path, script path, environment, or log path over IPC.
  - Tests / invariants: invert `testPrivilegedPairScriptAcceptsUserOwnedBundleResourceWhenModeSafe`; add tests that reject current-user-owned Python/package/script content, symlink swaps, and inode replacement between validation and execution. Add a signed-helper integration test that proves arbitrary operations and paths are rejected.
- **Incorrect fixes to avoid**: Do not rely on an exact version string, filename allowlist, `PYTHONSAFEPATH`, group/other-write checks, or a pre-authorization hash performed by the unprivileged process. Do not copy the same shell command into a different authorization API without changing code provenance.
- **Residual risk after fix**: A compromised signed/root-owned helper or approved dependency release remains a supply-chain risk. Authorization-prompt spoofing and user consent remain human factors, but same-UID file replacement should no longer yield root execution.
- **Priority / SLA suggestion**: Patch now / Wave 0. Disable privileged pairing and privileged tunnel launch in production builds until root execution is constrained to immutable signed code; complete the helper migration this sprint.
- **Confidence**: CONFIRMED
- **Effort**: L

## 5. Medium findings

### [MEDIUM] Privileged AppleScript timeouts do not cancel execution and pairing has no completion deadline
- **ID**: BUG-002
- **Category**: Bug | Error-handling | Design flaw
- **CWE / OWASP / ASVS**: CWE-667 Improper Locking; CWE-400 Uncontrolled Resource Consumption; CWE-367 Time-of-check Time-of-use Race Condition
- **Location**: `PathChanger/Device/TunneldManager+LaunchExecution.swift:L110-L203`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L415-L419`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L464-L528`; `Tests/PathChangerTests/TunneldManagerTests.swift:L997-L1067`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    DispatchQueue.global().async {
        let resultDescriptor = appleScript.executeAndReturnError(&error)
        state.resume(.returned(output: resultDescriptor.stringValue ?? "", returnTime: wrapperReturnTime))
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        state.resume(.timedOut)
    }
    ```

  - Data flow: administrator prompt/execution runs synchronously on a global worker; an independent timer wins the one-shot continuation but has no handle that cancels `executeAndReturnError` (`PathChanger/Device/TunneldManager+LaunchExecution.swift:156-203`).
  - Control flow: timeout cleanup only scans for children that exist at that moment. If authorization completes later, the result is discarded by `PrivilegedWrapperContinuation`, and no second cleanup runs (`PathChanger/Device/TunneldCommandExecutionState.swift:14-31`, `PathChanger/Device/TunneldManager+StartupAcquisitionContinuation.swift:276-312`). Wi-Fi pairing uses a checked continuation around the same blocking API with no outer timeout at all (`PathChanger/Device/TunneldManager+LaunchExecution.swift:469-528`).
- **Description**: The timeout changes Swift-visible state but does not cancel the privileged operation. A delayed administrator approval can therefore execute after the state machine has failed startup, producing an untracked root tunnel. Pairing is worse: its timeout parameter bounds Bonjour discovery only; a stalled pairing handshake or authorization call can leave `wifiPairingInProgress` true indefinitely.
- **Preconditions**: Slow user response, a blocked authorization UI, a hung AppleScript, or a Bonjour peer/pairing endpoint that stalls after discovery.
- **Impact**: Orphan privileged processes, tunnel/interface conflicts, inability to reliably stop what the app started, stuck pairing UI, and repeated administrator prompts on retry. Impact is local availability and privileged lifecycle integrity.
- **Exploitability analysis**: No command injection is required. Timing the approval after the wrapper deadline is sufficient for the tunnel case. A same-network peer that advertises and then stalls the protocol can contribute to the pairing case, subject to upstream timeout behavior.
- **Why scanners may miss this**: The continuation is correctly protected against double resume and tests verify immediate `.timedOut` classification and current-child cleanup (`Tests/PathChangerTests/TunneldManagerTests.swift:997-1067`). They do not model a real operation returning or spawning after the timeout.
- **Chaining**: Amplifies VULN-001 by widening the mutable-code window between validation and root use.
- **Recommended fix** (preferred + alternatives):
  - Replace AppleScript shell elevation with the signed helper described in VULN-001 and use request IDs with explicit cancellation and authoritative helper-side lifecycle state.
  - Interim: do not declare final failure until the authorization operation has returned or been definitively canceled. If a late PID/result arrives, validate and terminate it. Add a bounded post-timeout reconciliation scan tied to the launch generation.
  - Add an end-to-end pairing deadline that cancels the Python helper/process group, clears state, and records whether a pair record may have been partially written.
  - Regression tests must delay the debug wrapper beyond the deadline and then return/spawn; assert no live validated child remains. Add a pairing helper that hangs after discovery and assert bounded completion.
- **Incorrect fixes to avoid**: Do not merely shorten/lengthen the timer, ignore late callbacks, or clear `wifiPairingInProgress` while leaving the root operation alive.
- **Residual risk after fix**: macOS authorization UI timing remains outside app control; the helper must retain reconciliation state across UI cancellation and app termination.
- **Priority / SLA suggestion**: This sprint.
- **Confidence**: CONFIRMED for non-cancellation and missing deadline; LIKELY for the exact late-approval orphan timing on all macOS versions.
- **Effort**: M

### [MEDIUM] Daemon refresh retains stale per-device RSD endpoints and can report false health
- **ID**: BUG-003
- **Category**: Bug | Design flaw
- **CWE / OWASP / ASVS**: CWE-672 Operation on a Resource after Expiration or Release; CWE-613 Insufficient Session Expiration
- **Location**: `PathChanger/Device/TunneldManager+RSDResolution.swift:L227-L301`; `PathChanger/Device/TunneldManager+ProcessManagement.swift:L119-L146`; `Tests/PathChangerTests/TunneldManagerTests.swift:L358-L402`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    var updatedInfo = deviceTunnelInfo
    ...
    updatedInfo[udid] = TunnelInfo(...)
    ...
    deviceTunnelInfo = updatedInfo
    ```

  - Data flow: each successful API response starts from the previous cache and overwrites only returned UDIDs; absent or now-invalid entries are never deleted (`PathChanger/Device/TunneldManager+RSDResolution.swift:242-292`).
  - Control flow: `getRsdInfo` returns any syntactically usable cached entry while state is running, and health accepts any usable cached RSD plus a live daemon PID without probing the selected device (`PathChanger/Device/TunneldManager+RSDResolution.swift:296-315`, `PathChanger/Device/TunneldManager+ProcessManagement.swift:119-146`).
- **Description**: The daemon API response is a current inventory, but the app treats it as an additive delta. When a device disconnects, rotates to an invalid entry, or disappears from the response, its prior endpoint remains owned by the running lifecycle. The health check can stay green based on that stale record.
- **Preconditions**: Daemon mode has published a device RSD, then the device disconnects or the API omits/invalidates that UDID while the daemon process remains alive.
- **Impact**: Commands target expired RSD addresses/ports, recovery is delayed, and UI/health state can claim connectivity that no longer exists. Port/address reuse creates a low-probability integrity risk of contacting the wrong local/device endpoint; the primary impact is single-device availability.
- **Exploitability analysis**: Normal disconnect/reconnect behavior is sufficient. A malformed local API response can also preserve all old entries because invalid entries are skipped rather than expiring prior state.
- **Why scanners may miss this**: Each parsed entry is validated, and tests cover healthy-with-cache, empty-cache unhealthy, and dead-daemon unhealthy. They do not exercise “previous cache populated, next authoritative response omits device” (`Tests/PathChangerTests/TunneldManagerTests.swift:358-402`).
- **Chaining**: Repeated command failures can trigger bridge/tunnel invalidation and privileged recovery paths, increasing exposure to BUG-002 (`PathChanger/Device/LocationBridge.swift:605-622`).
- **Recommended fix** (preferred + alternatives):
  - Parse each successful 200 response into a fresh dictionary and atomically replace `deviceTunnelInfo`.
  - Track response generation and `lastSeen`; expire entries not present in the current generation. If transient preservation is required, apply a short explicit grace TTL and never use grace entries for “healthy.”
  - Bind health to the selected device's current-generation entry and perform a bounded RSD reachability probe rather than checking syntax plus process existence.
  - Validate HTTP status and bound response size before parsing.
- **Incorrect fixes to avoid**: Do not clear only on JSON parse failure, retain absent entries indefinitely “for reconnect,” or treat daemon liveness as device liveness.
- **Residual risk after fix**: A current endpoint can fail immediately after publication; command failure still needs generation-aware invalidation and retry.
- **Priority / SLA suggestion**: This sprint.
- **Confidence**: CONFIRMED
- **Effort**: S

### [MEDIUM] Subprocess output caps and timeouts are ineffective before process exit
- **ID**: BUG-004
- **Category**: Bug | Error-handling
- **CWE / OWASP / ASVS**: CWE-400 Uncontrolled Resource Consumption; CWE-667 Improper Locking
- **Location**: `PathChanger/Device/DeviceManager+CommandExecution.swift:L10-L65`; `PathChanger/Device/DeviceManager+CommandExecution.swift:L68-L130`; `PathChanger/Device/DevLocationBridge.swift:L1089-L1215`; `Tests/PathChangerTests/DevLocationBridgeSecurityTests.swift:L12-L25`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    process.waitUntilExit()
    ...
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    ```

  - Data flow: child stdout/stderr → finite `Pipe` buffers → parent waits for child exit → parent drains only afterward. `DevLocationBridge` computes the 1 MiB cap only after both reads complete (`PathChanger/Device/DevLocationBridge.swift:1161-1198`).
  - Control flow: timeout sends only `process.terminate()` and then still depends on `waitUntilExit()` returning; there is no SIGKILL escalation or timeout-side continuation completion (`PathChanger/Device/DeviceManager+CommandExecution.swift:31-49`, `PathChanger/Device/DevLocationBridge.swift:1140-1168`). The security test verifies only that the constant equals 1 MiB, not that streaming enforces it (`Tests/PathChangerTests/DevLocationBridgeSecurityTests.swift:12-25`).
- **Description**: The runners advertise timeout and output-size protection, but neither is authoritative. A child can block writing when either pipe fills before exit, and a child that does not terminate on SIGTERM leaves the parent waiting indefinitely. The post-exit size check cannot prevent pipe backpressure or bound memory before completion.
- **Preconditions**: `pymobiledevice3`, a device-driven command path, or a substituted/incorrect dependency emits enough output, stops reading/closing, or ignores SIGTERM.
- **Impact**: Device refresh, preflight, clear-location, or command tasks can hang; auto-refresh can accumulate delayed work; user-visible workflows become unavailable until restart. The blast radius is the local app session.
- **Exploitability analysis**: An incorrect dependency is sufficient. A malicious paired device may influence error/output volume through upstream parsing paths, but the exact reachable volume is dependency-specific and was not dynamically tested.
- **Why scanners may miss this**: A visible timeout closure and explicit byte-count check look protective without modeling POSIX pipe capacity and wait/read ordering.
- **Chaining**: VULN-005 can expose these runners to an unapproved dependency before validation; a malicious build can intentionally hit the deadlock path.
- **Recommended fix** (preferred + alternatives):
  - Reuse one centralized streaming runner modeled on `TunneldCommandExecutionState`, draining combined output while the process runs and enforcing the byte cap at append time (`PathChanger/Device/TunneldCommandExecutionState.swift:37-72`).
  - Make timeout completion independent of `waitUntilExit`; send SIGTERM, wait a short bounded grace period, then SIGKILL the process group and resume once.
  - Bound combined stdout+stderr, cancel readability handlers safely, and reject nonzero termination status consistently.
  - Add integration tests with a local fixture that writes beyond pipe capacity and one that ignores SIGTERM; both must terminate within a deterministic budget.
- **Incorrect fixes to avoid**: Do not increase pipe/output limits, read stdout and stderr sequentially after exit, or assume Python always honors SIGTERM.
- **Residual risk after fix**: Descendant processes can outlive the direct child unless the runner creates and terminates an owned process group.
- **Priority / SLA suggestion**: This sprint.
- **Confidence**: CONFIRMED
- **Effort**: M

### [MEDIUM] Exact pymobiledevice3 pin validation is not an atomic prerequisite for execution
- **ID**: VULN-005
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-494 Download of Code Without Integrity Check; CWE-367 Time-of-check Time-of-use Race Condition
- **Location**: `PathChanger/Device/DeviceManager.swift:L467-L491`; `PathChanger/Device/DeviceManager+CommandExecution.swift:L10-L21`; `PathChanger/PathChangerApp.swift:L17-L42`; `PathChanger/PathChangerApp.swift:L326-L333`; `PathChanger/Core/PythonPathResolver.swift:L70-L73`; `Tests/PathChangerTests/Pymobiledevice3PinTests.swift:L11-L47`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    init() {
        setupTunnelStateObserver()
        Task {
            await checkTunneldStatus()
            await refreshDevices()
            startAutoRefresh()
        }
    }
    ```

    ```swift
    if dependencyValidator.validationStatus == .invalid {
        DependencyErrorView(...)
    } else {
        ContentView()
        .onAppear {
            Task { await dependencyValidator.validateAll() }
        }
    }
    ```

  - Data flow: `PathChangerApp` constructs `AppState`, which constructs `DeviceManager`, whose initialization task calls discovery runners that execute `PythonPathResolver.path`; validation begins later from `ContentView.onAppear` (`PathChanger/PathChangerApp.swift:17-42`, `PathChanger/PathChangerApp.swift:326-333`, `PathChanger/Device/DeviceManager.swift:478-491`).
  - Control flow: `.pending` and `.validating` render the operational `ContentView`; only `.invalid` blocks it (`PathChanger/PathChangerApp.swift:22-29`). Scoped runners do not require a validated token and directly execute the cached path (`PathChanger/Device/DeviceManager+CommandExecution.swift:10-21`).
  - Tests assert exact string acceptance and install-message content, but do not assert that zero `pymobiledevice3` subprocesses can start before `.valid` (`Tests/PathChangerTests/Pymobiledevice3PinTests.swift:11-47`).
- **Description**: The repository has an exact version policy, but validation is an asynchronous UI event rather than a prerequisite enforced at every execution boundary. Initialization-triggered discovery can race ahead of validation and can start auto-refresh. A path refresh or environment mutation after validation also leaves no execution-scoped proof.
- **Preconditions**: A mismatched or malicious `pymobiledevice3` installation is discoverable at a resolver path, and initialization/discovery runs before validation completes or the executable/module changes afterward.
- **Impact**: Unapproved third-party Python executes with user privileges and can access the user's device trust context, files, and network. Privileged launch has an additional synchronous pin probe, so this finding alone does not grant root.
- **Exploitability analysis**: Requires control of or replacement of the local Python environment. The app itself supplies the trigger automatically during initialization, reducing required user interaction.
- **Why scanners may miss this**: Unit tests and resolver functions correctly implement exact equality. The flaw is lifecycle ordering and lack of a capability/token coupling validation to every process launch.
- **Chaining**: BUG-004 makes intentionally noisy unapproved code an app-level DoS. VULN-001 shows that version equality alone is not sufficient provenance for the privileged path.
- **Recommended fix** (preferred + alternatives):
  - Keep process-capable managers inert until dependency status is `.valid`; render a blocking validation state for `.pending` and `.validating`.
  - Centralize all Python execution behind a dependency gate that returns an immutable validated executable identity (canonical path plus file identity/signature/hash and module provenance) and invalidates on path/inode change.
  - Do not start device discovery or auto-refresh from `DeviceManager.init`; start explicitly only after successful validation and stop immediately on invalidation.
  - Add a lifecycle regression test with an execution spy proving no pmd3 command occurs before validation success, including initialization and menu actions.
- **Incorrect fixes to avoid**: Do not add another best-effort `validateAll()` call inside each feature, rely only on the UI hiding buttons, or cache a Boolean forever after the path can change.
- **Residual risk after fix**: Exact direct pinning does not lock transitive dependencies or authenticate installed bytes; reproducible, hash-locked distribution is still needed.
- **Priority / SLA suggestion**: This sprint.
- **Confidence**: LIKELY because task scheduling determines whether a specific launch wins the startup race; the absence of an execution gate is CONFIRMED.
- **Effort**: M

## 6. Low / Info

### [INFO] Dormant companion service would auto-trust nearby peers if re-enabled
- **ID**: DEAD-006
- **Category**: Dead code | Design flaw
- **CWE / OWASP / ASVS**: CWE-306 Missing Authentication for Critical Function; CWE-200 Exposure of Sensitive Information
- **Location**: `PathChanger/Device/CompanionHostService.swift:L47-L68`; `PathChanger/Device/CompanionHostService.swift:L93-L128`; `PathChanger/Device/CompanionHostService.swift:L193-L216`
- **Evidence**:
  - Snippet (minimal):

    ```swift
    session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    ...
    invitationHandler(true, session)
    ```

  - Data flow if instantiated: any discovered/accepted peer → encrypted but not application-authenticated MCSession → `connectedPeers`; location/status is broadcast to all peers and any decoded `.emergencyStop` calls `onEmergencyStop` (`PathChanger/Device/CompanionHostService.swift:93-128`).
  - Repository-wide exact-symbol search found no initializer or consumer outside `CompanionHostService.swift`; only its declaration and protocol extensions matched. It is therefore not a current network entry point.
- **Description**: Encryption is required, but the service supplies no identity, discovery secret, pairing code, or peer allowlist and auto-invites/accepts peers. Because the class is unreferenced, current production reachability was not established; the risk is dormant attack surface and unsafe future reactivation.
- **Preconditions**: A future code path instantiates and starts the service; an attacker is discoverable through MultipeerConnectivity with the same service type.
- **Impact**: Potential location/status disclosure and unauthorized emergency stop. Current blast radius is zero under the observed call graph.
- **Exploitability analysis**: Straightforward after reactivation; currently unreachable.
- **Why scanners may miss this**: Transport encryption can be mistaken for peer authorization, and dead-code analysis is needed to avoid overstating current exposure.
- **Chaining**: None in the current reachable application.
- **Recommended fix** (preferred + alternatives): Remove the file if the feature is abandoned. If retained, require explicit user-confirmed pairing with a short authentication string or certificate/public-key pin, persist the approved peer identity, accept exactly one peer, and authorize message types per peer.
- **Incorrect fixes to avoid**: Do not trust `MCPeerID.displayName`, service type secrecy, encryption alone, or first-peer-wins without user verification.
- **Residual risk after fix**: Nearby discovery metadata remains observable; rotate pairing state and provide revocation.
- **Priority / SLA suggestion**: Wave 2 hardening, before any companion feature is enabled.
- **Confidence**: CONFIRMED for no code reference and unsafe dormant design; production exclusion still needs build/runtime confirmation.
- **Effort**: S to remove; M to secure.

## 7. Vulnerability chains

### Same-UID compromise to root through a legitimate PathChanger prompt
The primary chain is: attacker-controlled same-UID write to accepted interpreter/module/script → version/path checks pass or are raced → user initiates expected tunnel/pair operation → administrator prompt authorizes root execution → modified code runs as root (`PathChanger/Core/PrivilegedPathSecurity.swift:125-160`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:82-119`). BUG-002 extends the race window because the authorization operation can remain live after the app reports timeout (`PathChanger/Device/TunneldManager+LaunchExecution.swift:156-203`). This is a known-class local privilege-escalation composition, not labeled a zero-day.

### Unapproved dependency to local denial of service
The secondary chain is: asynchronous startup executes pmd3 before the exact-pin gate → unapproved code emits unbounded pipe output or ignores SIGTERM → parent waits indefinitely despite advertised limits (`PathChanger/Device/DeviceManager.swift:478-491`, `PathChanger/Device/DeviceManager+CommandExecution.swift:31-57`). Impact remains within the user session unless combined with VULN-001.

## 8. Dead code & unused surface report

### Dead / unused inventory
| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-006 | `CompanionHostService` | Unreachable feature surface | Repository-wide exact-symbol search found only the class and its protocol extensions in `PathChanger/Device/CompanionHostService.swift:17-227` | Could be dynamically instantiated only if an unseen target/config exists; none was found in opened project sources | Remove, or secure before wiring |
| DEAD-007 | `TunneldManager.validateSingleTunnelInstance` | Duplicate/unreachable safety helper | Definition only at `PathChanger/Device/TunneldManager+ProcessValidation.swift:16-58`; no production/test call matched | Low; authoritative child acquisition independently deduplicates startup PIDs at `PathChanger/Device/TunneldManager+StartupAcquisitionContinuation.swift:24-76` | Remove after tests confirm acquisition path |
| DEAD-008 | `recordLaunchedTunnelChildren` | Test-only duplicate implementation | Production definition at `PathChanger/Device/TunneldManager+ProcessValidation.swift:121-136`; only wrapper/test use at `PathChanger/Device/TunneldManager+Testing.swift:194-196` | Medium if external code relies on module-internal access, though no reference was found | Collapse tests onto authoritative handoff acquisition |
| DEAD-009 | `tunnelQueue` | Unused state | Declaration only at `PathChanger/Device/TunneldManager.swift:252-253` | Low; manager is `@MainActor` | Remove misleading “serial queue” claim |
| DEAD-010 | `DevLocationBridge.minOutputSize` | Unused constant | Declaration only at `PathChanger/Device/DevLocationBridge.swift:334-335` | None | Remove or use in configuration validation |

### Complexity / unneeded surface reduction
Tunnel process ownership is implemented across state-machine PIDs, `trackedTunnelChildProcessIds`, pgrep discovery, handed-off PID validation, and two duplicate acquisition helpers (`PathChanger/Device/TunneldManager.swift:254-263`, `PathChanger/Device/TunneldManager+ProcessValidation.swift:12-136`, `PathChanger/Device/TunneldManager+StartupAcquisitionContinuation.swift:24-88`). Preserve the handed-off PID as the primary capability, retain pgrep only for bounded reconciliation, and remove dead duplicate helpers after regression coverage.

Three subprocess implementations have materially different safety properties: `TunneldCommandExecutionState` streams and caps output, while `DeviceManager` and `DevLocationBridge` wait before draining (`PathChanger/Device/TunneldCommandExecutionState.swift:37-72`, `PathChanger/Device/DeviceManager+CommandExecution.swift:23-57`, `PathChanger/Device/DevLocationBridge.swift:1129-1198`). Consolidating them reduces divergent timeout and resource-lifecycle behavior.

## 9. Bugs / mistakes / error-handling defects
BUG-002, BUG-003, and BUG-004 are the primary correctness defects. Additional non-finding observations:

- `queryTunneldAPI` ignores the HTTP response/status and silently retains old state on errors (`PathChanger/Device/TunneldManager+RSDResolution.swift:237-292`). Fixing BUG-003 should also require HTTP 200 and bounded payloads.
- `DeviceManager.runPython` and `runCommand` access `didTimeout` from different queues without consistent lock coverage (`PathChanger/Device/DeviceManager+CommandExecution.swift:31-47`, `PathChanger/Device/DeviceManager+CommandExecution.swift:89-105`). Centralizing the runner removes this race.
- Process signaling performs command and UID checks through separate `ps` calls before `kill`, leaving a narrow PID-reuse TOCTOU window (`PathChanger/Device/TunneldManager+ProcessValidation.swift:324-385`). The current command/mode/UID checks and PID > 1 guard substantially constrain impact; a privileged helper owning child process handles would be stronger.

## 10. Dependency & supply-chain notes
The direct dependency is exactly pinned to `pymobiledevice3==9.12.0`, and the resolver requires exact version equality rather than a minimum (`requirements-pathchanger.txt:11-17`, `PathChanger/Core/PythonPathResolver.swift:70-73`, `PathChanger/Core/PythonPathResolver.swift:215-229`). This is a meaningful improvement over unconstrained upgrade behavior.

The requirements file records one wheel hash as informational and explicitly does not enforce `--require-hashes` for the transitive tree (`requirements-pathchanger.txt:11-16`). Therefore the install is version-pinned but not reproducible or byte-authenticated across direct/transitive artifacts.

The privileged path verifies the module version on the same interpreter it later elevates (`PathChanger/Device/TunneldManager+LaunchExecution.swift:31-44`), but VULN-001 shows why version identity is not code provenance. Distribution should pin and verify the full dependency graph, then keep all privileged code immutable.

The app's tunneld client endpoint is explicitly loopback at `http://127.0.0.1:49151/` (`PathChanger/Core/Constants.swift:119-126`). The launch command relies on the pinned dependency's default bind because it passes no explicit host/port (`PathChanger/Device/TunneldManager+LaunchExecution.swift:46-57`). Keep a regression check that the approved dependency default remains loopback, or pass an explicit loopback bind once the command allowlist supports it.

## 11. Remediation roadmap

### Wave 0: emergency
1. Disable privileged execution through current-user-owned Python, modules, and bundle scripts; ship only a signed/root-owned narrow helper (`PathChanger/Core/PrivilegedPathSecurity.swift:125-160`, `PathChanger/Core/PrivilegedPathSecurity.swift:489-524`).
2. Until the helper exists, reject owner-writable and non-root-owned privileged code and verify immutable provenance inside the privileged boundary immediately before execution.
3. Add telemetry for authorization request ID, final helper disposition, child PID, lifecycle generation, and late completion without logging secrets.

### Wave 1: high-risk design fixes
1. Make dependency validation a blocking prerequisite before constructing/starting process-capable managers (`PathChanger/PathChangerApp.swift:17-42`, `PathChanger/Device/DeviceManager.swift:478-491`).
2. Give privileged operations durable cancellation/reconciliation semantics and bound the full Wi-Fi pair operation (`PathChanger/Device/TunneldManager+LaunchExecution.swift:156-203`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:469-528`).
3. Replace daemon RSD cache state atomically per successful response and bind health to the selected device/current generation (`PathChanger/Device/TunneldManager+RSDResolution.swift:242-315`).

### Wave 2: hardening & dead-code removal
1. Consolidate all subprocesses on one streaming, capped, process-group-aware runner (`PathChanger/Device/TunneldCommandExecutionState.swift:37-177`).
2. Remove the dormant companion service or add explicit authenticated peer enrollment before enabling it (`PathChanger/Device/CompanionHostService.swift:193-216`).
3. Remove DEAD-007 through DEAD-010 after call-graph and test confirmation.
4. Enforce full hash-locked dependency installation rather than informational wheel metadata (`requirements-pathchanger.txt:11-17`).

### Wave 3: long-term architecture
1. Make the privileged helper the sole owner of tunnel child handles, stop/reconciliation, and root-side logs.
2. Expose a capability-oriented IPC API: `start(mode, validatedUDID)`, `stop(capability)`, and `status(capability)`, never arbitrary strings or paths.
3. Treat RSD records as leases with generation, selected-device binding, and expiry rather than syntactically valid cached values.

## 12. Verification plan

### VULN-001 invariants
- Unit: current-user-owned interpreters, module trees, and scripts are always rejected for root execution, including mode `0500`/`0644` and allowed path strings.
- Unit: symlinked executable and any symlinked parent component are rejected.
- Integration: replace an approved file/inode after validation but before authorization completion; the helper must refuse it.
- Integration: IPC rejects arbitrary executable paths, command strings, environment keys, and unsupported operations.
- CI gate: code owner approval for privileged helper, authorization, `Process`, `NSAppleScript`, and subprocess policy changes.

### BUG-002 invariants
- Delayed wrapper returns after timeout with a valid PID; reconciliation must terminate it or adopt it explicitly, never discard it.
- Pair helper stalls after discovery/authorization; the operation must resolve within its deadline and leave no root child.
- App termination during authorization leaves no unowned tunnel child.

### BUG-003 invariants
- Populate two device entries, return one on the next API generation, and assert the absent device is not returned and cannot satisfy health.
- Return an invalid current entry for a previously valid UDID and assert the old value expires.
- Rotate port for one UDID and assert all commands consume the new generation.

### BUG-004 invariants
- Fixture writes more than pipe capacity and more than the configured cap before exit; runner must terminate and return the size error within a fixed budget.
- Fixture ignores SIGTERM and forks a child; runner must SIGKILL the owned process group and complete once.
- Concurrent stdout/stderr writes cannot deadlock or exceed the combined cap.

### VULN-005 invariants
- Execution spy records zero Python/pmd3 launches while dependency state is pending, validating, or invalid.
- DeviceManager initialization is side-effect free; explicit `start()` is allowed only with a current validation capability.
- Changing executable file identity invalidates prior validation before the next launch.

### Runtime detection
Record structured events for dependency identity, privileged request lifecycle, handed-off PID, late authorization completion, cleanup failure, RSD generation/expiry, and subprocess timeout escalation. Alert locally on any privileged child that exists without an active lifecycle capability. Do not record pairing-record contents or full command output.

## 13. Residual risk & future-proofing
Even after remediation, PathChanger delegates a security-critical device protocol and large parsing surface to Python dependencies. Full dependency hashes, release qualification, and a narrow root helper reduce but do not remove upstream compromise risk (`requirements-pathchanger.txt:11-17`).

The iOS device and its pairing state remain external trust anchors. The app should preserve the invariant that every device command is bound to a user-selected, validated UDID and a current-generation RSD lease (`PathChanger/Device/TunneldManager+ModeSelection.swift:69-74`, `PathChanger/Device/TunneldManager+RSDResolution.swift:296-315`).

Loopback HTTP is acceptable only as a local discovery interface while the listener remains loopback-bound and responses are treated as untrusted data. Preserve an ADR that tunneld must never bind a non-loopback address and add a dependency-release regression check against the exact approved version (`PathChanger/Core/Constants.swift:119-126`).

Do not expand root authority to solve lifecycle reliability. Root code should shrink to interface creation and process ownership; device discovery, parsing, UI, and location policy should remain unprivileged.

## 14. Missing context / questions that would change severity
1. The production ownership and mode of the selected Python binary, its site-packages tree, and `PathChanger.app/Contents/Resources/scripts/pair_wifi.py` were not supplied. Proof that every privileged code byte is root-owned and immutable would narrow VULN-001, although current policy and tests still intentionally accept user-owned content (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:125-142`).
2. Code-signing, notarization, hardened-runtime, and installer behavior were not dynamically verified. A helper designated requirement and root-owned installation would materially change the privilege analysis.
3. No live macOS authorization-dialog test was run. Confirmation that `NSAppleScript.executeAndReturnError` is forcibly canceled by an external mechanism not visible in this code would narrow BUG-002; no such mechanism was found in the opened files.
4. No device was connected, so maximum attacker-influenced pmd3 output, pairing-handshake timeout behavior, and RSD port-reuse behavior were not measured.
5. The companion target/feature roadmap was not supplied. A separate target or runtime loader outside the indexed project could change DEAD-006 reachability.
6. Upstream vendor source beyond the pinned bind/default documentation and invoked interfaces was not fully audited; cryptographic pairing implementation and pairing-record storage permissions remain supply-chain residual risk.

## Out-of-scope observations
The high finding necessarily cites supporting policy in `PathChanger/Core` because the scoped `TunneldManager` delegates its privilege decision there. No separate deep audit of all Core/UI/scripts code was performed.
