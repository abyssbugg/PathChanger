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
}
