//
//  Device.swift
//  PathChanger
//
//  Device model for iOS devices
//

import Foundation

/// Connection type for device
enum ConnectionType: String, Codable, Hashable {
    case usb = "USB"
    case wifi = "WiFi"
    
    var icon: String {
        switch self {
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
        }
    }
}

/// Represents an iOS device
struct Device: Identifiable, Hashable, Equatable {
    let id: String  // UDID
    let displayName: String
    let connectionType: ConnectionType
    let productType: String?
    let productVersion: String?
    let deviceName: String?
    
    /// Computed property for model name (derived from productType)
    var modelName: String {
        guard let productType = productType else { return "iPhone" }
        return Device.modelNameFrom(productType: productType)
    }
    
    /// iOS version (alias for productVersion)
    var iosVersion: String {
        return productVersion ?? "Unknown"
    }
    
    /// Major iOS version number parsed from productVersion.
    /// Returns nil if productVersion is nil or parsing fails.
    /// Requires major.minor format (e.g., "17.4"); single-component versions return nil.
    /// Example: "17.4" → 17, "18.0.1" → 18, "17" → nil
    var iosMajorVersion: Int? {
        guard let version = productVersion else { return nil }
        return IOSVersionHelper.majorVersion(version)
    }
    
    /// Minor iOS version number parsed from productVersion.
    /// Returns nil if productVersion is nil or parsing fails.
    /// Requires major.minor format (e.g., "17.4"); single-component versions return nil.
    /// Example: "17.4" → 4, "18.0.1" → 0, "17" → nil
    var iosMinorVersion: Int? {
        guard let version = productVersion else { return nil }
        return IOSVersionHelper.minorVersion(version)
    }
    
    /// Whether this device's iOS version is supported for location simulation.
    /// Returns true for iOS 17 and below, false for iOS 18+.
    /// Returns true if version cannot be determined (fail open for backward compatibility).
    /// Uses shared IOSVersionHelper for consistent behavior with ArgumentSanitizer.
    var isIOSVersionSupported: Bool {
        guard let version = productVersion else { return true }
        return IOSVersionHelper.isVersionSupported(version)
    }
    
    /// Whether device is connected wirelessly
    var isWireless: Bool {
        return connectionType == .wifi
    }
    
    init(
        id: String,
        displayName: String,
        connectionType: ConnectionType = .usb,
        productType: String? = nil,
        productVersion: String? = nil,
        deviceName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.connectionType = connectionType
        self.productType = productType
        self.productVersion = productVersion
        self.deviceName = deviceName
    }
    
    // Legacy initializer for compatibility
    init(
        id: String,
        displayName: String,
        modelName: String,
        iosVersion: String,
        isWireless: Bool,
        developerModeEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.connectionType = isWireless ? .wifi : .usb
        self.productType = nil
        self.productVersion = iosVersion
        self.deviceName = displayName
    }
    
    /// Parse device from pymobiledevice3 lockdown info output
    static func from(udid: String, info: [String: String]) -> Device {
        let isWiFi = info["EnableWifiDebugging"] == "true" || info["connection"] == "wifi"
        return Device(
            id: udid,
            displayName: info["DeviceName"] ?? "iOS Device",
            connectionType: isWiFi ? .wifi : .usb,
            productType: info["ProductType"],
            productVersion: info["ProductVersion"],
            deviceName: info["DeviceName"]
        )
    }
    
    static func modelNameFrom(productType: String) -> String {
        let models: [String: String] = [
            // iPhone 16 series
            "iPhone17,5": "iPhone 16 Pro Max",
            "iPhone17,4": "iPhone 16 Pro",
            "iPhone17,3": "iPhone 16 Plus",
            "iPhone17,2": "iPhone 16",
            // iPhone 15 series
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,4": "iPhone 15",
            // iPhone 14 series
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,7": "iPhone 14",
            // iPhone 13 series
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,2": "iPhone 13 Pro",
            // iPhone 12 series
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,2": "iPhone 12",
            "iPhone13,1": "iPhone 12 mini",
        ]
        return models[productType] ?? productType
    }
}
