//
//  BoundedProcessRunner.swift
//  PathChanger
//
//  A subprocess run with the limits every untrusted-output boundary in the app keeps: a
//  deadline, a 1 MB output cap, the hardened `ProcessEnvironment`, an explicit exit
//  status, cancellation, and both pipe ends closed on every path. It never waits on the
//  caller's actor: the process is launched, read and reaped on a background thread.
//

import Darwin
import Foundation

/// The outcome of one bounded subprocess run.
struct BoundedProcessResult: Equatable, Sendable {
    enum Termination: Equatable, Sendable {
        /// The process exited on its own with this status.
        case exited(Int32)
        /// The deadline passed; the process was stopped.
        case timedOut
        /// The process wrote more than `BoundedProcessRunner.maxOutputBytes`; it was stopped.
        case outputLimitExceeded
        /// The calling task was cancelled; the process was stopped.
        case cancelled
        /// The process could not be started.
        case launchFailed(String)
    }

    let termination: Termination
    /// Standard output and standard error, interleaved, at most `maxOutputBytes`.
    let output: String

    /// True only for a zero exit status.
    var succeeded: Bool { termination == .exited(0) }

    /// A plain-language reason the run did not succeed, or nil when it did.
    var failureDescription: String? {
        switch termination {
        case .exited(0): return nil
        case .exited(let status): return "exited with status \(status)"
        case .timedOut: return "did not finish in time and was stopped"
        case .outputLimitExceeded: return "wrote more output than the 1 MB limit and was stopped"
        case .cancelled: return "was cancelled"
        case .launchFailed(let reason): return "could not start: \(reason)"
        }
    }
}

struct BoundedProcessRunner: Sendable {
    static let defaultTimeout: TimeInterval = 15
    /// Matches the other subprocess boundaries (`DevLocationBridge`, `TunneldManager`).
    static let maxOutputBytes = 1_048_576

    let timeout: TimeInterval

    init(timeout: TimeInterval = BoundedProcessRunner.defaultTimeout) {
        self.timeout = timeout
    }

    func run(executable: String, arguments: [String]) async -> BoundedProcessResult {
        let cancellation = CancellationFlag()
        let timeout = self.timeout
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.execute(
                        executable: executable,
                        arguments: arguments,
                        timeout: timeout,
                        cancellation: cancellation
                    ))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    // MARK: - Background execution

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    /// How often the read loop wakes to check the deadline and cancellation.
    private static let pollIntervalMilliseconds: Int32 = 50
    /// After the process exits, how long to keep draining output a child process may still
    /// hold open before giving up on it.
    private static let drainGraceSeconds: TimeInterval = 1
    /// After SIGTERM, how long to wait before SIGKILL.
    private static let terminateGraceSeconds: TimeInterval = 1

    /// Blocking; runs on a background queue only.
    private static func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        cancellation: CancellationFlag
    ) -> BoundedProcessResult {
        guard !cancellation.isCancelled else {
            return BoundedProcessResult(termination: .cancelled, output: "")
        }

        let process = Process()
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        defer {
            // Drained or not, both ends close on every path (pipe-leak lesson, 2026-10-25).
            try? reader.close()
            try? pipe.fileHandleForWriting.close()
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        process.environment = ProcessEnvironment.configured()

        do {
            try process.run()
        } catch {
            return BoundedProcessResult(termination: .launchFailed(error.localizedDescription), output: "")
        }
        // Only the child writes; without this the read end never sees end-of-file.
        try? pipe.fileHandleForWriting.close()

        let descriptor = reader.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var output = Data()
        var stopReason: BoundedProcessResult.Termination?
        var exitedAt: Date?
        var buffer = [UInt8](repeating: 0, count: 65_536)

        readLoop: while true {
            if cancellation.isCancelled { stopReason = .cancelled; break }
            if Date() >= deadline { stopReason = .timedOut; break }
            if exitedAt == nil, !process.isRunning { exitedAt = Date() }
            if let exitedAt, Date().timeIntervalSince(exitedAt) >= drainGraceSeconds { break }

            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, pollIntervalMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }

            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                output.append(contentsOf: buffer[0..<count])
                if output.count > maxOutputBytes {
                    output = output.prefix(maxOutputBytes)
                    stopReason = .outputLimitExceeded
                    break readLoop
                }
            } else if count == 0 {
                break // End of file: every writer closed.
            } else if errno != EINTR && errno != EAGAIN {
                break
            }
        }

        if stopReason == nil {
            // End of file can arrive just before the process is reaped; wait for its exit
            // within the same deadline.
            while process.isRunning {
                if cancellation.isCancelled { stopReason = .cancelled; break }
                if Date() >= deadline { stopReason = .timedOut; break }
                usleep(10_000)
            }
        }
        if process.isRunning {
            stop(process)
        }
        process.waitUntilExit()

        let text = String(decoding: output, as: UTF8.self)
        if let stopReason {
            return BoundedProcessResult(termination: stopReason, output: text)
        }
        return BoundedProcessResult(termination: .exited(process.terminationStatus), output: text)
    }

    /// SIGTERM, then SIGKILL if the process outlives the grace period. Only the process
    /// this runner launched is signalled.
    private static func stop(_ process: Process) {
        process.terminate()
        let killAt = Date().addingTimeInterval(terminateGraceSeconds)
        while process.isRunning && Date() < killAt {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
