//
//  ProcessEnvironment.swift
//  PathChanger
//
//  Centralized environment configuration for subprocess execution.
//  Provides secure, consistent environment variables for all process operations.
//

import Foundation

enum AppRuntimeEnvironment {

    /// Whether this process is hosting a test bundle.
    ///
    /// Detection is deliberately belt-and-braces. Sniffing environment variables alone is
    /// not reliable: the SwiftPM runner used by Xcode 16+ / Swift 6 launches the bundle via
    /// `swiftpm-testing-helper` and sets no `XCTest*` variables at all. That left this guard
    /// silently open, so the app host was free to start privileged background work — and
    /// raise an administrator prompt — in the middle of `swift test`.
    ///
    /// The class lookup is the authoritative signal, because the test framework is only ever
    /// linked into a test host. The environment check is retained so the pure, injectable
    /// form below stays usable from unit tests.
    static var isHostingTests: Bool {
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return isHostingTests(environment: ProcessInfo.processInfo.environment)
    }

    /// Pure, injectable form of ``isHostingTests`` for unit testing.
    static func isHostingTests(environment: [String: String]) -> Bool {
        environment.keys.contains { key in
            key.hasPrefix("XCTest")
                || key.hasPrefix("SWIFT_TESTING")
                || key.hasPrefix("SWIFTPM_TESTING")
        }
    }

    static var allowsAutomaticStartup: Bool {
        !isHostingTests
    }

    static func allowsAutomaticStartup(environment: [String: String]) -> Bool {
        !isHostingTests(environment: environment)
    }
}

/// Centralized environment configuration for subprocess execution
///
/// This enum provides a single source of truth for environment variables used
/// when launching Python subprocesses. All process execution code should use
/// `ProcessEnvironment.configured()` to ensure consistent behavior across the app.
///
/// # Security Rationale
/// The PATH variable is restricted to well-known system locations to prevent
/// path injection attacks. The order of paths prioritizes commonly-used Python
/// installation locations while maintaining security boundaries.
///
/// # Example Usage
/// ```swift
/// let process = Process()
/// process.environment = ProcessEnvironment.configured()
/// ```
public enum ProcessEnvironment {

    // MARK: - PATH Configuration

    /// Approved PATH directories in priority order
    ///
    /// # Security Note
    /// Only well-known, system-managed directories are included.
    /// User-writable bin directories (like ~/.local/bin) are intentionally excluded
    /// to prevent local privilege escalation attacks.
    public static let approvedPathDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    // MARK: - Public API

    /// Generate a fully configured environment for subprocess execution
    ///
    /// This method creates an environment dictionary suitable for Process.environment.
    /// It includes:
    /// - Restricted PATH with approved directories only
    /// - Removal of parent Python, virtual-environment, and pip overrides
    /// - All other current process environment variables
    ///
    /// # Thread Safety
    /// This method is thread-safe and can be called from any queue.
    ///
    /// - Returns: Environment dictionary ready for use with Process
    public static func configured() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        env["PATH"] = approvedPathDirectories.joined(separator: ":")
        env.removeValue(forKey: "PYTHONPATH")
        env.removeValue(forKey: "PYTHONHOME")
        env.removeValue(forKey: "VIRTUAL_ENV")
        for key in env.keys.filter({ $0.hasPrefix("PIP_") }) {
            env.removeValue(forKey: key)
        }

        return env
    }

    /// Generate a minimal environment with only essential variables
    ///
    /// Use this for processes that should run with minimal environmental influence.
    /// This is more secure but may cause issues with some Python packages.
    ///
    /// - Returns: Minimal environment dictionary
    public static func minimal() -> [String: String] {
        var env: [String: String] = [:]

        // Only include essential PATH
        env["PATH"] = approvedPathDirectories.joined(separator: ":")

        // Preserve locale settings for proper text handling
        if let lang = ProcessInfo.processInfo.environment["LANG"] {
            env["LANG"] = lang
        }
        if let lcAll = ProcessInfo.processInfo.environment["LC_ALL"] {
            env["LC_ALL"] = lcAll
        }

        // Preserve HOME for packages that need it
        env["HOME"] = NSHomeDirectory()

        // Preserve USER for ownership checks
        if let user = ProcessInfo.processInfo.environment["USER"] {
            env["USER"] = user
        }

        return env
    }

    /// Check if a path is within the approved PATH directories
    ///
    /// - Parameter path: Full path to validate
    /// - Returns: True if the path starts with an approved directory
    public static func isPathApproved(_ path: String) -> Bool {
        guard path.hasPrefix("/") else {
            return false
        }

        let standardizedPath = (path as NSString).standardizingPath
        return approvedPathDirectories.contains { approvedDir in
            standardizedPath.hasPrefix(approvedDir + "/") || standardizedPath == approvedDir
        }
    }

    /// Get the configured PATH as a string
    ///
    /// - Returns: Colon-separated PATH string
    public static var pathString: String {
        approvedPathDirectories.joined(separator: ":")
    }
}

// MARK: - Environment Keys

extension ProcessEnvironment {
    /// Well-known environment variable keys
    public enum Keys {
        public static let path = "PATH"
        public static let pythonPath = "PYTHONPATH"
        public static let home = "HOME"
        public static let user = "USER"
        public static let lang = "LANG"
        public static let lcAll = "LC_ALL"
        public static let term = "TERM"
        public static let shell = "SHELL"
        public static let testLocationInjector = "PATHCHANGER_TEST_LOCATION_INJECTOR"
    }
}
