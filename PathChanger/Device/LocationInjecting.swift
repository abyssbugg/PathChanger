import Foundation

enum LocationBridgeEvent: Equatable, Sendable {
    case sessionReady(LocationSessionIdentity)
    case sessionLost(LocationSessionIdentity?, reason: String)
    case processTerminated(exitCode: Int32)
    case receipt(LocationInjectionReceipt)
}

protocol LocationInjecting: Sendable {
    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt
    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws
    func adoptManagedSession(
        receipt: LocationInjectionReceipt,
        stableDeviceID: String
    ) async throws
    /// Undo an `adoptManagedSession` the app then refused (a Clear or Move began while
    /// the adoption was out). Forgets only the session that receipt installed.
    func abandonAdoptedSession(_ receipt: LocationInjectionReceipt, stableDeviceID: String) async
    func events() async -> AsyncStream<LocationBridgeEvent>
}

extension LocationInjecting {
    func adoptManagedSession(
        receipt: LocationInjectionReceipt,
        stableDeviceID: String
    ) async throws {}

    func abandonAdoptedSession(_ receipt: LocationInjectionReceipt, stableDeviceID: String) async {}

    func events() async -> AsyncStream<LocationBridgeEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
