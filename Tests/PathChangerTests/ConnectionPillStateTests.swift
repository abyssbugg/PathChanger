//
//  ConnectionPillStateTests.swift
//  PathChangerTests
//
//  Tests for the pure ConnectionPillState resolver backing the ConnectionPill
//  component (mockup `.conn-pill` port). Mirrors the 4-state model:
//  disconnected → connecting → usbActive → wifiActive.
//

import XCTest
@testable import PathChanger

final class ConnectionPillStateTests: XCTestCase {

    func testStartingAlwaysWinsOverRunning() {
        // While the tunnel is coming up, show Connecting even if a stale
        // isRunning signal is present.
        XCTAssertEqual(
            ConnectionPillState.resolve(isStarting: true, isRunning: true, transportIcon: "wifi"),
            .connecting
        )
        XCTAssertEqual(
            ConnectionPillState.resolve(isStarting: true, isRunning: false, transportIcon: "cable.connector"),
            .connecting
        )
    }

    func testNotRunningIsDisconnectedRegardlessOfTransport() {
        for icon in ["wifi", "cable.connector", "point.3.connected.trianglepath.dotted", "iphone.slash"] {
            XCTAssertEqual(
                ConnectionPillState.resolve(isStarting: false, isRunning: false, transportIcon: icon),
                .disconnected,
                "icon \(icon) should not affect the disconnected state"
            )
        }
    }

    func testRunningWifiTransportIsWifiActive() {
        XCTAssertEqual(
            ConnectionPillState.resolve(isStarting: false, isRunning: true, transportIcon: "wifi"),
            .wifiActive
        )
    }

    func testRunningUsbTransportIsUsbActive() {
        XCTAssertEqual(
            ConnectionPillState.resolve(isStarting: false, isRunning: true, transportIcon: "cable.connector"),
            .usbActive
        )
    }

    func testRunningGenericTransportFallsBackToUsbActive() {
        // ActiveTransportPresentation can emit a generic icon for auto/unknown
        // modes; the pill treats any non-wifi active tunnel as USB-style.
        XCTAssertEqual(
            ConnectionPillState.resolve(
                isStarting: false,
                isRunning: true,
                transportIcon: "point.3.connected.trianglepath.dotted"
            ),
            .usbActive
        )
    }

    func testPresentationAttributesAreDefinedForAllStates() {
        for state in ConnectionPillState.allCases {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.subtitle.isEmpty)
            XCTAssertFalse(state.systemImage.isEmpty)
        }
    }

    func testPulseBehaviorMatchesMockup() {
        // Mockup: disconnected has no animation; connecting pulses fast (1.2s);
        // active states pulse slow (2.4s).
        XCTAssertFalse(ConnectionPillState.disconnected.pulses)
        XCTAssertTrue(ConnectionPillState.connecting.pulses)
        XCTAssertTrue(ConnectionPillState.usbActive.pulses)
        XCTAssertTrue(ConnectionPillState.wifiActive.pulses)
        XCTAssertEqual(ConnectionPillState.connecting.pulsePeriod, 1.2, accuracy: 0.001)
        XCTAssertEqual(ConnectionPillState.usbActive.pulsePeriod, 2.4, accuracy: 0.001)
    }
}
