//
//  DependencyValidator.swift
//  PathChanger
//
//  Pre-flight validation of Python and pymobiledevice3 dependencies
//  Prevents startup failures by validating all required tools upfront
//

import Foundation
import Darwin

/// Validates project dependencies at startup
@MainActor
class DependencyValidator: ObservableObject {
    @Published var validationStatus: ValidationStatus = .pending
    @Published var errors: [ValidationError] = []
    @Published var installProgress: String = ""

    enum ValidationStatus {
        case pending
        case validating
        case valid
        case invalid
        case installing
    }

    struct ValidationError: Identifiable {
        let id = UUID()
        let type: ErrorType
        let message: String
        let suggestion: String

        enum ErrorType {
            case pythonMissing
            case pythonVersionTooOld
            case pymobiledevice3Missing
            case pymobiledevice3CapabilitiesMissing
            case pythonNotExecutable
        }
    }

    static let shared = DependencyValidator()
    private init() {}

    /// Run complete dependency validation
    func validateAll() async {
        validationStatus = .validating
        errors.removeAll()
        _ = PythonPathResolver.refresh()

        // Validate Python first
        await validatePython()

        // Only if Python is valid, check pymobiledevice3
        if !errors.contains(where: { $0.type == .pythonMissing || $0.type == .pythonVersionTooOld }) {
            await validatePymobiledevice3()
        }

        // Update status
        validationStatus = errors.isEmpty ? .valid : .invalid

        // Log results
        if errors.isEmpty {
            Logger.info("✅ All dependencies validated successfully", category: .device)
        } else {
            Logger.error("❌ Dependency validation failed: \(errors.count) issue(s) found", category: .device)
            for error in errors {
                Logger.error("  - \(error.message)", category: .device)
            }
        }
    }

    /// Validate Python installation
    private func validatePython() async {
        do {
            try await PythonPathResolver.validateInstallation()
            Logger.info("✅ Python validation passed", category: .device)
        } catch let error as PythonResolverError {
            let validationError = mapPythonError(error)
            errors.append(validationError)
            Logger.error("❌ Python validation failed: \(validationError.message)", category: .device)
        } catch {
            errors.append(ValidationError(
                type: .pythonMissing,
                message: "Unknown Python error: \(error.localizedDescription)",
                suggestion: "Check Python installation and try again"
            ))
        }
    }

    /// Validate pymobiledevice3 installation
    private func validatePymobiledevice3() async {
        do {
            try await PythonPathResolver.validatePymobiledevice3()
            Logger.info("✅ pymobiledevice3 validation passed", category: .device)
        } catch let error as PythonResolverError {
            let validationError = mapPmd3Error(error)
            errors.append(validationError)
            Logger.error("❌ pymobiledevice3 validation failed: \(validationError.message)", category: .device)
        } catch {
            errors.append(ValidationError(
                type: .pymobiledevice3Missing,
                message: "Unknown pymobiledevice3 error: \(error.localizedDescription)",
                suggestion: "Check pymobiledevice3 installation and try again"
            ))
        }
    }

    /// Map PythonResolverError to ValidationError for Python
    private func mapPythonError(_ error: PythonResolverError) -> ValidationError {
        switch error {
        case .pythonNotFound:
            return ValidationError(
                type: .pythonMissing,
                message: "Python 3 is not installed",
                suggestion: "Install a managed Homebrew Python that meets PathChanger's capability floor; Apple's /usr/bin/python3 is not used"
            )
        case .pythonNotExecutable(let path):
            return ValidationError(
                type: .pythonNotExecutable,
                message: "Python at '\(path)' is not executable",
                suggestion: "Check file permissions or reinstall Python"
            )
        case .invalidPythonVersion(let version):
            return ValidationError(
                type: .pythonVersionTooOld,
                message: "Python version \(version) is below the capability floor (minimum: \(ManagedLocationRuntimeContract.minimumPythonMajor).\(ManagedLocationRuntimeContract.minimumPythonMinor))",
                suggestion: "Install a newer managed Homebrew Python runtime"
            )
        case .pymobiledevice3NotInstalled:
            return ValidationError(
                type: .pythonMissing,
                message: "Unexpected error during Python validation",
                suggestion: "Try restarting the application"
            )
        case .pymobiledevice3CapabilitiesMissing:
            return ValidationError(
                type: .pythonVersionTooOld,
                message: "Unexpected error during Python validation",
                suggestion: "Try restarting the application"
            )
        }
    }

    /// Map PythonResolverError to ValidationError for pymobiledevice3
    private func mapPmd3Error(_ error: PythonResolverError) -> ValidationError {
        switch error {
        case .pymobiledevice3NotInstalled:
            return ValidationError(
                type: .pymobiledevice3Missing,
                message: "The managed pymobiledevice3 runtime is not installed",
                suggestion: "Build the managed runtime from PathChanger's reviewed dependency snapshot"
            )
        case .pymobiledevice3CapabilitiesMissing(let version, let missing):
            return ValidationError(
                type: .pymobiledevice3CapabilitiesMissing,
                message: "pymobiledevice3 \(version) is missing required capabilities: \(missing.joined(separator: ", "))",
                suggestion: "Install a reviewed pymobiledevice3 snapshot that provides every required capability"
            )
        case .pythonNotFound, .pythonNotExecutable, .invalidPythonVersion:
            return ValidationError(
                type: .pymobiledevice3Missing,
                message: "Cannot validate the managed location runtime",
                suggestion: "Install Homebrew python@3.13, then rebuild the managed runtime"
            )
        }
    }

    /// Check if validation was successful
    var isValid: Bool {
        validationStatus == .valid
    }

    /// Get the first error message for display
    var firstErrorMessage: String? {
        errors.first?.message
    }

    /// Get recovery suggestion for first error
    var firstErrorSuggestion: String? {
        errors.first?.suggestion
    }

    /// True when the deterministic managed runtime is missing, corrupt, or has a dependency mismatch.
    var canInstallPymobiledevice3: Bool {
        let pythonBroken = errors.contains {
            $0.type == .pythonMissing || $0.type == .pythonVersionTooOld || $0.type == .pythonNotExecutable
        }
        let pmd3Issue = errors.contains {
            $0.type == .pymobiledevice3Missing || $0.type == .pymobiledevice3CapabilitiesMissing
        }
        return pythonBroken || pmd3Issue
    }

    /// Rebuild the deterministic managed runtime from the bundled hash lock.
    func installLatestPymobiledevice3() async {
        validationStatus = .installing
        installProgress = "Preparing the managed location runtime…"

        do {
            let output = try await rebuildManagedRuntime()
            Logger.info("Managed location runtime install finished:\n\(output.suffix(500))", category: .device)
            installProgress = "Install finished. Rechecking…"
            await validateAll()
            if validationStatus == .valid {
                installProgress = "Managed location runtime is ready."
            } else {
                installProgress = "Install completed but validation did not pass."
            }
        } catch {
            Logger.error("Managed location runtime install failed: \(error.localizedDescription)", category: .device)
            installProgress = "Install failed: \(error.localizedDescription)"
            validationStatus = .invalid
        }
    }

    private func rebuildManagedRuntime() async throws -> String {
        let fileManager = FileManager.default
        let managedPython = URL(fileURLWithPath: PythonPathResolver.managedPythonPath).standardizedFileURL
        let finalRuntime = managedPython.deletingLastPathComponent().deletingLastPathComponent()
        let runtimeParent = finalRuntime.deletingLastPathComponent()
        let stagingRuntime = runtimeParent.appendingPathComponent("location.staging-\(UUID().uuidString)")
        let stagingPython = stagingRuntime.appendingPathComponent("bin/python3")
        let rollbackRuntime = runtimeParent.appendingPathComponent("location.rollback")
        let lockPath = PythonPathResolver.dependencyLockPath

        guard fileManager.fileExists(atPath: lockPath) else {
            throw installerError("Bundled requirements-location.lock is missing")
        }
        let bootstrapCandidates = [
            "/opt/homebrew/opt/python@3.13/bin/python3.13",
            "/usr/local/opt/python@3.13/bin/python3.13",
        ]
        guard let bootstrapPython = bootstrapCandidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw installerError("Homebrew Python 3.13 is required to create the managed runtime")
        }

        try fileManager.createDirectory(at: runtimeParent, withIntermediateDirectories: true)
        let installLock = runtimeParent.appendingPathComponent(".location-install.lock")
        let lockDescriptor = open(
            installLock.path,
            O_CREAT | O_RDWR | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard lockDescriptor >= 0 else {
            throw installerError("Unable to open the managed runtime installation lock")
        }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(lockDescriptor)
            throw installerError("Another managed runtime installation is already in progress")
        }
        defer {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
            try? fileManager.removeItem(at: stagingRuntime)
        }

        func rejectSymbolicLink(_ url: URL) throws {
            if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
                throw installerError("Refusing a symbolic-link runtime path: \(url.lastPathComponent)")
            }
        }
        try [finalRuntime, rollbackRuntime, stagingRuntime].forEach(rejectSymbolicLink)

        installProgress = "Creating an isolated Python 3.13 runtime…"
        var output = try await runInstallerCommand(
            executable: bootstrapPython,
            arguments: ["-m", "venv", stagingRuntime.path],
            timeout: 120
        )

        let installArguments = PythonPathResolver.pymobiledevice3InstallArguments(for: stagingPython.path)
        guard !installArguments.isEmpty else {
            throw installerError("Refusing to install outside the managed staging runtime")
        }
        installProgress = "Installing hash-locked location dependencies…"
        output += try await runInstallerCommand(
            executable: stagingPython.path,
            arguments: installArguments,
            timeout: 600
        )

        installProgress = "Verifying exact runtime versions…"
        let verification = "import importlib.metadata as m, sys; assert sys.version_info[:2] == (3, 13); assert m.version('pymobiledevice3') == '\(ManagedLocationRuntimeContract.pymobiledevice3SnapshotVersion)'"
        output += try await runInstallerCommand(
            executable: stagingPython.path,
            arguments: ["-c", verification],
            timeout: 30
        )

        try [finalRuntime, rollbackRuntime, stagingRuntime].forEach(rejectSymbolicLink)
        if fileManager.fileExists(atPath: rollbackRuntime.path) {
            try fileManager.removeItem(at: rollbackRuntime)
        }
        let hadPreviousRuntime = fileManager.fileExists(atPath: finalRuntime.path)
        if hadPreviousRuntime {
            try fileManager.moveItem(at: finalRuntime, to: rollbackRuntime)
        }
        do {
            try fileManager.moveItem(at: stagingRuntime, to: finalRuntime)
        } catch {
            if hadPreviousRuntime,
               !fileManager.fileExists(atPath: finalRuntime.path),
               fileManager.fileExists(atPath: rollbackRuntime.path) {
                try? fileManager.moveItem(at: rollbackRuntime, to: finalRuntime)
            }
            throw error
        }

        _ = PythonPathResolver.refresh()
        return output
    }

    private func runInstallerCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = ProcessEnvironment.configured()

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pathchanger-runtime-\(UUID().uuidString).log")
                guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
                      let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
                    continuation.resume(throwing: self.installerError("Unable to create installer output log"))
                    return
                }

                process.standardOutput = outputHandle
                process.standardError = outputHandle
                defer {
                    try? outputHandle.close()
                    try? FileManager.default.removeItem(at: outputURL)
                }

                do {
                    try process.run()
                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    if process.isRunning {
                        process.terminate()
                        process.waitUntilExit()
                        continuation.resume(throwing: self.installerError("Installer command timed out"))
                        return
                    }
                    try? outputHandle.close()
                    let data = (try? Data(contentsOf: outputURL)) ?? Data()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    guard process.terminationStatus == 0 else {
                        let snippet = output.split(separator: "\n").suffix(8).joined(separator: "\n")
                        continuation.resume(throwing: self.installerError(
                            snippet.isEmpty ? "Installer exited \(process.terminationStatus)" : snippet
                        ))
                        return
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private func installerError(_ message: String) -> NSError {
        NSError(
            domain: "PathChanger.ManagedRuntimeInstaller",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
