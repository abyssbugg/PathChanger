//
//  AppStateSimulationTests.swift
//  PathChangerTests
//
//  Multi-Spot waypoint editing and Play dispatch without a live device.
//

import XCTest
@testable import PathChanger

@MainActor
final class AppStateSimulationTests: XCTestCase {

    private func makeState() -> AppState {
        AppState(startBackgroundServices: false)
    }

    private let first = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let second = LocationCoordinate(latitude: 35.6772, longitude: 139.6513)

    func testAddRouteWaypointAppendsWithoutInjecting() {
        let state = makeState()

        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        XCTAssertEqual(state.currentRoute, [first, second])
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertFalse(state.isSimulating)
    }

    func testRemoveLastRouteWaypoint() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        state.removeLastRouteWaypoint()

        XCTAssertEqual(state.currentRoute, [first])
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testClearRouteEmptiesWaypoints() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)
        state.routeProgress = 0.4

        state.clearRoute()

        XCTAssertTrue(state.currentRoute.isEmpty)
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testStartSimulationWithoutDeviceDoesNotMarkSimulating() async {
        let state = makeState()
        state.activeMode = .route
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        await state.startSimulation()

        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationRouteWithoutTwoSpotsSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .route
        state.addRouteWaypoint(first)

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Add at least two spots on the map")
        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationJoystickWithoutStartSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .joystick

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Tap the map to set a starting location")
        XCTAssertFalse(state.isSimulating)
    }

    func testUpdateJoystickDirectionStoresVector() {
        let state = makeState()
        let direction = CGPoint(x: 0.4, y: -0.6)

        state.updateJoystickDirection(direction)

        XCTAssertEqual(state.joystickDirection.x, direction.x, accuracy: 1e-9)
        XCTAssertEqual(state.joystickDirection.y, direction.y, accuracy: 1e-9)
    }
}
