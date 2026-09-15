# PathChanger

**Capability-based GPS location simulation for current and future iOS devices**

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

**Status: Not release-ready.** The feature branch remains under automated, visual, and physical acceptance. Do not publish a release until the ten-case USB/Wi-Fi matrix, interruption checks, signing, and evidence gates pass.

PathChanger is a macOS SwiftUI application backed by a managed, hash-verified Python runtime. Runtime support is selected by capability probes rather than a hard-coded maximum iOS or pymobiledevice3 version. Provider acknowledgements are the source of truth for applied location state.

## Five user modes

- **Teleport** — apply one selected target and hold it.
- **Jump** — apply a discrete jump with an explicit distance.
- **Two-Spot** — move repeatedly between two acknowledged targets.
- **Multi-Spot** — play an ordered route of multiple targets.
- **Joystick** — move continuously from an acknowledged starting location.

Stop and Clear are different operations. Stop preserves the last acknowledged coordinate. Clear is destructive, requires explicit confirmation, and succeeds only after provider reset acknowledgement.

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