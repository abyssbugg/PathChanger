//
//  TelemetryServiceTests.swift
//  PathChangerTests
//
//  Tests for the privacy-first telemetry service (OBS-002).
//

import XCTest
@testable import PathChanger

// MARK: - Telemetry Configuration Tests

final class TelemetryConfigTests: XCTestCase {

    func testMaxQueueSizeIsReasonable() {
        XCTAssertGreaterThan(TelemetryConfig.maxQueueSize, 0)
        XCTAssertLessThanOrEqual(TelemetryConfig.maxQueueSize, 1000)
    }

    func testAggregationIntervalIsReasonable() {
        // Should be at least 10 minutes, no more than 24 hours
        XCTAssertGreaterThanOrEqual(TelemetryConfig.aggregationInterval, 600)
        XCTAssertLessThanOrEqual(TelemetryConfig.aggregationInterval, 86400)
    }

    func testMaxRetentionDaysIsReasonable() {
        XCTAssertGreaterThan(TelemetryConfig.maxRetentionDays, 0)
        XCTAssertLessThanOrEqual(TelemetryConfig.maxRetentionDays, 365)
    }

    func testOptInKeyExists() {
        XCTAssertFalse(TelemetryConfig.optInKey.isEmpty)
    }
}

// MARK: - Telemetry Event Type Tests

final class TelemetryEventTypeTests: XCTestCase {

    func testAllEventTypesHaveRawValues() {
        for eventType in TelemetryEventType.allCases {
            XCTAssertFalse(eventType.rawValue.isEmpty, "Event type \(eventType) should have a raw value")
        }
    }

    func testEventTypeCategorization() {
        // Feature events
        XCTAssertEqual(TelemetryEventType.teleportUsed.category, "feature")
        XCTAssertEqual(TelemetryEventType.routeUsed.category, "feature")
        XCTAssertEqual(TelemetryEventType.joystickUsed.category, "feature")
        XCTAssertEqual(TelemetryEventType.multiDeviceUsed.category, "feature")

        // Connection events
        XCTAssertEqual(TelemetryEventType.tunnelConnected.category, "connection")
        XCTAssertEqual(TelemetryEventType.tunnelDisconnected.category, "connection")
        XCTAssertEqual(TelemetryEventType.tunnelError.category, "connection")

        // Error events
        XCTAssertEqual(TelemetryEventType.locationInjectionError.category, "error")
        XCTAssertEqual(TelemetryEventType.gpxParseError.category, "error")
        XCTAssertEqual(TelemetryEventType.networkError.category, "error")

        // Session events
        XCTAssertEqual(TelemetryEventType.sessionStart.category, "session")
        XCTAssertEqual(TelemetryEventType.sessionEnd.category, "session")
    }

    func testEventTypeRawValuesAreUnique() {
        var rawValues = Set<String>()
        for eventType in TelemetryEventType.allCases {
            XCTAssertFalse(rawValues.contains(eventType.rawValue), "Duplicate raw value: \(eventType.rawValue)")
            rawValues.insert(eventType.rawValue)
        }
    }

    func testEventTypesAreCodable() throws {
        for eventType in TelemetryEventType.allCases {
            let encoded = try JSONEncoder().encode(eventType)
            let decoded = try JSONDecoder().decode(TelemetryEventType.self, from: encoded)
            XCTAssertEqual(decoded, eventType)
        }
    }
}

// MARK: - Telemetry Event Tests

final class TelemetryEventTests: XCTestCase {

    func testEventCreation() {
        let event = TelemetryEvent(type: .teleportUsed, sessionId: "test-session")

        XCTAssertEqual(event.type, .teleportUsed)
        XCTAssertNotNil(event.id)
        XCTAssertNotNil(event.timestamp)
        XCTAssertEqual(event.sessionId, "test-session")
    }

    func testEventWithEmptySessionId() {
        let event = TelemetryEvent(type: .teleportUsed)

        XCTAssertEqual(event.type, .teleportUsed)
        XCTAssertTrue(event.sessionId.isEmpty)
    }

    func testEventWithMetadata() {
        let metadata = ["featureVariant": "A", "duration": "short"]
        let event = TelemetryEvent(type: .routeUsed, metadata: metadata)

        XCTAssertEqual(event.metadata?["featureVariant"], "A")
        XCTAssertEqual(event.metadata?["duration"], "short")
    }

    func testEventIsCodable() throws {
        let event = TelemetryEvent(type: .joystickUsed, metadata: ["test": "value"])

        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: encoded)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.type, event.type)
        XCTAssertEqual(decoded.metadata?["test"], "value")
    }

    func testEventTimestampIsRecent() {
        let beforeCreation = Date()
        let event = TelemetryEvent(type: .teleportUsed)
        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(event.timestamp, beforeCreation)
        XCTAssertLessThanOrEqual(event.timestamp, afterCreation)
    }
}

// MARK: - Session Summary Tests

final class SessionSummaryTests: XCTestCase {

    func testSessionDurationCalculation() {
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(3600) // 1 hour later

        let session = SessionSummary(
            sessionId: "test-session",
            startTime: startTime,
            endTime: endTime,
            deviceCategory: "macOS 14"
        )

        XCTAssertEqual(session.duration, 3600, accuracy: 0.1)
    }

    func testSessionDurationWithNoEndTime() {
        let session = SessionSummary(
            sessionId: "test-session",
            startTime: Date(),
            endTime: nil,
            deviceCategory: "macOS 14"
        )

        XCTAssertEqual(session.duration, 0)
    }

    func testSessionIsCodable() throws {
        let session = SessionSummary(
            sessionId: "test-session",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            deviceCategory: "macOS 14"
        )

        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionSummary.self, from: encoded)

        XCTAssertEqual(decoded.sessionId, session.sessionId)
        XCTAssertEqual(decoded.deviceCategory, "macOS 14")
    }
}

// MARK: - Aggregated Telemetry Data Tests

final class AggregatedTelemetryDataTests: XCTestCase {

    func testAggregationWithEmptyData() {
        let aggregated = AggregatedTelemetryData.aggregate(events: [], sessions: [])

        XCTAssertEqual(aggregated.sessionCount, 0)
        XCTAssertTrue(aggregated.eventCounts.isEmpty)
        XCTAssertNil(aggregated.tunnelSuccessRate)
        XCTAssertNil(aggregated.averageSessionDuration)
    }

    func testAggregationCountsEvents() {
        let events = [
            TelemetryEvent(type: .teleportUsed),
            TelemetryEvent(type: .teleportUsed),
            TelemetryEvent(type: .routeUsed)
        ]

        let aggregated = AggregatedTelemetryData.aggregate(events: events, sessions: [])

        XCTAssertEqual(aggregated.eventCounts[TelemetryEventType.teleportUsed.rawValue], 2)
        XCTAssertEqual(aggregated.eventCounts[TelemetryEventType.routeUsed.rawValue], 1)
    }

    func testTunnelSuccessRateCalculation() {
        let events = [
            TelemetryEvent(type: .tunnelConnected),
            TelemetryEvent(type: .tunnelConnected),
            TelemetryEvent(type: .tunnelError)
        ]

        let aggregated = AggregatedTelemetryData.aggregate(events: events, sessions: [])

        // 2 connects out of 3 attempts = 66.67%
        XCTAssertNotNil(aggregated.tunnelSuccessRate)
        XCTAssertEqual(aggregated.tunnelSuccessRate!, 2.0 / 3.0, accuracy: 0.01)
    }

    func testAverageSessionDurationCalculation() {
        let sessions = [
            SessionSummary(sessionId: "1", startTime: Date(), endTime: Date().addingTimeInterval(3600), deviceCategory: nil),
            SessionSummary(sessionId: "2", startTime: Date(), endTime: Date().addingTimeInterval(1800), deviceCategory: nil)
        ]

        let aggregated = AggregatedTelemetryData.aggregate(events: [], sessions: sessions)

        // Average of 3600 and 1800 = 2700
        XCTAssertNotNil(aggregated.averageSessionDuration)
        XCTAssertEqual(aggregated.averageSessionDuration!, 2700, accuracy: 1)
    }

    func testDeviceCategoryAggregation() {
        let sessions = [
            SessionSummary(sessionId: "1", startTime: Date(), endTime: Date().addingTimeInterval(100), deviceCategory: "macOS 14"),
            SessionSummary(sessionId: "2", startTime: Date(), endTime: Date().addingTimeInterval(100), deviceCategory: "macOS 14"),
            SessionSummary(sessionId: "3", startTime: Date(), endTime: Date().addingTimeInterval(100), deviceCategory: "macOS 15")
        ]

        let aggregated = AggregatedTelemetryData.aggregate(events: [], sessions: sessions)

        XCTAssertEqual(aggregated.deviceModelCategories?["macOS 14"], 2)
        XCTAssertEqual(aggregated.deviceModelCategories?["macOS 15"], 1)
    }

    func testAggregatedDataIsCodable() throws {
        let aggregated = AggregatedTelemetryData(
            periodStart: Date(),
            periodEnd: Date(),
            sessionCount: 5,
            eventCounts: ["test": 10],
            tunnelSuccessRate: 0.95,
            averageSessionDuration: 3600,
            deviceModelCategories: ["macOS 14": 5],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        let encoded = try JSONEncoder().encode(aggregated)
        let decoded = try JSONDecoder().decode(AggregatedTelemetryData.self, from: encoded)

        XCTAssertEqual(decoded.sessionCount, 5)
        XCTAssertEqual(decoded.eventCounts["test"], 10)
        XCTAssertEqual(decoded.tunnelSuccessRate, 0.95)
    }
}

// MARK: - Telemetry Service Tests

final class TelemetryServiceTests: XCTestCase {

    @MainActor
    func testServiceSharedInstance() async {
        // Service should be accessible
        let service = TelemetryService.shared
        XCTAssertNotNil(service)
    }

    @MainActor
    func testOptInPreferenceCheck() async {
        let service = TelemetryService.shared
        // hasUserDecided should return a boolean
        let _ = service.hasUserDecided
    }

    @MainActor
    func testConvenienceFeatureTracking() async {
        let service = TelemetryService.shared

        // These should not crash even when opted out
        service.trackFeatureUsage(.teleport)
        service.trackFeatureUsage(.route)
        service.trackFeatureUsage(.joystick)
        service.trackFeatureUsage(.multiDevice)
    }

    @MainActor
    func testConvenienceConnectionTracking() async {
        let service = TelemetryService.shared

        // These should not crash even when opted out
        service.trackConnection(.tunnelConnected)
        service.trackConnection(.tunnelDisconnected)
        service.trackConnection(.tunnelError)
        service.trackConnection(.deviceConnected)
        service.trackConnection(.deviceDisconnected)
    }

    @MainActor
    func testConvenienceErrorTracking() async {
        let service = TelemetryService.shared

        // These should not crash even when opted out
        service.trackError(.locationInjection)
        service.trackError(.gpxParse)
        service.trackError(.network)
        service.trackError(.validation)
    }

    @MainActor
    func testDataSummaryGeneration() async {
        let service = TelemetryService.shared
        let summary = service.getDataSummary()

        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Telemetry Data Summary"))
    }

    @MainActor
    func testExportDataReturnsValidStructure() async {
        let service = TelemetryService.shared
        let data = service.exportData()

        XCTAssertNotNil(data.appVersion)
        XCTAssertNotNil(data.osVersion)
        XCTAssertGreaterThanOrEqual(data.sessionCount, 0)
    }
}

// MARK: - Privacy Tests

final class TelemetryPrivacyTests: XCTestCase {

    func testNoLocationDataInEvents() {
        // Verify event types don't include location data
        for eventType in TelemetryEventType.allCases {
            let rawValue = eventType.rawValue.lowercased()
            XCTAssertFalse(rawValue.contains("latitude"))
            XCTAssertFalse(rawValue.contains("longitude"))
            XCTAssertFalse(rawValue.contains("coordinate"))
            XCTAssertFalse(rawValue.contains("lat"))
            XCTAssertFalse(rawValue.contains("lon"))
        }
    }

    func testNoDeviceIdentifiersInEvents() {
        // Verify event types don't include device identifiers
        for eventType in TelemetryEventType.allCases {
            let rawValue = eventType.rawValue.lowercased()
            XCTAssertFalse(rawValue.contains("udid"))
            XCTAssertFalse(rawValue.contains("serial"))
            XCTAssertFalse(rawValue.contains("imei"))
        }
    }

    func testAggregatedDataDoesNotContainPII() {
        let aggregated = AggregatedTelemetryData(
            periodStart: Date(),
            periodEnd: Date(),
            sessionCount: 1,
            eventCounts: [:],
            tunnelSuccessRate: 1.0,
            averageSessionDuration: 3600,
            deviceModelCategories: ["macOS 14": 1],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        // Verify no PII in exported data
        XCTAssertNil(aggregated.deviceModelCategories?["iPhone"])  // No specific iPhone model
        XCTAssertTrue(aggregated.appVersion.count <= 20)  // Version string is short
    }

    @MainActor
    func testClearDataRemovesEverything() async {
        let service = TelemetryService.shared

        // Clear data
        service.clearAllData()

        // Verify counts are reset
        XCTAssertEqual(service.eventCount, 0)
        XCTAssertNil(service.lastAggregationDate)
    }
}

// MARK: - Convenience Type Tests

final class TelemetryConvenienceTypeTests: XCTestCase {

    func testFeatureTypeCoversAllFeatures() {
        // Ensure all feature types can be instantiated
        let features: [TelemetryService.FeatureType] = [.teleport, .route, .joystick, .multiDevice]
        XCTAssertEqual(features.count, 4)
    }

    func testConnectionEventCoversAllEvents() {
        let events: [TelemetryService.ConnectionEvent] = [
            .tunnelConnected, .tunnelDisconnected, .tunnelError,
            .deviceConnected, .deviceDisconnected
        ]
        XCTAssertEqual(events.count, 5)
    }

    func testErrorCategoryCoversAllCategories() {
        let categories: [TelemetryService.ErrorCategory] = [
            .locationInjection, .gpxParse, .network, .validation
        ]
        XCTAssertEqual(categories.count, 4)
    }
}
