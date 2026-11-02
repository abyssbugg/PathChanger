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

/// Records which legs were asked for, and how many points had been applied by then.
private actor PathRequests {
    private(set) var requests: [(from: LocationCoordinate, to: LocationCoordinate, appliedBefore: Int)] = []
    func record(_ from: LocationCoordinate, _ to: LocationCoordinate, appliedBefore: Int) {
        requests.append((from, to, appliedBefore))
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
}
