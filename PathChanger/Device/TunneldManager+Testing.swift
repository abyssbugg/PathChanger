//
//  TunneldManager+Testing.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

#if DEBUG
@MainActor
extension TunneldManager {
    var testTunnelLifecycleGeneration: UInt64 {
        tunnelLifecycleGeneration
    }

    var testHasScheduledRecovery: Bool {
        recoveryTask != nil
    }

    var testHasScheduledRestart: Bool {
        restartTask != nil
    }

    func testResetTunnelLifecycleForTests() {
        recoveryTask?.cancel()
        recoveryTask = nil
        restartTask?.cancel()
        restartTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        healthMonitor.stopMonitoring()
        cleanupTunnelProcessResources(terminateProcess: true)
        stateMachine.testModeEnabled = true
        stateMachine.reset()
        syncStateWithStateMachine()
        tunnelStartInFlight = false
        tunnelLifecycleGeneration &+= 1
        trackedTunnelChildProcessIds.removeAll()
        lastTunnelModeForCleanup = nil
        lastTunnelTargetUDIDForCleanup = nil
        targetTunnelUDID = nil
        targetTunnelConnectionType = nil
        targetTunnelIOSMajorVersion = nil
        debugProcessCommandOverrides.removeAll()
        debugProcessUIDOverrides.removeAll()
        debugProcessStateOverrides.removeAll()
        debugKillZeroResultOverrides.removeAll()
        debugLiveProcessIdsOverrides.removeAll()
        debugLiveProcessIdsSequenceOverrides.removeAll()
        debugStartupRsdInfoSequence.removeAll()
        debugUsesStartupRsdInfoSequence = false
        debugStartupTimeoutOverride = nil
        debugStartupPollIntervalOverride = nil
        debugWrapperReturnTimeoutOverride = nil
        debugRecoveredRsdInfoFromLogOverride = nil
        debugRecoveredRsdInfoFromLogOverrideEnabled = false
        debugPrivilegedWrapperRunner = nil
        debugSignalHandler = nil
        let wasLoadingPreferredModeFromDefaults = isLoadingPreferredModeFromDefaults
        isLoadingPreferredModeFromDefaults = true
        preferredMode = .auto
        isLoadingPreferredModeFromDefaults = wasLoadingPreferredModeFromDefaults
    }

    @discardableResult
    func testSendTunnelEvent(_ event: TunnelEvent) -> TransitionResult {
        stateMachine.testModeEnabled = true
        let result = stateMachine.send(event)
        syncStateWithStateMachine()
        return result
    }

    func testScheduleRecovery(after delay: TimeInterval) {
        scheduleRecovery(after: delay)
    }

    var testTrackedTunnelChildProcessIds: Set<Int32> {
        trackedTunnelChildProcessIds
    }

    func testSetTrackedTunnelChildren(_ pids: Set<Int32>, mode: TunnelMode?, targetUDID: String?) {
        trackedTunnelChildProcessIds = pids
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID
    }

    func testSetProcessOverride(pid: Int32, command: String, uid: uid_t = getuid(), state: String? = "S") {
        debugProcessCommandOverrides[pid] = command
        debugProcessUIDOverrides[pid] = uid
        debugProcessStateOverrides.updateValue(state, forKey: pid)
    }

    func testSetProcessState(pid: Int32, state: String?) {
        debugProcessStateOverrides.updateValue(state, forKey: pid)
    }

    func testSetKillZeroResult(pid: Int32, result: TestKillZeroResult) {
        debugKillZeroResultOverrides[pid] = result
    }

    func testSetLiveProcessIds(_ pids: [Int32], matching pattern: String) {
        debugLiveProcessIdsOverrides[pattern] = pids
    }

    func testSetLiveProcessIdSequence(_ sequence: [[Int32]], matching pattern: String) {
        debugLiveProcessIdsSequenceOverrides[pattern] = sequence
    }

    func testSetStartupRsdInfoSequence(_ sequence: [TunnelInfo?]) {
        debugStartupRsdInfoSequence = sequence
        debugUsesStartupRsdInfoSequence = true
    }

    func testSetStartupTiming(
        timeout: TimeInterval?,
        pollInterval: TimeInterval?
    ) {
        debugStartupTimeoutOverride = timeout
        debugStartupPollIntervalOverride = pollInterval
    }

    func testSetWrapperReturnTimeout(_ timeout: TimeInterval?) {
        debugWrapperReturnTimeoutOverride = timeout
    }

    func testSetRecoveredRsdInfoFromLog(_ info: TunnelInfo?) {
        debugRecoveredRsdInfoFromLogOverride = info
        debugRecoveredRsdInfoFromLogOverrideEnabled = true
    }

    func testSetPrivilegedWrapperRunner(_ runner: (@Sendable (String) -> PrivilegedWrapperExecutionResult)?) {
        debugPrivilegedWrapperRunner = runner
    }

    func testSetTargetTunnelUDID(_ udid: String?) {
        targetTunnelUDID = udid
    }

    func testAttemptStart(mode: TunnelMode) async -> Bool {
        await attemptStart(mode: mode)
    }

    func testAttachToRunningTunnelIfAvailable(replaceStaleOnMissingRsd: Bool) async -> Bool {
        let generation = tunnelLifecycleGeneration
        return await attachToRunningTunnelIfAvailable(
            generation: generation,
            replaceStaleOnMissingRsd: replaceStaleOnMissingRsd
        )
    }

    func testFinalizeWrapperReturnTimeout(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        timeout: TimeInterval
    ) {
        finalizeWrapperReturnTimeout(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: tunnelLifecycleGeneration,
            timeout: timeout
        )
    }

    var testActiveTunnelProcessIds: Set<Int32> {
        stateMachine.currentContext.activeProcessIds
    }

    func testWaitForAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        handedOffPid: Int32? = nil
    ) async -> TunnelInfo? {
        await waitForAuthoritativeStartup(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: tunnelLifecycleGeneration,
            handedOffPid: handedOffPid
        )
    }

    func testSetSignalHandler(_ handler: (@MainActor (Int32, Int32) -> Bool)?) {
        debugSignalHandler = handler
    }

    func testCleanupCandidateProcessIds(mode: TunnelMode?, targetUDID: String?) -> [Int32] {
        cleanupCandidateProcessIds(mode: mode, targetUDID: targetUDID)
    }

    func testRecordLaunchedTunnelChildren(mode: TunnelMode, targetUDID: String?, beforeLaunchPids: Set<Int32>) {
        recordLaunchedTunnelChildren(mode: mode, targetUDID: targetUDID, beforeLaunchPids: beforeLaunchPids)
    }

    func testRunTrackedTunnelCleanup() {
        killTrackedTunnelProcesses()
    }

    nonisolated static func testIsZombieProcessState(_ state: String) -> Bool {
        isZombieProcessState(state)
    }

    nonisolated static func testIsSanctionedTunnelChildCommand(
        _ command: String,
        mode: TunnelMode,
        targetUDID: String?,
        requireTargetUDID: Bool = true
    ) -> Bool {
        isSanctionedTunnelChildCommand(
            command,
            mode: mode,
            targetUDID: targetUDID,
            requireTargetUDID: requireTargetUDID
        )
    }
}
#endif