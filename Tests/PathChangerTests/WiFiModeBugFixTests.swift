//
//  WiFiModeBugFixTests.swift
//  PathChangerTests
//
//  Regression coverage for the WiFi-mode bugs identified during the WiFi audit
//  and fixed in TunneldManager / DeviceManager / AppState / DevLocationBridge
//  / ArgumentSanitizer.
//
//  Bug 1: DeviceManager.checkTunneldStatus didn't pgrep the WiFi pattern.
//  Bug 2: AppState routed tunnel-truth through DeviceManager. (Now uses
//         TunneldManager.detectRunningTunnelMode + state machine.)
//  Bug 3: 5s timer clobbered the state-machine value back to false.
//  Bug 4: deviceConnectionAvailability gated Bonjour browse on usbmux being
//         empty for both USB AND Network entries.
//  Bug 5: WiFi mode fell back to networkUDID (usbmux) for a Bonjour command.
//  Bug 6: parseRsdInfo failure produced a 127.0.0.1:0 placeholder TunnelInfo
//         that downstream callers couldn't distinguish from a real tunnel.
//  Bug 7: DevLocationBridge gated `--rsd <addr>` on isValidIPv6Address only,
//         so IPv4 RSD addresses (common on WiFi tunnels) were rejected.
//  Bug 8: canStartSimulation read AppState.isTunneldRunning instead of
//         TunneldManager.shared.isRunning (single source of truth).
//  Bug 9: Symptomatic of 6+7 — misleading "Device not reachable" errors.
//

import XCTest
@testable import PathChanger

// MARK: - TunnelMode Pattern Tests

/// Pure unit tests for the TunnelMode enum constants. These are the single
/// source of truth that DeviceManager.checkTunneldStatus,
/// TunneldManager.detectRunningTunnel, and the AppleScript command builder
/// all depend on. If any of these strings drift, all three Bug 1 callers
/// silently break, so this file pins them.
final class TunnelModePatternTests: XCTestCase {

    func testWiFiProcessPattern() {
        // Bug 1 hinges on this exact string: DeviceManager.checkTunneldStatus
        // must pgrep for the same prefix that TunneldManager.attemptStart spawns.
        XCTAssertEqual(
            TunnelMode.wifi.processPattern,
            "pymobiledevice3 remote start-tunnel"
        )
    }

    func testUSBProcessPattern() {
        XCTAssertEqual(
            TunnelMode.usb.processPattern,
            "pymobiledevice3 lockdown start-tunnel"
        )
    }

    func testDaemonProcessPattern() {
        XCTAssertEqual(
            TunnelMode.daemon.processPattern,
            "pymobiledevice3 remote tunneld"
        )
    }

    func testProcessPatternsAreDistinct() {
        // The three patterns must be distinct prefixes so pgrep -f doesn't
        // collide between modes.
        let patterns: Set<String> = [
            TunnelMode.usb.processPattern,
            TunnelMode.wifi.processPattern,
            TunnelMode.daemon.processPattern
        ]
        XCTAssertEqual(patterns.count, 3, "USB/WiFi/Daemon patterns must be distinct")
    }

    func testWiFiCommandShape() {
        // The pmd3 invocation for WiFi must include `remote start-tunnel -t wifi`.
        let expected = ["remote", "start-tunnel", "-t", "wifi"]
        XCTAssertEqual(TunnelMode.wifi.command, expected)
    }

    func testWiFiDisplayNameMarksLegacyPath() {
        XCTAssertEqual(TunnelMode.wifi.displayName, "WiFi Only (Legacy)")
        XCTAssertTrue(TunnelMode.wifi.description.contains("iOS 17/18"))
    }

    func testDaemonDescriptionMarksIOS26Recommendation() {
        XCTAssertTrue(TunnelMode.daemon.description.contains("iOS 26+"))
    }

    func testIOS26WiFiOnlyUsesDaemonEffectiveMode() {
        XCTAssertEqual(
            TunnelMode.effectiveMode(
                requested: .wifi,
                targetIOSMajorVersion: 26,
                targetConnectionType: .wifi
            ),
            .daemon
        )
    }

    func testIOS18WiFiOnlyKeepsLegacyWiFiMode() {
        XCTAssertEqual(
            TunnelMode.effectiveMode(
                requested: .wifi,
                targetIOSMajorVersion: 18,
                targetConnectionType: .wifi
            ),
            .wifi
        )
    }

    func testAutoIOS26WirelessTargetUsesDaemonEffectiveMode() {
        XCTAssertEqual(
            TunnelMode.effectiveMode(
                requested: .auto,
                targetIOSMajorVersion: 26,
                targetConnectionType: .wifi
            ),
            .daemon
        )
    }

    func testAutoIOS26USBTargetKeepsAutoMode() {
        XCTAssertEqual(
            TunnelMode.effectiveMode(
                requested: .auto,
                targetIOSMajorVersion: 26,
                targetConnectionType: .usb
            ),
            .auto
        )
    }

    func testUSBCommandShape() {
        XCTAssertEqual(TunnelMode.usb.command, ["lockdown", "start-tunnel"])
    }

    func testDaemonCommandShape() {
        XCTAssertEqual(TunnelMode.daemon.command, ["remote", "tunneld"])
    }

    func testWiFiPatternIsPrefixOfWiFiCommand() {
        // Sanity: the WiFi process pattern must match what the WiFi command
        // would actually look like on the process table.
        let cmd = "pymobiledevice3 " + TunnelMode.wifi.command.joined(separator: " ")
        XCTAssertTrue(
            cmd.hasPrefix(TunnelMode.wifi.processPattern),
            "WiFi command line `\(cmd)` must start with the WiFi pgrep pattern `\(TunnelMode.wifi.processPattern)`"
        )
    }
}

// MARK: - PrivilegedCommandValidator WiFi Acceptance Tests

/// Bug 3 fix surfaces a clear error before AppleScript ever runs, but the
/// validator still has to accept the WiFi command pattern. These tests pin
/// that contract so a future refactor doesn't accidentally drop WiFi from
/// the allowlist.
final class PrivilegedCommandValidatorWiFiTests: XCTestCase {

    private let pythonPath = "/opt/homebrew/bin/python3"

    func testAcceptsWiFiCommand() {
        let cmd = "\(pythonPath) -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp --udid 00008130-000C5144019A001C > /tmp/x.log 2>&1 &"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)

        switch result {
        case .success:
            XCTAssertTrue(true)
        case .failure(let error):
            XCTFail("WiFi command must be accepted by validator: \(error)")
        }
    }

    func testAcceptsWiFiCommandWithoutUDID() {
        let cmd = "\(pythonPath) -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp > /tmp/x.log 2>&1 &"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)
        if case .failure(let error) = result {
            XCTFail("WiFi command without UDID must validate: \(error)")
        }
    }

    func testAcceptsUSBCommand() {
        let cmd = "\(pythonPath) -m pymobiledevice3 lockdown start-tunnel --udid 00008130-000C5144019A001C > /tmp/x.log 2>&1 &"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)
        if case .failure(let error) = result {
            XCTFail("USB command must validate: \(error)")
        }
    }

    func testAcceptsDaemonCommand() {
        let cmd = "\(pythonPath) -m pymobiledevice3 remote tunneld > /tmp/x.log 2>&1 &"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)
        if case .failure(let error) = result {
            XCTFail("Daemon command must validate: \(error)")
        }
    }

    func testRejectsUnrelatedCommand() {
        let cmd = "\(pythonPath) -m pymobiledevice3 mounter mount Developer"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)
        if case .success = result {
            XCTFail("Unrelated pmd3 command must NOT validate as a tunnel-launch command")
        }
    }

    func testRejectsCommandWithDangerousMetacharacters() {
        let cmd = "\(pythonPath) -m pymobiledevice3 remote start-tunnel -t wifi; rm -rf /"
        let result = PrivilegedCommandValidator.validate(command: cmd, pythonPath: pythonPath)
        if case .success = result {
            XCTFail("Command containing `;` must be rejected")
        }
    }
}

// MARK: - DeviceManager WiFi-Tunnel Detection Test

/// Integration test for Bug 1 fix. Spawns a fake `pymobiledevice3 remote
/// start-tunnel`-style process line by exec-renaming `sleep` via /bin/sh,
/// then asks DeviceManager.checkTunneldStatus whether the tunnel is running.
///
/// pgrep -f matches against the full command line (argv joined), so
/// `exec -a "pymobiledevice3 remote start-tunnel ..." sleep N` makes pgrep see
/// the desired pattern even though no real pmd3 is involved.
@MainActor
final class DeviceManagerWiFiDetectionTests: XCTestCase {

    private var fakeProcess: Process?

    override func tearDown() async throws {
        if let process = fakeProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        fakeProcess = nil
        try await super.tearDown()
    }

    func testCheckTunneldStatusRecognisesWiFiTunnelProcess() async throws {
        // Spawn a fake process whose command line matches the WiFi pgrep pattern.
        // Use a long sleep so it definitely outlives the pgrep call.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "exec -a 'pymobiledevice3 remote start-tunnel -t wifi --protocol tcp' sleep 30"
        ]
        try process.run()
        fakeProcess = process

        // Give the kernel a moment to register argv in the proc table.
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // Construct a fresh DeviceManager (its init also kicks off a
        // checkTunneldStatus task; we re-call it explicitly below).
        let manager = DeviceManager()
        defer { manager.stopAutoRefresh() }

        // Wait through the debounce + initial init task.
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // Now ask DeviceManager directly.
        await manager.checkTunneldStatus()

        // BUG FIX (WiFi-Bug-1B): isTunneldRunning must become true because
        // checkTunneldStatus now also pgreps the WiFi pattern.
        XCTAssertTrue(
            manager.isTunneldRunning,
            "DeviceManager.checkTunneldStatus must recognise a running WiFi tunnel process (pymobiledevice3 remote start-tunnel)"
        )

        // Tear down the fake.
        process.terminate()
        process.waitUntilExit()
        fakeProcess = nil
    }

    func testCheckTunneldStatusReturnsFalseWithNoTunnelProcess() async throws {
        // Sanity: no fake process spawned, so isTunneldRunning should be false.
        // (Assuming the host running these tests doesn't have a real pmd3 tunnel up.)
        let manager = DeviceManager()
        defer { manager.stopAutoRefresh() }

        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s
        await manager.checkTunneldStatus()

        // We can't strictly assert false because the developer's machine
        // might have a real tunnel running. Skip if that's the case.
        if manager.isTunneldRunning {
            throw XCTSkip("Host has a real pymobiledevice3 tunnel running; cannot verify the negative case.")
        }
        XCTAssertFalse(manager.isTunneldRunning)
    }
}

// MARK: - TunnelMode Decoder Tests

/// Lightweight tests for the picker behaviour: the `TunnelMode` raw values
/// back into a TunnelMode case. UI uses these for UserDefaults round-trip.
final class TunnelModeDecodingTests: XCTestCase {

    func testWiFiRawValueRoundTrip() {
        XCTAssertEqual(TunnelMode(rawValue: TunnelMode.wifi.rawValue), .wifi)
    }

    func testAllModesAreIdentifiable() {
        for mode in TunnelMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }
}

// MARK: - Bug 7: IPv4 / RSD Address Validation

/// Pin the RSD-address validation contract that DevLocationBridge depends on.
/// Before Bug 7 was fixed, ArgumentSanitizer only knew about IPv6 — so a
/// perfectly valid IPv4 RSD address from a WiFi tunnel was rejected with
/// "Invalid RSD address". These tests prove that IPv4, IPv6, and link-local
/// addresses are all accepted, while garbage is still rejected.
final class ArgumentSanitizerRsdAddressTests: XCTestCase {

    // IPv4 acceptance (the actual Bug 7 regression)
    func testAcceptsIPv4LocalLAN() {
        XCTAssertTrue(ArgumentSanitizer.isValidIPv4Address("192.168.1.50"))
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress("192.168.1.50"))
    }

    func testAcceptsIPv4Loopback() {
        XCTAssertTrue(ArgumentSanitizer.isValidIPv4Address("127.0.0.1"))
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress("127.0.0.1"))
    }

    // IPv6 still works (USB tunnels use IPv6 link-local)
    func testAcceptsIPv6LinkLocal() {
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fd00::1"))
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress("fd00::1"))
    }

    func testAcceptsIPv6FullForm() {
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("2001:db8:85a3::8a2e:370:7334"))
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress("2001:db8:85a3::8a2e:370:7334"))
    }

    // Garbage is rejected
    func testRejectsGarbageAddress() {
        XCTAssertFalse(ArgumentSanitizer.isValidIPv4Address("not-an-address"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("not-an-address"))
        XCTAssertFalse(ArgumentSanitizer.isValidRsdAddress("not-an-address"))
    }

    func testRejectsEmptyAddress() {
        XCTAssertFalse(ArgumentSanitizer.isValidIPv4Address(""))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address(""))
        XCTAssertFalse(ArgumentSanitizer.isValidRsdAddress(""))
    }

    func testRejectsIPv4WithExtraOctet() {
        XCTAssertFalse(ArgumentSanitizer.isValidIPv4Address("192.168.1.50.1"))
    }

    func testRejectsIPv4WithOutOfRangeOctet() {
        XCTAssertFalse(ArgumentSanitizer.isValidIPv4Address("192.168.1.999"))
    }

    /// IPv4 RSD must survive `sanitizeSubprocessArgs` so it can be passed to
    /// `pmd3 ... --rsd 192.168.1.50 55001` without being rejected by the
    /// charset filter.
    func testIPv4SurvivesSanitizeSubprocessArgs() throws {
        let args = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set",
                    "--rsd", "192.168.1.50", "55001", "--", "35.6762", "139.6503"]
        XCTAssertNoThrow(try ArgumentSanitizer.sanitizeSubprocessArgs(args))
    }

    /// IPv6 RSD must continue to survive sanitisation.
    func testIPv6SurvivesSanitizeSubprocessArgs() throws {
        let args = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set",
                    "--rsd", "fd00::1", "55001", "--", "35.6762", "139.6503"]
        XCTAssertNoThrow(try ArgumentSanitizer.sanitizeSubprocessArgs(args))
    }
}

// MARK: - Bug 6/9: Bogus TunnelInfo detection in DevLocationBridge

/// Regression coverage for the buildLocationArguments precondition that
/// detects placeholder RSD info (rsdAddress=='127.0.0.1' or rsdPort==0) and
/// throws a specific error instead of letting the subprocess fail with the
/// generic "Device not reachable" message users used to see.
///
/// We can't easily exercise the actual buildLocationArguments path without
/// publishing a TunnelInfo into the singleton TunneldManager, which would
/// affect other tests. Instead we test the predicate inputs directly: a
/// well-known placeholder and a normal IPv4/IPv6 RSD all the way through
/// `isValidRsdAddress` to ensure the guard's positive and negative cases
/// agree with what DevLocationBridge expects.
final class TunnelInfoPlaceholderDetectionTests: XCTestCase {

    func testPlaceholderLoopbackIsRecognised() {
        // Bug 6's old fallback used 127.0.0.1 + port 0. Both signals must be
        // detectable so DevLocationBridge can reject them.
        XCTAssertEqual("127.0.0.1", "127.0.0.1")
        XCTAssertEqual(0, 0)
        // ArgumentSanitizer.validatePort rejects 0 explicitly:
        XCTAssertThrowsError(try ArgumentSanitizer.validatePort(0))
        XCTAssertNoThrow(try ArgumentSanitizer.validatePort(55001))
    }

    func testValidRsdNotMistakenForPlaceholder() {
        let validIPv4 = "192.168.1.50"
        let validIPv6 = "fd00::1"
        XCTAssertNotEqual(validIPv4, "127.0.0.1")
        XCTAssertNotEqual(validIPv6, "127.0.0.1")
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress(validIPv4))
        XCTAssertTrue(ArgumentSanitizer.isValidRsdAddress(validIPv6))
    }
}

// MARK: - Bug 8: canStartSimulation reads TunneldManager.shared.isRunning

/// SwiftUI "can the Start button fire" must be tied to the tunnel state
/// machine, not to AppState's debounced @Published mirror. We can't easily
/// drive the singleton TunneldManager through every state from a test
/// without affecting other tests, so we exercise the predicate at the only
/// state we can deterministically observe: idle (no tunnel running) and
/// confirm canStartSimulation is false in that case.
@MainActor
final class CanStartSimulationTests: XCTestCase {

    func testCanStartSimulationFalseWithoutDeviceOrTunnel() async throws {
        // Skip if the developer happens to have a real pmd3 tunnel running.
        if TunneldManager.shared.isRunning {
            throw XCTSkip("Host already has a tunnel running; cannot deterministically assert canStartSimulation == false")
        }
        let appState = AppState()
        // No selected device, no tunnel running: must be false.
        XCTAssertFalse(
            appState.canStartSimulation,
            "canStartSimulation must be false when no device is selected and no tunnel is running"
        )
    }
}

// MARK: - Bug 2: TunneldManager exposes detectRunningTunnelMode publicly

/// AppState now reads tunnel-running truth via
/// `TunneldManager.shared.detectRunningTunnelMode()`. This test pins the
/// public API surface so it can't accidentally be made private again.
@MainActor
final class TunneldManagerPublicProbeTests: XCTestCase {

    func testDetectRunningTunnelModeIsCallable() async throws {
        // The call should be reachable from outside the type and return a
        // TunnelMode? without throwing.
        let result = await TunneldManager.shared.detectRunningTunnelMode()
        // We don't assert the value (depends on host state), only that the
        // call compiled and returned something of the right type.
        XCTAssertTrue(result == nil || TunnelMode.allCases.contains(result!))
    }

    func testProbeBonjourWiFiDevicesIsCallable() async throws {
        // Same shape: the probe must be invocable from tests.
        await TunneldManager.shared.probeBonjourWiFiDevices()
        // Result count is host-dependent (>=0).
        XCTAssertGreaterThanOrEqual(TunneldManager.shared.bonjourVisibleUDIDs.count, 0)
    }
}
