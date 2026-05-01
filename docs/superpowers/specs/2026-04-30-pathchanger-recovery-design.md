# PathChanger Recovery Design

Date: 2026-04-30

## Executive Summary

PathChanger is the clean recovered version of the LocationSpoofer project. It is not a cosmetic folder rename and it is not a direct continuation of the current messy local state. The project will be rebuilt from a verified GitHub baseline, audited against accessible local LocationSpoofer-related copies, renamed consistently, fixed through evidence-based diagnostics, and then initialized as a clean new repository history after recovery.

The original upstream project is `https://github.com/abyssbugg/LocationSpoofer`. It remains the source reference and attribution baseline. PathChanger becomes the new product identity and the clean future working project.

## Confirmed User Requirements

- The whole project name must become `PathChanger`.
- `PathChanger` is the fixed, clean version of the project.
- The existing local mess must not be blindly copied into the final project.
- The GitHub repository must be checked against all accessible local items named LocationSpoofer or locationspoofer.
- The current/fresh files must be identified against GitHub.
- The broken behavior is unknown, so the plan must audit everything.
- The final repository should have clean new project history after recovery.
- The plan must be highly technical, detailed, and professional.

## Current Inventory Findings

### Active Workspace

- Path: `/Users/datamatics/Desktop/PathChanger`
- Initial state: empty directory
- Initial git state: not a git repository

### GitHub Baseline

- Repository: `https://github.com/abyssbugg/LocationSpoofer`
- Default branch: `main`
- Observed GitHub `main` commit: `e8aa39f20a4b0e078245282967b8c9c791350f10`
- Language: Swift
- License: MIT
- Open GitHub issues observed:
  - `#1` Suggestion: on-device spoofing
  - `#2` Bug report: cannot open the app

### Local Candidates

1. `/Users/datamatics/Desktop/LocationSpoofer`
   - Real git checkout candidate.
   - Remote origin points to `https://github.com/abyssbugg/LocationSpoofer.git`.
   - HEAD observed at `e8aa39f20a4b0e078245282967b8c9c791350f10`, matching GitHub `main`.
   - Contains many untracked files relative to HEAD.
   - This is useful as local evidence, not as the clean final source tree.

2. `/Users/datamatics/Desktop/changeit/LocationSpoofer`
   - Older or partial copy inside a parent git context at `/Users/datamatics/Desktop/changeit`.
   - Parent repo has no commits at the time of inspection.
   - Package manifest is simpler and appears older than the Desktop checkout.
   - Useful as forensic reference only.

3. `/Users/datamatics/Documents/LocationSpoofer/routes.json`
   - Runtime or user route data.
   - Not source code.
   - May be migration data, sample data, or user state, but must not be imported into source without explicit intent.

4. `/Users/datamatics/Desktop/LocationSpoofer.zip`
   - Archive candidate.
   - Must be treated as an artifact until inspected.

## Source Of Truth Design

The authoritative source for recovery will be a fresh clone of the GitHub repository into a temporary audit location. The final PathChanger workspace will not be a direct rename of `/Users/datamatics/Desktop/LocationSpoofer` and will not be a direct import of `/Users/datamatics/Desktop/changeit/LocationSpoofer`.

The fresh clone provides the reproducible baseline. Local copies provide evidence for comparison. PathChanger becomes the clean product tree built from validated source and validated fixes.

## Recovery Architecture

The recovery will use four lanes.

### 1. Canonical Source Lane

Fresh clone `https://github.com/abyssbugg/LocationSpoofer` into a temporary audit area. Record commit SHA, file tree, package manifest, scripts, resources, tests, docs, and GitHub issue context.

### 2. Local Evidence Lane

Audit accessible local LocationSpoofer-related candidates as references only. Classify each file as one of:

- Same as GitHub baseline.
- Modified source candidate.
- New source candidate.
- Stale source candidate.
- Generated artifact.
- Build output.
- Runtime/user data.
- Documentation-only note.
- Discard candidate.

### 3. Clean Product Lane

Build `/Users/datamatics/Desktop/PathChanger` as the final clean project. The product lane receives only files that pass the audit and are intentionally renamed or fixed.

### 4. Verification Lane

Run build, test, packaging, launchability, dependency, and rename checks. Every failure must be categorized before any fix is applied.

## Rename Scope

The rename from LocationSpoofer to PathChanger must be technically consistent across product identity, source organization, runtime identifiers, documentation, tests, and packaging.

### Must Rename

- Swift package name.
- Executable product name.
- App bundle name.
- Source target name where practical.
- Test target name.
- Source folders where practical.
- `Info.plist` product and display names.
- Entitlements filenames and internal references.
- Helper tool names.
- Helper service labels.
- Launch daemon or launch agent labels, if present.
- Bundle identifiers.
- Log names.
- Temporary file paths.
- Build scripts.
- Install scripts.
- README and project documentation.
- User-facing application strings.
- Test references that assert names, paths, bundle identifiers, or UI text.

### May Retain With Explanation

- Attribution references to the original LocationSpoofer repository.
- MIT license provenance references.
- Audit reports referencing old local paths.
- Migration notes that explain the rename.

### Proposed Identity Mapping

| Old Identity | New Identity |
| --- | --- |
| `LocationSpoofer` | `PathChanger` |
| `LocationSpoofer.app` | `PathChanger.app` |
| `LocationSpooferTests` | `PathChangerTests` |
| `com.locationspoofer` | `com.pathchanger` |
| `locationspoofer` logs/paths | `pathchanger` logs/paths |
| LocationSpoofer helper labels | PathChanger helper labels |

The final bundle identifier namespace should use `com.pathchanger...` unless a later developer account or organization identifier requires a different namespace.

## Audit Strategy

Because the failure mode is unknown, the recovery must start with a full audit.

### Repository Cleanliness Audit

- Confirm no generated artifacts are imported into PathChanger.
- Confirm `.build`, `.venv`, `build`, app bundles, derived data, zip extracts, logs, and caches are excluded.
- Confirm `.gitignore` covers SwiftPM, macOS, Python tooling, app bundles, logs, local env files, and IDE noise.
- Confirm no secrets are present.

### Source Comparison Audit

- Compare fresh GitHub clone to `/Users/datamatics/Desktop/LocationSpoofer`.
- Compare fresh GitHub clone to `/Users/datamatics/Desktop/changeit/LocationSpoofer`.
- Classify every meaningful local difference.
- Reject compiled artifacts and generated test output.
- Flag local-only code that may contain fixes, enhancements, or stale experiments.

### Build System Audit

- Resolve Swift Package dependencies.
- Run debug build.
- Run release build.
- Run app bundle build script.
- Validate script path assumptions after rename.
- Validate optional dependencies such as Sparkle are handled deterministically.

### Test Suite Audit

- Run the Swift test suite.
- Classify failures as compile failures, deterministic test failures, snapshot failures, environment-dependent failures, device-dependent failures, or flaky tests.
- Avoid changing tests until the failure category and root cause are known.

### App Bundle And Launchability Audit

- Verify `.app` structure.
- Verify executable path.
- Verify `Info.plist` keys.
- Verify bundle identifier.
- Verify signing status.
- Check quarantine risks.
- Reproduce or analyze GitHub issue `#2` about app launch failure.

### Runtime Dependency Audit

- Verify Python version detection.
- Verify `pymobiledevice3` discovery.
- Verify pinned or expected version policy.
- Verify subprocess invocation safety.
- Verify error messages for missing dependencies.
- Verify environment propagation for app launches outside Terminal.

### Device Workflow Audit

- Audit device discovery.
- Audit pairing and Developer Mode expectations.
- Audit tunnel startup.
- Audit iOS version detection.
- Audit DVT location injection command construction.
- Audit route playback.
- Audit joystick mode.
- Audit clear-location behavior.
- Audit iOS 18+ warning and failure handling.

### Rename Validation Audit

After rename, search for:

- `LocationSpoofer`
- `locationspoofer`
- `location spoofer`
- `com.locationspoofer`

Every remaining hit must be intentional and documented.

## Fix Strategy

Fixing must follow root-cause debugging rules.

- No guessing.
- Reproduce or isolate failures first.
- Read build errors, test errors, and runtime logs fully.
- Compare broken behavior against working examples.
- Form one hypothesis at a time.
- Make the smallest correct change.
- Add or update tests where feasible.
- Verify before claiming a fix.

The initial implementation phase should not attempt to solve all possible feature requests. GitHub issue `#1` about on-device spoofing is out of scope for the first recovery unless the user explicitly expands scope later.

## Clean Repository Design

The final PathChanger repo should contain source, tests, docs, scripts, and verified configuration only.

### Include

- Swift package manifest.
- PathChanger app source.
- PathChanger tests.
- Resources required by the app.
- Build/install scripts that work after rename.
- README rewritten for PathChanger.
- `LICENSE` from original MIT project.
- `NOTICE.md` or README attribution to the original LocationSpoofer repo.
- Audit documentation.
- Rename matrix.
- Verification report.

### Exclude

- `.build`.
- `.venv`.
- `build` output.
- `.app` bundles.
- `.dSYM` bundles.
- DerivedData.
- Zip files.
- Logs.
- Local environment files.
- Python caches.
- SwiftPM local state.
- IDE workspace state unless intentionally shared.

## Documentation Deliverables

The recovery should produce these documents inside PathChanger:

- `docs/audit/github-baseline.md`
- `docs/audit/local-candidates.md`
- `docs/audit/import-decisions.md`
- `docs/rename-matrix.md`
- `docs/verification.md`
- `NOTICE.md` or an equivalent attribution section in `README.md`

The documents must explain what was kept, changed, rejected, and why.

## New Git History Strategy

PathChanger should become a new clean repository after recovery, not before.

Recommended sequence:

1. Build and verify the clean working tree.
2. Remove generated artifacts.
3. Confirm no old unwanted LocationSpoofer identifiers remain.
4. Initialize a new git repository in `/Users/datamatics/Desktop/PathChanger`.
5. Create the first commit as the clean recovered baseline.

Proposed first commit message:

```text
Initial PathChanger recovery from LocationSpoofer baseline
```

## Acceptance Criteria

PathChanger recovery is acceptable when all of the following are true:

- `/Users/datamatics/Desktop/PathChanger` contains a clean standalone project.
- Project identity is consistently `PathChanger`.
- The old `LocationSpoofer` name remains only in attribution, audit, or migration context.
- The app builds in debug mode or any build failure is fully documented with root cause.
- The app builds in release mode or any build failure is fully documented with root cause.
- The app bundle script creates `PathChanger.app` or any failure is fully documented with root cause.
- Tests pass or failures are categorized and documented.
- App launchability is verified or blocked by a documented environment/signing issue.
- GitHub issue `#2` is considered in the launchability audit.
- Local LocationSpoofer candidates are classified and documented.
- Runtime data in `/Users/datamatics/Documents/LocationSpoofer/routes.json` is not imported as source unless explicitly approved.
- Generated artifacts are excluded from the final repo.
- A clean new git history is initialized only after recovery cleanup.

## Out Of Scope For Initial Recovery

- Implementing on-device iOS-only spoofing from GitHub issue `#1`.
- Publishing a GitHub repository.
- Pushing to a remote.
- Code signing with a paid Apple Developer identity unless credentials and requirements are provided.
- Supporting unsupported iOS behavior beyond clear diagnostics and documented limitations.
- Importing private route data into source control without explicit approval.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| Local copies contain useful fixes hidden among artifacts | Perform structured diff and classify local-only files before rejecting them. |
| Rename breaks bundle scripts or SwiftPM targets | Use a rename matrix and run build/package verification after each major rename stage. |
| App cannot launch due to signing/quarantine | Audit `.app` structure, signing, quarantine attributes, and Info.plist metadata. |
| Device tests require hardware | Separate hardware-dependent checks from deterministic local tests and document blockers. |
| iOS 18+ DVT behavior causes silent failures | Preserve or improve explicit iOS version warnings and diagnostic messages. |
| Clean new repo loses provenance | Keep MIT license and attribution notice referencing the original upstream. |

## Next Step

After this design is reviewed and approved, create a detailed implementation plan. The implementation plan should break the work into ordered phases: fresh clone, local audit, clean import, rename, diagnostics, fixes, documentation, verification, and clean git initialization.
