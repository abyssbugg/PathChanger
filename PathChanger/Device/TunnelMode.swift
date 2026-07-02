//
//  TunnelMode.swift
//  PathChanger
//

import Foundation

// MARK: - Tunnel Mode

/// Available tunnel connection modes for iOS 17+ devices.
///
/// `TunnelMode` defines the different methods for establishing a secure tunnel
/// to an iOS 17+ device. Each mode has different requirements and trade-offs.
///
/// ## Overview
///
/// Choose the appropriate mode based on your connection scenario:
///
/// | Mode | USB Required | Use Case |
/// |------|--------------|----------|
/// | Auto | Varies | Best for most users |
/// | USB | Yes | Fastest, most reliable |
/// | WiFi | No | Legacy manual-pairing Wi-Fi for iOS 17/18 |
/// | Daemon | No | Recommended wireless path for iOS 26+ |
///
/// ## Example
///
/// ```swift
/// let manager = TunneldManager()
/// manager.preferredMode = .wifi  // Set preferred mode
/// await manager.startTunnel(mode: .auto)  // Auto will respect preference
/// ```
enum TunnelMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case usb = "USB (Lockdown)"
    case wifi = "WiFi Only"
    case daemon = "Background Daemon"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .auto:
            return "Automatically select best method"
        case .usb:
            return "Fast tunnel via USB (lockdown start-tunnel)"
        case .wifi:
            return "Legacy manual-pairing Wi-Fi path for iOS 17/18"
        case .daemon:
            return "Recommended wireless mode for iOS 26+"
        }
    }


    var displayName: String {
        switch self {
        case .wifi:
            return "WiFi Only (Legacy)"
        default:
            return rawValue
        }
    }

    static func usesDaemonForModernWireless(
        requested mode: TunnelMode,
        targetIOSMajorVersion: Int?,
        targetConnectionType: ConnectionType?
    ) -> Bool {
        guard let targetIOSMajorVersion, targetIOSMajorVersion >= 26 else {
            return false
        }

        if mode == .wifi {
            return true
        }

        return mode == .auto && targetConnectionType == .wifi
    }

    static func effectiveMode(
        requested mode: TunnelMode,
        targetIOSMajorVersion: Int?,
        targetConnectionType: ConnectionType?
    ) -> TunnelMode {
        usesDaemonForModernWireless(
            requested: mode,
            targetIOSMajorVersion: targetIOSMajorVersion,
            targetConnectionType: targetConnectionType
        ) ? .daemon : mode
    }

    /// Whether the `.auto` path should back a modern device with the persistent
    /// `remote tunneld` daemon.
    ///
    /// Stability fix: a per-session `lockdown start-tunnel` child dies when the
    /// device sleeps/locks or the RSD drops, forcing a fresh admin-prompted
    /// restart. On iOS 26+, the auto path instead prefers the long-lived
    /// daemon, which keeps per-device tunnels alive, auto-recreates them on
    /// reconnect, and exposes the current RSD over its local HTTP API — so the
    /// app recovers by re-querying the API rather than re-prompting for admin.
    /// This applies regardless of whether the device is currently on USB or
    /// wireless; an explicitly-requested `.usb` mode still uses script-mode.
    static func prefersPersistentDaemon(forAutoTargetIOSMajorVersion targetIOSMajorVersion: Int?) -> Bool {
        guard let targetIOSMajorVersion, targetIOSMajorVersion >= 26 else {
            return false
        }
        return true
    }


    var command: [String] {
        switch self {
        case .auto:
            return [] // Determined at runtime
        case .usb:
            return ["lockdown", "start-tunnel"]
        case .wifi:
            return ["remote", "start-tunnel", "-t", "wifi"]
        case .daemon:
            return ["remote", "tunneld"]
        }
    }

    var processPattern: String {
        switch self {
        case .auto:
            return "pymobiledevice3" // Match any
        case .usb:
            return "pymobiledevice3 lockdown start-tunnel"
        case .wifi:
            return "pymobiledevice3 remote start-tunnel"
        case .daemon:
            return "pymobiledevice3 remote tunneld"
        }
    }
}

