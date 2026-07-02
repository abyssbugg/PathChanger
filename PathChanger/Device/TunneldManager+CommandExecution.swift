//
//  TunneldManager+CommandExecution.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func runCommand(_ command: String, arguments: [String], timeout: TimeInterval? = nil) async throws -> String {
        let effectiveTimeout = max(0.1, timeout ?? AppSettings.shared.commandTimeout)

        return try await withCheckedThrowingContinuation { continuation in
            let execution = TunneldCommandExecutionState(
                command: command,
                arguments: arguments,
                timeout: effectiveTimeout,
                maxOutputSize: TunneldManager.maxOutputSize,
                continuation: continuation
            )

            execution.pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                if !execution.appendOutput(data) {
                    Logger.error("[SECURITY] Subprocess output exceeded limit (max: \(execution.maxOutputSize) bytes)", category: .security)
                    execution.terminateWithGracePeriod()
                }
            }

            execution.process.terminationHandler = { terminatedProcess in
                execution.finishAfterTermination(terminatedProcess)
            }

            let timeoutItem = execution.makeTimeoutWorkItem()
            execution.installTimeout(timeoutItem)

            do {
                try execution.process.run()
            } catch {
                execution.finish(.failure(error))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + effectiveTimeout, execute: timeoutItem)
        }
    }

    /// Returns the maximum output size limit for testing purposes
    nonisolated static var maxOutputSizeLimit: Int {
        return maxOutputSize
    }
}
