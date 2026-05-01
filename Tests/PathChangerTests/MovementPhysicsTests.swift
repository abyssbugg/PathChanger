//
//  MovementPhysicsTests.swift
//  PathChangerTests
//
//  Tests for physics-based movement simulation
//

import XCTest
@testable import PathChanger

// MARK: - Movement Behavior Tests

final class MovementBehaviorTests: XCTestCase {

    func testAllBehaviorsHaveDisplayNames() {
        for behavior in MovementBehavior.allCases {
            XCTAssertFalse(behavior.displayName.isEmpty, "\(behavior) should have display name")
        }
    }

    func testAllBehaviorsHaveIcons() {
        for behavior in MovementBehavior.allCases {
            XCTAssertFalse(behavior.icon.isEmpty, "\(behavior) should have icon")
        }
    }

    func testBehaviorSpeedsIncreaseReasonably() {
        let walking = MovementBehavior.walking.physics.maxSpeed
        let running = MovementBehavior.running.physics.maxSpeed
        let cycling = MovementBehavior.cycling.physics.maxSpeed
        let driving = MovementBehavior.driving.physics.maxSpeed

        XCTAssertLessThan(walking, running, "Walking should be slower than running")
        XCTAssertLessThan(running, cycling, "Running should be slower than cycling")
        XCTAssertLessThan(cycling, driving, "Cycling should be slower than driving")
    }

    func testWalkingSpeedIsRealistic() {
        let physics = MovementBehavior.walking.physics

        // Walking should be ~1.4 m/s (about 5 km/h)
        XCTAssertGreaterThan(physics.maxSpeed, 1.0)
        XCTAssertLessThan(physics.maxSpeed, 2.0)
    }

    func testDrivingSpeedIsRealistic() {
        let physics = MovementBehavior.driving.physics

        // City driving should be ~13-17 m/s (about 50-60 km/h)
        XCTAssertGreaterThan(physics.maxSpeed, 10.0)
        XCTAssertLessThan(physics.maxSpeed, 30.0)
    }

    func testAllBehaviorsHavePositiveAcceleration() {
        for behavior in MovementBehavior.allCases {
            XCTAssertGreaterThan(behavior.physics.acceleration, 0, "\(behavior) should have positive acceleration")
        }
    }

    func testAllBehaviorsHavePositiveDeceleration() {
        for behavior in MovementBehavior.allCases {
            XCTAssertGreaterThan(behavior.physics.deceleration, 0, "\(behavior) should have positive deceleration")
        }
    }

    func testJitterIsWithinReasonableRange() {
        for behavior in MovementBehavior.allCases {
            XCTAssertGreaterThanOrEqual(behavior.physics.jitter, 0, "\(behavior) jitter should be non-negative")
            XCTAssertLessThan(behavior.physics.jitter, 1.0, "\(behavior) jitter should be less than 1 meter")
        }
    }

    func testTurnSmoothnessIsNormalized() {
        for behavior in MovementBehavior.allCases {
            XCTAssertGreaterThanOrEqual(behavior.physics.turnSmoothness, 0, "\(behavior) turn smoothness should be >= 0")
            XCTAssertLessThanOrEqual(behavior.physics.turnSmoothness, 1, "\(behavior) turn smoothness should be <= 1")
        }
    }

    func testPauseDurationRangeIsValid() {
        for behavior in MovementBehavior.allCases {
            let range = behavior.physics.pauseDuration
            XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound, "\(behavior) pause duration should be valid range")
        }
    }
}

// MARK: - Physics Configuration Tests

final class MovementPhysicsConfigTests: XCTestCase {

    func testCustomConfigurationInitialization() {
        let config = MovementPhysicsConfig(
            maxSpeed: 5.0,
            acceleration: 1.0,
            deceleration: 2.0,
            jitter: 0.05,
            turnSmoothness: 0.5,
            stopProbability: 0.01,
            pauseDuration: 1.0...3.0
        )

        XCTAssertEqual(config.maxSpeed, 5.0)
        XCTAssertEqual(config.acceleration, 1.0)
        XCTAssertEqual(config.deceleration, 2.0)
        XCTAssertEqual(config.jitter, 0.05)
        XCTAssertEqual(config.turnSmoothness, 0.5)
        XCTAssertEqual(config.stopProbability, 0.01)
    }
}

// MARK: - Movement State Tests

final class MovementStateTests: XCTestCase {

    func testInitialState() {
        let position = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let state = MovementState(position: position)

        XCTAssertEqual(state.velocity, 0)
        XCTAssertEqual(state.heading, 0)
        XCTAssertEqual(state.targetHeading, 0)
        XCTAssertEqual(state.position.latitude, 35.0)
        XCTAssertEqual(state.position.longitude, 139.0)
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.pauseRemaining, 0)
    }
}

// MARK: - Movement Physics Engine Tests

final class MovementPhysicsEngineTests: XCTestCase {

    var engine: MovementPhysicsEngine!
    let startPosition = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

    override func setUp() {
        super.setUp()
        engine = MovementPhysicsEngine(startPosition: startPosition, behavior: .walking)
    }

    func testInitialization() {
        XCTAssertEqual(engine.state.position.latitude, startPosition.latitude)
        XCTAssertEqual(engine.state.position.longitude, startPosition.longitude)
        XCTAssertEqual(engine.state.velocity, 0)
        XCTAssertFalse(engine.isMoving)
    }

    func testBehaviorChange() {
        engine.behavior = .driving
        XCTAssertEqual(engine.behavior, .driving)
    }

    func testSetTarget() {
        let target = LocationCoordinate(latitude: 35.68, longitude: 139.65)
        engine.setTarget(target)

        // Heading should be calculated toward target
        // Target is north-northeast of start
        XCTAssertNotEqual(engine.state.targetHeading, 0)
    }

    func testNoMovementWhenNotActive() {
        let initialPosition = engine.state.position

        engine.isMoving = false
        let newPosition = engine.update(deltaTime: 1.0)

        // Should not have moved significantly
        XCTAssertEqual(newPosition.latitude, initialPosition.latitude, accuracy: 0.0001)
        XCTAssertEqual(newPosition.longitude, initialPosition.longitude, accuracy: 0.0001)
    }

    func testAcceleration() {
        let target = LocationCoordinate(latitude: 35.68, longitude: 139.65)
        engine.setTarget(target)
        engine.isMoving = true

        let initialVelocity = engine.state.velocity
        _ = engine.update(deltaTime: 1.0)

        // Should have accelerated
        XCTAssertGreaterThan(engine.state.velocity, initialVelocity)
    }

    func testVelocityDoesNotExceedMaxSpeed() {
        let target = LocationCoordinate(latitude: 36.0, longitude: 140.0) // Far away
        engine.setTarget(target)
        engine.isMoving = true

        // Run many updates to reach max speed
        for _ in 0..<100 {
            _ = engine.update(deltaTime: 0.1)
        }

        XCTAssertLessThanOrEqual(engine.state.velocity, engine.behavior.physics.maxSpeed)
    }

    func testReset() {
        let target = LocationCoordinate(latitude: 35.68, longitude: 139.65)
        engine.setTarget(target)
        engine.isMoving = true
        _ = engine.update(deltaTime: 1.0)

        let newPosition = LocationCoordinate(latitude: 34.0, longitude: 138.0)
        engine.reset(to: newPosition)

        XCTAssertEqual(engine.state.position.latitude, newPosition.latitude)
        XCTAssertEqual(engine.state.position.longitude, newPosition.longitude)
        XCTAssertEqual(engine.state.velocity, 0)
        XCTAssertFalse(engine.isMoving)
    }

    func testSetVelocity() {
        engine.setVelocity(1.0)
        XCTAssertEqual(engine.state.velocity, 1.0)
    }

    func testSetVelocityClampedToMaxSpeed() {
        engine.setVelocity(100.0) // Way over max
        XCTAssertLessThanOrEqual(engine.state.velocity, engine.behavior.physics.maxSpeed)
    }

    func testSetVelocityClampedToZero() {
        engine.setVelocity(-5.0) // Negative
        XCTAssertGreaterThanOrEqual(engine.state.velocity, 0)
    }

    func testMovementTowardTarget() {
        let target = LocationCoordinate(latitude: 35.68, longitude: 139.65)
        engine.setTarget(target)
        engine.isMoving = true

        let initialDistance = distanceBetween(engine.state.position, target)

        // Move for a while
        for _ in 0..<10 {
            _ = engine.update(deltaTime: 0.1)
        }

        let newDistance = distanceBetween(engine.state.position, target)

        // Should be closer to target
        XCTAssertLessThan(newDistance, initialDistance)
    }

    // Helper function
    private func distanceBetween(_ a: LocationCoordinate, _ b: LocationCoordinate) -> Double {
        let R = 6371000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180

        let aa = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(aa), sqrt(1-aa))

        return R * c
    }
}

// MARK: - Route Recorder Tests

final class RouteRecorderTests: XCTestCase {

    var recorder: RouteRecorder!

    override func setUp() {
        super.setUp()
        recorder = RouteRecorder()
    }

    func testInitialState() {
        XCTAssertTrue(recorder.recordedPoints.isEmpty)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.totalDistance, 0)
        XCTAssertEqual(recorder.totalDuration, 0)
    }

    func testStartRecording() {
        recorder.startRecording()
        XCTAssertTrue(recorder.isRecording)
    }

    func testStopRecording() {
        recorder.startRecording()
        recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
    }

    func testRecordPointWhenNotRecording() {
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let added = recorder.recordPoint(coord)

        XCTAssertFalse(added)
        XCTAssertTrue(recorder.recordedPoints.isEmpty)
    }

    func testRecordPointWhenRecording() {
        recorder.startRecording()

        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let added = recorder.recordPoint(coord)

        XCTAssertTrue(added)
        XCTAssertEqual(recorder.recordedPoints.count, 1)
    }

    func testMinimumDistanceFilter() {
        recorder.startRecording()

        let coord1 = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let coord2 = LocationCoordinate(latitude: 35.00001, longitude: 139.00001) // Very close

        recorder.recordPoint(coord1)
        let added = recorder.recordPoint(coord2)

        // Second point should be filtered out (too close)
        XCTAssertFalse(added)
        XCTAssertEqual(recorder.recordedPoints.count, 1)
    }

    func testRecordDistantPoints() {
        recorder.startRecording()

        let coord1 = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let coord2 = LocationCoordinate(latitude: 35.001, longitude: 139.001) // ~150m away

        recorder.recordPoint(coord1)
        let added = recorder.recordPoint(coord2)

        XCTAssertTrue(added)
        XCTAssertEqual(recorder.recordedPoints.count, 2)
    }

    func testClearRecording() {
        recorder.startRecording()
        recorder.recordPoint(LocationCoordinate(latitude: 35.0, longitude: 139.0))

        recorder.clearRecording()

        XCTAssertTrue(recorder.recordedPoints.isEmpty)
        XCTAssertFalse(recorder.isRecording)
    }

    func testExportAsCoordinates() {
        recorder.startRecording()

        let coord1 = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let coord2 = LocationCoordinate(latitude: 35.001, longitude: 139.001)

        recorder.recordPoint(coord1)
        recorder.recordPoint(coord2)

        let exported = recorder.exportAsCoordinates()

        XCTAssertEqual(exported.count, 2)
        XCTAssertEqual(exported[0].latitude, coord1.latitude)
        XCTAssertEqual(exported[1].latitude, coord2.latitude)
    }

    func testExportWithTiming() {
        recorder.startRecording()

        let coord1 = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let coord2 = LocationCoordinate(latitude: 35.001, longitude: 139.001)

        recorder.recordPoint(coord1)

        // Small delay
        Thread.sleep(forTimeInterval: 0.1)

        recorder.recordPoint(coord2)

        let exported = recorder.exportWithTiming()

        XCTAssertEqual(exported.count, 2)
        XCTAssertEqual(exported[0].delay, 0.0) // First point has no delay
        XCTAssertGreaterThan(exported[1].delay, 0.05) // Second point has some delay
    }

    func testTotalDistance() {
        recorder.startRecording()

        // Record two points about 111m apart (roughly 0.001 degrees latitude)
        recorder.recordPoint(LocationCoordinate(latitude: 35.0, longitude: 139.0))
        recorder.recordPoint(LocationCoordinate(latitude: 35.001, longitude: 139.0))

        // Should be approximately 111 meters
        XCTAssertGreaterThan(recorder.totalDistance, 100)
        XCTAssertLessThan(recorder.totalDistance, 150)
    }
}

// MARK: - Recorded Waypoint Tests

final class RecordedWaypointTests: XCTestCase {

    func testWaypointInitialization() {
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let waypoint = RecordedWaypoint(coordinate: coord)

        XCTAssertEqual(waypoint.coordinate.latitude, 35.0)
        XCTAssertEqual(waypoint.coordinate.longitude, 139.0)
        XCTAssertNotNil(waypoint.id)
        XCTAssertNotNil(waypoint.timestamp)
    }

    func testWaypointsHaveUniqueIds() {
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let waypoint1 = RecordedWaypoint(coordinate: coord)
        let waypoint2 = RecordedWaypoint(coordinate: coord)

        XCTAssertNotEqual(waypoint1.id, waypoint2.id)
    }

    func testWaypointCodable() throws {
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let waypoint = RecordedWaypoint(coordinate: coord)

        let encoder = JSONEncoder()
        let data = try encoder.encode(waypoint)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RecordedWaypoint.self, from: data)

        XCTAssertEqual(waypoint.coordinate.latitude, decoded.coordinate.latitude)
        XCTAssertEqual(waypoint.coordinate.longitude, decoded.coordinate.longitude)
    }
}

// MARK: - Physics Route Simulation Tests

final class PhysicsRouteSimulationTests: XCTestCase {

    var simulation: PhysicsRouteSimulation!

    override func setUp() {
        super.setUp()
        simulation = PhysicsRouteSimulation(behavior: .walking)
    }

    func testInitialState() {
        XCTAssertFalse(simulation.isActive)
        XCTAssertNil(simulation.currentPosition)
        XCTAssertEqual(simulation.currentVelocity, 0)
        XCTAssertEqual(simulation.progress, 0)
    }

    func testConfigureWithWaypoints() {
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.001, longitude: 139.001)
        ]

        simulation.configure(waypoints: waypoints, behavior: .running)

        XCTAssertNotNil(simulation.currentPosition)
        XCTAssertEqual(simulation.currentPosition?.latitude, waypoints[0].latitude)
    }

    func testStartWithNoWaypoints() {
        simulation.start()

        // Should not start without waypoints
        XCTAssertFalse(simulation.isActive)
    }

    func testStartWithWaypoints() {
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.001, longitude: 139.001)
        ]

        simulation.configure(waypoints: waypoints, behavior: .walking)
        simulation.start()

        XCTAssertTrue(simulation.isActive)
    }

    func testStop() {
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.001, longitude: 139.001)
        ]

        simulation.configure(waypoints: waypoints, behavior: .walking)
        simulation.start()
        simulation.stop()

        XCTAssertFalse(simulation.isActive)
    }

    func testPauseAndResume() {
        let waypoints = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.001, longitude: 139.001)
        ]

        simulation.configure(waypoints: waypoints, behavior: .walking)
        simulation.start()

        simulation.pause()
        XCTAssertFalse(simulation.isActive)

        simulation.resume()
        XCTAssertTrue(simulation.isActive)

        simulation.stop() // Cleanup
    }

    func testLoopingSetting() {
        simulation.shouldLoop = true
        XCTAssertTrue(simulation.shouldLoop)

        simulation.shouldLoop = false
        XCTAssertFalse(simulation.shouldLoop)
    }
}
