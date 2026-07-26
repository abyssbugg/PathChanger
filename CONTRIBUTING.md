# Contributing to PathChanger

## Code Style

### SwiftLint Enforcement
- All Swift code must pass SwiftLint validation. The *Swift Lint* check is required
  by branch protection and will fail the build.
- CI runs a **pinned, checksum-verified SwiftLint 0.65.0** (see the `lint` job in
  `.github/workflows/ci.yml`). Match that version locally or your results will
  differ from CI:

  ```bash
  brew install swiftlint            # convenient, but tracks whatever brew has
  swiftlint --version               # compare against the pin in ci.yml
  ```

- Run before committing: `swiftlint lint`

  Do **not** use `--strict` as a pre-commit gate. It promotes warnings to errors,
  and the codebase currently carries a large warning backlog. CI does not use it.
- The build fails on SwiftLint **errors** only. If you are adding a file, keep it
  under the `file_length` (1200) and `type_body_length` (600) error thresholds —
  see `Tests/PathChangerTests/TunneldManagerStopTunnelTests.swift` for the
  extension-split pattern used when a type outgrows them.

### Swift Conventions
- Follow Swift API Design Guidelines
- Use meaningful variable/function names
- Add documentation comments for public APIs
- Maintain existing architectural patterns (SwiftUI, Actors, Combine)

## Pull Request Process

### Before Submitting
1. Fork the repository and create a feature branch
2. Run tests locally: `swift test`
3. Verify SwiftLint passes: `swiftlint lint`
4. Check code coverage: `./scripts/coverage.sh`

### CI Pipeline
All PRs trigger automated checks (`.github/workflows/ci.yml`):
- **Build & Test**: Debug + Release builds, unit tests, app-bundle smoke test
- **Coverage**: exports `coverage.lcov` via `llvm-cov` as a build artifact. It is
  not uploaded to a coverage service and no coverage threshold is enforced in CI.
- **Swift Lint**: SwiftLint, pinned and checksum-verified. This gate fails the build.
- **Security Scan**: gitleaks secret scan and entitlement policy assertion
- **Python Dependency Lock**: hash-enforced install of `requirements-pathchanger.lock`
- **Build Documentation**: DocC build verification

Four of these are required by branch protection: *Build & Test*, *Python Dependency
Lock*, *Swift Lint*, *Security Scan*.

> A pull request that has merge conflicts will show **none** of these checks.
> GitHub cannot construct a merge ref for a conflicted PR, so the workflows never
> start and the required checks sit unreported rather than red. Rebase or merge
> `main` first, then look for the checks.

### Review Process
- PRs target `main`
- Require 1 approving review
- All required CI checks must pass (green status)
- Address review feedback promptly

## Testing Requirements

### Standards
- **100% test pass rate** — enforced by the *Build & Test* required check
- **Add tests for new features and bug fixes**
- **>70% code coverage** is a goal, not a gate. Nothing in CI enforces a coverage
  threshold today. `scripts/coverage.sh` accepts `--threshold N` if you want to
  check locally, and wiring it into CI is tracked as follow-up work — the number
  should be set from a measured baseline rather than asserted.

### Running Tests
```bash
# Run all tests (device-dependent tests are skipped by default in CI)
PATHCHANGER_RUN_DEVICE_TESTS=0 swift test

# Run with coverage
swift test --enable-code-coverage

# Generate HTML coverage report
./scripts/coverage.sh --html

# Check against a threshold locally
./scripts/coverage.sh --threshold 70
```

> **macOS sync folders break local builds.** If the repository lives in a folder
> synced by iCloud Drive, Dropbox, Google Drive or similar, the sync client
> attaches `com.apple.fileprovider.*`, `com.apple.FinderInfo` and `com.apple.macl`
> extended attributes to your files. `codesign` rejects these with *"resource fork,
> Finder information, or similar detritus not allowed"*, so `swift test` and
> `./build.sh` fail while CI passes. `xattr -c` cannot remove `com.apple.macl`.
> Clone into a non-synced directory such as `~/Developer/`.

### Test Suites
- Unit tests: `Tests/PathChangerTests/`
- Integration tests: Device/tunnel workflows
- Performance tests: Latency/memory benchmarks
- Security tests: Input validation, injection prevention

## Commit Format

Use **Conventional Commits** specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style (formatting, no logic change)
- `refactor`: Code restructuring
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

### Examples
```
feat(device): add iOS 18+ version detection

Implements version parsing in Device model and validation
in DevLocationBridge to detect unsupported iOS versions.

Closes #123
```

```
fix(tunnel): resolve race condition in device cache

Adds proper actor isolation to prevent concurrent access
issues in DeviceManager.

Fixes #456
```

## Good First Issues

New contributors can start with:
- **Add more preset locations** - Expand quick location library
- **Create sample GPX routes** - Add example routes for testing
- **UI/UX improvements** - Enhance interface polish
- **Performance optimizations** - Improve latency/memory usage
- **Documentation translations** - Add localization support

## Development Workflow

1. **Fork** the repository
2. **Create** feature branch: `git checkout -b feature/amazing-feature`
3. **Commit** changes: `git commit -m 'feat: add amazing feature'`
4. **Push** to branch: `git push origin feature/amazing-feature`
5. **Open** Pull Request with clear description

## Questions?

- **Issues**: [GitHub Issues](https://github.com/abyssbugg/PathChanger/issues)
- **Security reports**: see [SECURITY.md](SECURITY.md) — report privately, not via Issues

---

**Thank you for contributing to PathChanger!**
