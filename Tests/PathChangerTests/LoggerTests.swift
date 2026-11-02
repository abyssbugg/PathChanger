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

// MARK: - Repeat Suppression Tests

final class LogRepeatSuppressorTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testARepeatedFailureAtTheUpdateRateWritesOneLinePerWindow() {
        // Review 2026-11-01: a joystick failure loop wrote error lines at 10 Hz.
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start), ["[Apply] Failed: E"])
        for tick in 1...30 {
            XCTAssertEqual(
                suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start + Double(tick) * 0.1),
                [],
                "tick \(tick)"
            )
        }
        // The window passed: one line with the count of the suppressed repeats.
        XCTAssertEqual(
            suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start + 5.1),
            ["[Apply] Failed: E (repeated 30 times)"]
        )
        XCTAssertEqual(suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start + 5.2), [])
    }

    func testAChangedMessageFlushesTheCountAndPassesAtOnce() {
        var suppressor = LogRepeatSuppressor(window: 5)
        _ = suppressor.lines(for: "A", key: "k", now: start)
        _ = suppressor.lines(for: "A", key: "k", now: start + 0.1)
        _ = suppressor.lines(for: "A", key: "k", now: start + 0.2)
        XCTAssertEqual(
            suppressor.lines(for: "B", key: "k", now: start + 0.3),
            ["A (repeated 2 times)", "B"]
        )
        // Nothing was suppressed for B yet: a change back passes without a summary.
        XCTAssertEqual(suppressor.lines(for: "A", key: "k", now: start + 0.4), ["A"])
    }

    func testTheSameMessageAfterTheWindowWithoutRepeatsHasNoCount() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "A", key: "k", now: start), ["A"])
        XCTAssertEqual(suppressor.lines(for: "A", key: "k", now: start + 6), ["A"])
    }

    func testKeysAreIndependent() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "A", key: "bridge", now: start), ["A"])
        XCTAssertEqual(suppressor.lines(for: "A", key: "app", now: start + 0.1), ["A"])
        XCTAssertEqual(suppressor.lines(for: "A", key: "bridge", now: start + 0.2), [])
    }

    func testEndingAKeyFlushesTheSuppressedCount() {
        // Review 2026-11-01 issue 2: when a failure run stopped, its last count was
        // never written.
        var suppressor = LogRepeatSuppressor(window: 5)
        _ = suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start)
        for tick in 1...7 {
            _ = suppressor.lines(for: "[Apply] Failed: E", key: "apply", now: start + Double(tick) * 0.1)
        }
        XCTAssertEqual(suppressor.end(key: "apply"), ["[Apply] Failed: E (repeated 7 times)"])
        // Ended: a second end has nothing left to write.
        XCTAssertEqual(suppressor.end(key: "apply"), [])
    }

    func testAnIdenticalFailureInsideTheWindowAfterEndIsCountedAndFlushedByTheNextEnd() {
        // Review 2026-11-01-192235 issue 3: end(key:) forgot the entry, so a flapping
        // link (failure, success, failure) wrote every failure line. End keeps the window
        // anchor: the same failure inside the window is counted, not written.
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start), ["E"])
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 0.2), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 0.3), [])
        XCTAssertEqual(suppressor.end(key: "apply"), ["E (repeated 2 times)"])
        // The count was reset; the anchor was not.
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 0.4), [])
        XCTAssertEqual(suppressor.end(key: "apply"), ["E (repeated 1 times)"])
    }

    func testAFailureAfterTheWindowAfterEndPassesAtOnce() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start), ["E"])
        _ = suppressor.lines(for: "E", key: "apply", now: start + 0.1)
        XCTAssertEqual(suppressor.end(key: "apply"), ["E (repeated 1 times)"])
        // Nothing pending and the window passed: the failure is written with no count.
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 5.1), ["E"])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 5.2), [])
    }

    func testAFailureCountedAfterEndIsFlushedByTheFirstIdenticalLineAfterTheWindow() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start), ["E"])
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 1), [])
        XCTAssertEqual(
            suppressor.lines(for: "E", key: "apply", now: start + 5.5),
            ["E (repeated 1 times)"]
        )
        XCTAssertEqual(suppressor.end(key: "apply"), [])
    }

    func testAFailureCountedAfterEndIsFlushedByAChangedMessage() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start), ["E"])
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start + 0.1), [])
        XCTAssertEqual(
            suppressor.lines(for: "F", key: "apply", now: start + 0.2),
            ["E (repeated 1 times)", "F"]
        )
        XCTAssertEqual(suppressor.end(key: "apply"), [])
    }

    func testAFlappingLinkWritesOneFailureLineAndLosesNoCount() {
        // Fail, end, fail, end, fail inside 5 s: one written failure line, and the
        // summaries account for every suppressed failure.
        var suppressor = LogRepeatSuppressor(window: 5)
        var written: [String] = []
        written += suppressor.lines(for: "E", key: "apply", now: start)
        written += suppressor.end(key: "apply")
        written += suppressor.lines(for: "E", key: "apply", now: start + 0.1)
        written += suppressor.end(key: "apply")
        written += suppressor.lines(for: "E", key: "apply", now: start + 0.2)
        written += suppressor.end(key: "apply")
        XCTAssertEqual(written, ["E", "E (repeated 1 times)", "E (repeated 1 times)"])

        // The joystick's 10 Hz: 48 fail/success pairs, all inside one window.
        var flapping = LogRepeatSuppressor(window: 5)
        var lines: [String] = []
        let failures = 48
        for tick in 0..<failures {
            lines += flapping.lines(for: "E", key: "apply", now: start + Double(tick) * 0.1)
            lines += flapping.end(key: "apply")
        }
        XCTAssertEqual(lines.filter { $0 == "E" }.count, 1, "one written failure line")
        let summarized = lines.filter { $0 != "E" }.map(Self.repeatCount)
        XCTAssertFalse(summarized.contains(nil), "every other line is a summary: \(lines)")
        XCTAssertEqual(summarized.compactMap { $0 }.reduce(0, +), failures - 1, "no count lost")
    }

    private static func repeatCount(_ line: String) -> Int? {
        guard line.hasPrefix("E (repeated "), line.hasSuffix(" times)") else { return nil }
        return Int(line.dropFirst("E (repeated ".count).dropLast(" times)".count))
    }

    func testEndWithoutSuppressedLinesWritesNothing() {
        var suppressor = LogRepeatSuppressor(window: 5)
        XCTAssertEqual(suppressor.end(key: "never-seen"), [])
        XCTAssertEqual(suppressor.lines(for: "E", key: "apply", now: start), ["E"])
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        // Ending one key leaves another's count alone.
        _ = suppressor.lines(for: "F", key: "other", now: start)
        _ = suppressor.lines(for: "F", key: "other", now: start + 0.1)
        XCTAssertEqual(suppressor.end(key: "apply"), [])
        XCTAssertEqual(suppressor.end(key: "other"), ["F (repeated 1 times)"])
    }

    func testTheSharedSuppressorEndsAKeyAtTheLevelItsLinesWereWrittenAt() {
        let shared = SharedLogRepeatSuppressor()
        XCTAssertEqual(shared.lines(for: "Q", key: "queued", level: .info), ["Q"])
        XCTAssertEqual(shared.lines(for: "Q", key: "queued", level: .info), [])
        let ended = shared.end(key: "queued")
        XCTAssertEqual(ended.lines, ["Q (repeated 1 times)"])
        XCTAssertEqual(ended.level, .info)

        XCTAssertEqual(shared.lines(for: "F", key: "failed"), ["F"])
        XCTAssertEqual(shared.lines(for: "F", key: "failed"), [])
        XCTAssertEqual(shared.end(key: "failed").level, .error)
        // Nothing pending: no lines and no level.
        let none = shared.end(key: "failed")
        XCTAssertEqual(none.lines, [])
        XCTAssertNil(none.level)

        // Counted after an end (window anchor kept): the summary keeps the level.
        XCTAssertEqual(shared.lines(for: "Q", key: "queued", level: .info), [])
        let again = shared.end(key: "queued")
        XCTAssertEqual(again.lines, ["Q (repeated 1 times)"])
        XCTAssertEqual(again.level, .info)
    }
}

// MARK: - Redaction Tests

final class LogRedactionTests: XCTestCase {
    func testUDIDShapedTokensKeepOnlyTheirFirstEightCharacters() {
        // Review 2026-11-01: provider errors can carry the full device UDID.
        XCTAssertEqual(
            LogRedaction.redactingDeviceIdentifiers("Device 00008130-000C5144019A001C not found"),
            "Device 00008130… not found"
        )
        XCTAssertEqual(
            LogRedaction.redactingDeviceIdentifiers(
                "udid=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678, again 00008130-000C5144019A001C."
            ),
            "udid=a1b2c3d4…, again 00008130…."
        )
    }

    func testOtherIdentifiersAndTextAreUnchanged() {
        let text = "request 251B5D4D-9580-4091-B8E5-026E9344EB3F generation=4 port 49151 deadbeef"
        XCTAssertEqual(LogRedaction.redactingDeviceIdentifiers(text), text)
        XCTAssertEqual(LogRedaction.redactingDeviceIdentifiers(""), "")
    }
}
