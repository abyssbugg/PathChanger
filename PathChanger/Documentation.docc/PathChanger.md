# ``PathChanger``

Location simulation toolkit for iOS devices using pymobiledevice3.

## Overview

PathChanger is a macOS application that enables GPS location spoofing on iOS devices. It provides multiple simulation modes including teleportation, route playback, and joystick-based movement control.

### Key Features

- **Teleport Mode**: Instantly set any GPS coordinate on your iOS device
- **Route Mode**: Play back GPX routes with configurable speed and looping
- **Joystick Mode**: Real-time movement control using keyboard or on-screen joystick
- **Multi-Device Support**: Works with both USB and WiFi-connected devices
- **Future-Compatible iOS Support**: Runtime capability probes select supported pymobiledevice3 providers without a hard-coded maximum iOS version

### Requirements

- macOS 14.0 or later
- Python 3.9+ with pymobiledevice3 installed
- iOS device with Developer Mode enabled

### iOS Version Compatibility

PathChanger is optimized for **iOS 17.0 through 17.6**. 

**iOS 18+ Limitations:**
- Location simulation may not work due to Apple's DVT service changes
- App automatically detects iOS 18+ and displays warnings
- See <doc:ErrorHandling> for troubleshooting steps

**Recommended Setup:**
- Use iOS 17.6 for best compatibility
- Enable Developer Mode (Settings → Privacy & Security)
- Keep pymobiledevice3 updated to latest version

## Topics

### Getting Started

- <doc:Installation>
- <doc:QuickStart>

### Core Components

- ``DevLocationBridge``
- ``DeviceManager``
- ``SimulationEngine``
- ``TunneldManager``

### Simulation Modes

- ``TeleportMode``
- ``RouteMode``
- ``JoystickMode``
- ``SimulationSpeed``

### Device Management

- ``Device``
- ``DeviceError``
- ``DeviceConnectionState``

### Location Types

- ``LocationCoordinate``
- ``LocationInjectionError``

### Configuration

- ``AppSettings``
- ``Constants``

### Reliability & Monitoring

- ``ReliabilityManager``
- ``RateLimiter``
- ``Logger``
