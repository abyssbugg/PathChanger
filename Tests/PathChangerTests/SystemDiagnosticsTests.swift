//
//  SystemDiagnosticsTests.swift
//  PathChangerTests
//
//  Diagnostics is read-only: it never sends a location, never starts or stops a tunnel
//  or the location helper, and reports a check as failed unless its command exited 0.
//

import XCTest
@testable import PathChanger

/// Records every command Diagnostics runs and answers from a script.
private final class RecordingDiagnosticsRunner: DiagnosticsCommandRunning, @unchecked Sendable {
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recorded: [Command] = []
    private let respond: @Sendable ([String]) -> BoundedProcessResult

    init(respond: @escaping @Sendable ([String]) -> BoundedProcessResult) {
        self.respond = respond
    }

    var commands: [Command] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(executable: String, arguments: [String]) async -> BoundedProcessResult {
        lock.lock()
        recorded.append(Command(executable: executable, arguments: arguments))
        lock.unlock()
        return respond(arguments)
    }
}

/// Holds every command until its task is cancelled, then answers as the bounded runner does.
private final class CancellableDiagnosticsRunner: DiagnosticsCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var started = 0
    private var cancelled = 0

    var startedCount: Int { lock.lock(); defer { lock.unlock() }; return started }
    var cancelledCount: Int { lock.lock(); defer { lock.unlock() }; return cancelled }

    func run(executable: String, arguments: [String]) async -> BoundedProcessResult {
        lock.lock()
        started += 1
        lock.unlock()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        lock.lock()
        cancelled += 1
        lock.unlock()
        return BoundedProcessResult(termination: .cancelled, output: "")
    }
}

/// Command answers shared by the tests (nonisolated: the runner calls them off the main actor).
private enum Fixture {
    static let allCapabilities = PythonPathResolver.requiredPymobiledevice3Capabilities.sorted()

    static func capabilityJSON(_ capabilities: [String], version: String = "11.49.1") -> String {
        let list = capabilities.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"version\":\"\(version)\",\"capabilities\":[\(list)]}\n"
    }

    /// Every command succeeds the way a healthy machine answers it.
    static func healthyResponse(_ arguments: [String]) -> BoundedProcessResult {
        switch arguments {
        case SystemDiagnostics.pythonVersionArguments:
            return BoundedProcessResult(termination: .exited(0), output: "Python 3.13.14\n")
        case SystemDiagnostics.capabilityProbeArguments:
            return BoundedProcessResult(termination: .exited(0), output: capabilityJSON(allCapabilities))
        case SystemDiagnostics.usbmuxListUSBArguments:
            // `usbmux list --simple`: UDIDs only, as pymobiledevice3 11.49.1 prints them.
            return BoundedProcessResult(termination: .exited(0), output: "[]\n")
        case SystemDiagnostics.usbmuxListNetworkArguments:
            return BoundedProcessResult(
                termination: .exited(0),
                output: "[\n    \"00008110-001A2B3C4D5E6F70\"\n]\n"
            )
        default:
            // Anything else would be a command Diagnostics must not run; answer as a
            // device would so that only the command list can catch it.
            return BoundedProcessResult(termination: .exited(0), output: "")
        }
    }
}

@MainActor
final class SystemDiagnosticsTests: XCTestCase {
    private let deviceID = "00008110-001A2B3C4D5E6F70"
    private let pythonPath = "/tmp/tmp_rovodev_runtime/bin/python3"

    /// The state in which the old Diagnostics ran its location-injection test: runtime
    /// and pymobiledevice3 fine, a live device connection, a selected device.
    private func connectedSnapshot(lane: String? = "remotePairingRSD") -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            pythonPath: pythonPath,
            selectedDevice: .init(id: deviceID, displayName: "Test iPhone", transport: .wifi, productVersion: "27.2"),
            desiredCoordinate: LocationCoordinate(latitude: 35.0, longitude: 139.0),
            helperProcessID: 4242,
            tunnelState: .running,
            tunnelInfo: TunnelInfo(
                rsdAddress: "",
                rsdPort: 0,
                mode: .wifi,
                interface: nil,
                processId: 4242,
                channel: .helperUserspace,
                deviceId: deviceID
            ),
            heldLocationLane: lane
        )
    }

    private func idleSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            pythonPath: pythonPath,
            selectedDevice: .init(id: deviceID, displayName: "Test iPhone", transport: .wifi, productVersion: "27.2"),
            desiredCoordinate: nil,
            helperProcessID: nil,
            tunnelState: .idle,
            tunnelInfo: nil,
            heldLocationLane: nil
        )
    }

    private func diagnostics(
        runner: RecordingDiagnosticsRunner,
        diskImage: @escaping SystemDiagnostics.DiskImageStatusQuery = { _, _ in .mounted }
    ) -> SystemDiagnostics {
        SystemDiagnostics(runner: runner, diskImageStatus: diskImage)
    }

    private func result(_ name: String, in results: [DiagnosticResult]) -> DiagnosticResult? {
        results.first { $0.name == name }
    }

    // MARK: - Read-only

    func testNeverBuildsALocationCommandEvenWhenEveryPrerequisitePasses() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        _ = await diagnostics(runner: runner).run(connectedSnapshot())

        XCTAssertFalse(runner.commands.isEmpty)
        for command in runner.commands {
            XCTAssertEqual(command.executable, pythonPath)
            for forbidden in ["simulate-location", "dvt", "developer", "set", "clear", "auto-mount",
                              "start-tunnel", "tunneld", "remotepairing", "wifi-connections"] {
                XCTAssertFalse(
                    command.arguments.contains(forbidden),
                    "Diagnostics ran a device-changing command: \(command.arguments)"
                )
            }
        }
        // Exactly the read-only commands, each once.
        XCTAssertEqual(runner.commands.map(\.arguments), [
            SystemDiagnostics.pythonVersionArguments,
            SystemDiagnostics.capabilityProbeArguments,
            SystemDiagnostics.usbmuxListUSBArguments,
            SystemDiagnostics.usbmuxListNetworkArguments,
        ])
    }

    func testNoCheckClaimsALocationInjection() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        XCTAssertNil(result("Location Injection", in: results))
        XCTAssertFalse(results.contains { $0.message.contains("0.0, 0.0") })
    }

    func testDiagnosticsSourcesNeverMentionTheSimulateLocationCommand() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["PathChanger/UI/DiagnosticsView.swift", "PathChanger/Core/SystemDiagnostics.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(source.contains("simulate-location"), "\(path) builds a location command")
            XCTAssertFalse(source.contains("locationConnectionArguments"), "\(path) builds a device command")
        }
    }

    // MARK: - Exit status, deadline

    func testNonZeroExitFailsTheCheck() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.pythonVersionArguments {
                return BoundedProcessResult(termination: .exited(1), output: "Python 3.13.14\n")
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let python = result("Python runtime", in: results)
        XCTAssertEqual(python?.status, .failure)
        XCTAssertTrue(python?.message.contains("exited with status 1") ?? false, python?.message ?? "")
    }

    func testTimeoutFailsTheCheck() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.capabilityProbeArguments {
                return BoundedProcessResult(termination: .timedOut, output: "")
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let probe = result("pymobiledevice3", in: results)
        XCTAssertEqual(probe?.status, .failure)
        XCTAssertTrue(probe?.message.contains("did not finish in time") ?? false, probe?.message ?? "")
    }

    func testUsbmuxListFailureFailsItsCheck() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.usbmuxListNetworkArguments {
                return BoundedProcessResult(termination: .exited(2), output: "Traceback ...\n")
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let usbmux = result("usbmux", in: results)
        XCTAssertEqual(usbmux?.status, .failure)
        XCTAssertTrue(usbmux?.message.contains("usbmuxd") ?? false, usbmux?.message ?? "")
    }

    // MARK: - Capability probe

    func testAllSixCapabilitiesPass() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let probe = result("pymobiledevice3", in: results)
        XCTAssertEqual(probe?.status, .success)
        XCTAssertTrue(probe?.message.contains("11.49.1") ?? false, probe?.message ?? "")
    }

    func testAMissingCapabilityFailsAndIsNamed() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.capabilityProbeArguments {
                let partial = Fixture.allCapabilities.filter { $0 != "location_simulation" }
                return BoundedProcessResult(termination: .exited(0), output: Fixture.capabilityJSON(partial))
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let probe = result("pymobiledevice3", in: results)
        XCTAssertEqual(probe?.status, .failure)
        XCTAssertTrue(probe?.message.contains("location_simulation") ?? false, probe?.message ?? "")
    }

    // MARK: - Helper, connection, Developer Disk Image

    func testHelperAndConnectionAreReportedFromAppStateWithTheirLane() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let helper = result("Location helper", in: results)
        XCTAssertEqual(helper?.status, .success)
        XCTAssertTrue(helper?.message.contains("4242") ?? false, helper?.message ?? "")
        let connection = result("Device connection", in: results)
        XCTAssertEqual(connection?.status, .success)
        XCTAssertTrue(connection?.message.contains("remotePairingRSD") ?? false, connection?.message ?? "")
    }

    func testNoHelperAndNoConnectionAreWarningsAndAskNothing() async {
        var diskImageQueries = 0
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner, diskImage: { _, _ in
            diskImageQueries += 1
            return .mounted
        }).run(idleSnapshot())

        XCTAssertEqual(diskImageQueries, 0, "with no open connection the helper must not be asked")
        XCTAssertEqual(result("Location helper", in: results)?.status, .warning)
        XCTAssertEqual(result("Device connection", in: results)?.status, .warning)
        XCTAssertEqual(result("Developer Disk Image", in: results)?.status, .warning)
    }

    func testDiskImageIsAskedOverTheOpenConnectionForTheSelectedDevice() async {
        var asked: [(String, LocationTransport)] = []
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner, diskImage: { id, transport in
            asked.append((id, transport))
            return .notMounted
        }).run(connectedSnapshot())

        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.0, deviceID)
        XCTAssertEqual(asked.first?.1, .wifi)
        XCTAssertEqual(result("Developer Disk Image", in: results)?.status, .failure)
    }

    func testDiskImageMountedPasses() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner, diskImage: { _, _ in .mounted }).run(connectedSnapshot())
        XCTAssertEqual(result("Developer Disk Image", in: results)?.status, .success)
    }

    func testAConnectionForAnotherDeviceIsNotThisDevicesConnection() async {
        var diskImageQueries = 0
        var snapshot = connectedSnapshot()
        snapshot.tunnelInfo = TunnelInfo(
            rsdAddress: "", rsdPort: 0, mode: .wifi, interface: nil, processId: 4242,
            channel: .helperUserspace, deviceId: "00008110-FFFFFFFFFFFFFFFF"
        )
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner, diskImage: { _, _ in
            diskImageQueries += 1
            return .mounted
        }).run(snapshot)
        XCTAssertEqual(diskImageQueries, 0)
        XCTAssertEqual(result("Device connection", in: results)?.status, .warning)
    }

    func testATunnelErrorIsAFailure() async {
        var snapshot = idleSnapshot()
        snapshot.tunnelState = .error("Could not connect to the device")
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner).run(snapshot)
        let connection = result("Device connection", in: results)
        XCTAssertEqual(connection?.status, .failure)
        XCTAssertTrue(connection?.message.contains("Could not connect to the device") ?? false)
    }

    // MARK: - Cancellation

    /// Review 2026-11-03 issue 6: closing the Diagnostics sheet must stop its run. A
    /// cancelled run cancels the command in flight and starts no further command.
    func testACancelledRunCancelsItsCommandAndStartsNoOther() async throws {
        let runner = CancellableDiagnosticsRunner()
        let diagnostics = SystemDiagnostics(runner: runner, diskImageStatus: { _, _ in .mounted })
        let snapshot = connectedSnapshot()
        let run = Task { await diagnostics.run(snapshot) }
        let deadline = Date().addingTimeInterval(5)
        while runner.startedCount < 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(runner.startedCount, 1)

        run.cancel()
        _ = await run.value

        XCTAssertEqual(runner.cancelledCount, 1, "the cancellation reached the command in flight")
        XCTAssertEqual(runner.startedCount, 1, "no command started after the cancellation")
    }

    // MARK: - usbmux

    /// Review 2026-11-03 issue 5: `usbmux list` without `--simple` opens a lockdown
    /// session on every listed phone, and one unreachable network device failed the whole
    /// check. Only usbmuxd's own list is read.
    func testTheUsbmuxCheckNeverOpensALockdownSession() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        _ = await diagnostics(runner: runner).run(connectedSnapshot())
        let usbmuxCommands = runner.commands.filter { $0.arguments.contains("usbmux") }
        XCTAssertFalse(usbmuxCommands.isEmpty)
        for command in usbmuxCommands {
            XCTAssertTrue(command.arguments.contains("--simple"), "\(command.arguments) connects to lockdownd")
        }
    }

    func testAnEmptyUsbmuxListIsAWarningNotAFailure() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.usbmuxListUSBArguments
                || arguments == SystemDiagnostics.usbmuxListNetworkArguments {
                return BoundedProcessResult(termination: .exited(0), output: "[]\n")
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        XCTAssertEqual(result("usbmux", in: results)?.status, .warning)
    }

    func testAPhoneListedOverUSBAndNetworkSaysBoth() async {
        let runner = RecordingDiagnosticsRunner { arguments in
            if arguments == SystemDiagnostics.usbmuxListUSBArguments {
                return BoundedProcessResult(termination: .exited(0), output: "[\"00008110-001A2B3C4D5E6F70\"]\n")
            }
            return Fixture.healthyResponse(arguments)
        }
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let usbmux = result("usbmux", in: results)
        XCTAssertEqual(usbmux?.status, .success)
        XCTAssertTrue(usbmux?.message.contains("Network and USB") ?? false, usbmux?.message ?? "")
    }

    func testTheSimpleListParserReadsUDIDsOnly() {
        XCTAssertEqual(SystemDiagnostics.usbmuxIdentifiers("[\n    \"00008110-001A2B3C4D5E6F70\"\n]\n"),
                       ["00008110-001A2B3C4D5E6F70"])
        XCTAssertEqual(SystemDiagnostics.usbmuxIdentifiers("[]"), [])
        XCTAssertNil(SystemDiagnostics.usbmuxIdentifiers("Traceback (most recent call last)"))
    }

    func testUsbmuxReportsHowItListsTheSelectedPhone() async {
        let runner = RecordingDiagnosticsRunner(respond: Fixture.healthyResponse)
        let results = await diagnostics(runner: runner).run(connectedSnapshot())
        let usbmux = result("usbmux", in: results)
        XCTAssertEqual(usbmux?.status, .success)
        XCTAssertTrue(usbmux?.message.contains("Network") ?? false, usbmux?.message ?? "")
        XCTAssertFalse(usbmux?.message.contains(deviceID) ?? true, "no device identifier on screen")
    }
}
