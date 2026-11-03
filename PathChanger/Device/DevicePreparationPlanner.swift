//
//  DevicePreparationPlanner.swift
//  PathChanger
//
//  Exact pymobiledevice3 commands required to turn a trusted USB attachment into a
//  reusable iOS 27 Wi-Fi / RemotePairing session.
//

import Foundation
import Combine

enum DevicePreparationPlanner {

    static func canPrepareWiFi(deviceId: String, usbDeviceIds: Set<String>) -> Bool {
        ArgumentSanitizer.isValidDeviceUDID(deviceId) && usbDeviceIds.contains(deviceId)
    }

    /// Extract a validated UDID from a non-secret RemotePairing record filename.
    static func remotePairingDeviceId(from filename: String) -> String? {
        let prefix = "remote_"
        let suffix = ".plist"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return nil }

        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let deviceId = String(filename[start..<end])

        return ArgumentSanitizer.isValidDeviceUDID(deviceId) ? deviceId : nil
    }

    /// Unprivileged Bonjour discovery for devices known through MobileDevice2 pairing.
    static func mobdev2BrowseArguments(pairingRecordsPath: String) -> [String] {
        [
            "-m", "pymobiledevice3", "bonjour", "mobdev2",
            "--timeout", "5", "--pair-records", pairingRecordsPath,
        ]
    }

    /// Commands which must run unprivileged, in order, while the trusted phone is on USB.
    ///
    /// `wifi-connections on` makes the phone available as a Network device through
    /// usbmuxd. `remotepairing --pair` performs promptless RemotePairing over the trusted
    /// lockdown channel and writes the record consumed by `remote start-tunnel`.
    static func wifiBootstrapCommands(deviceId: String) -> [[String]] {
        guard ArgumentSanitizer.isValidDeviceUDID(deviceId) else { return [] }

        return [
            [
                "-m", "pymobiledevice3", "lockdown", "wifi-connections",
                "on", "--udid", deviceId,
            ],
            [
                "-m", "pymobiledevice3", "lockdown", "remotepairing",
                "--pair", "--udid", deviceId,
            ],
        ]
    }

    /// `mounter list` reports mounted images as a JSON array — an empty array
    /// means the personalized Developer Disk Image is NOT mounted (live root
    /// cause 2026-10-31: injection silently no-ops without it).
    static func ddiMountStatusCommand(udid: String) -> [String] {
        ["-m", "pymobiledevice3", "mounter", "list", "--udid", udid]
    }

    /// `mounter auto-mount` mounts the personalized Developer Disk Image —
    /// required for DVT location injection on iOS 17 and later; silently
    /// missing on CLI-only devices (live root cause 2026-10-31).
    static func ddiMountCommand(udid: String) -> [String] {
        ["-m", "pymobiledevice3", "mounter", "auto-mount", "--udid", udid]
    }

    /// `mounter list` resolved over Bonjour/mobdev2 instead of usbmux. Live 2026-11-01:
    /// usbmux listed no Wi-Fi phone for 3.5 min while Bonjour still reached it, and this
    /// form returned the mounted image list without usbmux.
    static func ddiMountStatusMobdev2Command(udid: String) -> [String] {
        ["-m", "pymobiledevice3", "mounter", "list", "--mobdev2", "--udid", udid]
    }

    /// `mounter auto-mount` resolved over Bonjour/mobdev2 instead of usbmux.
    static func ddiMountMobdev2Command(udid: String) -> [String] {
        ["-m", "pymobiledevice3", "mounter", "auto-mount", "--mobdev2", "--udid", udid]
    }
}

/// This Mac's RemotePairing records (written by pymobiledevice3 as
/// `<recordsDirectory>/remote_<UDID>.plist`) and the archive Prepare for Wi‑Fi moves a
/// record into when it cannot identify the phone over Bonjour.
///
/// A record from before pymobiledevice3 learned the phone's altIRK still pair-verifies,
/// so `lockdown remotepairing --pair` keeps it and never runs pair setup, the only step
/// that saves the altIRK (pymobiledevice3 11.49.1 `RemotePairingProtocol.connect`).
/// Without that key, the helper's remote pairing lane cannot match the phone's advert
/// at a new Wi‑Fi address. Records are moved, never deleted, and their contents are
/// never logged.
struct RemotePairingRecordStore {

    /// pymobiledevice3 `remote/tunnel_service.py` `PEER_ALT_IRK_KEY` (11.49.1).
    static let peerAltIRKKey = "peer_alt_irk"

    enum RecordState: Equatable {
        case missing
        case withoutAltIRK
        case withAltIRK
    }

    let recordsDirectory: URL
    let archiveDirectory: URL
    let now: () -> Date

    init(recordsDirectory: URL, archiveDirectory: URL, now: @escaping () -> Date = Date.init) {
        self.recordsDirectory = recordsDirectory
        self.archiveDirectory = archiveDirectory
        self.now = now
    }

    /// `~/.pymobiledevice3` and `~/Library/Application Support/PathChanger/pairing-archive`.
    static func standard(fileManager: FileManager = .default) -> RemotePairingRecordStore {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return RemotePairingRecordStore(
            recordsDirectory: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".pymobiledevice3", isDirectory: true),
            archiveDirectory: applicationSupport
                .appendingPathComponent("PathChanger/pairing-archive", isDirectory: true)
        )
    }

    /// The record path for a validated UDID; anything else throws before a path exists.
    func recordURL(for udid: String) throws -> URL {
        try ArgumentSanitizer.validateDeviceUDID(udid)
        return recordsDirectory.appendingPathComponent("remote_\(udid).plist", isDirectory: false)
    }

    /// Whether the record exists and holds the phone's altIRK. Only the key's presence
    /// is read. A record that is not a property-list dictionary cannot pair either, so it
    /// counts as one without the altIRK.
    func state(for udid: String) throws -> RecordState {
        let url = try recordURL(for: udid)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data = try Data(contentsOf: url)
        let record = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
            as? [String: Any]
        return record?[Self.peerAltIRKKey] != nil ? .withAltIRK : .withoutAltIRK
    }

    /// Move a record without the altIRK into the archive (0600), so `--pair` runs pair
    /// setup. Returns the archived file, or nil when there was nothing to move.
    func archiveIfMissingAltIRK(udid: String) throws -> URL? {
        guard try state(for: udid) == .withoutAltIRK else { return nil }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: archiveDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let formatter = ISO8601DateFormatter()
        // Basic ISO 8601 (no colons), UTC: 20261103T003000Z.
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        let stamp = formatter.string(from: now())
        var destination = archiveDirectory.appendingPathComponent("remote_\(udid)-\(stamp).plist")
        var suffix = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = archiveDirectory.appendingPathComponent("remote_\(udid)-\(stamp)-\(suffix).plist")
            suffix += 1
        }
        try fileManager.moveItem(at: try recordURL(for: udid), to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return destination
    }

    /// Put an archived record back, only when no record took its place.
    /// Returns false when a record already exists (the archive is kept).
    @discardableResult
    func restore(_ archived: URL, udid: String) throws -> Bool {
        let url = try recordURL(for: udid)
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.moveItem(at: archived, to: url)
        return true
    }
}

enum DevicePreparationError: LocalizedError, Equatable {
    /// `--pair` finished but this Mac still has no RemotePairing record with the altIRK.
    case remotePairingIncomplete

    var errorDescription: String? {
        switch self {
        case .remotePairingIncomplete:
            return "The Wi‑Fi pairing did not complete. Keep the cable connected and the iPhone unlocked, then press Prepare for Wi‑Fi again."
        }
    }
}

@MainActor
final class DevicePreparationService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case enablingWiFi
        case pairing
        case ready
        case failed(String)
    }

    typealias Runner = (_ arguments: [String], _ timeout: TimeInterval) async throws -> String

    @Published private(set) var phase: Phase = .idle

    private let run: Runner
    private let records: RemotePairingRecordStore

    init(records: RemotePairingRecordStore, run: @escaping Runner) {
        self.records = records
        self.run = run
    }

    /// Prepare an already-trusted USB device for repeatable Wi-Fi discovery/tunneling.
    ///
    /// Finishes only when this Mac holds a RemotePairing record with the phone's altIRK
    /// (what the helper's remote pairing lane needs). A record without it is archived
    /// before `--pair` so pairing runs pair setup; the archived record goes back only when
    /// no new record was written.
    func prepareWiFi(deviceId: String) async throws {
        let commands = DevicePreparationPlanner.wifiBootstrapCommands(deviceId: deviceId)
        guard commands.count == 2 else {
            let error = ValidationError.invalidDeviceUDID(deviceId)
            phase = .failed(error.localizedDescription)
            throw error
        }

        do {
            phase = .enablingWiFi
            _ = try await run(commands[0], 30)

            phase = .pairing
            let archived = try records.archiveIfMissingAltIRK(udid: deviceId)
            if archived != nil {
                Logger.info("Moved a RemotePairing record without the phone's altIRK to the pairing archive before re-pairing", category: .device)
            }
            do {
                _ = try await run(commands[1], 45)
            } catch {
                restoreIfNoNewRecord(archived, deviceId: deviceId)
                throw error
            }

            switch try records.state(for: deviceId) {
            case .withAltIRK:
                phase = .ready
            case .missing:
                restoreIfNoNewRecord(archived, deviceId: deviceId)
                throw DevicePreparationError.remotePairingIncomplete
            case .withoutAltIRK:
                // A new record without the altIRK: keep it and the archive as they are.
                throw DevicePreparationError.remotePairingIncomplete
            }
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    private func restoreIfNoNewRecord(_ archived: URL?, deviceId: String) {
        guard let archived else { return }
        do {
            if try records.restore(archived, udid: deviceId) {
                Logger.info("Restored the archived RemotePairing record; no new record was written", category: .device)
            }
        } catch {
            Logger.error("Could not restore the archived RemotePairing record; it stays in the pairing archive (\(type(of: error)))", category: .device)
        }
    }
}
