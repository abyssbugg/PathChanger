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
        let trail = TravelTrail.appending(s1, to: TravelTrail.appending(s0, to: [], capacity: 10), capacity: 10)
        XCTAssertEqual(TravelTrail.appending(s1, to: trail, capacity: 10), [s0, s1])
    }

    func testTheTrailNeverExceedsItsCapAndKeepsItsEnds() {
        var trail: [LocationCoordinate] = []
        for index in 0..<5_000 {
            trail = TravelTrail.appending(point(index), to: trail, capacity: 2_000)
            XCTAssertLessThanOrEqual(trail.count, 2_000)
        }
        XCTAssertEqual(trail.first, point(0), "the start of the run stays")
        XCTAssertEqual(trail.last, point(4_999), "the newest acknowledged point stays")
        XCTAssertGreaterThan(trail.count, 900, "downsampling halves, it does not empty")
        let latitudes = trail.map(\.latitude)
        XCTAssertEqual(latitudes, latitudes.sorted(), "order is kept")
    }

    func testDownsamplingKeepsEveryOtherPointAndTheLast() {
        let points = (0..<7).map(point)
        XCTAssertEqual(TravelTrail.downsampled(points), [point(0), point(2), point(4), point(6)])
        let even = (0..<6).map(point)
        XCTAssertEqual(TravelTrail.downsampled(even), [point(0), point(2), point(4), point(5)])
        XCTAssertEqual(TravelTrail.downsampled([point(0)]), [point(0)])
    }

    func testTheTrailBelongsToAModeAndAnotherModeStartsANewOne() {
        let trail = TravelTrail()
        trail.record(s0, mode: .route)
        trail.record(s1, mode: .route)
        trail.record(s2, mode: .route)
        XCTAssertEqual(trail.points, [s0, s1, s2], "later runs of the same mode extend the trail")
        XCTAssertEqual(trail.mode, .route)
        trail.record(s0, mode: .twospot)
        XCTAssertEqual(trail.points, [s0], "another mode's travel starts its own trail")
        XCTAssertEqual(trail.mode, .twospot)
        trail.reset()
        XCTAssertTrue(trail.points.isEmpty)
        XCTAssertNil(trail.mode)
    }

    func testTheTrailIsDrawnOnlyForItsMode() {
        let trail = TravelTrail()
        trail.record(s0, mode: .route)
        trail.record(s1, mode: .route)
        XCTAssertEqual(trail.points(for: .route), [s0, s1])
        XCTAssertTrue(trail.points(for: .jump).isEmpty, "another stop mode does not draw it")
        XCTAssertTrue(trail.points(for: .twospot).isEmpty)
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
        XCTAssertEqual(state.travelTrail.points, applied, "the trail is the acknowledged points, in order")
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
        let afterSecondMove = state.travelTrail.points
        XCTAssertTrue(afterSecondMove.contains(s1))
        await state.startSimulation()

        XCTAssertEqual(state.currentLocation, s2)
        XCTAssertEqual(Array(state.travelTrail.points.prefix(afterSecondMove.count)), afterSecondMove, "the earlier Move stays drawn")
        XCTAssertEqual(state.travelTrail.points.last, s2)
        let applied = await injector.applied
        XCTAssertEqual(state.travelTrail.points, Array(applied.suffix(state.travelTrail.points.count)))
    }

    func testAStopEditResetsTheTrailByItsOwnModesRule() {
        // Review 2026-11-03 issue 7: the reset used Jump's append rule. Adding Two-Spot's
        // second spot resets Two-Spot's progress, so it must reset Two-Spot's trail.
        let state = AppState(startBackgroundServices: false, locationInjector: TrailAckInjector(), routeDelay: { _ in })
        state.loadRoute(from: [s0])
        state.travelTrail.record(s1, mode: .twospot)
        state.travelTrail.record(s2, mode: .twospot)
        state.loadRoute(from: [s0, s1])
        XCTAssertTrue(state.travelTrail.points.isEmpty, "Two-Spot's run changed, so its trail goes")

        state.loadRoute(from: [s0, s1])
        state.travelTrail.record(s1, mode: .route)
        state.travelTrail.record(s2, mode: .route)
        state.loadRoute(from: [s0, s1, s2])
        XCTAssertEqual(state.travelTrail.points, [s1, s2], "appending keeps Multi-Spot's progress and its trail")
    }

    func testAJumpRunDrawsNoTrail() async {
        let (state, injector) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .jump)
        await state.startSimulation()
        let applied = await injector.applied
        XCTAssertEqual(applied.count, 3)
        XCTAssertTrue(state.travelTrail.points.isEmpty, "jumps are not travelled, so there is no trail")
    }

    func testClearAndEditingTheStopsEraseTheTrail() async {
        let (state, _) = makeState(mode: .route, stops: [s0, s1, s2], arrival: .travel)
        await state.startSimulation()
        XCTAssertFalse(state.travelTrail.points.isEmpty)
        await state.clearLocation()
        XCTAssertTrue(state.travelTrail.points.isEmpty, "Clear erases the trail")

        await state.startSimulation()
        XCTAssertFalse(state.travelTrail.points.isEmpty)
        state.removeRouteWaypoint(at: 2)
        XCTAssertTrue(state.travelTrail.points.isEmpty, "editing the stops erases the trail")
    }
}
