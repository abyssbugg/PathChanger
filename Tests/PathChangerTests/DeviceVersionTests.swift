//
//  DeviceVersionTests.swift
//  PathChangerTests
//
//  Unit tests for Device iOS version parsing
//

import XCTest
@testable import PathChanger

final class DeviceVersionTests: XCTestCase {
    
    // MARK: - Major Version Parsing Tests
    
    func testIOSMajorVersionParsing() {
        // Test iOS 17
        let device17 = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.4",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device17.iosMajorVersion, 17)
        
        // Test iOS 18
        let device18 = Device(
            id: "test-device-002",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device18.iosMajorVersion, 18)
        
        // Test iOS 16
        let device16 = Device(
            id: "test-device-003",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone14,5",
            productVersion: "16.5",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device16.iosMajorVersion, 16)
    }
    
    // MARK: - Minor Version Parsing Tests
    
    func testIOSMinorVersionParsing() {
        // Test minor version 4
        let device174 = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.4",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device174.iosMinorVersion, 4)
        
        // Test minor version 0
        let device180 = Device(
            id: "test-device-002",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device180.iosMinorVersion, 0)
        
        // Test three-part version
        let device1801 = Device(
            id: "test-device-003",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0.1",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device1801.iosMinorVersion, 0)
    }
    
    // MARK: - Edge Case Tests
    
    func testIOSVersionParsingEdgeCases() {
        // Test nil productVersion
        let deviceNilVersion = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: nil,
            deviceName: "Test Device"
        )
        XCTAssertNil(deviceNilVersion.iosMajorVersion)
        XCTAssertNil(deviceNilVersion.iosMinorVersion)
        
        // Test "Unknown" version string
        let deviceUnknown = Device(
            id: "test-device-002",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "Unknown",
            deviceName: "Test Device"
        )
        XCTAssertNil(deviceUnknown.iosMajorVersion)
        XCTAssertNil(deviceUnknown.iosMinorVersion)
        
        // Test malformed version (single number) - requires major.minor format
        let deviceMalformed = Device(
            id: "test-device-003",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17",
            deviceName: "Test Device"
        )
        // Single-component version should fail to parse (requires major.minor)
        XCTAssertNil(deviceMalformed.iosMajorVersion)
        XCTAssertNil(deviceMalformed.iosMinorVersion)
        // Fail open: malformed version should be treated as supported
        XCTAssertTrue(deviceMalformed.isIOSVersionSupported)
        
        // Test empty version string
        let deviceEmpty = Device(
            id: "test-device-004",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "",
            deviceName: "Test Device"
        )
        XCTAssertNil(deviceEmpty.iosMajorVersion)
        XCTAssertNil(deviceEmpty.iosMinorVersion)
        // Fail open for empty version
        XCTAssertTrue(deviceEmpty.isIOSVersionSupported)
        
        // Test version with non-numeric parts
        let deviceNonNumeric = Device(
            id: "test-device-005",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.x",
            deviceName: "Test Device"
        )
        XCTAssertNil(deviceNonNumeric.iosMajorVersion)
        XCTAssertNil(deviceNonNumeric.iosMinorVersion)
        // Fail open for non-numeric version
        XCTAssertTrue(deviceNonNumeric.isIOSVersionSupported)
    }
    
    // MARK: - Consistency Tests with ArgumentSanitizer
    
    func testConsistencyWithArgumentSanitizer() {
        // Test that Device and ArgumentSanitizer produce consistent results
        let testVersions = [
            "17.4",
            "17.6",
            "18.0",
            "18.1",
            "16.5",
            "17",       // Single component
            "",         // Empty
            "Unknown",  // Invalid
            "17.x",     // Non-numeric
        ]
        
        for version in testVersions {
            let device = Device(
                id: "test-device",
                displayName: "Test iPhone",
                connectionType: .usb,
                productType: "iPhone15,2",
                productVersion: version,
                deviceName: "Test Device"
            )
            
            // Both should produce identical results for isIOSVersionSupported
            let deviceResult = device.isIOSVersionSupported
            let sanitizerResult = ArgumentSanitizer.isIOSVersionSupported(version)
            
            XCTAssertEqual(
                deviceResult,
                sanitizerResult,
                "Inconsistent results for version '\(version)': Device=\(deviceResult), ArgumentSanitizer=\(sanitizerResult)"
            )
        }
    }
    
    // MARK: - Version Support Tests
    
    func testIsIOSVersionSupported() {
        // iOS 17.6 should be supported
        let device176 = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.6",
            deviceName: "Test Device"
        )
        XCTAssertTrue(device176.isIOSVersionSupported)
        
        // iOS 18.0 should NOT be supported
        let device180 = Device(
            id: "test-device-002",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "Test Device"
        )
        XCTAssertFalse(device180.isIOSVersionSupported)
        
        // iOS 18.1 should NOT be supported
        let device181 = Device(
            id: "test-device-003",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.1",
            deviceName: "Test Device"
        )
        XCTAssertFalse(device181.isIOSVersionSupported)
        
        // nil version should be supported (fail open)
        let deviceNilVersion = Device(
            id: "test-device-004",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: nil,
            deviceName: "Test Device"
        )
        XCTAssertTrue(deviceNilVersion.isIOSVersionSupported)
        
        // iOS 16.5 should be supported
        let device165 = Device(
            id: "test-device-005",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone14,5",
            productVersion: "16.5",
            deviceName: "Test Device"
        )
        XCTAssertTrue(device165.isIOSVersionSupported)
    }
    
    // MARK: - iosVersion Computed Property Tests
    
    func testIOSVersionComputedProperty() {
        // Test with valid version
        let device = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.4",
            deviceName: "Test Device"
        )
        XCTAssertEqual(device.iosVersion, "17.4")
        
        // Test with nil version - should return "Unknown"
        let deviceNilVersion = Device(
            id: "test-device-002",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: nil,
            deviceName: "Test Device"
        )
        XCTAssertEqual(deviceNilVersion.iosVersion, "Unknown")
    }
}
