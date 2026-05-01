//
//  StateManagerTests.swift
//  PathChangerTests
//
//  Tests for domain-specific state managers (ARCH-002).
//

import XCTest
@testable import PathChanger

// MARK: - Simulation State Manager Tests

final class SimulationStateManagerTests: XCTestCase {

    @MainActor
    func testInitialState() async {
        let manager = SimulationStateManager()

        XCTAssertFalse(manager.isSimulating)
        XCTAssertFalse(manager.isPaused)
        XCTAssertEqual(manager.simulationSpeed, .walking)
        XCTAssertEqual(manager.activeMode, .none)
        XCTAssertNil(manager.currentLocation)
        XCTAssertNil(manager.targetLocation)
        XCTAssertEqual(manager.joystickDirection, .zero)
    }

    @MainActor
    func testCanStartSimulationRequiresDeviceState() async {
        let manager = SimulationStateManager()

        // No device state manager set
        XCTAssertFalse(manager.canStartSimulation)
    }

    @MainActor
    func testStatusTextWithNoDeviceState() async {
        let manager = SimulationStateManager()

        XCTAssertEqual(manager.statusText, "Initializing...")
    }

    @MainActor
    func testPauseAndResumeSimulation() async {
        let manager = SimulationStateManager()

        manager.isSimulating = true
        manager.pauseSimulation()

        XCTAssertTrue(manager.isPaused)

        manager.resumeSimulation()

        XCTAssertFalse(manager.isPaused)
    }

    @MainActor
    func testUpdateJoystickDirectionChangesMode() async {
        let manager = SimulationStateManager()

        XCTAssertEqual(manager.activeMode, .none)

        manager.updateJoystickDirection(CGPoint(x: 0.5, y: 0.5))

        XCTAssertEqual(manager.activeMode, .joystick)
        XCTAssertEqual(manager.joystickDirection, CGPoint(x: 0.5, y: 0.5))
    }

    @MainActor
    func testSetSpeed() async {
        let manager = SimulationStateManager()

        manager.setSpeed(.driving)

        XCTAssertEqual(manager.simulationSpeed, .driving)
    }

    @MainActor
    func testActiveSimulationModeProperties() {
        XCTAssertEqual(ActiveSimulationMode.none.icon, "circle.slash")
        XCTAssertEqual(ActiveSimulationMode.teleport.icon, "location.fill")
        XCTAssertEqual(ActiveSimulationMode.route.icon, "point.topleft.down.curvedto.point.bottomright.up")
        XCTAssertEqual(ActiveSimulationMode.joystick.icon, "gamecontroller.fill")
    }
}

// MARK: - Route State Manager Tests

final class RouteStateManagerTests: XCTestCase {

    var routeLibrary: RouteLibraryManager!

    @MainActor
    override func setUp() async throws {
        routeLibrary = RouteLibraryManager()
    }

    @MainActor
    override func tearDown() async throws {
        routeLibrary = nil
    }

    @MainActor
    func testInitialState() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        XCTAssertTrue(manager.currentRoute.isEmpty)
        XCTAssertEqual(manager.progress, 0)
        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertNil(manager.routeName)
        XCTAssertFalse(manager.loopEnabled)
        XCTAssertFalse(manager.reverseOnLoop)

        if case .idle = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected idle playback state")
        }
    }

    @MainActor
    func testIsRouteLoaded() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        XCTAssertFalse(manager.isRouteLoaded)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)

        XCTAssertTrue(manager.isRouteLoaded)
    }

    @MainActor
    func testLoadRouteWithCoordinates() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504),
            LocationCoordinate(latitude: 35.6764, longitude: 139.6505)
        ]

        manager.loadRoute(from: coordinates, name: "Test Route")

        XCTAssertEqual(manager.currentRoute.count, 3)
        XCTAssertEqual(manager.routeName, "Test Route")
        XCTAssertEqual(manager.waypointCount, 3)
        XCTAssertGreaterThan(manager.totalDistance, 0)

        if case .ready = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected ready playback state")
        }
    }

    @MainActor
    func testLoadEmptyRouteSetsError() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        manager.loadRoute(from: [])

        if case .error(let message) = manager.playbackState {
            XCTAssertEqual(message, "Empty route")
        } else {
            XCTFail("Expected error state")
        }
    }

    @MainActor
    func testClearRoute() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates, name: "Test Route")
        XCTAssertTrue(manager.isRouteLoaded)

        manager.clearRoute()

        XCTAssertFalse(manager.isRouteLoaded)
        XCTAssertNil(manager.routeName)
        XCTAssertEqual(manager.progress, 0)

        if case .idle = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected idle playback state")
        }
    }

    @MainActor
    func testSkipToWaypoint() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = (0..<10).map { i in
            LocationCoordinate(latitude: 35.6762 + Double(i) * 0.001, longitude: 139.6503)
        }

        manager.loadRoute(from: coordinates)

        manager.skipToWaypoint(5)

        XCTAssertEqual(manager.currentIndex, 5)
        XCTAssertEqual(manager.progress, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testSkipForwardAndBackward() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = (0..<20).map { i in
            LocationCoordinate(latitude: 35.6762 + Double(i) * 0.001, longitude: 139.6503)
        }

        manager.loadRoute(from: coordinates)

        // Start at index 0
        manager.skipForward(5)
        XCTAssertEqual(manager.currentIndex, 5)

        manager.skipForward(5)
        XCTAssertEqual(manager.currentIndex, 10)

        manager.skipBackward(3)
        XCTAssertEqual(manager.currentIndex, 7)

        // Test bounds
        manager.skipBackward(100) // Should clamp to 0
        XCTAssertEqual(manager.currentIndex, 0)

        manager.skipForward(100) // Should clamp to last index
        XCTAssertEqual(manager.currentIndex, 19)
    }

    @MainActor
    func testPausePlayback() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)
        manager.pausePlayback()

        if case .paused = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected paused playback state")
        }
    }

    @MainActor
    func testStopPlayback() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)
        manager.currentIndex = 1
        manager.progress = 0.5

        manager.stopPlayback()

        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertEqual(manager.progress, 0)

        // Route is still loaded
        if case .ready = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected ready playback state after stop")
        }
    }

    @MainActor
    func testCurrentWaypoint() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)

        XCTAssertEqual(manager.currentWaypoint?.latitude, 35.6762)

        manager.skipToWaypoint(1)
        XCTAssertEqual(manager.currentWaypoint?.latitude, 35.6763)
    }

    @MainActor
    func testRoutePlaybackStateDisplayText() {
        XCTAssertEqual(RoutePlaybackState.idle.displayText, "No route loaded")
        XCTAssertEqual(RoutePlaybackState.loading.displayText, "Loading route...")
        XCTAssertEqual(RoutePlaybackState.ready.displayText, "Ready to play")
        XCTAssertEqual(RoutePlaybackState.playing.displayText, "Playing...")
        XCTAssertEqual(RoutePlaybackState.paused.displayText, "Paused")
        XCTAssertEqual(RoutePlaybackState.completed.displayText, "Completed")
        XCTAssertEqual(RoutePlaybackState.error("Test").displayText, "Error: Test")
    }

    @MainActor
    func testRoutePlaybackStateIsActive() {
        XCTAssertFalse(RoutePlaybackState.idle.isActive)
        XCTAssertFalse(RoutePlaybackState.loading.isActive)
        XCTAssertFalse(RoutePlaybackState.ready.isActive)
        XCTAssertTrue(RoutePlaybackState.playing.isActive)
        XCTAssertTrue(RoutePlaybackState.paused.isActive)
        XCTAssertFalse(RoutePlaybackState.completed.isActive)
        XCTAssertFalse(RoutePlaybackState.error("Test").isActive)
    }
}

// MARK: - Connection Status Tests

final class ConnectionStatusTests: XCTestCase {

    func testConnectionStatusColors() {
        // Test that each status has a defined color
        XCTAssertNotNil(ConnectionStatus.disconnected.color)
        XCTAssertNotNil(ConnectionStatus.connecting.color)
        XCTAssertNotNil(ConnectionStatus.connected.color)
        XCTAssertNotNil(ConnectionStatus.error.color)
    }

    func testConnectionStatusText() {
        XCTAssertEqual(ConnectionStatus.disconnected.text, "Disconnected")
        XCTAssertEqual(ConnectionStatus.connecting.text, "Connecting...")
        XCTAssertEqual(ConnectionStatus.connected.text, "Connected")
        XCTAssertEqual(ConnectionStatus.error.text, "Error")
    }
}
