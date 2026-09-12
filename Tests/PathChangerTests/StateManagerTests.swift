//
//  StateManagerTests.swift
//  PathChangerTests
//
//  Tests for domain-specific state managers (ARCH-002).
//

import XCTest
@testable import PathChanger

// MARK: - Simulation State Manager Tests

final class SimulationStateManagerTests: XCTestCase {

    @MainActor
    func testInitialState() async {
        let manager = SimulationStateManager()

        XCTAssertFalse(manager.isSimulating)
        XCTAssertFalse(manager.isPaused)
        XCTAssertEqual(manager.simulationSpeed, .walking)
        XCTAssertEqual(manager.activeMode, .teleport)
        XCTAssertNil(manager.currentLocation)
        XCTAssertNil(manager.targetLocation)
        XCTAssertEqual(manager.joystickDirection, .zero)
    }

    @MainActor
    func testEffectiveSpeedFollowsAutoSpeedFlag() async {
        let manager = SimulationStateManager()

        manager.autoSpeed = true
        manager.setSpeed(.cycling)
        XCTAssertEqual(manager.effectiveMetersPerSecond, SimulationSpeed.cycling.presetMetersPerSecond)

        manager.autoSpeed = false
        manager.customSpeedMps = 9.9
        XCTAssertEqual(manager.effectiveMetersPerSecond, 9.9)
    }

    @MainActor
    func testCanStartSimulationRequiresDeviceState() async {
        let manager = SimulationStateManager()

        // No device state manager set
        XCTAssertFalse(manager.canStartSimulation)
    }

    @MainActor
    func testStatusTextWithNoDeviceState() async {
        let manager = SimulationStateManager()

        XCTAssertEqual(manager.statusText, "Initializing...")
    }

    @MainActor
    func testPauseAndResumeSimulation() async {
        let manager = SimulationStateManager()

        manager.isSimulating = true
        manager.pauseSimulation()

        XCTAssertTrue(manager.isPaused)

        manager.resumeSimulation()

        XCTAssertFalse(manager.isPaused)
    }

    @MainActor
    func testUpdateJoystickDirectionStoresVector() async {
        let manager = SimulationStateManager()

        manager.updateJoystickDirection(CGPoint(x: 0.5, y: 0.5))

        XCTAssertEqual(manager.joystickDirection, CGPoint(x: 0.5, y: 0.5))

        // Deciding whether a stick movement should start a simulation needs the planner,
        // so it belongs to the composition root rather than to this manager.
        XCTAssertEqual(manager.activeMode, .teleport)
    }

    @MainActor
    func testResetJoystickClearsVector() async {
        let manager = SimulationStateManager()

        manager.updateJoystickDirection(CGPoint(x: 0.4, y: -0.6))
        manager.resetJoystick()

        XCTAssertEqual(manager.joystickDirection, .zero)
    }

    @MainActor
    func testSetSpeed() async {
        let manager = SimulationStateManager()

        manager.setSpeed(.driving)

        XCTAssertEqual(manager.simulationSpeed, .driving)
    }

    @MainActor
    func testAppModeCoversEveryUserFacingMode() {
        // `AppMode` replaced a four-case `ActiveSimulationMode` that could not represent
        // Jump or Two-spot. Guard against that regression.
        let modes = Set(AppMode.allCases)
        XCTAssertTrue(modes.contains(.teleport))
        XCTAssertTrue(modes.contains(.jump))
        XCTAssertTrue(modes.contains(.twospot))
        XCTAssertTrue(modes.contains(.route))
        XCTAssertTrue(modes.contains(.joystick))
        XCTAssertEqual(AppMode.mapModes.count, 5)
    }

    @MainActor
    func testStopAndClearAreDistinctLocationSemantics() async {
        let manager = SimulationStateManager()
        let target = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let receipt = LocationInjectionReceipt(requestID: UUID(), session: UUID(), coordinate: target, completedAt: Date(timeIntervalSince1970: 0), outcome: .applied)
        manager.desiredLocation = target
        manager.lastAcknowledgedReceipt = receipt
        manager.locationApplication = .active(receipt)
        manager.isSimulating = true
        manager.pauseSimulation()
        XCTAssertTrue(manager.isPaused)
        XCTAssertTrue(manager.locationApplication.isActive)
        XCTAssertEqual(manager.desiredLocation, target)
        manager.isSimulating = false
        XCTAssertTrue(manager.locationApplication.isActive)
        manager.clearLocationSession()
        XCTAssertNil(manager.desiredLocation)
        XCTAssertNil(manager.lastAcknowledgedReceipt)
        XCTAssertEqual(manager.locationApplication, .idle)
    }

    @MainActor
    func testTunnelLossMarksGUIInactiveWhileLocationStateIsUncertain() {
        let manager = SimulationStateManager()
        let target = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let receipt = LocationInjectionReceipt(requestID: UUID(), session: UUID(), coordinate: target, completedAt: Date(timeIntervalSince1970: 0), outcome: .applied)
        manager.desiredLocation = target
        manager.lastAcknowledgedReceipt = receipt
        manager.locationApplication = .active(receipt)
        manager.isTunnelCallbackActive = false
        manager.locationApplication = .uncertain(lastReceipt: receipt, reason: "tunnel callback inactive")
        XCTAssertFalse(manager.isTunnelCallbackActive)
        XCTAssertFalse(manager.locationApplication.isActive)
        XCTAssertEqual(manager.locationApplication, .uncertain(lastReceipt: receipt, reason: "tunnel callback inactive"))
        XCTAssertEqual(manager.desiredLocation, target)
        XCTAssertEqual(manager.lastAcknowledgedReceipt, receipt)
    }

    @MainActor
    func testJoystickDisengageStopsMovementButPreservesAppliedLocation() {
        let manager = SimulationStateManager()
        let target = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let receipt = LocationInjectionReceipt(requestID: UUID(), session: UUID(), coordinate: target, completedAt: Date(timeIntervalSince1970: 0), outcome: .applied)
        manager.desiredLocation = target
        manager.lastAcknowledgedReceipt = receipt
        manager.locationApplication = .active(receipt)
        manager.isSimulating = true
        manager.updateJoystickDirection(CGPoint(x: 0.5, y: -0.5))
        manager.resetJoystick()
        manager.isSimulating = false
        XCTAssertFalse(manager.isSimulating)
        XCTAssertEqual(manager.joystickDirection, .zero)
        XCTAssertTrue(manager.locationApplication.isActive)
        XCTAssertEqual(manager.desiredLocation, target)
        XCTAssertEqual(manager.lastAcknowledgedReceipt, receipt)
    }

    @MainActor
    func testApplicationCoordinateNeverMutatesRequestedTarget() {
        let manager = SimulationStateManager()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        XCTAssertEqual(manager.coordinateForApplication(target), target)
    }

    @MainActor
    func testLegacyLocationSemanticsAreRemovedDuringMigration() {
        let suite = "Task10LegacyLocationSemantics"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in AppSettings.legacyLocationSemanticsKeys {
            defaults.set(true, forKey: key)
        }

        AppSettings.removeLegacyLocationSemantics(from: defaults)

        for key in AppSettings.legacyLocationSemanticsKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }
}

// MARK: - Device State Manager Direct Transport Tests

@MainActor
final class DeviceStateManagerDirectTransportTests: XCTestCase {

    func testDirectWiFiDeviceIsReadyWithoutTunnel() {
        let manager = DeviceStateManager(startBackgroundServices: false)
        manager.selectedDevice = Device(
            id: "00008130-000C5144019A001C",
            displayName: "Wi-Fi iPhone",
            connectionType: .wifi
        )
        manager.wifiDirectDeviceIds = ["00008130-000C5144019A001C"]
        manager.isWiFiTransportAvailable = true
        manager.isTunneldRunning = false

        XCTAssertTrue(
            manager.isDeviceReady,
            "A Network device discovered by usbmux is a valid direct Wi-Fi path"
        )
    }

    func testDirectUSBDeviceIsReadyWithoutTunnel() {
        let manager = DeviceStateManager(startBackgroundServices: false)
        manager.selectedDevice = Device(
            id: "00008130-000C5144019A001C",
            displayName: "USB iPhone",
            connectionType: .usb
        )
        manager.usbDirectDeviceIds = ["00008130-000C5144019A001C"]
        manager.isUSBConnected = true
        manager.isTunneldRunning = false

        XCTAssertTrue(manager.isDeviceReady)
    }

    func testUnreachableDeviceStillRequiresTunnel() {
        let manager = DeviceStateManager(startBackgroundServices: false)
        manager.selectedDevice = Device(
            id: "00008130-000C5144019A001C",
            displayName: "Unavailable iPhone",
            connectionType: .wifi
        )
        manager.isWiFiTransportAvailable = false
        manager.isTunneldRunning = false

        XCTAssertFalse(manager.isDeviceReady)
    }

    func testAnotherWiFiDeviceDoesNotMakeSelectedDeviceReady() {
        let manager = DeviceStateManager(startBackgroundServices: false)
        manager.selectedDevice = Device(
            id: "00008130-000C5144019A001C",
            displayName: "Selected iPhone",
            connectionType: .wifi
        )
        manager.wifiDirectDeviceIds = ["00008130-1111111111111111"]
        manager.isWiFiTransportAvailable = true
        manager.isTunneldRunning = false

        XCTAssertFalse(
            manager.isDeviceReady,
            "Transport availability must belong to the selected UDID"
        )
    }
}

// MARK: - Device Manager Deduplication Tests

@MainActor
final class DeviceManagerDeduplicationTests: XCTestCase {

    func testDeduplicatesWifiEndpointIdentifiersIntoSinglePhysicalDevice() {
        let manager = DeviceManager()
        manager.stopAutoRefresh()

        let canonical = Device(
            id: "00008130-000C5144019A001C",
            displayName: "🖇️ (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "🖇️"
        )

        let variants: [Device] = [
            canonical,
            Device(
                id: "192.168.8.138",
                displayName: "🖇️ (iOS 27.0)",
                connectionType: .wifi,
                productType: "iPhone16,2",
                productVersion: "27.0",
                deviceName: "🖇️"
            ),
            Device(
                id: "2c0f:f5c0:600:ac13:1839:d9a8:fd2b:a7ad",
                displayName: "🖇️ (iOS 27.0)",
                connectionType: .wifi,
                productType: "iPhone16,2",
                productVersion: "27.0",
                deviceName: "🖇️"
            ),
            Device(
                id: "2c0f:f5c0:600:ac13:e2ea:c420:fa6c:3",
                displayName: "🖇️ (iOS 27.0)",
                connectionType: .wifi,
                productType: "iPhone16,2",
                productVersion: "27.0",
                deviceName: "🖇️"
            ),
        ]

        let deduped = manager.deduplicatedDevicesForTesting(variants)

        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, canonical.id)
        XCTAssertEqual(deduped.first?.productType, canonical.productType)
        XCTAssertEqual(deduped.first?.productVersion, canonical.productVersion)
    }

    func testKeepsDistinctDevicesWhenIdentityDiffers() {
        let manager = DeviceManager()
        manager.stopAutoRefresh()

        let first = Device(
            id: "00008130-000C5144019A001C",
            displayName: "Phone A (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "Phone A"
        )
        let second = Device(
            id: "00008120-000A111122223333",
            displayName: "Phone B (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "Phone B"
        )

        let deduped = manager.deduplicatedDevicesForTesting([first, second])

        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(Set(deduped.map(\.id)), Set([first.id, second.id]))
    }
}

// MARK: - Route State Manager Tests

final class RouteStateManagerTests: XCTestCase {

    var routeLibrary: RouteLibraryManager!

    @MainActor
    override func setUp() async throws {
        routeLibrary = RouteLibraryManager()
    }

    @MainActor
    override func tearDown() async throws {
        routeLibrary = nil
    }

    @MainActor
    func testInitialState() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        XCTAssertTrue(manager.currentRoute.isEmpty)
        XCTAssertEqual(manager.progress, 0)
        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertNil(manager.routeName)
        XCTAssertFalse(manager.loopEnabled)
        XCTAssertFalse(manager.reverseOnLoop)

        if case .idle = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected idle playback state")
        }
    }

    @MainActor
    func testIsRouteLoaded() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        XCTAssertFalse(manager.isRouteLoaded)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)

        XCTAssertTrue(manager.isRouteLoaded)
    }

    @MainActor
    func testLoadRouteWithCoordinates() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504),
            LocationCoordinate(latitude: 35.6764, longitude: 139.6505)
        ]

        manager.loadRoute(from: coordinates, name: "Test Route")

        XCTAssertEqual(manager.currentRoute.count, 3)
        XCTAssertEqual(manager.routeName, "Test Route")
        XCTAssertEqual(manager.waypointCount, 3)
        XCTAssertGreaterThan(manager.totalDistance, 0)

        if case .ready = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected ready playback state")
        }
    }

    @MainActor
    func testLoadEmptyRouteSetsError() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        manager.loadRoute(from: [])

        if case .error(let message) = manager.playbackState {
            XCTAssertEqual(message, "Empty route")
        } else {
            XCTFail("Expected error state")
        }
    }

    @MainActor
    func testClearRoute() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates, name: "Test Route")
        XCTAssertTrue(manager.isRouteLoaded)

        manager.clearRoute()

        XCTAssertFalse(manager.isRouteLoaded)
        XCTAssertNil(manager.routeName)
        XCTAssertEqual(manager.progress, 0)

        if case .idle = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected idle playback state")
        }
    }

    @MainActor
    func testSkipToWaypoint() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = (0..<10).map { i in
            LocationCoordinate(latitude: 35.6762 + Double(i) * 0.001, longitude: 139.6503)
        }

        manager.loadRoute(from: coordinates)

        manager.skipToWaypoint(5)

        XCTAssertEqual(manager.currentIndex, 5)
        XCTAssertEqual(manager.progress, 0.5, accuracy: 0.01)
    }

    @MainActor
    func testSkipForwardAndBackward() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = (0..<20).map { i in
            LocationCoordinate(latitude: 35.6762 + Double(i) * 0.001, longitude: 139.6503)
        }

        manager.loadRoute(from: coordinates)

        // Start at index 0
        manager.skipForward(5)
        XCTAssertEqual(manager.currentIndex, 5)

        manager.skipForward(5)
        XCTAssertEqual(manager.currentIndex, 10)

        manager.skipBackward(3)
        XCTAssertEqual(manager.currentIndex, 7)

        // Test bounds
        manager.skipBackward(100) // Should clamp to 0
        XCTAssertEqual(manager.currentIndex, 0)

        manager.skipForward(100) // Should clamp to last index
        XCTAssertEqual(manager.currentIndex, 19)
    }

    @MainActor
    func testPausePlayback() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)
        manager.pausePlayback()

        if case .paused = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected paused playback state")
        }
    }

    @MainActor
    func testStopPlayback() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)
        manager.currentIndex = 1
        manager.progress = 0.5

        manager.stopPlayback()

        XCTAssertEqual(manager.currentIndex, 0)
        XCTAssertEqual(manager.progress, 0)

        // Route is still loaded
        if case .ready = manager.playbackState {
            // Expected
        } else {
            XCTFail("Expected ready playback state after stop")
        }
    }

    @MainActor
    func testCurrentWaypoint() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        ]

        manager.loadRoute(from: coordinates)

        XCTAssertEqual(manager.currentWaypoint?.latitude, 35.6762)

        manager.skipToWaypoint(1)
        XCTAssertEqual(manager.currentWaypoint?.latitude, 35.6763)
    }

    @MainActor
    func testRoutePlaybackStateDisplayText() {
        XCTAssertEqual(RoutePlaybackState.idle.displayText, "No route loaded")
        XCTAssertEqual(RoutePlaybackState.loading.displayText, "Loading route...")
        XCTAssertEqual(RoutePlaybackState.ready.displayText, "Ready to play")
        XCTAssertEqual(RoutePlaybackState.playing.displayText, "Playing...")
        XCTAssertEqual(RoutePlaybackState.paused.displayText, "Paused")
        XCTAssertEqual(RoutePlaybackState.completed.displayText, "Completed")
        XCTAssertEqual(RoutePlaybackState.error("Test").displayText, "Error: Test")
    }

    @MainActor
    func testRoutePlaybackStateIsActive() {
        XCTAssertFalse(RoutePlaybackState.idle.isActive)
        XCTAssertFalse(RoutePlaybackState.loading.isActive)
        XCTAssertFalse(RoutePlaybackState.ready.isActive)
        XCTAssertTrue(RoutePlaybackState.playing.isActive)
        XCTAssertTrue(RoutePlaybackState.paused.isActive)
        XCTAssertFalse(RoutePlaybackState.completed.isActive)
        XCTAssertFalse(RoutePlaybackState.error("Test").isActive)
    }
}

// MARK: - Connection Status Tests

final class ConnectionStatusTests: XCTestCase {

    func testConnectionStatusColors() {
        // Test that each status has a defined color
        XCTAssertNotNil(ConnectionStatus.disconnected.color)
        XCTAssertNotNil(ConnectionStatus.connecting.color)
        XCTAssertNotNil(ConnectionStatus.connected.color)
        XCTAssertNotNil(ConnectionStatus.error.color)
    }

    func testConnectionStatusText() {
        XCTAssertEqual(ConnectionStatus.disconnected.text, "Disconnected")
        XCTAssertEqual(ConnectionStatus.connecting.text, "Connecting...")
        XCTAssertEqual(ConnectionStatus.connected.text, "Connected")
        XCTAssertEqual(ConnectionStatus.error.text, "Error")
    }
}
