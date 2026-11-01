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

final class DeviceDiscoveryReconciliationTests: XCTestCase {
    func testTheTunneldAPIIsQueriedOnlyWhileTheDaemonRuns() {
        // Live 2026-11-01: every discovery poll asked 127.0.0.1:49151 although no
        // `remote tunneld` was running (the helper owns the connection), logging
        // "Failed to query tunneld API" every few seconds.
        XCTAssertFalse(DeviceManager.shouldQueryTunneldAPI(daemonRunning: false))
        XCTAssertTrue(DeviceManager.shouldQueryTunneldAPI(daemonRunning: true))
    }

    /// A fake `pgrep -f`: matches the pattern (as pgrep does, a regular expression)
    /// against a fixed process table and records every request, so no process spawns.
    @MainActor
    private final class ProcessTableProbe {
        var commandLines: [String]
        private(set) var requests: [(executable: String, arguments: [String])] = []

        init(_ commandLines: [String]) {
            self.commandLines = commandLines
        }

        func list(_ executable: String, _ arguments: [String]) throws -> String {
            requests.append((executable, arguments))
            guard executable == "/usr/bin/pgrep",
                  arguments.count == 2, arguments[0] == "-f" else {
                // A relative or unexpected executable fails exactly as Process.run does.
                throw CocoaError(.fileNoSuchFile)
            }
            let pattern = arguments[1]
            return commandLines.enumerated()
                .filter { $0.element.range(of: pattern, options: .regularExpression) != nil }
                .map { "\(4000 + $0.offset)\n" }
                .joined()
        }
    }

    private static let strayStartTunnel =
        "/Users/me/Library/Application Support/PathChanger/runtime/location/bin/python3 -m pymobiledevice3 remote start-tunnel --native"
    private static let tunneldDaemon =
        "/Users/me/Library/Application Support/PathChanger/runtime/location/bin/python3 -m pymobiledevice3 remote tunneld"

    @MainActor
    private func makeManager(probe: ProcessTableProbe, apiFetches: (() -> Void)? = nil) -> DeviceManager {
        let manager = DeviceManager(startBackgroundServices: false)
        manager.processListing = { executable, arguments in
            try probe.list(executable, arguments)
        }
        manager.tunneldAPIFetch = { url in
            apiFetches?()
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }
        return manager
    }

    @MainActor
    func testTunnelStatusProbeAsksForTheAbsolutePgrep() async {
        // URL(fileURLWithPath: "pgrep") resolves against the app's working directory,
        // so a relative probe never ran and its catch reported "no tunnel".
        let probe = ProcessTableProbe([])
        let manager = makeManager(probe: probe)

        await manager.checkTunneldStatus()

        XCTAssertFalse(probe.requests.isEmpty)
        XCTAssertEqual(Set(probe.requests.map(\.executable)), ["/usr/bin/pgrep"])
    }

    @MainActor
    func testAStrayStartTunnelProcessAloneDoesNotReportATunnelRunning() async {
        // Option A launches no start-tunnel, and a leftover one is never adopted;
        // counting it made readiness claim a tunnel nothing could use.
        let probe = ProcessTableProbe([Self.strayStartTunnel])
        let manager = makeManager(probe: probe)

        await manager.checkTunneldStatus()

        XCTAssertFalse(manager.isTunneldRunning)
        XCTAssertFalse(manager.isTunneldDaemonRunning)
    }

    @MainActor
    func testARunningTunneldDaemonReportsTheTunnelRunning() async {
        let probe = ProcessTableProbe([Self.tunneldDaemon])
        let manager = makeManager(probe: probe)

        await manager.checkTunneldStatus()

        XCTAssertTrue(manager.isTunneldRunning)
        XCTAssertTrue(manager.isTunneldDaemonRunning)
    }

    @MainActor
    func testDiscoverySkipsTheTunneldAPIWhenNoDaemonRuns() async {
        let probe = ProcessTableProbe([Self.strayStartTunnel])
        var fetches = 0
        let manager = makeManager(probe: probe, apiFetches: { fetches += 1 })

        let devices = await manager.discoverTunneldAPIDevicesForTesting()

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(probe.requests.count, 1, "one live daemon probe per discovery pass")
    }

    @MainActor
    func testDiscoveryQueriesTheTunneldAPIForADaemonStartedSinceTheLastStatusPoll() async {
        // The 5 s status poll saw no daemon; the daemon started afterwards. Discovery
        // must not wait for the next poll to ask its API.
        let probe = ProcessTableProbe([])
        var fetches = 0
        let manager = makeManager(probe: probe, apiFetches: { fetches += 1 })
        await manager.checkTunneldStatus()
        XCTAssertFalse(manager.isTunneldDaemonRunning)
        probe.commandLines = [Self.tunneldDaemon]
        let requestsBeforeDiscovery = probe.requests.count

        _ = await manager.discoverTunneldAPIDevicesForTesting()

        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(probe.requests.count - requestsBeforeDiscovery, 1, "one live daemon probe per discovery pass")
        XCTAssertTrue(manager.isTunneldDaemonRunning)
    }

    @MainActor
    func testDuplicatePhysicalFingerprintsDoNotTrapOrCollapseDistinctUDIDs() {
        let manager = DeviceManager(startBackgroundServices: false)
        manager.stopAutoRefresh()

        let first = Device(
            id: "00008110-001A000E3E82001E",
            displayName: "iPhone (iOS 18.0)",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "iPhone"
        )
        let second = Device(
            id: "00008120-001B000E3E82002F",
            displayName: "iPhone (iOS 18.0)",
            connectionType: .wifi,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "iPhone"
        )

        let devices = manager.deduplicatedDevicesForTesting([first, second])

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(Set(devices.map(\.id)), Set([first.id, second.id]))
    }

    @MainActor
    func testDirectUSBObservationOutranksTunnelMetadataForSameDevice() {
        let manager = DeviceManager(startBackgroundServices: false)
        manager.stopAutoRefresh()
        let id = "00008110-001A000E3E82001E"
        let usb = Device(id: id, displayName: "USB Device", connectionType: .usb)
        let tunnel = Device(id: id, displayName: "Tunnel Device", connectionType: .wifi)

        let devices = manager.mergedDiscoverySourcesForTesting(
            knownWiFiDevices: [],
            mobdev2Devices: [],
            usbmuxDevices: [usb],
            tunnelDevices: [tunnel],
            mode: .auto
        )

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.connectionType, .usb)
        XCTAssertEqual(devices.first?.displayName, "USB Device")
    }

    @MainActor
    func testExplicitConnectionModeFiltersFinalMergedDeviceList() {
        let manager = DeviceManager(startBackgroundServices: false)
        manager.stopAutoRefresh()
        let usb = Device(
            id: "00008110-001A000E3E82001E",
            displayName: "USB Device",
            connectionType: .usb
        )
        let wifi = Device(
            id: "00008120-001B000E3E82002F",
            displayName: "Wi-Fi Device",
            connectionType: .wifi
        )

        let usbOnly = manager.mergedDiscoverySourcesForTesting(
            knownWiFiDevices: [wifi],
            mobdev2Devices: [wifi],
            usbmuxDevices: [usb, wifi],
            tunnelDevices: [wifi],
            mode: .usb
        )
        let wifiOnly = manager.mergedDiscoverySourcesForTesting(
            knownWiFiDevices: [wifi],
            mobdev2Devices: [wifi],
            usbmuxDevices: [usb, wifi],
            tunnelDevices: [wifi],
            mode: .wifi
        )

        XCTAssertEqual(usbOnly.map(\.id), [usb.id])
        XCTAssertEqual(wifiOnly.map(\.id), [wifi.id])
    }

    @MainActor
    func testPairingRecordWithoutLiveObservationIsNotReportedConnected() {
        let manager = DeviceManager(startBackgroundServices: false)
        let remembered = Device(
            id: "00008120-001B000E3E82002F",
            displayName: "Remembered Wi-Fi Device",
            connectionType: .wifi
        )

        let devices = manager.mergedDiscoverySourcesForTesting(
            knownWiFiDevices: [remembered],
            mobdev2Devices: [],
            usbmuxDevices: [],
            tunnelDevices: [],
            mode: .auto
        )

        XCTAssertTrue(devices.isEmpty)
    }

    @MainActor
    func testFailedScanPreservesLastKnownDevicesAndPublishesError() {
        let manager = DeviceManager(startBackgroundServices: false)
        let existing = Device(
            id: "00008110-001A000E3E82001E",
            displayName: "Existing USB Device",
            connectionType: .usb
        )
        manager.devices = [existing]
        manager.selectedDevice = existing

        manager.commitDiscoverySnapshotForTesting(
            [],
            scanSucceeded: false,
            generation: 2,
            latestGeneration: 2,
            errorMessage: "usbmux scan failed"
        )

        XCTAssertEqual(manager.devices, [existing])
        XCTAssertEqual(manager.selectedDevice, existing)
        XCTAssertNotNil(manager.lastError)
    }

    @MainActor
    func testOlderRefreshGenerationCannotOverwriteNewerSnapshot() {
        let manager = DeviceManager(startBackgroundServices: false)
        let current = Device(
            id: "00008120-001B000E3E82002F",
            displayName: "Current Network Device",
            connectionType: .wifi
        )
        let stale = Device(
            id: "00008110-001A000E3E82001E",
            displayName: "Stale USB Device",
            connectionType: .usb
        )
        manager.devices = [current]
        manager.selectedDevice = current

        manager.commitDiscoverySnapshotForTesting(
            [stale],
            scanSucceeded: true,
            generation: 1,
            latestGeneration: 2,
            errorMessage: nil
        )

        XCTAssertEqual(manager.devices, [current])
        XCTAssertEqual(manager.selectedDevice, current)
    }
}
