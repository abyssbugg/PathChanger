# PathChanger CI/CD, Supply-Chain, and Companion Integrity Audit

## 1. Executive summary
PathChanger is a local macOS Swift application that controls paired iOS devices through Python tooling and optionally exchanges status/control messages with an iOS companion.
Overall risk posture for the assigned scope is **Medium**.
No Critical or High finding was confirmed.
The most consequential issue is that the companion encrypts MultipeerConnectivity traffic but automatically trusts any peer using the service type, so a nearby peer can inject status messages into the companion UI.
Release artifacts are ad-hoc signed and accompanied only by a checksum generated and uploaded through the same GitHub workflow, so consumers lack an independent publisher-authenticity signal.
Python dependency guidance is internally contradictory: the approved file forbids unconstrained upgrades, but deployment troubleshooting instructs them; the approved hash is informational and the transitive tree is not locked.
The CI security job has least-privilege token permissions, but its secret and entitlement checks leave important file types and policy assertions uncovered.
No committed secret was found in the assigned files by the scoped pattern scan.
The Swift package manifests use only local path dependencies; no remote SwiftPM dependency or third-party GitHub Action was present in the assigned scope.
Within 48 hours: remove the unconstrained `pip3 install -U` instruction, commit and enforce a fully hashed Python lock, and make the CI entitlement check fail on policy drift.
Within 7 days: define a Developer ID/notarization or equivalent independently verifiable release-authenticity process.
Within 30 days: add authenticated companion pairing, pin executable CI tooling, and decide whether App Sandbox or a split privileged-helper architecture is feasible.

## 2. Threat model

### System summary
PathChanger builds a macOS executable and a shared companion protocol from local Swift packages (`Package.swift:L6-L35`, `SharedCompanionProtocol/Package.swift:L5-L22`). The iOS companion discovers and advertises a MultipeerConnectivity service, receives location/spoofing status, and can send an emergency-stop message (`PathChangerCompanion/CompanionConnectionService.swift:L50-L64`, `SharedCompanionProtocol/Sources/CompanionProtocolModels.swift:L3-L24`). Production artifacts are built on GitHub-hosted macOS runners and published as a zip plus SHA-256 file (`.github/workflows/release.yml:L18-L24`, `.github/workflows/release.yml:L117-L145`).

Primary assets are release-artifact authenticity, the integrity of the local Python/device-control toolchain, companion status/control integrity, device/location metadata, and the local user's files and privileges. Actors are the local user, a nearby MultipeerConnectivity peer, a repository/release maintainer, the GitHub Actions bot, and dependency/tool maintainers. The deployment is a local desktop application, not a multi-tenant internet service; local-network/Bluetooth discovery and GitHub/PyPI supply-chain boundaries remain relevant.

### Entry points
- GitHub `pull_request`, `push`, manual validation, and `release.published` events (`.github/workflows/ci.yml:L3-L8`, `.github/workflows/release-validation.yml:L3-L9`, `.github/workflows/release.yml:L3-L5`).
- Python package installation directed by `requirements-pathchanger.txt:L1-L17` and `DEPLOYMENT/TUNNEL_MODES.md:L178-L186`.
- Multipeer invitations, discovered peers, and arbitrary Codable companion messages (`PathChangerCompanion/CompanionConnectionService.swift:L83-L106`, `PathChangerCompanion/CompanionConnectionService.swift:L174-L179`, `PathChangerCompanion/CompanionConnectionService.swift:L237-L247`).
- Signed bundle entitlements for network, USB, Bluetooth, file, and location access (`Resources/PathChanger.entitlements:L34-L88`).
- GitHub release asset upload with repository-content write permission (`.github/workflows/release.yml:L18-L24`, `.github/workflows/release.yml:L131-L145`).

### Trust boundaries
- Nearby iOS/macOS peer → encrypted Multipeer session → companion message decoder/UI state (`PathChangerCompanion/CompanionConnectionService.swift:L50-L64`, `PathChangerCompanion/CompanionConnectionService.swift:L114-L143`, `PathChangerCompanion/CompanionConnectionService.swift:L174-L179`).
- PyPI and transitive maintainers → pip resolver → Python environment later used by the documented privileged daemon mode (`requirements-pathchanger.txt:L1-L17`, `DEPLOYMENT/TUNNEL_MODES.md:L99-L120`).
- Repository/tag and GitHub runner → ad-hoc app bundle → GitHub release assets → local user (`.github/workflows/release.yml:L79-L110`, `.github/workflows/release.yml:L117-L159`).
- Application process → network/USB/Bluetooth/files/location capabilities described by the entitlement file (`Resources/PathChanger.entitlements:L34-L88`).

### Abuse cases
1. A nearby peer advertises/invites using `pathchanger-cmp`, is auto-accepted, and sends a forged status or location update; detection is low because the UI displays only a peer-selected display name (`PathChangerCompanion/CompanionConnectionService.swift:L38-L46`, `PathChangerCompanion/CompanionConnectionService.swift:L114-L143`, `PathChangerCompanion/CompanionConnectionService.swift:L237-L247`).
2. A user follows the troubleshooting command and upgrades to an unreviewed package version that is later executed in daemon mode; detection depends on runtime failure or manual version inspection (`DEPLOYMENT/TUNNEL_MODES.md:L99-L120`, `DEPLOYMENT/TUNNEL_MODES.md:L178-L186`).
3. A transitive Python dependency changes while the top-level version stays fixed; the current file neither locks the tree nor enforces hashes (`requirements-pathchanger.txt:L12-L17`).
4. A release-channel or workflow compromise replaces both the zip and its co-hosted checksum; consumers have no independent Developer ID/notarization signal in the reviewed process (`.github/workflows/release.yml:L117-L159`, `DEPLOYMENT/README.md:L22-L27`).
5. A credential is committed in Python, shell, YAML, Markdown, or text and the CI secret regex does not examine it (`.github/workflows/ci.yml:L139-L146`).
6. A dangerous entitlement is added and CI still passes because it only prints the file (`.github/workflows/ci.yml:L148-L153`).
7. A compromised/mistaken Homebrew resolution supplies a different SwiftLint binary; the lint job executes it with repository read access (`.github/workflows/ci.yml:L97-L119`).
8. A maintainer updates the build-excluded plist rather than the release plist, producing version/privacy metadata drift (`Package.swift:L20-L29`, `PathChanger/Info.plist:L19-L38`, `Resources/Info.plist:L15-L24`).

## 3. Methodology notes
The review operated in diagnostic/read-only mode except for this report. Passes A-K were applied to the assigned scope, with emphasis on Pass G (dependency sources, pins, hashes, lockfiles, and tool installation) and Pass H (workflow triggers/permissions/expressions, artifact signing, entitlements, and plist configuration).

Files opened in full: all three `.github/workflows/*.yml` files; the three assigned `Package.swift` files; both `PathChangerCompanion/*.swift` files; `SharedCompanionProtocol/Sources/CompanionProtocolModels.swift`; both assigned Info.plists; `Resources/PathChanger.entitlements`; `requirements-pathchanger.txt`; `.swiftlint.yml`; `.gitignore`; and both `DEPLOYMENT/*.md` documents.

Read-only searches checked workflow triggers, `${{ }}` use at shell boundaries, permission scopes, third-party Actions, secret-shaped values, package/lock artifacts, and exact evidence lines. `git status --short -- requirements-pathchanger.txt` reported `?? requirements-pathchanger.txt`; no `Package.resolved` was found. The scoped secret-pattern search returned no matches. PyPI metadata for `pymobiledevice3` 9.12.0 was consulted to confirm that it has a large, range-based transitive dependency set; no dependency was labeled abandoned solely from age.

Coverage gaps: the workflow-invoked build and validation scripts were outside this agent's assigned scope and were not opened. Consequently, this report does not assert whether `Resources/PathChanger.entitlements` is actually embedded in the final signature, whether hardened runtime is enabled, or whether release validation has controls not visible in the three workflows. The macOS companion host implementation was also outside scope, so peer-authentication impact is limited to behavior proven in the iOS companion. Builds, package installs, and live network tests were prohibited and not run.

Assumptions: GitHub-hosted runners are ephemeral; release permissions are limited to authorized maintainers; users may follow repository deployment documentation; daemon mode can request administrator privileges as documented at `DEPLOYMENT/TUNNEL_MODES.md:L99-L120`; and there is no separate enterprise artifact-signing channel not represented in the assigned files.

## 4. Critical & High findings
No Critical or High finding was confirmed in the assigned scope.

## 5. Medium findings

### [MEDIUM] AUTO-ACCEPTED, UNAUTHENTICATED PEERS CAN INJECT COMPANION STATUS
- **ID**: VULN-001
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-306 Missing Authentication for Critical Function; OWASP A07:2021 Identification and Authentication Failures; ASVS N/A (native peer protocol)
- **Location**: `PathChangerCompanion/CompanionConnectionService.swift:L50-L64`, `PathChangerCompanion/CompanionConnectionService.swift:L83-L106`, `PathChangerCompanion/CompanionConnectionService.swift:L114-L143`, `PathChangerCompanion/CompanionConnectionService.swift:L174-L179`, `PathChangerCompanion/CompanionConnectionService.swift:L237-L247`, `SharedCompanionProtocol/Sources/CompanionProtocolModels.swift:L3-L24`
- **Evidence**:
  - Snippet (minimal): `MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)` and `invitationHandler(true, session)`.
  - Data flow: nearby peer invitation/data → unconditional invitation acceptance → `JSONDecoder().decode(CompanionMessage.self, from: data)` → `handleReceivedMessage` → status, location, connection, or emergency-stop display state.
  - Control flow / auth decision points: outbound invitations carry `withContext: nil`; inbound invitations are always accepted; the `peer` argument to `handleReceivedMessage` is not used for an allowlist or identity check; sends target every `session.connectedPeers` member.
- **Description**: Transport encryption is required, which protects message confidentiality/integrity in transit, but the application does not authenticate the peer as the user's PathChanger Mac. Any peer that can participate in discovery with the service type can be accepted and can submit protocol-valid messages that alter the companion's displayed safety/status state.
- **Preconditions**: The companion is browsing/advertising; the attacker is within applicable local-network/Bluetooth discovery range and can implement the known service type and Codable message format.
- **Impact**: Integrity and limited availability impact to one companion session. A forged peer can display false device, location, route, active/inactive, or connection state, potentially causing the local user to rely on an incorrect emergency/status indicator. No host-side privileged action from attacker-supplied messages was proven in the assigned scope.
- **Exploitability analysis**: Discovery is intentionally enabled on app appearance and incoming invitations require no user confirmation, shared secret, certificate, or prior pairing. The attacker still needs local proximity/network reach and protocol compatibility; the issue is not internet-wide.
- **Why scanners may miss this**: Generic analysis sees `.required` encryption and may treat the channel as secure without modeling the separate application-identity decision or the safety semantics of the status UI.
- **Chaining**: If the out-of-scope macOS host also auto-accepts and authorizes messages solely by service membership, the same missing identity layer could affect host-side emergency-stop control; that extension is unverified.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: add an explicit pairing handshake that binds the companion to one expected Mac key, persist the peer public-key fingerprint in Keychain, reject unknown invitations, and authorize each decoded message against the bound session peer. Use invitation context only as a transport for a challenge, not as the sole trust proof.
  - Config / platform control: expose a user-confirmed short authentication string or QR-assisted pairing and require re-pairing on key changes.
  - Least privilege: maintain one authenticated control peer and send emergency-stop messages only to that peer, not all connected peers.
  - Tests / invariants: unknown invitation is rejected; known-key invitation succeeds; a second peer cannot alter status; replayed handshake/message counters fail; disconnect/reconnect preserves the correct identity binding.
- **Incorrect fixes to avoid**: Trusting `MCPeerID.displayName`, hiding unknown peers only in the UI, relying on the service type as a secret, or treating encryption without identity binding as authentication.
- **Residual risk after fix**: A compromised already-paired Mac can still send false state; key-reset and device-transfer flows must be explicit and auditable.
- **Priority / SLA suggestion**: Medium — design and test this sprint; ship before presenting companion status as an authoritative safety control.
- **Confidence**: CONFIRMED
- **Effort**: M

### [MEDIUM] RELEASE ARTIFACTS LACK AN INDEPENDENT PUBLISHER-AUTHENTICITY SIGNAL
- **ID**: VULN-002
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-345 Insufficient Verification of Data Authenticity; OWASP A08:2021 Software and Data Integrity Failures; ASVS N/A (desktop distribution)
- **Location**: `.github/workflows/release.yml:L18-L24`, `.github/workflows/release.yml:L79-L110`, `.github/workflows/release.yml:L117-L159`, `.github/workflows/release-validation.yml:L93-L109`, `DEPLOYMENT/README.md:L2-L7`, `DEPLOYMENT/README.md:L22-L27`, `DEPLOYMENT/README.md:L39-L44`
- **Evidence**:
  - Snippet (minimal): release summary states `Build style: ad-hoc signed app bundle`; the upload uses `gh release upload ... --clobber`.
  - Data flow: Git tag/repository → mutable hosted runner → ad-hoc-signed bundle → zip and checksum generated in the same job → both uploaded to the same GitHub release.
  - Control flow / auth decision points: the release job correctly scopes `contents: write` to the publishing job, but `codesign --verify` verifies signature structure; the reviewed workflow contains no Developer ID identity check, notarization submission/stapling, or independently signed provenance.
- **Description**: Ad-hoc signing does not identify the publisher to macOS. The SHA-256 file detects accidental corruption only when obtained from a trustworthy independent source; because the zip and checksum are generated and replaceable through the same workflow/channel, a release-channel compromise can replace both consistently.
- **Preconditions**: An attacker compromises an authorized release maintainer, the publishing workflow/token/runner, or convinces a user to install a lookalike artifact; the user must download and execute the application and may need to override Gatekeeper warnings.
- **Impact**: Confidentiality and integrity impact on each user who installs a substituted build. The application later controls iOS devices and can enter a documented administrator-assisted daemon mode (`DEPLOYMENT/TUNNEL_MODES.md:L99-L120`), increasing the value of release substitution, although no automatic privilege gain is asserted.
- **Exploitability analysis**: This is not a direct unauthenticated code-execution path. GitHub access control, TLS, branch/release permissions, and user interaction are material compensating controls. The gap matters after release-channel or social-distribution compromise because consumers cannot verify a stable Apple publisher identity or independent attestation.
- **Why scanners may miss this**: CI scanners often accept any successful `codesign --verify` and any checksum as integrity controls without distinguishing ad-hoc signature validity from publisher authentication or checking channel independence.
- **Chaining**: The `contents: write` release job and `--clobber` capability make same-channel artifact/checksum replacement possible after workflow compromise; VULN-003 increases the build's dependency-resolution variability.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: sign release bundles with a protected Developer ID Application certificate, enable hardened runtime as compatibility permits, notarize with Apple, staple the ticket, and verify `codesign --verify --deep --strict`, designated requirement/team identity, `spctl --assess`, and stapling before upload.
  - Config / platform control: protect the release environment with required reviewers; keep signing credentials in narrowly scoped release secrets or a dedicated signing service; generate signed provenance/SBOM and publish its verification identity separately.
  - Least privilege: retain job-level `contents: write`; do not grant write permissions to validation/PR jobs.
  - Tests / invariants: release fails unless the expected Team ID/designated requirement and notarization ticket are present; uploaded asset digests must match signed provenance.
  - Alternative when Developer ID is temporarily unavailable: sign provenance with a separately controlled key/identity and publish verification instructions, while clearly retaining the Gatekeeper limitation.
- **Incorrect fixes to avoid**: Replacing one ad-hoc signature with another, publishing only a checksum beside the artifact, or treating `codesign --verify` alone as proof of publisher identity.
- **Residual risk after fix**: Compromise of the signing identity or authorized release process remains possible; certificate revocation, secret rotation, and incident response are still required.
- **Priority / SLA suggestion**: Medium — establish the release-authenticity design this sprint and gate the next public release on the selected control.
- **Confidence**: CONFIRMED
- **Effort**: M

### [MEDIUM] PYTHON INSTALLATION GUIDANCE BYPASSES THE APPROVED PIN AND DOES NOT ENFORCE THE DEPENDENCY TREE
- **ID**: VULN-003
- **Category**: Vulnerability | Design flaw
- **CWE / OWASP / ASVS**: CWE-353 Missing Support for Integrity Check; CWE-829 Inclusion of Functionality from Untrusted Control Sphere; OWASP A08:2021 Software and Data Integrity Failures; ASVS N/A
- **Location**: `requirements-pathchanger.txt:L1-L17`, `DEPLOYMENT/TUNNEL_MODES.md:L99-L120`, `DEPLOYMENT/TUNNEL_MODES.md:L178-L186`, `.github/workflows/ci.yml:L46-L47`, `.github/workflows/release-validation.yml:L87-L91`, `.github/workflows/release.yml:L79-L83`
- **Evidence**:
  - Snippet (minimal): the approved file says `do NOT use unconstrained pip install -U`, while deployment troubleshooting says `pip3 install -U pymobiledevice3`.
  - Data flow: documentation command → pip resolves the latest top-level and transitive packages from PyPI → resulting Python environment → documented administrator-assisted tunneld execution.
  - Control flow / auth decision points: `pymobiledevice3==9.12.0` pins only the direct package; its wheel hash is explicitly “informational” and not supplied as an enforceable `--hash`; the file explicitly leaves the transitive tree unpinned. The assigned workflows resolve only Swift packages and contain no Python lock/hash verification step.
  - Repository-state evidence: read-only `git status --short -- requirements-pathchanger.txt` returned `?? requirements-pathchanger.txt`, so the intended control is not currently versioned in the audited branch/worktree state.
- **Description**: The repository contains a direct version pin, but neither the direct artifact nor the transitive closure is cryptographically enforced, and operational guidance tells users to bypass the pin entirely. The current control therefore does not provide reproducible or tamper-evident installation.
- **Preconditions**: A user follows the troubleshooting command or installs from the one-line requirements file; a malicious/compromised package release, dependency, index path, or accidental incompatible release is resolved before a reviewed lock update.
- **Impact**: Integrity and availability impact is limited to Macs using the affected Python environment and connected devices. Because daemon mode can require administrator privileges, dependency code may later run in a privileged operational path; package installation itself is not asserted to run as root.
- **Exploitability analysis**: Exploitation requires a supply-chain compromise, malicious release, index misconfiguration, or unsafe operator upgrade. PyPI TLS and the explicit direct version pin are partial controls, but they do not authenticate the selected artifacts against repository-approved hashes or constrain transitive versions.
- **Why scanners may miss this**: A manifest scanner sees `==9.12.0` and reports the top-level package pinned; it may not model contradictory deployment documentation, untracked file state, pip's transitive resolution, or whether the recorded hash is actually passed to pip.
- **Chaining**: VULN-002 can distribute a build/process whose dependency inputs are not independently attestable; the unconstrained troubleshooting path bypasses even the partial direct pin.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: generate and commit a platform/Python-version-specific lock containing every transitive dependency and all accepted wheel/sdist hashes; install with `python3 -m pip install --require-hashes -r <lockfile>`. Keep the reviewed top-level constraint in a separate input file if desired.
  - Config / platform control: add CI that regenerates/checks lock drift, performs a hash-enforced dry resolution, runs an advisory audit, and fails if deployment docs contain unconstrained production upgrade commands.
  - Least privilege: install into an application-owned virtual environment as the local user; elevate only the minimal tunneling operation, never the package installer.
  - Tests / invariants: clean-environment install resolves exactly the lock; an altered wheel or unlisted transitive version fails; the runtime version matches the approved version; daemon smoke tests pass before lock promotion.
  - Documentation: replace `pip3 install -U pymobiledevice3` with the repository lock command and a maintainer-controlled upgrade procedure.
- **Incorrect fixes to avoid**: Keeping a hash in a comment, pinning only the direct package, using `--no-deps` without explicitly supplying the required locked dependencies, or recommending `sudo pip`.
- **Residual risk after fix**: A malicious dependency version intentionally approved into the lock remains possible; review, provenance, advisory monitoring, and periodic controlled upgrades remain necessary.
- **Priority / SLA suggestion**: Medium — remove the unsafe command within 48 hours and land a committed, hash-enforced lock this sprint.
- **Confidence**: CONFIRMED
- **Effort**: M

## 6. Low / Info

### [LOW] CI SECURITY CHECKS DO NOT ENFORCE THE CLAIMED SECRET AND ENTITLEMENT POLICIES
- **ID**: VULN-004
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-693 Protection Mechanism Failure; OWASP A05:2021 Security Misconfiguration; ASVS N/A
- **Location**: `.github/workflows/ci.yml:L121-L153`
- **Evidence**:
  - Snippet (minimal): secret scanning includes only `*.swift`, `*.json`, and `*.plist`; entitlement validation is `cat Resources/PathChanger.entitlements`.
  - Data flow: repository content → narrow grep or file print → successful security-scan job despite unexamined Python/shell/YAML/text/Markdown files or policy-invalid entitlement values.
  - Control flow / auth decision points: the entitlement step succeeds when the file is absent and makes no allowlist/denylist assertion; tests are excluded from secret scanning.
- **Description**: The job name implies a security gate, but its checks do not cover several security-relevant file types present in the project and do not validate entitlement policy. The scoped audit found no secret in the assigned files, so this is a preventive-control gap rather than confirmed exposure.
- **Preconditions**: A secret or dangerous entitlement change is introduced in a form the regex/policy does not recognize.
- **Impact**: Potential repository secret disclosure or unreviewed capability expansion; actual impact depends on the omitted value and repository visibility.
- **Exploitability analysis**: Bypass is straightforward for unsupported file types or provider-specific token formats, but an attacker generally needs contribution/merge capability and review failure.
- **Why scanners may miss this**: The presence of a job called “Security Scan” can satisfy superficial CI-control inventories.
- **Chaining**: A leaked release/signing credential would amplify VULN-002; an unexpected entitlement would amplify process-compromise impact.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: use a maintained secret scanner across all tracked files/diffs and optionally history, with provider-aware patterns and a reviewed allowlist.
  - Config / platform control: parse the entitlement plist and fail on missing file, unexpected true keys, or dangerous code-signing entitlements; compare against a committed allowlist.
  - Least privilege: keep the existing `contents: read` CI permission (`.github/workflows/ci.yml:L14-L15`).
  - Tests / invariants: synthetic secret fixtures in every relevant extension are detected; deleting or adding an entitlement fails.
- **Incorrect fixes to avoid**: Adding more ad-hoc grep alternations indefinitely or printing sensitive matches/entitlements without an assertion.
- **Residual risk after fix**: Secret scanners have false negatives; code review, credential scoping, and rotation procedures remain necessary.
- **Priority / SLA suggestion**: Low — harden in the next CI-maintenance cycle.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] SWIFTLINT IS DOWNLOADED AND EXECUTED WITHOUT A VERSION OR ARTIFACT PIN
- **ID**: VULN-005
- **Category**: Unused dependency | Design flaw
- **CWE / OWASP / ASVS**: CWE-829 Inclusion of Functionality from Untrusted Control Sphere; OWASP A08:2021 Software and Data Integrity Failures; ASVS N/A
- **Location**: `.github/workflows/ci.yml:L97-L119`
- **Evidence**:
  - Snippet (minimal): `brew install swiftlint` followed by `swiftlint lint --quiet`.
  - Data flow: current Homebrew formula/bottle resolution → executable on the CI runner → repository lint job.
  - Control flow / auth decision points: no formula version, release checksum, lock, or expected binary version is checked.
- **Description**: The lint job executes whatever SwiftLint version the mutable Homebrew repository resolves at run time. This weakens reproducibility and adds a tool-distribution compromise point.
- **Preconditions**: Homebrew/formula/bottle compromise or an incompatible future SwiftLint release; the lint job must run.
- **Impact**: Primarily CI integrity/availability. The job has repository read permission and no project secrets in the reviewed workflow, materially limiting blast radius.
- **Exploitability analysis**: A remote attacker would need to compromise the trusted tool distribution or runner path. Routine version drift is the more likely failure mode.
- **Why scanners may miss this**: GitHub Action pinning checks do not inspect package-manager commands inside `run` steps.
- **Chaining**: A broader runner/tool compromise could affect logs or source visibility, but the lint job cannot publish releases under the reviewed permissions.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: install a reviewed SwiftLint release at an exact version and verify its published checksum, or integrate a SwiftPM plugin/dependency pinned by package resolution.
  - Config / platform control: assert `swiftlint version` before use and update through reviewed dependency-renovation changes.
  - Least privilege: preserve read-only permissions and job isolation.
  - Tests / invariants: CI fails if the actual version/hash differs from the approved value.
- **Incorrect fixes to avoid**: Pinning only the Homebrew tap branch or logging a version without enforcing it.
- **Residual risk after fix**: The selected publisher and artifact host remain supply-chain dependencies.
- **Priority / SLA suggestion**: Low — address with the next CI toolchain update.
- **Confidence**: CONFIRMED
- **Effort**: S

### [LOW] THE ENTITLEMENT SET DOES NOT ESTABLISH AN APP-SANDBOX LEAST-PRIVILEGE BOUNDARY
- **ID**: VULN-006
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-250 Execution with Unnecessary Privileges; OWASP A05:2021 Security Misconfiguration; ASVS N/A
- **Location**: `Resources/PathChanger.entitlements:L4-L89`
- **Evidence**:
  - Snippet (minimal): the dictionary enables network client/server, USB, Bluetooth, user-selected read/write, Downloads read/write, and location keys, but contains no `com.apple.security.app-sandbox` key.
  - Data flow: signed application process → macOS discretionary access under the local user → network/files/devices; the listed sandbox capability keys do not by themselves create a sandbox boundary.
  - Control flow / auth decision points: user-selected file access and ambient Downloads read/write are both declared (`Resources/PathChanger.entitlements:L68-L78`); high-risk JIT, unsigned-executable-memory, library-validation, and DYLD exceptions are explicitly disabled/absent (`Resources/PathChanger.entitlements:L14-L31`).
- **Description**: The file is thoughtfully restrictive about dangerous code-signing exceptions, but it does not opt the app into App Sandbox. Consequently, the capability list should not be treated as an effective least-privilege boundary. The broad Downloads read/write declaration also deserves removal if user-mediated file selection is sufficient.
- **Preconditions**: The final bundle uses this entitlement file; an attacker first gains code execution in the app process or abuses an app file/network path. Neither premise was demonstrated in the assigned scope.
- **Impact**: Defense-in-depth impact: process compromise can reach resources available to the local user rather than being limited by an application sandbox. Blast radius is one local account/Mac.
- **Exploitability analysis**: This finding does not identify an initial code-execution primitive. External Python/USB/privileged tunneling may make full sandbox adoption non-trivial, which is why severity is Low.
- **Why scanners may miss this**: Entitlement scanners often flag dangerous true keys but do not distinguish a capability allowlist from the absence of the sandbox enforcement key.
- **Chaining**: VULN-001 provides a local peer input surface but does not itself prove process compromise. VULN-003 concerns Python code that runs in a separate process and therefore needs its own containment.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: perform a sandbox feasibility spike; if viable, enable App Sandbox and remove ambient Downloads access in favor of user-selected URLs/security-scoped bookmarks.
  - Config / platform control: if the main UI cannot be sandboxed, split privileged/device operations into a narrowly defined helper with authenticated IPC and retain the UI in a sandbox where possible.
  - Least privilege: keep JIT, unsigned executable memory, DYLD environment, and library-validation exceptions disabled; remove any capability not proven by a test.
  - Tests / invariants: entitlement allowlist check; sandboxed GPX import/export test; network/USB/helper integration tests; negative test for arbitrary Downloads access.
- **Incorrect fixes to avoid**: Enabling App Sandbox without testing Python/USB/helper flows, adding broad temporary exceptions, or assuming the existing capability comments enforce restrictions.
- **Residual risk after fix**: A privileged helper and external Python process remain separate high-value boundaries and require their own authorization and path-integrity controls.
- **Priority / SLA suggestion**: Low — make an explicit architecture decision within 30 days; avoid a blind entitlement toggle.
- **Confidence**: LIKELY
- **Effort**: L

### [INFO] BUILD-EXCLUDED INFOPLIST DUPLICATES LIVE RELEASE METADATA
- **ID**: DEAD-001
- **Category**: Dead code
- **CWE / OWASP / ASVS**: CWE-1059 Insufficient Technical Documentation; OWASP/ASVS N/A
- **Location**: `Package.swift:L20-L29`, `PathChanger/Info.plist:L19-L38`, `Resources/Info.plist:L15-L30`, `.github/workflows/release.yml:L62-L73`
- **Evidence**:
  - Snippet (minimal): the target declares `exclude: ["Info.plist"]`; the excluded plist says version `1.0`, while the release plist says `1.0.0`.
  - Data flow: maintainer edit to `PathChanger/Info.plist` → file excluded from SwiftPM target → release workflow reads `Resources/Info.plist` instead.
  - Control flow / auth decision points: privacy-purpose strings and entitlement-looking keys exist only in the excluded plist; release version validation explicitly reads `Resources/Info.plist`.
- **Description**: `PathChanger/Info.plist` is build-excluded in the reviewed package and has already drifted from the authoritative release plist. It is a zombie configuration surface that can misdirect security/privacy/version updates.
- **Preconditions**: A maintainer assumes the excluded plist is authoritative.
- **Impact**: Low-probability correctness/configuration drift; no direct exploit path. A required privacy-purpose string or version update could be applied to the wrong file.
- **Exploitability analysis**: This is maintainer-induced rather than attacker-driven.
- **Why scanners may miss this**: Plist linters validate syntax independently and may not trace SwiftPM exclusion plus workflow use.
- **Chaining**: It weakens confidence in entitlement/privacy configuration review but does not amplify a confirmed vulnerability directly.
- **Recommended fix** (preferred + alternatives):
  - Code-level change: remove the excluded plist if no non-SwiftPM build consumes it, or generate both from one authoritative source.
  - Config / platform control: make release validation assert the authoritative plist contains every required privacy-purpose key.
  - Least privilege: keep entitlement keys only in the entitlement file, not Info.plist.
  - Tests / invariants: fail CI if duplicate bundle metadata files diverge or if a non-authoritative plist reappears.
- **Incorrect fixes to avoid**: Manually synchronizing two files indefinitely without defining authority.
- **Residual risk after fix**: Alternative local Xcode build paths, if any exist outside the assigned scope, may still require a plist.
- **Priority / SLA suggestion**: Info — resolve during routine configuration cleanup after confirming no external consumer.
- **Confidence**: CONFIRMED
- **Effort**: S

## 7. Vulnerability chains

### Python supply-chain drift → privileged runtime use
`DEPLOYMENT/TUNNEL_MODES.md:L178-L186` directs an unconstrained upgrade, while `requirements-pathchanger.txt:L12-L17` does not enforce even its recorded direct-wheel hash or the transitive closure. Daemon mode documents administrator privileges at `DEPLOYMENT/TUNNEL_MODES.md:L99-L120`. The realistic chain is operator troubleshooting → mutable PyPI resolution → later execution in the device-tunneling daemon path. It requires dependency/index compromise or an incompatible release and affects one local environment, so the compound chain remains Medium rather than High.

### Same-channel release generation → same-channel checksum replacement
The release job has necessary `contents: write` permission (`.github/workflows/release.yml:L18-L24`), creates both artifact and checksum (`.github/workflows/release.yml:L117-L129`), and uploads both with `--clobber` (`.github/workflows/release.yml:L131-L145`). Ad-hoc signing is the only publisher-signing model described (`.github/workflows/release.yml:L157-L159`, `DEPLOYMENT/README.md:L22-L27`). A workflow/release compromise can therefore replace the artifact and its verification file consistently; independent Developer ID/notarization or signed provenance breaks this chain.

### Local peer discovery → false safety state
The companion advertises and browses automatically (`PathChangerCompanion/CompanionConnectionService.swift:L50-L64`), accepts invitations unconditionally (`PathChangerCompanion/CompanionConnectionService.swift:L237-L247`), and maps decoded messages directly to status (`PathChangerCompanion/CompanionConnectionService.swift:L114-L143`). Encryption blocks passive tampering but not an active untrusted participant. Pairing identity plus sender authorization breaks the chain.

## 8. Dead code & unused surface report

### Dead / unused inventory
| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-001 | `PathChanger/Info.plist` | Build-excluded zombie configuration | `Package.swift:L20-L29` excludes it; release validation reads `Resources/Info.plist` at `.github/workflows/release.yml:L62-L73` | An unreviewed Xcode/non-SwiftPM path may still consume it | Confirm all build paths, then delete it or generate it from the authoritative release plist |

### Complexity / unneeded surface reduction
The companion both browses and advertises (`PathChangerCompanion/CompanionConnectionService.swift:L55-L63`) even though the UI's stated purpose is to find the Mac. If inbound Mac-initiated connections are not required, removing advertising and its auto-accept delegate would reduce peer attack surface; runtime/product confirmation is required.

The entitlement file grants both user-selected read/write and Downloads read/write (`Resources/PathChanger.entitlements:L68-L78`). Prefer only the user-mediated capability if product tests show default Downloads access is unnecessary. Because App Sandbox is not declared in the reviewed file, this is an architecture/cleanup recommendation rather than proof of a currently effective extra sandbox grant.

No unused remote Swift dependency was found: all three Swift package manifests use only local targets/path dependencies (`Package.swift:L12-L23`, `PathChangerCompanion/Package.swift:L10-L22`, `SharedCompanionProtocol/Package.swift:L11-L21`).

## 9. Bugs / mistakes / error-handling defects
DEAD-001 is the principal configuration-integrity defect: two plists disagree on version and privacy/entitlement-like keys while only one is used by the reviewed release path (`PathChanger/Info.plist:L19-L38`, `Resources/Info.plist:L15-L30`, `.github/workflows/release.yml:L62-L73`).

The companion decoder reports malformed messages but has no message-size or rate guard (`PathChangerCompanion/CompanionConnectionService.swift:L174-L184`). This was not promoted to a separate vulnerability because MultipeerConnectivity already requires an accepted peer and no measurable resource-exhaustion path was tested; add bounded-message/rate tests when implementing VULN-001.

## 10. Dependency & supply-chain notes
- Root and companion Swift manifests depend only on the local `SharedCompanionProtocol` package (`Package.swift:L15-L23`, `PathChangerCompanion/Package.swift:L13-L21`). In this assigned scope, absence of `Package.resolved` does not leave a remote Swift package floating.
- The three workflows use no third-party `uses:` Actions; checkout is implemented directly with a command-scoped authentication header. CI and validation have `contents: read`; only the release publisher has `contents: write` (`.github/workflows/ci.yml:L14-L15`, `.github/workflows/release-validation.yml:L23-L28`, `.github/workflows/release.yml:L18-L24`).
- CI uses `pull_request`, not `pull_request_target`, so reviewed PR code does not receive a write-scoped token under the assigned workflow (`.github/workflows/ci.yml:L3-L8`, `.github/workflows/ci.yml:L14-L15`).
- The manually supplied release-validation input is copied through `env` and format-validated before use (`.github/workflows/release-validation.yml:L59-L80`). Release tag input is likewise constrained to `vMAJOR.MINOR.PATCH` before shell-derived use (`.github/workflows/release.yml:L54-L73`). No exploitable `${{ }}` shell interpolation was confirmed.
- `pymobiledevice3` 9.12.0 is directly pinned (`requirements-pathchanger.txt:L12-L17`), but the file is untracked in the audited worktree and lacks an enforceable transitive lock/hash policy. PyPI's 9.12.0 metadata lists numerous unbounded or lower-bound-only dependencies; the package appears actively maintained, so it is not classified as abandoned.
- The scoped secret scan found no private-key/provider-token/hard-coded credential pattern. `.gitignore` excludes `.env` and `.env.*` (`.gitignore:L22-L25`), but ignore rules are not a substitute for a repository-wide secret gate.
- Hosted runner labels and the Swift/Xcode/Homebrew toolchain remain mutable (`.github/workflows/ci.yml:L21-L24`, `.github/workflows/release.yml:L18-L21`). Reproducibility would improve by selecting a validated Xcode version and asserting exact tool versions, even though hosted-image pinning cannot eliminate platform trust.

## 11. Remediation roadmap

### Wave 0: emergency
No emergency Critical/High patch is required. Within 48 hours, replace the unconstrained pip troubleshooting command, add `requirements-pathchanger.txt` or its replacement lock to version control, and ensure installs cannot proceed without approved hashes (`DEPLOYMENT/TUNNEL_MODES.md:L178-L186`, `requirements-pathchanger.txt:L1-L17`).

### Wave 1: high-risk design fixes
Implement authenticated, single-peer companion pairing and sender authorization around `PathChangerCompanion/CompanionConnectionService.swift:L50-L64` and `L237-L247`. Establish Developer ID/notarization or independently signed provenance for the release path at `.github/workflows/release.yml:L79-L159`.

### Wave 2: hardening and dead-surface removal
Replace ad-hoc CI grep/print checks with enforced secret and entitlement policies (`.github/workflows/ci.yml:L121-L153`), pin SwiftLint (`.github/workflows/ci.yml:L115-L119`), and remove or generate the excluded plist from one source (`Package.swift:L20-L29`).

### Wave 3: long-term architecture
Evaluate a sandboxed UI plus narrowly privileged authenticated helper. Record an ADR defining entitlement ownership, Python lock generation/promotion, companion trust establishment, and release identity/provenance.

## 12. Verification plan
- Companion tests: reject unknown invitations; accept only a persisted expected key; ensure one peer owns status; reject replay/out-of-order messages; exercise key rotation and lost-device reset.
- Python CI gate: generate/check a complete lock for each supported Python/platform tuple; install with `--require-hashes`; compare runtime package inventory; run advisory and license scans; smoke-test tunnel start/location set before promotion.
- Release gate: assert exact Team ID/designated requirement, hardened-runtime expectation, notarization/stapling, `spctl` assessment, SBOM, signed provenance, and asset digest equality before `gh release upload`.
- Workflow policy: lint workflows; reject `pull_request_target`; reject job-level write permissions outside release; reject unpinned `uses:` references if Actions are introduced; reject unvalidated expressions in shell.
- Entitlement policy: parse the final signed bundle's entitlements, not only the source plist; compare against an allowlist and fail on JIT, unsigned executable memory, library-validation disablement, DYLD exceptions, or undocumented capabilities.
- Secret gate: scan all tracked file types and diffs with redacted output; include synthetic fixtures proving Python, shell, YAML, plist, Markdown, and text detection.
- Configuration gate: verify only one authoritative Info.plist or verify generated copies are byte-for-byte/policy equivalent.
- Metrics: dependency-lock age, days behind approved direct dependency, percent of artifacts with verified provenance/notarization, secret-scan coverage by tracked file type, entitlement-policy exceptions, and companion pairing failures/rejections.

## 13. Residual risk & future-proofing
Even after lock/hash enforcement, dependency maintainers and the lock-review process remain trusted. Maintain controlled update cadence, provenance review, and a rollbackable known-good Python environment.

Developer ID/notarization improves consumer verification but does not prevent an authorized malicious release. Preserve release approvals, narrow credentials, immutable audit logs, and rapid certificate/token revocation.

Authenticated peer pairing protects identity, not the correctness of an already-compromised paired Mac. Keep message capabilities narrow, version the protocol, validate numeric ranges, and separate “display status” from authority to execute host actions.

If App Sandbox is infeasible, document why and isolate privilege behind a small authenticated helper rather than allowing the UI process to accumulate device/file/process authority. Preserve the invariant that JIT, unsigned executable memory, DYLD environment, and disabled library validation remain off (`Resources/PathChanger.entitlements:L14-L31`).

Suggested ADRs: “Python dependency lock and promotion policy,” “macOS release identity and provenance,” “Companion peer identity and message authorization,” and “Sandbox/helper privilege boundary.”

## 14. Missing context / questions that would change severity
1. Does `build-app-bundle.sh` apply `Resources/PathChanger.entitlements`, enable hardened runtime, or perform signing/notarization outside the reviewed workflow? Confirmation could reduce or increase VULN-002/VULN-006.
2. Does the out-of-scope macOS `CompanionHostService` authenticate peers before accepting emergency-stop or other messages? If it also auto-accepts, VULN-001's impact may extend from misleading companion state to host control.
3. Is there a separate signed release/provenance channel or Developer ID process not represented in `DEPLOYMENT/README.md:L2-L27`? A verified independent channel would reduce VULN-002.
4. Which Python versions/platforms are supported, and is an external lock/installer maintained outside the repository? A complete enforced lock would reduce VULN-003.
5. Is `PathChanger/Info.plist` consumed by an external Xcode project not represented by `Package.swift:L20-L29`? If yes, DEAD-001 should be converted from removal to generation/synchronization.
6. Which entitlements appear in `codesign -d --entitlements :-` on the shipped app? Source-plist review cannot prove final-bundle enforcement.

## Out-of-scope observations
No Critical or High out-of-scope issue was observed during the assigned review. Workflow-invoked shell scripts and the macOS host-side companion implementation warrant separate focused review because they determine final signing/entitlement application and whether companion messages can trigger host actions.
