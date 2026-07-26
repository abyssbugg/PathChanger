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

    // MARK: Active tunnel — Connected (green) vs Active (grey)

    func testWiFiDaemonHealthyIsConnectedGreen() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Connected")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertEqual(presentation?.tone, .connected)
        XCTAssertTrue(presentation?.detail?.contains("background daemon tunnel") == true)
        XCTAssertTrue(presentation?.detail?.contains("Wi-Fi available") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("USB") == true)
    }

    func testWiFiDaemonNotHealthyIsActiveGrey() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Active")
        XCTAssertEqual(presentation?.tone, .active)
        XCTAssertTrue(presentation?.detail?.contains("background daemon tunnel") == true)
    }

    func testBothAvailableDetailShowsUSBPlusWiFi() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Connected")
        XCTAssertEqual(presentation?.tone, .connected)
        XCTAssertTrue(presentation?.detail?.contains("USB + Wi-Fi available") == true)
    }

    func testUSBHealthyIsConnectedWithLockdownDetail() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: false,
            isConnectionHealthy: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "USB Connected")
        XCTAssertEqual(presentation?.icon, "cable.connector")
        XCTAssertEqual(presentation?.tone, .connected)
        XCTAssertTrue(presentation?.detail?.contains("lockdown tunnel") == true)
        XCTAssertTrue(presentation?.detail?.contains("USB available") == true)
    }

    /// Regression: cable pulled but activeMode still `.usb` — must collapse to
    /// Wi-Fi and never claim USB.
    func testStaleUSBActiveModeCollapsesToWiFiWhenCableUnplugged() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Connected")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertFalse(presentation?.title.contains("USB") == true)
        XCTAssertFalse(presentation?.detail?.localizedCaseInsensitiveContains("USB") == true)
    }

    func testPreferredWiFiOverridesStaleUSBActiveMode() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            tunnelInfoMode: .wifi,
            preferredMode: .wifi,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Connected")
        XCTAssertEqual(presentation?.icon, "wifi")
    }

    // MARK: No tunnel — Not Connected (red) / No Connection (warning)

    func testWiFiAvailableNoTunnelIsNotConnectedRed() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "Wi-Fi Not Connected")
        XCTAssertEqual(presentation?.icon, "wifi")
        XCTAssertEqual(presentation?.tone, .notConnected)
        XCTAssertEqual(presentation?.detail, "Wi-Fi available")
    }

    func testUSBAvailableNoTunnelIsNotConnectedRed() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: true,
            isWiFiAvailable: false,
            isConnectionHealthy: false,
            preferUSBConnection: true
        )

        XCTAssertEqual(presentation?.title, "USB Not Connected")
        XCTAssertEqual(presentation?.icon, "cable.connector")
        XCTAssertEqual(presentation?.tone, .notConnected)
        XCTAssertEqual(presentation?.detail, "USB available")
    }

    func testNoConnectionWhenNothingAvailable() {
        let presentation = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: false,
            isWiFiAvailable: false,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(presentation?.title, "No Connection")
        XCTAssertEqual(presentation?.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(presentation?.tone, .warning)
        XCTAssertEqual(presentation?.detail, "connect USB or start tunnel")
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
