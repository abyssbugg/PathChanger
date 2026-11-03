//
//  RoutePreviewTests.swift
//  PathChangerTests
//
//  The planned route the map draws for Jump, Two-Spot and Multi-Spot: which legs, how
//  each leg looks, when the road paths are fetched (owner ask 2026-11-03, PRODUCT_REQUIREMENTS 3.6).
//

import XCTest
@testable import PathChanger

/// Answers each leg from `respond`, records every request, and can hold requests until opened.
private actor PreviewRouter: RoadRouting {
    private let respond: @Sendable (LocationCoordinate, LocationCoordinate) -> RoadRoute
    private(set) var requests: [(from: LocationCoordinate, to: LocationCoordinate, travel: SimulationSpeed)] = []
    private var gated = false
    private var released: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(respond: @escaping @Sendable (LocationCoordinate, LocationCoordinate) -> RoadRoute) {
        self.respond = respond
    }

    func route(from: LocationCoordinate, to: LocationCoordinate, travel: SimulationSpeed) async -> RoadRoute {
        requests.append((from, to, travel))
        let ready = countWaiters.filter { requests.count >= $0.0 }
        countWaiters.removeAll { requests.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        if gated { await withCheckedContinuation { released.append($0) } }
        return respond(from, to)
    }

    func close() { gated = true }

    func open() {
        gated = false
        released.forEach { $0.resume() }
        released.removeAll()
    }

    func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { countWaiters.append((count, $0)) }
    }

    func requestedLegs() -> [[LocationCoordinate]] { requests.map { [$0.from, $0.to] } }
}

/// Acknowledges every application at once.
private actor PreviewAckInjector: LocationInjecting {
    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        LocationInjectionReceipt(
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
final class RoutePreviewTests: XCTestCase {
    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)
    private let s3 = LocationCoordinate(latitude: 35.68200, longitude: 139.76110)

    private func settings(
        _ arrival: StopTravelSettings.Arrival,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> StopTravelSettings {
        StopTravelSettings(arrival: arrival, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: repeatMode)
    }

    private func key(
        _ stops: [LocationCoordinate],
        arrival: StopTravelSettings.Arrival = .travel,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay,
        transport: RoadTransport = .walking
    ) -> RoutePreviewKey {
        RoutePreviewKey(stops: stops, transport: transport, arrival: arrival, repeatMode: repeatMode)
    }

    private func road(_ from: LocationCoordinate, _ to: LocationCoordinate) -> RoadRoute {
        let middle = LocationCoordinate(latitude: from.latitude, longitude: to.longitude)
        return RoadRoute(points: [from, middle, to], distanceMeters: 200, followsRoads: true, note: nil)
    }

    private func straight(_ from: LocationCoordinate, _ to: LocationCoordinate) -> RoadRoute {
        RoadRoute(points: [from, to], distanceMeters: 100, followsRoads: false, note: MapKitRoadRouter.straightLineNote)
    }

    // MARK: - Key

    func testOnlyStopModesWithTwoStopsHaveAPreview() {
        let travel = settings(.travel)
        XCTAssertNil(RoutePreviewPlanner.key(mode: .teleport, stops: [s0, s1], held: nil, settings: travel, travel: .walking))
        XCTAssertNil(RoutePreviewPlanner.key(mode: .joystick, stops: [s0, s1], held: nil, settings: travel, travel: .walking))
        XCTAssertNil(RoutePreviewPlanner.key(mode: .route, stops: [s0], held: nil, settings: travel, travel: .walking))
        XCTAssertNil(RoutePreviewPlanner.key(mode: .jump, stops: [], held: s0, settings: travel, travel: .walking))
        XCTAssertEqual(
            RoutePreviewPlanner.key(mode: .route, stops: [s0, s1, s2], held: nil, settings: travel, travel: .walking),
            key([s0, s1, s2])
        )
        let invalid = LocationCoordinate(latitude: 200, longitude: 0)
        XCTAssertEqual(
            RoutePreviewPlanner.key(mode: .jump, stops: [s0, invalid, s1], held: nil, settings: travel, travel: .walking)?.stops,
            [s0, s1],
            "invalid stops are skipped, as the engine skips them"
        )
    }

    func testTwoSpotPreviewsItsTwoEndpointsOrTheHeldStart() {
        let travel = settings(.travel)
        XCTAssertEqual(
            RoutePreviewPlanner.key(mode: .twospot, stops: [s0, s1, s2], held: nil, settings: travel, travel: .walking)?.stops,
            [s0, s1]
        )
        XCTAssertEqual(
            RoutePreviewPlanner.key(mode: .twospot, stops: [s1], held: s0, settings: travel, travel: .walking)?.stops,
            [s0, s1],
            "one spot travels from the held location (PRODUCT_REQUIREMENTS 3.3)"
        )
        XCTAssertNil(RoutePreviewPlanner.key(mode: .twospot, stops: [s1], held: s1, settings: travel, travel: .walking))
        XCTAssertNil(RoutePreviewPlanner.key(mode: .twospot, stops: [s1], held: nil, settings: travel, travel: .walking))
    }

    func testTheKeyUsesTheDirectionsTransportOfTheTravelMode() {
        let travel = settings(.travel)
        func transport(_ speed: SimulationSpeed) -> RoadTransport? {
            RoutePreviewPlanner.key(mode: .route, stops: [s0, s1], held: nil, settings: travel, travel: speed)?.transport
        }
        XCTAssertEqual(transport(.walking), .walking)
        XCTAssertEqual(transport(.cycling), .cycling)
        XCTAssertEqual(transport(.fast), .automobile)
        XCTAssertEqual(transport(.driving), .automobile)
        XCTAssertEqual(
            RoutePreviewPlanner.key(mode: .route, stops: [s0, s1], held: nil, settings: travel, travel: .fast),
            RoutePreviewPlanner.key(mode: .route, stops: [s0, s1], held: nil, settings: travel, travel: .driving),
            "Riding and Driving ask for the same directions, so the preview is the same"
        )
    }

    func testKeyEqualityFollowsStopsTransportArrivalAndRepeat() {
        XCTAssertEqual(key([s0, s1]), key([s0, s1]))
        XCTAssertNotEqual(key([s0, s1]), key([s0, s2]))
        XCTAssertNotEqual(key([s0, s1]), key([s0, s1], transport: .cycling))
        XCTAssertNotEqual(key([s0, s1]), key([s0, s1], arrival: .jump))
        XCTAssertNotEqual(key([s0, s1]), key([s0, s1], repeat: .loop))
    }

    // MARK: - Legs

    func testOneWayDrawsEachLegBetweenConsecutiveStops() {
        let legs = RoutePreviewPlanner.legs(for: key([s0, s1, s2]))
        XCTAssertEqual(legs, [
            RoutePreviewLegSpec(from: s0, to: s1, returnsToStart: false),
            RoutePreviewLegSpec(from: s1, to: s2, returnsToStart: false)
        ])
    }

    func testLoopAddsTheLegBackToTheFirstStop() {
        let legs = RoutePreviewPlanner.legs(for: key([s0, s1, s2], repeat: .loop))
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(legs.last, RoutePreviewLegSpec(from: s2, to: s0, returnsToStart: true))

        let twoSpot = RoutePreviewPlanner.legs(for: key([s0, s1], repeat: .loop))
        XCTAssertEqual(twoSpot.map(\.to), [s1, s0], "Two-Spot loop travels home the same way")
    }

    func testBackAndForthDrawsTheForwardLegsOnly() {
        XCTAssertEqual(
            RoutePreviewPlanner.legs(for: key([s0, s1, s2], repeat: .backAndForth)),
            RoutePreviewPlanner.legs(for: key([s0, s1, s2]))
        )
    }

    func testSamePlaceLegsAreSkipped() {
        let legs = RoutePreviewPlanner.legs(for: key([s0, s0, s1, s0], repeat: .loop))
        XCTAssertEqual(legs.map { [$0.from, $0.to] }, [[s0, s1], [s1, s0]], "no zero-length legs; the loop leg is not needed when the run ends at stop 1")
    }

    // MARK: - The leg the next Move drives

    private func nextMoveKey(
        mode: AppMode = .route,
        _ stops: [LocationCoordinate],
        origin: LocationCoordinate?,
        cursor: Int,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> RoutePreviewKey? {
        RoutePreviewPlanner.key(
            mode: mode, stops: stops, held: origin, settings: settings(.travel, repeat: repeatMode),
            travel: .walking, origin: origin, cursor: StopCursor(nextIndex: cursor)
        )
    }

    func testThePreviewDrawsTheLegFromTheHeldLocationToTheNextStop() {
        // Review 2026-11-03 issue 5: the next Move travels held -> next unreached stop.
        let key = nextMoveKey([s0, s1, s2], origin: s3, cursor: 1)
        XCTAssertEqual(key?.nextMoveLeg, RoutePreviewLegSpec(from: s3, to: s1, returnsToStart: false))
        XCTAssertEqual(key.map(RoutePreviewPlanner.legs(for:))?.first, RoutePreviewLegSpec(from: s3, to: s1, returnsToStart: false))
        XCTAssertEqual(key.map(RoutePreviewPlanner.legs(for:))?.count, 3)
    }

    func testAFinishedOneWayRunPreviewsTheStartOverLeg() {
        let key = nextMoveKey([s0, s1, s2], origin: s2, cursor: 3)
        XCTAssertEqual(key?.nextMoveLeg, RoutePreviewLegSpec(from: s2, to: s0, returnsToStart: false), "last stop -> stop 1")
        XCTAssertEqual(key.map(RoutePreviewPlanner.legs(for:))?.map { [$0.from, $0.to] }, [[s2, s0], [s0, s1], [s1, s2]])
    }

    func testNoNextMoveLegWithNothingHeldOrWhenItIsAlreadyDrawn() {
        XCTAssertNil(nextMoveKey([s0, s1, s2], origin: nil, cursor: 0)?.nextMoveLeg, "nothing held: stop 1 is placed, not travelled")
        XCTAssertNil(nextMoveKey([s0, s1, s2], origin: s1, cursor: 1)?.nextMoveLeg, "already at the next stop")
        let atStop = nextMoveKey([s0, s1, s2], origin: s1, cursor: 2)
        XCTAssertEqual(atStop.map(RoutePreviewPlanner.legs(for:)), RoutePreviewPlanner.legs(for: key([s0, s1, s2])), "a stop -> stop leg is not drawn twice")
    }

    func testJumpWithOneStopPreviewsTheLegFromTheHeldLocation() {
        let key = nextMoveKey(mode: .jump, [s1], origin: s0, cursor: 0)
        XCTAssertEqual(key.map(RoutePreviewPlanner.legs(for:)), [RoutePreviewLegSpec(from: s0, to: s1, returnsToStart: false)])
        XCTAssertNil(nextMoveKey(mode: .route, [s1], origin: s0, cursor: 0), "Multi-Spot needs two spots to Move")
    }

    func testTheNextMoveLegChangesTheKey() {
        XCTAssertNotEqual(nextMoveKey([s0, s1, s2], origin: s3, cursor: 1), nextMoveKey([s0, s1, s2], origin: s3, cursor: 2), "the cursor")
        XCTAssertNotEqual(
            nextMoveKey([s0, s1, s2], origin: s3, cursor: 1),
            nextMoveKey([s0, s1, s2], origin: LocationCoordinate(latitude: 35.683, longitude: 139.762), cursor: 1),
            "the held location"
        )
    }

    // MARK: - Style

    func testEachLegStyleFollowsItsState() {
        XCTAssertEqual(RoutePreviewPlanner.style(arrival: .jump, route: nil), .jump)
        XCTAssertEqual(RoutePreviewPlanner.style(arrival: .jump, route: road(s0, s1)), .jump, "a jump is never drawn as a road")
        XCTAssertEqual(RoutePreviewPlanner.style(arrival: .travel, route: nil), .loading)
        XCTAssertEqual(RoutePreviewPlanner.style(arrival: .travel, route: road(s0, s1)), .road)
        XCTAssertEqual(RoutePreviewPlanner.style(arrival: .travel, route: straight(s0, s1)), .straight)
    }

    func testTheLegendNamesOnlyTheLinesShown() {
        XCTAssertNil(RoutePreviewPlanner.legendText(for: []))
        XCTAssertEqual(RoutePreviewPlanner.legendText(for: [.road, .straight]), "Solid line: road route · Dashed: straight line")
        XCTAssertEqual(RoutePreviewPlanner.legendText(for: [.road, .loading]), "Solid line: road route · Dashed: straight line · Dotted: finding route")
        XCTAssertEqual(RoutePreviewPlanner.legendText(for: [.jump, .jump]), "Dashed line: jump, not a road")
    }

    // MARK: - Model

    func testTravelLegsLoadThenShowTheRoadPathOrTheStraightFallback() async {
        let (s0, s1, s2) = (self.s0, self.s1, self.s2)
        let road01 = road(s0, s1)
        let router = PreviewRouter { from, to in
            from == s0 ? road01 : RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: false, note: "none")
        }
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 0)

        model.update(key([s0, s1, s2], transport: .cycling))
        XCTAssertEqual(model.legs.map(\.style), [.loading, .loading], "legs show at once, before any route is known")
        XCTAssertEqual(model.legs.map(\.points), [[s0, s1], [s1, s2]])

        await model.settled()
        XCTAssertEqual(model.legs.map(\.style), [.road, .straight])
        XCTAssertEqual(model.legs.first?.points, road01.points)
        let requests = await router.requests
        XCTAssertEqual(requests.map(\.travel), [.cycling, .cycling], "the preview asks for the run's own directions")
    }

    func testJumpArrivalNeverAsksForDirections() async {
        let router = PreviewRouter { RoadRoute(points: [$0, $1], distanceMeters: 1, followsRoads: true, note: nil) }
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 0)
        model.update(key([s0, s1, s2], arrival: .jump))
        await model.settled()
        XCTAssertEqual(model.legs.map(\.style), [.jump, .jump])
        XCTAssertEqual(model.legs.map(\.points), [[s0, s1], [s1, s2]])
        let count = await router.requests.count
        XCTAssertEqual(count, 0)
    }

    func testTheSameKeyIsNotFetchedAgainAndAddedStopsFetchOnlyTheNewLeg() async {
        let router = PreviewRouter { from, to in
            RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: true, note: nil)
        }
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 0)
        model.update(key([s0, s1, s2]))
        await model.settled()
        model.update(key([s0, s1, s2]))
        await model.settled()
        model.update(key([s0, s1, s2, s3]))
        XCTAssertEqual(model.legs.map(\.style), [.road, .road, .loading], "known legs keep their road path")
        await model.settled()
        let legs = await router.requestedLegs()
        XCTAssertEqual(legs, [[s0, s1], [s1, s2], [s2, s3]])
    }

    func testANewKeyCancelsTheStaleFetch() async {
        let router = PreviewRouter { from, to in
            RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: true, note: nil)
        }
        await router.close()
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 0)
        model.update(key([s0, s1]))
        await router.waitForRequests(1)

        model.update(key([s2, s3]))
        XCTAssertEqual(model.legs.map(\.points), [[s2, s3]])
        XCTAssertEqual(model.legs.map(\.style), [.loading])
        await router.open()
        await model.settled()

        XCTAssertEqual(model.legs.map(\.points), [[s2, s3]], "the stale leg never comes back")
        XCTAssertEqual(model.legs.map(\.style), [.road])
    }

    func testUpdatesWithinTheDebounceAskOnlyForTheLatestStops() async {
        let router = PreviewRouter { from, to in
            RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: true, note: nil)
        }
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 50_000_000)
        model.update(key([s0, s1]))
        model.update(key([s0, s2]))
        model.update(key([s0, s3]))
        await model.settled()
        let legs = await router.requestedLegs()
        XCTAssertEqual(legs, [[s0, s3]])
        XCTAssertEqual(model.legs.map(\.style), [.road])
    }

    func testAStraightFallbackIsAskedForAgainOnTheNextChange() async {
        let attempts = Counter()
        let router = PreviewRouter { from, to in
            attempts.increment() == 1
                ? RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: false, note: "none")
                : RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: true, note: nil)
        }
        let model = RoutePreviewModel(router: router, debounceNanoseconds: 0)
        model.update(key([s0, s1]))
        await model.settled()
        XCTAssertEqual(model.legs.map(\.style), [.straight])
        model.update(nil)
        XCTAssertTrue(model.legs.isEmpty)
        model.update(key([s0, s1]))
        await model.settled()
        XCTAssertEqual(model.legs.map(\.style), [.road], "the router decides when a failed leg is retried")
    }

    func testWithoutARouterTravelLegsStayLoading() async {
        let model = RoutePreviewModel(router: nil, debounceNanoseconds: 0)
        model.update(key([s0, s1]))
        await model.settled()
        XCTAssertEqual(model.legs.map(\.style), [.loading])
    }

    // MARK: - AppState

    func testAppStateBuildsThePreviewKeyFromTheModeSettingsAndSpeed() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        state.activeMode = .route
        XCTAssertNil(state.routePreviewKey(for: .route))
        state.stageLocation(s0, for: .route)
        state.stageLocation(s1, for: .route)
        state.autoSpeed = false
        state.customSpeedMps = 6
        state.setStopTravelSettings(settings(.travel, repeat: .loop), for: .route)

        XCTAssertEqual(state.routePreviewKey(for: .route), key([s0, s1], repeat: .loop, transport: .cycling))
        XCTAssertNil(state.routePreviewKey(for: .teleport))
    }

    func testAppStatePreviewsTheNextMovesLegOnlyBetweenMoves() async {
        let state = AppState(startBackgroundServices: false, locationInjector: PreviewAckInjector(), routeDelay: { _ in await Task.yield() })
        state.selectedDevice = Device(id: "preview-device", displayName: "Preview Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .route
        state.autoSpeed = false
        state.customSpeedMps = 20
        state.updateFrequencyHz = 5
        for stop in [s0, s1, s2] { state.stageLocation(stop, for: .route) }
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .onePerMove, repeatMode: .oneWay),
            for: .route
        )
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: "preview-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        ))
        XCTAssertNil(state.routePreviewKey(for: .route)?.nextMoveLeg, "nothing held: the first Move places stop 1")

        for _ in 0..<3 { await state.startSimulation() }
        XCTAssertEqual(state.currentLocation, s2)
        XCTAssertEqual(
            state.routePreviewKey(for: .route)?.nextMoveLeg,
            RoutePreviewLegSpec(from: s2, to: s0, returnsToStart: false),
            "the finished One way run starts over from the held last stop"
        )
    }

    func testAppStateDrawsNoNextMoveLegWhileItsRunIsMoving() async {
        // The run's own steps would change the key at every update and keep cancelling
        // the preview's fetches; the run is already driving that leg.
        let fake = FakeLocationInjector()
        let session = LocationSessionIdentity(stableDeviceID: "preview-device", transport: .wifi, endpointClass: .unresolved, generation: 1)
        let state = AppState(startBackgroundServices: false, locationInjector: fake, routeDelay: { _ in })
        state.selectedDevice = Device(id: "preview-device", displayName: "Preview Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .route
        state.autoSpeed = false
        state.customSpeedMps = 20
        state.updateFrequencyHz = 5
        for stop in [s0, s1, s2] { state.stageLocation(stop, for: .route) }
        state.setStopTravelSettings(settings(.travel), for: .route)
        state.locationSessionCoordinator.connectionReady(session)
        state.currentLocation = s3
        XCTAssertEqual(state.routePreviewKey(for: .route)?.nextMoveLeg, RoutePreviewLegSpec(from: s3, to: s0, returnsToStart: false))

        let run = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        XCTAssertTrue(state.isStopRunActive(for: .route))
        XCTAssertNil(state.routePreviewKey(for: .route)?.nextMoveLeg)
        await state.stopSimulation()
        await fake.releaseNextApplication(session: session)
        await run.value
    }

    func testAppStatePreviewUsesTheInjectedRouter() async {
        let router = PreviewRouter { from, to in
            RoadRoute(points: [from, to], distanceMeters: 1, followsRoads: true, note: nil)
        }
        let routed = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector(), roadRouter: router)
        routed.routePreview.update(key([s0, s1]))
        await routed.routePreview.settled()
        XCTAssertEqual(routed.routePreview.legs.map(\.style), [.road])

        let plain = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        plain.routePreview.update(key([s0, s1]))
        await plain.routePreview.settled()
        XCTAssertEqual(plain.routePreview.legs.map(\.style), [.loading], "no router in tests: nothing reaches Apple Maps")
    }
}

/// A thread-safe call counter for `@Sendable` closures.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
