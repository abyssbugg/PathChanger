//
//  TunneldCommandExecutionState.swift
//  PathChanger
//

import Foundation

enum PrivilegedWrapperExecutionResult: Sendable {
    case returned(output: String, returnTime: TimeInterval)
    case failed(message: String)
    case timedOut
}

final class PrivilegedWrapperContinuation: @unchecked Sendable {
    private let continuation: CheckedContinuation<PrivilegedWrapperExecutionResult, Never>
    private let lock = NSLock()
    private var hasResumed = false

    init(continuation: CheckedContinuation<PrivilegedWrapperExecutionResult, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: PrivilegedWrapperExecutionResult) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()

        continuation.resume(returning: result)
    }
}

final class TunneldCommandExecutionState: @unchecked Sendable {
    let process = Process()
    let pipe = Pipe()
    let maxOutputSize: Int

    private let timeout: TimeInterval
    private let continuation: CheckedContinuation<String, Error>
    private let lock = NSLock()
    private var output = Data()
    private var hasFinished = false
    private var outputExceededLimit = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        command: String,
        arguments: [String],
        timeout: TimeInterval,
        maxOutputSize: Int,
        continuation: CheckedContinuation<String, Error>
    ) {
        self.timeout = timeout
        self.maxOutputSize = maxOutputSize
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessEnvironment.configured()
    }

    func appendOutput(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }

        lock.lock()
        defer { lock.unlock() }

        guard output.count + data.count <= maxOutputSize else {
            let remainingCapacity = max(0, maxOutputSize - output.count)
            if remainingCapacity > 0 {
                output.append(data.prefix(remainingCapacity))
            }
            outputExceededLimit = true
            return false
        }

        output.append(data)
        return true
    }

    func terminateWithGracePeriod() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.forceKillIfStillRunning()
        }
    }

    func makeTimeoutWorkItem() -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            guard let self else { return }
            terminateWithGracePeriod()
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Command timed out after \(timeout) seconds"]
            )))
        }
    }

    func installTimeout(_ timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func finishAfterTermination(_ terminatedProcess: Process) {
        guard !isFinished else { return }

        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = appendOutput(remainingData)
        let snapshot = outputSnapshot()

        if snapshot.exceededLimit {
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Output exceeded safety limit (\(maxOutputSize) bytes)"]
            )))
            return
        }

        let text = String(data: snapshot.data, encoding: .utf8) ?? ""
        guard terminatedProcess.terminationStatus == 0 else {
            let diagnostic = boundedDiagnostic(from: snapshot.data)
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: Int(terminatedProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Command exited with status \(terminatedProcess.terminationStatus): \(diagnostic)"]
            )))
            return
        }

        finish(.success(text))
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        let pendingTimeout = timeoutWorkItem
        timeoutWorkItem = nil
        lock.unlock()

        pendingTimeout?.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForReading.close()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasFinished
    }

    private func forceKillIfStillRunning() {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func outputSnapshot() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (output, outputExceededLimit)
    }

    private func boundedDiagnostic(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 4000 {
            return trimmed
        }
        return String(trimmed.suffix(4000))
    }
}