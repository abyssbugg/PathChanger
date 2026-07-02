//
//  AppState+SimulationMirrors.swift
//  PathChanger
//

import SwiftUI
import Combine

@MainActor
extension AppState {
    func setupSimulationEngineMirrors() {
        simulationEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] engineState in
                guard let self = self else { return }
                switch engineState {
                case .running:
                    self.isSimulating = true
                    self.isPaused = false
                    self.captureResumableSessionSnapshot(mode: self.simulationEngine.currentMode)
                case .paused:
                    self.isSimulating = true
                    self.isPaused = true
                    self.captureResumableSessionSnapshot(mode: self.simulationEngine.currentMode)
                case .completed:
                    // Final-waypoint history recording: when a route finishes
                    // naturally, persist the last waypoint to history. Prior
                    // to Milestone 3 this was inlined in AppState’s route
                    // playback loop.
                    if self.simulationEngine.currentMode == .route,
                       let last = self.currentRoute.last {
                        self.locationHistoryStore.record(
                            coordinate: last,
                            name: "Route end",
                            source: "Route"
                        )
                        self.locationHistory = self.locationHistoryStore.entries
                        self.statusMessage = "Route playback complete"
                    }
                    self.isSimulating = false
                    self.isPaused = false
                case .idle:
                    self.isSimulating = false
                    self.isPaused = false
                case .error(let message):
                    if LocationBridge.isRecoverableTransportDisruption(message) {
                        self.beginTransientTransportRecovery(reason: message)
                    } else {
                        self.isSimulating = false
                        self.isPaused = false
                        self.lastError = message
                    }
                }
            }
            .store(in: &cancellables)

        simulationEngine.$currentCoordinate
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] coordinate in
                guard let self else { return }
                self.currentLocation = coordinate
                self.captureResumableSessionSnapshot(mode: self.simulationEngine.currentMode)
            }
            .store(in: &cancellables)

        simulationEngine.$routeProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                self.routeProgress = progress
                if self.simulationEngine.currentMode == .route {
                    self.captureResumableSessionSnapshot(mode: .route)
                }
            }
            .store(in: &cancellables)

        // Spoof persistence: when the background daemon recreates its tunnel
        // the per-device RSD rotates. A held Teleport session is bound to the
        // old RSD and would silently revert, so re-apply it on RSD change.
        TunneldManager.shared.$deviceTunnelInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reapplyTeleportIfRsdRotated()
            }
            .store(in: &cancellables)

        TunneldManager.shared.$tunnelInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reapplyTeleportIfRsdRotated()
            }
            .store(in: &cancellables)
    }

    // MARK: Manager Setup

    func setupReliabilityManager() {
        reliabilityManager.onReconnect = { [weak self] in
            guard let self = self else { return false }
            await self.refreshDevices()
            return self.selectedDevice != nil && self.isTunneldRunning
        }

        reliabilityManager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.connectionStatus = .disconnected
                self?.statusMessage = "Connection lost, attempting to reconnect..."
            }
        }

        reliabilityManager.onReconnectionFailed = { [weak self] reason in
            Task { @MainActor in
                self?.lastError = reason
                self?.connectionStatus = .error
            }
        }
    }

    func cancelTransientTransportRecovery(clearSnapshot: Bool) {
        transientRecoverySerial &+= 1
        transientRecoveryTask?.cancel()
        transientRecoveryTask = nil
        if clearSnapshot {
            resumableSessionSnapshot = nil
        }
    }

    func setupErrorHandler() {
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

    func setupUSBFallback() {
        usbFallbackManager.$isUSBConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.updateUSBConnected(connected)
            }
            .store(in: &cancellables)

        usbFallbackManager.$preferUSB
            .assign(to: &$preferUSBConnection)
    }

    // MARK: Device Management

}
