//
//  PrivilegedTunnelCommand.swift
//  PathChanger
//
//  Builds the only shell commands allowed to run with administrator privileges:
//  start-tunnel / tunneld, and stop of PIDs we launched. Detect, install, and
//  device list stay unprivileged.
//

import Foundation

enum PrivilegedTunnelCommand {
    enum ValidationError: Error, Equatable, LocalizedError {
        case unapprovedPythonPath(String)
        case unapprovedArguments([String])
        case unsafePath(String)
        case unapprovedProcessIds([Int32])

        var errorDescription: String? {
            switch self {
            case .unapprovedPythonPath(let path):
                return "Python path is not on the tunnel allowlist: \(path)"
            case .unapprovedArguments(let arguments):
                return "Tunnel arguments are not an approved start command: \(arguments.joined(separator: " "))"
            case .unsafePath(let path):
                return "Refusing to embed an unsafe path in an elevated command: \(path)"
            case .unapprovedProcessIds(let pids):
                return "Refusing to elevate stop for invalid process ids: \(pids)"
            }
        }
    }

    /// Exact argv lists that may be launched with administrator privileges.
    static let allowedArgumentLists: [[String]] = TunnelMode.allCases.compactMap {
        TunneldManager.arguments(for: $0)
    }

    static func isApprovedPythonPath(_ path: String) -> Bool {
        PythonPathResolver.candidatePaths.contains(path)
    }

    static func isApprovedArgumentList(_ arguments: [String]) -> Bool {
        allowedArgumentLists.contains(arguments)
    }

    /// Start command. stdout of the shell is the new PID (`echo $!`).
    static func startShellCommand(
        pythonPath: String,
        arguments: [String],
        logFilePath: String
    ) -> Result<String, ValidationError> {
        guard isApprovedPythonPath(pythonPath) else {
            return .failure(.unapprovedPythonPath(pythonPath))
        }
        guard isApprovedArgumentList(arguments) else {
            return .failure(.unapprovedArguments(arguments))
        }
        guard let quotedPython = posixSingleQuote(pythonPath) else {
            return .failure(.unsafePath(pythonPath))
        }
        guard let quotedLog = posixSingleQuote(logFilePath) else {
            return .failure(.unsafePath(logFilePath))
        }

        var quotedTokens = [quotedPython]
        for argument in arguments {
            guard let quoted = posixSingleQuote(argument) else {
                return .failure(.unsafePath(argument))
            }
            quotedTokens.append(quoted)
        }

        let launch = quotedTokens.joined(separator: " ")
        return .success("\(launch) > \(quotedLog) 2>&1 & echo $!")
    }

    static func stopShellCommand(pids: [Int32]) -> Result<String, ValidationError> {
        guard !pids.isEmpty, pids.allSatisfy({ $0 > 1 }) else {
            return .failure(.unapprovedProcessIds(pids))
        }
        let pidList = pids.map(String.init).joined(separator: " ")
        return .success("/bin/kill -15 \(pidList); /bin/sleep 0.2; /bin/kill -9 \(pidList)")
    }

    static func parseLaunchedPid(from output: String) -> Int32? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(trimmed), pid > 1 else {
            return nil
        }
        return pid
    }

    /// Quote for `/bin/sh` without allowing embedded single quotes.
    static func posixSingleQuote(_ value: String) -> String? {
        guard !value.isEmpty, !value.contains("'") else {
            return nil
        }
        return "'\(value)'"
    }
}
