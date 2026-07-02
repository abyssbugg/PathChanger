//
//  TunneldManager+ProcessManagement.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {

    // MARK: - Process Management (Security Hardened)

    /// Kill lifecycle-scoped pmd3 tunnel child processes safely using PID + command validation.
    /// Does NOT use global killall behavior or terminate non-tunnel pymobiledevice3 commands.
    ///
    /// Security Features:
    /// - Only terminates state-machine PIDs, lifecycle-discovered child PIDs, or exact mode/UDID matches
    /// - Verifies command line, owner UID, and tunnel mode before termination
    /// - Uses graceful SIGTERM, escalates to SIGKILL, then validates termination
    /// - Does NOT kill system services (e.g., usbmuxd)
    func killTrackedTunnelProcesses() {
        let cleanupMode = stateMachine.currentContext.activeMode ?? activeMode ?? lastTunnelModeForCleanup
        let cleanupTargetUDID = lastTunnelTargetUDIDForCleanup ?? targetTunnelUDID
        let lifecycleCandidatePids = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        let candidatePids = cleanupCandidateProcessIds(mode: cleanupMode, targetUDID: cleanupTargetUDID)

        Logger.debug("[SECURITY] Terminating \(candidatePids.count) validated tunnel child process(es)", category: .security)

        guard !candidatePids.isEmpty else {
            trackedTunnelChildProcessIds = trackedTunnelChildProcessIds.filter {
                isProcessAliveAndNonZombie(pid: $0)
            }
            Logger.debug("[SECURITY] No validated tunnel child processes to terminate", category: .security)
            return
        }

        // First pass: Send SIGTERM for graceful shutdown
        for pid in candidatePids {
            let allowMissingTargetUDID = lifecycleCandidatePids.contains(pid)
            if sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGTERM,
                mode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
            ) {
                Logger.debug("[SECURITY] Sent SIGTERM to validated tunnel PID \(pid)", category: .security)
            }
        }

        // Brief wait for graceful termination
#if DEBUG
        let gracefulTerminationDelay: useconds_t = debugSignalHandler == nil ? 500_000 : 1_000
#else
        let gracefulTerminationDelay: useconds_t = 500_000
#endif
        usleep(gracefulTerminationDelay)

        // Second pass: Force kill any remaining validated tunnel children.
        for pid in candidatePids {
            let allowMissingTargetUDID = lifecycleCandidatePids.contains(pid)
            if isProcessRunning(pid: pid),
               sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGKILL,
                mode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
               ) {
                Logger.debug("[SECURITY] Sent SIGKILL to validated tunnel PID \(pid)", category: .security)
            }
        }
#if DEBUG
        let verificationDelay: useconds_t = debugSignalHandler == nil ? 200_000 : 1_000
#else
        let verificationDelay: useconds_t = 200_000
#endif
        usleep(verificationDelay)

        let remainingPids = candidatePids.filter {
            isProcessRunning(pid: $0) &&
            isValidatedTunnelProcess(
                pid: $0,
                cleanupMode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: lifecycleCandidatePids.contains($0)
            )
        }

        if remainingPids.isEmpty {
            trackedTunnelChildProcessIds.subtract(candidatePids)
        } else {
            trackedTunnelChildProcessIds.formUnion(remainingPids)
            Logger.error("[SECURITY] Tunnel child cleanup verification failed for PID(s): \(remainingPids.map(String.init).joined(separator: ", "))", category: .security)
        }

        // Process IDs are cleared by state machine when it transitions to idle
        Logger.debug("[SECURITY] Tunnel child process cleanup complete", category: .security)
    }

    /// Check if process is owned by current user
    /// Returns false if process doesn't exist or ownership cannot be verified
    func isOwnedProcess(pid: Int32) -> Bool {
        processUID(pid: pid) == getuid()
    }

    /// Check if a process is still running
    func isProcessRunning(pid: Int32) -> Bool {
        isProcessAliveAndNonZombie(pid: pid)
    }

    func isTunnelProcessAlive(pid: Int32) -> Bool {
        isProcessAliveAndNonZombie(pid: pid)
    }

    /// Mode-aware tunnel connectivity health check.
    ///
    /// The legacy health check only inspected the single log-parsed `tunnelInfo`,
    /// which is fragile in daemon mode: there the live RSD is served per-device
    /// from the tunneld HTTP API (`deviceTunnelInfo`), while the log-parsed
    /// `tunnelInfo` may be nil or stale. That mismatch caused false
    /// "connectivity lost" → "Tunnel Required" flips even though injection kept
    /// working. This check treats the tunnel as healthy when a usable RSD exists
    /// in EITHER source and, if we track tunnel process IDs (the USB lockdown
    /// child or the long-lived `tunneld` daemon), at least one is still alive.
    func currentTunnelConnectivityHealthy() -> Bool {
        guard isRunning else { return false }

        // A usable RSD may live in the legacy single `tunnelInfo` (USB
        // script-mode log parse) or per-device in `deviceTunnelInfo` (daemon
        // mode, refreshed from the tunneld HTTP API).
        let hasUsableRsd = (tunnelInfo.map { isUsableTunnelInfo($0) } ?? false)
            || deviceTunnelInfo.values.contains { isUsableTunnelInfo($0) }
        guard hasUsableRsd else { return false }

        // If we are tracking tunnel process IDs (the USB lockdown child or the
        // long-lived `tunneld` daemon), require at least one to still be alive.
        let trackedPids = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        if !trackedPids.isEmpty {
            return trackedPids.contains { isTunnelProcessAlive(pid: $0) }
        }

        // No tracked PID (e.g. attached to an externally-started tunnel): the
        // running state plus a usable RSD established above is sufficient.
        return true
    }

    func isProcessAliveAndNonZombie(pid: Int32) -> Bool {
#if DEBUG
        if let overrideIndex = debugProcessStateOverrides.index(forKey: pid) {
            let override = debugProcessStateOverrides[overrideIndex].value
            guard let state = override else { return false }
            return !Self.isZombieProcessState(state)
        }
#endif
        guard processExistsForValidation(pid: pid) else {
            return false
        }

        guard let state = processState(pid: pid) else {
            return false
        }

        return !Self.isZombieProcessState(state)
    }

    func processExistsForValidation(pid: Int32) -> Bool {
#if DEBUG
        if let override = debugKillZeroResultOverrides[pid] {
            switch override {
            case .allowed, .permissionDenied:
                return true
            case .missing:
                return false
            }
        }
#endif
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    func processState(pid: Int32) -> String? {
#if DEBUG
        if let overrideIndex = debugProcessStateOverrides.index(forKey: pid) {
            return debugProcessStateOverrides[overrideIndex].value
        }
#endif
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "stat="]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        do {
            try ps.run()
            ps.waitUntilExit()
        } catch {
            return nil
        }

        guard ps.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.isEmpty ? nil : state
    }

    nonisolated static func isZombieProcessState(_ state: String) -> Bool {
        state.uppercased().contains("Z")
    }

    /// Monitor tunnel status periodically
    func startMonitoring() {
        monitorTask?.cancel()

        // Set up health monitor failure notifications
        healthMonitor.setFailureNotificationHandler { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                Logger.error("🔴 Tunnel connectivity lost; automatic privileged restart is disabled", category: .device)
                self.lastError = "Tunnel connection lost. Reconnect the device and click Start to retry."
                self.statusMessage = "Tunnel disconnected"
                self.monitorTask?.cancel()
                self.monitorTask = nil
                self.healthMonitor.stopMonitoring()
                self.stateMachine.send(.healthCheckFailed)
            }
        }

        // Start health monitoring
        healthMonitor.startMonitoring()

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    guard let self else { return }
                    // Daemon mode keeps per-device tunnels alive but re-creates
                    // them on device reconnect, which changes the RSD port. The
                    // tunneld HTTP API always reports the current RSD, so keep
                    // `deviceTunnelInfo` fresh here. This is prompt-free (no
                    // privileged relaunch) and lets device commands pick up the
                    // new port automatically via `getRsdInfo(for:)`.
                    if self.activeMode == .daemon {
                        await self.refreshDeviceRsdInfo()
                    }
                    Logger.debug("✓ Health check passed", category: .device)
                } catch {
                    return
                }
            }
        }
    }

    nonisolated static let maxOutputSize = 1_048_576
}
