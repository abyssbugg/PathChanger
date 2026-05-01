//
//  ArgumentSanitizerTests.swift
//  PathChangerTests
//
//  Unit tests for input validation and sanitization
//

import XCTest
@testable import PathChanger

final class ArgumentSanitizerTests: XCTestCase {
    
    // MARK: - Coordinate Validation Tests
    
    func testValidCoordinates() throws {
        XCTAssertNoThrow(try ArgumentSanitizer.validateCoordinateBounds(latitude: 0, longitude: 0))
        XCTAssertNoThrow(try ArgumentSanitizer.validateCoordinateBounds(latitude: 45.5, longitude: -122.6))
        XCTAssertNoThrow(try ArgumentSanitizer.validateCoordinateBounds(latitude: 90, longitude: 180))
        XCTAssertNoThrow(try ArgumentSanitizer.validateCoordinateBounds(latitude: -90, longitude: -180))
    }
    
    func testInvalidLatitude() {
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: 91, longitude: 0))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: -91, longitude: 0))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: Double.nan, longitude: 0))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: Double.infinity, longitude: 0))
    }
    
    func testInvalidLongitude() {
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: 0, longitude: 181))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: 0, longitude: -181))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: 0, longitude: Double.nan))
        XCTAssertThrowsError(try ArgumentSanitizer.validateCoordinateBounds(latitude: 0, longitude: Double.infinity))
    }
    
    // MARK: - UDID Validation Tests
    
    func testValidLegacyUDID() throws {
        // Legacy 40-character hexadecimal format
        let validUDID = "00008030001234567890123456789012345678ab"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(validUDID))
        XCTAssertNoThrow(try ArgumentSanitizer.validateDeviceUDID(validUDID))
        
        // All uppercase
        let upperUDID = "00008030001234567890123456789012345678AB"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(upperUDID))
        
        // Mixed case
        let mixedUDID = "00008030001234567890123456789012345678Ab"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(mixedUDID))
    }
    
    func testValidModernUDID() throws {
        // Modern 25-character format (8-16) for iPhone 12+ devices
        let modernUDID = "00008030-001234567890ABCD"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(modernUDID))
        XCTAssertNoThrow(try ArgumentSanitizer.validateDeviceUDID(modernUDID))
        
        // All lowercase
        let lowerUDID = "00008030-001234567890abcd"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(lowerUDID))
        
        // Typical iPhone 12+ format
        let typicalUDID = "00008101-000A11223344CDEF"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(typicalUDID))
    }
    
    func testValidUDID() throws {
        let validUDID = "00008030001234567890123456789012345678ab"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(validUDID))
        XCTAssertNoThrow(try ArgumentSanitizer.validateDeviceUDID(validUDID))
    }
    
    func testInvalidUDIDLength() {
        // Too short for both formats
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("short"))
        XCTAssertThrowsError(try ArgumentSanitizer.validateDeviceUDID("short"))
        
        // 41 chars (one too many for legacy)
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("00008030001234567890123456789012345678ab1"))
        
        // 39 chars (one too few for legacy)
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("000080300012345678901234567890123456789"))
        
        // Modern format with wrong part lengths
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("0000803-001234567890ABCDE")) // 7-17 instead of 8-16
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("000080300-01234567890ABCD")) // 9-15 instead of 8-16
    }
    
    func testInvalidUDIDFormat() {
        // Modern format without dash
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("00008030001234567890ABCD")) // 24 chars no dash
        
        // Modern format with dash in wrong position
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("0000-8030001234567890ABCD")) // wrong position
        
        // Multiple dashes
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("00008030-0012-34567890ABCD"))
    }
    
    func testInvalidUDIDCharacters() {
        // Non-hex characters in legacy format
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("0000803000123456789012345678901234567xyz"))
        XCTAssertThrowsError(try ArgumentSanitizer.validateDeviceUDID("0000803000123456789012345678901234567xyz"))
        
        // Non-hex characters in modern format
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("00008030-001234567890GHIJ"))
        
        // Special characters
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID("00008030-001234567890!@#$"))
    }
    
    func testEmptyUDID() {
        XCTAssertFalse(ArgumentSanitizer.isValidDeviceUDID(""))
        XCTAssertThrowsError(try ArgumentSanitizer.validateDeviceUDID(""))
    }
    
    // MARK: - IPv6 Validation Tests
    
    func testValidIPv6Loopback() {
        // Loopback address
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("::1"))
    }
    
    func testValidIPv6AllZeros() {
        // All zeros (unspecified address)
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("::"))
    }
    
    func testValidIPv6LinkLocal() {
        // Link-local addresses
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1234:5678:abcd:ef01"))
    }
    
    func testValidIPv6GlobalUnicast() {
        // Global unicast addresses
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("2001:db8::1"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("2001:0db8:85a3:0000:0000:8a2e:0370:7334"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("2001:db8:85a3::8a2e:370:7334"))
    }
    
    func testValidIPv6WithInterfaceSuffix() {
        // Link-local with interface suffix (zone ID)
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1%en0"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1%eth0"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1%lo0"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("fe80::1234:5678:abcd:ef01%awdl0"))
    }
    
    func testValidIPv6IPv4Mapped() {
        // IPv4-mapped IPv6 addresses
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("::ffff:192.0.2.1"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("::ffff:10.0.0.1"))
    }
    
    func testValidIPv6Multicast() {
        // Multicast addresses
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("ff02::1"))
        XCTAssertTrue(ArgumentSanitizer.isValidIPv6Address("ff02::2"))
    }
    
    func testInvalidIPv6PlainIPv4() {
        // Plain IPv4 should be rejected
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("192.168.1.1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("10.0.0.1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("127.0.0.1"))
    }
    
    func testInvalidIPv6NonHexCharacters() {
        // Invalid hex characters
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("gggg::1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("zzzz::1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("2001:xyz8::1"))
    }
    
    func testInvalidIPv6MalformedFormat() {
        // Malformed addresses
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("invalid"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address(":::1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("2001:::1"))
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("2001:db8::1::2"))
    }
    
    func testInvalidIPv6TooManyGroups() {
        // Too many groups (more than 8)
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("1:2:3:4:5:6:7:8:9"))
    }
    
    func testInvalidIPv6EmptyString() {
        // Empty string
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address(""))
    }
    
    func testInvalidIPv6InterfaceSuffix() {
        // Invalid interface suffix
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("fe80::1%")) // Empty suffix
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("fe80::1%%en0")) // Multiple %
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("fe80::1%en0%eth0")) // Multiple interfaces
        XCTAssertFalse(ArgumentSanitizer.isValidIPv6Address("fe80::1%en 0")) // Space in suffix
    }
    
    func testParseIPv6AddressWithoutInterface() {
        // Parse without interface
        let result = ArgumentSanitizer.parseIPv6Address("2001:db8::1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.address, "2001:db8::1")
        XCTAssertNil(result?.interface)
    }
    
    func testParseIPv6AddressWithInterface() {
        // Parse with interface
        let result = ArgumentSanitizer.parseIPv6Address("fe80::1%en0")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.address, "fe80::1")
        XCTAssertEqual(result?.interface, "en0")
    }
    
    func testParseIPv6AddressInvalid() {
        // Invalid address returns nil
        XCTAssertNil(ArgumentSanitizer.parseIPv6Address("invalid"))
        XCTAssertNil(ArgumentSanitizer.parseIPv6Address("192.168.1.1"))
        XCTAssertNil(ArgumentSanitizer.parseIPv6Address(""))
    }
    
    // MARK: - Port Validation Tests
    
    func testValidPorts() throws {
        XCTAssertNoThrow(try ArgumentSanitizer.validatePort(1))
        XCTAssertNoThrow(try ArgumentSanitizer.validatePort(8080))
        XCTAssertNoThrow(try ArgumentSanitizer.validatePort(65535))
    }
    
    func testInvalidPorts() {
        XCTAssertThrowsError(try ArgumentSanitizer.validatePort(0))
        XCTAssertThrowsError(try ArgumentSanitizer.validatePort(-1))
        XCTAssertThrowsError(try ArgumentSanitizer.validatePort(65536))
        XCTAssertThrowsError(try ArgumentSanitizer.validatePort(100000))
    }
    
    // MARK: - Command Injection Prevention Tests
    
    func testCommandInjectionPrevention() {
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "arg2; rm -rf /"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "arg2 | cat /etc/passwd"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "arg2 && malicious"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "$(whoami)"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "`ls`"]))
    }
    
    func testNewlineInjectionPrevention() {
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "arg2\nmalicious"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "arg2\r\nmalicious"]))
    }
    
    // MARK: - Path Traversal Prevention Tests
    
    func testPathTraversalPrevention() {
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "../../../etc/passwd"]))
        XCTAssertThrowsError(try ArgumentSanitizer.sanitizeSubprocessArgs(["arg1", "..\\..\\..\\windows\\system32"]))
    }
    
    // MARK: - Safe Arguments Tests
    
    func testSafeArguments() throws {
        let safeArgs = ["python3", "-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--udid", "00008030001234567890123456789012345678ab", "--", "35.6762", "139.6503"]
        
        let sanitized = try ArgumentSanitizer.sanitizeSubprocessArgs(safeArgs)
        XCTAssertEqual(sanitized, safeArgs)
    }
    
    func testArgumentsWithSpecialCharacters() throws {
        let args = ["-m", "pymobiledevice3", "--rsd", "fe80::1", "8080"]
        let sanitized = try ArgumentSanitizer.sanitizeSubprocessArgs(args)
        XCTAssertEqual(sanitized, args)
    }
    
    // MARK: - iOS Version Validation Tests
    
    func testParseValidIOSVersions() {
        // Test basic two-part versions
        let result170 = ArgumentSanitizer.parseIOSVersion("17.0")
        XCTAssertNotNil(result170)
        XCTAssertEqual(result170?.major, 17)
        XCTAssertEqual(result170?.minor, 0)
        XCTAssertNil(result170?.patch)
        
        let result174 = ArgumentSanitizer.parseIOSVersion("17.4")
        XCTAssertNotNil(result174)
        XCTAssertEqual(result174?.major, 17)
        XCTAssertEqual(result174?.minor, 4)
        XCTAssertNil(result174?.patch)
        
        let result180 = ArgumentSanitizer.parseIOSVersion("18.0")
        XCTAssertNotNil(result180)
        XCTAssertEqual(result180?.major, 18)
        XCTAssertEqual(result180?.minor, 0)
        XCTAssertNil(result180?.patch)
        
        // Test three-part version with patch
        let result1801 = ArgumentSanitizer.parseIOSVersion("18.0.1")
        XCTAssertNotNil(result1801)
        XCTAssertEqual(result1801?.major, 18)
        XCTAssertEqual(result1801?.minor, 0)
        XCTAssertEqual(result1801?.patch, 1)
    }
    
    func testParseInvalidIOSVersions() {
        // Empty string
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion(""))
        
        // Invalid format - no dot
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("invalid"))
        
        // Single component (missing minor)
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17"))
        
        // Non-numeric components
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17.x"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("x.0"))
    }
    
    func testIOSVersionSupported() {
        // iOS 17 and below should be supported
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("17.0"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("17.6"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("16.5"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("15.0"))
        
        // Invalid versions should fail open (return true)
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("invalid"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported(""))
    }
    
    func testIOSVersionUnsupported() {
        // iOS 18+ should not be supported
        XCTAssertFalse(ArgumentSanitizer.isIOSVersionSupported("18.0"))
        XCTAssertFalse(ArgumentSanitizer.isIOSVersionSupported("18.1"))
        XCTAssertFalse(ArgumentSanitizer.isIOSVersionSupported("19.0"))
        XCTAssertFalse(ArgumentSanitizer.isIOSVersionSupported("20.0"))
    }
    
    func testIOSVersionValidationThrows() {
        // iOS 18+ should throw
        XCTAssertThrowsError(try ArgumentSanitizer.validateIOSVersion("18.0")) { error in
            guard case ValidationError.unsupportedIOSVersion(let version) = error else {
                XCTFail("Expected unsupportedIOSVersion error")
                return
            }
            XCTAssertEqual(version, "18.0")
        }
        
        XCTAssertThrowsError(try ArgumentSanitizer.validateIOSVersion("18.1"))
        XCTAssertThrowsError(try ArgumentSanitizer.validateIOSVersion("19.0"))
    }
    
    func testIOSVersionValidationPasses() {
        // iOS 17 and below should not throw
        XCTAssertNoThrow(try ArgumentSanitizer.validateIOSVersion("17.0"))
        XCTAssertNoThrow(try ArgumentSanitizer.validateIOSVersion("17.6"))
        XCTAssertNoThrow(try ArgumentSanitizer.validateIOSVersion("16.5"))
        
        // Invalid versions fail open (don't throw)
        XCTAssertNoThrow(try ArgumentSanitizer.validateIOSVersion("invalid"))
    }
    
    // MARK: - iOS Version Edge Cases (Consistent Parsing)
    
    func testIOSVersionEdgeCases() {
        // Single component should fail to parse (requires major.minor)
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("18"))
        
        // Single component should fail open for isIOSVersionSupported
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("17"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("18"))
        
        // Empty string should fail to parse
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion(""))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported(""))
        
        // Non-numeric minor should fail to parse
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17.x"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("x.0"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("17.x"))
        
        // Whitespace should fail to parse
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion(" 17.0"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17.0 "))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported(" 17.0"))
        
        // Negative numbers should fail to parse
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("-17.0"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("17.-4"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("-17.0"))
        
        // Special strings should fail to parse
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("Unknown"))
        XCTAssertNil(ArgumentSanitizer.parseIOSVersion("N/A"))
        XCTAssertTrue(ArgumentSanitizer.isIOSVersionSupported("Unknown"))
    }
    
    func testIOSVersionParsingConsistency() {
        // Valid versions should parse correctly
        let version174 = ArgumentSanitizer.parseIOSVersion("17.4")
        XCTAssertNotNil(version174)
        XCTAssertEqual(version174?.major, 17)
        XCTAssertEqual(version174?.minor, 4)
        XCTAssertNil(version174?.patch)
        
        let version1801 = ArgumentSanitizer.parseIOSVersion("18.0.1")
        XCTAssertNotNil(version1801)
        XCTAssertEqual(version1801?.major, 18)
        XCTAssertEqual(version1801?.minor, 0)
        XCTAssertEqual(version1801?.patch, 1)
        
        // Four-part version should parse first three
        let version18012 = ArgumentSanitizer.parseIOSVersion("18.0.1.2")
        XCTAssertNotNil(version18012)
        XCTAssertEqual(version18012?.major, 18)
        XCTAssertEqual(version18012?.minor, 0)
        XCTAssertEqual(version18012?.patch, 1)
    }
}
