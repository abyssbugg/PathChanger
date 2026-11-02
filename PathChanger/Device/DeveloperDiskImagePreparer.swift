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

/// Ensures the personalized Developer Disk Image is mounted on the device.
///
/// DDI mount status is device readiness, not connection state: a mount failure
/// must surface as an honest application failure, never as a connection loss.
/// The subprocess runner is injectable so tests run without devices; the
/// production runner executes the managed-runtime python through the hardened
/// `DeviceManager.runPython` path (`ProcessEnvironment.configured()`).
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
    private var mountedUDIDs: Set<String> = []

    init(
        runner: @escaping ([String]) async throws -> String,
        allowsNetworkFallback: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.runner = runner
        self.allowsNetworkFallback = allowsNetworkFallback
    }

    /// Production runner: managed-runtime python through the hardened
    /// subprocess path, 240 s timeout (cryptex download observed ~30 s).
    /// `DeviceManager` has no shared singleton; the composition root passes
    /// the same instance AppState already owns. The mobdev2 retry is read from the
    /// current connection mode at each usbmux miss: USB-only never crosses to Wi-Fi.
    static func live(deviceManager: DeviceManager) -> DeveloperDiskImagePreparer {
        DeveloperDiskImagePreparer(
            runner: { command in
                try await deviceManager.runPython(arguments: command, timeout: 240)
            },
            allowsNetworkFallback: { @MainActor in
                deviceManager.connectionMode != .usb
            }
        )
    }

    func isDeveloperDiskImageMounted(udid: String) async throws -> Bool {
        if mountedUDIDs.contains(udid) { return true }
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
        return !entries.isEmpty
    }

    func ensureMounted(udid: String) async throws {
        if try await isDeveloperDiskImageMounted(udid: udid) { return }
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
