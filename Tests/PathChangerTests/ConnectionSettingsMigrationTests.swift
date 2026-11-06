//
//  ConnectionSettingsMigrationTests.swift
//  PathChangerTests
//
//  The one-time migration of the two stored connection settings (`connectionMode`,
//  `tunnelMode`) to the USB or Wi-Fi pair PathChanger offers (owner decision
//  2026-11-06). Every test uses a throwaway UserDefaults suite: the app-hosted suite
//  shares the app's own preferences domain, which must never be written from tests.
//

import XCTest
@testable import PathChanger

@MainActor
final class ConnectionSettingsMigrationTests: XCTestCase {
    /// One suite, emptied before each use: a suite per row would leave one empty plist
    /// behind in ~/Library/Preferences for every row of every run.
    private static let suiteName = "tmp_rovodev.pathchanger.connection-settings"

    override func tearDown() {
        Self.removeSuite()
        super.tearDown()
    }

    private static func removeSuite() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let file = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: file)
    }

    private func makeDefaults(connectionMode: String?, tunnelMode: String?) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        XCTAssertNil(defaults.string(forKey: "connectionMode"), "the suite starts empty")
        if let connectionMode { defaults.set(connectionMode, forKey: "connectionMode") }
        if let tunnelMode { defaults.set(tunnelMode, forKey: "tunnelMode") }
        return defaults
    }

    private struct Row {
        let connectionMode: String?
        let tunnelMode: String?
        let expected: ConnectionSettingsMigration.Transport
        let rule: String
    }

    private static let usbConnection = "USB Only"
    private static let wifiConnection = "WiFi Only"
    private static let usbTunnel = "USB (Lockdown)"
    private static let wifiTunnel = "WiFi Only"

    /// Every owner rule, one row each.
    private let rules: [Row] = [
        Row(connectionMode: nil, tunnelMode: nil, expected: .wifi, rule: "fresh install"),
        Row(connectionMode: "Auto", tunnelMode: "Auto", expected: .wifi, rule: "Auto"),
        Row(connectionMode: "Auto", tunnelMode: nil, expected: .wifi, rule: "Auto without a tunnel mode"),
        Row(connectionMode: "Auto", tunnelMode: usbTunnel, expected: .wifi, rule: "Auto with a USB tunnel mode"),
        Row(connectionMode: nil, tunnelMode: "Auto", expected: .wifi, rule: "tunnel Auto only"),
        Row(connectionMode: "Auto", tunnelMode: "Background Daemon", expected: .wifi, rule: "Daemon"),
        Row(connectionMode: nil, tunnelMode: "Background Daemon", expected: .wifi, rule: "Daemon only"),
        Row(connectionMode: usbConnection, tunnelMode: "Background Daemon", expected: .wifi, rule: "Daemon over USB Only"),
        Row(connectionMode: wifiConnection, tunnelMode: "Background Daemon", expected: .wifi, rule: "Daemon over Wi-Fi Only"),
        Row(connectionMode: "Random", tunnelMode: usbTunnel, expected: .usb, rule: "Random picked USB"),
        Row(connectionMode: "Random", tunnelMode: wifiTunnel, expected: .wifi, rule: "Random picked Wi-Fi"),
        Row(connectionMode: "Random", tunnelMode: nil, expected: .wifi, rule: "Random, no tunnel mode"),
        Row(connectionMode: "Random", tunnelMode: "Auto", expected: .wifi, rule: "Random, tunnel Auto"),
        Row(connectionMode: "Random", tunnelMode: "Background Daemon", expected: .wifi, rule: "Random, tunnel Daemon"),
        Row(connectionMode: "Random", tunnelMode: "Bogus", expected: .wifi, rule: "Random, unknown tunnel mode"),
        Row(connectionMode: usbConnection, tunnelMode: usbTunnel, expected: .usb, rule: "USB Only kept"),
        Row(connectionMode: usbConnection, tunnelMode: nil, expected: .usb, rule: "USB Only, no tunnel mode"),
        Row(connectionMode: usbConnection, tunnelMode: wifiTunnel, expected: .usb, rule: "USB Only wins over a Wi-Fi tunnel mode"),
        Row(connectionMode: usbConnection, tunnelMode: "Auto", expected: .usb, rule: "USB Only wins over tunnel Auto"),
        Row(connectionMode: wifiConnection, tunnelMode: wifiTunnel, expected: .wifi, rule: "Wi-Fi Only kept"),
        Row(connectionMode: wifiConnection, tunnelMode: nil, expected: .wifi, rule: "Wi-Fi Only, no tunnel mode"),
        Row(connectionMode: wifiConnection, tunnelMode: usbTunnel, expected: .wifi, rule: "Wi-Fi Only wins over a USB tunnel mode"),
        Row(connectionMode: nil, tunnelMode: usbTunnel, expected: .usb, rule: "only the tunnel mode: USB"),
        Row(connectionMode: nil, tunnelMode: wifiTunnel, expected: .wifi, rule: "only the tunnel mode: Wi-Fi"),
        Row(connectionMode: "Bogus", tunnelMode: usbTunnel, expected: .wifi, rule: "unknown connection mode"),
        Row(connectionMode: nil, tunnelMode: "Bogus", expected: .wifi, rule: "unknown tunnel mode"),
        Row(connectionMode: "Bogus", tunnelMode: "Bogus", expected: .wifi, rule: "both unknown"),
    ]

    func testEveryRuleWritesTheAgreeingPairAndTheMarker() throws {
        for row in rules {
            let defaults = try makeDefaults(connectionMode: row.connectionMode, tunnelMode: row.tunnelMode)
            var lines: [String] = []

            let outcome = ConnectionSettingsMigration.migrate(defaults, log: { lines.append($0) })

            XCTAssertEqual(outcome?.transport, row.expected, row.rule)
            XCTAssertEqual(defaults.string(forKey: "connectionMode"),
                           row.expected == .usb ? Self.usbConnection : Self.wifiConnection, row.rule)
            XCTAssertEqual(defaults.string(forKey: "tunnelMode"),
                           row.expected == .usb ? Self.usbTunnel : Self.wifiTunnel, row.rule)
            XCTAssertEqual(defaults.integer(forKey: "connectionSettingsVersion"), 2, row.rule)
            XCTAssertEqual(lines.count, 1, "one log line: \(row.rule)")
        }
    }

    func testTheStoredPairDecodesToTheSameTransportInBothManagers() throws {
        for row in rules {
            let defaults = try makeDefaults(connectionMode: row.connectionMode, tunnelMode: row.tunnelMode)
            ConnectionSettingsMigration.migrate(defaults, log: { _ in })

            let connection = try XCTUnwrap(
                DeviceManager.ConnectionMode(rawValue: defaults.string(forKey: "connectionMode") ?? ""), row.rule)
            let tunnel = try XCTUnwrap(TunnelMode(rawValue: defaults.string(forKey: "tunnelMode") ?? ""), row.rule)
            XCTAssertEqual(connection == .usb, tunnel == .usb, "both keys agree: \(row.rule)")
            XCTAssertTrue([DeviceManager.ConnectionMode.usb, .wifi].contains(connection), row.rule)
            XCTAssertTrue([TunnelMode.usb, .wifi].contains(tunnel), row.rule)
        }
    }

    func testASecondRunChangesNothingAndLogsNothing() throws {
        for row in rules {
            let defaults = try makeDefaults(connectionMode: row.connectionMode, tunnelMode: row.tunnelMode)
            ConnectionSettingsMigration.migrate(defaults, log: { _ in })
            let first = defaults.dictionaryRepresentation().filter { Self.keys.contains($0.key) }
            var lines: [String] = []

            let outcome = ConnectionSettingsMigration.migrate(defaults, log: { lines.append($0) })

            XCTAssertNil(outcome, row.rule)
            XCTAssertTrue(lines.isEmpty, row.rule)
            let second = defaults.dictionaryRepresentation().filter { Self.keys.contains($0.key) }
            XCTAssertEqual(NSDictionary(dictionary: first), NSDictionary(dictionary: second), row.rule)
        }
    }

    private static let keys: Set<String> = ["connectionMode", "tunnelMode", "connectionSettingsVersion"]

    func testAMarkedAgreeingPairIsLeftAlone() throws {
        let defaults = try makeDefaults(connectionMode: Self.usbConnection, tunnelMode: Self.usbTunnel)
        defaults.set(2, forKey: "connectionSettingsVersion")

        XCTAssertNil(ConnectionSettingsMigration.migrate(defaults, log: { _ in XCTFail("nothing to migrate") }))
        XCTAssertEqual(defaults.string(forKey: "connectionMode"), Self.usbConnection)
        XCTAssertEqual(defaults.string(forKey: "tunnelMode"), Self.usbTunnel)
    }

    /// An older build running beside this one can still write a retired value after the
    /// marker is set; the next launch normalizes it again instead of loading it.
    func testARetiredValueWrittenAfterTheMarkerIsNormalizedAgain() throws {
        let defaults = try makeDefaults(connectionMode: Self.usbConnection, tunnelMode: "Background Daemon")
        defaults.set(2, forKey: "connectionSettingsVersion")

        let outcome = ConnectionSettingsMigration.migrate(defaults, log: { _ in })

        XCTAssertEqual(outcome?.transport, .wifi)
        XCTAssertEqual(defaults.string(forKey: "connectionMode"), Self.wifiConnection)
        XCTAssertEqual(defaults.string(forKey: "tunnelMode"), Self.wifiTunnel)
    }

    func testAnUnmarkedAgreeingPairOnlyGainsTheMarker() throws {
        let defaults = try makeDefaults(connectionMode: Self.wifiConnection, tunnelMode: Self.wifiTunnel)

        let outcome = ConnectionSettingsMigration.migrate(defaults, log: { _ in })

        XCTAssertEqual(outcome?.transport, .wifi)
        XCTAssertEqual(defaults.string(forKey: "connectionMode"), Self.wifiConnection)
        XCTAssertEqual(defaults.string(forKey: "tunnelMode"), Self.wifiTunnel)
        XCTAssertEqual(defaults.integer(forKey: "connectionSettingsVersion"), 2)
    }

    func testTheLogLineNamesTheOldValuesAndTheResult() throws {
        let defaults = try makeDefaults(connectionMode: "Random", tunnelMode: Self.usbTunnel)
        var lines: [String] = []

        ConnectionSettingsMigration.migrate(defaults, log: { lines.append($0) })

        XCTAssertEqual(lines, [
            "[Settings] Connection settings migrated: connectionMode Random, tunnelMode USB (Lockdown) → USB"
        ])
        let fresh = try makeDefaults(connectionMode: nil, tunnelMode: nil)
        lines = []
        ConnectionSettingsMigration.migrate(fresh, log: { lines.append($0) })
        XCTAssertEqual(lines, [
            "[Settings] Connection settings migrated: connectionMode none, tunnelMode none → Wi\u{2011}Fi"
        ])
    }

    /// The app-hosted suite shares the app's own preferences domain: the startup entry
    /// point never migrates `.standard` while hosting tests.
    func testStartupNeverWritesTheStandardDomainWhileHostingTests() {
        XCTAssertNil(ConnectionSettingsMigration.prepare(.standard, isHostingTests: true, log: { _ in
            XCTFail("the app's own preferences must not be migrated by a test host")
        }))
    }

    func testStartupMigratesAnInjectedSuiteWhileHostingTests() throws {
        let defaults = try makeDefaults(connectionMode: "Auto", tunnelMode: "Auto")

        let outcome = ConnectionSettingsMigration.prepare(defaults, isHostingTests: true, log: { _ in })

        XCTAssertEqual(outcome?.transport, .wifi)
        XCTAssertEqual(defaults.string(forKey: "connectionMode"), Self.wifiConnection)
    }

    // MARK: Wiring: each manager migrates before it reads its key

    func testDeviceManagerMigratesBeforeReadingTheConnectionMode() throws {
        let defaults = try makeDefaults(connectionMode: "Random", tunnelMode: Self.usbTunnel)

        let manager = DeviceManager(startBackgroundServices: false, settings: defaults)

        XCTAssertEqual(manager.connectionMode, .usb, "Random is read as the transport it last picked")
        XCTAssertEqual(defaults.integer(forKey: "connectionSettingsVersion"), 2)
        XCTAssertEqual(defaults.string(forKey: "tunnelMode"), Self.usbTunnel)
    }

    func testDeviceManagerReadsAFreshInstallAsWiFi() throws {
        let defaults = try makeDefaults(connectionMode: nil, tunnelMode: nil)

        let manager = DeviceManager(startBackgroundServices: false, settings: defaults)

        XCTAssertEqual(manager.connectionMode, .wifi)
    }

    func testTunnelManagerMigratesBeforeReadingTheTunnelMode() throws {
        let defaults = try makeDefaults(connectionMode: "Auto", tunnelMode: "Background Daemon")

        XCTAssertEqual(TunneldManager.loadPreferredMode(from: defaults), .wifi)
        XCTAssertEqual(defaults.string(forKey: "connectionMode"), Self.wifiConnection)
        XCTAssertEqual(defaults.integer(forKey: "connectionSettingsVersion"), 2)
    }

    func testTunnelManagerKeepsAnExplicitUSBChoice() throws {
        let defaults = try makeDefaults(connectionMode: Self.usbConnection, tunnelMode: "Auto")

        XCTAssertEqual(TunneldManager.loadPreferredMode(from: defaults), .usb)
    }
}
