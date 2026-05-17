//
//  ConnectionStatusTests.swift
//  PathChangerTests
//
//  Tests for the ConnectionStatus enum declared in PathChangerApp.swift.
//
//  Previously hosted inside StateManagerTests.swift; preserved during
//  Milestone 1 (shadow state-architecture elimination) because the
//  ConnectionStatus enum lives in production code (PathChangerApp.swift)
//  and is independent of the deleted Core/StateManagers/ triplet.
//

import XCTest
@testable import PathChanger

final class ConnectionStatusTests: XCTestCase {

    func testConnectionStatusColors() {
        // Each status must have a defined color for the UI to render correctly.
        XCTAssertNotNil(ConnectionStatus.disconnected.color)
        XCTAssertNotNil(ConnectionStatus.connecting.color)
        XCTAssertNotNil(ConnectionStatus.connected.color)
        XCTAssertNotNil(ConnectionStatus.error.color)
    }

    func testConnectionStatusText() {
        // Canonical §5 lexicon (W0 vocabulary unification):
        //   .disconnected → "Not connected"  (replaces deprecated "Disconnected")
        //   .connecting   → "Connecting…"   (typographic ellipsis)
        //   .connected    → "Connected"
        //   .error        → "Connection lost" (per §5.1 device-connection lexicon)
        XCTAssertEqual(ConnectionStatus.disconnected.text, "Not connected")
        XCTAssertEqual(ConnectionStatus.connecting.text, "Connecting…")
        XCTAssertEqual(ConnectionStatus.connected.text, "Connected")
        XCTAssertEqual(ConnectionStatus.error.text, "Connection lost")
    }
}
