# PathChanger

**Capability-based GPS location simulation for current and future iOS devices**

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

**Status: Not release-ready.** The feature branch remains under automated, visual, and physical acceptance. Do not publish a release until the ten-case USB/Wi-Fi matrix, interruption checks, signing, and evidence gates pass.

PathChanger is a macOS SwiftUI application backed by a managed, rolling-latest Python runtime that the app bootstraps itself (pyenv-first; no version pins or hash locks). Runtime support is selected by capability probes rather than a hard-coded maximum iOS or pymobiledevice3 version. Provider acknowledgements are the source of truth for applied location state.

## Five user modes

- **Teleport** — apply one selected target and hold it.
- **Jump** — apply an ordered list of discrete destinations one Move at a time; the index advances only after each successful injection.
- **Two-Spot** — move repeatedly between two acknowledged targets.
- **Multi-Spot** — play an ordered route of multiple targets.
- **Joystick** — move continuously from an acknowledged starting location.

Stop and Clear are different operations. Stop preserves the last acknowledged coordinate. Clear is destructive, requires explicit confirmation, and succeeds only after provider reset acknowledgement.

The binding mode contracts live in `PRODUCT_REQUIREMENTS.md` §2 (scope) and §3 (per-mode behavior).

## Device and iOS support

PathChanger attempts location simulation on every parseable iOS version — iOS 17 through 27 included — and hard-blocks none of them. iOS 18 and newer are surfaced as caution-only: the flag is advisory and never blocks injection. Simulation runs as a held session, so an applied coordinate stays active as long as PathChanger keeps the session open; Stop, Pause, and mode changes hold the spoof, and only explicit Clear/Reset ends it. This replaces the behavior of earlier pymobiledevice3 releases, which silently dropped simulation on iOS 18+ (upstream issue #1387).

Wi-Fi-prepared devices appear as Network connections and work through the same injection path. Device visibility depends on the phone staying unlocked, awake, and on the same network.

## Transport model

USB and Wi-Fi describe observed physical reachability. Direct lockdown, explicit RSD, native RSD, and userspace RSD describe the actual DVT service channel. Normal use applies the hybrid capability policy; strict diagnostics never silently substitute a requested channel.
## Build and install locally

Prerequisites are macOS 14 or newer, Xcode, an unlocked and trusted iOS device, and Developer Mode. PathChanger creates and validates its own managed runtime; do not install dependencies into Apple system Python.

```bash
./build-app-bundle.sh
```

The builder retains `build/PathChanger.app` and never modifies `/Applications`. Installation is a separate, explicit operation:

```bash
./install.sh
```

During agent-driven development, use FlowDeck for package resolution, builds, tests, launches, logs, and UI automation. Do not substitute raw Apple build or device commands.

## Testing

The suite is 30+ XCTest suites and 1000+ tests. Locally, run `./scripts/test.sh` — it wraps `swift test` with scratch-path and framework-linking workarounds for iCloud-synced checkouts — and during agent-driven development FlowDeck drives the same suite. The scheme's test action builds the `ReleaseTesting` configuration. A small number of tests require a physical device and stay skipped unless `PATHCHANGER_RUN_DEVICE_TESTS=1` is set explicitly.

## Verification

Before integration or release:

1. Run the complete `ReleaseTesting` suite.
2. Build a fresh local Release bundle from the exact tested commit.
3. Complete visual and accessibility review.
4. Exercise Teleport, Jump, Two-Spot, Multi-Spot, and Joystick over USB and Wi-Fi.
5. Verify Apply, Hold, Stop, explicit Clear, transport loss, helper recovery, and app relaunch.
6. Sanitize evidence and confirm local/remote Git identities.
7. Complete signing and notarization for distribution.

See `PRODUCT_REQUIREMENTS.md`, `DEPLOYMENT/README.md`, and `DEPLOYMENT/TUNNEL_MODES.md` for binding behavior and acceptance gates.

## License and provenance

PathChanger is derived from the original LocationSpoofer project. See `NOTICE.md` for attribution. Licensed under the MIT License; see `LICENSE`.