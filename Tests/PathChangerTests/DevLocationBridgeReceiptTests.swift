import XCTest
@testable import PathChanger

final class DevLocationBridgeReceiptTests: XCTestCase {
    func testDirectAndRSDClassificationRetainsPhysicalTransport() {
        let usb = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .usb,
            rsdAddress: nil, rsdPort: nil
        )
        XCTAssertEqual(usb.arguments, ["--udid", "device"])
        XCTAssertEqual(usb.transport, .usb)
        XCTAssertEqual(usb.endpointClass, .direct)

        let rsd = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .wifi,
            rsdAddress: "fd00::1", rsdPort: 49155
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

    func testClearRetriedAfterTheDeviceWasClearedIsAcceptedForTheSameIdentityOnly() throws {
        // Live 2026-11-01: the first Clear cleared the phone (completeClear ran), but
        // the app still saw an error; every retry then failed in beginClear with
        // missingSession before reaching the helper, wedging Move until relaunch.
        var tracker = LocationSessionGenerationTracker()
        let session = tracker.resolve(
            stableDeviceID: "device-clear-again",
            transport: .wifi,
            endpointClass: .remoteServiceDiscovery
        )
        let identity = LocationSessionIdentity(
            stableDeviceID: "device-clear-again",
            transport: .wifi,
            endpointClass: .remoteServiceDiscovery,
            generation: session.generation
        )
        try tracker.beginClear(identity)
        try tracker.completeClear(identity)

        XCTAssertNoThrow(try tracker.beginClear(identity))
        XCTAssertNoThrow(try tracker.completeClear(identity))

        let otherGeneration = LocationSessionIdentity(
            stableDeviceID: identity.stableDeviceID, transport: .wifi,
            endpointClass: .remoteServiceDiscovery, generation: session.generation + 1
        )
        XCTAssertThrowsError(try tracker.beginClear(otherGeneration)) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .staleAcknowledgement)
        }
        let otherEndpoint = LocationSessionIdentity(
            stableDeviceID: identity.stableDeviceID, transport: .wifi,
            endpointClass: .direct, generation: session.generation
        )
        XCTAssertThrowsError(try tracker.beginClear(otherEndpoint)) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .endpointMismatch)
        }
        let otherTransport = LocationSessionIdentity(
            stableDeviceID: identity.stableDeviceID, transport: .usb,
            endpointClass: .remoteServiceDiscovery, generation: session.generation
        )
        XCTAssertThrowsError(try tracker.beginClear(otherTransport)) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .transportMismatch)
        }

        // The cleared session still cannot take an acknowledgement, and the next
        // apply starts a new generation.
        let stale = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: UUID(), sessionGeneration: session.generation,
            physicalTransport: .wifi, channel: .userspaceRSD,
            endpointClass: .remoteServiceDiscovery
        ))
        XCTAssertThrowsError(try tracker.adopt(
            stale, stableDeviceID: identity.stableDeviceID, sessionID: session.sessionID
        ))
        let next = tracker.resolve(
            stableDeviceID: identity.stableDeviceID, transport: .wifi,
            endpointClass: .remoteServiceDiscovery
        )
        XCTAssertEqual(next.generation, session.generation + 1)
    }

    func testClearAcknowledgementOverTheOtherLaneIsAcceptedButTransportAndGenerationMustMatch() throws {
        // The helper rebuilds its device connection after an error and may come back on
        // its other lane (direct usbmux vs userspace RSD). A Clear ends simulation on the
        // whole device whichever lane carried it, so a Clear acknowledgement on another
        // endpoint class is still the Clear of this session (review 2026-11-01).
        let session = LocationSessionIdentity(
            stableDeviceID: "device-clear-lane", transport: .wifi,
            endpointClass: .direct, generation: 4
        )
        func acknowledgement(
            generation: UInt64 = 4,
            transport: LocationTransport = .wifi,
            channel: LocationDVTChannel,
            endpointClass: LocationEndpointClass
        ) throws -> LocationProviderAcknowledgement {
            try XCTUnwrap(LocationProviderAcknowledgement(
                requestID: UUID(), sessionGeneration: generation,
                physicalTransport: transport, channel: channel, endpointClass: endpointClass
            ))
        }

        XCTAssertEqual(
            DevLocationBridge.checkClearAcknowledgement(
                try acknowledgement(channel: .usbmuxDirect, endpointClass: .direct), session: session
            ),
            .matches
        )
        XCTAssertEqual(
            DevLocationBridge.checkClearAcknowledgement(
                try acknowledgement(channel: .userspaceRSD, endpointClass: .remoteServiceDiscovery), session: session
            ),
            .endpointDiffers
        )
        XCTAssertEqual(
            DevLocationBridge.checkClearAcknowledgement(
                try acknowledgement(generation: 5, channel: .usbmuxDirect, endpointClass: .direct), session: session
            ),
            .mismatch
        )
        XCTAssertEqual(
            DevLocationBridge.checkClearAcknowledgement(
                try acknowledgement(transport: .usb, channel: .usbmuxDirect, endpointClass: .direct), session: session
            ),
            .mismatch
        )
        XCTAssertTrue(ClearAcknowledgementCheck.endpointDiffers.acceptsClear)
        XCTAssertTrue(ClearAcknowledgementCheck.matches.acceptsClear)
        XCTAssertFalse(ClearAcknowledgementCheck.mismatch.acceptsClear)
    }

    private func restoredHelperReceipt(generation: UInt64) -> LocationInjectionReceipt {
        LocationInjectionReceipt(
            requestID: UUID(), session: UUID(),
            coordinate: .init(latitude: 37.33182, longitude: -122.03118),
            transport: .usb, actualChannel: .nativeRSD, endpointClass: .remoteServiceDiscovery,
            sessionGeneration: generation, completedAt: Date(timeIntervalSince1970: 42), outcome: .applied
        )
    }

    private func restoredIdentity(_ device: String, generation: UInt64 = 9) -> LocationSessionIdentity {
        LocationSessionIdentity(
            stableDeviceID: device, transport: .usb,
            endpointClass: .remoteServiceDiscovery, generation: generation
        )
    }

    func testAnAbandonedAdoptionIsNotAdoptedAndTheNextApplyStartsANewerSession() throws {
        // The app refused a restore after the adapter had adopted it (a Clear or Move
        // began meanwhile, review 2026-11-01 issue 4). The adapter must not keep a session
        // the coordinator never took: an acknowledgement on it is refused, and the next
        // apply starts a newer session.
        var tracker = LocationSessionGenerationTracker()
        let receipt = restoredHelperReceipt(generation: 9)
        try tracker.restore(receipt: receipt, stableDeviceID: "device")

        tracker.abandon(receipt: receipt, stableDeviceID: "device")

        let acknowledgement = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: UUID(), sessionGeneration: 9, physicalTransport: .usb,
            channel: .userspaceRSD, endpointClass: .remoteServiceDiscovery
        ))
        XCTAssertThrowsError(
            try tracker.adopt(acknowledgement, stableDeviceID: "device", sessionID: receipt.session)
        ) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .missingSession)
        }
        let next = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(next.generation, 10, "generations never go back below what the helper saw")
        XCTAssertNotEqual(next.sessionID, receipt.session)
        // The newer session replaces the abandoned one: a Clear of the old identity is stale.
        XCTAssertThrowsError(try tracker.beginClear(restoredIdentity("device"))) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .staleAcknowledgement)
        }
    }

    func testAClearOfAnAbandonedAdoptionStillReachesTheHelper() throws {
        // AppState bumps its Clear counter (refusing the restore, which abandons it) before
        // its Clear reaches the adapter. The helper record may still hold that location and
        // the helper's clear is idempotent, so a Clear of the same identity must validate,
        // exactly like a retry after a completed Clear. Refusing it wedged Clear on every
        // retry (review 2026-11-01 issue 8).
        var tracker = LocationSessionGenerationTracker()
        let receipt = restoredHelperReceipt(generation: 9)
        try tracker.restore(receipt: receipt, stableDeviceID: "device")
        tracker.abandon(receipt: receipt, stableDeviceID: "device")

        XCTAssertNoThrow(try tracker.beginClear(restoredIdentity("device")))
        XCTAssertNoThrow(try tracker.completeClear(restoredIdentity("device")))
        XCTAssertNoThrow(try tracker.beginClear(restoredIdentity("device")), "a retried Clear still validates")
        XCTAssertThrowsError(try tracker.beginClear(restoredIdentity("device", generation: 8))) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .staleAcknowledgement)
        }

        let next = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(next.generation, 10)
    }

    func testAnAbandonedAdoptionLostToAConnectionLossRefusesClear() throws {
        // A connection loss after the abandon is a real loss: Clear refuses as for any
        // record lost to a connection drop.
        var tracker = LocationSessionGenerationTracker()
        let receipt = restoredHelperReceipt(generation: 9)
        try tracker.restore(receipt: receipt, stableDeviceID: "device")
        tracker.abandon(receipt: receipt, stableDeviceID: "device")
        tracker.markLost(stableDeviceID: "device")

        XCTAssertThrowsError(try tracker.beginClear(restoredIdentity("device"))) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .missingSession)
        }
    }

    func testAbandoningAnAdoptionLeavesANewerOrInUseSessionAlone() throws {
        // A Move that resolved a newer session meanwhile, or already applies on the
        // restored one, owns that session now: abandoning the old receipt must not end it.
        var tracker = LocationSessionGenerationTracker()
        let receipt = restoredHelperReceipt(generation: 9)
        try tracker.restore(receipt: receipt, stableDeviceID: "newer")
        let newer = tracker.resolve(
            stableDeviceID: "newer", transport: .usb, endpointClass: .direct, minimumGeneration: 12
        )
        tracker.abandon(receipt: receipt, stableDeviceID: "newer")
        XCTAssertEqual(
            tracker.resolve(stableDeviceID: "newer", transport: .usb, endpointClass: .direct), newer
        )
        XCTAssertNoThrow(try tracker.beginClear(LocationSessionIdentity(
            stableDeviceID: "newer", transport: .usb, endpointClass: .remoteServiceDiscovery,
            generation: newer.generation
        )))

        try tracker.restore(receipt: receipt, stableDeviceID: "in-use")
        let inUse = tracker.resolve(stableDeviceID: "in-use", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(inUse.generation, 9)
        tracker.abandon(receipt: receipt, stableDeviceID: "in-use")
        XCTAssertEqual(
            tracker.resolve(stableDeviceID: "in-use", transport: .usb, endpointClass: .direct), inUse
        )

        // A different receipt of the same generation is not the one that was abandoned.
        let other = restoredHelperReceipt(generation: 9)
        try tracker.restore(receipt: other, stableDeviceID: "other")
        tracker.abandon(receipt: receipt, stableDeviceID: "other")
        XCTAssertNoThrow(try tracker.beginClear(LocationSessionIdentity(
            stableDeviceID: "other", transport: .usb, endpointClass: .remoteServiceDiscovery, generation: 9
        )))
    }

    func testClearAfterAConnectionLossIsStillRefused() {
        // A record lost to a connection drop (not a completed Clear) keeps refusing.
        var tracker = LocationSessionGenerationTracker()
        let session = tracker.resolve(
            stableDeviceID: "device-lost", transport: .usb, endpointClass: .direct
        )
        tracker.markLost(stableDeviceID: "device-lost")
        let identity = LocationSessionIdentity(
            stableDeviceID: "device-lost", transport: .usb,
            endpointClass: .direct, generation: session.generation
        )
        XCTAssertThrowsError(try tracker.beginClear(identity)) {
            XCTAssertEqual($0 as? LocationSessionGenerationTracker.AdoptionError, .missingSession)
        }
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

    /// Live 2026-11-02: after a loss (and after a relaunch) the app cleared a provisional
    /// session this Mac never held. The tracker refused it before the helper and the app
    /// saw a generic failure, stored an unresolved Clear, and every retry was refused the
    /// same way: Move stayed blocked for three hours. The refusal is typed, so the app can
    /// tell "nothing held here" from a Clear the helper failed, and it is thrown before
    /// anything reaches the helper (no helper is running in this test host).
    func testAClearOfASessionThisMacDoesNotHoldIsTypedAndNeverReachesTheHelper() async throws {
        let bridge = DevLocationBridge(pythonExecutablePath: "/usr/bin/false")
        let deviceID = "00008130-0011223344556677"
        let target = LocationInjectionTarget(stableDeviceID: deviceID, transport: .usb)
        func identity(_ generation: UInt64) -> LocationSessionIdentity {
            LocationSessionIdentity(
                stableDeviceID: deviceID, transport: .usb, endpointClass: .unresolved, generation: generation
            )
        }
        func assertNoHeldSession(_ session: LocationSessionIdentity, _ label: String) async {
            let clock = ContinuousClock()
            let startedAt = clock.now
            do {
                try await bridge.clear(target: target, session: session)
                XCTFail("\(label): a Clear the tracker cannot match must not succeed")
            } catch LocationInjectionError.noHeldSession {
                // Expected: typed, and raised before any helper command.
            } catch {
                XCTFail("\(label): expected noHeldSession, got \(error)")
            }
            XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(1), "\(label): no helper round trip")
        }

        // Relaunch: the tracker has no record at all (missingSession).
        await assertNoHeldSession(identity(1), "relaunch")
        // Loss: recovery left the tracker on a newer generation than the provisional
        // session discovery published (staleAcknowledgement).
        try await bridge.adoptManagedSession(receipt: restoredHelperReceipt(generation: 4), stableDeviceID: deviceID)
        await assertNoHeldSession(identity(2), "stale generation")
        // A refused Clear leaves no Clear in progress: the next one is refused the same way.
        await assertNoHeldSession(identity(2), "retry")
    }
}

final class DevLocationBridgeRateLimitTests: XCTestCase {
    func testTheFastestOfferedUpdateRateIsNeverThrottled() async throws {
        // Settings offers 10 Hz; a 10 Hz route stalled after ~2 s because the limiter
        // refilled 5 tokens per second (review 2026-11-01). Three seconds at 10 Hz with
        // a little timer jitter must all be admitted.
        let limiter = DevLocationBridge.makeRateLimiter()
        var throttled = 0
        for tick in 0..<30 {
            if await !limiter.checkRequest() { throttled += 1 }
            // Gaps as short as 60 ms (a delayed step followed by an on-time one),
            // averaging the 100 ms grid.
            let jitter: UInt64 = tick.isMultiple(of: 3) ? 60_000_000 : 120_000_000
            try await Task.sleep(nanoseconds: jitter)
        }
        XCTAssertEqual(throttled, 0)
    }
}
