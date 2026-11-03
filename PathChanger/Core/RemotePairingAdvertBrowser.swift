//
//  RemotePairingAdvertBrowser.swift
//  PathChanger
//
//  A "the phone may be back" hint for the automatic reconnects (live 2026-11-03). After
//  the phone returned to Wi-Fi its `_remotepairing._tcp` advert reappeared, but usbmuxd
//  listed nothing and the mobdev2 advert did not change, so the reconnects only tried on
//  their timers. The helper's remote pairing lane finds the phone through this advert,
//  matched by the altIRK in its pairing record; the app cannot match it (it never reads
//  pairing secrets), so an advert appearing is only a hint, never visibility.
//
//  Unprivileged multicast DNS browsing through Network.framework. AppState runs it only
//  while a tunnel or location reconnect is armed, and never under test hosts.
//

import Foundation
import Network

/// Browses for RemotePairing adverts. `NetworkRemotePairingAdvertBrowser` is the only
/// production conformer; tests substitute a fake.
@MainActor
protocol RemotePairingAdvertBrowsing: AnyObject {
    /// Starts browsing (a no-op while already browsing, apart from replacing the handlers).
    /// `onAdvert` runs on the main actor when an advert appears or changes after the
    /// browse began; the adverts already known when it starts are not news. `onFailure`
    /// runs once if the browse fails and ends on its own; a later `start` browses again.
    func start(onAdvert: @escaping @MainActor (RemotePairingAdvertNews) -> Void, onFailure: @escaping @MainActor () -> Void)
    /// Stops browsing. Neither handler runs afterwards.
    func stop()
}

/// What a browse update said about the adverts. Advert names stay opaque (never logged).
struct RemotePairingAdvertNews: Equatable, Sendable {
    /// A new advert appeared within `RemotePairingAdvertTracker.replacementWindow` of
    /// another one's withdrawal: what the phone does when it comes back (live 2026-11-03:
    /// a new instance 3-318 ms after the old one was withdrawn).
    var isReplacement: Bool

    static let appeared = RemotePairingAdvertNews(isReplacement: false)
    static let replacement = RemotePairingAdvertNews(isReplacement: true)
}

/// Starting a browse again after it failed while a reconnect is armed (review 2026-11-03
/// issue 10). A few tries per reconnect, spaced out: the reconnect timers run regardless.
enum RemotePairingBrowseRestart {
    static let delay: TimeInterval = 30
    static let maximumRestarts = 3
}

/// Decides which browse results are news. Pure, so the rule is testable without a network.
struct RemotePairingAdvertTracker {
    /// How soon after a withdrawal a new advert counts as its replacement.
    static let replacementWindow: TimeInterval = 5

    private var known: Set<String>?
    /// When an advert last left, until a replacement uses it.
    private var lastWithdrawal: Date?

    /// `present` is every advert listed now; `changed` the adverts whose interfaces or
    /// TXT record changed in this update. Returns true when an advert appeared that the
    /// previous update did not list, or a listed one changed. The first update is the
    /// baseline; an advert leaving is not news.
    mutating func update(present: Set<String>, changed: Set<String>) -> Bool {
        news(present: present, changed: changed, at: Date()) != nil
    }

    /// The same rule, saying whether the news is a replacement: an advert that appeared
    /// within `replacementWindow` after another left (also in the same update). Each
    /// withdrawal makes at most one replacement.
    mutating func news(present: Set<String>, changed: Set<String>, at now: Date) -> RemotePairingAdvertNews? {
        defer { known = present }
        guard let known else { return nil }
        if !known.subtracting(present).isEmpty { lastWithdrawal = now }
        let appeared = !present.subtracting(known).isEmpty
        guard appeared || !changed.isDisjoint(with: present) else { return nil }
        if appeared, let lastWithdrawal {
            let elapsed = now.timeIntervalSince(lastWithdrawal)
            if elapsed >= 0, elapsed <= Self.replacementWindow {
                self.lastWithdrawal = nil
                return .replacement
            }
        }
        return .appeared
    }
}

/// How often an advert alone may wake a reconnect (review 2026-11-03 issue 9). The browser
/// cannot be filtered to the remembered phone (no altIRK in the app), so any Apple device
/// joining or leaving the LAN is news. The first advert after a reconnect arms wakes it at
/// once; further adverts within `window` of that wake are ignored, and the reconnect keeps
/// its own timers, except one replacement per window (live 2026-11-03: the phone's fresh
/// advert came right after its stale one had opened the window, and was ignored). So churn
/// wakes a reconnect at most twice per window. Real visibility (usbmux, mobdev2) never
/// passes through this.
struct RemotePairingAdvertHintLimiter {
    static let window: TimeInterval = 30

    private var lastAdmitted: Date?
    private var replacementAdmittedInWindow = false

    /// True when an advert at `now` may wake the reconnect. A plain advert outside the
    /// window starts a new one; a replacement inside it is admitted once without moving
    /// it. A clock that went back keeps the window closed.
    mutating func admit(at now: Date, news: RemotePairingAdvertNews = .appeared) -> Bool {
        if let lastAdmitted {
            let elapsed = now.timeIntervalSince(lastAdmitted)
            if elapsed < Self.window {
                guard news.isReplacement, elapsed >= 0, !replacementAdmittedInWindow else { return false }
                replacementAdmittedInWindow = true
                return true
            }
        }
        lastAdmitted = now
        replacementAdmittedInWindow = false
        return true
    }

    /// A reconnect armed again: its first advert wakes it at once.
    mutating func reset() {
        lastAdmitted = nil
        replacementAdmittedInWindow = false
    }
}

@MainActor
final class NetworkRemotePairingAdvertBrowser: RemotePairingAdvertBrowsing {
    static let serviceType = "_remotepairing._tcp"

    private var browser: NWBrowser?
    private var onAdvert: (@MainActor (RemotePairingAdvertNews) -> Void)?
    private var onFailure: (@MainActor () -> Void)?
    private var tracker = RemotePairingAdvertTracker()
    /// Bumped by every start and stop, so a callback queued by an ended browse is ignored.
    private var generation: UInt64 = 0

    func start(onAdvert: @escaping @MainActor (RemotePairingAdvertNews) -> Void, onFailure: @escaping @MainActor () -> Void) {
        self.onAdvert = onAdvert
        self.onFailure = onFailure
        guard browser == nil else { return }
        generation &+= 1
        let id = generation
        tracker = RemotePairingAdvertTracker()
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: "local."),
            using: NWParameters()
        )
        // Delivered on the main queue, so the updates arrive in order.
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            let present = Set(results.compactMap { Self.key(for: $0.endpoint) })
            let changed = Set(changes.compactMap(Self.changedKey(for:)))
            MainActor.assumeIsolated {
                self?.received(present: present, changed: changed, generation: id)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.stateChanged(to: state, generation: id)
            }
        }
        self.browser = browser
        browser.start(queue: .main)
        Logger.info("[RemotePairingBrowse] Browsing for RemotePairing adverts while reconnecting", category: .device)
    }

    func stop() {
        onAdvert = nil
        onFailure = nil
        guard let browser else { return }
        generation &+= 1
        self.browser = nil
        browser.browseResultsChangedHandler = nil
        browser.stateUpdateHandler = nil
        browser.cancel()
        Logger.info("[RemotePairingBrowse] Stopped browsing", category: .device)
    }

    private func received(present: Set<String>, changed: Set<String>, generation id: UInt64) {
        guard id == generation, browser != nil else { return }
        guard let news = tracker.news(present: present, changed: changed, at: Date()) else { return }
        onAdvert?(news)
    }

    private func stateChanged(to state: NWBrowser.State, generation id: UInt64) {
        guard id == generation else { return }
        switch state {
        case .failed(let error):
            // The browse ended itself; the owner decides whether to start again.
            Logger.error("[RemotePairingBrowse] Browse failed: \(error)", category: .device)
            let failure = onFailure
            onAdvert = nil
            onFailure = nil
            browser?.cancel()
            browser = nil
            generation &+= 1
            failure?()
        case .waiting(let error):
            // For example Local Network access denied: no adverts, the timers still run.
            Logger.info("[RemotePairingBrowse] Browse waiting: \(error)", category: .device)
        case .setup, .ready, .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// The advert's identity. Its name is opaque (not a UDID) and is never logged.
    private nonisolated static func key(for endpoint: NWEndpoint) -> String? {
        guard case .service(let name, let type, let domain, _) = endpoint else { return nil }
        return "\(name)\u{1F}\(type)\u{1F}\(domain)"
    }

    /// An advert that gained an interface (back on a network) or changed its TXT record.
    private nonisolated static func changedKey(for change: NWBrowser.Result.Change) -> String? {
        guard case .changed(_, let new, let flags) = change,
              flags.contains(.interfaceAdded) || flags.contains(.metadataChanged) else { return nil }
        return key(for: new.endpoint)
    }
}
