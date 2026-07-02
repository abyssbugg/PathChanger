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
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(p?.title, "Wi-Fi Connected")
        XCTAssertEqual(p?.icon, "wifi")
        XCTAssertEqual(p?.tone, .connected)
        XCTAssertTrue(p?.detail?.contains("background daemon tunnel") == true)
        XCTAssertTrue(p?.detail?.contains("Wi-Fi available") == true)
        XCTAssertFalse(p?.detail?.localizedCaseInsensitiveContains("USB") == true)
    }

    func testWiFiDaemonNotHealthyIsActiveGrey() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(p?.title, "Wi-Fi Active")
        XCTAssertEqual(p?.tone, .active)
        XCTAssertTrue(p?.detail?.contains("background daemon tunnel") == true)
    }

    func testBothAvailableDetailShowsUSBPlusWiFi() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .daemon,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(p?.title, "Wi-Fi Connected")
        XCTAssertEqual(p?.tone, .connected)
        XCTAssertTrue(p?.detail?.contains("USB + Wi-Fi available") == true)
    }

    func testUSBHealthyIsConnectedWithLockdownDetail() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .usb,
            isUSBConnected: true,
            isWiFiAvailable: false,
            isConnectionHealthy: true,
            preferUSBConnection: true
        )

        XCTAssertEqual(p?.title, "USB Connected")
        XCTAssertEqual(p?.icon, "cable.connector")
        XCTAssertEqual(p?.tone, .connected)
        XCTAssertTrue(p?.detail?.contains("lockdown tunnel") == true)
        XCTAssertTrue(p?.detail?.contains("USB available") == true)
    }

    /// Regression: cable pulled but activeMode still `.usb` — must collapse to
    /// Wi-Fi and never claim USB.
    func testStaleUSBActiveModeCollapsesToWiFiWhenCableUnplugged() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: true,
            activeTunnelMode: .usb,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: true,
            preferUSBConnection: false
        )

        XCTAssertEqual(p?.title, "Wi-Fi Connected")
        XCTAssertEqual(p?.icon, "wifi")
        XCTAssertFalse(p?.title.contains("USB") == true)
        XCTAssertFalse(p?.detail?.localizedCaseInsensitiveContains("USB") == true)
    }

    func testPreferredWiFiOverridesStaleUSBActiveMode() {
        let p = ConnectionSummaryPresentation.resolve(
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

        XCTAssertEqual(p?.title, "Wi-Fi Connected")
        XCTAssertEqual(p?.icon, "wifi")
    }

    // MARK: No tunnel — Not Connected (red) / No Connection (warning)

    func testWiFiAvailableNoTunnelIsNotConnectedRed() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: .wifi,
            isUSBConnected: false,
            isWiFiAvailable: true,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(p?.title, "Wi-Fi Not Connected")
        XCTAssertEqual(p?.icon, "wifi")
        XCTAssertEqual(p?.tone, .notConnected)
        XCTAssertEqual(p?.detail, "Wi-Fi available")
    }

    func testUSBAvailableNoTunnelIsNotConnectedRed() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: true,
            isWiFiAvailable: false,
            isConnectionHealthy: false,
            preferUSBConnection: true
        )

        XCTAssertEqual(p?.title, "USB Not Connected")
        XCTAssertEqual(p?.icon, "cable.connector")
        XCTAssertEqual(p?.tone, .notConnected)
        XCTAssertEqual(p?.detail, "USB available")
    }

    func testNoConnectionWhenNothingAvailable() {
        let p = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: false,
            activeTunnelMode: nil,
            selectedConnectionType: nil,
            isUSBConnected: false,
            isWiFiAvailable: false,
            isConnectionHealthy: false,
            preferUSBConnection: false
        )

        XCTAssertEqual(p?.title, "No Connection")
        XCTAssertEqual(p?.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(p?.tone, .warning)
        XCTAssertEqual(p?.detail, "connect USB or start tunnel")
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
