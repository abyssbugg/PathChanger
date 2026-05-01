//
//  ArgumentSanitizer.swift
//  PathChanger
//
//  Input validation and sanitization for security
//

import Foundation

/// Errors related to input validation
enum ValidationError: Error, LocalizedError {
    case invalidCoordinates(latitude: Double, longitude: Double)
    case invalidDeviceUDID(String)
    case invalidArgument(String)
    case pathTraversalAttempt(String)
    case unsupportedIOSVersion(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCoordinates(let lat, let lon):
            return "Invalid coordinates: latitude=\(lat), longitude=\(lon). Valid ranges: latitude -90 to 90, longitude -180 to 180"
        case .invalidDeviceUDID(let udid):
            return "Invalid device UDID format: '\(udid)'. Expected format: 40-character hexadecimal string"
        case .invalidArgument(let arg):
            return "Invalid argument contains prohibited characters: '\(arg)'"
        case .pathTraversalAttempt(let arg):
            return "Security violation: Path traversal attempt detected in '\(arg)'"
        case .unsupportedIOSVersion(let version):
            return "iOS version \(version) is not supported. Location simulation may not work on iOS 18+. Please downgrade to iOS 17.6 or check for pymobiledevice3 updates."
        }
    }
}

/// Sanitizes and validates command-line arguments and user inputs
enum ArgumentSanitizer {
    
    /// Allowed character set for command arguments (alphanumeric + basic punctuation)
    private static let allowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ".-_/:@") // Common safe characters
        return allowed
    }()
    
    /// UDID regex pattern - supports both formats:
    /// - Legacy: 40-character hexadecimal (e.g., 00008030001234567890123456789012345678ab)
    /// - Modern: 00008XXX-XXXXXXXXXXXXXXXX format (e.g., 00008030-001234567890ABCD)
    private static let udidPattern = "^([0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16})$"
    
    /// IPv6 address pattern for RSD addresses
    private static let ipv6Pattern = "^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}(%[0-9a-zA-Z]+)?$"
    
    // MARK: - Coordinate Validation
    
    /// Validate coordinate bounds
    /// - Parameters:
    ///   - latitude: Latitude value
    ///   - longitude: Longitude value
    /// - Throws: ValidationError if coordinates are out of bounds
    static func validateCoordinateBounds(latitude: Double, longitude: Double) throws {
        guard latitude >= -90.0 && latitude <= 90.0 else {
            throw ValidationError.invalidCoordinates(latitude: latitude, longitude: longitude)
        }
        
        guard longitude >= -180.0 && longitude <= 180.0 else {
            throw ValidationError.invalidCoordinates(latitude: latitude, longitude: longitude)
        }
        
        // Check for NaN and Infinity
        guard latitude.isFinite && longitude.isFinite else {
            throw ValidationError.invalidCoordinates(latitude: latitude, longitude: longitude)
        }
    }
    
    // MARK: - UDID Validation
    
    /// Validate device UDID format
    /// - Parameter udid: Device UDID to validate
    /// - Returns: True if valid, false otherwise
    static func isValidDeviceUDID(_ udid: String) -> Bool {
        guard !udid.isEmpty else { return false }
        
        // Check against regex pattern
        guard let regex = try? NSRegularExpression(pattern: udidPattern) else {
            return false
        }
        
        let range = NSRange(udid.startIndex..., in: udid)
        return regex.firstMatch(in: udid, range: range) != nil
    }
    
    /// Validate device UDID and throw error if invalid
    /// - Parameter udid: Device UDID to validate
    /// - Throws: ValidationError if UDID is invalid
    static func validateDeviceUDID(_ udid: String) throws {
        guard isValidDeviceUDID(udid) else {
            throw ValidationError.invalidDeviceUDID(udid)
        }
    }
    
    // MARK: - IPv6 Address Validation
    
    /// Validate IPv6 address format using system-level inet_pton
    ///
    /// This method uses the POSIX inet_pton function for accurate IPv6 validation,
    /// which handles all IPv6 address formats including:
    /// - Full format: 2001:0db8:85a3:0000:0000:8a2e:0370:7334
    /// - Compressed format: 2001:db8:85a3::8a2e:370:7334
    /// - Loopback: ::1
    /// - All zeros: ::
    /// - IPv4-mapped: ::ffff:192.0.2.1
    /// - Interface suffix: fe80::1%en0 (link-local with interface)
    ///
    /// - Parameter address: IPv6 address to validate (may include interface suffix)
    /// - Returns: True if the address is a valid IPv6 address
    static func isValidIPv6Address(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        
        // Remove interface suffix if present (e.g., %en0 for link-local addresses)
        // Store the suffix for validation if needed
        let components = address.components(separatedBy: "%")
        let cleanAddress = components[0]
        
        // Validate interface suffix if present
        if components.count > 1 {
            let interfaceSuffix = components[1]
            // Interface suffix should only contain alphanumeric characters
            guard !interfaceSuffix.isEmpty,
                  interfaceSuffix.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                return false
            }
        }
        
        // Too many % signs is invalid
        guard components.count <= 2 else { return false }
        
        // Use inet_pton for accurate IPv6 validation
        var addr = in6_addr()
        return inet_pton(AF_INET6, cleanAddress, &addr) == 1
    }
    
    /// Validate and extract IPv6 address components
    /// - Parameter address: IPv6 address to parse
    /// - Returns: Tuple of (address, interfaceSuffix) if valid, nil otherwise
    static func parseIPv6Address(_ address: String) -> (address: String, interface: String?)? {
        guard !address.isEmpty else { return nil }
        
        let components = address.components(separatedBy: "%")
        let cleanAddress = components[0]
        let interfaceSuffix = components.count > 1 ? components[1] : nil
        
        // Validate interface suffix if present
        if let suffix = interfaceSuffix {
            guard !suffix.isEmpty,
                  suffix.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                return nil
            }
        }
        
        // Validate the address itself
        var addr = in6_addr()
        guard inet_pton(AF_INET6, cleanAddress, &addr) == 1 else {
            return nil
        }
        
        return (cleanAddress, interfaceSuffix)
    }
    
    // MARK: - Argument Sanitization
    
    /// Sanitize subprocess arguments to prevent injection attacks
    /// - Parameter arguments: Array of arguments to sanitize
    /// - Returns: Sanitized arguments
    /// - Throws: ValidationError if dangerous patterns detected
    static func sanitizeSubprocessArgs(_ arguments: [String]) throws -> [String] {
        return try arguments.map { arg in
            try sanitizeSingleArgument(arg)
        }
    }
    
    /// Sanitize a single argument
    /// - Parameter argument: Argument to sanitize
    /// - Returns: Sanitized argument
    /// - Throws: ValidationError if dangerous patterns detected
    static func sanitizeSingleArgument(_ argument: String) throws -> String {
        // Check for path traversal attempts
        if argument.contains("../") || argument.contains("..\\") {
            throw ValidationError.pathTraversalAttempt(argument)
        }
        
        // Check for command injection attempts
        let dangerousPatterns = [";", "|", "&", "$", "`", "\n", "\r"]
        for pattern in dangerousPatterns {
            if argument.contains(pattern) {
                throw ValidationError.invalidArgument(argument)
            }
        }
        
        // Validate against allowed character set (with exceptions for specific patterns)
        // Allow negative numbers, coordinates, and IPv6 addresses
        if !isSpecialAllowedFormat(argument) {
            let argumentCharSet = CharacterSet(charactersIn: argument)
            if !allowedCharacters.isSuperset(of: argumentCharSet) {
                throw ValidationError.invalidArgument(argument)
            }
        }
        
        return argument
    }
    
    /// Check if argument is a special allowed format (coordinates, IPv6, etc.)
    private static func isSpecialAllowedFormat(_ argument: String) -> Bool {
        // Allow negative numbers (coordinates)
        if argument.starts(with: "-") && Double(argument) != nil {
            return true
        }
        
        // Allow IPv6 addresses
        if isValidIPv6Address(argument) {
            return true
        }
        
        // Allow common flag patterns (--flag)
        if argument.starts(with: "--") && argument.count > 2 {
            let flagName = String(argument.dropFirst(2))
            return CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).isSuperset(of: CharacterSet(charactersIn: flagName))
        }
        
        return false
    }
    
    // MARK: - Port Validation
    
    /// Validate port number
    /// - Parameter port: Port number to validate
    /// - Returns: True if valid (1-65535)
    static func isValidPort(_ port: Int) -> Bool {
        return port > 0 && port <= 65535
    }
    
    /// Validate port number and throw error if invalid
    /// - Parameter port: Port number to validate
    /// - Throws: ValidationError if port is invalid
    static func validatePort(_ port: Int) throws {
        guard isValidPort(port) else {
            throw ValidationError.invalidArgument("Port \(port) is out of valid range (1-65535)")
        }
    }
    
    // MARK: - iOS Version Validation
    
    /// Parse an iOS version string into major, minor, and optional patch components.
    /// Delegates to IOSVersionHelper for consistent parsing behavior across the codebase.
    /// - Parameter versionString: Version string like "17.4", "18.0", "18.0.1"
    /// - Returns: Tuple with major, minor, and optional patch versions, or nil if parsing fails
    static func parseIOSVersion(_ versionString: String) -> (major: Int, minor: Int, patch: Int?)? {
        guard let parsed = IOSVersionHelper.parseVersion(versionString) else {
            return nil
        }
        return (major: parsed.major, minor: parsed.minor, patch: parsed.patch)
    }
    
    /// Check if an iOS version is supported for location simulation.
    /// Delegates to IOSVersionHelper for consistent support checking across the codebase.
    /// - Parameter versionString: Version string like "17.4", "18.0"
    /// - Returns: false if iOS 18+, true if iOS 17 or below, true if parsing fails (fail open)
    static func isIOSVersionSupported(_ versionString: String) -> Bool {
        return IOSVersionHelper.isVersionSupported(versionString)
    }
    
    /// Validate iOS version and throw error if unsupported.
    /// - Parameter versionString: Version string like "17.4", "18.0"
    /// - Throws: ValidationError.unsupportedIOSVersion if iOS 18+
    static func validateIOSVersion(_ versionString: String) throws {
        guard isIOSVersionSupported(versionString) else {
            throw ValidationError.unsupportedIOSVersion(versionString)
        }
    }
}
