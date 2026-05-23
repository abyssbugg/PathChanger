//
//  SimulationEngineTests.swift
//  PathChangerTests
//
//  Comprehensive tests for SimulationEngine (TEST-001)
//

import XCTest
@testable import PathChanger

// MARK: - Simulation Speed Tests

final class SimulationSpeedTests: XCTestCase {

    func testAllSpeedCasesExist() {
        let allCases = SimulationSpeed.allCases

        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.walking))
        XCTAssertTrue(allCases.contains(.running))
        XCTAssertTrue(allCases.contains(.cycling))
        XCTAssertTrue(allCases.contains(.driving))
        XCTAssertTrue(allCases.contains(.fast))
        XCTAssertTrue(allCases.contains(.teleport))
    }

    func testSpeedMetersPerSecond() {
        XCTAssertEqual(SimulationSpeed.walking.metersPerSecond, 1.4, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.running.metersPerSecond, 3.0, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.cycling.metersPerSecond, 5.5, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.driving.metersPerSecond, 13.9, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.fast.metersPerSecond, 27.8, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.teleport.metersPerSecond, 1000.0, accuracy: 0.1)
    }

    func testSpeedIncreases() {
        // Verify speeds are ordered from slowest to fastest
        XCTAssertLessThan(SimulationSpeed.walking.metersPerSecond, SimulationSpeed.running.metersPerSecond)
        XCTAssertLessThan(SimulationSpeed.running.metersPerSecond, SimulationSpeed.cycling.metersPerSecond)
        XCTAssertLessThan(SimulationSpeed.cycling.metersPerSecond, SimulationSpeed.driving.metersPerSecond)
        XCTAssertLessThan(SimulationSpeed.driving.metersPerSecond, SimulationSpeed.fast.metersPerSecond)
        XCTAssertLessThan(SimulationSpeed.fast.metersPerSecond, SimulationSpeed.teleport.metersPerSecond)
    }

    func testUpdateIntervals() {
        XCTAssertEqual(SimulationSpeed.walking.updateInterval, 1.0, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.running.updateInterval, 1.0, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.cycling.updateInterval, 0.5, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.driving.updateInterval, 0.3, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.fast.updateInterval, 0.2, accuracy: 0.1)
        XCTAssertEqual(SimulationSpeed.teleport.updateInterval, 0.1, accuracy: 0.1)
    }

    func testFasterSpeedsHaveShorterIntervals() {
        // Faster speeds should have shorter update intervals for smoother movement
        XCTAssertGreaterThanOrEqual(SimulationSpeed.walking.updateInterval, SimulationSpeed.cycling.updateInterval)
        XCTAssertGreaterThanOrEqual(SimulationSpeed.cycling.updateInterval, SimulationSpeed.driving.updateInterval)
        XCTAssertGreaterThanOrEqual(SimulationSpeed.driving.updateInterval, SimulationSpeed.fast.updateInterval)
        XCTAssertGreaterThanOrEqual(SimulationSpeed.fast.updateInterval, SimulationSpeed.teleport.updateInterval)
    }

    func testDisplayNames() {
        XCTAssertEqual(SimulationSpeed.walking.displayName, "Walking")
        XCTAssertEqual(SimulationSpeed.running.displayName, "Running")
        XCTAssertEqual(SimulationSpeed.cycling.displayName, "Cycling")
        XCTAssertEqual(SimulationSpeed.driving.displayName, "Driving")
        XCTAssertEqual(SimulationSpeed.fast.displayName, "Fast")
        XCTAssertEqual(SimulationSpeed.teleport.displayName, "Instant")
    }

    func testIcons() {
        XCTAssertEqual(SimulationSpeed.walking.icon, "figure.walk")
        XCTAssertEqual(SimulationSpeed.running.icon, "figure.run")
        XCTAssertEqual(SimulationSpeed.cycling.icon, "bicycle")
        XCTAssertEqual(SimulationSpeed.driving.icon, "car.fill")
        XCTAssertEqual(SimulationSpeed.fast.icon, "car.2.fill")
        XCTAssertEqual(SimulationSpeed.teleport.icon, "location.fill")
    }

    func testIdentifiableConformance() {
        for speed in SimulationSpeed.allCases {
            XCTAssertEqual(speed.id, speed.rawValue)
        }
    }
}

// MARK: - Simulation State Tests

final class SimulationStateTests: XCTestCase {

    func testIdleStateNotActive() {
        let state = SimulationState.idle
        XCTAssertFalse(state.isActive)
    }

    func testRunningStateIsActive() {
        let state = SimulationState.running
        XCTAssertTrue(state.isActive)
    }

    func testPausedStateIsActive() {
        let state = SimulationState.paused
        XCTAssertTrue(state.isActive)
    }

    func testCompletedStateNotActive() {
        let state = SimulationState.completed
        XCTAssertFalse(state.isActive)
    }

    func testErrorStateNotActive() {
        let state = SimulationState.error("Test error")
        XCTAssertFalse(state.isActive)
    }

    func testStateEquality() {
        XCTAssertEqual(SimulationState.idle, SimulationState.idle)
        XCTAssertEqual(SimulationState.running, SimulationState.running)
        XCTAssertEqual(SimulationState.paused, SimulationState.paused)
        XCTAssertEqual(SimulationState.completed, SimulationState.completed)
        XCTAssertEqual(SimulationState.error("A"), SimulationState.error("A"))
    }

    func testStateInequality() {
        XCTAssertNotEqual(SimulationState.idle, SimulationState.running)
        XCTAssertNotEqual(SimulationState.running, SimulationState.paused)
        XCTAssertNotEqual(SimulationState.error("A"), SimulationState.error("B"))
    }
}

// MARK: - Teleport Mode Tests

final class TeleportModeTests: XCTestCase {

    func testInitialStateNotActive() {
        let mode = TeleportMode()

        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.currentCoordinate)
    }

    func testSetTargetAndStart() {
        let mode = TeleportMode()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        mode.setTarget(target)
        mode.start()

        XCTAssertTrue(mode.isActive)
        XCTAssertEqual(mode.currentCoordinate?.latitude, target.latitude)
        XCTAssertEqual(mode.currentCoordinate?.longitude, target.longitude)
    }

    func testStopClearsState() {
        let mode = TeleportMode()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        mode.setTarget(target)
        mode.start()
        mode.stop()

        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.currentCoordinate)
    }

    func testUpdateReturnsCurrentCoordinate() {
        let mode = TeleportMode()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        mode.setTarget(target)
        mode.start()

        let result = mode.update()

        XCTAssertEqual(result?.latitude, target.latitude)
    }

    func testPauseAndResumeAreNoOps() {
        let mode = TeleportMode()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        mode.setTarget(target)
        mode.start()

        // Teleport mode pause/resume are no-ops
        mode.pause()
        XCTAssertTrue(mode.isActive) // Still active

        mode.resume()
        XCTAssertTrue(mode.isActive) // Still active
    }
}

// MARK: - Route Mode Tests

final class RouteModeTests: XCTestCase {

    func testInitialState() {
        let mode = RouteMode()

        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.currentCoordinate)
        XCTAssertEqual(mode.progress, 0)
        XCTAssertEqual(mode.totalDistance, 0)
    }

    func testConfigureWithWaypoints() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6802, longitude: 139.6500)
        ]

        mode.configure(waypoints: waypoints, speed: .walking, loop: false)
        mode.start()

        XCTAssertTrue(mode.isActive)
        XCTAssertNotNil(mode.currentCoordinate)
        XCTAssertGreaterThan(mode.totalDistance, 0)
    }

    func testProgressUpdatesOnUpdate() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.01, longitude: 139.0) // ~1km apart
        ]

        mode.configure(waypoints: waypoints, speed: .teleport, loop: false)
        mode.start()

        let initialProgress = mode.progress

        // Update several times
        for _ in 0..<5 {
            _ = mode.update()
        }

        XCTAssertGreaterThan(mode.progress, initialProgress)
    }

    func testPauseAndResume() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.0)
        ]

        mode.configure(waypoints: waypoints, speed: .driving)
        mode.start()

        XCTAssertTrue(mode.isActive)

        mode.pause()
        XCTAssertFalse(mode.isActive)

        mode.resume()
        XCTAssertTrue(mode.isActive)
    }

    func testStopResetsProgress() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.0)
        ]

        mode.configure(waypoints: waypoints, speed: .driving)
        mode.start()

        // Update a few times
        for _ in 0..<3 {
            _ = mode.update()
        }

        mode.stop()

        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.currentCoordinate)
    }

    func testLoopingBehavior() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.0001, longitude: 139.0) // Very close
        ]

        mode.configure(waypoints: waypoints, speed: .teleport, loop: true)
        mode.start()

        // Should loop and stay active after completing route
        for _ in 0..<100 {
            _ = mode.update()
        }

        // Should still be active due to looping
        XCTAssertTrue(mode.isActive)
    }

    func testNonLoopingCompletes() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.0001, longitude: 139.0)
        ]

        mode.configure(waypoints: waypoints, speed: .teleport, loop: false)
        mode.start()

        // Update many times to complete route
        for _ in 0..<1000 {
            _ = mode.update()
        }

        // Should become inactive after completion
        XCTAssertFalse(mode.isActive)
    }

    func testEstimatedDuration() {
        let mode = RouteMode()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.01, longitude: 139.0)
        ]

        mode.configure(waypoints: waypoints, speed: .walking)

        // Should have estimated duration based on distance and speed
        XCTAssertGreaterThan(mode.estimatedDuration, 0)
    }
}

// MARK: - Joystick Mode Tests

final class JoystickModeTests: XCTestCase {

    func testInitialState() {
        let mode = JoystickMode()

        XCTAssertFalse(mode.isActive)
        XCTAssertNil(mode.currentCoordinate)
    }

    func testConfigureAndStart() {
        let mode = JoystickMode()
        let startLocation = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        mode.configure(startLocation: startLocation, speed: .walking)
        mode.start()

        XCTAssertTrue(mode.isActive)
        XCTAssertEqual(mode.currentCoordinate?.latitude, startLocation.latitude)
    }

    func testHeadingConversion() {
        let mode = JoystickMode()

        mode.setDirection(degrees: 90)
        XCTAssertEqual(mode.heading, 90, accuracy: 0.001)

        mode.setDirection(degrees: 180)
        XCTAssertEqual(mode.heading, 180, accuracy: 0.001)

        mode.setDirection(degrees: 270)
        XCTAssertEqual(mode.heading, 270, accuracy: 0.001)
    }

    func testMovementWhenActive() {
        let mode = JoystickMode()
        let startLocation = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        mode.configure(startLocation: startLocation, speed: .walking)
        mode.start()
        mode.setMoving(true)
        mode.setDirection(degrees: 0) // North

        let initialLat = mode.currentCoordinate!.latitude

        _ = mode.update()

        // Should move north (latitude increases)
        XCTAssertGreaterThan(mode.currentCoordinate!.latitude, initialLat)
    }

    func testNoMovementWhenNotMoving() {
        let mode = JoystickMode()
        let startLocation = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        mode.configure(startLocation: startLocation, speed: .walking)
        mode.start()
        mode.setMoving(false)

        let initialCoord = mode.currentCoordinate

        _ = mode.update()

        // Should not move
        XCTAssertEqual(mode.currentCoordinate?.latitude, initialCoord?.latitude)
        XCTAssertEqual(mode.currentCoordinate?.longitude, initialCoord?.longitude)
    }

    func testPauseAndResume() {
        let mode = JoystickMode()
        let startLocation = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        mode.configure(startLocation: startLocation, speed: .walking)
        mode.start()

        XCTAssertTrue(mode.isActive)

        mode.pause()
        XCTAssertFalse(mode.isActive)

        mode.resume()
        XCTAssertTrue(mode.isActive)
    }

    func testStopClearsMoving() {
        let mode = JoystickMode()
        let startLocation = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        mode.configure(startLocation: startLocation, speed: .walking)
        mode.start()
        mode.setMoving(true)

        mode.stop()

        XCTAssertFalse(mode.isActive)
    }
}

// MARK: - Simulation Engine State Tests

final class SimulationEngineStateTests: XCTestCase {

    private func testDevice() -> Device {
        Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
    }

    @MainActor
    func testInitialState() {
        let engine = SimulationEngine()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.currentMode, .teleport)
        XCTAssertEqual(engine.speed, .driving)
        XCTAssertNil(engine.currentCoordinate)
        XCTAssertEqual(engine.routeProgress, 0.0)
        XCTAssertEqual(engine.elapsedTime, 0)
        XCTAssertFalse(engine.loopRoute)
    }

    @MainActor
    func testSpeedCanBeChanged() {
        let engine = SimulationEngine()

        engine.speed = .walking
        XCTAssertEqual(engine.speed, .walking)

        engine.speed = .fast
        XCTAssertEqual(engine.speed, .fast)
    }

    @MainActor
    func testLoopRouteCanBeToggled() {
        let engine = SimulationEngine()

        XCTAssertFalse(engine.loopRoute)

        engine.loopRoute = true
        XCTAssertTrue(engine.loopRoute)

        engine.loopRoute = false
        XCTAssertFalse(engine.loopRoute)
    }

    @MainActor
    func testTeleportWithoutDeviceFails() async {
        let engine = SimulationEngine()
        let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        do {
            try await engine.teleport(to: coordinate)
            XCTFail("Should throw error without device")
        } catch {
            // Canonical §5.1 lexicon (W0 vocabulary unification):
            // "No device selected" → "Connect an iPhone to begin".
            XCTAssertEqual(engine.state, .error("Connect an iPhone to begin"))
        }
    }

    @MainActor
    func testStartRouteWithoutDeviceFails() async {
        let engine = SimulationEngine()
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.0)
        ]

        await engine.startRoute(waypoints: waypoints)

        // Canonical §5.1 lexicon (W0 vocabulary unification).
        XCTAssertEqual(engine.state, .error("Connect an iPhone to begin"))
    }

    @MainActor
    func testStartRouteWithSingleWaypointFails() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
        engine.setDevice(device)

        let waypoints = [LocationCoordinate(latitude: 35.0, longitude: 139.0)]

        await engine.startRoute(waypoints: waypoints)

        XCTAssertEqual(engine.state, .error("Route requires at least 2 waypoints"))
    }

    @MainActor
    func testStartJoystickWithoutDeviceFails() async {
        let engine = SimulationEngine()
        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)

        // Canonical §5.1 lexicon (W0 vocabulary unification).
        XCTAssertEqual(engine.state, .error("Connect an iPhone to begin"))
    }

    @MainActor
    func testPauseChangesState() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
        engine.setDevice(device)

        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)

        XCTAssertEqual(engine.state, .running)

        engine.pause()

        XCTAssertEqual(engine.state, .paused)
    }

    @MainActor
    func testResumeFromPaused() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
        engine.setDevice(device)

        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)
        engine.pause()

        XCTAssertEqual(engine.state, .paused)

        engine.resume()

        XCTAssertEqual(engine.state, .running)
    }

    @MainActor
    func testResumeWhenNotPausedIsNoOp() {
        let engine = SimulationEngine()

        engine.resume()

        XCTAssertEqual(engine.state, .idle)
    }

    @MainActor
    func testPauseWhenIdleIsNoOp() {
        let engine = SimulationEngine()

        engine.pause()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.testHasActiveTimer)
    }

    @MainActor
    func testStartingRouteAdvancesSessionAndInvalidatesJoystickTimer() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: start)
        let joystickSessionID = engine.testSimulationSessionID

        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.currentMode, .joystick)
        XCTAssertTrue(engine.testHasActiveTimer)

        await engine.startRoute(waypoints: [
            start,
            LocationCoordinate(latitude: 35.01, longitude: 139.0)
        ])

        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.currentMode, .route)
        XCTAssertGreaterThan(engine.testSimulationSessionID, joystickSessionID)
        XCTAssertTrue(engine.testHasActiveTimer)

        engine.pause()
    }

    @MainActor
    func testStaleTickFromPriorSessionCannotMutateNewRoute() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: start)
        let staleSessionID = engine.testSimulationSessionID

        await engine.startRoute(waypoints: [
            start,
            LocationCoordinate(latitude: 35.01, longitude: 139.0)
        ])
        let currentSessionID = engine.testSimulationSessionID
        let routeProgress = engine.routeProgress

        await engine.testRunTick(sessionID: staleSessionID)

        XCTAssertEqual(engine.testSimulationSessionID, currentSessionID)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.currentMode, .route)
        XCTAssertEqual(engine.routeProgress, routeProgress)

        engine.pause()
    }

    @MainActor
    func testJoystickTickStopsAndDoesNotAdvanceOnTunnelInvalidation() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        var sendCount = 0
        engine.testSetLocationHandler = { _, _ in
            sendCount += 1
            throw LocationBridge.LocationBridgeError.tunnelInvalidated("No route to host")
        }
        defer {
            engine.testSetLocationHandler = nil
        }

        await engine.startJoystick(at: start)
        let sessionID = engine.testSimulationSessionID
        engine.setJoystickDirection(degrees: 0)
        engine.setJoystickMoving(true)

        await engine.testRunTick(sessionID: sessionID)

        XCTAssertEqual(sendCount, 1)
        if case .error(let message) = engine.state {
            XCTAssertTrue(message.contains("No route to host"))
        } else {
            XCTFail("Expected simulation to enter error after tunnel invalidation")
        }
        XCTAssertFalse(engine.testHasActiveTimer)
        XCTAssertFalse(engine.testHasActiveTick)
        XCTAssertEqual(engine.currentCoordinate?.latitude, start.latitude)
        XCTAssertEqual(engine.currentCoordinate?.longitude, start.longitude)
    }

    @MainActor
    func testRestoreJoystickSessionAfterTransportRecoveryCanResumeRunning() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: start)
        engine.updateJoystickDirection(CGPoint(x: 0, y: 1))
        let originalSessionID = engine.testSimulationSessionID

        engine.testFailActiveSimulationAfterTransportFailure("No route to host")
        XCTAssertFalse(engine.testHasActiveTimer)
        if case .error = engine.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected error state before recovery restoration")
        }

        engine.restoreSessionAfterTransportRecovery(
            mode: .joystick,
            coordinate: start,
            routeWaypoints: [],
            routeProgress: 0,
            joystickDirection: CGPoint(x: 0, y: 1),
            wasPaused: false
        )

        XCTAssertGreaterThan(engine.testSimulationSessionID, originalSessionID)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.currentMode, .joystick)
        XCTAssertTrue(engine.testHasActiveTimer)
        XCTAssertEqual(engine.currentCoordinate?.latitude, start.latitude)
        XCTAssertEqual(engine.currentCoordinate?.longitude, start.longitude)

        engine.pause()
    }

    @MainActor
    func testRestoreJoystickSessionAfterTransportRecoveryPreservesPausedState() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        engine.restoreSessionAfterTransportRecovery(
            mode: .joystick,
            coordinate: start,
            routeWaypoints: [],
            routeProgress: 0,
            joystickDirection: CGPoint(x: 0, y: 1),
            wasPaused: true
        )

        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(engine.currentMode, .joystick)
        XCTAssertFalse(engine.testHasActiveTimer)
        XCTAssertEqual(engine.currentCoordinate?.latitude, start.latitude)
        XCTAssertEqual(engine.currentCoordinate?.longitude, start.longitude)
    }

    @MainActor
    func testPauseResumeKeepsSessionAndRestartsTimer() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        await engine.startJoystick(at: LocationCoordinate(latitude: 35.0, longitude: 139.0))
        let runningSessionID = engine.testSimulationSessionID

        engine.pause()

        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(engine.testSimulationSessionID, runningSessionID)
        XCTAssertFalse(engine.testHasActiveTimer)

        engine.resume()

        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.testSimulationSessionID, runningSessionID)
        XCTAssertTrue(engine.testHasActiveTimer)

        engine.pause()
    }

    @MainActor
    func testRapidLifecycleTransitionsInvalidateTimersAndStaleTicks() async {
        let engine = SimulationEngine()
        engine.speed = .walking
        engine.setDevice(testDevice())

        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        var staleSessionIDs: [UInt64] = []

        for index in 0..<20 {
            let location = LocationCoordinate(
                latitude: start.latitude + Double(index) * 0.0001,
                longitude: start.longitude
            )

            await engine.startJoystick(at: location)
            let joystickSessionID = engine.testSimulationSessionID

            XCTAssertEqual(engine.state, .running)
            XCTAssertEqual(engine.currentMode, .joystick)
            XCTAssertTrue(engine.testHasActiveTimer)

            engine.pause()

            XCTAssertEqual(engine.state, .paused)
            XCTAssertFalse(engine.testHasActiveTimer)

            await engine.startRoute(waypoints: [
                location,
                LocationCoordinate(latitude: location.latitude + 0.01, longitude: location.longitude)
            ])
            let routeSessionID = engine.testSimulationSessionID

            XCTAssertEqual(engine.state, .running)
            XCTAssertEqual(engine.currentMode, .route)
            XCTAssertGreaterThan(routeSessionID, joystickSessionID)
            XCTAssertTrue(engine.testHasActiveTimer)

            await engine.testRunTick(sessionID: joystickSessionID)

            XCTAssertEqual(engine.testSimulationSessionID, routeSessionID)
            XCTAssertEqual(engine.state, .running)
            XCTAssertEqual(engine.currentMode, .route)

            staleSessionIDs.append(joystickSessionID)
            engine.pause()
        }

        for staleSessionID in staleSessionIDs {
            await engine.testRunTick(sessionID: staleSessionID)
        }

        XCTAssertEqual(engine.state, .paused)
        XCTAssertFalse(engine.testHasActiveTimer)
        XCTAssertFalse(engine.testHasActiveTick)
    }

    @MainActor
    func testStopResetsState() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
        engine.setDevice(device)

        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)

        await engine.stop()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.currentCoordinate)
        XCTAssertEqual(engine.routeProgress, 0)
        XCTAssertEqual(engine.elapsedTime, 0)
    }

    @MainActor
    func testSetDevice() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "ABCD1234-5678-90EF-GHIJ-KLMNOPQRSTUV",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone14,2"
        )

        engine.setDevice(device)

        // Device is set (we can't access it directly, but we can verify
        // that operations requiring a device work now)
        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)

        XCTAssertEqual(engine.state, .running)
    }

    @MainActor
    func testJoystickDirectionControl() async {
        let engine = SimulationEngine()
        let device = Device(
            id: "00000000-0000000000000000",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone"
        )
        engine.setDevice(device)

        let location = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        await engine.startJoystick(at: location)

        // These should not crash
        engine.setJoystickDirection(degrees: 45)
        engine.setJoystickMoving(true)
        engine.setJoystickMoving(false)
    }
}

// MARK: - Simulation Mode Type Tests

final class SimulationModeTypeTests: XCTestCase {

    func testModeTypeValues() {
        XCTAssertEqual(SimulationModeType.teleport.rawValue, "teleport")
        XCTAssertEqual(SimulationModeType.route.rawValue, "route")
        XCTAssertEqual(SimulationModeType.joystick.rawValue, "joystick")
    }
}
