//
//  ConnectionSettingsMigration.swift
//  PathChanger
//
//  PathChanger offers two connection modes, USB and Wi-Fi, chosen by the user (owner
//  decisions 2026-11-06). Earlier builds stored two settings that could disagree:
//  `connectionMode` (Random, Auto, USB Only, WiFi Only) and `tunnelMode` (Auto,
//  USB (Lockdown), WiFi Only, Background Daemon). This migration rewrites both to the
//  same transport before either is read, and records a version marker.
//

import Foundation

enum ConnectionSettingsMigration {
    static let connectionModeKey = "connectionMode"
    static let tunnelModeKey = "tunnelMode"
    static let versionKey = "connectionSettingsVersion"
    static let currentVersion = 2

    /// The transport both settings name after the migration.
    enum Transport: Equatable {
        case usb
        case wifi

        /// Raw values the stored settings keep, so earlier builds can still read them.
        var connectionModeRawValue: String { self == .usb ? "USB Only" : "WiFi Only" }
        var tunnelModeRawValue: String { self == .usb ? "USB (Lockdown)" : "WiFi Only" }

        var title: String { self == .usb ? "USB" : "Wi\u{2011}Fi" }
    }

    struct Outcome: Equatable {
        let previousConnectionMode: String?
        let previousTunnelMode: String?
        let transport: Transport
    }

    /// The transport a stored pair migrates to (owner rules, 2026-11-06):
    /// - USB Only and WiFi Only are the user's explicit choice and keep their value,
    ///   whatever the tunnel mode says, Background Daemon included;
    /// - Random becomes the transport it last selected, which it wrote as the tunnel mode
    ///   (USB (Lockdown) or WiFi Only); with no usable tunnel mode, Wi-Fi;
    /// - Auto becomes Wi-Fi;
    /// - a missing or unknown connection mode keeps a legacy USB (Lockdown) tunnel mode,
    ///   which earlier builds stored on its own;
    /// - everything else, a fresh install included, becomes Wi-Fi.
    static func transport(connectionMode: String?, tunnelMode: String?) -> Transport {
        switch connectionMode {
        case "USB Only": return .usb
        case "WiFi Only": return .wifi
        case "Random": return lastSelectedTransport(tunnelMode: tunnelMode) ?? .wifi
        case "Auto": return .wifi
        default: return tunnelMode == Transport.usb.tunnelModeRawValue ? .usb : .wifi
        }
    }

    private static func lastSelectedTransport(tunnelMode: String?) -> Transport? {
        switch tunnelMode {
        case Transport.usb.tunnelModeRawValue: return .usb
        case Transport.wifi.tunnelModeRawValue: return .wifi
        default: return nil
        }
    }

    /// Rewrites both settings to one transport and sets the version marker. Runs when
    /// the marker is missing, and again whenever the stored pair is not an agreeing USB
    /// or Wi-Fi pair (an older build can still write a retired value); otherwise it
    /// changes nothing and returns nil, so it is safe to call more than once.
    @discardableResult
    static func migrate(
        _ defaults: UserDefaults,
        log: (String) -> Void = { Logger.info($0, category: .device) }
    ) -> Outcome? {
        let connectionMode = defaults.string(forKey: connectionModeKey)
        let tunnelMode = defaults.string(forKey: tunnelModeKey)
        let marked = defaults.integer(forKey: versionKey) >= currentVersion
        if marked, isAgreeingPair(connectionMode: connectionMode, tunnelMode: tunnelMode) {
            return nil
        }

        let transport = transport(connectionMode: connectionMode, tunnelMode: tunnelMode)
        defaults.set(transport.connectionModeRawValue, forKey: connectionModeKey)
        defaults.set(transport.tunnelModeRawValue, forKey: tunnelModeKey)
        defaults.set(currentVersion, forKey: versionKey)
        log("[Settings] Connection settings migrated: connectionMode \(connectionMode ?? "none"), "
            + "tunnelMode \(tunnelMode ?? "none") → \(transport.title)")
        return Outcome(previousConnectionMode: connectionMode, previousTunnelMode: tunnelMode, transport: transport)
    }

    /// The startup entry point both managers call before reading their setting. The
    /// app-hosted test suite runs inside the app and shares its preferences domain, so
    /// `.standard` is never migrated while hosting tests; injected suites always are.
    @discardableResult
    static func prepare(
        _ defaults: UserDefaults,
        isHostingTests: Bool = AppRuntimeEnvironment.isHostingTests,
        log: (String) -> Void = { Logger.info($0, category: .device) }
    ) -> Outcome? {
        if isHostingTests && defaults === UserDefaults.standard { return nil }
        return migrate(defaults, log: log)
    }

    private static func isAgreeingPair(connectionMode: String?, tunnelMode: String?) -> Bool {
        [Transport.usb, .wifi].contains {
            $0.connectionModeRawValue == connectionMode && $0.tunnelModeRawValue == tunnelMode
        }
    }
}
