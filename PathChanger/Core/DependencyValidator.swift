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
                suggestion: "Install with: pip3 install pymobiledevice3"
            )
        case .pymobiledevice3VersionTooOld(let version):
            return ValidationError(
                type: .pymobiledevice3VersionTooOld,
                message: "pymobiledevice3 version \(version) is too old (minimum: 6.1.5)",
                suggestion: "Upgrade with: pip3 install --upgrade pymobiledevice3"
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
}
