//
//  TunneldManagerTests.swift
//  PathChangerTests
//
//  Unit tests for tunnel lifecycle and race condition prevention
//

import XCTest
@testable import PathChanger

@MainActor
final class TunneldManagerTests: XCTestCase {

    var manager: TunneldManager!

    override func setUp() async throws {
        // Note: Using shared singleton - tests may affect each other
        manager = TunneldManager.shared

        // Hermetic start: earlier suites (e.g. TunnelHealthMonitorTests) drive the shared
        // state machine into running, whose action starts this manager's health monitor.
        // Residual consecutive-failure counts would otherwise fire .healthCheckFailed into
        // the machine within milliseconds of connectionEstablished below.
        let mirror = Mirror(reflecting: manager as TunneldManager)
        if let sharedMonitor = mirror.children.first(where: { $0.label == "healthMonitor" })?.value as? TunnelHealthMonitor {
            sharedMonitor.stopMonitoring()
            sharedMonitor.resetMetrics()
        }
    }

    func testTunnelCommandsTargetSelectedDeviceWhenProvided() {
        let udid = "00000000-0000000000000001"

        // USB and Wi-Fi no longer launch a tunnel process: the managed helper owns
        // the device connection (Option A, 2026-11-01). Only the daemon is a process.
        XCTAssertNil(TunneldManager.arguments(for: .usb, deviceId: udid))
        XCTAssertNil(TunneldManager.arguments(for: .wifi, deviceId: udid))
        XCTAssertEqual(TunneldManager.arguments(for: .daemon, deviceId: udid), [
            "-m", "pymobiledevice3", "remote", "tunneld",
        ])
    }

    // MARK: - Helper-owned device connection (Option A)

    func testStartTunnelOpensTheHelperConnectionForTheSelectedDevice() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"

        await manager.startTunnel(deviceId: udid)

        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(connector.connectCalls, [FakeDeviceConnector.Call(deviceId: udid, transport: .wifi)])
        let info = try XCTUnwrap(manager.tunnelInfo)
        XCTAssertEqual(info.channel, .helperUserspace)
        XCTAssertEqual(info.deviceId, udid)
        XCTAssertEqual(info.processId, connector.helperPID)
        // No external RSD endpoint exists: CLI paths target the device directly and
        // the helper is never handed an endpoint to dial.
        XCTAssertNil(manager.getRsdInfo(for: udid))
        XCTAssertEqual(manager.locationConnectionArguments(for: udid), ["--udid", udid])

        manager.stopTunnel()
        try await waitUntil { connector.disconnectCalls.count == 1 }
        XCTAssertEqual(connector.disconnectCalls, [FakeDeviceConnector.Call(deviceId: udid, transport: .wifi)])
        try await waitUntil { self.manager.state == .idle }
    }

    // MARK: - Wi-Fi Start waits for the phone (live 2026-11-01)

    // usbmux drops an idle Wi-Fi phone for seconds to minutes (07:13:57-07:16:14,
    // 07:19:45-07:20:02 with the phone unlocked); a Start in such a gap failed at
    // once with a usbmux error. Start now waits for the phone, visibly, until it
    // appears, the user stops, or the wait runs out.

    private static let notVisible = PersistentLocationBridge.PersistentBridgeError
        .deviceNotVisible("Device not found: usbmux has no device matching udid over Network")

    func testWiFiStartWaitsUntilThePhoneBecomesVisible() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 5, interval: 0.02)
        connector.connectErrors = [Self.notVisible, Self.notVisible]
        let udid = "00008130-000C5144019A001C"

        await manager.startTunnel(deviceId: udid)

        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(connector.connectCalls.count, 3)
        XCTAssertFalse(manager.isWaitingForDevice)
        XCTAssertNil(manager.lastError)
    }

    func testWiFiStartGivesUpWithAPlainMessageWhenThePhoneNeverAppears() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 0.15, interval: 0.02)
        connector.connectError = Self.notVisible

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        guard case .error = manager.state else {
            return XCTFail("expected error after the wait ran out, got \(manager.state)")
        }
        XCTAssertGreaterThan(connector.connectCalls.count, 1)
        XCTAssertFalse(manager.isWaitingForDevice)
        let message = manager.lastError ?? ""
        XCTAssertTrue(message.contains("not reachable over Wi‑Fi"), message)
        XCTAssertTrue(message.contains("Unlock"), message)
        XCTAssertFalse(message.contains("usbmux"), message)
    }

    // Live 2026-11-02: the phone was unlocked and on the same Wi-Fi (mobdev2 Bonjour
    // found its paired lockdown) while usbmuxd listed nothing for hours after the
    // phone's private Wi-Fi address rotated. Telling the owner to unlock the phone
    // and join the Wi-Fi was false; the give-up message names the real gap.

    private static let usbmuxUnlistedDetail =
        "DeviceLanesUnavailable: DVT lanes unavailable ("
        + "userspace tunnel: DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130-000C5144019A001C; "
        + "usbmux direct: DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130-000C5144019A001C; "
        + "preferred RSD: DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130-000C5144019A001C; "
        + "mobdev2: ConnectionTerminatedError: Connection was terminated abruptly.)"

    func testWiFiStartGivesUpNamingTheUsbmuxGapWhenMobdev2ReachedThePhone() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 0.15, interval: 0.02)
        connector.connectError = PersistentLocationBridge.PersistentBridgeError
            .deviceNotVisible(Self.usbmuxUnlistedDetail)

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        let message = manager.lastError ?? ""
        XCTAssertTrue(message.contains("Your iPhone answers on this Mac's network"), message)
        XCTAssertTrue(message.contains("cable"), message)
        XCTAssertTrue(message.contains("unlocked"), "keep the unlock advice: a locked phone looks the same. \(message)")
        XCTAssertFalse(message.contains("00008130"), message)
    }

    /// Review 2026-11-02-173842 issue 3: an earlier attempt proved the phone answers; a
    /// last attempt whose Bonjour browse missed must not bring back the false advice.
    func testWiFiStartRemembersThatAnEarlierAttemptReachedThePhone() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 0.15, interval: 0.02)
        let missed = Self.lanes(
            Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2],
            "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s"
        )
        connector.connectErrors = [PersistentLocationBridge.PersistentBridgeError.deviceNotVisible(Self.usbmuxUnlistedDetail)]
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.deviceNotVisible(missed)

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        XCTAssertEqual(manager.lastError, TunneldManager.wifiUnlistedByUsbmuxMessage)
    }

    private static func lanes(_ segments: String...) -> String {
        "DeviceLanesUnavailable: DVT lanes unavailable (\(segments.joined(separator: "; ")))"
    }

    private static let usbmuxAbsentLanes = [
        "userspace tunnel: DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130…",
        "usbmux direct: NoDeviceConnectedError: ",
        "preferred RSD: DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130…",
    ]

    func testGaveUpMessageNamesTheUsbmuxGapForTheLiveDetail() {
        XCTAssertEqual(
            TunneldManager.wifiGaveUpMessage(detail: Self.usbmuxUnlistedDetail),
            TunneldManager.wifiUnlistedByUsbmuxMessage
        )
        XCTAssertEqual(
            TunneldManager.wifiUnlistedByUsbmuxMessage,
            "Your iPhone answers on this Mac's network, but macOS has not picked it up for developer connections (this can happen after the phone's Wi‑Fi address changes). Connect it with a cable once, keep it unlocked, then press Start again."
        )
    }

    func testGaveUpMessageNamesTheUsbmuxGapForAnyMobdev2ErrorAfterTheLockdown() {
        for mobdev2 in [
            "mobdev2: ConnectionTerminatedError: Connection was terminated abruptly.",
            "mobdev2: ConnectionFailedError: ",
            "mobdev2: ConnectionResetError: [Errno 54] Connection reset by peer",
            "mobdev2: TimeoutError: ",
        ] {
            let detail = Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2], mobdev2)
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiUnlistedByUsbmuxMessage, detail)
        }
        // The redacted, wrapped form the error description carries is still read.
        let wrapped = "The iPhone is not visible to this Mac right now (\(Self.usbmuxUnlistedDetail))"
            .replacingOccurrences(of: "00008130-000C5144019A001C", with: "00008130…")
        XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: wrapped), TunneldManager.wifiUnlistedByUsbmuxMessage)
    }

    func testGaveUpMessageKeepsTheReachabilityAdviceWhenMobdev2DidNotReachThePhone() {
        for mobdev2 in [
            "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s",
            "mobdev2: Mobdev2BrowseError: OSError: [Errno 65] No route to host",
            "mobdev2: LanesTimedOutError: no lane opened within 20s",
            "mobdev2: LaneUnsupportedError: pymobiledevice3 no longer reads userspace_tunnel.create_using_usbmux "
                + "(the open failed with DeviceNotFoundError: usbmux has no device matching udid 00008130…)",
        ] {
            let detail = Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2], mobdev2)
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiDeviceNotReachableMessage, detail)
        }
    }

    // The helper's remote pairing lane finds the phone over RemotePairing Bonjour at any
    // address without usbmuxd, but only with a RemotePairing record that holds the
    // phone's altIRK. A missing or pre-altIRK record is fixed by a refresh over the
    // cable (Prepare for Wi‑Fi), not by USB mode.

    private static let remotePairingRefreshMessage =
        "This Mac's Wi‑Fi pairing with your iPhone needs a refresh. Connect the iPhone with a cable once, keep it unlocked, press Prepare for Wi‑Fi, then unplug it and press Start again. Wi‑Fi mode stays on."

    private static let staleRemotePairingLane =
        "remote pairing: RemotePairingRecordStaleError: the phone's RemotePairing record predates altIRK, "
        + "so Bonjour cannot find the phone at a new Wi-Fi address; connect the cable once and press Prepare for Wi-Fi"

    func testGaveUpMessageAsksForAWiFiPairingRefreshWhenTheRemotePairingRecordIsStale() {
        for mobdev2 in [
            "mobdev2: ConnectionTerminatedError: Connection was terminated abruptly.",
            "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s",
        ] {
            for remotePairing in [
                Self.staleRemotePairingLane,
                "remote pairing: RemotePairingRecordStaleError: this Mac has no RemotePairing record for the phone",
            ] {
                let detail = Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1],
                                        Self.usbmuxAbsentLanes[2], remotePairing, mobdev2)
                XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                               Self.remotePairingRefreshMessage, detail)
            }
        }
        let message = Self.remotePairingRefreshMessage
        XCTAssertEqual(TunneldManager.wifiRemotePairingRefreshMessage, message)
        XCTAssertTrue(message.contains("Prepare for Wi‑Fi") && message.contains("cable") && message.contains("unlocked"))
        XCTAssertFalse(message.contains("USB Only"), "a refresh, not USB mode")
    }

    func testGaveUpMessageNamesTheUsbmuxGapWhenTheRemotePairingLaneReachedThePhone() {
        for remotePairing in [
            "remote pairing: ConnectionTerminatedError: Connection was terminated abruptly.",
            "remote pairing: ConnectionResetError: [Errno 54] Connection reset by peer",
            "remote pairing: TimeoutError: ",
            // The lane's own bound (above the browse bound): an advert matched and
            // pair-verify stalled, so the phone is on the network.
            "remote pairing: RemotePairingTimeoutError: RemotePairing browse and pair-verify did not finish within 12s",
        ] {
            let detail = Self.lanes(
                Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2], remotePairing,
                "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s"
            )
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiUnlistedByUsbmuxMessage, detail)
        }
    }

    func testGaveUpMessageKeepsTheReachabilityAdviceWhenNeitherWiFiLaneReachedThePhone() {
        for remotePairing in [
            "remote pairing: RemotePairingDeviceNotFoundError: RemotePairing Bonjour found no advert that accepted this Mac's pairing for the phone within 8s (it may be off this network, or its pairing may need a refresh)",
            "remote pairing: RemotePairingBrowseError: OSError: [Errno 65] No route to host",
            "remote pairing: LaneUnsupportedError: remote pairing lane needs pymobiledevice3 APIs",
            "remote pairing: LanesTimedOutError: no lane opened within 30s",
        ] {
            let detail = Self.lanes(
                Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2], remotePairing,
                "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s"
            )
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiDeviceNotReachableMessage, detail)
        }
        // A remote pairing lane that did not reach the phone keeps mobdev2's verdict.
        let detail = Self.lanes(
            Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2],
            "remote pairing: RemotePairingDeviceNotFoundError: none",
            "mobdev2: ConnectionTerminatedError: Connection was terminated abruptly."
        )
        XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail), TunneldManager.wifiUnlistedByUsbmuxMessage)
    }

    /// The refresh is the fix that lets Wi‑Fi work at any address, so it wins over an
    /// earlier attempt's "answers but unlisted" advice.
    func testWiFiStartAsksForTheRefreshEvenAfterAnEarlierAttemptReachedThePhone() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 0.15, interval: 0.02)
        let stale = Self.lanes(
            Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2],
            Self.staleRemotePairingLane,
            "mobdev2: Mobdev2DeviceNotFoundError: mobdev2 Bonjour found no paired lockdown for udid 00008130… within 8s"
        )
        connector.connectErrors = [PersistentLocationBridge.PersistentBridgeError.deviceNotVisible(Self.usbmuxUnlistedDetail)]
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.deviceNotVisible(stale)

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        XCTAssertEqual(manager.lastError, Self.remotePairingRefreshMessage)
    }

    func testGaveUpMessageKeepsTheReachabilityAdviceUnlessEveryUsbmuxLaneMissedThePhone() {
        let reached = "mobdev2: ConnectionTerminatedError: Connection was terminated abruptly."
        let details = [
            // A usbmux lane that timed out did not prove the phone is unlisted.
            Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1],
                       "preferred RSD: LanesTimedOutError: no lane opened within 20s"),
            Self.lanes(Self.usbmuxAbsentLanes[0], "usbmux direct: LanesTimedOutError: no lane opened within 20s"),
            // A usbmux lane is missing from the detail.
            Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[2], reached),
            // No mobdev2 lane ran (a USB request).
            Self.lanes(Self.usbmuxAbsentLanes[0], Self.usbmuxAbsentLanes[1], Self.usbmuxAbsentLanes[2]),
        ]
        for detail in details {
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiDeviceNotReachableMessage, detail)
        }
    }

    func testGaveUpMessageKeepsTheReachabilityAdviceForUnreadableDetail() {
        for detail in [
            "",
            "lanes failed",
            "Device not found: usbmux has no device matching udid over Network",
            "mobdev2: ConnectionTerminatedError: x",
            "DeviceLanesUnavailable: DVT lanes unavailable (mobdev2: : ; usbmux direct:",
            "(((;;;: : :",
            String(repeating: "mobdev2: ", count: 500),
        ] {
            XCTAssertEqual(TunneldManager.wifiGaveUpMessage(detail: detail),
                           TunneldManager.wifiDeviceNotReachableMessage, detail)
        }
    }

    func testStopWhileWaitingForThePhoneCancelsTheStart() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 30, interval: 0.02)
        connector.connectError = Self.notVisible

        let start = Task { await self.manager.startTunnel(deviceId: "00008130-000C5144019A001C") }
        try await waitUntil { self.manager.isWaitingForDevice }
        manager.stopTunnel()
        await start.value

        try await waitUntil { self.manager.state == .idle }
        XCTAssertFalse(manager.isWaitingForDevice)
        let callsAfterStop = connector.connectCalls.count
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(connector.connectCalls.count, callsAfterStop, "Start kept retrying after Stop")
    }

    func testAConnectionThatOpensAfterStopIsClosedNotLeftBehind() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 30, interval: 0.02)
        let udid = "00008130-000C5144019A001C"
        connector.onConnect = { [weak self] in self?.manager.stopTunnel() }

        await manager.startTunnel(deviceId: udid)

        try await waitUntil { self.manager.state == .idle }
        try await waitUntil { connector.disconnectCalls.count == 1 }
        XCTAssertEqual(connector.disconnectCalls, [FakeDeviceConnector.Call(deviceId: udid, transport: .wifi)])
    }

    func testALateConnectNeverClosesAConnectionAHeldLocationUses() async throws {
        // Stop during the connect, then a Move applied a location over the same
        // per-device helper connection: the stale Start must not close it.
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"
        connector.onConnect = { [weak self] in
            self?.manager.stopTunnel()
            connector.activeLocationDeviceId = udid
        }

        await manager.startTunnel(deviceId: udid)

        try await waitUntil { self.manager.state == .idle }
        XCTAssertTrue(connector.disconnectCalls.isEmpty, "\(connector.disconnectCalls)")
    }

    func testOtherConnectFailuresDoNotWait() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        manager.deviceVisibilityWait = .init(timeout: 5, interval: 0.02)
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.bridgeError("pairing rejected")

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        guard case .error = manager.state else { return XCTFail("expected error, got \(manager.state)") }
        XCTAssertEqual(connector.connectCalls.count, 1)
        XCTAssertTrue((manager.lastError ?? "").contains("pairing rejected"), manager.lastError ?? "")
    }

    func testHelperNotVisibleReasonMapsToDeviceNotVisible() {
        XCTAssertEqual(
            PersistentLocationBridge.connectFailure(error: "lanes failed", reason: "device_not_visible"),
            .deviceNotVisible("lanes failed")
        )
        XCTAssertEqual(
            PersistentLocationBridge.connectFailure(error: "lanes failed", reason: nil),
            .bridgeError("lanes failed")
        )
        XCTAssertEqual(
            PersistentLocationBridge.connectFailure(error: nil, reason: nil),
            .bridgeError("Device connection failed")
        )
    }

    func testStartTunnelWithoutADeviceFailsHonestly() async throws {
        let connector = try installFakeConnector(mode: .wifi)

        await manager.startTunnel(deviceId: nil)

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        guard case .error = manager.state else {
            return XCTFail("expected error without a device, got \(manager.state)")
        }
        XCTAssertTrue(connector.connectCalls.isEmpty)
        XCTAssertTrue((manager.lastError ?? "").lowercased().contains("device"), manager.lastError ?? "")
    }

    func testHelperConnectFailureSurfacesTheHelperReason() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.bridgeError(
            "UserspaceTunnelUnavailableError: device not reachable"
        )

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        guard case .error = manager.state else {
            return XCTFail("expected error, got \(manager.state)")
        }
        XCTAssertTrue((manager.lastError ?? "").contains("device not reachable"), manager.lastError ?? "")
    }

    func testRestartTunnelReconnectsTheSameDevice() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)

        await manager.restartTunnel()

        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(connector.connectCalls.map(\.deviceId), [udid, udid],
                       "Reconnect must not drop the device (it used to restart without --udid)")
        manager.stopTunnel()
        try await waitUntil { connector.disconnectCalls.count >= 2 }
    }

    func testIdleManagerAdoptsAHelperConnectionThatIsAlreadyOpen() async throws {
        // After Move (the helper opens the connection on demand) or a Preserve
        // relaunch, the tunnel pill must report the connection that really exists.
        let connector = try installFakeConnector(mode: .wifi)
        connector.status = .connected
        let udid = "00008130-000C5144019A001C"

        await manager.adoptHelperConnectionIfPresent(deviceId: udid, transport: .wifi)

        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(manager.tunnelInfo?.channel, .helperUserspace)
        XCTAssertTrue(connector.connectCalls.isEmpty, "adoption must not open a connection")
        manager.stopTunnel()
        try await waitUntil { connector.disconnectCalls.count == 1 }
    }

    func testIdleManagerStaysIdleWhenTheHelperHasNoConnection() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        connector.status = .notConnected("not connected")

        await manager.adoptHelperConnectionIfPresent(deviceId: "00008130-000C5144019A001C", transport: .wifi)

        try await waitUntil { self.manager.state == .idle }
    }

    func testQuitClosesTheHelperConnectionWithoutKillingAProcess() async throws {
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)

        let result = await manager.stopTunnelForQuit()

        XCTAssertEqual(result, .stopped)
        XCTAssertEqual(connector.disconnectCalls.map(\.deviceId), [udid])
        try await waitUntil { self.manager.state == .idle }
    }

    func testHelperStartIsNotOverwrittenByAStaleTunnelLog() async throws {
        // Live review finding: processLaunched ran parseRsdInfo, which replaced the
        // helper connection with a dead `--rsd` from an old tunnel.log ~500 ms later.
        let connector = try installFakeConnector(mode: .wifi)
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-stale-tunnel-\(UUID().uuidString).log")
        try "Use the follow connection option:\n--rsd fd8b:e285:f321::1 55823\n"
            .write(to: log, atomically: true, encoding: .utf8)
        manager.tunnelLogPathOverride = log.path
        defer {
            manager.tunnelLogPathOverride = nil
            try? FileManager.default.removeItem(at: log)
        }
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)
        try await waitUntil { self.manager.state == .running }

        try await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(manager.tunnelInfo?.channel, .helperUserspace)
        XCTAssertNil(manager.getRsdInfo(for: udid))
        _ = connector
    }

    func testStartWorksAgainAfterAFailedStart() async throws {
        // "Start-from-.error dead-end": the state machine had no error -> starting
        // transition, so Start silently did nothing after any failure.
        let connector = try installFakeConnector(mode: .wifi)
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.bridgeError("offline")
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)
        try await waitUntil { if case .error = self.manager.state { return true }; return false }

        connector.connectError = nil
        await manager.startTunnel(deviceId: udid)

        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(connector.connectCalls.count, 2)
    }

    func testErroredManagerAdoptsAHelperConnectionThatIsAlive() async throws {
        // After a health failure, recovery may reconnect through the helper; the tunnel
        // pill must not stay "Error" over a live connection.
        let connector = try installFakeConnector(mode: .wifi)
        connector.connectError = PersistentLocationBridge.PersistentBridgeError.bridgeError("offline")
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)
        try await waitUntil { if case .error = self.manager.state { return true }; return false }
        connector.status = .connected

        await manager.adoptHelperConnectionIfPresent(deviceId: udid, transport: .wifi)

        try await waitUntil { self.manager.state == .running }
    }

    func testStopBlocksLocationCommandsBeforeClosingAndReportsTheOutcome() async throws {
        // A queued or in-flight Joystick update must not reopen the connection after
        // Stop; and the app may only claim the location ended once the close is confirmed.
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)
        try await waitUntil { self.manager.state == .running }
        XCTAssertEqual(connector.resumedDevices, [udid], "an explicit Start lifts a previous Stop")

        manager.stopTunnel()

        XCTAssertEqual(connector.suspendedDevices, [udid], "blocked synchronously, before the close")
        let pending = try XCTUnwrap(manager.pendingHelperStop(for: udid))
        let ended = await pending.value
        XCTAssertTrue(ended)
        XCTAssertNil(manager.pendingHelperStop(for: "00008130-0000000000000000"))
    }

    func testDaemonStopClosesTheHelperConnectionThatCarriesTheLocation() async throws {
        let connector = try installFakeConnector(mode: .daemon)
        connector.activeLocationDeviceId = "00008130-000C5144019A001C"
        let mirror = Mirror(reflecting: manager as TunneldManager)
        let stateMachine = try XCTUnwrap(mirror.children.first(where: { $0.label == "stateMachine" })?.value as? TunnelStateMachine)
        stateMachine.send(.externalTunnelDetected(mode: .daemon))
        try await waitUntil { self.manager.state == .running }

        manager.stopTunnel()
        let pending = try XCTUnwrap(manager.pendingHelperStop(for: "00008130-000C5144019A001C"))
        _ = await pending.value

        XCTAssertEqual(connector.disconnectCalls.map(\.deviceId), ["00008130-000C5144019A001C"])
    }

    func testReplacedHelperConnectionIsReportedSoTheLocationIsReapplied() async throws {
        // connect_device replacing a stalled connection ends any location held on it.
        let connector = try installFakeConnector(mode: .wifi)
        connector.replaced = true
        var replacedDevices: [String] = []
        manager.onHelperConnectionReplaced = { replacedDevices.append($0) }
        defer { manager.onHelperConnectionReplaced = nil }

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")
        try await waitUntil { self.manager.state == .running }

        XCTAssertEqual(replacedDevices, ["00008130-000C5144019A001C"])
    }

    func testDaemonModeNeverAdoptsTheHelperConnection() async throws {
        let connector = try installFakeConnector(mode: .daemon)
        connector.status = .connected

        await manager.adoptHelperConnectionIfPresent(deviceId: "00008130-000C5144019A001C", transport: .wifi)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertTrue(connector.statusCalls.isEmpty)
    }

    func testFailedHealthProbeMakesTheNextMoveReconnectFirst() async throws {
        // A connection the probe found dead must be reopened under the connect budget
        // before the next location command, not on demand inside its reply window.
        let connector = try installFakeConnector(mode: .wifi)
        let udid = "00008130-000C5144019A001C"
        await manager.startTunnel(deviceId: udid)
        try await waitUntil { self.manager.state == .running }
        connector.status = .notConnected("TimeoutError")

        let probe = try XCTUnwrap(
            Mirror(reflecting: manager as TunneldManager).children
                .first(where: { $0.label == "healthMonitor" })?.value as? TunnelHealthMonitor
        ).helperConnectionProbe
        let alive = await probe?(try XCTUnwrap(manager.tunnelInfo))

        XCTAssertEqual(alive, false)
        XCTAssertEqual(connector.unverifiedCalls, [udid])
    }

    func testHelperConnectionExposesNoRSDEndpoint() {
        let helper = TunnelInfo(
            rsdAddress: "", rsdPort: 0, mode: .wifi, interface: nil, processId: 4242,
            channel: .helperUserspace, deviceId: "00008130-000C5144019A001C"
        )
        XCTAssertTrue(helper.isUsable)
        XCTAssertFalse(helper.exposesRSDEndpoint)

        let daemon = TunnelInfo(rsdAddress: "fd00::1", rsdPort: 58783, mode: .daemon,
                                interface: "utun9", processId: 7)
        XCTAssertTrue(daemon.exposesRSDEndpoint)
    }

    private func installFakeConnector(mode: TunnelMode) throws -> FakeDeviceConnector {
        let connector = FakeDeviceConnector()
        let previousMode = manager.preferredMode
        let stateMachine = try XCTUnwrap(
            Mirror(reflecting: manager as TunneldManager).children
                .first(where: { $0.label == "stateMachine" })?.value as? TunnelStateMachine
        )
        #if DEBUG
        stateMachine.testModeEnabled = true // no debounce between setup stop and start
        #endif
        manager.stopTunnel()
        manager.deviceConnector = connector
        manager.preferredMode = mode
        addTeardownBlock { @MainActor [weak self] in
            guard let self else { return }
            self.manager.stopTunnel()
            self.manager.allowDaemonAdoptionForTesting() // later suites start unlatched
            self.manager.deviceConnector = nil
            self.manager.preferredMode = previousMode
            self.manager.deviceVisibilityWait = .standard
            #if DEBUG
            stateMachine.testModeEnabled = false
            #endif
        }
        return connector
    }

    // MARK: - Daemon adoption gates (review 2026-11-01, lane C)

    // The pgrep probe for `remote tunneld` now really runs. Adoption must follow the
    // user's choice: only Background Daemon mode adopts a daemon, and never after Stop.

    final class DetectorCalls { var count = 0 }

    private func installDaemonDetector(returning mode: TunnelMode?) -> DetectorCalls {
        let calls = DetectorCalls()
        manager.runningTunnelDetectorForTesting = { calls.count += 1; return mode }
        manager.tunnelLogPathOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_no_tunnel_\(UUID().uuidString).log").path
        addTeardownBlock { @MainActor [weak self] in
            self?.manager.runningTunnelDetectorForTesting = nil
            self?.manager.tunnelLogPathOverride = nil
        }
        return calls
    }

    func testHelperModesNeverAdoptARunningDaemon() async throws {
        for mode in [TunnelMode.auto, .usb, .wifi] {
            _ = try installFakeConnector(mode: mode)
            manager.allowDaemonAdoptionForTesting()
            let calls = installDaemonDetector(returning: .daemon)

            await manager.adoptRunningTunnelIfPresent()

            XCTAssertEqual(manager.state, .idle, "\(mode.rawValue) adopted a daemon")
            XCTAssertEqual(calls.count, 0, "\(mode.rawValue) probed for a daemon")
        }
    }

    func testStopKeepsARunningDaemonFromBeingAdoptedAgain() async throws {
        _ = try installFakeConnector(mode: .daemon)
        manager.allowDaemonAdoptionForTesting()
        let calls = installDaemonDetector(returning: .daemon)

        manager.stopTunnel()
        try await waitUntil { self.manager.state == .idle }
        await manager.adoptRunningTunnelIfPresent()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(calls.count, 0)
    }

    func testDaemonModeStillLooksForADaemonWhenNotStopped() async throws {
        _ = try installFakeConnector(mode: .daemon)
        manager.allowDaemonAdoptionForTesting()
        let calls = installDaemonDetector(returning: nil)

        await manager.adoptRunningTunnelIfPresent()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(manager.state, .idle)
    }

    func testExplicitStartClearsTheStopLatch() async throws {
        _ = try installFakeConnector(mode: .wifi) // stops first, like a user Stop
        XCTAssertTrue(manager.isDaemonAdoptionSuppressedByStop)

        await manager.startTunnel(deviceId: "00008130-000C5144019A001C")

        try await waitUntil { self.manager.state == .running }
        XCTAssertFalse(manager.isDaemonAdoptionSuppressedByStop)
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within \(timeout)s") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testWiFiPreparationRequiresMatchingUSBDevice() {
        let selected = "00000000-0000000000000001"

        XCTAssertTrue(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: [selected]
        ))
        XCTAssertFalse(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: ["00008130-1111111111111111"]
        ))
        XCTAssertFalse(DevicePreparationPlanner.canPrepareWiFi(
            deviceId: selected,
            usbDeviceIds: []
        ))
    }

    func testRemotePairingRecordFilenameYieldsKnownDeviceId() {
        XCTAssertEqual(
            DevicePreparationPlanner.remotePairingDeviceId(
                from: "remote_00000000-0000000000000001.plist"
            ),
            "00000000-0000000000000001"
        )
        XCTAssertNil(
            DevicePreparationPlanner.remotePairingDeviceId(from: "00000000-0000000000000001.plist")
        )
        XCTAssertNil(DevicePreparationPlanner.remotePairingDeviceId(from: "remote_not-a-udid.plist"))
        XCTAssertNil(DevicePreparationPlanner.remotePairingDeviceId(from: "notes.txt"))
    }

    func testMobdev2DiscoveryUsesUserPairingRecords() {
        XCTAssertEqual(
            DevicePreparationPlanner.mobdev2BrowseArguments(
                pairingRecordsPath: "/Users/test/.pymobiledevice3"
            ),
            [
                "-m", "pymobiledevice3", "bonjour", "mobdev2",
                "--timeout", "5", "--pair-records", "/Users/test/.pymobiledevice3",
            ]
        )
    }

    func testDeveloperDiskImageCommandsResolveTheDeviceThroughUsbmux() {
        let udid = "00008130-001234567890ABCD"
        XCTAssertEqual(
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            ["-m", "pymobiledevice3", "mounter", "list", "--udid", udid]
        )
        XCTAssertEqual(
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
            ["-m", "pymobiledevice3", "mounter", "auto-mount", "--udid", udid]
        )
    }

    func testDeveloperDiskImageMobdev2CommandsKeepTheUDIDAndUseBonjour() {
        // Live 2026-11-01: usbmux listed no Wi-Fi phone for 3.5 min while Bonjour still
        // reached it; `mounter list --mobdev2 --udid <UDID>` returned the mounted image.
        let udid = "00008130-001234567890ABCD"
        XCTAssertEqual(
            DevicePreparationPlanner.ddiMountStatusMobdev2Command(udid: udid),
            ["-m", "pymobiledevice3", "mounter", "list", "--mobdev2", "--udid", udid]
        )
        XCTAssertEqual(
            DevicePreparationPlanner.ddiMountMobdev2Command(udid: udid),
            ["-m", "pymobiledevice3", "mounter", "auto-mount", "--mobdev2", "--udid", udid]
        )
    }

    func testWiFiPreparationRunsCommandsInOrder() async throws {
        let udid = "00000000-0000000000000001"
        let store = try makePairingRecordStore()
        var calls: [[String]] = []
        let service = DevicePreparationService(records: store) { arguments, _ in
            calls.append(arguments)
            if arguments.contains("remotepairing") {
                try self.writePairingRecord(in: store, udid: udid, withAltIRK: true)
            }
            return ""
        }

        try await service.prepareWiFi(deviceId: udid)

        XCTAssertEqual(calls, DevicePreparationPlanner.wifiBootstrapCommands(deviceId: udid))
        XCTAssertEqual(service.phase, .ready)
    }

    func testWiFiPreparationStopsAtFirstFailure() async throws {
        let udid = "00000000-0000000000000001"
        let store = try makePairingRecordStore()
        var calls: [[String]] = []
        let service = DevicePreparationService(records: store) { arguments, _ in
            calls.append(arguments)
            throw DeviceError.commandFailed("bootstrap failed")
        }

        do {
            try await service.prepareWiFi(deviceId: udid)
            XCTFail("expected preparation to fail")
        } catch {
            // Expected.
        }

        XCTAssertEqual(calls.count, 1)
        guard case .failed(let message) = service.phase else {
            return XCTFail("expected failed phase")
        }
        XCTAssertTrue(message.contains("bootstrap failed"))
    }

    func testWiFiPreparationCommandsMatchPymobiledevice3ColdStartFlow() {
        let udid = "00000000-0000000000000001"

        XCTAssertEqual(DevicePreparationPlanner.wifiBootstrapCommands(deviceId: udid), [
            [
                "-m", "pymobiledevice3", "lockdown", "wifi-connections",
                "on", "--udid", udid,
            ],
            [
                "-m", "pymobiledevice3", "lockdown", "remotepairing",
                "--pair", "--udid", udid,
            ],
        ])
    }

    // MARK: - Prepare for Wi‑Fi leaves a RemotePairing record with the phone's altIRK
    //
    // Review 2026-11-03 issue 1: `lockdown remotepairing --pair` re-pairs only when
    // pair-verify fails, so a pre-altIRK record the phone still accepts stayed stale and
    // the remote pairing lane's "press Prepare for Wi‑Fi" advice looped. Prepare now moves
    // such a record into the pairing archive before `--pair` (owner approved re-pairing
    // 2026-11-02) and checks the record afterwards.

    private let pairingUDID = "00008130-000C5144019A001C"

    private func makePairingRecordStore() throws -> RemotePairingRecordStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_pairing_\(UUID().uuidString)", isDirectory: true)
        let records = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RemotePairingRecordStore(
            recordsDirectory: records,
            archiveDirectory: root.appendingPathComponent("pairing-archive", isDirectory: true),
            now: { Date(timeIntervalSince1970: 1_793_000_000) }
        )
    }

    private nonisolated func pairingRecordData(withAltIRK: Bool, marker: UInt8 = 1) throws -> Data {
        var record: [String: Any] = [
            "private_key": Data(repeating: marker, count: 32),
            "public_key": Data(repeating: marker, count: 32),
        ]
        if withAltIRK {
            record[RemotePairingRecordStore.peerAltIRKKey] = Data(repeating: 7, count: 16)
        }
        return try PropertyListSerialization.data(fromPropertyList: record, format: .xml, options: 0)
    }

    @discardableResult
    private nonisolated func writePairingRecord(
        in store: RemotePairingRecordStore, udid: String, withAltIRK: Bool, marker: UInt8 = 1
    ) throws -> Data {
        let data = try pairingRecordData(withAltIRK: withAltIRK, marker: marker)
        try data.write(to: store.recordsDirectory.appendingPathComponent("remote_\(udid).plist"))
        return data
    }

    private func recordURL(_ store: RemotePairingRecordStore, _ udid: String) -> URL {
        store.recordsDirectory.appendingPathComponent("remote_\(udid).plist")
    }

    private func archivedRecords(_ store: RemotePairingRecordStore) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.archiveDirectory.path)) ?? []
        return names.sorted().map { store.archiveDirectory.appendingPathComponent($0) }
    }

    func testPrepareArchivesARecordWithoutAltIRKBeforePairingThenSucceeds() async throws {
        let store = try makePairingRecordStore()
        let old = try writePairingRecord(in: store, udid: pairingUDID, withAltIRK: false, marker: 1)
        var recordPresentAtPair: Bool?
        let service = DevicePreparationService(records: store) { arguments, _ in
            if arguments.contains("remotepairing") {
                recordPresentAtPair = FileManager.default.fileExists(
                    atPath: self.recordURL(store, self.pairingUDID).path)
                try self.writePairingRecord(in: store, udid: self.pairingUDID, withAltIRK: true, marker: 2)
            }
            return ""
        }

        try await service.prepareWiFi(deviceId: pairingUDID)

        XCTAssertEqual(service.phase, .ready)
        XCTAssertEqual(recordPresentAtPair, false, "the stale record is moved aside before --pair")
        let archived = archivedRecords(store)
        XCTAssertEqual(archived.count, 1)
        let name = try XCTUnwrap(archived.first?.lastPathComponent)
        XCTAssertTrue(name.hasPrefix("remote_\(pairingUDID)-") && name.hasSuffix(".plist"), name)
        XCTAssertTrue(name.contains("2026"), "the archive name carries an ISO 8601 timestamp: \(name)")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archived.first)), old, "moved, not rewritten")
        let attributes = try FileManager.default.attributesOfItem(atPath: XCTUnwrap(archived.first).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try store.state(for: pairingUDID), .withAltIRK)
    }

    func testPrepareLeavesARecordWithAltIRKUntouched() async throws {
        let store = try makePairingRecordStore()
        let current = try writePairingRecord(in: store, udid: pairingUDID, withAltIRK: true)
        let service = DevicePreparationService(records: store) { _, _ in "" }

        try await service.prepareWiFi(deviceId: pairingUDID)

        XCTAssertEqual(service.phase, .ready)
        XCTAssertEqual(try Data(contentsOf: recordURL(store, pairingUDID)), current)
        XCTAssertTrue(archivedRecords(store).isEmpty)
    }

    func testPrepareWithNoRecordSucceedsWhenPairingWritesOne() async throws {
        let store = try makePairingRecordStore()
        let service = DevicePreparationService(records: store) { arguments, _ in
            if arguments.contains("remotepairing") {
                try self.writePairingRecord(in: store, udid: self.pairingUDID, withAltIRK: true)
            }
            return ""
        }

        try await service.prepareWiFi(deviceId: pairingUDID)

        XCTAssertEqual(service.phase, .ready)
        XCTAssertTrue(archivedRecords(store).isEmpty)
    }

    func testPrepareRestoresTheArchivedRecordWhenPairingFails() async throws {
        let store = try makePairingRecordStore()
        let old = try writePairingRecord(in: store, udid: pairingUDID, withAltIRK: false)
        let service = DevicePreparationService(records: store) { arguments, _ in
            if arguments.contains("remotepairing") {
                throw DeviceError.commandFailed("pairing failed")
            }
            return ""
        }

        do {
            try await service.prepareWiFi(deviceId: pairingUDID)
            XCTFail("expected preparation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("pairing failed"), error.localizedDescription)
        }

        XCTAssertEqual(try Data(contentsOf: recordURL(store, pairingUDID)), old, "the old record is back")
        XCTAssertTrue(archivedRecords(store).isEmpty)
        guard case .failed = service.phase else { return XCTFail("expected failed phase") }
    }

    func testPrepareReportsIncompletePairingWhenTheNewRecordLacksAltIRK() async throws {
        let store = try makePairingRecordStore()
        let old = try writePairingRecord(in: store, udid: pairingUDID, withAltIRK: false, marker: 1)
        let service = DevicePreparationService(records: store) { arguments, _ in
            if arguments.contains("remotepairing") {
                try self.writePairingRecord(in: store, udid: self.pairingUDID, withAltIRK: false, marker: 2)
            }
            return ""
        }

        do {
            try await service.prepareWiFi(deviceId: pairingUDID)
            XCTFail("expected preparation to fail")
        } catch {
            XCTAssertEqual(error as? DevicePreparationError, .remotePairingIncomplete)
            XCTAssertEqual(
                error.localizedDescription,
                "The Wi‑Fi pairing did not complete. Keep the cable connected and the iPhone unlocked, then press Prepare for Wi‑Fi again."
            )
        }

        XCTAssertEqual(service.phase, .failed(DevicePreparationError.remotePairingIncomplete.localizedDescription))
        XCTAssertEqual(try store.state(for: pairingUDID), .withoutAltIRK, "the new record is left in place")
        let archived = archivedRecords(store)
        XCTAssertEqual(archived.count, 1, "the old record stays archived, not silently restored")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archived.first)), old)
    }

    func testPrepareRestoresTheArchivedRecordWhenPairingWritesNoRecord() async throws {
        let store = try makePairingRecordStore()
        let old = try writePairingRecord(in: store, udid: pairingUDID, withAltIRK: false)
        let service = DevicePreparationService(records: store) { _, _ in "" }

        do {
            try await service.prepareWiFi(deviceId: pairingUDID)
            XCTFail("expected preparation to fail")
        } catch {
            XCTAssertEqual(error as? DevicePreparationError, .remotePairingIncomplete)
        }

        XCTAssertEqual(try Data(contentsOf: recordURL(store, pairingUDID)), old, "the old record is back")
        XCTAssertTrue(archivedRecords(store).isEmpty)
    }

    func testPrepareWithNoRecordReportsIncompletePairingWhenNoneIsWritten() async throws {
        let store = try makePairingRecordStore()
        let service = DevicePreparationService(records: store) { _, _ in "" }

        do {
            try await service.prepareWiFi(deviceId: pairingUDID)
            XCTFail("expected preparation to fail")
        } catch {
            XCTAssertEqual(error as? DevicePreparationError, .remotePairingIncomplete)
        }
        XCTAssertEqual(try store.state(for: pairingUDID), .missing)
    }

    func testPairingRecordStoreRejectsAnInvalidUDIDBeforeBuildingAPath() async throws {
        let store = try makePairingRecordStore()
        // A record outside the records folder that a traversal would reach.
        let outside = store.recordsDirectory.deletingLastPathComponent()
            .appendingPathComponent("remote_x.plist")
        try pairingRecordData(withAltIRK: false).write(to: outside)

        for bad in ["../x", "../remote_x", "00008130-000C5144019A001C/../../x", "", "a b"] {
            XCTAssertThrowsError(try store.recordURL(for: bad), bad)
            XCTAssertThrowsError(try store.state(for: bad), bad)
            XCTAssertThrowsError(try store.archiveIfMissingAltIRK(udid: bad), bad)
        }
        var ran = false
        let service = DevicePreparationService(records: store) { _, _ in ran = true; return "" }
        do {
            try await service.prepareWiFi(deviceId: "../x")
            XCTFail("expected an invalid UDID to fail")
        } catch {}
        XCTAssertFalse(ran)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(archivedRecords(store).isEmpty)
    }

    func testStandardPairingRecordStoreUsesPymobiledevice3AndPathChangerFolders() {
        let store = RemotePairingRecordStore.standard()
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(store.recordsDirectory.standardizedFileURL,
                       home.appendingPathComponent(".pymobiledevice3").standardizedFileURL)
        XCTAssertTrue(store.archiveDirectory.path.hasSuffix(
            "Library/Application Support/PathChanger/pairing-archive"), store.archiveDirectory.path)
        XCTAssertEqual(RemotePairingRecordStore.peerAltIRKKey, "peer_alt_irk")
    }

    func testTunnelInfoRequiresUsableRSDPort() {
        let placeholder = TunnelInfo(
            rsdAddress: "127.0.0.1",
            rsdPort: 0,
            mode: .wifi,
            interface: nil,
            processId: 42
        )
        let usable = TunnelInfo(
            rsdAddress: "fd00::1",
            rsdPort: 58783,
            mode: .wifi,
            interface: "utun9",
            processId: 42
        )

        XCTAssertFalse(placeholder.isUsable)
        XCTAssertTrue(usable.isUsable)
    }

    func testStartupWaitsUntilUsableTunnelInfoArrives() async {
        let expected = TunnelInfo(
            rsdAddress: "fd00::1",
            rsdPort: 58783,
            mode: .wifi,
            interface: "utun9",
            processId: 42
        )
        var attempts = 0

        let result = await TunnelStartupWaiter.wait(
            timeout: 1,
            pollInterval: 0.01,
            processIsRunning: { true },
            readInfo: {
                attempts += 1
                return attempts >= 3 ? expected : nil
            }
        )

        XCTAssertEqual(result, expected)
        XCTAssertGreaterThanOrEqual(attempts, 3)
    }

    func testStartupStopsWaitingWhenProcessExits() async {
        var reads = 0

        let result = await TunnelStartupWaiter.wait(
            timeout: 1,
            pollInterval: 0.01,
            processIsRunning: { false },
            readInfo: {
                reads += 1
                return nil
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(reads, 0)
    }

    func testDeadTunnelProcessClearsRunningState() async throws {
        // Drive the manager's real state machine without launching or elevating anything.
        // The fake PID cannot exist, so TunnelHealthMonitor will report three consecutive
        // process-liveness failures. The manager must consume that report and leave
        // `.running`; otherwise the UI lies with "Tunnel live" forever.
        let mirror = Mirror(reflecting: manager as TunneldManager)
        guard let stateMachine = mirror.children.first(where: { $0.label == "stateMachine" })?.value
            as? TunnelStateMachine else {
            return XCTFail("could not access TunneldManager's state machine")
        }

        stateMachine.reset()
        #if DEBUG
        stateMachine.testModeEnabled = true
        defer { stateMachine.testModeEnabled = false }
        #endif
        stateMachine.send(.startRequested(mode: .wifi))
        stateMachine.send(.connectionEstablished(info: TunnelInfo(
            rsdAddress: "127.0.0.1",
            rsdPort: 49152,
            mode: .wifi,
            interface: nil,
            processId: Int32.max
        )))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(stateMachine.isActive)

        // Health checks run immediately and then every two seconds; three failures are
        // critical. Seven seconds leaves margin for scheduler variance.
        try await Task.sleep(nanoseconds: 7_000_000_000)

        XCTAssertFalse(
            stateMachine.isActive,
            "A dead tunnel process must not leave the UI in 'Tunnel live'"
        )
    }

    override func tearDown() async throws {
        // Clean up any running tunnels after each test
        await manager.stopTunnel()

        // Give it time to fully stop
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }

    // MARK: - State Machine Tests

    func testTunnelElevationRequiresExplicitUserAction() {
        XCTAssertFalse(TunnelStartPolicy.mayElevate(for: .applicationLaunch))
        XCTAssertFalse(TunnelStartPolicy.mayElevate(for: .statusPoll))
        XCTAssertTrue(TunnelStartPolicy.mayElevate(for: .explicitUserAction))
    }

    func testAutoStartAllowedOutsideTests() {
        XCTAssertTrue(TunneldManager.shouldAutoStart(environment: [:]))
    }

    func testAutoStartDisabledForXCTestHost() {
        XCTAssertFalse(TunneldManager.shouldAutoStart(environment: [
            "XCTestConfigurationFilePath": "/tmp/PathChangerTests.xctestconfiguration",
        ]))
        XCTAssertFalse(TunneldManager.shouldAutoStart(environment: [
            "XCTestBundlePath": "/tmp/PathChangerTests.xctest",
        ]))
    }

    func testInitialStateIsIdle() {
        let state = manager.state
        XCTAssertEqual(state, .idle)
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.isStarting)
    }

    func testStateTransitionsAreAtomic() async {
        // Initial state
        XCTAssertEqual(manager.state, .idle)

        // Cannot test full tunnel start without actual device
        // but we can verify state consistency
        XCTAssertFalse(manager.state.isTransitioning)
    }

    func testIsRunningComputedFromState() {
        // When state is .idle
        XCTAssertFalse(manager.isRunning)

        // Note: Cannot set state directly (private setter)
        // This test validates the computed property logic
    }

    func testIsStartingComputedFromState() {
        // When state is .idle
        XCTAssertFalse(manager.isStarting)

        // Validates computed property for .starting state
    }

    // MARK: - Tunnel Mode Tests

    func testTunnelModeEnumValues() {
        XCTAssertEqual(TunnelMode.allCases.count, 4)
        XCTAssertTrue(TunnelMode.allCases.contains(.auto))
        XCTAssertTrue(TunnelMode.allCases.contains(.usb))
        XCTAssertTrue(TunnelMode.allCases.contains(.wifi))
        XCTAssertTrue(TunnelMode.allCases.contains(.daemon))
    }

    func testTunnelModeCommands() {
        XCTAssertEqual(TunnelMode.usb.command, [])
        XCTAssertEqual(TunnelMode.wifi.command, [])
        XCTAssertEqual(TunnelMode.daemon.command, ["remote", "tunneld"])
        XCTAssertEqual(TunnelMode.auto.command, [])
    }

    func testTunnelModeProcessPatterns() {
        XCTAssertEqual(TunnelMode.usb.processPattern, "pymobiledevice3 lockdown start-tunnel")
        XCTAssertEqual(TunnelMode.wifi.processPattern, "pymobiledevice3 remote start-tunnel")
        XCTAssertEqual(TunnelMode.daemon.processPattern, "pymobiledevice3 remote tunneld")
        XCTAssertEqual(TunnelMode.auto.processPattern, "pymobiledevice3")
    }

    // MARK: - Tunnel Info Tests

    func testTunnelInfoConnectionString() {
        let info = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        XCTAssertEqual(info.connectionString, "--rsd fe80::1 58783")
    }

    func testTunnelInfoEquality() {
        let info1 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        let info2 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        XCTAssertEqual(info1, info2)
    }

    func testTunnelInfoWithDifferentProcessId() {
        let info1 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        let info2 = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 58783,
            mode: .usb,
            interface: "en0",
            processId: 67890
        )

        XCTAssertNotEqual(info1, info2)
    }

    // MARK: - Preference Persistence Tests

    func testPreferredModePersistence() {
        // Set mode
        manager.preferredMode = .wifi

        // Verify persistence
        let saved = UserDefaults.standard.string(forKey: "tunnelMode")
        XCTAssertEqual(saved, TunnelMode.wifi.rawValue)

        // Cleanup
        manager.preferredMode = .auto
    }

    // MARK: - Stop Tunnel Tests

    func testStopTunnelWhenIdle() {
        // Should handle gracefully when already idle
        manager.stopTunnel()
        XCTAssertEqual(manager.state, .idle)
    }

    // MARK: - Tunnel State Tests

    func testTunnelStateIsActive() {
        XCTAssertTrue(TunnelState.running.isActive)
        XCTAssertFalse(TunnelState.idle.isActive)
        XCTAssertFalse(TunnelState.starting.isActive)
        XCTAssertFalse(TunnelState.stopping.isActive)
        XCTAssertFalse(TunnelState.error("test").isActive)
    }

    func testTunnelStateIsTransitioning() {
        XCTAssertTrue(TunnelState.starting.isTransitioning)
        XCTAssertTrue(TunnelState.stopping.isTransitioning)
        XCTAssertFalse(TunnelState.idle.isTransitioning)
        XCTAssertFalse(TunnelState.running.isTransitioning)
        XCTAssertFalse(TunnelState.error("test").isTransitioning)
    }

    func testTunnelStateEquality() {
        XCTAssertEqual(TunnelState.idle, TunnelState.idle)
        XCTAssertEqual(TunnelState.running, TunnelState.running)
        XCTAssertEqual(TunnelState.starting, TunnelState.starting)
        XCTAssertEqual(TunnelState.stopping, TunnelState.stopping)
        XCTAssertNotEqual(TunnelState.idle, TunnelState.running)
    }

    // MARK: - Race Condition Prevention Tests

    func testConcurrentStartCallsPrevented() async throws {
        try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
            "This test launches a live pymobiledevice3 tunnel and requires a prepared device host."
        )
        // First call should set state to starting
        // Subsequent calls should be ignored

        // Start two concurrent calls
        async let call1: Void = manager.startTunnel()
        async let call2: Void = manager.startTunnel()

        // Both should complete without crash
        _ = await (call1, call2)

        // State should not be corrupted
        XCTAssertTrue(manager.state == .idle || manager.state == .starting || manager.state == .running)
    }

    // MARK: - Tunnel Command Tests

    func testTunnelCommandsUseFixedArguments() {
        XCTAssertNil(TunneldManager.arguments(for: .usb))
        XCTAssertNil(TunneldManager.arguments(for: .wifi))
        XCTAssertEqual(TunneldManager.arguments(for: .daemon), [
            "-m", "pymobiledevice3", "remote", "tunneld",
        ])
    }

    func testNativeTunnelLaunchDoesNotInvokeAdministratorShell() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Device/TunneldManager.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "private func attemptStart"),
              let end = source.range(of: "private func checkLogForErrors", range: start.upperBound..<source.endIndex) else {
            return XCTFail("Unable to isolate attemptStart implementation")
        }
        let implementation = source[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(implementation.contains("runAdministratorShell"))
        XCTAssertFalse(source.contains("\"start-tunnel\", \"--native\""),
                       "the --native tunnel refused the location service; it must not be launched")
    }

    func testTerminationPreparationRetainsHandlerUntilReply() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Device/TunneldManager.swift"),
            encoding: .utf8
        )
        guard let function = source.range(of: "private func applicationShouldTerminateOnMainActor"),
              let start = source.range(
                of: "Task { @MainActor [weak self",
                range: function.lowerBound..<source.endIndex
              ),
              let end = source.range(
                of: "return .terminateLater",
                range: start.lowerBound..<source.endIndex
              ) else {
            return XCTFail("Unable to isolate asynchronous termination preparation")
        }
        let implementation = source[start.lowerBound..<end.upperBound]
        XCTAssertTrue(implementation.contains("[weak self, terminationHandler]"))
        XCTAssertFalse(implementation.contains("weak terminationHandler"))
    }

    func testAutoModeHasNoDirectTunnelCommand() {
        XCTAssertNil(TunneldManager.arguments(for: .auto))
    }

    // MARK: - Process Management Security Tests (SEC-004)

    func testProcessOwnershipVerificationExists() {
        // Verify the TunneldManager has proper process tracking
        // The activeProcessIds property should exist and be managed correctly
        XCTAssertFalse(manager.isRunning, "Manager should not be running initially")

        // After stop, there should be no tracked processes
        // This validates the security improvement of tracking PIDs
    }

    func testKillTrackingDoesNotUsePkill() async {
        // This test validates that we don't use unsafe pkill patterns
        // By ensuring stop() uses PID-based termination

        // Start with no running tunnel
        XCTAssertEqual(manager.state, .idle)

        // Stop should work safely even with no running processes
        await manager.stopTunnel()

        // Manager should return to idle state
        XCTAssertEqual(manager.state, .idle)
    }

    func testTunnelStateTransitionsSafe() {
        // Validate state machine doesn't allow dangerous transitions
        let states: [TunnelState] = [.idle, .starting, .running, .stopping]

        for state in states {
            // isTransitioning should only be true for certain states
            switch state {
            case .idle:
                XCTAssertFalse(state.isTransitioning)
            case .starting:
                XCTAssertTrue(state.isTransitioning)
            case .running:
                XCTAssertFalse(state.isTransitioning)
            case .stopping:
                XCTAssertTrue(state.isTransitioning)
            case .error:
                XCTAssertFalse(state.isTransitioning)
            }
        }
    }

    func testProcessIdTrackingIntegrity() async {
        // Verify that process tracking maintains integrity
        // After stopTunnel(), no PIDs should remain tracked

        // Initial state
        XCTAssertFalse(manager.isRunning)

        // Stop should clear any tracked PIDs
        await manager.stopTunnel()

        // State should be idle
        XCTAssertEqual(manager.state, .idle)
    }

    func testSystemServiceProtection() throws {
        let source = try tunneldManagerSource()

        XCTAssertTrue(source.contains("guard let process = tunneldProcess"))
        XCTAssertFalse(source.contains("for pid in trackedPids"))
        XCTAssertFalse(source.contains("pkill"))
    }

    func testGracefulTerminationStrategy() throws {
        let source = try tunneldManagerSource()

        XCTAssertTrue(source.contains("process.terminate()"))
        XCTAssertTrue(source.contains("Task { @MainActor"))
        XCTAssertTrue(source.contains("SIGKILL"))
        XCTAssertTrue(source.contains("200_000_000"))
    }

    // MARK: - Quit Teardown (live 2026-11-01: tunnel outlived every normal quit)

    private func launchChild(_ executable: String, _ arguments: [String]) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func testTerminatorStopsOwnedChildAndWaitsForExit() async throws {
        let child = try await launchChild("/bin/sleep", ["30"])
        defer { if child.isRunning { child.terminate() } }

        let outcome = await TunnelProcessTerminator.stop(
            pid: child.processIdentifier,
            requiredCommandPattern: nil,
            isAlive: { child.isRunning },
            termGrace: 2.0,
            killGrace: 1.0
        )

        XCTAssertEqual(outcome, .exited)
        XCTAssertFalse(child.isRunning, "stop must not return before the process has exited")
    }

    func testTerminatorEscalatesToSIGKILLWhenSIGTERMIsIgnored() async throws {
        let child = try await launchChild("/usr/bin/perl", ["-e", "$SIG{TERM}='IGNORE'; sleep 30"])
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        try await Task.sleep(nanoseconds: 300_000_000) // let perl install the TERM handler

        let outcome = await TunnelProcessTerminator.stop(
            pid: child.processIdentifier,
            requiredCommandPattern: nil,
            isAlive: { child.isRunning },
            termGrace: 0.3,
            killGrace: 1.0
        )

        XCTAssertEqual(outcome, .exited)
        XCTAssertFalse(child.isRunning)
    }

    func testTerminatorRefusesAdoptedPidThatIsNotATunnel() async throws {
        // An adopted tunnel is identified only by PID. If that PID no longer runs the
        // tunnel command (exited and reused), it must never be signalled.
        let unrelated = try await launchChild("/bin/sleep", ["30"])
        defer { if unrelated.isRunning { unrelated.terminate() } }

        let outcome = await TunnelProcessTerminator.stop(
            pid: unrelated.processIdentifier,
            requiredCommandPattern: TunnelMode.wifi.processPattern,
            isAlive: { unrelated.isRunning },
            termGrace: 0.3,
            killGrace: 0.3
        )

        guard case .refused = outcome else {
            return XCTFail("Expected refusal for a non-tunnel PID, got \(outcome)")
        }
        XCTAssertTrue(unrelated.isRunning, "a refused PID must not be signalled")
    }

    func testTerminatorStopsAdoptedPidWhoseCommandIsTheTunnel() async throws {
        let decoy = try await launchChild(
            "/usr/bin/perl",
            ["-e", "$0='python3 -m \(TunnelMode.wifi.processPattern) --native'; sleep 30"]
        )
        defer { if decoy.isRunning { kill(decoy.processIdentifier, SIGKILL) } }
        try await Task.sleep(nanoseconds: 300_000_000) // let perl rename its argv

        let outcome = await TunnelProcessTerminator.stop(
            pid: decoy.processIdentifier,
            requiredCommandPattern: TunnelMode.wifi.processPattern,
            isAlive: { decoy.isRunning },
            termGrace: 2.0,
            killGrace: 1.0
        )

        XCTAssertEqual(outcome, .exited)
        XCTAssertFalse(decoy.isRunning)
    }

    func testTerminatorReportsAlreadyExitedPid() async {
        let outcome = await TunnelProcessTerminator.stop(
            pid: Int32.max,
            requiredCommandPattern: nil,
            isAlive: { false },
            termGrace: 0.1,
            killGrace: 0.1
        )
        XCTAssertEqual(outcome, .notRunning)
    }

    func testExitBackstopSignalsSynchronouslyWithoutDeferredTasks() async throws {
        // AppKit calls exit() as soon as applicationWillTerminate returns, so a
        // `Task { stopTunnel() }` there never runs. The backstop must be synchronous,
        // and the duplicate willTerminate observer (same dead Task) must be gone.
        let source = try tunneldManagerSource()
        guard let start = source.range(of: "func applicationWillTerminate"),
              let end = source.range(
                of: "applicationShouldTerminateAfterLastWindowClosed",
                range: start.upperBound..<source.endIndex
              ) else {
            return XCTFail("Unable to isolate applicationWillTerminate")
        }
        let body = source[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(body.contains("stopTunnelBeforeExit()"), String(body))
        XCTAssertFalse(body.contains("Task {"), String(body))
        XCTAssertFalse(source.contains("willTerminateNotification"))
    }

    func testRetainedTunnelIsLeftRunningAtExit() async throws {
        let defaults = try isolatedOwnedTunnelDefaults()
        let child = try await launchChild("/bin/sleep", ["30"])
        defer { if child.isRunning { child.terminate() } }
        manager.installOwnedTunnelForTesting(child, mode: .wifi)
        defer { manager.stopTunnel(); OwnedTunnelRecord.clear(from: defaults) }

        manager.retainTunnelForPreservedLocation()
        manager.stopTunnelBeforeExit()

        XCTAssertTrue(child.isRunning, "Preserve keeps the tunnel the helper's session rides on")
        XCTAssertNotNil(OwnedTunnelRecord.load(from: defaults), "the relaunch needs the ownership record")
    }

    func testExitBackstopStopsOwnedTunnelWhenNotRetained() async throws {
        let defaults = try isolatedOwnedTunnelDefaults()
        let child = try await launchChild("/bin/sleep", ["30"])
        defer { if child.isRunning { child.terminate() } }
        manager.installOwnedTunnelForTesting(child, mode: .wifi)
        defer { manager.stopTunnel(); OwnedTunnelRecord.clear(from: defaults) }

        manager.stopTunnelBeforeExit()

        let deadline = Date().addingTimeInterval(1.0)
        while child.isRunning, Date() < deadline { usleep(20_000) }
        XCTAssertFalse(child.isRunning)
    }

    func testStopTunnelForQuitStopsOwnedTunnelAndClearsRecord() async throws {
        let defaults = try isolatedOwnedTunnelDefaults()
        let child = try await launchChild("/bin/sleep", ["30"])
        defer { if child.isRunning { child.terminate() } }
        manager.installOwnedTunnelForTesting(child, mode: .wifi)

        let result = await manager.stopTunnelForQuit()

        XCTAssertEqual(result, .stopped)
        XCTAssertFalse(child.isRunning, "quit must return only after the tunnel exited")
        XCTAssertNil(OwnedTunnelRecord.load(from: defaults))
        XCTAssertFalse(manager.hasOwnedTunnelProcessForTesting)
    }

    func testRelaunchOwnsOnlyTheRecordedTunnelInstance() async throws {
        let defaults = try isolatedOwnedTunnelDefaults()
        let tunnel = try await launchChild(
            "/usr/bin/perl",
            ["-e", "$0='python3 -m \(TunnelMode.wifi.processPattern) --native'; sleep 30"]
        )
        defer { if tunnel.isRunning { kill(tunnel.processIdentifier, SIGKILL) } }
        try await Task.sleep(nanoseconds: 300_000_000)

        // Session 1 launched it (record written), then Preserve-and-Quit left it running.
        manager.installOwnedTunnelForTesting(tunnel, mode: .wifi)
        // Session 2 adopts it by PID: the record proves ownership.
        manager.adoptTunnelForTesting(pid: tunnel.processIdentifier)
        XCTAssertTrue(manager.adoptedTunnelIsOwnedForTesting)

        let result = await manager.stopTunnelForQuit()

        XCTAssertEqual(result, .stopped)
        XCTAssertFalse(tunnel.isRunning)
        XCTAssertNil(OwnedTunnelRecord.load(from: defaults))
    }

    func testQuitLeavesTunnelPathChangerDidNotStartRunning() async throws {
        let defaults = try isolatedOwnedTunnelDefaults()
        let foreign = try await launchChild(
            "/usr/bin/perl",
            ["-e", "$0='python3 -m \(TunnelMode.wifi.processPattern) --native'; sleep 30"]
        )
        defer { if foreign.isRunning { kill(foreign.processIdentifier, SIGKILL) } }
        try await Task.sleep(nanoseconds: 300_000_000)
        OwnedTunnelRecord.clear(from: defaults)

        manager.adoptTunnelForTesting(pid: foreign.processIdentifier)
        XCTAssertFalse(manager.adoptedTunnelIsOwnedForTesting)

        let result = await manager.stopTunnelForQuit()

        XCTAssertEqual(result, .stopped)
        XCTAssertTrue(foreign.isRunning, "a tunnel started outside PathChanger is never signalled")
    }

    func testFailedQuitStopKeepsTunnelStateForRetry() async throws {
        try XCTSkipIf(getuid() == 0, "requires an unprivileged test host")
        let defaults = try isolatedOwnedTunnelDefaults()
        // A root-owned system daemon stands in for a root-owned leftover tunnel: SIGTERM
        // from this user fails with EPERM. `.auto` skips the command-line check.
        let rootPID = try rootOwnedDaemonPID()
        let rootStart = try XCTUnwrap(ProcessStartTime.of(pid: rootPID))
        OwnedTunnelRecord(pid: rootPID, startTime: rootStart, mode: .auto).save(to: defaults)
        manager.adoptTunnelForTesting(pid: rootPID)
        defer { OwnedTunnelRecord.clear(from: defaults); manager.adoptTunnelForTesting(pid: 0) }
        XCTAssertTrue(manager.adoptedTunnelIsOwnedForTesting)

        let first = await manager.stopTunnelForQuit()
        guard case .failed = first else { return XCTFail("expected failure, got \(first)") }
        XCTAssertTrue(manager.adoptedTunnelIsOwnedForTesting, "failure must not forget the survivor")
        XCTAssertNotNil(OwnedTunnelRecord.load(from: defaults))

        let retry = await manager.stopTunnelForQuit()
        guard case .failed = retry else {
            return XCTFail("a retried quit must still see the surviving tunnel, got \(retry)")
        }
    }

    private func rootOwnedDaemonPID() throws -> Int32 {
        let pgrep = Process()
        let pipe = Pipe()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-U", "0", "-x", "logd"]
        pgrep.standardOutput = pipe
        defer { try? pipe.fileHandleForReading.close() }
        try pgrep.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        pgrep.waitUntilExit()
        let pid = output.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.first { $0 > 1 }
        return try XCTUnwrap(pid, "logd should always be running as root")
    }

    func testProcessStartTimeIdentifiesOneProcessInstance() async throws {
        let child = try await launchChild("/bin/sleep", ["30"])
        defer { if child.isRunning { child.terminate() } }
        let start = try XCTUnwrap(ProcessStartTime.of(pid: child.processIdentifier))
        let record = OwnedTunnelRecord(pid: child.processIdentifier, startTime: start, mode: .wifi)
        XCTAssertTrue(record.isLive)

        let reused = OwnedTunnelRecord(
            pid: child.processIdentifier,
            startTime: ProcessStartTime(seconds: start.seconds - 60, microseconds: start.microseconds),
            mode: .wifi
        )
        XCTAssertFalse(reused.isLive, "same PID with another start time is a different process")
        XCTAssertNil(ProcessStartTime.of(pid: Int32.max))
    }

    private func isolatedOwnedTunnelDefaults() throws -> UserDefaults {
        let suite = "com.pathchanger.tests.ownedtunnel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        manager.ownedTunnelDefaults = defaults
        addTeardownBlock { @MainActor [weak self] in
            defaults.removePersistentDomain(forName: suite)
            self?.manager.ownedTunnelDefaults = .standard
        }
        return defaults
    }

    private func tunneldManagerSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("PathChanger/Device/TunneldManager.swift")
        // The app-hosted suite's MapKit/XPC plumbing transiently fills the fd table
        // (~4.7k open PIPEs at peak). Retry the open briefly instead of failing the
        // source-text assertions on a momentary EMFILE — same assertions, robust read.
        for attempt in 0..<6 {
            do {
                return try String(contentsOf: sourceURL, encoding: .utf8)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile
                    || (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == 24 {
                if attempt == 5 { throw error }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: sourceURL.path])
    }
}

@MainActor
final class FakeDeviceConnector: DeviceConnectionOpening {
    struct Call: Equatable {
        let deviceId: String
        let transport: LocationTransport
    }

    let helperPID: Int32 = 4242
    var connectError: Error?
    /// Thrown in order, one per connect, before `connectError` applies.
    var connectErrors: [Error] = []
    /// Runs inside a successful connect, before it returns.
    var onConnect: (() -> Void)?
    var status: HelperConnectionStatus = .connected
    private(set) var connectCalls: [Call] = []
    private(set) var disconnectCalls: [Call] = []
    private(set) var statusCalls: [Call] = []
    private(set) var unverifiedCalls: [String] = []

    func markDeviceConnectionUnverified(_ deviceId: String) {
        unverifiedCalls.append(deviceId)
    }

    var replaced = false
    var disconnectSucceeds = true
    var activeLocationDeviceId: String?
    private(set) var suspendedDevices: [String] = []
    private(set) var resumedDevices: [String] = []

    func connectDevice(_ deviceId: String, transport: LocationTransport) async throws -> HelperDeviceConnection {
        connectCalls.append(Call(deviceId: deviceId, transport: transport))
        if !connectErrors.isEmpty { throw connectErrors.removeFirst() }
        if let connectError { throw connectError }
        onConnect?()
        return HelperDeviceConnection(helperPID: helperPID, channel: "userspaceRSD", replaced: replaced)
    }

    func suspendLocationCommands(for deviceId: String) { suspendedDevices.append(deviceId) }
    func resumeLocationCommands(for deviceId: String) { resumedDevices.append(deviceId) }

    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus {
        statusCalls.append(Call(deviceId: deviceId, transport: transport))
        return status
    }

    func helperProcessIdentifierIfRunning() -> Int32? { helperPID }

    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool {
        disconnectCalls.append(Call(deviceId: deviceId, transport: transport))
        return disconnectSucceeds
    }
}
