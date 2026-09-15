//
//  PythonPathResolver.swift
//  PathChanger
//
//  Dynamic Python 3 path resolution for pymobiledevice3 integration
//  Enhanced with validation and dependency checking
//

import Foundation

enum ManagedLocationRuntimeContract {
    static let minimumPythonMajor = 3
    static let minimumPythonMinor = 13
    static let pythonSnapshotVersion = "3.13"
    static let pymobiledevice3SnapshotVersion = "11.12.5"
}

/// Errors that can occur during Python path resolution and dependency validation
enum PythonResolverError: Error, LocalizedError {
    case pythonNotFound
    case pythonNotExecutable(String)
    case pymobiledevice3NotInstalled
    case pymobiledevice3CapabilitiesMissing(version: String, missing: [String])
    case invalidPythonVersion(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "No supported Python 3 executable was found"
        case .pythonNotExecutable(let path):
            return "Python 3 found at '\(path)' but is not executable"
        case .pymobiledevice3NotInstalled:
            return "pymobiledevice3 is not installed"
        case .pymobiledevice3CapabilitiesMissing(let version, let missing):
            return "pymobiledevice3 \(version) is missing required capabilities: \(missing.joined(separator: ", "))"
        case .invalidPythonVersion(let version):
            return "Python version \(version) is below PathChanger's capability floor (minimum \(ManagedLocationRuntimeContract.minimumPythonMajor).\(ManagedLocationRuntimeContract.minimumPythonMinor))"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pythonNotFound:
            return "Install a managed Homebrew Python that meets PathChanger's capability floor, then rebuild the runtime snapshot"
        case .pythonNotExecutable:
            return "Check file permissions for the Python executable"
        case .pymobiledevice3NotInstalled:
            return "Build the managed runtime from the release's requirements-location.lock snapshot"
        case .pymobiledevice3CapabilitiesMissing:
            return "Update PathChanger's reviewed dependency snapshot to a pymobiledevice3 build that provides every required capability"
        case .invalidPythonVersion:
            return "Install a managed Python runtime that meets PathChanger's capability floor"
        }
    }
}

/// Resolves the Python 3 executable path using the app's fixed candidate policy.
enum PythonPathResolver {

    /// PathChanger executes only its deterministic managed runtime.
    /// Homebrew Python is a bootstrap dependency and is never used directly by the app.
    static var managedPythonPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PathChanger/runtime/location/bin/python3")
            .path
    }

    static var candidatePaths: [String] {
        [managedPythonPath]
    }

    /// Cached resolved path
    private static var _resolvedPath: String?
    private static let cacheLock = NSLock()

    /// Minimum language/runtime floor. Newer Python releases remain eligible.
    private static let minimumPythonVersion = (
        major: ManagedLocationRuntimeContract.minimumPythonMajor,
        minor: ManagedLocationRuntimeContract.minimumPythonMinor
    )

    static let requiredPymobiledevice3Capabilities: Set<String> = [
        "create_using_tcp",
        "create_using_usbmux",
        "dvt_provider",
        "location_simulation",
        "preferred_rsd_tunnel",
        "remote_service_discovery",
    ]

    static func isSupportedPythonVersion(major: Int, minor: Int) -> Bool {
        major > minimumPythonVersion.major ||
            (major == minimumPythonVersion.major && minor >= minimumPythonVersion.minor)
    }

    static func validatePymobiledevice3Capabilities(
        version: String,
        available: Set<String>
    ) throws {
        let missing = requiredPymobiledevice3Capabilities.subtracting(available).sorted()
        guard missing.isEmpty else {
            throw PythonResolverError.pymobiledevice3CapabilitiesMissing(
                version: version,
                missing: missing
            )
        }
    }

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

    static var dependencyLockPath: String {
        if let bundled = Bundle.main.path(
            forResource: "requirements-location",
            ofType: "lock"
        ) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("requirements-location.lock")
            .path
    }

    /// Build a hash-locked installation command only for the final managed runtime
    /// or a deterministic sibling staging runtime created for atomic replacement.
    static func pymobiledevice3InstallArguments(for pythonPath: String) -> [String] {
        let candidatePython = URL(fileURLWithPath: pythonPath).standardizedFileURL
        let managedPython = URL(fileURLWithPath: managedPythonPath).standardizedFileURL
        let candidateRuntime = candidatePython.deletingLastPathComponent().deletingLastPathComponent()
        let managedRuntime = managedPython.deletingLastPathComponent().deletingLastPathComponent()
        let isStagingRuntime = candidateRuntime.deletingLastPathComponent() == managedRuntime.deletingLastPathComponent() &&
            candidateRuntime.lastPathComponent.hasPrefix("location.staging-") &&
            candidatePython.lastPathComponent == "python3" &&
            candidatePython.deletingLastPathComponent().lastPathComponent == "bin"
        guard candidatePython == managedPython || isStagingRuntime else { return [] }
        return [
            "-m", "pip", "install", "--require-hashes",
            "-r", dependencyLockPath,
        ]
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

        guard isSupportedPythonVersion(major: major, minor: minor) else {
            throw PythonResolverError.invalidPythonVersion("\(major).\(minor)")
        }
    }

    private struct Pymobiledevice3CapabilityReport: Decodable {
        let version: String
        let capabilities: [String]
    }

    /// Returns true only when the installed package provides every capability PathChanger uses.
    static func isPymobiledevice3Installed() async -> Bool {
        do {
            try await validatePymobiledevice3()
            return true
        } catch {
            return false
        }
    }

    /// Validate pymobiledevice3 by executable capabilities, not an exact package version.
    static func validatePymobiledevice3() async throws {
        let report = try await checkPymobiledevice3Installation()
        try validatePymobiledevice3Capabilities(
            version: report.version,
            available: Set(report.capabilities)
        )
    }

    private static func checkPymobiledevice3Installation() async throws
        -> Pymobiledevice3CapabilityReport
    {
        let script = #"""
        import importlib
        import json
        from importlib.metadata import version

        checks = (
            ("create_using_tcp", "pymobiledevice3.lockdown", "create_using_tcp"),
            ("create_using_usbmux", "pymobiledevice3.lockdown", "create_using_usbmux"),
            ("dvt_provider", "pymobiledevice3.services.dvt.instruments.dvt_provider", "DvtProvider"),
            ("location_simulation", "pymobiledevice3.services.dvt.instruments.location_simulation", "LocationSimulation"),
            ("preferred_rsd_tunnel", "pymobiledevice3.remote.rsd_tunnel", "PreferredRsdTunnel"),
            ("remote_service_discovery", "pymobiledevice3.remote.remote_service_discovery", "RemoteServiceDiscoveryService"),
        )
        available = []
        for name, module_name, attribute_name in checks:
            try:
                module = importlib.import_module(module_name)
                getattr(module, attribute_name)
                available.append(name)
            except (ImportError, AttributeError):
                pass
        print(json.dumps({
            "version": version("pymobiledevice3"),
            "capabilities": sorted(available),
        }, separators=(",", ":")))
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", script]
        process.environment = ProcessEnvironment.configured()

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

                    let timeoutDate = Date().addingTimeInterval(5.0)
                    while process.isRunning && Date() < timeoutDate {
                        Thread.sleep(forTimeInterval: 0.05)
                    }

                    guard !process.isRunning, process.terminationStatus == 0 else {
                        process.terminate()
                        continuation.resume(
                            throwing: PythonResolverError.pymobiledevice3NotInstalled
                        )
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let report = try? JSONDecoder().decode(
                        Pymobiledevice3CapabilityReport.self,
                        from: data
                    ) else {
                        continuation.resume(
                            throwing: PythonResolverError.pymobiledevice3NotInstalled
                        )
                        return
                    }
                    continuation.resume(returning: report)
                } catch {
                    continuation.resume(
                        throwing: PythonResolverError.pymobiledevice3NotInstalled
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods

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
