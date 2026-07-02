//
//  DeviceManager+RemoteBrowse.swift
//  PathChanger
//

import Foundation
import Combine

@MainActor
extension DeviceManager {
    func discoverTunneldDevices() async -> [Device] {
        do {
            // Use pymobiledevice3 remote browse to find tunneld devices
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "--no-color",
                "remote", "browse",
                "--timeout", "3"
            ], timeout: 5.0)
            if let remoteBrowseDevices = parseRemoteBrowseWiFiDevices(output) {
                return remoteBrowseDevices
            }

            // Try JSON parsing first
            let jsonDevices = parseDeviceListJSON(output, connectionType: ConnectionType.wifi)
            if !jsonDevices.isEmpty {
                return jsonDevices
            }

            // Fallback to text parsing for older versions
            return parseTextDeviceList(output, connectionType: ConnectionType.wifi)
        } catch {
            return []
        }
    }

    func parseRemoteBrowseWiFiDevices(_ output: String) -> [Device]? {
        guard let jsonStart = output.firstIndex(of: "{"),
              let jsonEnd = output.lastIndex(of: "}"),
              let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json.keys.contains("wifi") || json.keys.contains("usb") else {
            return nil
        }

        guard let wifiValue = json["wifi"] else {
            return []
        }

        let udids = extractUDIDs(fromJSONValue: wifiValue)
        return udids.map { udid in
            Device(
                id: udid,
                displayName: "iOS Device (WiFi)",
                connectionType: .wifi,
                productType: nil,
                productVersion: nil,
                deviceName: nil
            )
        }
    }

    func extractUDIDs(fromJSONValue value: Any) -> [String] {
        var results: [String] = []

        func append(_ udid: String) {
            guard !results.contains(udid) else { return }
            results.append(udid)
        }

        func walk(_ value: Any) {
            if let string = value as? String {
                if let udid = extractUDID(from: string) {
                    append(udid)
                }
                return
            }

            if let array = value as? [Any] {
                array.forEach { walk($0) }
                return
            }

            if let dictionary = value as? [String: Any] {
                for key in ["UniqueDeviceID", "Identifier", "UDID", "udid", "identifier"] {
                    if let string = dictionary[key] as? String,
                       let udid = extractUDID(from: string) {
                        append(udid)
                    }
                }
                dictionary.values.forEach { walk($0) }
            }
        }

        walk(value)
        return results
    }

    func parseTextDeviceList(_ output: String, connectionType: ConnectionType) -> [Device] {
        var devices: [Device] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if let udid = extractUDID(from: line) {
                // Avoid duplicates
                if !devices.contains(where: { $0.id == udid }) {
                    let device = Device(
                        id: udid,
                        displayName: "iOS Device (\(connectionType == .wifi ? "WiFi" : "USB"))",
                        connectionType: connectionType,
                        productType: nil,
                        productVersion: nil,
                        deviceName: nil
                    )
                    devices.append(device)
                }
            }
        }

        return devices
    }

    // MARK: Device Info (pymobiledevice3 lockdown info)
    func getDeviceInfo(udid: String, viaUSB: Bool) async -> Device? {
        do {
            let args: [String]
            if !viaUSB && isTunneldRunning {
                args = ["-m", "pymobiledevice3", "--no-color", "lockdown", "info", "--tunnel", udid]
            } else {
                args = ["-m", "pymobiledevice3", "--no-color", "lockdown", "info", "--udid", udid]
            }

            let output = try await runPython(arguments: args, timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? info["DeviceClass"] ?? "iOS Device"
            let productType = info["ProductType"]
            let productVersion = info["ProductVersion"]

            return Device(
                id: udid,
                displayName: "\(deviceName) (\(productVersion ?? "Unknown"))",
                connectionType: viaUSB ? .usb : .wifi,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            return nil
        }
    }

    // MARK: Connection Management
}
