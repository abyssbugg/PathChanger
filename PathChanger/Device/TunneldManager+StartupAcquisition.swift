//
//  TunneldManager+StartupAcquisition.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func waitForValidRsdInfo(mode: TunnelMode) async -> TunnelInfo? {
        if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
            return info
        }
        if let info = tunnelInfo, isUsableTunnelInfo(info) {
            return info
        }
        let maxAttempts = 4
        for attempt in 0..<maxAttempts {
            await parseRsdInfo()
            if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
                return info
            }
            if let info = tunnelInfo, isUsableTunnelInfo(info) {
                return info
            }
            // Don't sleep after the last attempt.
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
        }

        // Last-ditch: query the tunneld HTTP API once more in case the daemon
        // already has a usable record even when log parsing failed.
        await queryTunneldAPI()
        if let firstDeviceInfo = deviceTunnelInfo.values.first(where: { isUsableTunnelInfo($0) }) {
            tunnelInfo = firstDeviceInfo
            return firstDeviceInfo
        }

        Logger.error("[Tunnel] waitForValidRsdInfo gave up for mode \(mode.rawValue) after \(maxAttempts) attempts", category: .device)
        return nil
    }

    func startupAcquisitionTimeout(for mode: TunnelMode) -> TimeInterval {
#if DEBUG
        if let debugStartupTimeoutOverride {
            return debugStartupTimeoutOverride
        }
#endif
        switch mode {
        case .daemon:
            return 45
        case .usb, .wifi, .auto:
            return ServiceLevelObjectives.startupTimeSecondsThreshold
        }
    }

    var startupAcquisitionPollInterval: TimeInterval {
#if DEBUG
        if let debugStartupPollIntervalOverride {
            return debugStartupPollIntervalOverride
        }
#endif
        return 0.5
    }

    var handoffStabilizationTimeout: TimeInterval {
        0.75
    }

    var handoffStabilizationPollInterval: TimeInterval {
#if DEBUG
        if let debugStartupPollIntervalOverride {
            return debugStartupPollIntervalOverride
        }
#endif
        return 0.02
    }

    func wrapperReturnTimeout(for mode: TunnelMode) -> TimeInterval {
#if DEBUG
        if let debugWrapperReturnTimeoutOverride {
            return debugWrapperReturnTimeoutOverride
        }
#endif
        return max(15, startupAcquisitionTimeout(for: mode) * 3)
    }

    func logStartupTrace(_ event: String, fields: [String: Any] = [:]) {
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = details.isEmpty ? "" : " \(details)"
        Logger.info("[Tunnel][Startup] \(event) t=\(Date().timeIntervalSince1970)\(suffix)", category: .device)
        appendStartupTrace(event, fields: fields)
    }

    func appendStartupTrace(_ event: String, fields: [String: Any]) {
        var payload = fields
        payload["event"] = event
        payload["timestamp"] = Date().timeIntervalSince1970
        payload["state"] = "\(stateMachine.currentState)"

        guard JSONSerialization.isValidJSONObject(startupTraceSanitized(payload)),
              let data = try? JSONSerialization.data(withJSONObject: startupTraceSanitized(payload), options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }

        ensureLogDirectoryExists()
        let traceLine = line + "\n"
        if FileManager.default.fileExists(atPath: startupTraceFilePath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: startupTraceFilePath)) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(traceLine.utf8))
            try? handle.close()
        } else {
            try? traceLine.write(toFile: startupTraceFilePath, atomically: true, encoding: .utf8)
        }
    }

    func startupTraceSanitized(_ value: Any) -> Any {
        if let value = value as? [String: Any] {
            return value.mapValues { startupTraceSanitized($0) }
        }
        if let value = value as? [Any] {
            return value.map { startupTraceSanitized($0) }
        }
        if let value = value as? Set<Int32> {
            return value.sorted().map(Int.init)
        }
        if let value = value as? Int32 {
            return Int(value)
        }
        if let value = value as? UInt64 {
            return String(value)
        }
        if JSONSerialization.isValidJSONObject(["value": value]) {
            return value
        }
        return "\(value)"
    }

    func waitForAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        handedOffPid: Int32?
    ) async -> TunnelInfo? {
        let timeout = startupAcquisitionTimeout(for: mode)
        let pollInterval = startupAcquisitionPollInterval
        let deadline = Date().addingTimeInterval(timeout)
        var authoritativePid: Int32?
        var pollCount = 0
        let waitStartTime = Date().timeIntervalSince1970

        logStartupTrace("authoritative_wait_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "timeout": timeout,
            "pollInterval": pollInterval,
            "beforeLaunchPids": beforeLaunchPids.sorted(),
            "handedOffPid": handedOffPid as Any
        ])

        if let handedOffPid {
            guard let validatedPid = await waitForStableHandedOffTunnelChild(
                pid: handedOffPid,
                mode: mode,
                targetUDID: targetUDID,
                beforeLaunchPids: beforeLaunchPids,
                startupDeadline: deadline,
                waitStartTime: waitStartTime,
                phase: "handoff"
            ) else {
                await finalizeFailedStartupAcquisition(
                    mode: mode,
                    targetUDID: targetUDID,
                    generation: generation,
                    waitStartTime: waitStartTime,
                    pollCount: pollCount,
                    handedOffPid: handedOffPid,
                    beforeLaunchPids: beforeLaunchPids
                )
                return nil
            }

            authoritativePid = adoptAuthoritativeTunnelChild(
                pid: validatedPid,
                mode: mode,
                targetUDID: targetUDID,
                phase: "handoff"
            )
        }

        if let info = await pollAuthoritativeStartup(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: generation,
            deadline: deadline,
            phase: handedOffPid == nil ? "discovery" : "handoff",
            pollInterval: pollInterval,
            authoritativePid: &authoritativePid,
            pollCount: &pollCount
        ) {
            logStartupTrace("authoritative_wait_ready", fields: [
                "mode": mode.rawValue,
                "phase": handedOffPid == nil ? "discovery" : "handoff",
                "pid": info.processId ?? -1,
                "rsdAddress": info.rsdAddress,
                "rsdPort": info.rsdPort,
                "poll": pollCount,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
            return info
        }

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            logStartupTrace("authoritative_wait_cancelled", fields: [
                "mode": mode.rawValue,
                "state": "\(stateMachine.currentState)",
                "poll": pollCount,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
            return nil
        }
        logStartupTrace("authoritative_wait_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "activeProcessIds": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        await finalizeFailedStartupAcquisition(
            mode: mode,
            targetUDID: targetUDID,
            generation: generation,
            waitStartTime: waitStartTime,
            pollCount: pollCount,
            handedOffPid: handedOffPid,
            beforeLaunchPids: beforeLaunchPids
        )
        return nil
    }

    // swiftlint:disable:next function_parameter_count -- authoritative startup polling needs the full acquisition context. Collapsing these into a struct is a mechanical follow-up.
    func pollAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        deadline: Date,
        phase: String,
        pollInterval: TimeInterval,
        authoritativePid: inout Int32?,
        pollCount: inout Int
    ) async -> TunnelInfo? {
        while Date() < deadline {
            guard isCurrentTunnelLifecycle(generation) else {
                logStartupTrace("authoritative_wait_cancelled_generation_changed", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "poll": pollCount
                ])
                return nil
            }

            guard case .starting = stateMachine.currentState else {
                logStartupTrace("authoritative_wait_cancelled_state_changed", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "state": "\(stateMachine.currentState)",
                    "poll": pollCount
                ])
                return nil
            }

            pollCount += 1
            if authoritativePid == nil {
                authoritativePid = acquireAuthoritativeTunnelChild(
                    mode: mode,
                    targetUDID: targetUDID,
                    beforeLaunchPids: beforeLaunchPids,
                    pollCount: pollCount,
                    phase: phase
                )
            }

            if let authoritativePid,
               let info = await startupRsdInfo(mode: mode, authoritativePid: authoritativePid) {
                let authoritativeInfo = tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
                tunnelInfo = authoritativeInfo
                logStartupTrace("authoritative_poll_ready", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "pid": authoritativePid,
                    "rsdAddress": authoritativeInfo.rsdAddress,
                    "rsdPort": authoritativeInfo.rsdPort,
                    "poll": pollCount
                ])
                return authoritativeInfo
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.001, pollInterval) * 1_000_000_000))
        }

        return nil
    }

    func finalizeFailedStartupAcquisition(
        mode: TunnelMode,
        targetUDID: String?,
        generation: UInt64,
        waitStartTime: TimeInterval,
        pollCount: Int,
        handedOffPid: Int32? = nil,
        beforeLaunchPids: Set<Int32> = []
    ) async {
        if let handedOffPid,
           let cleanupPid = await waitForStableHandedOffTunnelChild(
            pid: handedOffPid,
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            startupDeadline: Date().addingTimeInterval(handoffStabilizationTimeout),
            waitStartTime: waitStartTime,
            phase: "cleanup"
           ) {
            trackedTunnelChildProcessIds.insert(cleanupPid)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            logStartupTrace("startup_failure_cleanup_handoff_candidate_included", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": cleanupPid,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
        }
        logStartupTrace("startup_failure_cleanup_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "activeProcessIds": stateMachine.currentContext.activeProcessIds.sorted()
        ])
        killTrackedTunnelProcesses()

        let remainingCandidates = cleanupCandidateProcessIds(mode: mode, targetUDID: targetUDID)
        logStartupTrace("startup_failure_cleanup_complete", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "remainingCandidates": remainingCandidates,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])
    }

    func waitForStableHandedOffTunnelChild(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        startupDeadline: Date,
        waitStartTime: TimeInterval,
        phase: String
    ) async -> Int32? {
        let stabilizationDeadline = min(
            startupDeadline,
            Date().addingTimeInterval(handoffStabilizationTimeout)
        )
        var attempt = 0

        logStartupTrace("handoff_stabilization_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "phase": phase,
            "timeout": handoffStabilizationTimeout,
            "pollInterval": handoffStabilizationPollInterval,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])

        repeat {
            attempt += 1
            if let validatedPid = validateHandedOffTunnelChild(
                pid: pid,
                mode: mode,
                targetUDID: targetUDID,
                beforeLaunchPids: beforeLaunchPids
            ) {
                logStartupTrace("handoff_stabilization_validated", fields: [
                    "mode": mode.rawValue,
                    "targetUDID": targetUDID ?? "nil",
                    "pid": pid,
                    "phase": phase,
                    "attempt": attempt,
                    "elapsed": Date().timeIntervalSince1970 - waitStartTime
                ])
                return validatedPid
            }

            logStartupTrace("handoff_stabilization_retry", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": pid,
                "phase": phase,
                "attempt": attempt,
                "snapshot": processValidationSnapshot(pid: pid),
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])

            guard Date() < stabilizationDeadline else {
                break
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.001, handoffStabilizationPollInterval) * 1_000_000_000))
        } while Date() < stabilizationDeadline

        logStartupTrace("handoff_stabilization_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "phase": phase,
            "attempts": attempt,
            "snapshot": processValidationSnapshot(pid: pid),
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])
        return nil
    }

    func validateHandedOffTunnelChild(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>
    ) -> Int32? {
        let snapshot = processValidationSnapshot(pid: pid)

        func reject(_ reason: String) -> Int32? {
            logStartupTrace("handoff_pid_rejected", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": pid,
                "reason": reason,
                "snapshot": snapshot
            ])
            return nil
        }

        guard pid > 1 else {
            return reject("pid_not_signalable")
        }
        guard !beforeLaunchPids.contains(pid) else {
            return reject("pid_existed_before_launch")
        }
        guard isProcessAliveAndNonZombie(pid: pid) else {
            return reject("pid_not_live_or_zombie")
        }
        guard let command = processCommand(pid: pid) else {
            return reject("command_unavailable")
        }
        guard Self.isSanctionedTunnelChildCommand(
            command,
            mode: mode,
            targetUDID: targetUDID,
            requireTargetUDID: mode != .daemon
        ) else {
            return reject("command_mode_or_udid_mismatch")
        }
        guard let uid = processUID(pid: pid) else {
            return reject("uid_unavailable")
        }
        guard uid == getuid() || uid == 0 else {
            return reject("uid_not_allowed")
        }

        logStartupTrace("handoff_pid_validated", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "snapshot": snapshot
        ])
        return pid
    }

    func processValidationSnapshot(pid: Int32) -> [String: Any] {
        [
            "pid": pid,
            "command": processCommand(pid: pid) ?? "nil",
            "uid": processUID(pid: pid).map(Int.init) as Any,
            "state": processState(pid: pid) ?? "nil",
            "aliveNonZombie": isProcessAliveAndNonZombie(pid: pid)
        ]
    }

}
