//
//  TunneldManagerTests.swift
//  PathChangerTests
//
//  Unit tests for tunnel lifecycle and race condition prevention
//

import XCTest
import Darwin
@testable import PathChanger

@MainActor
final class TunneldManagerTests: XCTestCase {

    var manager: TunneldManager!
    let testUDID = "00008130-000C5144019A001C"

    func usbTunnelCommand(udid: String? = nil) -> String {
        let udidArgument = udid.map { " --udid \($0)" } ?? ""
        return "/Users/test/.pyenv/versions/3.12.11/bin/python3 -m pymobiledevice3 lockdown start-tunnel --script-mode\(udidArgument)"
    }

    func wifiTunnelCommand(udid: String? = nil) -> String {
        let udidArgument = udid.map { " --udid \($0)" } ?? ""
        return "/Users/test/.pyenv/versions/3.12.11/bin/python3 -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp\(udidArgument)"
    }

    override func setUp() async throws {
        // Note: Using shared singleton - tests may affect each other
        manager = TunneldManager.shared
#if DEBUG
        manager.testResetTunnelLifecycleForTests()
        // Wave 1 made attemptStart resolve a non-pyenv interpreter carrying the
        // pinned pymobiledevice3 before it builds anything. That is a property of
        // the host: on a pyenv-based dev machine, or on a CI runner without the
        // pin, resolution returns nil and attemptStart bails before any of the
        // orchestration these tests actually cover. Pin it so the launch tests
        // are hermetic; the resolver itself is covered by
        // PrivilegedPathSecurityTests.
        manager.testSetPrivilegedPythonPath("/usr/bin/python3")
#else
        manager.stopTunnel()
#endif
    }

    override func tearDown() async throws {
        // Clean up any running tunnels after each test
#if DEBUG
        manager.testResetTunnelLifecycleForTests()
#else
        manager.stopTunnel()
#endif

        // Give it time to fully stop
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }

    // MARK: - State Machine Tests

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
        XCTAssertEqual(TunnelMode.usb.command, ["lockdown", "start-tunnel"])
        XCTAssertEqual(TunnelMode.wifi.command, ["remote", "start-tunnel", "-t", "wifi"])
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

    // MARK: - RSD Parsing Tests

    func testParseScriptModeRsdLineAcceptsIOS27IPv6Output() {
        let output = """
        Identifier: 00008130-000C5144019A001C
        fd14:d8b0:f31e::1 52064
        """

        let parsed = manager.parseScriptModeRsdLine(from: output)

        XCTAssertEqual(parsed.address, "fd14:d8b0:f31e::1")
        XCTAssertEqual(parsed.port, 52064)
    }

    func testParseScriptModeRsdLineAcceptsIPv4Output() {
        let parsed = manager.parseScriptModeRsdLine(from: "192.168.1.50 52068\n")

        XCTAssertEqual(parsed.address, "192.168.1.50")
        XCTAssertEqual(parsed.port, 52068)
    }

    func testParseScriptModeRsdLineRejectsMalformedOutput() {
        let malformedOutputs = [
            "not-an-address 52064",
            "abc:def 52064",
            "fd14:d8b0:f31e::1 0",
            "fd14:d8b0:f31e::1 65536",
            "fd14:d8b0:f31e::1 not-a-port",
            "fd14:d8b0:f31e::1 52064 extra",
            "status ready"
        ]

        for output in malformedOutputs {
            let parsed = manager.parseScriptModeRsdLine(from: output)
            XCTAssertNil(parsed.address, "Unexpected address for output: \(output)")
            XCTAssertNil(parsed.port, "Unexpected port for output: \(output)")
        }
    }

    func testLegacyRsdHintParsingStillWorks() {
        let parsed = manager.parseRsdHintLine(from: "Use developer dvt ls / --rsd fd4d:fb00:8c25::1 52072")

        XCTAssertEqual(parsed.address, "fd4d:fb00:8c25::1")
        XCTAssertEqual(parsed.port, 52072)
    }

    func testStructuredRsdLogParsingStillWorks() {
        let output = """
        Interface: utun9
        RSD Address: fdc3:ad86:9ca9::1
        RSD Port: 52068
        """

        let parsed = manager.parseStructuredLogLines(from: output)

        XCTAssertEqual(parsed.address, "fdc3:ad86:9ca9::1")
        XCTAssertEqual(parsed.port, 52068)
        XCTAssertEqual(parsed.interface, "utun9")
    }

    func testJsonRsdParsingStillWorks() throws {
        let parsed = try manager.parseJsonOutput(from: #"{"rsd-address":"fd14:d8b0:f31e::1","rsd-port":52064,"interface":"utun10"}"#)

        XCTAssertEqual(parsed.address, "fd14:d8b0:f31e::1")
        XCTAssertEqual(parsed.port, 52064)
        XCTAssertEqual(parsed.interface, "utun10")
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
            "This test calls startTunnel(), which uses administrator-privileged AppleScript and cannot run in noninteractive CI."
        )
        // First call should set state to starting
        // Subsequent calls should be ignored

        // Start two concurrent calls
        async let call1: Void = manager.startTunnel()
        async let call2: Void = manager.startTunnel()

        // Both should complete without crash
        _ = await (call1, call2)

        // State should not be corrupted
        XCTAssertTrue(
            manager.state == .idle ||
            manager.state == .starting ||
            manager.state == .running ||
            {
                if case .error = manager.state { return true }
                return false
            }()
        )
    }

}
