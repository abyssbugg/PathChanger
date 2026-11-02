//
//  AppStateSimulationTests.swift
//  PathChangerTests
//
//  Multi-Spot waypoint editing and Play dispatch without a live device.
//

import XCTest
@testable import PathChanger

@MainActor
final class AppStateSimulationTests: XCTestCase {

    private final class FakeManagedLocationSessionSource: ManagedLocationSessionSource {
        var adoptedHelperID: UUID?
        var adoptedHelperSessions: [ManagedLocationHelperSession]
        var hasRecordedHeldSessions = false
        var connectionStatus: HelperConnectionStatus = .connected
        private(set) var statusCallCount = 0
        /// Runs inside the liveness probe before it answers (holds it open for a test).
        var statusGate: (@MainActor () async -> Void)?
        /// Recorded sessions survive shutdown (helper could not be stopped).
        var shutdownLeavesRecordedSessions = false
        private(set) var startCallCount = 0
        private(set) var refreshCallCount = 0
        private(set) var shutdownCallCount = 0

        init(helperID: UUID?, sessions: [ManagedLocationHelperSession]) {
            adoptedHelperID = helperID
            adoptedHelperSessions = sessions
        }

        func start() async throws {
            startCallCount += 1
        }

        func refreshAdoptedHelperSessions() async throws {
            refreshCallCount += 1
        }

        func deviceConnectionStatus(
            _ deviceId: String,
            transport: LocationTransport
        ) async -> HelperConnectionStatus {
            statusCallCount += 1
            if let statusGate { await statusGate() }
            return connectionStatus
        }

        func shutdownHelper() async throws {
            shutdownCallCount += 1
            if !shutdownLeavesRecordedSessions {
                hasRecordedHeldSessions = false
            }
        }
    }

    private final class FakeTunnelQuitController: TunnelQuitControlling {
        var stopResult: TunnelQuitStopResult = .stopped
        var onStop: (() -> Void)?
        var helperStop: Task<Bool, Never>?

        func pendingHelperStop(for deviceId: String) -> Task<Bool, Never>? {
            helperStop
        }

        private(set) var resumedDevices: [String] = []
        func resumeLocationCommands(for deviceId: String) {
            resumedDevices.append(deviceId)
        }
        private(set) var stopCallCount = 0
        private(set) var retainCallCount = 0

        func stopTunnelForQuit() async -> TunnelQuitStopResult {
            stopCallCount += 1
            onStop?()
            return stopResult
        }

        func retainTunnelForPreservedLocation() {
            retainCallCount += 1
        }
    }

    private final class AdoptionRecordingLocationInjector: LocationInjecting, @unchecked Sendable {
        private(set) var adoptedReceipts: [(LocationInjectionReceipt, String)] = []
        private(set) var abandonedReceipts: [(LocationInjectionReceipt, String)] = []
        /// Runs inside `adoptManagedSession` after it adopted (holds it open for a test).
        var adoptionGate: (@MainActor () async -> Void)?

        func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
            throw LocationInjectionError.injectionFailed("Apply is not used by this restoration test")
        }

        func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}

        func adoptManagedSession(
            receipt: LocationInjectionReceipt,
            stableDeviceID: String
        ) async throws {
            adoptedReceipts.append((receipt, stableDeviceID))
            if let adoptionGate { await adoptionGate() }
        }

        func abandonAdoptedSession(_ receipt: LocationInjectionReceipt, stableDeviceID: String) async {
            abandonedReceipts.append((receipt, stableDeviceID))
        }
    }

    /// Stubs the one DeviceManager entry point one-tap reconnect exercises, so
    /// reconnect tests never invoke pymobiledevice3 discovery or clobber the
    /// selected fake device with live host state.
    private final class ReconnectStubDeviceManager: DeviceManager {
        private(set) var refreshCallCount = 0

        override func refreshDevices() async {
            refreshCallCount += 1
        }
    }

    private func makeState(locationInjector: (any LocationInjecting)? = nil) -> AppState {
        AppState(startBackgroundServices: false, locationInjector: locationInjector)
    }

    private let first = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let second = LocationCoordinate(latitude: 35.6772, longitude: 139.6513)

    private func awaitReadyIdentity(in state: AppState) async throws -> LocationSessionIdentity {
        for _ in 0..<100 {
            if case .ready(let identity) = state.locationSessionCoordinator.state.connection {
                return identity
            }
            await Task.yield()
        }
        throw NSError(
            domain: "AppStateSimulationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the device-selection callback"]
        )
    }

    private func drainSelectionCallbacks() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }

    func testSelectingVerifiedDevicePublishesReadyLocationSession() async throws {
        let state = makeState()
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )

        state.selectDevice(device)
        let identity = try await awaitReadyIdentity(in: state)
        XCTAssertEqual(identity.stableDeviceID, device.id)
        XCTAssertEqual(identity.transport, .usb)
        XCTAssertEqual(identity.endpointClass, .unresolved)
        XCTAssertEqual(identity.generation, 1)
    }

    func testSameDeviceRediscoveryPreservesApplyingIdentityAndRequest() async throws {
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source
        )
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )

        state.selectDevice(device)
        let original = try await awaitReadyIdentity(in: state)
        state.locationSessionCoordinator.select(first, mode: .teleport)
        let request = try state.locationSessionCoordinator.beginApplication()

        state.selectDevice(device)
        await drainSelectionCallbacks()

        guard case .ready(let rediscovered) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected rediscovery to preserve the ready session")
        }
        XCTAssertEqual(rediscovered, original)
        guard case .applying(let activeRequestID, let coordinate) =
                state.locationSessionCoordinator.state.application else {
            return XCTFail("Expected rediscovery to preserve the in-flight application")
        }
        XCTAssertEqual(activeRequestID, request.id)
        XCTAssertEqual(coordinate, first)
    }

    func testTransportReplacementDuringApplyingBecomesUncertainWithoutNewReadyIdentity() async throws {
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source
        )
        let usbDevice = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let wifiDevice = Device(
            id: usbDevice.id,
            displayName: usbDevice.displayName,
            connectionType: .wifi,
            productType: usbDevice.productType,
            productVersion: usbDevice.productVersion
        )

        state.selectDevice(usbDevice)
        _ = try await awaitReadyIdentity(in: state)
        state.locationSessionCoordinator.select(first, mode: .teleport)
        _ = try state.locationSessionCoordinator.beginApplication()

        state.selectDevice(wifiDevice)
        await drainSelectionCallbacks()

        guard case .failed(let reason) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected transport replacement to fail the ready connection")
        }
        XCTAssertTrue(reason.contains("transport changed"))
        guard case .uncertain(let lastReceipt, _) = state.locationSessionCoordinator.state.application else {
            return XCTFail("Expected in-flight application truth to become uncertain")
        }
        XCTAssertNil(lastReceipt)
    }

    func testDiscoverySyncNeverReplacesThisSessionsOwnLocationWithTheHelperRecord() async throws {
        // Live 2026-11-01: every discovery sync re-adopted the helper's recorded session,
        // which dropped the in-flight hop and set Movement to Idle in every moving mode.
        // Adoption is for a relaunch (no location truth of our own), not mid-session.
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .wifi,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 1,
            physicalTransport: "Network",
            actualChannel: "userspaceRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 36.3, longitude: -86.6),
            acknowledgedAt: 1_725_000_000
        )
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [session])
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: AdoptionRecordingLocationInjector(),
            managedLocationSessionSource: source
        )
        state.selectDevice(device)
        _ = try await awaitReadyIdentity(in: state)

        // This session is applying a hop of a moving route...
        state.locationSessionCoordinator.select(first, mode: .multiSpot)
        state.locationSessionCoordinator.beginMovement(.multiSpot)
        let request = try state.locationSessionCoordinator.beginApplication()
        // ...when the helper record (now holding the previous hop) is published.
        source.adoptedHelperID = UUID()

        state.selectDevice(device)
        await drainSelectionCallbacks()

        guard case .applying(let requestID, _) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the in-flight hop must survive a discovery sync")
        }
        XCTAssertEqual(requestID, request.id)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.multiSpot))
    }

    func testRestoreManagedHelperSessionPublishesHeldProviderTruth() async throws {
        let locationInjector = AdoptionRecordingLocationInjector()
        let state = makeState(locationInjector: locationInjector)
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let helperID = UUID()
        let requestID = UUID()
        let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: requestID.uuidString,
            sessionGeneration: 9,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            acknowledgedAt: 1_725_000_000
        )

        state.selectDevice(device)
        let restored = await state.restoreManagedHelperSession(session, helperID: helperID, for: device)
        XCTAssertTrue(restored)

        guard case .ready(let identity) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected adopted helper session to be ready")
        }
        XCTAssertEqual(identity.stableDeviceID, device.id)
        XCTAssertEqual(identity.transport, .usb)
        XCTAssertEqual(identity.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(identity.generation, 9)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .active(
            receipt: try XCTUnwrap(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        ))
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertEqual(state.currentLocation, coordinate)
        XCTAssertEqual(state.targetLocation, coordinate)
        XCTAssertTrue(state.isSimulating)
        XCTAssertEqual(locationInjector.adoptedReceipts.count, 1)
        XCTAssertEqual(locationInjector.adoptedReceipts.first?.0.requestID, requestID)
        XCTAssertEqual(locationInjector.adoptedReceipts.first?.1, device.id)
        XCTAssertTrue(locationInjector.abandonedReceipts.isEmpty, "an accepted restore is not abandoned")
    }

    func testDeviceFirstStartupRestoresMatchingManagedSession() async throws {
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let helperID = UUID()
        let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 11,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            acknowledgedAt: 1_725_000_000
        )
        let source = FakeManagedLocationSessionSource(helperID: helperID, sessions: [session])
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source
        )

        state.selectDevice(device)
        let restored = await state.restoreManagedLocationSessionFromSource()
        XCTAssertTrue(restored)

        XCTAssertEqual(source.startCallCount, 1)
        XCTAssertGreaterThanOrEqual(source.statusCallCount, 1, "restore must probe the live connection")
        XCTAssertEqual(state.currentLocation, coordinate)
        XCTAssertTrue(state.isSimulating)
        XCTAssertEqual(
            state.locationSessionCoordinator.state.movement,
            LocationMovementPhase.idle
        )
    }

    func testRestoreRefusesARecordedSessionWhoseConnectionIsGone() async throws {
        // The helper record can outlive a silently dropped link; restoring it without a
        // probe showed a location as held that the device no longer applied.
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .wifi,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 11,
            physicalTransport: "Network",
            actualChannel: "userspaceRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 36.3, longitude: -86.6),
            acknowledgedAt: 1_725_000_000
        )
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [session])
        source.connectionStatus = .notConnected("probe timed out after 3s")
        let state = AppState(startBackgroundServices: false, managedLocationSessionSource: source)

        state.selectDevice(device)
        let restored = await state.restoreManagedLocationSessionFromSource()

        XCTAssertFalse(restored)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
    }

    /// Holds the helper liveness probe open until the test releases it.
    @MainActor
    private final class ProbeGate {
        private var waiter: CheckedContinuation<Void, Never>?
        private(set) var entered = false
        func hold() async {
            entered = true
            await withCheckedContinuation { waiter = $0 }
        }
        func release() {
            waiter?.resume()
            waiter = nil
        }
    }

    func testAClearDuringTheRestoreProbeIsNotUndoneByTheHelperRecord() async throws {
        // The restore reads the helper record, then probes the connection (up to 8 s).
        // A Clear that started and finished during the probe left the app owning no
        // operation, so the restore adopted the pre-Clear record: the GUI showed a held
        // location the phone no longer had (false active, PRODUCT_REQUIREMENTS 4).
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 11,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 37.33182, longitude: -122.03118),
            acknowledgedAt: 1_725_000_000
        )
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [session])
        let gate = ProbeGate()
        source.statusGate = { await gate.hold() }
        let injector = FakeLocationInjector()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: source
        )
        state.selectedDevice = device
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: device.id, transport: .usb, endpointClass: .unresolved, generation: 1
        ))

        let restore = Task { await state.restoreManagedLocationSessionFromSource() }
        while !gate.entered { await Task.yield() }
        await state.clearLocation()
        XCTAssertEqual(state.statusMessage, "Location cleared")
        source.statusGate = nil
        gate.release()
        let restored = await restore.value

        XCTAssertFalse(restored, "a record read before the Clear is stale after it")
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertNil(state.currentLocation)
    }

    func testAConfirmedClearThatSawAConnectionLossReportsTheHelperConnectionTruthfully() async throws {
        // A loss reported while the Clear was out (a replaced helper connection, a
        // transport change) left the Connection chip on Lost after the helper confirmed
        // the Clear over that very connection. After the Clear, the helper's own probe
        // decides: a live (replaced or reopened) connection is Ready again, a dead one
        // stays Lost.
        for status in [HelperConnectionStatus.connected, .notConnected("no route to host")] {
            let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
            source.connectionStatus = status
            let injector = FakeLocationInjector()
            let state = AppState(
                startBackgroundServices: false,
                locationInjector: injector,
                managedLocationSessionSource: source
            )
            let device = Device(id: "00008130-0011223344556677", displayName: "Test Device", connectionType: .wifi)
            state.selectedDevice = device
            let cleared = LocationSessionIdentity(
                stableDeviceID: device.id, transport: .wifi, endpointClass: .remoteServiceDiscovery, generation: 3
            )
            state.locationSessionCoordinator.connectionReady(cleared)

            await injector.setShouldBlockClear(true)
            let clear = Task { await state.clearLocation() }
            try await injector.waitForClearEntered()
            state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Location endpoint replaced"))
            let probesBefore = source.statusCallCount
            await injector.releaseClear()
            await clear.value

            XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle, "\(status)")
            XCTAssertNil(state.moveBlockedByClear, "\(status)")
            XCTAssertGreaterThan(source.statusCallCount, probesBefore, "the helper connection is probed (\(status))")
            switch status {
            case .connected:
                guard case .ready(let identity) = state.locationSessionCoordinator.state.connection else {
                    XCTFail("a live helper connection is Ready, got \(state.locationSessionCoordinator.state.connection)")
                    continue
                }
                XCTAssertEqual(identity.stableDeviceID, device.id)
                XCTAssertEqual(identity.transport, .wifi)
                XCTAssertGreaterThan(identity.generation, cleared.generation)
            case .notConnected:
                guard case .failed = state.locationSessionCoordinator.state.connection else {
                    XCTFail("a dead connection stays Lost, got \(state.locationSessionCoordinator.state.connection)")
                    continue
                }
            }
        }
    }

    func testANewerLossDuringThePostClearProbeKeepsTheConnectionLost() async throws {
        // The post-Clear probe can answer "connected" just before the link dies. A loss
        // the health monitor or the bridge reports while that probe is out is newer than
        // the one being repaired: the connection must stay Lost, not turn Ready on a dead
        // link (review 2026-11-01, issue 1).
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.connectionStatus = .connected
        let injector = FakeLocationInjector()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: source
        )
        let device = Device(id: "00008130-0011223344556677", displayName: "Test Device", connectionType: .wifi)
        state.selectedDevice = device
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: device.id, transport: .wifi, endpointClass: .remoteServiceDiscovery, generation: 3
        ))

        await injector.setShouldBlockClear(true)
        let clear = Task { await state.clearLocation() }
        try await injector.waitForClearEntered()
        state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Location endpoint replaced"))
        let gate = ProbeGate()
        source.statusGate = { await gate.hold() }
        await injector.releaseClear()
        while !gate.entered { await Task.yield() }
        // The newer loss lands while the probe is out.
        state.locationSessionCoordinator.connectionLost(reason: "Health check failed")
        source.statusGate = nil
        gate.release()
        await clear.value

        // The newer loss arrived after the Clear committed: no receipt is held, and the
        // coordinator's own loss rule (an idle phase becomes uncertain with no receipt)
        // applies; nothing claims a location.
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertFalse(state.locationPresentation.isSpoofing)
        XCTAssertEqual(
            state.locationSessionCoordinator.state.connection,
            .failed("Health check failed"),
            "a loss newer than the probe stays reported"
        )
    }

    func testClearAndQuitDoesNotWaitForThePostClearConnectionProbe() async throws {
        // Quit shuts the helper down right after its Clear: probing the connection it is
        // about to close only delayed quit by up to 8 s (review 2026-11-01, issue 2).
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: source,
            tunnelQuitController: tunnel
        )
        state.stageLocation(first, for: .teleport)
        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        XCTAssertNotNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)

        await fake.setShouldBlockClear(true)
        let quit = Task { await state.prepareForQuit(.clearAndQuit) }
        try await fake.waitForClearEntered()
        // A loss while the quit Clear is out is what made the probe run.
        state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Location endpoint replaced"))
        let probesBefore = source.statusCallCount
        await fake.releaseClear()
        let result = await quit.value

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.statusCallCount, probesBefore, "the quit Clear does not probe the connection")
        XCTAssertEqual(source.shutdownCallCount, 1)
        XCTAssertEqual(tunnel.stopCallCount, 1)
    }

    func testALossDuringAFailedClearKeepsMoveBlockedAndARetryReachesTheInjector() async throws {
        // A loss during Clear fails only the connection; a Clear that then fails leaves
        // the location unconfirmed. The GUI must say so on both dimensions, keep Move
        // blocked, and let the next Clear press reach the injector (review 2026-11-01,
        // issue 5).
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.connectionStatus = .notConnected("no route to host")
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: source
        )
        state.stageLocation(first, for: .teleport)
        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        let receipt = try XCTUnwrap(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)

        await fake.setShouldBlockClear(true)
        await fake.setShouldFailClear(true)
        let clearing = Task { await state.clearLocation() }
        try await fake.waitForClearEntered()
        state.submitLocationBridgeEvent(.sessionLost(nil, reason: "Location endpoint replaced"))
        await fake.releaseClear()
        await clearing.value

        guard case .failed = state.locationSessionCoordinator.state.application else {
            return XCTFail("a failed Clear leaves the application Failed, got \(state.locationSessionCoordinator.state.application)")
        }
        guard case .failed = state.locationSessionCoordinator.state.connection else {
            return XCTFail("the loss stays reported, got \(state.locationSessionCoordinator.state.connection)")
        }
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        XCTAssertFalse(state.locationPresentation.isSpoofing, "an unconfirmed Clear never claims a held location")
        XCTAssertFalse(state.locationPresentation.canMove)
        XCTAssertEqual(state.moveBlockedByClear, .clearUnresolved)
        XCTAssertFalse(state.canStartSimulation)

        await fake.setShouldBlockClear(false)
        await fake.setShouldFailClear(false)
        await state.clearLocation()

        let clears = await fake.calls().filter { call in
            if case .clear = call { return true }
            return false
        }
        XCTAssertEqual(clears.count, 2, "the retry reaches the injector")
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertNil(state.moveBlockedByClear)
    }

    func testARestoreRefusedForAnOwnedOperationNeverReachesTheAdapter() async throws {
        // The restore refused a session this app was already applying only after
        // `adoptManagedSession` had written the stale receipt into the adapter's
        // generation tracker: adapter and coordinator disagreed (review 2026-11-01,
        // issue 4). An owned operation is refused before the adapter call.
        let injector = AdoptionRecordingLocationInjector()
        let state = makeState(locationInjector: injector)
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 9,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 37.33182, longitude: -122.03118),
            acknowledgedAt: 1_725_000_000
        )
        state.selectedDevice = device
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: device.id, transport: .usb, endpointClass: .unresolved, generation: 1
        ))
        state.locationSessionCoordinator.select(first, mode: .teleport)
        let request = try state.locationSessionCoordinator.beginApplication()

        let restored = await state.restoreManagedHelperSession(session, helperID: UUID(), for: device)

        XCTAssertFalse(restored)
        XCTAssertTrue(injector.adoptedReceipts.isEmpty, "a refused restore must not adopt in the adapter")
        guard case .applying(let requestID, _) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the owned application survives, got \(state.locationSessionCoordinator.state.application)")
        }
        XCTAssertEqual(requestID, request.id)
    }

    private func makeGatedRestoreFixture() -> (
        AppState, AdoptionRecordingLocationInjector, ProbeGate, Device, ManagedLocationHelperSession
    ) {
        let injector = AdoptionRecordingLocationInjector()
        let gate = ProbeGate()
        injector.adoptionGate = { await gate.hold() }
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        )
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 9,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 37.33182, longitude: -122.03118),
            acknowledgedAt: 1_725_000_000
        )
        state.selectedDevice = device
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: device.id, transport: .usb, endpointClass: .unresolved, generation: 1
        ))
        return (state, injector, gate, device, session)
    }

    func testAClearDuringTheAdapterAdoptionRefusesTheRestoreAndAbandonsTheAdoption() async throws {
        // A Clear that starts while `adoptManagedSession` is out makes the restore refuse
        // after the adapter already wrote the record's receipt into its generation
        // tracker. The adapter must forget that adoption, or adapter and coordinator
        // disagree about the session a later Clear validates against (review 2026-11-01,
        // issue 4).
        let (state, injector, gate, device, session) = makeGatedRestoreFixture()
        let helperID = UUID()

        let restore = Task { await state.restoreManagedHelperSession(session, helperID: helperID, for: device) }
        while !gate.entered { await Task.yield() }
        await state.clearLocation()
        XCTAssertEqual(state.statusMessage, "Location cleared")
        gate.release()
        let restored = await restore.value

        XCTAssertFalse(restored)
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        let adopted = try XCTUnwrap(injector.adoptedReceipts.first)
        XCTAssertEqual(injector.abandonedReceipts.count, 1, "the refused adoption is undone in the adapter")
        XCTAssertEqual(injector.abandonedReceipts.first?.0, adopted.0)
        XCTAssertEqual(injector.abandonedReceipts.first?.1, device.id)
    }

    func testAnOperationBegunDuringTheAdapterAdoptionRefusesTheRestoreAndAbandonsTheAdoption() async throws {
        let (state, injector, gate, device, session) = makeGatedRestoreFixture()

        let restore = Task { await state.restoreManagedHelperSession(session, helperID: UUID(), for: device) }
        while !gate.entered { await Task.yield() }
        state.locationSessionCoordinator.select(first, mode: .teleport)
        let request = try state.locationSessionCoordinator.beginApplication()
        gate.release()
        let restored = await restore.value

        XCTAssertFalse(restored)
        guard case .applying(let requestID, _) = state.locationSessionCoordinator.state.application else {
            return XCTFail("the owned application survives, got \(state.locationSessionCoordinator.state.application)")
        }
        XCTAssertEqual(requestID, request.id)
        let adopted = try XCTUnwrap(injector.adoptedReceipts.first)
        XCTAssertEqual(injector.abandonedReceipts.count, 1, "the refused adoption is undone in the adapter")
        XCTAssertEqual(injector.abandonedReceipts.first?.0, adopted.0)
        XCTAssertEqual(injector.abandonedReceipts.first?.1, device.id)
    }

    /// Adopts, abandons and clears through the real `LocationSessionGenerationTracker`
    /// as `DevLocationBridge` does. Its Clear waits until the refused restore abandoned
    /// its adoption, the order AppState allows: the Clear counter bump that refuses the
    /// restore comes before the Clear reaches the adapter (review 2026-11-01 issue 8).
    @MainActor
    private final class TrackerBackedRestoreInjector: LocationInjecting {
        private var tracker = LocationSessionGenerationTracker()
        let adoptionGate = ProbeGate()
        private(set) var abandonCount = 0
        private(set) var clearCount = 0
        private var abandonWaiter: CheckedContinuation<Void, Never>?

        func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
            throw LocationInjectionError.injectionFailed("Apply is not used by this restoration test")
        }

        func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {
            guard let session else { throw LocationInjectionError.injectionFailed("no session") }
            if abandonCount == 0 {
                await withCheckedContinuation { abandonWaiter = $0 }
            }
            try tracker.beginClear(session)
            clearCount += 1
            try tracker.completeClear(session)
        }

        func adoptManagedSession(receipt: LocationInjectionReceipt, stableDeviceID: String) async throws {
            try tracker.restore(receipt: receipt, stableDeviceID: stableDeviceID)
            await adoptionGate.hold()
        }

        func abandonAdoptedSession(_ receipt: LocationInjectionReceipt, stableDeviceID: String) async {
            tracker.abandon(receipt: receipt, stableDeviceID: stableDeviceID)
            abandonCount += 1
            abandonWaiter?.resume()
            abandonWaiter = nil
        }
    }

    func testAClearOfTheRestoredSessionAfterItsAdoptionWasAbandonedReachesTheHelper() async throws {
        // The coordinator still holds the helper record's identity as Ready (an earlier
        // adoption). A restore of that record is out in the adapter when the user presses
        // Clear: the Clear counter bump refuses the restore, which abandons the adoption
        // before the Clear enters the adapter. The Clear of that identity must still reach
        // the helper; refusing it stored it as unresolved and every retry failed the same
        // way (review 2026-11-01 issue 8, the Clear-wedge class).
        let injector = TrackerBackedRestoreInjector()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        )
        let device = Device(
            id: "00008130-0011223344556677",
            displayName: "Test Device",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "27.0"
        )
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(device.id),
            requestID: UUID().uuidString,
            sessionGeneration: 9,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 37.33182, longitude: -122.03118),
            acknowledgedAt: 1_725_000_000
        )
        let restoredIdentity = LocationSessionIdentity(
            stableDeviceID: device.id, transport: .usb, endpointClass: .remoteServiceDiscovery, generation: 9
        )
        state.selectedDevice = device
        state.locationSessionCoordinator.connectionReady(restoredIdentity)

        let restore = Task { await state.restoreManagedHelperSession(session, helperID: UUID(), for: device) }
        while !injector.adoptionGate.entered { await Task.yield() }
        let clear = Task { await state.clearLocation(reconcilingConnection: false) }
        while state.moveBlockedByClear == nil { await Task.yield() }
        injector.adoptionGate.release()
        let restored = await restore.value
        await clear.value

        XCTAssertFalse(restored)
        XCTAssertEqual(injector.abandonCount, 1, "the refused adoption is undone in the adapter")
        XCTAssertEqual(injector.clearCount, 1, "the Clear reached the helper")
        XCTAssertEqual(state.statusMessage, "Location cleared")
        XCTAssertNil(state.moveBlockedByClear, "no unresolved Clear blocks Move")
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
    }

    func testStoppingTheTunnelEndsTheHeldLocationTruthfully() async throws {
        // Closing the helper connection ends the held DVT session: once the helper
        // confirms the close, the app must say so (not "uncertain"), keep the desired
        // spot, and not ask Preserve/Clear at quit.
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnelController = FakeTunnelQuitController()
        let stateTunnel: FakeTunnelQuitController? = tunnelController
        let (state, session) = makeAcknowledgementState(
            injector: fake, mode: .teleport, managedSessionSource: source,
            tunnelQuitController: tunnelController
        )
        state.stageLocation(first, for: .teleport)
        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)

        let tunnel = try XCTUnwrap(stateTunnel)
        tunnel.helperStop = Task { true }
        state.device.onLocationSessionLoss?(.tunnelStoppedByUser)
        for _ in 0..<50 where state.locationSessionCoordinator.state.application != .idle {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertFalse(state.isSimulating)
        XCTAssertFalse(state.requiresLocationQuitDecision)
    }

    func testStopWithoutAConfirmedHelperCloseLeavesTheLocationUncertain() async throws {
        // If nothing confirms the connection closed (daemon tunnel, failed disconnect),
        // claiming "back on real location" would be false: report it uncertain.
        let fake = FakeLocationInjector()
        let tunnel = FakeTunnelQuitController()
        let (state, session) = makeAcknowledgementState(
            injector: fake, mode: .teleport,
            managedSessionSource: FakeManagedLocationSessionSource(helperID: UUID(), sessions: []),
            tunnelQuitController: tunnel
        )
        state.stageLocation(first, for: .teleport)
        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        tunnel.helperStop = Task { false }

        state.device.onLocationSessionLoss?(.tunnelStoppedByUser)
        for _ in 0..<50 {
            if case .uncertain = state.locationSessionCoordinator.state.application { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        guard case .uncertain = state.locationSessionCoordinator.state.application else {
            return XCTFail("expected uncertain, got \(state.locationSessionCoordinator.state.application)")
        }
        XCTAssertNotNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
    }

    func testAddRouteWaypointAppendsWithoutInjecting() {
        let state = makeState()

        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        XCTAssertEqual(state.currentRoute, [first, second])
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertFalse(state.isSimulating)
    }

    func testRemoveLastRouteWaypoint() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        state.removeLastRouteWaypoint()

        XCTAssertEqual(state.currentRoute, [first])
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testClearRouteEmptiesWaypoints() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)
        state.routeProgress = 0.4

        state.clearRoute()

        XCTAssertTrue(state.currentRoute.isEmpty)
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testStartSimulationWithoutDeviceDoesNotMarkSimulating() async {
        let state = makeState()
        state.activeMode = .route
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        await state.startSimulation()

        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationRouteWithoutTwoSpotsSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .route
        state.addRouteWaypoint(first)

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Add at least two spots on the map")
        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationJoystickWithoutStartSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .joystick

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Tap the map to set a starting location")
        XCTAssertFalse(state.isSimulating)
    }

    func testUpdateJoystickDirectionStoresVector() {
        let state = makeState()
        let direction = CGPoint(x: 0.4, y: -0.6)

        state.updateJoystickDirection(direction)

        XCTAssertEqual(state.joystickDirection.x, direction.x, accuracy: 1e-9)
        XCTAssertEqual(state.joystickDirection.y, direction.y, accuracy: 1e-9)
    }

    func testStageTeleportUpdatesTargetWithoutStartingSimulation() {
        let state = makeState()

        state.stageLocation(first, for: .teleport)

        XCTAssertEqual(state.targetLocation, first)
        XCTAssertEqual(state.currentRoute, [first])
        XCTAssertFalse(state.isSimulating)
        XCTAssertNil(state.currentLocation)
    }

    func testStageJumpAppendsWithoutStartingSimulation() {
        let state = makeState()

        state.stageLocation(first, for: .jump)
        state.stageLocation(second, for: .jump)

        XCTAssertEqual(state.currentRoute, [first, second])
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertFalse(state.isSimulating)
    }

    func testHistoryEligibilityRequiresConnectionAndValidPlan() {
        let accepted = SimulationStartPlan.teleport(first)
        let rejected = SimulationStartPlan.failed("No target")

        XCTAssertTrue(LocationHistoryPolicy.shouldRecord(canStartSimulation: true, plan: accepted))
        XCTAssertFalse(LocationHistoryPolicy.shouldRecord(canStartSimulation: false, plan: accepted))
        XCTAssertFalse(LocationHistoryPolicy.shouldRecord(canStartSimulation: true, plan: rejected))
    }

    func testMockTravelSpeedsMatchCanonicalValues() {
        let state = makeState()

        XCTAssertEqual(state.mockMetersPerSecond(for: .walking), 1.6)
        XCTAssertEqual(state.mockMetersPerSecond(for: .cycling), 5.4)
        XCTAssertEqual(state.mockMetersPerSecond(for: .fast), 11.2)
        XCTAssertEqual(state.mockMetersPerSecond(for: .driving), 15.6)
    }

    func testTunnelTargetUsesSelectedUDIDWhenAlreadyCanonical() {
        let state = makeState()
        let udid = "00000000-0000000000000001"
        state.selectedDevice = Device(
            id: udid,
            displayName: "🖇️ (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "🖇️"
        )

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    func testTunnelTargetFallsBackToMatchingDiscoveredUDID() {
        let state = makeState()
        let udid = "00000000-0000000000000001"
        state.selectedDevice = Device(
            id: "192.168.8.138",
            displayName: "🖇️ (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "🖇️"
        )
        state.availableDevices = [
            state.selectedDevice!,
            Device(
                id: udid,
                displayName: "🖇️ (iOS 27.0)",
                connectionType: .wifi,
                productType: "iPhone16,2",
                productVersion: "27.0",
                deviceName: "🖇️"
            ),
        ]

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    func testTunnelTargetFallsBackToSingleVisibleUDID() {
        let state = makeState()
        let udid = "00000000-0000000000000001"
        state.selectedDevice = Device(
            id: "2c0f:f5c0:600:ac13:1839:d9a8:fd2b:a7ad",
            displayName: "Paired iOS Device",
            connectionType: .wifi
        )
        state.availableDevices = [
            state.selectedDevice!,
            Device(id: udid, displayName: "Paired iOS Device", connectionType: .wifi),
        ]

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    // MARK: - Task 3: Location Session Model Tests

    @MainActor
    func testCooldownCannotCreateFalseActiveState() {
        let state = makeState()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        state.locationSessionCoordinator.select(target, mode: .teleport)

        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, target)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
    }


    private func makeAcknowledgementState(
        injector: FakeLocationInjector,
        mode: AppMode,
        managedSessionSource: (any ManagedLocationSessionSource)? = nil,
        deviceManager: DeviceManager? = nil,
        tunnelQuitController: (any TunnelQuitControlling)? = nil
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: managedSessionSource,
            deviceManager: deviceManager,
            tunnelQuitController: tunnelQuitController
        )
        state.selectedDevice = Device(id: "ack-device", displayName: "Ack Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = mode
        let session = LocationSessionIdentity(
            stableDeviceID: "ack-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)
        return (state, session)
    }

    func testCancelQuitPerformsNoManagedHelperOperation() async {
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuit(.cancel)

        XCTAssertEqual(result, .cancel)
        XCTAssertEqual(source.startCallCount, 0)
        XCTAssertEqual(source.refreshCallCount, 0)
        XCTAssertEqual(source.shutdownCallCount, 0)
        XCTAssertEqual(tunnel.stopCallCount, 0)
        XCTAssertEqual(tunnel.retainCallCount, 0)
    }

    func testQuitWithoutHeldLocationShutsDownEmptyManagedHelper() async {
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuitWithoutLocation()

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 1)
        // Quitting with nothing held must leave nothing running: the tunnel is
        // stopped and awaited before AppKit is told to terminate (live 2026-11-01:
        // the tunnel outlived every normal quit).
        XCTAssertEqual(tunnel.stopCallCount, 1)
        XCTAssertEqual(tunnel.retainCallCount, 0)
    }

    func testQuitStopsHelperBeforeTunnel() async {
        // The helper's DVT session rides the tunnel; stop it first.
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        var helperShutdownsWhenTunnelStopped: Int?
        tunnel.onStop = { helperShutdownsWhenTunnelStopped = source.shutdownCallCount }
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        _ = await state.prepareForQuitWithoutLocation()

        XCTAssertEqual(helperShutdownsWhenTunnelStopped, 1)
    }

    func testUnrestoredPreservedSessionRequiresQuitDecision() {
        // After a Preserve relaunch the helper record still holds the location even
        // before any device is selected; a plain quit must not silently end it.
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.hasRecordedHeldSessions = true
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: FakeTunnelQuitController()
        )

        XCTAssertTrue(state.requiresLocationQuitDecision)
    }

    func testPreserveAndQuitKeepsUnrestoredSessionRunning() async {
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.hasRecordedHeldSessions = true
        let tunnel = FakeTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuit(.preserveAndQuit)

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 0)
        XCTAssertEqual(tunnel.stopCallCount, 0)
        XCTAssertEqual(tunnel.retainCallCount, 1)
    }

    func testClearAndQuitEndsUnrestoredSessionByStoppingHelper() async {
        // Terminating the helper's held session is the real Clear for a session this
        // app session never restored (nothing for the coordinator to clear).
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.hasRecordedHeldSessions = true
        let tunnel = FakeTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: fake,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuit(.clearAndQuit)

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 1)
        XCTAssertEqual(tunnel.stopCallCount, 1)
    }

    func testClearAndQuitReportsUnrestoredSessionThatSurvived() async {
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        source.hasRecordedHeldSessions = true
        source.shutdownLeavesRecordedSessions = true
        let tunnel = FakeTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuit(.clearAndQuit)

        guard case .failed = result else {
            return XCTFail("A held location that survived Clear must be reported, got \(result)")
        }
        XCTAssertEqual(tunnel.stopCallCount, 0, "the tunnel carries the surviving session")
    }

    func testQuitWithoutHeldLocationReportsTunnelThatWouldNotStop() async {
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        tunnel.stopResult = .failed("tunnel PID 4242 is still running")
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source,
            tunnelQuitController: tunnel
        )

        let result = await state.prepareForQuitWithoutLocation()

        guard case .failed(let message) = result else {
            return XCTFail("A tunnel that survives quit must be reported, got \(result)")
        }
        XCTAssertTrue(message.contains("tunnel PID 4242 is still running"), message)
    }

    func testPreserveAndQuitKeepsHeldTruthAndManagedHelperAlive() async throws {
        let fake = FakeLocationInjector()
        let helperID = UUID()
        let source = FakeManagedLocationSessionSource(helperID: helperID, sessions: [])
        let tunnel = FakeTunnelQuitController()
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: source,
            tunnelQuitController: tunnel
        )
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value

        let receipt = try XCTUnwrap(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        let actualChannel = try XCTUnwrap(receipt.actualChannel)
        source.adoptedHelperSessions = [ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash("ack-device"),
            requestID: receipt.requestID.uuidString,
            sessionGeneration: receipt.sessionGeneration,
            physicalTransport: receipt.transport.rawValue,
            actualChannel: actualChannel.rawValue,
            endpointClass: receipt.endpointClass.rawValue,
            coordinate: ManagedLocationHelperCoordinate(
                latitude: receipt.coordinate.latitude,
                longitude: receipt.coordinate.longitude
            ),
            acknowledgedAt: receipt.completedAt.timeIntervalSince1970
        )]

        let result = await state.prepareForQuit(.preserveAndQuit)

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.startCallCount, 1)
        XCTAssertEqual(source.refreshCallCount, 1)
        XCTAssertEqual(source.shutdownCallCount, 0)
        // The helper injects only over the app tunnel's RSD endpoint (885ea3a), so a
        // preserved location needs the tunnel kept alive deliberately, not stopped.
        XCTAssertEqual(tunnel.stopCallCount, 0)
        XCTAssertEqual(tunnel.retainCallCount, 1)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        let preserveCalls = await fake.calls()
        XCTAssertFalse(preserveCalls.contains { call in
            if case .clear = call { return true }
            return false
        })
    }

    func testTransportReplacementDuringAConfirmedClearReportsClearAndTheLiveConnectionReady() async throws {
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: nil, sessions: [])
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: source
        )
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        let receipt = try XCTUnwrap(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)

        await fake.setShouldBlockClear(true)
        let clearing = Task { await state.clearLocation() }
        try await fake.waitForClearEntered()
        let wifiDevice = Device(
            id: session.stableDeviceID,
            displayName: "Ack Device",
            connectionType: .wifi
        )
        state.selectDevice(wifiDevice)
        await drainSelectionCallbacks()

        guard case .failed(let reason) = state.locationSessionCoordinator.state.connection else {
            await fake.releaseClear()
            await clearing.value
            return XCTFail("Expected transport replacement to fail connection during Clear")
        }
        XCTAssertTrue(reason.contains("transport changed"))
        // The Clear owns the location dimension until it returns; the replacement fails
        // only the connection (a phase moved off `.clearing` wedged Clear, live 2026-11-01).
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .clearing)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)

        await fake.releaseClear()
        await clearing.value
        // The injector confirmed the Clear: the device holds nothing, so the location
        // dimension is idle and Clear is reported as done. The Clear itself does not
        // repair the connection; the helper's probe on the transport the device is now
        // selected on does: the replaced (Wi-Fi) connection is live, so it is Ready on
        // the next generation (three-dimensional state truth).
        XCTAssertEqual(state.locationSessionCoordinator.state.application, .idle)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        // PRODUCT_REQUIREMENTS 5.2: the cleared point stays staged (not applied).
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, receipt.coordinate)
        XCTAssertNil(state.locationPresentation.appliedCoordinate)
        guard case .ready(let replaced) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("A live replaced connection is Ready again, got \(state.locationSessionCoordinator.state.connection)")
        }
        XCTAssertEqual(replaced.transport, .wifi)
        XCTAssertGreaterThan(replaced.generation, session.generation)
        XCTAssertNil(state.moveBlockedByClear)
        XCTAssertEqual(state.statusMessage, "Location cleared. The last spot is staged for the next mode.")
        XCTAssertFalse(state.requiresLocationQuitDecision)
    }

    func testClearAndQuitRequiresClearThenShutsDownManagedHelper() async throws {
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let tunnel = FakeTunnelQuitController()
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: source,
            tunnelQuitController: tunnel
        )
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value

        let result = await state.prepareForQuit(.clearAndQuit)

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 1)
        XCTAssertEqual(tunnel.stopCallCount, 1)
        XCTAssertEqual(tunnel.retainCallCount, 0)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        let clearCalls = await fake.calls()
        XCTAssertTrue(clearCalls.contains { call in
            if case .clear = call { return true }
            return false
        })
    }

    func testTeleportDoesNotBecomeActiveBeforeAcknowledgement() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .teleport)
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        XCTAssertFalse(state.isSimulating)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)

        await fake.releaseNextApplication(session: session)
        await application.value

        XCTAssertTrue(state.isSimulating)
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
    }

    func testJumpAdvancesExactlyOneHopAfterAcknowledgement() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .jump)
        state.stageLocation(first, for: .jump)
        state.stageLocation(second, for: .jump)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        XCTAssertEqual(state.jumpIndex, 0)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.isSimulating)

        await fake.releaseNextApplication(session: session)
        await application.value

        XCTAssertEqual(state.jumpIndex, 1)
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertTrue(state.isSimulating)
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter { if case .apply = $0 { return true }; return false }.count, 1)
    }

    func testQueuedJumpDoesNotAdvanceProgressOrClaimActiveLocation() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .jump)
        state.stageLocation(first, for: .jump)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session, outcome: .queued)
        await application.value

        XCTAssertEqual(state.jumpIndex, 0)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.isSimulating)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertNotNil(state.statusMessage)
    }

    // MARK: - One-Tap Reconnect

    /// Applies once through the Move path, forces a connection-class rejection so the
    /// coordinator classifies the connection as failed, then verifies one-tap
    /// reconnect restores a ready session and reapplies the desired coordinate.
    func testReconnectNowRestoresReadySessionAndReappliesDesiredLocation() async throws {
        let fake = FakeLocationInjector()
        let deviceManager = ReconnectStubDeviceManager(startBackgroundServices: false)
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: FakeManagedLocationSessionSource(helperID: nil, sessions: []),
            deviceManager: deviceManager
        )
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value
        XCTAssertEqual(state.currentLocation, first)

        let rejected = try state.locationSessionCoordinator.beginApplication()
        state.locationSessionCoordinator.reject(
            requestID: rejected.id,
            error: LocationInjectionError.endpointUnreachable
        )
        guard case .failed = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected the connection-class rejection to fail the connection")
        }
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)

        let reconnect = Task { await state.reconnectNow() }
        let reconnected = try await awaitReadyIdentity(in: state)
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: reconnected)
        await reconnect.value

        XCTAssertEqual(deviceManager.refreshCallCount, 1)
        guard case .ready(let restored) = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected reconnect to restore a ready session")
        }
        XCTAssertEqual(restored.stableDeviceID, session.stableDeviceID)
        XCTAssertEqual(restored.generation, session.generation + 1)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.currentLocation, first)
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter { if case .apply = $0 { return true }; return false }.count, 2)
    }

    func testReconnectNowWithoutSelectedDeviceChangesNothing() async {
        let fake = FakeLocationInjector()
        let deviceManager = ReconnectStubDeviceManager(startBackgroundServices: false)
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: fake,
            managedLocationSessionSource: FakeManagedLocationSessionSource(helperID: nil, sessions: []),
            deviceManager: deviceManager
        )
        state.locationSessionCoordinator.select(first, mode: .teleport)

        await state.reconnectNow()

        XCTAssertEqual(deviceManager.refreshCallCount, 1)
        guard case .unavailable = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected connection to remain unavailable without a selected device")
        }
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertFalse(state.isSimulating)
        let calls = await fake.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testReconnectNowTappedTwiceRunsASingleRecovery() async throws {
        let fake = FakeLocationInjector()
        let deviceManager = ReconnectStubDeviceManager(startBackgroundServices: false)
        let (state, session) = makeAcknowledgementState(
            injector: fake,
            mode: .teleport,
            managedSessionSource: FakeManagedLocationSessionSource(helperID: nil, sessions: []),
            deviceManager: deviceManager
        )
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await application.value

        let rejected = try state.locationSessionCoordinator.beginApplication()
        state.locationSessionCoordinator.reject(
            requestID: rejected.id,
            error: LocationInjectionError.endpointUnreachable
        )

        let firstTap = Task { await state.reconnectNow() }
        let secondTap = Task { await state.reconnectNow() }
        let reconnected = try await awaitReadyIdentity(in: state)
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: reconnected)
        await firstTap.value
        await secondTap.value

        guard case .ready = state.locationSessionCoordinator.state.connection else {
            return XCTFail("Expected repeated taps to leave one ready session")
        }
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter { if case .apply = $0 { return true }; return false }.count, 2)
    }
}
