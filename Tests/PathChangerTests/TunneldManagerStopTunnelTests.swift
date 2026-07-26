//
//  TunneldManagerStopTunnelTests.swift
//  PathChangerTests
//
//  Stop-tunnel lifecycle and process-termination tests. Split out of
//  TunneldManagerTests.swift to keep each test file within the SwiftLint
//  file_length budget, mirroring how TunneldManager itself is split.
//

import XCTest
import Darwin
@testable import PathChanger

private final class CapturedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    func set(_ value: String) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

extension TunneldManagerTests {
    // MARK: - Stop Tunnel Tests

    func testStopTunnelWhenIdle() {
        // Should handle gracefully when already idle
        manager.stopTunnel()
        XCTAssertEqual(manager.state, .idle)
    }

#if DEBUG
    func testStopCancelsScheduledRecoveryAndInvalidatesGeneration() async throws {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: nil
        )

        manager.testSendTunnelEvent(.startRequested(mode: .usb))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        manager.testSendTunnelEvent(.healthCheckFailed)
        manager.testScheduleRecovery(after: 0.2)

        XCTAssertTrue(manager.testHasScheduledRecovery)
        let generationBeforeStop = manager.testTunnelLifecycleGeneration

        manager.stopTunnel()

        XCTAssertFalse(manager.testHasScheduledRecovery)
        XCTAssertGreaterThan(manager.testTunnelLifecycleGeneration, generationBeforeStop)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isStarting)
    }

    func testModeSwitchRestartTaskIsTrackedAndCanceledByStop() async throws {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: nil
        )

        manager.preferredMode = .usb
        manager.testSendTunnelEvent(.startRequested(mode: .usb))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))

        manager.preferredMode = .wifi
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(manager.testHasScheduledRestart)

        manager.stopTunnel()

        XCTAssertFalse(manager.testHasScheduledRestart)

        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isRunning)
    }

    func testRepeatedRecoverySchedulingIsCanceledByStop() async throws {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: nil
        )

        for _ in 0..<5 {
            manager.testResetTunnelLifecycleForTests()
            manager.testSendTunnelEvent(.startRequested(mode: .usb))
            manager.testSendTunnelEvent(.connectionEstablished(info: info))
            manager.testSendTunnelEvent(.healthCheckFailed)
            manager.testScheduleRecovery(after: 0.2)

            XCTAssertTrue(manager.testHasScheduledRecovery)
            let generationBeforeStop = manager.testTunnelLifecycleGeneration

            manager.stopTunnel()

            XCTAssertFalse(manager.testHasScheduledRecovery)
            XCTAssertGreaterThan(manager.testTunnelLifecycleGeneration, generationBeforeStop)

            try await Task.sleep(nanoseconds: 300_000_000)

            XCTAssertEqual(manager.state, .idle)
            XCTAssertFalse(manager.isStarting)
            XCTAssertFalse(manager.testHasScheduledRecovery)
        }
    }

    func testGetRsdInfoOnlyServesRunningTunnelInfo() {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: nil
        )

        XCTAssertNil(manager.getRsdInfo(for: "00008130-000C5144019A001C"))

        manager.testSendTunnelEvent(.startRequested(mode: .usb))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        XCTAssertEqual(manager.getRsdInfo(for: "00008130-000C5144019A001C"), info)

        manager.testSendTunnelEvent(.healthCheckFailed)
        XCTAssertNil(manager.getRsdInfo(for: "00008130-000C5144019A001C"))
    }

    func testDaemonModeConnectivityHealthyFromApiRsdWhenLogTunnelInfoMissing() {
        // Daemon mode keeps the live RSD in deviceTunnelInfo (from the tunneld
        // HTTP API); the legacy log-parsed `tunnelInfo` can be nil/stale. The
        // connectivity check must treat the tunnel as healthy when the daemon
        // process is alive AND the API RSD is usable — otherwise it falsely
        // flips to "Tunnel Required" while injection still works.
        let pid: Int32 = 7001
        manager.testSetProcessOverride(pid: pid, command: "/usr/bin/python3 -m pymobiledevice3 remote tunneld", uid: 0, state: "S")
        let info = TunnelInfo(rsdAddress: "fd00:dead:beef::1", rsdPort: 55041, mode: .daemon, interface: "usbmux-Network", processId: pid)
        manager.testSendTunnelEvent(.startRequested(mode: .daemon))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        manager.tunnelInfo = nil
        manager.deviceTunnelInfo = [testUDID: info]
        manager.testSetTrackedTunnelChildren([pid], mode: .daemon, targetUDID: testUDID)

        XCTAssertTrue(manager.currentTunnelConnectivityHealthy())
    }

    func testConnectivityUnhealthyWhenNoUsableRsd() {
        let info = TunnelInfo(rsdAddress: "fd00:dead:beef::1", rsdPort: 55041, mode: .daemon, interface: "usbmux-Network", processId: nil)
        manager.testSendTunnelEvent(.startRequested(mode: .daemon))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        manager.tunnelInfo = nil
        manager.deviceTunnelInfo = [:]

        XCTAssertFalse(manager.currentTunnelConnectivityHealthy())
    }

    func testConnectivityUnhealthyWhenTrackedDaemonProcessDead() {
        let pid: Int32 = 7002
        manager.testSetProcessOverride(pid: pid, command: "/usr/bin/python3 -m pymobiledevice3 remote tunneld", uid: 0, state: "Z")
        let info = TunnelInfo(rsdAddress: "fd00:dead:beef::1", rsdPort: 55041, mode: .daemon, interface: "usbmux-Network", processId: pid)
        manager.testSendTunnelEvent(.startRequested(mode: .daemon))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        manager.tunnelInfo = nil
        manager.deviceTunnelInfo = [testUDID: info]
        manager.testSetTrackedTunnelChildren([pid], mode: .daemon, targetUDID: testUDID)

        XCTAssertFalse(manager.currentTunnelConnectivityHealthy())
    }

    func testTransportFailureInvalidatesEndpointBeforeBridgeReuse() {
        let info = TunnelInfo(
            rsdAddress: "fe80::2",
            rsdPort: 58784,
            mode: .usb,
            interface: "en0",
            processId: nil
        )

        manager.testSendTunnelEvent(.startRequested(mode: .usb))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        XCTAssertNotNil(manager.getRsdInfo(for: "00008130-000C5144019A001C"))

        manager.invalidateActiveTunnelAfterTransportFailure("No route to host")

        XCTAssertNil(manager.getRsdInfo(for: "00008130-000C5144019A001C"))
        if case .error = manager.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected tunnel state to enter error after transport failure")
        }
    }

    func testZombieProcessStateIsTreatedAsDead() {
        XCTAssertTrue(TunneldManager.testIsZombieProcessState("Z+"))
        XCTAssertTrue(TunneldManager.testIsZombieProcessState("z"))
        XCTAssertTrue(TunneldManager.testIsZombieProcessState("SsZ"))
        XCTAssertFalse(TunneldManager.testIsZombieProcessState("S+"))
        XCTAssertFalse(TunneldManager.testIsZombieProcessState("R"))
    }

    func testSanctionedTunnelChildCommandRequiresExactTunnelSubcommand() {
        XCTAssertTrue(TunneldManager.testIsSanctionedTunnelChildCommand(
            usbTunnelCommand(udid: testUDID),
            mode: .usb,
            targetUDID: testUDID
        ))
        XCTAssertTrue(TunneldManager.testIsSanctionedTunnelChildCommand(
            wifiTunnelCommand(udid: testUDID),
            mode: .wifi,
            targetUDID: testUDID
        ))

        XCTAssertFalse(TunneldManager.testIsSanctionedTunnelChildCommand(
            "/Users/test/bin/python3 -m pymobiledevice3 usbmux list",
            mode: .usb,
            targetUDID: testUDID
        ))
        XCTAssertFalse(TunneldManager.testIsSanctionedTunnelChildCommand(
            usbTunnelCommand(),
            mode: .usb,
            targetUDID: testUDID
        ))
        XCTAssertTrue(TunneldManager.testIsSanctionedTunnelChildCommand(
            usbTunnelCommand(),
            mode: .usb,
            targetUDID: testUDID,
            requireTargetUDID: false
        ))
    }

    func testRecordLaunchedTunnelChildrenTracksOnlyNewTrueChildPids() {
        manager.testSetProcessOverride(pid: 4101, command: usbTunnelCommand(), state: "S")
        manager.testSetProcessOverride(pid: 4102, command: usbTunnelCommand(), state: "S")
        manager.testSetLiveProcessIds([4101, 4102], matching: TunnelMode.usb.processPattern)

        manager.testRecordLaunchedTunnelChildren(
            mode: .usb,
            targetUDID: nil,
            beforeLaunchPids: [4101]
        )

        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [4102])
    }

    func testDeterministicCleanupEscalatesAndVerifiesTrackedChildTermination() {
        let pid: Int32 = 4201
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetTrackedTunnelChildren([pid], mode: .usb, targetUDID: testUDID)
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(), state: "S")
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        manager.testRunTrackedTunnelCleanup()

        XCTAssertEqual(signals.map(\.pid), [pid, pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertTrue(manager.testTrackedTunnelChildProcessIds.isEmpty)
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testOrphanedLiveTunnelChildIsCleanedWhenItMatchesModeAndTarget() {
        let pid: Int32 = 4301
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetTrackedTunnelChildren([], mode: .usb, targetUDID: testUDID)
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), state: "S")
        manager.testSetLiveProcessIds([pid], matching: TunnelMode.usb.processPattern)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGTERM {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        XCTAssertEqual(manager.testCleanupCandidateProcessIds(mode: .usb, targetUDID: testUDID), [pid])
        manager.testRunTrackedTunnelCleanup()

        XCTAssertEqual(signals.map(\.pid), [pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testRootOwnedTrackedTunnelChildIsEligibleForValidatedCleanup() {
        let pid: Int32 = 4351
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetTrackedTunnelChildren([pid], mode: .usb, targetUDID: testUDID)
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(), uid: 0, state: "S")
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGTERM {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        XCTAssertEqual(manager.testCleanupCandidateProcessIds(mode: .usb, targetUDID: testUDID), [pid])
        manager.testRunTrackedTunnelCleanup()

        XCTAssertEqual(signals.map(\.pid), [pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testForcedTunnelDeathCleanupPrunesTrackedChildWithoutSignaling() {
        let pid: Int32 = 4401
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetTrackedTunnelChildren([pid], mode: .usb, targetUDID: testUDID)
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), state: nil)
        manager.testSetSignalHandler { pid, signal in
            signals.append((pid, signal))
            return true
        }

        manager.testRunTrackedTunnelCleanup()

        XCTAssertTrue(signals.isEmpty)
        XCTAssertTrue(manager.testTrackedTunnelChildProcessIds.isEmpty)
    }

    func testRepeatedRestartFailureCleanupDoesNotAccumulateTrackedChildren() {
        var signals: [(pid: Int32, signal: Int32)] = []

        for offset in 0..<8 {
            let pid = Int32(4500 + offset)
            manager.testSetTrackedTunnelChildren([pid], mode: .usb, targetUDID: nil)
            manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(), state: "S")
            manager.testSetSignalHandler { [weak manager] pid, signal in
                signals.append((pid, signal))
                if signal == SIGTERM {
                    manager?.testSetProcessState(pid: pid, state: nil)
                }
                return true
            }

            manager.testRunTrackedTunnelCleanup()

            XCTAssertTrue(manager.testTrackedTunnelChildProcessIds.isEmpty)
            XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
        }

        XCTAssertEqual(signals.count, 8)
        XCTAssertEqual(signals.map(\.signal), Array(repeating: SIGTERM, count: 8))
    }

    func testTunnelLifetimeMonitoringTreatsZombieTrackedChildAsDead() {
        let pid: Int32 = 4601
        manager.testSetTrackedTunnelChildren([pid], mode: .usb, targetUDID: nil)
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(), state: "Z+")

        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
        XCTAssertTrue(manager.testCleanupCandidateProcessIds(mode: .usb, targetUDID: nil).isEmpty)
    }

    func testStartupAcquisitionPollsUntilDelayedChildAndRsdAreReady() async throws {
        let pid: Int32 = 4701
        let info = TunnelInfo(
            rsdAddress: "fdbf:1ace:5d2d::1",
            rsdPort: 58044,
            mode: .usb,
            interface: "utun10",
            processId: pid
        )
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[], [], [pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([nil, nil, info])
        manager.testSetStartupTiming(timeout: 2.0, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: []
        )

        XCTAssertEqual(acquiredInfo, info)
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [pid])
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
    }

    func testStartupAcquisitionDoesNotReturnRsdBeforeChildOwnership() async throws {
        let pid: Int32 = 4702
        let info = TunnelInfo(
            rsdAddress: "fd2e:b3a3:3601::1",
            rsdPort: 58042,
            mode: .usb,
            interface: "utun13",
            processId: pid
        )
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[], [], [pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([info, info, info])
        manager.testSetStartupTiming(timeout: 0.5, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: []
        )

        XCTAssertEqual(acquiredInfo?.processId, pid)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
    }

    func testStartupFailureCleansValidatedChildWhenRsdNeverPublishes() async throws {
        let pid: Int32 = 4703
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[pid], [pid], [pid], [pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([nil, nil, nil, nil])
        manager.testSetStartupTiming(timeout: 0.05, pollInterval: 0.01)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: []
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(signals.map(\.pid), [pid, pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testStartupHandoffAdoptsValidatedPid() async throws {
        let pid: Int32 = 4704
        let info = TunnelInfo(
            rsdAddress: "fd54:8f4d:42c7::1",
            rsdPort: 58053,
            mode: .usb,
            interface: "utun10",
            processId: pid
        )
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[], [], []], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([info])
        manager.testSetStartupTiming(timeout: 2.0, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertEqual(acquiredInfo, info)
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [pid])
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])

        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.getRsdInfo(for: testUDID), info)
    }

    func testStartupHandoffWaitsForTransientPidVisibilityBeforeAdoption() async throws {
        let pid: Int32 = 4713
        let info = TunnelInfo(
            rsdAddress: "fd54:8f4d:42c7::2",
            rsdPort: 58054,
            mode: .usb,
            interface: "utun11",
            processId: pid
        )
        manager.testSetProcessState(pid: pid, state: nil)
        manager.testSetStartupRsdInfoSequence([info])
        manager.testSetStartupTiming(timeout: 2.0, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        Task { @MainActor [weak manager] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            manager?.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "R")
        }

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertEqual(acquiredInfo, info)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [pid])
    }

    func testStartupHandoffWaitsForDelayedNonZombieTransitionBeforeAdoption() async throws {
        let pid: Int32 = 4714
        let info = TunnelInfo(
            rsdAddress: "fd54:8f4d:42c7::3",
            rsdPort: 58055,
            mode: .usb,
            interface: "utun12",
            processId: pid
        )
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "Z")
        manager.testSetStartupRsdInfoSequence([info])
        manager.testSetStartupTiming(timeout: 0.2, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        Task { @MainActor [weak manager] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            manager?.testSetProcessState(pid: pid, state: "S")
        }

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertEqual(acquiredInfo, info)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
    }

    func testStartupHandoffTreatsRootOwnedPermissionProbeAsLiveWhenStateIsQueryable() async throws {
        let pid: Int32 = 4715
        let info = TunnelInfo(
            rsdAddress: "fd54:8f4d:42c7::4",
            rsdPort: 58056,
            mode: .usb,
            interface: "utun13",
            processId: pid
        )
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "R")
        manager.testSetKillZeroResult(pid: pid, result: .permissionDenied)
        manager.testSetStartupRsdInfoSequence([info])
        manager.testSetStartupTiming(timeout: 0.2, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertEqual(acquiredInfo, info)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
    }

    func testStartupFailureCleansHandedOffPidThatStabilizesAfterInitialRejection() async throws {
        let pid: Int32 = 4716
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetProcessState(pid: pid, state: nil)
        manager.testSetStartupRsdInfoSequence([nil, nil, nil, nil, nil])
        manager.testSetStartupTiming(timeout: 0.12, pollInterval: 0.01)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        Task { @MainActor [weak manager] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            manager?.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        }

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(signals.map(\.pid), [pid, pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testStartupHandoffTimesOutDuringStabilizationWithoutAdoption() async throws {
        let pid: Int32 = 4717
        manager.testSetProcessState(pid: pid, state: nil)
        manager.testSetStartupRsdInfoSequence([])
        manager.testSetStartupTiming(timeout: 0.04, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [])
    }

    func testStartupHandoffRejectsInvalidPidAfterStabilizationWindow() async throws {
        let pid: Int32 = 4718
        manager.testSetProcessOverride(pid: pid, command: "\(PythonPathResolver.path) -m pymobiledevice3 developer dvt simulate-location", uid: 0, state: "S")
        manager.testSetStartupRsdInfoSequence([])
        manager.testSetStartupTiming(timeout: 0.08, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [])
    }

    func testStartupHandoffRejectsInvalidUnrelatedPid() async throws {
        let pid: Int32 = 4705
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetProcessOverride(pid: pid, command: "\(PythonPathResolver.path) -m pymobiledevice3 developer dvt simulate-location", uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[pid], [pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([])
        manager.testSetStartupTiming(timeout: 0.02, pollInterval: 0.01)
        manager.testSetSignalHandler { pid, signal in
            signals.append((pid, signal))
            return true
        }

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [])
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
        XCTAssertTrue(signals.isEmpty)
    }

    func testStartupHandoffRejectsWrapperPid() async throws {
        let pid: Int32 = 4706
        manager.testSetProcessOverride(pid: pid, command: "/usr/bin/osascript -e do shell script", uid: getuid(), state: "S+")
        manager.testSetLiveProcessIdSequence([[pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([])
        manager.testSetStartupTiming(timeout: 0.02, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
    }

    func testStartupHandoffRejectsStalePidReuse() async throws {
        let pid: Int32 = 4707
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([])
        manager.testSetStartupTiming(timeout: 0.02, pollInterval: 0.01)

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [pid],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
    }

    func testStartupFailureCleansValidatedHandedOffPidWhenRsdNeverPublishes() async throws {
        let pid: Int32 = 4708
        var signals: [(pid: Int32, signal: Int32)] = []
        manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[pid], [pid], [pid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([nil, nil, nil, nil])
        manager.testSetStartupTiming(timeout: 0.04, pollInterval: 0.01)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [],
            handedOffPid: pid
        )

        XCTAssertNil(acquiredInfo)
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
        XCTAssertEqual(signals.map(\.pid), [pid, pid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: pid))
    }

    func testRepeatedRestartCycleUsesOnlyCurrentHandedOffPid() async throws {
        for offset in 0..<3 {
            manager.testResetTunnelLifecycleForTests()
            let pid = Int32(4710 + offset)
            let info = TunnelInfo(
                rsdAddress: "fd99:beef:\(offset)::1",
                rsdPort: 58060 + offset,
                mode: .usb,
                interface: "utun\(offset)",
                processId: pid
            )
            manager.testSetProcessOverride(pid: pid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
            manager.testSetLiveProcessIdSequence([[], []], matching: TunnelMode.usb.processPattern)
            manager.testSetStartupRsdInfoSequence([info])
            manager.testSetStartupTiming(timeout: 2.0, pollInterval: 0.01)
            manager.testSendTunnelEvent(.startRequested(mode: .usb))

            let acquiredInfo = await manager.testWaitForAuthoritativeStartup(
                mode: .usb,
                targetUDID: testUDID,
                beforeLaunchPids: [],
                handedOffPid: pid
            )

            XCTAssertEqual(acquiredInfo, info)
            XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [pid])
            XCTAssertEqual(manager.testActiveTunnelProcessIds, [pid])
        }
    }

    func testWrapperReturnTimeoutClassifiesFailureAndCleansOnlyLaunchScopedDelta() async throws {
        let stalePid: Int32 = 6501
        let stalledChildPid: Int32 = 6502
        let wrongUDIDPid: Int32 = 6503
        let wrongModePid: Int32 = 6504
        var signals: [(pid: Int32, signal: Int32)] = []

        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetWrapperReturnTimeout(0.02)
        manager.testSetPrivilegedWrapperRunner { _ in
            .timedOut
        }
        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let success = await manager.testAttemptStart(mode: .usb)
        XCTAssertFalse(success)
        XCTAssertTrue(manager.lastError?.contains("wrapper did not return") == true)

        manager.testSendTunnelEvent(.errorOccurred(manager.lastError ?? "wrapper timeout"))
        if case .error(let message) = manager.state {
            XCTAssertTrue(message.contains("wrapper did not return"))
        } else {
            XCTFail("Expected wrapper-stall startup to converge to error state")
        }
        XCTAssertFalse(manager.isStarting)

        manager.testResetTunnelLifecycleForTests()
        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetProcessOverride(pid: stalePid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetProcessOverride(pid: stalledChildPid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetProcessOverride(pid: wrongUDIDPid, command: usbTunnelCommand(udid: "00008130000C5144019A9999"), uid: 0, state: "S")
        manager.testSetProcessOverride(pid: wrongModePid, command: wifiTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIds([stalePid, stalledChildPid, wrongUDIDPid, wrongModePid], matching: TunnelMode.usb.processPattern)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        manager.testFinalizeWrapperReturnTimeout(
            mode: .usb,
            targetUDID: testUDID,
            beforeLaunchPids: [stalePid],
            timeout: 0.02
        )
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [])
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
        XCTAssertEqual(signals.map(\.pid), [stalledChildPid, stalledChildPid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertFalse(signals.contains { $0.pid == stalePid })
        XCTAssertFalse(signals.contains { $0.pid == wrongUDIDPid })
        XCTAssertFalse(signals.contains { $0.pid == wrongModePid })
    }

    func testRestartCycleWrapperStallCleanupUsesOnlyCurrentLaunchDelta() async throws {
        var signals: [(pid: Int32, signal: Int32)] = []

        for offset in 0..<2 {
            manager.testResetTunnelLifecycleForTests()
            manager.testSetTargetTunnelUDID(testUDID)
            manager.testSetWrapperReturnTimeout(0.02)
            let stalePid = Int32(6600 + offset)
            let stalledChildPid = Int32(6610 + offset)
            manager.testSetProcessOverride(pid: stalePid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
            manager.testSetProcessOverride(pid: stalledChildPid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
            manager.testSetLiveProcessIds([stalePid, stalledChildPid], matching: TunnelMode.usb.processPattern)
            manager.testSetSignalHandler { [weak manager] pid, signal in
                signals.append((pid, signal))
                if signal == SIGKILL {
                    manager?.testSetProcessState(pid: pid, state: nil)
                }
                return true
            }

            manager.testSendTunnelEvent(.startRequested(mode: .usb))

            manager.testFinalizeWrapperReturnTimeout(
                mode: .usb,
                targetUDID: testUDID,
                beforeLaunchPids: [stalePid],
                timeout: 0.02
            )
            XCTAssertTrue(manager.lastError?.contains("wrapper did not return") == true)
            XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [])
            XCTAssertEqual(manager.testActiveTunnelProcessIds, [])
        }

        XCTAssertEqual(signals.map(\.pid), [6610, 6610, 6611, 6611])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL, SIGTERM, SIGKILL])
    }

    func testReturnedWrapperPidRemainsSoleAuthoritativeHandoffPath() async throws {
        let handedOffPid: Int32 = 6701
        let discoveryOnlyPid: Int32 = 6702
        let info = TunnelInfo(
            rsdAddress: "fd54:8f4d:42c7::10",
            rsdPort: 58100,
            mode: .usb,
            interface: "utun14",
            processId: handedOffPid
        )

        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetWrapperReturnTimeout(0.2)
        manager.testSetPrivilegedWrapperRunner { _ in
            .returned(output: "\(handedOffPid)\n", returnTime: Date().timeIntervalSince1970)
        }
        manager.testSetProcessOverride(pid: handedOffPid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetProcessOverride(pid: discoveryOnlyPid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence(
            [
                [],
                [handedOffPid, discoveryOnlyPid]
            ],
            matching: TunnelMode.usb.processPattern
        )
        manager.testSetStartupRsdInfoSequence([info])

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let success = await manager.testAttemptStart(mode: .usb)
        XCTAssertTrue(success)
        XCTAssertEqual(manager.tunnelInfo, info)
        XCTAssertEqual(manager.testTrackedTunnelChildProcessIds, [handedOffPid])
        XCTAssertEqual(manager.testActiveTunnelProcessIds, [handedOffPid])
        XCTAssertFalse(manager.testTrackedTunnelChildProcessIds.contains(discoveryOnlyPid))
        XCTAssertFalse(manager.testActiveTunnelProcessIds.contains(discoveryOnlyPid))
    }

    func testUSBAttemptStartUsesScriptModeLockdownCommand() async throws {
        let handedOffPid: Int32 = 6751
        let capturedScript = CapturedStringBox()
        let info = TunnelInfo(
            rsdAddress: "fd14:d8b0:f31e::1",
            rsdPort: 52064,
            mode: .usb,
            interface: "utun10",
            processId: handedOffPid
        )

        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetWrapperReturnTimeout(0.2)
        manager.testSetPrivilegedWrapperRunner { script in
            capturedScript.set(script)
            return .returned(output: "\(handedOffPid)\n", returnTime: Date().timeIntervalSince1970)
        }
        manager.testSetProcessOverride(pid: handedOffPid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIdSequence([[], [handedOffPid]], matching: TunnelMode.usb.processPattern)
        manager.testSetStartupRsdInfoSequence([info])

        manager.testSendTunnelEvent(.startRequested(mode: .usb))

        let success = await manager.testAttemptStart(mode: .usb)

        XCTAssertTrue(success)
        XCTAssertTrue(capturedScript.value?.contains("lockdown start-tunnel --script-mode --udid \(testUDID)") == true)
        XCTAssertEqual(manager.tunnelInfo?.rsdAddress, "fd14:d8b0:f31e::1")
        XCTAssertEqual(manager.tunnelInfo?.rsdPort, 52064)
    }

    func testNormalAttachRemainsFailClosedWhenExistingTunnelHasNoRecoverableRsd() async throws {
        let stalePid: Int32 = 6801
        var signals: [(pid: Int32, signal: Int32)] = []

        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetProcessOverride(pid: stalePid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIds([stalePid], matching: TunnelMode.usb.processPattern)
        manager.testSetSignalHandler { pid, signal in
            signals.append((pid, signal))
            return true
        }

        let attached = await manager.testAttachToRunningTunnelIfAvailable(replaceStaleOnMissingRsd: false)

        XCTAssertTrue(attached)
        XCTAssertTrue(manager.lastError?.contains("could not read its RSD address") == true)
        XCTAssertTrue(signals.isEmpty)
        XCTAssertTrue(manager.isTunnelProcessAlive(pid: stalePid))
    }

    func testRecoveryAttachCleansStaleTunnelWhenRsdCannotBeRecovered() async throws {
        let stalePid: Int32 = 6802
        var signals: [(pid: Int32, signal: Int32)] = []

        manager.testSetTargetTunnelUDID(testUDID)
        manager.testSetProcessOverride(pid: stalePid, command: usbTunnelCommand(udid: testUDID), uid: 0, state: "S")
        manager.testSetLiveProcessIds([stalePid], matching: TunnelMode.usb.processPattern)
        manager.testSetSignalHandler { [weak manager] pid, signal in
            signals.append((pid, signal))
            if signal == SIGKILL {
                manager?.testSetProcessState(pid: pid, state: nil)
            }
            return true
        }

        let attached = await manager.testAttachToRunningTunnelIfAvailable(replaceStaleOnMissingRsd: true)

        XCTAssertFalse(attached)
        XCTAssertEqual(signals.map(\.pid), [stalePid, stalePid])
        XCTAssertEqual(signals.map(\.signal), [SIGTERM, SIGKILL])
        XCTAssertFalse(manager.isTunnelProcessAlive(pid: stalePid))
        XCTAssertNil(manager.lastError)
    }
#endif

}
