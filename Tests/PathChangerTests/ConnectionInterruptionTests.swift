import XCTest
@testable import PathChanger

@MainActor
final class ConnectionInterruptionTests: XCTestCase {
    private enum Phase: CaseIterable { case beforeAcknowledgement, duringMovement, afterCompletion }
    private struct MatrixCase {
        let mode: LocationMode
        let transport: LocationTransport
        var name: String { "\(mode.rawValue)-\(transport.rawValue)" }
    }
    private let target = LocationCoordinate(latitude: 35.681236, longitude: 139.767125)

    private var cases: [MatrixCase] {
        LocationMode.allCases.flatMap { mode in
            [LocationTransport.usb, .wifi].map { MatrixCase(mode: mode, transport: $0) }
        }
    }

    private func session(_ testCase: MatrixCase, generation: UInt64) -> LocationSessionIdentity {
        LocationSessionIdentity(
            stableDeviceID: "matrix-device",
            transport: testCase.transport,
            endpointClass: testCase.transport == .usb ? .direct : .remoteServiceDiscovery,
            generation: generation
        )
    }

    private func startApply(
        coordinator: LocationSessionCoordinator,
        fake: FakeLocationInjector,
        testCase: MatrixCase
    ) throws -> (LocationApplicationRequest, Task<LocationInjectionReceipt, Error>) {
        coordinator.select(target, mode: testCase.mode)
        let request = try coordinator.beginApplication()
        return (request, Task { try await fake.apply(request) })
    }

    private func releaseAndAccept(
        _ task: Task<LocationInjectionReceipt, Error>,
        session: LocationSessionIdentity,
        coordinator: LocationSessionCoordinator,
        fake: FakeLocationInjector
    ) async throws -> LocationInjectionReceipt {
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        let receipt = try await task.value
        XCTAssertNil(coordinator.accept(receipt))
        return receipt
    }

    func testEveryModeAndTransportPreservesTruthAcrossThreeInterruptionPhases() async throws {
        XCTAssertEqual(cases.count * Phase.allCases.count, 30)
        for testCase in cases {
            for phase in Phase.allCases {
                let fake = FakeLocationInjector()
                let coordinator = LocationSessionCoordinator(injector: fake)
                let first = session(testCase, generation: 1)
                let second = session(testCase, generation: 2)
                coordinator.connectionReady(first)
                let (request, apply) = try startApply(coordinator: coordinator, fake: fake, testCase: testCase)
                await fake.waitUntilApplicationPending()

                if phase == .beforeAcknowledgement {
                    coordinator.connectionLost(reason: "matrix interruption")
                    await fake.releaseNextApplication(session: first)
                    let late = try await apply.value
                    XCTAssertEqual(coordinator.accept(late), .noPendingRequest, testCase.name)
                } else {
                    await fake.releaseNextApplication(session: first)
                    let receipt = try await apply.value
                    XCTAssertNil(coordinator.accept(receipt), testCase.name)
                    coordinator.beginMovement(testCase.mode)
                    if phase == .afterCompletion { coordinator.completeMovement() }
                    coordinator.connectionLost(reason: "matrix interruption")
                    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt, testCase.name)
                }

                XCTAssertEqual(coordinator.state.desiredLocation, target, testCase.name)
                if case .uncertain = coordinator.state.application {} else {
                    XCTFail("Expected uncertainty for \(testCase.name) phase \(phase)")
                }

                coordinator.connectionReady(second)
                let reapplyRequest = try coordinator.beginApplication()
                let reapply = Task { try await fake.apply(reapplyRequest) }
                let recovered = try await releaseAndAccept(
                    reapply,
                    session: second,
                    coordinator: coordinator,
                    fake: fake
                )
                XCTAssertEqual(recovered.sessionGeneration, 2, testCase.name)
                XCTAssertEqual(coordinator.state.desiredLocation, target, testCase.name)
                XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, recovered, testCase.name)
                XCTAssertTrue(coordinator.state.application.isActive, testCase.name)
                let calls = await fake.calls()
                XCTAssertFalse(calls.contains { if case .clear = $0 { true } else { false } }, testCase.name)
                _ = request
            }
        }
    }

    func testMalformedReceiptsFromFakeNeverBecomeActive() async throws {
        enum Fault: CaseIterable { case wrongRequestID, staleEndpoint, staleGeneration, wrongCoordinate }
        for testCase in cases {
            for fault in Fault.allCases {
                let fake = FakeLocationInjector()
                let coordinator = LocationSessionCoordinator(injector: fake)
                let identity = session(testCase, generation: 4)
                coordinator.connectionReady(identity)
                coordinator.select(target, mode: testCase.mode)
                let request = try coordinator.beginApplication()
                let apply = Task { try await fake.apply(request) }
                await fake.waitUntilApplicationPending()
                await fake.releaseNextApplication(
                    session: identity,
                    requestIDOverride: fault == .wrongRequestID ? UUID() : nil,
                    coordinateOverride: fault == .wrongCoordinate ? LocationCoordinate(latitude: 0, longitude: 0) : nil,
                    endpointClassOverride: fault == .staleEndpoint ? (identity.endpointClass == .direct ? .remoteServiceDiscovery : .direct) : nil,
                    generationOverride: fault == .staleGeneration ? identity.generation - 1 : nil
                )
                let receipt = try await apply.value
                let expected: LocationSessionTransitionError
                switch fault {
                case .wrongRequestID, .staleEndpoint: expected = .requestMismatch
                case .staleGeneration: expected = .staleGeneration
                case .wrongCoordinate: expected = .coordinateMismatch
                }
                XCTAssertEqual(coordinator.accept(receipt), expected, "\(testCase.name)-\(fault)")
                XCTAssertFalse(coordinator.state.application.isActive, testCase.name)
                XCTAssertNil(coordinator.state.lastAcknowledgedReceipt, testCase.name)
            }
        }
    }

    func testRejectedApplicationsExposeRateLimitQueueOverflowAndTimeoutTruth() throws {
        let failures = ["rate_limited", "queue_overflow", "timeout"]
        for code in failures {
            let testCase = MatrixCase(mode: .teleport, transport: .usb)
            let coordinator = LocationSessionCoordinator(injector: FakeLocationInjector())
            coordinator.connectionReady(session(testCase, generation: 1))
            coordinator.select(target, mode: .teleport)
            let request = try coordinator.beginApplication()
            let error = NSError(domain: "MatrixFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: code])
            XCTAssertNil(coordinator.reject(requestID: request.id, error: error))
            XCTAssertFalse(coordinator.state.application.isActive)
            XCTAssertEqual(coordinator.state.desiredLocation, target)
        }
    }

    func testProcessDeathAndSelectedDeviceLossPreserveDesiredWithoutImplicitClear() throws {
        for event in [LocationSessionLossEvent.bridgeTerminated(exitCode: 9), .selectedDeviceLost(stableDeviceID: "matrix-device")] {
            let testCase = MatrixCase(mode: .multiSpot, transport: .wifi)
            let coordinator = LocationSessionCoordinator(injector: FakeLocationInjector())
            coordinator.connectionReady(session(testCase, generation: 1))
            coordinator.select(target, mode: .multiSpot)
            coordinator.submit(event)
            XCTAssertEqual(coordinator.state.desiredLocation, target)
            XCTAssertFalse(coordinator.state.application.isActive)
        }
    }

    func testFailedExplicitClearRetainsAcknowledgedTruth() async throws {
        let testCase = MatrixCase(mode: .teleport, transport: .usb)
        let fake = FakeLocationInjector()
        let coordinator = LocationSessionCoordinator(injector: fake)
        let identity = session(testCase, generation: 1)
        coordinator.connectionReady(identity)
        let (_, apply) = try startApply(coordinator: coordinator, fake: fake, testCase: testCase)
        let receipt = try await releaseAndAccept(apply, session: identity, coordinator: coordinator, fake: fake)
        await fake.setShouldFailClear(true)
        let clearError = await coordinator.clear()
        XCTAssertEqual(clearError, .clearFailed)
        XCTAssertEqual(coordinator.state.desiredLocation, target)
        XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
    }
    func testRecoveryExhaustionAndSelectedDeviceReplacementRemainTruthful() async throws {
        let strategy = ReconnectionStrategy(maxAttempts: 2, initialDelaySeconds: 0, maxDelaySeconds: 0, backoffMultiplier: 1, jitterFactor: 0)
        for transport in [LocationTransport.usb, .wifi] {
            let testCase = MatrixCase(mode: .twoSpot, transport: transport)
            let coordinator = LocationSessionCoordinator(injector: FakeLocationInjector())
            let original = session(testCase, generation: 1)
            coordinator.connectionReady(original)
            coordinator.select(target, mode: .twoSpot)
            coordinator.connectionLost(reason: "matrix loss")
            var attempts = 0
            let exhausted = await coordinator.recover(strategy: strategy) { _, _ in
                attempts += 1
                throw NSError(domain: "offline", code: 1)
            }
            XCTAssertEqual(exhausted, .recoveryExhausted, testCase.name)
            XCTAssertEqual(attempts, 2, testCase.name)
            XCTAssertEqual(coordinator.state.desiredLocation, target, testCase.name)
            XCTAssertFalse(coordinator.state.application.isActive, testCase.name)
        }

        let testCase = MatrixCase(mode: .teleport, transport: .usb)
        let replacement = LocationSessionIdentity(stableDeviceID: "replacement-device", transport: .usb, endpointClass: .direct, generation: 2)
        let coordinator = LocationSessionCoordinator(injector: FakeLocationInjector())
        coordinator.connectionReady(session(testCase, generation: 1))
        coordinator.select(target, mode: .teleport)
        coordinator.connectionLost(reason: "device replaced")
        let mismatch = await coordinator.recover(strategy: ReconnectionStrategy(maxAttempts: 1, initialDelaySeconds: 0, maxDelaySeconds: 0, backoffMultiplier: 1, jitterFactor: 0)) { _, _ in replacement }
        XCTAssertEqual(mismatch, .recoveryExhausted)
        XCTAssertEqual(coordinator.state.desiredLocation, target)
        XCTAssertFalse(coordinator.state.application.isActive)
    }

}
