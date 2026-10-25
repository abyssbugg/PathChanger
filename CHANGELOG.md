# Changelog

> **Status correction (2026-10-25):** this document predates the August-2026 audit
> lineage, which rates production-release confidence "not acceptable"
> (Consolidated-Source-Of-Truth-Aug-23-2026.md §A). Treat historical claims here as
> superseded by the audit lineage and the requirements ledger in
> docs/requirements-ledger-2026-10-25.md.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CI/CD pipeline with GitHub Actions
- Comprehensive error handling documentation
- Device cache race condition fixes with tunnel state observer
- GPX timestamp parsing with fallback formatters
- Joystick direction normalization for consistent movement speed
- Output size limiting for subprocess commands
- Centralized configuration constants

### Changed
- Consolidated hardcoded port values into AppConstants
- Improved error messages with recovery actions

### Fixed
- Device cache invalidation on tunnel disconnect
- Joystick diagonal movement speed consistency

## [1.0.0] - 2024-12-12

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

[Unreleased]: https://github.com/username/PathChanger/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/username/PathChanger/releases/tag/v1.0.0
