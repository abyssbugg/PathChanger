//
//  ConnectionSummaryPresentationTests.swift
//  PathChangerTests
//
//  Regression coverage for the Settings connection summary. The summary must
//  distinguish transport availability/preference from the transport that
//  actually owns the active tunnel.
//

import XCTest
@testable import PathChanger

final class ConnectionSummaryPresentationTests: XCTestCase {

    func testWiFiActiveWinsOverUSBPreferenceAndAvailability() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .wifi,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Active")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertEqual(presentation?.tone, .primary)
        XCTAssertTrue(presentation?.detail?.contains("active tunnel") == true)
        XCTAssertTrue(presentation?.detail?.contains("USB available") == true)
        XCTAssertFalse(presentation?.title.contains("USB") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("cable") == true)
    }

    func testPreferredWiFiOverridesStaleUSBActiveModeInSettingsSummary() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            tunnelInfoMode: .wifi,
            preferredMode: .wifi,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Active")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertTrue(presentation?.detail?.contains("USB available") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("cable in use") == true)
    }

    func testDaemonActiveIsPresentedAsWirelessOwnership() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Active")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertEqual(presentation?.tone, .primary)
        XCTAssertTrue(presentation?.detail?.contains("background daemon tunnel") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("using cable") == true)
    }

    func testUSBActiveShowsCableInUse() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .wifi,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "USB Active")
        XCTAssertEqual(presentation?.icon, "cable.connector")
        XCTAssertEqual(presentation?.tone, .primary)
        XCTAssertEqual(presentation?.detail, "active tunnel · cable in use")
    }

    func testUnknownActiveTunnelDoesNotFallBackToStaleSelectedUSB() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: nil,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Tunnel Active")
        XCTAssertEqual(presentation?.icon, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(presentation?.tone, .secondary)
        XCTAssertFalse(presentation?.title.contains("USB") == true)
    }

    func testUSBPreferredWithoutActiveTunnelIsNotPresentedAsActive() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "USB Preferred")
        XCTAssertEqual(presentation?.icon, "cable.connector")
        XCTAssertEqual(presentation?.tone, .secondary)
        XCTAssertEqual(presentation?.detail, "USB available · not active")
    }

    func testNoConnectionRemainsExplicit() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: false,
            isWiFiAvailable: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "No Connection")
        XCTAssertEqual(presentation?.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(presentation?.tone, .warning)
        XCTAssertEqual(presentation?.detail, "connect USB or start tunnel")
    }

    /// Regression: when the cable has been pulled (or the session started
    /// over Wi-Fi) but `activeMode` still reports `.usb`, the Settings
    /// summary must NOT claim "USB Active · cable in use". Physical USB
    /// disconnect collapses the presentation to Wi-Fi.
    func testStaleUSBActiveModeCollapsesToWiFiWhenCableUnplugged() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Active")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertEqual(presentation?.tone, .primary)
        XCTAssertFalse(presentation?.title.contains("USB") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("cable") == true)
    }

    /// Regression: USB-active presentation remains correct when the cable IS
    /// physically connected, even if other inputs would otherwise prefer
    /// wireless. The guard must not over-trigger.
    func testUSBActivePresentationPreservedWhenCablePhysicallyConnected() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: false,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "USB Active")
        XCTAssertEqual(presentation?.icon, "cable.connector")
        XCTAssertEqual(presentation?.tone, .primary)
        XCTAssertEqual(presentation?.detail, "active tunnel · cable in use")
    }
}

final class ActiveTransportPresentationTests: XCTestCase {
    func testWiFiActiveWinsOverUSBSelectedAndAvailableInDevicePill() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .wifi,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation.title, "Wi-Fi Active")
        XCTAssertEqual(presentation.icon, "wifi")
        XCTAssertTrue(presentation.isActive)
    }

    func testPreferredWiFiOverridesStaleUSBActiveModeInDevicePill() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            tunnelInfoMode: .wifi,
            preferredMode: .wifi,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation.title, "Wi-Fi Active")
        XCTAssertEqual(presentation.icon, "wifi")
        XCTAssertTrue(presentation.isActive)
    }

    func testDaemonActivePresentsAsWirelessInDevicePill() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation.title, "Wi-Fi Active")
        XCTAssertEqual(presentation.icon, "wifi")
        XCTAssertTrue(presentation.isActive)
    }

    func testUSBAvailabilityIsNotActiveWithoutRunningTunnel() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: true,
            isWiFiAvailable: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation.title, "USB Preferred")
        XCTAssertEqual(presentation.icon, "cable.connector")
        XCTAssertFalse(presentation.isActive)
    }

    /// Regression: device-pill mirror of the cable-disconnected case. A
    /// stale `.usb` active mode must not appear as "USB Active" when the
    /// cable is no longer plugged in.
    func testStaleUSBActiveModeCollapsesToWiFiInDevicePillWhenCableUnplugged() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation.title, "Wi-Fi Active")
        XCTAssertEqual(presentation.icon, "wifi")
        XCTAssertTrue(presentation.isActive)
        XCTAssertFalse(presentation.title.contains("USB"))
    }

    /// Regression: device-pill USB-Active presentation remains correct when
    /// the cable IS physically connected; the new guard must not over-trigger.
    func testUSBActivePresentationPreservedInDevicePillWhenCableConnected() {
        let presentation = ActiveTransportPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: false,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation.title, "USB Active")
        XCTAssertEqual(presentation.icon, "cable.connector")
        XCTAssertTrue(presentation.isActive)
    }
}
