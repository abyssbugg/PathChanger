import Foundation
@testable import PathChanger

actor FakeLocationInjector: LocationInjecting {
    enum Call: Equatable {
        case apply(LocationApplicationRequest)
        case clear(LocationInjectionTarget, LocationSessionIdentity?)
        case event(LocationBridgeEvent)
    }

    enum FakeError: Error, Equatable {
        case applicationFailed(String)
        case clearFailed
    }

    private typealias PendingApplication = (
        request: LocationApplicationRequest,
        continuation: CheckedContinuation<LocationInjectionReceipt, Error>
    )

    private var pendingApplications: [PendingApplication] = []
    private var pendingWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventContinuations: [AsyncStream<LocationBridgeEvent>.Continuation] = []
    private var callLog: [Call] = []
    private var shouldFailClear = false
    private var shouldBlockClear = false
    private var clearEntered = false
    private var clearEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var clearReleaseContinuation: CheckedContinuation<Void, Never>?

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        callLog.append(.apply(request))
        return try await withCheckedThrowingContinuation { continuation in
            pendingApplications.append((request, continuation))
            pendingWaiters.forEach { $0.resume() }
            pendingWaiters.removeAll()
        }
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {
        callLog.append(.clear(target, session))
        clearEntered = true
        clearEnteredWaiters.forEach { $0.resume() }
        clearEnteredWaiters.removeAll()

        if shouldBlockClear {
            await withCheckedContinuation { clearReleaseContinuation = $0 }
        }
        if shouldFailClear { throw FakeError.clearFailed }
    }

    func events() async -> AsyncStream<LocationBridgeEvent> {
        let (stream, continuation) = AsyncStream<LocationBridgeEvent>.makeStream()
        eventContinuations.append(continuation)
        return stream
    }

    func waitUntilApplicationPending() async {
        guard pendingApplications.isEmpty else { return }
        await withCheckedContinuation { pendingWaiters.append($0) }
    }

    func releaseNextApplication(
        session: LocationSessionIdentity,
        outcome: LocationInjectionOutcome = .applied,
        completedAt: Date = Date(timeIntervalSince1970: 1_789_000_000)
    ) {
        guard !pendingApplications.isEmpty else { return }
        let pending = pendingApplications.removeFirst()
        pending.continuation.resume(returning: LocationInjectionReceipt(
            requestID: pending.request.id,
            session: UUID(),
            coordinate: pending.request.coordinate,
            transport: session.transport,
            endpointClass: session.endpointClass,
            sessionGeneration: session.generation,
            completedAt: completedAt,
            outcome: outcome
        ))
    }

    func failNextApplication(code: String) {
        guard !pendingApplications.isEmpty else { return }
        let pending = pendingApplications.removeFirst()
        pending.continuation.resume(throwing: FakeError.applicationFailed(code))
    }

    func emit(_ event: LocationBridgeEvent) {
        callLog.append(.event(event))
        eventContinuations.forEach { $0.yield(event) }
    }

    func finishEvents() {
        eventContinuations.forEach { $0.finish() }
        eventContinuations.removeAll()
    }

    func setShouldFailClear(_ value: Bool) { shouldFailClear = value }
    func setShouldBlockClear(_ value: Bool) { shouldBlockClear = value }

    func waitForClearEntered() async throws {
        guard !clearEntered else { return }
        await withCheckedContinuation { clearEnteredWaiters.append($0) }
    }

    func releaseClear() {
        clearReleaseContinuation?.resume()
        clearReleaseContinuation = nil
    }

    func calls() -> [Call] { callLog }
    func pendingApplicationCount() -> Int { pendingApplications.count }
}
