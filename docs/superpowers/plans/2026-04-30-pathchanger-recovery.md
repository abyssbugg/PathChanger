# PathChanger Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PathChanger` as the clean fixed version of `LocationSpoofer`, using GitHub as the canonical baseline, local copies as forensic evidence, and a new clean git history only after recovery verification.

**Architecture:** Use a clean-room recovery workflow: clone upstream into `.recovery/upstream`, extract source into `/Users/datamatics/Desktop/PathChanger`, audit local candidates separately, rename the product identity, run diagnostic-first build/test/package checks, document findings, then initialize a new repo. Do not directly rename or continue the dirty local `LocationSpoofer` checkout.

**Tech Stack:** Swift 5.9, Swift Package Manager, SwiftUI macOS app, Python/pymobiledevice3 runtime dependency, macOS app bundle packaging, Git.

---

## Source Spec

Implementation follows the approved design:

`/Users/datamatics/Desktop/PathChanger/docs/superpowers/specs/2026-04-30-pathchanger-recovery-design.md`

## Global Rules

- Treat `/Users/datamatics/Desktop/PathChanger` as the clean final workspace.
- Treat `https://github.com/abyssbugg/LocationSpoofer` as the upstream source reference.
- Treat `/Users/datamatics/Desktop/LocationSpoofer`, `/Users/datamatics/Desktop/changeit/LocationSpoofer`, `/Users/datamatics/Documents/LocationSpoofer`, and `/Users/datamatics/Desktop/LocationSpoofer.zip` as evidence only.
- Do not copy `.git`, `.build`, `.venv`, app bundles, `.dSYM`, logs, caches, or zip files into final source.
- Do not initialize git until the final cleanup task.
- Do not commit before recovery verification because the user explicitly requested clean new history after recovery.
- Do not push to any remote.
- Use `apply_patch` for manual text edits.
- Use shell commands for git, SwiftPM, archive extraction, build/test verification, and bulk filesystem operations that cannot be done with `apply_patch`.
- Never run `git reset --hard`, `git checkout --`, or destructive commands against the user's existing local copies.

## File Structure

### Temporary Recovery Files

- `.recovery/upstream/`: fresh GitHub clone used for baseline comparison.
- `.recovery/reports/`: command output captured during audits if needed.
- `.recovery/local-file-lists/`: generated lists for local candidates if needed.

These files are temporary and must not remain in final git history.

### Final Project Files

- `Package.swift`: Swift package identity, products, targets, dependencies, resources.
- `PathChanger/`: main app source directory after rename.
- `Tests/PathChangerTests/`: test target after rename.
- `Resources/`: app resources, `Info.plist`, entitlements, sample routes.
- `build-app-bundle.sh`: app bundle builder updated for PathChanger.
- `build.sh`: build helper updated for PathChanger if present.
- `install.sh`: install helper updated for PathChanger if present.
- `cleanup-project.sh`: cleanup helper updated or removed if obsolete.
- `.gitignore`: clean ignore rules for SwiftPM, macOS, Python, app bundles, logs, and recovery staging.
- `README.md`: PathChanger product documentation.
- `LICENSE`: original MIT license retained.
- `NOTICE.md`: attribution to the original LocationSpoofer repository.
- `docs/audit/github-baseline.md`: upstream baseline record.
- `docs/audit/local-candidates.md`: local evidence classification.
- `docs/audit/import-decisions.md`: keep/reject decisions for local files.
- `docs/rename-matrix.md`: old-to-new identity mapping and remaining old-name justifications.
- `docs/verification.md`: build, test, package, launch, dependency, and rename verification evidence.
- `docs/superpowers/specs/2026-04-30-pathchanger-recovery-design.md`: approved design.
- `docs/superpowers/plans/2026-04-30-pathchanger-recovery.md`: this implementation plan.

---

### Task 1: Prepare Clean Recovery Workspace

**Files:**
- Create: `.recovery/upstream/`
- Create: `.recovery/reports/`
- Create: `.recovery/local-file-lists/`

- [ ] **Step 1: Verify the final workspace exists and contains only planning docs**

Run:

```bash
ls -la "/Users/datamatics/Desktop/PathChanger"
```

Expected:

```text
docs
```

If other source files already exist, stop and inspect them before proceeding because the recovery workspace is no longer clean.

- [ ] **Step 2: Create recovery staging directories**

Run:

```bash
mkdir -p "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" "/Users/datamatics/Desktop/PathChanger/.recovery/reports" "/Users/datamatics/Desktop/PathChanger/.recovery/local-file-lists"
```

Expected: command exits with status `0`.

- [ ] **Step 3: Clone upstream into staging**

Run:

```bash
git clone --depth 1 https://github.com/abyssbugg/LocationSpoofer.git "/Users/datamatics/Desktop/PathChanger/.recovery/upstream"
```

Expected:

```text
Cloning into '/Users/datamatics/Desktop/PathChanger/.recovery/upstream'...
```

- [ ] **Step 4: Verify upstream commit**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" rev-parse HEAD
```

Expected:

```text
e8aa39f20a4b0e078245282967b8c9c791350f10
```

If GitHub has advanced, record the new SHA in `docs/audit/github-baseline.md` during Task 2 and continue from the fresh SHA.

- [ ] **Step 5: Extract upstream source into final workspace without `.git`**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" archive HEAD | tar -x -C "/Users/datamatics/Desktop/PathChanger"
```

Expected: upstream source files appear in `/Users/datamatics/Desktop/PathChanger` and `.git` is not created.

- [ ] **Step 6: Verify extraction did not overwrite planning docs**

Run:

```bash
test -f "/Users/datamatics/Desktop/PathChanger/docs/superpowers/specs/2026-04-30-pathchanger-recovery-design.md" && test -f "/Users/datamatics/Desktop/PathChanger/docs/superpowers/plans/2026-04-30-pathchanger-recovery.md"
```

Expected: command exits with status `0`.

---

### Task 2: Record GitHub Baseline

**Files:**
- Create: `docs/audit/github-baseline.md`
- Create: `.recovery/reports/upstream-files.txt`
- Create: `.recovery/reports/upstream-status.txt`

- [ ] **Step 1: Create audit docs directory**

Run:

```bash
mkdir -p "/Users/datamatics/Desktop/PathChanger/docs/audit"
```

Expected: command exits with status `0`.

- [ ] **Step 2: Capture upstream status**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" status --short --branch > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/upstream-status.txt"
```

Expected `upstream-status.txt` content begins with:

```text
## main...origin/main
```

- [ ] **Step 3: Capture upstream file list**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" ls-tree -r --name-only HEAD > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/upstream-files.txt"
```

Expected: file contains entries such as `Package.swift`, `README.md`, and source paths.

- [ ] **Step 4: Write `docs/audit/github-baseline.md`**

Use `apply_patch` to create:

```markdown
# GitHub Baseline Audit

Date: 2026-04-30

## Repository

- URL: `https://github.com/abyssbugg/LocationSpoofer`
- Default branch: `main`
- Baseline commit: `e8aa39f20a4b0e078245282967b8c9c791350f10`
- License: MIT
- Primary language: Swift

## Recovery Role

This repository is the canonical upstream reference for building PathChanger. The final PathChanger project is a clean recovered derivative with new project history after verification.

## Open Issues Considered

- `#1` Suggestion On-device spoofing: feature request, out of initial recovery scope.
- `#2` Can't open the app: launchability audit input for PathChanger recovery.

## Captured Evidence

- Upstream status: `.recovery/reports/upstream-status.txt`
- Upstream tracked files: `.recovery/reports/upstream-files.txt`
```

- [ ] **Step 5: Verify baseline doc exists**

Run:

```bash
test -f "/Users/datamatics/Desktop/PathChanger/docs/audit/github-baseline.md"
```

Expected: command exits with status `0`.

---

### Task 3: Audit Local LocationSpoofer Candidates

**Files:**
- Create: `docs/audit/local-candidates.md`
- Create: `.recovery/local-file-lists/desktop-locationspoofer-files.txt`
- Create: `.recovery/local-file-lists/changeit-locationspoofer-files.txt`
- Create: `.recovery/local-file-lists/documents-locationspoofer-files.txt`

- [ ] **Step 1: Capture Desktop candidate file list**

Run:

```bash
git -C "/Users/datamatics/Desktop/LocationSpoofer" ls-files --cached --modified --others --exclude-standard > "/Users/datamatics/Desktop/PathChanger/.recovery/local-file-lists/desktop-locationspoofer-files.txt"
```

Expected: file includes source names and local-only entries from `/Users/datamatics/Desktop/LocationSpoofer`.

- [ ] **Step 2: Capture Desktop candidate identity**

Run:

```bash
git -C "/Users/datamatics/Desktop/LocationSpoofer" rev-parse --show-toplevel && git -C "/Users/datamatics/Desktop/LocationSpoofer" rev-parse HEAD && git -C "/Users/datamatics/Desktop/LocationSpoofer" remote -v
```

Expected includes:

```text
/Users/datamatics/Desktop/LocationSpoofer
origin	https://github.com/abyssbugg/LocationSpoofer.git (fetch)
origin	https://github.com/abyssbugg/LocationSpoofer.git (push)
```

- [ ] **Step 3: Capture changeit candidate file list**

Run:

```bash
find "/Users/datamatics/Desktop/changeit/LocationSpoofer" -type f \( -name "*.swift" -o -name "Package.swift" -o -name "README.md" -o -name "*.md" -o -name "*.plist" -o -name "*.sh" \) -not -path "*/.build/*" -not -path "*/build/*" > "/Users/datamatics/Desktop/PathChanger/.recovery/local-file-lists/changeit-locationspoofer-files.txt"
```

Expected: file includes older source and documentation paths from the changeit copy.

- [ ] **Step 4: Capture Documents runtime data list**

Run:

```bash
find "/Users/datamatics/Documents/LocationSpoofer" -maxdepth 2 -type f > "/Users/datamatics/Desktop/PathChanger/.recovery/local-file-lists/documents-locationspoofer-files.txt"
```

Expected includes:

```text
/Users/datamatics/Documents/LocationSpoofer/routes.json
```

- [ ] **Step 5: Write `docs/audit/local-candidates.md`**

Use `apply_patch` to create:

```markdown
# Local Candidates Audit

Date: 2026-04-30

## Summary

PathChanger uses GitHub as the canonical baseline. Local LocationSpoofer items are audit evidence only until an import decision explicitly accepts a file.

## Candidates

| Path | Classification | Recovery Decision |
| --- | --- | --- |
| `/Users/datamatics/Desktop/LocationSpoofer` | GitHub-linked checkout at the observed upstream commit with local/untracked changes | Compare for useful local-only source and documentation; do not copy wholesale. |
| `/Users/datamatics/Desktop/changeit/LocationSpoofer` | Older or partial copy inside parent git context | Use only for forensic comparison; reject generated artifacts. |
| `/Users/datamatics/Documents/LocationSpoofer/routes.json` | Runtime/user route data | Do not import into source unless explicitly approved. |
| `/Users/datamatics/Desktop/LocationSpoofer.zip` | Archive artifact | Do not import into source; inspect only if source candidates are missing. |

## Evidence Files

- `.recovery/local-file-lists/desktop-locationspoofer-files.txt`
- `.recovery/local-file-lists/changeit-locationspoofer-files.txt`
- `.recovery/local-file-lists/documents-locationspoofer-files.txt`
```

- [ ] **Step 6: Verify local candidate docs exist**

Run:

```bash
test -f "/Users/datamatics/Desktop/PathChanger/docs/audit/local-candidates.md"
```

Expected: command exits with status `0`.

---

### Task 4: Establish Clean Ignore Rules

**Files:**
- Modify or create: `.gitignore`

- [ ] **Step 1: Replace `.gitignore` with clean recovery-safe rules**

Use `apply_patch` so `.gitignore` contains:

```gitignore
# macOS
.DS_Store
.AppleDouble
.LSOverride
Icon?

# Xcode / SwiftPM
.build/
.swiftpm/
DerivedData/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcworkspace/xcuserdata/
*.xcuserstate
*.xcuserdata/
Package.resolved

# Build outputs
build/
*.app/
*.dSYM/
*.ipa
*.dmg

# Python runtime/dependency tooling
.venv/
venv/
__pycache__/
*.pyc
.pytest_cache/

# Local environment and logs
.env
.env.*
!.env.example
*.log
*.tmp

# Recovery staging
.recovery/

# Archives
*.zip
*.tar
*.tar.gz
```

- [ ] **Step 2: Verify generated artifacts are ignored**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" check-ignore -v "/Users/datamatics/Desktop/PathChanger/.recovery/upstream/.build" || true
```

Expected: this command may not apply because it runs in upstream, but final verification after git init will use the PathChanger repo. Continue to Task 15 for final ignore verification.

---

### Task 5: Rename Filesystem Structure

**Files:**
- Move: `LocationSpoofer/` to `PathChanger/`
- Move: `Tests/LocationSpooferTests/` to `Tests/PathChangerTests/`
- Move if present: `LocationSpooferCompanion/` to `PathChangerCompanion/`
- Move if present: `LocationSpooferHelper/` to `PathChangerHelper/`
- Move if present: `Resources/LocationSpoofer.entitlements` to `Resources/PathChanger.entitlements`

- [ ] **Step 1: Rename main source directory**

Run:

```bash
mv "/Users/datamatics/Desktop/PathChanger/LocationSpoofer" "/Users/datamatics/Desktop/PathChanger/PathChanger"
```

Expected: command exits with status `0` and `PathChanger/` exists.

- [ ] **Step 2: Rename test directory**

Run:

```bash
mv "/Users/datamatics/Desktop/PathChanger/Tests/LocationSpooferTests" "/Users/datamatics/Desktop/PathChanger/Tests/PathChangerTests"
```

Expected: command exits with status `0` and `Tests/PathChangerTests/` exists.

- [ ] **Step 3: Rename companion directory when present**

Run:

```bash
if [ -d "/Users/datamatics/Desktop/PathChanger/LocationSpooferCompanion" ]; then mv "/Users/datamatics/Desktop/PathChanger/LocationSpooferCompanion" "/Users/datamatics/Desktop/PathChanger/PathChangerCompanion"; fi
```

Expected: command exits with status `0`.

- [ ] **Step 4: Rename helper directory when present**

Run:

```bash
if [ -d "/Users/datamatics/Desktop/PathChanger/LocationSpooferHelper" ]; then mv "/Users/datamatics/Desktop/PathChanger/LocationSpooferHelper" "/Users/datamatics/Desktop/PathChanger/PathChangerHelper"; fi
```

Expected: command exits with status `0`.

- [ ] **Step 5: Rename entitlements file when present**

Run:

```bash
if [ -f "/Users/datamatics/Desktop/PathChanger/Resources/LocationSpoofer.entitlements" ]; then mv "/Users/datamatics/Desktop/PathChanger/Resources/LocationSpoofer.entitlements" "/Users/datamatics/Desktop/PathChanger/Resources/PathChanger.entitlements"; fi
```

Expected: command exits with status `0`.

---

### Task 6: Rename Swift Package Manifest

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Read current manifest**

Run:

```bash
swift package dump-package --package-path "/Users/datamatics/Desktop/PathChanger" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/package-before-rename.json"
```

Expected: command exits with status `0` or fails with a manifest error that must be copied into `docs/verification.md` during Task 12.

- [ ] **Step 2: Update package identity**

Use `apply_patch` to make these replacements in `Package.swift`:

```swift
name: "PathChanger"
```

```swift
.executable(name: "PathChanger", targets: ["PathChanger"])
```

```swift
name: "PathChanger"
```

```swift
path: "PathChanger"
```

```swift
name: "PathChangerTests"
```

```swift
dependencies: ["PathChanger"]
```

```swift
path: "Tests/PathChangerTests"
```

- [ ] **Step 3: Verify manifest parses after rename**

Run:

```bash
swift package dump-package --package-path "/Users/datamatics/Desktop/PathChanger" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/package-after-rename.json"
```

Expected: command exits with status `0`.

---

### Task 7: Rename Source-Level App Identity

**Files:**
- Modify: `PathChanger/**/*.swift`
- Modify: `Tests/PathChangerTests/**/*.swift`
- Modify if present: `Resources/Info.plist`
- Modify if present: `PathChanger/Info.plist`
- Modify if present: `PathChanger/Resources/**/*.strings`

- [ ] **Step 1: Search source-level old names**

Run:

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer|Location Spoofer|location spoofer" "/Users/datamatics/Desktop/PathChanger" -g '!/.recovery/**'
```

Expected: matches appear before rename.

- [ ] **Step 2: Apply source identity replacements**

Use `apply_patch` to replace source references according to this mapping:

```text
LocationSpoofer -> PathChanger
locationspoofer -> pathchanger
Location Spoofer -> PathChanger
location spoofer -> PathChanger
com.locationspoofer -> com.pathchanger
LocationSpooferTests -> PathChangerTests
```

Do not replace references inside `docs/audit/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, or `NOTICE.md` because those files intentionally document provenance.

- [ ] **Step 3: Rename Swift app entry file when present**

Run:

```bash
if [ -f "/Users/datamatics/Desktop/PathChanger/PathChanger/LocationSpooferApp.swift" ]; then mv "/Users/datamatics/Desktop/PathChanger/PathChanger/LocationSpooferApp.swift" "/Users/datamatics/Desktop/PathChanger/PathChanger/PathChangerApp.swift"; fi
```

Expected: command exits with status `0`.

- [ ] **Step 4: Verify no old names remain outside provenance docs**

Run:

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer|Location Spoofer|location spoofer" "/Users/datamatics/Desktop/PathChanger" -g '!/.recovery/**' -g '!docs/audit/**' -g '!docs/superpowers/**' -g '!NOTICE.md'
```

Expected: no output. Any output must be fixed or documented in `docs/rename-matrix.md`.

---

### Task 8: Rename Build And Install Scripts

**Files:**
- Modify if present: `build-app-bundle.sh`
- Modify if present: `build.sh`
- Modify if present: `install.sh`
- Modify if present: `cleanup-project.sh`

- [ ] **Step 1: Search scripts for old names**

Run:

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer" "/Users/datamatics/Desktop/PathChanger" -g '*.sh' -g '!/.recovery/**'
```

Expected: script matches appear before patching.

- [ ] **Step 2: Patch script identity references**

Use `apply_patch` to apply this mapping in shell scripts:

```text
APP_NAME="LocationSpoofer" -> APP_NAME="PathChanger"
LocationSpoofer.app -> PathChanger.app
.build/release/LocationSpoofer -> .build/release/PathChanger
Resources/LocationSpoofer.entitlements -> Resources/PathChanger.entitlements
com.locationspoofer -> com.pathchanger
/tmp/locationspoofer -> /tmp/pathchanger
```

- [ ] **Step 3: Make scripts executable**

Run:

```bash
chmod +x "/Users/datamatics/Desktop/PathChanger/build-app-bundle.sh" 2>/dev/null || true; chmod +x "/Users/datamatics/Desktop/PathChanger/build.sh" 2>/dev/null || true; chmod +x "/Users/datamatics/Desktop/PathChanger/install.sh" 2>/dev/null || true; chmod +x "/Users/datamatics/Desktop/PathChanger/cleanup-project.sh" 2>/dev/null || true
```

Expected: command exits with status `0`.

- [ ] **Step 4: Verify scripts no longer contain product old names**

Run:

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer" "/Users/datamatics/Desktop/PathChanger" -g '*.sh' -g '!/.recovery/**'
```

Expected: no output.

---

### Task 9: Create Attribution And Rename Matrix Docs

**Files:**
- Create: `NOTICE.md`
- Create: `docs/rename-matrix.md`

- [ ] **Step 1: Create `NOTICE.md`**

Use `apply_patch` to create:

```markdown
# Notice

PathChanger is a clean recovered derivative of the open-source LocationSpoofer project.

Original project:

- Repository: `https://github.com/abyssbugg/LocationSpoofer`
- License: MIT
- Baseline commit used for recovery: `e8aa39f20a4b0e078245282967b8c9c791350f10`

PathChanger changes the project identity, performs recovery cleanup, and documents verification separately from the original upstream history.
```

- [ ] **Step 2: Create `docs/rename-matrix.md`**

Use `apply_patch` to create:

```markdown
# Rename Matrix

Date: 2026-04-30

## Product Identity

| Old | New | Status |
| --- | --- | --- |
| `LocationSpoofer` | `PathChanger` | Required in product/source/runtime identity. |
| `LocationSpoofer.app` | `PathChanger.app` | Required in app bundle output. |
| `LocationSpooferTests` | `PathChangerTests` | Required in SwiftPM test target. |
| `com.locationspoofer` | `com.pathchanger` | Required in bundle/helper/log namespaces. |
| `locationspoofer` | `pathchanger` | Required in lowercase paths, logs, labels, and temp files. |

## Allowed Remaining References

The old name may remain only in:

- `NOTICE.md`
- `docs/audit/`
- `docs/superpowers/specs/2026-04-30-pathchanger-recovery-design.md`
- `docs/superpowers/plans/2026-04-30-pathchanger-recovery.md`

## Validation Command

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer|Location Spoofer|location spoofer" /Users/datamatics/Desktop/PathChanger -g '!/.recovery/**' -g '!docs/audit/**' -g '!docs/superpowers/**' -g '!NOTICE.md'
```

Expected result: no output.
```

- [ ] **Step 3: Verify docs exist**

Run:

```bash
test -f "/Users/datamatics/Desktop/PathChanger/NOTICE.md" && test -f "/Users/datamatics/Desktop/PathChanger/docs/rename-matrix.md"
```

Expected: command exits with status `0`.

---

### Task 10: Rewrite README For PathChanger

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README title and clone instructions**

Use `apply_patch` to ensure the top of `README.md` begins with:

```markdown
# PathChanger

**GPS Location Simulation for iOS 17+ Devices**

PathChanger is a recovered and cleaned macOS application for simulating GPS locations on iOS devices for development and testing workflows. It is derived from the MIT-licensed LocationSpoofer project and has been renamed, audited, and documented as a clean standalone project.
```

- [ ] **Step 2: Replace build instructions**

Use `apply_patch` so installation examples use:

```bash
git clone <new-pathchanger-repository-url>
cd PathChanger
./build-app-bundle.sh
cp -R build/PathChanger.app /Applications/
open /Applications/PathChanger.app
```

Use the literal placeholder `<new-pathchanger-repository-url>` only in README because the new remote does not exist yet and the project must not push to a remote during recovery.

- [ ] **Step 3: Add attribution section**

Use `apply_patch` to add this section near the license section:

```markdown
## Attribution

PathChanger is a clean recovered derivative of `https://github.com/abyssbugg/LocationSpoofer`, which is distributed under the MIT License. See `NOTICE.md` for provenance details.
```

- [ ] **Step 4: Verify README has PathChanger product name**

Run:

```bash
rg -n "# PathChanger|PathChanger.app|NOTICE.md" "/Users/datamatics/Desktop/PathChanger/README.md"
```

Expected: at least three matching lines.

---

### Task 11: Build Diagnostics Before Fixes

**Files:**
- Create or append: `docs/verification.md`
- Create: `.recovery/reports/swift-build-debug.log`
- Create: `.recovery/reports/swift-build-release.log`
- Create: `.recovery/reports/swift-test.log`

- [ ] **Step 1: Create initial verification document**

Use `apply_patch` to create:

```markdown
# Verification Report

Date: 2026-04-30

## Commands

Verification commands are run from `/Users/datamatics/Desktop/PathChanger`.

## Results

| Check | Command | Result | Notes |
| --- | --- | --- | --- |
| Swift package manifest | `swift package dump-package` | Pending | Execute in Task 6 and update this row with `Pass` or `Fail`. |
| Debug build | `swift build` | Pending | Execute in Task 11 and update this row with `Pass` or `Fail`. |
| Release build | `swift build -c release` | Pending | Execute in Task 11 and update this row with `Pass` or `Fail`. |
| Test suite | `swift test` | Pending | Execute in Task 11 and update this row with `Pass` or `Fail`. |
| App bundle | `./build-app-bundle.sh` | Pending | Execute in Task 13 and update this row with `Pass` or `Fail`. |
| Rename scan | `rg old names` | Pending | Execute in Task 16 and update this row with `Pass` or `Fail`. |

## GitHub Issue #2 Launchability Audit

The upstream issue `#2` reports that the app cannot be opened. PathChanger must verify app bundle structure, `Info.plist`, executable path, signing state, and quarantine behavior before launchability is considered fixed.
```

- [ ] **Step 2: Run debug build**

Run:

```bash
swift build --package-path "/Users/datamatics/Desktop/PathChanger" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/swift-build-debug.log" 2>&1
```

Expected: command exits with status `0`. If it fails, read the log completely and do not patch until root cause is documented.

- [ ] **Step 3: Run release build**

Run:

```bash
swift build -c release --package-path "/Users/datamatics/Desktop/PathChanger" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/swift-build-release.log" 2>&1
```

Expected: command exits with status `0`. If it fails, read the log completely and do not patch until root cause is documented.

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --package-path "/Users/datamatics/Desktop/PathChanger" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/swift-test.log" 2>&1
```

Expected: command exits with status `0` or produces failures classified in `docs/verification.md`.

- [ ] **Step 5: Update verification document with actual results**

Use `apply_patch` to replace each `Pending` result in `docs/verification.md` with `Pass` or `Fail`. For every `Fail`, add the exact first failing compiler or test error in the `Notes` column.

---

### Task 12: Root-Cause Fix Build And Test Failures

**Files:**
- Modify only files implicated by build/test evidence.
- Modify: `docs/verification.md`

- [ ] **Step 1: Read failure logs when a command fails**

Run:

```bash
open -a TextEdit "/Users/datamatics/Desktop/PathChanger/.recovery/reports/swift-build-debug.log" || true
```

Expected: log opens for review, or command exits with status `0` without opening in headless environments.

- [ ] **Step 2: Identify one root cause**

Write the hypothesis into `docs/verification.md` using this exact format:

```markdown
### Build/Test Failure Hypothesis

- Failing command: `swift build --package-path /Users/datamatics/Desktop/PathChanger`
- First error: paste the first compiler, linker, manifest, or test assertion error line exactly as it appears in the relevant `.recovery/reports/*.log` file.
- Suspected root cause: name one concrete file and state why that file is responsible for the error.
- Minimal fix: state one concrete edit that removes the root cause without unrelated cleanup.
```

If the failing command is not `swift build --package-path /Users/datamatics/Desktop/PathChanger`, replace only that command value with the actual failing command. Do not patch until the other three lines contain real evidence from the log.

- [ ] **Step 3: Patch one root cause**

Use `apply_patch` to modify only the file named in the hypothesis. Do not bundle unrelated cleanup.

- [ ] **Step 4: Re-run the failing command**

Run the exact command from the hypothesis.

Expected: the previous failure is gone. If a new failure appears, add a new hypothesis entry before patching again.

- [ ] **Step 5: Re-run full local verification after each successful fix**

Run:

```bash
swift build --package-path "/Users/datamatics/Desktop/PathChanger" && swift test --package-path "/Users/datamatics/Desktop/PathChanger"
```

Expected: both commands pass, or any failure is documented with a new root-cause hypothesis.

---

### Task 13: App Bundle And Launchability Verification

**Files:**
- Modify if needed: `build-app-bundle.sh`
- Modify if needed: `Resources/Info.plist`
- Modify if needed: `PathChanger/Info.plist`
- Modify: `docs/verification.md`

- [ ] **Step 1: Run app bundle script**

Run:

```bash
cd "/Users/datamatics/Desktop/PathChanger" && ./build-app-bundle.sh > ".recovery/reports/app-bundle.log" 2>&1
```

Expected: command exits with status `0` and creates `build/PathChanger.app`.

- [ ] **Step 2: Verify app bundle structure**

Run:

```bash
test -d "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/MacOS" && test -f "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/Info.plist" && find "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/MacOS" -type f
```

Expected: output includes a `PathChanger` executable inside `Contents/MacOS`.

- [ ] **Step 3: Inspect bundle identifier and executable name**

Run:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleName" "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/Info.plist" && /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/Info.plist" && /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app/Contents/Info.plist"
```

Expected:

```text
PathChanger
PathChanger
com.pathchanger
```

If the bundle identifier includes a suffix such as `com.pathchanger.app`, document the exact value in `docs/verification.md` and ensure source/scripts agree with it.

- [ ] **Step 4: Check signing status**

Run:

```bash
codesign --verify --deep --strict --verbose=2 "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/codesign-verify.log" 2>&1
```

Expected: command exits with status `0`, or verification failure is documented with the exact `codesign` message.

- [ ] **Step 5: Check quarantine attribute**

Run:

```bash
xattr -l "/Users/datamatics/Desktop/PathChanger/build/PathChanger.app" > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/xattr-app.log" 2>&1 || true
```

Expected: no `com.apple.quarantine` attribute for locally built app. If present, document it as a launchability risk.

- [ ] **Step 6: Update GitHub issue #2 section**

Use `apply_patch` to update `docs/verification.md` with bundle structure, executable, identifier, signing, quarantine, and launchability result.

---

### Task 14: Dependency And Device Workflow Diagnostics

**Files:**
- Modify: `docs/verification.md`
- Create: `.recovery/reports/python-version.log`
- Create: `.recovery/reports/pymobiledevice3-version.log`
- Create: `.recovery/reports/pymobiledevice3-usbmux.log`

- [ ] **Step 1: Check Python version**

Run:

```bash
python3 --version > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/python-version.log" 2>&1
```

Expected: Python version is `3.9` or newer.

- [ ] **Step 2: Check pymobiledevice3 availability**

Run:

```bash
python3 -m pymobiledevice3 version > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/pymobiledevice3-version.log" 2>&1
```

Expected: command exits with status `0`. If missing, document dependency failure and exact installation command from README.

- [ ] **Step 3: Check USB device listing command**

Run:

```bash
python3 -m pymobiledevice3 usbmux list > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/pymobiledevice3-usbmux.log" 2>&1 || true
```

Expected: command either lists devices or reports no connected devices. Treat no device as an environment condition, not a source failure.

- [ ] **Step 4: Document dependency results**

Use `apply_patch` to add this section to `docs/verification.md` with actual command outcomes:

```markdown
## Runtime Dependency Diagnostics

| Check | Result | Evidence |
| --- | --- | --- |
| Python version | Pending | `.recovery/reports/python-version.log` |
| pymobiledevice3 version | Pending | `.recovery/reports/pymobiledevice3-version.log` |
| usbmux device listing | Pending | `.recovery/reports/pymobiledevice3-usbmux.log` |
```

Replace each `Pending` value with one of these exact outcomes after reading the evidence file: `Pass`, `Fail`, or `No Device`. Use `No Device` only for `usbmux device listing` when the command works but reports that no iOS device is connected.

---

### Task 15: Local Import Decisions

**Files:**
- Create: `docs/audit/import-decisions.md`
- Modify source files only if a local candidate is accepted after comparison.

- [ ] **Step 1: Compare Desktop local-only files to clean PathChanger**

Run:

```bash
comm -23 <(cd "/Users/datamatics/Desktop/LocationSpoofer" && git ls-files --others --exclude-standard | sort) <(cd "/Users/datamatics/Desktop/PathChanger/.recovery/upstream" && git ls-tree -r --name-only HEAD | sort) > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/desktop-local-only-files.txt"
```

Expected: file lists local-only files from the Desktop checkout.

- [ ] **Step 2: Compare changed tracked files in Desktop candidate**

Run:

```bash
git -C "/Users/datamatics/Desktop/LocationSpoofer" diff --name-status HEAD -- > "/Users/datamatics/Desktop/PathChanger/.recovery/reports/desktop-tracked-diff-name-status.txt"
```

Expected: file lists tracked modifications or is empty.

- [ ] **Step 3: Write import decisions document**

Use `apply_patch` to create:

```markdown
# Import Decisions

Date: 2026-04-30

## Rule

No local file is imported into PathChanger unless it is source, documentation, test, or configuration that improves the clean project and survives build/test/rename verification.

## Decisions

| Candidate Path | Decision | Reason |
| --- | --- | --- |
| `/Users/datamatics/Documents/LocationSpoofer/routes.json` | Reject from source | Runtime/user route data, not project source. |
| `/Users/datamatics/Desktop/LocationSpoofer.zip` | Reject from source | Archive artifact. |
| `/Users/datamatics/Desktop/changeit/LocationSpoofer/.build` | Reject from source | Generated SwiftPM build output. |
| `/Users/datamatics/Desktop/LocationSpoofer/.build` | Reject from source | Generated SwiftPM build output. |

## Evidence Files

- `.recovery/reports/desktop-local-only-files.txt`
- `.recovery/reports/desktop-tracked-diff-name-status.txt`
```

- [ ] **Step 4: For each accepted local source file, patch intentionally**

Use `apply_patch` to import the specific accepted code into the renamed `PathChanger` paths. After each accepted import, run:

```bash
swift build --package-path "/Users/datamatics/Desktop/PathChanger" && swift test --package-path "/Users/datamatics/Desktop/PathChanger"
```

Expected: build and tests pass, or failure is documented with a root-cause hypothesis in `docs/verification.md` before additional changes.

---

### Task 16: Final Rename And Cleanliness Verification

**Files:**
- Modify: `docs/rename-matrix.md`
- Modify: `docs/verification.md`

- [ ] **Step 1: Run old-name scan outside provenance docs**

Run:

```bash
rg -n "LocationSpoofer|locationspoofer|com\.locationspoofer|Location Spoofer|location spoofer" "/Users/datamatics/Desktop/PathChanger" -g '!/.recovery/**' -g '!docs/audit/**' -g '!docs/superpowers/**' -g '!NOTICE.md'
```

Expected: no output.

- [ ] **Step 2: Run generated artifact scan**

Run:

```bash
find "/Users/datamatics/Desktop/PathChanger" \( -path "*/.build" -o -path "*/.venv" -o -path "*/build" -o -name "*.app" -o -name "*.dSYM" -o -name "*.zip" \) -not -path "/Users/datamatics/Desktop/PathChanger/.recovery/*" -print
```

Expected: no output for final source files. If `build/PathChanger.app` exists from verification, remove it before final git initialization.

- [ ] **Step 3: Remove final build artifacts created by verification**

Run:

```bash
rm -rf "/Users/datamatics/Desktop/PathChanger/.build" "/Users/datamatics/Desktop/PathChanger/build" "/Users/datamatics/Desktop/PathChanger/.swiftpm"
```

Expected: command exits with status `0`.

- [ ] **Step 4: Re-run generated artifact scan**

Run:

```bash
find "/Users/datamatics/Desktop/PathChanger" \( -path "*/.build" -o -path "*/.venv" -o -path "*/build" -o -name "*.app" -o -name "*.dSYM" -o -name "*.zip" \) -not -path "/Users/datamatics/Desktop/PathChanger/.recovery/*" -print
```

Expected: no output.

- [ ] **Step 5: Update verification report with final scans**

Use `apply_patch` to add:

```markdown
## Final Cleanliness Verification

| Check | Result |
| --- | --- |
| Old product names outside provenance docs | Pass |
| Generated artifacts outside `.recovery` | Pass |
| Build artifacts removed before git init | Pass |
```

---

### Task 17: Initialize Clean New Git History

**Files:**
- Create: `.git/`

- [ ] **Step 1: Remove recovery staging before git init**

Run:

```bash
rm -rf "/Users/datamatics/Desktop/PathChanger/.recovery"
```

Expected: command exits with status `0`.

- [ ] **Step 2: Initialize new repository**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" init
```

Expected:

```text
Initialized empty Git repository in /Users/datamatics/Desktop/PathChanger/.git/
```

- [ ] **Step 3: Verify ignored artifacts are not tracked**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" status --short
```

Expected: source, docs, scripts, tests, `README.md`, `LICENSE`, `NOTICE.md`, and `.gitignore` appear as untracked files; `.recovery`, `.build`, `build`, `.venv`, app bundles, and zip files do not appear.

- [ ] **Step 4: Stage final project**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" add .
```

Expected: command exits with status `0`.

- [ ] **Step 5: Review staged files before first commit**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" diff --cached --name-status
```

Expected: only clean PathChanger source/docs/config files are listed.

- [ ] **Step 6: Create first clean commit**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" commit -m "Initial PathChanger recovery from LocationSpoofer baseline"
```

Expected: first commit succeeds.

- [ ] **Step 7: Verify final git status**

Run:

```bash
git -C "/Users/datamatics/Desktop/PathChanger" status --short --branch
```

Expected:

```text
## main
```

If git initializes with branch `master`, either leave it for the user to rename later or ask for approval before changing branch naming.

---

## Self-Review Notes

### Spec Coverage

- Clean source of truth from GitHub: Tasks 1 and 2.
- Local candidate audit: Tasks 3 and 15.
- Full project rename: Tasks 5 through 10 and 16.
- Unknown broken behavior audit: Tasks 11 through 14.
- Root-cause-only fixes: Task 12.
- Clean docs: Tasks 2, 3, 9, 10, 11, 15, and 16.
- New clean git history after recovery: Task 17.

### Placeholder Scan

The only literal placeholder intentionally present is `<new-pathchanger-repository-url>` in README instructions because no remote repository exists during recovery. It is explicitly explained in Task 10 and must not be used for code, build, or verification.

### Type And Name Consistency

- Package: `PathChanger`.
- Product: `PathChanger`.
- Main target: `PathChanger`.
- Test target: `PathChangerTests`.
- Bundle: `PathChanger.app`.
- Namespace: `com.pathchanger`.
