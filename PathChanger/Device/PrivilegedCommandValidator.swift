//
//  PrivilegedCommandValidator.swift
//  PathChanger
//

import Foundation

// MARK: - Security Validation

/// Security errors for privileged command validation
enum PrivilegedCommandError: LocalizedError {
    case invalidPythonPath(String)
    case dangerousCharacters(String)
    case unrecognizedCommand(String)
    case commandStructureInvalid(String)

    var errorDescription: String? {
        switch self {
        case .invalidPythonPath(let path):
            return "Invalid Python path: \(path)"
        case .dangerousCharacters(let chars):
            return "Dangerous characters detected: \(chars)"
        case .unrecognizedCommand(let cmd):
            return "Unrecognized command pattern: \(cmd)"
        case .commandStructureInvalid(let reason):
            return "Invalid command structure: \(reason)"
        }
    }
}

/// Security validator for privileged AppleScript commands
/// Only allows pre-approved pymobiledevice3 operations to prevent command injection.
///
/// Python-path and forbidden-character lists are sourced from `SubprocessPolicy`
/// (single source of truth). Command-pattern allowlist is kept local because
/// privileged commands are a narrower whitelist than general pmd3 invocations.
struct PrivilegedCommandValidator {

    // MARK: - Security Constants

    /// Allowed pymobiledevice3 command patterns (exact subcommand match required).
    /// This is narrower than `SubprocessPolicy.allowedSubcommands` because only
    /// these specific compositions are permitted under privileged execution.
    private static let allowedCommandPatterns: [(module: String, subcommands: [String])] = [
        ("lockdown", ["start-tunnel"]),
        ("remote", ["start-tunnel", "-t", "wifi"]),
        ("remote", ["tunneld"])
    ]

    /// Characters that should NEVER appear in privileged commands — sourced from the
    /// narrower `SubprocessPolicy.privilegedCommandForbiddenCharacters` set.
    ///
    /// This is intentionally narrower than `SubprocessPolicy.forbiddenCharacters`
    /// because privileged shell commands legitimately contain `&` (backgrounding)
    /// and `>` (log redirect) — see SubprocessPolicy doc comment for rationale.
    private static var dangerousCharacters: Set<Character> { SubprocessPolicy.privilegedCommandForbiddenCharacters }

    // MARK: - Validation

    /// Validates a command is safe for privileged execution
    /// - Parameters:
    ///   - command: The full command string to validate
    ///   - pythonPath: The Python executable path being used
    /// - Returns: Success if command is safe, failure with specific error otherwise
    static func validate(command: String, pythonPath: String) -> Result<Void, PrivilegedCommandError> {
        // Step 1: Validate Python path is in allowlist
        if !isPythonPathAllowed(pythonPath) {
            return .failure(.invalidPythonPath(pythonPath))
        }

        // Step 2: Check for dangerous shell metacharacters
        for char in dangerousCharacters {
            if command.contains(char) {
                return .failure(.dangerousCharacters(String(char)))
            }
        }

        // Step 3: Validate command starts with the approved Python path
        guard command.hasPrefix(pythonPath) else {
            return .failure(.commandStructureInvalid("Command must start with approved Python path"))
        }

        // Step 4: Validate pymobiledevice3 module invocation
        guard command.contains("-m pymobiledevice3") else {
            return .failure(.commandStructureInvalid("Must invoke pymobiledevice3 via -m flag"))
        }

        // Step 5: Validate command matches one of the allowed patterns
        let isAllowed = allowedCommandPatterns.contains { pattern in
            command.contains("pymobiledevice3 \(pattern.module)") &&
            pattern.subcommands.allSatisfy { command.contains($0) }
        }

        guard isAllowed else {
            return .failure(.unrecognizedCommand("Command does not match any allowed pattern"))
        }

        return .success(())
    }

    /// Quick check if a Python path is in the allowlist
    static func isPythonPathAllowed(_ path: String) -> Bool {
        SubprocessPolicy.isAllowedPythonPath(path)
    }
}

