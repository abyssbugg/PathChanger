//
//  TelemetryService.swift
//  PathChanger
//
//  Privacy-first opt-in telemetry service for anonymous usage analytics (OBS-002).
//

import Foundation
import Combine

// MARK: - Telemetry Configuration

/// Configuration for the telemetry service
enum TelemetryConfig {
    /// Maximum number of events to store before aggregation
    static let maxQueueSize: Int = 100

    /// Interval for local aggregation (seconds)
    static let aggregationInterval: TimeInterval = 3600 // 1 hour

    /// User defaults key for opt-in preference
    static let optInKey = "telemetryOptIn"

    /// User defaults key for last upload timestamp
    static let lastUploadKey = "telemetryLastUpload"

    /// Maximum retention period for local data (days)
    static let maxRetentionDays: Int = 30
}

// MARK: - Telemetry Event Types

/// Types of telemetry events collected
///
/// These events are anonymized and aggregated locally before any
/// potential transmission. No personally identifiable information
/// is collected.
enum TelemetryEventType: String, Codable, CaseIterable {
    // Feature usage
    case teleportUsed = "feature.teleport"
    case routeUsed = "feature.route"
    case joystickUsed = "feature.joystick"
    case multiDeviceUsed = "feature.multi_device"

    // Connection events
    case tunnelConnected = "connection.tunnel_connected"
    case tunnelDisconnected = "connection.tunnel_disconnected"
    case tunnelError = "connection.tunnel_error"
    case deviceConnected = "connection.device_connected"
    case deviceDisconnected = "connection.device_disconnected"

    // Error categories (no details, just counts)
    case locationInjectionError = "error.location_injection"
    case gpxParseError = "error.gpx_parse"
    case networkError = "error.network"
    case validationError = "error.validation"

    // Session events
    case sessionStart = "session.start"
    case sessionEnd = "session.end"

    /// Category for grouping related events
    var category: String {
        rawValue.split(separator: ".").first.map(String.init) ?? "unknown"
    }
}

// MARK: - Telemetry Event

/// A single telemetry event
///
/// Events are stored locally and aggregated before any transmission.
/// No personally identifiable information is stored.
struct TelemetryEvent: Codable, Identifiable {
    let id: UUID
    let type: TelemetryEventType
    let timestamp: Date
    let sessionId: String
    let metadata: [String: String]?

    init(type: TelemetryEventType, sessionId: String = "", metadata: [String: String]? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.sessionId = sessionId
        self.metadata = metadata
    }
}

// MARK: - Aggregated Telemetry Data

/// Aggregated telemetry data for a time period
///
/// This is the format used for local storage and potential transmission.
/// All data is anonymous and aggregated at the event type level.
struct AggregatedTelemetryData: Codable {
    let periodStart: Date
    let periodEnd: Date
    let sessionCount: Int
    let eventCounts: [String: Int]
    let tunnelSuccessRate: Double?
    let averageSessionDuration: TimeInterval?
    let deviceModelCategories: [String: Int]?
    let appVersion: String
    let osVersion: String

    /// Create aggregated data from raw events
    static func aggregate(events: [TelemetryEvent], sessions: [SessionSummary]) -> AggregatedTelemetryData {
        let now = Date()
        let periodStart = events.map(\.timestamp).min() ?? now

        // Count events by type
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.type.rawValue, default: 0] += 1
        }

        // Calculate tunnel success rate
        let tunnelConnects = counts[TelemetryEventType.tunnelConnected.rawValue] ?? 0
        let tunnelErrors = counts[TelemetryEventType.tunnelError.rawValue] ?? 0
        let totalTunnelAttempts = tunnelConnects + tunnelErrors
        let tunnelSuccessRate: Double? = totalTunnelAttempts > 0 ?
            Double(tunnelConnects) / Double(totalTunnelAttempts) : nil

        // Calculate average session duration
        let totalDuration = sessions.reduce(0) { $0 + $1.duration }
        let avgDuration: TimeInterval? = sessions.isEmpty ? nil : totalDuration / Double(sessions.count)

        // Aggregate device model categories (e.g., "iPhone 14 series", not specific model)
        var modelCategories: [String: Int] = [:]
        for session in sessions {
            if let category = session.deviceCategory {
                modelCategories[category, default: 0] += 1
            }
        }

        return AggregatedTelemetryData(
            periodStart: periodStart,
            periodEnd: now,
            sessionCount: sessions.count,
            eventCounts: counts,
            tunnelSuccessRate: tunnelSuccessRate,
            averageSessionDuration: avgDuration,
            deviceModelCategories: modelCategories.isEmpty ? nil : modelCategories,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

// MARK: - Session Summary

/// Summary of a telemetry session (no PII)
struct SessionSummary: Codable {
    let sessionId: String
    let startTime: Date
    let endTime: Date?
    let deviceCategory: String?

    var duration: TimeInterval {
        guard let endTime = endTime else { return 0 }
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Telemetry Service

/// Privacy-first telemetry service for anonymous usage analytics
///
/// ## Privacy Principles
///
/// This service follows strict privacy principles:
///
/// 1. **Explicit Opt-In Required**: Users must explicitly enable telemetry
/// 2. **No Device Identifiers**: No UDID, IMEI, or any device-specific identifiers
/// 3. **No Location Data**: Location coordinates are never collected
/// 4. **Local Aggregation**: Data is aggregated locally before any transmission
/// 5. **Minimal Data**: Only essential usage patterns are collected
/// 6. **User Control**: Users can disable telemetry at any time and clear all data
///
/// ## Collected Data
///
/// - Feature usage counts (teleport, route, joystick)
/// - Connection success/failure rates
/// - Error category counts (no error details)
/// - Session duration averages
/// - Device model category (e.g., "iPhone 14 series", not specific model)
///
/// ## Not Collected
///
/// - Device identifiers (UDID, serial number)
/// - Location coordinates
/// - IP addresses
/// - User account information
/// - Specific error messages or details
@MainActor
class TelemetryService: ObservableObject {

    // MARK: Singleton

    static let shared = TelemetryService()

    // MARK: Published Properties

    @Published private(set) var isOptedIn: Bool = false
    @Published private(set) var eventCount: Int = 0
    @Published private(set) var lastAggregationDate: Date?

    // MARK: Private Properties

    private var events: [TelemetryEvent] = []
    private var sessions: [SessionSummary] = []
    private var currentSession: SessionSummary?
    private(set) var currentSessionId: String = UUID().uuidString
    private var aggregationTimer: Timer?

    private let storageURL: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let telemetryDir = appSupport.appendingPathComponent("PathChanger/Telemetry", isDirectory: true)
        try? FileManager.default.createDirectory(at: telemetryDir, withIntermediateDirectories: true)
        return telemetryDir
    }()

    // MARK: Lifecycle

    private init() {
        loadOptInPreference()
        loadPersistedData()

        if isOptedIn {
            startSession()
            startAggregationTimer()
        }
    }

    // MARK: Opt-In Management

    /// Set the user's opt-in preference for telemetry
    /// - Parameter enabled: Whether telemetry should be enabled
    func setOptIn(_ enabled: Bool) {
        let previousState = isOptedIn
        isOptedIn = enabled
        UserDefaults.standard.set(enabled, forKey: TelemetryConfig.optInKey)

        if enabled && !previousState {
            // Just opted in - start collecting
            startSession()
            startAggregationTimer()
            Logger.info("Telemetry opted in", category: .general)
        } else if !enabled && previousState {
            // Just opted out - stop and clear
            stopSession()
            stopAggregationTimer()
            clearAllData()
            Logger.info("Telemetry opted out and data cleared", category: .general)
        }
    }

    /// Check if user has made a preference decision
    var hasUserDecided: Bool {
        UserDefaults.standard.object(forKey: TelemetryConfig.optInKey) != nil
    }

    // MARK: Event Tracking

    /// Track a telemetry event
    /// - Parameters:
    ///   - eventType: The type of event to track
    ///   - metadata: Optional anonymous metadata (no PII)
    func track(_ eventType: TelemetryEventType, metadata: [String: String]? = nil) {
        guard isOptedIn else { return }

        // Filter metadata to ensure no PII
        let safeMetadata = metadata?.filter { key, _ in
            !isPotentialPII(key: key)
        }

        let event = TelemetryEvent(type: eventType, sessionId: currentSessionId, metadata: safeMetadata)
        events.append(event)
        eventCount = events.count

        // Aggregate if queue is full
        if events.count >= TelemetryConfig.maxQueueSize {
            aggregateAndPersist()
        }

        Logger.debug("Telemetry event tracked: \(eventType.rawValue)", category: .general)
    }

    /// Check if a metadata key might contain PII
    private func isPotentialPII(key: String) -> Bool {
        let piiKeywords = ["udid", "id", "name", "email", "phone", "address", "ip", "location", "coordinate", "lat", "lon", "serial"]
        let lowerKey = key.lowercased()
        return piiKeywords.contains { lowerKey.contains($0) }
    }

    // MARK: Session Management

    /// Start a new telemetry session
    func startSession() {
        guard isOptedIn else { return }

        currentSessionId = UUID().uuidString
        currentSession = SessionSummary(
            sessionId: currentSessionId,
            startTime: Date(),
            endTime: nil,
            deviceCategory: getDeviceCategory()
        )

        track(.sessionStart)
    }

    /// End the current telemetry session
    func stopSession() {
        guard isOptedIn, var session = currentSession else { return }

        track(.sessionEnd)

        session = SessionSummary(
            sessionId: session.sessionId,
            startTime: session.startTime,
            endTime: Date(),
            deviceCategory: session.deviceCategory
        )
        sessions.append(session)
        currentSession = nil
    }

    /// Get anonymized device category (e.g., "macOS 14")
    private func getDeviceCategory() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion)"
    }

    // MARK: Data Management

    /// Clear all telemetry data
    func clearAllData() {
        events.removeAll()
        sessions.removeAll()
        eventCount = 0
        lastAggregationDate = nil
        currentSession = nil

        // Clear persisted data
        if let storageURL = storageURL {
            try? FileManager.default.removeItem(at: storageURL)
            try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }

        UserDefaults.standard.removeObject(forKey: TelemetryConfig.lastUploadKey)

        Logger.info("All telemetry data cleared", category: .general)
    }

    /// Export aggregated telemetry data for user review
    func exportData() -> AggregatedTelemetryData {
        AggregatedTelemetryData.aggregate(events: events, sessions: sessions)
    }

    /// Get human-readable summary of collected data
    func getDataSummary() -> String {
        let data = exportData()
        var summary = "Telemetry Data Summary\n"
        summary += "=====================\n\n"
        summary += "Period: \(formatDate(data.periodStart)) to \(formatDate(data.periodEnd))\n"
        summary += "Sessions: \(data.sessionCount)\n"
        summary += "Events: \(eventCount)\n\n"

        summary += "Feature Usage:\n"
        for type in TelemetryEventType.allCases where type.category == "feature" {
            let count = data.eventCounts[type.rawValue] ?? 0
            summary += "  - \(type.rawValue.replacingOccurrences(of: "feature.", with: "")): \(count)\n"
        }

        summary += "\nConnection Stats:\n"
        if let successRate = data.tunnelSuccessRate {
            summary += "  - Tunnel success rate: \(Int(successRate * 100))%\n"
        }

        summary += "\nError Counts:\n"
        for type in TelemetryEventType.allCases where type.category == "error" {
            let count = data.eventCounts[type.rawValue] ?? 0
            if count > 0 {
                summary += "  - \(type.rawValue.replacingOccurrences(of: "error.", with: "")): \(count)\n"
            }
        }

        return summary
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Persistence

    private func loadOptInPreference() {
        isOptedIn = UserDefaults.standard.bool(forKey: TelemetryConfig.optInKey)
    }

    private func loadPersistedData() {
        guard let storageURL = storageURL else { return }

        let eventsURL = storageURL.appendingPathComponent("events.json")
        let sessionsURL = storageURL.appendingPathComponent("sessions.json")

        if let eventsData = try? Data(contentsOf: eventsURL),
           let loadedEvents = try? JSONDecoder().decode([TelemetryEvent].self, from: eventsData) {
            events = loadedEvents
            eventCount = events.count
        }

        if let sessionsData = try? Data(contentsOf: sessionsURL),
           let loadedSessions = try? JSONDecoder().decode([SessionSummary].self, from: sessionsData) {
            sessions = loadedSessions
        }
    }

    private func persistData() {
        guard let storageURL = storageURL else { return }

        let eventsURL = storageURL.appendingPathComponent("events.json")
        let sessionsURL = storageURL.appendingPathComponent("sessions.json")

        if let eventsData = try? JSONEncoder().encode(events) {
            try? eventsData.write(to: eventsURL)
        }

        if let sessionsData = try? JSONEncoder().encode(sessions) {
            try? sessionsData.write(to: sessionsURL)
        }
    }

    // MARK: Aggregation

    private func startAggregationTimer() {
        stopAggregationTimer()

        aggregationTimer = Timer.scheduledTimer(
            withTimeInterval: TelemetryConfig.aggregationInterval,
            repeats: true
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.aggregateAndPersist()
            }
        }
    }

    private func stopAggregationTimer() {
        aggregationTimer?.invalidate()
        aggregationTimer = nil
    }

    private func aggregateAndPersist() {
        guard !events.isEmpty else { return }

        // Create aggregated data
        let aggregated = AggregatedTelemetryData.aggregate(events: events, sessions: sessions)

        // Persist aggregated data
        if let storageURL = storageURL {
            let aggregatedURL = storageURL.appendingPathComponent("aggregated_\(ISO8601DateFormatter().string(from: Date())).json")
            if let data = try? JSONEncoder().encode(aggregated) {
                try? data.write(to: aggregatedURL)
            }
        }

        // Clear raw events (keeping aggregated data)
        events.removeAll()
        eventCount = 0
        lastAggregationDate = Date()

        // Persist remaining data
        persistData()

        // Cleanup old aggregated files
        cleanupOldData()

        Logger.debug("Telemetry data aggregated", category: .general)
    }

    private func cleanupOldData() {
        guard let storageURL = storageURL else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -TelemetryConfig.maxRetentionDays, to: Date()) ?? Date()

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        for file in files {
            guard file.lastPathComponent.hasPrefix("aggregated_") else { continue }

            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

// MARK: - Telemetry Convenience Extensions

extension TelemetryService {
    /// Track feature usage
    func trackFeatureUsage(_ feature: FeatureType) {
        switch feature {
        case .teleport:
            track(.teleportUsed)
        case .route:
            track(.routeUsed)
        case .joystick:
            track(.joystickUsed)
        case .multiDevice:
            track(.multiDeviceUsed)
        }
    }

    /// Track connection event
    func trackConnection(_ event: ConnectionEvent) {
        switch event {
        case .tunnelConnected:
            track(.tunnelConnected)
        case .tunnelDisconnected:
            track(.tunnelDisconnected)
        case .tunnelError:
            track(.tunnelError)
        case .deviceConnected:
            track(.deviceConnected)
        case .deviceDisconnected:
            track(.deviceDisconnected)
        }
    }

    /// Track error category
    func trackError(_ category: ErrorCategory) {
        switch category {
        case .locationInjection:
            track(.locationInjectionError)
        case .gpxParse:
            track(.gpxParseError)
        case .network:
            track(.networkError)
        case .validation:
            track(.validationError)
        }
    }

    /// Feature types for convenience tracking
    enum FeatureType {
        case teleport
        case route
        case joystick
        case multiDevice
    }

    /// Connection events for convenience tracking
    enum ConnectionEvent {
        case tunnelConnected
        case tunnelDisconnected
        case tunnelError
        case deviceConnected
        case deviceDisconnected
    }

    /// Error categories for convenience tracking
    enum ErrorCategory {
        case locationInjection
        case gpxParse
        case network
        case validation
    }
}
