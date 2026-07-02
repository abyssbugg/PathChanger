//
//  DeviceManager+CommandExecution.swift
//  PathChanger
//

import Foundation
import Combine

@MainActor
extension DeviceManager {
    func runPython(arguments: [String], timeout: TimeInterval = 30.0) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment using centralized configuration
        process.environment = ProcessEnvironment.configured()

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
                do {
                    try process.run()

                    // Timeout handling with proper error throwing
                    var didTimeout = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            didTimeout = true
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: DeviceError.commandFailed("Command timed out after \(timeout) seconds"))
                        return
                    }

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    // Combine output
                    continuation.resume(returning: output + errorOutput)
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    continuation.resume(throwing: DeviceError.commandFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Legacy Command Execution (for pgrep etc)
    func runCommand(_ command: String, arguments: [String] = [], timeout: TimeInterval = 10.0) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Set environment using centralized configuration
        process.environment = ProcessEnvironment.configured()

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
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

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: DeviceError.commandFailed("Command timed out after \(timeout) seconds"))
                        return
                    }

                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    continuation.resume(returning: output)
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    continuation.resume(throwing: DeviceError.commandFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Convenience Methods
    var hasDevices: Bool {
        !devices.isEmpty
    }

    var isConnected: Bool {
        connectionState.isConnected
    }

    func selectDevice(_ device: Device) async {
        do {
            try await connect(to: device)
        } catch {
            lastError = error as? DeviceError ?? .connectionFailed(error.localizedDescription)
        }
    }

    func setConnectionMode(_ mode: ConnectionMode) {
        connectionMode = mode
        Task {
            await refreshDevices()
        }
    }
}
