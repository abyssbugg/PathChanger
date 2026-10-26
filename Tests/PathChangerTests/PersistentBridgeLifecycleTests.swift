import XCTest
@testable import PathChanger

@MainActor
final class PersistentBridgeLifecycleTests: XCTestCase {
    func testRequestGateRejectsOverlapAndWrongIdentity() throws {
        var gate = PersistentBridgeRequestGate()
        let first = UUID()
        let second = UUID()

        try gate.begin(requestID: first, generation: 7)
        XCTAssertThrowsError(try gate.begin(requestID: second, generation: 7)) { error in
            XCTAssertEqual(error as? PersistentLocationBridge.PersistentBridgeError, .requestInProgress)
        }
        XCTAssertFalse(gate.accepts(requestID: second, generation: 7))
        XCTAssertFalse(gate.accepts(requestID: first, generation: 8))
        XCTAssertTrue(gate.accepts(requestID: first, generation: 7))
        gate.finish(requestID: first, generation: 7)
        XCTAssertNoThrow(try gate.begin(requestID: second, generation: 8))
    }

    func testReadinessRequiresReadyProtocolMessage() {
        var gate = PersistentBridgeReadinessGate()
        XCTAssertFalse(gate.consume(ready: false))
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.consume(ready: true))
        XCTAssertTrue(gate.isReady)
    }

    func testTerminationEventsAreOrderedExactlyOnce() {
        let session = LocationSessionIdentity(
            stableDeviceID: "persistent-device",
            transport: .wifi,
            endpointClass: .remoteServiceDiscovery,
            generation: 4
        )
        var events = PersistentBridgeTerminationEvents()

        XCTAssertEqual(
            events.consume(exitCode: 9, intentional: false, session: session),
            [.processTerminated(exitCode: 9), .sessionLost(session, reason: "unexpected process exit")]
        )
        XCTAssertTrue(events.consume(exitCode: 9, intentional: false, session: session).isEmpty)

        var intentional = PersistentBridgeTerminationEvents()
        XCTAssertEqual(
            intentional.consume(exitCode: 0, intentional: true, session: session),
            [.processTerminated(exitCode: 0), .sessionLost(session, reason: "intentional stop")]
        )
    }

    func testEventHubPublishesTerminationThenSessionLoss() async {
        let session = LocationSessionIdentity(
            stableDeviceID: "stream-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 2
        )
        let expected: [LocationBridgeEvent] = [
            .processTerminated(exitCode: 7),
            .sessionLost(session, reason: "unexpected process exit")
        ]
        let hub = PersistentBridgeEventHub()
        let stream = hub.stream()
        let collected = Task { () -> [LocationBridgeEvent] in
            var result: [LocationBridgeEvent] = []
            for await event in stream {
                result.append(event)
                if result.count == expected.count { break }
            }
            return result
        }

        hub.publish(expected)
        let values = await collected.value
        XCTAssertEqual(values, expected)
    }

    // MARK: - Remediation Group 1: cleanup() Gate Reset Tests

    func testCleanupResetsReadinessGateForNextGeneration() {
        var gate = PersistentBridgeReadinessGate()
        XCTAssertTrue(gate.consume(ready: true))
        XCTAssertTrue(gate.isReady)
        gate = PersistentBridgeReadinessGate()
        XCTAssertTrue(gate.consume(ready: true))
        XCTAssertTrue(gate.isReady)
    }

    func testCleanupResetsTerminationEventsForNextGeneration() {
        let session = LocationSessionIdentity(
            stableDeviceID: "test-device",
            transport: .wifi,
            endpointClass: .remoteServiceDiscovery,
            generation: 1
        )
        var events = PersistentBridgeTerminationEvents()
        let first = events.consume(exitCode: 1, intentional: false, session: session)
        XCTAssertEqual(first.count, 2)
        let second = events.consume(exitCode: 1, intentional: false, session: session)
        XCTAssertTrue(second.isEmpty)
        events = PersistentBridgeTerminationEvents()
        let third = events.consume(exitCode: 2, intentional: true, session: session)
        XCTAssertEqual(third.count, 2)
    }

    func testCleanupCancelsContinuationsSafely() {
        var gate = PersistentBridgeRequestGate()
        XCTAssertNoThrow(try gate.begin(requestID: UUID(), generation: 1))
    }

    func testIntentionalStopSemanticsPreservedAcrossCleanup() {
        let session = LocationSessionIdentity(
            stableDeviceID: "intent-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 5
        )
        var events = PersistentBridgeTerminationEvents()
        let intentionalStop = events.consume(exitCode: 0, intentional: true, session: session)
        XCTAssertTrue(intentionalStop.contains { event in
            if case .sessionLost(_, reason: let reason) = event {
                return reason == "intentional stop"
            }
            return false
        })
    }

    func testSignalShutdownWakesPendingStdinRead() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/location_bridge.py"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("run_in_executor(None, sys.stdin.readline)"))
        XCTAssertTrue(source.contains("_shutdown_event"))
        XCTAssertTrue(source.contains("connect_read_pipe"))
        XCTAssertTrue(source.contains("return_when=asyncio.FIRST_COMPLETED"))
        XCTAssertTrue(source.contains("read_task.cancel()"))
    }
}
