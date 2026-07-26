# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **No release tags have been published yet.** The `1.0.0` entry below records a
> build that was never tagged in this repository, so there are no comparison links.
> Releases are cut by pushing a `vMAJOR.MINOR.PATCH` tag; see `DEPLOYMENT/README.md`.

## [Unreleased]

### Added

**Interface**
- Map-dominant, Apple-Maps-style application shell (`MainMapShell`)
- Design system with per-mode accent tokens and a mockup-aligned palette
- Component set: `ConnectionPill` (4-state connection indicator), `DeviceDropdown`,
  `ThemeToggle` (persisted dark/light override), `TelemetryBar`, `LibraryFlyout`
  (Favorites/History), `ModeControlPanel`, `PrimaryActionPill`, `CollapsibleSidebar`,
  `SidebarToggleButton`, `DeviceTunnelPill`
- Liquid Glass treatment on mode panels

**Transport and core**
- iOS 27 tunnel/RSD support and a persistent daemon tunnel mode
- Daemon-aware health monitoring; spoof persistence across RSD rotation
- Explicit tunnel state machine (`TunnelStateMachine`, `TunnelState`, `TunnelMode`, `TunnelInfo`)
- `AppState` split into focused extensions (orchestration, recovery/history,
  simulation mirrors, testing seams)
- `ServiceLevelObjectives`, `SubprocessPolicy`, `RuntimeOwnershipDeclarations`
- `LocationHistoryStore`, `AppStateStores`, `LegacyDocumentsMigration`
- `MultiDeviceCoordinator`

**Documentation**
- ADR 004 (security remediation and privilege boundary), ADR 005 (interim ad-hoc distribution)
- `SECURITY.md`, `.github/CODEOWNERS`, `.github/dependabot.yml`
- Six-agent security and code-integrity audit reports under `docs/audit/reports/`

### Security

Remediation of a 41-finding audit (0 Critical, 4 High, 14 Medium), landed in waves.
See [ADR 004](docs/adr/004-security-remediation-and-privilege-boundary.md).

- **Wave 0 — containment and governance.** Hash-enforced Python dependency lock
  (`requirements-pathchanger.lock`) installed with `--require-hashes --no-deps` and
  verified in CI; build/install workspaces moved to unique `mktemp` directories with
  post-copy signature re-verification, closing a bundle-substitution TOCTOU;
  fail-closed validation scripts; hardened `.gitignore` for signing material.
- **Wave 1 — privileged-path hardening (interim).** Reject privileged targets
  reachable through a group- or other-writable ancestor; prefer a root-owned pinned
  interpreter.
- **Wave 2 — attack-surface reduction.** Removed the dormant, unauthenticated
  MultipeerConnectivity companion host and its entitlements; GPX input caps,
  coordinate-bounds validation and context-correct parsing; bounded concurrent
  subprocess capture with SIGTERM→SIGKILL escalation; CI secret scanning (gitleaks,
  pinned and checksum-verified), entitlement policy gate, and pinned SwiftLint.
- **Wave 3 — cleanup.** Removed the build-excluded duplicate `Info.plist`,
  superseded stale ADRs, added CODEOWNERS.

### Changed
- SwiftLint in CI is now pinned and checksum-verified and can actually fail the
  build. It previously ran as `brew install swiftlint || true` followed by
  `swiftlint lint --quiet || true`, so the "Swift Lint" required check could never
  report failure.
- Release validation now validates an ad-hoc-signed zip plus SHA-256 manifest
  instead of a Developer-ID-signed, notarized DMG. See
  [ADR 005](docs/adr/005-interim-adhoc-distribution.md).
- Consolidated hardcoded port values into `AppConstants`; improved error messages
  with recovery actions.

### Fixed
- Two compile errors that blocked the release build: a six-term optional-coalescing
  chain in the tunneld API port fallback that exceeded the Swift type checker's
  expression budget, and a concurrent capture of a `weak self` var in the
  `DevLocationBridge` process termination handler.
- Device cache invalidation on tunnel disconnect; joystick diagonal movement speed
  consistency; GPX timestamp parsing fallbacks.

### Removed
- **Sparkle auto-update** and `PathChanger/Core/UpdaterController.swift`. Updates
  cannot be signed without a Developer ID, and an unsigned update channel is a
  worse risk than none. See [ADR 005](docs/adr/005-interim-adhoc-distribution.md).
- `PathChanger/Device/CompanionHostService.swift` — dormant, unauthenticated
  Multipeer listener (Wave 2), with its entitlements.
- `PathChanger/Core/CloudSync.swift` and `PathChanger/Core/HealthCheckServer.swift`
- `PathChanger/Core/StateManagers/` (`DeviceStateManager`, `RouteStateManager`,
  `SimulationStateManager`) — superseded by the `AppState` extensions
- `PathChanger/Device/PersistentLocationBridge.swift` — superseded by `LocationBridge`
- `PathChanger/UI/DeviceListView.swift` and `SidebarView.swift` — superseded by
  `PathChanger/UI/Components/`
- `DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md` through `05_UAT_SIGN_OFF.md` — they
  describe a Developer-ID/notarization release model that this repository no longer
  supports. Their absence is asserted by `scripts/validate-release-config.sh`;
  recover the content from `git show 75321f5:<path>` if signing is adopted.
- `Package.resolved` — the package no longer has external dependencies
- `.env.example`, `cleanup-project.sh`, and the duplicate `PathChanger/Info.plist`

## [1.0.0] - 2024-12-12

> Never tagged in this repository. Note that `DEPLOYMENT/04_PERFORMANCE_BASELINE.md`
> and `05_UAT_SIGN_OFF.md` date the same 1.0.0 build to December 2025; the
> discrepancy is unresolved and both are retained as historical records.

### Added
- Initial release of PathChanger
- Support for iOS device location simulation via USB and WiFi tunnels
- Multiple tunnel modes: USB, WiFi, Daemon, Auto
- GPX route import and playback
- Joystick-style manual location control
- Teleport to specific coordinates
- Multi-device support
- Persistent Python bridge for low-latency location updates
- Rate limiting and request queue management
- Health monitoring and automatic recovery
- macOS native SwiftUI interface
- Localization support (English, Japanese)

### Security
- Command validation for privileged operations
- Subprocess output size limiting
- Secure process ownership verification
- Input sanitization for coordinates and paths
