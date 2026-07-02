//
//  TunneldManager+StartupAcquisitionContinuation.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func parseHandedOffPid(from output: String) -> Int32? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.allSatisfy({ $0.isNumber }),
                  let value = Int32(trimmed),
                  value > 1 else {
                continue
            }
            return value
        }
        return nil
    }

    func acquireAuthoritativeTunnelChild(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        pollCount: Int,
        phase: String
    ) -> Int32? {
        let livePids = liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID)
        let lifecyclePids = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        let startupPids = livePids.filter {
            !beforeLaunchPids.contains($0) || lifecyclePids.contains($0)
        }

        logStartupTrace("child_acquisition_poll", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "phase": phase,
            "poll": pollCount,
            "livePids": livePids,
            "startupPids": startupPids,
            "trackedPids": trackedTunnelChildProcessIds.sorted(),
            "statePids": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        guard let authoritativePid = startupPids.first else {
            return nil
        }

        if startupPids.count > 1 {
            for extraPid in startupPids.dropFirst() {
                _ = sendSignalToValidatedTunnelProcess(
                    pid: extraPid,
                    signal: SIGKILL,
                    mode: mode,
                    targetUDID: targetUDID,
                    allowMissingTargetUDID: lifecyclePids.contains(extraPid)
                )
            }
        }

        return adoptAuthoritativeTunnelChild(
            pid: authoritativePid,
            mode: mode,
            targetUDID: targetUDID,
            phase: phase
        )
    }

    func adoptAuthoritativeTunnelChild(
        pid authoritativePid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        phase: String
    ) -> Int32 {
        trackedTunnelChildProcessIds.insert(authoritativePid)
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID

        if !stateMachine.currentContext.activeProcessIds.contains(authoritativePid) {
            stateMachine.send(.processLaunched(pid: authoritativePid))
            syncStateWithStateMachine()
        }

        logStartupTrace("child_acquired", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "phase": phase,
            "pid": authoritativePid,
            "trackedPids": trackedTunnelChildProcessIds.sorted(),
            "statePids": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        return authoritativePid
    }

    func startupRsdInfo(mode: TunnelMode, authoritativePid: Int32) async -> TunnelInfo? {
#if DEBUG
        if debugUsesStartupRsdInfoSequence {
            guard !debugStartupRsdInfoSequence.isEmpty else {
                logStartupTrace("rsd_sequence_exhausted", fields: [
                    "mode": mode.rawValue,
                    "pid": authoritativePid
                ])
                return nil
            }
            guard let info = debugStartupRsdInfoSequence.removeFirst() else {
                logStartupTrace("rsd_not_ready_debug", fields: [
                    "mode": mode.rawValue,
                    "pid": authoritativePid
                ])
                return nil
            }
            let authoritativeInfo = tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
            tunnelInfo = authoritativeInfo
            logStartupTrace("rsd_ready_debug", fields: [
                "mode": mode.rawValue,
                "pid": authoritativePid,
                "rsdAddress": authoritativeInfo.rsdAddress,
                "rsdPort": authoritativeInfo.rsdPort
            ])
            return authoritativeInfo
        }
#endif
        await parseRsdInfo()
        if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
            return tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
        }
        if let info = tunnelInfo, isUsableTunnelInfo(info) {
            return tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
        }
        return nil
    }

    func tunnelInfoWithAuthoritativeProcessId(_ info: TunnelInfo, pid: Int32) -> TunnelInfo {
        guard info.processId != pid else {
            return info
        }
        return TunnelInfo(
            rsdAddress: info.rsdAddress,
            rsdPort: info.rsdPort,
            mode: info.mode,
            interface: info.interface,
            processId: pid
        )
    }

    /// True only when a TunnelInfo can actually be used to talk to the device.
    /// Rejects the legacy 127.0.0.1:0 placeholder and any zero-port info.
    func isUsableTunnelInfo(_ info: TunnelInfo) -> Bool {
        guard info.rsdPort > 0, info.rsdPort <= 65_535 else { return false }
        if info.rsdAddress == "127.0.0.1" { return false }
        if info.rsdAddress.isEmpty { return false }
        return isValidRsdAddress(info.rsdAddress)
    }

    /// Attach to an already-running tunnel instead of launching another privileged process.
    ///
    /// Returns `true` only if a running tunnel exists AND it matches the user's `preferredMode`
    /// (or `preferredMode == .auto`). When the user picks a specific mode different from what's
    /// running (e.g. WiFi while a USB tunnel is up), this returns `false` so the caller will
    /// proceed to stop the mismatching tunnel and start fresh in the requested mode.
    func attachToRunningTunnelIfAvailable(
        generation: UInt64,
        replaceStaleOnMissingRsd: Bool = false
    ) async -> Bool {
        guard let runningMode = await detectRunningTunnel() else {
            return false
        }
        guard isCurrentTunnelLifecycle(generation) else { return true }

        // Mode-aware reattach gate: refuse to silently bind to a tunnel that doesn't
        // match the user's explicit preference.
        let desiredMode = TunnelMode.effectiveMode(
            requested: preferredMode,
            targetIOSMajorVersion: targetTunnelIOSMajorVersion,
            targetConnectionType: targetTunnelConnectionType
        )
        let modeMatches = preferredMode == .auto || desiredMode == runningMode
        if !modeMatches {
            Logger.info(
                "[Tunnel] Existing \(runningMode.rawValue) tunnel detected but preferredMode is \(preferredMode.rawValue) (effective \(desiredMode.rawValue)) - stopping it to start fresh in requested mode",
                category: .device
            )
            statusMessage = "Stopping \(runningMode.rawValue) tunnel to switch to \(desiredMode.rawValue)..."
            stopTunnel(invalidateScheduledRestart: true, advanceGeneration: false)
            try? await Task.sleep(nanoseconds: 500_000_000) // grace for processes to exit
            guard isCurrentTunnelLifecycle(generation) else { return true }
            return false
        }

        guard let recoveredInfo = recoverRsdInfoFromLog() else {
            if replaceStaleOnMissingRsd {
                let stalePids = liveTunnelProcessIdsSync(for: runningMode, targetUDID: targetTunnelUDID)
                trackedTunnelChildProcessIds.formUnion(stalePids)
                lastTunnelModeForCleanup = runningMode
                lastTunnelTargetUDIDForCleanup = targetTunnelUDID
                Logger.info("[Tunnel] Recovery replacing stale \(runningMode.rawValue) tunnel without recoverable RSD info", category: .device)
                killTrackedTunnelProcesses()
                lastError = nil
                statusMessage = "Cleaned stale tunnel; retrying…"
                return false
            }
            let message = "A tunnel process is already running, but PathChanger could not read its RSD address. Stop the existing tunnel and start it again."
            lastError = message
            statusMessage = message
            Logger.error(message, category: .device)
            return true
        }
        guard isCurrentTunnelLifecycle(generation) else { return true }

        tunnelInfo = recoveredInfo
        lastError = nil
        statusMessage = "Tunnel already running (RSD: \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort))"
        Logger.info("Attached to existing \(runningMode.rawValue) tunnel at \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort)", category: .device)
        stateMachine.send(.externalTunnelDetected(mode: runningMode, info: recoveredInfo))
        return true
    }

    func finalizeWrapperReturnTimeout(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        timeout: TimeInterval
    ) {
        let message = "Privileged \(mode.rawValue) tunnel wrapper did not return a handed-off PID within \(String(format: "%.1f", timeout)) seconds. Startup was failed closed."
        lastError = message
        statusMessage = message
        logStartupTrace("wrapper_return_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "timeout": timeout,
            "beforeLaunchPids": beforeLaunchPids.sorted()
        ])

        cleanupWrapperStalledLaunch(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: generation
        )

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            return
        }
        stateMachine.send(.errorOccurred(message))
        syncStateWithStateMachine()
    }

    func cleanupWrapperStalledLaunch(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64
    ) {
        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            logStartupTrace("wrapper_stall_cleanup_skipped", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "generationCurrent": isCurrentTunnelLifecycle(generation),
                "state": "\(stateMachine.currentState)"
            ])
            return
        }

        let candidatePids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
            .subtracting(beforeLaunchPids)
            .sorted()

        logStartupTrace("wrapper_stall_cleanup_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "beforeLaunchPids": beforeLaunchPids.sorted(),
            "candidatePids": candidatePids
        ])

        let remainingPids = terminateLaunchScopedTunnelChildren(
            candidatePids,
            mode: mode,
            targetUDID: targetUDID
        )

        logStartupTrace("wrapper_stall_cleanup_complete", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "candidatePids": candidatePids,
            "remainingCandidates": remainingPids
        ])
    }

    func terminateLaunchScopedTunnelChildren(
        _ candidatePids: [Int32],
        mode: TunnelMode,
        targetUDID: String?
    ) -> [Int32] {
        guard !candidatePids.isEmpty else {
            return []
        }

        for pid in candidatePids {
            _ = sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGTERM,
                mode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: false
            )
        }

#if DEBUG
        let gracefulTerminationDelay: useconds_t = debugSignalHandler == nil ? 500_000 : 1_000
#else
        let gracefulTerminationDelay: useconds_t = 500_000
#endif
        usleep(gracefulTerminationDelay)

        for pid in candidatePids where isProcessRunning(pid: pid) {
            _ = sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGKILL,
                mode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: false
            )
        }

#if DEBUG
        let verificationDelay: useconds_t = debugSignalHandler == nil ? 200_000 : 1_000
#else
        let verificationDelay: useconds_t = 200_000
#endif
        usleep(verificationDelay)

        return candidatePids.filter {
            isProcessRunning(pid: $0) &&
            isValidatedTunnelProcess(
                pid: $0,
                mode: mode,
                targetUDID: targetUDID
            )
        }
    }

    /// Attempt to start tunnel with specific mode
}
