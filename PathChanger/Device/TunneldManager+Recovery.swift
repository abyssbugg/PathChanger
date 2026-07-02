//
//  TunneldManager+Recovery.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func scheduleRecovery(after delay: TimeInterval) {
        recoveryTask?.cancel()
        guard stateMachine.currentContext.isRecovering,
              case .error = stateMachine.currentState else {
            recoveryTask = nil
            return
        }
        let generation = tunnelLifecycleGeneration

        recoveryTask = Task { [weak self] in
            guard let self else { return }
            let clampedDelay = max(0, delay)
            try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
            guard !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(generation),
                  self.stateMachine.currentContext.isRecovering else {
                return
            }
            guard case .error = self.stateMachine.currentState else {
                return
            }
            self.stateMachine.send(.recoveryAttempted)
        }
    }

    func launchRecoveryTunnel(mode: TunnelMode) async {
        guard !tunnelStartInFlight else {
            Logger.debug("[Tunnel] Recovery launch ignored because another start is already in flight", category: .device)
            return
        }
        guard case .starting = stateMachine.currentState else {
            Logger.debug("[Tunnel] Recovery launch ignored because state is no longer starting", category: .device)
            return
        }

        let generation = tunnelLifecycleGeneration
        tunnelStartInFlight = true
        defer {
            tunnelStartInFlight = false
        }

        let success = await attemptStart(mode: mode)
        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            if success {
                killTrackedTunnelProcesses()
            }
            return
        }

        if success, let info = await waitForValidRsdInfo(mode: mode) {
            guard isCurrentTunnelLifecycle(generation),
                  case .starting = stateMachine.currentState else {
                return
            }
            stateMachine.send(.connectionEstablished(info: info))
            return
        }

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            return
        }

        if success {
            killTrackedTunnelProcesses()
        }
        stateMachine.send(.errorOccurred(lastError ?? "Failed to recover \(mode.rawValue) tunnel"))
    }

    func cleanupTunnelProcessResources(terminateProcess: Bool) {
        monitorTask?.cancel()
        monitorTask = nil
        healthMonitor.stopMonitoring()

        if terminateProcess, let process = tunneldProcess, process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        tunneldProcess = nil
        outputPipe = nil
        errorPipe = nil
        invalidateRsdInfo(reason: "Tunnel process resources cleaned up")
        activeMode = nil
    }

    // MARK: - Public API

    /// Start tunnel automatically - called on app launch
}
