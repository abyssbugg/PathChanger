# PathChanger Authoritative Release Process (GitHub Direct)
This is the single source of truth for production release operations.
## Scope
PathChanger releases are distributed as GitHub release assets only:
- `PathChanger-<version>-macOS.zip`
- `PathChanger-<version>-macOS.sha256`
No alternative release path is supported by this repository.
## Release authority
The authoritative executable process is defined by:
- `.github/workflows/release.yml`
- `.github/workflows/release-validation.yml`
- `scripts/validate-release-config.sh`
If documentation and workflow behavior diverge, workflow + validation script are authoritative and documentation must be updated immediately.
## Release inputs
1. Create and push a semantic tag in the format `vMAJOR.MINOR.PATCH`.
2. Ensure `Resources/Info.plist` has:
   - `CFBundleShortVersionString` matching the tag version (without `v`)
   - numeric `CFBundleVersion`
3. Ensure repository validation passes:
   - `scripts/validate-release-config.sh`
## Build and package model
Release workflow performs:
1. Swift package resolution and release build.
2. App bundle assembly via `build-app-bundle.sh` using ad-hoc signing suitable for GitHub-direct distribution.
3. Bundle hygiene verification (codesign verification, framework embedding, xattr checks).
4. Artifact packaging as zip + checksum.
5. Upload of zip and checksum to the GitHub release.
## Local verification
Before creating a release tag, run:
```bash
chmod +x scripts/validate-release-config.sh
scripts/validate-release-config.sh
```
Optional local preflight:
```bash
chmod +x DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh
./DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh
```
## Consumer verification
After downloading a release:
```bash
shasum -a 256 -c PathChanger-<version>-macOS.sha256
```
If checksum validation fails, do not install the app.
## Change control
Any modification to release behavior must update, in the same change set:
1. `.github/workflows/release.yml`
2. `.github/workflows/release-validation.yml`
3. `scripts/validate-release-config.sh`
4. This document
## Document status
Authoritative and active.
