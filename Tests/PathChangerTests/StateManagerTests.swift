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
    func testReverseRoutePreservesCardinality() async {
        let manager = RouteStateManager(routeLibrary: routeLibrary)

        let coordinates = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6763, longitude: 139.6504),
            LocationCoordinate(latitude: 35.6764, longitude: 139.6505)
        ]

        manager.loadRoute(from: coordinates, name: "Test Route")
        let originalCount = manager.currentRoute.count
        let originalDistance = manager.totalDistance

        manager.reverseRoute()

        // Verify cardinality preserved
        XCTAssertEqual(manager.currentRoute.count, originalCount)
        // Verify distance unchanged
        XCTAssertEqual(manager.totalDistance, originalDistance, accuracy: 0.1)
        // Verify order reversed
        XCTAssertEqual(manager.currentRoute[0].latitude, 35.6764, accuracy: 0.0001)
        XCTAssertEqual(manager.currentRoute[2].latitude, 35.6762, accuracy: 0.0001)
        // Verify progress reset
        XCTAssertEqual(manager.progress, 0)
        XCTAssertEqual(manager.currentIndex, 0)
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

@MainActor
final class AcknowledgedRouteStateTests: XCTestCase {
    func testLocationStatusPresentationUsesLocalizedKeys() async {
        let state = LocationSessionState(
            desiredLocation: nil,
            lastAcknowledgedReceipt: nil,
            connection: .unavailable,
            application: .idle,
            movement: .idle
        )

        let presentation = LocationStatusPresentation(state: state, deviceVisible: true)

        // Verify labels are not empty (localization worked)
        XCTAssertFalse(presentation.connectionLabel.isEmpty)
        XCTAssertFalse(presentation.applicationLabel.isEmpty)
        XCTAssertFalse(presentation.movementLabel.isEmpty)

        // Verify they use localized strings
        XCTAssertEqual(presentation.connectionLabel, "Unavailable")
    }


    func testProgressAdvancesOnlyWhenWaypointIsAcknowledged() {
        let manager = RouteStateManager(routeLibrary: RouteLibraryManager())
        manager.loadRoute(from: [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.1),
            LocationCoordinate(latitude: 35.2, longitude: 139.2)
        ])

        manager.beginAcknowledgedPlayback()
        XCTAssertEqual(manager.progress, 0)
        XCTAssertEqual(manager.currentIndex, 0)

        manager.acknowledgeWaypoint(at: 0, totalCount: 3)
        XCTAssertEqual(manager.progress, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(manager.currentIndex, 1)
        XCTAssertEqual(manager.playbackState, .playing)

        manager.completeAcknowledgedPlayback()
        XCTAssertEqual(manager.progress, 1)
        XCTAssertEqual(manager.playbackState, .completed)
    }

    func testAcknowledgedWaypointKeepsPausedPlaybackPaused() {
        let manager = RouteStateManager(routeLibrary: RouteLibraryManager())
        manager.loadRoute(from: [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.1)
        ])
        manager.beginAcknowledgedPlayback()
        manager.pausePlayback()

        manager.acknowledgeWaypoint(at: 0, totalCount: 2)
        XCTAssertEqual(manager.currentIndex, 1, "the landed point still counts")
        XCTAssertEqual(manager.playbackState, .paused, "a point landing while paused does not resume playback")
    }
}

@MainActor
final class DeviceStateManagerTests: XCTestCase {

    private final class TransportRefreshRecordingDeviceManager: DeviceManager {
        private(set) var transportRefreshCount = 0

        init() {
            // Skip DeviceManager's background discovery tasks; only the overridden
            // refresh is observed.
            super.init(startBackgroundServices: false)
        }

        override func refreshTransportAvailability(
            browseBonjour shouldBrowse: (_ usbmuxUSB: Set<String>, _ usbmuxNetwork: Set<String>) -> Bool
        ) async {
            transportRefreshCount += 1
        }
    }

    private func makeDevice() -> Device {
        Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
    }

    private func makeManager(deviceManager: DeviceManager) -> DeviceStateManager {
        DeviceStateManager(
            deviceManager: deviceManager,
            startBackgroundServices: false
        )
    }

    func testRecoverySessionLeavesTheEndpointToTheProviderAcknowledgement() async throws {
        // Option A: the helper chooses its lane (userspace RSD first) whatever usbmux
        // shows. A recovery candidate that claimed `.direct` rejected every reapply as
        // requestMismatch until recovery was exhausted (review 2026-11-01).
        final class QuietDeviceManager: DeviceManager {
            override func refreshDevices() async {}
        }
        let deviceManager = QuietDeviceManager(startBackgroundServices: false)
        let manager = makeManager(deviceManager: deviceManager)
        let device = Device(
            id: "00008130-0011223344556677", displayName: "Test Device",
            connectionType: .wifi, productType: "iPhone17,1", productVersion: "27.0"
        )
        manager.availableDevices = [device]
        manager.wifiDirectDeviceIds = [device.id]
        let previous = LocationSessionIdentity(
            stableDeviceID: device.id, transport: .wifi,
            endpointClass: .remoteServiceDiscovery, generation: 3
        )

        let candidate = try await manager.establishRecoverySession(previous: previous)

        XCTAssertEqual(candidate.transport, .wifi)
        XCTAssertEqual(candidate.endpointClass, .unresolved)
        XCTAssertEqual(candidate.generation, 4)
    }

    func testManagerWithoutBackgroundServicesBuildsAQuietDeviceManager() {
        // Each test AppState used to build a DeviceManager with background services on:
        // hundreds of hidden managers each watched the shared tunnel state and spawned
        // pymobiledevice3 discovery on every change (~4.8k pipes, EMFILE in the suite).
        let manager = DeviceStateManager(startBackgroundServices: false)
        defer { manager.deviceManager.stopAutoRefresh() }

        let observer = Mirror(reflecting: manager.deviceManager).children
            .first(where: { $0.label == "tunnelStateObserver" })?.value
        XCTAssertNotNil(observer.map { String(describing: $0) })
        XCTAssertEqual(observer.map { String(describing: $0) }, "nil",
                       "a DeviceManager without background services must not observe the tunnel")
    }

    func testOnlyARunningTunnelThatStopsCountsAsLost() {
        XCTAssertNil(DeviceStateManager.tunnelLossEvent(previous: .idle, current: .starting))
        XCTAssertEqual(DeviceStateManager.tunnelLossEvent(previous: .running, current: .error("x")),
                       .tunnelHealthLost)
        // An explicit Stop (or Reconnect/mode switch) is the user's decision: it must
        // not be undone by automatic recovery re-applying the location.
        XCTAssertEqual(DeviceStateManager.tunnelLossEvent(previous: .running, current: .stopping),
                       .tunnelStoppedByUser)
        XCTAssertEqual(DeviceStateManager.tunnelLossEvent(previous: .running, current: .idle),
                       .tunnelStoppedByUser)
        XCTAssertTrue(LocationSessionLossEvent.tunnelHealthLost.startsAutomaticRecovery)
        XCTAssertFalse(LocationSessionLossEvent.tunnelStoppedByUser.startsAutomaticRecovery)
        XCTAssertFalse(LocationSessionLossEvent.appCancelled.startsAutomaticRecovery)
    }

    func testTunnelStopDoesNotShutDownTheLocationHelper() throws {
        // The helper owns its own connection; stopping the tunnel closes that
        // connection (TunneldManager.stopTunnel). Shutting the whole helper down on
        // every tunnel stop raced Reconnect into a helper that was quitting.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("PathChanger/Device/DevLocationBridge.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("stopIfUsingTunnel"))
    }


    func testPublishedDiscoverySynchronizesWrapperState() {
        let deviceManager = DeviceManager()
        deviceManager.stopAutoRefresh()
        let manager = DeviceStateManager(
            deviceManager: deviceManager,
            startBackgroundServices: false
        )
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )

        deviceManager.devices = [device]

        XCTAssertEqual(manager.availableDevices, [device])
        XCTAssertEqual(manager.selectedDevice, device)
        XCTAssertEqual(manager.connectionStatus, .connected)
    }

    func testTransportRefreshIsSkippedInsideMinimumInterval() async {
        let deviceManager = TransportRefreshRecordingDeviceManager()
        let manager = makeManager(deviceManager: deviceManager)
        manager.selectedDevice = makeDevice()

        let firstTrigger = Date(timeIntervalSinceReferenceDate: 1_000_000)
        await manager.refreshTransportAvailabilityIfNeeded(now: firstTrigger)
        XCTAssertEqual(deviceManager.transportRefreshCount, 1)

        // The 15 s guard: an immediate second trigger must not spawn the usbmux
        // subprocess again, even though a device is selected.
        await manager.refreshTransportAvailabilityIfNeeded(now: firstTrigger.addingTimeInterval(1))
        XCTAssertEqual(deviceManager.transportRefreshCount, 1)
    }

    func testTransportRefreshRunsAfterMinimumIntervalWithDeviceSelected() async {
        let deviceManager = TransportRefreshRecordingDeviceManager()
        let manager = makeManager(deviceManager: deviceManager)
        manager.selectedDevice = makeDevice()

        let firstTrigger = Date(timeIntervalSinceReferenceDate: 2_000_000)
        await manager.refreshTransportAvailabilityIfNeeded(now: firstTrigger)
        XCTAssertEqual(deviceManager.transportRefreshCount, 1)

        await manager.refreshTransportAvailabilityIfNeeded(now: firstTrigger.addingTimeInterval(15))
        XCTAssertEqual(deviceManager.transportRefreshCount, 2)
    }

    func testTransportRefreshSkippedWithoutDeviceOrTunnel() async {
        let deviceManager = TransportRefreshRecordingDeviceManager()
        let manager = makeManager(deviceManager: deviceManager)

        await manager.refreshTransportAvailabilityIfNeeded(
            now: Date(timeIntervalSinceReferenceDate: 3_000_000)
        )

        XCTAssertEqual(deviceManager.transportRefreshCount, 0)
    }

    func testTransportRefreshRunsWhenTunnelRunningWithoutDevice() async {
        let deviceManager = TransportRefreshRecordingDeviceManager()
        let manager = makeManager(deviceManager: deviceManager)
        manager.isTunneldRunning = true

        await manager.refreshTransportAvailabilityIfNeeded(
            now: Date(timeIntervalSinceReferenceDate: 4_000_000)
        )

        XCTAssertEqual(deviceManager.transportRefreshCount, 1)
    }

    // MARK: Daemon process on the status poll (review 2026-11-01, lane C)

    /// Reports a `remote tunneld` process on every poll, as the fixed pgrep probe does
    /// whenever any daemon runs, whether or not the user chose it.
    final class DaemonProcessDeviceManager: DeviceManager {
        override func checkTunneldStatus() async { isTunneldRunning = true }
        override func refreshDevices() async {}
    }

    private func prepareSharedTunnel(mode: TunnelMode) async throws -> TunneldManager {
        let tunnel = TunneldManager.shared
        let previousMode = tunnel.preferredMode
        let stateMachine = try XCTUnwrap(
            Mirror(reflecting: tunnel as TunneldManager).children
                .first(where: { $0.label == "stateMachine" })?.value as? TunnelStateMachine
        )
        #if DEBUG
        stateMachine.testModeEnabled = true
        #endif
        tunnel.stopTunnel()
        tunnel.preferredMode = mode
        tunnel.runningTunnelDetectorForTesting = { .daemon }
        tunnel.tunnelLogPathOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_no_tunnel_\(UUID().uuidString).log").path
        addTeardownBlock { @MainActor in
            tunnel.stopTunnel()
            tunnel.allowDaemonAdoptionForTesting() // later suites start unlatched
            tunnel.preferredMode = previousMode
            tunnel.runningTunnelDetectorForTesting = nil
            tunnel.tunnelLogPathOverride = nil
            #if DEBUG
            stateMachine.testModeEnabled = false
            #endif
        }
        // Idle first, so the poll tests exercise the gate rather than the idle guard.
        let deadline = Date().addingTimeInterval(2)
        while tunnel.state != .idle {
            guard Date() < deadline else {
                XCTFail("shared tunnel did not reach idle, got \(tunnel.state)")
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return tunnel
    }

    func testPollAfterStopLeavesTheDaemonStopped() async throws {
        let tunnel = try await prepareSharedTunnel(mode: .daemon) // includes the user's Stop
        let manager = makeManager(deviceManager: DaemonProcessDeviceManager(startBackgroundServices: false))

        await manager.checkTunneldStatus()
        await manager.checkTunneldStatus()

        XCTAssertEqual(tunnel.state, .idle, "the poll undid the user's Stop")
        XCTAssertFalse(manager.isTunneldRunning)
    }

    func testPollInDaemonModeAdoptsADaemonThatSurvivedARelaunch() async throws {
        // Preserve and Quit in daemon mode: autoStart never runs at launch (no
        // elevation policy), so the poll is the only relaunch adoption path.
        let tunnel = try await prepareSharedTunnel(mode: .daemon)
        tunnel.allowDaemonAdoptionForTesting() // a fresh launch has no Stop latched
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_daemon_\(UUID().uuidString).log")
        try "Use the follow connection option:\n--rsd fd8b:e285:f321::1 55823\n"
            .write(to: log, atomically: true, encoding: .utf8)
        tunnel.tunnelLogPathOverride = log.path
        defer { try? FileManager.default.removeItem(at: log) }
        let manager = makeManager(deviceManager: DaemonProcessDeviceManager(startBackgroundServices: false))

        await manager.checkTunneldStatus()
        // The published state syncs through RunLoop.main; readiness follows on the next poll.
        let deadline = Date().addingTimeInterval(2)
        while tunnel.state != .running, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await manager.checkTunneldStatus()

        XCTAssertEqual(tunnel.state, .running)
        XCTAssertEqual(tunnel.tunnelInfo?.mode, .daemon)
        XCTAssertTrue(manager.isTunneldRunning, "an adopted daemon is the tunnel")
    }

    func testPollInHelperModesDoesNotTreatAStrayDaemonAsTheTunnel() async throws {
        for mode in [TunnelMode.auto, .usb, .wifi] {
            let tunnel = try await prepareSharedTunnel(mode: mode)
            tunnel.allowDaemonAdoptionForTesting()
            let manager = makeManager(deviceManager: DaemonProcessDeviceManager(startBackgroundServices: false))

            await manager.checkTunneldStatus()

            XCTAssertEqual(tunnel.state, .idle, "\(mode.rawValue) adopted a daemon it never chose")
            XCTAssertFalse(manager.isTunneldRunning, "\(mode.rawValue) reported a bare process as the tunnel")
        }
    }
}

/// Live 2026-11-01: for 3.5 minutes usbmux did not list the phone, yet the chip read
/// "trusted · Wi-Fi". Reachability comes from live evidence only (invariant 2).
final class DeviceReachabilityTests: XCTestCase {
    private let device = Device(
        id: "00008130-0011223344556677", displayName: "iPhone",
        connectionType: .wifi, productType: "iPhone17,1", productVersion: "27.2"
    )

    private func reachability(
        usb: Set<String> = [], network: Set<String> = [],
        advertised: Set<String> = [], tunnelRunning: Bool = false
    ) -> DeviceReachability {
        DeviceReachability.of(
            device: device,
            usbmuxUSB: usb,
            usbmuxNetwork: network,
            networkAdvertised: advertised,
            tunnelRunning: tunnelRunning
        )
    }

    func testARunningConnectionIsConnected() {
        XCTAssertEqual(reachability(tunnelRunning: true), .connected)
        XCTAssertEqual(reachability(usb: [device.id], network: [device.id], tunnelRunning: true), .connected)
    }

    func testUsbmuxOverUSBIsReadyOnUSB() {
        XCTAssertEqual(reachability(usb: [device.id], network: [device.id], advertised: [device.id]), .readyUSB)
    }

    func testUsbmuxOverNetworkIsReadyOnWiFi() {
        XCTAssertEqual(reachability(network: [device.id], advertised: [device.id]), .readyWiFi)
    }

    func testOnlyBonjourSeeingThePhoneIsOnTheNetwork() {
        XCTAssertEqual(reachability(advertised: [device.id]), .onNetwork)
    }

    func testAPairedPhoneNoLiveSourceSeesIsNotReachable() {
        XCTAssertEqual(reachability(), .notReachable)
        // Another phone's evidence says nothing about this one.
        let other: Set<String> = ["00008120-001B000E3E82002F"]
        XCTAssertEqual(reachability(usb: other, network: other, advertised: other), .notReachable)
    }
}

@MainActor
final class DeviceStateManagerReachabilityTests: XCTestCase {
    private let device = Device(
        id: "00008130-0011223344556677", displayName: "iPhone",
        connectionType: .wifi, productType: "iPhone17,1", productVersion: "27.2"
    )

    func testTheBonjourSetIsMirroredWithTheUsbmuxSets() {
        let deviceManager = DeviceManager(startBackgroundServices: false)
        let manager = DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false)
        _ = deviceManager.applyMobdev2ObservationForTesting("""
        [{"ConnectionType": "Network", "DeviceName": "iPhone", "Identifier": "\(device.id)",
          "ProductVersion": "27.2", "UniqueDeviceID": "\(device.id)"}]
        """)

        deviceManager.devices = [device]

        XCTAssertEqual(manager.networkAdvertisedDeviceIds, [device.id])
        XCTAssertEqual(manager.reachability(of: device, tunnelRunning: false), .onNetwork)
    }

    func testOnlyTheSelectedDeviceIsConnectedByTheTunnel() {
        let manager = DeviceStateManager(startBackgroundServices: false)
        defer { manager.deviceManager.stopAutoRefresh() }
        let other = Device(id: "00008120-001B000E3E82002F", displayName: "Other", connectionType: .wifi)
        manager.availableDevices = [device, other]
        manager.selectedDevice = device

        XCTAssertEqual(manager.reachability(of: device, tunnelRunning: true), .connected)
        XCTAssertEqual(manager.reachability(of: other, tunnelRunning: true), .notReachable)
    }
}

/// Answers `runPython` from canned output keyed by subcommand (`usbmux`, `bonjour`) and
/// records the order the subcommands ran in.
@MainActor
private final class TransportScriptedDeviceManager: DeviceManager {
    struct NoScriptedOutput: Error {}

    var outputs: [String: String] = [:]
    var subcommands: [String] = []

    init() {
        super.init(startBackgroundServices: false)
        connectionMode = .auto
    }

    override func runPython(arguments: [String], timeout: TimeInterval = 30.0) async throws -> String {
        let subcommand = arguments.count > 2 ? arguments[2] : ""
        subcommands.append(subcommand)
        guard let output = outputs[subcommand] else { throw NoScriptedOutput() }
        return output
    }
}

/// Review 2026-11-01 v2 (issue 3): the 15 s transport refresh spawned a Bonjour browse
/// (a Python process, a 5 s mDNS browse and LAN lockdown handshakes) even when its result
/// could not change the chip. `DeviceReachability.of` reads the Bonjour set only when the
/// selected device is not connected and usbmux does not list it.
@MainActor
final class BonjourBrowseGateTests: XCTestCase {
    private let device = Device(
        id: "00008130-0011223344556677", displayName: "iPhone",
        connectionType: .wifi, productType: "iPhone17,1", productVersion: "27.2"
    )

    private func usbmuxListing(_ type: String) -> String {
        """
        [{"ConnectionType": "\(type)", "DeviceName": "iPhone", "Identifier": "\(device.id)",
          "ProductVersion": "27.2", "UniqueDeviceID": "\(device.id)"}]
        """
    }

    func testTheBrowseRunsOnlyWhenItCanChangeTheSelectedDevicesReachability() {
        let id = device.id
        let other = "00008120-001B000E3E82002F"
        func decide(_ selected: String?, tunnel: Bool = false,
                    usb: Set<String> = [], network: Set<String> = []) -> Bool {
            DeviceStateManager.shouldBrowseBonjour(
                selectedDeviceID: selected, tunnelRunning: tunnel,
                usbmuxUSB: usb, usbmuxNetwork: network
            )
        }

        XCTAssertTrue(decide(id), "selected, not connected, not listed: Bonjour decides the chip")
        XCTAssertTrue(decide(id, usb: [other], network: [other]), "another phone's listing says nothing about ours")
        XCTAssertFalse(decide(nil), "no device selected")
        XCTAssertFalse(decide(nil, tunnel: true), "a running tunnel with nothing selected")
        XCTAssertFalse(decide(id, tunnel: true), "the connection is running: the chip reads connected")
        XCTAssertFalse(decide(id, usb: [id]), "usbmux lists it over USB")
        XCTAssertFalse(decide(id, network: [id]), "usbmux lists it over Network")
    }

    func testAnUnneededBrowseIsSkippedAndOnlyUsbmuxRuns() async {
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.outputs = ["usbmux": usbmuxListing("Network"), "bonjour": "[]"]
        let manager = DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false)
        manager.selectedDevice = device

        await manager.refreshTransportAvailabilityIfNeeded(now: Date())

        XCTAssertEqual(deviceManager.subcommands, ["usbmux"])
    }

    func testTheBrowseIsSkippedWhileTheConnectionRuns() async {
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.outputs = ["usbmux": "[]", "bonjour": "[]"]
        let manager = DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false)
        manager.selectedDevice = device
        manager.isTunneldRunning = true

        await manager.refreshTransportAvailabilityIfNeeded(now: Date())

        XCTAssertEqual(deviceManager.subcommands, ["usbmux"])
    }

    func testTheBrowseRunsAfterUsbmuxWhenUsbmuxDoesNotListTheSelectedPhone() async {
        // The decision reads this refresh's usbmux result, so a phone that just left
        // usbmux is browsed in the same refresh rather than read from an old Bonjour set.
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.outputs = ["usbmux": "[]", "bonjour": """
        [{"ConnectionType": "Network", "DeviceName": "iPhone", "Identifier": "\(device.id)",
          "ProductVersion": "27.2", "UniqueDeviceID": "\(device.id)"}]
        """]
        let manager = DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false)
        manager.selectedDevice = device

        await manager.refreshTransportAvailabilityIfNeeded(now: Date())

        XCTAssertEqual(deviceManager.subcommands, ["usbmux", "bonjour"])
        XCTAssertEqual(deviceManager.networkAdvertisedDeviceIds, [device.id])
    }

    // MARK: Review 2026-11-01 v3 (issue 2): Bonjour evidence carried across a closed gate

    private var bonjourListing: String { usbmuxListing("Network") }

    /// The chip from DeviceManager's evidence (DeviceStateManager mirrors it on the
    /// status poll, which these tests do not run).
    private func chip(_ deviceManager: DeviceManager) -> DeviceReachability {
        DeviceReachability.of(
            device: device,
            usbmuxUSB: deviceManager.usbDirectDeviceIds,
            usbmuxNetwork: deviceManager.wifiDirectDeviceIds,
            networkAdvertised: deviceManager.networkAdvertisedDeviceIds,
            tunnelRunning: false
        )
    }

    /// Selects the phone while usbmux lists it over Network, so the gate stays closed,
    /// with a Bonjour entry the 120 s discovery browse left behind.
    private func closedGateWithCarriedOverBonjour() async
        -> (TransportScriptedDeviceManager, DeviceStateManager, Date) {
        let deviceManager = TransportScriptedDeviceManager()
        _ = deviceManager.applyMobdev2ObservationForTesting(bonjourListing)
        deviceManager.outputs = ["usbmux": usbmuxListing("Network"), "bonjour": "[]"]
        let manager = DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false)
        manager.selectedDevice = device
        let start = Date(timeIntervalSinceReferenceDate: 5_000_000)
        await manager.refreshTransportAvailabilityIfNeeded(now: start)
        XCTAssertEqual(deviceManager.subcommands, ["usbmux"], "precondition: the gate is closed")
        return (deviceManager, manager, start)
    }

    /// Drops the phone from usbmux and refreshes until the gate opens (the usbmux
    /// Network set holds it through two misses), returning the next refresh time.
    private func refreshUntilTheGateReopens(
        _ deviceManager: TransportScriptedDeviceManager,
        _ manager: DeviceStateManager,
        from start: Date
    ) async -> Date {
        deviceManager.outputs["usbmux"] = "[]"
        var now = start
        for _ in 0..<3 {
            now = now.addingTimeInterval(15)
            await manager.refreshTransportAvailabilityIfNeeded(now: now)
        }
        XCTAssertEqual(deviceManager.subcommands.filter { $0 == "bonjour" }.count, 1,
                       "precondition: only the third usbmux miss reopens the gate: \(deviceManager.subcommands)")
        return now.addingTimeInterval(15)
    }

    func testTheFirstBrowseAfterTheGateReopensDecidesAPhoneBonjourNoLongerSees() async {
        // While usbmux listed the phone the 15 s browse was skipped, so its Bonjour entry
        // aged only on the 120 s discovery browse. When usbmux dropped it the chip kept
        // "on Wi-Fi network" for two or three more browses that did not see it.
        let (deviceManager, manager, start) = await closedGateWithCarriedOverBonjour()

        _ = await refreshUntilTheGateReopens(deviceManager, manager, from: start)

        XCTAssertEqual(deviceManager.networkAdvertisedDeviceIds, [], "the reopening browse did not see the phone")
        XCTAssertEqual(chip(deviceManager), .notReachable)
    }

    func testTheFirstBrowseAfterTheGateReopensKeepsAPhoneBonjourStillSees() async {
        let (deviceManager, manager, start) = await closedGateWithCarriedOverBonjour()
        deviceManager.outputs["bonjour"] = bonjourListing

        _ = await refreshUntilTheGateReopens(deviceManager, manager, from: start)

        XCTAssertEqual(chip(deviceManager), .onNetwork)
    }

    func testAfterTheReopeningBrowseOneMissIsOnlyAMissAgain() async {
        // The reopening browse decides once; later browses keep the 3-miss hysteresis
        // (one slow mDNS answer must not flip the chip).
        let (deviceManager, manager, start) = await closedGateWithCarriedOverBonjour()
        deviceManager.outputs["bonjour"] = bonjourListing
        let next = await refreshUntilTheGateReopens(deviceManager, manager, from: start)

        deviceManager.outputs["bonjour"] = "[]"
        await manager.refreshTransportAvailabilityIfNeeded(now: next)

        XCTAssertEqual(deviceManager.subcommands.filter { $0 == "bonjour" }.count, 2)
        XCTAssertEqual(chip(deviceManager), .onNetwork)
    }

    func testTheReopeningDecisionAppliesOnlyToTheSelectedPhone() async {
        // The gate serves the selected device; other rows keep their discovery-cadence
        // hysteresis.
        let other = "00008120-001B000E3E82002F"
        let (deviceManager, manager, start) = await closedGateWithCarriedOverBonjour()
        _ = deviceManager.applyMobdev2ObservationForTesting("""
        [{"ConnectionType": "Network", "DeviceName": "Other", "Identifier": "\(other)",
          "ProductVersion": "27.1", "UniqueDeviceID": "\(other)"}]
        """) // also one miss for ours
        deviceManager.subcommands = []

        _ = await refreshUntilTheGateReopens(deviceManager, manager, from: start)

        XCTAssertEqual(deviceManager.networkAdvertisedDeviceIds, [other])
    }
}

/// Review 2026-11-01 v3 (issue 1): a Move that reopened the helper connection sent the
/// row's connection type, and a row last merged over USB stays `.usb` until discovery
/// relabels it (up to 120 s), so after the cable was pulled in Auto mode the helper never
/// tried its mobdev2 lane. The connect hint follows the connection mode, like Start.
@MainActor
final class HelperConnectTransportTests: XCTestCase {
    private let id = "00008130-0011223344556677"

    private func usbmuxListing(_ type: String) -> String {
        """
        [{"ConnectionType": "\(type)", "DeviceName": "iPhone", "Identifier": "\(id)",
          "ProductVersion": "27.2", "UniqueDeviceID": "\(id)"}]
        """
    }

    private func refresh(_ deviceManager: TransportScriptedDeviceManager, usbmux: String) async {
        deviceManager.outputs = ["usbmux": usbmux, "bonjour": "[]"]
        await deviceManager.refreshTransportAvailability(browseBonjour: { _, _ in false })
    }

    func testAutoModeAsksForNetworkOnceUsbmuxStopsListingThePhoneOverUSB() async {
        let deviceManager = TransportScriptedDeviceManager()
        await refresh(deviceManager, usbmux: usbmuxListing("USB"))
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .usb, "cabled: usbmux direct over USB")

        await refresh(deviceManager, usbmux: "[]") // cable pulled
        XCTAssertEqual(deviceManager.usbDirectDeviceIds, [id], "precondition: the chip's set still holds it (hysteresis)")
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .wifi,
                       "the latest listing no longer has it over USB: the helper may try mobdev2")
    }

    func testAutoModeAsksForNetworkWhenUsbmuxListsThePhoneOnlyOverNetwork() async {
        let deviceManager = TransportScriptedDeviceManager()
        await refresh(deviceManager, usbmux: usbmuxListing("Network"))
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .wifi)
    }

    func testAnotherPhoneOnUSBDoesNotMakeOursUSB() async {
        let deviceManager = TransportScriptedDeviceManager()
        await refresh(deviceManager, usbmux: """
        [{"ConnectionType": "USB", "Identifier": "00008120-001B000E3E82002F",
          "UniqueDeviceID": "00008120-001B000E3E82002F"}]
        """)
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .wifi)
    }

    func testUSBOnlyModeNeverAsksForNetwork() async {
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.connectionMode = .usb
        await refresh(deviceManager, usbmux: "[]")
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .usb, "USB-only never crosses to Wi-Fi")
    }

    func testWiFiOnlyModeAsksForNetworkLikeStart() async {
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.connectionMode = .wifi
        await refresh(deviceManager, usbmux: usbmuxListing("USB"))
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .wifi)
    }

    func testRandomModeFollowsUsbmuxLikeAuto() async {
        let deviceManager = TransportScriptedDeviceManager()
        deviceManager.connectionMode = .random
        await refresh(deviceManager, usbmux: usbmuxListing("USB"))
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .usb)
        await refresh(deviceManager, usbmux: "[]")
        XCTAssertEqual(deviceManager.helperConnectTransport(for: id), .wifi)
    }

    func testAppStateHandsTheBridgeTheModeDerivedConnectHint() {
        // The bridge has no DeviceManager; the composition root wires the hint in.
        let deviceManager = TransportScriptedDeviceManager()
        let usbRow = Device(id: id, displayName: "iPhone", connectionType: .usb)
        withExtendedLifetime(AppState(startBackgroundServices: false, deviceManager: deviceManager)) {
            XCTAssertEqual(PersistentLocationBridge.shared.connectTransport(for: usbRow), .wifi,
                           "Auto mode, usbmux has not listed it over USB: not the row's .usb")
            deviceManager.connectionMode = .usb
            XCTAssertEqual(PersistentLocationBridge.shared.connectTransport(for: usbRow), .usb)
        }
    }
}
