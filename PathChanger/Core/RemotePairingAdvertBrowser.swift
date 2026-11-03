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
    /// Starts browsing (a no-op while already browsing, apart from replacing `onAdvert`).
    /// `onAdvert` runs on the main actor when an advert appears or changes after the
    /// browse began; the adverts already known when it starts are not news.
    func start(onAdvert: @escaping @MainActor () -> Void)
    /// Stops browsing. No `onAdvert` runs afterwards.
    func stop()
}

/// Decides which browse results are news. Pure, so the rule is testable without a network.
struct RemotePairingAdvertTracker {
    private var known: Set<String>?

    /// `present` is every advert listed now; `changed` the adverts whose interfaces or
    /// TXT record changed in this update. Returns true when an advert appeared that the
    /// previous update did not list, or a listed one changed. The first update is the
    /// baseline; an advert leaving is not news.
    mutating func update(present: Set<String>, changed: Set<String>) -> Bool {
        defer { known = present }
        guard let known else { return false }
        return !present.subtracting(known).isEmpty || !changed.isDisjoint(with: present)
    }
}

/// How often an advert alone may wake a reconnect (review 2026-11-03 issue 9). The browser
/// cannot be filtered to the remembered phone (no altIRK in the app), so any Apple device
/// joining or leaving the LAN is news. The first advert after a reconnect arms wakes it at
/// once; further adverts within `window` of that wake are ignored, and the reconnect keeps
/// its own timers. Real visibility (usbmux, mobdev2) never passes through this.
struct RemotePairingAdvertHintLimiter {
    static let window: TimeInterval = 30

    private var lastAdmitted: Date?

    /// True when an advert at `now` may wake the reconnect; it then starts a new window.
    /// A clock that went back keeps the window closed.
    mutating func admit(at now: Date) -> Bool {
        if let lastAdmitted, now.timeIntervalSince(lastAdmitted) < Self.window { return false }
        lastAdmitted = now
        return true
    }

    /// A reconnect armed again: its first advert wakes it at once.
    mutating func reset() {
        lastAdmitted = nil
    }
}

@MainActor
final class NetworkRemotePairingAdvertBrowser: RemotePairingAdvertBrowsing {
    static let serviceType = "_remotepairing._tcp"

    private var browser: NWBrowser?
    private var onAdvert: (@MainActor () -> Void)?
    private var tracker = RemotePairingAdvertTracker()
    /// Bumped by every start and stop, so a callback queued by an ended browse is ignored.
    private var generation: UInt64 = 0

    func start(onAdvert: @escaping @MainActor () -> Void) {
        self.onAdvert = onAdvert
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
        guard tracker.update(present: present, changed: changed) else { return }
        onAdvert?()
    }

    private func stateChanged(to state: NWBrowser.State, generation id: UInt64) {
        guard id == generation else { return }
        switch state {
        case .failed(let error):
            // A later start (the next reconnect) browses again.
            Logger.error("[RemotePairingBrowse] Browse failed: \(error)", category: .device)
            browser?.cancel()
            browser = nil
            generation &+= 1
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
