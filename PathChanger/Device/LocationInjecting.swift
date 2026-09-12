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
    func events() async -> AsyncStream<LocationBridgeEvent>
}

extension LocationInjecting {
    func events() async -> AsyncStream<LocationBridgeEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
