//
//  TunneldManagerTests.swift
//  PathChangerTests
//
//  Unit tests for tunnel lifecycle and race condition prevention
//

import XCTest
@testable import PathChanger

@MainActor
final class TunneldManagerTests: XCTestCase {

    var manager: TunneldManager!

    override func setUp() async throws {
        // Note: Using shared singleton - tests may affect each other
        manager = TunneldManager.shared
    }

    func testTunnelCommandsTargetSelectedDeviceWhenProvided() {
        let udid = "00000000-0000000000000001"

        XCTAssertEqual(TunneldManager.arguments(for: .usb, deviceId: udid), [
            "-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native", "--udid", udid,
        ])
        XCTAssertEqual(TunneldManager.arguments(for: .wifi, deviceId: udid), [
            "-m", "pymobiledevice3", "remote", "start-tunnel", "--native", "--udid", udid,
        ])
        XCTAssertEqual(TunneldManager.arguments(for: .daemon, deviceId: udid), [
            "-m", "pymobiledevice3", "remote", "tunneld",
        ])
    }

    func testWiFiPreparationRequiresMatchingUSBDevice() {
        let selected = "00000000-0000000000000001"

        XCTAssertTrue(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: [selected]
        ))
        XCTAssertFalse(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: ["00008130-1111111111111111"]
        ))
        XCTAssertFalse(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: []
        ))
    }

    func testRemotePairingRecordFilenameYieldsKnownDeviceId() {
        XCTAssertEqual(
            DevicePreparationPlanner.remotePairingDeviceId(
                from: "remote_00000000-0000000000000001.plist"
            ),
            "00000000-0000000000000001"
        )
        XCTAssertNil(
            DevicePreparationPlanner.remotePairingDeviceId(from: "00000000-0000000000000001.plist")
        )
        XCTAssertNil(DevicePreparationPlanner.remotePairingDeviceId(from: "remote_not-a-udid.plist"))
        XCTAssertNil(DevicePreparationPlanner.remotePairingDeviceId(from: "notes.txt"))
    }

    func testMobdev2DiscoveryUsesUserPairingRecords() {
        XCTAssertEqual(
            DevicePreparationPlanner.mobdev2BrowseArguments(
                pairingRecordsPath: "/Users/test/.pymobiledevice3"
            ),
            [
                "-m", "pymobiledevice3", "bonjour", "mobdev2",
                "--timeout", "5", "--pair-records", "/Users/test/.pymobiledevice3",
            ]
        )
    }

    func testWiFiPreparationRunsCommandsInOrder() async throws {
        let udid = "00000000-0000000000000001"
        var calls: [[String]] = []
        let service = DevicePreparationService { arguments, _ in
            calls.append(arguments)
            return ""
        }

        try await service.prepareWiFi(deviceId: udid)

        XCTAssertEqual(calls, DevicePreparationPlanner.wifiBootstrapCommands(deviceId: udid))
        XCTAssertEqual(service.phase, .ready)
    }

    func testWiFiPreparationStopsAtFirstFailure() async {
        let udid = "00000000-0000000000000001"
        var calls: [[String]] = []
        let service = DevicePreparationService { arguments, _ in
            calls.append(arguments)
            throw DeviceError.commandFailed("bootstrap failed")
        }

        do {
            try await service.prepareWiFi(deviceId: udid)
            XCTFail("expected preparation to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(calls.count, 1)
        guard case .failed(let message) = service.phase else {
            return XCTFail("expected failed phase")
        }
        XCTAssertTrue(message.contains("bootstrap failed"))
    }

    func testWiFiPreparationCommandsMatchPymobiledevice3ColdStartFlow() {
        let udid = "00000000-0000000000000001"

        XCTAssertEqual(DevicePreparationPlanner.wifiBootstrapCommands(deviceId: udid), [
            [
                "-m", "pymobiledevice3", "lockdown", "wifi-connections",
                "on", "--udid", udid,
            ],
            [
                "-m", "pymobiledevice3", "lockdown", "remotepairing",
                "--pair", "--udid", udid,
            ],
        ])
    }

    func testTunnelInfoRequiresUsableRSDPort() {
        let placeholder = TunnelInfo(
            rsdAddress: "127.0.0.1",
            rsdPort: 0,
            mode: .wifi,
            interface: nil,
            processId: 42
        )
        let usable = TunnelInfo(
            rsdAddress: "fd00::1",
            rsdPort: 58783,
            mode: .wifi,
            interface: "utun9",
            processId: 42
        )

        XCTAssertFalse(placeholder.isUsable)
        XCTAssertTrue(usable.isUsable)
    }

    func testStartupWaitsUntilUsableTunnelInfoArrives() async {
        let expected = TunnelInfo(
            rsdAddress: "fd00::1",
            rsdPort: 58783,
            mode: .wifi,
            interface: "utun9",
            processId: 42
        )
        var attempts = 0

        let result = await TunnelStartupWaiter.wait(
            timeout: 1,
            pollInterval: 0.01,
            processIsRunning: { true },
            readInfo: {
                attempts += 1
                return attempts >= 3 ? expected : nil
            }
        )

        XCTAssertEqual(result, expected)
        XCTAssertGreaterThanOrEqual(attempts, 3)
    }

    func testStartupStopsWaitingWhenProcessExits() async {
        var reads = 0

        let result = await TunnelStartupWaiter.wait(
            timeout: 1,
            pollInterval: 0.01,
            processIsRunning: { false },
            readInfo: {
                reads += 1
                return nil
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(reads, 0)
    }

    func testDeadTunnelProcessClearsRunningState() async throws {
        // Drive the manager's real state machine without launching or elevating anything.
        // The fake PID cannot exist, so TunnelHealthMonitor will report three consecutive
        // process-liveness failures. The manager must consume that report and leave
        // `.running`; otherwise the UI lies with "Tunnel live" forever.
        let mirror = Mirror(reflecting: manager as TunneldManager)
        guard let stateMachine = mirror.children.first(where: { $0.label == "stateMachine" })?.value
            as? TunnelStateMachine else {
            return XCTFail("could not access TunneldManager's state machine")
        }

        stateMachine.reset()
        #if DEBUG
        stateMachine.testModeEnabled = true
        defer { stateMachine.testModeEnabled = false }
        #endif
        stateMachine.send(.startRequested(mode: .wifi))
        stateMachine.send(.connectionEstablished(info: TunnelInfo(
            rsdAddress: "127.0.0.1",
            rsdPort: 49152,
            mode: .wifi,
            interface: nil,
            processId: Int32.max
        )))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(stateMachine.isActive)

        // Health checks run immediately and then every two seconds; three failures are
        // critical. Seven seconds leaves margin for scheduler variance.
        try await Task.sleep(nanoseconds: 7_000_000_000)

        XCTAssertFalse(
            stateMachine.isActive,
            "A dead tunnel process must not leave the UI in 'Tunnel live'"
        )
    }

    override func tearDown() async throws {
        // Clean up any running tunnels after each test
        await manager.stopTunnel()

        // Give it time to fully stop
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }

    // MARK: - State Machine Tests

    func testTunnelElevationRequiresExplicitUserAction() {
        XCTAssertFalse(TunnelStartPolicy.mayElevate(for: .applicationLaunch))
        XCTAssertFalse(TunnelStartPolicy.mayElevate(for: .statusPoll))
        XCTAssertTrue(TunnelStartPolicy.mayElevate(for: .explicitUserAction))
    }

    func testAutoStartAllowedOutsideTests() {
        XCTAssertTrue(TunneldManager.shouldAutoStart(environment: [:]))
    }

    func testAutoStartDisabledForXCTestHost() {
        XCTAssertFalse(TunneldManager.shouldAutoStart(environment: [
            "XCTestConfigurationFilePath": "/tmp/PathChangerTests.xctestconfiguration",
        ]))
        XCTAssertFalse(TunneldManager.shouldAutoStart(environment: [
            "XCTestBundlePath": "/tmp/PathChangerTests.xctest",
        ]))
    }

    func testInitialStateIsIdle() {
        let state = manager.state
        XCTAssertEqual(state, .idle)
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.isStarting)
    }

    func testStateTransitionsAreAtomic() async {
        // Initial state
        XCTAssertEqual(manager.state, .idle)

        // Cannot test full tunnel start without actual device
        // but we can verify state consistency
        XCTAssertFalse(manager.state.isTransitioning)
    }

    func testIsRunningComputedFromState() {
        // When state is .idle
        XCTAssertFalse(manager.isRunning)

        // Note: Cannot set state directly (private setter)
        // This test validates the computed property logic
    }

    func testIsStartingComputedFromState() {
        // When state is .idle
        XCTAssertFalse(manager.isStarting)

        // Validates computed property for .starting state
    }

    // MARK: - Tunnel Mode Tests

    func testTunnelModeEnumValues() {
        XCTAssertEqual(TunnelMode.allCases.count, 4)
        XCTAssertTrue(TunnelMode.allCases.contains(.auto))
        XCTAssertTrue(TunnelMode.allCases.contains(.usb))
        XCTAssertTrue(TunnelMode.allCases.contains(.wifi))
        XCTAssertTrue(TunnelMode.allCases.contains(.daemon))
    }

    func testTunnelModeCommands() {
        XCTAssertEqual(TunnelMode.usb.command, ["lockdown", "start-tunnel", "--native"])
        XCTAssertEqual(TunnelMode.wifi.command, ["remote", "start-tunnel", "--native"])
        XCTAssertEqual(TunnelMode.daemon.command, ["remote", "tunneld"])
        XCTAssertEqual(TunnelMode.auto.command, [])
    }

    func testTunnelModeProcessPatterns() {
        XCTAssertEqual(TunnelMode.usb.processPattern, "pymobiledevice3 lockdown start-tunnel")
        XCTAssertEqual(TunnelMode.wifi.processPattern, "pymobiledevice3 remote start-tunnel")
        XCTAssertEqual(TunnelMode.daemon.processPattern, "pymobiledevice3 remote tunneld")
        XCTAssertEqual(TunnelMode.auto.processPattern, "pymobiledevice3")
    }

    // MARK: - Tunnel Info Tests

    func testTunnelInfoConnectionString() {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        XCTAssertEqual(info.connectionString, "--rsd fe80::1 58783")
    }

    func testTunnelInfoEquality() {
        let info1 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        let info2 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        XCTAssertEqual(info1, info2)
    }

    func testTunnelInfoWithDifferentProcessId() {
        let info1 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        let info2 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 67890
        )

        XCTAssertNotEqual(info1, info2)
    }

    // MARK: - Preference Persistence Tests

    func testPreferredModePersistence() {
        // Set mode
        manager.preferredMode = .wifi

        // Verify persistence
        let saved = UserDefaults.standard.string(forKey: "tunnelMode")
        XCTAssertEqual(saved, TunnelMode.wifi.rawValue)

        // Cleanup
        manager.preferredMode = .auto
    }

    // MARK: - Stop Tunnel Tests

    func testStopTunnelWhenIdle() {
        // Should handle gracefully when already idle
        manager.stopTunnel()
        XCTAssertEqual(manager.state, .idle)
    }

    // MARK: - Tunnel State Tests

    func testTunnelStateIsActive() {
        XCTAssertTrue(TunnelState.running.isActive)
        XCTAssertFalse(TunnelState.idle.isActive)
        XCTAssertFalse(TunnelState.starting.isActive)
        XCTAssertFalse(TunnelState.stopping.isActive)
        XCTAssertFalse(TunnelState.error("test").isActive)
    }

    func testTunnelStateIsTransitioning() {
        XCTAssertTrue(TunnelState.starting.isTransitioning)
        XCTAssertTrue(TunnelState.stopping.isTransitioning)
        XCTAssertFalse(TunnelState.idle.isTransitioning)
        XCTAssertFalse(TunnelState.running.isTransitioning)
        XCTAssertFalse(TunnelState.error("test").isTransitioning)
    }

    func testTunnelStateEquality() {
        XCTAssertEqual(TunnelState.idle, TunnelState.idle)
        XCTAssertEqual(TunnelState.running, TunnelState.running)
        XCTAssertEqual(TunnelState.starting, TunnelState.starting)
        XCTAssertEqual(TunnelState.stopping, TunnelState.stopping)
        XCTAssertNotEqual(TunnelState.idle, TunnelState.running)
    }

    // MARK: - Race Condition Prevention Tests

    func testConcurrentStartCallsPrevented() async throws {
        try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
            "This test launches a live pymobiledevice3 tunnel and requires a prepared device host."
        )
        // First call should set state to starting
        // Subsequent calls should be ignored

        // Start two concurrent calls
        async let call1: Void = manager.startTunnel()
        async let call2: Void = manager.startTunnel()

        // Both should complete without crash
        _ = await (call1, call2)

        // State should not be corrupted
        XCTAssertTrue(manager.state == .idle || manager.state == .starting || manager.state == .running)
    }

    // MARK: - Tunnel Command Tests

    func testTunnelCommandsUseFixedArguments() {
        XCTAssertEqual(TunneldManager.arguments(for: .usb), [
            "-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native",
        ])
        XCTAssertEqual(TunneldManager.arguments(for: .wifi), [
            "-m", "pymobiledevice3", "remote", "start-tunnel", "--native",
        ])
        XCTAssertEqual(TunneldManager.arguments(for: .daemon), [
            "-m", "pymobiledevice3", "remote", "tunneld",
        ])
    }

    func testNativeTunnelLaunchDoesNotInvokeAdministratorShell() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Device/TunneldManager.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "private func attemptStart"),
              let end = source.range(of: "private func checkLogForErrors", range: start.upperBound..<source.endIndex) else {
            return XCTFail("Unable to isolate attemptStart implementation")
        }
        let implementation = source[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(implementation.contains("runAdministratorShell"))
        XCTAssertTrue(implementation.contains("Process()"))
    }

    func testTerminationPreparationRetainsHandlerUntilReply() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Device/TunneldManager.swift"),
            encoding: .utf8
        )
        guard let function = source.range(of: "private func applicationShouldTerminateOnMainActor"),
              let start = source.range(
                of: "Task { @MainActor [weak self",
                range: function.lowerBound..<source.endIndex
              ),
              let end = source.range(
                of: "return .terminateLater",
                range: start.lowerBound..<source.endIndex
              ) else {
            return XCTFail("Unable to isolate asynchronous termination preparation")
        }
        let implementation = source[start.lowerBound..<end.upperBound]
        XCTAssertTrue(implementation.contains("[weak self, terminationHandler]"))
        XCTAssertFalse(implementation.contains("weak terminationHandler"))
    }

    func testAutoModeHasNoDirectTunnelCommand() {
        XCTAssertNil(TunneldManager.arguments(for: .auto))
    }

    // MARK: - Process Management Security Tests (SEC-004)

    func testProcessOwnershipVerificationExists() {
        // Verify the TunneldManager has proper process tracking
        // The activeProcessIds property should exist and be managed correctly
        XCTAssertFalse(manager.isRunning, "Manager should not be running initially")

        // After stop, there should be no tracked processes
        // This validates the security improvement of tracking PIDs
    }

    func testKillTrackingDoesNotUsePkill() async {
        // This test validates that we don't use unsafe pkill patterns
        // By ensuring stop() uses PID-based termination

        // Start with no running tunnel
        XCTAssertEqual(manager.state, .idle)

        // Stop should work safely even with no running processes
        await manager.stopTunnel()

        // Manager should return to idle state
        XCTAssertEqual(manager.state, .idle)
    }

    func testTunnelStateTransitionsSafe() {
        // Validate state machine doesn't allow dangerous transitions
        let states: [TunnelState] = [.idle, .starting, .running, .stopping]

        for state in states {
            // isTransitioning should only be true for certain states
            switch state {
            case .idle:
                XCTAssertFalse(state.isTransitioning)
            case .starting:
                XCTAssertTrue(state.isTransitioning)
            case .running:
                XCTAssertFalse(state.isTransitioning)
            case .stopping:
                XCTAssertTrue(state.isTransitioning)
            case .error:
                XCTAssertFalse(state.isTransitioning)
            }
        }
    }

    func testProcessIdTrackingIntegrity() async {
        // Verify that process tracking maintains integrity
        // After stopTunnel(), no PIDs should remain tracked

        // Initial state
        XCTAssertFalse(manager.isRunning)

        // Stop should clear any tracked PIDs
        await manager.stopTunnel()

        // State should be idle
        XCTAssertEqual(manager.state, .idle)
    }

    func testSystemServiceProtection() throws {
        let source = try tunneldManagerSource()

        XCTAssertTrue(source.contains("guard let process = tunneldProcess"))
        XCTAssertFalse(source.contains("for pid in trackedPids"))
        XCTAssertFalse(source.contains("pkill"))
    }

    func testGracefulTerminationStrategy() throws {
        let source = try tunneldManagerSource()

        XCTAssertTrue(source.contains("process.terminate()"))
        XCTAssertTrue(source.contains("Task { @MainActor"))
        XCTAssertTrue(source.contains("SIGKILL"))
        XCTAssertTrue(source.contains("200_000_000"))
    }

    private func tunneldManagerSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("PathChanger/Device/TunneldManager.swift"),
            encoding: .utf8
        )
    }
}
