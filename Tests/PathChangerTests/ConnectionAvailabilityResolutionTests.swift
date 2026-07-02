//
//  ConnectionAvailabilityResolutionTests.swift
//  PathChangerTests
//
//  Regression coverage for the Connection Mode availability indicator. The
//  Wi-Fi availability badge must reflect that wireless connectivity is in use
//  when a wireless (daemon/Wi-Fi) tunnel is active — not only when device
//  discovery happens to label the device as `.wifi`. This fixes the case where
//  the cards showed "USB Available / Wi-Fi Unavailable" while the active tunnel
//  was the background daemon (wireless).
//

import XCTest
@testable import PathChanger

@MainActor
final class ConnectionAvailabilityResolutionTests: XCTestCase {

    func testDiscoveredWiFiDeviceIsAlwaysAvailable() {
        XCTAssertTrue(AppState.resolveWiFiAvailability(
            wifiDiscovered: true,
            isTunnelRunning: false,
            activeTransport: nil
        ))
    }

    func testDaemonActiveTunnelMarksWiFiAvailable() {
        XCTAssertTrue(AppState.resolveWiFiAvailability(
            wifiDiscovered: false,
            isTunnelRunning: true,
            activeTransport: .daemon
        ))
    }

    func testWiFiActiveTunnelMarksWiFiAvailable() {
        XCTAssertTrue(AppState.resolveWiFiAvailability(
            wifiDiscovered: false,
            isTunnelRunning: true,
            activeTransport: .wifi
        ))
    }

    func testUSBActiveTunnelDoesNotMarkWiFiAvailable() {
        XCTAssertFalse(AppState.resolveWiFiAvailability(
            wifiDiscovered: false,
            isTunnelRunning: true,
            activeTransport: .usb
        ))
    }

    func testNoTunnelAndNoWiFiDeviceIsNotAvailable() {
        XCTAssertFalse(AppState.resolveWiFiAvailability(
            wifiDiscovered: false,
            isTunnelRunning: false,
            activeTransport: nil
        ))
    }
}
