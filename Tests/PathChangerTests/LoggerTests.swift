//
//  LoggerTests.swift
//  PathChangerTests
//
//  Tests for Logger and structured logging (CODE-002)
//

import XCTest
@testable import PathChanger

// MARK: - LogMetadata Tests

final class LogMetadataTests: XCTestCase {

    func testEmptyMetadata() {
        let metadata = LogMetadata.empty

        XCTAssertNil(metadata.sessionId)
        XCTAssertNil(metadata.deviceUDID)
        XCTAssertNil(metadata.operationType)
        XCTAssertNil(metadata.additionalInfo)
    }

    func testMetadataWithAllFields() {
        let metadata = LogMetadata(
            sessionId: "test-session-123",
            deviceUDID: "00008030-001234567890ABCD",
            operationType: "setLocation",
            additionalInfo: ["lat": "35.6762", "lon": "139.6503"]
        )

        XCTAssertEqual(metadata.sessionId, "test-session-123")
        XCTAssertEqual(metadata.deviceUDID, "00008030-001234567890ABCD")
        XCTAssertEqual(metadata.operationType, "setLocation")
        XCTAssertNotNil(metadata.additionalInfo)
        XCTAssertEqual(metadata.additionalInfo?["lat"], "35.6762")
    }

    func testMetadataFormattedWithSession() {
        let metadata = LogMetadata(sessionId: "abc123")

        let formatted = metadata.formatted

        XCTAssertTrue(formatted.contains("session=abc123"))
    }

    func testMetadataFormattedWithDevice() {
        let metadata = LogMetadata(deviceUDID: "00008030-001234567890ABCD")

        let formatted = metadata.formatted

        // UDID should be truncated for privacy
        XCTAssertTrue(formatted.contains("device=00008030..."))
        XCTAssertFalse(formatted.contains("001234567890ABCD"))
    }

    func testMetadataFormattedWithOperation() {
        let metadata = LogMetadata(operationType: "clearLocation")

        let formatted = metadata.formatted

        XCTAssertTrue(formatted.contains("op=clearLocation"))
    }

    func testMetadataFormattedWithAdditionalInfo() {
        let metadata = LogMetadata(additionalInfo: ["key1": "value1", "key2": "value2"])

        let formatted = metadata.formatted

        XCTAssertTrue(formatted.contains("key1=value1"))
        XCTAssertTrue(formatted.contains("key2=value2"))
    }

    func testMetadataFormattedEscapesMultilineValues() {
        let metadata = LogMetadata(
            sessionId: "session\nwith\rcontrols",
            operationType: "diagnostics\tcheck",
            additionalInfo: [
                "multi\nline": "first\nsecond\rthird\tfourth"
            ]
        )

        let formatted = metadata.formatted

        XCTAssertFalse(formatted.contains("\n"))
        XCTAssertFalse(formatted.contains("\r"))
        XCTAssertFalse(formatted.contains("\t"))
        XCTAssertTrue(formatted.contains("\\n"))
        XCTAssertTrue(formatted.contains("\\r"))
        XCTAssertTrue(formatted.contains("\\t"))
    }

    func testMetadataFormattedBoundsAdditionalValues() {
        let longValue = String(repeating: "x", count: 2_000)
        let metadata = LogMetadata(additionalInfo: ["long": longValue])

        let formatted = metadata.formatted

        XCTAssertLessThan(formatted.count, longValue.count)
        XCTAssertTrue(formatted.contains("…"))
    }

    func testEmptyMetadataFormattedReturnsEmptyString() {
        let metadata = LogMetadata.empty

        XCTAssertEqual(metadata.formatted, "")
    }

    func testMetadataFormattedIsBracketed() {
        let metadata = LogMetadata(sessionId: "test123")

        let formatted = metadata.formatted

        XCTAssertTrue(formatted.hasPrefix("["))
        XCTAssertTrue(formatted.hasSuffix("]"))
    }
}

// MARK: - LogEntry Tests

final class LogEntryTests: XCTestCase {

    func testLogEntryFormattedLine() {
        let entry = LogEntry(
            timestamp: Date(),
            level: "info",
            category: "general",
            message: "Test message",
            metadata: nil
        )

        let line = entry.formattedLine

        XCTAssertTrue(line.contains("[INFO]"))
        XCTAssertTrue(line.contains("[general]"))
        XCTAssertTrue(line.contains("Test message"))
    }

    func testLogEntryWithMetadata() {
        let metadata = LogMetadata(sessionId: "session123", operationType: "test")
        let entry = LogEntry(
            timestamp: Date(),
            level: "debug",
            category: "device",
            message: "Device connected",
            metadata: metadata
        )

        let line = entry.formattedLine

        XCTAssertTrue(line.contains("[DEBUG]"))
        XCTAssertTrue(line.contains("[device]"))
        XCTAssertTrue(line.contains("session=session123"))
        XCTAssertTrue(line.contains("Device connected"))
    }

    func testLogEntryEscapesMultilineMessage() {
        let entry = LogEntry(
            timestamp: Date(),
            level: "error",
            category: "general",
            message: "line1\nline2\rline3\tline4",
            metadata: nil
        )

        let line = entry.formattedLine

        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.contains("\r"))
        XCTAssertFalse(line.contains("\t"))
        XCTAssertTrue(line.contains("\\n"))
        XCTAssertTrue(line.contains("\\r"))
        XCTAssertTrue(line.contains("\\t"))
    }

    func testLogEntryLevelIsUppercased() {
        let entry = LogEntry(
            timestamp: Date(),
            level: "error",
            category: "security",
            message: "Error occurred",
            metadata: nil
        )

        XCTAssertTrue(entry.formattedLine.contains("[ERROR]"))
    }

    func testLogEntryContainsISO8601Timestamp() {
        let entry = LogEntry(
            timestamp: Date(),
            level: "info",
            category: "general",
            message: "Test",
            metadata: nil
        )

        let line = entry.formattedLine

        // ISO8601 format should contain T and Z
        XCTAssertTrue(line.contains("T"))
        XCTAssertTrue(line.contains("Z"))
    }
}

// MARK: - Logger Category Tests

final class LoggerCategoryTests: XCTestCase {

    func testAllCategoriesHaveNames() {
        for category in Logger.Category.allCases {
            XCTAssertFalse(category.name.isEmpty)
            XCTAssertEqual(category.name, category.rawValue)
        }
    }

    func testCategoryCount() {
        // Should have 7 categories: general, session, map, device, security, performance, network
        XCTAssertEqual(Logger.Category.allCases.count, 7)
    }

    func testNetworkCategoryExists() {
        XCTAssertNotNil(Logger.Category.network)
        XCTAssertEqual(Logger.Category.network.name, "network")
    }

    func testPerformanceCategoryExists() {
        XCTAssertNotNil(Logger.Category.performance)
        XCTAssertEqual(Logger.Category.performance.name, "performance")
    }
}

// MARK: - Logger Session Tests

final class LoggerSessionTests: XCTestCase {

    func testSessionIdIsNotEmpty() {
        XCTAssertFalse(Logger.sessionId.isEmpty)
    }

    func testSessionIdCanBeSet() {
        let originalId = Logger.sessionId
        let newId = "test-session-\(UUID().uuidString)"

        Logger.sessionId = newId

        XCTAssertEqual(Logger.sessionId, newId)

        // Restore
        Logger.sessionId = originalId
    }

    func testStartNewSessionChangesSessionId() {
        let originalId = Logger.sessionId

        Logger.startNewSession()

        XCTAssertNotEqual(Logger.sessionId, originalId)
    }
}

// MARK: - Logger File Logging Tests

final class LoggerFileLoggingTests: XCTestCase {

    func testFileLoggingCanBeEnabled() async {
        // Should not throw
        Logger.setFileLoggingEnabled(true)

        // Small delay to allow async operation
        try? await Task.sleep(nanoseconds: 100_000_000)

        let enabled = await Logger.isFileLoggingEnabled()
        XCTAssertTrue(enabled)

        // Disable after test
        Logger.setFileLoggingEnabled(false)
    }

    func testFileLoggingCanBeDisabled() async {
        Logger.setFileLoggingEnabled(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        Logger.setFileLoggingEnabled(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let enabled = await Logger.isFileLoggingEnabled()
        XCTAssertFalse(enabled)
    }

    func testLogDirectoryIsValid() async {
        let logDir = await Logger.getLogDirectory()

        XCTAssertTrue(logDir.path.contains("Logs/PathChanger"))
    }
}

// MARK: - FileLogger Tests

final class FileLoggerTests: XCTestCase {

    func testFileLoggerIsSingleton() async {
        let instance1 = FileLogger.shared
        let instance2 = FileLogger.shared

        // Both should be the same actor instance
        let dir1 = await instance1.getLogDirectory()
        let dir2 = await instance2.getLogDirectory()

        XCTAssertEqual(dir1, dir2)
    }

    func testFileLoggerLogDirectoryPath() async {
        let logDir = await FileLogger.shared.getLogDirectory()

        XCTAssertTrue(logDir.path.contains("Library"))
        XCTAssertTrue(logDir.path.contains("Logs"))
        XCTAssertTrue(logDir.path.contains("PathChanger"))
    }
}

// MARK: - Log Redaction Tests

final class LogRedactionTests: XCTestCase {

    func testLogRedactorMasksDeviceIdentifiersCoordinatesAndHomePaths() {
        let raw = "device=00008030-001234567890ABCD legacy=00008030001234567890123456789012345678ab lat=37.3317 lon=-122.0307 file=/Users/alice/Library/Logs/PathChanger/private.log"

        let redacted = LogRedactor.redact(raw)

        XCTAssertFalse(redacted.contains("00008030-001234567890ABCD"))
        XCTAssertFalse(redacted.contains("00008030001234567890123456789012345678ab"))
        XCTAssertFalse(redacted.contains("37.3317"))
        XCTAssertFalse(redacted.contains("-122.0307"))
        XCTAssertFalse(redacted.contains("/Users/alice"))
        XCTAssertTrue(redacted.contains("[REDACTED"))
    }

    func testLogEntryFormattedLineRedactsSensitiveMessageAndMetadataValues() {
        let entry = LogEntry(
            timestamp: Date(),
            level: "info",
            category: "device",
            message: "Setting 37.3317,-122.0307 on 00008030-001234567890ABCD",
            metadata: LogMetadata(
                sessionId: "session-1",
                deviceUDID: "00008030-001234567890ABCD",
                operationType: "diagnostics",
                additionalInfo: [
                    "path": "/Users/alice/Library/Logs/PathChanger/private.log",
                    "latitude": "37.3317",
                    "longitude": "-122.0307"
                ]
            )
        )

        let line = entry.formattedLine

        XCTAssertFalse(line.contains("00008030-001234567890ABCD"))
        XCTAssertFalse(line.contains("37.3317"))
        XCTAssertFalse(line.contains("-122.0307"))
        XCTAssertFalse(line.contains("/Users/alice"))
        XCTAssertTrue(line.contains("[REDACTED"))
    }

    func testFileLoggerExportWritesRedactedLogCopies() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathChanger-LoggerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let rawLog = tempRoot.appendingPathComponent("PathChanger-test.log")
        try "[2026-06-11T00:00:00Z] [INFO] [device] device=00008030-001234567890ABCD lat=37.3317 lon=-122.0307 path=/Users/alice/private\n"
            .write(to: rawLog, atomically: true, encoding: .utf8)

        let logger = FileLogger(logDirectory: tempRoot)
        let exportedArchive = await logger.exportLogs()
        let archive = try XCTUnwrap(exportedArchive)

        let unzipDir = tempRoot.appendingPathComponent("unzipped", isDirectory: true)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, unzipDir.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let exportedText = try collectTextFiles(under: unzipDir, extension: "log")

        XCTAssertFalse(exportedText.contains("00008030-001234567890ABCD"))
        XCTAssertFalse(exportedText.contains("37.3317"))
        XCTAssertFalse(exportedText.contains("-122.0307"))
        XCTAssertFalse(exportedText.contains("/Users/alice"))
        XCTAssertTrue(exportedText.contains("[REDACTED"))
    }

    private func collectTextFiles(under directory: URL, extension pathExtension: String) throws -> String {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var collected = ""
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == pathExtension else { continue }
            collected += try String(contentsOf: file, encoding: .utf8)
            collected += "\n"
        }
        return collected
    }
}

// MARK: - Logger Integration Tests

final class LoggerIntegrationTests: XCTestCase {

    func testLogWithDeviceUDID() {
        // Should not throw - just verifying the API works
        Logger.debug("Test message", category: .device, deviceUDID: "test-udid-123")
        Logger.info("Test message", category: .device, deviceUDID: "test-udid-123")
        Logger.error("Test message", category: .device, deviceUDID: "test-udid-123")
    }

    func testLogWithMetadata() {
        let metadata = LogMetadata(
            sessionId: "test-session",
            deviceUDID: "test-device",
            operationType: "testOp"
        )

        // Should not throw
        Logger.debug("Test debug", metadata: metadata)
        Logger.info("Test info", metadata: metadata)
        Logger.error("Test error", metadata: metadata)
        Logger.fault("Test fault", metadata: metadata)
    }

    func testPerformanceLogging() {
        // Should not throw
        Logger.performance("testOperation", duration: 0.123)
        Logger.performance("anotherOp", duration: 1.5, category: .device)
    }
}
