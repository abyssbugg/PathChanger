# PathChanger — working notes for agents

macOS SwiftUI app that drives a paired iOS device through Python
`pymobiledevice3`. Parts of it run with administrator privileges. Read
`docs/adr/004-security-remediation-and-privilege-boundary.md` and
`docs/adr/005-interim-adhoc-distribution.md` before changing anything under
`PathChanger/Device/`, `PathChanger/Core/Privileged*`, `scripts/`, or `.github/`.

## Build and test

Swift Package Manager. There is no `.xcodeproj` — do not create one.

```bash
swift build -c debug
PATHCHANGER_RUN_DEVICE_TESTS=0 swift test
swiftlint lint                      # pinned 0.65.0 in CI; match it
scripts/validate-release-config.sh
scripts/validate-w1-convergence-lock.sh
```

**If the repo lives in an iCloud/Dropbox/Google-Drive-synced folder** (for example
under `~/Desktop`), the sync client attaches `com.apple.fileprovider.*`,
`com.apple.FinderInfo` and `com.apple.macl` xattrs to your files. `codesign` then
rejects the built bundle with *"resource fork, Finder information, or similar
detritus not allowed"* and every local build fails while CI passes. `xattr -c`
cannot remove `com.apple.macl`. Either clone into a non-synced directory, or keep
build products out of the synced tree:

```bash
swift test --scratch-path /tmp/pcbuild
```

## Hard constraints

- **Ad-hoc signing only.** No Developer ID, no notarization, no Sparkle, no
  `SMAppService`. Do not add code paths that need them — they cannot be built or
  tested here. ADR 005 lists the reversal criteria.
- **`scripts/validate-release-config.sh` is authoritative** over documentation, and
  it runs in the required *Build & Test* check. It asserts, among other things,
  that Sparkle wiring stays absent and that `DEPLOYMENT/02`–`05` do not exist. If
  you need to change release behaviour, change the workflow, the script, and
  `DEPLOYMENT/README.md` in the same commit.
- **`requirements-pathchanger.lock` is hash-enforced.** CI installs it with
  `--require-hashes --no-deps`. Bumping `requirements-pathchanger.txt` without
  regenerating the lock fails CI by design. Regenerate with `pip-compile
  --generate-hashes` and update the version assertion in `ci.yml` together.
- **`LocationBridge.BridgeRequest` / `BridgeResponse` `CodingKeys` are the wire
  protocol** with `scripts/location_bridge.py`. Renaming a property without
  updating its `CodingKeys` case silently breaks device communication.
- **CI runs `macos-26`.** `PathChanger/UI/DesignSystem.swift` uses Liquid Glass
  (`glassEffect`) behind `if #available(macOS 26.0, *)`. The guard controls runtime
  availability, not SDK contents, so an older image cannot compile the project.

## Conventions

- Conventional Commits (`feat(scope):`, `fix(scope):`, `docs:`, `test:`, `chore:`).
  See `CONTRIBUTING.md`.
- Architectural or security-relevant decisions get an ADR in `docs/adr/`. Record
  the *reason*, not just the change — the gap this repository actually had was
  enforcement without explanation.
- Large types are split into extensions across files rather than allowed to grow
  (`TunneldManager+*.swift`, `AppState+*.swift`, `TunneldManagerStopTunnelTests.swift`).
  SwiftLint errors at 1200 lines/file and 600 lines/type body.
- SwiftLint **errors** fail the build; warnings do not. There is a large warning
  backlog — do not run `--strict` as a gate, and do not silence a rule globally to
  make something pass. Existing `swiftlint:disable` comments carry an explicit
  per-site justification; match that.

## Gotchas

- `TunneldManagerTests` uses the `TunneldManager.shared` singleton, so tests can
  affect each other. `setUp`/`tearDown` reset lifecycle state.
- A pull request with merge conflicts shows **no** checks at all — GitHub cannot
  build a merge ref, so required checks sit unreported rather than red. Merge
  `main` first, then look for checks.
