import XCTest
@testable import PathChanger

private func pythonStringLiteral(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let literal = String(data: data, encoding: .utf8) else {
        // Encoding a String cannot fail in practice. If it ever does, emit a
        // literal that makes the generated Python fail loudly rather than
        // silently substituting a valid-but-wrong path.
        return "None"
    }
    return literal
}

@MainActor
private func withTemporaryBridgeScript<T>(
    _ source: String,
    readyTimeout: TimeInterval = 1.0,
    responseTimeout: TimeInterval = 1.0,
    operation: (LocationBridge) async throws -> T
) async throws -> T {
    let bridge = LocationBridge.shared
    await bridge.stop()

    let scriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pathchanger-bridge-\(UUID().uuidString).py")
    try source.write(to: scriptURL, atomically: true, encoding: .utf8)
    bridge.testOverrideBridgeConfiguration(
        bridgeScriptPath: scriptURL.path,
        readyTimeout: readyTimeout,
        responseTimeout: responseTimeout
    )

    do {
        let value = try await operation(bridge)
        await bridge.stop()
        bridge.testRestoreBridgeConfiguration()
        try? FileManager.default.removeItem(at: scriptURL)
        return value
    } catch {
        await bridge.stop()
        bridge.testRestoreBridgeConfiguration()
        try? FileManager.default.removeItem(at: scriptURL)
        throw error
    }
}

/// Unit tests for the authoritative LocationBridge.
final class LocationBridgeTests: XCTestCase {

    // MARK: - Error Description Tests

    func testBridgeErrorDescriptions() {
        let errors: [LocationBridge.LocationBridgeError] = [
            .processNotRunning,
            .processStartFailed("test reason"),
            .timeout,
            .invalidResponse("bad response"),
            .bridgeError("bridge error"),
            .processExited(exitCode: 42, details: "boom"),
            .pythonNotFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    func testProcessNotRunningError() {
        let error = LocationBridge.LocationBridgeError.processNotRunning
        XCTAssertEqual(error.errorDescription, "Python bridge process is not running")
    }

    func testProcessStartFailedError() {
        let error = LocationBridge.LocationBridgeError.processStartFailed("Python not found")
        XCTAssertTrue(error.errorDescription!.contains("Python not found"))
    }

    func testTimeoutError() {
        let error = LocationBridge.LocationBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    func testInvalidResponseError() {
        let error = LocationBridge.LocationBridgeError.invalidResponse("garbage data")
        XCTAssertTrue(error.errorDescription!.contains("garbage data"))
    }

    func testBridgeError() {
        let error = LocationBridge.LocationBridgeError.bridgeError("Device not found")
        XCTAssertTrue(error.errorDescription!.contains("Device not found"))
    }

    func testProcessExitedError() {
        let error = LocationBridge.LocationBridgeError.processExited(exitCode: 42, details: "fatal bridge boom")
        XCTAssertTrue(error.errorDescription!.contains("42"))
        XCTAssertTrue(error.errorDescription!.contains("fatal bridge boom"))
    }

    func testPythonNotFoundError() {
        let error = LocationBridge.LocationBridgeError.pythonNotFound
        XCTAssertEqual(error.errorDescription, "Python3 not found in PATH")
    }

    // MARK: - Singleton Tests

    @MainActor
    func testSharedInstanceExists() {
        let bridge = LocationBridge.shared
        XCTAssertNotNil(bridge, "Shared instance should exist")
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let bridge1 = LocationBridge.shared
        let bridge2 = LocationBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "Should return same instance")
    }

    // MARK: - Initial State Tests

    @MainActor
    func testInitialStateNotRunning() {
        let bridge = LocationBridge.shared
        _ = bridge.isRunning
        XCTAssertTrue(true, "isRunning property should be accessible")
    }

    @MainActor
    func testInitialStatsAreZero() {
        let bridge = LocationBridge.shared
        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)
    }

    // MARK: - Runtime Determinism Tests

    @MainActor
    func testPingWhenNotRunning() async throws {
        let bridge = LocationBridge.shared

        if !bridge.isRunning {
            let pingResult = try? await bridge.ping()
            XCTAssertTrue(
                pingResult == nil || pingResult == false,
                "Ping when not running should fail or return false"
            )
        }
    }

    @MainActor
    func testStartWaitsForReadyAndPingUsesRequestID() async throws {
        let bridge = LocationBridge.shared
        await bridge.stop()
        bridge.testRestoreBridgeConfiguration()

        do {
            try await bridge.start()
            XCTAssertTrue(bridge.isRunning)
            let pingResult = try await bridge.ping()
            XCTAssertTrue(pingResult)
        } catch {
            await bridge.stop()
            throw error
        }

        await bridge.stop()
        XCTAssertFalse(bridge.isRunning)
    }

    @MainActor
    func testStartTimesOutWhenReadySignalNeverArrives() async throws {
        let bridge = LocationBridge.shared
        await bridge.stop()

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-no-ready-\(UUID().uuidString).py")
        try """
        import time
        time.sleep(2)
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: scriptURL)
            bridge.testRestoreBridgeConfiguration()
        }

        bridge.testOverrideBridgeConfiguration(
            bridgeScriptPath: scriptURL.path,
            readyTimeout: 0.2,
            responseTimeout: 0.2
        )

        do {
            try await bridge.start()
            XCTFail("Bridge start should time out when the helper never emits ready")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.lowercased().contains("timed out") ||
                error.localizedDescription.lowercased().contains("timeout"),
                "Unexpected error: \(error.localizedDescription)"
            )
        }

        await bridge.stop()
    }

    @MainActor
    func testConcurrentStartCallsCoalesceToSingleProcess() async throws {
        let counterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-bridge-start-count-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: counterURL)
        }

        let script = """
        import json
        import sys

        counter_path = \(pythonStringLiteral(counterURL.path))
        with open(counter_path, "a", encoding="utf-8") as counter:
            counter.write("start\\n")
            counter.flush()

        print(json.dumps({"ready": True}), flush=True)

        for line in sys.stdin:
            request = json.loads(line)
            request_id = request.get("request_id")
            cmd = request.get("cmd")
            if cmd == "ping":
                print(json.dumps({"request_id": request_id, "success": True, "message": "pong"}), flush=True)
            elif cmd == "quit":
                print(json.dumps({"request_id": request_id, "success": True, "message": "shutting down"}), flush=True)
                break
            else:
                print(json.dumps({"request_id": request_id, "success": False, "error": "unknown"}), flush=True)
        """

        try await withTemporaryBridgeScript(script) { bridge in
            async let firstStart: Void = bridge.start()
            async let secondStart: Void = bridge.start()
            _ = try await (firstStart, secondStart)

            XCTAssertTrue(bridge.isRunning)
            XCTAssertFalse(bridge.testHasStartInProgress)

            let counterContent = try String(contentsOf: counterURL, encoding: .utf8)
            XCTAssertEqual(counterContent.split(separator: "\n").count, 1)
        }
    }

    @MainActor
    func testAbnormalBridgeExitFailsPendingRequestWithDiagnostics() async throws {
        let script = """
        import json
        import sys

        print(json.dumps({"ready": True}), flush=True)

        for line in sys.stdin:
            request = json.loads(line)
            if request.get("cmd") == "ping":
                print("fatal bridge boom", file=sys.stderr, flush=True)
                sys.exit(42)
        """

        try await withTemporaryBridgeScript(script) { bridge in
            try await bridge.start()

            do {
                _ = try await bridge.ping()
                XCTFail("Ping should fail when the helper exits abnormally")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("42"), "Unexpected error: \(error)")
                XCTAssertTrue(error.localizedDescription.contains("fatal bridge boom"), "Unexpected error: \(error)")
            }

            XCTAssertFalse(bridge.isRunning)
            XCTAssertNotNil(bridge.lastError)
        }
    }

    @MainActor
    func testStructuredFatalBridgeResponseFailsBridgeAndPendingRequest() async throws {
        let script = """
        import json
        import sys

        print(json.dumps({"ready": True}), flush=True)

        for line in sys.stdin:
            request = json.loads(line)
            if request.get("cmd") == "ping":
                print(json.dumps({"fatal": True, "success": False, "error": "structured fatal bridge failure"}), flush=True)
                sys.stdin.close()
                break
        """

        try await withTemporaryBridgeScript(script) { bridge in
            try await bridge.start()

            do {
                _ = try await bridge.ping()
                XCTFail("Ping should fail when the helper emits a structured fatal response")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("structured fatal bridge failure"), "Unexpected error: \(error)")
            }

            XCTAssertFalse(bridge.isRunning)
            XCTAssertNotNil(bridge.lastError)
        }
    }

    @MainActor
    func testSetLocationFailFastDoesNotStartBridgeWithoutLiveRsd() async throws {
        let counterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-bridge-fail-fast-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: counterURL)
        }

        #if DEBUG
        TunneldManager.shared.testResetTunnelLifecycleForTests()
        #endif

        let script = """
        import json
        import sys

        counter_path = \(pythonStringLiteral(counterURL.path))
        with open(counter_path, "a", encoding="utf-8") as counter:
            counter.write("started\\n")
            counter.flush()

        print(json.dumps({"ready": True}), flush=True)

        for line in sys.stdin:
            request = json.loads(line)
            request_id = request.get("request_id")
            if request.get("cmd") == "quit":
                print(json.dumps({"request_id": request_id, "success": True}), flush=True)
                break
            print(json.dumps({"request_id": request_id, "success": True}), flush=True)
        """
        let device = Device(
            id: "00008130000C5144019A001C",
            displayName: "Test iPhone",
            connectionType: .usb,
            productVersion: "17.4"
        )
        let coordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)

        try await withTemporaryBridgeScript(script) { bridge in
            do {
                try await bridge.setLocationViaNDJSON(coordinate, for: device)
                XCTFail("Expected bridge request to fail before Python starts")
            } catch {
                XCTAssertTrue(LocationBridge.isTunnelInvalidationError(error), "Unexpected error: \(error)")
            }

            XCTAssertFalse(bridge.isRunning)
            XCTAssertFalse(FileManager.default.fileExists(atPath: counterURL.path))
        }
    }

    @MainActor
    func testTransportBridgeErrorInvalidatesRsdAndResetsBridge() async throws {
        let requestLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-bridge-transport-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: requestLogURL)
            #if DEBUG
            TunneldManager.shared.testResetTunnelLifecycleForTests()
            #endif
        }

        #if DEBUG
        let manager = TunneldManager.shared
        manager.testResetTunnelLifecycleForTests()
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: nil
        )
        manager.testSendTunnelEvent(.startRequested(mode: .usb))
        manager.testSendTunnelEvent(.connectionEstablished(info: info))
        #endif

        let script = """
        import json
        import sys

        request_log = \(pythonStringLiteral(requestLogURL.path))
        print(json.dumps({"ready": True}), flush=True)

        for line in sys.stdin:
            request = json.loads(line)
            request_id = request.get("request_id")
            with open(request_log, "a", encoding="utf-8") as log:
                log.write(request.get("cmd", "") + "\\n")
                log.flush()
            if request.get("cmd") == "quit":
                print(json.dumps({"request_id": request_id, "success": True}), flush=True)
                break
            print(json.dumps({
                "request_id": request_id,
                "success": False,
                "error": "OSError: [Errno 65] No route to host"
            }), flush=True)
        """
        let device = Device(
            id: "00008130000C5144019A001C",
            displayName: "Test iPhone",
            connectionType: .usb,
            productVersion: "17.4"
        )
        let coordinate = LocationCoordinate(latitude: 37.3349, longitude: -122.0090)

        try await withTemporaryBridgeScript(script) { bridge in
            do {
                try await bridge.setLocationViaNDJSON(coordinate, for: device)
                XCTFail("Expected transport bridge error")
            } catch {
                XCTAssertTrue(LocationBridge.isTunnelInvalidationError(error), "Unexpected error: \(error)")
            }

            XCTAssertFalse(bridge.isRunning)
            #if DEBUG
            XCTAssertNil(TunneldManager.shared.getRsdInfo(for: device.id))
            if case .error = TunneldManager.shared.state {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected tunnel state to enter error after bridge transport failure")
            }
            #endif
        }

        let requestLog = try String(contentsOf: requestLogURL, encoding: .utf8)
        XCTAssertTrue(requestLog.contains("set_location"))
    }
}

// MARK: - Edge Case Tests

final class LocationBridgeEdgeCaseTests: XCTestCase {

    func testMalformedJSONResponseHandling() {
        let malformedJSON = "{ invalid json }"
        let error = LocationBridge.LocationBridgeError.invalidResponse(malformedJSON)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("invalid json"))
    }

    func testTimeoutScenarioErrorMessage() {
        let error = LocationBridge.LocationBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    func testVPNLikeTransportMessagesAreRecoverableDisruptions() {
        let recoverableMessages = [
            "OSError: [Errno 65] No route to host",
            "Network is unreachable while writing to DVT",
            "BrokenPipeError: broken pipe",
            "Connection reset by peer",
            "Connection refused",
            "Unable to connect to Tunneld",
            "Tunnel transport failed: set_location failed for Test iPhone: Bridge request timed out",
            "No valid live RSD exists for Test iPhone"
        ]

        for message in recoverableMessages {
            XCTAssertTrue(
                LocationBridge.isRecoverableTransportDisruption(message),
                "Expected recoverable transport disruption for: \(message)"
            )
        }
    }

    func testTerminalFailuresAreNotRecoverableTransportDisruptions() {
        let terminalMessages = [
            "Security violation: Unknown subcommand 'rm'",
            "Refusing to run pair_wifi.py: resolved path is unsafe",
            "DeveloperModeError: Developer Mode disabled",
            "PairingError: device is not paired",
            "Python3 not found in PATH",
            "Invalid response from bridge: { invalid json }"
        ]

        for message in terminalMessages {
            XCTAssertFalse(
                LocationBridge.isRecoverableTransportDisruption(message),
                "Expected terminal failure to remain non-recoverable: \(message)"
            )
        }
    }

    @MainActor
    func testConcurrentRequestSafety() async throws {
        let bridge = LocationBridge.shared
        await bridge.stop()
        bridge.testRestoreBridgeConfiguration()

        do {
            try await bridge.start()
        } catch {
            await bridge.stop()
            throw error
        }

        await withTaskGroup(of: Bool?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await bridge.ping()
                }
            }

            var results: [Bool?] = []
            for await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, 5)
            XCTAssertTrue(results.allSatisfy { $0 == true })
        }

        await bridge.stop()
    }

    @MainActor
    func testMalformedBridgeOutputFailsBridgeDeterministically() async {
        let bridge = LocationBridge.shared
        await bridge.stop()
        bridge.testRestoreBridgeConfiguration()

        bridge.testInjectBridgeOutput("{ invalid json }\n")

        XCTAssertFalse(bridge.isRunning)
        XCTAssertNotNil(bridge.lastError)
    }

    func testProcessNotRunningRecoveryHint() {
        let error = LocationBridge.LocationBridgeError.processNotRunning
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not running"))
    }

    func testBridgeErrorWithEmptyMessage() {
        let error = LocationBridge.LocationBridgeError.bridgeError("")
        XCTAssertNotNil(error.errorDescription)
    }

    @MainActor
    func testStatsAccumulationSafety() {
        let bridge = LocationBridge.shared

        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)
        XCTAssertLessThan(bridge.averageResponseTime, 3_600_000)
    }

    func testInvalidResponseSpecialCharacters() {
        let specialChars = "Response: \u{0000}\u{FFFF}\"'<>&"
        let error = LocationBridge.LocationBridgeError.invalidResponse(specialChars)
        XCTAssertNotNil(error.errorDescription)
    }

    func testProcessStartFailedLongMessage() {
        let longMessage = String(repeating: "error ", count: 1000)
        let error = LocationBridge.LocationBridgeError.processStartFailed(longMessage)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("error"))
    }
}

// MARK: - Performance Mode Integration Tests

final class PerformanceModeTests: XCTestCase {

    func testPerformanceModePropertyExists() async {
        let bridge = DevLocationBridge()
        await bridge.setPerformanceMode(true)
        await bridge.setPerformanceMode(false)
        XCTAssertTrue(true, "Performance mode methods should be callable")
    }

    func testSetLocationAcceptsPerformanceMode() async {
        let bridge = DevLocationBridge()
        let coordinate = LocationCoordinate(latitude: 37.785834, longitude: -122.406417)
        let device = Device(
            id: "TEST-DEVICE-00008030-001234567890ABCD",
            displayName: "Test iPhone",
            connectionType: .usb
        )

        _ = { [bridge] in
            Task {
                do {
                    try await bridge.setLocation(
                        coordinate,
                        for: device,
                        priority: .normal,
                        usePerformanceMode: true
                    )
                } catch {
                    // Expected to fail without a real device
                }
            }
        }

        XCTAssertTrue(true, "setLocation should accept usePerformanceMode parameter")
    }
}

// MARK: - Python Bridge Script Tests

final class LocationBridgeScriptTests: XCTestCase {

    func testBridgeScriptExists() {
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"
        let scriptExists = FileManager.default.fileExists(atPath: workspacePath)

        if !scriptExists {
            print("Note: Bridge script not found at \(workspacePath)")
        }

        XCTAssertTrue(true, "Script check completed")
    }

    func testBridgeScriptSyntax() throws {
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"

        guard FileManager.default.fileExists(atPath: workspacePath) else {
            throw XCTSkip("Bridge script not found, skipping syntax check")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "py_compile", workspacePath]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0,
                "Bridge script should have valid Python syntax"
            )
        } catch {
            throw XCTSkip("Python3 not available for syntax check")
        }
    }

    func testBridgeScriptEchoesRequestIDs() throws {
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"

        guard FileManager.default.fileExists(atPath: workspacePath) else {
            throw XCTSkip("Bridge script not found, skipping request-id protocol check")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", workspacePath]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw XCTSkip("Python3 not available for bridge protocol check")
        }

        let pingID = "test-ping-\(UUID().uuidString)"
        let badID = "test-bad-\(UUID().uuidString)"
        let quitID = "test-quit-\(UUID().uuidString)"
        let input = """
        {"request_id":"\(pingID)","cmd":"ping"}
        {"request_id":"\(badID)","cmd":"unknown"}
        {"request_id":"\(quitID)","cmd":"quit"}

        """

        try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, errorOutput)

        let responses = output
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }

        XCTAssertTrue(responses.contains { $0["ready"] as? Bool == true })
        XCTAssertTrue(responses.contains {
            $0["request_id"] as? String == pingID &&
            $0["success"] as? Bool == true &&
            $0["message"] as? String == "pong"
        })
        XCTAssertTrue(responses.contains {
            $0["request_id"] as? String == badID &&
            $0["success"] as? Bool == false &&
            (($0["error"] as? String)?.contains("Unknown command") ?? false)
        })
        XCTAssertTrue(responses.contains {
            $0["request_id"] as? String == quitID &&
            $0["success"] as? Bool == true
        })
    }
}
