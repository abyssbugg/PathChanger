import XCTest
@testable import PathChanger

private actor RecordingRecoverySleeper: RecoverySleeping {
    private var delays: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        delays.append(seconds)
    }

    func recordedDelays() -> [TimeInterval] { delays }
}

private actor BlockingRecoverySleeper: RecoverySleeping {
    private var continuation: CheckedContinuation<Void, Error>?
    private var entered = false

    func sleep(seconds: TimeInterval) async throws {
        entered = true
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelPendingSleep() }
        }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    private func cancelPendingSleep() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@MainActor
final class LocationSessionRecoveryTests: XCTestCase {
    private let coordinate = LocationCoordinate(latitude: 35.681236, longitude: 139.767125)

    private func session(
        transport: LocationTransport,
        endpoint: LocationEndpointClass,
        generation: UInt64
    ) -> LocationSessionIdentity {
        LocationSessionIdentity(
            stableDeviceID: "device-stable",
            transport: transport,
            endpointClass: endpoint,
            generation: generation
        )
    }

    private func seedActive(
        _ coordinator: LocationSessionCoordinator,
        session: LocationSessionIdentity,
        mode: LocationMode = .multiSpot
    ) throws {
        coordinator.select(coordinate, mode: mode)
        coordinator.connectionReady(session)
        let request = try coordinator.beginApplication()
        let receipt = LocationInjectionReceipt.accepted(
            request: request,
            endpointClass: session.endpointClass,
            session: LocationBridgeSession(sessionID: UUID(), generation: session.generation),
            outcome: .applied,
            completedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
        XCTAssertNil(coordinator.accept(receipt))
    }

    func testUSBReconnectPreservesDesiredAndWaitsForGenerationTwoReceipt() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let first = session(transport: .usb, endpoint: .direct, generation: 1)
        let second = session(transport: .usb, endpoint: .direct, generation: 2)
        try seedActive(coordinator, session: first)
        coordinator.beginMovement(.multiSpot)
        coordinator.connectionLost(reason: "USB disconnected")

        let sleeper = RecordingRecoverySleeper()
        let recovery = Task { @MainActor in
            await coordinator.recover(
                strategy: ReconnectionStrategy(maxAttempts: 2, initialDelaySeconds: 0, maxDelaySeconds: 0, backoffMultiplier: 1, jitterFactor: 0),
                sleeper: sleeper,
                establishSession: { _, _ in second }
            )
        }

        await injector.waitUntilApplicationPending()
        XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
        XCTAssertEqual(coordinator.state.movement, .paused(.multiSpot))
        XCTAssertFalse(coordinator.state.application.isActive)

        await injector.releaseNextApplication(session: second)
        let usbResult = await recovery.value
        XCTAssertNil(usbResult)
        XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt?.sessionGeneration, 2)
        XCTAssertTrue(coordinator.state.application.isActive)
        XCTAssertEqual(coordinator.state.movement, .moving(.multiSpot))
    }

    func testWiFiRSDReconnectRequiresReapplyNotDeviceRefreshAlone() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let first = session(transport: .wifi, endpoint: .remoteServiceDiscovery, generation: 1)
        let second = session(transport: .wifi, endpoint: .remoteServiceDiscovery, generation: 2)
        try seedActive(coordinator, session: first, mode: .teleport)
        coordinator.connectionLost(reason: "RSD endpoint lost")

        let recovery = Task { @MainActor in
            await coordinator.recover(
                strategy: .conservative,
                sleeper: RecordingRecoverySleeper(),
                establishSession: { _, _ in second }
            )
        }

        await injector.waitUntilApplicationPending()
        XCTAssertFalse(coordinator.state.application.isActive, "A refreshed device/session is not recovery success")
        await injector.releaseNextApplication(session: second)
        let wifiResult = await recovery.value
        XCTAssertNil(wifiResult)
        XCTAssertTrue(coordinator.state.application.isActive)
    }

    func testFailoverKeepsStableIdentityAndReappliesBeforeActive() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let usb = session(transport: .usb, endpoint: .direct, generation: 4)
        let wifi = session(transport: .wifi, endpoint: .remoteServiceDiscovery, generation: 5)
        try seedActive(coordinator, session: usb, mode: .joystick)
        coordinator.beginMovement(.joystick)
        coordinator.connectionLost(reason: "USB unavailable; Wi-Fi verified")

        let recovery = Task { @MainActor in
            await coordinator.recover(
                strategy: .conservative,
                sleeper: RecordingRecoverySleeper(),
                establishSession: { _, previous in
                    XCTAssertEqual(previous?.stableDeviceID, wifi.stableDeviceID)
                    return wifi
                }
            )
        }

        await injector.waitUntilApplicationPending()
        XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
        XCTAssertEqual(coordinator.state.movement, .paused(.joystick))
        await injector.releaseNextApplication(session: wifi)
        let failoverResult = await recovery.value
        XCTAssertNil(failoverResult)
        XCTAssertEqual(coordinator.state.connection, .ready(identity: wifi))
        XCTAssertTrue(coordinator.state.application.isActive)
    }

    func testRecoveryExhaustionUsesConfiguredBoundAndRetainsDesiredLocation() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let first = session(transport: .usb, endpoint: .direct, generation: 1)
        try seedActive(coordinator, session: first)
        coordinator.connectionLost(reason: "transport lost")
        let sleeper = RecordingRecoverySleeper()
        var attempts = 0
        let strategy = ReconnectionStrategy(
            maxAttempts: 3,
            initialDelaySeconds: 1,
            maxDelaySeconds: 4,
            backoffMultiplier: 2,
            jitterFactor: 0
        )

        let result = await coordinator.recover(
            strategy: strategy,
            sleeper: sleeper,
            establishSession: { _, _ in
                attempts += 1
                throw DeviceError.connectionFailed("still unavailable")
            }
        )

        XCTAssertEqual(result, .recoveryExhausted)
        XCTAssertEqual(attempts, strategy.maxAttempts)
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(delays, [1, 2])
        XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
        XCTAssertFalse(coordinator.state.application.isActive)
    }

    func testExplicitRetryRequiresANewerGeneration() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let first = session(transport: .usb, endpoint: .direct, generation: 7)
        let stale = session(transport: .usb, endpoint: .direct, generation: 7)
        let fresh = session(transport: .usb, endpoint: .direct, generation: 8)
        try seedActive(coordinator, session: first)
        coordinator.connectionLost(reason: "transport lost")
        var sessions = [stale, fresh]

        let recovery = Task { @MainActor in
            await coordinator.recover(
                strategy: ReconnectionStrategy(maxAttempts: 2, initialDelaySeconds: 0, maxDelaySeconds: 0, backoffMultiplier: 1, jitterFactor: 0),
                sleeper: RecordingRecoverySleeper(),
                establishSession: { _, _ in sessions.removeFirst() }
            )
        }

        await injector.waitUntilApplicationPending()
        await injector.releaseNextApplication(session: fresh)
        let result = await recovery.value
        XCTAssertNil(result)
        XCTAssertEqual(coordinator.state.connection, .ready(identity: fresh))
    }

    func testRecoveryCancellationIsTerminalButPreservesDesiredLocation() async throws {
        let injector = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: injector)
        let first = session(transport: .wifi, endpoint: .remoteServiceDiscovery, generation: 2)
        try seedActive(coordinator, session: first, mode: .joystick)
        coordinator.beginMovement(.joystick)
        coordinator.connectionLost(reason: "tunnel lost")
        let sleeper = BlockingRecoverySleeper()

        let recovery = Task { @MainActor in
            await coordinator.recover(
                strategy: .default,
                sleeper: sleeper,
                establishSession: { _, _ in throw DeviceError.connectionFailed("offline") }
            )
        }

        await sleeper.waitUntilEntered()
        recovery.cancel()
        let result = await recovery.value
        XCTAssertEqual(result, .recoveryCancelled)
        XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
        XCTAssertEqual(coordinator.state.movement, .paused(.joystick))
        XCTAssertFalse(coordinator.state.application.isActive)
    }

    func testTypedLossSourcesPauseMovementAndPreserveDesiredTruth() throws {
        let events: [LocationSessionLossEvent] = [
            .bridgeTerminated(exitCode: 9),
            .heldProcessExited,
            .tunnelHealthLost,
            .selectedDeviceLost(stableDeviceID: "device-stable"),
            .endpointReplaced,
            .appCancelled
        ]

        for event in events {
            let coordinator = LocationSessionCoordinator(injector: FakeLocationInjector())
            let first = session(transport: .wifi, endpoint: .remoteServiceDiscovery, generation: 1)
            try seedActive(coordinator, session: first, mode: .joystick)
            let receipt = coordinator.state.lastAcknowledgedReceipt
            coordinator.beginMovement(.joystick)

            coordinator.submit(event)

            XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
            XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
            XCTAssertEqual(coordinator.state.movement, .paused(.joystick))
            XCTAssertFalse(coordinator.state.application.isActive)
        }
    }
}
