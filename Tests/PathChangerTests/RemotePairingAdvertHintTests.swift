//
//  RemotePairingAdvertHintTests.swift
//  PathChangerTests
//
//  Live 2026-11-03: after the phone came back on Wi-Fi its `_remotepairing._tcp` advert
//  reappeared (03:58:14), but the tunnel reconnect only tried on its retry timer
//  (03:58:18): usbmuxd listed nothing and the mobdev2 advert did not change, so the
//  "phone became visible" signal never fired. A RemotePairing advert appearing is now a
//  hint ("the phone may be back") for both reconnects while one is armed. The advert's
//  name is opaque (no UDID without the altIRK), so it never counts as visibility.
//
//  No device, no network, no privilege: the browser, tunnel, sleeper and clock are fakes.
//

import XCTest
import Combine
@testable import PathChanger

// MARK: - Test doubles

/// Delivers adverts only while browsing, like the real browser; `deliverLateAdvert()`
/// replays a callback that was already queued when the browser stopped.
@MainActor
final class FakeRemotePairingAdvertBrowser: RemotePairingAdvertBrowsing {
    private(set) var isBrowsing = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onAdvert: (@MainActor () -> Void)?
    private var onFailure: (@MainActor () -> Void)?
    private var lastHandler: (@MainActor () -> Void)?

    func start(onAdvert: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor () -> Void) {
        isBrowsing = true
        startCount += 1
        self.onAdvert = onAdvert
        self.onFailure = onFailure
        lastHandler = onAdvert
    }

    func stop() {
        isBrowsing = false
        stopCount += 1
        onAdvert = nil
        onFailure = nil
    }

    func advertAppeared() {
        onAdvert?()
    }

    func deliverLateAdvert() {
        lastHandler?()
    }

    /// Like `NWBrowser` reaching `.failed`: the browse ends on its own and says so once.
    func fail() {
        let failure = onFailure
        isBrowsing = false
        onAdvert = nil
        onFailure = nil
        failure?()
    }
}

private final class QuietAdvertTestDeviceManager: DeviceManager {
    private(set) var refreshCount = 0
    override func refreshDevices() async { refreshCount += 1 }
}

private final class AdvertTestManagedSessionSource: ManagedLocationSessionSource {
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

private final class AdvertTestQuitController: TunnelQuitControlling {
    func stopTunnelForQuit() async -> TunnelQuitStopResult { .stopped }
    func retainTunnelForPreservedLocation() {}
    func pendingHelperStop(for deviceId: String) -> Task<Bool, Never>? { nil }
    func resumeLocationCommands(for deviceId: String) {}
}

private struct AdvertWaitTimeout: Error {}

@MainActor
private func waitUntil(
    _ what: String,
    timeout: TimeInterval = 5,
    _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await condition()) {
        if Date() > deadline {
            XCTFail("Timed out waiting for: \(what)")
            throw AdvertWaitTimeout()
        }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// Lets queued main-actor work run before asserting that nothing happened.
@MainActor
private func settle() async {
    for _ in 0..<20 { try? await Task.sleep(nanoseconds: 2_000_000) }
}

// MARK: - Which browse results are news

@MainActor
final class RemotePairingAdvertTrackerTests: XCTestCase {
    func testTheAdvertsAlreadyThereWhenBrowsingStartsAreNotNews() {
        var tracker = RemotePairingAdvertTracker()
        XCTAssertFalse(tracker.update(present: ["a", "b"], changed: ["a"]), "the first results are the baseline")
        XCTAssertFalse(tracker.update(present: ["a", "b"], changed: []))
    }

    func testANewAdvertIsNewsAndARemovalIsNot() {
        var tracker = RemotePairingAdvertTracker()
        _ = tracker.update(present: ["a"], changed: [])
        XCTAssertTrue(tracker.update(present: ["a", "b"], changed: []))
        XCTAssertFalse(tracker.update(present: ["b"], changed: []), "an advert leaving is not the phone coming back")
        XCTAssertTrue(tracker.update(present: ["a", "b"], changed: []), "an advert that left and reappeared is news")
    }

    func testAnAdvertThatChangedIsNews() {
        var tracker = RemotePairingAdvertTracker()
        _ = tracker.update(present: ["a"], changed: [])
        XCTAssertTrue(tracker.update(present: ["a"], changed: ["a"]))
    }

    func testAnEmptyFirstResultIsStillTheBaseline() {
        var tracker = RemotePairingAdvertTracker()
        XCTAssertFalse(tracker.update(present: [], changed: []))
        XCTAssertTrue(tracker.update(present: ["a"], changed: []), "the phone's advert appearing after the start is news")
    }
}

// MARK: - How often an advert alone may wake a reconnect

final class RemotePairingAdvertHintLimiterTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 7_000_000)

    func testTheFirstAdvertWakesAndLaterOnesInsideTheWindowDoNot() {
        var limiter = RemotePairingAdvertHintLimiter()
        let window = RemotePairingAdvertHintLimiter.window
        XCTAssertTrue(limiter.admit(at: start))
        XCTAssertFalse(limiter.admit(at: start.addingTimeInterval(1)))
        XCTAssertFalse(limiter.admit(at: start.addingTimeInterval(window - 0.1)))
        XCTAssertTrue(limiter.admit(at: start.addingTimeInterval(window)))
        XCTAssertFalse(limiter.admit(at: start.addingTimeInterval(window + 1)), "the window restarts at each wake")
    }

    func testAResetLetsTheNextAdvertWakeAtOnce() {
        var limiter = RemotePairingAdvertHintLimiter()
        XCTAssertTrue(limiter.admit(at: start))
        limiter.reset()
        XCTAssertTrue(limiter.admit(at: start.addingTimeInterval(1)))
    }

    func testAClockThatWentBackDoesNotOpenTheWindow() {
        var limiter = RemotePairingAdvertHintLimiter()
        XCTAssertTrue(limiter.admit(at: start))
        XCTAssertFalse(limiter.admit(at: start.addingTimeInterval(-60)))
    }
}

// MARK: - The tunnel reconnect takes the hint

@MainActor
final class TunnelReconnectAdvertHintTests: XCTestCase {
    private let udid = "00008130-0011223344556677"

    private func makeReconnector(
        _ tunnel: FakeReconnectTunnel
    ) -> (TunnelAutoReconnector, ControlledReconnectSleeper, ReconnectTestClock) {
        let sleeper = ControlledReconnectSleeper()
        let clock = ReconnectTestClock()
        let reconnector = TunnelAutoReconnector(environment: TunnelAutoReconnectEnvironment(
            isEnabled: true, tunnel: tunnel, sleeper: sleeper, now: { clock.now }
        ))
        addTeardownBlock { @MainActor in reconnector.cancel() }
        return (reconnector, sleeper, clock)
    }

    private func loseTunnel(_ tunnel: FakeReconnectTunnel) {
        tunnel.state = .running
        tunnel.state = .error("Health check failed")
    }

    func testAnAdvertDuringTheWaitAttemptsAtOnceOnceTheSpacingHasPassed() async throws {
        let tunnel = FakeReconnectTunnel()
        tunnel.automaticStartResult = .running
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        loseTunnel(tunnel)
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        clock.now += 3 // past the 2 s spacing, before the 5 s retry
        reconnector.noteRemotePairingAdvert()

        try await waitUntil("the attempt") { tunnel.automaticStarts == [self.udid] }
        try await waitUntil("reconnected") { !reconnector.isReconnecting }
    }

    func testAnAdvertTooSoonAfterTheLastTryWaitsOutTheSpacing() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        loseTunnel(tunnel)
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        clock.now += 0.5
        reconnector.noteRemotePairingAdvert()

        try await waitUntil("the spacing wait") { await sleeper.recordedRequests() == [5, 1.5] }
        XCTAssertTrue(tunnel.automaticStarts.isEmpty, "never sooner than the spacing")
        clock.now += 1.5
        await sleeper.releaseOldest()
        try await waitUntil("the attempt") { tunnel.automaticStarts == [self.udid] }
    }

    func testRepeatedAdvertsWithinTheSpacingMakeOneAttempt() async throws {
        let tunnel = FakeReconnectTunnel() // every attempt fails: the phone is not reachable yet
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        loseTunnel(tunnel)
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        clock.now += 3
        for _ in 0..<5 { reconnector.noteRemotePairingAdvert() }
        try await waitUntil("the attempt") { tunnel.automaticStarts.count == 1 }
        for _ in 0..<5 { reconnector.noteRemotePairingAdvert() } // a flickering advert
        await settle()

        XCTAssertEqual(tunnel.automaticStarts.count, 1, "one attempt per spacing, however many adverts")
        XCTAssertTrue(reconnector.isReconnecting)
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(requests.last, TunnelAutoReconnectPolicy.retryDelay(afterFailedAttempts: 1),
                       "adverts inside the window keep the normal backoff")
    }

    /// Review 2026-11-03 issue 9: the browser is unfiltered, so other Apple devices joining
    /// and leaving the LAN must not keep bypassing the retry backoff.
    func testSustainedAdvertChurnMakesABoundedNumberOfAttempts() async throws {
        let tunnel = FakeReconnectTunnel() // every attempt fails
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        loseTunnel(tunnel)
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        // A few adverts every 10 s for five minutes. The retry timers are never released,
        // so every attempt here came from an advert.
        let duration: TimeInterval = 300
        for _ in 0..<Int(duration / 10) {
            clock.now += 10
            for _ in 0..<3 { reconnector.noteRemotePairingAdvert() }
            await settle()
        }

        let bound = Int(duration / RemotePairingAdvertHintLimiter.window) + 1
        XCTAssertLessThanOrEqual(tunnel.automaticStarts.count, bound, "at most one advert wake per window")
        XCTAssertGreaterThanOrEqual(tunnel.automaticStarts.count, 2, "an advert after the window still wakes it")
        XCTAssertTrue(reconnector.isReconnecting)
    }

    func testThePhoneBecomingVisibleStillWakesInsideTheAdvertWindow() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, clock) = makeReconnector(tunnel)
        loseTunnel(tunnel)
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }

        clock.now += 3
        reconnector.noteRemotePairingAdvert()
        try await waitUntil("the advert attempt") { tunnel.automaticStarts.count == 1 }
        try await waitUntil("the retry wait") { await sleeper.recordedRequests().count == 2 }

        clock.now += 3
        reconnector.noteRemotePairingAdvert()
        await settle()
        XCTAssertEqual(tunnel.automaticStarts.count, 1, "a second advert inside the window wakes nothing")

        reconnector.noteVisibleDevices([udid])
        try await waitUntil("the visibility attempt") { tunnel.automaticStarts.count == 2 }
    }

    func testAnAdvertWhileNothingReconnectsIsNotKept() async throws {
        let tunnel = FakeReconnectTunnel()
        let (reconnector, sleeper, _) = makeReconnector(tunnel)
        tunnel.state = .running
        reconnector.noteRemotePairingAdvert()
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty)

        tunnel.state = .error("Health check failed")
        try await waitUntil("the periodic wait") { await sleeper.pendingCount() == 1 }
        await settle()
        XCTAssertTrue(tunnel.automaticStarts.isEmpty, "an advert seen before the loss is not news after it")
        let requests = await sleeper.recordedRequests()
        XCTAssertEqual(requests, [5])
    }
}

// MARK: - AppState runs the browser only while a reconnect is armed

@MainActor
final class RemotePairingAdvertBrowserLifecycleTests: XCTestCase {
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
        let browser: FakeRemotePairingAdvertBrowser
        let tunnel: FakeReconnectTunnel
        let tunnelSleeper: ControlledReconnectSleeper
        let locationSleeper: ControlledReconnectSleeper
        let browseRestartSleeper: ControlledReconnectSleeper
        let clock: ReconnectTestClock
        let deviceManager: QuietAdvertTestDeviceManager
        let injector: FakeLocationInjector
    }

    private func makeFixture(daemonMode: Bool = false) -> Fixture {
        let injector = FakeLocationInjector()
        let deviceManager = QuietAdvertTestDeviceManager(startBackgroundServices: false)
        deviceManager.connectionMode = .auto
        let browser = FakeRemotePairingAdvertBrowser()
        let tunnel = FakeReconnectTunnel()
        if daemonMode { tunnel.preferredMode = .daemon }
        let tunnelSleeper = ControlledReconnectSleeper()
        let locationSleeper = ControlledReconnectSleeper()
        let browseRestartSleeper = ControlledReconnectSleeper()
        let clock = ReconnectTestClock()
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            managedLocationSessionSource: AdvertTestManagedSessionSource(),
            deviceManager: deviceManager,
            tunnelQuitController: AdvertTestQuitController(),
            automaticReconnect: AutomaticReconnectEnvironment(
                isEnabled: true,
                usesHelperConnection: { !daemonMode },
                sleeper: locationSleeper,
                now: { clock.now },
                burstStrategy: oneAttempt
            ),
            tunnelAutoReconnect: TunnelAutoReconnectEnvironment(
                isEnabled: true, tunnel: tunnel, sleeper: tunnelSleeper, now: { clock.now }
            ),
            remotePairingAdvertBrowser: browser,
            remotePairingBrowseRestartSleeper: browseRestartSleeper
        )
        state.device.availableDevices = [phone]
        state.device.wifiDirectDeviceIds = [deviceID]
        state.device.selectedDevice = phone
        addTeardownBlock { @MainActor in
            state.tunnelAutoReconnector.cancel()
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
        return Fixture(state: state, browser: browser, tunnel: tunnel, tunnelSleeper: tunnelSleeper,
                       locationSleeper: locationSleeper, browseRestartSleeper: browseRestartSleeper,
                       clock: clock, deviceManager: deviceManager,
                       injector: injector)
    }

    private func loseTunnel(_ fixture: Fixture) {
        fixture.tunnel.state = .running
        fixture.tunnel.state = .error("Health check failed")
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

    func testTheBrowserRunsOnlyWhileTheTunnelReconnectIsArmed() async throws {
        let fixture = makeFixture()
        fixture.tunnel.state = .running
        await settle()
        XCTAssertFalse(fixture.browser.isBrowsing, "no LAN browsing while nothing is armed")
        XCTAssertEqual(fixture.browser.startCount, 0)

        fixture.tunnel.state = .error("Health check failed")
        try await waitUntil("browsing while reconnecting") { fixture.browser.isBrowsing }

        fixture.tunnel.state = .running // adopted or reconnected
        try await waitUntil("stopped once live") { !fixture.browser.isBrowsing }
        XCTAssertEqual(fixture.browser.startCount, 1)
    }

    func testAnAdvertWakesTheTunnelReconnect() async throws {
        let fixture = makeFixture()
        fixture.tunnel.automaticStartResult = .running
        loseTunnel(fixture)
        try await waitUntil("the periodic wait") { await fixture.tunnelSleeper.pendingCount() == 1 }
        try await waitUntil("browsing") { fixture.browser.isBrowsing }

        fixture.clock.now += 3
        fixture.browser.advertAppeared()

        try await waitUntil("the attempt") { fixture.tunnel.automaticStarts == [self.deviceID] }
        try await waitUntil("browsing ends once live") { !fixture.browser.isBrowsing }
    }

    func testStopTunnelStopsTheBrowserAndALateAdvertDoesNothing() async throws {
        let fixture = makeFixture()
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }

        fixture.state.stopTunnelReconnect()

        try await waitUntil("stopped") { !fixture.browser.isBrowsing }
        fixture.clock.now += 60
        fixture.browser.deliverLateAdvert()
        await settle()
        XCTAssertTrue(fixture.tunnel.automaticStarts.isEmpty)
        XCTAssertFalse(fixture.browser.isBrowsing)
    }

    func testQuitStopsTheBrowserForGood() async throws {
        let fixture = makeFixture()
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }

        _ = await fixture.state.prepareForQuitWithoutLocation()

        XCTAssertFalse(fixture.browser.isBrowsing)
        try seedHeldLocation(fixture)
        losePhone(fixture) // a loss during teardown must not browse again
        fixture.tunnel.state = .running
        fixture.tunnel.state = .error("Health check failed")
        fixture.browser.deliverLateAdvert()
        await settle()
        XCTAssertFalse(fixture.browser.isBrowsing)
        XCTAssertEqual(fixture.browser.startCount, 1)
        XCTAssertTrue(fixture.tunnel.automaticStarts.isEmpty)
    }

    func testDaemonModeNeverBrowsesAndAnAdvertChangesNothing() async throws {
        let fixture = makeFixture(daemonMode: true)
        try seedHeldLocation(fixture)
        losePhone(fixture)
        loseTunnel(fixture)
        await settle()

        XCTAssertFalse(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertFalse(fixture.state.isTunnelAutoReconnecting)
        XCTAssertEqual(fixture.browser.startCount, 0)
        fixture.state.tunnelAutoReconnector.noteRemotePairingAdvert()
        await settle()
        XCTAssertTrue(fixture.tunnel.automaticStarts.isEmpty)
        XCTAssertEqual(fixture.deviceManager.refreshCount, 0, "no burst")
    }

    func testAnAdvertWakesTheLocationWaitButIsNotVisibility() async throws {
        let fixture = makeFixture()
        try seedHeldLocation(fixture)
        losePhone(fixture)
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        try await waitUntil("the fallback timer") { await fixture.locationSleeper.pendingCount() == 1 }
        try await waitUntil("browsing while the location waits") { fixture.browser.isBrowsing }
        let reachabilityBefore = fixture.state.device.reachability(of: phone, tunnelRunning: false)
        XCTAssertEqual(reachabilityBefore, .notReachable)

        fixture.browser.advertAppeared()

        // One burst runs before the 60 s fallback. No live source lists the phone, so it
        // finds no verified transport and the wait goes on: the hint opened no path itself.
        try await waitUntil("the next wait after the burst") {
            await fixture.locationSleeper.recordedRequests().count == 2
        }
        XCTAssertEqual(fixture.deviceManager.refreshCount, 1, "exactly one burst")
        XCTAssertTrue(fixture.state.isAwaitingAutomaticReconnect)
        XCTAssertEqual(fixture.state.device.reachability(of: phone, tunnelRunning: false), .notReachable,
                       "the device chip never reads an opaque advert as the phone")
        XCTAssertTrue(fixture.state.device.networkAdvertisedDeviceIds.isEmpty)
        XCTAssertTrue(fixture.state.device.wifiDirectDeviceIds.isEmpty)
        XCTAssertFalse(fixture.state.locationSessionCoordinator.state.application.isActive)

        // More adverts inside the window wake nothing (review 2026-11-03 issue 9): the
        // wait keeps its fallback timer.
        for _ in 0..<3 { fixture.browser.advertAppeared() }
        await settle()
        let requestsInWindow = await fixture.locationSleeper.recordedRequests()
        XCTAssertEqual(requestsInWindow, [60, 60])
        XCTAssertEqual(fixture.deviceManager.refreshCount, 1, "no second burst inside the window")

        // After the window an advert wakes it again; the 20 s spacing has passed too.
        fixture.clock.now += RemotePairingAdvertHintLimiter.window
        fixture.browser.advertAppeared()
        try await waitUntil("the wait after the second burst") {
            await fixture.locationSleeper.recordedRequests().count == 3
        }
        XCTAssertEqual(fixture.deviceManager.refreshCount, 2)
        let requests = await fixture.locationSleeper.recordedRequests()
        XCTAssertEqual(requests, [60, 60, 120])
    }
    // MARK: A failed browse (review 2026-11-03 issue 10)

    func testAFailedBrowseStartsAgainAfterADelayWhileArmed() async throws {
        let fixture = makeFixture()
        fixture.tunnel.automaticStartResult = .running
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }
        try await waitUntil("the periodic wait") { await fixture.tunnelSleeper.pendingCount() == 1 }

        fixture.browser.fail()
        try await waitUntil("the restart delay") { await fixture.browseRestartSleeper.pendingCount() == 1 }
        let requests = await fixture.browseRestartSleeper.recordedRequests()
        XCTAssertEqual(requests, [RemotePairingBrowseRestart.delay], "never a tight loop")
        XCTAssertFalse(fixture.browser.isBrowsing)
        XCTAssertEqual(fixture.browser.startCount, 1, "not before the delay")

        await fixture.browseRestartSleeper.releaseOldest()
        try await waitUntil("browsing again") { fixture.browser.isBrowsing }
        XCTAssertEqual(fixture.browser.startCount, 2)

        // The restarted browse is live: its advert reaches the tunnel reconnect.
        fixture.clock.now += 3
        fixture.browser.advertAppeared()
        try await waitUntil("the attempt") { fixture.tunnel.automaticStarts == [self.deviceID] }
    }

    func testBrowseRestartsAreBoundedPerReconnect() async throws {
        let fixture = makeFixture()
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }

        for restart in 1...RemotePairingBrowseRestart.maximumRestarts {
            fixture.browser.fail()
            try await waitUntil("restart delay \(restart)") { await fixture.browseRestartSleeper.pendingCount() == 1 }
            await fixture.browseRestartSleeper.releaseOldest()
            try await waitUntil("restart \(restart)") { fixture.browser.startCount == restart + 1 }
        }
        fixture.browser.fail()
        await settle()

        let pendingAfterLastFailure = await fixture.browseRestartSleeper.pendingCount()
        XCTAssertEqual(pendingAfterLastFailure, 0, "no further restart")
        XCTAssertEqual(fixture.browser.startCount, RemotePairingBrowseRestart.maximumRestarts + 1)
        XCTAssertFalse(fixture.browser.isBrowsing)
        XCTAssertTrue(fixture.state.isTunnelAutoReconnecting, "the retry timers still run")
    }

    func testDisarmingCancelsAPendingRestartAndTheNextReconnectBrowsesAtOnce() async throws {
        let fixture = makeFixture()
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }
        fixture.browser.fail()
        try await waitUntil("the restart delay") { await fixture.browseRestartSleeper.pendingCount() == 1 }

        fixture.tunnel.state = .running // adopted or reconnected: nothing armed
        try await waitUntil("the restart cancelled") { await fixture.browseRestartSleeper.pendingCount() == 0 }
        let cancellations = await fixture.browseRestartSleeper.cancellationCount()
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(fixture.browser.isBrowsing)
        XCTAssertEqual(fixture.browser.startCount, 1)

        fixture.tunnel.state = .error("Health check failed")
        try await waitUntil("browsing for the next reconnect") { fixture.browser.isBrowsing }
        XCTAssertEqual(fixture.browser.startCount, 2)
    }

    func testAFailureAfterQuitNeverRestarts() async throws {
        let fixture = makeFixture()
        loseTunnel(fixture)
        try await waitUntil("browsing") { fixture.browser.isBrowsing }

        _ = await fixture.state.prepareForQuitWithoutLocation()
        fixture.browser.fail() // a failure callback that was already on its way
        await settle()

        let pendingAfterQuit = await fixture.browseRestartSleeper.pendingCount()
        XCTAssertEqual(pendingAfterQuit, 0)
        XCTAssertEqual(fixture.browser.startCount, 1)
    }
}
