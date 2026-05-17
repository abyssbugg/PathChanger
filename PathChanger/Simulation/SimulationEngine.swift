//
//  SimulationEngine.swift
//  PathChanger
//
//  Core simulation engine for location playback with multiple modes
//

import Foundation
import Combine
import CoreLocation

// MARK: - Simulation Mode Protocol

/// A protocol that defines the interface for location simulation modes.
///
/// `SimulationModeProtocol` provides a common interface for different ways to simulate
/// location updates on an iOS device. The protocol supports both continuous simulation
/// (like route following or joystick control) and instantaneous simulation (teleportation).
///
/// ## Overview
///
/// Location simulation modes allow users to move their device's location in different ways:
/// - **Teleport Mode**: Instantly move to a specific coordinate
/// - **Route Mode**: Follow a predefined path with realistic movement
/// - **Joystick Mode**: Manual directional control with configurable speed
///
/// ## Implementing a Custom Mode
///
/// To implement a custom simulation mode, conform to this protocol and implement
/// all required properties and methods:
///
/// ```swift
/// class CustomMode: SimulationModeProtocol {
///     var isActive: Bool = false
///     var currentCoordinate: LocationCoordinate?
///
///     func start() {
///         isActive = true
///         // Initialize simulation
///     }
///
///     func stop() {
///         isActive = false
///         // Clean up resources
///     }
///
///     func pause() {
///         isActive = false
///     }
///
///     func resume() {
///         isActive = true
///     }
///
///     func update() -> LocationCoordinate? {
///         // Calculate and return next coordinate
///         return currentCoordinate
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### State
///
/// - ``isActive``
/// - ``currentCoordinate``
///
/// ### Lifecycle
///
/// - ``start()``
/// - ``stop()``
/// - ``pause()``
/// - ``resume()``
///
/// ### Updates
///
/// - ``update()``
protocol SimulationModeProtocol {
    var isActive: Bool { get }
    var currentCoordinate: LocationCoordinate? { get }
    func start()
    func stop()
    func pause()
    func resume()
    func update() -> LocationCoordinate?
}

// MARK: - Speed Presets

/// Speed presets for location simulation.
///
/// `SimulationSpeed` defines realistic movement speeds for simulating location changes.
/// Each preset includes the appropriate update interval for smooth, natural-looking movement.
///
/// ## Overview
///
/// Choose a speed that matches your testing scenario:
///
/// | Speed | Movement | Realistic Use Case |
/// |-------|----------|-------------------|
/// | Walking | 5 km/h | Pedestrian navigation |
/// | Running | 11 km/h | Fitness tracking |
/// | Cycling | 20 km/h | Bike navigation |
/// | Driving | 50 km/h | City driving |
/// | Fast | 100 km/h | Highway driving |
/// | Teleport | Instant | Quick location changes |
///
/// ## Example
///
/// ```swift
/// let engine = SimulationEngine()
/// engine.speed = .cycling
///
/// // Get speed information
/// print("Speed: \(engine.speed.metersPerSecond) m/s")
/// print("Updates every: \(engine.speed.updateInterval) seconds")
/// ```
enum SimulationSpeed: String, CaseIterable, Identifiable {
    case walking = "Walking"
    case running = "Running"
    case cycling = "Cycling"
    case driving = "Driving"
    case fast = "Fast"
    case teleport = "Instant"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Speed in meters per second
    var metersPerSecond: Double {
        switch self {
        case .walking: return 1.4      // ~5 km/h
        case .running: return 3.0      // ~11 km/h
        case .cycling: return 5.5      // ~20 km/h
        case .driving: return 13.9     // ~50 km/h
        case .fast: return 27.8        // ~100 km/h
        case .teleport: return 1000.0  // Instant
        }
    }

    /// Update interval in seconds
    var updateInterval: TimeInterval {
        switch self {
        case .walking, .running: return 1.0
        case .cycling: return 0.5
        case .driving: return 0.3
        case .fast: return 0.2
        case .teleport: return 0.1
        }
    }

    /// Icon for UI
    var icon: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .fast: return "car.2.fill"
        case .teleport: return "location.fill"
        }
    }
}

// MARK: - Simulation State

enum SimulationState: Equatable {
    case idle
    case running
    case paused
    case completed
    case error(String)

    var isActive: Bool {
        switch self {
        case .running, .paused:
            return true
        default:
            return false
        }
    }
}

// MARK: - Teleport Mode

/// Instant teleportation to a single location
class TeleportMode: SimulationModeProtocol {
    private(set) var isActive: Bool = false
    private(set) var currentCoordinate: LocationCoordinate?
    private var targetCoordinate: LocationCoordinate?

    func setTarget(_ coordinate: LocationCoordinate) {
        targetCoordinate = coordinate
    }

    func start() {
        isActive = true
        currentCoordinate = targetCoordinate
    }

    func stop() {
        isActive = false
        currentCoordinate = nil
    }

    func pause() {
        // Teleport doesn't pause - it's instant
    }

    func resume() {
        // Teleport doesn't resume
    }

    func update() -> LocationCoordinate? {
        return currentCoordinate
    }
}

// MARK: - Route Mode

/// Follow a predefined route with interpolated points
class RouteMode: SimulationModeProtocol {
    private(set) var isActive: Bool = false
    private(set) var currentCoordinate: LocationCoordinate?

    private var waypoints: [LocationCoordinate] = []
    private var interpolatedPoints: [LocationCoordinate] = []
    private var currentIndex: Int = 0
    private var speed: SimulationSpeed = .driving
    private var loop: Bool = false

    var progress: Double {
        guard !interpolatedPoints.isEmpty else { return 0 }
        return Double(currentIndex) / Double(interpolatedPoints.count)
    }

    var totalDistance: CLLocationDistance {
        guard waypoints.count > 1 else { return 0 }
        var distance: CLLocationDistance = 0
        for i in 1..<waypoints.count {
            distance += RouteInterpolator.haversineDistance(from: waypoints[i-1], to: waypoints[i])
        }
        return distance
    }

    var estimatedDuration: TimeInterval {
        totalDistance / speed.metersPerSecond
    }

    func configure(waypoints: [LocationCoordinate], speed: SimulationSpeed, loop: Bool = false) {
        self.waypoints = waypoints
        self.speed = speed
        self.loop = loop
        self.interpolatedPoints = RouteInterpolator.interpolateRoute(waypoints: waypoints, speed: speed)
        self.currentIndex = 0
    }

    func start() {
        guard !interpolatedPoints.isEmpty else { return }
        isActive = true
        currentIndex = 0
        currentCoordinate = interpolatedPoints.first
    }

    func stop() {
        isActive = false
        currentIndex = 0
        currentCoordinate = nil
    }

    func pause() {
        isActive = false
    }

    func resume() {
        isActive = true
    }

    func update() -> LocationCoordinate? {
        guard isActive, !interpolatedPoints.isEmpty else { return currentCoordinate }

        currentIndex += 1

        if currentIndex >= interpolatedPoints.count {
            if loop {
                currentIndex = 0
            } else {
                isActive = false
                return currentCoordinate
            }
        }

        currentCoordinate = interpolatedPoints[currentIndex]
        return currentCoordinate
    }
}

// MARK: - Joystick Mode

/// Manual control with directional input
class JoystickMode: SimulationModeProtocol {
    private(set) var isActive: Bool = false
    private(set) var currentCoordinate: LocationCoordinate?

    private var speed: SimulationSpeed = .walking
    private var direction: Double = 0  // Radians, 0 = North
    private var isMoving: Bool = false

    /// Direction in degrees (0 = North, 90 = East, etc.)
    var heading: Double {
        get { direction * 180 / .pi }
        set { direction = newValue * .pi / 180 }
    }

    func configure(startLocation: LocationCoordinate, speed: SimulationSpeed) {
        self.currentCoordinate = startLocation
        self.speed = speed
    }

    func setMoving(_ moving: Bool) {
        isMoving = moving
    }

    func setDirection(degrees: Double) {
        heading = degrees
    }

    func start() {
        isActive = true
    }

    func stop() {
        isActive = false
        isMoving = false
    }

    func pause() {
        isActive = false
    }

    func resume() {
        isActive = true
    }

    func update() -> LocationCoordinate? {
        guard isActive, isMoving, let current = currentCoordinate else {
            return currentCoordinate
        }

        // Calculate new position based on speed and direction
        let distancePerUpdate = speed.metersPerSecond * speed.updateInterval
        let newCoordinate = RouteInterpolator.moveCoordinate(
            from: current,
            distanceMeters: distancePerUpdate,
            bearingDegrees: heading
        )

        currentCoordinate = newCoordinate
        return newCoordinate
    }
}

// MARK: - Main Simulation Engine

/// The main simulation engine that coordinates location spoofing across multiple modes.
///
/// `SimulationEngine` is the central component for simulating location on iOS devices.
/// It manages three simulation modes and handles the communication with the device
/// through ``DevLocationBridge``.
///
/// ## Overview
///
/// The simulation engine provides:
/// - **Multi-mode support**: Teleport, Route, and Joystick modes
/// - **Speed control**: Multiple speed presets from walking to instant teleport
/// - **Device integration**: Automatic location injection to connected devices
/// - **State management**: Observable state for SwiftUI integration
///
/// ## Getting Started
///
/// ```swift
/// @StateObject private var engine = SimulationEngine()
///
/// // Set target device
/// engine.setDevice(connectedDevice)
///
/// // Teleport to a location
/// let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
/// try await engine.teleport(to: coordinate)
///
/// // Follow a route
/// let route = [
///     LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
///     LocationCoordinate(latitude: 35.6812, longitude: 139.7671)
/// ]
/// try await engine.startRoute(waypoints: route)
/// ```
///
/// ## Simulation Modes
///
/// ### Teleport Mode
///
/// Instantly moves the device location to a specific coordinate:
///
/// ```swift
/// try await engine.teleport(to: coordinate)
/// ```
///
/// ### Route Mode
///
/// Follows a predefined path with realistic movement:
///
/// ```swift
/// engine.loopRoute = true  // Optional: repeat the route
/// engine.speed = .cycling
/// try await engine.startRoute(waypoints: routeWaypoints)
/// ```
///
/// ### Joystick Mode
///
/// Manual directional control for real-time movement:
///
/// ```swift
/// engine.speed = .walking
/// try await engine.startJoystick(at: startLocation)
///
/// // Update direction based on user input
/// engine.setJoystickDirection(degrees: 45)  // Northeast
/// engine.setJoystickMoving(true)  // Start moving
/// ```
///
/// ## State Observation
///
/// The engine publishes state changes for UI updates:
///
/// ```swift
/// struct SimulationView: View {
///     @ObservedObject var engine: SimulationEngine
///
///     var body: some View {
///         VStack {
///             Text("Status: \(engine.state)")
///             Text("Mode: \(engine.currentMode)")
///
///             if engine.currentMode == .route {
///                 ProgressView(value: engine.routeProgress)
///             }
///         }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// `SimulationEngine` is marked `@MainActor` to ensure all state updates
/// happen on the main thread, making it safe for SwiftUI observation.
///
/// ## Topics
///
/// ### Published State
///
/// - ``state``
/// - ``currentMode``
/// - ``speed``
/// - ``currentCoordinate``
/// - ``routeProgress``
/// - ``elapsedTime``
/// - ``loopRoute``
///
/// ### Device Management
///
/// - ``setDevice(_:)``
///
/// ### Simulation Control
///
/// - ``teleport(to:)``
/// - ``startRoute(waypoints:)``
/// - ``startJoystick(at:)``
/// - ``pause()``
/// - ``resume()``
/// - ``stop()``
///
/// ### Joystick Control
///
/// - ``setJoystickDirection(degrees:)``
/// - ``setJoystickMoving(_:)``
@MainActor
class SimulationEngine: ObservableObject {
    // MARK: Published State
    @Published var state: SimulationState = .idle
    @Published var currentMode: SimulationModeType = .teleport
    @Published var speed: SimulationSpeed = .driving
    @Published var currentCoordinate: LocationCoordinate?
    @Published var routeProgress: Double = 0.0
    @Published var elapsedTime: TimeInterval = 0
    @Published var loopRoute: Bool = false

    // MARK: Mode Instances
    private let teleportMode = TeleportMode()
    private let routeMode = RouteMode()
    private let joystickMode = JoystickMode()

    // MARK: Timer
    private var timer: Timer?
    private var startTime: Date?
    private var simulationSessionID: UInt64 = 0
    private var activeTimerSessionID: UInt64?
    private var activeTickSessionID: UInt64?
    private var activeTickTask: Task<Void, Never>?

    // MARK: Device Bridge
    //
    // SimulationEngine routes all location injection through
    // `LocationBridge.shared` — the sole authoritative bridge after
    // Milestone 2. It no longer owns its own DevLocationBridge instance.
    private var targetDevice: Device?

    // MARK: Initialization
    init() {}

    // MARK: Device Management
    func setDevice(_ device: Device) {
        self.targetDevice = device
    }

    // MARK: Teleport
    func teleport(to coordinate: LocationCoordinate) async throws {
        let sessionID = await prepareForNewSimulationSession()
        guard isCurrentSession(sessionID) else { return }

        guard let device = targetDevice else {
            if isCurrentSession(sessionID) {
                state = .error("Connect an iPhone to begin")
            }
            throw LocationInjectionError.deviceNotFound
        }

        // Mode-dispatch consistency: set `currentMode` so any observer of
        // engine state (notably AppState’s mirrors after Milestone 3) sees
        // the correct active mode.
        currentMode = .teleport
        state = .running
        teleportMode.setTarget(coordinate)
        teleportMode.start()

        do {
            try await sendLocation(coordinate, for: device)
        } catch {
            if isCurrentSession(sessionID) {
                teleportMode.stop()
                state = .error(error.localizedDescription)
            }
            throw error
        }

        guard isCurrentSession(sessionID), state == .running else { return }
        currentCoordinate = coordinate
        state = .completed
    }

    // MARK: Route Simulation
    func startRoute(waypoints: [LocationCoordinate]) async {
        let sessionID = await prepareForNewSimulationSession()
        guard isCurrentSession(sessionID) else { return }

        guard targetDevice != nil else {
            if isCurrentSession(sessionID) {
                state = .error("Connect an iPhone to begin")
            }
            return
        }

        guard waypoints.count >= 2 else {
            if isCurrentSession(sessionID) {
                state = .error("Route requires at least 2 waypoints")
            }
            return
        }

        // Mode-dispatch consistency: tick() dispatches on currentMode, so it
        // must reflect the requested mode before the timer starts ticking.
        currentMode = .route
        routeMode.configure(waypoints: waypoints, speed: speed, loop: loopRoute)
        routeMode.start()

        state = .running
        startTime = Date()
        elapsedTime = 0
        routeProgress = 0

        startTimer(for: sessionID)
    }

    // MARK: Joystick Control
    func startJoystick(at location: LocationCoordinate) async {
        let sessionID = await prepareForNewSimulationSession()
        guard isCurrentSession(sessionID) else { return }

        guard targetDevice != nil else {
            if isCurrentSession(sessionID) {
                state = .error("Connect an iPhone to begin")
            }
            return
        }

        // Mode-dispatch consistency: tick() dispatches on currentMode.
        currentMode = .joystick
        joystickMode.configure(startLocation: location, speed: speed)
        joystickMode.start()

        state = .running
        startTime = Date()
        currentCoordinate = location

        startTimer(for: sessionID)
    }

    func setJoystickDirection(degrees: Double) {
        joystickMode.setDirection(degrees: degrees)
    }

    func setJoystickMoving(_ moving: Bool) {
        joystickMode.setMoving(moving)
    }

    /// Vector-direction joystick input.
    ///
    /// Accepts a 2D direction vector (x = east component, y = north component;
    /// units are joystick-stick fraction, magnitude clamped to [0, 1]).
    /// Internally converts to a compass bearing for the bearing-based
    /// `JoystickMode`. `isMoving` is enabled when the magnitude exceeds the
    /// dead-zone threshold (matches the prior AppState semantics).
    ///
    /// Added in Milestone 3 to become the **sole** entry point for joystick
    /// input. AppState now forwards user input here instead of running its
    /// own joystick motion loop.
    func updateJoystickDirection(_ direction: CGPoint) {
        let magnitude = sqrt(direction.x * direction.x + direction.y * direction.y)
        // Dead-zone threshold preserved from AppState.startJoystickControl.
        let deadZone: CGFloat = 0.05
        if magnitude > deadZone {
            // atan2(x, y) returns 0 for due-north (positive y) and increases
            // clockwise toward east — i.e. compass bearing.
            let bearing = atan2(direction.x, direction.y) * 180 / .pi
            joystickMode.setDirection(degrees: Double(bearing))
            joystickMode.setMoving(true)
        } else {
            joystickMode.setMoving(false)
        }
    }

    // MARK: Control
    func pause() {
        guard state == .running else { return }

        invalidateTimer()
        activeTickTask?.cancel()
        state = .paused

        switch currentMode {
        case .route:
            routeMode.pause()
        case .joystick:
            joystickMode.pause()
        case .teleport:
            break
        }
    }

    func resume() {
        guard state == .paused else { return }

        state = .running

        switch currentMode {
        case .route:
            routeMode.resume()
        case .joystick:
            joystickMode.resume()
        case .teleport:
            break
        }

        startTimer(for: simulationSessionID)
    }

    func stop() async {
        let (sessionID, previousTickTask) = invalidateCurrentSimulationSession()
        stopModes()

        await previousTickTask?.value
        guard isCurrentSession(sessionID) else { return }

        // Clear location on device after any older tick has drained. This
        // preserves device clear ordering without moving bridge ownership out
        // of the engine.
        if let device = targetDevice {
            try? await LocationBridge.shared.clearLocation(for: device)
        }

        guard isCurrentSession(sessionID) else { return }
        state = .idle
        currentCoordinate = nil
        routeProgress = 0
        elapsedTime = 0
    }

    // MARK: Timer
    private func startTimer(for sessionID: UInt64) {
        invalidateTimer()
        activeTimerSessionID = sessionID
        timer = Timer.scheduledTimer(withTimeInterval: speed.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isCurrentSession(sessionID), self.state == .running else { return }
                guard self.activeTickTask == nil else { return }

                self.activeTickSessionID = sessionID
                let tickTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.tick(sessionID: sessionID)
                }
                self.activeTickTask = tickTask
            }
        }
    }

    private func tick(sessionID: UInt64) async {
        guard isCurrentSession(sessionID), state == .running, !Task.isCancelled else {
            clearActiveTickIfCurrent(sessionID: sessionID)
            return
        }

        defer {
            clearActiveTickIfCurrent(sessionID: sessionID)
        }

        // Update elapsed time
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }

        // Get next coordinate based on mode
        var nextCoordinate: LocationCoordinate?

        switch currentMode {
        case .teleport:
            nextCoordinate = teleportMode.update()
        case .route:
            nextCoordinate = routeMode.update()
            routeProgress = routeMode.progress

            if !routeMode.isActive {
                guard isCurrentSession(sessionID), state == .running, !Task.isCancelled else { return }
                state = .completed
                invalidateTimer()
                return
            }
        case .joystick:
            nextCoordinate = joystickMode.update()
        }

        // Send to device
        if let coordinate = nextCoordinate, let device = targetDevice {
            guard isCurrentSession(sessionID), state == .running, !Task.isCancelled else { return }
            do {
                try await sendLocation(coordinate, for: device)
            } catch {
                guard isCurrentSession(sessionID), state == .running, !Task.isCancelled else { return }
                if LocationBridge.isTunnelInvalidationError(error) {
                    failActiveSimulationAfterTransportFailure(error, sessionID: sessionID)
                } else {
                    Logger.error("Location tick failed: \(error.localizedDescription)", category: .device)
                }
                return
            }
            guard isCurrentSession(sessionID), state == .running, !Task.isCancelled else { return }
            currentCoordinate = coordinate
        }
    }

    // MARK: Session Coordination

    private func prepareForNewSimulationSession() async -> UInt64 {
        let (sessionID, previousTickTask) = invalidateCurrentSimulationSession()
        stopModes()
        await previousTickTask?.value
        return sessionID
    }

    private func invalidateCurrentSimulationSession() -> (UInt64, Task<Void, Never>?) {
        invalidateTimer()
        simulationSessionID &+= 1
        let previousTickTask = activeTickTask
        previousTickTask?.cancel()
        return (simulationSessionID, previousTickTask)
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
        activeTimerSessionID = nil
    }

    private func stopModes() {
        teleportMode.stop()
        routeMode.stop()
        joystickMode.stop()
    }

    private func isCurrentSession(_ sessionID: UInt64) -> Bool {
        simulationSessionID == sessionID
    }

    private func clearActiveTickIfCurrent(sessionID: UInt64) {
        guard activeTickSessionID == sessionID else { return }
        activeTickSessionID = nil
        activeTickTask = nil
    }

    private func sendLocation(_ coordinate: LocationCoordinate, for device: Device) async throws {
        #if DEBUG
        if let testSetLocationHandler {
            try await testSetLocationHandler(coordinate, device)
            return
        }
        #endif
        try await LocationBridge.shared.setLocation(coordinate, for: device)
    }

    private func failActiveSimulationAfterTransportFailure(_ error: Error, sessionID: UInt64) {
        guard isCurrentSession(sessionID) else { return }
        invalidateTimer()
        activeTickTask?.cancel()
        stopModes()
        state = .error(error.localizedDescription)
    }

    #if DEBUG
    var testSetLocationHandler: ((LocationCoordinate, Device) async throws -> Void)?
    var testSimulationSessionID: UInt64 {
        simulationSessionID
    }

    var testHasActiveTimer: Bool {
        timer != nil
    }

    var testHasActiveTick: Bool {
        activeTickTask != nil
    }

    func testRunTick(sessionID: UInt64) async {
        await tick(sessionID: sessionID)
    }
    #endif

}
