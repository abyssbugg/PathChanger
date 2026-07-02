//
//  DeviceManager+Discovery.swift
//  PathChanger
//

import Foundation
import Combine

@MainActor
extension DeviceManager {
    func checkTunneldStatus() async {
        let stateMachineRunning = TunneldManager.shared.isRunning
        let externallyDetectedMode = await TunneldManager.shared.detectRunningTunnelMode()
        updateTunnelRunning(stateMachineRunning || externallyDetectedMode != nil)
    }

    // MARK: Device Discovery - Unified pymobiledevice3
    func refreshDevices() async {
        isScanning = true
        let startTime = Date()
        defer {
            isScanning = false
            // Record discovery statistics (PERF-003)
            let duration = Date().timeIntervalSince(startTime)
            Task {
                await deviceCache.recordDiscoveryDuration(duration)
                await deviceCache.markDiscoveryComplete()
                Logger.debug("Device discovery completed in \(String(format: "%.2f", duration))s", category: .device)
            }
        }

        let usbDevices: [Device]
        let tunnelDevices: [Device]
        let browsedDevices: [Device]

        switch connectionMode {
        case .usb:
            usbDevices = await discoverUSBDevices()
            tunnelDevices = []
            browsedDevices = []
        case .wifi:
            async let tunnelDevicesTask = discoverTunneldAPIDevices()
            async let browsedDevicesTask = discoverTunneldDevices()
            usbDevices = []
            tunnelDevices = await tunnelDevicesTask
            browsedDevices = await browsedDevicesTask
        case .auto:
            async let usbDevicesTask = discoverUSBDevices()
            async let tunnelDevicesTask = discoverTunneldAPIDevices()
            async let browsedDevicesTask = discoverTunneldDevices()
            usbDevices = await usbDevicesTask
            tunnelDevices = await tunnelDevicesTask
            browsedDevices = await browsedDevicesTask
        }

        // Merge devices. In Auto mode keep USB as the preferred visible source when
        // the same UDID is also discoverable over Wi-Fi, so the stable USB path is
        // not masked. Wi-Fi-only mode naturally prefers network sources.
        var deviceMap: [String: Device] = [:]
        for device in usbDevices {
            deviceMap[device.id] = device
        }
        for device in browsedDevices {
            if connectionMode == .wifi || deviceMap[device.id] == nil {
                deviceMap[device.id] = device
            }
        }
        for device in tunnelDevices {
            if connectionMode == .wifi || deviceMap[device.id] == nil {
                deviceMap[device.id] = device
            }
        }

        let discoveredDevices = Array(deviceMap.values)

        // Only update if there's a change to prevent UI flickering
        let currentIds = Set(devices.map { $0.id })
        let newIds = Set(discoveredDevices.map { $0.id })

        if currentIds != newIds || devices.isEmpty {
            devices = discoveredDevices
        } else {
            for (index, device) in devices.enumerated() {
                if let updated = discoveredDevices.first(where: { $0.id == device.id }) {
                    devices[index] = updated
                }
            }
        }

        if let selected = selectedDevice {
            if !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = devices.first
                connectionState = .disconnected
            }
        } else if selectedDevice == nil && !devices.isEmpty {
            selectedDevice = devices.first
        }

        lastError = nil
    }

    // MARK: USB Device Discovery (pymobiledevice3 usbmux list)
    func discoverUSBDevices() async -> [Device] {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "--no-color",
                "usbmux", "list"
            ])

            let baseDevices = parseDeviceListJSON(
                output,
                connectionType: ConnectionType.usb,
                honorJSONConnectionType: false
            )

            // For each USB device, fetch detailed lockdown info to get DeviceName
            // Use cache to avoid repeated lockdown queries (PERF-003)
            var devices: [Device] = []
            var fetchTasks: [Task<Device, Never>] = []

            for baseDevice in baseDevices {
                let task = Task {
                    // Check cache first (PERF-003)
                    if let cachedDevice = await self.deviceCache.getCachedDevice(udid: baseDevice.id) {
                        // Update connection type from base device (may have changed)
                        return Device(
                            id: cachedDevice.id,
                            displayName: cachedDevice.displayName,
                            connectionType: baseDevice.connectionType,
                            productType: cachedDevice.productType,
                            productVersion: cachedDevice.productVersion,
                            deviceName: cachedDevice.deviceName
                        )
                    }

                    // Cache miss - fetch lockdown info
                    if let enrichedDevice = await self.fetchUSBDeviceInfo(udid: baseDevice.id, baseDevice: baseDevice) {
                        // Cache the enriched device info
                        await self.deviceCache.cacheDevice(enrichedDevice, source: .usb)
                        return enrichedDevice
                    } else {
                        // Return base device if lockdown info fetch fails
                        return baseDevice
                    }
                }
                fetchTasks.append(task)
            }

            // Collect all enriched devices in parallel
            for task in fetchTasks {
                let device = await task.value
                devices.append(device)
            }

            return devices
        } catch {
            return []
        }
    }

    // MARK: Fetch USB Device Info via Lockdown
    func fetchUSBDeviceInfo(udid: String, baseDevice: Device) async -> Device? {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "--no-color",
                "lockdown", "info",
                "--udid", udid
            ], timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? baseDevice.displayName
            let productType = info["ProductType"] ?? baseDevice.productType
            let productVersion = info["ProductVersion"] ?? baseDevice.productVersion
            let deviceClass = info["DeviceClass"]

            let displayName: String
            if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                if let version = productVersion {
                    displayName = "\(modelName) (iOS \(version))"
                } else {
                    displayName = modelName
                }
            } else {
                if let version = productVersion {
                    displayName = "\(deviceName) (iOS \(version))"
                } else {
                    displayName = deviceName
                }
            }

            Logger.debug("Enriched USB device info: \(displayName) [\(udid)]", category: .device)

            return Device(
                id: udid,
                displayName: displayName,
                connectionType: baseDevice.connectionType,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            Logger.debug("Failed to fetch USB device lockdown info for \(udid): \(error)", category: .device)
            return nil
        }
    }

    // MARK: Tunneld API Device Discovery
    var tunneldAPIEndpoint: String { AppConstants.Tunnel.tunneldAPIEndpoint }

    func discoverTunneldAPIDevices() async -> [Device] {
        guard let url = URL(string: tunneldAPIEndpoint) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.debug("Tunneld API returned non-200 status", category: .device)
                return []
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
                Logger.debug("Tunneld API returned invalid JSON format", category: .device)
                return []
            }

            let tunnelConnectionType: ConnectionType
            switch TunneldManager.shared.activeMode {
            case .wifi, .daemon:
                tunnelConnectionType = .wifi
            case .auto, .usb, nil:
                tunnelConnectionType = .usb
            }

            Logger.debug("Tunneld API returned \(json.count) device(s)", category: .device)

            // Fetch device info for all UDIDs in parallel with caching (PERF-003)
            var fetchTasks: [Task<Device, Never>] = []

            for udid in json.keys {
                let task = Task {
                    // Check cache first (PERF-003)
                    if let cachedDevice = await self.deviceCache.getCachedDevice(udid: udid) {
                        // Return cached device with the active tunnel transport type.
                        return Device(
                            id: cachedDevice.id,
                            displayName: cachedDevice.displayName,
                            connectionType: tunnelConnectionType,
                            productType: cachedDevice.productType,
                            productVersion: cachedDevice.productVersion,
                            deviceName: cachedDevice.deviceName
                        )
                    }

                    // Cache miss - fetch detailed info
                    if let device = await self.fetchDeviceInfoViaTunnel(udid: udid, connectionType: tunnelConnectionType) {
                        // Cache the device info
                        await self.deviceCache.cacheDevice(device, source: .tunnel)
                        return device
                    } else {
                        // Fallback to basic device with just UDID
                        return Device(
                            id: udid,
                            displayName: tunnelConnectionType == .wifi ? "iOS Device (WiFi Tunnel)" : "iOS Device (USB Tunnel)",
                            connectionType: tunnelConnectionType,
                            productType: nil,
                            productVersion: nil,
                            deviceName: nil
                        )
                    }
                }
                fetchTasks.append(task)
            }

            // Collect all results
            var devices: [Device] = []
            for task in fetchTasks {
                let device = await task.value
                if !device.id.isEmpty {
                    devices.append(device)
                }
            }

            Logger.info("✅ Discovered \(devices.count) device(s) via Tunneld API", category: .device)
            return devices
        } catch {
            Logger.debug("Failed to query tunneld API: \(error.localizedDescription)", category: .device)
            return []
        }
    }

    func fetchDeviceInfoViaTunnel(udid: String, connectionType: ConnectionType) async -> Device? {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "--no-color",
                "lockdown", "info",
                "--tunnel", udid
            ], timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? "iOS Device"
            let productType = info["ProductType"]
            let productVersion = info["ProductVersion"]
            let deviceClass = info["DeviceClass"]

            let displayName: String
            if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                if let version = productVersion {
                    displayName = "\(modelName) (iOS \(version))"
                } else {
                    displayName = modelName
                }
            } else {
                if let version = productVersion {
                    displayName = "\(deviceName) (iOS \(version))"
                } else {
                    displayName = deviceName
                }
            }

            Logger.debug("Fetched device info via tunnel: \(displayName) [\(udid)]", category: .device)

            return Device(
                id: udid,
                displayName: displayName,
                connectionType: connectionType,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            Logger.debug("Failed to fetch device info via tunnel for \(udid): \(error)", category: .device)
            return nil
        }
    }

    func parseDeviceListJSON(
        _ output: String,
        connectionType: ConnectionType,
        honorJSONConnectionType: Bool = true
    ) -> [Device] {
        var devices: [Device] = []

        // Find JSON array in output (skip warnings)
        guard let jsonStart = output.firstIndex(of: "["),
              let jsonEnd = output.lastIndex(of: "]") else {
            Logger.debug("No JSON array found in device list output", category: .device)
            return []
        }

        let jsonString = String(output[jsonStart...jsonEnd])

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.debug("Failed to convert JSON string to data", category: .device)
            return []
        }

        do {
            if let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                for item in jsonArray {
                    guard let udid = item["UniqueDeviceID"] as? String ??
                        item["Identifier"] as? String ??
                        item["UDID"] as? String ??
                        item["udid"] as? String ??
                        item["identifier"] as? String else {
                        continue
                    }

                    let deviceName = item["DeviceName"] as? String ??
                        item["deviceName"] as? String ??
                        item["name"] as? String ??
                        "iOS Device"
                    let productType = item["ProductType"] as? String ?? item["productType"] as? String
                    let productVersion = item["ProductVersion"] as? String ?? item["productVersion"] as? String
                    let deviceClass = item["DeviceClass"] as? String ?? item["deviceClass"] as? String

                    // Determine connection type from JSON if available
                    var connType = connectionType
                    if honorJSONConnectionType,
                       let jsonConnType = item["ConnectionType"] as? String ?? item["connectionType"] as? String {
                        // "Network" means connected via lockdown tunnel
                        connType = jsonConnType.lowercased().contains("usb") ? .usb : .wifi
                    }

                    // Build display name with device name and iOS version
                    // Show model name if device name is generic
                    let displayName: String
                    if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                        // Use model name derived from productType if available
                        let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                        if let version = productVersion {
                            displayName = "\(modelName) (iOS \(version))"
                        } else {
                            displayName = modelName
                        }
                    } else {
                        // Use custom device name
                        if let version = productVersion {
                            displayName = "\(deviceName) (iOS \(version))"
                        } else {
                            displayName = deviceName
                        }
                    }

                    let device = Device(
                        id: udid,
                        displayName: displayName,
                        connectionType: connType,
                        productType: productType,
                        productVersion: productVersion,
                        deviceName: deviceName
                    )

                    // Avoid duplicates by UDID
                    if !devices.contains(where: { $0.id == udid }) {
                        devices.append(device)
                        Logger.debug("Found device: \(displayName) [\(udid)]", category: .device)
                    }
                }
            }
        } catch {
            Logger.debug("Failed to parse device JSON: \(error)", category: .device)
        }

        return devices
    }

    func extractUDID(from text: String) -> String? {
        // UDID is typically 40 hex chars (old) or 25 chars with dashes (new format)
        let patterns = [
            "[0-9a-fA-F]{40}",  // Old format
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{16}"  // New format (00008xxx-xxxxxxxxxxxx)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    // MARK: WiFi/Tunneld Device Discovery
}
