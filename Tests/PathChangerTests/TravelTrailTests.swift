//
//  TravelTrailTests.swift
//  PathChangerTests
//
//  The trail of acknowledged positions the map draws for a travelled stop run
//  (owner ask 2026-11-03; PRODUCT_REQUIREMENTS 3.6 and 4: acknowledged updates only).
//

import XCTest
@testable import PathChanger

/// Acknowledges every application at once.
private actor TrailAckInjector: LocationInjecting {
    private(set) var applied: [LocationCoordinate] = []

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        applied.append(request.coordinate)
        return LocationInjectionReceipt(
            requestID: request.id,
            session: UUID(),
            coordinate: request.coordinate,
            transport: request.target.transport,
            actualChannel: .networkLockdown,
            endpointClass: .direct,
            sessionGeneration: request.sessionGeneration ?? 1,
            completedAt: Date(),
            outcome: .applied
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}
    func events() async -> AsyncStream<LocationBridgeEvent> { AsyncStream { _ in } }
}

@MainActor
final class TravelTrailTests: XCTestCase {
    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)

    private func point(_ index: Int) -> LocationCoordinate {
        LocationCoordinate(latitude: 35 + Double(index) * 0.00001, longitude: 139)
    }

    // MARK: - Pure

    func testAppendingSkipsARepeatedPoint() {
        let one = TravelTrail.appending(s0, to: [], startsSegment: true, capacity: 10)
        let trail = TravelTrail.appending(s1, to: one, startsSegment: false, capacity: 10)
        XCTAssertEqual(TravelTrail.appending(s1, to: trail, startsSegment: false, capacity: 10), [[s0, s1]])
    }

    func testTheTrailNeverExceedsItsCapAndKeepsItsEnds() {
        var trail: [[LocationCoordinate]] = []
        for index in 0..<5_000 {
            trail = TravelTrail.appending(point(index), to: trail, startsSegment: false, capacity: 2_000)
            XCTAssertEqual(trail.count, 1)
            XCTAssertLessThanOrEqual(trail[0].count, 2_000)
        }
        let line = trail[0]
        XCTAssertEqual(line.first, point(0), "the start of the run stays")
        XCTAssertEqual(line.last, point(4_999), "the newest acknowledged point stays")
        XCTAssertGreaterThan(line.count, 900, "downsampling halves, it does not empty")
        let latitudes = line.map(\.latitude)
        XCTAssertEqual(latitudes, latitudes.sorted(), "order is kept")
    }

    func testDownsamplingKeepsEveryOtherPointAndTheLast() {
        let points = (0..<7).map(point)
        XCTAssertEqual(TravelTrail.downsampled(points), [point(0), point(2), point(4), point(6)])
        let even = (0..<6).map(point)
        XCTAssertEqual(TravelTrail.downsampled(even), [point(0), point(2), point(4), point(5)])
        XCTAssertEqual(TravelTrail.downsampled([point(0)]), [point(0)])
    }

    /// Owner decision 2026-11-03: each stop mode keeps its own trail; travel in one mode
    /// never erases another's.
    func testEachStopModeKeepsItsOwnTrail() {
        let trail = TravelTrail()
        trail.record(s0, mode: .route, after: nil)
        trail.record(s1, mode: .route, after: s0)
        trail.record(s2, mode: .route, after: s1)
        XCTAssertEqual(trail.points(for: .route), [s0, s1, s2], "later runs of the same mode extend the trail")
        trail.record(s1, mode: .twospot, after: nil)
        trail.record(s0, mode: .twospot, after: s1)
        XCTAssertEqual(trail.segments(for: .twospot), [[s1, s0]], "Two-Spot draws its own trail")
        XCTAssertEqual(trail.segments(for: .route), [[s0, s1, s2]], "and Multi-Spot's stays")
        trail.record(s2, mode: .jump, after: nil)
        XCTAssertEqual(trail.points(for: .jump), [s2])
        XCTAssertEqual(trail.points(for: .route), [s0, s1, s2])
        XCTAssertEqual(trail.points(for: .twospot), [s1, s0])
    }

    func testResettingOneModesTrailKeepsTheOthersAndResetEndsThemAll() {
        let trail = TravelTrail()
        trail.record(s0, mode: .route, after: nil)
        trail.record(s1, mode: .route, after: s0)
        trail.record(s1, mode: .twospot, after: nil)
        trail.record(s2, mode: .twospot, after: s1)
        trail.record(s0, mode: .jump, after: nil)
        trail.record(s2, mode: .jump, after: s0)

        trail.reset(.twospot)
        XCTAssertTrue(trail.segments(for: .twospot).isEmpty, "Two-Spot's progress reset, so its trail goes")
        XCTAssertEqual(trail.points(for: .route), [s0, s1], "Multi-Spot's trail stays")
        XCTAssertEqual(trail.points(for: .jump), [s0, s2], "Jump's trail stays")

        trail.reset()
        for mode in [AppMode.jump, .twospot, .route] {
            XCTAssertTrue(trail.segments(for: mode).isEmpty, "a confirmed Clear erases every trail (\(mode))")
        }
    }

    func testOnlyTheShownModesTrailIsDrawn() {
        let trail = TravelTrail()
        trail.record(s0, mode: .route, after: nil)
        trail.record(s1, mode: .route, after: s0)
        XCTAssertEqual(trail.segments(for: .route), [[s0, s1]])
        XCTAssertTrue(trail.segments(for: .jump).isEmpty, "another stop mode does not draw it")
        XCTAssertTrue(trail.segments(for: .twospot).isEmpty)
        XCTAssertTrue(trail.segments(for: .teleport).isEmpty)
    }

    /// Review 2026-11-03 (fixes) issue 1: a point reached by something other than this
    /// trail's travel (a Teleport, a Joystick drive, a Jump arrival) must not be bridged
    /// by a straight line the phone never drove.
    func testAPointNotTravelledFromTheTrailsEndStartsANewSegment() {
        let elsewhere = LocationCoordinate(latitude: 35.68000, longitude: 139.76110)
        let trail = TravelTrail()
        trail.record(s0, mode: .route, after: nil)
        trail.record(s1, mode: .route, after: s0)
        XCTAssertEqual(trail.segments(for: .route), [[s0, s1]], "travel from the trail's end extends it")
        trail.record(s2, mode: .route, after: elsewhere)
        XCTAssertEqual(trail.segments(for: .route), [[s0, s1], [s2]], "travel from elsewhere starts its own segment")
        trail.record(s0, mode: .route, after: s2)
        XCTAssertEqual(trail.segments(for: .route), [[s0, s1], [s2, s0]])
        XCTAssertEqual(trail.points(for: .route), [s0, s1, s2, s0], "points are every segment, in order")
    }

    func testTheCapCountsEverySegmentAndKeepsTheNewestPoint() {
        let trail = TravelTrail()
        var held: LocationCoordinate?
        for index in 0..<(TravelTrail.capacity * 2) {
            // A new segment every 10 points.
            let after = index % 10 == 0 ? nil : held
            trail.record(point(index), mode: .route, after: after)
            held = point(index)
            XCTAssertLessThanOrEqual(trail.segments(for: .route).reduce(0) { $0 + $1.count }, TravelTrail.capacity)
        }
        XCTAssertEqual(trail.points(for: .route).last, point(TravelTrail.capacity * 2 - 1), "the newest point stays")
        let latitudes = trail.points(for: .route).map(\.latitude)
        XCTAssertEqual(latitudes, latitudes.sorted(), "order is kept")
        XCTAssertFalse(trail.segments(for: .route).contains { $0.isEmpty })
    }

    func testTheCapIsPerMode() {
        let trail = TravelTrail()
        for index in 0..<TravelTrail.capacity {
            trail.record(point(index), mode: .route, after: index == 0 ? nil : point(index - 1))
        }
        trail.record(s0, mode: .twospot, after: nil)
        XCTAssertEqual(trail.points(for: .route).count, TravelTrail.capacity, "another mode's travel takes nothing from it")
    }

    // MARK: - AppState

    private func makeState(
        mode: AppMode,
        stops: [LocationCoordinate],
        arrival: StopTravelSettings.Arrival
    ) -> (AppState, TrailAckInjector) {
        let injector = TrailAckInjector()
        let state = AppState(startBackgroundServices: false, locationInjector: injector, routeDelay: { _ in await Task.yield() })
        state.selectedDevice = Device(id: "trail-device", displayName: "Trail Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = mode
        state.autoSpeed = false
        state.customSpeedMps = 20
        state.updateFrequencyHz = 5
        for stop in stops { state.stageLocation(stop, for: mode) }
        state.setStopTravelSettings(
            StopTravelSettings(arrival: arrival, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay),
            for: mode
        )
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: "trail-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        ))
        return (state, injector)
    }

    func testATravelledRunDrawsEveryAcknowledgedPoint() async {
        let (state, injector) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        await state.startSimulation()
        let applied = await injector.applied
        XCTAssertGreaterThan(applied.count, 5)
        XCTAssertEqual(state.travelTrail.points(for: .route), applied, "the trail is the acknowledged points, in order")
    }

    func testTheTrailKeepsEveryMoveOfTheSequence() async {
        // Review 2026-11-03 issue 3: the trail restarted with every run, so with one stop
        // per Move (or a Move after Stop) the map showed only the last Move.
        let (state, injector) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .onePerMove, repeatMode: .oneWay),
            for: .route
        )
        await state.startSimulation()
        await state.startSimulation()
        let afterSecondMove = state.travelTrail.points(for: .route)
        XCTAssertTrue(afterSecondMove.contains(s1))
        await state.startSimulation()

        XCTAssertEqual(state.currentLocation, s2)
        XCTAssertEqual(Array(state.travelTrail.points(for: .route).prefix(afterSecondMove.count)), afterSecondMove, "the earlier Move stays drawn")
        XCTAssertEqual(state.travelTrail.points(for: .route).last, s2)
        let applied = await injector.applied
        XCTAssertEqual(state.travelTrail.points(for: .route), Array(applied.suffix(state.travelTrail.points(for: .route).count)))
        XCTAssertEqual(state.travelTrail.segments(for: .route).count, 1, "back-to-back travelled Moves are one line")
    }

    /// Review 2026-11-03 (fixes) issue 1: a Teleport between two travelled Moves left the
    /// trail joining the old end to the new travel with a line the phone never drove.
    func testATeleportBetweenTravelledMovesSplitsTheTrail() async {
        let elsewhere = LocationCoordinate(latitude: 35.68000, longitude: 139.76110)
        let (state, _) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .onePerMove, repeatMode: .oneWay),
            for: .route
        )
        await state.startSimulation()
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, s1)
        XCTAssertEqual(state.travelTrail.points(for: .route).last, s1)

        state.activeMode = .teleport
        state.stageLocation(elsewhere, for: .teleport)
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, elsewhere)

        state.activeMode = .route
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, s2)

        let segments = state.travelTrail.segments(for: .route)
        XCTAssertEqual(segments.count, 2, "the Teleport splits the trail")
        XCTAssertEqual(segments.first?.last, s1, "the first line ends where that Move stopped")
        XCTAssertEqual(segments.last?.last, s2)
        XCTAssertFalse(segments.last?.contains(s1) ?? true, "no line joins stop 2 to the travel that left from elsewhere")
        XCTAssertFalse(state.travelTrail.points(for: .route).contains(elsewhere), "the Teleport itself is not travel")
    }

    func testAStopEditResetsTheTrailByItsOwnModesRule() {
        // Review 2026-11-03 issue 7: the reset used Jump's append rule. Adding Two-Spot's
        // second spot resets Two-Spot's progress, so it must reset Two-Spot's trail.
        let state = AppState(startBackgroundServices: false, locationInjector: TrailAckInjector(), routeDelay: { _ in })
        state.travelTrail.record(s0, mode: .route, after: nil)
        state.travelTrail.record(s2, mode: .route, after: s0)
        state.activeMode = .twospot
        state.stageLocation(s0, for: .twospot)
        state.travelTrail.record(s1, mode: .twospot, after: nil)
        state.travelTrail.record(s2, mode: .twospot, after: s1)
        state.stageLocation(s1, for: .twospot)
        XCTAssertTrue(state.travelTrail.points(for: .twospot).isEmpty, "Two-Spot's run changed, so its trail goes")
        XCTAssertEqual(state.travelTrail.points(for: .route), [s0, s2], "Multi-Spot's stops did not change, so its trail stays")

        state.activeMode = .route
        state.clearRoute()
        state.stageLocation(s0, for: .route)
        state.stageLocation(s1, for: .route)
        state.travelTrail.record(s1, mode: .route, after: nil)
        state.travelTrail.record(s2, mode: .route, after: s1)
        state.stageLocation(s2, for: .route)
        XCTAssertEqual(state.travelTrail.points(for: .route), [s1, s2], "appending keeps Multi-Spot's progress and its trail")
    }

    /// Review 2026-11-03 (fixes) issue 3: loading stops into one mode erased the trail of
    /// another mode, whose progress the load kept.
    func testLoadingStopsErasesOnlyTheLoadedModesTrail() async {
        let (state, _) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        await state.startSimulation()
        let trail = state.travelTrail.points(for: .route)
        XCTAssertFalse(trail.isEmpty)

        state.activeMode = .jump
        state.loadRoute(from: [s2, s0])
        XCTAssertEqual(state.travelTrail.points(for: .route), trail, "a load into Jump keeps Multi-Spot's trail")
        XCTAssertEqual(state.travelTrail.segments(for: .route).flatMap { $0 }, trail)

        state.activeMode = .route
        state.loadRoute(from: [s0, s1, s2])
        XCTAssertTrue(state.travelTrail.points(for: .route).isEmpty, "a load into Multi-Spot erases its trail")
    }

    func testTheRunsLastReceiptAfterStopIsDrawn() async {
        // Review 2026-11-03 issue 8: a receipt landing after Stop is committed as held but
        // was not drawn, so the trail ended short of the held dot.
        let fake = FakeLocationInjector()
        let session = LocationSessionIdentity(stableDeviceID: "trail-device", transport: .wifi, endpointClass: .unresolved, generation: 1)
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "trail-device", displayName: "Trail Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .route
        state.autoSpeed = false
        state.customSpeedMps = 20
        state.updateFrequencyHz = 5
        for stop in [s0, s1, s2] { state.stageLocation(stop, for: .route) }
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay),
            for: .route
        )
        state.locationSessionCoordinator.connectionReady(session)

        let run = Task { await state.startSimulation() }
        for _ in 0..<2 {
            await fake.waitUntilApplicationPending()
            await fake.releaseNextApplication(session: session)
        }
        await fake.waitUntilApplicationPending()
        await state.stopSimulation()
        await fake.releaseNextApplication(session: session)
        await run.value
        for _ in 0..<50 { await Task.yield() }

        let held = state.currentLocation
        XCTAssertNotNil(held)
        XCTAssertEqual(state.travelTrail.points(for: .route).count, 3, "the receipt after Stop is drawn too")
        XCTAssertEqual(state.travelTrail.points(for: .route).last, held, "the trail ends at the held dot")
    }

    /// Owner decision 2026-11-03: travel in one stop mode never erases another's trail,
    /// and a confirmed Clear erases them all.
    func testTravelInAnotherModeKeepsEachModesTrailUntilClear() async {
        let (state, _) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        await state.startSimulation()
        let multiSpot = state.travelTrail.points(for: .route)
        XCTAssertFalse(multiSpot.isEmpty)

        state.activeMode = .twospot
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay),
            for: .twospot
        )
        state.stageLocation(s0, for: .twospot)
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, s0)
        let twoSpot = state.travelTrail.points(for: .twospot)
        XCTAssertFalse(twoSpot.isEmpty, "Two-Spot draws its own trail")
        XCTAssertEqual(state.travelTrail.points(for: .route), multiSpot, "Multi-Spot's trail stays")

        state.activeMode = .route
        XCTAssertEqual(state.travelTrail.segments(for: .route).flatMap { $0 }, multiSpot, "and is drawn again in Multi-Spot")

        await state.clearLocation()
        XCTAssertTrue(state.travelTrail.points(for: .route).isEmpty, "a confirmed Clear erases every mode's trail")
        XCTAssertTrue(state.travelTrail.points(for: .twospot).isEmpty)
    }

    func testAJumpRunDrawsNoTrail() async {
        let (state, injector) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .jump)
        await state.startSimulation()
        let applied = await injector.applied
        XCTAssertEqual(applied.count, 3)
        XCTAssertTrue(state.travelTrail.points(for: .route).isEmpty, "jumps are not travelled, so there is no trail")
    }

    func testClearAndEditingTheStopsEraseTheTrail() async {
        let (state, _) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        await state.startSimulation()
        XCTAssertFalse(state.travelTrail.points(for: .route).isEmpty)
        await state.clearLocation()
        XCTAssertTrue(state.travelTrail.points(for: .route).isEmpty, "Clear erases the trail")

        await state.startSimulation()
        XCTAssertFalse(state.travelTrail.points(for: .route).isEmpty)
        state.removeRouteWaypoint(at: 2)
        XCTAssertTrue(state.travelTrail.points(for: .route).isEmpty, "editing the stops erases the trail")
    }
}
