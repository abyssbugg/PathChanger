//
//  SimulationStateManager.swift
//  PathChanger
//
//  Owns simulation delivery policy: exact coordinates, turn smoothing, and speed selection.
//  Part of the AppState decomposition (ARCH-002).
//
//  This replaces an earlier unwired version that could not represent the app's behaviour.
//  That version modelled modes with a four-case `ActiveSimulationMode` (none/teleport/
//  route/joystick), which has no way to express Jump or Two-spot, and its
//  `startSimulation()` teleported to `targetLocation` directly instead of going through
//  `SimulationPlanner`. It also had no turn smoothing, performance mode or queue-strategy
//  switching. `AppMode` is now the single mode type and `ActiveSimulationMode` was removed.
//
//  Playback loops deliberately do not live here. AppState still owns `playRoute` and
//  `startJoystick` until the simulation engine takes them over, so that exactly one
//  playback implementation exists at any time.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SimulationStateManager: ObservableObject {

    // MARK: Published State

    @Published var isSimulating: Bool = false
    @Published var isPaused: Bool = false
    @Published var simulationSpeed: SimulationSpeed = .walking
    @Published var activeMode: AppMode = .teleport

    @Published var currentLocation: LocationCoordinate?
    @Published var targetLocation: LocationCoordinate?

    // MARK: Movement Tuning

    @Published var autoSpeed: Bool = true
    @Published var customSpeedMps: Double = 1.6
    @Published var updateFrequencyHz: Double = 5
    @Published var smoothTurns: Bool = true

    // MARK: Joystick

    @Published var joystickDirection: CGPoint = .zero
    @Published var joystickSpeed: Double = 5.0

    // MARK: Statistics

    @Published var injectionStats: InjectionStats = InjectionStats()

    // MARK: Dependencies

    let locationBridge: DevLocationBridge
    private let errorHandler: ErrorHandler
    weak var deviceStateManager: DeviceStateManager?

    /// Reports user-facing status text. Owned by the composition root so that route,
    /// device and simulation messages all land in one place.
    var onStatusMessage: ((String?) -> Void)?

    // MARK: Private

    private var lastTeleportAt: Date?
    private var smoothedJoystickHeading: Double?

    // MARK: Computed

    var canStartSimulation: Bool {
        deviceStateManager?.isDeviceReady ?? false
    }

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

    /// Speed actually applied to movement: the preset when auto, otherwise the custom value.
    var effectiveMetersPerSecond: Double {
        autoSpeed ? simulationSpeed.presetMetersPerSecond : customSpeedMps
    }

    func coordinateForApplication(_ coordinate: LocationCoordinate) -> LocationCoordinate {
        coordinate
    }

    // MARK: Initialization

    // Dependencies are resolved inside the body: default arguments are evaluated in the
    // caller's context, which is nonisolated, and these types are main-actor isolated.
    init(
        locationBridge: DevLocationBridge? = nil,
        errorHandler: ErrorHandler? = nil
    ) {
        self.locationBridge = locationBridge ?? DevLocationBridge()
        self.errorHandler = errorHandler ?? ErrorHandler()
    }

    func setDeviceStateManager(_ manager: DeviceStateManager) {
        self.deviceStateManager = manager
    }

    // MARK: Location Control

    /// Apply a coordinate to the selected device.
    ///
    /// - Parameters:
    ///   - quiet: suppresses user-facing toasts and status text for continuous movement.
    ///   - usePerformanceMode: routes through the persistent Python bridge.
    func setLocation(
        _ coordinate: LocationCoordinate,
        quiet: Bool = false,
        usePerformanceMode: Bool = false
    ) async {
        guard let targetDevice = deviceStateManager?.selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device, action: .checkConnection)
            if !quiet {
                ToastManager.shared.error("No device selected")
            }
            return
        }

        let applicationCoordinate = coordinateForApplication(coordinate)
        targetLocation = applicationCoordinate
        if !quiet {
            onStatusMessage?("Injecting location...")
        }

        do {
            try await locationBridge.setLocation(
                applicationCoordinate,
                for: targetDevice,
                priority: quiet ? .high : .normal,
                usePerformanceMode: usePerformanceMode
            )
            currentLocation = applicationCoordinate
            isSimulating = true
            injectionStats = await locationBridge.getStats()
            errorHandler.clearCurrentError()

            if !quiet {
                let locationStr = String(
                    format: "%.4f, %.4f",
                    applicationCoordinate.latitude,
                    applicationCoordinate.longitude
                )
                onStatusMessage?("Location spoofed to \(locationStr)")
                ToastManager.shared.success("Location spoofed successfully!")
            }
        } catch let error as LocationInjectionError {
            if case .rateLimited = error {
                if currentLocation == nil {
                    isSimulating = false
                }
                onStatusMessage?("Location update rejected by adapter backpressure")
                if !quiet {
                    ToastManager.shared.warning("Location update was not applied")
                }
                return
            }
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            if !quiet {
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }

            if case .deviceNotFound = error {
                deviceStateManager?.connectionLost()
            }
        } catch {
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            if !quiet {
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }
        }
    }

    /// Clear the simulated location on the selected device.
    func clearLocation() async {
        guard let targetDevice = deviceStateManager?.selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device)
            return
        }

        do {
            try await locationBridge.clearLocation(for: targetDevice)
            currentLocation = nil
            targetLocation = nil
            isSimulating = false
            isPaused = false
            onStatusMessage?("Location cleared")
            errorHandler.clearCurrentError()
        } catch {
            errorHandler.handle(error, context: "Clear location")
        }
    }

    /// Release the held DVT session without clearing state.
    func stopHeldSimulation() async {
        await locationBridge.stopHeldSimulation()
    }

    /// Choose how queued updates are drained.
    func setQueueStrategy(_ strategy: QueueProcessingStrategy) async {
        await locationBridge.setQueueStrategy(strategy)
    }

    // MARK: Playback Flags

    func pauseSimulation() {
        isPaused = true
    }

    func resumeSimulation() {
        isPaused = false
    }

    // MARK: Joystick

    /// Store the current stick vector. Deciding whether that should start a simulation is
    /// the composition root's job, because it needs the planner.
    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction
    }

    func resetJoystick() {
        joystickDirection = .zero
        smoothedJoystickHeading = nil
    }

    /// Blend a raw stick vector toward the previous heading to soften turns.
    func smoothedDirection(_ raw: CGPoint) -> CGPoint {
        let magnitude = hypot(raw.x, raw.y)
        guard magnitude > 0.05 else {
            smoothedJoystickHeading = nil
            return raw
        }
        let heading = atan2(raw.x, raw.y)
        if let previous = smoothedJoystickHeading {
            var delta = heading - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            let blended = previous + delta * 0.35
            smoothedJoystickHeading = blended
            return CGPoint(x: sin(blended) * magnitude, y: cos(blended) * magnitude)
        }
        smoothedJoystickHeading = heading
        return raw
    }

    func setSpeed(_ speed: SimulationSpeed) {
        simulationSpeed = speed
        if autoSpeed {
            customSpeedMps = speed.presetMetersPerSecond
        }
    }
}
