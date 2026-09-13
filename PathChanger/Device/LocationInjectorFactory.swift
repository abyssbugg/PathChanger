import Foundation

enum LocationInjectorBuildFlavor {
    case shipping
    case releaseTesting

    static var current: Self {
#if DEBUG
        .releaseTesting
#else
        .shipping
#endif
    }
}

enum LocationInjectorFactory {
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        buildFlavor: LocationInjectorBuildFlavor = .current
    ) -> any LocationInjecting {
#if DEBUG
        if buildFlavor == .releaseTesting,
           environment[ProcessEnvironment.Keys.testLocationInjector] == "1" {
            return ScriptedLocationInjector()
        }
#endif
        return DevLocationBridge()
    }
}

#if DEBUG
actor ScriptedLocationInjector: LocationInjecting {
    static let sessionIdentity = LocationSessionIdentity(
        stableDeviceID: "release-testing-device",
        transport: .usb,
        endpointClass: .direct,
        generation: 1
    )
    private let identity = ScriptedLocationInjector.sessionIdentity
    private var continuations: [UUID: AsyncStream<LocationBridgeEvent>.Continuation] = [:]

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        let receipt = LocationInjectionReceipt(
            requestID: request.id,
            session: UUID(),
            coordinate: request.coordinate,
            transport: identity.transport,
            endpointClass: identity.endpointClass,
            sessionGeneration: identity.generation,
            completedAt: Date(),
            outcome: .applied
        )
        continuations.values.forEach { $0.yield(.receipt(receipt)) }
        return receipt
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}

    func events() async -> AsyncStream<LocationBridgeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(.sessionReady(identity))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}
#endif
