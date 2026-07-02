//
//  DeviceManager+Connection.swift
//  PathChanger
//

import Foundation
import Combine

@MainActor
extension DeviceManager {
    func connect(to device: Device) async throws {
        connectionState = .connecting

        // Check if tunneld is running for iOS 17+
        await checkTunneldStatus()

        // For WiFi devices, tunneld must be running
        if device.connectionType == .wifi && !isTunneldRunning {
            connectionState = .error("Tunnel offline")
            throw DeviceError.tunneldNotRunning
        }

        // Verify device is reachable via pymobiledevice3
        do {
            let args: [String]
            if device.connectionType == .wifi && isTunneldRunning {
                args = ["-m", "pymobiledevice3", "--no-color", "lockdown", "info", "--tunnel", device.id]
            } else {
                args = ["-m", "pymobiledevice3", "--no-color", "lockdown", "info", "--udid", device.id]
            }

            let output = try await runPython(arguments: args, timeout: 10.0)
            let normalizedOutput = output.lowercased()
            guard !normalizedOutput.contains("error"),
                  !normalizedOutput.contains("no such option"),
                  output.contains("UniqueDeviceID") || output.contains("ProductVersion") || output.contains("DeviceName") else {
                throw DeviceError.connectionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            selectedDevice = device
            connectionState = .connected
            try await sessionController.startSession(with: device)
        } catch {
            connectionState = .error("Connection failed")
            throw DeviceError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await sessionController.endSession()
        connectionState = .disconnected
    }

    // MARK: Developer Mode Check
    func checkDeveloperMode(for device: Device) async -> Bool {
        do {
            let args: [String]
            if let tunnelInfo = TunneldManager.shared.getRsdInfo(for: device.id) {
                args = ["-m", "pymobiledevice3", "--no-color", "developer", "dvt", "ls", "--rsd", tunnelInfo.rsdAddress, String(tunnelInfo.rsdPort), "/"]
            } else if device.connectionType == .wifi || isTunneldRunning {
                args = ["-m", "pymobiledevice3", "--no-color", "developer", "dvt", "ls", "--tunnel", device.id, "/"]
            } else {
                args = ["-m", "pymobiledevice3", "--no-color", "developer", "dvt", "ls", "--udid", device.id, "/"]
            }

            let output = try await runPython(arguments: args, timeout: 15.0)
            return !output.contains("DeveloperModeError") && !output.contains("ERROR")
        } catch {
            return false
        }
    }

    // MARK: Python Command Execution
    /// Run Python command with proper timeout protection
}
