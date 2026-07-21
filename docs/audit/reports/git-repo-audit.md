# PathChanger Git Repository and Repo-Hygiene Audit

**Audit date:** 2026-07-20  
**Auditor:** `git-repo` read-only audit agent  
**Repository:** `https://github.com/abyssbugg/PathChanger.git`  
**Audited local branch:** `feat/ui-redesign` at `b897b6cb5855174c4c118ae60e8e5b579400e8ea`, including the uncommitted working tree  
**Mode:** DIAGNOSTIC; no source, Git reference, dependency, build output, or GitHub setting was modified  
**Finding count:** 0 Critical, 0 High, 2 Medium, 1 Low, 3 Info

## 1. Executive summary
PathChanger is a private macOS/Swift application repository whose source, CI, release automation, Python helpers, and dependency instructions collectively control a paired iOS device and its simulated location.

No committed credential, private key, signing archive, provisioning profile, or recognized provider-token signature was confirmed in the 30 reachable commits. The only historical secret-pattern candidates were explicit placeholders in the deleted `.env.example` and test-only password fixtures.

The highest repository-integrity risks are:

1. GitHub reports `main` as unprotected with no repository ruleset, despite the repository stating that one approval and green CI are required (`CONTRIBUTING.md:L34-L38`).
2. The pushed feature branch instructs users and recovery paths to run an unconstrained `pip install -U pymobiledevice3` and accepts any version at or above 6.1.5 (`origin/feat/ui-redesign:README.md:L73-L79`; `origin/feat/ui-redesign:PathChanger/Core/PythonPathResolver.swift:L40-L43,L60-L61`).
3. The local dependency-pin remediation is not yet in the GitHub branch, and its proposed wheel hash is informational rather than enforced (`requirements-pathchanger.txt:L11-L17`).
4. CI secret detection scans only Swift, JSON, and plist files, while `.gitignore` does not cover common key/signing formats (`.github/workflows/ci.yml:L139-L146`; `.gitignore:L17-L19`).
5. Dormant companion-network code, an associated root-package dependency, and stale accepted ADRs create avoidable review and maintenance surface (`PathChanger/Device/CompanionHostService.swift:L17-L37`; `Package.swift:L13-L24`; `docs/adr/001-python-bridge-architecture.md:L12-L17`).

**Overall risk posture:** Medium. There is no confirmed current secret exposure or unauthenticated repository compromise path. The material risks require GitHub write authority, operator action, or dependency compromise, but they affect source/release integrity and code that controls a paired device.

**Immediate actions**

- **Within 48 hours:** protect `main`; require the CI jobs and one independent approval; commit a complete, reproducible Python lock/hashing strategy before publishing dependency guidance.
- **Within 7 days:** enable platform secret scanning and dependency alerts; replace the narrow regex check with a maintained scanner covering the full PR diff and history.
- **Within 30 days:** resolve dormant companion-host code and root dependency ownership; supersede stale ADRs; separate security/CI changes from the UI redesign branch for focused review.

## 2. Threat model

### System summary
The audited system is the Git/GitHub control plane for a local desktop application. The primary assets are source-code integrity, release-workflow integrity, GitHub Actions credentials, dependency provenance, app-bundle integrity, device-pairing trust, and the confidentiality of any future signing or API credentials. The GitHub repository is **PRIVATE**, as observed through `gh repo view abyssbugg/PathChanger --json visibility,isPrivate`; it is not a public multi-tenant service.

The application package itself targets macOS 14 and builds an executable that consumes a local shared protocol package (`Package.swift:L6-L24`). Release automation produces ad-hoc-signed GitHub assets and grants the release job `contents: write` (`.github/workflows/release.yml:L1-L24`).

Actors in this repository scope are the sole current GitHub administrator, a holder of a compromised administrator/token credential, GitHub Actions jobs, dependency maintainers or a compromised package index, contributors submitting pull requests, and the local operator installing dependencies or building/releases.

### Entry points

- Git pushes and pull requests targeting `main` or `develop` (`.github/workflows/ci.yml:L3-L8`).
- GitHub release publication, which triggers a write-capable artifact workflow (`.github/workflows/release.yml:L1-L24`).
- Manual release validation input (`.github/workflows/release-validation.yml:L1-L12`).
- Python package installation and version resolution (`origin/feat/ui-redesign:README.md:L73-L79`; `origin/feat/ui-redesign:PathChanger/Core/PythonPathResolver.swift:L40-L43,L60-L61`).
- Shell/Python helper scripts packaged into the app (`build-app-bundle.sh:L163-L181`).
- Dormant MultipeerConnectivity host/companion code (`PathChanger/Device/CompanionHostService.swift:L17-L37,L48-L75`).

### Trust-boundary map

1. Contributor or administrator → GitHub branch/ref.
2. GitHub ref → hosted Actions runner (`.github/workflows/ci.yml:L20-L38`).
3. Published release event → write-capable release job → GitHub release assets (`.github/workflows/release.yml:L13-L24,L135-L146`).
4. Repository instructions/local app → `pip`/PyPI → executable Python dependency (`origin/feat/ui-redesign:README.md:L73-L79`).
5. Build scripts → local Swift/Python files → signed app bundle (`build-app-bundle.sh:L153-L181,L188-L220`).
6. Dormant Mac companion host → MultipeerConnectivity peer → emergency-stop callback (`PathChanger/Device/CompanionHostService.swift:L23-L37,L116-L141`).

### Principal abuse cases

1. A compromised GitHub administrator pushes directly to unprotected `main`, bypassing review and required CI.
2. An operator publishes a release from an insufficiently reviewed ref; the release workflow obtains `contents: write`.
3. An upstream Python package or newly selected transitive version executes on installation or when invoked by PathChanger.
4. A future credential is committed in YAML, shell, Python, Markdown, or a key archive that the current CI regex does not scan.
5. A removed credential remains reachable in Git history.
6. Dormant network code is re-enabled without authentication/security review.
7. Stale accepted ADRs cause a maintainer to restore a deleted or divergent implementation.
8. Security-sensitive tunnel, subprocess, and release changes are reviewed as part of a very large UI branch rather than as focused changes.

## 3. Methodology notes

### Passes completed

- **Pass A:** repository/CI/release/dependency entry points and trust boundaries.
- **Pass D:** full-history sensitive-filename and redacted secret-signature scans.
- **Pass G:** SwiftPM and Python dependency declarations, GitHub dependency-alert status, and reproducibility controls.
- **Pass H:** repository visibility, branch protection, rulesets, open pull requests, security-advisory endpoint, Dependabot status, workflows, and ignore rules.
- **Pass I:** tracked-script references, dormant product modules, local-package dependency use, and stale documentation/ADR checks.
- **Pass J:** branch-policy plus release-permission and dependency-install chains.
- **Pass K:** verification and regression controls for each material finding.

Passes B, C, E, and F were not deep-dived because this assignment was limited to Git/GitHub and repository-wide hygiene. Runtime authorization, subprocess, tunnel, UI, and helper-script audits were assigned separately. No build, test, dependency install, fetch, pull, checkout, reset, stash, or GitHub mutation was performed.

### Evidence commands

All commands were read-only. Material observations were established with:

- `git --no-pager status --short --branch`
- `git --no-pager branch -a -vv --no-abbrev`
- `git rev-list --all --count`
- `git --no-pager log --all --full-history ...` for sensitive filename and content candidates
- `git --no-pager diff --stat origin/main...origin/feat/ui-redesign`
- `git --no-pager diff --name-status origin/main...origin/feat/ui-redesign`
- `git ls-files -ci --exclude-standard`
- `git ls-files` filtered for secrets, build outputs, local configs, and binary artifacts
- `rg` reference inventories for tracked scripts, companion-host symbols, and stale implementation names
- `gh repo view`, `gh pr list`, and read-only `gh api` calls for branch state, rulesets, collaborators, advisories, and Dependabot alerts

### Repository and GitHub baseline

- Local `feat/ui-redesign` matched `origin/feat/ui-redesign` at `b897b6cb5855174c4c118ae60e8e5b579400e8ea` before uncommitted changes.
- `origin/main` was `75321f51b786d319d2ddad568ca4b09364666c5e`.
- The refs diverged by 1 `main` commit and 22 feature commits.
- The requested three-dot comparison changed 156 files with 21,586 insertions and 11,571 deletions.
- The GitHub repository was private, active, and had one collaborator (`abyssbugg`, admin).
- One open pull request existed: #1, `oz/ui-tunnel-stabilization-20260505` → `main`. No PR for `feat/ui-redesign` was observed.
- The `main` branch API returned `protected: false`; repository rulesets were `[]`.
- Dependabot alerts returned HTTP 403 with “Dependabot alerts are disabled for this repository.”
- The security-advisories endpoint returned HTTP 404; therefore private advisory availability/state could not be independently established.

### Git-history secret scan result

Thirty commits across all reachable refs were scanned. The exact sensitive-filename history query covered `*.p12`, `*.pem`, `*.key`, `*.mobileprovision`, `*.env`, `.env*`, credential/secret/token names, identity keys, and certificate/provisioning extensions.

Only `.env.example` appeared in that filename history: it was added in `8fe005f1e806ae5e90d0b2ecb6fc04a37357f36e` and deleted in `c1d550bc14ef6f47e0cc9dce646cc5c938b761ee`. A redacted classifier established that lines 2–12 all contained explicit placeholder markers. Two generic password matches at `Tests/PathChangerTests/CloudSyncTests.swift:L309,L317` in the initial commit were test authentication fixtures. Known signatures for private keys, AWS keys, GitHub tokens, OpenAI-style tokens, Slack tokens, and Google API keys produced no confirmed match. No historical `.p12`, PEM/private key, `.mobileprovision`, or equivalent signing artifact was observed.

This is a negative result, not proof that every possible secret format is absent. The scanner intentionally did not print candidate values.

### Assumptions

- GitHub’s authenticated branch `protected` field and empty rulesets response accurately represent effective repository policy.
- The private repository currently has one administrator/collaborator as reported by the collaborators endpoint.
- Dynamic loading of internal Swift classes is not performed outside the opened repository; candidate-unused items remain labeled where runtime confirmation is appropriate.
- The local uncommitted dependency-pin work is not available to GitHub consumers until committed and pushed.

## 4. Critical & High findings

No Critical or High finding was confirmed in this scope. The repository is private, no committed secret was confirmed, and no unauthenticated path to repository or release control was identified.

## 5. Medium findings

### [MEDIUM] Documented review and CI gates are not enforced on `main`
- **ID**: VULN-001
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-284 (Improper Access Control), supply-chain/change-control context; OWASP/ASVS not directly applicable
- **Location**: `CONTRIBUTING.md:L25-L38`; `.github/workflows/ci.yml:L3-L8`; `.github/workflows/release.yml:L13-L24`
- **Evidence**:
  - The repository says pull requests require one approving review and green CI (`CONTRIBUTING.md:L34-L38`).
  - CI is configured for pushes and pull requests to `main`/`develop`, but workflow presence does not make its checks mandatory (`.github/workflows/ci.yml:L3-L8`).
  - The release job receives `contents: write` after a release is published (`.github/workflows/release.yml:L13-L24`).
  - Authenticated GitHub API evidence returned `main.protected=false`, protection enforcement `off`, no required contexts, and an empty repository ruleset list. The sole listed collaborator is the administrator.
  - Control flow: administrator/token with push authority → direct update to `main` without required review/checks → release publication → write-capable release workflow.
- **Description**: The repository documents review and CI as mandatory controls, but GitHub does not enforce them. A direct push can bypass the intended independent review and status checks.
- **Preconditions**: A malicious or mistaken action by the sole administrator, or compromise of an administrator/push-capable credential. Anonymous users and ordinary local app users cannot use this path.
- **Impact**: Source and release integrity can be lost. A bypassed change can alter build scripts, workflows, entitlements, packaged Python helpers, or application code and then be distributed as a GitHub release. The current blast radius is this private repository and its release consumers.
- **Exploitability analysis**: The attacker must first obtain GitHub write/admin capability; this finding does not create that capability. Once obtained, no repository policy requires an independent approval or successful security/build checks before `main` changes.
- **Why scanners may miss this**: Static source scanners see the workflow and contribution policy but not the effective GitHub branch/ruleset configuration.
- **Chaining**: Amplifies VULN-002 and VULN-003 because dependency or secret-scanning changes can bypass review. The release job’s write permission increases downstream artifact impact.
- **Recommended fix** (preferred + alternatives):
  - Protect `main` or create an active ruleset requiring pull requests, at least one approval from a distinct account, dismissal of stale approvals, resolution of review conversations, and up-to-date branches.
  - Require the actual CI job checks: build/test, lint, security scan, release configuration validation, and documentation.
  - Restrict force pushes and deletions; require signed commits/tags where operationally feasible.
  - Put release publication behind a protected GitHub environment with explicit approval and least-privilege permissions.
  - Add a second trusted reviewer or revise the documented one-review claim until independent approval is operationally possible.
  - Add a periodic API assertion that fails governance checks if `main.protected` becomes false or required contexts disappear.
- **Incorrect fixes to avoid**: Do not treat workflow triggers, a contribution document, or a local pre-push hook as equivalent to server-enforced branch policy. Do not grant broad bypass rights to routine automation.
- **Residual risk after fix**: Repository administrators can usually alter protection settings; account security, narrow tokens, MFA/passkeys, audit-log review, and release-environment approval remain necessary.
- **Priority / SLA suggestion**: Wave 0; enforce before the next release or merge to `main`.
- **Confidence**: CONFIRMED
- **Effort**: S

### [MEDIUM] The pushed branch installs security-sensitive Python code without a reproducible integrity lock
- **ID**: VULN-002
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-494 (Download of Code Without Integrity Check); OWASP A08:2021 Software and Data Integrity Failures
- **Location**: `origin/feat/ui-redesign:README.md:L73-L79`; `origin/feat/ui-redesign:PathChanger/Core/PythonPathResolver.swift:L40-L43,L60-L61`; `requirements-pathchanger.txt:L11-L17`; `.github/workflows/ci.yml:L40-L96`
- **Evidence**:
  - The pushed branch tells users to run `python3 -m pip install -U pymobiledevice3` and accepts versions `>= 6.1.5` (`origin/feat/ui-redesign:README.md:L73-L79`).
  - The pushed resolver repeats unconstrained upgrade guidance and only defines a minimum version (`origin/feat/ui-redesign:PathChanger/Core/PythonPathResolver.swift:L40-L43,L60-L61`).
  - The uncommitted local mitigation pins `pymobiledevice3==9.12.0`, but explicitly says the wheel hash is informational and that transitive dependencies are not hash-pinned (`requirements-pathchanger.txt:L11-L17`).
  - The requirement file is untracked in the audited working tree, so it is absent from `origin/feat/ui-redesign`.
  - CI resolves/builds Swift and packages/tests the app but does not install the Python dependency from a locked graph or run a Python dependency audit (`.github/workflows/ci.yml:L40-L96`).
  - GitHub reported Dependabot alerts disabled.
  - Data flow: repository guidance/recovery suggestion → mutable package index selection → package/transitive installation → PathChanger executes the installed Python module to control device/tunnel operations.
- **Description**: GitHub consumers receive an open-ended upgrade instruction rather than a reviewed, reproducible dependency graph. The local work improves the direct pin but does not yet protect GitHub users and does not enforce hashes for the full transitive closure.
- **Preconditions**: A user follows the installation/recovery guidance, or a maintainer updates/install dependencies in an environment where the selected package or a transitive release is compromised or unexpectedly incompatible.
- **Impact**: Installed Python code executes with the local user’s permissions and participates in iOS pairing/tunnel/location operations. A malicious dependency could affect workstation confidentiality/integrity and paired-device operations. This is not an automatic remote path; package installation/operator action is required.
- **Exploitability analysis**: An attacker needs control of an accepted upstream package/release, package-index delivery path, or maintainer guidance. The unconstrained `-U` widens the candidate version set; the absence of full hash enforcement prevents deterministic artifact verification.
- **Why scanners may miss this**: Dependency scanners cannot reliably evaluate an untracked requirement file, and the GitHub branch exposes only a runtime minimum rather than a complete manifest/lock graph.
- **Chaining**: VULN-001 permits dependency-policy changes to bypass required review. Disabled Dependabot alerts reduce detection of known vulnerable releases.
- **Recommended fix** (preferred + alternatives):
  - Commit the dependency manifest and resolver/README changes as one atomic, reviewed change.
  - Generate a platform-appropriate lock for the complete transitive graph with hashes and install with `--require-hashes`; record supported Python and macOS architectures.
  - Treat the direct wheel hash as enforced input, not an informational comment.
  - Add CI that creates a clean virtual environment, installs exactly the locked graph, verifies hashes, imports/runs a non-device smoke check, and runs a maintained Python vulnerability audit.
  - Enable Dependabot or an equivalent scheduled dependency monitor for the committed Python manifest.
  - Define an intentional update procedure with device/tunnel regression testing before changing any pin.
- **Incorrect fixes to avoid**: A direct version pin without transitive hashes is not a complete integrity lock. Do not restore `pip install -U`, silently fall back to a different version, or download/execute packages during privileged operations.
- **Residual risk after fix**: A legitimately signed/hashed upstream release can still contain malicious code. Maintainer review, provenance/signature verification where available, sandboxing, and least-privilege process execution remain necessary.
- **Priority / SLA suggestion**: Wave 0; resolve before publishing the feature branch’s dependency guidance or next release.
- **Confidence**: CONFIRMED
- **Effort**: M

## 6. Low / Info findings

### [LOW] Secret-prevention controls omit common repository and signing-secret paths
- **ID**: VULN-003
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: CWE-312 (Cleartext Storage of Sensitive Information), preventive-control gap; OWASP A02/A08 context
- **Location**: `.github/workflows/ci.yml:L139-L146`; `.gitignore:L17-L19`
- **Evidence**:
  - CI greps only `*.swift`, `*.json`, and `*.plist` for a narrow quoted-assignment pattern (`.github/workflows/ci.yml:L139-L146`).
  - The repository also contains security-relevant YAML, shell, Python, Markdown, and environment/config surfaces, including workflows and packaged helpers (`.github/workflows/release.yml:L1-L24`; `build-app-bundle.sh:L163-L181`).
  - `.gitignore` ignores `.env` and `.env.*` but has no patterns for `.p12`, `.pfx`, PEM/private keys, provisioning profiles, certificates, or common local signing directories (`.gitignore:L17-L19`).
  - GitHub’s repository metadata returned `security_and_analysis: null`; native secret-scanning status could not be confirmed as enabled.
  - The full-history audit found no confirmed credential, which limits current impact.
- **Description**: The current checks provide false-negative-prone coverage for future secrets, especially workflow tokens, shell/Python assignments, raw key material, and signing archives.
- **Preconditions**: A maintainer accidentally adds a secret in an unscanned source type or key archive and commits/pushes it.
- **Impact**: Potential credential or signing-material exposure to repository collaborators, CI, backups, forks/clones, or future visibility changes. The repository is private and no present secret was confirmed, so severity is Low.
- **Exploitability analysis**: Access requires the accidental commit plus an actor able to read the private repository or its clones/logs. If repository visibility becomes public, impact and urgency increase substantially.
- **Why scanners may miss this**: This is the scanner coverage gap itself; the regex does not inspect full history, entropy, key headers across all relevant types, or binary signing containers.
- **Chaining**: VULN-001 allows direct pushes to bypass even this limited CI job.
- **Recommended fix** (preferred + alternatives):
  - Enable GitHub secret scanning and push protection if the repository plan supports them.
  - Run a maintained scanner such as gitleaks/trufflehog in pre-commit and CI against the PR diff; run a separately controlled scheduled full-history scan.
  - Add ignore patterns for local signing assets and provisioning profiles while retaining intentional public certificates only through explicit negation/allowlisting.
  - Document immediate revoke/rotate/history-rewrite procedures; never rely on deletion in a later commit.
- **Incorrect fixes to avoid**: Do not print matched credential values in logs, add real-looking tokens to regex tests, or assume `.gitignore` protects already tracked/history content.
- **Residual risk after fix**: Novel token formats and encrypted/binary containers can evade detection; operator review and credential rotation remain required.
- **Priority / SLA suggestion**: Wave 1; complete within 30 days and before introducing production signing secrets.
- **Confidence**: CONFIRMED
- **Effort**: S

### [INFO] Dormant companion-host network code is the root package’s only shared-protocol consumer
- **ID**: DEAD-001
- **Category**: Dead code
- **CWE / OWASP / ASVS**: N/A; unnecessary attack/maintenance surface
- **Location**: `PathChanger/Device/CompanionHostService.swift:L17-L37,L48-L75,L116-L147,L193-L220`; `Package.swift:L13-L24`; `Resources/PathChanger.entitlements:L37-L63`
- **Evidence**:
  - `CompanionHostService` creates advertiser/browser/session state, exposes an emergency-stop callback, auto-accepts invitations, and auto-invites discovered peers (`PathChanger/Device/CompanionHostService.swift:L17-L37,L48-L75,L116-L147,L193-L220`).
  - Repository-wide `rg` found no `CompanionHostService` construction or reference outside its own file. The shared service string appears in the separate iOS companion implementation and entitlement comments, not in a Mac app call site.
  - The root Swift package depends on `SharedCompanionProtocol` (`Package.swift:L13-L24`), and the only import under the root `PathChanger` target is in this dormant host file (`PathChanger/Device/CompanionHostService.swift:L8-L11`).
  - Network-server and Bluetooth entitlements are documented solely for this host service (`Resources/PathChanger.entitlements:L37-L63`).
- **Description**: The host code is compiled into the root target but has no observed runtime construction path. It retains a local package dependency and security-sensitive networking implementation without current product wiring.
- **Preconditions**: Current reachability assumes no out-of-repository dynamic instantiation. The separate iOS companion package is real product code and must not be deleted solely because the Mac host is dormant.
- **Impact**: No active listener was confirmed. The current impact is review burden, stale assumptions, and risk that the auto-accept/emergency-stop path is later enabled without an explicit authentication/security design.
- **Exploitability analysis**: No current exploit path was established because `start()` is not reachable from an observed instance. Re-enablement would change that conclusion.
- **Why scanners may miss this**: SwiftPM includes source files by target path, so build inclusion does not prove runtime reachability; simple unused-import tools may also treat the local package as used.
- **Chaining**: Stale docs and entitlement comments can lead maintainers to assume the feature is active.
- **Recommended fix** (preferred + alternatives):
  - **CANDIDATE-UNUSED — NEEDS RUNTIME/CONFIG CONFIRMATION.**
  - If the feature is abandoned, remove the Mac host file and root-target dependency; then re-evaluate the companion-specific entitlements and tests. Preserve the separate iOS package only if it remains supported.
  - If the feature is planned, add explicit lifecycle wiring, authenticated peer binding, tests, ownership documentation, and a security review before activation.
- **Incorrect fixes to avoid**: Do not delete the shared protocol or iOS companion package without checking the separate package build/release path. Do not activate the host merely to make the code “used.”
- **Residual risk after fix**: An active companion feature will retain a local wireless trust boundary and requires peer-authentication and replay/authorization review.
- **Priority / SLA suggestion**: Wave 2; decide ownership before the next companion-related change.
- **Confidence**: LIKELY
- **Effort**: S if removed; M/L if productized securely

### [INFO] Accepted ADRs and contribution documentation contradict current code and CI
- **ID**: DEAD-002
- **Category**: Design flaw
- **CWE / OWASP / ASVS**: N/A; stale documentation/code-integrity risk
- **Location**: `docs/adr/001-python-bridge-architecture.md:L12-L17`; `docs/adr/003-state-machine-tunnel-management.md:L22-L43`; `PathChanger/Device/TunnelState.swift:L40-L46`; `README.md:L340-L343`; `.github/workflows/ci.yml:L171-L179`; `CONTRIBUTING.md:L25-L38`
- **Evidence**:
  - ADR 001 remains “Accepted” and identifies `PersistentLocationBridge`, but Git history shows that `PathChanger/Device/PersistentLocationBridge.swift` was deleted in commit `c1d550bc14ef6f47e0cc9dce646cc5c938b761ee`; the current tracked tree contains no such path (`docs/adr/001-python-bridge-architecture.md:L3-L17`).
  - ADR 003 describes mode-associated `starting`/`running` states and `externallyManaged`, while the current `TunnelState` has simple `starting`/`running` cases and no `externallyManaged` case (`docs/adr/003-state-machine-tunnel-management.md:L22-L43`; `PathChanger/Device/TunnelState.swift:L40-L46`).
  - README says DocC generation is disabled, while CI executes `xcodebuild ... docbuild` and requires a `.doccarchive` (`README.md:L340-L343`; `.github/workflows/ci.yml:L171-L179`).
  - CONTRIBUTING says CI uploads to Codecov and requires an approval (`CONTRIBUTING.md:L25-L38`), but the workflow only generates local LCOV output (`.github/workflows/ci.yml:L84-L96`) and GitHub reports no enforced approval.
- **Description**: Architectural and contribution documents present superseded behavior as current, creating a misleading basis for security and maintenance decisions.
- **Preconditions**: A maintainer relies on these documents rather than tracing current code and GitHub settings.
- **Impact**: Incorrect changes, reintroduction of removed dual paths, mistaken release/coverage assurance, and delayed detection of governance drift.
- **Exploitability analysis**: This is not directly exploitable. It increases the probability of unsafe maintenance and weak review.
- **Why scanners may miss this**: Cross-document semantic drift is not a syntax or dependency error.
- **Chaining**: Reinforces VULN-001 by claiming controls that GitHub does not enforce and DEAD-001 by keeping inactive architectures conceptually alive.
- **Recommended fix** (preferred + alternatives):
  - Mark superseded ADRs explicitly and link replacement decisions; do not silently rewrite historical decisions.
  - Add the actual current bridge/state-machine architecture as a new ADR.
  - Correct README/CONTRIBUTING claims or implement the stated DocC/Codecov/review controls.
  - Extend release/config validation with narrow assertions for high-value documentation claims.
- **Incorrect fixes to avoid**: Do not delete ADR history without preserving decision provenance, and do not change code solely to match a stale document.
- **Residual risk after fix**: Documentation can drift again; designate owners and review docs in the same change as architecture/CI modifications.
- **Priority / SLA suggestion**: Wave 2; correct before onboarding contributors or changing bridge/tunnel architecture.
- **Confidence**: CONFIRMED
- **Effort**: S

### [INFO] App-icon generator is an unreferenced manual tool with an undeclared dependency
- **ID**: DEAD-003
- **Category**: Dead code
- **CWE / OWASP / ASVS**: N/A
- **Location**: `scripts/create_icon.py:L1-L6,L112-L147`; `Resources/AppIcon.iconset/icon_16x16.png` and sibling tracked icon assets
- **Evidence**:
  - The script imports Pillow and writes the complete `Resources/AppIcon.iconset` (`scripts/create_icon.py:L4-L6,L112-L147`).
  - Repository-wide `rg` found no `create_icon.py` or `create_location_icon` reference outside the script.
  - Generated PNG assets and `Resources/AppIcon.icns` are already tracked; Pillow is not declared in `requirements-pathchanger.txt:L1-L17`.
- **Description**: This appears to be a one-time/manual asset generator retained without documentation or a reproducible development dependency.
- **Preconditions**: It may still be intentionally run manually; no CI/config reference proves non-use.
- **Impact**: Minimal security impact. It creates dependency ambiguity and a maintenance path that can regenerate branded assets non-deterministically across Pillow versions.
- **Exploitability analysis**: None established.
- **Why scanners may miss this**: Manual asset-generation tools can be intentionally unreferenced.
- **Chaining**: None.
- **Recommended fix** (preferred + alternatives):
  - **CANDIDATE-UNUSED — NEEDS MANUAL WORKFLOW CONFIRMATION.**
  - If obsolete, remove it in a focused change while retaining reviewed generated assets.
  - If retained, document its invocation, pin Pillow in a separate developer-tool requirements lock, and verify generated output deterministically.
- **Incorrect fixes to avoid**: Do not add Pillow to the runtime dependency graph solely to justify a manual tool.
- **Residual risk after fix**: Generated binary assets still require review when intentionally changed.
- **Priority / SLA suggestion**: Wave 3 / backlog.
- **Confidence**: LIKELY
- **Effort**: S

## 7. Vulnerability chains

### Chain A: Write-capable account compromise → direct `main` update → release artifact modification
A push-capable administrator credential can update unprotected `main` without the review/check policy documented in `CONTRIBUTING.md:L34-L38`. A subsequent release publication triggers a job with `contents: write` (`.github/workflows/release.yml:L13-L24`) that packages repository-controlled scripts and app code. Branch protection and protected release-environment approval break this chain at independent points.

### Chain B: Mutable package guidance → compromised dependency → paired-device control path
The pushed branch selects the latest accepted `pymobiledevice3` rather than an integrity-locked graph (`origin/feat/ui-redesign:README.md:L73-L79`). The app packages helpers and invokes the installed Python ecosystem for tunnel/device operations (`build-app-bundle.sh:L163-L181`). A compromised selected package therefore reaches local execution and a paired-device control context. Full hash locking, clean-environment CI, dependency monitoring, and least-privilege execution reduce this chain.

No project-specific zero-day-class weakness was claimed.

## 8. Dead code & unused surface report

### Dead / unused inventory

| ID | Symbol / path | Type | Evidence of non-use | Removal risk | Recommendation |
|---|---|---|---|---|---|
| DEAD-001 | `PathChanger/Device/CompanionHostService.swift` | CANDIDATE-UNUSED dormant network feature | No construction/reference outside its definition; root protocol import exists only here | Medium: separate iOS companion product and possible future wiring | Confirm roadmap; remove root host/dependency if abandoned, or productize with authentication/tests |
| DEAD-001A | Root `SharedCompanionProtocol` dependency | CANDIDATE unused dependency | Root target import is only in dormant host; separate companion package still uses it | Medium: deleting shared package would break companion | Remove only from root target if host is removed |
| DEAD-002 | ADR 001 persistent bridge decision | Stale accepted ADR | Named implementation deleted in `c1d550b`; path absent | Low: historical provenance | Mark superseded and link current architecture |
| DEAD-002A | ADR 003 state shape | Stale accepted ADR | State cases diverge from `PathChanger/Device/TunnelState.swift:L40-L46` | Low | Supersede/update with current state ownership |
| DEAD-003 | `scripts/create_icon.py` | CANDIDATE-UNUSED manual tool | No repository reference; outputs already tracked | Low: may be manual brand workflow | Confirm use; remove or document with dev-only lock |

No external SwiftPM dependency bloat was found in the opened manifests. The root package declares only the local shared protocol (`Package.swift:L13-L24`); the companion package also uses that local protocol (`PathChangerCompanion/Package.swift:L10-L19`).

### Complexity / unneeded surface reduction

- Resolve whether the companion feature is supported before retaining two discovery implementations, network-specific entitlements/comments, and a root dependency (`PathChanger/Device/CompanionHostService.swift:L17-L37`; `Resources/PathChanger.entitlements:L37-L63`).
- Keep asset-generation tooling separate from runtime Python dependencies (`scripts/create_icon.py:L4-L6`; `requirements-pathchanger.txt:L11-L17`).
- Supersede stale ADRs instead of allowing deleted dual-path designs to remain “Accepted” (`docs/adr/001-python-bridge-architecture.md:L3-L17`).

## 9. Bugs / mistakes / error-handling defects

No additional non-security correctness defect was established in the assigned Git/GitHub scope. Documentation/control mismatches are reported as DEAD-002 and VULN-001 rather than duplicated here.

## 10. Dependency & supply-chain notes

- **SwiftPM:** No remote Swift dependency is declared in the three opened manifests. Root and companion packages use a local shared protocol (`Package.swift:L13-L24`; `PathChangerCompanion/Package.swift:L10-L19`; `SharedCompanionProtocol/Package.swift:L11-L23`).
- **Python:** The GitHub branch has no committed reproducible dependency lock and uses an unconstrained upgrade command; local remediation is untracked and only directly pins one package without enforced transitive hashes (VULN-002).
- **CI tooling:** CI installs the current Homebrew SwiftLint formula rather than a repository-pinned version (`.github/workflows/ci.yml:L114-L118`). This is a reproducibility gap, but it is not elevated separately because SwiftLint runs in a read-only lint job with `contents: read` and no confirmed compromise.
- **GitHub monitoring:** Dependabot alerts are disabled. The security-advisory endpoint returned 404, so advisory state was not assertable.
- **Release integrity:** Release archives receive a generated SHA-256 file and are verified during validation (`.github/workflows/release-validation.yml:L112-L130`), but checksums hosted beside an artifact do not independently authenticate a compromised repository/release account.

## 11. Remediation roadmap

### Wave 0: emergency integrity controls

1. Protect `main`; require independent approval and all material CI checks.
2. Protect the release environment and minimize release-job permissions.
3. Commit a complete Python lock/hashing solution with the resolver/README update before the next release.

### Wave 1: high-risk design fixes

1. Enable secret scanning/push protection and dependency alerts.
2. Add clean-environment Python install/import/audit CI.
3. Add a read-only governance check for branch protection, required checks, and release-environment policy.

### Wave 2: hardening and dead-surface removal

1. Decide whether the companion host is supported; remove or securely productize it.
2. Supersede stale ADRs and correct DocC/Codecov/review statements.
3. Add key/signing/local-config ignore rules and incident-response guidance.

### Wave 3: long-term repository integrity

1. Separate UI changes from tunnel/subprocess/CI/release changes.
2. Add CODEOWNERS for workflows, release scripts, entitlements, subprocess policy, and dependency manifests.
3. Use signed tags/provenance attestations for release artifacts when the distribution model supports them.

## 12. Verification plan

### VULN-001

- Query `repos/abyssbugg/PathChanger/branches/main` and assert `protected=true`.
- Query rules/protection and assert required PR reviews, stale-review dismissal, force-push/deletion denial, and exact required CI contexts.
- Attempt a policy test with a disposable branch/PR; verify merge is blocked without approval and green checks.
- Require release-environment approval and confirm the release job cannot publish without it.

### VULN-002

- In a clean virtual environment, install with the committed lock and `--require-hashes`.
- Verify every direct/transitive artifact hash and exact version.
- Run dependency audit plus non-device `pymobiledevice3` import/version smoke tests.
- Add a test asserting UI/recovery instructions never contain `pip install -U pymobiledevice3`.
- Assert `requirements-pathchanger.txt` and any generated lock are tracked before release.

### VULN-003

- Seed scanner tests with nonfunctional canary signatures in each supported source type and a test-only PEM header; verify CI blocks them without printing values.
- Verify `.p12`, `.pfx`, `.pem`, `.key`, `.mobileprovision`, and local environment files are ignored unless explicitly allowlisted.
- Run a controlled full-history scan and store only redacted metadata.

### Pass I

- Add a compile/reference inventory for internal services.
- If removing companion host code, build/test the root and separate companion packages independently and inspect final entitlements.
- Validate documentation claims against workflow commands and current symbols.
- If retaining the icon generator, regenerate in a controlled environment and compare asset hashes.

### Metrics

- Percentage of protected default branches and required checks.
- Time from dependency advisory to reviewed pin update.
- Percentage of Python dependency artifacts with enforced hashes.
- Secret-scanner false-negative canary pass rate.
- Count and age of accepted ADRs that reference absent symbols.
- Count of candidate-unused modules/dependencies awaiting ownership decisions.

## 13. Residual risk & future-proofing

Branch protection does not eliminate administrator compromise; protect administrator identities with strong MFA/passkeys, narrow tokens, audit-log review, and independent release approval. Hash locks prevent silent artifact substitution but cannot prove benign upstream source; dependency provenance and least privilege still matter. Secret scanners are heuristic and cannot guarantee detection of encrypted, novel, or binary credentials.

Architectural invariants to preserve:

- No release reaches consumers without server-enforced independent review and green checks.
- No downloaded executable dependency is selected by an open-ended version range in production guidance.
- Secrets are never printed by scanners, and removal from the tip is never treated as removal from history.
- Dormant network/control features are removed or explicitly owned, authenticated, tested, and documented.
- Security-sensitive CI, entitlement, subprocess, tunnel, and dependency changes receive focused review rather than being hidden in broad UI changes.

Suggested ADRs:

- “Repository protection and release authority.”
- “Python dependency integrity, provenance, and update policy.”
- “Companion feature lifecycle and peer-authentication boundary.”

## 14. Missing context / questions that would change severity

- Whether GitHub organization-level policy exists outside the repository API responses. An enforced organization rule could reduce VULN-001.
- Whether branch/release protections are intentionally pending until a second trusted reviewer is added.
- Whether GitHub Advanced Security/secret scanning is available under the repository plan; `security_and_analysis: null` did not prove feature state.
- Whether a complete transitive Python lock exists outside the repository. A reviewed, enforced external lock could reduce VULN-002, though repository guidance would still be inconsistent.
- Whether `CompanionHostService` is instantiated by code/config outside the opened repository. Confirmed runtime wiring would remove the “unused” classification and require a separate peer-authentication review.
- Whether `scripts/create_icon.py` is part of an undocumented design-release workflow.

## Out-of-scope observations

The feature branch and working tree contain security-sensitive runtime changes in privileged path handling, subprocess execution, Wi-Fi pairing, tunneling, and UI/device state. Those surfaces were not deep-dived here because separate agents were assigned them. This report only uses those paths to characterize repository delta, dependency flow, and dead/unused surface.
