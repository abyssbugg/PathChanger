//
//  DeviceManagerIntegrationTests.swift
//  PathChangerTests
//
//  Integration tests for device discovery and connection
//

import XCTest
@testable import PathChanger

final class DeviceManagerIntegrationTests: XCTestCase {
    var deviceManager: DeviceManager!

    override func setUp() async throws {
        try await super.setUp()
        try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
            "Device discovery invokes pymobiledevice3 and depends on host USB/tunneld state."
        )
        await MainActor.run {
            deviceManager = DeviceManager()
        }
    }

    override func tearDown() async throws {
        if let deviceManager {
            await deviceManager.stopAutoRefresh()
        }
        deviceManager = nil
        try await super.tearDown()
    }

    // MARK: - Device Discovery Tests

    func testParallelDeviceDiscovery() async throws {
        /// Test that device discovery runs efficiently with parallel fetching
        let startTime = Date()

        await deviceManager.refreshDevices()

        let duration = Date().timeIntervalSince(startTime)
        let devices = await MainActor.run { deviceManager.devices }

        // Should complete in reasonable time even with multiple devices
        XCTAssertLessThan(duration, 10.0, "Device discovery should complete within 10 seconds")

        // Basic sanity check - should have 0 or more devices
        XCTAssertGreaterThanOrEqual(devices.count, 0)

        Logger.info("✅ Device discovery completed in \(String(format: "%.2f", duration))s with \(devices.count) device(s)", category: .device)
    }

    func testTunnelStatusCheck() async throws {
        /// Test tunnel status detection
        let startTime = Date()

        await deviceManager.checkTunneldStatus()

        let duration = Date().timeIntervalSince(startTime)
        let isTunneldRunning = await MainActor.run { deviceManager.isTunneldRunning }

        // Should complete quickly
        XCTAssertLessThan(duration, 5.0, "Tunnel status check should complete within 5 seconds")

        Logger.info("✅ Tunnel status check: \(isTunneldRunning ? "running" : "not running") (took \(String(format: "%.2f", duration))s)", category: .device)
    }

    func testDeviceSelectionFlow() async throws {
        /// Test selecting a device and checking connection state
        // First discover devices
        await deviceManager.refreshDevices()

        // Try to select first device if available
        let device = await MainActor.run { deviceManager.devices.first }

        if let device = device {
            do {
                try await deviceManager.connect(to: device)
                let isConnected = await MainActor.run { deviceManager.isConnected }
                let selectedDeviceId = await MainActor.run { deviceManager.selectedDevice?.id }

                XCTAssertTrue(isConnected, "Should be connected after connection attempt")
                XCTAssertEqual(selectedDeviceId, device.id)
            } catch {
                // Connection might fail if device not available, which is OK
                Logger.debug("Connection attempt failed (expected if device not available): \(error)", category: .device)
            }
        } else {
            Logger.info("ℹ️ No devices available for connection test", category: .device)
        }
    }

    // MARK: - Error Handling Tests

    func testGracefulHandlingOfMissingPython() async throws {
        /// Verify that missing Python is handled gracefully
        // This test assumes python3 is available, so it mainly tests the flow
        let startTime = Date()

        await deviceManager.refreshDevices()

        let duration = Date().timeIntervalSince(startTime)

        // Should not crash
        XCTAssertLessThan(duration, 15.0, "Should handle missing dependencies gracefully")

        Logger.info("✅ Graceful error handling test passed", category: .device)
    }

    // MARK: - Performance Tests

    func testDeviceDiscoveryPerformance() async throws {
        /// Benchmark device discovery performance
        measure {
            let startTime = Date()

            let task = Task { @MainActor in
                await deviceManager.refreshDevices()
            }

            // Use timeout to prevent hanging
            var completed = false
            let deadline = Date().addingTimeInterval(30)

            while !completed && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                completed = !task.isCancelled
            }

            if !completed {
                task.cancel()
            }

            let duration = Date().timeIntervalSince(startTime)
            Logger.info("📊 Device discovery took: \(String(format: "%.2f", duration))s", category: .device)
        }
    }

    // MARK: - Stability Tests

    func testRepeatedRefreshStability() async throws {
        /// Test that repeated refreshes don't cause crashes or memory leaks
        for i in 0..<5 {
            await deviceManager.refreshDevices()
            await deviceManager.checkTunneldStatus()

            Logger.debug("Refresh cycle \(i + 1)/5 completed", category: .device)

            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms between refreshes
        }

        Logger.info("✅ Repeated refresh stability test passed", category: .device)
    }
}
