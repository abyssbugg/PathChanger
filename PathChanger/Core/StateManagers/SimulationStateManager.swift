//
//  SimulationStateManager.swift
//  PathChanger
//
//  Domain-specific state manager for simulation-related state.
//  Part of AppState decomposition (ARCH-002).
//

import Foundation
import Combine
import SwiftUI

// MARK: - Simulation Mode

/// Available simulation modes
enum ActiveSimulationMode: String, CaseIterable {
    case none = "None"
    case teleport = "Teleport"
    case route = "Route"
    case joystick = "Joystick"
    
    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .teleport: return "location.fill"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .joystick: return "gamecontroller.fill"
        }
    }
}

// MARK: - Simulation State Manager

/// Manages simulation-related state including modes, playback, and joystick control.
///
/// `SimulationStateManager` is responsible for:
/// - Tracking active simulation mode
/// - Managing simulation start/stop/pause
/// - Controlling joystick input
/// - Tracking simulation statistics
///
/// ## Thread Safety
///
/// This class is marked `@MainActor` for safe SwiftUI integration.
/// All published properties update on the main thread.
///
/// ## Usage
///
/// ```swift
/// @StateObject private var simState = SimulationStateManager()
///
/// // Check simulation status
/// if simState.isSimulating {
///     print("Mode: \(simState.activeMode)")
/// }
///
/// // Start simulation
/// await simState.startSimulation()
/// ```
@MainActor
class SimulationStateManager: ObservableObject {
    
    // MARK: Published Properties
    
    /// Whether simulation is currently active
    @Published var isSimulating: Bool = false
    
    /// Whether simulation is paused
    @Published var isPaused: Bool = false
    
    /// Current simulation speed
    @Published var simulationSpeed: SimulationSpeed = .walking
    
    /// Active simulation mode
    @Published var activeMode: ActiveSimulationMode = .none
    
    /// Current location being simulated
    @Published var currentLocation: LocationCoordinate?
    
    /// Target location for teleport mode
    @Published var targetLocation: LocationCoordinate?
    
    /// Joystick direction vector (-1 to 1 on each axis)
    @Published var joystickDirection: CGPoint = .zero
    
    /// Joystick speed multiplier
    @Published var joystickSpeed: Double = 5.0
    
    /// Injection statistics
    @Published var injectionStats: InjectionStats = InjectionStats()
    
    /// Last error message
    @Published var lastError: String?
    
    /// Status message for UI
    @Published var statusMessage: String?
    
    // MARK: Dependencies
    
    private let locationBridge: DevLocationBridge
    private let errorHandler: ErrorHandler
    weak var deviceStateManager: DeviceStateManager?
    
    // MARK: Private Properties
    
    private var simulationTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: Computed Properties
    
    /// Whether simulation can be started
    var canStartSimulation: Bool {
        deviceStateManager?.isDeviceReady ?? false
    }
    
    /// Human-readable simulation status
    var statusText: String {
        guard let deviceState = deviceStateManager else {
            return "Initializing..."
        }
        
        if !deviceState.isTunneldRunning {
            return "Tunnel not running"
        }
        if deviceState.selectedDevice == nil {
            return "No device selected"
        }
        if isSimulating {
            return isPaused ? "Paused" : "Simulating..."
        }
        return "Ready"
    }
    
    // MARK: Initialization
    
    init(
        locationBridge: DevLocationBridge = DevLocationBridge(),
        errorHandler: ErrorHandler = ErrorHandler()
    ) {
        self.locationBridge = locationBridge
        self.errorHandler = errorHandler
        
        setupErrorHandling()
    }
    
    /// Set the device state manager reference
    func setDeviceStateManager(_ manager: DeviceStateManager) {
        self.deviceStateManager = manager
    }
    
    // MARK: Setup
    
    private func setupErrorHandling() {
        errorHandler.$currentError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.lastError = error.message
                if let suggestion = error.suggestion {
                    self?.lastError? += "\n\n\(suggestion)"
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: Location Control
    
    /// Set a specific location on the device
    func setLocation(_ coordinate: LocationCoordinate) async {
        guard let device = deviceStateManager?.selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device, action: .checkConnection)
            return
        }
        
        targetLocation = coordinate
        
        do {
            try await locationBridge.setLocation(coordinate, for: device)
            currentLocation = coordinate
            isSimulating = true
            lastError = nil
            injectionStats = await locationBridge.getStats()
            errorHandler.clearCurrentError()
        } catch let error as LocationInjectionError {
            errorHandler.handle(error, context: "Location injection")
            
            if case .deviceNotFound = error {
                deviceStateManager?.connectionLost()
            }
        } catch {
            errorHandler.handle(error, context: "Location injection")
        }
    }
    
    /// Clear the simulated location
    func clearLocation() async {
        guard let device = deviceStateManager?.selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device)
            return
        }
        
        do {
            try await locationBridge.clearLocation(for: device)
            currentLocation = nil
            targetLocation = nil
            isSimulating = false
            isPaused = false
            activeMode = .none
            lastError = nil
            statusMessage = "Location cleared"
            errorHandler.clearCurrentError()
        } catch {
            errorHandler.handle(error, context: "Clear location")
        }
    }
    
    // MARK: Simulation Control
    
    /// Start simulation with current target location
    func startSimulation() async {
        guard canStartSimulation else { return }
        
        guard let target = targetLocation else {
            lastError = "No target location selected"
            return
        }
        
        isPaused = false
        isSimulating = true
        activeMode = .teleport
        await setLocation(target)
    }
    
    /// Pause the current simulation
    func pauseSimulation() {
        isPaused = true
    }
    
    /// Resume a paused simulation
    func resumeSimulation() {
        isPaused = false
    }
    
    /// Stop and reset the simulation
    func stopSimulation() async {
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil
        joystickTask = nil
        
        isPaused = false
        isSimulating = false
        activeMode = .none
        joystickDirection = .zero
        
        await clearLocation()
    }
    
    // MARK: Joystick Control
    
    /// Update joystick direction
    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction
        
        if direction != .zero && activeMode != .joystick {
            activeMode = .joystick
        }
    }
    
    /// Start joystick mode
    func startJoystickMode() {
        guard canStartSimulation else { return }
        
        activeMode = .joystick
        isSimulating = true
        isPaused = false
        
        joystickTask = Task {
            while !Task.isCancelled && activeMode == .joystick {
                if !isPaused && joystickDirection != .zero {
                    await updateJoystickLocation()
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func updateJoystickLocation() async {
        guard let current = currentLocation else { return }
        
        // Normalize direction vector to ensure consistent speed in all directions
        let dirX = Double(joystickDirection.x)
        let dirY = Double(joystickDirection.y)
        let magnitude = sqrt(dirX * dirX + dirY * dirY)
        let normalizedX = magnitude > 0 ? dirX / max(magnitude, 1.0) : 0
        let normalizedY = magnitude > 0 ? dirY / max(magnitude, 1.0) : 0
        let speedFactor = min(magnitude, 1.0) // Allow partial speed for small movements
        
        // Calculate movement based on joystick direction and speed
        let metersPerUpdate = joystickSpeed * 0.1 * speedFactor // meters per 100ms
        let latOffset = normalizedY * metersPerUpdate / 111_000 // ~111km per degree
        let lonOffset = normalizedX * metersPerUpdate / (111_000 * cos(current.latitude * .pi / 180))
        
        if let newLocation = try? LocationCoordinate(
            latitude: current.latitude + latOffset,
            longitude: current.longitude + lonOffset
        ) {
            await setLocation(newLocation)
        }
    }
    
    // MARK: Speed Control
    
    /// Set simulation speed
    func setSpeed(_ speed: SimulationSpeed) {
        simulationSpeed = speed
    }
}
