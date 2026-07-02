//
//  AppState+RecoveryAndHistory.swift
//  PathChanger
//

import SwiftUI
import Combine

@MainActor
extension AppState {
    func loadRoute(from coordinates: [LocationCoordinate]) {
        currentRoute = coordinates
        routeProgress = 0
        targetLocation = coordinates.first
        targetLocationName = coordinates.isEmpty ? nil : "Route start"
    }

    func addRoutePoint(_ coordinate: LocationCoordinate? = nil) {
        guard let point = coordinate ?? targetLocation, point.isValid else {
            lastError = "Select a valid location before adding a waypoint"
            return
        }

        currentRoute.append(point)
        routeProgress = 0
        targetLocation = point
        targetLocationName = "Waypoint \(currentRoute.count)"
        statusMessage = "Added waypoint \(currentRoute.count)"
    }

    func removeRoutePoint(at index: Int) {
        guard currentRoute.indices.contains(index) else { return }
        currentRoute.remove(at: index)
        routeProgress = 0
    }

    func moveRoutePoint(from sourceIndex: Int, to destinationIndex: Int) {
        guard currentRoute.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex < currentRoute.count,
              sourceIndex != destinationIndex else {
            return
        }

        let point = currentRoute.remove(at: sourceIndex)
        currentRoute.insert(point, at: destinationIndex)
        routeProgress = 0
    }

    func clearRoute() {
        currentRoute.removeAll()
        routeProgress = 0
        statusMessage = "Route cleared"
    }

    func startRoutePlayback() async {
        guard canStartSimulation else { return }

        guard currentRoute.count >= 2 else {
            lastError = "Add at least two route points"
            return
        }

        // Fire the iOS-18-compatibility warning toast once for the active
        // device, preserving the per-session de-duplication behavior that
        // used to live inside AppState.setLocation’s per-tick path.
        if let device = selectedDevice {
            warnIfNewerIOSDeviceOnce(device: device)
        }

        // Record the start-of-route waypoint in history before handing off to
        // the engine. Previously this was done inside the per-tick loop with
        // `recordHistory: index == 0`. The end-of-route waypoint is recorded
        // by `setupSimulationEngineMirrors` when engine.state transitions to
        // .completed.
        if let first = currentRoute.first {
            locationHistoryStore.record(
                coordinate: first,
                name: "Route start",
                source: "Route"
            )
            locationHistory = locationHistoryStore.entries
        }

        // Hand off motion progression to the simulation authority. The engine
        // owns the per-tick timer, RouteInterpolator integration, and
        // LocationBridge calls from here on. AppState only observes.
        isPaused = false
        isSimulating = true
        routeProgress = 0
        simulationEngine.speed = simulationSpeed
        await simulationEngine.startRoute(waypoints: currentRoute)
        captureResumableSessionSnapshot(mode: .route)
    }

    // MARK: Joystick Mode

    /// Update the user-facing joystick direction binding and forward the
    /// vector to the simulation authority.
    ///
    /// `joystickDirection` remains the SwiftUI-bindable source of truth for
    /// the joystick control view. The simulation engine consumes the vector
    /// at its boundary (converting to a compass bearing internally).
    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction
        simulationEngine.updateJoystickDirection(direction)
    }

    func startJoystickControl() async {
        guard canStartSimulation else { return }

        guard let start = currentLocation ?? targetLocation else {
            lastError = "Pick a starting location"
            return
        }

        // Fire the iOS-18-compatibility warning toast once for the active
        // device (per-session de-duplication preserved from the per-tick path).
        if let device = selectedDevice {
            warnIfNewerIOSDeviceOnce(device: device)
        }

        // Persist the starting position to history once. Before Milestone 3
        // this was the first invocation of the per-tick setLocation loop.
        locationHistoryStore.record(
            coordinate: start,
            name: targetLocationName ?? "Joystick start",
            source: "Joystick"
        )
        locationHistory = locationHistoryStore.entries

        // Hand off motion progression to the simulation authority. The engine
        // owns the per-tick joystick loop and LocationBridge calls.
        targetLocation = start
        isPaused = false
        isSimulating = true
        simulationEngine.speed = simulationSpeed
        simulationEngine.updateJoystickDirection(joystickDirection)
        await simulationEngine.startJoystick(at: start)
        captureResumableSessionSnapshot(mode: .joystick)
    }

    func captureResumableSessionSnapshot(mode: SimulationModeType) {
        guard let device = selectedDevice else {
            resumableSessionSnapshot = nil
            return
        }

        let coordinate = currentLocation ?? targetLocation
        guard coordinate != nil || mode == .route else {
            resumableSessionSnapshot = nil
            return
        }

        if mode == .route, currentRoute.count < 2 {
            return
        }

        resumableSessionSnapshot = ResumableSessionSnapshot(
            device: device,
            mode: mode,
            coordinate: coordinate,
            targetLocation: targetLocation,
            targetLocationName: targetLocationName,
            routeWaypoints: currentRoute,
            routeProgress: routeProgress,
            joystickDirection: joystickDirection,
            wasPaused: isPaused || simulationEngine.state == .paused,
            wasSimulating: isSimulating || simulationEngine.state.isActive,
            speed: simulationSpeed
        )
    }

    func beginTransientTransportRecovery(reason: String) {
        guard transientRecoveryTask == nil else {
            return
        }
        guard let snapshot = resumableSessionSnapshot,
              selectedDevice?.id == snapshot.device.id else {
            lastError = reason
            isSimulating = false
            isPaused = false
            return
        }

        transientRecoverySerial &+= 1
        let serial = transientRecoverySerial
        isSimulating = snapshot.wasSimulating
        isPaused = snapshot.wasPaused
        lastError = nil
        statusMessage = "Recovering tunnel connection…"

        transientRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let recovered = await self.recoverTunnelForTransientFailure(reason: reason)
            guard self.transientRecoverySerial == serial else { return }
            if recovered {
#if DEBUG
                if !self.debugSkipDeviceRefreshDuringTransientRecovery {
                    await self.refreshDevices()
                }
#else
                await self.refreshDevices()
#endif
            }
            guard self.transientRecoverySerial == serial else { return }

            if recovered,
               self.selectedDevice?.id == snapshot.device.id {
                await self.restoreResumableSession(snapshot)
            } else {
                self.isSimulating = false
                self.isPaused = false
                self.lastError = reason
                self.statusMessage = "Tunnel recovery failed"
            }

            if self.transientRecoverySerial == serial {
                self.transientRecoveryTask = nil
            }
        }
    }

    func recoverTunnelForTransientFailure(reason: String) async -> Bool {
#if DEBUG
        if let debugTransientRecoveryHandler {
            return await debugTransientRecoveryHandler(reason)
        }
#endif
        return await TunneldManager.shared.recoverFromTransientTransportFailure(reason: reason)
    }

    func restoreResumableSession(_ snapshot: ResumableSessionSnapshot) async {
        guard selectedDevice?.id == snapshot.device.id else {
            lastError = "Recovered tunnel, but the selected device changed before session restoration."
            isSimulating = false
            isPaused = false
            return
        }

        simulationSpeed = snapshot.speed
        simulationEngine.speed = snapshot.speed
        targetLocation = snapshot.targetLocation
        targetLocationName = snapshot.targetLocationName
        currentRoute = snapshot.routeWaypoints
        joystickDirection = snapshot.joystickDirection

        switch snapshot.mode {
        case .teleport:
            guard let coordinate = snapshot.coordinate else {
                isSimulating = false
                isPaused = false
                return
            }
            do {
                try await LocationBridge.shared.setLocation(coordinate, for: snapshot.device)
                currentLocation = coordinate
                targetLocation = coordinate
                isSimulating = true
                isPaused = false
                lastError = nil
                statusMessage = "Location restored after tunnel recovery"
                captureResumableSessionSnapshot(mode: .teleport)
            } catch {
                isSimulating = false
                isPaused = false
                lastError = error.localizedDescription
                statusMessage = "Tunnel recovered, but location restoration failed"
            }
        case .route, .joystick:
            simulationEngine.restoreSessionAfterTransportRecovery(
                mode: snapshot.mode,
                coordinate: snapshot.coordinate,
                routeWaypoints: snapshot.routeWaypoints,
                routeProgress: snapshot.routeProgress,
                joystickDirection: snapshot.joystickDirection,
                wasPaused: snapshot.wasPaused
            )
            isSimulating = true
            isPaused = snapshot.wasPaused
            lastError = nil
            statusMessage = snapshot.wasPaused
                ? "Session restored after tunnel recovery (paused)"
                : "Session resumed after tunnel recovery"
            captureResumableSessionSnapshot(mode: snapshot.mode)
        }
    }

    /// Show the iOS-18+ compatibility warning toast at most once per device
    /// per session.
    ///
    /// Extracted in Milestone 3 from the prior per-tick `setLocation` path
    /// so it can fire exactly once at simulation start instead of every tick.
    func warnIfNewerIOSDeviceOnce(device: Device) {
        guard device.hasLocationCompatibilityWarning else { return }
        let versionStr = device.iosVersion

        if !simulation.shownIOSWarningDeviceIds.contains(device.id) {
            ToastManager.shared.warning(
                "iOS \(versionStr) detected - attempting location simulation, but newer iOS may need pymobiledevice3 updates.",
                duration: 5.0
            )
            simulation.shownIOSWarningDeviceIds.insert(device.id)
        }

        Logger.info(
            "Attempting location injection on newer iOS version with compatibility warning: \(versionStr)",
            category: .device,
            deviceUDID: device.id
        )
    }

    // MARK: Location History

    func selectHistoryEntry(_ entry: LocationHistoryEntry) {
        targetLocation = entry.coordinate
        targetLocationName = entry.displayName
        statusMessage = "Selected recent location: \(entry.displayName)"
    }

    func removeHistoryEntry(_ entry: LocationHistoryEntry) {
        locationHistoryStore.remove(entry)
        locationHistory = locationHistoryStore.entries
    }

    func clearLocationHistory() {
        locationHistoryStore.clear()
        locationHistory = locationHistoryStore.entries
    }

    // MARK: Speed Control

    func setSpeed(_ speed: SimulationSpeed) {
        simulationSpeed = speed
    }
}

