//
//  AppState+Orchestration.swift
//  PathChanger
//

import SwiftUI
import Combine

@MainActor
extension AppState {
    func refreshDevices() async {
        await deviceManager.refreshDevices()

        // Deduplicate devices by UDID and ensure no duplicates in the list
        var seenUDIDs = Set<String>()
        var uniqueDevices: [Device] = []

        for device in deviceManager.devices {
            if !seenUDIDs.contains(device.id) {
                uniqueDevices.append(device)
                seenUDIDs.insert(device.id)
            }
        }
        syncConnectionAvailability(from: uniqueDevices)

        if availableDevices != uniqueDevices {
            availableDevices = uniqueDevices
        }

        if let selected = selectedDevice {
            if let updatedSelection = availableDevices.first(where: { $0.id == selected.id }) {
                if selected != updatedSelection {
                    selectedDevice = updatedSelection
                    simulationEngine.setDevice(updatedSelection)
                    TunneldManager.shared.setTargetDevice(updatedSelection)
                }
            } else if let first = availableDevices.first {
                selectedDevice = first
                simulationEngine.setDevice(first)
                TunneldManager.shared.setTargetDevice(first)
            } else {
                selectedDevice = nil
            }
        } else if let first = availableDevices.first {
            selectedDevice = first
            simulationEngine.setDevice(first)
            TunneldManager.shared.setTargetDevice(first)
        }

        connectionStatus = selectedDevice != nil ? .connected : .disconnected

        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }

    func checkTunneldStatus() async {
        // BUG FIX (WiFi-Bug-2): tunnel-running truth lives in TunneldManager,
        // not DeviceManager. The previous code routed through
        // `deviceManager.checkTunneldStatus()` which (before Bug-1B fix) didn't
        // know about the WiFi process pattern, and the result kept clobbering
        // the state-machine-derived value via the 5s timer.
        //
        // Now we ask TunneldManager itself two questions:
        //   1. Does its state machine think a tunnel is up? (`isRunning`)
        //   2. As a self-heal, does pgrep find any pmd3 tunnel process that the
        //      state machine missed? (`detectRunningTunnelMode()`)
        // The OR of those is the single tunnel-truth signal AppState publishes.
        let stateMachineRunning = TunneldManager.shared.isRunning
        let externallyDetectedMode = await TunneldManager.shared.detectRunningTunnelMode()
        let isRunning = stateMachineRunning || externallyDetectedMode != nil
        updateTunnelRunning(isRunning, force: true)

        if UserDefaults.standard.object(forKey: "autoStartTunneld") as? Bool == true,
           !isRunning && !TunneldManager.shared.isStarting {
            await TunneldManager.shared.autoStart()
            updateTunnelRunning(TunneldManager.shared.isRunning, force: true)
        }

        if isWiFiAvailable {
            usbFallbackManager.wirelessRestored()
        } else if !isTunneldRunning {
            usbFallbackManager.wirelessFailed()
        }
    }

    func selectDevice(_ device: Device) {
        if selectedDevice?.id != device.id {
            cancelTransientTransportRecovery(clearSnapshot: true)
        }
        selectedDevice = device
        simulationEngine.setDevice(device)
        TunneldManager.shared.setTargetDevice(device)
        connectionStatus = .connected
        reliabilityManager.connectionEstablished()
    }

    // MARK: - Spoof persistence across RSD rotation

    /// Pure decision: should a held Teleport spoof be re-applied because the
    /// active tunnel's RSD (address:port) rotated? Route/Joystick re-inject on
    /// every tick with the fresh RSD so they self-heal; only a static Teleport
    /// holds a session bound to one RSD and silently reverts when the daemon
    /// recreates its tunnel — so only Teleport needs an explicit re-apply.
    nonisolated static func shouldReapplyAfterRsdChange(
        isSimulating: Bool,
        isPaused: Bool,
        mode: SimulationModeType,
        hasCurrentLocation: Bool,
        previousRsdKey: String?,
        currentRsdKey: String?
    ) -> Bool {
        guard isSimulating, !isPaused, mode == .teleport, hasCurrentLocation else {
            return false
        }
        guard let currentRsdKey else { return false }
        return previousRsdKey != currentRsdKey
    }

    /// Current active RSD endpoint key ("address:port") for the selected device,
    /// or nil if none is usable right now.
    func currentActiveRsdKey() -> String? {
        guard let device = selectedDevice,
              let rsd = TunneldManager.shared.getRsdInfo(for: device.id) else {
            return nil
        }
        return "\(rsd.rsdAddress):\(rsd.rsdPort)"
    }

    /// Re-apply a held Teleport spoof when the daemon rotated the tunnel RSD so
    /// the device does not silently revert to its real location while the app
    /// still reports "connected".
    func reapplyTeleportIfRsdRotated() {
        let key = currentActiveRsdKey()
        guard AppState.shouldReapplyAfterRsdChange(
            isSimulating: isSimulating,
            isPaused: isPaused,
            mode: simulationEngine.currentMode,
            hasCurrentLocation: currentLocation != nil,
            previousRsdKey: lastAppliedRsdKey,
            currentRsdKey: key
        ), let coordinate = currentLocation else {
            return
        }

        Logger.info("[Tunnel] RSD rotated while Teleport active; re-applying spoof to persist location", category: .device)
        // Set immediately so repeated RSD emissions don't queue re-apply storms.
        lastAppliedRsdKey = key
        Task { [weak self] in
            await self?.setLocation(coordinate, source: "Teleport", recordHistory: false, showToast: false)
        }
    }

    // MARK: Location Control

    func setLocation(
        _ coordinate: LocationCoordinate,
        source: String = "Manual",
        name: String? = nil,
        recordHistory: Bool = true,
        showToast: Bool = true
    ) async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "Connect an iPhone to begin", type: .device, action: .checkConnection)
            ToastManager.shared.error("Connect an iPhone to begin")
            return
        }

        // Show newer-iOS compatibility warning once per device per session.
        if device.hasLocationCompatibilityWarning {
            let versionStr = device.iosVersion

            // Only show toast if we haven't shown it for this device yet
            if !simulation.shownIOSWarningDeviceIds.contains(device.id) {
                ToastManager.shared.warning(
                    "iOS \(versionStr) detected - attempting location simulation, but newer iOS may need pymobiledevice3 updates.",
                    duration: 5.0
                )
                simulation.shownIOSWarningDeviceIds.insert(device.id)
            }

            // Always log the attempt
            Logger.info(
                "Attempting location injection on newer iOS version with compatibility warning: \(versionStr)",
                category: .device,
                deviceUDID: device.id
            )
        }

        targetLocation = coordinate
        statusMessage = "Teleporting…"

        do {
            try await LocationBridge.shared.setLocation(coordinate, for: device)
            currentLocation = coordinate
            isSimulating = true
            lastError = nil
            // Record the RSD this spoof was applied over so a later daemon
            // tunnel rotation can be detected and the spoof re-applied.
            lastAppliedRsdKey = currentActiveRsdKey()
            captureResumableSessionSnapshot(mode: .teleport)
            injectionStats = await LocationBridge.shared.getStats()
            errorHandler.clearCurrentError()
            if recordHistory {
                locationHistoryStore.record(coordinate: coordinate, name: name ?? targetLocationName, source: source)
                locationHistory = locationHistoryStore.entries
            }

            // Show success toast
            let locationStr = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
            statusMessage = "Location set to \(locationStr)"
            if showToast {
                ToastManager.shared.success("Location set successfully")
            }

        } catch let error as LocationInjectionError {
            if LocationBridge.isTunnelInvalidationError(error),
               LocationBridge.isRecoverableTransportDisruption(error.localizedDescription) {
                beginTransientTransportRecovery(reason: error.localizedDescription)
            } else {
                errorHandler.handle(error, context: "Location injection")
                isSimulating = false
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }

            if case .deviceNotFound = error {
                reliabilityManager.connectionLost()
            }
        } catch {
            if LocationBridge.isTunnelInvalidationError(error),
               LocationBridge.isRecoverableTransportDisruption(error.localizedDescription) {
                beginTransientTransportRecovery(reason: error.localizedDescription)
            } else {
                errorHandler.handle(error, context: "Location injection")
                isSimulating = false
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }
        }
    }

    func clearLocation() async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "Connect an iPhone to begin", type: .device)
            return
        }
        cancelTransientTransportRecovery(clearSnapshot: true)

        do {
            try await LocationBridge.shared.clearLocation(for: device)
            currentLocation = nil
            targetLocation = nil
            targetLocationName = nil
            isSimulating = false
            isPaused = false
            lastError = nil
            statusMessage = "Location cleared"
            errorHandler.clearCurrentError()
        } catch {
            errorHandler.handle(error, context: "Clear location")
        }
    }

    // MARK: Simulation Control
    func canStartSimulation(for mode: AppMode) -> Bool {
        guard canStartSimulation else { return false }

        switch mode {
        case .teleport:
            return targetLocation != nil
        case .route:
            return currentRoute.count >= 2
        case .joystick:
            return currentLocation != nil || targetLocation != nil
        case .settings:
            return false
        }
    }

    func startSimulation() async {
        await startSimulation(mode: .teleport)
    }

    func startSimulation(mode: AppMode) async {
        await runSimulationTransition { [weak self] in
            guard let self = self else { return }
            await self.performStartSimulation(mode: mode)
        }
    }

    func performStartSimulation(mode: AppMode) async {
        guard canStartSimulation else { return }

        switch mode {
        case .teleport:
            guard let target = targetLocation else {
                lastError = "Pick a location"
                return
            }
            isPaused = false
            await setLocation(target, source: "Teleport", name: targetLocationName)
        case .route:
            await startRoutePlayback()
        case .joystick:
            await startJoystickControl()
        case .settings:
            return
        }
    }

    func pauseSimulation() {
        guard simulationTransitionTail == nil else { return }
        // Delegate to the simulation authority. The engine flips its state
        // machine to .paused which our mirror subscription propagates back
        // to AppState.isPaused.
        simulationEngine.pause()
        if simulationEngine.state == .paused {
            isPaused = true
        }
    }

    func resumeSimulation() {
        guard simulationTransitionTail == nil else { return }
        // Delegate to the simulation authority.
        simulationEngine.resume()
        if simulationEngine.state == .running {
            isPaused = false
        }
    }

    func stopSimulation() async {
        await runSimulationTransition { [weak self] in
            guard let self = self else { return }
            await self.performStopSimulation()
        }
    }

    func performStopSimulation() async {
        cancelTransientTransportRecovery(clearSnapshot: true)
        // Delegate to the simulation authority. The engine cancels its timer,
        // stops its mode, and clears the device location.
        await simulationEngine.stop()
        resetLocalSimulationStateAfterEngineStop()
    }

    func runSimulationTransition(_ operation: @escaping @MainActor () async -> Void) async {
        let previousTail = simulationTransitionTail
        simulationTransitionSerial &+= 1
        let serial = simulationTransitionSerial

        let transitionTask = Task { @MainActor in
            await previousTail?.value
            await operation()
        }
        simulationTransitionTail = transitionTask

        await transitionTask.value

        if simulationTransitionSerial == serial {
            simulationTransitionTail = nil
        }
    }

    func resetLocalSimulationStateAfterEngineStop() {
        cancelTransientTransportRecovery(clearSnapshot: true)
        currentLocation = nil
        targetLocation = nil
        targetLocationName = nil
        isPaused = false
        isSimulating = false
        routeProgress = 0
        joystickDirection = .zero
        lastError = nil
        statusMessage = "Location cleared"
        errorHandler.clearCurrentError()
    }

    // MARK: Route Playback

}
