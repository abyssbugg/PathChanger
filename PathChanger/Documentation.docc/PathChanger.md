# ``PathChanger``

Location simulation toolkit for iOS devices using pymobiledevice3.

## Overview

PathChanger is a macOS application that enables GPS location simulation on iOS devices. It provides multiple simulation modes including teleportation, route playback, and joystick-based movement control.

### Key Features

- **Teleport Mode**: Instantly set any GPS coordinate on your iOS device
- **Route Mode**: Play back GPX routes with configurable speed and looping
- **Joystick Mode**: Real-time movement control using keyboard or on-screen joystick
- **Multi-Device Support**: Works with both USB and WiFi-connected devices
- **iOS 17+ Compatible**: Full support for modern iOS versions via pymobiledevice3

### Requirements

- macOS 14.0 or later
- Python 3.9+ with pymobiledevice3 installed
- iOS device with Developer Mode enabled

### iOS Version Compatibility

PathChanger is optimized for iOS 17 and attempts location simulation on newer iOS versions instead of blocking them.

**Newer iOS compatibility:**
- Location simulation may depend on upstream pymobiledevice3 support for Apple's DVT service changes
- App automatically detects newer iOS versions and displays warnings
- See <doc:ErrorHandling> for troubleshooting steps

**Recommended Setup:**
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
