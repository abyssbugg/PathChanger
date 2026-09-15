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

        func shutdownHelper() async throws {
            shutdownCallCount += 1
        }
    }

    private final class AdoptionRecordingLocationInjector: LocationInjecting, @unchecked Sendable {
        private(set) var adoptedReceipts: [(LocationInjectionReceipt, String)] = []

        func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
            throw LocationInjectionError.injectionFailed("Apply is not used by this restoration test")
        }

        func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}

        func adoptManagedSession(
            receipt: LocationInjectionReceipt,
            stableDeviceID: String
        ) async throws {
            adoptedReceipts.append((receipt, stableDeviceID))
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
        XCTAssertEqual(state.currentLocation, coordinate)
        XCTAssertTrue(state.isSimulating)
        XCTAssertEqual(
            state.locationSessionCoordinator.state.movement,
            LocationMovementPhase.idle
        )
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
        managedSessionSource: (any ManagedLocationSessionSource)? = nil
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: managedSessionSource
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
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source
        )

        let result = await state.prepareForQuit(.cancel)

        XCTAssertEqual(result, .cancel)
        XCTAssertEqual(source.startCallCount, 0)
        XCTAssertEqual(source.refreshCallCount, 0)
        XCTAssertEqual(source.shutdownCallCount, 0)
    }

    func testQuitWithoutHeldLocationShutsDownEmptyManagedHelper() async {
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
        let state = AppState(
            startBackgroundServices: false,
            managedLocationSessionSource: source
        )

        let result = await state.prepareForQuitWithoutLocation()

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 1)
    }

    func testPreserveAndQuitKeepsHeldTruthAndManagedHelperAlive() async throws {
        let fake = FakeLocationInjector()
        let helperID = UUID()
        let source = FakeManagedLocationSessionSource(helperID: helperID, sessions: [])
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
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt, receipt)
        let preserveCalls = await fake.calls()
        XCTAssertFalse(preserveCalls.contains { call in
            if case .clear = call { return true }
            return false
        })
    }

    func testTransportReplacementDuringClearPreservesAcknowledgedTruthAsUncertain() async throws {
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
        guard case .uncertain(let lastReceipt, _) = state.locationSessionCoordinator.state.application else {
            await fake.releaseClear()
            await clearing.value
            return XCTFail("Expected Clear interruption to remain uncertain")
        }
        XCTAssertEqual(lastReceipt, receipt)

        await fake.releaseClear()
        await clearing.value
        guard case .uncertain(let finalReceipt, _) = state.locationSessionCoordinator.state.application else {
            return XCTFail("Completed stale Clear must not overwrite newer uncertainty")
        }
        XCTAssertEqual(finalReceipt, receipt)
    }

    func testClearAndQuitRequiresClearThenShutsDownManagedHelper() async throws {
        let fake = FakeLocationInjector()
        let source = FakeManagedLocationSessionSource(helperID: UUID(), sessions: [])
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

        let result = await state.prepareForQuit(.clearAndQuit)

        XCTAssertEqual(result, .terminate)
        XCTAssertEqual(source.shutdownCallCount, 1)
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
}
