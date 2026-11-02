//
//  AutomaticReconnectTests.swift
//  PathChangerTests
//
//  PRODUCT_REQUIREMENTS §7.3 automatic reconnect (owner decision 2026-11-02): after a
//  connection loss the user did not cause, PathChanger waits for the phone, reopens the
//  helper's unprivileged connection and reapplies the held coordinate without Start.
//  Overnight 2026-11-01 one 5-attempt burst ended "recoveryExhausted" and nothing retried.
//
//  No device, no tunnel, no privilege: the injector, device manager, tunnel controller,
//  sleeper and clock are fakes. Every wait is bounded so a regression fails, not hangs.
//

import XCTest
@testable import PathChanger

// MARK: - Test doubles

/// Records each requested delay and holds it until the test releases it (or the waiting
/// task is cancelled), so the reconnect schedule is observable without real time.
actor ControlledReconnectSleeper: RecoverySleeping {
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]
    private var order: [Int] = []
    private var nextID = 0
    private var requests: [TimeInterval] = []
    private var cancellations = 0

    func sleep(seconds: TimeInterval) async throws {
        let id = nextID
        nextID += 1
        requests.append(seconds)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[id] = continuation
                order.append(id)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        cancellations += 1
        continuation.resume(throwing: CancellationError())
    }

    func releaseOldest() {
        guard let id = order.first, let continuation = waiters.removeValue(forKey: id) else { return }
        order.removeFirst()
        continuation.resume()
    }

    func recordedRequests() -> [TimeInterval] { requests }
    func pendingCount() -> Int { waiters.count }
    func cancellationCount() -> Int { cancellations }
}

@MainActor
final class ReconnectTestClock {
    var now = Date(timeIntervalSinceReferenceDate: 7_000_000)
}

@MainActor
final class ReconnectTestFlag {
    var value = false
}

/// Holds a caller until `open()`.
actor ReconnectTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private final class QuietReconnectDeviceManager: DeviceManager {
    private(set) var refreshCount = 0
    override func refreshDevices() async { refreshCount += 1 }
}

private final class EmptyManagedSessionSource: ManagedLocationSessionSource {
    var adoptedHelperID: UUID? { nil }
    var adoptedHelperSessions: [ManagedLocationHelperSession] { [] }
    var hasRecordedHeldSessions: Bool { false }
    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus {
        .notConnected("test")
    }
    func start() async throws {}
    func refreshAdoptedHelperSessions() async throws {}
    func shutdownHelper() async throws {}
}

private final class RecordingTunnelQuitController: TunnelQuitControlling {
    private(set) var resumedDevices: [String] = []
    func stopTunnelForQuit() async -> TunnelQuitStopResult { .stopped }
    func retainTunnelForPreservedLocation() {}
    func pendingHelperStop(for deviceId: String) -> Task<Bool, Never>? { nil }
    func resumeLocationCommands(for deviceId: String) { resumedDevices.append(deviceId) }
}

/// A helper record holding a session for the awaited phone; counts the liveness probes
/// the record restore runs (it probes only once it decided it may restore).
private final class ProbeCountingManagedSessionSource: ManagedLocationSessionSource {
    let adoptedHelperID: UUID? = UUID()
    let adoptedHelperSessions: [ManagedLocationHelperSession]
    var hasRecordedHeldSessions: Bool { true }
    private(set) var probeCount = 0

    init(deviceID: String) {
        adoptedHelperSessions = [ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(deviceID),
            requestID: UUID().uuidString,
            sessionGeneration: 1,
            physicalTransport: "Network",
            actualChannel: "networkLockdown",
            endpointClass: "direct",
            coordinate: ManagedLocationHelperCoordinate(latitude: 35.6762, longitude: 139.6503),
            acknowledgedAt: 1_789_000_000
        )]
    }

    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus {
        probeCount += 1
        return .notConnected("test")
    }
    func start() async throws {}
    func refreshAdoptedHelperSessions() async throws {}
    func shutdownHelper() async throws {}
}

/// Records each Developer Disk Image command and when it ran relative to the applies.
actor DDICommandRecorder {
    private(set) var commands: [[String]] = []
    private(set) var appliesSeenAtEachCommand: [Int] = []

    func record(_ command: [String], appliesSoFar: Int) {
        commands.append(command)
        appliesSeenAtEachCommand.append(appliesSoFar)
    }
}

private struct DDIRunnerFailure: Error {}

private struct BoundedWaitTimeout: Error {}

// MARK: - Pure policy and schedule

@MainActor
final class AutomaticReconnectPolicyTests: XCTestCase {
    private let id = "00008130-0011223344556677"
    private let receipt = LocationInjectionReceipt(
        requestID: UUID(), session: UUID(),
        coordinate: LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
        completedAt: Date(timeIntervalSince1970: 1_789_000_000), outcome: .applied
    )

    private func inputs(
        enabled: Bool = true, helper: Bool = true, latched: Bool = false, clearPending: Bool = false,
        application: LocationApplicationPhase? = nil, receipt hasReceipt: Bool = true,
        awaited: String?? = .none, selected: String? = nil
    ) -> AutoReconnectPolicy.Inputs {
        AutoReconnectPolicy.Inputs(
            isEnabled: enabled,
            usesHelperConnection: helper,
            isLatchedByUser: latched,
            hasClearPending: clearPending,
            application: application ?? .uncertain(lastReceipt: receipt, reason: "lost"),
            hasAcknowledgedReceipt: hasReceipt,
            awaitedDeviceID: awaited ?? id,
            selectedDeviceID: selected
        )
    }

    func testAHeldLocationLostWithoutTheUserWaitsForItsDevice() {
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs()), .wait(deviceID: id))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .lost("gone"))), .wait(deviceID: id))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(selected: id)), .wait(deviceID: id))
    }

    func testEveryRefusalHasItsReason() {
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(enabled: false)), .refuse(.disabled))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(helper: false)), .refuse(.daemonMode))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(latched: true)), .refuse(.stoppedByUser))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(clearPending: true)), .refuse(.clearPending))
        // After a successful Clear the last point is only staged: desired, no receipt, idle.
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .idle, receipt: false)), .refuse(.nothingHeld))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .idle)), .refuse(.nothingHeld))
        XCTAssertEqual(
            AutoReconnectPolicy.evaluate(inputs(application: .uncertain(lastReceipt: nil, reason: "x"), receipt: false)),
            .refuse(.nothingHeld)
        )
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .active(receipt: receipt))), .refuse(.nothingHeld))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .clearing)), .refuse(.nothingHeld))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(application: .failed("x"))), .refuse(.nothingHeld))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(awaited: .some(nil))), .refuse(.noDevice))
        XCTAssertEqual(AutoReconnectPolicy.evaluate(inputs(selected: "00008120-001B000E3E82002F")),
                       .refuse(.otherDeviceSelected))
    }

    func testBurstsAreSpacedAndBackOffToFiveMinutes() {
        XCTAssertEqual((0...6).map(AutoReconnectSchedule.spacing(afterFailedBursts:)), [0, 20, 40, 80, 160, 300, 300])
        XCTAssertEqual((0...5).map(AutoReconnectSchedule.fallbackDelay(afterFailedBursts:)), [60, 60, 120, 240, 300, 300])
        for failures in 0...20 {
            XCTAssertGreaterThanOrEqual(
                AutoReconnectSchedule.fallbackDelay(afterFailedBursts: failures),
                AutoReconnectSchedule.spacing(afterFailedBursts: failures)
            )
        }
    }
}

// MARK: - AppState

/// Finding 12: a second wait must end a first one still stored, not leak it.
@MainActor
final class AutoReconnectWaiterTests: XCTestCase {
    @MainActor
    private final class WakeBox {
        var value: AutoReconnectWaiter.Wake?
    }

    func testASecondWaitEndsTheFirstInsteadOfLeakingIt() async throws {
        let waiter = AutoReconnectWaiter()
        let sleeper = ControlledReconnectSleeper()
        let first = WakeBox()
        _ = Task { @MainActor in first.value = await waiter.wait(timeout: 60, sleeper: sleeper) }
        var deadline = Date().addingTimeInterval(2)
        while await sleeper.pendingCount() < 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        let second = Task { @MainActor in await waiter.wait(timeout: 60, sleeper: sleeper) }
        deadline = Date().addingTimeInterval(2)
        while first.value == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        XCTAssertEqual(first.value, .cancelled, "the first wait must end, not hang with a dropped continuation")
        waiter.signalReachable()
        let secondWake = await second.value
        XCTAssertEqual(secondWake, .reachable)
    }
}

@MainActor
final class AutomaticReconnectTests: XCTestCase {
    private let deviceID = "00008130-0011223344556677"
    private let held = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private var phone: Device {
        Device(id: deviceID, displayName: "Owner iPhone", connectionType: .wifi,
               productType: "iPhone17,1", productVersion: "27.2", deviceName: "Owner iPhone")
    }
    private let oneAttempt = ReconnectionStrategy(
        maxAttempts: 1, initialDelaySeconds: 0, maxDelaySeconds: 0, backoffMultiplier: 1, jitterFactor: 0
    )

    private struct Fixture {
        let state: AppState
        let injector: FakeLocationInjector
        let sleeper: ControlledReconnectSleeper
        let clock: ReconnectTestClock
        let deviceManager: QuietReconnectDeviceManager
        let tunnel: RecordingTunnelQuitController
    }

    private func makeFixture(
        usesHelper: Bool = true,
        managedSource: (any ManagedLocationSessionSource)? = nil,
        ddiRunner: (([String]) async throws -> String)? = nil
    ) -> Fixture {
        let injector = FakeLocationInjector()
        let deviceManager = QuietReconnectDeviceManager(startBackgroundServices: false)
        deviceManager.connectionMode = .auto
        let sleeper = ControlledReconnectSleeper()
        let clock = ReconnectTestClock()
        let tunnel = RecordingTunnelQuitController()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: managedSource ?? EmptyManagedSessionSource(),
            deviceManager: deviceManager,
            ddiPreparerFactory: ddiRunner.map { runner -> (DeviceManager) -> DeveloperDiskImagePreparer in
                { _ in DeveloperDiskImagePreparer(runner: runner, allowsNetworkFallback: { false }) }
            },
            tunnelQuitController: tunnel,
            automaticReconnect: AutomaticReconnectEnvironment(
                isEnabled: true,
                usesHelperConnection: { usesHelper },
                sleeper: sleeper,
                now: { clock.now },
                burstStrategy: oneAttempt
            )
        )
        state.device.availableDevices = [phone]
        state.device.wifiDirectDeviceIds = [deviceID]
        state.device.selectedDevice = phone
        addTeardownBlock { @MainActor in
            // A burst left mid-apply would wait forever on the fake (it ignores
            // cancellation): release its application while the wait stops.
            let stop = Task { @MainActor in await state.stopAutomaticReconnect(reason: "test teardown") }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let pending = await injector.pendingApplicationCount()
                guard state.isAwaitingAutomaticReconnect || pending > 0 else { break }
                await injector.cancelNextApplication()
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            await stop.value
        }
        return Fixture(state: state, injector: injector, sleeper: sleeper, clock: clock,
                       deviceManager: deviceManager, tunnel: tunnel)
    }

    /// The held location: generation 1 acknowledged over Wi-Fi.
    private func seedHeldLocation(_ fixture: Fixture) throws {
        let coordinator = fixture.state.locationSessionCoordinator
        let session = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                              endpointClass: .direct, generation: 1)
        coordinator.select(held, mode: .teleport)
        coordinator.connectionReady(session)
        let request = try coordinator.beginApplication()
        XCTAssertNil(coordinator.accept(LocationInjectionReceipt.accepted(
            request: request, endpointClass: .direct,
            session: LocationBridgeSession(sessionID: UUID(), generation: 1),
            outcome: .applied, completedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )))
    }

    /// The phone dropped out of every source; discovery deselected it (as it does).
    private func losePhone(_ fixture: Fixture) {
        fixture.state.device.wifiDirectDeviceIds = []
        fixture.state.device.selectedDevice = nil
        fixture.state.device.onLocationSessionLoss?(.selectedDeviceLost(stableDeviceID: deviceID))
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("Timed out waiting for: \(what)")
                throw BoundedWaitTimeout()
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Lets queued main-actor work run before asserting that nothing happened.
    private func settle() async {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func applyCount(_ injector: FakeLocationInjector) async -> Int {
        await injector.calls().filter { if case .apply = $0 { return true }; return false }.count
    }

    private func readyIdentity(_ state: AppState) async throws -> LocationSessionIdentity {
        var identity: LocationSessionIdentity?
        try await waitUntil("a ready recovery session") {
            if case .ready(let ready) = state.locationSessionCoordinator.state.connection { identity = ready }
            return identity != nil
        }
        return identity!
    }

    // MARK: Waiting and the phone's return

    func testABurstThatExhaustsKeepsWaitingAndSaysSoInWords() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")

        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in
            throw DeviceError.connectionFailed("No verified transport is available")
        }

        try await waitUntil("waiting for the phone") { fixture.state.isAwaitingAutomaticReconnect }
        XCTAssertNotEqual(fixture.state.lastError, "recoveryExhausted")
        XCTAssertEqual(fixture.state.device.awaitedReconnectDeviceID, deviceID)
        let notice = try XCTUnwrap(fixture.state.automaticReconnectNotice)
        XCTAssertTrue(notice.contains("reconnects"), notice)
        guard case .failed = fixture.state.locationSessionCoordinator.state.connection else {
            return XCTFail("The connection stays Lost while waiting")
        }
        XCTAssertEqual(fixture.state.locationSessionCoordinator.state.desiredLocation, held)
        XCTAssertFalse(fixture.state.locationSessionCoordinator.state.application.isActive)
    }

    func testThePhoneComingBackRunsOneBurstAndReappliesBeforeActive() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)

        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertEqual(fixture.state.device.awaitedReconnectDeviceID, deviceID)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }
        let observed300 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed300, [60])
        let observed301 = await applyCount(fixture.injector)
        XCTAssertEqual(observed301, 0)

        fixture.state.device.wifiDirectDeviceIds = [deviceID]

        try await waitUntil("the reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        XCTAssertFalse(fixture.state.locationSessionCoordinator.state.application.isActive,
                       "Reconnected is not active until the reapply is acknowledged")
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertNotNil(fixture.state.automaticReconnectNotice)
        let identity = try await readyIdentity(fixture.state)
        XCTAssertEqual(identity.generation, 2)
        XCTAssertEqual(identity.transport, .wifi)
        await fixture.injector.releaseNextApplication(session: identity)

        try await waitUntil("reconnected") { !fixture.state.isAwaitingAutomaticReconnect }
        let coordinatorState = fixture.state.locationSessionCoordinator.state
        XCTAssertTrue(coordinatorState.application.isActive)
        XCTAssertEqual(coordinatorState.lastAcknowledgedReceipt?.sessionGeneration, 2)
        XCTAssertEqual(coordinatorState.lastAcknowledgedReceipt?.coordinate, held)
        XCTAssertNil(fixture.state.device.awaitedReconnectDeviceID)
        XCTAssertNil(fixture.state.automaticReconnectNotice)
        XCTAssertEqual(fixture.state.selectedDevice?.id, deviceID)
        XCTAssertEqual(fixture.state.selectedDevice?.displayName, "Owner iPhone")
        await settle()
        let observed325 = await applyCount(fixture.injector)
        XCTAssertEqual(observed325, 1, "exactly one reapply")
        let observed326 = await fixture.sleeper.pendingCount()
        XCTAssertEqual(observed326, 0, "the fallback timer was cancelled")
        XCTAssertTrue(fixture.tunnel.resumedDevices.isEmpty, "auto reconnect never lifts a Stop's block")
    }

    func testABonjourOnlySightingAlsoTriggersTheReconnect() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        fixture.state.device.networkAdvertisedDeviceIds = [deviceID]

        try await waitUntil("the reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        let identity = try await readyIdentity(fixture.state)
        XCTAssertEqual(identity.transport, .wifi)
        await fixture.injector.releaseNextApplication(session: identity)
        try await waitUntil("reconnected") { !fixture.state.isAwaitingAutomaticReconnect }
        XCTAssertTrue(fixture.state.locationSessionCoordinator.state.application.isActive)
    }

    func testFailedBurstsAreRateLimitedWithBackoff() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        // Burst 1: the phone is seen, but the helper fails to apply.
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("burst 1") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.failNextApplication(code: "No route to host")
        try await waitUntil("the next wait") { await fixture.sleeper.recordedRequests().count == 2 }
        let observed357 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed357, [60, 60])
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)

        // Seen again at once: the next burst waits out the 20 s spacing.
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("the spacing wait") { await fixture.sleeper.recordedRequests().count == 3 }
        let observed363 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed363, [60, 60, 20])
        await settle()
        let observed365 = await applyCount(fixture.injector)
        XCTAssertEqual(observed365, 1, "no burst before the spacing elapsed")

        fixture.clock.now = fixture.clock.now.addingTimeInterval(20)
        await fixture.sleeper.releaseOldest()
        try await waitUntil("burst 2") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.failNextApplication(code: "No route to host")
        try await waitUntil("the next wait") { await fixture.sleeper.recordedRequests().count == 4 }
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("the spacing wait") { await fixture.sleeper.recordedRequests().count == 5 }
        let observed374 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed374, [60, 60, 20, 120, 40])
        let observed375 = await applyCount(fixture.injector)
        XCTAssertEqual(observed375, 2)
    }

    func testTheFallbackTimerTriesEvenWhenVisibilityNeverUpdates() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }
        let refreshesBefore = fixture.deviceManager.refreshCount

        await fixture.sleeper.releaseOldest()

        // The burst rediscovers (refresh) and finds no verified transport: it fails and
        // the next fallback wait begins.
        try await waitUntil("the next fallback wait") { await fixture.sleeper.recordedRequests().count == 2 }
        XCTAssertGreaterThan(fixture.deviceManager.refreshCount, refreshesBefore)
        let observed391 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed391, [60, 60])
        let observed392 = await applyCount(fixture.injector)
        XCTAssertEqual(observed392, 0)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
    }

    // MARK: What never reconnects automatically

    func testStopTunnelLatchesUntilReconnectOrMove() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)

        fixture.state.device.onLocationSessionLoss?(.tunnelStoppedByUser)
        losePhone(fixture)
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        await settle()
        let observed407 = await applyCount(fixture.injector)
        XCTAssertEqual(observed407, 0)
        let observed408 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed408, [])

        // Reconnect is explicit: it lifts the latch.
        fixture.state.device.selectedDevice = phone
        let reconnect = Task { await fixture.state.reconnectNow() }
        try await waitUntil("the manual reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        await reconnect.value
        XCTAssertTrue(fixture.state.locationSessionCoordinator.state.application.isActive)

        fixture.state.device.wifiDirectDeviceIds = []
        fixture.state.device.onLocationSessionLoss?(.tunnelHealthLost)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect, "after Reconnect a later loss waits again")
    }

    func testMoveLiftsTheStopLatch() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        fixture.state.device.onLocationSessionLoss?(.tunnelStoppedByUser)
        fixture.state.device.onLocationSessionLoss?(.tunnelHealthLost)
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)

        fixture.state.activeMode = .teleport
        fixture.state.stageLocation(held, for: .teleport)
        let move = Task { await fixture.state.startSimulation() }
        try await waitUntil("the Move apply") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        await move.value
        XCTAssertTrue(fixture.state.locationSessionCoordinator.state.application.isActive)

        fixture.state.device.wifiDirectDeviceIds = []
        fixture.state.device.onLocationSessionLoss?(.tunnelHealthLost)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
    }

    func testDaemonModeNeverReconnectsAutomatically() async throws {
        let fixture = makeFixture(usesHelper: false)
        try seedHeldLocation(fixture)
        losePhone(fixture)
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        await settle()
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        let observed448 = await applyCount(fixture.injector)
        XCTAssertEqual(observed448, 0)
        let observed449 = await fixture.sleeper.recordedRequests()
        XCTAssertEqual(observed449, [])
    }

    func testAStagedPointAfterASuccessfulClearIsNeverSentAutomatically() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        await fixture.state.clearLocation(reconcilingConnection: false)
        XCTAssertNil(fixture.state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        // The Clear-staging lane stages the last point as desired, with no receipt.
        fixture.state.locationSessionCoordinator.select(held, mode: .teleport)

        losePhone(fixture)
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        await settle()
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        let observed464 = await applyCount(fixture.injector)
        XCTAssertEqual(observed464, 0)
    }

    func testClearDuringTheWaitCancelsItAndNothingIsAppliedAfter() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        await fixture.state.clearLocation(reconcilingConnection: false)

        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertNil(fixture.state.device.awaitedReconnectDeviceID)
        try await waitUntil("the fallback timer cancelled") { await fixture.sleeper.pendingCount() == 0 }
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        fixture.state.device.onLocationSessionLoss?(.tunnelHealthLost)
        await settle()
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect,
                       "a Clear the phone could not confirm must not be undone by a reapply")
        let observed483 = await applyCount(fixture.injector)
        XCTAssertEqual(observed483, 0)
    }

    func testReconnectNowSupersedesTheWait() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        fixture.state.device.selectedDevice = phone
        let reconnect = Task { await fixture.state.reconnectNow() }
        try await waitUntil("the manual reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        try await waitUntil("the fallback timer cancelled") { await fixture.sleeper.pendingCount() == 0 }
        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        await reconnect.value

        XCTAssertTrue(fixture.state.locationSessionCoordinator.state.application.isActive)
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        await settle()
        let observed503 = await applyCount(fixture.injector)
        XCTAssertEqual(observed503, 1)
    }

    func testAFailedReconnectNowWaitsAgain() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        fixture.state.device.selectedDevice = phone
        let reconnect = Task { await fixture.state.reconnectNow() }
        try await waitUntil("the manual reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.failNextApplication(with: LocationInjectionError.endpointUnreachable)
        await reconnect.value

        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
    }

    func testABurstCancelledWhileRebuildingTheSessionSendsNothing() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")
        let gate = ReconnectTestGate()
        let entered = ReconnectTestFlag()
        let recovered = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                                endpointClass: .unresolved, generation: 2)
        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in
            entered.value = true
            await gate.wait()
            return recovered
        }
        try await waitUntil("the burst rebuilding the session") { entered.value }

        // Clear cancels the burst and waits for it while it is still rebuilding.
        let clear = Task { await fixture.state.clearLocation(reconcilingConnection: false) }
        await settle()
        await gate.open()
        await settle()

        let applies = await applyCount(fixture.injector)
        XCTAssertEqual(applies, 0, "a cancelled burst must not send the location")
        await fixture.injector.cancelNextApplication()
        await clear.value
    }

    // MARK: Movement after recovery

    func testRecoveryDoesNotLeaveMovementMovingWithNoEngine() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        let coordinator = fixture.state.locationSessionCoordinator
        coordinator.beginMovement(.multiSpot)
        coordinator.connectionLost(reason: "Tunnel health lost")
        XCTAssertEqual(coordinator.state.movement, .paused(.multiSpot))
        let recovered = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                                endpointClass: .unresolved, generation: 2)

        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in recovered }
        try await waitUntil("the reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.releaseNextApplication(session: recovered)
        try await waitUntil("recovered") { coordinator.state.application.isActive }

        XCTAssertEqual(coordinator.state.movement, .idle, "no engine survives a loss; the location holds")
        XCTAssertFalse(fixture.state.isMovementEngineRunning)
    }

    // MARK: Review 2026-11-02 (semantic-review/2026-11-02-135207-review.md)

    /// Finding 1: after a confirmed Clear the staged point is desired with no receipt.
    /// Reconnect reconnects but sends nothing (5.2), and Clear's latch holds.
    func testReconnectAfterAConfirmedClearDoesNotSendTheStagedPoint() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        await fixture.state.clearLocation(reconcilingConnection: false)
        XCTAssertEqual(fixture.state.stagedStartAfterClear, held)
        XCTAssertNil(fixture.state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Wi-Fi lost")

        let done = ReconnectTestFlag()
        let reconnect = Task { @MainActor in
            await fixture.state.reconnectNow()
            done.value = true
        }
        try await waitUntil("Reconnect finished or sent something") {
            if done.value { return true }
            return await fixture.injector.pendingApplicationCount() > 0
        }
        let applies = await applyCount(fixture.injector)
        if applies > 0 { await fixture.injector.cancelNextApplication() }
        await reconnect.value

        XCTAssertEqual(applies, 0, "Reconnect after Clear must not spoof the staged point")
        guard case .ready = fixture.state.locationSessionCoordinator.state.connection else {
            return XCTFail("Reconnect still reconnects the session")
        }
        XCTAssertEqual(fixture.state.stagedStartAfterClear, held, "the point stays staged")
        XCTAssertTrue(fixture.state.isAutomaticReconnectLatchedByUser,
                      "nothing was reapplied, so Clear's hold on automatic reconnect stays")
    }

    /// Finding 2: a burst must pass the Developer Disk Image gate before it reapplies.
    func testABurstChecksTheDiskImageBeforeItReapplies() async throws {
        let recorder = DDICommandRecorder()
        let fixture = makeFixture(ddiRunner: { command in
            await recorder.record(command, appliesSoFar: 0)
            return "[{\"image\":\"DeveloperDiskImage\"}]"
        })
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")
        let recovered = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                                endpointClass: .unresolved, generation: 2)

        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in recovered }

        try await waitUntil("the reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        let commandsBeforeApply = await recorder.commands
        XCTAssertEqual(commandsBeforeApply.count, 1, "the mount status is checked before the reapply")
        await fixture.injector.releaseNextApplication(session: recovered)
        try await waitUntil("recovered") { fixture.state.locationSessionCoordinator.state.application.isActive }
    }

    func testABurstWhoseDiskImageMountFailsIsAFailedAttemptNotActive() async throws {
        let recorder = DDICommandRecorder()
        let fixture = makeFixture(ddiRunner: { command in
            await recorder.record(command, appliesSoFar: 0)
            throw DDIRunnerFailure()
        })
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")
        let recovered = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                                endpointClass: .unresolved, generation: 2)

        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in recovered }

        try await waitUntil("the burst ended or reapplied") {
            if fixture.state.isAwaitingAutomaticReconnect { return true }
            return await fixture.injector.pendingApplicationCount() > 0
        }
        let applies = await applyCount(fixture.injector)
        let commands = await recorder.commands
        let wasActive = fixture.state.locationSessionCoordinator.state.application.isActive
        if applies > 0 { await fixture.injector.cancelNextApplication() }

        XCTAssertFalse(commands.isEmpty, "the burst asks for the Developer Disk Image")
        XCTAssertEqual(applies, 0, "a failed mount sends nothing; DVT would no-op on the phone")
        XCTAssertFalse(wasActive)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect, "the failed burst waits again")
    }

    /// Finding 3: Clear is the GUI's way to stop the wait. The phone is unreachable, so
    /// the Clear cannot be confirmed: the wait stops, the location stays Uncertain, Move
    /// is not wedged, and the message says what is true.
    func testClearIsOfferedWhileWaitingAndStopsTheWaitHonestly() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }

        XCTAssertTrue(fixture.state.locationPresentation.canClear, "Clear must be usable while waiting")
        await fixture.state.clearLocation()

        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertTrue(fixture.state.isAutomaticReconnectLatchedByUser)
        guard case .uncertain(let receipt, _) = fixture.state.locationSessionCoordinator.state.application else {
            return XCTFail("the phone may still hold the location: Uncertain, not idle or active")
        }
        XCTAssertEqual(receipt?.coordinate, held)
        XCTAssertNil(fixture.state.moveBlockedByClear, "an unreachable phone must not wedge Move")
        let message = fixture.state.statusMessage ?? ""
        XCTAssertTrue(message.contains("Stopped reconnecting"), message)
        XCTAssertTrue(message.contains("Reconnect"), message)
        let clears = await fixture.injector.calls().filter { if case .clear = $0 { return true }; return false }
        XCTAssertEqual(clears.count, 0, "nothing can reach the phone without a connection")

        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        await settle()
        let applies = await applyCount(fixture.injector)
        XCTAssertEqual(applies, 0)
    }

    /// Finding 4: the chip says Reconnecting while PathChanger waits, Lost after.
    func testTheConnectionChipSaysReconnectingWhileWaiting() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)

        XCTAssertEqual(fixture.state.locationPresentation.connectionLabel, "Reconnecting")
        XCTAssertNil(fixture.state.selectedDevice, "discovery deselected the phone")
        XCTAssertEqual(fixture.state.connectionChipLabel, "Reconnecting", "not Unavailable while waiting")

        await fixture.state.stopAutomaticReconnect(reason: "test")
        XCTAssertEqual(fixture.state.locationPresentation.connectionLabel, "Lost")
    }

    /// Finding 5: Move waits for an in-flight burst, then re-checks readiness.
    func testAMoveThatWaitedOnABurstRechecksReadiness() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("the burst's reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        XCTAssertTrue(fixture.state.canStartSimulation)

        fixture.state.activeMode = .teleport
        fixture.state.stageLocation(LocationCoordinate(latitude: 35.68, longitude: 139.66), for: .teleport)
        let done = ReconnectTestFlag()
        let move = Task { @MainActor in
            await fixture.state.startSimulation()
            done.value = true
        }
        await settle()
        // The phone leaves again while Move waits for the burst's helper command.
        fixture.state.device.wifiDirectDeviceIds = []
        await fixture.injector.failNextApplication(with: LocationInjectionError.endpointUnreachable)
        try await waitUntil("Move returned or sent") {
            if done.value { return true }
            return await fixture.injector.pendingApplicationCount() > 0
        }
        let applies = await applyCount(fixture.injector)
        if !done.value { await fixture.injector.cancelNextApplication() }
        await move.value

        XCTAssertEqual(applies, 1, "only the burst's reapply; Move must not send to a phone that is not ready")
    }

    /// Finding 5: Quit cancels an in-flight burst and does not wait out its helper command.
    func testQuitDoesNotBlockOnAnInFlightBurst() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("the burst's reapply") { await fixture.injector.pendingApplicationCount() == 1 }

        let done = ReconnectTestFlag()
        let quit = Task { @MainActor () -> LocationQuitPreparationResult in
            let result = await fixture.state.prepareForQuitWithoutLocation()
            done.value = true
            return result
        }
        let deadline = Date().addingTimeInterval(4)
        while !done.value, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let finishedInTime = done.value
        if !finishedInTime { await fixture.injector.cancelNextApplication() }
        let result = await quit.value

        XCTAssertTrue(finishedInTime, "Quit must not wait out the helper's command timeout")
        XCTAssertEqual(result, .terminate)
    }

    /// Finding 6: the helper-record restore must not run while a burst owns the session.
    func testHelperRecordRestoreDoesNotRaceABurst() async throws {
        let source = ProbeCountingManagedSessionSource(deviceID: deviceID)
        let fixture = makeFixture(managedSource: source)
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")
        await settle()
        let probesBefore = source.probeCount
        let gate = ReconnectTestGate()
        let reselected = ReconnectTestFlag()
        let recovered = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                                endpointClass: .unresolved, generation: 2)
        let phone = self.phone
        fixture.state.startLocationRecovery(strategy: oneAttempt) { _, _ in
            // The burst re-selects the phone (as `establishRecoverySession` does)...
            fixture.state.device.selectDevice(phone)
            reselected.value = true
            await gate.wait()
            return recovered
        }
        try await waitUntil("the burst re-selected the phone") { reselected.value }
        await settle()

        XCTAssertEqual(source.probeCount, probesBefore, "...and the restore must not probe or adopt meanwhile")
        await gate.open()
        try await waitUntil("the reapply") { await fixture.injector.pendingApplicationCount() == 1 }
        await fixture.injector.releaseNextApplication(session: recovered)
        try await waitUntil("recovered") { fixture.state.locationSessionCoordinator.state.application.isActive }
    }

    /// Finding 7: a wait whose session moved to another device waits for that device.
    func testAWaitRearmsForANewlyLostDevice() async throws {
        let otherID = "00008120-001B000E3E82002F"
        let other = Device(id: otherID, displayName: "Second iPhone", connectionType: .wifi,
                           productType: "iPhone16,1", productVersion: "27.2", deviceName: "Second iPhone")
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        try await waitUntil("the fallback timer") { await fixture.sleeper.pendingCount() == 1 }
        XCTAssertEqual(fixture.state.device.awaitedReconnectDeviceID, deviceID)

        // The user moved to a second phone, and that phone's session was lost too.
        let coordinator = fixture.state.locationSessionCoordinator
        fixture.state.device.availableDevices = [phone, other]
        fixture.state.device.selectedDevice = other
        coordinator.connectionReady(LocationSessionIdentity(stableDeviceID: otherID, transport: .wifi,
                                                            endpointClass: .direct, generation: 5))
        coordinator.connectionLost(reason: "Second phone lost")
        XCTAssertEqual(coordinator.recoverableDeviceID, otherID)

        // The first phone shows up: the loop wakes and finds the session moved on.
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        try await waitUntil("the wait re-armed for the second phone or ended") {
            fixture.state.device.awaitedReconnectDeviceID != deviceID
        }
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertEqual(fixture.state.device.awaitedReconnectDeviceID, otherID)
    }

    /// Finding 11: no engine runs while waiting, so Movement is not Paused.
    func testMovementIsIdleWhileWaiting() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.beginMovement(.multiSpot)
        losePhone(fixture)

        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertEqual(fixture.state.locationSessionCoordinator.state.movement, .idle)
        XCTAssertNotNil(fixture.state.locationSessionCoordinator.state.lastAcknowledgedReceipt,
                        "the location holds")
    }

    /// Finding 8: a held but uncertain location is not "Staged".
    func testAnUncertainHeldLocationIsNotMarkedStaged() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)

        let marker = try XCTUnwrap(fixture.state.locationMarker)
        XCTAssertEqual(marker.coordinate, held)
        XCTAssertEqual(marker.accessibilityLabel, "Location uncertain")
    }

    /// Finding 9: a step the phone applied while Clear drained its producers is the last
    /// spoofed point, so it is what Clear stages.
    func testClearStagesAPointAppliedDuringItsDrain() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        let next = LocationCoordinate(latitude: 35.70, longitude: 139.70)
        fixture.state.activeMode = .teleport
        fixture.state.stageLocation(next, for: .teleport)
        let move = Task { @MainActor in await fixture.state.startSimulation() }
        try await waitUntil("the Move apply") { await fixture.injector.pendingApplicationCount() == 1 }

        let clear = Task { @MainActor in await fixture.state.clearLocation(reconcilingConnection: false) }
        await settle()
        let session = LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                              endpointClass: .direct, generation: 1)
        await fixture.injector.releaseNextApplication(session: session)
        await clear.value
        await move.value

        XCTAssertNil(fixture.state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertEqual(fixture.state.stagedStartAfterClear, next)
    }
}

// MARK: - DeviceStateManager

@MainActor
final class AutomaticReconnectDeviceStateTests: XCTestCase {
    private let deviceID = "00008130-0011223344556677"
    private var phone: Device {
        Device(id: deviceID, displayName: "Owner iPhone", connectionType: .wifi,
               productType: "iPhone17,1", productVersion: "27.2", deviceName: "Owner iPhone")
    }
    private var previous: LocationSessionIdentity {
        LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi,
                                endpointClass: .remoteServiceDiscovery, generation: 3)
    }

    private final class RefreshRecordingDeviceManager: DeviceManager {
        private(set) var refreshes = 0
        private(set) var browseDecisions: [Bool] = []
        override func refreshDevices() async {}
        override func refreshTransportAvailability(
            browseBonjour shouldBrowse: (Set<String>, Set<String>) -> Bool = { _, _ in true }
        ) async {
            refreshes += 1
            browseDecisions.append(shouldBrowse([], []))
        }
    }

    private func manager(mode: DeviceManager.ConnectionMode) -> (DeviceStateManager, RefreshRecordingDeviceManager) {
        let deviceManager = RefreshRecordingDeviceManager(startBackgroundServices: false)
        deviceManager.connectionMode = mode
        return (DeviceStateManager(deviceManager: deviceManager, startBackgroundServices: false), deviceManager)
    }

    func testTheAwaitedPhoneIsStillPolledAndBrowsedWithNothingSelected() async {
        let (manager, deviceManager) = manager(mode: .auto)
        XCTAssertNil(manager.selectedDevice)
        manager.awaitedReconnectDeviceID = deviceID

        await manager.refreshTransportAvailabilityIfNeeded(now: Date(timeIntervalSinceReferenceDate: 8_000_000))

        XCTAssertEqual(deviceManager.refreshes, 1)
        XCTAssertEqual(deviceManager.browseDecisions, [true], "Bonjour is browsed for the awaited phone")
    }

    func testABonjourOnlyPhoneRecoversOverWiFiInWiFiAndAutoModes() async throws {
        for mode in [DeviceManager.ConnectionMode.wifi, .auto] {
            let (manager, _) = manager(mode: mode)
            manager.availableDevices = [phone]
            manager.networkAdvertisedDeviceIds = [deviceID]

            let candidate = try await manager.establishRecoverySession(previous: previous)

            XCTAssertEqual(candidate.transport, .wifi, "\(mode)")
            XCTAssertEqual(candidate.generation, 4)
            XCTAssertEqual(manager.selectedDevice?.id, deviceID)
        }
    }

    func testABonjourOnlyPhoneDoesNotRecoverInUSBOnlyMode() async {
        let (manager, _) = manager(mode: .usb)
        manager.availableDevices = [phone]
        manager.networkAdvertisedDeviceIds = [deviceID]

        do {
            _ = try await manager.establishRecoverySession(previous: previous)
            XCTFail("USB Only must not reconnect over Wi-Fi")
        } catch {}
    }

    func testARememberedPhoneMissingFromTheListRecoversWhenReachable() async throws {
        let (manager, _) = manager(mode: .auto)
        manager.selectedDevice = phone
        manager.selectedDevice = nil
        manager.availableDevices = []
        manager.wifiDirectDeviceIds = [deviceID]

        let candidate = try await manager.establishRecoverySession(previous: previous)

        XCTAssertEqual(candidate.stableDeviceID, deviceID)
        XCTAssertEqual(manager.selectedDevice?.id, deviceID)
        XCTAssertEqual(manager.selectedDevice?.displayName, "Owner iPhone")
        XCTAssertEqual(manager.selectedDevice?.deviceName, "Owner iPhone")
    }
}
