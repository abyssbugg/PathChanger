# PathChanger Core Security and Code-Integrity Audit

## 1. Executive summary
PathChanger is a local macOS Swift application that discovers paired iOS devices, starts `pymobiledevice3` tunnels, and injects simulated locations.
This scoped audit reviewed all 23 files currently present in `PathChanger/Core` and the two requested path-security test files.
Overall scoped risk posture: **HIGH**.
No CRITICAL issue was substantiated: the root-impact paths require local same-UID write capability and a user-approved administrator prompt.
The primary risk is that administrator launches trust code that the current user can modify: both the selected Python runtime/package path and `pair_wifi.py`.
The exact `pymobiledevice3` version check is a compatibility/supply-chain pin, not a privilege-boundary integrity guarantee.
The privileged log launcher correctly applies `O_NOFOLLOW` to the final component, but does not bind the checked parent directory to the later elevated open.
Lower-severity defects can cause duplicate dependency errors, race-dependent timeout classification, and unbounded file-log growth.
Within 48 hours: stop elevating current-user-owned Python and the mutable pairing script, or disable those administrator flows pending a signed helper.
Within 7 days: move privileged operations to a narrow signed helper and add adversarial replacement/symlink regression tests.
Within 30 days: consolidate subprocess environments, enforce actual log-size rotation, and remove stale security-policy symbols.

## 2. Threat model

### System summary
The reviewed Core layer resolves Python, validates `pymobiledevice3`, centralizes subprocess policy and environment construction, orchestrates device/location actions, records logs, and manages reliability. Location injection is reached from `AppState.setLocation` and delegated to `LocationBridge` (`PathChanger/Core/AppState+Orchestration.swift:L148-L208`). Administrator tunnel and pairing launches consume the Core security policy and execute through AppleScript with administrator privileges (`PathChanger/Device/TunneldManager+LaunchExecution.swift:L32-L39`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L86-L118`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L376-L397`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L456-L474`).

Primary assets are macOS root integrity, the local user's files and Python environment, iOS pairing records, device-tunnel authenticity, simulated-location integrity, and diagnostic-log confidentiality/integrity. The deployment is a single-user local desktop application, not a multi-tenant or internet-facing service. The authenticated actor is the logged-in macOS user; administrator authority is granted interactively for tunnel/pairing operations.

### Entry points and trust boundaries
- User-selected device state and device-derived UDIDs flow into tunnel/location command construction. Privileged UDIDs are format-checked before launch (`PathChanger/Core/PrivilegedPathSecurity.swift:L475-L508`; `PathChanger/Core/ArgumentSanitizer.swift:L44-L47`, `PathChanger/Core/ArgumentSanitizer.swift:L77-L99`).
- Python executable discovery traverses user-managed pyenv, Homebrew, framework, and system paths (`PathChanger/Core/PythonPathResolver.swift:L77-L120`).
- `pymobiledevice3` version output crosses an external-process parsing boundary (`PathChanger/Core/PythonPathResolver.swift:L247-L277`, `PathChanger/Core/PythonPathResolver.swift:L467-L474`).
- Bundle resource paths and filesystem metadata cross into the pairing privilege decision (`PathChanger/Core/PrivilegedPathSecurity.swift:L202-L231`).
- User-owned `~/Library/Logs/PathChanger` paths cross into root file opens (`PathChanger/Device/TunneldManager.swift:L293-L324`; `PathChanger/Core/PrivilegedPathSecurity.swift:L236-L258`).
- Core generates shell text that is subsequently embedded in AppleScript administrator wrappers (`PathChanger/Core/PrivilegedPathSecurity.swift:L290-L332`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L113-L118`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L472-L474`).
- Process environment state crosses from the GUI app into Python children (`PathChanger/Core/PythonPathResolver.swift:L458-L464`; `PathChanger/Core/ProcessEnvironment.swift:L152-L170`).

### Abuse cases
1. Same-UID malware replaces a user-owned Homebrew interpreter or package, waits for tunnel start, and relies on the user approving the administrator dialog; impact is root code execution (`PathChanger/Core/PrivilegedPathSecurity.swift:L130-L136`, `PathChanger/Core/PrivilegedPathSecurity.swift:L154-L170`, `PathChanger/Core/PrivilegedPathSecurity.swift:L550-L570`).
2. Same-UID malware modifies the owner-writable bundled `pair_wifi.py` before pairing; the script is then run by the privileged interpreter (`PathChanger/Core/PrivilegedPathSecurity.swift:L207-L231`, `PathChanger/Core/PrivilegedPathSecurity.swift:L276-L287`).
3. A local process swaps the user-owned log directory after validation but before root `open`, redirecting a fixed-name root write through an intermediate symlink (`PathChanger/Core/PrivilegedPathSecurity.swift:L375-L391`, `PathChanger/Core/PrivilegedPathSecurity.swift:L241-L258`).
4. A hostile Python environment supplies a look-alike module that prints the pinned version during the preflight probe (`PathChanger/Core/PythonPathResolver.swift:L247-L277`, `PathChanger/Core/PythonPathResolver.swift:L458-L474`).
5. A malformed UDID attempts shell argument injection; the current strict UDID validator and privileged-value denylist reject it (`PathChanger/Core/PrivilegedPathSecurity.swift:L475-L508`; `PathChanger/Core/ArgumentSanitizer.swift:L44-L47`, `PathChanger/Core/ArgumentSanitizer.swift:L77-L99`).
6. A symlink is placed directly at a pairing-script or log leaf; current `lstat`/`O_NOFOLLOW` checks reject the final-component case (`PathChanger/Core/PrivilegedPathSecurity.swift:L226-L231`, `PathChanger/Core/PrivilegedPathSecurity.swift:L344-L372`, `PathChanger/Core/PrivilegedPathSecurity.swift:L241-L258`).
7. A dependency probe hangs near its deadline, exposing the unsynchronized timeout flag and causing nondeterministic validation state (`PathChanger/Core/PythonPathResolver.swift:L415-L450`).
8. Repeated opt-in file logging grows a daily log without enforcing the declared 10 MiB cap, consuming local disk over time (`PathChanger/Core/Logger.swift:L153-L160`, `PathChanger/Core/Logger.swift:L190-L200`, `PathChanger/Core/Logger.swift:L265-L283`).
9. A future caller interprets pyenv directories as “approved” based on `ProcessEnvironment.isPathApproved`, despite their current-user writability (`PathChanger/Core/ProcessEnvironment.swift:L48-L73`, `PathChanger/Core/ProcessEnvironment.swift:L206-L222`).

## 3. Methodology notes
Passes A–K were applied with emphasis on A, B, C, D, and F. Pass A mapped every `Process`, path, file-write, environment, and privilege seam in Core. Pass B reviewed the local-user-to-administrator boundary; web sessions, tenant authorization, JWTs, and CSRF are not applicable. Pass C traced shell construction, argv validation, path containment, symlinks, and TOCTOU. Pass D found no embedded private keys, tokens, custom cryptography, or TLS-disable logic in the 23 Core files. Pass E reviewed Core logging, telemetry, session persistence, and redaction. Pass F covered races, timeout handling, resource bounds, and fail-open/closed behavior. Passes G–H were limited to dependency use and runtime configuration visible in Core. Pass I used repository-wide exact-symbol searches to validate dead-code candidates. Pass J evaluated privilege chains. Pass K provides regression invariants below.

Coverage included every file in `PathChanger/Core` (23 files, although the assignment stated 22), `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift`, and `Tests/PathChangerTests/PythonPathResolverTests.swift`. Minimal production call-site ranges in `TunneldManager.swift` and `TunneldManager+LaunchExecution.swift` were opened only to establish reachability of Core policy functions. Device implementation behavior beyond those cited ranges remains outside this report's scope.

The working tree was audited as-is on `feat/ui-redesign`; no stash, reset, branch switch, dependency installation, build, or test execution was performed. Tests were inspected as specifications but not run, per the explicit audit constraints.

Assumptions: a threat actor may execute as the logged-in non-root user or compromise another same-UID process; administrator credentials are not already known to the actor; the user may approve a PathChanger administrator prompt; standard Homebrew/app drag-and-drop installations can be current-user-owned. If deployments guarantee root-owned immutable application and Python trees, VULN-001 and VULN-002 severity decreases, but the current policy explicitly permits current-user ownership.

## 4. Critical & High findings

### [HIGH] Current-user-owned Python code can cross the administrator boundary
- **ID**: VULN-001
- **Category**: Vulnerability
- **CWE / OWASP / ASVS**: CWE-250, CWE-367, CWE-59; OWASP A01:2021 Broken Access Control
- **Location**: `PathChanger/Core/PrivilegedPathSecurity.swift:L130-L170`, `PathChanger/Core/PrivilegedPathSecurity.swift:L186-L200`, `PathChanger/Core/PrivilegedPathSecurity.swift:L525-L570`; `PathChanger/Core/PythonPathResolver.swift:L247-L277`, `PathChanger/Core/PythonPathResolver.swift:L458-L474`; related production sink `PathChanger/Device/TunneldManager+LaunchExecution.swift:L32-L39`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L86-L118`
- **Evidence**:
  - Snippet: the resolver documents that “user-owned Homebrew remains replaceable by same-UID malware,” accepts candidates after `isPrivilegedPythonPathAcceptable`, and returns a preferred current-user path when it passes the version probe (`PathChanger/Core/PrivilegedPathSecurity.swift:L130-L170`).
  - Snippet: terminal symlinks are followed with `stat`, and the target is accepted when owned by root **or the current user** and not group/other-writable (`PathChanger/Core/PrivilegedPathSecurity.swift:L525-L570`).
  - Snippet: the pin checker executes `[pythonPath, "-m", "pymobiledevice3", "version"]` and accepts the first `x.y.z` output equal to the pin; its environment starts from the complete parent process environment (`PathChanger/Core/PythonPathResolver.swift:L247-L277`, `PathChanger/Core/PythonPathResolver.swift:L458-L474`).
  - Data flow: same-UID writable interpreter/package or symlink target → path/mode check → module-controlled version text → privileged command builder → `do shell script ... with administrator privileges` (`PathChanger/Device/TunneldManager+LaunchExecution.swift:L32-L39`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L86-L118`).
  - Control flow / auth decision points: exact version equality is the final module trust gate, but version identity does not establish byte integrity, ownership of all imported package files, or immutability between probe and root execution (`PathChanger/Core/PrivilegedPathSecurity.swift:L154-L170`; `PathChanger/Core/PythonPathResolver.swift:L241-L277`).
- **Description**: The privileged interpreter policy intentionally permits current-user-owned Homebrew executables and follows terminal symlinks. It validates only the current pathname target's owner/mode, then separately executes a module from that runtime to obtain a version string. The same pathname is later executed as root. A current-user-owned file is owner-writable even when mode `0755`, and neither the interpreter nor its imported module tree is bound to the checked inode across the administrator dialog. `PYTHONSAFEPATH=1` changes Python path ordering but does not make user-owned interpreter/package bytes trustworthy (`PathChanger/Core/PrivilegedPathSecurity.swift:L180-L183`, `PathChanger/Core/PrivilegedPathSecurity.swift:L241-L258`).
- **Preconditions**: The attacker can modify files as the logged-in user; an allowlisted Homebrew path or its imported `pymobiledevice3` tree is current-user-owned or replaceable through a user-owned parent/symlink; the user starts a tunnel or pairing flow and approves the administrator prompt.
- **Impact**: Root-level integrity and confidentiality loss on the local Mac. Blast radius is one Mac and the paired-device trust material accessible to root; it is not cross-tenant or remotely unauthenticated.
- **Exploitability analysis**: A same-UID process does not need to inject shell metacharacters. It only needs its code to occupy an accepted runtime/import path before the pin probe and remain or be substituted before privileged execution. The exact version output can still be returned. User interaction and local foothold reduce severity from CRITICAL, but the privilege escalation consequence supports HIGH.
- **Why scanners may miss this**: Each individual operation appears defensive—absolute path, allowlist, owner check, exact version, and `O_NOFOLLOW`. The weakness is the composition of mutable same-UID ownership, Python import semantics, symlink following, and a pathname reused after an interactive delay.
- **Chaining**: VULN-002 provides an independent mutable script input to the same privileged interpreter. VULN-003 provides an additional pathname race in the same launch transaction.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: stop executing general-purpose Python as root. Move only the required tunnel/pair operations into a signed, narrow `SMAppService`/XPC privileged helper with fixed operations and typed arguments.
  - Interim control: require root-owned, non-writable interpreter **and every imported package directory/file**; reject symlinked interpreter paths; resolve and verify all ancestors; run isolated Python (`-I`, with environment variables ignored) from a root-owned dedicated environment.
  - Bind checks to use: open/verify immutable artifacts in the helper immediately before use, verify code-signing or a signed manifest, and avoid a check-then-execute pathname gap.
  - Least privilege: separate tunnel setup from non-privileged device discovery/location operations; do not grant root to the full `pymobiledevice3` module surface.
  - Tests / invariants: reject self-owned allowlisted paths, intermediate and terminal symlinks, owner-writable package trees, replacement between validation and launch, hostile `PYTHONPATH`/`PYTHONHOME`, and a module that reports the pin from untrusted storage.
- **Incorrect fixes to avoid**: A stricter version string alone; checking a hash and later reopening by pathname; only removing group/other write bits; only canonicalizing once before the administrator prompt; shell escaping without changing trust ownership.
- **Residual risk after fix**: A signed helper still carries vendor/dependency supply-chain risk and must expose a minimal protocol. Root-owned environments require a secure update path and rollback.
- **Priority / SLA suggestion**: Wave 0 / 48 hours: disable or gate the affected elevation path; complete signed-helper migration this sprint.
- **Confidence**: CONFIRMED
- **Effort**: L

### [HIGH] Mutable user-owned bundle script is accepted and executed as root
- **ID**: VULN-002
- **Category**: Vulnerability
- **CWE / OWASP / ASVS**: CWE-250, CWE-367, CWE-59; OWASP A01:2021 Broken Access Control
- **Location**: `PathChanger/Core/PrivilegedPathSecurity.swift:L202-L231`, `PathChanger/Core/PrivilegedPathSecurity.swift:L276-L287`, `PathChanger/Core/PrivilegedPathSecurity.swift:L525-L570`; `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L125-L148`; related sink `PathChanger/Device/TunneldManager+LaunchExecution.swift:L376-L407`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L456-L474`
- **Evidence**:
  - Snippet: acceptance requires only an absolute path ending in `pair_wifi.py`, a textual `.app/Contents/Resources/` segment, a non-symlink leaf, and owner root **or current user** with no group/other write bits (`PathChanger/Core/PrivilegedPathSecurity.swift:L207-L231`, `PathChanger/Core/PrivilegedPathSecurity.swift:L550-L570`).
  - Snippet: the builder includes `scriptPath` directly in the argv passed to the privileged Python launcher (`PathChanger/Core/PrivilegedPathSecurity.swift:L276-L287`).
  - Test evidence: a user-owned fake `.app` created under the temporary directory with a mode-`0644` script is explicitly expected to pass (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L125-L137`). Only a symlink at the final script component is rejected (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L140-L148`).
  - Data flow: current-user-writable app resource → textual path and mode validation → privileged command argv → AppleScript administrator execution (`PathChanger/Device/TunneldManager+LaunchExecution.swift:L395-L407`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L456-L474`).
  - Control flow / auth decision points: there is no exact `Bundle.main.resourceURL` containment check in the Core validator, no code-signature validation, no signed-resource hash check, no ancestor check, and no inode binding across the administrator dialog (`PathChanger/Core/PrivilegedPathSecurity.swift:L209-L231`).
- **Description**: Mode `0644` prevents group/other writes but leaves the owner able to replace or edit the script. The validator treats current-user ownership as trusted for a root execution boundary and treats any textual `.app/Contents/Resources/` layout as signature-adjacent. A direct leaf symlink is rejected, but owner edits, atomic rename replacement, and intermediate symlinks remain possible.
- **Preconditions**: The application bundle or an ancestor/resource path is writable by the logged-in user; a same-UID attacker modifies or replaces `pair_wifi.py`; the user starts Wi-Fi pairing and approves the administrator prompt.
- **Impact**: Root code execution on one Mac, with possible access to pairing records and all root-readable local data. The iOS device itself is not automatically compromised, but the pairing workflow's authenticity is lost.
- **Exploitability analysis**: Drag-and-drop applications commonly remain user-owned, and the tests intentionally preserve that behavior. A same-UID process can change owner-writable bytes without defeating the leaf symlink check. The administrator prompt is a meaningful user-interaction precondition, so this is HIGH rather than CRITICAL.
- **Why scanners may miss this**: Static checks see an absolute bundle-looking path, `lstat`, owner validation, and a non-writable-by-group policy. The flaw is that “owned by current user” is incompatible with treating the file as trusted code after privilege elevation.
- **Chaining**: VULN-001 can replace the interpreter even if the script is protected; either issue independently crosses the same administrator boundary.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: eliminate root execution of `pair_wifi.py`; expose a minimal pairing operation in the signed privileged helper.
  - If the script must remain temporarily, require exact canonical containment beneath the running signed bundle, validate the bundle with Security.framework, verify the script against a digest stored in signed application metadata, and re-verify immediately inside the privileged helper.
  - Verify every ancestor without following symlinks and reject owner-writable privileged code. Do not accept arbitrary `.app` string shapes.
  - Least privilege: keep Bonjour discovery and device selection unprivileged; elevate only the minimal pair-record operation.
  - Tests / invariants: reverse the fake-user-owned-app acceptance test; add owner-edit, atomic rename, intermediate-symlink, signature-invalid, and replacement-during-auth tests.
- **Incorrect fixes to avoid**: Merely checking `Bundle.main.resourceURL` before the dialog; relying on `0644`; checking only the final symlink; assuming a `.app` path is signed; copying the script to another user-writable temporary path.
- **Residual risk after fix**: A correctly signed helper still must validate device selection and pairing-record destinations and protect its update channel.
- **Priority / SLA suggestion**: Wave 0 / 48 hours: disable privileged script execution or require a protected installation; signed-helper fix this sprint.
- **Confidence**: CONFIRMED
- **Effort**: M/L

## 5. Medium findings

### [MEDIUM] Parent-directory TOCTOU survives final-component `O_NOFOLLOW` log hardening
- **ID**: VULN-003
- **Category**: Vulnerability
- **CWE / OWASP / ASVS**: CWE-367, CWE-59
- **Location**: `PathChanger/Core/PrivilegedPathSecurity.swift:L236-L258`, `PathChanger/Core/PrivilegedPathSecurity.swift:L375-L391`, `PathChanger/Core/PrivilegedPathSecurity.swift:L409-L470`; `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L237-L249`; related path ownership `PathChanger/Device/TunneldManager.swift:L293-L324`
- **Evidence**:
  - Snippet: parent validation performs `lstat` only on the immediate parent and checks only “not a symlink” and “is a directory”; it does not check owner, mode, ancestors, or retain a directory descriptor (`PathChanger/Core/PrivilegedPathSecurity.swift:L375-L391`).
  - Snippet: the elevated Python process later calls `os.open(log, O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0o600)` by pathname (`PathChanger/Core/PrivilegedPathSecurity.swift:L236-L258`).
  - Snippet: the alternative preparer also performs pathname `lstat`, closes its file descriptor, and then revalidates by pathname rather than using `fstat` on a retained descriptor (`PathChanger/Core/PrivilegedPathSecurity.swift:L409-L470`).
  - Test evidence: the regression test covers a parent that is already a symlink before validation, but not replacement of a previously validated directory or a symlink in an ancestor (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L237-L249`).
  - Data flow: user-owned `~/Library/Logs/PathChanger` directory → pre-auth `lstat` → interactive delay → root pathname open (`PathChanger/Device/TunneldManager.swift:L293-L324`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L13-L29`, `PathChanger/Device/TunneldManager+LaunchExecution.swift:L113-L118`).
- **Description**: `O_NOFOLLOW` protects the final log component only. A same-UID process can rename or replace the user-owned parent after validation and before the root open, causing an intermediate symlink to be followed. The root write has fixed leaf names (`tunnel.log` or `pair-wifi.log`), which limits target selection but does not remove the trust-boundary violation.
- **Preconditions**: Same-UID write access to the log-directory hierarchy, successful race across the administrator interaction, and a useful destination directory containing or accepting the fixed leaf name.
- **Impact**: Root-context file creation or truncation at a redirected directory and corruption of log integrity. The fixed filenames and local/user-interaction requirements limit impact and justify MEDIUM rather than HIGH.
- **Exploitability analysis**: The administrator prompt naturally enlarges the check/use window. The attacker cannot freely select the final basename through this Core API, but can control the intermediate target directory if it can replace the checked parent.
- **Why scanners may miss this**: `lstat` and `O_NOFOLLOW` are present, so signature-based checks may treat the flow as remediated without modeling intermediate components and the interactive delay.
- **Chaining**: A compromised privileged Python path from VULN-001 makes log-path exploitation unnecessary, but both arise from pathname checks not bound to privileged use.
- **Recommended fix** (preferred + alternatives):
  - Open the trusted log directory in the privileged helper with `O_DIRECTORY|O_NOFOLLOW`, verify it with `fstat`, and open a fixed filename using `openat` relative to that retained descriptor.
  - Prefer a root-owned helper-managed log directory, or pass an already-open user-created file descriptor through a structured helper interface where supported.
  - Validate every ancestor and owner/mode as defense in depth, but do not rely on repeated pathname checks as the primary fix.
  - Tests / invariants: race parent replacement, intermediate ancestor symlinks, directory rename, and final leaf replacement; assert the opened descriptor's device/inode, owner, type, and mode.
- **Incorrect fixes to avoid**: More `lstat` calls before opening; canonicalizing once and reopening by string; assuming `0700` prevents its owner from renaming the directory; relying on final-component `O_NOFOLLOW` for the full path.
- **Residual risk after fix**: Log content itself may remain attacker-influenced and must never be interpreted as configuration or executable content.
- **Priority / SLA suggestion**: Fix this sprint alongside the privileged-helper work.
- **Confidence**: CONFIRMED
- **Effort**: M

## 6. Low / Info

### [LOW] Non-executable Python does not stop downstream dependency probing
- **ID**: BUG-001
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-754
- **Location**: `PathChanger/Core/DependencyValidator.swift:L43-L54`, `PathChanger/Core/DependencyValidator.swift:L107-L126`, `PathChanger/Core/DependencyValidator.swift:L163-L168`
- **Evidence**:
  - Snippet: `validateAll` skips `pymobiledevice3` only for `.pythonMissing` or `.pythonVersionTooOld`, omitting `.pythonNotExecutable` (`PathChanger/Core/DependencyValidator.swift:L43-L54`).
  - Data flow: non-executable path → `.pythonNotExecutable` error → condition still passes → second dependency probe → additional Python/pymobiledevice3 error (`PathChanger/Core/DependencyValidator.swift:L115-L120`, `PathChanger/Core/DependencyValidator.swift:L163-L168`).
  - Control flow / auth decision points: this is fail-closed for successful validation, but produces redundant work and misleading diagnostics.
- **Description**: The comment says downstream validation runs only when Python is valid, but the condition does not represent all Python-invalid states.
- **Preconditions**: A discovered Python path exists but lacks executable permission.
- **Impact**: Duplicate or confusing errors and unnecessary subprocess work; no privilege bypass.
- **Exploitability analysis**: A local user can trigger the state through permissions, but gains no additional authority.
- **Why scanners may miss this**: The status still ends as invalid, so outcome-only tests can pass.
- **Chaining**: None.
- **Recommended fix** (preferred + alternatives):
  - Gate downstream validation on absence of **all** Python error types, or have `validatePython` return a Boolean/result and call pmd3 validation only on success.
  - Add a test asserting exactly one error and no pmd3 probe for a non-executable interpreter.
- **Incorrect fixes to avoid**: Treating a non-executable path as merely “missing” while still probing it.
- **Residual risk after fix**: Filesystem permissions can change after validation; production launches still need their own checks.
- **Priority / SLA suggestion**: Next maintenance release.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] Dependency-process timeout classification uses a data-raced flag
- **ID**: BUG-002
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-362
- **Location**: `PathChanger/Core/PythonPathResolver.swift:L401-L450`
- **Evidence**:
  - Snippet: `didTimeout` is declared on one global-queue closure, mutated from a separate `asyncAfter` closure, and read after `waitUntilExit` without synchronization (`PathChanger/Core/PythonPathResolver.swift:L415-L450`).
  - Data flow: process deadline → concurrent flag write/process terminate → unsynchronized flag read → timeout versus normal-error classification.
  - Control flow / auth decision points: all resulting failures are still fail-closed for the pin, but the reported cause and timing are nondeterministic.
- **Description**: The captured mutable Boolean has no actor, lock, atomic, or serial-queue ordering. Near the deadline, process termination and flag visibility can race.
- **Preconditions**: A dependency subprocess exits or is terminated close to the configured deadline.
- **Impact**: Incorrect validation error classification and flaky dependency checks; availability only.
- **Exploitability analysis**: A hostile or hung local module can increase occurrence, but cannot use this race to make a non-pinned version pass exact equality.
- **Why scanners may miss this**: The code uses `waitUntilExit`, which appears sequential, but the timeout closure executes independently.
- **Chaining**: It can obscure diagnosis of VULN-001 preflight behavior but does not create that privilege issue.
- **Recommended fix** (preferred + alternatives):
  - Use a single synchronization domain for process completion and timeout (actor/serial queue/locked one-shot state), cancel the timer after completion, and resume the continuation exactly once from that state.
  - Add deterministic tests for completion just before, at, and just after the timeout.
- **Incorrect fixes to avoid**: Declaring the Boolean `volatile` (not a Swift synchronization primitive) or adding sleeps.
- **Residual risk after fix**: Child-process pipe backpressure still needs bounded output handling.
- **Priority / SLA suggestion**: Next maintenance release.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] Declared file-log size cap is never enforced
- **ID**: BUG-003
- **Category**: Bug
- **CWE / OWASP / ASVS**: CWE-770
- **Location**: `PathChanger/Core/Logger.swift:L153-L160`, `PathChanger/Core/Logger.swift:L190-L200`, `PathChanger/Core/Logger.swift:L265-L283`
- **Evidence**:
  - Snippet: `maxLogSize` is declared as 10 MiB but `write` appends without checking size (`PathChanger/Core/Logger.swift:L153-L160`, `PathChanger/Core/Logger.swift:L190-L200`).
  - Snippet: `rotateLogsIfNeeded` examines creation dates only; the requested `.fileSizeKey` and `maxLogSize` are unused (`PathChanger/Core/Logger.swift:L265-L283`).
  - Data flow: opt-in logging event → sanitized line → unconditional append → growth until external disk pressure or later age cleanup.
  - Control flow / auth decision points: rotation runs when logging is enabled, not on each size threshold crossing (`PathChanger/Core/Logger.swift:L174-L183`, `PathChanger/Core/Logger.swift:L265-L283`).
- **Description**: File logging claims rotation support and declares a maximum size, but no code enforces it. A busy or error-looping app can grow the daily file beyond 10 MiB.
- **Preconditions**: File logging is enabled and sufficient log volume is produced.
- **Impact**: Local disk consumption and eventual application/system availability degradation. The seven-day age policy partially limits duration but is only evaluated on rotation invocation.
- **Exploitability analysis**: Primarily an operational defect; repeated device errors can amplify log volume without an internet-facing attacker.
- **Why scanners may miss this**: The presence of a size constant and `.fileSizeKey` suggests a bound that is not implemented.
- **Chaining**: Reliability retry loops can increase logging volume, but no unbounded retry was identified in the reviewed Core paths.
- **Recommended fix** (preferred + alternatives):
  - Before append, track current file size and rotate atomically at the cap; bound retained file count and total bytes, not only age.
  - Add tests that cross the limit and verify rotation, permissions, and total retention bounds.
- **Incorrect fixes to avoid**: Truncating the active file without synchronization or enforcing only a per-message limit.
- **Residual risk after fix**: Other privileged tunnel logs have separate retention requirements outside this finding.
- **Priority / SLA suggestion**: Within 30 days.
- **Confidence**: CONFIRMED
- **Effort**: S/M

### [INFO] “Approved” subprocess PATH still contains user-writable pyenv directories
- **ID**: DESIGN-001
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-426
- **Location**: `PathChanger/Core/ProcessEnvironment.swift:L48-L73`, `PathChanger/Core/ProcessEnvironment.swift:L152-L170`, `PathChanger/Core/ProcessEnvironment.swift:L206-L222`; compensating privileged rejection `PathChanger/Core/PrivilegedPathSecurity.swift:L186-L200`
- **Evidence**:
  - Snippet: comments state user-writable bin paths are excluded, but `dynamicPathDirectories` returns every pyenv version `bin` plus `~/.pyenv/shims` (`PathChanger/Core/ProcessEnvironment.swift:L48-L73`).
  - Snippet: those paths are added to the configured PATH and treated as approved by `isPathApproved` (`PathChanger/Core/ProcessEnvironment.swift:L152-L170`, `PathChanger/Core/ProcessEnvironment.swift:L206-L222`).
  - Data flow: current user's pyenv tree → “approved” PATH → any child lookup that relies on PATH.
  - Control flow / auth decision points: the current privileged Python validator separately rejects `/.pyenv/`, preventing a direct elevation finding from this inconsistency (`PathChanger/Core/PrivilegedPathSecurity.swift:L186-L200`).
- **Description**: The API's name and comments overstate the trust level of its dynamic PATH. This is not currently proven to cross the administrator boundary, but it creates a dangerous reuse hazard and permits same-user command substitution in non-privileged children that perform PATH lookup.
- **Preconditions**: A child process resolves a helper by PATH and an attacker controls the user's pyenv tree.
- **Impact**: Same-user process-integrity loss and future privilege-boundary regression risk; no current root sink was established from this API in the assigned scope.
- **Exploitability analysis**: The logged-in user already controls these paths, so current impact is defense-in-depth.
- **Why scanners may miss this**: The directory list is dynamically generated and surrounded by security comments.
- **Chaining**: If this environment is ever reused by a privileged helper, severity would rise materially.
- **Recommended fix** (preferred + alternatives):
  - Split APIs into explicitly `trustedSystemEnvironment` and `userToolEnvironment`; never label pyenv paths approved.
  - Start trusted environments from an allowlist rather than the full parent environment, clearing Python influence variables unless explicitly needed.
  - Add an invariant test that privileged/trusted environments contain no home-directory entries.
- **Incorrect fixes to avoid**: Reordering pyenv after system paths while continuing to call it trusted.
- **Residual risk after fix**: Absolute executables can still load user-controlled libraries unless their language runtime is isolated.
- **Priority / SLA suggestion**: Wave 2 hardening.
- **Confidence**: CONFIRMED
- **Effort**: S

## 7. Vulnerability chains

### Chain A: same-UID foothold to root through trusted mutable Python
The attacker condition is write access as the logged-in user. The policy accepts a current-user-owned allowlisted interpreter/symlink target (`PathChanger/Core/PrivilegedPathSecurity.swift:L525-L570`), treats module-emitted version text as the pin proof (`PathChanger/Core/PythonPathResolver.swift:L247-L277`, `PathChanger/Core/PythonPathResolver.swift:L467-L474`), and reuses the pathname in an administrator command (`PathChanger/Core/PrivilegedPathSecurity.swift:L262-L272`; `PathChanger/Device/TunneldManager+LaunchExecution.swift:L86-L118`). The user approval step is the only remaining authority transition. Generic command-injection scanners are unlikely to report this because all command tokens can remain syntactically valid.

### Chain B: mutable application resource to root during Wi-Fi pairing
The user-owned app resource is intentionally accepted (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L125-L137`), then placed in the root interpreter argv (`PathChanger/Core/PrivilegedPathSecurity.swift:L276-L287`) and executed after an administrator dialog (`PathChanger/Device/TunneldManager+LaunchExecution.swift:L456-L474`). No shell metacharacters or malformed device data are required.

VULN-001 and VULN-002 are independent alternatives, not prerequisites for each other. VULN-003 can redirect a fixed-name root log write but does not materially increase either root-code-execution chain.

## 8. Dead code & unused surface report

### Dead / unused inventory

| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-001 | `PythonPathResolver.minimumPmd3Version` | Unused constant | Declared only at `PathChanger/Core/PythonPathResolver.swift:L74-L75`; repository-wide exact-symbol search found no consumer. | Low; comments say validation is exact-pin. | Remove it or use a distinct lower-bound model only if product policy requires one. |
| DEAD-002 | `ArgumentSanitizer.ipv6Pattern` | Duplicate unused validator | Declared at `PathChanger/Core/ArgumentSanitizer.swift:L49-L50`; actual validation uses `inet_pton` at `PathChanger/Core/ArgumentSanitizer.swift:L111-L139`. | Low; `inet_pton` is the stronger implementation. | Remove the stale regex. |
| DEAD-003 | `PrivilegedPathSecurity.prepareSecureLogFile` | Production-unreferenced security helper | Defined at `PathChanger/Core/PrivilegedPathSecurity.swift:L409-L470`; repository-wide references are tests at `Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L351-L380` plus a non-call comment at `PathChanger/Device/TunneldManager.swift:L299-L306`. | Medium: removal may obscure intended migration; keeping it implies a control is wired when it is not. | Either delete after updating comments/tests, or redesign it around retained descriptors and wire it through a helper. Do not present it as current protection. |
| DEAD-004 | `FileLogger.maxLogSize` | Unused security/resource bound | Declared at `PathChanger/Core/Logger.swift:L157-L160`; write and rotation paths do not read it (`PathChanger/Core/Logger.swift:L190-L200`, `PathChanger/Core/Logger.swift:L265-L283`). | Low if replaced by a working rotation limit; high if simply removed without another bound. | Implement BUG-003, then retain the constant as an enforced policy. |

### Complexity / unneeded surface reduction
`PrivilegedPathSecurity` currently combines path allowlisting, file metadata checks, shell quoting, embedded Python launcher source, log creation, and command-value parsing (`PathChanger/Core/PrivilegedPathSecurity.swift:L75-L582`). Moving privilege operations to a typed signed helper would remove the shell-string and embedded-launcher surfaces rather than adding more local validators. `ProcessEnvironment` and `PythonPathResolver.processEnvironment` are separate environment builders with different trust semantics (`PathChanger/Core/ProcessEnvironment.swift:L152-L203`; `PathChanger/Core/PythonPathResolver.swift:L458-L464`); they should be consolidated into clearly named trust profiles.

## 9. Bugs / mistakes / error-handling defects
BUG-001, BUG-002, and BUG-003 are fully specified in section 6. Additional reviewed correctness controls were generally fail-closed at the privileged boundary: missing/mismatched `pymobiledevice3` versions return failure (`PathChanger/Core/PythonPathResolver.swift:L218-L243`), privileged command values reject invalid UDIDs and quotes/backslashes (`PathChanger/Core/PrivilegedPathSecurity.swift:L475-L508`), and unsupported future iOS versions intentionally warn rather than hard-block (`PathChanger/Core/IOSVersionHelper.swift:L55-L82`).

## 10. Dependency & supply-chain notes
Core now requires exact `pymobiledevice3` version `9.12.0` (`PathChanger/Core/PythonPathResolver.swift:L64-L75`) and maps mismatches to user-facing remediation (`PathChanger/Core/DependencyValidator.swift:L145-L168`; `PathChanger/Core/LocalizationHelper.swift:L264-L275`). This improves reproducibility but does not attest runtime bytes; VULN-001 remains because the privileged trust decision consumes executable module output rather than a protected installation identity. No claim is made about external dependency CVEs because manifests/vendor advisories were outside this scoped Core review and no network/dependency audit was run.

## 11. Remediation roadmap

### Wave 0: emergency
Disable or strongly gate administrator execution of current-user-owned Python and `pair_wifi.py`. Require a protected installation as a temporary operational control. Add explicit security logging when no immutable privileged runtime is available, without logging full home paths or device identifiers (`PathChanger/Core/Logger.swift:L52-L68`, `PathChanger/Core/Logger.swift:L108-L148`).

### Wave 1: high-risk design fixes
Implement a signed `SMAppService`/XPC helper with a minimal typed protocol for tunnel setup and pairing. Remove general shell/module execution from the privileged boundary. Use root-owned resources, code-signature verification, isolated runtime semantics, and descriptor-relative log opens.

### Wave 2: hardening and dead-code removal
Fix the timeout synchronization, dependency gating, and file-log rotation. Split trusted system PATH from user tool PATH. Remove unused regex/version constants and reconcile the unwired secure-log helper/comments.

### Wave 3: long-term architecture
Document an ADR: “No current-user-writable executable, script, module, configuration, or path ancestor may influence administrator execution.” Assign code ownership for `PrivilegedPathSecurity`, subprocess policy, helper protocol, entitlements, and pairing-record operations. Threat-model updates should be required for every new privileged command or filesystem destination.

## 12. Verification plan
- VULN-001 unit/integration invariants: self-owned allowlisted Python fails; symlinked Python fails; any user-writable ancestor or package file fails; hostile Python environment variables are ignored; replacing the path during a delayed authorization test cannot change executed bytes.
- VULN-002 invariants: fake temporary `.app` paths fail; owner-writable resources fail; intermediate symlinks fail; invalid signatures/hashes fail; mutation during authorization fails; pairing discovery remains non-privileged.
- VULN-003 invariants: swap the log parent after validation, replace an ancestor with a symlink, and rename the checked directory; verify `openat` remains anchored to the expected device/inode and fixed filename.
- BUG-001 invariant: a non-executable Python produces one Python error and zero pmd3 probes.
- BUG-002 invariant: exactly one completion outcome for just-before/at/just-after timeout boundaries under Thread Sanitizer.
- BUG-003 invariant: cross 10 MiB, rotate atomically, preserve `0600`, cap file count and total bytes, and continue logging without data races.
- CI gates: Swift strict-concurrency diagnostics, Thread Sanitizer for process lifecycle tests, privileged-helper code-signature verification, and tests that enumerate all privileged inputs and assert root-owned/immutable provenance.
- Runtime detection: audit privileged operation type, helper version/signing identity, validated executable identity, and result; never log full UDIDs, coordinates, administrator output, or unredacted home paths (`PathChanger/Core/Logger.swift:L52-L68`, `PathChanger/Core/Logger.swift:L108-L148`).

No tests or builds were executed during this audit because the assignment explicitly prohibited them. The existing tests establish intended behavior but currently encode acceptance of user-owned pairing code (`Tests/PathChangerTests/PrivilegedPathSecurityTests.swift:L125-L137`) and do not exercise replacement races.

## 13. Residual risk & future-proofing
After a signed-helper migration, residual risk remains in helper protocol design, code-signing/update trust, `pymobiledevice3` supply chain, iOS pairing-record handling, and root log retention. Preserve these invariants: privileged operations accept typed values rather than shell strings; privileged code and all dependencies are immutable to the invoking user; validation is bound to the object used; log destinations are descriptor-relative and fixed; non-privileged device discovery never expands the helper's authority.

The app remains exposed to same-user tampering of non-privileged location behavior by design because it runs in the user's session. That is distinct from allowing those bytes to cross into root. If the app is later distributed system-wide, sandboxed, or made remotely controllable, this threat model and severity must be revisited.

Suggested ADRs: privileged-helper boundary and allowed operations; Python/runtime provenance; descriptor-based filesystem policy; subprocess environment trust profiles; security-log retention/redaction.

## 14. Missing context / questions that would change severity
- Deployment ownership/permissions for `/Applications/PathChanger.app`, Homebrew prefixes, and Python site-packages were not provided. Evidence that all privileged code and ancestors are root-owned and immutable would reduce VULN-001/VULN-002 exploitability; the current code nevertheless permits weaker states.
- The final helper/entitlement architecture and code-signing/notarization settings were outside this Core scope. A pre-existing signed helper that does not use these paths could make the cited production sinks unreachable, although the opened `TunneldManager+LaunchExecution.swift` ranges currently call them.
- AppleScript authorization caching and exact environment behavior can affect race duration and Python import paths, but neither is required for the owner-writable-code findings.
- Runtime test results, Thread Sanitizer output, and filesystem race harness results were unavailable because builds/tests were prohibited.
- Dependency manifests, wheel provenance, and upstream vulnerability advisories were not audited; no CVE conclusions are made.

## Out-of-scope observations
The production launch call sites still contain a development fallback that resolves `scripts/pair_wifi.py` from the current working directory, but Core rejects it for privileged use because it lacks the required `.app/Contents/Resources/` layout (`PathChanger/Device/TunneldManager+LaunchExecution.swift:L299-L318`; `PathChanger/Core/PrivilegedPathSecurity.swift:L219-L231`). No deeper Device-layer audit was performed.
