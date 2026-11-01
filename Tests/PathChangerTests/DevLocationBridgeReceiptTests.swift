import XCTest
@testable import PathChanger

final class DevLocationBridgeReceiptTests: XCTestCase {
    func testDirectAndRSDClassificationRetainsPhysicalTransport() {
        let usb = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .usb,
            isDaemonTunneld: false, rsdAddress: nil, rsdPort: nil
        )
        XCTAssertEqual(usb.arguments, ["--udid", "device"])
        XCTAssertEqual(usb.transport, .usb)
        XCTAssertEqual(usb.endpointClass, .direct)

        let rsd = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .wifi,
            isDaemonTunneld: false, rsdAddress: "fd00::1", rsdPort: 49155
        )
        XCTAssertEqual(rsd.arguments, ["--rsd", "fd00::1", "49155"])
        XCTAssertEqual(rsd.transport, .wifi)
        XCTAssertEqual(rsd.endpointClass, .remoteServiceDiscovery)
    }

    func testGenerationAdvancesOnlyAfterLossOrEndpointReplacement() {
        var tracker = LocationSessionGenerationTracker()
        let first = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        let same = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(same, first)

        tracker.markLost(stableDeviceID: "device")
        let afterLoss = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(afterLoss.generation, first.generation + 1)
        XCTAssertNotEqual(afterLoss.sessionID, first.sessionID)

        let rsd = tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .remoteServiceDiscovery)
        XCTAssertEqual(rsd.generation, afterLoss.generation + 1)
    }

    func testHelperAcknowledgedEndpointDoesNotRotateTheNextApply() throws {
        // Live 2026-11-01: Swift asks over `--udid` (.direct) while the helper's
        // userspace tunnel acknowledges remoteServiceDiscovery. Every next apply then
        // minted a new generation, so the app rejected each hop after the first as
        // stale although the helper had applied it (Jump/Two-Spot/Multi-Spot/Joystick).
        var tracker = LocationSessionGenerationTracker()
        let first = tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .direct)
        let acknowledgement = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: UUID(), sessionGeneration: first.generation,
            physicalTransport: .wifi, channel: .userspaceRSD,
            endpointClass: .remoteServiceDiscovery
        ))
        _ = try tracker.adopt(acknowledgement, stableDeviceID: "device", sessionID: first.sessionID)

        for _ in 0..<3 {
            XCTAssertEqual(
                tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .direct),
                first
            )
        }

        // A real change of transport still starts a new session.
        let usb = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(usb.generation, first.generation + 1)
    }

    func testAppSessionAheadOfTheTrackerSetsTheGeneration() {
        // After a connection loss the app starts generation N+1 before reapplying; the
        // tracker had no loss signal and kept N, so every reapply was stale (review
        // 2026-11-01). The acknowledged generation is the larger of the two.
        var tracker = LocationSessionGenerationTracker()
        let first = tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .direct)
        let ahead = tracker.resolve(
            stableDeviceID: "device", transport: .wifi, endpointClass: .direct,
            minimumGeneration: first.generation + 1
        )
        XCTAssertEqual(ahead.generation, first.generation + 1)
        XCTAssertNotEqual(ahead.sessionID, first.sessionID)
        // Not lowered by an older app generation, and stable once in step.
        XCTAssertEqual(
            tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .direct,
                            minimumGeneration: first.generation),
            ahead
        )
        XCTAssertEqual(
            tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .direct,
                            minimumGeneration: ahead.generation),
            ahead
        )
    }

    func testTrackerAdoptsActualAcknowledgedEndpointWithoutAdvancingGeneration() throws {
        var tracker = LocationSessionGenerationTracker()
        let provisional = tracker.resolve(
            stableDeviceID: "device", transport: .usb, endpointClass: .direct
        )
        let acknowledgement = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: UUID(), sessionGeneration: provisional.generation,
            physicalTransport: .usb, channel: .nativeRSD,
            endpointClass: .remoteServiceDiscovery
        ))

        let adopted = try tracker.adopt(
            acknowledgement,
            stableDeviceID: "device",
            sessionID: provisional.sessionID
        )

        XCTAssertEqual(adopted, provisional)
        XCTAssertEqual(
            tracker.resolve(
                stableDeviceID: "device", transport: .usb,
                endpointClass: .remoteServiceDiscovery
            ),
            provisional
        )
    }

    func testBeginClearInvalidatesOldAcknowledgementAndAdvancesGeneration() throws {
        var tracker = LocationSessionGenerationTracker()
        let provisional = tracker.resolve(
            stableDeviceID: "device-clear",
            transport: .usb,
            endpointClass: .direct
        )
        let clearing = LocationSessionIdentity(
            stableDeviceID: "device-clear",
            transport: .usb,
            endpointClass: .direct,
            generation: provisional.generation
        )

        try tracker.beginClear(clearing)
        try tracker.completeClear(clearing)

        let stale = LocationProviderAcknowledgement(
            requestID: UUID(),
            sessionGeneration: provisional.generation,
            physicalTransport: .usb,
            channel: .usbLockdown,
            endpointClass: .direct
        )!
        XCTAssertThrowsError(
            try tracker.adopt(
                stale,
                stableDeviceID: "device-clear",
                sessionID: provisional.sessionID
            )
        )

        let next = tracker.resolve(
            stableDeviceID: "device-clear",
            transport: .usb,
            endpointClass: .direct
        )
        XCTAssertEqual(next.generation, provisional.generation + 1)
    }

    func testFailedClearCanRetrySameAcknowledgedIdentity() throws {
        var tracker = LocationSessionGenerationTracker()
        let session = tracker.resolve(
            stableDeviceID: "device-clear-retry",
            transport: .usb,
            endpointClass: .direct
        )
        let identity = LocationSessionIdentity(
            stableDeviceID: "device-clear-retry",
            transport: .usb,
            endpointClass: .direct,
            generation: session.generation
        )

        try tracker.beginClear(identity)
        try tracker.beginClear(identity)

        XCTAssertEqual(
            tracker.resolve(
                stableDeviceID: identity.stableDeviceID,
                transport: identity.transport,
                endpointClass: identity.endpointClass
            ),
            session
        )
    }

    func testAcknowledgementRouterBuildsReceiptFromActualProviderTruth() throws {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: .init(stableDeviceID: "device", transport: .usb),
            coordinate: .init(latitude: 37.33182, longitude: -122.03118),
            mode: .teleport
        )
        var tracker = LocationSessionGenerationTracker()
        let provisional = tracker.resolve(
            stableDeviceID: "device", transport: .usb, endpointClass: .direct
        )
        let acknowledgement = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: request.id,
            sessionGeneration: provisional.generation,
            physicalTransport: .usb,
            channel: .nativeRSD,
            endpointClass: .remoteServiceDiscovery
        ))

        let receipt = try LocationApplicationAcknowledgementRouter.accept(
            request: request,
            provisionalSession: provisional,
            acknowledgement: acknowledgement,
            generationTracker: &tracker,
            completedAt: Date(timeIntervalSince1970: 42)
        )

        XCTAssertEqual(receipt.actualChannel, .nativeRSD)
        XCTAssertEqual(receipt.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(receipt.session, provisional.sessionID)
        XCTAssertEqual(receipt.sessionGeneration, provisional.generation)
        XCTAssertEqual(receipt.outcome, .applied)
    }

    func testReceiptEchoesAcceptedRequestAndSession() {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: .init(stableDeviceID: "device", transport: .wifi),
            coordinate: .init(latitude: 35.0, longitude: 139.0),
            mode: .jumpTeleport
        )
        let session = LocationBridgeSession(sessionID: UUID(), generation: 4)
        let receipt = LocationInjectionReceipt.accepted(
            request: request, endpointClass: .remoteServiceDiscovery,
            session: session, outcome: .applied, completedAt: Date(timeIntervalSince1970: 42)
        )
        XCTAssertEqual(receipt.requestID, request.id)
        XCTAssertEqual(receipt.coordinate, request.coordinate)
        XCTAssertEqual(receipt.transport, request.target.transport)
        XCTAssertEqual(receipt.sessionGeneration, 4)
    }

    func testDevLocationBridgeConformsToLocationInjecting() {
        func requireLocationInjector<T: LocationInjecting>(_: T.Type) {}
        requireLocationInjector(DevLocationBridge.self)
    }

    func testQueuedAndCompletionReceiptsPreserveOriginalRequestTruth() {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: LocationInjectionTarget(stableDeviceID: "queue-device", transport: .wifi),
            coordinate: LocationCoordinate(latitude: 51.5, longitude: -0.1),
            mode: .joystick
        )
        let session = LocationBridgeSession(sessionID: UUID(), generation: 3)
        let queued = LocationInjectionReceipt.accepted(
            request: request,
            endpointClass: .remoteServiceDiscovery,
            session: session,
            outcome: .queued,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        let completed = LocationInjectionReceipt.accepted(
            request: request,
            endpointClass: .remoteServiceDiscovery,
            session: session,
            outcome: .applied,
            completedAt: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(queued.requestID, request.id)
        XCTAssertEqual(queued.outcome, .queued)
        XCTAssertEqual(completed.requestID, queued.requestID)
        XCTAssertEqual(completed.outcome, .applied)
        XCTAssertEqual(LocationBridgeEvent.receipt(completed), .receipt(completed))
    }

    func testKeepAliveCommandReturnsAfterOwnershipIsRetained() async throws {
        let bridge = DevLocationBridge(
            pythonExecutablePath: "/bin/sleep",
            keepAliveObservationWindow: 0.05
        )
        let device = Device(id: "test-device", displayName: "Test Device", connectionType: .usb)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result = try await bridge.runPythonForTesting(
            arguments: ["30"],
            device: device,
            keepAlive: true
        )
        let elapsed = startedAt.duration(to: clock.now)
        let retained = await bridge.hasHeldSimulationProcessForTesting()
        await bridge.stopHeldSimulation()

        XCTAssertEqual(result, "")
        XCTAssertTrue(retained)
        XCTAssertLessThan(elapsed, .seconds(1))
    }
}
