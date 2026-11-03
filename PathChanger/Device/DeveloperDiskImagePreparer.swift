//
//  DeveloperDiskImagePreparer.swift
//  PathChanger
//
//  Ensures the personalized Developer Disk Image is mounted before DVT
//  location injection. Live-established 2026-10-31: on iOS 27.2 with no DDI
//  mounted, DVT location injection completes without error but silently does
//  not apply; `mounter auto-mount` fixes it (~30 s incl. cryptex download).
//

import Foundation

/// What the location helper reported about the Developer Disk Image, asked over the
/// device connection it holds.
enum HelperDiskImageStatus: Equatable, Sendable {
    case mounted
    case notMounted
    /// No helper, no held connection for the device, or the helper could not ask: the
    /// command path (usbmux, then mobdev2) decides.
    case unavailable(String)

    /// The helper's words for "it holds no connection for this device" and "it is not
    /// running". Only these mean that opening the helper's connection could let it answer.
    static let notConnectedDetail = "not connected"
    static let helperNotRunningDetail = "location helper is not running"
}

/// The outcome of a helper auto-mount over its device connection.
enum HelperDiskImageMountResult: Equatable, Sendable {
    case mounted
    /// The helper asked the phone and the mount failed: a preparation failure.
    case failed(String)
    /// The helper is not running or no longer holds the connection: the mount command
    /// path may still mount.
    case unavailable(String)
}

/// The helper's DDI commands for one UDID; injected so tests need no real bridge.
struct HelperDiskImageChannel: Sendable {
    let status: @Sendable (String) async -> HelperDiskImageStatus
    let mount: @Sendable (String) async -> HelperDiskImageMountResult
    /// Opens the helper's unprivileged device connection (the path Start and every Move
    /// use); true when it is open. Nil, or false in Background Daemon mode: never opened.
    let connect: (@Sendable (String) async -> Bool)?

    init(
        status: @escaping @Sendable (String) async -> HelperDiskImageStatus,
        mount: @escaping @Sendable (String) async -> HelperDiskImageMountResult,
        connect: (@Sendable (String) async -> Bool)? = nil
    ) {
        self.status = status
        self.mount = mount
        self.connect = connect
    }
}

/// Ensures the personalized Developer Disk Image is mounted on the device.
///
/// DDI mount status is device readiness, not connection state: a mount failure
/// must surface as an honest application failure, never as a connection loss.
/// The subprocess runner is injectable so tests run without devices; the
/// production runner executes the managed-runtime python through the hardened
/// `DeviceManager.runPython` path (`ProcessEnvironment.configured()`).
///
/// The location helper is asked first, over the connection it already holds (live
/// 2026-11-03: with the phone held over the helper's remote pairing lane, usbmuxd listed
/// nothing and the phone refused the image mounter over mobdev2, so the command path
/// failed every Move; over the helper's RSD the image mounter answered). When the helper
/// holds no connection for the device, the command path runs as before.
actor DeveloperDiskImagePreparer {
    enum PreparationError: Error, LocalizedError {
        case mountFailed(String)
        case statusUnparseable(String)

        var errorDescription: String? {
            switch self {
            case .mountFailed(let output):
                return "Developer Disk Image mount failed: \(output)"
            case .statusUnparseable(let output):
                return "Could not determine Developer Disk Image mount status: \(output)"
            }
        }
    }

    private let runner: ([String]) async throws -> String
    private let allowsNetworkFallback: @Sendable () async -> Bool
    private let helper: HelperDiskImageChannel?
    private var mountedUDIDs: Set<String> = []

    init(
        runner: @escaping ([String]) async throws -> String,
        allowsNetworkFallback: @escaping @Sendable () async -> Bool = { true },
        helper: HelperDiskImageChannel? = nil
    ) {
        self.runner = runner
        self.allowsNetworkFallback = allowsNetworkFallback
        self.helper = helper
    }

    /// Production runner: managed-runtime python through the hardened
    /// subprocess path, 240 s timeout (cryptex download observed ~30 s).
    /// `DeviceManager` has no shared singleton; the composition root passes
    /// the same instance AppState already owns. The mobdev2 retry is read from the
    /// current connection mode at each usbmux miss: USB-only never crosses to Wi-Fi.
    /// The helper channel is the shared location helper, asked with the same transport
    /// hint its connection was opened with. Its status and mount never start the helper;
    /// its connect opens the helper's unprivileged connection like Move does, only in the
    /// helper modes (never in Background Daemon mode).
    static func live(deviceManager: DeviceManager) -> DeveloperDiskImagePreparer {
        DeveloperDiskImagePreparer(
            runner: { command in
                try await deviceManager.runPython(arguments: command, timeout: 240)
            },
            allowsNetworkFallback: { @MainActor in
                deviceManager.connectionMode != .usb
            },
            helper: HelperDiskImageChannel(
                status: { @MainActor udid in
                    await PersistentLocationBridge.shared.ddiStatus(
                        deviceId: udid, transport: deviceManager.helperConnectTransport(for: udid))
                },
                mount: { @MainActor udid in
                    await PersistentLocationBridge.shared.ddiMount(
                        deviceId: udid, transport: deviceManager.helperConnectTransport(for: udid))
                },
                connect: { @MainActor udid in
                    guard TunneldManager.shared.preferredMode.usesHelperConnection else { return false }
                    return await PersistentLocationBridge.shared.openDeviceConnectionForDiskImage(
                        udid, transport: deviceManager.helperConnectTransport(for: udid))
                }
            )
        )
    }

    func isDeveloperDiskImageMounted(udid: String) async throws -> Bool {
        try await mountStatus(udid: udid).mounted
    }

    /// The mount status, and whether the helper answered it (then the helper mounts too).
    private func mountStatus(udid: String) async throws -> (mounted: Bool, viaHelper: Bool) {
        if mountedUDIDs.contains(udid) { return (true, false) }
        if let helper {
            switch await helperStatus(udid: udid, helper: helper) {
            case .mounted:
                mountedUDIDs.insert(udid)
                return (true, true)
            case .notMounted:
                return (false, true)
            case .unavailable:
                break
            }
        }
        let output = try await runResolvingDevice(
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            mobdev2Fallback: DevicePreparationPlanner.ddiMountStatusMobdev2Command(udid: udid)
        )
        guard let data = output.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw PreparationError.statusUnparseable(String(output.prefix(200)))
        }
        // An image already mounted is cached like one this preparer mounted: the status
        // check costs ~1.2 s and ran before every hop, point and joystick tick (live
        // 2026-11-01). `forget` drops it when the connection is lost (a reboot unmounts).
        if !entries.isEmpty { mountedUDIDs.insert(udid) }
        return (!entries.isEmpty, false)
    }

    /// The helper's answer. The gate runs before anything opened the helper's connection
    /// in Move after a loss and in the recovery burst (review 2026-11-03 issue 3): when the
    /// helper holds no connection (or is not running), open it through the same path Start
    /// and every Move use, then ask again. Only a failed open, or a helper that still
    /// cannot answer, leaves the decision to the command path.
    private func helperStatus(udid: String, helper: HelperDiskImageChannel) async -> HelperDiskImageStatus {
        let first = await helper.status(udid)
        guard case .unavailable(let detail) = first,
              detail == HelperDiskImageStatus.notConnectedDetail
                || detail == HelperDiskImageStatus.helperNotRunningDetail,
              let connect = helper.connect else { return first }
        Logger.info("[Preparation] The helper holds no device connection yet; opening it before the Developer Disk Image check", category: .device)
        guard await connect(udid) else {
            Logger.info("[Preparation] The helper could not open the device connection; the command path checks the Developer Disk Image", category: .device)
            return first
        }
        return await helper.status(udid)
    }

    /// Whether the image is known mounted (no check would run).
    func isKnownMounted(udid: String) -> Bool {
        mountedUDIDs.contains(udid)
    }

    func ensureMounted(udid: String) async throws {
        let status = try await mountStatus(udid: udid)
        if status.mounted { return }
        if status.viaHelper, let helper {
            switch await helper.mount(udid) {
            case .mounted:
                mountedUDIDs.insert(udid)
                return
            case .failed(let message):
                throw PreparationError.mountFailed(String(message.suffix(300)))
            case .unavailable:
                break  // The helper lost the connection since its status: try the command path.
            }
        }
        let output = try await runResolvingDevice(
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
            mobdev2Fallback: DevicePreparationPlanner.ddiMountMobdev2Command(udid: udid)
        )
        guard output.contains("mounted successfully") else {
            throw PreparationError.mountFailed(String(output.suffix(300)))
        }
        mountedUDIDs.insert(udid)
    }

    /// Re-check the mount next time (the device connection was lost).
    func forget(udid: String) {
        mountedUDIDs.remove(udid)
    }

    /// Runs `command` (which resolves `--udid` through usbmux); when usbmux could not
    /// find the device and the network fallback is allowed, runs `mobdev2Fallback` once
    /// and returns its outcome as-is. Live 2026-11-01: usbmux listed no Wi-Fi phone for
    /// 3.5 min while Bonjour still reached it, so every Move failed at this gate although
    /// the helper was connected. In USB-only mode the miss stands (review 2026-11-01 v2
    /// issue 5: the retry would reach the phone over Wi-Fi), so it fails as it did before
    /// the fallback existed.
    private func runResolvingDevice(_ command: [String], mobdev2Fallback: [String]) async throws -> String {
        let output: String
        do {
            output = try await runner(command)
        } catch {
            let text = "\(error) \(error.localizedDescription)"
            guard Self.isUsbmuxDeviceNotFound(text), await allowsNetworkFallback() else { throw error }
            return try await runner(mobdev2Fallback)
        }
        guard Self.isUsbmuxDeviceNotFound(output), await allowsNetworkFallback() else { return output }
        return try await runner(mobdev2Fallback)
    }

    /// pymobiledevice3 11.49 raises `DeviceNotFoundError("Device not found: usbmux has no
    /// device matching udid …")` for an unknown `--udid`, `NoDeviceConnectedError` when
    /// usbmux lists nothing (`service_connection.py`, `cli/cli_common.py`).
    private static func isUsbmuxDeviceNotFound(_ text: String) -> Bool {
        let markers = ["DeviceNotFoundError", "NoDeviceConnectedError", "usbmux has no device matching udid"]
        return markers.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }
}
