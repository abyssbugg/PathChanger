//
//  DeviceManager+CommandExecution.swift
//  PathChanger
//

import Foundation
import Combine
import Darwin

/// Thread-safe, size-capped accumulator for subprocess output. Prevents unbounded
/// memory use and, together with concurrent draining, avoids pipe-buffer deadlock.
/// Bytes beyond the cap are marked truncated and discarded.
final class CappedOutputCollector: @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var data = Data()
    private(set) var truncated = false

    init(cap: Int) { self.cap = cap }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        guard data.count < cap else { truncated = true; return }
        let room = cap - data.count
        if chunk.count <= room {
            data.append(chunk)
        } else {
            data.append(chunk.prefix(room))
            truncated = true
        }
    }

    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
extension DeviceManager {
    /// Upper bound on captured subprocess output (defense against unbounded output).
    static let maxSubprocessOutputBytes = 5 * 1024 * 1024

    /// Run a configured process, concurrently draining stdout/stderr into size-capped
    /// buffers so the child never blocks on a full pipe, and enforcing the timeout
    /// with SIGTERM then SIGKILL escalation. Returns captured (stdout, stderr).
    private func runProcessCaptured(
        _ process: Process,
        stdout: Pipe,
        stderr: Pipe,
        timeout: TimeInterval
    ) async throws -> (out: String, err: String) {
        let cap = Self.maxSubprocessOutputBytes
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(out: String, err: String), Error>) in
            let resumeLock = NSLock()
            var hasResumed = false
            let outCollector = CappedOutputCollector(cap: cap)
            let errCollector = CappedOutputCollector(cap: cap)
            let outEOF = DispatchSemaphore(value: 0)
            let errEOF = DispatchSemaphore(value: 0)
            let outHandle = stdout.fileHandleForReading
            let errHandle = stderr.fileHandleForReading

            // Drain concurrently so a large writer never blocks on a full pipe.
            outHandle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    fh.readabilityHandler = nil
                    outEOF.signal()
                } else {
                    outCollector.append(chunk)
                }
            }
            errHandle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty {
                    fh.readabilityHandler = nil
                    errEOF.signal()
                } else {
                    errCollector.append(chunk)
                }
            }

            func finish(_ result: Result<(out: String, err: String), Error>) {
                resumeLock.lock(); defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            DispatchQueue.global().async {
                do {
                    try process.run()
                } catch {
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    finish(.failure(DeviceError.commandFailed(error.localizedDescription)))
                    return
                }

                var didTimeout = false
                let termItem = DispatchWorkItem {
                    if process.isRunning {
                        didTimeout = true
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: termItem)
                // Escalate to SIGKILL if the process ignores SIGTERM.
                let killItem = DispatchWorkItem {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 3.0, execute: killItem)

                process.waitUntilExit()
                termItem.cancel()
                killItem.cancel()

                // Bounded wait for the drains to reach EOF so no output is lost.
                _ = outEOF.wait(timeout: .now() + 2.0)
                _ = errEOF.wait(timeout: .now() + 2.0)
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil

                if didTimeout {
                    finish(.failure(DeviceError.commandFailed("Command timed out after \(timeout) seconds")))
                } else {
                    finish(.success((outCollector.string(), errCollector.string())))
                }
            }
        }
    }

    func runPython(arguments: [String], timeout: TimeInterval = 30.0) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessEnvironment.configured()

        let result = try await runProcessCaptured(process, stdout: outputPipe, stderr: errorPipe, timeout: timeout)
        return result.out + result.err
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
        process.environment = ProcessEnvironment.configured()

        let result = try await runProcessCaptured(process, stdout: pipe, stderr: errorPipe, timeout: timeout)
        return result.out
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
