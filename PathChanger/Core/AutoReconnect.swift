//
//  AutoReconnect.swift
//  PathChanger
//
//  Automatic reconnect after a connection loss the user did not cause
//  (PRODUCT_REQUIREMENTS §7.3, owner decision 2026-11-02). Overnight 2026-11-01 the
//  owner left with the phone for about an hour: the one bounded recovery burst ended
//  "recoveryExhausted" and nothing tried again when the phone came back.
//
//  The pure rules live here; AppState owns the waiting task. Reconnecting goes only
//  through the location helper's unprivileged path (the recovery burst reapplies via
//  the injector, which opens the helper's device connection). It never starts or
//  restarts a tunnel or daemon, never elevates, and never lifts a Stop's command block.
//

import Foundation
import Combine

/// Whether PathChanger may wait for a lost phone and reapply its held location on its own.
enum AutoReconnectPolicy {
    struct Inputs: Equatable {
        /// Off under test hosts and previews: derives from `AppRuntimeEnvironment`.
        var isEnabled: Bool
        /// Auto, USB and Wi-Fi modes use the helper's connection; Background Daemon does not.
        var usesHelperConnection: Bool
        /// Stop Tunnel or Clear since the last Start, Move or Reconnect.
        var isLatchedByUser: Bool
        /// A Clear is running or unconfirmed.
        var hasClearPending: Bool
        var application: LocationApplicationPhase
        var hasAcknowledgedReceipt: Bool
        /// The stable device the lost session belonged to.
        var awaitedDeviceID: String?
        var selectedDeviceID: String?
    }

    enum Refusal: Equatable {
        case disabled
        case daemonMode
        case stoppedByUser
        case clearPending
        /// No acknowledged location is held and lost. After a successful Clear the last
        /// point is only staged (desired, no receipt, idle) and is never sent on its own.
        case nothingHeld
        case noDevice
        /// The user selected another device; reconnecting would re-select the old one.
        case otherDeviceSelected
    }

    enum Decision: Equatable {
        case wait(deviceID: String)
        case refuse(Refusal)
    }

    static func evaluate(_ inputs: Inputs) -> Decision {
        guard inputs.isEnabled else { return .refuse(.disabled) }
        guard inputs.usesHelperConnection else { return .refuse(.daemonMode) }
        guard !inputs.isLatchedByUser else { return .refuse(.stoppedByUser) }
        guard !inputs.hasClearPending else { return .refuse(.clearPending) }
        switch inputs.application {
        case .uncertain, .lost:
            guard inputs.hasAcknowledgedReceipt else { return .refuse(.nothingHeld) }
        case .idle, .applying, .active, .clearing, .failed:
            return .refuse(.nothingHeld)
        }
        guard let deviceID = inputs.awaitedDeviceID else { return .refuse(.noDevice) }
        if let selected = inputs.selectedDeviceID, selected != deviceID {
            return .refuse(.otherDeviceSelected)
        }
        return .wait(deviceID: deviceID)
    }
}

/// How often the waiting task may try. A burst is the existing bounded recovery
/// (5 attempts, about 1/2/4/8 s apart); these numbers space the bursts.
enum AutoReconnectSchedule {
    static let minimumSpacing: TimeInterval = 20
    static let fallbackBase: TimeInterval = 60
    static let maximumDelay: TimeInterval = 300

    /// The least time between the end of a failed burst and the next one, doubling per
    /// consecutive failure up to five minutes. No wait before the first burst.
    static func spacing(afterFailedBursts failedBursts: Int) -> TimeInterval {
        guard failedBursts > 0 else { return 0 }
        return backoff(base: minimumSpacing, failedBursts: failedBursts)
    }

    /// How long to wait for the phone to show up before trying anyway (visibility may
    /// never update, e.g. usbmux stops listing a phone Bonjour still reaches).
    static func fallbackDelay(afterFailedBursts failedBursts: Int) -> TimeInterval {
        backoff(base: fallbackBase, failedBursts: max(failedBursts, 1))
    }

    private static func backoff(base: TimeInterval, failedBursts: Int) -> TimeInterval {
        // 2^8 already exceeds the cap; bounding the exponent avoids overflow.
        min(base * pow(2, Double(min(failedBursts - 1, 8))), maximumDelay)
    }
}

/// What the waiting task depends on, injectable for tests.
struct AutomaticReconnectEnvironment {
    var isEnabled: Bool
    var usesHelperConnection: @MainActor () -> Bool
    var sleeper: any RecoverySleeping
    var now: @MainActor () -> Date
    /// The strategy for each burst; nil uses the reliability manager's, like the first one.
    var burstStrategy: ReconnectionStrategy?

    /// Production: only helper modes, real time.
    static func live(isEnabled: Bool) -> AutomaticReconnectEnvironment {
        AutomaticReconnectEnvironment(
            isEnabled: isEnabled,
            usesHelperConnection: { TunneldManager.shared.preferredMode.usesHelperConnection },
            sleeper: TaskRecoverySleeper(),
            now: { Date() },
            burstStrategy: nil
        )
    }
}

/// One wait for "the phone is visible again" (or a RemotePairing advert hint) or a
/// fallback timeout, cancelable. A signal that arrives while nobody waits is kept for the
/// next wait; a kept visibility signal outranks a kept advert.
@MainActor
final class AutoReconnectWaiter {
    enum Wake: Equatable {
        /// usbmux or mobdev2 lists the awaited phone again.
        case reachable
        /// Only a RemotePairing advert appeared: a hint, never visibility (review
        /// 2026-11-03 issue 11).
        case remotePairingAdvert
        case timeout
        case cancelled

        /// Why the wait ended, as the reconnect logs it.
        var logText: String {
            switch self {
            case .reachable: return "The phone is visible again"
            case .remotePairingAdvert: return "A RemotePairing advert appeared (a hint, not visibility)"
            case .timeout, .cancelled: return "Fallback timer"
            }
        }
    }

    private var continuation: CheckedContinuation<Wake, Never>?
    private var waitID: UInt64 = 0
    private var pendingSignal: Wake?

    func signalReachable() {
        signal(.reachable)
    }

    func signalRemotePairingAdvert() {
        signal(.remotePairingAdvert)
    }

    func discardPendingSignal() {
        pendingSignal = nil
    }

    private func signal(_ wake: Wake) {
        if continuation != nil {
            finish(wake, waitID: waitID)
        } else if pendingSignal != .reachable {
            pendingSignal = wake
        }
    }

    func wait(timeout: TimeInterval, sleeper: any RecoverySleeping) async -> Wake {
        guard !Task.isCancelled else { return .cancelled }
        if let pending = pendingSignal {
            pendingSignal = nil
            return pending
        }
        waitID &+= 1
        let id = waitID
        let timer = Task { @MainActor [weak self] in
            do {
                try await sleeper.sleep(seconds: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finish(.timeout, waitID: id)
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Wake, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                } else {
                    // One wait at a time: a wait still stored (its cancel hop not run yet)
                    // ends as cancelled instead of being dropped, which hung its task.
                    if let previous = self.continuation {
                        self.continuation = nil
                        previous.resume(returning: .cancelled)
                    }
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.cancelled, waitID: id) }
        }
    }

    private func finish(_ wake: Wake, waitID id: UInt64) {
        guard id == waitID, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: wake)
    }
}

// MARK: - Tunnel auto-reconnect (live 2026-11-03)

/// The tunnel lifecycle as automatic and manual reconnect see it. `TunneldManager` is the
/// only production conformer; it stays the one lifecycle owner.
@MainActor
protocol TunnelReconnectControlling: AnyObject {
    var preferredMode: TunnelMode { get }
    /// The state machine's state now (the published copy lags one run-loop hop).
    var lifecycleState: TunnelState { get }
    /// Every lifecycle transition, synchronously.
    var lifecycleStatePublisher: AnyPublisher<TunnelState, Never> { get }
    /// Stop Tunnel since the last explicit Start.
    var isStoppedByUser: Bool { get }
    /// The device the lost tunnel belonged to, kept when discovery deselects it.
    var reconnectDeviceId: String? { get }
    /// The last Start's failure, if any.
    var lastError: String? { get }
    /// Facts the reconnect depends on that are not lifecycle transitions: the preferred
    /// mode changed, Stop Tunnel was pressed (also when the state machine ignores it), the
    /// Stop latch was lifted.
    var reconnectControlChanges: AnyPublisher<Void, Never> { get }
    func startTunnelAutomatically(deviceId: String) async
    func reconnectTunnel(deviceId: String?) async
    /// Stop Tunnel: latches until an explicit Start, Move or Reconnect.
    func stopTunnel()
    /// An explicit user action (Move) lifts Stop Tunnel's latch.
    func liftStopLatch()
}

/// Whether and when PathChanger reopens the tunnel itself. Pure: the driver supplies the
/// facts and the time. Only helper modes (the helper's unprivileged connection) qualify;
/// a Stop Tunnel ends it, Clear does not (Clear only blocks a location reapply).
enum TunnelAutoReconnectPolicy {
    /// The first periodic attempt, doubling per failed attempt up to `maximumRetryDelay`.
    static let firstRetryDelay: TimeInterval = 5
    static let maximumRetryDelay: TimeInterval = 30
    /// The phone coming back tries at once, but never sooner than this after the last try,
    /// so a source that flickers cannot drive attempts back to back.
    static let visibilitySpacing: TimeInterval = 2
    /// How long to look away while someone else's Start or Stop runs (a state change
    /// wakes the driver sooner).
    static let busyRecheck: TimeInterval = 5

    struct Inputs: Equatable {
        var isEnabled: Bool
        var mode: TunnelMode
        var isStoppedByUser: Bool
        var tunnel: TunnelState
        /// The remembered device, kept when discovery deselects it.
        var deviceID: String?
        /// The device appeared in usbmux (USB or Network) or mobdev2 Bonjour since the last
        /// try, or a RemotePairing advert appeared (a hint only: its name is opaque).
        var phoneBecameVisible: Bool
        /// Since the loss, then since the last attempt ended.
        var secondsSinceLastTry: TimeInterval
        var failedAttempts: Int
    }

    enum Refusal: Equatable {
        case disabled
        case daemonMode
        case stoppedByUser
        case connected
        case noDevice
    }

    enum Decision: Equatable {
        case stop(Refusal)
        /// A Start or Stop is in flight: never overlap it.
        case busy
        case wait(seconds: TimeInterval)
        case attempt(deviceID: String)
    }

    static func retryDelay(afterFailedAttempts failedAttempts: Int) -> TimeInterval {
        // 2^3 already exceeds the cap; bounding the exponent avoids overflow.
        min(firstRetryDelay * pow(2, Double(min(max(failedAttempts, 0), 8))), maximumRetryDelay)
    }

    static func evaluate(_ inputs: Inputs) -> Decision {
        guard inputs.isEnabled else { return .stop(.disabled) }
        guard inputs.mode.usesHelperConnection else { return .stop(.daemonMode) }
        guard !inputs.isStoppedByUser else { return .stop(.stoppedByUser) }
        switch inputs.tunnel {
        case .running:
            return .stop(.connected)
        case .starting, .stopping:
            return .busy
        case .idle, .error:
            break
        }
        guard let deviceID = inputs.deviceID, ArgumentSanitizer.isValidDeviceUDID(deviceID) else {
            return .stop(.noDevice)
        }
        let since = max(inputs.secondsSinceLastTry, 0)
        if inputs.phoneBecameVisible {
            return since >= visibilitySpacing ? .attempt(deviceID: deviceID) : .wait(seconds: visibilitySpacing - since)
        }
        let delay = retryDelay(afterFailedAttempts: inputs.failedAttempts)
        return since >= delay ? .attempt(deviceID: deviceID) : .wait(seconds: delay - since)
    }
}

struct TunnelAutoReconnectEnvironment {
    var isEnabled: Bool
    var tunnel: any TunnelReconnectControlling
    var sleeper: any RecoverySleeping
    var now: @MainActor () -> Date

    @MainActor
    static func live(isEnabled: Bool) -> TunnelAutoReconnectEnvironment {
        TunnelAutoReconnectEnvironment(
            isEnabled: isEnabled,
            tunnel: TunneldManager.shared,
            sleeper: TaskRecoverySleeper(),
            now: { Date() }
        )
    }
}

/// Reopens the tunnel after it left running for a reason the user did not cause (a health
/// failure or a lost phone), until it is live again, the user stops it, or the mode changes
/// to Background Daemon. Attempts go through `startTunnelAutomatically`, which opens only
/// the helper's unprivileged connection and never elevates.
@MainActor
final class TunnelAutoReconnector: ObservableObject {
    /// True from the loss until the tunnel is live again or the reconnect stops.
    @Published private(set) var isReconnecting = false
    /// The last failed attempt's error, shown under the Reconnecting notice; nil before
    /// the first attempt and after the reconnect ends.
    @Published private(set) var lastAttemptError: String?

    private let environment: TunnelAutoReconnectEnvironment
    private var tunnel: any TunnelReconnectControlling { environment.tunnel }
    private var stateSubscription: AnyCancellable?
    private var previousState: TunnelState?
    private var visibleDeviceIDs: Set<String> = []
    private var wasRememberedDeviceVisible = false
    /// Why the next attempt may come early, if anything did since the last try.
    private enum VisibilityHint {
        /// usbmux or mobdev2 lists the remembered device again.
        case phoneVisible
        /// A `_remotepairing._tcp` advert appeared or changed. Its name cannot be tied to
        /// a UDID without the pairing record's altIRK, so it only says the phone may be back.
        case remotePairingAdvert

        var logText: String {
            switch self {
            case .phoneVisible: return "the phone is visible again"
            case .remotePairingAdvert: return "a RemotePairing advert appeared"
            }
        }
    }

    private var visibilityHint: VisibilityHint?
    private var phoneBecameVisible: Bool { visibilityHint != nil }
    /// Advert-only hints per reconnect: the first wakes at once, then one per window.
    private var advertHints = RemotePairingAdvertHintLimiter()
    private var lastTry = Date.distantPast
    private var failedAttempts = 0
    private var task: Task<Void, Never>?
    /// Bumped by every start and cancel, so an ended loop never clears a newer one.
    private var runID: UInt64 = 0
    /// Set by `cancel()` (Quit): nothing re-arms afterwards (review 2026-11-03 issue 11).
    private var isShutDown = false
    private var controlSubscription: AnyCancellable?
    private let waiter = AutoReconnectWaiter()

    init(environment: TunnelAutoReconnectEnvironment) {
        self.environment = environment
        guard environment.isEnabled else { return }
        stateSubscription = environment.tunnel.lifecycleStatePublisher
            .sink { [weak self] state in self?.lifecycleStateChanged(to: state) }
        controlSubscription = environment.tunnel.reconnectControlChanges
            .sink { [weak self] in self?.controlChanged() }
    }

    /// Every device usbmux (USB or Network) or mobdev2 Bonjour lists right now.
    func noteVisibleDevices(_ deviceIDs: Set<String>) {
        visibleDeviceIDs = deviceIDs
        let visible = tunnel.reconnectDeviceId.map(deviceIDs.contains) ?? false
        defer { wasRememberedDeviceVisible = visible }
        guard task != nil, visible, !wasRememberedDeviceVisible else { return }
        visibilityHint = .phoneVisible
        waiter.signalReachable()
    }

    /// A RemotePairing advert appeared or changed (live 2026-11-03: it came back while
    /// usbmuxd listed nothing and the mobdev2 advert stayed the same, so only the retry
    /// timer tried). Only while reconnecting, and never sooner than `visibilitySpacing`
    /// after the last try, however often adverts arrive. Only the first advert per
    /// `RemotePairingAdvertHintLimiter.window` counts: the browser sees every Apple device
    /// on the LAN, so churn must not keep bypassing the retry backoff. It is not
    /// visibility: nothing here or in the device list treats it as the phone being reachable.
    func noteRemotePairingAdvert() {
        guard task != nil else { return }
        guard advertHints.admit(at: environment.now()) else { return }
        if visibilityHint == nil { visibilityHint = .remotePairingAdvert }
        waiter.signalReachable()
    }

    /// Stop reconnecting for good (Quit). Stop Tunnel ends it through the lifecycle latch
    /// instead. A health failure during Quit's teardown must not re-arm it: its attempt
    /// would relaunch the helper Quit had just stopped.
    func cancel() {
        isShutDown = true
        stateSubscription = nil
        controlSubscription = nil
        guard let task else { return }
        task.cancel()
        runID &+= 1
        finish()
        Logger.info("[TunnelReconnect] Stopped: cancelled", category: .device)
    }

    /// The mode changed, Stop Tunnel was pressed (also one the state machine ignored, from
    /// idle), or the latch lifted (review 2026-11-03 issue 8): a reconnect the policy now
    /// refuses ends at once, so "Reconnecting…" never outlives it by a 5-30 s wait.
    private func controlChanged() {
        guard let task else { return }
        if case .stop(let refusal) = TunnelAutoReconnectPolicy.evaluate(inputs()) {
            task.cancel()
            runID &+= 1
            finish()
            Logger.info("[TunnelReconnect] Stopped: \(refusal)", category: .device)
            return
        }
        waiter.signalReachable()
    }

    // The publisher reports a transition before the lifecycle state reads it (willSet):
    // only the delivered value is used here, and the loop evaluates after it settles.
    private func lifecycleStateChanged(to state: TunnelState) {
        let previous = previousState
        previousState = state
        let wasArmed = task != nil
        switch state {
        case .running:
            isReconnecting = false
        case .error:
            guard case .running = previous else { break }
            if wasArmed {
                // Live again only briefly (the loop had not ended yet): start over.
                isReconnecting = true
                failedAttempts = 0
                lastTry = environment.now()
            } else {
                arm()
            }
        case .idle, .starting, .stopping:
            break
        }
        // Let a waiting loop look again (a Stop, a Start finishing, an adoption).
        if wasArmed { waiter.signalReachable() }
    }

    private func arm() {
        guard task == nil, !isShutDown else { return }
        // The facts that do not depend on the state that is still being written.
        let decision = TunnelAutoReconnectPolicy.evaluate(inputs(tunnel: .error("")))
        guard case .stop(let refusal) = decision else {
            start()
            return
        }
        Logger.debug("[TunnelReconnect] Not reconnecting: \(refusal)", category: .device)
    }

    private func start() {
        runID &+= 1
        let id = runID
        failedAttempts = 0
        lastTry = environment.now()
        visibilityHint = nil
        advertHints.reset()
        wasRememberedDeviceVisible = tunnel.reconnectDeviceId.map(visibleDeviceIDs.contains) ?? false
        waiter.discardPendingSignal()
        isReconnecting = true
        Logger.info("[TunnelReconnect] Tunnel lost without Stop; reconnecting automatically", category: .device)
        task = Task { @MainActor [weak self] in
            await self?.run(id: id)
        }
    }

    private func inputs(tunnel state: TunnelState? = nil) -> TunnelAutoReconnectPolicy.Inputs {
        TunnelAutoReconnectPolicy.Inputs(
            isEnabled: environment.isEnabled,
            mode: tunnel.preferredMode,
            isStoppedByUser: tunnel.isStoppedByUser,
            tunnel: state ?? tunnel.lifecycleState,
            deviceID: tunnel.reconnectDeviceId,
            phoneBecameVisible: phoneBecameVisible,
            secondsSinceLastTry: environment.now().timeIntervalSince(lastTry),
            failedAttempts: failedAttempts
        )
    }

    private func run(id: UInt64) async {
        defer { if runID == id { finish() } }
        while !Task.isCancelled {
            switch TunnelAutoReconnectPolicy.evaluate(inputs()) {
            case .stop(let refusal):
                Logger.info("[TunnelReconnect] Stopped: \(refusal)", category: .device)
                return
            case .busy:
                guard await waiter.wait(timeout: TunnelAutoReconnectPolicy.busyRecheck,
                                        sleeper: environment.sleeper) != .cancelled else { return }
            case .wait(let seconds):
                guard await waiter.wait(timeout: seconds, sleeper: environment.sleeper) != .cancelled else { return }
            case .attempt(let deviceID):
                let trigger = visibilityHint?.logText ?? "retry timer"
                visibilityHint = nil
                waiter.discardPendingSignal()
                Logger.info(
                    "[TunnelReconnect] Attempt \(failedAttempts + 1) (\(trigger)) for "
                        + LogRedaction.redactingDeviceIdentifiers(deviceID),
                    category: .device
                )
                await tunnel.startTunnelAutomatically(deviceId: deviceID)
                guard !Task.isCancelled else { return }
                // State changes during the attempt are not news.
                waiter.discardPendingSignal()
                lastTry = environment.now()
                if case .running = tunnel.lifecycleState {
                    Logger.info("[TunnelReconnect] Reconnected; the tunnel is live", category: .device)
                    return
                }
                lastAttemptError = tunnel.lastError
                failedAttempts += 1
            }
        }
    }

    private func finish() {
        task = nil
        isReconnecting = false
        lastAttemptError = nil
        visibilityHint = nil
        waiter.discardPendingSignal()
    }
}
