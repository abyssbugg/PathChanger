//
//  IOSVersionHelper.swift
//  PathChanger
//
//  Shared iOS version parsing and support logic
//

import Foundation

/// Utility type for iOS version parsing and support checking.
/// Provides a single source of truth for version support logic used by both
/// Device model and ArgumentSanitizer.
enum IOSVersionHelper {

    /// Parsed iOS version components
    struct ParsedVersion {
        let major: Int
        let minor: Int
        let patch: Int?
    }

    /// Parse an iOS version string into major, minor, and optional patch components.
    /// Requires at least major.minor format (e.g., "17.4") to succeed.
    ///
    /// - Parameter versionString: Version string like "17.4", "18.0", "18.0.1"
    /// - Returns: ParsedVersion if parsing succeeds, nil otherwise
    ///
    /// Examples:
    /// - "17.4" → ParsedVersion(major: 17, minor: 4, patch: nil)
    /// - "18.0.1" → ParsedVersion(major: 18, minor: 0, patch: 1)
    /// - "17" → nil (single component not supported)
    /// - "invalid" → nil
    /// - "" → nil
    static func parseVersion(_ versionString: String) -> ParsedVersion? {
        guard !versionString.isEmpty else { return nil }

        let components = versionString.split(separator: ".")

        // Require at least major.minor format
        guard components.count >= 2 else { return nil }

        guard let major = Int(String(components[0])),
              let minor = Int(String(components[1])),
              major >= 0, minor >= 0 else {
            return nil
        }

        // Parse optional patch, rejecting negative values
        var patch: Int? = nil
        if components.count >= 3 {
            if let patchValue = Int(String(components[2])), patchValue >= 0 {
                patch = patchValue
            }
            // Negative patch is treated as no patch (nil)
        }

        return ParsedVersion(major: major, minor: minor, patch: patch)
    }

    /// Check if an iOS version should be allowed to attempt location simulation.
    /// Newer iOS versions may have upstream pymobiledevice3/DVT compatibility issues,
    /// but PathChanger should not hard-block them because support can change upstream.
    /// Returns true if parsing fails (fail open for backward compatibility).
    ///
    /// - Parameter versionString: Version string like "17.4", "18.0"
    /// - Returns: true if the app should attempt location simulation
    static func isVersionSupported(_ versionString: String) -> Bool {
        return true
    }

    /// Check whether a version should show a compatibility warning.
    /// iOS 18+ may change Apple's DVT location service behavior, so warn users
    /// while still allowing the real command to run.
    ///
    /// - Parameter versionString: Version string like "17.4", "18.0", "26.5"
    /// - Returns: true for iOS 18+; false for iOS 17 and below or unknown versions
    static func shouldShowLocationCompatibilityWarning(_ versionString: String) -> Bool {
        guard let parsed = parseVersion(versionString) else {
            return false
        }
        return parsed.major >= 18
    }

    /// Extract major version number from a version string.
    /// Requires at least major.minor format to succeed.
    ///
    /// - Parameter versionString: Version string like "17.4"
    /// - Returns: Major version number or nil if parsing fails
    static func majorVersion(_ versionString: String) -> Int? {
        return parseVersion(versionString)?.major
    }

    /// Extract minor version number from a version string.
    /// Requires at least major.minor format to succeed.
    ///
    /// - Parameter versionString: Version string like "17.4"
    /// - Returns: Minor version number or nil if parsing fails
    static func minorVersion(_ versionString: String) -> Int? {
        return parseVersion(versionString)?.minor
    }
}
