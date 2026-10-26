import XCTest
@testable import PathChanger

@MainActor
private final class ControlledRouteDelay {
    let entered: XCTestExpectation
    let cancelled: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?

    init(entered: XCTestExpectation, cancelled: XCTestExpectation) {
        self.entered = entered
        self.cancelled = cancelled
    }

    func wait() async {
        let cancelled = cancelled
        await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation = $0
                entered.fulfill()
            }
        } onCancel: {
            cancelled.fulfill()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class ModePersistenceTests: XCTestCase {
    private let first = LocationCoordinate(latitude: 35.67620, longitude: 139.65030)
    private let second = LocationCoordinate(latitude: 35.67621, longitude: 139.65031)
    private let third = LocationCoordinate(latitude: 35.67622, longitude: 139.65032)

    private func makeRouteState(
        injector: FakeLocationInjector,
        mode: AppMode,
        route: [LocationCoordinate],
        routeDelay: @escaping @MainActor @Sendable (TimeInterval) async -> Void = { _ in }
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            routeDelay: routeDelay
        )
        state.selectedDevice = Device(id: "route-device", displayName: "Route Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = mode
        state.simulationSpeed = .teleport
        state.loadRoute(from: route)
        state.targetLocation = route.last
        let locationMode = mode == .twospot ? LocationMode.twoSpot : .multiSpot
        state.locationSessionCoordinator.select(route.last!, mode: locationMode)
        let session = LocationSessionIdentity(
            stableDeviceID: "route-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)
        return (state, session)
    }

    func testTwoSpotAdvancesOnlyAfterReceiptsAndHoldsDestination() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .twospot,
            route: [first, second]
        )

        let playback = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        XCTAssertEqual(state.routeProgress, 0)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.isSimulating)

        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertEqual(state.routeProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.twoSpot))

        await fake.releaseNextApplication(session: session)
        await playback.value

        XCTAssertEqual(state.routeProgress, 1, accuracy: 0.001)
        XCTAssertEqual(state.currentLocation, second)
        XCTAssertFalse(state.isSimulating)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.twoSpot))
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, second)

        await state.stopSimulation()
        XCTAssertEqual(state.currentLocation, second)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        var calls = await fake.calls()
        XCTAssertFalse(calls.contains { if case .clear = $0 { return true }; return false })

        await state.clearLocation()
        XCTAssertNil(state.currentLocation)
        XCTAssertNil(state.locationSessionCoordinator.state.desiredLocation)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        calls = await fake.calls()
        XCTAssertTrue(calls.contains { if case .clear = $0 { return true }; return false })
    }

    func testMultiSpotProgressTracksOnlyAcknowledgedPointsAndHoldsFinalWaypoint() async {
        let fake = FakeLocationInjector()
        let points = [first, second, third]
        let (state, session) = makeRouteState(injector: fake, mode: .route, route: points)

        let playback = Task { await state.startSimulation() }
        for (index, point) in points.enumerated() {
            await fake.waitUntilApplicationPending()
            XCTAssertEqual(state.routeProgress, Double(index) / Double(points.count), accuracy: 0.001)
            if index > 0 {
                XCTAssertEqual(state.currentLocation, points[index - 1])
            }
            await fake.releaseNextApplication(session: session)
        }
        await playback.value

        XCTAssertEqual(state.routeProgress, 1, accuracy: 0.001)
        XCTAssertEqual(state.currentLocation, third)
        XCTAssertFalse(state.isSimulating)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.multiSpot))
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, third)
    }


    func testStoppingWhileReceiptIsPendingRejectsLateRouteUpdate() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .twospot,
            route: [first, second]
        )

        let playback = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await state.stopSimulation()
        await fake.releaseNextApplication(session: session)
        await playback.value

        XCTAssertNil(state.currentLocation)
        XCTAssertEqual(state.routeProgress, 0)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
    }


    func testClearWaitsForPendingRouteApplicationBeforeClearingAdapter() async {
        let fake = FakeLocationInjector()
        let cancelled = expectation(description: "Pending delivery receives cancellation")
        await fake.setApplicationCancellationObserver { cancelled.fulfill() }
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .twospot,
            route: [first, second]
        )
        let playback = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)
        let callsBeforeCompletion = await fake.calls()
        XCTAssertFalse(callsBeforeCompletion.contains {
            if case .clear = $0 { return true }
            return false
        }, "Clear must wait for already-dispatched delivery to finish")
        await state.startSimulation()
        let callsAfterAnotherMove = await fake.calls()
        XCTAssertEqual(callsAfterAnotherMove, callsBeforeCompletion,
                       "Move must not start another application during Clear")

        await fake.releaseNextApplication(session: session)
        await clearing.value
        await playback.value

        XCTAssertNil(state.currentLocation)
        XCTAssertNil(state.locationSessionCoordinator.state.desiredLocation)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(calls.filter {
            if case .clear = $0 { return true }
            return false
        }.count, 1)
    }

    func testClearJoinsRouteDelayAndCoalescesConcurrentClearRequests() async {
        let fake = FakeLocationInjector()
        let entered = expectation(description: "Route delay entered")
        let cancelled = expectation(description: "Route delay cancelled")
        let delay = ControlledRouteDelay(entered: entered, cancelled: cancelled)
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .twospot,
            route: [first, second],
            routeDelay: { _ in await delay.wait() }
        )
        let playback = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await fulfillment(of: [entered], timeout: 1)

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)
        let callsBeforeRelease = await fake.calls()
        XCTAssertFalse(callsBeforeRelease.contains {
            if case .clear = $0 { return true }
            return false
        })
        let duplicateStarted = expectation(description: "Duplicate Clear started")
        let duplicateClear = Task {
            duplicateStarted.fulfill()
            await state.clearLocation()
        }
        await fulfillment(of: [duplicateStarted], timeout: 1)
        delay.release()
        await clearing.value
        await duplicateClear.value
        await playback.value

        let calls = await fake.calls()
        XCTAssertEqual(calls.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 1, "The cancelled route must not apply its next waypoint")
        XCTAssertEqual(calls.filter {
            if case .clear = $0 { return true }
            return false
        }.count, 1, "Concurrent Clear callers must share the same reset")
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
    }

    func testClearWaitsForJoystickStartupAndPreventsLateWorkerCreation() async {
        let fake = FakeLocationInjector()
        let cancelled = expectation(description: "Joystick startup cancelled")
        await fake.setApplicationCancellationObserver { cancelled.fulfill() }
        let (state, session) = makeJoystickState(injector: fake)
        let startup = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)
        let beforeCompletion = await fake.calls()
        XCTAssertFalse(beforeCompletion.contains {
            if case .clear = $0 { return true }
            return false
        })
        await fake.releaseNextApplication(session: session)
        await clearing.value
        await startup.value

        XCTAssertNil(state.currentLocation)
        XCTAssertEqual(state.joystickDirection, .zero)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 1)
    }

    func testClearPublishesBusyStoppedStateWhileApplicationDrains() async {
        let fake = FakeLocationInjector()
        let cancelled = expectation(description: "Pending joystick update cancelled")
        await fake.setApplicationCancellationObserver { cancelled.fulfill() }
        let (state, session) = makeJoystickState(injector: fake)
        let startup = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await startup.value
        await fake.waitUntilApplicationPending()
        let receipt = state.locationSessionCoordinator.state.lastAcknowledgedReceipt
        let desired = state.locationSessionCoordinator.state.desiredLocation

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)

        XCTAssertEqual(
            state.locationPresentation.applicationLabel,
            NSLocalizedString("location.status.application.clearing", comment: "")
        )
        XCTAssertFalse(state.locationPresentation.isMovementActive)
        XCTAssertFalse(state.locationPresentation.canApply)
        XCTAssertFalse(state.locationPresentation.canMove)
        XCTAssertFalse(state.locationPresentation.canClear)
        XCTAssertFalse(state.canStartSimulation)
        XCTAssertFalse(state.isSimulating)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, desired)
        let calls = await fake.calls()
        XCTAssertFalse(calls.contains {
            if case .clear = $0 { return true }
            return false
        })

        await fake.releaseNextApplication(session: session)
        await clearing.value
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertFalse(state.locationPresentation.canClear)
    }

    func testFailedClearStopsJoystickButPreservesAcknowledgedCoordinate() async {
        let fake = FakeLocationInjector()
        let cancelled = expectation(description: "Joystick movement cancelled")
        await fake.setApplicationCancellationObserver { cancelled.fulfill() }
        let (state, session) = makeJoystickState(injector: fake)
        let startup = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await startup.value
        await fake.waitUntilApplicationPending()
        let acknowledged = state.locationSessionCoordinator.state.lastAcknowledgedReceipt
        await fake.setShouldFailClear(true)

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)
        await fake.releaseNextApplication(session: session)
        await clearing.value

        XCTAssertEqual(state.currentLocation, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, acknowledged)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertEqual(state.joystickDirection, .zero)
        guard case .failed = state.locationSessionCoordinator.state.application else {
            return XCTFail("Failed Clear must not report Idle or Active")
        }
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 2)
    }

    func testClearPreservesRecoveryTargetAfterLateReceipt() async {
        await verifyClearDuringRecovery(completesWithCancellation: false)
    }

    func testClearPreservesRecoveryTargetAfterCancellationError() async {
        await verifyClearDuringRecovery(completesWithCancellation: true)
    }

    func testFailedRecoveryClearCanRetryAfterLateReceipt() async {
        await verifyClearDuringRecovery(completesWithCancellation: false, retryAfterFailure: true)
    }

    func testFailedRecoveryClearCanRetryAfterCancellationError() async {
        await verifyClearDuringRecovery(completesWithCancellation: true, retryAfterFailure: true)
    }

    private func verifyClearDuringRecovery(
        completesWithCancellation: Bool,
        retryAfterFailure: Bool = false
    ) async {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .teleport,
            route: [first]
        )
        let initialApplication = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await initialApplication.value
        state.submitLocationBridgeEvent(.sessionLost(session, reason: "Test transport loss"))
        let recoveredSession = LocationSessionIdentity(
            stableDeviceID: session.stableDeviceID,
            transport: session.transport,
            endpointClass: session.endpointClass,
            generation: session.generation + 1
        )
        let cancelled = expectation(description: "Recovery receives cancellation")
        await fake.setApplicationCancellationObserver { cancelled.fulfill() }
        state.startLocationRecovery(
            strategy: ReconnectionStrategy(
                maxAttempts: 1, initialDelaySeconds: 0, maxDelaySeconds: 0,
                backoffMultiplier: 1, jitterFactor: 0
            ),
            establishSession: { _, _ in recoveredSession }
        )
        await fake.waitUntilApplicationPending()
        await fake.setShouldFailClear(retryAfterFailure)

        let clearing = Task { await state.clearLocation() }
        await fulfillment(of: [cancelled], timeout: 1)
        let beforeCompletion = await fake.calls()
        XCTAssertFalse(beforeCompletion.contains {
            if case .clear = $0 { return true }
            return false
        })
        if completesWithCancellation {
            await fake.cancelNextApplication()
        } else {
            await fake.releaseNextApplication(session: recoveredSession)
        }
        await clearing.value

        if retryAfterFailure {
            XCTAssertEqual(state.currentLocation, first)
            XCTAssertNotNil(state.locationSessionCoordinator.state.desiredLocation)
            XCTAssertNotNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
            XCTAssertFalse(state.locationSessionCoordinator.state.connection.isReady)
            XCTAssertTrue(state.locationPresentation.canClear,
                          "Failed Clear must retain an explicit retry target without readiness")
            await fake.setShouldFailClear(false)
            await state.clearLocation()
        }
        let calls = await fake.calls()
        let clearedSessions = calls.compactMap { call -> LocationSessionIdentity? in
            if case .clear(_, let session) = call { return session }
            return nil
        }
        let expectedSessions = Array(repeating: recoveredSession, count: retryAfterFailure ? 2 : 1)
        XCTAssertEqual(clearedSessions, expectedSessions,
                       "Recovery cancellation must not erase the explicit Clear target")
        XCTAssertEqual(calls.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 2)
        XCTAssertNil(state.currentLocation)
        XCTAssertNil(state.locationSessionCoordinator.state.desiredLocation)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertFalse(state.locationSessionCoordinator.state.connection.isReady,
                       "Clearing a retained target must not invent connection readiness")
        XCTAssertFalse(state.locationPresentation.canClear)
    }

    func testUnresolvedClearBlocksNewDeviceApplicationUntilRetrySucceeds() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(
            injector: fake, mode: .teleport, route: [first]
        )
        let initial = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await initial.value
        await fake.setShouldFailClear(true)
        await state.clearLocation()

        state.selectDevice(Device(id: "second-device", displayName: "Second Device", connectionType: .usb))
        state.stageLocation(second, for: .teleport)
        XCTAssertFalse(state.canStartSimulation)
        XCTAssertFalse(state.locationPresentation.canApply)
        XCTAssertFalse(state.locationPresentation.canMove)
        XCTAssertTrue(state.locationPresentation.canClear)
        let unexpectedApplication = expectation(description: "No application while reset is unresolved")
        unexpectedApplication.isInverted = true
        await fake.setApplicationObserver { unexpectedApplication.fulfill() }
        let attemptedMove = Task { await state.startSimulation() }
        await fulfillment(of: [unexpectedApplication], timeout: 0.1)
        attemptedMove.cancel()
        if await fake.pendingApplicationCount() > 0 {
            await fake.failNextApplication(code: "Test cleanup")
        }
        await attemptedMove.value
        await fake.setApplicationObserver(nil)
        let beforeRetry = await fake.calls()
        XCTAssertEqual(beforeRetry.filter {
            if case .apply = $0 { return true }
            return false
        }.count, 1)

        await fake.setShouldFailClear(false)
        await state.clearLocation()
        let clearedSessions = await fake.calls().compactMap { call -> LocationSessionIdentity? in
            if case .clear(_, let session) = call { return session }
            return nil
        }
        XCTAssertEqual(clearedSessions, [session, session])
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.currentLocation)

        state.stageLocation(second, for: .teleport)
        XCTAssertTrue(state.canStartSimulation)
        guard case .ready(let currentSession) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("The newly selected device must retain its ready session")
        }
        let newApplication = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: currentSession)
        await newApplication.value
        XCTAssertEqual(state.currentLocation, second)
        guard case .ready(let acknowledgedSession) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Provider acknowledgement must promote the provisional session")
        }
        XCTAssertEqual(acknowledgedSession.endpointClass, .direct)

        await state.clearLocation()
        let finalClearedSessions = await fake.calls().compactMap { call -> LocationSessionIdentity? in
            if case .clear(_, let session) = call { return session }
            return nil
        }
        XCTAssertEqual(finalClearedSessions, [session, session, acknowledgedSession])
    }

    private func makeJoystickState(
        injector: FakeLocationInjector
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            routeDelay: { _ in }
        )
        state.selectedDevice = Device(id: "joystick-device", displayName: "Joystick Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = .joystick
        state.simulationSpeed = .walking
        state.stageLocation(first, for: .joystick)
        state.joystickDirection = CGPoint(x: 0, y: 1)
        let session = LocationSessionIdentity(
            stableDeviceID: "joystick-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)
        return (state, session)
    }

    func testJoystickEngagesOnlyAfterStartCoordinateReceipt() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeJoystickState(injector: fake)

        let engagement = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        XCTAssertFalse(state.isSimulating)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)

        await fake.releaseNextApplication(session: session)
        await engagement.value

        XCTAssertEqual(state.currentLocation, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.joystick))
        await fake.waitUntilApplicationPending()
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    func testRapidJoystickInputKeepsOneApplyInFlightAndUsesLatestDirectionNext() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeJoystickState(injector: fake)
        let engagement = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await engagement.value

        await fake.waitUntilApplicationPending()
        state.updateJoystickDirection(CGPoint(x: 1, y: 0))
        state.updateJoystickDirection(CGPoint(x: 0, y: -1))
        state.updateJoystickDirection(CGPoint(x: -1, y: 0))
        var applyCalls = await fake.calls().compactMap { call -> LocationApplicationRequest? in
            if case .apply(let request) = call { return request }
            return nil
        }
        XCTAssertEqual(applyCalls.count, 2)

        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()
        applyCalls = await fake.calls().compactMap { call -> LocationApplicationRequest? in
            if case .apply(let request) = call { return request }
            return nil
        }
        XCTAssertEqual(applyCalls.count, 3)
        XCTAssertLessThan(applyCalls[2].coordinate.longitude, applyCalls[1].coordinate.longitude)

        let held = state.currentLocation
        state.disengageJoystick()
        XCTAssertFalse(state.isSimulating)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.joystick))
        XCTAssertEqual(state.currentLocation, held)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        await fake.releaseNextApplication(session: session)
    }

    func testJoystickTransportLossCancelsMovementAndPreservesLocationTruth() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeJoystickState(injector: fake)
        let engagement = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await engagement.value
        let receipt = state.locationSessionCoordinator.state.lastAcknowledgedReceipt
        await fake.waitUntilApplicationPending()
        let desiredBeforeLoss = state.locationSessionCoordinator.state.desiredLocation

        state.submitLocationBridgeEvent(.sessionLost(session, reason: "tunnel callback inactive"))

        XCTAssertFalse(state.isSimulating)
        XCTAssertEqual(state.joystickDirection, .zero)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, desiredBeforeLoss)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        if case .uncertain(let lastReceipt, _) = state.locationSessionCoordinator.state.application {
            XCTAssertEqual(lastReceipt, receipt)
        } else {
            XCTFail("transport loss must make application state uncertain")
        }
        await fake.releaseNextApplication(session: session)
    }
}
