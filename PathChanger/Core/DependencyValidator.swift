//
//  DependencyValidator.swift
//  PathChanger
//
//  Pre-flight validation of Python and pymobiledevice3 dependencies
//  Prevents startup failures by validating all required tools upfront
//

import Foundation

/// Validates project dependencies at startup
@MainActor
class DependencyValidator: ObservableObject {
    @Published var validationStatus: ValidationStatus = .pending
    @Published var errors: [ValidationError] = []
    @Published var installProgress: String = ""

    /// Python the Aug 9 app checks and installs against. Not pyenv, not pip3.
    nonisolated static let runtimePythonPath = "/usr/bin/python3"

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
            case pymobiledevice3VersionTooOld
            case pythonNotExecutable
        }
    }

    static let shared = DependencyValidator()
    private init() {}

    /// Run complete dependency validation
    func validateAll() async {
        validationStatus = .validating
        errors.removeAll()

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
                suggestion: "Install Python 3.9 or later from https://www.python.org or use: brew install python3"
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
                message: "Python version \(version) is too old (minimum: 3.9)",
                suggestion: "Upgrade Python to 3.9 or later"
            )
        case .pymobiledevice3NotInstalled:
            return ValidationError(
                type: .pythonMissing,
                message: "Unexpected error during Python validation",
                suggestion: "Try restarting the application"
            )
        case .pymobiledevice3VersionTooOld:
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
                message: "pymobiledevice3 is not installed",
                suggestion: "Install the latest pymobiledevice3 from PathChanger"
            )
        case .pymobiledevice3VersionTooOld(let version):
            return ValidationError(
                type: .pymobiledevice3VersionTooOld,
                message: "pymobiledevice3 version \(version) is too old (minimum: 6.1.5)",
                suggestion: "Install the latest pymobiledevice3 from PathChanger"
            )
        case .pythonNotFound, .pythonNotExecutable, .invalidPythonVersion:
            return ValidationError(
                type: .pymobiledevice3Missing,
                message: "Cannot validate pymobiledevice3 - Python issue found",
                suggestion: "Fix Python installation first"
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

    /// True when Python is usable and pymobiledevice3 is missing or too old.
    var canInstallPymobiledevice3: Bool {
        let pythonBroken = errors.contains {
            $0.type == .pythonMissing || $0.type == .pythonVersionTooOld || $0.type == .pythonNotExecutable
        }
        let pmd3Issue = errors.contains {
            $0.type == .pymobiledevice3Missing || $0.type == .pymobiledevice3VersionTooOld
        }
        return !pythonBroken && pmd3Issue
    }

    /// Install the latest pymobiledevice3 into the same interpreter the app checks.
    /// No version pin. Does not use pip3 or pyenv.
    func installLatestPymobiledevice3() async {
        validationStatus = .installing
        installProgress = "Installing the latest pymobiledevice3…"

        do {
            let output = try await runPipInstallLatest()
            Logger.info("pymobiledevice3 install finished:\n\(output.suffix(500))", category: .device)
            installProgress = "Install finished. Rechecking…"
            await validateAll()
            if validationStatus == .valid {
                installProgress = "pymobiledevice3 is ready."
            } else {
                installProgress = "Install ran but PathChanger still cannot see pymobiledevice3."
            }
        } catch {
            Logger.error("pymobiledevice3 install failed: \(error.localizedDescription)", category: .device)
            installProgress = "Install failed: \(error.localizedDescription)"
            validationStatus = .invalid
        }
    }

    private func runPipInstallLatest() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: DependencyValidator.runtimePythonPath)
                process.arguments = ["-m", "pip", "install", "--user", "--upgrade", "pymobiledevice3"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()

                    let timeout = DispatchTime.now() + 600
                    while process.isRunning {
                        if DispatchTime.now() > timeout {
                            process.terminate()
                            continuation.resume(throwing: NSError(
                                domain: "PathChanger",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Install timed out after 10 minutes"]
                            ))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.2)
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let snippet = output.split(separator: "\n").suffix(8).joined(separator: "\n")
                        continuation.resume(throwing: NSError(
                            domain: "PathChanger",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: snippet.isEmpty ? "pip exited \(process.terminationStatus)" : snippet]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
