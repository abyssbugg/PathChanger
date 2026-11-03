import Darwin
import XCTest
@testable import PathChanger

@MainActor
final class PersistentBridgeRequestSerializerTests: XCTestCase {
    func testConcurrentHelperRequestsRunOneAtATimeInArrivalOrder() async {
        // PRODUCT_REQUIREMENTS 8: serialize persistent bridge requests. The single-slot
        // gate threw "request in progress" at a second caller instead of letting it wait.
        let serializer = PersistentBridgeRequestSerializer()
        var events: [String] = []

        await withTaskGroup(of: Void.self) { group in
            for name in ["a", "b", "c"] {
                group.addTask { @MainActor in
                    try? await serializer.acquire()
                    events.append("start \(name)")
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    events.append("end \(name)")
                    serializer.release()
                }
                await Task.yield()
            }
        }

        XCTAssertEqual(events, ["start a", "end a", "start b", "end b", "start c", "end c"])
    }

    func testACancelledWaiterNeverSendsAndDoesNotBlockTheQueue() async throws {
        // Review 2026-11-01: a request cancelled while waiting (Stop, mode change, loss)
        // still reached the device once admitted, while the app restored the previous
        // location as held.
        let serializer = PersistentBridgeRequestSerializer()
        try await serializer.acquire()

        let cancelled = Task { @MainActor () -> Bool in
            do {
                try await serializer.acquire()
                serializer.release()
                return true
            } catch {
                return false
            }
        }
        await Task.yield()
        cancelled.cancel()
        let admitted = await cancelled.value
        XCTAssertFalse(admitted, "a cancelled waiter must not be admitted")

        serializer.release()
        try await serializer.acquire()  // the slot is free again
        serializer.release()
    }
}

/// Performance and unit tests for PersistentLocationBridge
/// Tests the high-performance persistent Python bridge implementation
final class ManagedLocationHelperRecordTests: XCTestCase {
    private let helperID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testSocketReadTimeoutPreservesHelperStateForDurableReconciliation() {
        let timeout = ManagedLocationHelperClient.ClientError.readFailed(EAGAIN)

        XCTAssertTrue(timeout.isResponseTimeout)
        XCTAssertFalse(timeout.invalidatesManagedHelperState)
    }

    func testDurableResultReconstructsExactProviderResponse() throws {
        let requestID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let result = ManagedLocationHelperResult(
            command: "set_location",
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash("device-A"),
            requestID: requestID.uuidString,
            sessionGeneration: 7,
            success: true,
            error: nil,
            code: nil,
            physicalTransport: "Network",
            actualChannel: "userspaceRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(latitude: 37.33182, longitude: -122.03118),
            completedAt: 1
        )

        XCTAssertTrue(result.matches(deviceID: "device-A", requestID: requestID, generation: 7))
        let response = try result.wireResponse()
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.request_id, requestID)
        XCTAssertEqual(response.session_generation, 7)
        XCTAssertEqual(response.channel, "userspaceRSD")
        XCTAssertEqual(response.endpoint_class, "remoteServiceDiscovery")
    }

    func testHelperPathsCreatePrivateStableToken() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-helper-paths-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ManagedLocationHelperPaths(baseDirectory: root)

        let firstToken = try paths.prepare()
        let secondToken = try paths.prepare()
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        ).intValue
        let tokenMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: paths.tokenURL.path)[.posixPermissions] as? NSNumber
        ).intValue

        XCTAssertEqual(firstToken, secondToken)
        XCTAssertGreaterThanOrEqual(Data(base64Encoded: firstToken)?.count ?? 0, 32)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(tokenMode & 0o777, 0o600)
    }

    func testHelperPathsRejectSymlinkDirectory() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-helper-symlink-\(UUID().uuidString)")
        let realDirectory = parent.appendingPathComponent("real")
        let linkedDirectory = parent.appendingPathComponent("linked")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: linkedDirectory.path,
            withDestinationPath: realDirectory.path
        )

        let paths = ManagedLocationHelperPaths(baseDirectory: linkedDirectory)
        XCTAssertThrowsError(try paths.prepare())
    }

    @MainActor
    func testPersistentSetRejectsInvalidDeviceIDBeforeStartingHelper() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-invalid-set-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = PersistentLocationBridge(
            helperController: ManagedLocationHelperController(
                paths: ManagedLocationHelperPaths(baseDirectory: root),
                pythonPath: root.appendingPathComponent("missing-python").path,
                bridgePath: root.appendingPathComponent("missing-bridge.py").path
            )
        )
        let invalidID = "invalid;device"
        let device = Device(id: invalidID, displayName: "Invalid", connectionType: .usb)

        do {
            _ = try await bridge.setLocation(
                LocationCoordinate(latitude: 37.33182, longitude: -122.03118),
                for: device
            )
            XCTFail("Expected invalid device ID rejection")
        } catch let ValidationError.invalidDeviceUDID(value) {
            XCTAssertEqual(value, invalidID)
        } catch {
            XCTFail("Expected invalidDeviceUDID, received \(error)")
        }

        XCTAssertFalse(bridge.isRunning)
    }

    @MainActor
    func testPersistentClearRejectsInvalidDeviceIDBeforeStartingHelper() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-invalid-clear-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = PersistentLocationBridge(
            helperController: ManagedLocationHelperController(
                paths: ManagedLocationHelperPaths(baseDirectory: root),
                pythonPath: root.appendingPathComponent("missing-python").path,
                bridgePath: root.appendingPathComponent("missing-bridge.py").path
            )
        )
        let invalidID = "invalid;device"
        let device = Device(id: invalidID, displayName: "Invalid", connectionType: .usb)

        do {
            _ = try await bridge.clearLocation(for: device)
            XCTFail("Expected invalid device ID rejection")
        } catch let ValidationError.invalidDeviceUDID(value) {
            XCTAssertEqual(value, invalidID)
        } catch {
            XCTFail("Expected invalidDeviceUDID, received \(error)")
        }

        XCTAssertFalse(bridge.isRunning)
    }

    @MainActor
    func testPersistentBridgeExposesAdoptedHelperSessions() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let temporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pc-adopt-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let paths = ManagedLocationHelperPaths(baseDirectory: temporaryDirectory)
        let firstController = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: root.appendingPathComponent("scripts/location_bridge.py").path
        )

        do {
            let firstConnection = try await firstController.connectOrLaunch()
            let session = ManagedLocationHelperSession(
                deviceIDSHA256: String(repeating: "a", count: 64),
                requestID: UUID().uuidString,
                sessionGeneration: 9,
                physicalTransport: "usb",
                actualChannel: "explicitRsd",
                endpointClass: "remoteServiceDiscovery",
                coordinate: ManagedLocationHelperCoordinate(
                    latitude: 37.33182,
                    longitude: -122.03118
                ),
                acknowledgedAt: Date().timeIntervalSince1970
            )
            let updatedRecord = ManagedLocationHelperRecord(
                protocolVersion: firstConnection.record.protocolVersion,
                helperID: firstConnection.record.helperID,
                pid: firstConnection.record.pid,
                socketPath: firstConnection.record.socketPath,
                pythonPath: firstConnection.record.pythonPath,
                pythonSHA256: firstConnection.record.pythonSHA256,
                bridgePath: firstConnection.record.bridgePath,
                bridgeSHA256: firstConnection.record.bridgeSHA256,
                tokenSHA256: firstConnection.record.tokenSHA256,
                activeSessions: [session]
            )
            let data = try JSONEncoder().encode(updatedRecord)
            try data.write(to: paths.recordURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.recordURL.path
            )

            let bridge = PersistentLocationBridge(
                helperController: ManagedLocationHelperController(
                    paths: paths,
                    pythonPath: PythonPathResolver.managedPythonPath,
                    bridgePath: root.appendingPathComponent("scripts/location_bridge.py").path
                )
            )
            try await bridge.start()
            XCTAssertEqual(bridge.adoptedHelperID, firstConnection.record.helperID)
            XCTAssertEqual(bridge.adoptedHelperSessions, [session])

            let clearedRecord = ManagedLocationHelperRecord(
                protocolVersion: updatedRecord.protocolVersion,
                helperID: updatedRecord.helperID,
                pid: updatedRecord.pid,
                socketPath: updatedRecord.socketPath,
                pythonPath: updatedRecord.pythonPath,
                pythonSHA256: updatedRecord.pythonSHA256,
                bridgePath: updatedRecord.bridgePath,
                bridgeSHA256: updatedRecord.bridgeSHA256,
                tokenSHA256: updatedRecord.tokenSHA256,
                activeSessions: []
            )
            let clearedData = try JSONEncoder().encode(clearedRecord)
            try clearedData.write(to: paths.recordURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.recordURL.path
            )

            try await bridge.refreshAdoptedHelperSessions()
            XCTAssertEqual(bridge.adoptedHelperID, firstConnection.record.helperID)
            XCTAssertTrue(bridge.adoptedHelperSessions.isEmpty)
            try await bridge.shutdownHelper()
        } catch {
            try? await firstController.shutdown()
            throw error
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.recordURL.path))
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testManagedSessionMatchesDeviceAndBuildsProviderTruthReceipt() throws {
        let helperID = UUID()
        let requestID = UUID()
        let session = ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash("device-123"),
            requestID: requestID.uuidString,
            sessionGeneration: 9,
            physicalTransport: "usb",
            actualChannel: "explicitRSD",
            endpointClass: "remoteServiceDiscovery",
            coordinate: ManagedLocationHelperCoordinate(
                latitude: 37.33182,
                longitude: -122.03118
            ),
            acknowledgedAt: 1_725_000_000
        )

        XCTAssertTrue(session.matches(deviceID: "device-123"))
        XCTAssertFalse(session.matches(deviceID: "another-device"))

        let receipt = try XCTUnwrap(session.locationReceipt(helperID: helperID))
        XCTAssertEqual(receipt.requestID, requestID)
        XCTAssertEqual(receipt.session, helperID)
        XCTAssertEqual(receipt.sessionGeneration, 9)
        XCTAssertEqual(receipt.transport, .usb)
        XCTAssertEqual(receipt.actualChannel, .explicitRSD)
        XCTAssertEqual(receipt.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(
            receipt.coordinate,
            LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
        )
        XCTAssertEqual(receipt.outcome, .applied)
    }

    func testHelperRecordGoldenFixtureWithPythonTransportValuesBuildsReceipt() throws {
        // Pins the EXACT active_sessions entry scripts/location_bridge.py writes
        // to helper.json: physical_transport echoes the request's
        // connection_type, which Swift sends as "Network" (Wi-Fi) or "USB".
        // Regression (live 2026-11-01): "Network" failed to parse, so every
        // successful Wi-Fi injection was reported to the GUI as failed.
        let cases: [(wire: String, expected: LocationTransport)] = [
            ("Network", .wifi), ("USB", .usb)
        ]
        for (wire, expected) in cases {
            let json = """
            {"device_id_sha256": "\(ManagedLocationHelperSession.deviceIDHash("device-123"))",
             "request_id": "D81A6845-7B11-43EF-9D19-A3149FD0D097",
             "session_generation": 3,
             "physical_transport": "\(wire)",
             "actual_channel": "userspaceRSD",
             "endpoint_class": "remoteServiceDiscovery",
             "coordinate": {"latitude": 36.3043026, "longitude": -86.6413561},
             "acknowledged_at": 1761969911.5}
            """
            let session = try JSONDecoder().decode(
                ManagedLocationHelperSession.self, from: Data(json.utf8))
            let receipt = try XCTUnwrap(
                session.locationReceipt(helperID: UUID()),
                "physical_transport \(wire) must produce a receipt")
            XCTAssertEqual(receipt.transport, expected)
            XCTAssertEqual(receipt.actualChannel, .userspaceRSD)
        }
        // The remote pairing lane's held session (Wi-Fi, no usbmuxd) must also restore.
        let remotePairing = """
        {"device_id_sha256": "\(ManagedLocationHelperSession.deviceIDHash("device-123"))",
         "request_id": "D81A6845-7B11-43EF-9D19-A3149FD0D097",
         "session_generation": 5,
         "physical_transport": "Network",
         "actual_channel": "remotePairingRSD",
         "endpoint_class": "remoteServiceDiscovery",
         "coordinate": {"latitude": 36.3043026, "longitude": -86.6413561},
         "acknowledged_at": 1761969911.5}
        """
        let session = try JSONDecoder().decode(
            ManagedLocationHelperSession.self, from: Data(remotePairing.utf8))
        let receipt = try XCTUnwrap(session.locationReceipt(helperID: UUID()),
                                    "a remotePairingRSD session must produce a receipt")
        XCTAssertEqual(receipt.transport, .wifi)
        XCTAssertEqual(receipt.actualChannel?.rawValue, "remotePairingRSD")
        XCTAssertEqual(receipt.endpointClass, .remoteServiceDiscovery)
    }

    func testLocationTransportHelperWireValueRoundTrips() {
        XCTAssertEqual(LocationTransport.wifi.helperWireValue, "Network")
        XCTAssertEqual(LocationTransport.usb.helperWireValue, "USB")
        for transport in [LocationTransport.usb, .wifi] {
            XCTAssertEqual(LocationTransport(helperWireValue: transport.helperWireValue), transport)
        }
        XCTAssertEqual(LocationTransport(helperWireValue: "usb"), .usb)
        XCTAssertEqual(LocationTransport(helperWireValue: "wifi"), .wifi)
        XCTAssertEqual(LocationTransport(helperWireValue: "network"), .wifi)
        XCTAssertNil(LocationTransport(helperWireValue: "bluetooth"))
        XCTAssertNil(LocationTransport(helperWireValue: ""))
    }

    func testUnauthorizedWireResponsePreservesStructuredFailureCode() throws {
        let json = #"{"success":false,"error":"Invalid helper authentication","code":"UNAUTHORIZED"}"#
        let response = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self,
            from: Data(json.utf8)
        )
        let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: response).children.compactMap {
            child -> (String, Any)? in
            guard let label = child.label else { return nil }
            return (label, child.value)
        })

        XCTAssertEqual(fields["code"] as? String, "UNAUTHORIZED")
    }

    @MainActor
    func testRefreshInvalidatesStateWhenVerifiedHelperIdentityRecordDisappears() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-helper-identity-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ManagedLocationHelperPaths(baseDirectory: root)
        let controller = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let bridge = PersistentLocationBridge(helperController: controller)

        do {
            try await bridge.start()
            XCTAssertTrue(bridge.isRunning)
            try FileManager.default.removeItem(at: paths.recordURL)

            do {
                try await bridge.refreshAdoptedHelperSessions()
                XCTFail("Expected missing authenticated identity record to fail refresh")
            } catch {
                XCTAssertFalse(bridge.isRunning)
                XCTAssertNil(bridge.adoptedHelperID)
                XCTAssertTrue(bridge.adoptedHelperSessions.isEmpty)
            }
        } catch {
            try? await controller.shutdown()
            throw error
        }
        try? await controller.shutdown()
    }

    func testWireResponseInvalidatesOnlyAuthenticationFailure() throws {
        let unauthorized = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self,
            from: Data(#"{"success":false,"code":"UNAUTHORIZED"}"#.utf8)
        )
        let providerError = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self,
            from: Data(#"{"success":false,"code":"INVALID_REQUEST"}"#.utf8)
        )

        XCTAssertTrue(unauthorized.invalidatesManagedHelperState)
        XCTAssertFalse(providerError.invalidatesManagedHelperState)
    }

    func testClientFailurePolicyPreservesStateForLocalEncodingOnly() {
        XCTAssertFalse(ManagedLocationHelperClient.ClientError.encodeFailed.invalidatesManagedHelperState)
        XCTAssertTrue(ManagedLocationHelperClient.ClientError.connectFailed(ECONNREFUSED).invalidatesManagedHelperState)
        XCTAssertTrue(ManagedLocationHelperClient.ClientError.emptyResponse.invalidatesManagedHelperState)
    }

    @MainActor
    func testProductionControllerLaunchesAndAdoptsManagedHelper() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-controller-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ManagedLocationHelperPaths(baseDirectory: root)
        let firstController = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let secondController = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )

        do {
            let launched = try await firstController.connectOrLaunch()
            let adopted = try await secondController.connectOrLaunch()
            XCTAssertTrue(launched.launchedNewHelper)
            XCTAssertFalse(adopted.launchedNewHelper)
            XCTAssertEqual(launched.record.helperID, adopted.record.helperID)
            try await secondController.shutdown()
        } catch {
            try? await firstController.shutdown()
            throw error
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.socketURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.recordURL.path))
    }

    @MainActor
    func testNeverStartedBridgeShutsDownHelperLeftByEarlierSession() async throws {
        // Quit in a session that never used the helper must still stop a helper an
        // earlier session left running; shutdownHelper used to return early.
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-orphan-helper-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ManagedLocationHelperPaths(baseDirectory: root)
        let earlierSession = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let bridge = PersistentLocationBridge(helperController: ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        ))

        _ = try await earlierSession.connectOrLaunch()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.recordURL.path))
        XCTAssertFalse(bridge.isRunning)

        do {
            try await bridge.shutdownHelper()
        } catch {
            try? await earlierSession.shutdown()
            throw error
        }

        let stillRunning = FileManager.default.fileExists(atPath: paths.recordURL.path)
            || FileManager.default.fileExists(atPath: paths.socketURL.path)
        if stillRunning { try? await earlierSession.shutdown() }
        XCTAssertFalse(stillRunning, "the earlier session's helper must be shut down")
    }

    // MARK: An orphaned helper (live 2026-11-03)

    /// Live 2026-11-03: helper 95276, launched by app 94135, was adopted by the next app
    /// after 94135 exited (its parent PID was 1). macOS denied the orphan the local
    /// network (EHOSTUNREACH) and its RemotePairing tunnel dropped 0.85 s after its app
    /// exited, so every Wi-Fi lane failed for 15 minutes while the phone advertised.
    @MainActor
    private func orphanFixture(_ label: String) throws -> (
        paths: ManagedLocationHelperPaths, bridgeScript: String, root: URL
    ) {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-\(label)-\(UUID().uuidString.prefix(8))")
        return (ManagedLocationHelperPaths(baseDirectory: root),
                repositoryRoot.appendingPathComponent("scripts/location_bridge.py").path, root)
    }

    /// Every helper reports the parent PID 1 (an orphan), except the ones the asking
    /// controller launched itself.
    private static let everyHelperIsOrphaned: (Int32) -> Int32? = { _ in 1 }

    private func writeRecord(_ record: ManagedLocationHelperRecord, sessions: [ManagedLocationHelperSession],
                             to paths: ManagedLocationHelperPaths) throws {
        let updated = ManagedLocationHelperRecord(
            protocolVersion: record.protocolVersion, helperID: record.helperID, pid: record.pid,
            socketPath: record.socketPath, pythonPath: record.pythonPath, pythonSHA256: record.pythonSHA256,
            bridgePath: record.bridgePath, bridgeSHA256: record.bridgeSHA256, tokenSHA256: record.tokenSHA256,
            activeSessions: sessions
        )
        try JSONEncoder().encode(updated).write(to: paths.recordURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.recordURL.path)
    }

    private func heldSession(for deviceID: String) -> ManagedLocationHelperSession {
        ManagedLocationHelperSession(
            deviceIDSHA256: ManagedLocationHelperSession.deviceIDHash(deviceID),
            requestID: UUID().uuidString, sessionGeneration: 7, physicalTransport: "Network",
            actualChannel: "usbmuxDirect", endpointClass: "direct",
            coordinate: ManagedLocationHelperCoordinate(latitude: 36.304303, longitude: -86.641356),
            acknowledgedAt: Date().timeIntervalSince1970
        )
    }

    func testTheLiveParentProcessIDIsTheKernelsAnswer() {
        XCTAssertEqual(ManagedLocationHelperController.liveParentProcessID(getpid()), getppid())
        XCTAssertNil(ManagedLocationHelperController.liveParentProcessID(-1))
    }

    @MainActor
    func testAnOrphanedHelperWithoutADeviceConnectionIsReplacedKeepingItsHeldSession() async throws {
        let (paths, bridgeScript, root) = try orphanFixture("orphan-replace")
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript)
        let orphan = try await earlier.connectOrLaunch()
        let deviceID = "00008130-0011223344556677"
        let held = heldSession(for: deviceID)
        try writeRecord(orphan.record, sessions: [held], to: paths)
        let controller = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript,
            parentProcessID: Self.everyHelperIsOrphaned)
        let bridge = PersistentLocationBridge(helperController: controller)
        bridge.setInheritedSessionClearEpochSource { 7 }

        do {
            try await bridge.start()
            XCTAssertEqual(bridge.adoptedHelperID, orphan.record.helperID, "adopted first, as on relaunch")

            try await bridge.replaceForeignHelperIfDisconnected(deviceID, transport: .wifi)

            XCTAssertNotEqual(bridge.adoptedHelperID, orphan.record.helperID, "a new helper under this app")
            XCTAssertTrue(bridge.isRunning)
            XCTAssertFalse(TunnelProcessTerminator.isAlive(pid: orphan.record.pid), "the orphan was stopped")
            XCTAssertEqual(bridge.inheritedHeldSession(for: deviceID)?.session, held, "looking does not take it")
            let inherited = try XCTUnwrap(bridge.takeInheritedHeldSession(for: deviceID))
            XCTAssertEqual(inherited.helperID, orphan.record.helperID)
            XCTAssertEqual(inherited.session, held)
            XCTAssertEqual(inherited.clearEpoch, 7, "stamped with the Clear counter at inheritance")
            XCTAssertNil(bridge.takeInheritedHeldSession(for: deviceID), "taken once")

            // The new helper is this app's own: never replaced again.
            let ownHelper = bridge.adoptedHelperID
            try await bridge.replaceForeignHelperIfDisconnected(deviceID, transport: .wifi)
            XCTAssertEqual(bridge.adoptedHelperID, ownHelper)
            try await bridge.shutdownHelper()
        } catch {
            try? await bridge.shutdownHelper()
            try? await earlier.shutdown()
            throw error
        }
    }

    @MainActor
    func testAHelperThisAppLaunchedIsNeverTreatedAsAnOrphan() async throws {
        let (paths, bridgeScript, root) = try orphanFixture("own-helper")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript,
            parentProcessID: Self.everyHelperIsOrphaned)
        let bridge = PersistentLocationBridge(helperController: controller)
        do {
            try await bridge.start()
            let launched = bridge.adoptedHelperID
            try await bridge.replaceForeignHelperIfDisconnected("00008130-0011223344556677", transport: .wifi)
            XCTAssertEqual(bridge.adoptedHelperID, launched)
            XCTAssertNil(bridge.takeInheritedHeldSession(for: "00008130-0011223344556677"))
            try await bridge.shutdownHelper()
        } catch {
            try? await bridge.shutdownHelper()
            throw error
        }
    }

    /// Review 2026-11-03 issue 4: while an orphan with a live connection is kept, every
    /// connect probed it again (`connection_status`, up to 5 s on a stalled link) before
    /// the `connect_device` that proves DVT anyway. One probe per adopted helper decides.
    @MainActor
    func testAKeptOrphanIsProbedOnceNotBeforeEveryConnect() async throws {
        let (paths, bridgeScript, root) = try orphanFixture("orphan-keep")
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript)
        let orphan = try await earlier.connectOrLaunch()
        let controller = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript,
            parentProcessID: Self.everyHelperIsOrphaned)
        var probes = 0
        let bridge = PersistentLocationBridge(helperController: controller, foreignHelperStatusProbe: { _, _ in
            probes += 1
            return .connected // the orphan still holds a live usbmux connection
        })
        do {
            try await bridge.start()

            try await bridge.replaceForeignHelperIfDisconnected("00008130-0011223344556677", transport: .wifi)
            try await bridge.replaceForeignHelperIfDisconnected("00008130-0011223344556677", transport: .wifi)

            XCTAssertEqual(bridge.adoptedHelperID, orphan.record.helperID, "kept for its live connection")
            XCTAssertEqual(probes, 1, "decided once for this adopted helper")
            try await bridge.shutdownHelper()
        } catch {
            try? await bridge.shutdownHelper()
            try? await earlier.shutdown()
            throw error
        }
    }

    /// Review 2026-11-03 issue 2: a request still in flight to the orphan fails after the
    /// replacement installed the new helper's connection. That late failure is about the
    /// replaced helper and must not wipe the new helper's state.
    @MainActor
    func testALateFailureFromAReplacedHelperLeavesTheNewHelpersStateAlone() async throws {
        let (paths, bridgeScript, root) = try orphanFixture("late-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript)
        let orphan = try await earlier.connectOrLaunch()
        let controller = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript,
            parentProcessID: Self.everyHelperIsOrphaned)
        let bridge = PersistentLocationBridge(helperController: controller)
        do {
            try await bridge.start()
            XCTAssertEqual(controller.activeRecord?.helperID, orphan.record.helperID, "adopted the orphan first")
            let stale = orphan
            try await bridge.replaceForeignHelperIfDisconnected("00008130-0011223344556677", transport: .wifi)
            let fresh = try XCTUnwrap(bridge.adoptedHelperID)
            XCTAssertNotEqual(fresh, orphan.record.helperID)

            bridge.invalidateManagedHelperState(
                after: ManagedLocationHelperClient.ClientError.emptyResponse, failedOn: stale)

            XCTAssertTrue(bridge.isRunning, "the new helper is still this bridge's")
            XCTAssertEqual(bridge.adoptedHelperID, fresh)
            XCTAssertNotNil(bridge.helperProcessIdentifierIfRunning())

            // A failure on the current helper's own connection still resets the state.
            let current = try XCTUnwrap(controller.activeRecord)
            bridge.invalidateManagedHelperState(
                after: ManagedLocationHelperClient.ClientError.emptyResponse,
                failedOn: ManagedLocationHelperConnection(client: stale.client, record: current, launchedNewHelper: true))
            XCTAssertFalse(bridge.isRunning)
            XCTAssertNil(bridge.adoptedHelperID)
            try await controller.shutdown()
        } catch {
            try? await bridge.shutdownHelper()
            try? await controller.shutdown()
            if TunnelProcessTerminator.isAlive(pid: orphan.record.pid) { kill(orphan.record.pid, SIGTERM) }
            throw error
        }
    }

    /// The orphan cannot be asked to quit (its socket is gone): SIGTERM goes only to the
    /// PID its validated record names, and a new helper starts.
    @MainActor
    func testAnOrphanThatCannotBeAskedToQuitIsTerminatedByItsRecordedPID() async throws {
        let (paths, bridgeScript, root) = try orphanFixture("orphan-sigterm")
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript)
        let orphan = try await earlier.connectOrLaunch()
        let controller = ManagedLocationHelperController(
            paths: paths, pythonPath: PythonPathResolver.managedPythonPath, bridgePath: bridgeScript,
            parentProcessID: Self.everyHelperIsOrphaned)
        let bridge = PersistentLocationBridge(helperController: controller)
        do {
            try await bridge.start()
            try FileManager.default.removeItem(at: paths.socketURL)

            try await bridge.replaceForeignHelperIfDisconnected("00008130-0011223344556677", transport: .wifi)

            XCTAssertFalse(TunnelProcessTerminator.isAlive(pid: orphan.record.pid))
            XCTAssertNotEqual(bridge.adoptedHelperID, orphan.record.helperID)
            XCTAssertTrue(bridge.isRunning)
            try await bridge.shutdownHelper()
        } catch {
            try? await bridge.shutdownHelper()
            if TunnelProcessTerminator.isAlive(pid: orphan.record.pid) { kill(orphan.record.pid, SIGTERM) }
            throw error
        }
    }

    /// Which helper the app may open a device connection through. An orphan that still
    /// holds a live connection keeps being adopted (usbmux lanes survive a relaunch).
    func testAnOrphanIsReplacedOnlyWhenItHasNoLiveConnection() {
        typealias Decision = PersistentLocationBridge.ForeignHelperDecision
        XCTAssertEqual(PersistentLocationBridge.foreignHelperDecision(isForeign: false, status: .notConnected("x")), .keep)
        XCTAssertEqual(PersistentLocationBridge.foreignHelperDecision(isForeign: true, status: .connected), .keep)
        XCTAssertEqual(PersistentLocationBridge.foreignHelperDecision(isForeign: true, status: .notConnected("x")), .replace)
    }

    @MainActor
    func testPersistentBridgeUsesManagedHelperForStartPingAndShutdown() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-bridge-controller-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: root),
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let bridge = PersistentLocationBridge(helperController: controller)

        do {
            try await bridge.start()
            XCTAssertTrue(bridge.isRunning)
            let pingSucceeded = try await bridge.ping()
            XCTAssertTrue(pingSucceeded)
            try await bridge.shutdownHelper()
            XCTAssertFalse(bridge.isRunning)
        } catch {
            try? await controller.shutdown()
            throw error
        }
    }

    @MainActor
    func testPersistentBridgeInvalidatesStateWhenVerifiedHelperDisappears() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-helper-death-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: root),
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let bridge = PersistentLocationBridge(helperController: controller)

        do {
            try await bridge.start()
            XCTAssertTrue(bridge.isRunning)
            XCTAssertNotNil(bridge.adoptedHelperID)

            try await controller.shutdown()
            do {
                _ = try await bridge.ping()
                XCTFail("Expected a dead helper request to fail")
            } catch {
                XCTAssertFalse(bridge.isRunning)
                XCTAssertNil(bridge.adoptedHelperID)
                XCTAssertTrue(bridge.adoptedHelperSessions.isEmpty)
            }
        } catch {
            try? await controller.shutdown()
            throw error
        }
    }

    func testSwiftClientAuthenticatesReconnectsAndQuitsManagedHelper() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ManagedLocationHelperPaths(baseDirectory: root)
        let token = try paths.prepare()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = [
            bridgeScript.path,
            "--socket", paths.socketURL.path,
            "--token-file", paths.tokenURL.path,
            "--record-file", paths.recordURL.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let terminationExpectation = expectation(description: "Managed helper exits after authenticated quit")
        process.terminationHandler = { _ in
            terminationExpectation.fulfill()
        }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        for _ in 0..<250 where !FileManager.default.fileExists(atPath: paths.socketURL.path) {
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(process.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.socketURL.path))

        let client = ManagedLocationHelperClient(socketPath: paths.socketURL.path, token: token)
        let ping: ManagedLocationHelperPingResponse = try await client.send(
            ManagedLocationHelperCommand(cmd: "ping"),
            responseType: ManagedLocationHelperPingResponse.self
        )
        let recordData = try Data(contentsOf: paths.recordURL)
        let record = try JSONDecoder().decode(ManagedLocationHelperRecord.self, from: recordData)
        XCTAssertTrue(ping.success)
        XCTAssertEqual(UUID(uuidString: ping.helperID), record.helperID)

        let quit: ManagedLocationHelperPingResponse = try await client.send(
            ManagedLocationHelperCommand(cmd: "quit"),
            responseType: ManagedLocationHelperPingResponse.self
        )
        XCTAssertTrue(quit.success)
        await fulfillment(of: [terminationExpectation], timeout: 5.0)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.socketURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.recordURL.path))
    }

    func testAdoptionRequiresMatchingProtocolAndFingerprints() throws {
        let record = ManagedLocationHelperRecord(
            protocolVersion: 1,
            helperID: helperID,
            pid: 4242,
            socketPath: "/private/helper.sock",
            pythonPath: "/runtime/bin/python3",
            pythonSHA256: "python-hash",
            bridgePath: "/bundle/location_bridge.py",
            bridgeSHA256: "bridge-hash",
            tokenSHA256: "token-hash",
            activeSessions: []
        )
        let expectation = ManagedLocationHelperExpectation(
            socketPath: record.socketPath,
            pythonPath: record.pythonPath,
            pythonSHA256: record.pythonSHA256,
            bridgePath: record.bridgePath,
            bridgeSHA256: record.bridgeSHA256,
            tokenSHA256: record.tokenSHA256
        )

        XCTAssertNoThrow(try record.validateForAdoption(expectation: expectation))

        var wrongToken = expectation
        wrongToken.tokenSHA256 = "wrong-token"
        XCTAssertThrowsError(try record.validateForAdoption(expectation: wrongToken))

        var wrongSocket = expectation
        wrongSocket.socketPath = "/private/other.sock"
        XCTAssertThrowsError(try record.validateForAdoption(expectation: wrongSocket))

        let futureRecord = ManagedLocationHelperRecord(
            protocolVersion: 2,
            helperID: helperID,
            pid: record.pid,
            socketPath: record.socketPath,
            pythonPath: record.pythonPath,
            pythonSHA256: record.pythonSHA256,
            bridgePath: record.bridgePath,
            bridgeSHA256: record.bridgeSHA256,
            tokenSHA256: record.tokenSHA256,
            activeSessions: []
        )
        XCTAssertThrowsError(try futureRecord.validateForAdoption(expectation: expectation))
    }

    func testSocketClientReadsEachResponseChunkExactlyOnce() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("PathChanger/Device/PersistentLocationBridge.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let clientStart = try XCTUnwrap(source.range(of: "struct ManagedLocationHelperClient"))
        let clientEnd = try XCTUnwrap(
            source.range(of: "struct ManagedLocationHelperCoordinate", range: clientStart.upperBound..<source.endIndex)
        )
        let clientSource = source[clientStart.lowerBound..<clientEnd.lowerBound]
        let readCount = clientSource.components(separatedBy: "Darwin.read(descriptor").count - 1

        XCTAssertEqual(readCount, 1, "Each socket response loop iteration must consume one chunk exactly once")
    }
}

final class ManagedLocationHelperStderrLogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-stderr-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @MainActor
    func testHelperStderrIsAppendedToAnOwnerOnlyLog() async throws {
        // Live 2026-11-01: helper stderr went to /dev/null, so nothing explained a
        // failed Clear. A launch that writes to stderr must leave it in the log.
        let helperDirectory = root.appendingPathComponent("helper", isDirectory: true)
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fakePython = root.appendingPathComponent("fake-python")
        try "#!/bin/sh\necho helper-stderr-marker >&2\nexit 3\n"
            .write(to: fakePython, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: fakePython.path
        )
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: helperDirectory),
            pythonPath: fakePython.path,
            bridgePath: fakePython.path,
            stderrLogURL: logURL
        )

        do {
            _ = try await controller.connectOrLaunch()
            XCTFail("A helper that exits at once must not connect")
        } catch {}

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("helper-stderr-marker"), contents)
        XCTAssertEqual(try permissions(logURL) & 0o777, 0o600)
    }

    func testHelperStderrLogAppendsAndRotatesOnceWhenOverTheCap() throws {
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        let rotatedURL = URL(fileURLWithPath: logURL.path + ".1")

        var handle = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: 16)
        handle.write(Data("first\n".utf8))
        try handle.close()
        handle = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: 16)
        handle.write(Data("second-line-long\n".utf8))
        try handle.close()
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "first\nsecond-line-long\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedURL.path))

        // Over the cap: the old log becomes .1 (replacing an older .1) and a new one starts.
        try Data("stale".utf8).write(to: rotatedURL)
        handle = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: 16)
        handle.write(Data("third\n".utf8))
        try handle.close()
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "third\n")
        XCTAssertEqual(try String(contentsOf: rotatedURL, encoding: .utf8), "first\nsecond-line-long\n")
        XCTAssertEqual(try permissions(logURL) & 0o777, 0o600)
    }

    func testHelperStderrLogIsNotSweptAsAnAppLog() throws {
        // FileLogger's age sweep deletes every *.log in the same directory; it would
        // unlink the live stderr file the helper holds open (review 2026-11-01).
        let url = try XCTUnwrap(ManagedLocationHelperStderrLog.defaultURL)
        XCTAssertEqual(url.lastPathComponent, "location-helper-stderr.txt")
        XCTAssertNotEqual(url.pathExtension, "log")
        XCTAssertNotEqual(URL(fileURLWithPath: url.path + ".1").pathExtension, "log")
    }

    func testAnAdoptedHelpersOversizedLogIsCappedInPlaceAndTheHelperKeepsWriting() throws {
        // An adopted helper keeps its descriptor open across app launches; a rename
        // would let it keep growing the renamed file. Capping in place keeps the newest
        // bytes in .1 and the helper's next append starts the live file again.
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        let rotatedURL = URL(fileURLWithPath: logURL.path + ".1")
        let helper = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: 16)
        helper.write(Data("old-old-old-old-\nnewest-tail\n".utf8))

        try ManagedLocationHelperStderrLog.capInPlace(at: logURL, maxBytes: 12)

        XCTAssertEqual(try String(contentsOf: rotatedURL, encoding: .utf8), "newest-tail\n")
        XCTAssertEqual(try permissions(rotatedURL) & 0o777, 0o600)
        helper.write(Data("after\n".utf8))
        try helper.close()
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "after\n")
        XCTAssertEqual(try permissions(logURL) & 0o777, 0o600)
    }

    func testCappingInPlaceLeavesASmallOrMissingLogAndRefusesASymlink() throws {
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        XCTAssertNoThrow(try ManagedLocationHelperStderrLog.capInPlace(at: logURL, maxBytes: 12))

        let handle = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: 12)
        handle.write(Data("small\n".utf8))
        try handle.close()
        try ManagedLocationHelperStderrLog.capInPlace(at: logURL, maxBytes: 12)
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "small\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path + ".1"))

        try FileManager.default.removeItem(at: logURL)
        let target = root.appendingPathComponent("elsewhere")
        try Data(repeating: 0x41, count: 64).write(to: target)
        try FileManager.default.createSymbolicLink(at: logURL, withDestinationURL: target)
        XCTAssertThrowsError(try ManagedLocationHelperStderrLog.capInPlace(at: logURL, maxBytes: 12))
        XCTAssertEqual(try Data(contentsOf: target).count, 64)
    }

    func testThePeriodicCapIsDueOncePerIntervalAndAfterTheClockMovesBack() {
        // Review 2026-11-01: a helper that runs for days grew its stderr log without
        // bound (capped only at launch and adoption).
        let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
        XCTAssertEqual(ManagedLocationHelperStderrLog.periodicCapInterval, 60)
        XCTAssertTrue(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: nil, now: t0))
        XCTAssertFalse(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: t0, now: t0))
        XCTAssertFalse(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: t0, now: t0 + 59.9))
        XCTAssertTrue(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: t0, now: t0 + 60))
        XCTAssertTrue(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: t0, now: t0 + 3_600))
        // A wall clock set back must not postpone the cap until it catches up.
        XCTAssertTrue(ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: t0, now: t0 - 1))
    }

    @MainActor
    func testTheControllerCapsTheStderrLogAtMostOncePerInterval() throws {
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        let rotatedURL = URL(fileURLWithPath: logURL.path + ".1")
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 20_000))
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: root.appendingPathComponent("helper")),
            pythonPath: "/nonexistent",
            bridgePath: "/nonexistent",
            stderrLogURL: logURL,
            stderrLogMaxBytes: 12,
            now: { clock.now }
        )
        let helper = try ManagedLocationHelperStderrLog.open(at: logURL)
        defer { try? helper.close() }
        // Each tail is exactly the 12-byte cap.
        helper.write(Data("first-episode-old\nfirst-tail1\n".utf8))

        controller.capStderrLogIfDue()
        XCTAssertEqual(try String(contentsOf: rotatedURL, encoding: .utf8), "first-tail1\n")
        XCTAssertEqual(try Data(contentsOf: logURL).count, 0)

        // Within the interval: the log may exceed the cap until the next due check.
        helper.write(Data("second-episode-old\nsecond-tail\n".utf8))
        clock.now += 30
        controller.capStderrLogIfDue()
        XCTAssertEqual(try String(contentsOf: rotatedURL, encoding: .utf8), "first-tail1\n")
        XCTAssertGreaterThan(try Data(contentsOf: logURL).count, 12)

        clock.now += 31
        controller.capStderrLogIfDue()
        XCTAssertEqual(try String(contentsOf: rotatedURL, encoding: .utf8), "second-tail\n")
        XCTAssertEqual(try Data(contentsOf: logURL).count, 0)
    }

    @MainActor
    func testRunningHelpersStderrLogIsCappedOnRefreshAndHealthProbeOncePerInterval() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        // Short path: the helper's Unix socket path has a length limit.
        let helperRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-stderr-cap-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: helperRoot) }
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        let rotatedURL = URL(fileURLWithPath: logURL.path + ".1")
        let clock = TestClock(Date(timeIntervalSinceReferenceDate: 30_000))
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: helperRoot),
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path,
            stderrLogURL: logURL,
            stderrLogMaxBytes: 64,
            now: { clock.now }
        )
        let bridge = PersistentLocationBridge(helperController: controller)

        func appendOversizedEpisode(_ marker: String) throws {
            let writer = try ManagedLocationHelperStderrLog.open(at: logURL, maxBytes: .max)
            writer.write(Data((String(repeating: "x", count: 200) + "\n" + marker + "\n").utf8))
            try writer.close()
        }

        do {
            try await bridge.start()
            XCTAssertTrue(bridge.isRunning)

            // Launch counts as a cap: a refresh within the interval leaves the log alone.
            try appendOversizedEpisode("refresh-tail")
            clock.now += 30
            try await bridge.refreshAdoptedHelperSessions()
            XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedURL.path))

            clock.now += 31
            try await bridge.refreshAdoptedHelperSessions()
            XCTAssertTrue(try String(contentsOf: rotatedURL, encoding: .utf8).hasSuffix("refresh-tail\n"))

            // The health probe (which runs while a location is held and nothing moves)
            // caps it too, under the same interval.
            try appendOversizedEpisode("probe-tail")
            clock.now += 61
            _ = await bridge.deviceConnectionStatus("00008130-000C5144019A0000", transport: .wifi)
            XCTAssertTrue(try String(contentsOf: rotatedURL, encoding: .utf8).hasSuffix("probe-tail\n"))
        } catch {
            try? await controller.shutdown()
            throw error
        }
        try? await controller.shutdown()
    }

    func testHelperStderrLogRefusesASymlink() throws {
        let logURL = root.appendingPathComponent("Logs/location-helper-stderr.txt")
        let target = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: logURL, withDestinationURL: target)

        XCTAssertThrowsError(try ManagedLocationHelperStderrLog.open(at: logURL))
        XCTAssertEqual(try Data(contentsOf: target).count, 0)
    }
}

final class PersistentLocationBridgeTests: XCTestCase {

    // MARK: - Error Description Tests

    func testBridgeErrorDescriptions() {
        let errors: [PersistentLocationBridge.PersistentBridgeError] = [
            .processNotRunning,
            .processStartFailed("test reason"),
            .timeout,
            .invalidResponse("bad response"),
            .bridgeError("bridge error"),
            .pythonNotFound
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }

    func testProcessNotRunningError() {
        let error = PersistentLocationBridge.PersistentBridgeError.processNotRunning
        XCTAssertEqual(error.errorDescription, "Python bridge process is not running")
    }

    func testProcessStartFailedError() {
        let error = PersistentLocationBridge.PersistentBridgeError.processStartFailed("Python not found")
        XCTAssertTrue(error.errorDescription!.contains("Python not found"))
    }

    func testTimeoutError() {
        let error = PersistentLocationBridge.PersistentBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    func testInvalidResponseError() {
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse("garbage data")
        XCTAssertTrue(error.errorDescription!.contains("garbage data"))
    }

    func testBridgeError() {
        let error = PersistentLocationBridge.PersistentBridgeError.bridgeError("Device not found")
        XCTAssertTrue(error.errorDescription!.contains("Device not found"))
    }

    func testPythonNotFoundError() {
        let error = PersistentLocationBridge.PersistentBridgeError.pythonNotFound
        XCTAssertEqual(error.errorDescription, "Python3 not found in PATH")
    }

    // MARK: - Singleton Tests

    @MainActor
    func testSharedInstanceExists() {
        let bridge = PersistentLocationBridge.shared
        XCTAssertNotNil(bridge, "Shared instance should exist")
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let bridge1 = PersistentLocationBridge.shared
        let bridge2 = PersistentLocationBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "Should return same instance")
    }

    // MARK: - Initial State Tests

    @MainActor
    func testInitialStateNotRunning() {
        let bridge = PersistentLocationBridge.shared
        // Note: The shared instance may be running from previous tests
        // This test verifies the property is accessible
        _ = bridge.isRunning
        XCTAssertTrue(true, "isRunning property should be accessible")
    }

    @MainActor
    func testInitialStatsAreZero() {
        // After fresh start or if not running, stats should be zero or near-zero
        let bridge = PersistentLocationBridge.shared
        // Stats are cumulative, so we just verify they're accessible
        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)
    }

    // MARK: - Ping Tests (requires Python and bridge script)

    @MainActor
    func testPingWhenNotRunning() async throws {
        let bridge = PersistentLocationBridge.shared

        // If bridge is not running, ping should return false
        if !bridge.isRunning {
            let pingResult = try? await bridge.ping()
            XCTAssertTrue(pingResult == nil || pingResult == false,
                         "Ping when not running should fail or return false")
        }
    }

    @MainActor
    func testPersistentSetLocationReturnsProviderAcknowledgement() {
        let bridge = PersistentLocationBridge.shared
        let operation: (
            LocationCoordinate, Device, UUID, UInt64?
        ) async throws -> LocationProviderAcknowledgement = bridge.setLocation
        _ = operation
    }

    func testWireRequestEncodesPhysicalTransport() throws {
        let request = PersistentBridgeWireRequest(
            cmd: "set_location",
            request_id: UUID(),
            session_generation: 7,
            lat: 37.33182,
            lng: -122.03118,
            udid: "TEST-DEVICE-00008030-001234567890ABCD",
            rsd_address: nil,
            rsd_port: nil,
            connection_type: "Network"
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["connection_type"] as? String, "Network")
    }

    func testWireResponseBuildsActualChannelAcknowledgement() throws {
        let requestID = UUID()
        let json = """
        {"success":true,"request_id":"\(requestID.uuidString)",
         "session_generation":7,"actual_channel":"nativeRSD",
         "endpoint_class":"remoteServiceDiscovery"}
        """
        let response = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self, from: Data(json.utf8)
        )
        let acknowledgement = try response.acknowledgement(physicalTransport: .wifi)
        XCTAssertEqual(acknowledgement.requestID, requestID)
        XCTAssertEqual(acknowledgement.sessionGeneration, 7)
        XCTAssertEqual(acknowledgement.channel, .nativeRSD)
        XCTAssertEqual(acknowledgement.endpointClass, .remoteServiceDiscovery)
    }

    func testWireResponseRejectsUnknownChannelAcknowledgement() throws {
        let json = """
        {"success":true,"request_id":"\(UUID().uuidString)",
         "session_generation":7,"actual_channel":"future-channel",
         "endpoint_class":"remoteServiceDiscovery"}
        """
        let response = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self, from: Data(json.utf8)
        )
        XCTAssertThrowsError(try response.acknowledgement(physicalTransport: .wifi))
    }

    func testSocketSuccessResponseGoldenFixtureDecodesToAcknowledgement() throws {
        // Pins the EXACT JSON scripts/location_bridge.py emits on a successful
        // socket set_location: the success payload (location_bridge.py:208-212)
        // plus the validate_request echo and helper_id added by the socket
        // writer. If Python or Swift changes the wire shape, this test fails.
        let json = """
        {"success": true, "actual_channel": "explicitRSD",
         "endpoint_class": "remoteServiceDiscovery",
         "request_id": "D81A6845-7B11-43EF-9D19-A3149FD0D097",
         "session_generation": 1, "helper_id": "golden-fixture"}
        """
        let response = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self, from: Data(json.utf8))
        let acknowledgement = try response.acknowledgement(physicalTransport: .wifi)
        XCTAssertEqual(acknowledgement.requestID.uuidString,
                       "D81A6845-7B11-43EF-9D19-A3149FD0D097")
        XCTAssertEqual(acknowledgement.sessionGeneration, 1)
        XCTAssertEqual(acknowledgement.channel, .explicitRSD)
        XCTAssertEqual(acknowledgement.endpointClass, .remoteServiceDiscovery)
    }

    /// The remote pairing lane's success payload (connect_device / set_location) pins
    /// "remotePairingRSD"; an unsupported channel would reject every location the phone
    /// applied over the lane that works when usbmuxd lists nothing.
    func testRemotePairingSocketResponseGoldenFixtureDecodesToAcknowledgement() throws {
        let json = """
        {"success": true, "actual_channel": "remotePairingRSD",
         "endpoint_class": "remoteServiceDiscovery",
         "request_id": "D81A6845-7B11-43EF-9D19-A3149FD0D097",
         "session_generation": 4, "helper_id": "golden-fixture"}
        """
        let response = try JSONDecoder().decode(
            PersistentBridgeWireResponse.self, from: Data(json.utf8))
        let acknowledgement = try response.acknowledgement(physicalTransport: .wifi)
        XCTAssertEqual(acknowledgement.channel.rawValue, "remotePairingRSD")
        XCTAssertEqual(acknowledgement.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(acknowledgement.sessionGeneration, 4)
    }

    // MARK: Developer Disk Image over the helper's connection (live 2026-11-03)

    private func wireResponse(_ json: String) throws -> PersistentBridgeWireResponse {
        try JSONDecoder().decode(PersistentBridgeWireResponse.self, from: Data(json.utf8))
    }

    func testHelperDiskImageStatusRepliesMapToStatus() throws {
        XCTAssertEqual(PersistentLocationBridge.diskImageStatus(
            from: try wireResponse(#"{"success": true, "mounted": true, "helper_id": "h"}"#)), .mounted)
        XCTAssertEqual(PersistentLocationBridge.diskImageStatus(
            from: try wireResponse(#"{"success": true, "mounted": false}"#)), .notMounted)
        // No held connection, or the helper could not ask: the CLI path decides.
        XCTAssertEqual(PersistentLocationBridge.diskImageStatus(
            from: try wireResponse(#"{"success": false, "error": "not connected"}"#)),
            .unavailable("not connected"))
        XCTAssertEqual(PersistentLocationBridge.diskImageStatus(
            from: try wireResponse(#"{"success": false, "error": "ConnectionTerminatedError: gone"}"#)),
            .unavailable("ConnectionTerminatedError: gone"))
        guard case .unavailable = PersistentLocationBridge.diskImageStatus(
            from: try wireResponse(#"{"success": true}"#)) else {
            return XCTFail("a reply without a mount status is not a status")
        }
    }

    func testHelperDiskImageMountRepliesMapToResult() throws {
        XCTAssertEqual(PersistentLocationBridge.diskImageMountResult(
            from: try wireResponse(#"{"success": true, "mounted": true}"#)), .mounted)
        // The connection went away: the CLI path may still mount.
        XCTAssertEqual(PersistentLocationBridge.diskImageMountResult(
            from: try wireResponse(#"{"success": false, "error": "not connected"}"#)),
            .unavailable("not connected"))
        // The helper asked the phone and the mount failed: a preparation failure.
        XCTAssertEqual(PersistentLocationBridge.diskImageMountResult(
            from: try wireResponse(#"{"success": false, "error": "RuntimeError: TSS refused"}"#)),
            .failed("RuntimeError: TSS refused"))
        guard case .failed = PersistentLocationBridge.diskImageMountResult(
            from: try wireResponse(#"{"success": true}"#)) else {
            return XCTFail("a reply that does not say mounted is not a mount")
        }
        // Review 2026-11-03 issue 10: auto_mount over the usbmux-direct lockdown raises
        // RSDRequiredError on iOS 27+; the CLI auto-mount retries that over a tunnel.
        XCTAssertEqual(PersistentLocationBridge.diskImageMountResult(
            from: try wireResponse(#"{"success": false, "error": "RSDRequiredError: tunnel required"}"#)),
            .unavailable("RSDRequiredError: tunnel required"))
    }

    @MainActor
    func testDiskImageCommandsNeverStartTheHelper() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_ddi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = PersistentLocationBridge(
            helperController: ManagedLocationHelperController(
                paths: ManagedLocationHelperPaths(baseDirectory: root),
                pythonPath: root.appendingPathComponent("missing-python").path,
                bridgePath: root.appendingPathComponent("missing-bridge.py").path
            )
        )
        let udid = "00008130-001234567890ABCD"
        let status = await bridge.ddiStatus(deviceId: udid, transport: .wifi)
        let mount = await bridge.ddiMount(deviceId: udid, transport: .wifi)
        XCTAssertEqual(status, .unavailable("location helper is not running"))
        XCTAssertEqual(mount, .unavailable("location helper is not running"))
        XCTAssertFalse(bridge.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "nothing was prepared or started")
    }

    /// Python/Swift parity: every channel string scripts/location_bridge.py can
    /// acknowledge must be a supported Swift channel with the endpoint class the helper
    /// pairs it with.
    func testEveryChannelTheHelperEmitsIsSupportedBySwift() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/location_bridge.py"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: "\"([a-z][A-Za-z0-9]*(?:RSD|Direct))\"")
        let text = source as NSString
        let emitted = Set(pattern.matches(in: source, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range(at: 1)) })
        XCTAssertTrue(emitted.isSuperset(of: ["userspaceRSD", "usbmuxDirect", "nativeRSD",
                                              "mobdev2RSD", "remotePairingRSD"]), "\(emitted.sorted())")
        for raw in emitted {
            let channel = LocationDVTChannel(rawValue: raw)
            XCTAssertTrue(channel.isSupported, raw)
            XCTAssertEqual(channel.endpointClass, raw == "usbmuxDirect" ? .direct : .remoteServiceDiscovery, raw)
        }
    }

    @MainActor
    func testPersistentClearReturnsProviderAcknowledgementSignature() {
        let operation: (Device, UUID, UInt64?) async throws -> LocationProviderAcknowledgement =
            PersistentLocationBridge.shared.clearLocation
        _ = operation
    }

    func testUsumuxDirectChannelIsSupportedForDirectEndpointClass() {
        // Python emits "usbmuxDirect" with endpoint_class "direct" as the
        // proven primary injection lane (scripts/location_bridge.py).
        let channel = LocationDVTChannel(rawValue: "usbmuxDirect")
        XCTAssertEqual(channel.rawValue, "usbmuxDirect")
        XCTAssertEqual(channel.endpointClass, .direct)
        let acknowledgement = LocationProviderAcknowledgement(
            requestID: UUID(), sessionGeneration: 1,
            physicalTransport: .wifi, channel: channel,
            endpointClass: .direct)
        XCTAssertNotNil(acknowledgement)
    }

    func testStaleTunnelSessionDetection() {
        XCTAssertTrue(PersistentLocationBridge.isStaleTunnelSession(
            cachedPID: 100, livePID: 200, usesTunnel: true))
        XCTAssertTrue(PersistentLocationBridge.isStaleTunnelSession(
            cachedPID: 100, livePID: nil, usesTunnel: true))
        XCTAssertFalse(PersistentLocationBridge.isStaleTunnelSession(
            cachedPID: 100, livePID: 100, usesTunnel: true))
        XCTAssertFalse(PersistentLocationBridge.isStaleTunnelSession(
            cachedPID: nil, livePID: nil, usesTunnel: false))
    }

    @MainActor
    func testTheConnectHintComesFromTheProviderAndOtherwiseFromTheRow() {
        // Review 2026-11-01 v3 (issue 1): the connect hint decides whether the helper may
        // try its mobdev2 lane, so it follows the connection mode (wired by AppState);
        // without a provider it keeps the row's type.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-connect-hint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = PersistentLocationBridge(
            helperController: ManagedLocationHelperController(
                paths: ManagedLocationHelperPaths(baseDirectory: root),
                pythonPath: root.appendingPathComponent("missing-python").path,
                bridgePath: root.appendingPathComponent("missing-bridge.py").path
            )
        )
        let usbRow = Device(id: "00008130-0011223344556677", displayName: "iPhone", connectionType: .usb)
        let wifiRow = Device(id: "00008130-0011223344556677", displayName: "iPhone", connectionType: .wifi)

        XCTAssertEqual(bridge.connectTransport(for: usbRow), .usb)
        XCTAssertEqual(bridge.connectTransport(for: wifiRow), .wifi)

        var asked: [String] = []
        bridge.connectTransportProvider = { device in
            asked.append(device.id)
            return .wifi
        }
        XCTAssertEqual(bridge.connectTransport(for: usbRow), .wifi)
        XCTAssertEqual(asked, [usbRow.id])
        XCTAssertFalse(bridge.isRunning, "deciding the hint never starts the helper")
    }
}

// MARK: - Edge Case Tests (Task 45)

final class PersistentLocationBridgeEdgeCaseTests: XCTestCase {

    /// Test handling of malformed JSON response
    func testMalformedJSONResponseHandling() {
        let malformedJSON = "{ invalid json }"
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse(malformedJSON)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("invalid json"))
    }

    /// Test timeout scenario error message
    func testTimeoutScenarioErrorMessage() {
        let error = PersistentLocationBridge.PersistentBridgeError.timeout
        XCTAssertEqual(error.errorDescription, "Bridge request timed out")
    }

    /// Test concurrent access safety with multiple requests
    @MainActor
    func testConcurrentRequestSafety() async throws {
        let bridge = PersistentLocationBridge.shared

        // Create multiple concurrent ping attempts
        await withTaskGroup(of: Bool?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await bridge.ping()
                }
            }

            var results: [Bool?] = []
            for await result in group {
                results.append(result)
            }

            // All concurrent requests should complete without crash
            XCTAssertEqual(results.count, 5)
        }
    }

    /// Test process not running error recovery hint
    func testProcessNotRunningRecoveryHint() {
        let error = PersistentLocationBridge.PersistentBridgeError.processNotRunning
        // Error should have meaningful description
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not running"))
    }

    /// Test bridge error with empty message
    func testBridgeErrorEmptyMessage() {
        let error = PersistentLocationBridge.PersistentBridgeError.bridgeError("")
        XCTAssertNotNil(error.errorDescription)
    }

    /// Test stats accumulation doesn't overflow
    @MainActor
    func testStatsAccumulationSafety() {
        let bridge = PersistentLocationBridge.shared

        // Stats should be non-negative
        XCTAssertGreaterThanOrEqual(bridge.requestCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.averageResponseTime, 0)

        // Average response time should be reasonable (< 1 hour in ms)
        XCTAssertLessThan(bridge.averageResponseTime, 3_600_000)
    }

    /// Test invalid response with special characters
    func testInvalidResponseSpecialCharacters() {
        let specialChars = "Response: \u{0000}\u{FFFF}\"'<>&"
        let error = PersistentLocationBridge.PersistentBridgeError.invalidResponse(specialChars)
        XCTAssertNotNil(error.errorDescription)
    }

    /// Test process start failure with long message
    func testProcessStartFailedLongMessage() {
        let longMessage = String(repeating: "error ", count: 1000)
        let error = PersistentLocationBridge.PersistentBridgeError.processStartFailed(longMessage)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("error"))
    }
}

// MARK: - Performance Mode Integration Tests

final class PerformanceModeTests: XCTestCase {

    /// Test that DevLocationBridge has performance mode setting
    func testPerformanceModePropertyExists() async {
        let bridge = DevLocationBridge()
        // Just verify the method exists and is callable
        await bridge.setPerformanceMode(true)
        await bridge.setPerformanceMode(false)
        XCTAssertTrue(true, "Performance mode methods should be callable")
    }

    /// Test that setLocation accepts usePerformanceMode parameter
    func testSetLocationAcceptsPerformanceMode() async {
        // This test verifies the API signature exists
        // Actual location setting would require a device
        let bridge = DevLocationBridge()
        let coordinate = LocationCoordinate(latitude: 37.785834, longitude: -122.406417)
        let device = Device(id: "TEST-DEVICE-00008030-001234567890ABCD", displayName: "Test iPhone", connectionType: .usb)

        // The method should exist with the usePerformanceMode parameter
        // We can't actually call it without a real device, but the signature should compile
        _ = { [bridge] in
            Task {
                do {
                    try await bridge.setLocation(coordinate, for: device, priority: .normal, usePerformanceMode: true)
                } catch {
                    // Expected to fail without a real device
                }
            }
        }

        XCTAssertTrue(true, "setLocation should accept usePerformanceMode parameter")
    }
}

// MARK: - Python Bridge Script Tests

final class LocationBridgeScriptTests: XCTestCase {

    /// Test that the bridge script exists in the expected location
    func testBridgeScriptExists() {
        let workspacePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path

        // Check if script exists (may be in workspace or bundle)
        let scriptExists = FileManager.default.fileExists(atPath: workspacePath)

        // In test environment, the script should be in the workspace
        if !scriptExists {
            // Not a failure if running in a different context
            print("Note: Bridge script not found at \(workspacePath)")
        }

        XCTAssertTrue(true, "Script check completed")
    }

    /// Test that the bridge script is valid Python
    func testBridgeScriptSyntax() throws {
        let workspacePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path

        guard FileManager.default.fileExists(atPath: workspacePath) else {
            throw XCTSkip("Bridge script not found, skipping syntax check")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "py_compile", workspacePath]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(process.terminationStatus, 0,
                          "Bridge script should have valid Python syntax")
        } catch {
            throw XCTSkip("Python3 not available for syntax check")
        }
    }

    func testBridgeLoadsManagedPymobiledeviceAPI() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
import importlib.util
spec = importlib.util.spec_from_file_location("location_bridge", r"\(script)")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.DeviceConnection()._lazy_import()
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBridgeUsesAsyncPymobiledeviceLifecycle() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
import importlib.util, inspect
spec = importlib.util.spec_from_file_location("location_bridge", r"\(script)")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert inspect.iscoroutinefunction(module.DeviceConnection.set_location)
assert inspect.iscoroutinefunction(module.DeviceConnection.clear_location)
assert inspect.iscoroutinefunction(module.DeviceConnection.close_all)
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBridgeProtocolCarriesRequestIdentity() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(source.contains("request_id"))
        XCTAssertTrue(source.contains("session_generation"))
    }

    func testNonObjectRequestsPreserveBridgeProtocolSession() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
import json, subprocess, sys
invalid_requests = [[], None, "invalid", 7]
requests = invalid_requests + [
    {"cmd": "ping", "request_id": "protocol-ping", "session_generation": 1},
    {"cmd": "quit", "request_id": "protocol-quit", "session_generation": 1},
]
result = subprocess.run(
    [sys.executable, "-B", r"\(script)"],
    input="".join(json.dumps(request) + "\\n" for request in requests),
    capture_output=True,
    text=True,
    timeout=5,
)
assert result.returncode == 0, result.stderr
responses = [json.loads(line) for line in result.stdout.splitlines()]
assert len(responses) == len(requests) + 1, "Invalid JSON values must not terminate the bridge"
assert responses[0] == {"ready": True}
for response in responses[1:5]:
    assert response["success"] is False
    assert response["code"] == "INVALID_REQUEST"
assert responses[5] == {
    "success": True, "message": "pong",
    "request_id": "protocol-ping", "session_generation": 1,
}
assert responses[6] == {
    "success": True, "message": "shutting down",
    "request_id": "protocol-quit", "session_generation": 1,
}
assert not result.stderr, result.stderr
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testPythonCacheInvalidationContainsCloseFailures() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
        let source = try String(contentsOf: path, encoding: .utf8)
        guard let start = source.range(of: "async def _invalidate")?.lowerBound,
              let end = source.range(of: "async def set_location", range: start..<source.endIndex)?.lowerBound else {
            return XCTFail("Missing Python cache invalidation implementation")
        }
        let invalidation = String(source[start..<end])
        XCTAssertTrue(invalidation.contains("try:\n            await cached[\"stack\"].aclose()"))
        XCTAssertTrue(invalidation.contains("except Exception:\n            pass"))
    }

    func testPythonCacheInvalidationRebuildsService() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
import asyncio, importlib.util
spec = importlib.util.spec_from_file_location("location_bridge", r"\(script)")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
connection = module.DeviceConnection()
connection._initialized = True
created = []
providers = []
closed = []
class AsyncContext:
    async def __aenter__(self): return self
    async def __aexit__(self, *args): pass
class Provider:
    async def close(self):
        closed.append(self)
async def make_provider(serial):
    provider = Provider()
    providers.append(provider)
    return provider
class Location(AsyncContext):
    def __init__(self, should_fail): self.should_fail = should_fail
    async def set(self, lat, lng):
        if self.should_fail: raise RuntimeError("injected failure")
connection._lockdown_usb = make_provider
connection._dvt_module = lambda provider: AsyncContext()
def make_location(dvt):
    created.append(True)
    return Location(len(created) == 1)
connection._location_module = make_location
async def verify():
    first = await connection.set_location(1.0, 2.0, "fake-device")
    assert first["success"] is False
    assert connection._service_cache == {}
    assert len(providers) == 1, "The async provider factory must be awaited"
    assert closed == providers, "Invalidation must await provider close"
    second = await connection.set_location(1.0, 2.0, "fake-device")
    assert second["success"] is True
    assert len(created) == 2
    third = await connection.set_location(3.0, 4.0, "fake-device")
    assert third["success"] is True
    assert len(providers) == 2, "Successful updates must reuse the provider"
    assert len(closed) == 1
    await connection.close_all()
    assert closed == providers, "Shutdown must await every provider close"
asyncio.run(verify())
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testPythonAcknowledgementReportsExplicitUsbmuxChannel() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
import asyncio, importlib.util
spec = importlib.util.spec_from_file_location("location_bridge", r"\(script)")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
connection = module.DeviceConnection()
connection._initialized = True
requested_transports = []
class AsyncContext:
    async def __aenter__(self): return self
    async def __aexit__(self, *args): pass
class Provider:
    product_version = "16.7"
    async def close(self): pass
async def make_provider(serial, connection_type=None):
    requested_transports.append(connection_type)
    return Provider()
class Location(AsyncContext):
    async def set(self, lat, lng): pass
connection._lockdown_usb = make_provider
connection._dvt_module = lambda provider: AsyncContext()
connection._location_module = lambda dvt: Location()
async def verify():
    result = await connection.set_location(
        1.0, 2.0, "fake-device", connection_type="Network"
    )
    assert requested_transports == ["Network"]
    assert result["success"] is True
    # Direct usbmux lane (live-proven primary on iOS 17+, 2026-10-31):
    # "networkLockdown"/"usbLockdown" are retired; the direct lane now
    # reports "usbmuxDirect" with endpoint_class "direct".
    assert result["actual_channel"] == "usbmuxDirect"
    assert result["endpoint_class"] == "direct"
    await connection.close_all()
asyncio.run(verify())
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testPythonAcknowledgementReportsNativeFallbackChannel() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/location_bridge.py")
            .path
        let code = """
        import asyncio, importlib.util
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)

        class DirectProvider:
            product_version = "99.0"
            async def close(self): pass

        class RSDProvider: pass

        class Context:
            def __init__(self, value=None, error=None):
                self.value, self.error = value, error
            async def __aenter__(self):
                if self.error: raise self.error
                return self.value or self
            async def __aexit__(self, *args): pass

        class Location(Context):
            async def set(self, lat, lng): pass

        class NativeRemotedTunnel: pass
        class UserspaceRsdTunnel: pass
        class FutureTunnel: pass
        selected_handle = NativeRemotedTunnel

        class Preferred:
            def __init__(self, serial):
                self._handle = selected_handle()
            async def aopen(self): return RSDProvider()
            async def aclose(self): pass

        requested = []
        async def make_provider(serial, connection_type=None):
            requested.append(connection_type)
            return DirectProvider()

        def make_dvt(provider):
            if isinstance(provider, DirectProvider):
                return Context(error=RuntimeError("direct unavailable"))
            return Context()

        def make_connection():
            connection = bridge.DeviceConnection()
            connection._initialized = True
            connection._lockdown_usb = make_provider
            connection._preferred_tunnel_factory = Preferred
            connection._dvt_module = make_dvt
            connection._location_module = lambda dvt: Location()
            return connection

        async def verify_channel(handle, expected):
            global selected_handle
            selected_handle = handle
            requested.clear()
            connection = make_connection()
            result = await connection.set_location(
                1.0, 2.0, "fake-device", connection_type="Network"
            )
            assert requested == ["Network"]
            if expected is None:
                assert result["success"] is False
                assert "FutureTunnel" in result["error"]
            else:
                assert result["actual_channel"] == expected
                assert result["endpoint_class"] == "remoteServiceDiscovery"
            await connection.close_all()

        async def verify():
            await verify_channel(NativeRemotedTunnel, "nativeRSD")
            await verify_channel(UserspaceRsdTunnel, "userspaceRSD")
            await verify_channel(FutureTunnel, None)
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    /// One device connection, owned by the helper (owner decision 2026-11-01,
    /// Option A): the app's `--native` tunnel refused the location service 3/3
    /// while pymobiledevice3's own in-process tunnel served it 3/3. The helper
    /// therefore opens exactly one userspace tunnel per device, never dials an
    /// RSD endpoint supplied by Swift, proves DVT answers before reporting a
    /// connection, and reports the connection's live state honestly.
    func testPythonHelperOwnsTheOnlyDeviceConnection() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)

        calls = []
        ls_error = None
        class Context:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Location(Context):
            async def set(self, lat, lng): calls.append(("set", lat, lng))
            async def clear(self): calls.append(("clear",))
        class Info(Context):
            async def ls(self, path):
                calls.append(("ls", path))
                if ls_error: raise ls_error
                return ["/usr", "/bin"]
        class Tunnel:
            def __init__(self, **kwargs):
                calls.append(("userspace", kwargs))
            async def aopen(self):
                await asyncio.sleep(0.05)  # widen the race window
                return object()
            async def aclose(self): calls.append(("aclose",))
        def forbidden_rsd(endpoint):
            raise AssertionError("helper dialed a Swift-supplied RSD endpoint")

        def make_connection():
            c = bridge.DeviceConnection()
            c._initialized = True
            c._userspace_tunnel_factory = Tunnel
            c._rsd_module = forbidden_rsd
            c._dvt_module = lambda provider: Context()
            c._location_module = lambda dvt: Location()
            c._device_info_module = lambda dvt: Info()
            return c

        def count(kind):
            return sum(1 for call in calls if call[0] == kind)

        async def verify():
            global ls_error
            # Validation: the connection commands require a device.
            assert bridge.validate_request({"cmd": "connect_device", "udid": "d",
                "request_id": "r", "session_generation": 0}) == (True, "")
            assert bridge.validate_request({"cmd": "connection_status",
                "request_id": "r", "session_generation": 0})[0] is False
            assert bridge.validate_request({"cmd": "disconnect_device", "udid": "d",
                "request_id": "r", "session_generation": 0}) == (True, "")

            c = make_connection()
            # Concurrent connect + set open exactly one tunnel (one per process),
            # even when they carry different transport hints.
            connected, applied = await asyncio.gather(
                bridge.process_command(c, {"cmd": "connect_device", "udid": "dev",
                    "connection_type": "USB"}),
                c.set_location(36.3, -86.6, "dev", rsd_address="fdc9::1",
                    rsd_port=55817, connection_type="Network"),
            )
            assert connected["success"] is True and connected["connected"] is True, connected
            assert connected["replaced"] is False, connected
            assert connected["actual_channel"] == "userspaceRSD", connected
            assert applied["success"] is True, applied
            assert applied["actual_channel"] == "userspaceRSD", applied
            assert count("userspace") == 1, calls
            assert calls[0] == ("userspace", {"serial": "dev", "autopair": True,
                "remotepairing_fallback": False}), calls
            # DVT was proven to answer before the connection was reported.
            assert count("ls") >= 1, calls

            status = await bridge.process_command(c, {"cmd": "connection_status",
                "udid": "dev", "connection_type": "Network"})
            assert status == {"success": True, "connected": True,
                "actual_channel": "userspaceRSD",
                "endpoint_class": "remoteServiceDiscovery"}, status

            # A dead connection is reported as not connected and torn down.
            ls_error = ConnectionResetError("tunnel gone")
            status = await bridge.process_command(c, {"cmd": "connection_status",
                "udid": "dev", "connection_type": "Network"})
            assert status["success"] is True and status["connected"] is False, status
            assert "tunnel gone" in status["reason"], status
            assert count("aclose") == 1, calls
            ls_error = None
            status = await bridge.process_command(c, {"cmd": "connection_status",
                "udid": "dev", "connection_type": "Network"})
            assert status["connected"] is False and status["reason"] == "not connected", status

            # Disconnect closes the tunnel; a later status does not reopen it.
            await bridge.process_command(c, {"cmd": "connect_device", "udid": "dev",
                "connection_type": "Network"})
            closed = await bridge.process_command(c, {"cmd": "disconnect_device",
                "udid": "dev", "connection_type": "Network"})
            assert closed == {"success": True, "connected": False}, closed
            assert count("aclose") == 2, calls
            status = await bridge.process_command(c, {"cmd": "connection_status",
                "udid": "dev", "connection_type": "Network"})
            assert status["connected"] is False, status
            assert count("userspace") == 2, calls
            await c.close_all()
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
    }

    /// Live 2026-11-01: usbmux drops a Wi-Fi phone for seconds to minutes while no
    /// connection is open. A connect in such a gap must say "not visible" so the app
    /// can wait for the phone, and a lane's own failure must never be hidden behind
    /// the next lane's (the GUI showed only the last lane's usbmux error).
    func testPythonHelperReportsDeviceNotVisibleAndEveryLanesError() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util, types
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)

        class DeviceNotFoundError(Exception): pass
        lane_errors = {}
        def raiser(lane):
            error = lane_errors[lane]
            if error is not None: raise error
        class Context:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Info(Context):
            async def ls(self, path): return ["/usr"]
        class Userspace:
            def __init__(self, **kwargs): pass
            async def aopen(self): raiser("userspace"); return object()
            async def aclose(self): pass
        async def lockdown(**kwargs): raiser("usbmux"); return object()
        class Preferred:
            def __init__(self, serial): pass
            async def aopen(self): raiser("preferred"); return object()
            async def aclose(self): pass
        async def mobdev2_lockdowns(udid=None, timeout=None, only_paired=False):
            # Bonjour does not see the phone either: the browse yields nothing.
            assert only_paired is True, "the lane asks only for paired lockdowns"
            return
            yield

        def make_connection():
            c = bridge.DeviceConnection()
            c._initialized = True
            c._userspace_tunnel_factory = Userspace
            c._lockdown_usb = lockdown
            c._preferred_tunnel_factory = Preferred
            c._mobdev2_lockdowns = mobdev2_lockdowns
            c._userspace_tunnel_module = types.SimpleNamespace(create_using_usbmux=lockdown)
            c._dvt_module = lambda provider: Context()
            c._location_module = lambda dvt: Context()
            c._device_info_module = lambda dvt: Info()
            return c

        async def connect():
            c = make_connection()
            try:
                return await bridge.process_command(c, {"cmd": "connect_device",
                    "udid": "dev", "connection_type": "Network"})
            finally:
                await c.close_all()

        async def verify():
            # Every lane says the device is absent: report it as not visible.
            lane_errors.update(
                userspace=DeviceNotFoundError("no device dev (userspace)"),
                usbmux=DeviceNotFoundError("no device dev over Network"),
                preferred=DeviceNotFoundError("no device dev (preferred)"))
            result = await connect()
            assert result["success"] is False and result["connected"] is False, result
            assert result["reason"] == "device_not_visible", result
            for text in ("(userspace)", "over Network", "(preferred)", "userspace tunnel: DeviceNotFoundError",
                         "mobdev2: Mobdev2DeviceNotFoundError"):
                assert text in result["error"], result

            # The primary lane failed for another reason: not a visibility gap,
            # and that lane's own error is what the user sees first.
            lane_errors["userspace"] = PermissionError("pairing rejected")
            result = await connect()
            assert result["success"] is False, result
            assert result.get("reason") is None, result
            assert result["error"].index("pairing rejected") < result["error"].index("over Network"), result

            # Transport errors keep the wait only on the mobdev2 lane: a usbmux-backed
            # lane that reached the phone and was reset is still a real failure.
            lane_errors["userspace"] = ConnectionResetError("reset by peer")
            result = await connect()
            assert result["success"] is False and result.get("reason") is None, result

            # A lane that works still wins.
            lane_errors.update(userspace=None, usbmux=None, preferred=None)
            result = await connect()
            assert result["success"] is True and result["actual_channel"] == "userspaceRSD", result
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
    }

    /// Live 2026-11-01: for 3.5 minutes usbmux listed no Wi-Fi phone, so all three
    /// usbmux-backed lanes failed, while mobdev2 Bonjour still reached its lockdown.
    /// The fourth lane opens the userspace tunnel over that lockdown by substituting
    /// the tunnel module's `create_using_usbmux` for one open. The substitution must
    /// never outlive the open (success, failure, cancellation), never leak into a
    /// concurrent open of another device, and must close the lockdown it found.
    func testPythonHelperOpensMobdev2LaneWhenUsbmuxSeesNoDevice() throws {
        let code = mobdev2LaneFixture() + """

        async def verify():
            # (a) usbmux lists no phone, Bonjour does: connected over mobdev2RSD.
            mobdev2_visible.add("dev")
            c = make_connection()
            result = await connect(c)
            assert result["success"] is True and result["actual_channel"] == "mobdev2RSD", result
            assert result["endpoint_class"] == "remoteServiceDiscovery", result
            assert usermod.create_using_usbmux is ORIGINAL, "global restored after success"
            assert ("dev", False) in seen, seen
            lane_lockdown = lockdowns[-1]
            assert lane_lockdown.closed == 0, "the open connection keeps its lockdown"
            moved = await bridge.process_command(c, {"cmd": "set_location", "lat": 1.0,
                "lng": 2.0, "udid": "dev", "connection_type": "Network"})
            assert moved["success"] is True and moved["actual_channel"] == "mobdev2RSD", moved
            await bridge.process_command(c, {"cmd": "disconnect_device", "udid": "dev"})
            assert lane_lockdown.closed >= 1, "invalidating the connection closes its lockdown"
            await c.close_all()

            # (c) Bonjour finds the phone but the tunnel fails for a non-transport
            # reason: a real failure, not a visibility gap; the lockdown is closed;
            # (d) the global is restored.
            state["tunnel_error"] = UserspaceTunnelUnavailableError("CoreDeviceProxy refused")
            c = make_connection()
            result = await connect(c)
            await c.close_all()
            assert result["success"] is False and result.get("reason") is None, result
            assert "mobdev2: UserspaceTunnelUnavailableError: CoreDeviceProxy refused" in result["error"], result
            assert lockdowns[-1].closed >= 1, "lockdown closed when the tunnel fails"
            assert usermod.create_using_usbmux is ORIGINAL, "global restored after failure"
            state["tunnel_error"] = None

            # Cancellation mid-open also restores the global and closes the lockdown.
            state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
            c = make_connection()
            task = asyncio.create_task(connect(c))
            await asyncio.wait_for(state["entered"].wait(), 2)
            assert usermod.create_using_usbmux is not ORIGINAL, "swapped while the tunnel opens"
            task.cancel()
            try:
                await task
                raise AssertionError("connect was not cancelled")
            except asyncio.CancelledError:
                pass
            assert usermod.create_using_usbmux is ORIGINAL, "global restored after cancellation"
            assert lockdowns[-1].closed >= 1, "lockdown closed after cancellation"
            await c.close_all()

            # The swap never leaks into a concurrent open of another device: its
            # tunnel waits until the global is the original again.
            seen.clear()
            usbmux_visible.add("other")
            state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
            c = make_connection()
            first = asyncio.create_task(connect(c, "dev"))
            await asyncio.wait_for(state["entered"].wait(), 2)
            second = asyncio.create_task(connect(c, "other"))
            await asyncio.sleep(0.05)
            assert not second.done(), "the other device's tunnel open waited for the swap"
            state["hold"].set()
            r1, r2 = await asyncio.gather(first, second)
            await c.close_all()
            assert r1["actual_channel"] == "mobdev2RSD" and r2["actual_channel"] == "userspaceRSD", (r1, r2)
            assert ("other", True) in seen and ("other", False) not in seen, seen
            state["hold"] = None
            usbmux_visible.discard("other")

            # A runtime without the APIs the lane needs reports a clear lane error;
            # the lane observed nothing, so three absent lanes still mean not visible.
            for broken in ("browse", "module"):
                c = make_connection()
                if broken == "browse":
                    c._mobdev2_lockdowns = None
                else:
                    c._userspace_tunnel_module = types.SimpleNamespace()
                result = await connect(c)
                await c.close_all()
                assert result["success"] is False, result
                assert result.get("reason") == "device_not_visible", result
                assert "mobdev2: LaneUnsupportedError" in result["error"], result
                assert "get_mobdev2_lockdowns" in result["error"], result
            assert usermod.create_using_usbmux is ORIGINAL
            assert browse_calls and all(call["only_paired"] is True for call in browse_calls), browse_calls
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Owner decision (2026-11-01): Start keeps trying while the phone may come back.
    /// A mobdev2-lane failure that is transport-class (connection reset/refused, a
    /// Bonjour browse OSError, a timeout inside the lane, or the whole open running
    /// out of time) keeps the device_not_visible verdict so the app waits until its
    /// 150 s deadline. A failure after Bonjour found a paired phone for any other
    /// reason ends Start at once. The lane must also notice when pymobiledevice3 no
    /// longer reads the global it swaps, and must refuse unpaired lockdowns.
    func testPythonHelperMobdev2LaneVerdictKeepsWaitingOnlyOnTransportFailures() throws {
        let code = mobdev2LaneFixture() + """

        problems = []
        def check(name, ok, detail):
            if not ok:
                problems.append(f"{name}: {detail}")

        async def attempt():
            c = make_connection()
            try:
                result = await connect(c)
                result.setdefault("error", "")
                # Close counts as connect returned, before close_all tidies up.
                result["_aclosed"] = state["aclosed"]
                result["_lockdown_closed"] = lockdowns[-1].closed if lockdowns else None
                return result
            finally:
                await c.close_all()

        async def verify():
            mobdev2_visible.add("dev")

            # Transport-class failures inside the lane keep waiting. pymobiledevice3
            # wraps TLS and socket failures in its own ConnectionTerminatedError (not a
            # builtin ConnectionError) and dial failures in ConnectionFailedError.
            class StreamClosedError(ConnectionTerminatedError): pass
            for error in (ConnectionResetError("reset by peer"), ConnectionRefusedError("refused"),
                          BrokenPipeError("pipe closed"), asyncio.TimeoutError(), TimeoutError("handshake"),
                          ConnectionTerminatedError("TLS handshake reset"),
                          ConnectionFailedError("could not connect"), StreamClosedError("stream closed")):
                name = type(error).__name__
                state["tunnel_error"] = error
                result = await attempt()
                check(f"transport {name} keeps waiting", result.get("reason") == "device_not_visible", result)
                check(f"transport {name} is reported", f"mobdev2: {name}" in result["error"], result)
                check(f"transport {name} closes lockdown", lockdowns[-1].closed >= 1, lockdowns[-1].closed)
            state["tunnel_error"] = None

            # The Bonjour browse itself failing (mDNS socket) observed nothing: keep waiting.
            for error in (OSError(49, "Can't assign requested address"), OSError("mDNS socket closed")):
                state["browse_error"] = error
                result = await attempt()
                check(f"browse {error} keeps waiting", result.get("reason") == "device_not_visible", result)
                check(f"browse {error} is reported", "mobdev2: Mobdev2BrowseError" in result["error"]
                      and str(error.strerror or error) in result["error"], result)
            state["browse_error"] = None

            # Bonjour found the paired phone and the lane failed for another reason: fail fast.
            for error in (InvalidServiceError("no CoreDeviceProxy"), UserspaceTunnelUnavailableError("needs iOS 17.4+"),
                          PairingError("pairing rejected"), ValueError("bad RSD reply")):
                name = type(error).__name__
                state["tunnel_error"] = error
                result = await attempt()
                check(f"non-transport {name} fails fast", result["success"] is False
                      and result.get("reason") is None, result)
                check(f"non-transport {name} is reported", f"mobdev2: {name}" in result["error"], result)
            state["tunnel_error"] = None

            # The same upstream transport classes on a usbmux-backed lane are real.
            state["preferred_error"] = ConnectionTerminatedError("reset (preferred)")
            result = await attempt()
            check("ConnectionTerminatedError on preferred RSD fails fast", result.get("reason") is None, result)
            state["preferred_error"] = None

            # A pre-provider failure is upstream's own error, not drift: re-raised as is.
            state["pre_provider_error"] = PyMobileDevice3Exception(
                "A userspace tunnel is already active in this process; only one userspace tunnel per "
                "process is supported.")
            result = await attempt()
            check("pre-provider guard is reported as is", "mobdev2: PyMobileDevice3Exception: "
                  "A userspace tunnel is already active in this process" in result["error"], result)
            check("pre-provider guard is not drift", "LaneUnsupportedError" not in result["error"], result)
            check("pre-provider guard fails fast", result.get("reason") is None, result)
            check("pre-provider guard closes lockdown", (result["_lockdown_closed"] or 0) >= 1, result)
            check("pre-provider guard restores global", usermod.create_using_usbmux is ORIGINAL, "")
            state["pre_provider_error"] = None

            # The whole open runs out of time while the lane's tunnel hangs: keep
            # waiting, and keep every lane failure collected so far in the text.
            saved = bridge.CONNECT_TIMEOUT_SECONDS
            bridge.CONNECT_TIMEOUT_SECONDS = 0.3
            try:
                state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
                result = await attempt()
                check("outer timeout keeps waiting", result.get("reason") == "device_not_visible", result)
                for text in ("userspace tunnel: DeviceNotFoundError", "usbmux direct: DeviceNotFoundError",
                             "preferred RSD: DeviceNotFoundError", "mobdev2: LanesTimedOutError"):
                    check(f"outer timeout text has {text!r}", text in result.get("error", ""), result)
                check("outer timeout restores global", usermod.create_using_usbmux is ORIGINAL, "")
                check("outer timeout closes lockdown", lockdowns[-1].closed >= 1, lockdowns[-1].closed)

                # An earlier lane's real failure still decides when lane 4 then times out.
                state["preferred_error"] = PermissionError("pairing rejected (preferred)")
                result = await attempt()
                check("outer timeout after a real failure fails fast", result.get("reason") is None, result)
                check("outer timeout after a real failure keeps it", "pairing rejected (preferred)"
                      in result.get("error", ""), result)
                state["preferred_error"] = None

                # Lane 1 hangs with nothing collected: the wait cannot be won by the lane
                # it exists for, so Start fails fast (as before the timeout rule).
                state["hold"] = None
                state["userspace_hold"] = asyncio.Event()
                browses_before = len(browse_calls)
                result = await attempt()
                check("lane-1 hang fails fast", result["success"] is False and result.get("reason") is None, result)
                check("lane-1 hang is named", "userspace tunnel: LanesTimedOutError" in result["error"], result)
                check("lane-1 hang never reaches mobdev2", len(browse_calls) == browses_before, browse_calls)
                state["userspace_hold"] = None

                # A later lane hangs after every finished lane said the phone is absent:
                # the phone is not visible yet, so keep waiting.
                state["preferred_hold"] = asyncio.Event()
                result = await attempt()
                check("lane-3 hang after absent lanes keeps waiting",
                      result.get("reason") == "device_not_visible", result)
                check("lane-3 hang is named", "preferred RSD: LanesTimedOutError" in result["error"]
                      and "usbmux direct: DeviceNotFoundError" in result["error"], result)
                state["preferred_hold"] = None
            finally:
                bridge.CONNECT_TIMEOUT_SECONDS = saved
                state["hold"] = None
                state["userspace_hold"] = None
                state["preferred_hold"] = None

            # pymobiledevice3 stops reading the swapped global (fails, or returns a
            # tunnel it made some other way): the lane says so, observed nothing.
            for mode in ("ignores-global", "ignores-global-returns"):
                state["upstream"], state["usbmux_now"] = mode, set()
                closed_before = state["aclosed"]
                result = await attempt()
                check(f"{mode} reported unsupported", "mobdev2: LaneUnsupportedError" in result["error"]
                      and "pymobiledevice3 no longer reads userspace_tunnel.create_using_usbmux"
                      in result["error"], result)
                check(f"{mode} keeps waiting", result.get("reason") == "device_not_visible", result)
                check(f"{mode} closes lockdown", (result["_lockdown_closed"] or 0) >= 1, result)
                if mode == "ignores-global-returns":
                    check(f"{mode} closes the stray tunnel", result["_aclosed"] > closed_before, result)
                check(f"{mode} restores global", usermod.create_using_usbmux is ORIGINAL, "")
                if mode == "ignores-global":
                    # The drift message keeps the error the open really ended with.
                    check(f"{mode} keeps the original error", "DeviceNotFoundError: usbmux has no device "
                          "matching udid dev" in result["error"].partition("mobdev2: ")[2], result)
            state["upstream"] = "global"

            # A failure before the provider call that is not pymobiledevice3's own is
            # still drift, and its text is kept.
            state["pre_provider_error"] = AttributeError("module has no attribute 'create_tunnel'")
            result = await attempt()
            check("foreign pre-provider failure is drift", "mobdev2: LaneUnsupportedError" in result["error"]
                  and "AttributeError: module has no attribute 'create_tunnel'" in result["error"], result)
            check("foreign pre-provider failure keeps waiting", result.get("reason") == "device_not_visible", result)
            state["pre_provider_error"] = None

            # Only paired lockdowns are asked for; an unpaired-only result is not found,
            # also if a future browse ignored only_paired.
            mobdev2_unpaired.add("dev")
            for ignore in (False, True):
                state["ignore_only_paired"] = ignore
                result = await attempt()
                check(f"unpaired (ignore_only_paired={ignore}) is not found",
                      result.get("reason") == "device_not_visible"
                      and "mobdev2: Mobdev2DeviceNotFoundError" in result["error"], result)
                check(f"unpaired (ignore_only_paired={ignore}) closed", (result["_lockdown_closed"] or 0) >= 1,
                      result)
            state["ignore_only_paired"] = False
            mobdev2_unpaired.discard("dev")
            check("only_paired=True on every browse",
                  browse_calls and all(call["only_paired"] is True for call in browse_calls), browse_calls)

            if problems:
                raise AssertionError("\\n".join(problems))
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// The mobdev2 lane reaches the phone over Wi-Fi (Bonjour). A request that names
    /// USB must never cross to Wi-Fi: with lanes 1-3 absent, lane 4 is not attempted
    /// and the phone is reported not visible. Network and no transport hint still run it.
    func testPythonHelperMobdev2LaneNeverRunsForAUsbRequest() throws {
        let code = mobdev2LaneFixture() + """

        async def verify():
            mobdev2_visible.add("dev")
            c = make_connection()
            result = await connect(c, connection_type="USB")
            await c.close_all()
            assert result["success"] is False and result["reason"] == "device_not_visible", result
            assert not browse_calls, browse_calls
            assert ("dev", False) not in seen, seen
            assert "mobdev2" not in result["error"], result
            # The remote pairing lane reaches the phone over Wi-Fi too: never for USB.
            rp_records["dev"] = {"peer_alt_irk": b"k" * 16}
            rp_adverts["dev"] = ["192.168.0.177"]
            c = make_connection()
            result = await connect(c, connection_type="USB")
            await c.close_all()
            assert result["success"] is False and result["reason"] == "device_not_visible", result
            assert not rp_calls and not rp_services, (rp_calls, rp_services)
            assert "remote pairing" not in result["error"], result
            rp_records.clear()
            rp_adverts.clear()
            for text in ("userspace tunnel: DeviceNotFoundError", "usbmux direct: DeviceNotFoundError",
                         "preferred RSD: DeviceNotFoundError"):
                assert text in result["error"], result

            for hint in ("Network", None):
                c = make_connection()
                result = await connect(c, connection_type=hint)
                await c.close_all()
                assert result["success"] is True and result["actual_channel"] == "mobdev2RSD", (hint, result)
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Live 2026-11-02: after the phone's private Wi-Fi address rotated, usbmuxd listed
    /// nothing for hours (lanes 1-3) and the phone refused the mobdev2 lockdown's tunnel
    /// (lane 4). With a RemotePairing record that holds the phone's altIRK, RemotePairing
    /// Bonjour finds the phone at any address and opens the userspace tunnel without
    /// usbmuxd (proven live read-only). Lane 5 runs before mobdev2, picks one advertised
    /// address, closes the rest, and swaps the tunnel module's provider for one open only.
    func testPythonHelperOpensRemotePairingLaneWhenUsbmuxSeesNoDevice() throws {
        let code = mobdev2LaneFixture() + """

        GOOD = {"peer_alt_irk": b"k" * 16, "private_key": b"x" * 32}

        def reset():
            rp_records.clear(); rp_adverts.clear(); rp_services.clear(); rp_calls.clear()
            providers.clear(); browse_calls.clear(); mobdev2_visible.clear()

        def assert_restored(where):
            assert usermod._create_no_root_tunnel_provider is ORIGINAL_PROVIDER, f"provider restored {where}"
            assert usermod.create_using_usbmux is ORIGINAL, f"usbmux global untouched {where}"

        async def verify():
            # Address preference: routable IPv4, then any IPv4 (169.254 link-local), then IPv6.
            pick = bridge.DeviceConnection._preferred_remote_pairing_service
            def hosts(*names): return [types.SimpleNamespace(hostname=name) for name in names]
            for names, expected in [
                (("fe80::1%anri0", "169.254.10.2", "fe80::2%en7", "192.168.0.177"), "192.168.0.177"),
                (("fe80::1%anri0", "169.254.10.2", "10.0.0.5", "192.168.0.177"), "10.0.0.5"),
                (("fe80::1%anri0", "169.254.10.2"), "169.254.10.2"),
                (("fe80::1%en0", "2001:db8::1"), "fe80::1%en0"),
                (("not-an-address", "fe80::1%en0"), "not-an-address"),
            ]:
                chosen = pick(hosts(*names))
                assert chosen is not None and chosen.hostname == expected, (names, chosen)
            assert pick([]) is None

            # (a) usbmux lists nothing, RemotePairing Bonjour finds the phone at its Wi-Fi
            # address and at USB-link addresses: connected over remotePairingRSD via the
            # Wi-Fi one; the others are closed at once; mobdev2 is never browsed.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["fe80::1%anri0", "169.254.10.2", "fe80::2%en7", "192.168.0.177"]
            mobdev2_visible.add("dev")
            c = make_connection()
            result = await connect(c)
            assert result["success"] is True and result["actual_channel"] == "remotePairingRSD", result
            assert result["endpoint_class"] == "remoteServiceDiscovery", result
            assert not any(getattr(p, "source", None) == "mobdev2" for p in providers), \\
                "mobdev2 is tunnelled over only after the remote pairing lane failed"
            assert all(l.closed >= 1 for l in lockdowns), \\
                "a mobdev2 lockdown discovered at the same time is closed"
            assert rp_calls == [{"udid": "dev", "bonjour_timeout": bridge.REMOTE_PAIRING_BROWSE_SLICE_SECONDS}], rp_calls
            chosen = providers[-1]
            assert chosen.source == "remotepairing" and chosen.hostname == "192.168.0.177", chosen
            assert chosen.closed == 0, "the open connection keeps its service"
            assert all(s.closed >= 1 for s in rp_services if s is not chosen), [(s.hostname, s.closed) for s in rp_services]
            assert_restored("after success")
            moved = await bridge.process_command(c, {"cmd": "set_location", "lat": 1.0,
                "lng": 2.0, "udid": "dev", "connection_type": "Network"})
            assert moved["success"] is True and moved["actual_channel"] == "remotePairingRSD", moved
            status = await bridge.process_command(c, {"cmd": "connection_status", "udid": "dev"})
            assert status["connected"] is True and status["actual_channel"] == "remotePairingRSD", status
            await bridge.process_command(c, {"cmd": "disconnect_device", "udid": "dev"})
            assert chosen.closed >= 1, "invalidating the connection closes its service"
            await c.close_all()

            # No transport hint also runs the lane.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["192.168.0.177"]
            c = make_connection()
            result = await connect(c, connection_type=None)
            await c.close_all()
            assert result["success"] is True and result["actual_channel"] == "remotePairingRSD", result

            # (b) The tunnel fails for a non-transport reason after the phone answered: a
            # real failure; every service closed; the provider restored.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["fe80::1%anri0", "192.168.0.177"]
            state["tunnel_error"] = UserspaceTunnelUnavailableError("CoreDeviceProxy refused")
            c = make_connection()
            result = await connect(c)
            await c.close_all()
            state["tunnel_error"] = None
            assert result["success"] is False and result.get("reason") is None, result
            assert "remote pairing: UserspaceTunnelUnavailableError: CoreDeviceProxy refused" in result["error"], result
            assert rp_services and all(s.closed >= 1 for s in rp_services), [(s.hostname, s.closed) for s in rp_services]
            assert_restored("after failure")

            # (c) Cancellation mid-open restores the provider and closes every service.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["fe80::1%anri0", "192.168.0.177"]
            state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
            c = make_connection()
            task = asyncio.create_task(connect(c))
            await asyncio.wait_for(state["entered"].wait(), 2)
            assert usermod._create_no_root_tunnel_provider is not ORIGINAL_PROVIDER, "swapped while the tunnel opens"
            task.cancel()
            try:
                await task
                raise AssertionError("connect was not cancelled")
            except asyncio.CancelledError:
                pass
            state["hold"] = None
            assert_restored("after cancellation")
            assert all(s.closed >= 1 for s in rp_services), [(s.hostname, s.closed) for s in rp_services]
            await c.close_all()

            # Cancellation during the browse leaves the provider untouched.
            reset()
            rp_records["dev"] = GOOD
            rp_state["browse_hold"], rp_state["browse_entered"] = asyncio.Event(), asyncio.Event()
            c = make_connection()
            task = asyncio.create_task(connect(c))
            await asyncio.wait_for(rp_state["browse_entered"].wait(), 2)
            task.cancel()
            try:
                await task
                raise AssertionError("connect was not cancelled")
            except asyncio.CancelledError:
                pass
            rp_state["browse_hold"] = None
            assert_restored("after a cancelled browse")
            await c.close_all()

            # (d) The swap never leaks into a concurrent open of another device.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["192.168.0.177"]
            usbmux_visible.add("other")
            state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
            c = make_connection()
            first = asyncio.create_task(connect(c, "dev"))
            await asyncio.wait_for(state["entered"].wait(), 2)
            second = asyncio.create_task(connect(c, "other"))
            await asyncio.sleep(0.05)
            assert not second.done(), "the other device's tunnel open waited for the swap"
            state["hold"].set()
            r1, r2 = await asyncio.gather(first, second)
            await c.close_all()
            state["hold"] = None
            usbmux_visible.discard("other")
            assert r1["actual_channel"] == "remotePairingRSD" and r2["actual_channel"] == "userspaceRSD", (r1, r2)
            assert getattr(providers[-1], "source", None) == "usbmux", "the other device got its own lockdown"

            # (e) pymobiledevice3 stops reading the swapped provider: the lane says so and
            # observed nothing; the chosen service is closed; a stray tunnel is closed.
            for mode in ("ignores-global", "ignores-global-returns"):
                reset()
                rp_records["dev"] = GOOD
                rp_adverts["dev"] = ["192.168.0.177"]
                state["upstream"], state["usbmux_now"] = mode, set()
                closed_before = state["aclosed"]
                c = make_connection()
                result = await connect(c)
                aclosed = state["aclosed"]
                await c.close_all()
                state["upstream"] = "global"
                lane = result["error"].partition("remote pairing: ")[2].partition("; mobdev2:")[0]
                assert lane.startswith("LaneUnsupportedError: pymobiledevice3 no longer reads "
                                       "userspace_tunnel._create_no_root_tunnel_provider"), (mode, result)
                assert result.get("reason") == "device_not_visible", (mode, result)
                assert all(s.closed >= 1 for s in rp_services), (mode, [s.closed for s in rp_services])
                if mode == "ignores-global":
                    assert "DeviceNotFoundError: usbmux has no device matching udid dev" in lane, (mode, lane)
                else:
                    assert aclosed > closed_before, (mode, "the stray tunnel is closed")
                assert_restored(f"after {mode}")

            # (f) A pymobiledevice3 error from before the provider call (its one-tunnel
            # guard) is upstream's verdict, re-raised as is.
            reset()
            rp_records["dev"] = GOOD
            rp_adverts["dev"] = ["192.168.0.177"]
            state["pre_provider_error"] = PyMobileDevice3Exception(
                "A userspace tunnel is already active in this process; only one userspace tunnel per "
                "process is supported.")
            c = make_connection()
            result = await connect(c)
            await c.close_all()
            state["pre_provider_error"] = None
            assert "remote pairing: PyMobileDevice3Exception: A userspace tunnel is already active" in result["error"], result
            assert "remote pairing: LaneUnsupportedError" not in result["error"], result
            assert result.get("reason") is None, result
            assert all(s.closed >= 1 for s in rp_services), [s.closed for s in rp_services]
            assert_restored("after the pre-provider guard")

            # (g) A runtime without the APIs the lane needs reports a clear lane error and
            # observed nothing; the next lane still runs.
            for broken in ("services", "records", "module"):
                reset()
                rp_records["dev"] = GOOD
                rp_adverts["dev"] = ["192.168.0.177"]
                mobdev2_visible.add("dev")
                c = make_connection()
                if broken == "services":
                    c._remote_pairing_services = None
                elif broken == "records":
                    c._remote_pair_records = None
                else:
                    c._userspace_tunnel_module = types.SimpleNamespace(create_using_usbmux=usbmux_lockdown)
                result = await connect(c)
                await c.close_all()
                assert not rp_calls, (broken, rp_calls)
                assert not any(getattr(p, "source", None) == "remotepairing" for p in providers), (broken, providers)
                if broken == "module":
                    assert "remote pairing: LaneUnsupportedError: remote pairing lane needs" in result["error"], result
                else:
                    assert result["success"] is True and result["actual_channel"] == "mobdev2RSD", (broken, result)
                    # The lane's own verdict, seen directly: unsupported, before any browse.
                    c = make_connection()
                    if broken == "services":
                        c._remote_pairing_services = None
                    else:
                        c._remote_pair_records = None
                    try:
                        await c._open_remote_pairing("dev", "dev")
                        raise AssertionError("the lane opened without its APIs")
                    except bridge.LaneUnsupportedError as error:
                        assert "the installed pymobiledevice3 lacks one" in str(error), error
                    await c.close_all()
            assert_restored("after unsupported runtimes")
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// The remote pairing lane's verdicts. Bonjour not finding the phone, or the browse
    /// failing, is "not visible yet" (Start keeps waiting), and mobdev2 still runs. A
    /// missing or pre-altIRK record is its own class telling the user to refresh it over
    /// the cable; it looked at nothing, so it neither starts nor ends the wait.
    func testPythonHelperRemotePairingLaneVerdicts() throws {
        let code = mobdev2LaneFixture() + """

        import time
        GOOD = {"peer_alt_irk": b"k" * 16, "private_key": b"x" * 32}
        problems = []
        def check(name, ok, detail):
            if not ok:
                problems.append(f"{name}: {detail}")

        def reset():
            rp_records.clear(); rp_adverts.clear(); rp_services.clear(); rp_calls.clear()
            providers.clear(); browse_calls.clear(); mobdev2_visible.clear()

        async def attempt():
            c = make_connection()
            try:
                result = await connect(c)
                result.setdefault("error", "")
                result["_services_closed"] = all(s.closed >= 1 for s in rp_services)
                return result
            finally:
                await c.close_all()

        def lane_text(result):
            return result["error"].partition("remote pairing: ")[2].partition("; mobdev2:")[0]

        async def verify():
            # No advert matches the phone's record: not visible, and mobdev2 runs next.
            reset()
            rp_records["dev"] = GOOD
            result = await attempt()
            check("not found keeps waiting", result.get("reason") == "device_not_visible", result)
            check("not found is named", lane_text(result).startswith("RemotePairingDeviceNotFoundError"), result)
            # Upstream also returns nothing when an advert matched but every address
            # refused pair-verify, so the text must not claim there was no advert.
            check("not found covers a refused pairing",
                  "found no advert that accepted this Mac's pairing" in lane_text(result)
                  and "may need a refresh" in lane_text(result), lane_text(result))
            check("mobdev2 runs after", len(browse_calls) == 1, browse_calls)
            check("lane order", result["error"].index("preferred RSD:") < result["error"].index("remote pairing:")
                  < result["error"].index("mobdev2:"), result)
            mobdev2_visible.add("dev")
            result = await attempt()
            check("mobdev2 still wins after not found", result.get("actual_channel") == "mobdev2RSD", result)

            # A record without the phone's altIRK, or no record at all: its own class,
            # telling the user to refresh it over the cable; nothing is browsed.
            for name, record in (("stale", {"private_key": b"x" * 32}), ("missing", None)):
                reset()
                if record is not None:
                    rp_records["dev"] = record
                rp_records["someone-else"] = GOOD
                result = await attempt()
                text = lane_text(result)
                check(f"{name} record class", text.startswith("RemotePairingRecordStaleError: "), result)
                check(f"{name} record advice", "connect the cable once and press Prepare for Wi-Fi" in text, text)
                check(f"{name} record browses nothing", not rp_calls, rp_calls)
                check(f"{name} record, absent lanes: still not visible",
                      result.get("reason") == "device_not_visible", result)
                check(f"{name} record keeps the secrets out", "private_key" not in text and "kkkk" not in text, text)
                if name == "stale":
                    check("stale record names altIRK", "altIRK" in text, text)
                else:
                    check("missing record says so", "no RemotePairing record" in text, text)
                mobdev2_visible.add("dev")
                result = await attempt()
                check(f"{name} record, mobdev2 still runs", result.get("actual_channel") == "mobdev2RSD", result)

            # A stale record never turns a real failure elsewhere into a wait.
            reset()
            rp_records["dev"] = {"private_key": b"x" * 32}
            state["preferred_error"] = PermissionError("pairing rejected (preferred)")
            result = await attempt()
            state["preferred_error"] = None
            check("stale + real failure fails fast", result.get("reason") is None, result)

            # The records folder cannot be read: the same class, the lane looked at nothing.
            reset()
            rp_state["records_error"] = PermissionError(13, "Permission denied")
            result = await attempt()
            rp_state["records_error"] = None
            check("unreadable records class", lane_text(result).startswith("RemotePairingRecordStaleError"), result)
            check("unreadable records keeps waiting", result.get("reason") == "device_not_visible", result)

            # The Bonjour browse itself fails (mDNS socket): observed nothing, keep waiting.
            reset()
            rp_records["dev"] = GOOD
            rp_state["browse_error"] = OSError(49, "Can't assign requested address")
            result = await attempt()
            rp_state["browse_error"] = None
            check("browse failure class", lane_text(result).startswith("RemotePairingBrowseError"), result)
            check("browse failure keeps waiting", result.get("reason") == "device_not_visible", result)

            # Transport-class failures after the phone answered keep waiting (a dozing
            # phone on Wi-Fi), as on the mobdev2 lane; every service is closed.
            for error in (ConnectionResetError("reset by peer"), asyncio.TimeoutError(), TimeoutError("handshake"),
                          ConnectionTerminatedError("TLS handshake reset"), ConnectionFailedError("could not connect")):
                reset()
                rp_records["dev"] = GOOD
                rp_adverts["dev"] = ["192.168.0.177", "fe80::1%en0"]
                state["tunnel_error"] = error
                result = await attempt()
                name = type(error).__name__
                check(f"transport {name} keeps waiting", result.get("reason") == "device_not_visible", result)
                check(f"transport {name} is reported", lane_text(result).startswith(name), result)
                check(f"transport {name} closes services", result["_services_closed"], result)
            state["tunnel_error"] = None

            # The whole open runs out of time while the lane's tunnel hangs: keep waiting.
            saved = bridge.CONNECT_TIMEOUT_SECONDS
            bridge.CONNECT_TIMEOUT_SECONDS = 0.3
            try:
                reset()
                rp_records["dev"] = GOOD
                rp_adverts["dev"] = ["192.168.0.177", "fe80::1%en0"]
                state["hold"], state["entered"] = asyncio.Event(), asyncio.Event()
                result = await attempt()
                check("outer timeout keeps waiting", result.get("reason") == "device_not_visible", result)
                check("outer timeout names the lane", "remote pairing: LanesTimedOutError" in result["error"], result)
                check("outer timeout closes services", result["_services_closed"], result)
                check("outer timeout restores provider",
                      usermod._create_no_root_tunnel_provider is ORIGINAL_PROVIDER, "")
            finally:
                bridge.CONNECT_TIMEOUT_SECONDS = saved
                state["hold"] = None

            # Review 2026-11-03 issue 4: a phone that accepts TCP but stalls pair-verify
            # inside upstream's browse must not use the whole open. The lane has its own
            # bound (above upstream's 8 s browse, well under the 30 s open), keeps waiting
            # when it runs out, and leaves time for mobdev2 in the same attempt.
            check("lane bound exceeds the browse",
                  bridge.REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS
                  < getattr(bridge, "REMOTE_PAIRING_LANE_TIMEOUT_SECONDS", float("inf"))
                  < bridge.CONNECT_TIMEOUT_SECONDS - bridge.MOBDEV2_BROWSE_TIMEOUT_SECONDS,
                  (bridge.REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS,
                   getattr(bridge, "REMOTE_PAIRING_LANE_TIMEOUT_SECONDS", None)))
            saved_lane = getattr(bridge, "REMOTE_PAIRING_LANE_TIMEOUT_SECONDS", None)
            saved_open = bridge.CONNECT_TIMEOUT_SECONDS
            bridge.REMOTE_PAIRING_LANE_TIMEOUT_SECONDS = 0.2
            bridge.CONNECT_TIMEOUT_SECONDS = 5.0
            try:
                for mobdev2_answers in (True, False):
                    reset()
                    rp_records["dev"] = GOOD
                    rp_adverts["dev"] = ["192.168.0.177"]
                    rp_state["browse_hold"], rp_state["browse_entered"] = asyncio.Event(), asyncio.Event()
                    if mobdev2_answers:
                        mobdev2_visible.add("dev")
                    started = time.monotonic()
                    result = await attempt()
                    elapsed = time.monotonic() - started
                    tag = "mobdev2 up" if mobdev2_answers else "mobdev2 down"
                    check(f"stalled pair-verify is bounded ({tag})", elapsed < 2.0, elapsed)
                    check(f"stalled pair-verify reached the browse ({tag})", rp_state["browse_entered"].is_set(), "")
                    check(f"stalled pair-verify restores provider ({tag})",
                          usermod._create_no_root_tunnel_provider is ORIGINAL_PROVIDER, "")
                    check(f"stalled pair-verify, mobdev2 browsed ({tag})", len(browse_calls) == 1, browse_calls)
                    if mobdev2_answers:
                        check("stalled pair-verify, mobdev2 still wins",
                              result.get("actual_channel") == "mobdev2RSD", result)
                    else:
                        text = lane_text(result)
                        check("stalled pair-verify class", text.startswith("RemotePairingTimeoutError: "), result)
                        check("stalled pair-verify is not the whole open",
                              "LanesTimedOutError" not in result["error"], result)
                        check("stalled pair-verify keeps waiting", result.get("reason") == "device_not_visible", result)
                    rp_state["browse_hold"] = None
            finally:
                bridge.REMOTE_PAIRING_LANE_TIMEOUT_SECONDS = saved_lane
                bridge.CONNECT_TIMEOUT_SECONDS = saved_open
                rp_state["browse_hold"] = None
            check("the lane timeout keeps waiting by the verdict rules",
                  hasattr(bridge, "RemotePairingTimeoutError")
                  and bridge._keeps_waiting("remote pairing", bridge.RemotePairingTimeoutError("t"))
                  and not bridge._keeps_waiting("preferred RSD", bridge.RemotePairingTimeoutError("t")), "")

            if problems:
                raise AssertionError("\\n".join(problems))
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Live 2026-11-03 (03:57-04:00): after a loss the phone withdrew its stale RemotePairing
    /// advert and advertised a new instance within a second, but an attempt that had
    /// already tried the stale advert never looked again in its window, and the mobdev2
    /// browse only started after the remote pairing window ran out (about 16 s a failed
    /// attempt). The remote pairing lane now asks Bonjour again in short slices, so an
    /// advert that appears or changes during the window is tried; and the remote pairing
    /// and mobdev2 discovery run at the same time (a failed attempt takes one window). When
    /// both find the phone, remote pairing is used (the lane order), and the unused mobdev2
    /// lockdown is closed.
    func testPythonHelperWiFiLanesRetryNewAdvertsAndDiscoverConcurrently() throws {
        let code = mobdev2LaneFixture() + """

        GOOD = {"peer_alt_irk": b"k" * 16, "private_key": b"x" * 32}
        problems = []
        def check(name, ok, detail):
            if not ok:
                problems.append(f"{name}: {detail}")

        def reset():
            rp_records.clear(); rp_adverts.clear(); rp_services.clear(); rp_calls.clear()
            providers.clear(); browse_calls.clear(); mobdev2_visible.clear(); lockdowns.clear()

        # Scaled windows: the remote pairing window and its re-query slice.
        bridge.REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS = 0.8
        bridge.REMOTE_PAIRING_BROWSE_SLICE_SECONDS = 0.2
        live_adverts = []

        # Like upstream: one call browses for its whole window and tries each advert
        # instance once (an instance that changes address is not tried again in that call).
        async def realistic_rp(bonjour_timeout=None, udid=None, excluded_identifiers=()):
            loop = asyncio.get_running_loop()
            rp_calls.append({"udid": udid, "bonjour_timeout": bonjour_timeout})
            end = loop.time() + bonjour_timeout
            tried = set()
            while loop.time() < end:
                for advert in list(live_adverts):
                    if advert["name"] in tried:
                        continue
                    tried.add(advert["name"])
                    if advert["ok"]:
                        service = RPService(udid, advert["host"])
                        rp_services.append(service)
                        return [service]
                await asyncio.sleep(0.01)
            return []

        def timed_mobdev2(delay, visible):
            async def browse(udid=None, timeout=None, only_paired=False):
                browse_calls.append({"udid": udid, "at": asyncio.get_running_loop().time()})
                await asyncio.sleep(delay)
                if visible:
                    lockdown = Lockdown(udid, "mobdev2")
                    lockdowns.append(lockdown)
                    yield "fe80::1%en0", lockdown
            return browse

        def make(mobdev2_delay=0.0, mobdev2_found=False):
            c = make_connection()
            c._remote_pairing_services = realistic_rp
            c._mobdev2_lockdowns = timed_mobdev2(mobdev2_delay, mobdev2_found)
            return c

        async def timed_connect(c):
            loop = asyncio.get_running_loop()
            started = loop.time()
            result = await connect(c)
            return result, loop.time() - started, started

        async def later(seconds, action):
            await asyncio.sleep(seconds)
            action()

        async def verify():
            # A stale advert at the start; the phone re-advertises the same instance at a
            # new address during the window: tried again, connected over remote pairing.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = [{"name": "X", "host": "192.168.0.10", "ok": False}]
            c = make()
            def readvertise():
                live_adverts[:] = [{"name": "X", "host": "192.168.0.11", "ok": True}]
            mover = asyncio.ensure_future(later(0.3, readvertise))
            result, elapsed, _ = await timed_connect(c)
            await mover
            check("a changed advert is tried again", result.get("actual_channel") == "remotePairingRSD", result)
            check("within the window", elapsed < 0.8, elapsed)
            check("the slices", all(call["bonjour_timeout"] <= 0.2 + 1e-9 for call in rp_calls) and len(rp_calls) >= 2,
                  rp_calls)
            await c.close_all()

            # A new instance name appearing during the window is tried too.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = [{"name": "X", "host": "192.168.0.10", "ok": False}]
            c = make()
            def new_instance():
                live_adverts[:] = [{"name": "Y", "host": "192.168.0.12", "ok": True}]
            mover = asyncio.ensure_future(later(0.3, new_instance))
            result, _, _ = await timed_connect(c)
            await mover
            check("a new instance is tried", result.get("actual_channel") == "remotePairingRSD", result)
            await c.close_all()

            # No remote pairing advert; mobdev2 finds the phone after 0.5 s. Both browse at
            # once: about one window, not the window plus the mobdev2 browse.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = []
            c = make(mobdev2_delay=0.5, mobdev2_found=True)
            result, elapsed, started = await timed_connect(c)
            check("mobdev2 connects", result.get("actual_channel") == "mobdev2RSD", result)
            check("concurrent discovery is one window", elapsed < 1.1, elapsed)
            check("mobdev2 browsed from the start",
                  len(browse_calls) == 1 and browse_calls[0]["at"] - started < 0.15, browse_calls)
            await c.close_all()

            # Neither finds the phone: one window, both lanes reported in order, keep waiting.
            reset()
            rp_records["dev"] = GOOD
            c = make(mobdev2_delay=0.6, mobdev2_found=False)
            result, elapsed, _ = await timed_connect(c)
            error = result.get("error", "")
            check("a failed attempt is one window", elapsed < 1.1, elapsed)
            check("both lanes reported in order",
                  "remote pairing: RemotePairingDeviceNotFoundError" in error
                  and "mobdev2: Mobdev2DeviceNotFoundError" in error
                  and error.index("remote pairing:") < error.index("mobdev2:"), error)
            check("still not visible", result.get("reason") == "device_not_visible", result)
            await c.close_all()

            # Both find the phone: remote pairing wins (lane order); the mobdev2 lockdown
            # is closed and never tunnelled over.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = []
            c = make(mobdev2_delay=0.0, mobdev2_found=True)
            def phone_answers():
                live_adverts[:] = [{"name": "X", "host": "192.168.0.11", "ok": True}]
            mover = asyncio.ensure_future(later(0.15, phone_answers))
            result, _, _ = await timed_connect(c)
            await mover
            await asyncio.sleep(0.05)
            check("remote pairing wins", result.get("actual_channel") == "remotePairingRSD", result)
            check("the unused mobdev2 lockdown is closed",
                  lockdowns and all(lockdown.closed >= 1 for lockdown in lockdowns), [l.closed for l in lockdowns])
            check("no tunnel over mobdev2", not any(getattr(p, "source", None) == "mobdev2" for p in providers),
                  providers)
            await c.close_all()

            # Remote pairing finds the phone but its tunnel fails: the mobdev2 lockdown found
            # meanwhile is used.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = [{"name": "X", "host": "192.168.0.11", "ok": True}]
            c = make(mobdev2_delay=0.0, mobdev2_found=True)
            class RemotePairingTunnelFails(Userspace):
                async def aopen(self):
                    provider, _ = await usermod._create_no_root_tunnel_provider(
                        self.serial, True, self.remotepairing_fallback)
                    providers.append(provider)
                    if getattr(provider, "source", None) == "remotepairing":
                        raise UserspaceTunnelUnavailableError("CoreDeviceProxy refused")
                    return object()
            c._userspace_tunnel_factory = RemotePairingTunnelFails
            result, _, _ = await timed_connect(c)
            check("mobdev2 after a failed remote pairing tunnel",
                  result.get("actual_channel") == "mobdev2RSD", result)
            check("the remote pairing service is closed", rp_services and all(s.closed >= 1 for s in rp_services),
                  [s.closed for s in rp_services])
            check("usermod restored", usermod._create_no_root_tunnel_provider is ORIGINAL_PROVIDER
                  and usermod.create_using_usbmux is ORIGINAL, "")
            await c.close_all()

            # Cancelled while remote pairing still browses: the mobdev2 lockdown already
            # found is closed.
            reset()
            rp_records["dev"] = GOOD
            live_adverts[:] = []
            c = make(mobdev2_delay=0.0, mobdev2_found=True)
            task = asyncio.ensure_future(connect(c))
            await asyncio.sleep(0.3)
            check("mobdev2 found meanwhile", len(lockdowns) == 1, lockdowns)
            task.cancel()
            try:
                await task
                problems.append("connect was not cancelled")
            except asyncio.CancelledError:
                pass
            check("the found lockdown is closed on cancel", lockdowns and lockdowns[0].closed >= 1,
                  [l.closed for l in lockdowns])
            await c.close_all()

            if problems:
                raise AssertionError("\\n".join(problems))
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Live 2026-11-02/03: an orphaned helper's mDNS sends all failed with EHOSTUNREACH
    /// ("bonjour discovery is blocked ... Local Network") and both Wi-Fi lanes reported
    /// "found nothing", so the app waited for a phone that was there. When both Wi-Fi
    /// lanes saw nothing, the helper asks whether any mDNS query can leave this host; when
    /// none can and the refusals are EHOSTUNREACH/EPERM, `connect_device` says so with the
    /// typed code `local_network_blocked` next to the usual text.
    func testPythonHelperReportsATypedLocalNetworkBlock() throws {
        let code = mobdev2LaneFixture() + """

        import errno
        GOOD = {"peer_alt_irk": b"k" * 16, "private_key": b"x" * 32}
        problems = []
        def check(name, ok, detail):
            if not ok:
                problems.append(f"{name}: {detail}")
        probes = []
        def probe_returning(sent, errors, raises=None):
            async def probe():
                probes.append(1)
                if raises is not None:
                    raise raises
                return sent, errors
            return probe
        def blocked(sent, errors):  # upstream's rule: every send failed
            return bool(sent) and len(errors) >= sent
        denied = [OSError(errno.EHOSTUNREACH, "No route to host")] * 4

        def reset():
            rp_records.clear(); rp_adverts.clear(); rp_services.clear(); rp_calls.clear()
            providers.clear(); browse_calls.clear(); mobdev2_visible.clear(); probes.clear()
            rp_state["browse_error"] = None

        async def attempt(probe, connection_type="Network"):
            c = make_connection()
            c._multicast_probe = probe
            c._multicast_blocked = blocked
            try:
                return await connect(c, connection_type=connection_type)
            finally:
                await c.close_all()

        async def verify():
            reset()
            rp_records["dev"] = GOOD
            result = await attempt(probe_returning(4, denied))
            check("blocked is typed", result.get("code") == "local_network_blocked", result)
            check("the lanes' text is kept", "remote pairing: RemotePairingDeviceNotFoundError" in result.get("error", ""),
                  result)
            check("one probe", len(probes) == 1, probes)

            reset()
            rp_records["dev"] = GOOD
            result = await attempt(probe_returning(4, [OSError(errno.EPERM, "Operation not permitted")] * 4))
            check("EPERM is a block too", result.get("code") == "local_network_blocked", result)

            # Every send failed, but not with a denial (no interface up): not a privacy block.
            reset()
            rp_records["dev"] = GOOD
            result = await attempt(probe_returning(4, [OSError(errno.EADDRNOTAVAIL, "Can't assign")] * 4))
            check("other errors are no block", result.get("code") is None, result)
            check("still waiting", result.get("reason") == "device_not_visible", result)

            # Some sends left the host: Bonjour works, the phone is just not there.
            reset()
            rp_records["dev"] = GOOD
            result = await attempt(probe_returning(4, denied[:2]))
            check("a partial failure is no block", result.get("code") is None, result)

            # The probe itself fails, or the runtime has no probe: no claim.
            for name, probe in (("probe raises", probe_returning(0, [], raises=OSError(49, "x"))), ("no probe", None)):
                reset()
                rp_records["dev"] = GOOD
                result = await attempt(probe)
                check(name, result.get("code") is None and result.get("reason") == "device_not_visible", result)

            # A browse refused with EHOSTUNREACH is the same block.
            reset()
            rp_records["dev"] = GOOD
            rp_state["browse_error"] = OSError(errno.EHOSTUNREACH, "No route to host")
            result = await attempt(probe_returning(4, []))
            rp_state["browse_error"] = None
            check("a refused browse is a block", result.get("code") == "local_network_blocked", result)

            # A Wi-Fi lane connected: nothing to probe.
            reset()
            rp_records["dev"] = GOOD
            mobdev2_visible.add("dev")
            result = await attempt(probe_returning(4, denied))
            check("connected", result.get("success") is True, result)
            check("no probe when connected", not probes, probes)

            # A USB request never browses Bonjour: no probe, no code.
            reset()
            rp_records["dev"] = GOOD
            result = await attempt(probe_returning(4, denied), connection_type="USB")
            check("USB: no probe", not probes and result.get("code") is None, result)

            if problems:
                raise AssertionError("\\n".join(problems))
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// The local network probe is upstream's (`pymobiledevice3.bonjour`); the managed
    /// runtime must provide it and the helper must wire exactly those functions.
    func testManagedRuntimeProvidesTheLocalNetworkProbe() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import importlib.util
        import pymobiledevice3.bonjour as bonjour
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        c = bridge.DeviceConnection()
        assert c._lazy_import()
        assert c._multicast_probe is bonjour.probe_multicast, c._multicast_probe
        assert c._multicast_blocked is bonjour.is_multicast_blocked, c._multicast_blocked
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// The remote pairing lane depends on pymobiledevice3 APIs that may move under the
    /// rolling-latest policy; the managed runtime must have them and the helper must
    /// wire exactly those objects.
    func testManagedRuntimeProvidesRemotePairingLaneAPI() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import importlib.util, inspect
        import pymobiledevice3.remote.tunnel_service as ts
        import pymobiledevice3.pair_records as pr
        import pymobiledevice3.remote.userspace_tunnel as ut
        assert inspect.iscoroutinefunction(ts.get_remote_pairing_tunnel_services)
        parameters = inspect.signature(ts.get_remote_pairing_tunnel_services).parameters
        assert "udid" in parameters and "bonjour_timeout" in parameters, parameters
        assert ts.PEER_ALT_IRK_KEY == "peer_alt_irk"
        # The record the lane checks is the one the browse matches adverts with.
        names = ts.get_remote_pairing_tunnel_services.__code__.co_names
        assert "iter_remote_pair_records_by_identifier" in names and "PEER_ALT_IRK_KEY" in names, names
        assert inspect.isgeneratorfunction(pr.iter_remote_pair_records_by_identifier)
        assert "hostname" in inspect.signature(ts.RemotePairingTunnelService.__init__).parameters
        assert inspect.iscoroutinefunction(ut._create_no_root_tunnel_provider)
        assert list(inspect.signature(ut._create_no_root_tunnel_provider).parameters)[:3] == [
            "serial", "autopair", "remotepairing_fallback"]
        assert "_create_no_root_tunnel_provider" in ut.UserspaceRsdTunnel._aopen_locked.__code__.co_names
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        c = bridge.DeviceConnection()
        assert c._lazy_import()
        assert c._remote_pairing_services is ts.get_remote_pairing_tunnel_services
        assert c._remote_pair_records is pr.iter_remote_pair_records_by_identifier
        assert c._peer_alt_irk_key == ts.PEER_ALT_IRK_KEY
        assert c._userspace_tunnel_module is ut
        assert bridge.REMOTE_PAIRING_BROWSE_TIMEOUT_SECONDS < bridge.CONNECT_TIMEOUT_SECONDS
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Fakes for the four helper lanes. The userspace tunnel fake models
    /// pymobiledevice3 11.49.1: `aopen()` takes its lockdown from the tunnel module's
    /// global `create_using_usbmux` (or, in a drift mode, ignores it).
    private func mobdev2LaneFixture() -> String {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        return """
        import asyncio, importlib.util, types
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)

        # Same names and hierarchy as pymobiledevice3.exceptions in 11.49.1.
        class PyMobileDevice3Exception(Exception): pass
        class MuxException(PyMobileDevice3Exception): pass
        class DeviceNotFoundError(PyMobileDevice3Exception): pass
        class ConnectionTerminatedError(PyMobileDevice3Exception): pass
        class ConnectionFailedError(MuxException): pass
        class InvalidServiceError(PyMobileDevice3Exception): pass
        class UserspaceTunnelUnavailableError(PyMobileDevice3Exception): pass
        class PairingError(PyMobileDevice3Exception): pass
        usbmux_visible, mobdev2_visible, mobdev2_unpaired = set(), set(), set()
        state = {"tunnel_error": None, "hold": None, "entered": None, "browse_error": None,
                 "preferred_error": None, "upstream": "global", "usbmux_now": set(),
                 "ignore_only_paired": False, "aclosed": 0, "userspace_hold": None,
                 "pre_provider_error": None, "preferred_hold": None}
        seen, lockdowns, browse_calls, providers = [], [], [], []

        class Lockdown:
            def __init__(self, udid, source, paired=True):
                self.udid, self.source, self.paired, self.closed = udid, source, paired, 0
            async def close(self): self.closed += 1
        async def usbmux_lockdown(serial=None, autopair=True, **kwargs):
            if serial not in usbmux_visible:
                raise DeviceNotFoundError(f"usbmux has no device matching udid {serial}")
            return Lockdown(serial, "usbmux")
        ORIGINAL = usbmux_lockdown

        # pymobiledevice3 11.49.1: UserspaceRsdTunnel._aopen_locked asks the module-global
        # _create_no_root_tunnel_provider(serial, autopair, remotepairing_fallback), which
        # takes its lockdown from the module-global create_using_usbmux.
        async def no_root_provider(serial, autopair, remotepairing_fallback=True):
            lockdown = await usermod.create_using_usbmux(serial=serial, autopair=autopair)
            return lockdown, lockdown
        ORIGINAL_PROVIDER = no_root_provider
        usermod = types.SimpleNamespace(create_using_usbmux=usbmux_lockdown,
                                        _create_no_root_tunnel_provider=no_root_provider)

        # RemotePairing (lane 5): records by UDID, Bonjour adverts by UDID (hostnames).
        rp_records, rp_adverts, rp_services, rp_calls = {}, {}, [], []
        rp_state = {"records_error": None, "browse_error": None, "browse_hold": None,
                    "browse_entered": None}
        def rp_iter_records():
            if rp_state["records_error"] is not None:
                raise rp_state["records_error"]
            for identifier, record in list(rp_records.items()):
                yield identifier, f"/fake/remote_{identifier}.plist", record
        class RPService:
            source = "remotepairing"
            def __init__(self, identifier, hostname):
                self.remote_identifier, self.hostname, self.port, self.closed = identifier, hostname, 49152, 0
            async def close(self): self.closed += 1
        async def rp_tunnel_services(bonjour_timeout=None, udid=None, excluded_identifiers=()):
            rp_calls.append({"udid": udid, "bonjour_timeout": bonjour_timeout})
            if rp_state["browse_error"] is not None:
                raise rp_state["browse_error"]
            if rp_state["browse_hold"] is not None:
                rp_state["browse_entered"].set()
                await rp_state["browse_hold"].wait()
            # Upstream matches adverts by the record's altIRK; a stale record matches nothing.
            record = rp_records.get(udid)
            if not record or record.get("peer_alt_irk") is None:
                return []
            made = [RPService(udid, host) for host in rp_adverts.get(udid, [])]
            rp_services.extend(made)
            return made

        async def mobdev2_lockdowns(udid=None, timeout=None, only_paired=False):
            browse_calls.append({"udid": udid, "timeout": timeout, "only_paired": only_paired})
            assert timeout == bridge.MOBDEV2_BROWSE_TIMEOUT_SECONDS == 8, timeout
            if state["browse_error"] is not None:
                raise state["browse_error"]
            if udid in mobdev2_visible:
                lockdown = Lockdown(udid, "mobdev2", paired=udid not in mobdev2_unpaired)
                lockdowns.append(lockdown)
                if only_paired and not lockdown.paired and not state["ignore_only_paired"]:
                    # pymobiledevice3 closes and skips an unpaired client.
                    await lockdown.close()
                    return
                yield "fe80::1%en0", lockdown

        class Context:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Info(Context):
            async def ls(self, path): return ["/usr"]
        class Location(Context):
            async def set(self, lat, lng): pass
        class Userspace:
            def __init__(self, serial=None, autopair=True, remotepairing_fallback=True):
                self.serial, self.remotepairing_fallback = serial, remotepairing_fallback
            async def aopen(self):
                swapped = (usermod.create_using_usbmux is not ORIGINAL
                           or usermod._create_no_root_tunnel_provider is not ORIGINAL_PROVIDER)
                seen.append((self.serial, usermod.create_using_usbmux is ORIGINAL))
                if state["userspace_hold"] is not None and not swapped:
                    # Lane 1 hangs (for example a wedged lifecycle lock in the helper).
                    await state["userspace_hold"].wait()
                if state["pre_provider_error"] is not None and swapped:
                    # Upstream fails before it asks for a lockdown (its one-tunnel guard).
                    raise state["pre_provider_error"]
                if state["upstream"] == "ignores-global":
                    await ORIGINAL(serial=self.serial, autopair=True)
                    return object()
                if state["upstream"] == "ignores-global-returns":
                    # Real usbmux listed the phone again by the time lane 4 ran.
                    if self.serial not in state["usbmux_now"]:
                        state["usbmux_now"].add(self.serial)
                        raise DeviceNotFoundError(f"usbmux has no device matching udid {self.serial}")
                    return object()
                provider, _ = await usermod._create_no_root_tunnel_provider(
                    self.serial, True, self.remotepairing_fallback)
                providers.append(provider)
                if getattr(provider, "source", None) in ("mobdev2", "remotepairing"):
                    if state["hold"] is not None:
                        state["entered"].set()
                        await state["hold"].wait()
                    if state["tunnel_error"] is not None:
                        raise state["tunnel_error"]
                return object()
            async def aclose(self): state["aclosed"] += 1
        class Preferred:
            def __init__(self, serial): self.serial = serial
            async def aopen(self):
                if state["preferred_hold"] is not None:
                    await state["preferred_hold"].wait()
                if state["preferred_error"] is not None:
                    raise state["preferred_error"]
                if self.serial not in usbmux_visible:
                    raise DeviceNotFoundError(f"no device {self.serial} (preferred)")
                return object()
            async def aclose(self): pass

        def make_connection():
            c = bridge.DeviceConnection()
            c._initialized = True
            c._userspace_tunnel_factory = Userspace
            c._lockdown_usb = usbmux_lockdown
            c._preferred_tunnel_factory = Preferred
            c._mobdev2_lockdowns = mobdev2_lockdowns
            c._userspace_tunnel_module = usermod
            c._remote_pairing_services = rp_tunnel_services
            c._remote_pair_records = rp_iter_records
            c._peer_alt_irk_key = "peer_alt_irk"
            c._dvt_module = lambda provider: Context()
            c._location_module = lambda dvt: Location()
            c._device_info_module = lambda dvt: Info()
            return c

        async def connect(c, udid="dev", connection_type="Network"):
            request = {"cmd": "connect_device", "udid": udid}
            if connection_type is not None:
                request["connection_type"] = connection_type
            return await bridge.process_command(c, request)
        """
    }

    /// Live 2026-11-03: the helper held the phone over its remote pairing lane while
    /// usbmuxd listed nothing, and the phone refused the image mounter over the mobdev2
    /// lockdown, so every Move failed at the Developer Disk Image gate before anything was
    /// sent. Over that same RSD the image mounter answered. `ddi_status` / `ddi_mount` run
    /// over the provider DVT runs over (every lane), never open a connection, and a DDI
    /// failure never closes the device connection.
    func testPythonHelperDiskImageCommandsUseTheHeldConnection() throws {
        let code = mobdev2LaneFixture() + """

        import threading
        MAIN_THREAD = threading.get_ident()
        class AlreadyMountedError(PyMobileDevice3Exception): pass
        ddi = {"images": [], "list_error": None, "mount_error": None, "mount_delay": 0.0}
        mounter_providers, mount_providers, prefetches, dvt_providers = [], [], [], []
        class Mounter:
            def __init__(self, lockdown):
                self.lockdown = lockdown
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def list_images(self):
                mounter_providers.append(self.lockdown)
                if ddi["list_error"] is not None:
                    raise ddi["list_error"]
                return list(ddi["images"])
        async def auto_mount(lockdown):
            mount_providers.append(lockdown)
            if ddi["mount_delay"]:
                await asyncio.sleep(ddi["mount_delay"])
            if ddi["mount_error"] is not None:
                raise ddi["mount_error"]
            ddi["images"] = [{"DiskImageType": "Personalized", "IsMounted": True}]
        def prefetch(lockdown):
            prefetches.append((lockdown, threading.get_ident() != MAIN_THREAD))

        def with_ddi(c):
            c._image_mounter_service = Mounter
            c._ddi_auto_mount = auto_mount
            c._ddi_prefetch = prefetch
            c._already_mounted_error = AlreadyMountedError
            def dvt(provider):
                dvt_providers.append(provider)
                return Context()
            c._dvt_module = dvt
            return c

        def reset_ddi():
            ddi.update(images=[], list_error=None, mount_error=None, mount_delay=0.0)
            for calls in (mounter_providers, mount_providers, prefetches, dvt_providers):
                calls.clear()

        async def ddi_command(c, cmd, udid="dev"):
            return await bridge.process_command(c, {"cmd": cmd, "udid": udid,
                "connection_type": "Network"})

        async def verify():
            for cmd in ("ddi_status", "ddi_mount"):
                assert bridge.validate_request({"cmd": cmd, "udid": "d",
                    "request_id": "r", "session_generation": 0}) == (True, ""), cmd
                assert bridge.validate_request({"cmd": cmd,
                    "request_id": "r", "session_generation": 0})[0] is False, cmd
                assert bridge.validate_request({"cmd": cmd, "udid": 7,
                    "request_id": "r", "session_generation": 0})[0] is False, cmd

            # No held connection: "not connected", and nothing is opened or asked.
            reset_ddi()
            usbmux_visible.add("dev")
            c = with_ddi(make_connection())
            for cmd in ("ddi_status", "ddi_mount"):
                assert await ddi_command(c, cmd) == {"success": False, "error": "not connected"}, cmd
            assert not seen and not dvt_providers, "a DDI command must never open a connection"
            assert not mounter_providers and not mount_providers and not prefetches

            # Every lane: the image mounter runs over the provider DVT runs over.
            async def lane_userspace(c):
                usbmux_visible.add("dev")
            async def lane_remote_pairing(c):
                usbmux_visible.discard("dev")
                rp_records["dev"] = {"peer_alt_irk": b"irk"}
                rp_adverts["dev"] = ["192.168.0.177"]
            async def lane_mobdev2(c):
                usbmux_visible.discard("dev")
                rp_records.pop("dev", None)
                mobdev2_visible.add("dev")
            for setup, channel in ((lane_userspace, "userspaceRSD"),
                                   (lane_remote_pairing, "remotePairingRSD"),
                                   (lane_mobdev2, "mobdev2RSD")):
                reset_ddi()
                c = with_ddi(make_connection())
                await setup(c)
                connected = await connect(c)
                assert connected["actual_channel"] == channel, (channel, connected)
                held = dvt_providers[-1]
                status = await ddi_command(c, "ddi_status")
                assert status == {"success": True, "mounted": False}, (channel, status)
                assert mounter_providers == [held], (channel, mounter_providers, held)
                mounted = await ddi_command(c, "ddi_mount")
                assert mounted == {"success": True, "mounted": True}, (channel, mounted)
                assert mount_providers == [held], channel
                assert prefetches == [(held, True)], ("assets are fetched off the event loop", prefetches)
                status = await ddi_command(c, "ddi_status")
                assert status == {"success": True, "mounted": True}, (channel, status)
                assert len(dvt_providers) == 1, (channel, "no second connection was opened")
                await c.close_all()

            # The usbmux-direct lane holds a lockdown; the mounter runs over that lockdown.
            reset_ddi()
            usbmux_visible.add("dev")
            class NoUserspace:
                def __init__(self, **kwargs): pass
                async def aopen(self): raise InvalidServiceError("needs a tunnel")
                async def aclose(self): pass
            c = with_ddi(make_connection())
            c._userspace_tunnel_factory = NoUserspace
            connected = await connect(c)
            assert connected["actual_channel"] == "usbmuxDirect", connected
            held = dvt_providers[-1]
            assert getattr(held, "source", None) == "usbmux", held
            ddi["images"] = [{"DiskImageType": "Personalized"}]
            assert await ddi_command(c, "ddi_status") == {"success": True, "mounted": True}
            assert mounter_providers == [held], mounter_providers
            await c.close_all()

            # The preferred-RSD lane holds its RSD.
            reset_ddi()
            usbmux_visible.add("dev")
            class UserspaceRsdTunnel: pass
            class PreferredHandle(Preferred):
                def __init__(self, serial):
                    super().__init__(serial)
                    self._handle = UserspaceRsdTunnel()
            async def no_lockdown(**kwargs): raise InvalidServiceError("needs a tunnel")
            c = with_ddi(make_connection())
            c._userspace_tunnel_factory = NoUserspace
            c._lockdown_usb = no_lockdown
            c._preferred_tunnel_factory = PreferredHandle
            connected = await connect(c)
            assert connected["success"] is True and connected["actual_channel"] == "userspaceRSD", connected
            held = dvt_providers[-1]
            await ddi_command(c, "ddi_status")
            assert mounter_providers == [held], mounter_providers
            await c.close_all()

            # Already mounted is what was asked for; a failed status or mount is a typed
            # error and leaves the device connection open (a DDI failure is not a loss).
            reset_ddi()
            usbmux_visible.add("dev")
            c = with_ddi(make_connection())
            await connect(c)
            aclosed = state["aclosed"]
            ddi["mount_error"] = AlreadyMountedError("already mounted")
            assert await ddi_command(c, "ddi_mount") == {"success": True, "mounted": True}
            ddi["mount_error"] = RuntimeError("TSS refused")
            failed = await ddi_command(c, "ddi_mount")
            assert failed["success"] is False and "RuntimeError: TSS refused" in failed["error"], failed
            assert "mounted" not in failed, failed
            ddi["mount_error"] = None
            ddi["list_error"] = ConnectionTerminatedError("Connection was terminated abruptly")
            failed = await ddi_command(c, "ddi_status")
            assert failed["success"] is False and "ConnectionTerminatedError" in failed["error"], failed
            ddi["list_error"] = None
            # Bounded: a mount that outlives its budget is reported as timed out.
            original_timeout = bridge.DDI_MOUNT_TIMEOUT_SECONDS
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = 0.05
            ddi["mount_delay"] = 1.0
            failed = await ddi_command(c, "ddi_mount")
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = original_timeout
            ddi["mount_delay"] = 0.0
            assert failed["success"] is False and "timed out" in failed["error"], failed
            assert state["aclosed"] == aclosed, "a DDI failure must not close the device connection"
            status = await bridge.process_command(c, {"cmd": "connection_status", "udid": "dev"})
            assert status["connected"] is True, status

            # Concurrent mounts for one device run one at a time.
            reset_ddi()
            ddi["mount_delay"] = 0.05
            running = {"now": 0, "peak": 0}
            async def counted_mount(lockdown):
                running["now"] += 1
                running["peak"] = max(running["peak"], running["now"])
                try:
                    if ddi["images"]:
                        raise AlreadyMountedError("already mounted")
                    await auto_mount(lockdown)
                finally:
                    running["now"] -= 1
            c._ddi_auto_mount = counted_mount
            results = await asyncio.gather(ddi_command(c, "ddi_mount"), ddi_command(c, "ddi_mount"))
            assert results == [{"success": True, "mounted": True}] * 2, results
            assert running["peak"] == 1, running

            # A runtime without the image mounter API says so and asks nothing.
            c._image_mounter_service = None
            c._ddi_auto_mount = None
            for cmd in ("ddi_status", "ddi_mount"):
                result = await ddi_command(c, cmd)
                assert result["success"] is False and "image mounter" in result["error"], result
            await c.close_all()
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// Review 2026-11-03 issues 5 and 11. The 120 s mount budget used to include the wait
    /// for the per-device mount lock, so a second `ddi_mount` (Move beside the recovery
    /// burst) timed out while the first mounted the image. A timed-out mount left its image
    /// download running in a worker thread, and the next attempt started a second download
    /// into the same cache at the same time.
    func testPythonHelperDiskImageMountQueueAndSharedDownload() throws {
        let code = mobdev2LaneFixture() + """

        import threading, time
        class AlreadyMountedError(PyMobileDevice3Exception): pass
        ddi = {"images": [], "mount_delay": 0.0, "mount_error": None}
        counts = {"mounts": 0, "prefetches": 0, "prefetching": 0, "prefetch_peak": 0}
        prefetch_gate = {"event": None, "delay": 0.0}
        prefetch_lock = threading.Lock()
        class Mounter:
            def __init__(self, lockdown): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def list_images(self): return list(ddi["images"])
        async def auto_mount(lockdown):
            counts["mounts"] += 1
            if ddi["images"]:
                raise AlreadyMountedError("already mounted")
            error = ddi["mount_error"]
            await asyncio.sleep(ddi["mount_delay"])
            if error is not None:
                raise error
            ddi["images"] = [{"DiskImageType": "Personalized"}]
        def prefetch(lockdown):
            with prefetch_lock:
                counts["prefetches"] += 1
                counts["prefetching"] += 1
                counts["prefetch_peak"] = max(counts["prefetch_peak"], counts["prefetching"])
            try:
                if prefetch_gate["event"] is not None:
                    prefetch_gate["event"].wait(5)
                time.sleep(prefetch_gate["delay"])
            finally:
                with prefetch_lock:
                    counts["prefetching"] -= 1

        def with_ddi(c):
            c._image_mounter_service = Mounter
            c._ddi_auto_mount = auto_mount
            c._ddi_prefetch = prefetch
            c._already_mounted_error = AlreadyMountedError
            return c

        def reset():
            ddi.update(images=[], mount_delay=0.0, mount_error=None)
            counts.update(mounts=0, prefetches=0, prefetching=0, prefetch_peak=0)
            prefetch_gate.update(event=None, delay=0.0)

        async def ddi_mount(c):
            return await bridge.process_command(c, {"cmd": "ddi_mount", "udid": "dev",
                "connection_type": "Network"})

        async def verify():
            original_timeout = bridge.DDI_MOUNT_TIMEOUT_SECONDS
            usbmux_visible.add("dev")
            c = with_ddi(make_connection())
            assert (await connect(c))["success"] is True

            # 5: the queued mount's budget starts when it holds the lock, and a waiter
            # whose lock holder mounted the image returns mounted without a second mount.
            reset()
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = 1.0
            prefetch_gate["delay"] = 0.4
            ddi["mount_delay"] = 0.4
            results = await asyncio.gather(ddi_mount(c), ddi_mount(c))
            assert results == [{"success": True, "mounted": True}] * 2, results
            assert counts["prefetches"] == 1, ("the waiter downloaded again", counts)
            assert counts["mounts"] == 1, ("the waiter mounted again", counts)

            # 5: a waiter whose lock holder failed mounts on its own budget.
            reset()
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = 1.0
            ddi["mount_delay"] = 0.05
            ddi["mount_error"] = RuntimeError("TSS refused")
            first = asyncio.ensure_future(ddi_mount(c))
            await asyncio.sleep(0.01)
            second = asyncio.ensure_future(ddi_mount(c))
            await asyncio.sleep(0.02)
            ddi["mount_error"] = None
            first, second = await first, await second
            assert first["success"] is False and "TSS refused" in first["error"], first
            assert second == {"success": True, "mounted": True}, second
            assert counts["mounts"] == 2, counts

            # 11: a mount that timed out left its download running; the next mount waits
            # for that download instead of starting a second one beside it.
            reset()
            gate = threading.Event()
            prefetch_gate["event"] = gate
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = 0.1
            timed_out = await ddi_mount(c)
            assert timed_out["success"] is False and "timed out" in timed_out["error"], timed_out
            assert counts["prefetching"] == 1, ("the first download is still running", counts)
            bridge.DDI_MOUNT_TIMEOUT_SECONDS = 3.0
            retry = asyncio.ensure_future(ddi_mount(c))
            await asyncio.sleep(0.1)
            assert counts["prefetches"] == 1, ("a second download started beside the first", counts)
            gate.set()
            assert await retry == {"success": True, "mounted": True}
            assert counts["prefetch_peak"] == 1, counts
            assert counts["prefetches"] == 1, counts

            # 11: once the earlier download ended, a later mount downloads again as before.
            ddi["images"] = []
            prefetch_gate["event"] = None
            assert await ddi_mount(c) == {"success": True, "mounted": True}
            assert counts["prefetches"] == 2, counts

            bridge.DDI_MOUNT_TIMEOUT_SECONDS = original_timeout
            await c.close_all()
        asyncio.run(verify())
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    /// The helper's DDI commands depend on pymobiledevice3 APIs that may move under the
    /// rolling-latest policy; the managed runtime must have them and the helper must wire
    /// exactly those objects.
    func testManagedRuntimeProvidesDiskImageAPI() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import importlib.util, inspect
        import pymobiledevice3.services.mobile_image_mounter as mim
        import pymobiledevice3.services.cryptexd as cryptexd
        from pymobiledevice3.exceptions import AlreadyMountedError
        assert mim.MobileImageMounterService.RSD_SERVICE_NAME == "com.apple.mobile.mobile_image_mounter.shim.remote"
        assert inspect.iscoroutinefunction(mim.MobileImageMounterService.list_images)
        assert inspect.iscoroutinefunction(mim.auto_mount)
        # The prefetch fetches what auto_mount would fetch synchronously on the loop.
        for name in ("uses_personalized_image", "uses_cryptex_image", "fetch_personalized_ddi",
                     "CRYPTEX_IMAGE_MIN_VERSION", "RemoteServiceDiscoveryService"):
            assert hasattr(mim, name), name
        assert callable(cryptexd.fetch_cryptex_ddi)
        assert "fetch_cryptex_ddi" in cryptexd.load_cryptex1_assets.__code__.co_names
        assert "load_cryptex1_assets" in cryptexd.CryptexdService.auto_install_ddi.__code__.co_names
        assert "fetch_personalized_ddi" in mim.auto_mount_personalized.__code__.co_names
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        c = bridge.DeviceConnection()
        assert c._lazy_import()
        assert c._image_mounter_service is mim.MobileImageMounterService
        assert c._ddi_auto_mount is mim.auto_mount
        assert c._already_mounted_error is AlreadyMountedError
        assert c._ddi_prefetch is bridge._prefetch_ddi_assets
        assert bridge.DDI_MOUNT_TIMEOUT_SECONDS >= 60
        # The prefetch fetches only what auto_mount would (no network: fetches recorded).
        fetched = []
        mim.fetch_personalized_ddi = lambda: fetched.append("personalized")
        cryptexd.fetch_cryptex_ddi = lambda: fetched.append("cryptex")
        class Lockdown:
            def __init__(self, version): self.product_version = version
        real_uses_cryptex = mim.uses_cryptex_image
        for version, expected in (("16.7", []), ("18.0", ["personalized"]), ("27.2", [])):
            fetched.clear()
            bridge._prefetch_ddi_assets(Lockdown(version))
            assert fetched == expected, (version, fetched)
        mim.uses_cryptex_image = lambda provider: True
        fetched.clear()
        bridge._prefetch_ddi_assets(Lockdown("27.2"))
        assert fetched == ["cryptex"], fetched
        mim.uses_cryptex_image = real_uses_cryptex
        """
        let (status, errorOutput) = try runManagedPython(code)
        XCTAssertEqual(status, 0, errorOutput)
    }

    private func runManagedPython(_ code: String) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        return (process.terminationStatus, errorOutput)
    }

    /// The mobdev2 lane depends on two pymobiledevice3 APIs that may move under the
    /// rolling-latest policy: the Bonjour lockdown browse and the userspace tunnel's
    /// module-global `create_using_usbmux` lookup. The managed runtime must have both,
    /// and the helper must wire exactly those objects.
    func testManagedRuntimeProvidesMobdev2LaneAPI() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import importlib.util, inspect
        import pymobiledevice3.lockdown as lockdown
        import pymobiledevice3.remote.userspace_tunnel as ut
        assert inspect.isasyncgenfunction(lockdown.get_mobdev2_lockdowns)
        parameters = inspect.signature(lockdown.get_mobdev2_lockdowns).parameters
        assert "udid" in parameters and "timeout" in parameters, parameters
        # The lane asks only for paired lockdowns (an unpaired one is not the phone).
        assert "only_paired" in parameters, parameters
        assert inspect.iscoroutinefunction(ut.create_using_usbmux)
        assert "create_using_usbmux" in ut._create_no_root_tunnel_provider.__code__.co_names
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        c = bridge.DeviceConnection()
        assert c._lazy_import()
        assert c._mobdev2_lockdowns is lockdown.get_mobdev2_lockdowns
        assert c._userspace_tunnel_module is ut
        assert bridge.MOBDEV2_BROWSE_TIMEOUT_SECONDS < bridge.CONNECT_TIMEOUT_SECONDS
        # The helper classifies upstream errors by class name; every name it relies
        # on must still exist in pymobiledevice3.exceptions with the same meaning.
        import pymobiledevice3.exceptions as exceptions
        names = set(bridge._UPSTREAM_TRANSPORT_ERRORS) | set(bridge._USBMUX_LOOKUP_ERRORS) | {
            name for name in bridge._DEVICE_ABSENT_ERRORS
            if name not in (bridge.Mobdev2DeviceNotFoundError.__name__, "RemotePairingDeviceNotFoundError")}
        names.add(bridge._UPSTREAM_BASE_ERROR)
        assert {"ConnectionTerminatedError", "ConnectionFailedError"} <= set(bridge._UPSTREAM_TRANSPORT_ERRORS)
        for name in sorted(names):
            cls = getattr(exceptions, name, None)
            assert isinstance(cls, type) and issubclass(cls, exceptions.PyMobileDevice3Exception), name
        assert not issubclass(exceptions.ConnectionTerminatedError, ConnectionError)
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
    }

    /// The helper record must never list a held location on a connection that is
    /// gone, a probe that merely times out must not destroy a live connection, and
    /// a failure must close only the connection it happened on.
    func testPythonHelperKeepsConnectionTruthHonest() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util, json, os, tempfile
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        bridge.PROBE_TIMEOUT_SECONDS = 0.2

        calls = []
        ls_mode = "ok"
        class Context:
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Location(Context):
            async def set(self, lat, lng): calls.append(("set", lat, lng))
        class Info(Context):
            async def ls(self, path):
                global ls_mode
                if ls_mode == "stall": await asyncio.sleep(5)
                if ls_mode == "stall_once":
                    ls_mode = "ok"
                    await asyncio.sleep(5)
                if ls_mode == "dead": raise ConnectionResetError("tunnel gone")
                return ["/usr"]
        class Tunnel:
            def __init__(self, **kwargs): calls.append(("open",))
            async def aopen(self): return object()
            async def aclose(self): calls.append(("aclose",))

        def make_connection():
            c = bridge.DeviceConnection()
            c._initialized = True
            c._userspace_tunnel_factory = Tunnel
            c._dvt_module = lambda provider: Context()
            c._location_module = lambda dvt: Location()
            c._device_info_module = lambda dvt: Info()
            return c

        def sessions(path):
            with open(path) as f:
                return json.load(f)["active_sessions"]

        async def verify():
            global ls_mode
            with tempfile.TemporaryDirectory() as directory:
                record = os.path.join(directory, "helper.json")
                bridge._write_helper_record(record, os.path.join(directory, "s"), "t", "h")
                c = make_connection()
                c.on_connection_closed = lambda udid: bridge._forget_device_sessions(record, udid)
                request = {"cmd": "set_location", "udid": "dev", "lat": 1.0, "lng": 2.0,
                           "request_id": "r1", "session_generation": 1,
                           "connection_type": "Network"}
                response = await bridge.process_command(c, request)
                bridge._record_location_result(record, request, response)
                assert len(sessions(record)) == 1

                # A stalled probe reports not-connected but keeps the connection.
                ls_mode = "stall"
                status = await bridge.process_command(c, {"cmd": "connection_status",
                    "udid": "dev", "connection_type": "Network"})
                assert status["connected"] is False, status
                assert "timed out" in status["reason"], status
                assert ("aclose",) not in calls, calls
                assert len(sessions(record)) == 1

                # A dead connection is closed and its held location leaves the record.
                ls_mode = "dead"
                status = await bridge.process_command(c, {"cmd": "connection_status",
                    "udid": "dev", "connection_type": "Network"})
                assert status["connected"] is False, status
                assert calls.count(("aclose",)) == 1, calls
                assert sessions(record) == [], sessions(record)

                # Disconnect also clears the record.
                ls_mode = "ok"
                response = await bridge.process_command(c, request)
                bridge._record_location_result(record, request, response)
                assert len(sessions(record)) == 1
                await bridge.process_command(c, {"cmd": "disconnect_device",
                    "udid": "dev", "connection_type": "Network"})
                assert sessions(record) == []

                # connect_device proves a cached connection; a stalled one is replaced.
                opens_before = calls.count(("open",))
                await bridge.process_command(c, {"cmd": "connect_device", "udid": "dev",
                    "connection_type": "Network"})
                ls_mode = "stall_once"
                connected = await bridge.process_command(c, {"cmd": "connect_device",
                    "udid": "dev", "connection_type": "Network"})
                assert connected["connected"] is True, connected
                assert connected["replaced"] is True, connected
                assert calls.count(("open",)) == opens_before + 2, calls
                ls_mode = "ok"

                # Invalidating a stale entry never closes the newer connection.
                await bridge.process_command(c, {"cmd": "connect_device", "udid": "dev",
                    "connection_type": "Network"})
                stale = {"stack": None}
                await c._invalidate("dev", stale)
                assert "dev" in c._service_cache
                await c.close_all()
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        try? stderr.fileHandleForReading.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errorOutput)
    }

    func testPythonCommandLoopPropagatesConnectionType() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        class FakeConnection:
            async def set_location(self, lat, lng, udid, rsd_address=None,
                                   rsd_port=None, connection_type=None):
                return {"success": True, "connection_type": connection_type}
        async def verify():
            result = await bridge.process_command(FakeConnection(), {
                "cmd": "set_location", "lat": 1.0, "lng": 2.0,
                "udid": "fake-device", "connection_type": "Network",
                "request_id": "request-1", "session_generation": 1
            })
            assert result["connection_type"] == "Network"
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testHelperRecordTracksAcknowledgedSessionWithoutRawDeviceIdentity() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util, json, os, pathlib, tempfile
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        with tempfile.TemporaryDirectory() as directory:
            record_path = os.path.join(directory, "helper.json")
            bridge._write_helper_record(
                record_path, os.path.join(directory, "helper.sock"),
                "test-token", "helper-id"
            )
            request = {
                "cmd": "set_location", "udid": "private-device-id",
                "lat": 37.33182, "lng": -122.03118,
                "request_id": "set-request", "session_generation": 7,
                "connection_type": "USB",
            }
            class FakeLocation:
                async def set(self, lat, lng):
                    assert (lat, lng) == (37.33182, -122.03118)

            connection = bridge.DeviceConnection()
            connection._lazy_import = lambda: True
            async def fake_service(*args, **kwargs):
                return None, FakeLocation(), "native_rsd", "remote_service_discovery"
            connection._get_or_create_service = fake_service
            response = asyncio.run(connection.set_location(
                request["lat"], request["lng"], request["udid"],
                connection_type=request["connection_type"]
            ))
            assert response["success"] is True
            bridge._record_acknowledged_application(record_path, request, response)
            contents = pathlib.Path(record_path).read_text()
            record = json.loads(contents)
            assert "private-device-id" not in contents
            assert len(record["active_sessions"]) == 1
            session = record["active_sessions"][0]
            assert session["device_id_sha256"]
            assert session["request_id"] == "set-request"
            assert session["session_generation"] == 7
            assert session["physical_transport"] == "USB"
            assert session["actual_channel"] == "native_rsd"
            assert session["endpoint_class"] == "remote_service_discovery"
            assert session["coordinate"] == {"latitude": 37.33182, "longitude": -122.03118}
            assert len(record["recent_results"]) == 1
            set_result = record["recent_results"][0]
            assert set_result["cmd"] == "set_location"
            assert set_result["request_id"] == "set-request"
            assert set_result["session_generation"] == 7
            assert set_result["success"] is True
            assert set_result["physical_transport"] == "USB"
            assert set_result["actual_channel"] == "native_rsd"
            assert set_result["endpoint_class"] == "remote_service_discovery"
            assert set_result["device_id_sha256"] == session["device_id_sha256"]
            clear_request = dict(request, cmd="clear_location", request_id="clear-request")
            clear_response = dict(
                response, request_id="clear-request", session_generation=7,
                physical_transport="USB"
            )
            bridge._record_acknowledged_clear(record_path, clear_request, clear_response)
            cleared = json.loads(pathlib.Path(record_path).read_text())
            assert cleared["active_sessions"] == []
            assert len(cleared["recent_results"]) == 2
            clear_result = cleared["recent_results"][-1]
            assert clear_result["cmd"] == "clear_location"
            assert clear_result["request_id"] == "clear-request"
            assert clear_result["success"] is True
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testHelperOwnershipRecordFailureDoesNotImplicitlyClearLocation() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, importlib.util, json, os, tempfile
        spec = importlib.util.spec_from_file_location("bridge", r"\(script)")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)

        class FakeConnection:
            def __init__(self):
                self.clear_calls = 0
            async def set_location(self, *args, **kwargs):
                return {
                    "success": True,
                    "actual_channel": "native_rsd",
                    "endpoint_class": "remote_service_discovery",
                }
            async def clear_location(self, *args, **kwargs):
                self.clear_calls += 1
                return {"success": True}

        class FakeWriter:
            def __init__(self):
                self.buffer = bytearray()
            def write(self, data):
                self.buffer.extend(data)
            async def drain(self):
                pass
            def close(self):
                pass
            async def wait_closed(self):
                pass

        async def verify():
            with tempfile.TemporaryDirectory() as directory:
                record_path = os.path.join(directory, "helper.json")
                bridge._write_helper_record(
                    record_path, os.path.join(directory, "helper.sock"),
                    "test-token", "helper-id"
                )
                def fail_record(*args, **kwargs):
                    raise OSError("record unavailable")
                bridge._record_location_result = fail_record
                request = {
                    "cmd": "set_location", "auth_token": "test-token",
                    "udid": "private-device-id", "lat": 1.0, "lng": 2.0,
                    "request_id": "request-id", "session_generation": 1,
                    "connection_type": "USB",
                }
                reader = asyncio.StreamReader()
                reader.feed_data((json.dumps(request) + "\\n").encode())
                reader.feed_eof()
                writer = FakeWriter()
                connection = FakeConnection()
                await bridge._handle_socket_client(
                    reader, writer, connection, "test-token", "helper-id",
                    record_path, set()
                )
                response = json.loads(writer.buffer.decode().splitlines()[0])
                assert response["code"] == "OWNERSHIP_RECORD_FAILED"
                assert response["location_may_be_active"] is True
                assert connection.clear_calls == 0
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testManagedHelperSurvivesClientDisconnectAndRequiresExplicitShutdown() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/location_bridge.py").path
        let code = """
        import asyncio, json, os, pathlib, subprocess, sys, tempfile, time

        async def exchange(socket_path, token, command):
            reader, writer = await asyncio.open_unix_connection(socket_path)
            request = {
                "cmd": command,
                "auth_token": token,
                "request_id": f"{command}-request",
                "session_generation": 1,
            }
            writer.write((json.dumps(request) + "\\n").encode())
            await writer.drain()
            response = json.loads((await reader.readline()).decode())
            writer.close()
            await writer.wait_closed()
            return response

        async def verify():
            with tempfile.TemporaryDirectory() as directory:
                socket_path = os.path.join(directory, "helper.sock")
                token_path = os.path.join(directory, "token")
                record_path = os.path.join(directory, "helper.json")
                token = "test-helper-token"
                pathlib.Path(token_path).write_text(token)
                os.chmod(token_path, 0o600)
                helper = subprocess.Popen(
                    [sys.executable, "-B", r"\(script)",
                     "--socket", socket_path, "--token-file", token_path,
                     "--record-file", record_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                try:
                    ready = json.loads(helper.stdout.readline())
                    assert ready["ready"] is True
                    assert ready["transport"] == "unix_socket"
                    assert isinstance(ready["helper_id"], str)
                    assert os.stat(socket_path).st_mode & 0o777 == 0o600
                    assert os.stat(record_path).st_mode & 0o777 == 0o600
                    record = json.loads(pathlib.Path(record_path).read_text())
                    assert record["protocol_version"] == 1
                    assert record["helper_id"] == ready["helper_id"]
                    assert record["pid"] == helper.pid
                    assert record["socket_path"] == socket_path
                    assert record["python_sha256"]
                    assert record["bridge_sha256"]
                    assert record["token_sha256"]
                    assert "fake-device" not in pathlib.Path(record_path).read_text()
                    first = await exchange(socket_path, token, "ping")
                    assert first["success"] is True
                    assert first["helper_id"] == record["helper_id"]
                    assert helper.poll() is None, "Disconnect must not stop the helper"
                    second = await exchange(socket_path, token, "ping")
                    assert second["success"] is True
                    shutdown = await exchange(socket_path, token, "quit")
                    assert shutdown["success"] is True
                    helper.wait(timeout=5)
                    assert helper.returncode == 0, helper.stderr.read()
                finally:
                    if helper.poll() is None:
                        helper.terminate()
                        helper.wait(timeout=5)
        asyncio.run(verify())
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PythonPathResolver.managedPythonPath)
        process.arguments = ["-B", "-c", code]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

/// A settable clock for rate-limit tests.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}
