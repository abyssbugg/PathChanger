import XCTest
@testable import PathChanger

@MainActor
final class LocationInjectionReceiptTests: XCTestCase {
    private let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let session = LocationSessionIdentity(
        stableDeviceID: "device-internal-001",
        transport: .wifi,
        endpointClass: .remoteServiceDiscovery,
        generation: 7
    )

    func testRequestCarriesStableIdentityCoordinateAndMode() {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: LocationInjectionTarget(stableDeviceID: session.stableDeviceID, transport: session.transport),
            coordinate: coordinate,
            mode: .jumpTeleport
        )
        XCTAssertEqual(request.target.stableDeviceID, session.stableDeviceID)
        XCTAssertEqual(request.coordinate, coordinate)
        XCTAssertEqual(request.mode, .jumpTeleport)
    }

    func testAppliedReceiptEchoesRequestAndSessionMetadata() {
        let requestID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let receipt = LocationInjectionReceipt(
            requestID: requestID, session: UUID(), coordinate: coordinate,
            transport: session.transport, endpointClass: session.endpointClass,
            sessionGeneration: session.generation, completedAt: completedAt, outcome: .applied
        )
        XCTAssertEqual(receipt.requestID, requestID)
        XCTAssertEqual(receipt.coordinate, coordinate)
        XCTAssertEqual(receipt.transport, .wifi)
        XCTAssertEqual(receipt.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(receipt.sessionGeneration, 7)
        XCTAssertEqual(receipt.completedAt, completedAt)
        XCTAssertEqual(receipt.outcome, .applied)
    }

    func testBridgeEventsCarryTypedSessionLifecycle() {
        XCTAssertEqual(LocationBridgeEvent.sessionReady(session), .sessionReady(session))
        XCTAssertEqual(LocationBridgeEvent.sessionLost(session, reason: "link lost"), .sessionLost(session, reason: "link lost"))
        XCTAssertEqual(LocationBridgeEvent.processTerminated(exitCode: 9), .processTerminated(exitCode: 9))
    }

    func testFakeAcknowledgementGatesActiveState() async throws {
        let fake = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: fake)
        coordinator.connectionReady(session)
        coordinator.select(coordinate, mode: .teleport)
        let request = try coordinator.beginApplication()
        let applyTask = Task { try await fake.apply(request) }

        await fake.waitUntilApplicationPending()
        XCTAssertFalse(coordinator.state.application.isActive)

        await fake.releaseNextApplication(session: session)
        let receipt = try await applyTask.value
        XCTAssertFalse(coordinator.state.application.isActive)
        XCTAssertNil(coordinator.accept(receipt))
        XCTAssertTrue(coordinator.state.application.isActive)
        let calls = await fake.calls()
        XCTAssertEqual(calls, [.apply(request)])
    }

    func testFakeEmitsLifecycleEventsInOrder() async {
        let fake = FakeLocationInjector()
        let stream = await fake.events()
        let collector = Task { () -> [LocationBridgeEvent] in
            var events: [LocationBridgeEvent] = []
            for await event in stream { events.append(event) }
            return events
        }
        let lost = LocationBridgeEvent.sessionLost(session, reason: "link lost")

        await fake.emit(.sessionReady(session))
        await fake.emit(lost)
        await fake.emit(.processTerminated(exitCode: 9))
        await fake.finishEvents()

        let expected: [LocationBridgeEvent] = [.sessionReady(session), lost, .processTerminated(exitCode: 9)]
        let emittedEvents = await collector.value
        let calls = await fake.calls()
        XCTAssertEqual(emittedEvents, expected)
        XCTAssertEqual(calls, expected.map(FakeLocationInjector.Call.event))
    }

    func testFakeSupportsQueuedAndFailedApplications() async throws {
        let fake = FakeLocationInjector()
        let request = LocationApplicationRequest(
            id: UUID(),
            target: LocationInjectionTarget(stableDeviceID: session.stableDeviceID, transport: session.transport),
            coordinate: coordinate,
            mode: .twoSpot
        )
        let queuedTask = Task { try await fake.apply(request) }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session, outcome: .queued)
        let queuedReceipt = try await queuedTask.value
        XCTAssertEqual(queuedReceipt.outcome, .queued)

        let failedTask = Task { try await fake.apply(request) }
        await fake.waitUntilApplicationPending()
        await fake.failNextApplication(code: "bridge_failed")
        do {
            _ = try await failedTask.value
            XCTFail("Expected injected application failure")
        } catch {
            XCTAssertEqual(error as? FakeLocationInjector.FakeError, .applicationFailed("bridge_failed"))
        }
    }
}
