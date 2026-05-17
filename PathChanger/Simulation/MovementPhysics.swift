//
//  MovementPhysics.swift
//  PathChanger
//
//  Physics-based movement simulation for realistic location spoofing
//  Implements acceleration, deceleration, and behavioral patterns
//

import Foundation
import CoreLocation

// MARK: - Movement Behavior

/// Defines realistic movement patterns for different activities
enum MovementBehavior: String, CaseIterable, Identifiable {
    case walking
    case running
    case cycling
    case driving
    case publicTransit

    public var id: String { rawValue }

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        case .publicTransit: return "Public Transit"
        }
    }

    /// SF Symbol icon
    public var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .publicTransit: return "bus.fill"
        }
    }

    /// Physics configuration for this behavior
    public var physics: MovementPhysicsConfig {
        switch self {
        case .walking:
            return MovementPhysicsConfig(
                maxSpeed: 1.4,           // m/s (~5 km/h)
                acceleration: 0.5,        // m/s²
                deceleration: 0.8,        // m/s² (can stop quicker)
                jitter: 0.05,             // Small GPS noise
                turnSmoothness: 0.8,      // Smooth turns
                stopProbability: 0.01,    // Occasional pauses
                pauseDuration: 1.0...5.0  // Brief stops
            )
        case .running:
            return MovementPhysicsConfig(
                maxSpeed: 3.5,            // m/s (~12.6 km/h)
                acceleration: 1.5,
                deceleration: 2.0,
                jitter: 0.08,
                turnSmoothness: 0.6,
                stopProbability: 0.005,
                pauseDuration: 0.5...3.0
            )
        case .cycling:
            return MovementPhysicsConfig(
                maxSpeed: 6.0,            // m/s (~21.6 km/h)
                acceleration: 0.8,
                deceleration: 1.5,
                jitter: 0.03,
                turnSmoothness: 0.5,
                stopProbability: 0.02,    // Traffic lights
                pauseDuration: 3.0...15.0
            )
        case .driving:
            return MovementPhysicsConfig(
                maxSpeed: 16.7,           // m/s (~60 km/h city driving)
                acceleration: 2.5,
                deceleration: 4.0,
                jitter: 0.02,
                turnSmoothness: 0.3,
                stopProbability: 0.03,    // Traffic lights
                pauseDuration: 5.0...45.0
            )
        case .publicTransit:
            return MovementPhysicsConfig(
                maxSpeed: 13.9,           // m/s (~50 km/h)
                acceleration: 1.0,
                deceleration: 1.5,
                jitter: 0.01,
                turnSmoothness: 0.2,
                stopProbability: 0.08,    // Bus stops
                pauseDuration: 15.0...60.0
            )
        }
    }
}

// MARK: - Physics Configuration

/// Configuration for physics-based movement simulation
struct MovementPhysicsConfig {
    /// Maximum speed in meters per second
    public let maxSpeed: Double

    /// Acceleration rate in m/s²
    public let acceleration: Double

    /// Deceleration rate in m/s² (braking)
    public let deceleration: Double

    /// Random GPS jitter amount (0-1 scale, applied as meters)
    public let jitter: Double

    /// Turn smoothness (0 = sharp, 1 = very smooth)
    public let turnSmoothness: Double

    /// Probability of random stop per update (0-1)
    public let stopProbability: Double

    /// Duration range for random pauses (seconds)
    public let pauseDuration: ClosedRange<Double>

    public init(
        maxSpeed: Double,
        acceleration: Double,
        deceleration: Double,
        jitter: Double,
        turnSmoothness: Double,
        stopProbability: Double,
        pauseDuration: ClosedRange<Double>
    ) {
        self.maxSpeed = maxSpeed
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.jitter = jitter
        self.turnSmoothness = turnSmoothness
        self.stopProbability = stopProbability
        self.pauseDuration = pauseDuration
    }
}

// MARK: - Movement State

/// Current state of physics-based movement
struct MovementState {
    /// Current velocity in m/s
    public var velocity: Double = 0

    /// Current heading in degrees (0 = North)
    public var heading: Double = 0

    /// Target heading for smooth turning
    public var targetHeading: Double = 0

    /// Current position
    public var position: LocationCoordinate

    /// Whether currently in a pause state
    public var isPaused: Bool = false

    /// Time remaining in current pause (seconds)
    public var pauseRemaining: Double = 0

    /// Timestamp of last update
    public var lastUpdateTime: Date = Date()

    public init(position: LocationCoordinate) {
        self.position = position
    }
}

// MARK: - Movement Physics Engine

/// Physics engine for realistic movement simulation
class MovementPhysicsEngine {

    /// Current movement behavior
    public var behavior: MovementBehavior = .walking {
        didSet {
            physics = behavior.physics
        }
    }

    /// Current physics configuration
    private var physics: MovementPhysicsConfig

    /// Current movement state
    public private(set) var state: MovementState

    /// Target position for route following
    private var targetPosition: LocationCoordinate?

    /// Whether actively moving toward target
    public var isMoving: Bool = false

    /// Random number generator for jitter
    private var rng = SystemRandomNumberGenerator()

    // MARK: Initialization

    public init(startPosition: LocationCoordinate, behavior: MovementBehavior = .walking) {
        self.behavior = behavior
        self.physics = behavior.physics
        self.state = MovementState(position: startPosition)
    }

    // MARK: Target Management

    /// Set the next target position to move toward
    public func setTarget(_ target: LocationCoordinate) {
        targetPosition = target

        // Calculate heading to target
        let bearing = calculateBearing(from: state.position, to: target)
        state.targetHeading = bearing
    }

    /// Clear the current target
    public func clearTarget() {
        targetPosition = nil
    }

    // MARK: Physics Update

    /// Update the physics simulation
    /// - Parameter deltaTime: Time since last update in seconds
    /// - Returns: New position after physics update
    public func update(deltaTime: Double) -> LocationCoordinate {
        // Handle pause state
        if state.isPaused {
            state.pauseRemaining -= deltaTime
            if state.pauseRemaining <= 0 {
                state.isPaused = false
                state.pauseRemaining = 0
            }
            return state.position
        }

        // Random pause check
        if isMoving && Double.random(in: 0...1, using: &rng) < physics.stopProbability {
            state.isPaused = true
            state.pauseRemaining = Double.random(in: physics.pauseDuration, using: &rng)
            return state.position
        }

        guard isMoving, let target = targetPosition else {
            // Decelerate to stop
            if state.velocity > 0 {
                state.velocity = max(0, state.velocity - physics.deceleration * deltaTime)
            }
            return state.position
        }

        // Calculate distance to target
        let distanceToTarget = haversineDistance(from: state.position, to: target)

        // Stopping distance calculation (v² / 2a)
        let stoppingDistance = (state.velocity * state.velocity) / (2 * physics.deceleration)

        // Accelerate or decelerate based on distance
        if distanceToTarget > stoppingDistance * 1.5 {
            // Accelerate toward max speed
            state.velocity = min(physics.maxSpeed, state.velocity + physics.acceleration * deltaTime)
        } else if distanceToTarget < stoppingDistance {
            // Decelerate to stop at target
            state.velocity = max(0.1, state.velocity - physics.deceleration * deltaTime)
        }

        // Smooth heading transition
        let headingDiff = normalizeAngle(state.targetHeading - state.heading)
        let turnRate = (1.0 - physics.turnSmoothness) * 180.0 // degrees per second
        let maxTurn = turnRate * deltaTime
        let actualTurn = max(-maxTurn, min(maxTurn, headingDiff))
        state.heading = normalizeAngle(state.heading + actualTurn)

        // Calculate distance to move this update
        let moveDistance = state.velocity * deltaTime

        // Move position
        var newPosition = moveCoordinate(
            from: state.position,
            distanceMeters: moveDistance,
            bearingDegrees: state.heading
        )

        // Add GPS jitter
        newPosition = addJitter(to: newPosition, amount: physics.jitter)

        state.position = newPosition
        state.lastUpdateTime = Date()

        // Check if reached target
        if distanceToTarget < 2.0 {  // Within 2 meters
            state.velocity = 0
        }

        return newPosition
    }

    /// Force set the current velocity
    public func setVelocity(_ velocity: Double) {
        state.velocity = min(physics.maxSpeed, max(0, velocity))
    }

    /// Reset physics state
    public func reset(to position: LocationCoordinate) {
        state = MovementState(position: position)
        targetPosition = nil
        isMoving = false
    }

    // MARK: Helpers

    private func calculateBearing(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let yComponent = sin(dLon) * cos(lat2)
        let xComponent = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(yComponent, xComponent) * 180 / .pi
        return normalizeAngle(bearing)
    }

    private func haversineDistance(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let earthRadiusMeters = 6371000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180

        let haversineTerm = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let angularDistance = 2 * atan2(sqrt(haversineTerm), sqrt(1-haversineTerm))

        return earthRadiusMeters * angularDistance
    }

    private func moveCoordinate(from: LocationCoordinate, distanceMeters: Double, bearingDegrees: Double) -> LocationCoordinate {
        let earthRadiusMeters = 6371000.0
        let angularDistance = distanceMeters / earthRadiusMeters
        let bearing = bearingDegrees * .pi / 180

        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return LocationCoordinate(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    private func addJitter(to position: LocationCoordinate, amount: Double) -> LocationCoordinate {
        let jitterLat = Double.random(in: -amount...amount, using: &rng)
        let jitterLon = Double.random(in: -amount...amount, using: &rng)

        // Convert jitter to coordinate offset (rough approximation)
        let metersPerDegree = 111000.0

        return LocationCoordinate(
            latitude: position.latitude + (jitterLat / metersPerDegree),
            longitude: position.longitude + (jitterLon / (metersPerDegree * cos(position.latitude * .pi / 180)))
        )
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    #if DEBUG
    func testDisableRandomPausesAndJitter() {
        physics = MovementPhysicsConfig(
            maxSpeed: physics.maxSpeed,
            acceleration: physics.acceleration,
            deceleration: physics.deceleration,
            jitter: 0,
            turnSmoothness: physics.turnSmoothness,
            stopProbability: 0,
            pauseDuration: physics.pauseDuration
        )
        state.isPaused = false
        state.pauseRemaining = 0
    }
    #endif
}

// MARK: - Route Recording

/// Records GPS coordinates for route creation from real movement
class RouteRecorder: ObservableObject {

    /// Recorded waypoints
    @Published public private(set) var recordedPoints: [RecordedWaypoint] = []

    /// Whether currently recording
    @Published public private(set) var isRecording: Bool = false

    /// Total distance recorded in meters
    public var totalDistance: Double {
        guard recordedPoints.count > 1 else { return 0 }
        var distance = 0.0
        for recordedPointIndex in 1..<recordedPoints.count {
            distance += haversineDistance(
                from: recordedPoints[recordedPointIndex - 1].coordinate,
                to: recordedPoints[recordedPointIndex].coordinate
            )
        }
        return distance
    }

    /// Total duration of recording
    public var totalDuration: TimeInterval {
        guard let first = recordedPoints.first,
              let last = recordedPoints.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// Minimum distance between recorded points (meters)
    private let minimumDistance: Double = 5.0

    /// Last recorded point for distance calculation
    private var lastRecordedPoint: RecordedWaypoint?

    // MARK: Recording Control

    /// Start recording a new route
    public func startRecording() {
        recordedPoints.removeAll()
        lastRecordedPoint = nil
        isRecording = true
    }

    /// Stop recording
    public func stopRecording() {
        isRecording = false
    }

    /// Clear recorded points
    public func clearRecording() {
        recordedPoints.removeAll()
        lastRecordedPoint = nil
        isRecording = false
    }

    /// Add a coordinate to the recording
    /// - Parameter coordinate: The coordinate to record
    /// - Returns: Whether the point was added (may be filtered for distance)
    @discardableResult
    public func recordPoint(_ coordinate: LocationCoordinate) -> Bool {
        guard isRecording else { return false }

        // Check minimum distance from last point
        if let last = lastRecordedPoint {
            let distance = haversineDistance(from: last.coordinate, to: coordinate)
            if distance < minimumDistance {
                return false
            }
        }

        let waypoint = RecordedWaypoint(
            coordinate: coordinate,
            timestamp: Date()
        )

        recordedPoints.append(waypoint)
        lastRecordedPoint = waypoint

        return true
    }

    /// Export recorded points as simple coordinates
    public func exportAsCoordinates() -> [LocationCoordinate] {
        recordedPoints.map { $0.coordinate }
    }

    /// Export with timing information for realistic playback
    public func exportWithTiming() -> [(coordinate: LocationCoordinate, delay: TimeInterval)] {
        guard recordedPoints.count > 1 else {
            return recordedPoints.map { ($0.coordinate, 0.0) }
        }

        var result: [(LocationCoordinate, TimeInterval)] = []
        result.append((recordedPoints[0].coordinate, 0.0))

        for recordedPointIndex in 1..<recordedPoints.count {
            let delay = recordedPoints[recordedPointIndex].timestamp
                .timeIntervalSince(recordedPoints[recordedPointIndex - 1].timestamp)
            result.append((recordedPoints[recordedPointIndex].coordinate, delay))
        }

        return result
    }

    // MARK: Helpers

    private func haversineDistance(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let earthRadiusMeters = 6371000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180

        let haversineTerm = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let angularDistance = 2 * atan2(sqrt(haversineTerm), sqrt(1-haversineTerm))

        return earthRadiusMeters * angularDistance
    }
}

// MARK: - Recorded Waypoint

/// A waypoint recorded during route recording
struct RecordedWaypoint: Identifiable, Codable {
    public let id: UUID
    public let coordinate: LocationCoordinate
    public let timestamp: Date

    public init(coordinate: LocationCoordinate, timestamp: Date = Date()) {
        self.id = UUID()
        self.coordinate = coordinate
        self.timestamp = timestamp
    }
}

// MARK: - Enhanced Route Simulation

/// Enhanced route simulation with physics-based movement
class PhysicsRouteSimulation: ObservableObject {

    /// The physics engine for movement
    private let physicsEngine: MovementPhysicsEngine

    /// Route waypoints
    private var waypoints: [LocationCoordinate] = []

    /// Current waypoint index
    private var currentWaypointIndex: Int = 0

    /// Whether the simulation is active
    @Published public var isActive: Bool = false

    /// Current position
    @Published public var currentPosition: LocationCoordinate?

    /// Current velocity in m/s
    @Published public var currentVelocity: Double = 0

    /// Progress through route (0-1)
    @Published public var progress: Double = 0

    /// Whether to loop the route
    public var shouldLoop: Bool = false

    /// Update interval in seconds
    private let updateInterval: TimeInterval = 0.1

    /// Timer for updates
    private var timer: Timer?

    // MARK: Initialization

    public init(behavior: MovementBehavior = .walking) {
        self.physicsEngine = MovementPhysicsEngine(
            startPosition: LocationCoordinate(latitude: 0, longitude: 0),
            behavior: behavior
        )
    }

    // MARK: Configuration

    /// Configure the route to follow
    public func configure(waypoints: [LocationCoordinate], behavior: MovementBehavior) {
        self.waypoints = waypoints
        self.physicsEngine.behavior = behavior
        self.currentWaypointIndex = 0

        if let first = waypoints.first {
            physicsEngine.reset(to: first)
            currentPosition = first
        }
    }

    // MARK: Control

    /// Start the simulation
    public func start() {
        guard !waypoints.isEmpty else { return }

        isActive = true
        physicsEngine.isMoving = true

        if waypoints.count > 1 {
            physicsEngine.setTarget(waypoints[1])
            currentWaypointIndex = 0
        }

        startTimer()
    }

    /// Stop the simulation
    public func stop() {
        isActive = false
        physicsEngine.isMoving = false
        timer?.invalidate()
        timer = nil
    }

    /// Pause the simulation
    public func pause() {
        isActive = false
        physicsEngine.isMoving = false
        timer?.invalidate()
        timer = nil
    }

    /// Resume the simulation
    public func resume() {
        guard !waypoints.isEmpty else { return }
        isActive = true
        physicsEngine.isMoving = true
        startTimer()
    }

    // MARK: Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard isActive else { return }

        // Update physics
        let newPosition = physicsEngine.update(deltaTime: updateInterval)
        currentPosition = newPosition
        currentVelocity = physicsEngine.state.velocity

        // Check if reached current target
        if let target = getCurrentTarget() {
            let distance = distanceBetween(newPosition, target)

            if distance < 3.0 { // Within 3 meters
                advanceToNextWaypoint()
            }
        }

        // Update progress
        updateProgress()
    }

    private func getCurrentTarget() -> LocationCoordinate? {
        let targetIndex = currentWaypointIndex + 1
        guard targetIndex < waypoints.count else { return nil }
        return waypoints[targetIndex]
    }

    private func advanceToNextWaypoint() {
        currentWaypointIndex += 1

        if currentWaypointIndex >= waypoints.count - 1 {
            if shouldLoop {
                currentWaypointIndex = 0
                if let first = waypoints.first {
                    physicsEngine.setTarget(first)
                }
            } else {
                stop()
                progress = 1.0
            }
        } else {
            let nextTarget = waypoints[currentWaypointIndex + 1]
            physicsEngine.setTarget(nextTarget)
        }
    }

    private func updateProgress() {
        guard !waypoints.isEmpty else {
            progress = 0
            return
        }
        progress = Double(currentWaypointIndex) / Double(max(1, waypoints.count - 1))
    }

    private func distanceBetween(_ start: LocationCoordinate, _ end: LocationCoordinate) -> Double {
        let earthRadiusMeters = 6371000.0
        let dLat = (end.latitude - start.latitude) * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180

        let haversineTerm = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let angularDistance = 2 * atan2(sqrt(haversineTerm), sqrt(1-haversineTerm))

        return earthRadiusMeters * angularDistance
    }
}
