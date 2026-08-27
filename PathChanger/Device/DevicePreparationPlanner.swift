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
                "--state", "on", "--udid", deviceId,
            ],
            [
                "-m", "pymobiledevice3", "lockdown", "remotepairing",
                "--pair", "--udid", deviceId,
            ],
        ]
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

    init(run: @escaping Runner) {
        self.run = run
    }

    /// Prepare an already-trusted USB device for repeatable Wi-Fi discovery/tunneling.
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
            _ = try await run(commands[1], 45)

            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }
}
