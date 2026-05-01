# Contributing to PathChanger

## Code Style

### SwiftLint Enforcement
- All Swift code must pass SwiftLint validation
- CI automatically runs `swiftlint lint` on every PR (see `.github/workflows/ci.yml`)
- Install locally: `brew install swiftlint`
- Run before committing: `swiftlint lint --strict`

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
- **Build**: Debug + Release configurations
- **Tests**: All unit tests must pass (100% pass rate required)
- **Coverage**: Generates report via `llvm-cov`, uploads to CodeCov
- **Lint**: SwiftLint validation
- **Security**: Secret scanning, entitlement validation
- **Documentation**: DocC build verification

### Review Process
- PRs target `main` or `develop` branches
- Require 1 approving review
- All CI checks must pass (green status)
- Address review feedback promptly

## Testing Requirements

### Standards
- **100% test pass rate** (82/82 tests passing)
- **>70% code coverage** maintained
- Add tests for new features/bug fixes

### Running Tests
```bash
# Run all tests
swift test

# Run with coverage
swift test --enable-code-coverage

# Generate HTML coverage report
./scripts/coverage.sh --html
```

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

- **Issues**: [GitHub Issues](https://github.com/yourusername/PathChanger/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/PathChanger/discussions)

---

**Thank you for contributing to PathChanger!**
