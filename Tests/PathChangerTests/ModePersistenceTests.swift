import XCTest
@testable import PathChanger

@MainActor
final class ModePersistenceTests: XCTestCase {
    private let first = LocationCoordinate(latitude: 35.67620, longitude: 139.65030)
    private let second = LocationCoordinate(latitude: 35.67621, longitude: 139.65031)
    private let third = LocationCoordinate(latitude: 35.67622, longitude: 139.65032)

    private func makeRouteState(
        injector: FakeLocationInjector,
        mode: AppMode,
        route: [LocationCoordinate]
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            routeDelay: { _ in }
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
}
