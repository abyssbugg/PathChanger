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
            return "Python 3 is not installed or not found in PATH"
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
            return "Install Python 3.9+ from https://www.python.org or use Homebrew:\nbrew install python3"
        case .pythonNotExecutable:
            return "Check file permissions for the Python executable"
        case .pymobiledevice3NotInstalled:
            return "Install pymobiledevice3 using:\npython3 -m pip install -U pymobiledevice3"
        case .pymobiledevice3VersionTooOld:
            return "Upgrade pymobiledevice3 using:\npython3 -m pip install -U pymobiledevice3"
        case .invalidPythonVersion:
            return "Install Python 3.9 or later"
        }
    }
}

/// Resolves the Python 3 executable path dynamically
/// Supports multiple installation methods: system, Homebrew, pyenv, etc.
enum PythonPathResolver {

    /// Cached resolved path
    private static var _resolvedPath: String?

    /// Minimum required Python version (major.minor)
    private static let minimumPythonVersion = (major: 3, minor: 9)

    /// Minimum required pymobiledevice3 version
    private static let minimumPmd3Version = "6.1.5"

    /// Common Python 3 installation paths on macOS, ordered by user-managed installs first.
    private static var searchPaths: [String] {
        let home = NSHomeDirectory()
        let pyenvVersionsPath = "\(home)/.pyenv/versions"
        let pyenvVersionPaths = (try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsPath))?
            .sorted(by: >)
            .map { "\(pyenvVersionsPath)/\($0)/bin/python3" } ?? []

        let configuredPaths = [
            "\(home)/.pyenv/shims/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/usr/bin/python3"
        ]

        return uniquePaths(pyenvVersionPaths + configuredPaths)
    }

    /// Search directories for CLI tools used by Process from GUI-launched apps.
    private static var executableSearchDirectories: [String] {
        let home = NSHomeDirectory()
        let pyenvVersionsPath = "\(home)/.pyenv/versions"
        let pyenvVersionBinPaths = (try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsPath))?
            .sorted(by: >)
            .map { "\(pyenvVersionsPath)/\($0)/bin" } ?? []

        let configuredPaths = [
            "\(home)/.pyenv/shims",
            "\(home)/.local/bin",
            "\(home)/Library/Python/3.13/bin",
            "\(home)/Library/Python/3.12/bin",
            "\(home)/Library/Python/3.11/bin",
            "\(home)/Library/Python/3.10/bin",
            "\(home)/Library/Python/3.9/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin"
        ]

        return uniquePaths(pyenvVersionBinPaths + configuredPaths)
    }

    /// Get the Python 3 executable path
    /// Uses cached value if available, otherwise discovers dynamically
    /// - Returns: Path to Python 3 executable
    /// - Warning: Does NOT validate installation, use `validateInstallation()` for that
    static var path: String {
        if let cached = _resolvedPath {
            return cached
        }

        let resolved = resolvePath()
        _resolvedPath = resolved
        return resolved
    }

    /// Force re-resolve the Python path (clears cache)
    static func refresh() -> String {
        _resolvedPath = nil
        return path
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
        // Refresh lets a newly installed pyenv/Homebrew Python be picked up without restarting the app.
        let pythonPath = refresh()

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw PythonResolverError.pythonNotFound
        }

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw PythonResolverError.pythonNotExecutable(pythonPath)
        }

        try await checkPythonVersion()
    }

    /// Validate all dependencies (Python + pymobiledevice3)
    /// - Throws: PythonResolverError if any dependency is missing or invalid
    static func validateDependencies() async throws {
        try await validateInstallation()
        try await validatePymobiledevice3()
    }

    /// Check Python version meets minimum requirements
    /// - Throws: PythonResolverError if version is too old or cannot be determined
    static func checkPythonVersion() async throws {
        guard let versionString = await version() else {
            throw PythonResolverError.pythonNotFound
        }

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

        if version != "unknown", compareVersions(version, minimumPmd3Version) == .orderedAscending {
            throw PythonResolverError.pymobiledevice3VersionTooOld(version)
        }
    }

    /// Get the Python version string with timeout protection
    static func version() async -> String? {
        guard isAvailable else { return nil }

        return try? await runProcess(
            executablePath: path,
            arguments: ["--version"],
            timeout: 5.0
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the installed pymobiledevice3 version string if available.
    ///
    /// Returns nil when pymobiledevice3 cannot be resolved.
    static func pymobiledevice3Version() async -> String? {
        do {
            let version = try await checkPymobiledevice3Installation()
            return version == "unknown" ? nil : version
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private static func checkPymobiledevice3Installation() async throws -> String {
        do {
            return try await checkPymobiledevice3WithModule()
        } catch {
            return try await checkPymobiledevice3WithPip()
        }
    }

    /// Check pymobiledevice3 by running the module with the resolved Python.
    private static func checkPymobiledevice3WithModule() async throws -> String {
        let output = try await runProcess(
            executablePath: path,
            arguments: ["-m", "pymobiledevice3", "version"],
            timeout: 5.0
        )

        return extractVersion(from: output) ?? "unknown"
    }

    /// Check pymobiledevice3 using pip show with the resolved Python.
    private static func checkPymobiledevice3WithPip() async throws -> String {
        let output = try await runProcess(
            executablePath: path,
            arguments: ["-m", "pip", "show", "pymobiledevice3"],
            timeout: 5.0
        )

        return extractVersion(from: output) ?? "unknown"
    }

    private static func resolvePath() -> String {
        for searchPath in searchPaths where FileManager.default.isExecutableFile(atPath: searchPath) {
            return searchPath
        }

        if let whichPath = resolveViaWhich() {
            return whichPath
        }

        return "/usr/bin/python3"
    }

    private static func resolveViaWhich() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.environment = processEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        defer {
            try? pipe.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
            }
        }

        do {
            try process.run()

            let timeoutDate = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < timeoutDate {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                process.terminate()
                return nil
            }

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = output, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            // Silently fall through to static paths.
        }

        return nil
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = processEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                defer {
                    try? pipe.fileHandleForReading.close()
                    if process.isRunning {
                        process.terminate()
                    }
                }

                do {
                    try process.run()

                    var didTimeout = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            didTimeout = true
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    if didTimeout {
                        continuation.resume(throwing: PythonResolverError.pymobiledevice3NotInstalled)
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: PythonResolverError.pymobiledevice3NotInstalled)
                        return
                    }

                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let pathEntries = uniquePaths(executableSearchDirectories + existingPath.split(separator: ":").map(String.init))
        environment["PATH"] = pathEntries.joined(separator: ":")
        environment["PYENV_ROOT"] = "\(NSHomeDirectory())/.pyenv"
        return environment
    }

    private static func extractVersion(from output: String) -> String? {
        let versionPattern = #"(\d+\.\d+\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: versionPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range])
    }

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

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            guard !path.isEmpty, !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
