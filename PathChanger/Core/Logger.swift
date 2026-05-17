//
//  Logger.swift
//  PathChanger
//
//  Enhanced structured logging utility with file logging support
//

import Foundation
import os.log

private enum LogTextSanitizer {
    static let maxMessageLength = 4_000
    static let maxMetadataKeyLength = 64
    static let maxMetadataValueLength = 512

    static func message(_ value: String) -> String {
        sanitize(value, maxLength: maxMessageLength)
    }

    static func metadataKey(_ value: String) -> String {
        sanitize(value, maxLength: maxMetadataKeyLength)
    }

    static func metadataValue(_ value: String) -> String {
        sanitize(value, maxLength: maxMetadataValueLength)
    }

    private static func sanitize(_ value: String, maxLength: Int) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(min(value.count, maxLength))

        for scalar in value.unicodeScalars {
            switch scalar {
            case "\n":
                sanitized += "\\n"
            case "\r":
                sanitized += "\\r"
            case "\t":
                sanitized += "\\t"
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    sanitized += " "
                } else {
                    sanitized.unicodeScalars.append(scalar)
                }
            }

            if sanitized.count >= maxLength {
                return String(sanitized.prefix(maxLength)) + "…"
            }
        }

        return sanitized
    }
}

// MARK: - Log Metadata

/// Structured metadata for log entries
struct LogMetadata: Codable, Sendable {
    let sessionId: String?
    let deviceUDID: String?
    let iosVersion: String?
    let operationType: String?
    let additionalInfo: [String: String]?

    init(
        sessionId: String? = nil,
        deviceUDID: String? = nil,
        iosVersion: String? = nil,
        operationType: String? = nil,
        additionalInfo: [String: String]? = nil
    ) {
        self.sessionId = sessionId
        self.deviceUDID = deviceUDID
        self.iosVersion = iosVersion
        self.operationType = operationType
        self.additionalInfo = additionalInfo
    }

    static let empty = LogMetadata()

    /// Returns formatted metadata string for logging
    var formatted: String {
        var parts: [String] = []
        if let sessionId = sessionId {
            parts.append("session=\(LogTextSanitizer.metadataValue(sessionId))")
        }
        if let deviceUDID = deviceUDID {
            // Truncate UDID for privacy in logs
            let truncated = LogTextSanitizer.metadataValue(String(deviceUDID.prefix(8)) + "...")
            parts.append("device=\(truncated)")
        }
        if let iosVersion = iosVersion {
            parts.append("ios=\(LogTextSanitizer.metadataValue(iosVersion))")
        }
        if let operationType = operationType {
            parts.append("op=\(LogTextSanitizer.metadataValue(operationType))")
        }
        if let additionalInfo = additionalInfo {
            for (key, value) in additionalInfo.sorted(by: { $0.key < $1.key }) {
                let safeKey = LogTextSanitizer.metadataKey(key)
                let safeValue = LogTextSanitizer.metadataValue(value)
                parts.append("\(safeKey)=\(safeValue)")
            }
        }
        return parts.isEmpty ? "" : "[\(parts.joined(separator: ", "))]"
    }
}

// MARK: - Log Entry

/// Represents a single log entry for file logging
struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let metadata: LogMetadata?

    var formattedLine: String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = dateFormatter.string(from: timestamp)
        let meta = metadata?.formatted ?? ""
        let metaStr = meta.isEmpty ? "" : " \(meta)"
        return "[\(ts)] [\(level.uppercased())] [\(category)]\(metaStr) \(LogTextSanitizer.message(message))"
    }
}

// MARK: - File Logger

/// File-based logger with rotation support
actor FileLogger {
    static let shared = FileLogger()

    private let logDirectory: URL
    private let maxLogAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let maxLogSize: Int = 10 * 1024 * 1024 // 10 MB
    private var currentLogFile: URL?
    private var fileHandle: FileHandle?
    private var isEnabled: Bool = false

    init() {
        let appSupport = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = appSupport.appendingPathComponent("Logs/PathChanger", isDirectory: true)

        // Create log directory if needed
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            rotateLogsIfNeeded()
            openCurrentLogFile()
        } else {
            closeLogFile()
        }
    }

    func getEnabled() -> Bool {
        return isEnabled
    }

    func write(_ entry: LogEntry) {
        guard isEnabled else { return }

        let line = entry.formattedLine + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if fileHandle == nil {
            openCurrentLogFile()
        }

        fileHandle?.write(data)
    }

    func getLogDirectory() -> URL {
        return logDirectory
    }

    func exportLogs() -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return nil
        }

        let logFiles = files.filter { $0.pathExtension == "log" }
        guard !logFiles.isEmpty else { return nil }

        // Create export archive
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("PathChanger-Logs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Copy log files
        for file in logFiles {
            let dest = exportDir.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.copyItem(at: file, to: dest)
        }

        // Create zip archive
        let archivePath = FileManager.default.temporaryDirectory.appendingPathComponent("PathChanger-Logs.zip")
        try? FileManager.default.removeItem(at: archivePath)

        // Use ditto for zip creation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", exportDir.path, archivePath.path]
        try? process.run()
        process.waitUntilExit()

        // Cleanup temp directory
        try? FileManager.default.removeItem(at: exportDir)

        return process.terminationStatus == 0 ? archivePath : nil
    }

    private func openCurrentLogFile() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDirectory.appendingPathComponent("PathChanger-\(dateString).log")

        currentLogFile = logFile

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()
    }

    private func closeLogFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func rotateLogsIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            return
        }

        let now = Date()

        for file in files where file.pathExtension == "log" {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let creationDate = attributes[.creationDate] as? Date else {
                continue
            }

            // Remove logs older than maxLogAge
            if now.timeIntervalSince(creationDate) > maxLogAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

// MARK: - Logger

/// Centralized logging for PathChanger with structured metadata support
enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.pathchanger"

    private static let general = OSLog(subsystem: subsystem, category: "general")
    private static let session = OSLog(subsystem: subsystem, category: "session")
    private static let map = OSLog(subsystem: subsystem, category: "map")
    private static let device = OSLog(subsystem: subsystem, category: "device")
    private static let security = OSLog(subsystem: subsystem, category: "security")
    private static let performance = OSLog(subsystem: subsystem, category: "performance")
    private static let network = OSLog(subsystem: subsystem, category: "network")

    /// Current session ID for correlation
    private static var _sessionId: String = UUID().uuidString
    static var sessionId: String {
        get { _sessionId }
        set { _sessionId = newValue }
    }

    // MARK: - Log Levels with Metadata

    static func debug(_ message: String, category: Category = .general, metadata: LogMetadata? = nil) {
        let enrichedMetadata = enrichMetadata(metadata)
        let formattedMessage = formatMessage(message, metadata: enrichedMetadata)
        os_log(.debug, log: category.log, "%{public}@", formattedMessage)
        writeToFile(level: "debug", category: category.name, message: message, metadata: enrichedMetadata)
    }

    static func info(_ message: String, category: Category = .general, metadata: LogMetadata? = nil) {
        let enrichedMetadata = enrichMetadata(metadata)
        let formattedMessage = formatMessage(message, metadata: enrichedMetadata)
        os_log(.info, log: category.log, "%{public}@", formattedMessage)
        writeToFile(level: "info", category: category.name, message: message, metadata: enrichedMetadata)
    }

    static func error(_ message: String, category: Category = .general, metadata: LogMetadata? = nil) {
        let enrichedMetadata = enrichMetadata(metadata)
        let formattedMessage = formatMessage(message, metadata: enrichedMetadata)
        os_log(.error, log: category.log, "%{public}@", formattedMessage)
        writeToFile(level: "error", category: category.name, message: message, metadata: enrichedMetadata)
    }

    static func fault(_ message: String, category: Category = .general, metadata: LogMetadata? = nil) {
        let enrichedMetadata = enrichMetadata(metadata)
        let formattedMessage = formatMessage(message, metadata: enrichedMetadata)
        os_log(.fault, log: category.log, "%{public}@", formattedMessage)
        writeToFile(level: "fault", category: category.name, message: message, metadata: enrichedMetadata)
    }

    // MARK: - Performance Logging

    /// Log a performance metric with timing
    static func performance(_ operation: String, duration: TimeInterval, category: Category = .performance, metadata: LogMetadata? = nil) {
        let message = "\(operation) completed in \(String(format: "%.3f", duration * 1000))ms"
        var enriched = enrichMetadata(metadata)
        var additionalInfo = enriched.additionalInfo ?? [:]
        additionalInfo["duration_ms"] = String(format: "%.3f", duration * 1000)
        additionalInfo["operation"] = operation
        enriched = LogMetadata(
            sessionId: enriched.sessionId,
            deviceUDID: enriched.deviceUDID,
            iosVersion: enriched.iosVersion,
            operationType: enriched.operationType ?? operation,
            additionalInfo: additionalInfo
        )
        info(message, category: category, metadata: enriched)
    }

    // MARK: - Convenience Methods

    /// Log with device context
    static func debug(_ message: String, category: Category = .general, deviceUDID: String?, operation: String? = nil) {
        debug(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, operationType: operation))
    }

    static func info(_ message: String, category: Category = .general, deviceUDID: String?, operation: String? = nil) {
        info(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, operationType: operation))
    }

    static func error(_ message: String, category: Category = .general, deviceUDID: String?, operation: String? = nil) {
        error(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, operationType: operation))
    }

    /// Log with device context including iOS version
    static func debug(_ message: String, category: Category = .general, deviceUDID: String?, iosVersion: String?, operation: String? = nil) {
        debug(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, iosVersion: iosVersion, operationType: operation))
    }

    static func info(_ message: String, category: Category = .general, deviceUDID: String?, iosVersion: String?, operation: String? = nil) {
        info(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, iosVersion: iosVersion, operationType: operation))
    }

    static func error(_ message: String, category: Category = .general, deviceUDID: String?, iosVersion: String?, operation: String? = nil) {
        error(message, category: category, metadata: LogMetadata(deviceUDID: deviceUDID, iosVersion: iosVersion, operationType: operation))
    }

    // MARK: - File Logging Control

    /// Enable or disable file logging
    static func setFileLoggingEnabled(_ enabled: Bool) {
        Task {
            await FileLogger.shared.setEnabled(enabled)
        }
    }

    /// Check if file logging is enabled
    static func isFileLoggingEnabled() async -> Bool {
        await FileLogger.shared.getEnabled()
    }

    /// Export logs to a zip file for support
    static func exportLogs() async -> URL? {
        await FileLogger.shared.exportLogs()
    }

    /// Get the log directory path
    static func getLogDirectory() async -> URL {
        await FileLogger.shared.getLogDirectory()
    }

    /// Start a new logging session
    static func startNewSession() {
        sessionId = UUID().uuidString
        info("New logging session started", category: .general)
    }

    // MARK: - Private Helpers

    private static func enrichMetadata(_ metadata: LogMetadata?) -> LogMetadata {
        LogMetadata(
            sessionId: metadata?.sessionId ?? sessionId,
            deviceUDID: metadata?.deviceUDID,
            iosVersion: metadata?.iosVersion,
            operationType: metadata?.operationType,
            additionalInfo: metadata?.additionalInfo
        )
    }

    private static func formatMessage(_ message: String, metadata: LogMetadata) -> String {
        let metaStr = metadata.formatted
        let safeMessage = LogTextSanitizer.message(message)
        return metaStr.isEmpty ? safeMessage : "\(metaStr) \(safeMessage)"
    }

    private static func writeToFile(level: String, category: String, message: String, metadata: LogMetadata) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        Task {
            await FileLogger.shared.write(entry)
        }
    }

    // MARK: - Categories

    enum Category: String, CaseIterable {
        case general
        case session
        case map
        case device
        case security
        case performance
        case network

        var log: OSLog {
            switch self {
            case .general: return Logger.general
            case .session: return Logger.session
            case .map: return Logger.map
            case .device: return Logger.device
            case .security: return Logger.security
            case .performance: return Logger.performance
            case .network: return Logger.network
            }
        }

        var name: String { rawValue }
    }
}
