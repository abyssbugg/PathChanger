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

/// Applies through the real `LocationSessionGenerationTracker` and acknowledgement
/// router exactly as `DevLocationBridge.apply` does on the helper lane: Swift asks over
/// `--udid` (.direct) and the helper acknowledges its userspace RSD tunnel.
private actor HelperLaneGenerationInjector: LocationInjecting {
    private var tracker = LocationSessionGenerationTracker()
    private var applied: [LocationCoordinate] = []

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        let session = tracker.resolve(
            stableDeviceID: request.target.stableDeviceID,
            transport: request.target.transport,
            endpointClass: .direct,
            minimumGeneration: request.sessionGeneration
        )
        guard let acknowledgement = LocationProviderAcknowledgement(
            requestID: request.id, sessionGeneration: session.generation,
            physicalTransport: request.target.transport, channel: .userspaceRSD,
            endpointClass: .remoteServiceDiscovery
        ) else { throw LocationInjectionError.injectionFailed("bad acknowledgement") }
        applied.append(request.coordinate)
        return try LocationApplicationAcknowledgementRouter.accept(
            request: request, provisionalSession: session,
            acknowledgement: acknowledgement, generationTracker: &tracker
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {
        guard let session else { throw LocationInjectionError.injectionFailed("no session") }
        try tracker.beginClear(session)
        try tracker.completeClear(session)
    }

    func appliedCoordinates() -> [LocationCoordinate] { applied }
}

/// The helper lane with hooks that run after the device was cleared but before Clear
/// returns to the coordinator (where the live 2026-11-01 wedge began).
private actor ClearRetryHelperLaneInjector: LocationInjecting {
    private var tracker = LocationSessionGenerationTracker()
    private var afterDeviceCleared: (@MainActor @Sendable () -> Void)?
    private var failAfterDeviceClearedOnce = false
    private var clears = 0
    private var applied: [LocationCoordinate] = []

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        let session = tracker.resolve(
            stableDeviceID: request.target.stableDeviceID,
            transport: request.target.transport,
            endpointClass: .direct,
            minimumGeneration: request.sessionGeneration
        )
        guard let acknowledgement = LocationProviderAcknowledgement(
            requestID: request.id, sessionGeneration: session.generation,
            physicalTransport: request.target.transport, channel: .userspaceRSD,
            endpointClass: .remoteServiceDiscovery
        ) else { throw LocationInjectionError.injectionFailed("bad acknowledgement") }
        applied.append(request.coordinate)
        return try LocationApplicationAcknowledgementRouter.accept(
            request: request, provisionalSession: session,
            acknowledgement: acknowledgement, generationTracker: &tracker
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {
        guard let session else { throw LocationInjectionError.injectionFailed("no session") }
        try tracker.beginClear(session)
        clears += 1
        try tracker.completeClear(session)
        if let afterDeviceCleared { await afterDeviceCleared() }
        if failAfterDeviceClearedOnce {
            // The helper cleared the phone, but a later check in the bridge (the
            // acknowledgement match or the durable-clear confirmation) threw.
            failAfterDeviceClearedOnce = false
            throw LocationInjectionError.injectionFailed("Clear acknowledgement does not match the active session")
        }
    }

    func setAfterDeviceCleared(_ hook: (@MainActor @Sendable () -> Void)?) { afterDeviceCleared = hook }
    func setFailAfterDeviceClearedOnce() { failAfterDeviceClearedOnce = true }
    func clearCount() -> Int { clears }
    func appliedCoordinates() -> [LocationCoordinate] { applied }
}

/// Records the location phase a test observes from inside an injector hook.
@MainActor
private final class PhaseRecorder {
    var phases: [LocationApplicationPhase] = []
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
        // PRODUCT_REQUIREMENTS 5.2: the held destination stays staged (not applied).
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, second)
        XCTAssertEqual(state.stagedStartAfterClear, second)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        calls = await fake.calls()
        XCTAssertTrue(calls.contains { if case .clear = $0 { return true }; return false })
    }

    func testTwoSpotLetsTheUserPickBothEndpoints() {
        // PRODUCT_REQUIREMENTS 3.3: the user defines exactly two endpoints. Each map
        // click used to replace the single staged point, so only one spot could exist.
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        state.activeMode = .twospot

        state.stageLocation(first, for: .twospot)
        XCTAssertEqual(state.currentRoute, [first])
        state.stageLocation(second, for: .twospot)
        XCTAssertEqual(state.currentRoute, [first, second])
        // A third click moves the destination; the start stays.
        state.stageLocation(third, for: .twospot)
        XCTAssertEqual(state.currentRoute, [first, third])

        guard case .route(let points) = SimulationPlanner.plan(
            mode: .twospot, targetLocation: state.targetLocation, currentLocation: nil,
            route: state.currentRoute, speed: .teleport
        ) else { return XCTFail("two picked spots must plan a traversal") }
        XCTAssertEqual(points.first, first)
        XCTAssertEqual(points.last, third)
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


    func testStoppingWhileAReceiptIsPendingHoldsThePointTheDeviceApplied() async {
        // PRODUCT_REQUIREMENTS 3.3/3.4/4: Stop ends movement but holds the latest
        // applied coordinate. The helper finishes a command already sent, so a receipt
        // arriving after Stop is what the phone holds; dropping it showed the old point.
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

        XCTAssertEqual(state.currentLocation, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
        guard case .active(let held) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the applied point must show as held, got \(state.locationSessionCoordinator.state.application)")
        }
        XCTAssertEqual(held.coordinate, first)
        if case .moving = state.locationSessionCoordinator.state.movement {
            XCTFail("Stop ended movement; a late receipt must not resume it")
        }
        let applies = await fake.calls().filter { if case .apply = $0 { return true }; return false }
        XCTAssertEqual(applies.count, 1, "no further point is applied after Stop")
        let pending = await fake.pendingApplicationCount()
        XCTAssertEqual(pending, 0)
    }

    func testStoppingARetriedStepAfterAFailureHoldsThePointTheDeviceApplied() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(
            injector: fake,
            mode: .twospot,
            route: [first, second]
        )

        let failing = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.failNextApplication(code: "timeout")
        await failing.value
        guard case .failed = state.locationSessionCoordinator.state.application else {
            return XCTFail("the first attempt must fail, got \(state.locationSessionCoordinator.state.application)")
        }

        let retry = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await state.stopSimulation()
        await fake.releaseNextApplication(session: session)
        await retry.value

        XCTAssertEqual(state.currentLocation, first)
        guard case .active(let held) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the retried point applied on the device must not show Failed, got \(state.locationSessionCoordinator.state.application)")
        }
        XCTAssertEqual(held.coordinate, first)
        if case .moving = state.locationSessionCoordinator.state.movement {
            XCTFail("Stop ended movement; a late receipt must not resume it")
        }
        let pending = await fake.pendingApplicationCount()
        XCTAssertEqual(pending, 0)
    }

    /// Holds the DDI status check open until the test releases it.
    actor DDIStatusGate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var entered = false
        func hold() async {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }
        func waitUntilEntered() async {
            while !entered { await Task.yield() }
        }
        func release() {
            waiter?.resume()
            waiter = nil
        }
    }

    func testStopDuringTheDDICheckSendsNothingToTheDevice() async {
        // Review 2026-11-01: Stop while the mount check is awaited still created the
        // application task, so the phone moved once more after Stop.
        let fake = FakeLocationInjector()
        let gate = DDIStatusGate()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: fake,
            ddiPreparerFactory: { _ in
                DeveloperDiskImagePreparer(runner: { _ in
                    await gate.hold()
                    return "[{\"image\":\"DeveloperDiskImage\"}]"
                })
            },
            routeDelay: { _ in }
        )
        state.selectedDevice = Device(id: "route-device", displayName: "Route Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = .twospot
        state.simulationSpeed = .teleport
        state.loadRoute(from: [first, second])
        state.targetLocation = second
        state.locationSessionCoordinator.select(second, mode: .twoSpot)
        let session = LocationSessionIdentity(
            stableDeviceID: "route-device", transport: .usb, endpointClass: .direct, generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)

        let playback = Task { await state.startSimulation() }
        await gate.waitUntilEntered()
        await state.stopSimulation()
        await gate.release()
        // Without the guard the step reaches the injector; release it so the test ends.
        for _ in 0..<50 {
            if await fake.pendingApplicationCount() > 0 {
                await fake.releaseNextApplication(session: session)
                break
            }
            await Task.yield()
        }
        await playback.value

        let applies = await fake.calls().filter { if case .apply = $0 { return true }; return false }
        XCTAssertEqual(applies.count, 0, "Stop during the DDI check must not move the phone")
        XCTAssertNil(state.currentLocation)
        if case .applying = state.locationSessionCoordinator.state.application {
            XCTFail("a cancelled step must not stay Applying")
        }
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
        // PRODUCT_REQUIREMENTS 5.2: the last acknowledged point stays staged (not applied).
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertEqual(state.stagedStartAfterClear, first)
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

    /// Bounded wait: a regression that never applies must fail, not hang the suite.
    private func waitForPendingApplication(
        _ fake: FakeLocationInjector,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await fake.pendingApplicationCount() == 0 {
            guard Date() < deadline else {
                XCTFail("no location application was started within \(timeout)s")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testJoystickDragStartsOneEngagementEvenAfterAnEarlierLocation() async throws {
        // Live 2026-11-01: one drag sends many direction samples; each spawned its own
        // start, the starts cancelled each other, and none engaged (requestInProgress /
        // staleAcknowledgement). A location applied earlier (isSimulating) also blocked
        // the stick from starting at all.
        let fake = FakeLocationInjector()
        let (state, session) = makeJoystickState(injector: fake)
        state.isSimulating = true

        for _ in 0..<8 {
            state.updateJoystickDirection(CGPoint(x: 0, y: 1))
        }
        try await waitForPendingApplication(fake)
        try await Task.sleep(nanoseconds: 100_000_000)
        var applyCount = await fake.calls().filter {
            if case .apply = $0 { return true }
            return false
        }.count
        XCTAssertEqual(applyCount, 1, "one drag must start one engagement")

        await fake.releaseNextApplication(session: session)
        try await waitForPendingApplication(fake)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.joystick))
        applyCount = await fake.calls().filter {
            if case .apply = $0 { return true }
            return false
        }.count
        XCTAssertEqual(applyCount, 2, "the engaged loop sends the next step")

        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    private func makeClearRetryState(
        _ injector: ClearRetryHelperLaneInjector
    ) async -> AppState {
        let state = AppState(startBackgroundServices: false, locationInjector: injector, routeDelay: { _ in })
        state.selectedDevice = Device(id: "clear-retry-device", displayName: "Clear Retry", connectionType: .wifi)
        state.isTunneldRunning = true
        state.simulationSpeed = .teleport
        state.activeMode = .teleport
        state.stageLocation(first, for: .teleport)
        await state.startSimulation()
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertTrue(state.canStartSimulation)
        return state
    }

    private func assertMoveWorksAfterClear(_ state: AppState, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle, file: file, line: line)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, file: file, line: line)
        XCTAssertNil(state.moveBlockedByClear, file: file, line: line)
        XCTAssertTrue(state.canStartSimulation, "A successful Clear unblocks Move", file: file, line: line)
        XCTAssertEqual(state.statusMessage, "Location cleared. The last spot is staged for the next mode.", file: file, line: line)

        state.stageLocation(second, for: .teleport)
        await state.startSimulation()
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive, file: file, line: line)
        XCTAssertEqual(
            state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, second,
            file: file, line: line
        )
    }

    func testAClearTheHelperConfirmedDuringAConnectionLossSucceedsAndMoveStillWorks() async {
        // Live 2026-11-01: the helper cleared the phone, but the phone dropped out of
        // discovery during the await and the app reported the Clear as failed, so Move
        // stayed blocked. A Clear the helper confirmed is device truth: one press works.
        let injector = ClearRetryHelperLaneInjector()
        let state = await makeClearRetryState(injector)

        await injector.setAfterDeviceCleared { [weak state] in
            state?.locationSessionCoordinator.connectionLost(reason: "Selected device lost")
        }
        await state.clearLocation()
        await injector.setAfterDeviceCleared(nil)

        let clears = await injector.clearCount()
        XCTAssertEqual(clears, 1)
        guard case .failed = state.locationSessionCoordinator.state.connection else {
            return XCTFail("The connection loss stays reported; only the location dimension is idle")
        }
        await assertMoveWorksAfterClear(state)
    }

    func testAClearThatFailedAfterTheHelperClearedCanBeRetriedAndThenUnblocksMove() async {
        // The helper cleared the phone, but a later bridge check threw: the app keeps
        // Move blocked, and the retry must reach the helper again instead of failing in
        // the tracker before it (the wedge that lasted until relaunch).
        let injector = ClearRetryHelperLaneInjector()
        let state = await makeClearRetryState(injector)

        await injector.setFailAfterDeviceClearedOnce()
        await state.clearLocation()
        XCTAssertFalse(state.canStartSimulation, "An unconfirmed Clear keeps Move blocked")
        XCTAssertEqual(state.moveBlockedByClear, .clearUnresolved)
        // The status line names the real reason, not the coordinator's enum.
        let status = state.statusMessage ?? ""
        XCTAssertFalse(status.contains("clearFailed"), status)
        XCTAssertTrue(status.contains("Clear acknowledgement does not match the active session"), status)

        await state.clearLocation()

        let clears = await injector.clearCount()
        XCTAssertEqual(clears, 2, "The retry must reach the helper again")
        await assertMoveWorksAfterClear(state)
    }

    func testHelperLaneKeepsEveryModeAcknowledgedThroughClearAndConnectionLoss() async throws {
        // The live failure needed the real generation logic: the plain fake echoes the
        // session it is given, so it never showed every hop after the first going stale.
        let injector = HelperLaneGenerationInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: injector, routeDelay: { _ in })
        state.selectedDevice = Device(id: "helper-device", displayName: "Helper Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.simulationSpeed = .teleport

        // Teleport twice.
        state.activeMode = .teleport
        state.stageLocation(first, for: .teleport)
        await state.startSimulation()
        state.stageLocation(second, for: .teleport)
        await state.startSimulation()
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, second)

        // Jump: stops added after a Teleport, one hop per Move, index advances.
        state.activeMode = .jump
        state.clearRoute()
        state.stageLocation(first, for: .jump)
        state.stageLocation(third, for: .jump)
        XCTAssertEqual(state.currentRoute, [first, third])
        await state.startSimulation()
        XCTAssertEqual(state.jumpIndex, 1)
        await state.startSimulation()
        XCTAssertEqual(state.jumpIndex, 2)
        XCTAssertEqual(state.currentLocation, third)

        // Multi-Spot traverses every point and holds the last.
        state.activeMode = .route
        state.clearRoute()
        state.stageLocation(first, for: .route)
        state.stageLocation(second, for: .route)
        state.stageLocation(third, for: .route)
        await state.startSimulation()
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.multiSpot))
        XCTAssertEqual(state.currentLocation, third)

        // Clear, then Teleport again on the bridge's next generation.
        await state.clearLocation()
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        state.activeMode = .teleport
        state.stageLocation(first, for: .teleport)
        await state.startSimulation()
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)

        // A connection loss, then Move reapplies on the app's next generation.
        state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Wi-Fi dropped"))
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        state.stageLocation(second, for: .teleport)
        await state.startSimulation()
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, second)

        let applied = await injector.appliedCoordinates()
        XCTAssertEqual(applied.last, second)
    }

    // MARK: - Owner flow 2026-11-01: Jump + Auto jump, then Two-Spot, then Clear

    private let twoSpotStart = LocationCoordinate(latitude: 35.67630, longitude: 139.65040)
    private let twoSpotDestination = LocationCoordinate(latitude: 35.67640, longitude: 139.65050)

    /// Jump with Auto jump through three stops to completion, then select Two-Spot
    /// exactly as `ContentView.onChange(of: selectedMode)` does.
    private func runAutoJumpThenSelectTwoSpot(
        _ state: AppState,
        applied: () async -> [LocationCoordinate],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        state.activeMode = .jump
        for stop in [first, second, third] { state.stageLocation(stop, for: .jump) }
        state.autoJump = true
        await state.startSimulation()
        let jumped = await applied()
        XCTAssertEqual(jumped, [first, second, third], "Auto jump applies every stop", file: file, line: line)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.jumpTeleport), file: file, line: line)
        XCTAssertFalse(state.isMovementEngineRunning, file: file, line: line)

        state.activeMode = .twospot
        state.jumpIndex = 0
        if AppMode.twospot.maxStops > 0, state.currentRoute.count > AppMode.twospot.maxStops {
            state.loadRoute(from: Array(state.currentRoute.prefix(AppMode.twospot.maxStops)))
        }
    }

    /// `ContentView.performMove` for a Move (not Stop) press in `selectedMode`.
    private func pressMoveAsTheGUIDoes(
        _ state: AppState,
        selectedMode: AppMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        if state.locationPresentation.isMovementActive || state.isMovementEngineRunning,
           [.route, .twospot, .jump].contains(selectedMode) {
            return XCTFail("Move would act as Stop here", file: file, line: line)
        }
        state.activeMode = selectedMode == .settings ? .teleport : selectedMode
        await state.startSimulation()
    }

    func testTwoSpotMoveAfterAnAutoJumpSendsTheTraversal() async {
        // Owner report 2026-11-01: "a bug in Two-Spot keeps the GUI idle". The flow
        // without any Clear: Jump with Auto jump to completion, switch to Two-Spot, stage
        // two spots (directly, or after the card's Reset), Move.
        for useReset in [false, true] {
            let injector = HelperLaneGenerationInjector()
            let state = AppState(startBackgroundServices: false, locationInjector: injector, routeDelay: { _ in })
            state.selectedDevice = Device(id: "owner-flow-device", displayName: "Owner Flow", connectionType: .wifi)
            state.isTunneldRunning = true
            state.simulationSpeed = .teleport
            await runAutoJumpThenSelectTwoSpot(state, applied: { await injector.appliedCoordinates() })

            if useReset {
                // ModeContextCard.resetContext for Two-Spot: start from the held location.
                state.clearRoute()
                if let held = state.locationPresentation.appliedCoordinate {
                    state.stageLocation(held, for: .twospot)
                }
                state.stageLocation(twoSpotDestination, for: .twospot)
            } else {
                state.stageLocation(twoSpotStart, for: .twospot)
                state.stageLocation(twoSpotDestination, for: .twospot)
            }
            XCTAssertEqual(state.currentRoute.count, 2, "reset=\(useReset)")
            XCTAssertTrue(state.canStartSimulation, "reset=\(useReset)")

            let before = await injector.appliedCoordinates().count
            await pressMoveAsTheGUIDoes(state, selectedMode: .twospot)
            let applied = await injector.appliedCoordinates()

            XCTAssertGreaterThan(applied.count, before, "Two-Spot sends its traversal (reset=\(useReset))")
            XCTAssertEqual(applied.last, twoSpotDestination, "reset=\(useReset)")
            XCTAssertEqual(state.currentLocation, twoSpotDestination, "reset=\(useReset)")
            XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.twoSpot), "reset=\(useReset)")
            XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive, "reset=\(useReset)")
        }
    }

    func testAClearStaysInChargeWhileThePhoneDropsOutOfDiscoveryAndTwoSpotMovesAfterIt() async {
        // Live 2026-11-01 (Wi-Fi): Jump + Auto jump (3 hops), Two-Spot, Clear. The helper
        // cleared the phone, yet the app's location phase changed during the Clear's
        // await, and the Connection chip read Ready afterwards. A discovery drop of the
        // selected phone (it leaves usbmux when idle) followed by its return reproduces
        // both: the loss ran `connectionLost` mid-Clear and the re-selection published a
        // ready session. The Clear owns the location dimension until it returns.
        let deviceManager = DeviceManager(startBackgroundServices: false)
        let injector = ClearRetryHelperLaneInjector()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            deviceManager: deviceManager,
            routeDelay: { _ in }
        )
        let phone = Device(id: "clear-trigger-device", displayName: "Clear Trigger", connectionType: .wifi)
        state.selectedDevice = phone
        state.isTunneldRunning = true
        state.simulationSpeed = .teleport
        await runAutoJumpThenSelectTwoSpot(state, applied: { await injector.appliedCoordinates() })

        let recorder = PhaseRecorder()
        await injector.setAfterDeviceCleared { [weak state] in
            deviceManager.devices = []          // the phone drops out of discovery
            if let state { recorder.phases.append(state.locationSessionCoordinator.state.application) }
            deviceManager.devices = [phone]     // and comes back
        }
        await state.clearLocation()
        await injector.setAfterDeviceCleared(nil)
        for _ in 0..<100 { await Task.yield() }  // the re-selection callback

        XCTAssertEqual(recorder.phases, [.clearing], "a loss during Clear must not move the location phase")
        let clears = await injector.clearCount()
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertNil(state.moveBlockedByClear)
        XCTAssertEqual(state.statusMessage, "Location cleared. The last spot is staged for the next mode.")
        guard case .ready(let identity) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("the returned phone is ready again, got \(state.locationSessionCoordinator.state.connection)")
        }
        XCTAssertEqual(identity.stableDeviceID, phone.id)

        // Two-Spot after the Clear sends its traversal.
        state.stageLocation(twoSpotStart, for: .twospot)
        state.stageLocation(twoSpotDestination, for: .twospot)
        let before = await injector.appliedCoordinates().count
        await pressMoveAsTheGUIDoes(state, selectedMode: .twospot)
        let applied = await injector.appliedCoordinates()
        XCTAssertGreaterThan(applied.count, before)
        XCTAssertEqual(applied.last, twoSpotDestination)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.twoSpot))
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
    }

    func testAutoJumpAppliesEveryStopInOrderWithThePauseBetween() async throws {
        // Owner decision 2026-11-01: with Auto jump on, one Move jumps through every stop,
        // holding each for the chosen pause; the index still advances only on receipts.
        let fake = FakeLocationInjector()
        // The hold is counted down in ticks of at most 1 s (so Pause can stop it), keyed
        // here by the stop index it was counted at.
        var pauses: [Int: TimeInterval] = [:]
        var state: AppState!
        state = AppState(
            startBackgroundServices: false,
            locationInjector: fake,
            routeDelay: { seconds in
                XCTAssertLessThanOrEqual(seconds, 1)
                pauses[state.jumpIndex, default: 0] += seconds
            }
        )
        state.selectedDevice = Device(id: "jump-device", displayName: "Jump Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .jump
        for stop in [first, second, third] { state.stageLocation(stop, for: .jump) }
        state.autoJump = true
        state.autoJumpPauseSeconds = 7
        let session = LocationSessionIdentity(
            stableDeviceID: "jump-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)

        let run = Task { await state.startSimulation() }
        for (index, stop) in [first, second, third].enumerated() {
            try await waitForPendingApplication(fake)
            XCTAssertEqual(state.jumpIndex, index, "the index advances only on a receipt")
            if index > 0 {
                XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.jumpTeleport))
            }
            XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, stop)
            await fake.releaseNextApplication(session: session)
        }
        await run.value

        XCTAssertEqual(state.jumpIndex, 3)
        XCTAssertEqual(state.currentLocation, third)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.jumpTeleport))
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive, "the last stop holds")
        XCTAssertEqual(pauses, [1: 7, 2: 7], "a 7 s pause after stops 1 and 2, none after the last")
    }

    func testAutoJumpEndsWhenTheModeChangesOrAutoJumpIsTurnedOff() async throws {
        // Review 2026-11-01: the engine kept running after a mode change and, after its
        // pause, jumped back to stop 1 with no Move. Leaving Jump (or turning Auto jump
        // off) ends it and holds the last applied stop.
        for leave in ["mode", "toggle"] {
            let fake = FakeLocationInjector()
            let pause = ControlledRouteDelay(
                entered: expectation(description: "pause \(leave)"),
                cancelled: expectation(description: "cancelled \(leave)")
            )
            let state = AppState(
                startBackgroundServices: false,
                locationInjector: fake,
                routeDelay: { _ in await pause.wait() }
            )
            state.selectedDevice = Device(id: "jump-device", displayName: "Jump Device", connectionType: .wifi)
            state.isTunneldRunning = true
            state.activeMode = .jump
            for stop in [first, second, third] { state.stageLocation(stop, for: .jump) }
            state.autoJump = true
            let session = LocationSessionIdentity(
                stableDeviceID: "jump-device", transport: .wifi, endpointClass: .unresolved, generation: 1
            )
            state.locationSessionCoordinator.connectionReady(session)

            let run = Task { await state.startSimulation() }
            try await waitForPendingApplication(fake)
            await fake.releaseNextApplication(session: session)
            await fulfillment(of: [pause.entered], timeout: 2)

            if leave == "mode" { state.activeMode = .teleport } else { state.autoJump = false }
            await fulfillment(of: [pause.cancelled], timeout: 2)
            pause.release()  // the test pause does not return by itself on cancellation
            await run.value

            let applies = await fake.calls().filter { if case .apply = $0 { return true }; return false }
            XCTAssertEqual(applies.count, 1, "no stop after leaving (\(leave))")
            XCTAssertEqual(state.currentLocation, first)
            XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive, "the stop holds")
            XCTAssertFalse(state.isMovementEngineRunning)
        }
    }

    func testASecondMoveWhileARouteIsStartingDoesNotStartASecondRoute() async throws {
        let fake = FakeLocationInjector()
        let (state, session) = makeRouteState(injector: fake, mode: .route, route: [first, second, third])

        let playback = Task { await state.startSimulation() }
        try await waitForPendingApplication(fake)
        XCTAssertTrue(state.isMovementEngineRunning, "Move shows Stop from the start of the run")
        let secondMove = Task { await state.startSimulation() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let pending = await fake.pendingApplicationCount()
        XCTAssertEqual(pending, 1)

        await state.stopSimulation()
        await fake.releaseNextApplication(session: session)
        await playback.value
        await secondMove.value
    }

    func testAutoJumpWithoutStopsDoesNotClaimToHaveJumped() async {
        let fake = FakeLocationInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "jump-device", displayName: "Jump Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .jump
        state.autoJump = true
        state.targetLocation = first
        let session = LocationSessionIdentity(
            stableDeviceID: "jump-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)
        state.locationSessionCoordinator.select(first, mode: .jumpTeleport)

        let run = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await run.value

        XCTAssertEqual(state.currentLocation, first, "with no stops, Move applies the selected spot")
        XCTAssertNotEqual(state.statusMessage, "All jumps done; holding the last stop")
    }

    func testAMoveWhileTheLastOneIsStillApplyingIsIgnored() async throws {
        // A double click on Move raced two applications: the second replaced the first
        // pending request and the bridge answered "request in progress".
        let fake = FakeLocationInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "move-device", displayName: "Move Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .teleport
        state.stageLocation(first, for: .teleport)
        let session = LocationSessionIdentity(
            stableDeviceID: "move-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)

        let firstMove = Task { await state.startSimulation() }
        try await waitForPendingApplication(fake)
        let secondMove = Task { await state.startSimulation() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let pendingWhileFirstApplies = await fake.pendingApplicationCount()
        XCTAssertEqual(pendingWhileFirstApplies, 1, "the second Move must not start a second application")
        await fake.releaseNextApplication(session: session)
        await fake.releaseNextApplication(session: session)  // drains a second one if it exists
        await firstMove.value
        await secondMove.value

        let applies = await fake.calls().filter { if case .apply = $0 { return true }; return false }
        XCTAssertEqual(applies.count, 1)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
    }

    func testRouteStepIsTheShownSpeedPerUpdate() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        state.autoSpeed = false
        state.customSpeedMps = 4
        state.updateFrequencyHz = 5
        XCTAssertEqual(state.routeStepMeters, 0.8, accuracy: 1e-9)
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

/// PRODUCT_REQUIREMENTS 5.2 (owner decision 2026-11-02): after a successful Clear the last
/// spoofed coordinate stays on the map as a staged start for the next mode. It is shown as
/// staged, not applied, and nothing is sent until the user starts a mode.
@MainActor
final class ClearStagingTests: XCTestCase {
    private let first = LocationCoordinate(latitude: 35.67620, longitude: 139.65030)
    private let second = LocationCoordinate(latitude: 35.67621, longitude: 139.65031)
    private let third = LocationCoordinate(latitude: 35.67622, longitude: 139.65032)
    private let session = LocationSessionIdentity(
        stableDeviceID: "stage-device", transport: .usb, endpointClass: .direct, generation: 1
    )
    private static let stagedStatus = "Location cleared. The last spot is staged for the next mode."

    private final class Flag { var value = false }

    private func makeState(injector: FakeLocationInjector) -> AppState {
        // A real (short) delay: the joystick loop must suspend while the stick is idle.
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            routeDelay: { _ in try? await Task.sleep(nanoseconds: 1_000_000) }
        )
        state.selectedDevice = Device(id: "stage-device", displayName: "Stage Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = .teleport
        state.simulationSpeed = .teleport
        state.locationSessionCoordinator.connectionReady(session)
        return state
    }

    /// Bounded: a regression that never applies fails instead of hanging the suite.
    private func waitForPendingApplication(_ fake: FakeLocationInjector, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await fake.pendingApplicationCount() > 0 { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    private func appliedCoordinates(_ fake: FakeLocationInjector) async -> [LocationCoordinate] {
        await fake.calls().compactMap { call -> LocationCoordinate? in
            if case .apply(let request) = call { return request.coordinate }
            return nil
        }
    }

    private func teleport(_ state: AppState, _ fake: FakeLocationInjector, to point: LocationCoordinate) async {
        state.stageLocation(point, for: .teleport)
        let move = Task { await state.startSimulation() }
        guard await waitForPendingApplication(fake) else {
            move.cancel()
            await move.value
            return XCTFail("Teleport Move sent nothing")
        }
        await fake.releaseNextApplication(session: session)
        await move.value
    }

    /// Teleports to `first`, then Clears successfully.
    private func spoofThenClear() async -> (AppState, FakeLocationInjector) {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)
        await teleport(state, fake, to: first)
        XCTAssertEqual(state.locationPresentation.appliedCoordinate, first)
        await state.clearLocation()
        return (state, fake)
    }

    func testSuccessfulClearStagesTheLastSpoofedPointWithoutSendingIt() async {
        let (state, fake) = await spoofThenClear()

        XCTAssertEqual(state.stagedStartAfterClear, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertEqual(state.locationPresentation.desiredCoordinate, first)
        XCTAssertNil(state.locationPresentation.appliedCoordinate)
        XCTAssertFalse(state.locationPresentation.isSpoofing)
        XCTAssertEqual(state.targetLocation, first)
        XCTAssertNil(state.currentLocation)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertFalse(state.locationPresentation.canClear, "nothing is on the device to clear")
        XCTAssertEqual(state.statusMessage, Self.stagedStatus)
        XCTAssertEqual(state.locationMarker, LocationMarker(coordinate: first, style: .staged))

        try? await Task.sleep(nanoseconds: 100_000_000)
        let applied = await appliedCoordinates(fake)
        XCTAssertEqual(applied, [first], "the staged point is not sent to the device")
        let pending = await fake.pendingApplicationCount()
        XCTAssertEqual(pending, 0)
    }

    func testTeleportMoveAfterClearAppliesTheStagedPoint() async {
        let (state, fake) = await spoofThenClear()

        let move = Task { await state.startSimulation() }
        guard await waitForPendingApplication(fake) else {
            move.cancel()
            await move.value
            return XCTFail("Teleport Move after Clear sent nothing")
        }
        await fake.releaseNextApplication(session: session)
        await move.value

        let applied = await appliedCoordinates(fake)
        XCTAssertEqual(applied, [first, first])
        XCTAssertEqual(state.locationPresentation.appliedCoordinate, first)
        XCTAssertNil(state.stagedStartAfterClear, "an applied location ends the staged start")
        XCTAssertEqual(state.locationMarker, LocationMarker(coordinate: first, style: .spoofed))
    }

    func testJoystickAfterClearStartsAtTheStagedPoint() async {
        let (state, fake) = await spoofThenClear()
        state.activeMode = .joystick
        XCTAssertEqual(state.stagedStartAfterClear, first, "a mode change keeps the staged start")

        let engage = Task { await state.startSimulation() }
        guard await waitForPendingApplication(fake) else {
            engage.cancel()
            await engage.value
            return XCTFail("Joystick after Clear sent nothing")
        }
        let applied = await appliedCoordinates(fake)
        XCTAssertEqual(applied.last, first)
        await fake.releaseNextApplication(session: session)
        await engage.value
        await state.stopSimulation()
        if await fake.pendingApplicationCount() > 0 {
            await fake.releaseNextApplication(session: session)
        }
        XCTAssertNil(state.stagedStartAfterClear)
    }

    func testTwoSpotWithOneSpotAfterClearTravelsFromTheStagedPoint() async {
        let (state, fake) = await spoofThenClear()
        // Teleport staging leaves its point as the route; Reset route empties it, so
        // Two-Spot has exactly the one spot picked next.
        state.clearRoute()
        state.activeMode = .twospot
        state.stageLocation(third, for: .twospot)
        XCTAssertEqual(state.currentRoute, [third])
        XCTAssertEqual(state.stagedStartAfterClear, first, "one Two-Spot spot keeps the staged start")
        XCTAssertEqual(state.moveStartCoordinate, first)
        XCTAssertEqual(state.locationMarker, LocationMarker(coordinate: first, style: .staged))

        let done = Flag()
        let move = Task {
            await state.startSimulation()
            done.value = true
        }
        let deadline = Date().addingTimeInterval(3)
        while !done.value, Date() < deadline {
            if await fake.pendingApplicationCount() > 0 {
                await fake.releaseNextApplication(session: session)
            } else {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        if !done.value {
            await state.stopSimulation()
            move.cancel()
        }
        await move.value

        let applied = await appliedCoordinates(fake)
        XCTAssertGreaterThanOrEqual(applied.count, 3, "the travel must reach the device, got \(applied)")
        XCTAssertEqual(applied.dropFirst().first, first, "Two-Spot leaves from the staged point")
        XCTAssertEqual(applied.last, third)
        XCTAssertEqual(state.locationPresentation.appliedCoordinate, third)
        XCTAssertNil(state.stagedStartAfterClear)
    }

    func testTwoSpotWithTwoSpotsAfterClearIgnoresTheStagedPoint() async {
        let (state, _) = await spoofThenClear()
        state.clearRoute()
        state.activeMode = .twospot
        state.stageLocation(second, for: .twospot)
        state.stageLocation(third, for: .twospot)
        XCTAssertEqual(state.currentRoute, [second, third])
        XCTAssertNil(state.stagedStartAfterClear, "two picked spots define the start")
    }

    func testStagingANewPointReplacesTheStagedStart() async {
        let (state, fake) = await spoofThenClear()
        state.stageLocation(second, for: .teleport)

        XCTAssertNil(state.stagedStartAfterClear)
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, second)
        XCTAssertEqual(state.locationMarker, LocationMarker(coordinate: second, style: .staged))
        let applied = await appliedCoordinates(fake)
        XCTAssertEqual(applied, [first])
    }

    func testFailedClearStagesNothing() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)
        await teleport(state, fake, to: first)
        let receipt = state.locationSessionCoordinator.state.lastAcknowledgedReceipt
        await fake.setShouldFailClear(true)

        await state.clearLocation()

        XCTAssertNil(state.stagedStartAfterClear)
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        XCTAssertNotEqual(state.statusMessage, Self.stagedStatus)
        XCTAssertTrue(state.statusMessage?.hasPrefix("Unable to clear location") ?? false)
    }

    func testClearWithNothingSpoofedStagesNothing() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)

        await state.clearLocation()

        XCTAssertNil(state.stagedStartAfterClear)
        XCTAssertNil(state.targetLocation)
        XCTAssertNil(state.locationMarker)
    }

    /// Phase 3 (automatic reconnect) depends on this: a staged point is never sent
    /// automatically, even when the connection drops after the Clear and recovery runs.
    func testRecoveryAfterClearNeverSendsTheStagedPoint() async {
        let (state, fake) = await spoofThenClear()
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)

        state.submitLocationBridgeEvent(.sessionLost(session, reason: "Test transport loss"))
        let recovered = LocationSessionIdentity(
            stableDeviceID: session.stableDeviceID, transport: session.transport,
            endpointClass: session.endpointClass, generation: session.generation + 1
        )
        state.startLocationRecovery(
            strategy: ReconnectionStrategy(
                maxAttempts: 1, initialDelaySeconds: 0, maxDelaySeconds: 0,
                backoffMultiplier: 1, jitterFactor: 0
            ),
            establishSession: { _, _ in recovered }
        )

        let sent = await waitForPendingApplication(fake, timeout: 0.3)
        if sent { await fake.failNextApplication(code: "Test cleanup") }
        XCTAssertFalse(sent, "recovery must not send a staged point")
        let applied = await appliedCoordinates(fake)
        XCTAssertEqual(applied, [first])
        XCTAssertNil(state.locationPresentation.appliedCoordinate)
        XCTAssertEqual(state.stagedStartAfterClear, first)
    }
}
