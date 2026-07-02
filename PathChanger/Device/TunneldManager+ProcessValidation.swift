//
//  TunneldManager+ProcessValidation.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    // MARK: - Process Validation

    /// Validate that only a single tunnel instance is running
    /// Prevents race conditions where multiple processes start simultaneously
    func validateSingleTunnelInstance(mode: TunnelMode, targetUDID: String?) async -> Bool {
        let pids = await liveTunnelProcessIds(for: mode, targetUDID: targetUDID)

        // Get tracked PIDs from state machine context
        let trackedPids = stateMachine.currentContext.activeProcessIds

        // Check if we already know about these PIDs
        let lifecyclePids = trackedPids.union(trackedTunnelChildProcessIds)
        let newPids = pids.filter { !lifecyclePids.contains($0) }

        if newPids.count > 1 {
            // Multiple NEW processes detected - race condition!
            Logger.debug("Detected \(newPids.count) tunnel child processes for \(mode.rawValue), keeping only first", category: .device)

            // Keep only the first PID, kill the rest
            for pid in newPids.dropFirst() {
                _ = sendSignalToValidatedTunnelProcess(pid: pid, signal: SIGKILL, mode: mode, targetUDID: targetUDID)
            }

            // Track the surviving process via state machine event
            if let firstPid = newPids.first {
                trackedTunnelChildProcessIds.insert(firstPid)
                lastTunnelModeForCleanup = mode
                lastTunnelTargetUDIDForCleanup = targetUDID
                stateMachine.send(.processLaunched(pid: firstPid))
            }

            return true
        } else if let pid = newPids.first {
            // Single new process - track it via state machine
            trackedTunnelChildProcessIds.insert(pid)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            stateMachine.send(.processLaunched(pid: pid))
            return true
        } else if !pids.isEmpty {
            // All PIDs are already tracked
            trackedTunnelChildProcessIds.formUnion(pids)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            return true
        }

        return false
    }

    func liveProcessIds(matching pattern: String) async -> [Int32] {
        liveProcessIdsSync(matching: pattern)
    }

    func liveProcessIdsSync(matching pattern: String) -> [Int32] {
#if DEBUG
        if var sequence = debugLiveProcessIdsSequenceOverrides[pattern] {
            let pids = sequence.isEmpty ? [] : sequence.removeFirst()
            debugLiveProcessIdsSequenceOverrides[pattern] = sequence
            return Array(Set(pids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        }
        if let overridePids = debugLiveProcessIdsOverrides[pattern] {
            return Array(Set(overridePids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        }
#endif
        do {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-f", pattern]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return []
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            let pids = output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            return Array(Set(pids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        } catch {
            return []
        }
    }

    func liveTunnelProcessIds(for mode: TunnelMode, targetUDID: String?) async -> [Int32] {
        liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID)
    }

    func liveTunnelProcessIdsSync(for mode: TunnelMode, targetUDID: String?) -> [Int32] {
        liveProcessIdsSync(matching: mode.processPattern)
            .filter { isValidatedTunnelProcess(pid: $0, mode: mode, targetUDID: targetUDID) }
            .sorted()
    }

    func recordLaunchedTunnelChildren(mode: TunnelMode, targetUDID: String?, beforeLaunchPids: Set<Int32>) {
        let currentPids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
        let launchedPids = currentPids.subtracting(beforeLaunchPids)

        guard !launchedPids.isEmpty else {
            Logger.debug("[Tunnel] No new pmd3 tunnel child PID detected after \(mode.rawValue) launch", category: .device)
            return
        }

        trackedTunnelChildProcessIds.formUnion(launchedPids)
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID
        Logger.info("[Tunnel] Tracking pmd3 tunnel child PID(s): \(launchedPids.sorted().map(String.init).joined(separator: ", "))", category: .device)
    }

    func processCommand(pid: Int32) -> String? {
#if DEBUG
        if let override = debugProcessCommandOverrides[pid] {
            return override
        }
        if let stateOverrideIndex = debugProcessStateOverrides.index(forKey: pid),
           debugProcessStateOverrides[stateOverrideIndex].value == nil {
            return nil
        }
#endif
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "command="]
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
        let command = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    func processUID(pid: Int32) -> uid_t? {
#if DEBUG
        if let override = debugProcessUIDOverrides[pid] {
            return override
        }
        if let stateOverrideIndex = debugProcessStateOverrides.index(forKey: pid),
           debugProcessStateOverrides[stateOverrideIndex].value == nil {
            return nil
        }
#endif
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "uid="]
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
        guard let output = String(data: data, encoding: .utf8),
              let uid = uid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return uid
    }

    func isValidatedTunnelProcess(pid: Int32, mode: TunnelMode, targetUDID: String?) -> Bool {
        isValidatedTunnelProcess(pid: pid, mode: mode, targetUDID: targetUDID, allowMissingTargetUDID: false)
    }

    func isValidatedTunnelProcess(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        allowMissingTargetUDID: Bool
    ) -> Bool {
        guard let command = processCommand(pid: pid),
              Self.isSanctionedTunnelChildCommand(
                command,
                mode: mode,
                targetUDID: targetUDID,
                requireTargetUDID: !allowMissingTargetUDID
              ),
              let uid = processUID(pid: pid) else {
            return false
        }

        return uid == getuid() || uid == 0
    }

    func isValidatedTunnelProcess(pid: Int32, cleanupMode: TunnelMode?, targetUDID: String?) -> Bool {
        isValidatedTunnelProcess(pid: pid, cleanupMode: cleanupMode, targetUDID: targetUDID, allowMissingTargetUDID: false)
    }

    func isValidatedTunnelProcess(
        pid: Int32,
        cleanupMode: TunnelMode?,
        targetUDID: String?,
        allowMissingTargetUDID: Bool
    ) -> Bool {
        let modes = cleanupMode.map { [$0] } ?? [.usb, .wifi, .daemon]
        return modes.contains {
            isValidatedTunnelProcess(
                pid: pid,
                mode: $0,
                targetUDID: targetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
            )
        }
    }

    nonisolated static func isSanctionedTunnelChildCommand(_ command: String, mode: TunnelMode, targetUDID: String?) -> Bool {
        isSanctionedTunnelChildCommand(command, mode: mode, targetUDID: targetUDID, requireTargetUDID: true)
    }

    nonisolated static func isSanctionedTunnelChildCommand(
        _ command: String,
        mode: TunnelMode,
        targetUDID: String?,
        requireTargetUDID: Bool
    ) -> Bool {
        guard mode != .auto else {
            return false
        }

        let normalized = command
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable = normalized.split(separator: " ").first.map(String.init),
              executable.hasSuffix("python3"),
              normalized.contains("-m pymobiledevice3") else {
            return false
        }

        let modeMatches: Bool
        switch mode {
        case .usb:
            modeMatches = normalized.contains("pymobiledevice3 lockdown start-tunnel")
        case .wifi:
            modeMatches = normalized.contains("pymobiledevice3 remote start-tunnel") &&
                normalized.contains("-t wifi")
        case .daemon:
            modeMatches = normalized.contains("pymobiledevice3 remote tunneld")
        case .auto:
            modeMatches = false
        }

        guard modeMatches else {
            return false
        }

        if requireTargetUDID, mode != .daemon, let targetUDID {
            return normalized.contains(targetUDID)
        }

        return true
    }

    func cleanupCandidateProcessIds(mode: TunnelMode?, targetUDID: String?) -> [Int32] {
        let lifecycleCandidates = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        var candidates = Set(
            lifecycleCandidates
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .filter {
                    isValidatedTunnelProcess(
                        pid: $0,
                        cleanupMode: mode,
                        targetUDID: targetUDID,
                        allowMissingTargetUDID: true
                    )
                }
        )

        if let mode {
            candidates.formUnion(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
        }

        return candidates
            .filter { isProcessAliveAndNonZombie(pid: $0) }
            .filter {
                isValidatedTunnelProcess(
                    pid: $0,
                    cleanupMode: mode,
                    targetUDID: targetUDID,
                    allowMissingTargetUDID: lifecycleCandidates.contains($0)
                )
            }
            .sorted()
    }

    func sendSignalToValidatedTunnelProcess(
        pid: Int32,
        signal: Int32,
        mode: TunnelMode?,
        targetUDID: String?,
        allowMissingTargetUDID: Bool = false
    ) -> Bool {
        guard pid > 1,
              signal == SIGTERM || signal == SIGKILL,
              isValidatedTunnelProcess(
                pid: pid,
                cleanupMode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
              ),
              let uid = processUID(pid: pid) else {
            Logger.debug("[SECURITY] Refusing to signal unvalidated tunnel PID \(pid)", category: .security)
            return false
        }
#if DEBUG
        if let debugSignalHandler {
            return debugSignalHandler(pid, signal)
        }
        if debugProcessCommandOverrides[pid] != nil ||
            debugProcessUIDOverrides[pid] != nil ||
            debugProcessStateOverrides.keys.contains(pid) ||
            debugKillZeroResultOverrides[pid] != nil {
            if signal == SIGKILL {
                debugProcessStateOverrides.updateValue(nil, forKey: pid)
            }
            Logger.debug("[SECURITY] Simulated signal \(signal) to mocked tunnel PID \(pid)", category: .security)
            return true
        }
#endif

        if uid == getuid() {
            return sendLocalSignal(signal, to: pid)
        }

        guard uid == 0 else {
            Logger.debug("[SECURITY] Refusing to signal PID \(pid) owned by UID \(uid)", category: .security)
            return false
        }

        return sendPrivilegedSignal(signal, to: pid)
    }

    func sendLocalSignal(_ signal: Int32, to pid: Int32) -> Bool {
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProcess.arguments = ["-\(signal)", String(pid)]

        do {
            try killProcess.run()
            killProcess.waitUntilExit()
            return killProcess.terminationStatus == 0
        } catch {
            return false
        }
    }

    func sendPrivilegedSignal(_ signal: Int32, to pid: Int32) -> Bool {
        let command = "/bin/kill -\(signal) \(pid)"
        let script = """
        do shell script "\(command)" with administrator privileges
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }

        appleScript.executeAndReturnError(&error)
        if let error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown privileged kill error"
            Logger.debug("[SECURITY] Privileged kill failed for PID \(pid): \(errorMessage)", category: .security)
            return false
        }

        return true
    }

    // MARK: - Private Methods

    struct DeviceConnectionAvailability {
        let usbUDID: String?
        let networkUDID: String?
        let wifiBrowseUDID: String?
    }

}
