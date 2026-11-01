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
    private var mountedUDIDs: Set<String> = []

    init(runner: @escaping ([String]) async throws -> String) {
        self.runner = runner
    }

    /// Production runner: managed-runtime python through the hardened
    /// subprocess path, 240 s timeout (cryptex download observed ~30 s).
    /// `DeviceManager` has no shared singleton; the composition root passes
    /// the same instance AppState already owns.
    static func live(deviceManager: DeviceManager) -> DeveloperDiskImagePreparer {
        DeveloperDiskImagePreparer { command in
            try await deviceManager.runPython(arguments: command, timeout: 240)
        }
    }

    func isDeveloperDiskImageMounted(udid: String) async throws -> Bool {
        if mountedUDIDs.contains(udid) { return true }
        let output = try await runner(DevicePreparationPlanner.ddiMountStatusCommand(udid: udid))
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
        let output = try await runner(DevicePreparationPlanner.ddiMountCommand(udid: udid))
        guard output.contains("mounted successfully") else {
            throw PreparationError.mountFailed(String(output.suffix(300)))
        }
        mountedUDIDs.insert(udid)
    }

    /// Re-check the mount next time (the device connection was lost).
    func forget(udid: String) {
        mountedUDIDs.remove(udid)
    }
}
