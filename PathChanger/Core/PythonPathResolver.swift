//
//  PythonPathResolver.swift
//  PathChanger
//
//  Dynamic Python 3 path resolution for pymobiledevice3 integration
//  Enhanced with validation and dependency checking
//

import Foundation

/// Errors that can occur during Python path resolution and dependency validation
enum PythonResolverError: Error, LocalizedError {
    case pythonNotFound
    case pythonNotExecutable(String)
    case pymobiledevice3NotInstalled
    case pymobiledevice3VersionTooOld(String)
    case invalidPythonVersion(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "No supported Python 3 executable was found"
        case .pythonNotExecutable(let path):
            return "Python 3 found at '\(path)' but is not executable"
        case .pymobiledevice3NotInstalled:
            return "pymobiledevice3 is not installed"
        case .pymobiledevice3VersionTooOld(let version):
            return "pymobiledevice3 version \(version) is too old. Minimum required: 6.1.5"
        case .invalidPythonVersion(let version):
            return "Python version \(version) is not supported. Minimum required: 3.9"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pythonNotFound:
            return "Install Python 3.9 or later with Homebrew, or enable Apple's /usr/bin/python3"
        case .pythonNotExecutable:
            return "Check file permissions for the Python executable"
        case .pymobiledevice3NotInstalled:
            return "Install the latest pymobiledevice3 from PathChanger"
        case .pymobiledevice3VersionTooOld:
            return "Install the latest pymobiledevice3 from PathChanger"
        case .invalidPythonVersion:
            return "Install Python 3.9 or later"
        }
    }
}

/// Resolves the Python 3 executable path using the app's fixed candidate policy.
enum PythonPathResolver {

    /// Homebrew is preferred on both architectures. Apple's Python is the final fallback.
    static let candidatePaths: [String] = [
        "/opt/homebrew/bin/python3",
        "/opt/homebrew/bin/python3.14",
        "/opt/homebrew/bin/python3.13",
        "/opt/homebrew/bin/python3.12",
        "/usr/local/bin/python3",
        "/usr/local/bin/python3.14",
        "/usr/local/bin/python3.13",
        "/usr/local/bin/python3.12",
        "/usr/bin/python3",
    ]

    /// Cached resolved path
    private static var _resolvedPath: String?
    private static let cacheLock = NSLock()

    /// Minimum required Python version (major.minor)
    private static let minimumPythonVersion = (major: 3, minor: 9)

    /// Minimum required pymobiledevice3 version
    private static let minimumPmd3Version = "6.1.5"

    /// Get the Python 3 executable path
    /// Uses cached value if available, otherwise discovers dynamically
    /// - Returns: Path to Python 3 executable
    /// - Warning: Does NOT validate installation, use `validateInstallation()` for that
    static var path: String {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = _resolvedPath {
            return cached
        }

        let resolved = resolvePath() ?? candidatePaths[candidatePaths.count - 1]
        _resolvedPath = resolved
        return resolved
    }

    /// Force re-resolve the Python path (clears cache)
    static func refresh() -> String {
        let resolved = resolvePath() ?? candidatePaths[candidatePaths.count - 1]
        cacheLock.lock()
        _resolvedPath = resolved
        cacheLock.unlock()
        return resolved
    }

    /// Build the installation command for the selected interpreter.
    static func pymobiledevice3InstallArguments(for pythonPath: String) -> [String] {
        var arguments = ["-m", "pip", "install", "--upgrade"]

        if pythonPath.hasPrefix("/opt/homebrew/bin/") ||
           pythonPath.hasPrefix("/usr/local/bin/") {
            arguments.append("--break-system-packages")
        } else {
            arguments.append("--user")
        }

        arguments.append("pymobiledevice3")
        return arguments
    }

    /// Check if Python 3 is available and executable
    static var isAvailable: Bool {
        let pythonPath = path
        return FileManager.default.fileExists(atPath: pythonPath) &&
               FileManager.default.isExecutableFile(atPath: pythonPath)
    }

    // MARK: - Validation Methods

    /// Validate complete Python installation
    /// - Throws: PythonResolverError if validation fails
    static func validateInstallation() async throws {
        // Check Python exists and is executable
        let pythonPath = path

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw PythonResolverError.pythonNotFound
        }

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw PythonResolverError.pythonNotExecutable(pythonPath)
        }

        // Validate Python version
        try await checkPythonVersion()
    }

    /// Validate all dependencies (Python + pymobiledevice3)
    /// - Throws: PythonResolverError if any dependency is missing or invalid
    static func validateDependencies() async throws {
        // First validate Python installation
        try await validateInstallation()

        // Then check pymobiledevice3
        try await validatePymobiledevice3()
    }

    /// Check Python version meets minimum requirements
    /// - Throws: PythonResolverError if version is too old or cannot be determined
    static func checkPythonVersion() async throws {
        guard let versionString = await version() else {
            throw PythonResolverError.pythonNotFound
        }

        // Parse version (e.g., "Python 3.9.6" -> 3.9)
        let components = versionString.components(separatedBy: " ")
        guard components.count >= 2,
              let versionPart = components.last(where: { $0.contains(".") }) else {
            throw PythonResolverError.invalidPythonVersion(versionString)
        }

        let versionNumbers = versionPart.components(separatedBy: ".")
        guard versionNumbers.count >= 2,
              let major = Int(versionNumbers[0]),
              let minor = Int(versionNumbers[1]) else {
            throw PythonResolverError.invalidPythonVersion(versionString)
        }

        // Check against minimum version
        if major < minimumPythonVersion.major ||
           (major == minimumPythonVersion.major && minor < minimumPythonVersion.minor) {
            throw PythonResolverError.invalidPythonVersion("\(major).\(minor)")
        }
    }

    /// Check if pymobiledevice3 is installed
    /// - Returns: True if installed, false otherwise
    static func isPymobiledevice3Installed() async -> Bool {
        do {
            _ = try await checkPymobiledevice3Installation()
            return true
        } catch {
            return false
        }
    }

    /// Validate pymobiledevice3 installation and version
    /// - Throws: PythonResolverError if not installed or version is too old
    static func validatePymobiledevice3() async throws {
        let version = try await checkPymobiledevice3Installation()

        // Parse version and compare (simplified version check)
        if compareVersions(version, minimumPmd3Version) == .orderedAscending {
            throw PythonResolverError.pymobiledevice3VersionTooOld(version)
        }
    }

    /// Check pymobiledevice3 installation and get version
    /// - Returns: Version string (e.g., "6.1.5")
    /// - Throws: PythonResolverError if not installed
    private static func checkPymobiledevice3Installation() async throws -> String {
        return try await checkPymobiledevice3WithPip()
    }

    /// Check pymobiledevice3 using pip show
    private static func checkPymobiledevice3WithPip() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-m", "pip", "show", "pymobiledevice3"]
        process.environment = ProcessEnvironment.configured()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                defer {
                    // Ensure cleanup of file handles and process
                    try? pipe.fileHandleForReading.close()
                    if process.isRunning {
                        process.terminate()
                    }
                }

                do {
                    try process.run()

                    let timeoutDate = Date().addingTimeInterval(5.0)
                    while process.isRunning && Date() < timeoutDate {
                        Thread.sleep(forTimeInterval: 0.05)
                    }

                    if process.isRunning {
                        process.terminate()
                        continuation.resume(throwing: PythonResolverError.pymobiledevice3NotInstalled)
                        return
                    }

                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: PythonResolverError.pymobiledevice3NotInstalled)
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    // Extract version number from pip show output (format: "Version: X.Y.Z")
                    let versionPattern = #"Version:\s*(\d+\.\d+\.\d+)"#
                    if let regex = try? NSRegularExpression(pattern: versionPattern),
                       let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                       let range = Range(match.range(at: 1), in: output) {
                        let version = String(output[range])
                        continuation.resume(returning: version)
                    } else {
                        // If we got here with exit code 0, pymobiledevice3 is installed
                        continuation.resume(returning: "unknown")
                    }
                } catch {
                    continuation.resume(throwing: PythonResolverError.pymobiledevice3NotInstalled)
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Compare semantic versions
    private static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let v1Components = v1.components(separatedBy: ".").compactMap { Int($0) }
        let v2Components = v2.components(separatedBy: ".").compactMap { Int($0) }

        for componentIndex in 0..<max(v1Components.count, v2Components.count) {
            let v1Value = componentIndex < v1Components.count ? v1Components[componentIndex] : 0
            let v2Value = componentIndex < v2Components.count ? v2Components[componentIndex] : 0

            if v1Value < v2Value { return .orderedAscending }
            if v1Value > v2Value { return .orderedDescending }
        }

        return .orderedSame
    }

    /// Get the Python version string with timeout protection
    static func version() async -> String? {
        guard isAvailable else { return nil }

        return try? await withTimeout(seconds: 5.0) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            process.environment = ProcessEnvironment.configured()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            defer {
                try? pipe.fileHandleForReading.close()
                if process.isRunning {
                    process.terminate()
                }
            }

            try process.run()

            // Wait with timeout
            let timeoutDate = Date().addingTimeInterval(5.0)
            while process.isRunning && Date() < timeoutDate {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if process.isRunning {
                process.terminate()
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Private

    static func resolvePath(
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidatePaths.first(where: isExecutable)
    }

    // MARK: - Timeout Helper

    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T?) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}
