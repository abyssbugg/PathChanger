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
- PathChanger-managed Python runtime with the required pymobiledevice3 capabilities
- iOS device with Developer Mode enabled and trusted by this Mac

### iOS Compatibility

PathChanger has no hard-coded maximum iOS version. It probes available pymobiledevice3 providers at runtime, records the physical transport and actual DVT channel independently, and fails with actionable diagnostics when a required capability is unavailable.

Unknown future iOS versions are evaluated by capability rather than rejected by version number. USB or Wi-Fi reachability does not itself prove that a location-service channel is available.

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
