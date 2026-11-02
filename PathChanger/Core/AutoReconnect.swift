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

/// One wait for "the phone is visible again" or a fallback timeout, cancelable.
/// A signal that arrives while nobody waits is kept for the next wait.
@MainActor
final class AutoReconnectWaiter {
    enum Wake: Equatable {
        case reachable
        case timeout
        case cancelled
    }

    private var continuation: CheckedContinuation<Wake, Never>?
    private var waitID: UInt64 = 0
    private var hasPendingSignal = false

    func signalReachable() {
        if continuation != nil {
            finish(.reachable, waitID: waitID)
        } else {
            hasPendingSignal = true
        }
    }

    func discardPendingSignal() {
        hasPendingSignal = false
    }

    func wait(timeout: TimeInterval, sleeper: any RecoverySleeping) async -> Wake {
        guard !Task.isCancelled else { return .cancelled }
        if hasPendingSignal {
            hasPendingSignal = false
            return .reachable
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
