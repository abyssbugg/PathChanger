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
import Combine
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
    var isHelperRunning: Bool { true }
    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus {
        .notConnected("test")
    }
    func start() async throws {}
    func refreshAdoptedHelperSessions() async throws {}
    func shutdownHelper() async throws {}
    func clearLocationOverDeviceConnection(_ deviceId: String, transport: LocationTransport, sessionGeneration: UInt64?) async throws {}
    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool { true }
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
    var isHelperRunning: Bool { true }
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
    func clearLocationOverDeviceConnection(_ deviceId: String, transport: LocationTransport, sessionGeneration: UInt64?) async throws {}
    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool { true }
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

    // Review 2026-11-03 issue 11: an advert wake must not be logged as visibility.

    func testAnAdvertWakesAWaitWithItsOwnReason() async throws {
        let waiter = AutoReconnectWaiter()
        let sleeper = ControlledReconnectSleeper()
        let wait = Task { @MainActor in await waiter.wait(timeout: 60, sleeper: sleeper) }
        let deadline = Date().addingTimeInterval(2)
        while await sleeper.pendingCount() < 1, Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        waiter.signalRemotePairingAdvert()

        let wake = await wait.value
        XCTAssertEqual(wake, .remotePairingAdvert)
    }

    func testAPendingAdvertKeepsItsReasonAndVisibilityOutranksIt() async {
        let waiter = AutoReconnectWaiter()
        let sleeper = ControlledReconnectSleeper()

        waiter.signalRemotePairingAdvert()
        let advertOnly = await waiter.wait(timeout: 60, sleeper: sleeper)
        XCTAssertEqual(advertOnly, .remotePairingAdvert)

        waiter.signalRemotePairingAdvert()
        waiter.signalReachable()
        let advertThenVisible = await waiter.wait(timeout: 60, sleeper: sleeper)
        XCTAssertEqual(advertThenVisible, .reachable)

        waiter.signalReachable()
        waiter.signalRemotePairingAdvert()
        let visibleThenAdvert = await waiter.wait(timeout: 60, sleeper: sleeper)
        XCTAssertEqual(visibleThenAdvert, .reachable, "an advert never downgrades real visibility")
    }

    func testTheWakeLogTextSaysAnAdvertIsNotVisibility() {
        XCTAssertEqual(AutoReconnectWaiter.Wake.reachable.logText, "The phone is visible again")
        XCTAssertEqual(AutoReconnectWaiter.Wake.timeout.logText, "Fallback timer")
        let advert = AutoReconnectWaiter.Wake.remotePairingAdvert.logText
        XCTAssertTrue(advert.contains("RemotePairing advert"), advert)
        XCTAssertFalse(advert.contains("visible again"), advert)
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
        ddiRunner: (([String]) async throws -> String)? = nil,
        tunnelReconnect: FakeReconnectTunnel? = nil
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
            ),
            tunnelAutoReconnect: tunnelReconnect.map { fake in
                TunnelAutoReconnectEnvironment(isEnabled: true, tunnel: fake,
                                               sleeper: ControlledReconnectSleeper(), now: { clock.now })
            }
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

    // Review 2026-11-03 issue 7: Move lifted the location latch only; after Stop -> Move the
    // tunnel reconnector still read the tunnel's Stop latch and never reopened the tunnel.
    func testMoveLiftsTheTunnelStopLatchToo() async throws {
        let tunnel = FakeReconnectTunnel()
        tunnel.isStoppedByUser = true // Stop Tunnel earlier
        let fixture = makeFixture(tunnelReconnect: tunnel)
        try seedHeldLocation(fixture)

        fixture.state.activeMode = .teleport
        fixture.state.stageLocation(held, for: .teleport)
        let move = Task { await fixture.state.startSimulation() }
        try await waitUntil("the Move apply") { await fixture.injector.pendingApplicationCount() == 1 }
        XCTAssertEqual(tunnel.latchLifts, 1)
        XCTAssertFalse(tunnel.isStoppedByUser, "a later loss reconnects the tunnel too")
        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        await move.value
    }

    // Review 2026-11-03 issue 1: the pill and Settings could not stop the reconnect.
    func testStopWhileTheTunnelReconnectsStopsTheTunnelAndLatchesTheLocationReconnect() async throws {
        let tunnel = FakeReconnectTunnel()
        let fixture = makeFixture(tunnelReconnect: tunnel)
        try seedHeldLocation(fixture)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        fixture.state.device.wifiDirectDeviceIds = [] // the recovery burst fails fast
        fixture.state.device.onLocationSessionLoss?(.tunnelHealthLost)
        XCTAssertTrue(fixture.state.isTunnelAutoReconnecting)
        try await waitUntil("waiting for the phone") { fixture.state.isAwaitingAutomaticReconnect }

        fixture.state.stopTunnelReconnect()

        XCTAssertEqual(tunnel.stopCalls, 1)
        XCTAssertFalse(fixture.state.isTunnelAutoReconnecting)
        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect,
                       "the location reconnect would reopen the helper connection behind the Stop")
        fixture.state.device.wifiDirectDeviceIds = [deviceID]
        await settle()
        let applies = await applyCount(fixture.injector)
        XCTAssertEqual(applies, 0)
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    // Review 2026-11-03 issue 9: the reconnector reopened the remembered phone after the
    // user had selected another one.
    func testSelectingAnotherPhoneWhileReconnectingStopsTheTunnelReconnect() async throws {
        let tunnel = FakeReconnectTunnel()
        tunnel.reconnectDeviceId = deviceID
        let fixture = makeFixture(tunnelReconnect: tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        XCTAssertTrue(fixture.state.isTunnelAutoReconnecting)

        // The same phone (discovery re-selecting it) leaves the reconnect alone.
        fixture.state.selectDevice(phone)
        XCTAssertEqual(tunnel.stopCalls, 0)

        let other = Device(id: "00008120-001B000E3E82002F", displayName: "Second iPhone", connectionType: .usb,
                           productType: "iPhone16,2", productVersion: "18.0", deviceName: "Second iPhone")
        fixture.state.device.availableDevices = [phone, other]
        fixture.state.selectDevice(other)

        XCTAssertEqual(tunnel.stopCalls, 1)
        XCTAssertFalse(fixture.state.isTunnelAutoReconnecting)
        let message = try XCTUnwrap(fixture.state.statusMessage)
        XCTAssertTrue(message.contains("Stopped reconnecting"), message)
        XCTAssertTrue(message.contains("Second iPhone"), message)
    }

    // Review 2026-11-03 issue 6: an automatic tunnel attempt that replaced a stalled helper
    // connection reported a new loss in the middle of the recovery burst's reapply, which
    // dropped the burst's pending request and failed a reapply the phone had applied.
    func testAConnectionReplacedDuringARecoveryBurstDoesNotFailTheBurst() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        fixture.state.locationSessionCoordinator.connectionLost(reason: "Tunnel health lost")
        fixture.state.startLocationRecovery(strategy: oneAttempt) { [deviceID] _, previous in
            LocationSessionIdentity(stableDeviceID: deviceID, transport: .wifi, endpointClass: .direct,
                                    generation: (previous?.generation ?? 1) + 1)
        }
        try await waitUntil("the burst's reapply") { await fixture.injector.pendingApplicationCount() == 1 }

        fixture.state.helperConnectionReplaced(deviceId: deviceID)

        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        try await waitUntil("the burst applied") {
            fixture.state.locationSessionCoordinator.state.application.isActive
        }
    }

    func testAConnectionReplacedOutsideABurstIsStillALoss() throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        XCTAssertTrue(fixture.state.locationSessionCoordinator.state.application.isActive)
        fixture.state.device.wifiDirectDeviceIds = [] // the recovery burst fails fast

        fixture.state.helperConnectionReplaced(deviceId: deviceID)

        XCTAssertFalse(fixture.state.locationSessionCoordinator.state.application.isActive)
    }

    // Review 2026-11-03 issue 4: a helper mount can hold Move for minutes and further
    // clicks were dropped with only a log line.
    func testMoveSaysItIsPreparingTheIPhoneAndAFurtherClickSaysItIsStillPreparing() async throws {
        let gate = ReconnectTestGate()
        let fixture = makeFixture(ddiRunner: { _ in
            await gate.wait()
            return #"[{"DiskImageType": "Personalized"}]"#
        })
        try seedHeldLocation(fixture)
        fixture.state.activeMode = .teleport
        fixture.state.stageLocation(held, for: .teleport)

        let move = Task { await fixture.state.startSimulation() }
        try await waitUntil("the preparing status") {
            fixture.state.statusMessage == AppState.preparingDeviceForLocationText
        }
        await fixture.state.startSimulation()
        XCTAssertEqual(fixture.state.statusMessage, AppState.stillPreparingDeviceForLocationText)

        await gate.open()
        try await waitUntil("the Move apply") { await fixture.injector.pendingApplicationCount() == 1 }
        XCTAssertNotEqual(fixture.state.statusMessage, AppState.stillPreparingDeviceForLocationText)
        XCTAssertNotEqual(fixture.state.statusMessage, AppState.preparingDeviceForLocationText)
        await fixture.injector.releaseNextApplication(session: try await readyIdentity(fixture.state))
        await move.value
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

// MARK: - Tunnel auto-reconnect (live 2026-11-03)

// Monitor 2026-11-03, Wi-Fi, cable unplugged: a health failure left the tunnel in Error
// and nothing reopened it until the owner pressed Start, minutes after the phone was back
// (Bonjour 01:11:35, usbmux 01:11:43, Start 01:13:04). Reconnect on a live tunnel stopped
// it ("running -> stopping -> idle") and the owner needed 2-3 clicks.

/// A tunnel lifecycle the tests drive by hand.
@MainActor
final class FakeReconnectTunnel: TunnelReconnectControlling {
    @Published var state: TunnelState = .idle
    var preferredMode: TunnelMode = .wifi {
        didSet { controlChanges.send() }
    }
    var isStoppedByUser = false
    var reconnectDeviceId: String? = "00008130-0011223344556677"
    var lastError: String?
    /// What an automatic start ends in.
    var automaticStartResult: TunnelState = .error("not visible")
    /// The error an automatic start that fails leaves behind.
    var automaticStartError: String?
    var reconnectGate: ReconnectTestGate?
    private(set) var automaticStarts: [String] = []
    private(set) var reconnectCalls: [String?] = []
    private(set) var stopCalls = 0
    private(set) var latchLifts = 0
    private let controlChanges = PassthroughSubject<Void, Never>()

    var lifecycleState: TunnelState { state }
    var lifecycleStatePublisher: AnyPublisher<TunnelState, Never> { $state.eraseToAnyPublisher() }
    var reconnectControlChanges: AnyPublisher<Void, Never> { controlChanges.eraseToAnyPublisher() }

    func startTunnelAutomatically(deviceId: String) async {
        automaticStarts.append(deviceId)
        lastError = nil
        state = .starting
        await Task.yield()
        if case .error = automaticStartResult { lastError = automaticStartError }
        state = automaticStartResult
    }

    func reconnectTunnel(deviceId: String?) async {
        reconnectCalls.append(deviceId)
        await reconnectGate?.wait()
    }

    /// Like `TunneldManager.stopTunnel()`: latches, and from idle the state machine
    /// ignores the Stop (no transition).
    func stopTunnel() {
        stopCalls += 1
        isStoppedByUser = true
        if state != .idle {
            state = .stopping
            state = .idle
        }
        controlChanges.send()
    }

    func liftStopLatch() {
        latchLifts += 1
        isStoppedByUser = false
        controlChanges.send()
    }
}

@MainActor
final class TunnelAutoReconnectPolicyTests: XCTestCase {
    private let id = "00008130-0011223344556677"

    private func inputs(
        enabled: Bool = true, mode: TunnelMode = .wifi, stopped: Bool = false,
        tunnel: TunnelState = .error("Health check failed"), device: String?? = .none,
        becameVisible: Bool = false, since: TimeInterval = 0, failures: Int = 0
    ) -> TunnelAutoReconnectPolicy.Inputs {
        TunnelAutoReconnectPolicy.Inputs(
            isEnabled: enabled,
            mode: mode,
            isStoppedByUser: stopped,
            tunnel: tunnel,
            deviceID: device ?? id,
            phoneBecameVisible: becameVisible,
            secondsSinceLastTry: since,
            failedAttempts: failures
        )
    }

    func testEveryRefusalHasItsReason() {
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(enabled: false)), .stop(.disabled))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(mode: .daemon)), .stop(.daemonMode))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(stopped: true)), .stop(.stoppedByUser))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(tunnel: .running)), .stop(.connected))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(device: .some(nil))), .stop(.noDevice))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(device: "192.168.0.177")), .stop(.noDevice),
                       "an endpoint alias is not a UDID the helper can open")
    }

    func testAStartOrStopInFlightIsNeverOverlapped() {
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(tunnel: .starting, becameVisible: true, since: 60)), .busy)
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(tunnel: .stopping, since: 60)), .busy)
    }

    func testEveryHelperModeReconnectsFromErrorOrIdle() {
        for mode in [TunnelMode.auto, .usb, .wifi] {
            XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(mode: mode, since: 5)), .attempt(deviceID: id))
            XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(mode: mode, tunnel: .idle, since: 5)),
                           .attempt(deviceID: id))
        }
    }

    func testPeriodicAttemptsBackOffFromFiveToThirtySeconds() {
        XCTAssertEqual((0...6).map(TunnelAutoReconnectPolicy.retryDelay(afterFailedAttempts:)), [5, 10, 20, 30, 30, 30, 30])
        XCTAssertEqual(TunnelAutoReconnectPolicy.retryDelay(afterFailedAttempts: 10_000), 30)
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(since: 0)), .wait(seconds: 5))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(since: 5)), .attempt(deviceID: id))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(since: 19, failures: 2)), .wait(seconds: 1))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(since: 29, failures: 9)), .wait(seconds: 1))
    }

    func testThePhoneComingBackTriesAtOnceButNotInATightLoop() {
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(becameVisible: true, since: 2, failures: 5)),
                       .attempt(deviceID: id))
        XCTAssertEqual(TunnelAutoReconnectPolicy.evaluate(inputs(becameVisible: true, since: 0.5)), .wait(seconds: 1.5))
    }
}

@MainActor
final class TunnelAutoReconnectorTests: XCTestCase {
    private let udid = "00008130-0011223344556677"

    private func makeReconnector(
        _ tunnel: FakeReconnectTunnel,
        enabled: Bool = true
    ) -> (TunnelAutoReconnector, ControlledReconnectSleeper, ReconnectTestClock) {
        let sleeper = ControlledReconnectSleeper()
        let clock = ReconnectTestClock()
        let reconnector = TunnelAutoReconnector(environment: TunnelAutoReconnectEnvironment(
            isEnabled: enabled, tunnel: tunnel, sleeper: sleeper, now: { clock.now }
        ))
        addTeardownBlock { @MainActor in reconnector.cancel() }
        return (reconnector, sleeper, clock)
    }

    private func waitUntil(
        _ what: String, timeout: TimeInterval = 5, _ condition: @MainActor () async -> Bool
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

    private func settle() async {
        for _ in 0..<20 { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    func testAHealthFailureReconnectsAsSoonAsThePhoneIsVisibleAgain() async throws {
        let tunnel = FakeReconnectTunnel()
        tunnel.automaticStartResult = .running
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        reconnector.noteVisibleDevices([])

        tunnel.state = .error("Health check failed")
        XCTAssertTrue(reconnector.isReconnecting, "the pill reads Reconnecting, not Error")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)

        clock.now += 3
        reconnector.noteVisibleDevices([udid])

        try await waitUntil("the reconnect") { tunnel.automaticStarts == [self.udid] }
        try await waitUntil("reconnected") { !reconnector.isReconnecting }
        XCTAssertEqual(tunnel.state, .running)
        await settle()
        XCTAssertEqual(tunnel.automaticStarts.count, 1)
    }

    func testAnAbsentPhoneIsRetriedWithBackoffNotInALoop() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")

        let expected: [TimeInterval] = [5, 10, 20, 30, 30]
        for (index, delay) in expected.enumerated() {
            try await waitUntil("wait \(index + 1)") { await sleeper.recordedRequests().count == index + 1 }
            XCTAssertEqual(tunnel.automaticStarts.count, index, "no attempt before the delay")
            clock.now += delay
            await sleeper.releaseOldest()
            if index < expected.count - 1 {
                try await waitUntil("attempt \(index + 1)") { tunnel.automaticStarts.count == index + 1 }
            }
        }
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(Array(requests.prefix(expected.count)), expected)
        XCTAssertTrue(reconnector.isReconnecting)
        XCTAssertEqual(Set(tunnel.automaticStarts), [udid], "the remembered UDID, whatever is selected")
    }

    func testStopTunnelEndsTheReconnect() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        tunnel.isStoppedByUser = true
        tunnel.state = .stopping
        tunnel.state = .idle

        try await waitUntil("stopped") { !reconnector.isReconnecting }
        clock.now += 60
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    func testAUserStopOfALiveTunnelNeverReconnects() async {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, _) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.isStoppedByUser = true
        tunnel.state = .stopping
        tunnel.state = .idle
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertFalse(reconnector.isReconnecting)
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    func testDaemonModeNeverReconnectsTheTunnel() async {
        let tunnel = FakeReconnectTunnel()
        tunnel.preferredMode = .daemon
        let (reconnector, sleeper, _) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Tunnel process exited")
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertFalse(reconnector.isReconnecting)
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    func testDisabledUnderTestHostsAndPreviews() async {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, _, _) = makeReconnector(tunnel, enabled: false)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertFalse(reconnector.isReconnecting)
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    func testAStartAlreadyInFlightIsNotOverlapped() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        tunnel.state = .starting // the user pressed Start
        clock.now += 60
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty, "never a second Start beside the user's")
        XCTAssertTrue(reconnector.isReconnecting)

        tunnel.state = .error("not visible") // the user's Start failed: keep trying
        try await waitUntil("the next attempt") { tunnel.automaticStarts == [self.udid] }
    }

    func testAdoptingTheHelperConnectionEndsTheWait() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, _) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        tunnel.state = .idle
        tunnel.state = .starting
        tunnel.state = .running // the 5 s poll adopted the helper's connection

        XCTAssertFalse(reconnector.isReconnecting)
        try await waitUntil("the wait cancelled") { await sleeper.pendingCount() == 0 }
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    // Review 2026-11-03 issue 8: a switch to Background Daemon or a Stop the state machine
    // ignores did not wake the loop, so "Reconnecting…" stayed up for the rest of the wait.

    func testSwitchingToDaemonModeEndsReconnectingAtOnce() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        tunnel.preferredMode = .daemon

        XCTAssertFalse(reconnector.isReconnecting, "the label clears at once, not after the 5-30 s wait")
        try await waitUntil("the wait cancelled") { await sleeper.pendingCount() == 0 }
        clock.now += 60
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    func testAStopTheStateMachineIgnoresStillEndsReconnectingAtOnce() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        tunnel.state = .idle // a failed attempt can also end idle
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }
        XCTAssertTrue(reconnector.isReconnecting)

        tunnel.stopTunnel() // (.idle, .stopRequested) is ignored: no transition

        XCTAssertFalse(reconnector.isReconnecting)
        clock.now += 60
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
    }

    // Review 2026-11-03 issue 11: Quit's cancel() left the subscription armed; a health
    // failure during teardown re-armed it and relaunched the helper Quit had stopped.

    func testCancelShutsTheReconnectorDownForGood() async {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, _) = makeReconnector(tunnel)
        tunnel.state = .running

        reconnector.cancel() // Quit

        tunnel.state = .error("Health check failed")
        reconnector.noteVisibleDevices([udid])
        await settle()
        XCTAssertFalse(reconnector.isReconnecting)
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(requests, [])
    }

    // Review 2026-11-03 issue 2: the reconnector keeps the last attempt's error for the notice.

    func testTheLastAttemptsErrorIsKeptUntilTheReconnectEnds() async throws {
        let tunnel = FakeReconnectTunnel()
        tunnel.automaticStartError = "ConnectionTerminatedError: refused"
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
        XCTAssertNil(reconnector.lastAttemptError, "no attempt yet: the loss is not an attempt's error")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        clock.now += 5
        await sleeper.releaseOldest()
        try await waitUntil("the first attempt") { tunnel.automaticStarts.count == 1 }
        try await waitUntil("its error kept") { reconnector.lastAttemptError == "ConnectionTerminatedError: refused" }

        tunnel.automaticStartResult = .running
        tunnel.automaticStartError = nil
        clock.now += 3
        reconnector.noteVisibleDevices([udid])
        try await waitUntil("reconnected") { !reconnector.isReconnecting }
        XCTAssertNil(reconnector.lastAttemptError)
    }
}

/// Reconnect never stops a live tunnel and a second click while one runs does nothing.
@MainActor
final class ReconnectNowTunnelTests: XCTestCase {
    private let deviceID = "00008130-0011223344556677"

    func testReconnectHandsTheTunnelToReconnectOnceAndSaysReconnecting() async throws {
        let tunnel = FakeReconnectTunnel()
        let gate = ReconnectTestGate()
        tunnel.reconnectGate = gate
        let deviceManager = QuietReconnectDeviceManager(startBackgroundServices: false)
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: FakeLocationInjector(),
            managedLocationSessionSource: EmptyManagedSessionSource(),
            deviceManager: deviceManager,
            tunnelQuitController: RecordingTunnelQuitController(),
            tunnelAutoReconnect: TunnelAutoReconnectEnvironment(
                isEnabled: true, tunnel: tunnel, sleeper: ControlledReconnectSleeper(),
                now: { Date(timeIntervalSinceReferenceDate: 0) }
            )
        )
        let phone = Device(id: deviceID, displayName: "Owner iPhone", connectionType: .wifi,
                           productType: "iPhone17,1", productVersion: "27.2", deviceName: "Owner iPhone")
        state.device.availableDevices = [phone]
        state.device.selectedDevice = phone
        XCTAssertFalse(state.isReconnecting)

        let first = Task { await state.reconnectNow() }
        var deadline = Date().addingTimeInterval(5)
        while tunnel.reconnectCalls.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(tunnel.reconnectCalls, [deviceID], "Reconnect goes through the no-stop path")
        XCTAssertTrue(state.isReconnecting, "the button reads Reconnecting… and is disabled")

        let second = Task { await state.reconnectNow() }
        deadline = Date().addingTimeInterval(0.05)
        while Date() < deadline { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(tunnel.reconnectCalls.count, 1, "an extra click does nothing")

        await gate.open()
        await first.value
        await second.value
        XCTAssertFalse(state.isReconnecting)
        XCTAssertEqual(tunnel.reconnectCalls.count, 1)
    }
}
