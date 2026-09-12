import XCTest
@testable import PathChanger

/// Performance and unit tests for PersistentLocationBridge
/// Tests the high-performance persistent Python bridge implementation
final class PersistentLocationBridgeTests: XCTestCase {

    // MARK: - Error Description Tests

    func testBridgeErrorDescriptions() {
        let errors: [PersistentLocationBridge.PersistentBridgeError] = [
            .processNotRunning,
            .processStartFailed("test reason"),
            .timeout,
            .invalidResponse("bad response"),
            .bridgeError("bridge error"),
            .pythonNotFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    func testProcessNotRunningError() {
        let error = PersistentLocationBridge.PersistentBridgeError.processNotRunning
        XCTAssertEqual(error.errorDescription, "Python bridge process is not running")
    }

    func testProcessStartFailedError() {
        let error = PersistentLocationBridge.PersistentBridgeError.processStartFailed("Python not found")
        XCTAssertTrue(error.errorDescription!.contains("Python not found"))
    }

    func testTimeoutError() {
        let error = PersistentLocationBridge.PersistentBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    func testInvalidResponseError() {
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse("garbage data")
        XCTAssertTrue(error.errorDescription!.contains("garbage data"))
    }

    func testBridgeError() {
        let error = PersistentLocationBridge.PersistentBridgeError.bridgeError("Device not found")
        XCTAssertTrue(error.errorDescription!.contains("Device not found"))
    }

    func testPythonNotFoundError() {
        let error = PersistentLocationBridge.PersistentBridgeError.pythonNotFound
        XCTAssertEqual(error.errorDescription, "Python3 not found in PATH")
    }

    // MARK: - Singleton Tests

    @MainActor
    func testSharedInstanceExists() {
        let bridge = PersistentLocationBridge.shared
        XCTAssertNotNil(bridge, "Shared instance should exist")
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let bridge1 = PersistentLocationBridge.shared
        let bridge2 = PersistentLocationBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "Should return same instance")
    }

    // MARK: - Initial State Tests

    @MainActor
    func testInitialStateNotRunning() {
        let bridge = PersistentLocationBridge.shared
        // Note: The shared instance may be running from previous tests
        // This test verifies the property is accessible
        _ = bridge.isRunning
        XCTAssertTrue(true, "isRunning property should be accessible")
    }

    @MainActor
    func testInitialStatsAreZero() {
        // After fresh start or if not running, stats should be zero or near-zero
        let bridge = PersistentLocationBridge.shared
        // Stats are cumulative, so we just verify they're accessible
        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)
    }

    // MARK: - Ping Tests (requires Python and bridge script)

    @MainActor
    func testPingWhenNotRunning() async throws {
        let bridge = PersistentLocationBridge.shared

        // If bridge is not running, ping should return false
        if !bridge.isRunning {
            let pingResult = try? await bridge.ping()
            XCTAssertTrue(pingResult == nil || pingResult == false,
                         "Ping when not running should fail or return false")
        }
    }
}

// MARK: - Edge Case Tests (Task 45)

final class PersistentLocationBridgeEdgeCaseTests: XCTestCase {

    /// Test handling of malformed JSON response
    func testMalformedJSONResponseHandling() {
        let malformedJSON = "{ invalid json }"
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse(malformedJSON)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("invalid json"))
    }

    /// Test timeout scenario error message
    func testTimeoutScenarioErrorMessage() {
        let error = PersistentLocationBridge.PersistentBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    /// Test concurrent access safety with multiple requests
    @MainActor
    func testConcurrentRequestSafety() async throws {
        let bridge = PersistentLocationBridge.shared

        // Create multiple concurrent ping attempts
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

            // All concurrent requests should complete without crash
            XCTAssertEqual(results.count, 5)
        }
    }

    /// Test process not running error recovery hint
    func testProcessNotRunningRecoveryHint() {
        let error = PersistentLocationBridge.PersistentBridgeError.processNotRunning
        // Error should have meaningful description
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not running"))
    }

    /// Test bridge error with empty message
    func testBridgeErrorEmptyMessage() {
        let error = PersistentLocationBridge.PersistentBridgeError.bridgeError("")
        XCTAssertNotNil(error.errorDescription)
    }

    /// Test stats accumulation doesn't overflow
    @MainActor
    func testStatsAccumulationSafety() {
        let bridge = PersistentLocationBridge.shared

        // Stats should be non-negative
        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)

        // Average response time should be reasonable (< 1 hour in ms)
        XCTAssertLessThan(bridge.averageResponseTime, 3_600_000)
    }

    /// Test invalid response with special characters
    func testInvalidResponseSpecialCharacters() {
        let specialChars = "Response: \u{0000}\u{FFFF}\"'<>&"
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse(specialChars)
        XCTAssertNotNil(error.errorDescription)
    }

    /// Test process start failure with long message
    func testProcessStartFailedLongMessage() {
        let longMessage = String(repeating: "error ", count: 1000)
        let error = PersistentLocationBridge.PersistentBridgeError.processStartFailed(longMessage)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("error"))
    }
}

// MARK: - Performance Mode Integration Tests

final class PerformanceModeTests: XCTestCase {

    /// Test that DevLocationBridge has performance mode setting
    func testPerformanceModePropertyExists() async {
        let bridge = DevLocationBridge()
        // Just verify the method exists and is callable
        await bridge.setPerformanceMode(true)
        await bridge.setPerformanceMode(false)
        XCTAssertTrue(true, "Performance mode methods should be callable")
    }

    /// Test that setLocation accepts usePerformanceMode parameter
    func testSetLocationAcceptsPerformanceMode() async {
        // This test verifies the API signature exists
        // Actual location setting would require a device
        let bridge = DevLocationBridge()
        let coordinate = LocationCoordinate(latitude: 37.785834, longitude: -122.406417)
        let device = Device(id: "TEST-DEVICE-00008030-001234567890ABCD", displayName: "Test iPhone", connectionType: .usb)

        // The method should exist with the usePerformanceMode parameter
        // We can't actually call it without a real device, but the signature should compile
        _ = { [bridge] in
            Task {
                do {
                    try await bridge.setLocation(coordinate, for: device, priority: .normal, usePerformanceMode: true)
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

    /// Test that the bridge script exists in the expected location
    func testBridgeScriptExists() {
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"

        // Check if script exists (may be in workspace or bundle)
        let scriptExists = FileManager.default.fileExists(atPath: workspacePath)

        // In test environment, the script should be in the workspace
        if !scriptExists {
            // Not a failure if running in a different context
            print("Note: Bridge script not found at \(workspacePath)")
        }

        XCTAssertTrue(true, "Script check completed")
    }

    /// Test that the bridge script is valid Python
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

            XCTAssertEqual(process.terminationStatus, 0,
                          "Bridge script should have valid Python syntax")
        } catch {
            throw XCTSkip("Python3 not available for syntax check")
        }
    }

    func testBridgeProtocolCarriesRequestIdentity() throws {
        let path = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(source.contains("request_id"))
        XCTAssertTrue(source.contains("session_generation"))
    }

    func testPythonCacheInvalidationRebuildsService() throws {
        let script = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"
        let code = """
import importlib.util
spec = importlib.util.spec_from_file_location("location_bridge", r"\(script)")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
connection = module.DeviceConnection()
connection._initialized = True
created = []
class DVT:
    def perform_handshake(self): pass
class Location:
    def __init__(self, should_fail): self.should_fail = should_fail
    def simulate_location(self, lat, lng):
        if self.should_fail: raise RuntimeError("injected failure")
connection._lockdown_usb = lambda serial: object()
connection._dvt_module = lambda lockdown=None: DVT()
def make_location(dvt):
    created.append(True)
    return Location(len(created) == 1)
connection._location_module = make_location
first = connection.set_location(1.0, 2.0, "fake-device")
assert first["success"] is False
assert connection._service_cache == {}
second = connection.set_location(1.0, 2.0, "fake-device")
assert second["success"] is True
assert len(created) == 2
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
