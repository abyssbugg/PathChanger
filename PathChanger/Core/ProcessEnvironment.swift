//
//  ProcessEnvironment.swift
//  PathChanger
//
//  Centralized environment configuration for subprocess execution.
//  Provides secure, consistent environment variables for all process operations.
//

import Foundation

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
        "/opt/homebrew/bin",           // Apple Silicon homebrew (primary for M1/M2/M3)
        "/usr/local/bin",              // Intel homebrew and manual installs
        "/opt/local/bin",              // MacPorts
        "/usr/local/opt/python3/bin",  // Manual python3 install via Homebrew
        "/usr/bin",                    // System binaries
        "/bin",                        // Essential system binaries
        "/usr/sbin",                   // System administration binaries
        "/sbin"                        // Essential system administration binaries
    ]

    /// Dynamic PATH directories that include user home
    ///
    /// These paths require runtime resolution using NSHomeDirectory().
    ///
    /// # Security Note
    /// Only `pyenv` directories are included here. User-writable bin paths
    /// such as `~/.local/bin` and `~/Library/Python/<v>/bin` are intentionally
    /// EXCLUDED to prevent local privilege escalation: any code dropped into
    /// those locations would otherwise be picked up by sub-shells running as
    /// the privileged tunnel commands.
    ///
    /// pmd3 is invoked exclusively via `python3 -m pymobiledevice3` using the
    /// absolute Python path resolved by `PythonPathResolver`, with PYTHONPATH
    /// set to trusted Homebrew site-packages by default (user site-packages
    /// require explicit opt-in) — so we never need a `pymobiledevice3` shim
    /// binary on PATH.
    private static func dynamicPathDirectories() -> [String] {
        let home = NSHomeDirectory()
        let pyenvVersionsPath = "\(home)/.pyenv/versions"
        let pyenvVersionBinPaths = (try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsPath))?
            .sorted(by: >)
            .map { "\(pyenvVersionsPath)/\($0)/bin" } ?? []

        return pyenvVersionBinPaths + [
            "\(home)/.pyenv/shims"  // pyenv Python version manager
        ]
    }

    // MARK: - PYTHONPATH Configuration

    /// Supported Python versions for site-packages lookup
    private static let supportedPythonVersions = ["3.13", "3.12", "3.11", "3.10", "3.9"]

    /// UserDefaults key that explicitly opts in to user site-packages trust.
    ///
    /// Security default is `false` — user Library site-packages are excluded
    /// unless this key is enabled or the caller passes an explicit override.
    public static let allowUserSitePackagesDefaultsKey = "allowUserPythonSitePackages"

    /// Generate Python site-packages paths for user installs
    ///
    /// # Security Note
    /// These directories are user-writable and therefore untrusted by default.
    /// They are only appended when an explicit policy opt-in is provided.
    private static func userPythonPaths() -> [String] {
        return supportedPythonVersions.map { version in
            NSHomeDirectory() + "/Library/Python/\(version)/lib/python/site-packages"
        }
    }

    /// Generate Python site-packages paths for Homebrew installs
    private static func homebrewPythonPaths() -> [String] {
        return supportedPythonVersions.flatMap { version in
            [
                "/opt/homebrew/lib/python\(version)/site-packages",  // Apple Silicon
                "/usr/local/lib/python\(version)/site-packages"       // Intel
            ]
        }
    }

    /// Resolve whether user site-packages should be trusted for this process launch.
    /// Policy precedence:
    /// 1. Explicit `includeUserSitePackages` argument (strongest)
    /// 2. UserDefaults opt-in key `allowUserPythonSitePackages`
    /// 3. Secure default `false`
    private static func shouldIncludeUserSitePackages(_ includeUserSitePackages: Bool?) -> Bool {
        if let includeUserSitePackages {
            return includeUserSitePackages
        }
        return UserDefaults.standard.bool(forKey: allowUserSitePackagesDefaultsKey)
    }

    /// Build PYTHONPATH entries under an explicit trust policy.
    ///
    /// - Parameter includeUserSitePackages: Optional explicit override.
    ///   - `true`: include user Library site-packages
    ///   - `false`: exclude user Library site-packages
    ///   - `nil`: use `allowUserPythonSitePackages` UserDefaults policy key
    public static func configuredPythonPaths(includeUserSitePackages: Bool? = nil) -> [String] {
        var pythonPaths = homebrewPythonPaths()
        if shouldIncludeUserSitePackages(includeUserSitePackages) {
            pythonPaths.append(contentsOf: userPythonPaths())
        }
        return pythonPaths
    }
    // MARK: - Public API

    /// Generate a fully configured environment for subprocess execution
    ///
    /// This method creates an environment dictionary suitable for Process.environment.
    /// It includes:
    /// - Restricted PATH with approved directories only
    /// - PYTHONPATH for common Python package locations
    /// - All other current process environment variables
    ///
    /// # Thread Safety
    /// This method is thread-safe and can be called from any queue.
    ///
    /// - Parameter preserveExistingPath: If true, appends existing PATH to configured paths.
    ///   Default is false for security (prevents path injection from parent process).
    /// - Parameter includeUserSitePackages: Optional explicit override for user
    ///   Library site-packages trust. `nil` defers to
    ///   `allowUserPythonSitePackages` UserDefaults policy key.
    /// - Returns: Environment dictionary ready for use with Process
    public static func configured(
        preserveExistingPath: Bool = false,
        includeUserSitePackages: Bool? = nil
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // Build secure PATH
        var pathComponents = approvedPathDirectories + dynamicPathDirectories()

        if preserveExistingPath, let existingPath = env["PATH"] {
            pathComponents.append(existingPath)
        }

        env["PATH"] = pathComponents.joined(separator: ":")
        env["PYENV_ROOT"] = NSHomeDirectory() + "/.pyenv"
        // Build PYTHONPATH under explicit trust policy.
        let pythonPaths = configuredPythonPaths(includeUserSitePackages: includeUserSitePackages)
        env["PYTHONPATH"] = pythonPaths.joined(separator: ":")

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
        env["PYENV_ROOT"] = NSHomeDirectory() + "/.pyenv"

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
        let allApprovedDirs = approvedPathDirectories + dynamicPathDirectories()
        return allApprovedDirs.contains { approvedDir in
            path.hasPrefix(approvedDir + "/") || path == approvedDir
        }
    }

    /// Get the configured PATH as a string
    ///
    /// - Returns: Colon-separated PATH string
    public static var pathString: String {
        let pathComponents = approvedPathDirectories + dynamicPathDirectories()
        return pathComponents.joined(separator: ":")
    }

    /// Get the configured PYTHONPATH as a string
    ///
    /// Security default excludes user Library site-packages.
    ///
    /// - Returns: Colon-separated trusted PYTHONPATH string
    public static var pythonPathString: String {
        let pythonPaths = configuredPythonPaths(includeUserSitePackages: false)
        return pythonPaths.joined(separator: ":")
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
    }
}
