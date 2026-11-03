//
//  StopTravelEngineTests.swift
//  PathChangerTests
//
//  AppState's one stop-by-stop engine for Jump, Two-Spot and Multi-Spot
//  (PRODUCT_REQUIREMENTS 3.2-3.4, 3.6 and 4).
//

import XCTest
@testable import PathChanger

/// Acknowledges every application at once, after an optional main-actor hook.
private actor AutoAckInjector: LocationInjecting {
    private var applied: [LocationCoordinate] = []
    private var onApply: (@MainActor @Sendable (Int, LocationCoordinate) async -> Void)?

    func setOnApply(_ hook: (@MainActor @Sendable (Int, LocationCoordinate) async -> Void)?) { onApply = hook }

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        applied.append(request.coordinate)
        if let onApply { await onApply(applied.count, request.coordinate) }
        return LocationInjectionReceipt(
            requestID: request.id,
            session: UUID(),
            coordinate: request.coordinate,
            transport: request.target.transport,
            actualChannel: request.target.transport == .usb ? .usbLockdown : .networkLockdown,
            endpointClass: .direct,
            sessionGeneration: request.sessionGeneration ?? 1,
            completedAt: Date(),
            outcome: .applied
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}
    func events() async -> AsyncStream<LocationBridgeEvent> { AsyncStream { _ in } }
    func appliedCoordinates() -> [LocationCoordinate] { applied }
}

/// Returns one fixed road route and records the travel mode of each request.
private actor RecordingRoadRouter: RoadRouting {
    private let fixed: RoadRoute
    private(set) var travels: [SimulationSpeed] = []

    init(route: RoadRoute) { fixed = route }

    func route(from: LocationCoordinate, to: LocationCoordinate, travel: SimulationSpeed) async -> RoadRoute {
        travels.append(travel)
        return fixed
    }
}

/// Records which legs were asked for, and how many points had been applied by then.
private actor PathRequests {
    private(set) var requests: [(from: LocationCoordinate, to: LocationCoordinate, appliedBefore: Int)] = []
    func record(_ from: LocationCoordinate, _ to: LocationCoordinate, appliedBefore: Int) {
        requests.append((from, to, appliedBefore))
    }
}

/// Records the travel mode of each leg path request.
private actor TravelRequests {
    private(set) var travels: [SimulationSpeed] = []
    func record(_ travel: SimulationSpeed) { travels.append(travel) }
}

/// Holds a leg path request until it is opened (by the test, or by cancellation, like
/// the road router that returns at once when cancelled).
private actor PathGate {
    private var entered = false
    private var opened = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        guard !opened else { return }
        await withCheckedContinuation { release = $0 }
    }

    func waitEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        opened = true
        release?.resume()
        release = nil
    }
}

/// One AppState wired to the auto-acknowledging injector, with every apply and every
/// route delay recorded in order.
@MainActor
private final class StopRunHarness {
    enum Event: Equatable {
        case apply(LocationCoordinate)
        case delay(TimeInterval, holding: Bool)
    }

    let injector = AutoAckInjector()
    var state: AppState!
    var events: [Event] = []
    var onApply: ((Int, LocationCoordinate) async -> Void)?
    /// Called on every route delay with its 1-based index among holding delays (0 when
    /// the delay is not a hold tick).
    var onDelay: ((_ holdTick: Int) -> Void)?
    private var holdTicks = 0

    static let session = LocationSessionIdentity(
        stableDeviceID: "stop-device", transport: .wifi, endpointClass: .unresolved, generation: 1
    )

    static func make(
        mode: AppMode,
        stops: [LocationCoordinate],
        settings: StopTravelSettings? = nil,
        metersPerSecond: Double = 20,
        updateHz: Double = 5
    ) async -> StopRunHarness {
        let harness = StopRunHarness()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: harness.injector,
            routeDelay: { [weak harness] seconds in await harness?.delay(seconds) }
        )
        harness.state = state
        state.selectedDevice = Device(id: "stop-device", displayName: "Stop Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = mode
        state.autoSpeed = false
        state.customSpeedMps = metersPerSecond
        state.updateFrequencyHz = updateHz
        for stop in stops { state.stageLocation(stop, for: mode) }
        if let settings { state.setStopTravelSettings(settings, for: mode) }
        state.locationSessionCoordinator.connectionReady(session)
        await harness.injector.setOnApply { [weak harness] count, coordinate in
            harness?.events.append(.apply(coordinate))
            await harness?.onApply?(count, coordinate)
        }
        return harness
    }

    private func delay(_ seconds: TimeInterval) async {
        let holding = state.stopProgress?.holdSecondsLeft != nil
        events.append(.delay(seconds, holding: holding))
        if holding { holdTicks += 1 }
        onDelay?(holding ? holdTicks : 0)
        await Task.yield()
    }

    var applied: [LocationCoordinate] {
        events.compactMap { if case .apply(let coordinate) = $0 { return coordinate }; return nil }
    }

    /// Total delay (all kinds) between each apply and the next; the last entry is the
    /// delay after the final apply.
    var delayAfterEachApply: [TimeInterval] {
        var gaps: [TimeInterval] = []
        for event in events {
            switch event {
            case .apply: gaps.append(0)
            case .delay(let seconds, _): if !gaps.isEmpty { gaps[gaps.count - 1] += seconds }
            }
        }
        return gaps
    }

    /// Hold seconds counted down after each apply.
    var holdAfterEachApply: [TimeInterval] {
        var gaps: [TimeInterval] = []
        for event in events {
            switch event {
            case .apply: gaps.append(0)
            case .delay(let seconds, let holding): if holding, !gaps.isEmpty { gaps[gaps.count - 1] += seconds }
            }
        }
        return gaps
    }

    func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition not reached", file: file, line: line)
    }
}

@MainActor
final class StopTravelEngineTests: XCTestCase {
    // About 100 m apart: north, then east.
    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)

    private func settings(
        _ arrival: StopTravelSettings.Arrival,
        timing: StopTravelSettings.JumpTiming = .fixed,
        hold: Double = 0,
        progression: StopTravelSettings.Progression = .automatic,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> StopTravelSettings {
        StopTravelSettings(arrival: arrival, jumpTiming: timing, holdSeconds: hold, progression: progression, repeatMode: repeatMode)
    }

    private func expectedPoints(
        _ stops: [LocationCoordinate],
        settings: StopTravelSettings,
        origin: LocationCoordinate? = nil,
        cursor: StopCursor = StopCursor()
    ) -> [LocationCoordinate] {
        guard case .success(let steps) = StopTravelPlanner.plan(
            stops: stops, origin: origin, cursor: cursor, settings: settings,
            metersPerSecond: 20, updateHz: 5, maxLegs: 50
        ) else { return [] }
        return steps.flatMap { step -> [LocationCoordinate] in
            switch step {
            case .travel(let points, _): return points
            case .jump(let to, _, _): return [to]
            case .hold: return []
            }
        }
    }

    private func assertHeld(_ state: AppState, at coordinate: LocationCoordinate?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.currentLocation, coordinate, file: file, line: line)
        guard case .active(let receipt) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the location must hold, got \(state.locationSessionCoordinator.state.application)", file: file, line: line)
        }
        XCTAssertEqual(receipt.coordinate, coordinate, file: file, line: line)
        XCTAssertFalse(state.isMovementEngineRunning, file: file, line: line)
        XCTAssertNil(state.stopProgress, "no run, no progress", file: file, line: line)
    }

    // MARK: - Getting there

    func testJumpTravelArrivalMovesAlongTheRoadAndAdvancesOnlyOnArrival() async {
        var travel = StopTravelSettings.defaults(for: .jump)
        travel.arrival = .travel
        let harness = await StopRunHarness.make(mode: .jump, stops: [s0, s1], settings: travel)
        let state = harness.state!
        let east = LocationCoordinate(latitude: s0.latitude, longitude: s0.longitude + 0.0005)
        let eastNorth = LocationCoordinate(latitude: s1.latitude, longitude: s0.longitude + 0.0005)
        let requests = PathRequests()
        let injector = harness.injector
        state.legPathProvider = { from, to, _ in
            await requests.record(from, to, appliedBefore: await injector.appliedCoordinates().count)
            return LegPath(points: [from, east, eastNorth, to], followsRoads: true, note: nil)
        }

        // Move 1 places the first stop (nothing to travel from).
        await state.startSimulation()
        XCTAssertEqual(harness.applied, [s0])
        XCTAssertEqual(state.jumpIndex, 1)

        // Move 2 travels to the second stop along the road.
        var indexDuringLeg: [Int] = []
        harness.onApply = { _, _ in indexDuringLeg.append(state.jumpIndex) }
        await state.startSimulation()
        let leg = Array(harness.applied.dropFirst())
        XCTAssertGreaterThan(leg.count, 20, "the leg is travelled, not jumped")
        XCTAssertEqual(leg.last, s1)
        XCTAssertLessThan(leg.map { Geo.distance(from: $0, to: east) }.min() ?? .infinity, 3, "it follows the road path")
        XCTAssertEqual(Set(indexDuringLeg), [1], "the index advances only when the stop is reached and acknowledged")
        XCTAssertEqual(state.jumpIndex, 2)
        let asked = await requests.requests
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.from, s0)
        XCTAssertEqual(asked.first?.to, s1)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.jumpTeleport))
        assertHeld(state, at: s1)
    }

    func testMultiSpotJumpArrivalTeleportsAfterTheRealisticTripTime() async {
        let harness = await StopRunHarness.make(
            mode: .route, stops: [s0, s1, s2],
            settings: settings(.jump, timing: .realistic, hold: 2)
        )
        await harness.state.startSimulation()

        XCTAssertEqual(harness.applied, [s0, s1, s2], "each stop is one teleport")
        let gaps = harness.delayAfterEachApply
        XCTAssertEqual(gaps[0], 2 + Geo.distance(from: s0, to: s1) / 20, accuracy: 0.01)
        XCTAssertEqual(gaps[1], 2 + Geo.distance(from: s1, to: s2) / 20, accuracy: 0.01)
        XCTAssertEqual(gaps[2], 0, "nothing after the last stop of a one-way run")
        XCTAssertEqual(harness.state.locationSessionCoordinator.state.movement, .completed(.multiSpot))
        assertHeld(harness.state, at: s2)
    }

    func testTwoSpotFixedJumpWaitsTheStopTime() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1], settings: settings(.jump, hold: 3))
        await harness.state.startSimulation()

        XCTAssertEqual(harness.applied, [s0, s1])
        XCTAssertEqual(harness.delayAfterEachApply, [3, 0])
        XCTAssertEqual(harness.state.locationSessionCoordinator.state.movement, .completed(.twoSpot))
        assertHeld(harness.state, at: s1)
    }

    func testTravelHoldsEachReachedStopExceptTheLast() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: settings(.travel, hold: 2))
        await harness.state.startSimulation()

        XCTAssertEqual(harness.applied, expectedPoints([s0, s1, s2], settings: settings(.travel, hold: 2)))
        let holds = zip(harness.applied, harness.holdAfterEachApply).filter { $0.1 > 0 }
        XCTAssertEqual(holds.map(\.0), [s0, s1], "a hold at each reached stop, none after the last")
        XCTAssertEqual(holds.map(\.1), [2, 2])
        assertHeld(harness.state, at: s2)
    }

    // MARK: - Go through

    func testOneStopPerMoveInMultiSpot() async {
        let oneEach = settings(.travel, hold: 5, progression: .onePerMove)
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: oneEach)
        let state = harness.state!

        await state.startSimulation()
        XCTAssertEqual(harness.applied, [s0])
        XCTAssertEqual(state.routeStopIndex, 1)

        await state.startSimulation()
        XCTAssertEqual(harness.applied.last, s1)
        XCTAssertGreaterThan(harness.applied.count, 10, "the second stop is travelled to")
        XCTAssertEqual(state.routeStopIndex, 2)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.multiSpot))
        XCTAssertFalse(harness.events.contains { if case .delay(_, true) = $0 { return true }; return false }, "one stop per Move holds until the next Move")
        assertHeld(state, at: s1)

        await state.startSimulation()
        XCTAssertEqual(harness.applied.last, s2)
        XCTAssertEqual(state.routeStopIndex, 3)

        // A finished one-way run starts again from the first stop.
        await state.startSimulation()
        XCTAssertEqual(harness.applied.last, s0)
        XCTAssertEqual(state.routeStopIndex, 1)
    }

    func testOneJumpPerMoveBackAndForthKeepsItsDirection() async {
        let harness = await StopRunHarness.make(
            mode: .jump, stops: [s0, s1, s2],
            settings: settings(.jump, progression: .onePerMove, repeat: .backAndForth)
        )
        for _ in 0..<5 { await harness.state.startSimulation() }
        XCTAssertEqual(harness.applied, [s0, s1, s2, s1, s0])
        XCTAssertEqual(harness.state.jumpIndex, 1)
    }

    func testLoopTravelsHomeAndContinuesUntilStop() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1], settings: settings(.travel, repeat: .loop))
        let state = harness.state!
        var arrivals = 0
        harness.onApply = { _, coordinate in
            if coordinate == self.s0 || coordinate == self.s1 { arrivals += 1 }
            if arrivals == 4 { await state.stopSimulation() }
        }
        await state.startSimulation()

        let applied = harness.applied
        let stops = applied.filter { $0 == s0 || $0 == s1 }
        XCTAssertEqual(stops, [s0, s1, s0, s1], "home to the first stop, then on again")
        let home = applied.firstIndex(of: s1).map { applied[($0 + 1)...] }.map(Array.init) ?? []
        XCTAssertGreaterThan(home.prefix { $0 != s0 }.count, 10, "the home leg is travelled the same way")
        assertHeld(state, at: s1)
    }

    // MARK: - Pause and resume

    func testPauseMidLegHoldsAndResumeContinuesFromTheAcknowledgedPoint() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        harness.onApply = { count, _ in if count == 5 { state.pauseMovement() } }
        let run = Task { await state.startSimulation() }

        await harness.waitUntil { state.stopProgress?.isPaused == true && harness.applied.count == 5 }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(harness.applied.count, 5, "nothing is applied while paused")
        XCTAssertEqual(state.currentLocation, harness.applied[4], "pause holds the latest applied point")
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .paused(.twoSpot))
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertTrue(state.isMovementEngineRunning, "Move shows Stop while paused")

        state.resumeMovement()
        await run.value
        XCTAssertEqual(harness.applied, expectedPoints([s0, s1], settings: .defaults(for: .twospot)), "resume continues with the next point")
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.twoSpot))
        assertHeld(state, at: s1)
    }

    func testPauseMidHoldStopsTheCountdownUntilResume() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1], settings: settings(.jump, hold: 3))
        let state = harness.state!
        harness.onDelay = { holdTick in if holdTick == 2 { state.pauseMovement() } }
        let run = Task { await state.startSimulation() }

        await harness.waitUntil { state.stopProgress?.isPaused == true }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(harness.applied, [s0])
        XCTAssertEqual(state.stopProgress?.holdSecondsLeft, 1, "the countdown stops where it was")
        XCTAssertEqual(state.stopProgress?.heldStopIndex, 0)
        XCTAssertEqual(state.stopProgress?.nextStopIndex, 1)
        XCTAssertEqual(harness.holdAfterEachApply.reduce(0, +), 2)

        state.resumeMovement()
        await run.value
        XCTAssertEqual(harness.applied, [s0, s1])
        XCTAssertEqual(harness.holdAfterEachApply, [3, 0], "the hold resumes for the time that was left")
        assertHeld(state, at: s1)
    }

    // MARK: - Stop, Clear and ending a run

    func testStopMidLegEndsTheRunAndHoldsTheLastAppliedPoint() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        harness.onApply = { count, _ in if count == 4 { await state.stopSimulation() } }
        await state.startSimulation()

        XCTAssertEqual(harness.applied.count, 4, "nothing is applied after Stop")
        if case .moving = state.locationSessionCoordinator.state.movement { XCTFail("Stop ends movement") }
        assertHeld(state, at: harness.applied[3])
    }

    func testClearDuringAHoldWins() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1], settings: settings(.jump, hold: 5))
        let state = harness.state!
        var clearing: Task<Void, Never>?
        harness.onDelay = { holdTick in if holdTick == 1 { clearing = Task { await state.clearLocation() } } }
        await state.startSimulation()
        await clearing?.value

        XCTAssertEqual(harness.applied, [s0], "no stop after Clear")
        XCTAssertNil(state.currentLocation)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertNil(state.stopProgress)
        XCTAssertFalse(state.isMovementEngineRunning)
    }

    func testEditingTheStopsTheSettingsOrTheModeEndsTheRunAndHolds() async {
        for change in ["stops", "settings", "mode"] {
            let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: settings(.jump, hold: 2))
            let state = harness.state!
            harness.onDelay = { holdTick in
                guard holdTick == 1 else { return }
                switch change {
                case "stops": state.removeRouteWaypoint(at: 2)
                case "settings": state.setStopTravelSettings(self.settings(.jump, hold: 4), for: .route)
                default: state.activeMode = .teleport
                }
            }
            await state.startSimulation()

            XCTAssertEqual(harness.applied, [s0], "no stop after the change (\(change))")
            XCTAssertEqual(state.locationSessionCoordinator.state.movement, .completed(.multiSpot), change)
            assertHeld(state, at: s0)
        }
    }

    // MARK: - Truth

    func testTheStopIndexAdvancesOnlyOnAcknowledgedArrivals() async {
        let fake = FakeLocationInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "stop-device", displayName: "Stop Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .route
        for stop in [s0, s1, s2] { state.stageLocation(stop, for: .route) }
        state.setStopTravelSettings(settings(.jump), for: .route)
        state.locationSessionCoordinator.connectionReady(StopRunHarness.session)

        let run = Task { await state.startSimulation() }
        for index in 0..<3 {
            await fake.waitUntilApplicationPending()
            XCTAssertEqual(state.routeStopIndex, index, "not before the receipt")
            XCTAssertEqual(state.stopProgress?.nextStopIndex, index)
            XCTAssertEqual(state.stopProgress?.totalStops, 3)
            await fake.releaseNextApplication(session: StopRunHarness.session)
        }
        await run.value
        XCTAssertEqual(state.routeStopIndex, 3)

        // A queued (unacknowledged) arrival does not advance.
        state.setStopTravelSettings(settings(.jump, progression: .onePerMove), for: .route)
        state.removeRouteWaypoint(at: 2)
        XCTAssertEqual(state.routeStopIndex, 0, "editing the stops resets the stop index")
        let queued = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: StopRunHarness.session, outcome: .queued)
        await queued.value
        XCTAssertEqual(state.routeStopIndex, 0)
    }

    func testStopProgressReportsTheLegAndTheStraightLineFallback() async {
        for followsRoads in [false, true] {
            let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
            let state = harness.state!
            state.legPathProvider = { from, to, _ in
                followsRoads
                    ? LegPath(points: [from, to], followsRoads: true, note: nil)
                    : .straight(from: from, to: to, note: "No road route; going in a straight line")
            }
            var seen: StopProgress?
            harness.onApply = { count, _ in if count == 3 { seen = state.stopProgress } }
            await state.startSimulation()

            let legPoints = expectedPoints([s0, s1], settings: .defaults(for: .twospot)).count - 1
            XCTAssertEqual(seen?.nextStopIndex, 1)
            XCTAssertEqual(seen?.totalStops, 2)
            XCTAssertNil(seen?.holdSecondsLeft)
            XCTAssertEqual(seen?.isPaused, false)
            XCTAssertEqual(seen?.legSecondsLeft ?? -1, Double(legPoints - 1) * 0.2, accuracy: 0.001)
            XCTAssertEqual(seen?.usesStraightLineFallback, !followsRoads)
            XCTAssertEqual(seen?.fallbackNote, followsRoads ? nil : "No road route; going in a straight line")
            XCTAssertNil(state.stopProgress, "nil once the run ends")
        }
    }

    func testEachLegPathIsFetchedJustBeforeItsLeg() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2])
        let requests = PathRequests()
        let injector = harness.injector
        harness.state.legPathProvider = { from, to, _ in
            await requests.record(from, to, appliedBefore: await injector.appliedCoordinates().count)
            return .straight(from: from, to: to)
        }
        await harness.state.startSimulation()

        let firstLeg = expectedPoints([s0, s1], settings: .defaults(for: .route)).count - 1
        let asked = await requests.requests
        XCTAssertEqual(asked.map(\.from), [s0, s1])
        XCTAssertEqual(asked.map(\.to), [s1, s2])
        XCTAssertEqual(asked.map(\.appliedBefore), [1, 1 + firstLeg], "each leg is fetched when the run reaches it")
        assertHeld(harness.state, at: s2)
    }

    // MARK: - One stop per Move with Loop or Back and forth (review 2026-11-02, finding 1)

    /// Points applied by one Move.
    private func pointsOfNextMove(_ harness: StopRunHarness) async -> [LocationCoordinate] {
        let before = harness.applied.count
        await harness.state.startSimulation()
        return Array(harness.applied.dropFirst(before))
    }

    func testTwoSpotLoopOneStopPerMoveTravelsHomeOnTheWrap() async {
        let harness = await StopRunHarness.make(
            mode: .twospot, stops: [s0, s1],
            settings: settings(.travel, progression: .onePerMove, repeat: .loop)
        )
        let move1 = await pointsOfNextMove(harness)
        XCTAssertEqual(move1, [s0], "a fresh run places the first stop")
        let move2 = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(move2.count, 10)
        XCTAssertEqual(move2.last, s1)
        XCTAssertEqual(harness.state.routeStopIndex, 0, "Loop wraps to the first stop")

        let move3 = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(move3.count, 10, "the wrap leg is travelled home, not teleported")
        XCTAssertEqual(move3.last, s0)
        XCTAssertLessThan(Geo.distance(from: move3.first ?? s0, to: s1), 10, "it leaves from the held stop")
        XCTAssertEqual(harness.state.routeStopIndex, 1)
        assertHeld(harness.state, at: s0)

        let move4 = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(move4.count, 10)
        XCTAssertEqual(move4.last, s1)
    }

    func testTwoSpotBackAndForthOneStopPerMoveTravelsBack() async {
        let harness = await StopRunHarness.make(
            mode: .twospot, stops: [s0, s1],
            settings: settings(.travel, progression: .onePerMove, repeat: .backAndForth)
        )
        _ = await pointsOfNextMove(harness)
        _ = await pointsOfNextMove(harness)
        let back = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(back.count, 10, "the return leg is travelled")
        XCTAssertEqual(back.last, s0)
        let forth = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(forth.count, 10)
        XCTAssertEqual(forth.last, s1)
        assertHeld(harness.state, at: s1)
    }

    func testMultiSpotLoopOneStopPerMoveTravelsTheWrapLeg() async {
        let harness = await StopRunHarness.make(
            mode: .route, stops: [s0, s1, s2],
            settings: settings(.travel, progression: .onePerMove, repeat: .loop)
        )
        for _ in 0..<3 { _ = await pointsOfNextMove(harness) }
        XCTAssertEqual(harness.applied.last, s2)
        let wrap = await pointsOfNextMove(harness)
        XCTAssertGreaterThan(wrap.count, 10, "the leg home to stop 1 is travelled")
        XCTAssertEqual(wrap.last, s0)
        XCTAssertEqual(harness.state.routeStopIndex, 1)
        assertHeld(harness.state, at: s0)
    }

    func testAFreshOneStopPerMoveRunStillPlacesItsStop() async {
        let looped = settings(.travel, progression: .onePerMove, repeat: .loop)
        // After the stops change: the stop index resets. Owner rule 2026-11-03: stop 1
        // is reached from the held stop per Getting there (it used to be placed).
        let edited = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: looped)
        for _ in 0..<3 { _ = await pointsOfNextMove(edited) }
        edited.state.removeRouteWaypoint(at: 2)
        edited.state.stageLocation(s2, for: .route)
        XCTAssertEqual(edited.state.routeStopIndex, 0)
        let afterEdit = await pointsOfNextMove(edited)
        XCTAssertGreaterThan(afterEdit.count, 10, "travelled from the held stop, not placed")
        XCTAssertEqual(afterEdit.last, s0, "the new stop sequence starts at its first stop")

        // After Clear: nothing is held, so the stop is placed, not travelled to.
        let cleared = await StopRunHarness.make(mode: .twospot, stops: [s0, s1], settings: looped)
        _ = await pointsOfNextMove(cleared)
        _ = await pointsOfNextMove(cleared)
        await cleared.state.clearLocation()
        XCTAssertNil(cleared.state.currentLocation)
        let afterClear = await pointsOfNextMove(cleared)
        XCTAssertEqual(afterClear.count, 1, "nothing to travel from after Clear")
    }

    // MARK: - A failed step (finding 2)

    private func makeFakeState(
        mode: AppMode,
        stops: [LocationCoordinate],
        settings: StopTravelSettings
    ) -> (AppState, FakeLocationInjector) {
        let fake = FakeLocationInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "stop-device", displayName: "Stop Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = mode
        state.autoSpeed = false
        state.customSpeedMps = 20
        state.updateFrequencyHz = 5
        for stop in stops { state.stageLocation(stop, for: mode) }
        state.setStopTravelSettings(settings, for: mode)
        state.locationSessionCoordinator.connectionReady(StopRunHarness.session)
        return (state, fake)
    }

    func testAFailedStepEndsMovementWithoutAPhantomPause() async {
        for pausedFirst in [false, true] {
            let (state, fake) = makeFakeState(mode: .route, stops: [s0, s1, s2], settings: settings(.jump, hold: 2))
            let run = Task { await state.startSimulation() }
            await fake.waitUntilApplicationPending()
            await fake.releaseNextApplication(session: StopRunHarness.session)
            await fake.waitUntilApplicationPending()
            if pausedFirst { state.pauseMovement() }
            await fake.failNextApplication(code: "boom")
            await run.value

            let label = pausedFirst ? "paused before the failure" : "running"
            XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle, "a failed run is not resumable (\(label))")
            XCTAssertFalse(state.locationPresentation.isMovementActive, label)
            XCTAssertFalse(state.isPaused, "the pause ends with the run (\(label))")
            XCTAssertFalse(state.isMovementEngineRunning, label)
            XCTAssertNil(state.stopProgress, label)
            XCTAssertEqual(state.currentLocation, s0, "the reached stop holds (\(label))")
            XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, s0, label)
            XCTAssertEqual(state.routeStopIndex, 1, label)
        }
    }

    // MARK: - Road notes (findings 3 and 4)

    func testRoadNotesReachTheReadoutOnlyWhenTheRouterHadOne() async {
        let cases: [(path: (LocationCoordinate, LocationCoordinate) -> LegPath, fallback: Bool, routeNote: String?)] = [
            // The router's same-place result: a 2-point path, no road, nothing to report.
            ({ LegPath(points: [$0, $1], followsRoads: false, note: nil) }, false, nil),
            // A road route with an informational note.
            ({ LegPath(points: [$0, $1], followsRoads: true, note: "Road route is over 500 km long") }, false,
             "Road route is over 500 km long"),
        ]
        for (path, fallback, routeNote) in cases {
            let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
            let state = harness.state!
            state.legPathProvider = { from, to, _ in path(from, to) }
            var seen: StopProgress?
            harness.onApply = { count, _ in if count == 3 { seen = state.stopProgress } }
            await state.startSimulation()

            XCTAssertEqual(seen?.usesStraightLineFallback, fallback)
            XCTAssertNil(seen?.fallbackNote)
            XCTAssertEqual(seen?.routeNote, routeNote)
        }
    }

    // MARK: - Directions transport for a custom speed (finding 5)

    func testCustomSpeedChoosesTheDirectionsTransportFromTheSpeed() async {
        let cases: [(Double, RoadTransport)] = [(2.0, .walking), (2.5, .walking), (6, .cycling), (8, .cycling), (30, .automobile)]
        for (metersPerSecond, expected) in cases {
            let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1], metersPerSecond: metersPerSecond, updateHz: 1)
            let state = harness.state!
            state.simulationSpeed = metersPerSecond > 8 ? .walking : .driving  // a stale preset
            state.autoSpeed = false
            let requests = TravelRequests()
            state.legPathProvider = { from, to, travel in
                await requests.record(travel)
                return .straight(from: from, to: to)
            }
            await state.startSimulation()
            let asked = await requests.travels
            XCTAssertEqual(asked.map(RoadTransport.init(travel:)), [expected], "custom \(metersPerSecond) m/s")
        }
    }

    func testPresetSpeedKeepsItsDirectionsTransport() async {
        let cases: [(SimulationSpeed, RoadTransport)] = [(.walking, .walking), (.cycling, .cycling), (.fast, .automobile), (.driving, .automobile)]
        for (preset, expected) in cases {
            let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1], updateHz: 1)
            let state = harness.state!
            state.customSpeedMps = 1  // a stale custom value
            state.simulationSpeed = preset
            state.autoSpeed = true
            let requests = TravelRequests()
            state.legPathProvider = { from, to, travel in
                await requests.record(travel)
                return .straight(from: from, to: to)
            }
            await state.startSimulation()
            let asked = await requests.travels
            XCTAssertEqual(asked, [preset], "\(preset)")
            XCTAssertEqual(asked.map(RoadTransport.init(travel:)), [expected])
        }
    }

    // MARK: - A run-ending edit does not overlap the next Move (finding 7)

    func testMoveAfterARunEndingEditWaitsForTheOldApplyToFinish() async {
        let (state, fake) = makeFakeState(mode: .route, stops: [s0, s1, s2], settings: settings(.jump, hold: 2))
        let first = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: StopRunHarness.session)
        await fake.waitUntilApplicationPending()  // stop 2 is at the bridge

        state.setStopTravelSettings(settings(.jump, hold: 3), for: .route)  // ends the run
        let second = Task { await state.startSimulation() }
        for _ in 0..<200 { await Task.yield() }
        let applies = await fake.calls().filter { if case .apply = $0 { return true }; return false }.count
        XCTAssertEqual(applies, 2, "no new apply while the old one is still at the bridge")

        await fake.releaseNextApplication(session: StopRunHarness.session)
        await first.value
        XCTAssertEqual(state.currentLocation, s1, "the old apply the device took holds")
        // Owner rule 2026-11-03: the Move after an option change continues from the held
        // stop 2 to stop 3 (it used to replay all three stops from stop 1).
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: StopRunHarness.session)
        await second.value
        let applied = await fake.calls().compactMap { call -> LocationCoordinate? in
            if case .apply(let request) = call { return request.coordinate }
            return nil
        }
        XCTAssertEqual(applied, [s0, s1, s2])
        XCTAssertEqual(state.currentLocation, s2)
        XCTAssertFalse(state.isMovementEngineRunning)
    }

    // MARK: - Pause while a point is in flight (finding 8)

    func testAPointLandingWhilePausedKeepsRoutePlaybackPaused() async {
        let (state, fake) = makeFakeState(mode: .route, stops: [s0, s1, s2], settings: settings(.jump, hold: 2))
        let run = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: StopRunHarness.session)
        await fake.waitUntilApplicationPending()
        state.pauseMovement()
        await fake.releaseNextApplication(session: StopRunHarness.session)
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(state.currentLocation, s1)
        XCTAssertEqual(state.route.playbackState, .paused, "the landed point does not resume playback")
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .paused(.multiSpot))
        await state.stopSimulation()
        await run.value
    }

    // MARK: - Stop and Clear while a road path is being fetched

    func testStopDuringARoadFetchEndsTheRunAndTheLatePathWritesNothing() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        let gate = PathGate()
        let middle = LocationCoordinate(latitude: s0.latitude, longitude: s1.longitude + 0.001)
        // Ignores cancellation: the late result arrives after Stop.
        state.legPathProvider = { from, to, _ in
            await gate.enter()
            return LegPath(points: [from, middle, to], followsRoads: true, note: "Road route is over 500 km long")
        }
        let run = Task { await state.startSimulation() }
        await gate.waitEntered()
        XCTAssertNotNil(state.stopProgress)

        await state.stopSimulation()
        XCTAssertFalse(state.isMovementEngineRunning, "Stop ends the run without waiting for the road")
        XCTAssertNil(state.stopProgress)

        await gate.open()
        await run.value
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(harness.applied, [s0], "nothing from the late path is applied")
        XCTAssertNil(state.stopProgress, "the late path writes no progress")
        if case .moving = state.locationSessionCoordinator.state.movement { XCTFail("not moving after Stop") }
        assertHeld(state, at: s0)
    }

    func testClearDuringARoadFetchEndsTheRunAndClears() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        let gate = PathGate()
        // Returns at once when cancelled, like the road router.
        state.legPathProvider = { from, to, _ in
            await withTaskCancellationHandler {
                await gate.enter()
            } onCancel: {
                Task { await gate.open() }
            }
            return .straight(from: from, to: to, note: MapKitRoadRouter.straightLineNote)
        }
        let run = Task { await state.startSimulation() }
        await gate.waitEntered()

        await state.clearLocation()
        await run.value
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(harness.applied, [s0], "nothing is applied after Clear")
        XCTAssertNil(state.currentLocation)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertNil(state.stopProgress)
        XCTAssertFalse(state.isMovementEngineRunning)
    }

    // MARK: - Road routing wiring

    func testRoadRouterAdapterCarriesTheRoadPathNoteAndTravelMode() async {
        let middle = LocationCoordinate(latitude: s0.latitude, longitude: s1.longitude)
        let router = RecordingRoadRouter(route: RoadRoute(
            points: [s0, middle, s1], distanceMeters: 1_234, followsRoads: true, note: "detour"
        ))
        let provider = AppState.roadLegPathProvider(router)

        let leg = await provider(s0, s1, .cycling)

        XCTAssertEqual(leg, LegPath(points: [s0, middle, s1], followsRoads: true, note: "detour"))
        let asked = await router.travels
        XCTAssertEqual(asked, [.cycling])
    }

    func testAnInjectedRoadRouterBecomesTheLegPathProvider() {
        let plain = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        XCTAssertNil(plain.legPathProvider, "without a router, legs are straight lines")

        let routed = AppState(
            startBackgroundServices: false,
            locationInjector: FakeLocationInjector(),
            roadRouter: RecordingRoadRouter(route: RoadRoute(points: [s0, s1], distanceMeters: 1, followsRoads: true, note: nil))
        )
        XCTAssertNotNil(routed.legPathProvider)
    }

    // MARK: - Settings

    func testSettingsArePerModeAndPersisted() throws {
        let suite = "PathChangerTests.StopTravelSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = RouteStateManager(routeLibrary: RouteLibraryManager(), settingsDefaults: defaults)
        XCTAssertEqual(first.stopTravelSettings(for: .jump), .defaults(for: .jump))
        let looped = settings(.jump, timing: .realistic, hold: 9, progression: .onePerMove, repeat: .loop)
        first.setStopTravelSettings(looped, for: .route)

        let second = RouteStateManager(routeLibrary: RouteLibraryManager(), settingsDefaults: defaults)
        XCTAssertEqual(second.stopTravelSettings(for: .route), looped)
        XCTAssertEqual(second.stopTravelSettings(for: .twospot), .defaults(for: .twospot))
        XCTAssertEqual(second.stopTravelSettings(for: .jump), .defaults(for: .jump))

        let memoryOnly = RouteStateManager(routeLibrary: RouteLibraryManager())
        memoryOnly.setStopTravelSettings(looped, for: .route)
        XCTAssertEqual(memoryOnly.stopTravelSettings(for: .route), looped)
    }

    func testAutoJumpAndLoopAreViewsOfTheModeSettings() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        XCTAssertFalse(state.autoJump)
        XCTAssertEqual(state.autoJumpPauseSeconds, 5)
        state.autoJump = true
        state.autoJumpPauseSeconds = 7
        XCTAssertEqual(state.stopTravelSettings(for: .jump).progression, .automatic)
        XCTAssertEqual(state.stopTravelSettings(for: .jump).holdSeconds, 7)
        state.autoJumpPauseSeconds = 0
        XCTAssertEqual(state.autoJumpPauseSeconds, 1, "the Auto jump pause stays 1-60 s")

        state.activeMode = .route
        state.loopRoute = true
        XCTAssertEqual(state.stopTravelSettings(for: .route).repeatMode, .loop)
        XCTAssertEqual(state.stopTravelSettings(for: .twospot).repeatMode, .oneWay)
        state.activeMode = .twospot
        XCTAssertFalse(state.loopRoute)
    }

    // MARK: - Panel truth (stop-panel lane, 2026-11-02)

    func testARealisticJumpWaitIsPublishedAsTheWaitBeforeTheJump() async {
        let harness = await StopRunHarness.make(
            mode: .jump, stops: [s0, s1],
            settings: settings(.jump, timing: .realistic, hold: 5, progression: .onePerMove)
        )
        let state = harness.state!
        await state.startSimulation()
        XCTAssertEqual(harness.applied, [s0], "Move 1 places stop 1")

        var phasesDuringWait: [StopProgress.Phase?] = []
        var appliedDuringWait: [Int] = []
        harness.onDelay = { _ in
            phasesDuringWait.append(state.stopProgress?.phase)
            appliedDuringWait.append(harness.applied.count)
        }
        await state.startSimulation()

        XCTAssertFalse(phasesDuringWait.isEmpty)
        XCTAssertEqual(Set(phasesDuringWait.compactMap { $0 }), [.waitingToJump], "every countdown tick is the wait before the jump")
        XCTAssertEqual(Set(appliedDuringWait), [1], "nothing is sent while waiting")
        XCTAssertEqual(harness.holdAfterEachApply.reduce(0, +), 0, "One stop per Move: At each stop does not apply")
        XCTAssertEqual(harness.delayAfterEachApply.reduce(0, +), Geo.distance(from: s0, to: s1) / 20, accuracy: 0.01)
        assertHeld(state, at: s1)
    }

    func testTravelAndHoldArePublishedAsTheirPhases() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: settings(.travel, hold: 2))
        let state = harness.state!
        var applyPhases: [StopProgress.Phase?] = []
        var holdPhases: [StopProgress.Phase?] = []
        harness.onApply = { _, _ in applyPhases.append(state.stopProgress?.phase) }
        harness.onDelay = { holdTick in if holdTick > 0 { holdPhases.append(state.stopProgress?.phase) } }
        await state.startSimulation()

        XCTAssertEqual(applyPhases.first ?? nil, .jumping, "the first stop is placed")
        XCTAssertEqual(Set(applyPhases.dropFirst().compactMap { $0 }), [.travelling])
        XCTAssertFalse(holdPhases.isEmpty)
        XCTAssertEqual(Set(holdPhases.compactMap { $0 }), [.holding])
        assertHeld(state, at: s2)
    }

    func testFetchingALegPathIsPublishedAsFindingTheRoute() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        let gate = PathGate()
        state.legPathProvider = { from, to, _ in
            await gate.enter()
            return .straight(from: from, to: to)
        }
        let run = Task { await state.startSimulation() }
        await gate.waitEntered()
        XCTAssertEqual(state.stopProgress?.phase, .findingRoute)
        await gate.open()
        await run.value
        assertHeld(state, at: s1)
    }

    func testTheReachedJumpStopSurvivesALoopWrap() async {
        let harness = await StopRunHarness.make(
            mode: .jump, stops: [s0, s1, s2],
            settings: settings(.jump, progression: .onePerMove, repeat: .loop)
        )
        let state = harness.state!
        for _ in 0..<3 { await state.startSimulation() }
        XCTAssertEqual(harness.applied, [s0, s1, s2])
        XCTAssertEqual(state.jumpIndex, 0, "the cursor wrapped: the old Hop row read 0/3 here")
        XCTAssertEqual(
            StopTravelCardText.reachedStop(
                stops: state.currentRoute,
                cursor: state.displayStopCursor(for: .jump),
                repeatMode: .loop,
                held: state.locationPresentation.appliedCoordinate
            ),
            2,
            "the phone holds stop 3"
        )
    }

    /// Review 2026-11-02-163337 issue 8: Two-Spot with one spot leaves from the held
    /// location, so the run's stops are [held, spot] while the route holds only the spot.
    /// The completion line read "stop 1 of 1" for that two-stop run.
    func testTwoSpotWithOneSpotReadsTheRunsStopsNotTheRoute() async {
        let harness = await StopRunHarness.make(mode: .teleport, stops: [s0])
        let state = harness.state!
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, s0, "the start is held")

        state.activeMode = .twospot
        state.clearRoute()
        state.stageLocation(s1, for: .twospot)
        XCTAssertEqual(state.currentRoute, [s1], "the route holds the one spot")
        await state.startSimulation()
        assertHeld(state, at: s1)

        let stops = state.displayStops(for: .twospot)
        XCTAssertEqual(stops, [s0, s1], "the run's stops start at the held location")
        let reached = StopTravelCardText.reachedStop(
            stops: stops,
            cursor: state.displayStopCursor(for: .twospot),
            repeatMode: state.stopTravelSettings(for: .twospot).repeatMode,
            held: state.locationPresentation.appliedCoordinate
        )
        XCTAssertEqual(reached, 1)
        XCTAssertEqual(
            StopTravelCardText.completionLine(
                movement: state.locationSessionCoordinator.state.movement,
                mode: .twospot,
                isHeld: true,
                reachedStop: reached,
                totalStops: stops.count
            ),
            "Done · holding stop 2 of 2"
        )
        XCTAssertEqual(state.displayStops(for: .jump), state.currentRoute, "Jump indexes its hops")
    }

    func testJoystickSpeedNeverChangesAStopRun() async {
        let harness = await StopRunHarness.make(mode: .twospot, stops: [s0, s1])
        let state = harness.state!
        state.joystickSpeed = 1
        await state.startSimulation()
        XCTAssertEqual(
            harness.applied,
            expectedPoints([s0, s1], settings: .defaults(for: .twospot)),
            "the run travels at the travel speed (20 m/s), not the joystick's"
        )
    }
}

// MARK: - Owner rule 2026-11-03: a Move continues from where the run stands

/// The same rule for Jump, Two-Spot and Multi-Spot, for every combination of the stop
/// options: (1) a Move goes to the next stop not yet reached, from the held location;
/// Stop, Pause, an option change, a mode change and a connection loss never send the run
/// back to stop 1. (2) Progress resets only on a stop edit, Reset Route or a confirmed
/// Clear. (3) A finished One way run starts over at stop 1, reached per Getting there
/// (placed only when nothing is held). (4) Loop and Back and forth return per their rule.
extension StopTravelEngineTests {
    private static let stopModes: [AppMode] = [.jump, .twospot, .route]

    private func runStops(for mode: AppMode) -> [LocationCoordinate] {
        mode == .twospot ? [s0, s1] : [s0, s1, s2]
    }

    private func options(
        _ mode: AppMode,
        arrival: StopTravelSettings.Arrival = .travel,
        progression: StopTravelSettings.Progression,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> StopTravelSettings {
        var options = StopTravelSettings.defaults(for: mode)
        options.arrival = arrival
        options.jumpTiming = .fixed
        options.holdSeconds = 0
        options.progression = progression
        options.repeatMode = repeatMode
        return options
    }

    private func move(_ harness: StopRunHarness) async -> [LocationCoordinate] {
        let before = harness.applied.count
        await harness.state.startSimulation()
        return Array(harness.applied.dropFirst(before))
    }

    // MARK: Rule 1

    func testAMoveAfterARunEndedMidLegContinuesToTheNextUnreachedStop() async {
        for mode in Self.stopModes {
            for ending in ["Stop", "Pause then Stop", "option change", "mode change"] {
                let label = "\(mode) after \(ending)"
                let stops = runStops(for: mode)
                let harness = await StopRunHarness.make(mode: mode, stops: stops, settings: options(mode, progression: .automatic))
                let state = harness.state!
                harness.onApply = { count, _ in
                    guard count == 6 else { return }
                    switch ending {
                    case "Stop":
                        await state.stopSimulation()
                    case "Pause then Stop":
                        state.pauseMovement()
                        await state.stopSimulation()
                    case "option change":
                        var changed = state.stopTravelSettings(for: mode)
                        changed.jumpTiming = .realistic
                        state.setStopTravelSettings(changed, for: mode)
                    default:
                        state.activeMode = .teleport
                    }
                }
                await state.startSimulation()
                harness.onApply = nil
                XCTAssertEqual(harness.applied.count, 6, "the run ended mid-leg (\(label))")
                if ending == "mode change" { state.activeMode = mode }
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 1, "stop 1 reached, stop 2 not (\(label))")
                guard let held = state.currentLocation else { XCTFail("held (\(label))"); continue }
                XCTAssertNotEqual(held, s0, label)

                let next = await move(harness)
                XCTAssertFalse(next.contains(s0), "never back to stop 1 (\(label))")
                XCTAssertLessThan(Geo.distance(from: next.first ?? s0, to: held), 10, "it leaves from the held location (\(label))")
                XCTAssertEqual(next.last, stops.last, "and goes on through every remaining stop (\(label))")
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, stops.count, label)
                assertHeld(state, at: stops.last)
            }
        }
    }

    func testOneStopPerMoveKeepsItsPlaceAcrossAModeChangeAndAConnectionLoss() async {
        for mode in Self.stopModes {
            let stops = runStops(for: mode)
            let harness = await StopRunHarness.make(mode: mode, stops: stops, settings: options(mode, progression: .onePerMove))
            let state = harness.state!
            _ = await move(harness)
            _ = await move(harness)
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 2, "\(mode)")

            state.activeMode = .teleport
            state.activeMode = mode
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 2, "a mode change away and back keeps progress (\(mode))")

            state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Wi-Fi dropped"))
            state.locationSessionCoordinator.connectionReady(
                LocationSessionIdentity(stableDeviceID: "stop-device", transport: .wifi, endpointClass: .unresolved, generation: 2)
            )
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 2, "a loss and recovery keep progress (\(mode))")

            let next = await move(harness)
            if mode == .twospot {
                // Both spots reached (One way): start over, travelling back to stop 1.
                XCTAssertGreaterThan(next.count, 10, "\(mode)")
                XCTAssertEqual(next.last, s0, "\(mode)")
            } else {
                XCTAssertFalse(next.contains(s0), "never back to stop 1 (\(mode))")
                XCTAssertGreaterThan(next.count, 10, "travelled from the held stop (\(mode))")
                XCTAssertEqual(next.last, s2, "\(mode)")
            }
        }
    }

    func testAnArrivalAcknowledgedAfterAModeChangeStillAdvancesThatModesProgress() async {
        for mode in Self.stopModes {
            let (state, fake) = makeFakeState(mode: mode, stops: runStops(for: mode), settings: options(mode, arrival: .jump, progression: .onePerMove))
            let run = Task { await state.startSimulation() }
            await fake.waitUntilApplicationPending()
            state.activeMode = .teleport
            await fake.releaseNextApplication(session: StopRunHarness.session)
            await run.value
            XCTAssertEqual(state.currentLocation, s0, "\(mode)")
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 1, "the phone reached stop 1 (\(mode))")
        }
    }

    func testEachStopModeKeepsItsOwnProgress() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: options(.route, progression: .onePerMove))
        let state = harness.state!
        _ = await move(harness)
        _ = await move(harness)
        state.activeMode = .twospot
        XCTAssertEqual(state.displayStopCursor(for: .twospot), StopCursor(), "Two-Spot has not moved")
        XCTAssertEqual(state.displayStopCursor(for: .jump), StopCursor(), "Jump has not moved")
        state.activeMode = .route
        XCTAssertEqual(state.displayStopCursor(for: .route).nextIndex, 2)
    }

    /// The GUI's mode change (`ContentView.onChange(of: selectedMode)` only assigns
    /// `activeMode`) through every other mode, a Teleport click included, keeps the stop
    /// mode's own stops and progress (review 2026-11-03 issue 1: the shared list used to
    /// be truncated to one stop, cleared for Joystick and replaced by a Teleport click).
    func testAGUIModeRoundTripKeepsTheStopModesStopsAndProgress() async {
        let far = LocationCoordinate(latitude: 35.69000, longitude: 139.77000)
        for mode in Self.stopModes {
            let stops = runStops(for: mode)
            let harness = await StopRunHarness.make(mode: mode, stops: stops, settings: options(mode, progression: .onePerMove))
            let state = harness.state!
            let reached = mode == .twospot ? 1 : 2
            for _ in 0..<reached { _ = await move(harness) }
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, reached, "\(mode)")

            let others: [AppMode] = [.twospot, .teleport, .joystick, .jump, .route].filter { $0 != mode }
            for other in others {
                state.activeMode = other
                if other == .teleport { state.stageLocation(far, for: .teleport) }
            }
            state.activeMode = mode

            XCTAssertEqual(state.currentRoute, stops, "the mode's stops are kept (\(mode))")
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, reached, "and its progress (\(mode))")
            let next = await move(harness)
            if mode != .twospot { XCTAssertFalse(next.contains(s0), "never back to stop 1 (\(mode))") }
            XCTAssertEqual(next.last, stops[reached], "the next Move continues to the next stop (\(mode))")
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, reached + 1, "\(mode)")
        }
    }

    /// A mode's first visit starts from the stops being left, as many as it holds (the
    /// old truncation); Joystick has no stops; Settings keeps the current mode's stops.
    func testAModesFirstVisitIsSeededFromTheStopsBeingLeft() async {
        let harness = await StopRunHarness.make(mode: .jump, stops: [s0, s1, s2], settings: options(.jump, progression: .onePerMove))
        let state = harness.state!
        _ = await move(harness)
        XCTAssertEqual(state.displayStopCursor(for: .jump).nextIndex, 1)

        state.activeMode = .route
        XCTAssertEqual(state.currentRoute, [s0, s1, s2], "Multi-Spot holds 24 stops")
        XCTAssertEqual(state.displayStopCursor(for: .route), StopCursor(), "a seeded mode starts at stop 1")
        state.activeMode = .twospot
        XCTAssertEqual(state.currentRoute, [s0], "Two-Spot keeps the first spot")
        state.activeMode = .joystick
        XCTAssertEqual(state.currentRoute, [], "Joystick has no stops")
        state.activeMode = .teleport
        XCTAssertEqual(state.currentRoute, [], "seeded from Joystick's (empty) stops")

        state.activeMode = .jump
        XCTAssertEqual(state.currentRoute, [s0, s1, s2], "Jump's own stops")
        XCTAssertEqual(state.displayStopCursor(for: .jump).nextIndex, 1, "and progress")
        state.activeMode = .settings
        XCTAssertEqual(state.currentRoute, [s0, s1, s2], "Settings keeps the current stops")
        XCTAssertEqual(state.displayStopCursor(for: .jump).nextIndex, 1)
    }

    // MARK: Rule 2

    func testEditingTheStopsOrResetRouteResetsProgressInEveryStopMode() async {
        for mode in Self.stopModes {
            // Appending keeps progress (testAppendingAStopKeepsProgress); in Two-Spot a
            // further click replaces the destination, which is an edit.
            let edits = (mode == .twospot ? ["add"] : []) + ["remove", "move", "reverse", "import", "Reset Route"]
            for edit in edits {
                let label = "\(mode) \(edit)"
                let harness = await StopRunHarness.make(mode: mode, stops: runStops(for: mode), settings: options(mode, progression: .onePerMove))
                let state = harness.state!
                _ = await move(harness)
                _ = await move(harness)
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 2, label)
                let imported = mode == .twospot ? [s2, s0] : [s2, s0, s1]
                switch edit {
                case "add": state.stageLocation(LocationCoordinate(latitude: 35.68200, longitude: 139.76200), for: mode)
                case "remove": state.removeRouteWaypoint(at: 0)
                case "move": state.moveRouteWaypoint(from: 0, to: 1)
                case "reverse": state.reverseRoute(for: mode)
                case "import": state.loadRoute(from: imported)
                default: state.clearRoute()
                }
                XCTAssertEqual(state.displayStopCursor(for: mode), StopCursor(), "progress starts over (\(label))")
                guard edit == "import" else { continue }
                // Stop 1 of the new stops is reached from the held stop, per Getting there.
                let next = await move(harness)
                XCTAssertGreaterThan(next.count, 10, "travelled, not teleported (\(label))")
                XCTAssertLessThan(Geo.distance(from: next.first ?? s2, to: s1), 10, "from the held stop (\(label))")
                XCTAssertEqual(next.last, s2, label)
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 1, label)
            }
        }
    }

    func testAppendingAStopKeepsProgressAndTheNextMovesReachIt() async {
        let s3 = LocationCoordinate(latitude: 35.68000, longitude: 139.76110)
        for mode: AppMode in [.jump, .route] {
            for finished in [false, true] {
                let label = "\(mode) \(finished ? "finished" : "mid-run")"
                let harness = await StopRunHarness.make(mode: mode, stops: [s0, s1, s2], settings: options(mode, progression: .onePerMove))
                let state = harness.state!
                for _ in 0..<(finished ? 3 : 2) { _ = await move(harness) }
                let reached = finished ? 3 : 2
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, reached, label)

                state.stageLocation(s3, for: mode)
                XCTAssertEqual(state.currentRoute, [s0, s1, s2, s3], label)
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, reached, "appending keeps progress (\(label))")

                var next = await move(harness)
                if !finished {
                    XCTAssertFalse(next.contains(s0), "never back to stop 1 (\(label))")
                    XCTAssertEqual(next.last, s2, label)
                    next = await move(harness)
                }
                XCTAssertFalse(next.contains(s0), "never back to stop 1 (\(label))")
                XCTAssertEqual(next.last, s3, "the appended stop is reached (\(label))")
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 4, label)
                assertHeld(state, at: s3)
            }
        }
    }

    func testOnlyAPureAppendKeepsStopProgress() {
        let s3 = LocationCoordinate(latitude: 35.68000, longitude: 139.76110)
        XCTAssertTrue(RouteStateManager.keepsStopProgress(.jump, from: [s0, s1], to: [s0, s1, s2]))
        XCTAssertTrue(RouteStateManager.keepsStopProgress(.route, from: [s0, s1], to: [s0, s1, s2, s3]))
        XCTAssertTrue(RouteStateManager.keepsStopProgress(.twospot, from: [s0, s1], to: [s0, s1, s2]), "Two-Spot's two stops are unchanged")
        XCTAssertFalse(RouteStateManager.keepsStopProgress(.twospot, from: [s0], to: [s0, s1]), "Two-Spot with one spot began at the held location")
        XCTAssertFalse(RouteStateManager.keepsStopProgress(.route, from: [s0, s1, s2], to: [s0, s1]), "remove")
        XCTAssertFalse(RouteStateManager.keepsStopProgress(.route, from: [s0, s1], to: [s1, s0, s2]), "move")
        XCTAssertFalse(RouteStateManager.keepsStopProgress(.route, from: [s0, s1], to: [s0, s2, s1]), "insert")
        XCTAssertFalse(RouteStateManager.keepsStopProgress(.jump, from: [], to: [s0]), "nothing to keep")
    }

    func testAConfirmedClearResetsProgressAndThenPlacesStopOne() async {
        for mode in Self.stopModes {
            let harness = await StopRunHarness.make(mode: mode, stops: runStops(for: mode), settings: options(mode, progression: .onePerMove))
            let state = harness.state!
            _ = await move(harness)
            _ = await move(harness)
            await state.clearLocation()
            XCTAssertNil(state.currentLocation, "\(mode)")
            XCTAssertEqual(state.displayStopCursor(for: mode), StopCursor(), "a confirmed Clear resets progress (\(mode))")
            let next = await move(harness)
            XCTAssertEqual(next, [s0], "nothing held: stop 1 is placed (\(mode))")
            XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 1, "\(mode)")
        }
    }

    // MARK: Rule 3

    func testAFinishedOneWayRunStartsOverFromTheHeldStopPerGettingThere() async {
        for mode in Self.stopModes {
            for arrival in StopTravelSettings.Arrival.allCases {
                let label = "\(mode) \(arrival)"
                let stops = runStops(for: mode)
                let harness = await StopRunHarness.make(mode: mode, stops: stops, settings: options(mode, arrival: arrival, progression: .onePerMove))
                let state = harness.state!
                for _ in stops { _ = await move(harness) }
                XCTAssertEqual(state.currentLocation, stops.last, label)
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, stops.count, "finished (\(label))")

                let next = await move(harness)
                switch arrival {
                case .travel:
                    XCTAssertGreaterThan(next.count, 10, "travelled home, never a silent teleport (\(label))")
                    XCTAssertLessThan(Geo.distance(from: next.first ?? s0, to: stops.last!), 10, label)
                case .jump:
                    XCTAssertEqual(next.count, 1, "one jump (\(label))")
                }
                XCTAssertEqual(next.last, s0, label)
                XCTAssertEqual(state.displayStopCursor(for: mode).nextIndex, 1, label)
                assertHeld(state, at: s0)
            }
        }
    }

    func testAFinishedAutomaticRunStartsOverAndGoesThroughEveryStopAgain() async {
        for mode in Self.stopModes {
            let stops = runStops(for: mode)
            let harness = await StopRunHarness.make(mode: mode, stops: stops, settings: options(mode, progression: .automatic))
            let state = harness.state!
            _ = await move(harness)
            XCTAssertEqual(state.currentLocation, stops.last, "\(mode)")

            let next = await move(harness)
            let home = next.firstIndex(of: s0) ?? 0
            XCTAssertGreaterThan(home, 10, "stop 1 is travelled to from the held stop (\(mode))")
            XCTAssertLessThan(Geo.distance(from: next.first ?? s0, to: stops.last!), 10, "\(mode)")
            XCTAssertEqual(next.last, stops.last, "then every stop again (\(mode))")
            assertHeld(state, at: stops.last)
        }
    }

    // MARK: Next Move summary

    func testTheNextMoveSummaryDescribesWhatTheNextMoveDoes() async {
        let harness = await StopRunHarness.make(mode: .route, stops: [s0, s1, s2], settings: options(.route, progression: .onePerMove))
        let state = harness.state!
        XCTAssertEqual(state.nextMoveSummary(for: .route), "Next Move: place stop 1")
        _ = await move(harness)
        XCTAssertEqual(state.nextMoveSummary(for: .route), "Next Move: travel to stop 2", "no road router in tests")
        _ = await move(harness)
        _ = await move(harness)
        XCTAssertEqual(state.nextMoveSummary(for: .route), "Next Move: start over — travel to stop 1")
        XCTAssertNil(state.nextMoveSummary(for: .teleport))

        // None while a run of the mode is active (the live panel shows it).
        state.setStopTravelSettings(options(.route, progression: .automatic), for: .route)
        var duringRun: String? = "unset"
        let base = harness.applied.count
        harness.onApply = { count, _ in if count == base + 3 { duringRun = state.nextMoveSummary(for: .route) } }
        await state.startSimulation()
        XCTAssertNil(duringRun)

        // Two-Spot with one spot starts at the held location.
        state.activeMode = .twospot
        state.clearRoute()
        state.stageLocation(s1, for: .twospot)
        XCTAssertEqual(state.nextMoveSummary(for: .twospot), "Next Move: start at stop 1, then travel to stop 2")
    }
}
