# PathChanger Scripts Security and Code-Integrity Audit

## 1. Executive summary
PathChanger’s reviewed scripts build and install the macOS app, pair one iOS device over Bonjour, and maintain a persistent stdin/stdout location-simulation bridge (`scripts/pair_wifi.py:1-30`, `scripts/location_bridge.py:1-29`, `build-app-bundle.sh:112-181`, `install.sh:1-9`).
Overall risk posture for this scope: **High**, driven by one conditional local cross-user build-artifact substitution path.
Finding count: **1 High, 3 Medium, 3 Low, 1 Info; 0 Critical**.
Top risk: the local build/install path uses a predictable temporary bundle root, verifies that mutable source bundle, then copies and installs it without verifying the final copy (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:236-245`, `build.sh:33-40`, `install.sh:22-44`).
Other material risks are predictable `/tmp` validation files, helper-level network operations without deadlines, and a coverage gate that can return success after tests or coverage generation fail (`scripts/validate-release-config.sh:53-73`, `scripts/pair_wifi.py:88-108`, `scripts/location_bridge.py:93-110`, `scripts/coverage.sh:43-92`).
The Wi-Fi helper’s new single-device selection fails closed on zero, ambiguous, and unmatched discovery results; it no longer iterates over every advertisement (`scripts/pair_wifi.py:53-81`, `scripts/pair_wifi.py:142-166`).
The location bridge is not a network listener: it receives NDJSON on stdin and emits responses on stdout (`scripts/location_bridge.py:257-277`). No reviewed Python file invokes `os.system`, `subprocess`, `shell=True`, `eval`, or unsafe deserialization; the network sinks are direct library calls (`scripts/pair_wifi.py:88-108`, `scripts/location_bridge.py:93-110`).
Immediate actions: within 48 hours, replace the shared/predictable bundle root and verify the final `dist` and installed artifacts; within 7 days, replace fixed `/tmp` files and add bounded network deadlines; within 30 days, make coverage enforcement fail closed and harden bridge limits.

## 2. Threat model

### System summary
The reviewed surface is a local macOS toolchain and two Python helpers. `pair_wifi.py` discovers a manual-pairing Bonjour service and asks `pymobiledevice3` to write a pair record; its own documentation states that this may run as root (`scripts/pair_wifi.py:3-30`, `scripts/pair_wifi.py:88-108`). `location_bridge.py` keeps DVT/location sessions open for repeated location changes and accepts commands over a child-process pipe (`scripts/location_bridge.py:3-29`, `scripts/location_bridge.py:123-193`, `scripts/location_bridge.py:257-335`). Build scripts assemble, sanitize, sign, copy, and optionally install an app bundle into `/Applications` (`build-app-bundle.sh:112-245`, `build.sh:28-59`, `install.sh:20-44`).

Primary assets are the integrity of the installed app and its embedded Python helpers, the signing identity and resulting signature, iOS pairing records, device-selection authenticity, simulated-location integrity, and availability of the bridge. Data exposed in this scope is mainly device names, addresses, ports, UDIDs, coordinates, request IDs, and exception text (`scripts/pair_wifi.py:88-120`, `scripts/location_bridge.py:181-193`, `scripts/location_bridge.py:221-253`).

Deployment is a single-user local desktop app, not a multi-tenant or internet-facing server. Relevant actors are the local operator, another local account/process on a shared Mac, a device or service on the same LAN, a paired iOS device, a malformed/misconfigured tunnel endpoint, and CI/release automation.

### Entry points and dangerous sinks
- CLI options `--timeout` and `--name` enter the privileged pairing helper (`scripts/pair_wifi.py:169-190`).
- Bonjour advertisements provide device name, IP list, and port, which flow into a pairing connection (`scripts/pair_wifi.py:83-108`).
- NDJSON lines from stdin provide command, request ID, UDID, coordinates, RSD address, and RSD port (`scripts/location_bridge.py:221-246`, `scripts/location_bridge.py:266-331`).
- RSD address/port reach `RemoteServiceDiscoveryService`; UDID reaches `create_using_usbmux`; coordinates reach `LocationSimulation.set` (`scripts/location_bridge.py:93-110`, `scripts/location_bridge.py:164-193`).
- Environment variables and positional arguments control build roots, configuration, signing mode, and destination roots (`build-app-bundle.sh:76-89`, `build.sh:33-35`).
- Destructive filesystem sinks include `rm -rf`, recursive metadata operations, bundle copy, and `/Applications` replacement (`build-app-bundle.sh:118-130`, `build-app-bundle.sh:29-42`, `build.sh:28-40`, `install.sh:32-44`).

### Trust boundaries
1. Same-LAN Bonjour advertisement → root-capable pairing process (`scripts/pair_wifi.py:83-108`, `scripts/pair_wifi.py:183-190`).
2. Parent Swift process/pipe → Python JSON parser and device-control APIs (`scripts/location_bridge.py:221-246`, `scripts/location_bridge.py:257-335`).
3. RSD host/port tuple → outbound device/tunnel connection (`scripts/location_bridge.py:93-103`).
4. Local environment and shared temporary namespace → mutable app-bundle workspace (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:118-130`).
5. Verified temporary bundle → unverified `dist` copy → `/Applications` (`build-app-bundle.sh:236-245`, `build.sh:37-40`, `install.sh:25-44`).
6. Shared `/tmp` namespace → release-validation output redirections (`scripts/validate-release-config.sh:53-73`).

### Top abuse cases
1. Another local account prepares the predictable fallback bundle workspace before an operator runs the local build/install path; the mutable bundle is swapped after verification and before final copy, affecting one installed app (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:236-245`, `build.sh:37-40`, `install.sh:22-44`). Detection is low because the final copy is not re-verified.
2. Another local account pre-creates either fixed validation pathname as a symlink; a local preflight truncates a file writable by the victim (`scripts/validate-release-config.sh:53-73`). Detection is low unless the target corruption is noticed.
3. A selected LAN service accepts a connection but does not complete pairing, leaving the helper awaiting dependency behavior without an application deadline (`scripts/pair_wifi.py:88-108`). Detection is moderate through a visibly hung pairing action.
4. A stale or unresponsive RSD endpoint blocks the sequential bridge before it can process subsequent requests (`scripts/location_bridge.py:93-110`, `scripts/location_bridge.py:266-335`). Detection is moderate through missing responses.
5. A malformed local caller supplies many distinct valid device tuples, retaining one cached session per tuple until shutdown (`scripts/location_bridge.py:123-161`, `scripts/location_bridge.py:195-202`). Blast radius is the bridge process.
6. A local caller supplies an arbitrary RSD host/port; the bridge attempts a protocol connection without first constraining address family, range, or provenance (`scripts/location_bridge.py:93-103`, `scripts/location_bridge.py:221-246`, `scripts/location_bridge.py:307-331`). Impact is limited by the stdin-only boundary.
7. A failing test or `llvm-cov` command is masked, allowing the contributor-facing coverage script to print completion and exit successfully (`scripts/coverage.sh:43-92`, `scripts/coverage.sh:108-142`).
8. Installation deletes all matching app directories before the replacement copy succeeds, leaving no installed app if the final copy fails (`install.sh:32-44`). Detection is immediate but recovery is manual.

## 3. Methodology notes

### Passes completed
- **Pass A:** enumerated CLI, Bonjour, stdin JSON, environment, filesystem, signing, and network boundaries.
- **Pass B:** authentication/authorization is largely N/A for these non-server scripts. Device selection and pairing consent are delegated to `pymobiledevice3`; single-device selection logic was reviewed directly (`scripts/pair_wifi.py:53-81`, `scripts/pair_wifi.py:142-166`).
- **Pass C:** searched for command/shell injection, path traversal, unsafe deserialization, and SSRF-like outbound connection control. Shell variables used at destructive sinks are quoted, but pathname provenance and temporary-file safety remain defective (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:118-130`, `scripts/validate-release-config.sh:53-73`).
- **Pass D:** reviewed hard-coded secrets, randomness, and TLS-disable patterns. None are present in the opened scope; pairing and RSD cryptographic behavior is delegated to `pymobiledevice3` (`scripts/pair_wifi.py:42-47`, `scripts/location_bridge.py:49-73`).
- **Pass E:** reviewed device/network identifiers and error leakage (`scripts/pair_wifi.py:88-120`, `scripts/location_bridge.py:181-193`, `scripts/location_bridge.py:340-346`).
- **Pass F:** reviewed timeouts, cache lifetime, signal shutdown, partial installation, pipeline status, and fail-open error handling.
- **Pass G:** reviewed direct Python imports and build-time embedding. Dependency internals and dependency manifests were not in this agent’s assigned scope.
- **Pass H:** reviewed privilege statements, `/Applications`, temporary paths, code signing, error verbosity, remote installer patterns, and listener binds. No `curl|bash` or `0.0.0.0` bind exists in the opened files; the bridge uses stdin/stdout (`scripts/location_bridge.py:257-277`).
- **Pass I:** checked references and local symbol use for dead/unused candidates.
- **Pass J:** analyzed the temporary-workspace → signature verification → unverified copy → install chain and the RSD-control → no deadline/cache-retention chain.
- **Pass K:** supplied regression tests and invariants for the High finding and verification guidance for all findings.

### Files reviewed
`scripts/pair_wifi.py:1-203`, `scripts/location_bridge.py:1-354`, `scripts/create_icon.py:1-144`, `scripts/coverage.sh:1-142`, `scripts/validate-release-config.sh:1-189`, `scripts/validate-w1-convergence-lock.sh:1-117`, `scripts/test_pair_wifi_selection.py:1-66`, `install.sh:1-56`, `build.sh:1-75`, `build-app-bundle.sh:1-275`, and `DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh:1-334`.

### Coverage gaps and assumptions
- The Swift parent process, its validation of bridge requests, entitlements, workflows, and `pymobiledevice3`/Pillow internals were not audited. Minimal workflow/document references were consulted only to establish whether an in-scope script is intended to be run.
- VULN-001 assumes the fallback path resolves under a namespace writable by another local account/process, such as when `TMPDIR` is absent or set to `/tmp`, and that the operator later launches or installs the resulting bundle.
- BUG-003 is reduced if the installed `pymobiledevice3` version independently enforces shorter finite deadlines.
- VULN-005 becomes materially more severe only if untrusted data can reach the bridge’s stdin through the parent app; that upstream boundary was out of scope.

## 4. Critical & High findings

### [HIGH] Predictable mutable build workspace permits bundle substitution after signature verification
- **ID**: VULN-001
- **Category**: Vulnerability
- **CWE / OWASP / ASVS**: CWE-377, CWE-367; OWASP A08:2021 Software and Data Integrity Failures
- **Location**: `build-app-bundle.sh:L76-L81`, `build-app-bundle.sh:L118-L130`, `build-app-bundle.sh:L196-L245`, `build.sh:L33-L40`, `install.sh:L22-L44`
- **Evidence**:
  - Snippet:
    ```bash
    APP_BUNDLE_BUILD_ROOT="${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}"
    APP_DIR="$APP_BUNDLE_BUILD_ROOT/$APP_BUNDLE_NAME"
    rm -rf "$APP_DIR"
    mkdir -p "$MACOS_DIR"
    ```
    (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:118-130`)
  - The source bundle is signed and verified in the mutable build root (`build-app-bundle.sh:196-245`).
  - `build.sh` then copies that source to `dist` with `ditto` but performs no `codesign --verify` on the destination (`build.sh:33-59`).
  - `install.sh` trusts the existence of the destination directory and recursively copies it to `/Applications` without signature verification (`install.sh:22-44`).
  - Data flow: predictable/shared root or externally supplied root → mutable `APP_DIR` → signing/verification → time-of-check/time-of-use gap → unverified `ditto` destination → unverified `/Applications` copy.
- **Description**: The local build path uses a fixed bundle directory beneath `TMPDIR`, with a literal `/tmp` fallback. It neither creates the root atomically nor verifies ownership, mode, or symlink ancestry. The bundle remains mutable after signature verification. The final `dist` copy is then sanitized but not signature-verified, and the installer copies it again without verification. On a shared host, an account that controls the predictable parent can replace the bundle between verification and copy, causing a different artifact to be staged or installed.
- **Preconditions**: Another local account/process can control the resolved build-root namespace; the operator runs `build.sh` or `install.sh`; and the attacker wins the post-verification substitution window. Privileged impact additionally requires the operator to run with privileges or permissions sufficient to install into `/Applications`.
- **Impact**: Integrity and authenticity of one locally built/installed PathChanger bundle can be lost. The substituted code runs when the operator launches the app, with that operator’s authority; if installation/build was elevated, filesystem impact can be larger. The authoritative GitHub workflow may have separate runner isolation, but that does not protect this local script path.
- **Exploitability analysis**: This is local, interaction-dependent, and timing-dependent, not remotely exploitable. The fixed fallback name and lack of final verification make the conditions practical on a shared or already partially compromised Mac. Blast radius is the operator executing the resulting app and the one installed bundle, not other tenants or an internet service.
- **Why scanners may miss this**: Each individual command quotes its pathname and signature verification is present. The defect only appears by following ownership and mutability across two scripts and the interval between verification, `ditto`, and installation.
- **Chaining**: The shared-root weakness combines with the missing post-copy verification. Either control alone would be less useful: an attacker-controlled temporary namespace still has to cross the final trust decision, and a missing final verification needs a mutation opportunity.
- **Recommended fix** (preferred + alternatives):
  - Create a private root with `mktemp -d "${TMPDIR:-/tmp}/pathchanger-app-build.XXXXXXXX"`; set mode `0700`; retain the exact returned path; install a trap that removes only that verified directory.
  - Reject any caller-supplied root whose canonical parent is not owned by the effective user, whose ancestry contains a symlink, or whose permissions permit group/other writes. When an elevated build is unavoidable, drop privileges for build assembly.
  - Verify `codesign --verify --deep --strict` on the final `dist/PathChanger.app` after all copy/sanitization steps, then verify the staged installation immediately before an atomic replacement.
  - Prefer staging a verified bundle adjacent to the final destination and atomically renaming it; preserve the previous app until replacement succeeds.
  - Add audit output containing canonical source/destination paths, owner UID, mode, and the final code-directory hash.
  - Regression invariant: the build root is unique, mode `0700`, owned by the effective UID, not a symlink, and the exact artifact copied to `dist` and `/Applications` passes signature verification after its last mutation.
- **Incorrect fixes to avoid**: Merely quote the path (it is already quoted), add a random suffix using `$RANDOM`, verify only the temporary source again, or suppress symlink errors. Do not use `rm -rf` on a canonicalized path unless its ownership and expected root have already been established.
- **Residual risk after fix**: A process already running as the same operator may still modify same-user build inputs. A private atomic workspace and final signature checks remove the cross-user predictable-path and TOCTOU paths but do not substitute for host integrity.
- **Priority / SLA suggestion**: Patch within 48 hours before recommending local `install.sh` on shared systems.
- **Confidence**: CONFIRMED
- **Effort**: M

## 5. Medium findings

### [MEDIUM] Fixed `/tmp` validation files allow cross-user symlink clobbering
- **ID**: VULN-002
- **Category**: Vulnerability
- **CWE / OWASP / ASVS**: CWE-59, CWE-377; OWASP A01:2021 Broken Access Control
- **Location**: `scripts/validate-release-config.sh:L53-L73`
- **Evidence**:
  - Snippet:
    ```bash
    /usr/libexec/PlistBuddy ... >/tmp/pathchanger-get-task-allow
    /usr/libexec/PlistBuddy ... >/tmp/pathchanger-entitlement-check
    ```
    (`scripts/validate-release-config.sh:53-68`)
  - Both names are predictable, opened through ordinary shell redirection, reused across runs, and removed only after use (`scripts/validate-release-config.sh:53-73`).
  - Data flow: shared temporary pathname chosen by script → shell follows pre-existing symlink during truncating redirection → PlistBuddy output overwrites victim-writable target.
- **Description**: Local validation uses two global, predictable files rather than securely created private temporary files. An existing symlink is followed when the shell opens the redirection target.
- **Preconditions**: Another local account/process can create the fixed pathname before a victim runs the validation script and can predict a victim-writable target. CI isolation is a compensating control only for CI, not local preflight.
- **Impact**: Limited integrity/availability loss through truncation and replacement with a short entitlement value. If run elevated, the writable target set expands. The output content is constrained, which limits direct code-execution utility.
- **Exploitability analysis**: No race is required if the attacker creates the path first. The victim must run the script. Blast radius is one targeted file per pathname/run.
- **Why scanners may miss this**: The files appear to be harmless transient booleans, but redirection happens before PlistBuddy and follows symlinks.
- **Chaining**: Elevated invocation increases impact; pairing this with a sensitive local configuration target can cause lockout or operational failure.
- **Recommended fix** (preferred + alternatives):
  - Avoid files entirely: capture PlistBuddy output in a shell variable and compare it.
  - If a file is necessary, create a private directory using `mktemp -d`, mode `0700`, and clean it with a trap.
  - Treat unexpected PlistBuddy errors separately from “key absent” and fail closed on unreadable entitlements.
  - Add a test that pre-creates the former names as symlinks and confirms the external target is unchanged.
- **Incorrect fixes to avoid**: Adding PID-only suffixes, checking `-L` before redirection, or deleting the path before use; each remains race-prone.
- **Residual risk after fix**: Variable capture removes pathname risk; malformed plist handling still depends on explicit exit-status checks.
- **Priority / SLA suggestion**: Fix this sprint, before the next local release preflight.
- **Confidence**: CONFIRMED
- **Effort**: S

### [MEDIUM] Device network awaits have no helper-level deadlines and can stall the control plane
- **ID**: BUG-003
- **Category**: Error-handling
- **CWE / OWASP / ASVS**: CWE-400, CWE-770; OWASP A05:2021 Security Misconfiguration
- **Location**: `scripts/pair_wifi.py:L83-L108`, `scripts/location_bridge.py:L93-L110`, `scripts/location_bridge.py:L164-L193`, `scripts/location_bridge.py:L257-L335`
- **Evidence**:
  - Pairing awaits `service.connect(autopair=True)` directly; only Bonjour browsing has an explicit timeout (`scripts/pair_wifi.py:83-108`).
  - RSD connect, DVT context entry, location context entry, set, and clear are directly awaited without `asyncio.timeout`/`wait_for` (`scripts/location_bridge.py:93-110`, `scripts/location_bridge.py:164-193`).
  - `_serve` handles one request at a time, so one blocked await prevents ping, quit, and later location requests from completing (`scripts/location_bridge.py:266-335`).
  - Data flow: LAN/device/tunnel responsiveness → unbounded dependency await → sequential helper stops making progress.
- **Description**: The helpers rely entirely on undocumented dependency/socket timeout behavior at security-sensitive network boundaries. A non-responsive selected pairing service or RSD/DVT endpoint can monopolize the helper indefinitely.
- **Preconditions**: A selected service or tunnel endpoint accepts or begins a connection but does not complete the expected protocol, or the dependency itself waits indefinitely. The app does not externally kill and restart the helper within a stricter deadline.
- **Impact**: Availability loss for Wi-Fi pairing or all location updates handled by the bridge. No confidentiality or privilege escalation follows directly. Blast radius is one helper process and its current user/device session.
- **Exploitability analysis**: Same-LAN influence is relevant to pairing; bridge influence depends on who controls the supplied RSD endpoint. User interaction is required to select/attempt pairing. If the dependency has finite internal deadlines, the duration and severity decrease.
- **Why scanners may miss this**: The code is asynchronous and contains a browse timeout, which can look bounded even though later protocol stages are not.
- **Chaining**: VULN-005 allows a bad endpoint tuple to reach these unbounded awaits; BUG-006 makes graceful termination less reliable while stdin remains open.
- **Recommended fix** (preferred + alternatives):
  - Wrap discovery, connect, DVT enter, location enter, set, clear, and close in stage-specific `asyncio.timeout` scopes.
  - On timeout, close/drop the partial session, return a stable error code, and allow subsequent requests.
  - Keep the bridge responsive to `quit` by running the active device operation as a cancellable task rather than blocking the sole request loop.
  - Add tests with never-completing async fakes and assert bounded response and cleanup.
- **Incorrect fixes to avoid**: One very large global timeout, catching `TimeoutError` without closing partial contexts, or retrying indefinitely.
- **Residual risk after fix**: Slow but legitimate devices may require calibrated deadlines and one bounded retry. Metrics should distinguish connect, handshake, set, and cleanup timeouts.
- **Priority / SLA suggestion**: Fix within 7 days.
- **Confidence**: LIKELY
- **Effort**: M

### [MEDIUM] Coverage enforcement can return success after tests or report generation fail
- **ID**: BUG-004
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-252; OWASP A08:2021 Software and Data Integrity Failures
- **Location**: `scripts/coverage.sh:L5-L10`, `scripts/coverage.sh:L40-L61`, `scripts/coverage.sh:L64-L103`, `scripts/coverage.sh:L108-L142`
- **Evidence**:
  - The script enables `set -e` but not `pipefail`; therefore `swift test ... | tee` reports the status of `tee`, not necessarily the test process (`scripts/coverage.sh:5-10`, `scripts/coverage.sh:40-45`).
  - It does not clean `.build`; it finds the first existing `default.profdata` and test binary, permitting stale artifacts to be selected after a failed run (`scripts/coverage.sh:40-61`).
  - Every `llvm-cov` generation command is followed by `|| true` (`scripts/coverage.sh:64-103`).
  - Threshold enforcement runs only when a `TOTAL` line exists; an empty/failed report skips the threshold and reaches “Done!” with success (`scripts/coverage.sh:108-142`).
  - Data flow: failed tests/report → pipeline/tolerated failure → missing `TOTAL` → threshold branch skipped → exit 0.
- **Description**: The contributor-facing quality gate is fail open. It can reuse stale profiler data or silently omit a report, then claim completion even when `--threshold` was requested.
- **Preconditions**: Tests or `llvm-cov` fail while `tee` succeeds, or stale artifacts exist. A human or automation trusts the script exit code.
- **Impact**: Incorrect release/merge evidence and regression risk, including reduced security-test coverage. The authoritative CI shown to this agent runs its own test and coverage commands, which limits immediate production blast radius, but local policy enforcement remains unreliable.
- **Exploitability analysis**: This is primarily an integrity/correctness defect, not a remote attack. A contributor can intentionally or accidentally obtain a false-green local result.
- **Why scanners may miss this**: `set -e` appears to enforce failures, but pipeline status and explicit `|| true` override it.
- **Chaining**: It can conceal missing regression coverage for VULN-001 through VULN-005.
- **Recommended fix** (preferred + alternatives):
  - Use `set -euo pipefail` and capture `PIPESTATUS[0]` if custom reporting is required.
  - Derive exact profiler and binary paths from the just-completed build rather than `find | head`.
  - Remove `|| true`; require non-empty outputs and a parseable `TOTAL` whenever a threshold is supplied.
  - Reject non-numeric/missing threshold arguments and compare decimal coverage with a numeric tool.
  - Add negative tests for failing `swift test`, failing `llvm-cov`, missing `TOTAL`, and stale artifacts.
- **Incorrect fixes to avoid**: Only adding `pipefail` while retaining `|| true`, or defaulting a missing coverage value to 100/0 without failing.
- **Residual risk after fix**: Coverage percentage remains a proxy; security invariants still need focused tests.
- **Priority / SLA suggestion**: Fix this sprint.
- **Confidence**: CONFIRMED
- **Effort**: S

## 6. Low / Info

### [LOW] Unvalidated RSD endpoint tuples drive arbitrary outbound attempts and unbounded session retention
- **ID**: VULN-005
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-20, CWE-918, CWE-770; OWASP A10:2021 SSRF (analogue)
- **Location**: `scripts/location_bridge.py:L93-L103`, `scripts/location_bridge.py:L123-L161`, `scripts/location_bridge.py:L221-L246`, `scripts/location_bridge.py:L307-L331`
- **Evidence**:
  - Validation checks request ID, command, UDID, and set-location coordinates, but does not type/range-check `rsd_address` or `rsd_port` (`scripts/location_bridge.py:221-246`).
  - The values flow directly to `RemoteServiceDiscoveryService((rsd_address, int(rsd_port)))` (`scripts/location_bridge.py:93-103`).
  - Every distinct `(udid, rsd_address, rsd_port)` gets a session entry with no maximum, TTL, or LRU eviction; entries close only on explicit drop/error or process shutdown (`scripts/location_bridge.py:123-161`, `scripts/location_bridge.py:195-202`).
- **Description**: The bridge is an outbound-connection-capable deputy with no endpoint allowlist and a cache keyed by caller-controlled values. This is not an exposed server-side SSRF in the current file because input arrives through stdin, but an upstream validation failure would gain network-reach and resource-retention consequences.
- **Preconditions**: An untrusted or corrupted source can write bridge stdin, or the parent forwards untrusted endpoint fields. Cache growth additionally requires endpoints that complete enough of the device handshake to be cached.
- **Impact**: Limited network probing/protocol traffic and bridge-local file-descriptor/memory pressure. No direct internet exposure or privilege transition is evidenced in this scope.
- **Exploitability analysis**: A caller that already controls the child pipe has substantial local influence, so this is defense in depth. Severity should be raised if the parent accepts these fields from lower-trust IPC or network input.
- **Why scanners may miss this**: The connection is through a domain-specific library, not `requests` or a raw socket, and the cache growth spans validation and session-management methods.
- **Chaining**: Combines with BUG-003 to turn a supplied endpoint into a whole-bridge stall.
- **Recommended fix** (preferred + alternatives):
  - Require `rsd_address` to parse as an expected IPv6 tunnel address (or a narrowly documented allowed family) and `rsd_port` to be an integer in `1...65535`.
  - Bind the tuple to the selected/paired UDID in the parent and reject mismatches.
  - Cap cache entries, evict/close least-recently-used sessions, and close old sessions when the tunnel endpoint rotates.
  - Add allow/deny and cache-cap tests.
- **Incorrect fixes to avoid**: Regex-only IP checks, DNS resolution without post-resolution address validation, or dropping cache references without closing sessions.
- **Residual risk after fix**: A compromised valid device/tunnel remains a trusted protocol peer and must be contained by deadlines and parser robustness.
- **Priority / SLA suggestion**: Harden within 30 days; reassess after parent-process data-flow review.
- **Confidence**: LIKELY
- **Effort**: M

### [LOW] Custom SIGTERM handling can leave the bridge blocked on stdin
- **ID**: BUG-006
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-400; OWASP N/A (local reliability)
- **Location**: `scripts/location_bridge.py:L248-L255`, `scripts/location_bridge.py:L266-L275`, `scripts/location_bridge.py:L348-L354`
- **Evidence**:
  - SIGTERM/SIGINT only set `_shutdown_requested` (`scripts/location_bridge.py:248-255`).
  - The loop is awaiting `run_in_executor(None, sys.stdin.readline)` and re-checks the flag only after that blocking read returns (`scripts/location_bridge.py:266-275`).
  - The custom handler replaces default SIGTERM termination; cleanup runs only after control exits the loop (`scripts/location_bridge.py:266-335`, `scripts/location_bridge.py:348-354`).
- **Description**: If the parent sends SIGTERM but leaves stdin open and idle, the worker thread can remain blocked and the coroutine cannot observe the shutdown flag.
- **Preconditions**: The pipe remains open with no newline/EOF after the signal.
- **Impact**: A lingering helper process and delayed resource cleanup. Blast radius is one bridge process.
- **Exploitability analysis**: Primarily operational; a local caller controlling both pipe and signal timing can reproduce the condition.
- **Why scanners may miss this**: The loop condition and signal handler look cooperative, but the actual blocking call runs in a worker thread.
- **Chaining**: Cached device sessions remain open longer; BUG-003 can complicate shutdown further.
- **Recommended fix** (preferred + alternatives):
  - Use an asyncio pipe reader and signal-triggered task cancellation, or have the signal handler close a dedicated wakeup FD/reader.
  - Bound shutdown and force-close cached sessions in cancellation-safe `finally` blocks.
  - Test SIGTERM with stdin intentionally left open and assert process exit by deadline.
- **Incorrect fixes to avoid**: Polling the flag only before another blocking `readline`, or calling complex async cleanup directly from the signal handler.
- **Residual risk after fix**: Dependency close operations still need their own deadlines.
- **Priority / SLA suggestion**: Fix within 30 days.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] Installer deletes all matching apps before a replacement is safely staged
- **ID**: BUG-007
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-664; OWASP A08:2021 Software and Data Integrity Failures
- **Location**: `install.sh:L25-L44`
- **Evidence**:
  - The only precondition check is that `dist/PathChanger.app` is a directory (`install.sh:25-29`).
  - Every `/Applications/PathChanger*.app` directory is recursively removed before the copy begins (`install.sh:32-40`).
  - The replacement is a non-atomic `cp -R` after deletion (`install.sh:42-44`).
- **Description**: A copy failure leaves no prior installation, and the prefix match can remove intentionally separate app variants that happen to share the name.
- **Preconditions**: The user runs the installer with permissions to delete matching apps; the final copy fails or a separately named matching app should have been retained.
- **Impact**: Local availability and integrity loss limited to matching app bundles in `/Applications`.
- **Exploitability analysis**: This is user-initiated and narrowly scoped, so security exploitability is low. Disk-full, permission, and interrupted-copy conditions are sufficient for accidental impact.
- **Why scanners may miss this**: Paths are quoted and `find` is depth-limited; the defect is destructive ordering and over-broad policy, not injection.
- **Chaining**: VULN-001 can supply an untrusted replacement after the trusted prior app has already been removed.
- **Recommended fix** (preferred + alternatives):
  - Validate and signature-check a staged destination first.
  - Replace only the canonical target by default; require explicit migration logic for known legacy bundle names.
  - Use same-filesystem atomic rename with rollback to the previous bundle.
  - Test copy failure and confirm the old app remains launchable.
- **Incorrect fixes to avoid**: Ignore copy errors, broaden the wildcard, or delete the old app in a trap.
- **Residual risk after fix**: Atomic replacement still needs sufficient disk space and a recovery path for post-install launch failure.
- **Priority / SLA suggestion**: Fix within 30 days.
- **Confidence**: CONFIRMED
- **Effort**: M

### [INFO] Helpers emit raw device topology and dependency exception details
- **ID**: INFO-008
- **Category**: Error-handling
- **CWE / OWASP / ASVS**: CWE-209; OWASP A09:2021 Security Logging and Monitoring Failures
- **Location**: `scripts/pair_wifi.py:L88-L120`, `scripts/pair_wifi.py:L194-L199`, `scripts/location_bridge.py:L181-L193`, `scripts/location_bridge.py:L340-L346`
- **Evidence**:
  - Pairing output includes Bonjour name, IP list, port, selected address, exception type, and raw exception text (`scripts/pair_wifi.py:88-120`, `scripts/pair_wifi.py:194-199`).
  - Bridge responses return raw dependency exception type/text, and fatal errors are emitted on both protocol stdout and stderr (`scripts/location_bridge.py:181-193`, `scripts/location_bridge.py:340-346`).
- **Description**: Diagnostics can expose local device names, network topology, dependency paths, or protocol details to any log collector or UI that persists helper output.
- **Preconditions**: Output is captured or shared beyond the current local operator. Persistent logging behavior was outside scope.
- **Impact**: Minor local information disclosure; no secret material was observed in these messages.
- **Exploitability analysis**: Low-value in the stated single-user desktop model. Severity increases only if diagnostics are uploaded or broadly readable.
- **Why scanners may miss this**: Sensitive values are produced by service-discovery objects and third-party exceptions rather than explicit credential variables.
- **Chaining**: Network details can assist troubleshooting or later local reconnaissance but do not create access.
- **Recommended fix** (preferred + alternatives):
  - Emit stable user-facing error codes; put raw details behind an explicit diagnostic mode.
  - Redact UDIDs and truncate/normalize IP/device identifiers in persisted logs.
  - Document log retention and permissions.
- **Incorrect fixes to avoid**: Swallow all errors or remove actionable error codes.
- **Residual risk after fix**: Users can still intentionally enable detailed local diagnostics.
- **Priority / SLA suggestion**: Opportunistic hardening.
- **Confidence**: CONFIRMED
- **Effort**: S

## 7. Vulnerability chains

### Chain A — shared temporary namespace to installed code integrity loss
The root is selected from an environment value with a `/tmp` fallback, and a fixed child directory is removed/recreated (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:118-130`). The bundle is verified while still inside that mutable namespace (`build-app-bundle.sh:236-245`). A later script copies it to `dist` without verifying the copy (`build.sh:33-59`), and the installer trusts directory existence before removing prior apps and copying the bundle to `/Applications` (`install.sh:25-44`). The missing invariant is: “the exact bytes verified are the exact bytes installed.”

### Chain B — caller-controlled endpoint to whole-bridge availability loss
`rsd_address` and `rsd_port` are not validated (`scripts/location_bridge.py:221-246`), are used for outbound connection and as cache-key material (`scripts/location_bridge.py:93-103`, `scripts/location_bridge.py:123-161`), and all connection/device operations are awaited in a sequential loop without helper deadlines (`scripts/location_bridge.py:164-193`, `scripts/location_bridge.py:266-335`). An upstream trust-boundary mistake can therefore become outbound protocol traffic, resource retention, or a bridge-wide stall.

No zero-day-class label is warranted. Both chains are compositions of known temporary-path/TOCTOU, input-validation, timeout, and resource-lifetime weakness classes.

## 8. Dead code & unused surface report

| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-001 | `center_y`, `pin_highlight` in `scripts/create_icon.py` | Unused local variables | Assigned but not read by subsequent drawing logic (`scripts/create_icon.py:13-18`, `scripts/create_icon.py:37-47`) | None beyond trivial visual refactor risk | Remove after running icon-generation visual comparison. |
| DEAD-002 | `scripts/create_icon.py` | CANDIDATE-UNUSED — NEEDS RUNTIME/CONFIG CONFIRMATION | The script is standalone and writes iconset outputs only when manually invoked (`scripts/create_icon.py:113-144`); no in-scope build script invokes it (`build-app-bundle.sh:112-181`) | It may be an intentional maintainer tool | Document its manual role or move it to a clearly named developer-tools area; do not delete without maintainer confirmation. |
| DEAD-003 | `scripts/test_pair_wifi_selection.py` | Orphaned/manual test candidate | It dynamically imports the script and contains seven `unittest` cases (`scripts/test_pair_wifi_selection.py:11-66`), but no in-scope script invokes it | Removing it would lose regression coverage for the fail-closed selector | Integrate it into CI/test documentation rather than delete it. |

### Complexity / unneeded surface reduction
The bridge’s multi-session dictionary expands the lifetime and cleanup surface beyond the product’s apparent single-device focus (`scripts/location_bridge.py:123-161`, `scripts/pair_wifi.py:3-20`). If the application supports only one active device/tunnel, a single replace-on-change session would remove cache-capacity and stale-session risks. This requires parent-app confirmation before change.

## 9. Bugs / mistakes / error-handling defects
- BUG-003: a non-responsive device stage can block all later work because network awaits have no helper deadline and the request loop is sequential (`scripts/location_bridge.py:164-193`, `scripts/location_bridge.py:266-335`).
- BUG-004: pipeline status, stale artifact discovery, tolerated `llvm-cov` failures, and conditional threshold parsing produce false-green coverage results (`scripts/coverage.sh:40-61`, `scripts/coverage.sh:64-128`).
- BUG-006: the shutdown flag does not wake the executor-backed blocking stdin read (`scripts/location_bridge.py:248-275`).
- BUG-007: destructive removal precedes a non-atomic replacement (`install.sh:32-44`).
- Cleanup exceptions are intentionally swallowed in bridge close paths (`scripts/location_bridge.py:112-121`, `scripts/location_bridge.py:195-201`). This avoids one close failure blocking others, but leaves no observable signal for persistent resource-cleanup defects; record a bounded diagnostic counter rather than failing shutdown.
- `DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh` runs `git status --porcelain | head -10` under `pipefail`; sufficiently long output can cause an upstream SIGPIPE-dependent non-zero status, aborting before the summary (`DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh:6-8`, `DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh:174-186`). Treat as a minor operational defect.

## 10. Dependency & supply-chain notes
- The pairing helper imports Bonjour and remote-pairing implementations directly from `pymobiledevice3` (`scripts/pair_wifi.py:42-47`); the bridge lazily imports DVT, location simulation, RSD, and usbmux support (`scripts/location_bridge.py:45-73`). Timeout, peer-authentication, and parser behavior therefore depend on the installed version.
- `create_icon.py` depends on Pillow (`scripts/create_icon.py:4-6`). It is a developer-time asset generator, not copied into the app by the reviewed bundle-copy steps (`build-app-bundle.sh:112-181`).
- The bundle embeds Python source helpers as executable resources but does not vendor or hash their Python dependencies in the reviewed script (`build-app-bundle.sh:155-181`). Code signing protects the assembled bundle only after signing; VULN-001 identifies the subsequent local copy gap.
- No reviewed script downloads and executes remote content. Dependency pinning and manifest integrity were not assessed because manifests were outside this agent’s assigned scope.

## 11. Remediation roadmap

### Wave 0 — emergency integrity control (48 hours)
1. Replace the predictable bundle workspace with a private atomic directory; validate owner/mode/symlink ancestry (`build-app-bundle.sh:76-81`, `build-app-bundle.sh:118-130`).
2. Verify the final `dist` and staged installation after their last mutation and before atomic replacement (`build.sh:37-59`, `install.sh:25-44`).

### Wave 1 — high-risk design fixes (7 days)
1. Remove fixed `/tmp` output files from release validation (`scripts/validate-release-config.sh:53-73`).
2. Add stage-specific deadlines, cancellation, and cleanup to pairing and bridge network operations (`scripts/pair_wifi.py:88-108`, `scripts/location_bridge.py:93-110`, `scripts/location_bridge.py:164-193`).
3. Make the coverage script fail closed (`scripts/coverage.sh:40-128`).

### Wave 2 — hardening and surface reduction (30 days)
1. Validate/bind RSD tuples and bound session count/lifetime (`scripts/location_bridge.py:93-103`, `scripts/location_bridge.py:123-161`, `scripts/location_bridge.py:221-246`).
2. Make signal shutdown wake the read loop (`scripts/location_bridge.py:248-275`).
3. Stage installation atomically and narrow legacy cleanup (`install.sh:32-44`).
4. Redact routine logs and expose raw dependency errors only in explicit diagnostics (`scripts/pair_wifi.py:88-120`, `scripts/location_bridge.py:181-193`).

### Wave 3 — long-term architecture
Define one secure temporary-artifact API/invariant for local and CI builds; define one device-endpoint provenance contract between Swift and Python; and generate typed, bounded bridge requests rather than accepting loosely validated dictionaries (`scripts/location_bridge.py:221-246`, `scripts/location_bridge.py:307-331`).

## 12. Verification plan

### High-finding regression tests and CI invariants
- VULN-001 unit/integration test: run the build with a controlled temporary parent, assert the selected root is newly created, non-symlink, owned by the effective UID, and mode `0700`; assert build aborts for pre-existing group/other-writable or symlinked roots.
- VULN-001 integration invariant: mutate or replace the source after its verification point and assert final-copy verification fails. Verify `dist/PathChanger.app` and the staged install with `codesign --verify --deep --strict` after their last copy/sanitization step.
- Record source and destination code-directory hashes and assert equality before installation.

### Other tests
- VULN-002: pre-create former fixed names as symlinks in a controlled test namespace; the target must remain unchanged.
- BUG-003: use async fakes that never return from connect, enter, set, clear, and close; each operation must time out, clean partial state, and permit the next ping.
- BUG-004: inject failing test/coverage commands, stale artifacts, missing `TOTAL`, malformed threshold, and empty output; every case must exit non-zero.
- VULN-005: table-test address/port types, ranges, unsupported addresses, UDID/endpoint mismatches, and cache eviction/close behavior.
- BUG-006: send SIGTERM while stdin remains open and idle; require bounded exit and session cleanup.
- BUG-007: inject copy failure and insufficient space; the previous canonical app must remain intact.

### CI and ownership
Require code-owner review for build/install, signing, entitlements, pairing, and bridge protocol changes. Gate on shell static analysis, Python lint/type checks, focused helper tests, final artifact signature verification, and a check that no fixed global temporary names are introduced. Track timeouts, bridge restarts, cleanup failures, final-signature failures, and coverage-script false-green regressions.

## 13. Residual risk & future-proofing
After remediation, PathChanger still delegates device protocol parsing, peer authentication, and transport behavior to `pymobiledevice3` (`scripts/pair_wifi.py:42-47`, `scripts/location_bridge.py:49-73`). A malicious or malformed device remains an untrusted protocol peer even when endpoint provenance is correct.

Preserve these architectural invariants:
1. The exact artifact verified is the exact artifact distributed or installed.
2. Every temporary pathname is private, atomically created, owner-checked, and cleaned without broad deletion.
3. Every device/network operation has a bounded deadline, cancellation path, and observable cleanup result.
4. Every bridge request field is typed, bounded, and tied to the currently selected device/tunnel.
5. Local quality gates fail closed on missing, stale, or unparsable evidence.

Suggested ADRs: “Local build artifact provenance and atomic installation,” “Swift-to-Python bridge trust and endpoint provenance,” and “Device operation timeout/cancellation policy.”

## 14. Missing context / questions that would change severity
1. Does the supported local installation workflow ever run `install.sh` or `build.sh` with `sudo`, an unset `TMPDIR`, or a shared `APP_BUNDLE_BUILD_ROOT`? A firm “never,” enforced in code, would reduce VULN-001 severity.
2. What ownership and permissions does the parent process apply to bridge stdin/stdout, and can any lower-trust local IPC, imported route, or device metadata influence `rsd_address`/`rsd_port`? This determines whether VULN-005 remains Low.
3. What finite timeouts, peer verification, and size limits does the pinned `pymobiledevice3` version enforce internally? Confirmed short deadlines would reduce BUG-003.
4. Are helper stdout/stderr persisted, uploaded, or displayed to other users? If not, INFO-008 remains informational.
5. Is `scripts/coverage.sh` enforced by any merge/release automation beyond contributor instructions? If yes, BUG-004 may warrant High integrity priority.
6. Is multi-device or simultaneous multi-tunnel operation a supported requirement? If no, the bridge cache can be simplified to one replace-on-change session.

## Out-of-scope observations
Minimal workflow/document reads showed that release automation supplies a runner temporary root and separately verifies its bundle, while local documentation recommends the validation/preflight scripts. Those files were not audited for independent findings. Swift privileged-path controls, app entitlements, tunnel launch logic, and dependency manifests were assigned to other agents and were not deep-dived here.
