//
//  ReliabilityManager.swift
//  PathChanger
//
//  Reliability features: auto-reconnection, session persistence, error handling
//

import Foundation
import Combine

// MARK: - Reconnection Strategy

/// Strategy for automatic reconnection with exponential backoff and jitter (REL-001)
struct ReconnectionStrategy {
    var maxAttempts: Int
    var initialDelaySeconds: Double
    var maxDelaySeconds: Double
    var backoffMultiplier: Double
    /// Jitter factor (0.0 - 1.0) to randomize delay and prevent thundering herd
    var jitterFactor: Double

    static let `default` = ReconnectionStrategy(
        maxAttempts: 5,
        initialDelaySeconds: 1.0,
        maxDelaySeconds: 30.0,
        backoffMultiplier: 2.0,
        jitterFactor: 0.25
    )

    static let aggressive = ReconnectionStrategy(
        maxAttempts: 10,
        initialDelaySeconds: 0.5,
        maxDelaySeconds: 60.0,
        backoffMultiplier: 1.5,
        jitterFactor: 0.2
    )

    static let conservative = ReconnectionStrategy(
        maxAttempts: 3,
        initialDelaySeconds: 2.0,
        maxDelaySeconds: 15.0,
        backoffMultiplier: 2.0,
        jitterFactor: 0.3
    )

    /// Calculate delay with exponential backoff and jitter (REL-001)
    func delayForAttempt(_ attempt: Int) -> Double {
        let baseDelay = initialDelaySeconds * pow(backoffMultiplier, Double(attempt - 1))
        let cappedDelay = min(baseDelay, maxDelaySeconds)

        // Apply jitter: delay * (1 ± jitterFactor)
        let jitterRange = cappedDelay * jitterFactor
        let jitter = Double.random(in: -jitterRange...jitterRange)

        return max(0.1, cappedDelay + jitter)
    }
}

// MARK: - Circuit Breaker (REL-001)

/// Circuit breaker pattern to prevent cascading failures
actor CircuitBreaker {
    enum State: Equatable {
        case closed      // Normal operation
        case open        // Failing, reject requests
        case halfOpen    // Testing if service recovered
    }

    struct Config {
        let failureThreshold: Int      // Failures before opening
        let successThreshold: Int      // Successes in half-open to close
        let resetTimeout: TimeInterval // Time before trying half-open
        let monitoringWindow: TimeInterval // Window for failure counting

        static let `default` = Config(
            failureThreshold: 5,
            successThreshold: 2,
            resetTimeout: 30.0,
            monitoringWindow: 60.0
        )
    }

    private(set) var state: State = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?
    private var lastStateChange: Date = Date()
    private var failureTimestamps: [Date] = []
    private let config: Config

    init(config: Config = .default) {
        self.config = config
    }

    /// Check if request should be allowed
    func shouldAllowRequest() -> Bool {
        cleanupOldFailures()

        switch state {
        case .closed:
            return true
        case .open:
            // Check if reset timeout has passed
            if Date().timeIntervalSince(lastStateChange) >= config.resetTimeout {
                transitionTo(.halfOpen)
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    /// Record a successful operation
    func recordSuccess() {
        switch state {
        case .closed:
            // Reset failure count on success
            failureCount = 0
        case .halfOpen:
            successCount += 1
            if successCount >= config.successThreshold {
                transitionTo(.closed)
            }
        case .open:
            break // Shouldn't happen
        }
    }

    /// Record a failed operation
    func recordFailure() {
        let now = Date()
        failureTimestamps.append(now)
        lastFailureTime = now

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= config.failureThreshold {
                transitionTo(.open)
            }
        case .halfOpen:
            // Any failure in half-open goes back to open
            transitionTo(.open)
        case .open:
            break // Already open
        }
    }

    /// Get circuit breaker statistics
    func getStats() -> CircuitBreakerStats {
        cleanupOldFailures()
        return CircuitBreakerStats(
            state: state,
            failureCount: failureCount,
            successCount: successCount,
            recentFailures: failureTimestamps.count,
            lastFailureTime: lastFailureTime,
            lastStateChange: lastStateChange
        )
    }

    /// Force reset the circuit breaker
    func reset() {
        transitionTo(.closed)
        failureCount = 0
        successCount = 0
        failureTimestamps.removeAll()
        lastFailureTime = nil
    }

    private func transitionTo(_ newState: State) {
        guard state != newState else { return }
        state = newState
        lastStateChange = Date()
        failureCount = 0
        successCount = 0
        Logger.info("Circuit breaker transitioned to \(newState)", category: .session)
    }

    private func cleanupOldFailures() {
        let cutoff = Date().addingTimeInterval(-config.monitoringWindow)
        failureTimestamps.removeAll { $0 < cutoff }
    }
}

struct CircuitBreakerStats {
    let state: CircuitBreaker.State
    let failureCount: Int
    let successCount: Int
    let recentFailures: Int
    let lastFailureTime: Date?
    let lastStateChange: Date
}

// MARK: - Error Classification (REL-001)

/// Enhanced error classification for better recovery decisions
enum ErrorClassification {
    case transient      // Temporary, safe to retry immediately
    case retryable      // Likely to succeed with delay
    case persistent     // Unlikely to recover without intervention
    case fatal          // Cannot recover automatically

    var shouldRetry: Bool {
        switch self {
        case .transient, .retryable: return true
        case .persistent, .fatal: return false
        }
    }

    var suggestedDelay: TimeInterval {
        switch self {
        case .transient: return 0.5
        case .retryable: return 2.0
        case .persistent: return 10.0
        case .fatal: return 0
        }
    }
}

/// Classifies errors for appropriate recovery strategies
struct ErrorClassifier {
    /// Classify an error to determine recovery strategy
    static func classify(_ error: Error) -> ErrorClassification {
        // Device errors
        if let deviceError = error as? DeviceError {
            switch deviceError {
            case .timeout:
                return .transient
            case .connectionFailed:
                return .retryable
            case .deviceNotFound, .tunneldNotRunning:
                return .persistent
            case .developerModeDisabled, .pairingRequired, .trustRequired:
                return .fatal
            case .commandFailed:
                return .retryable
            }
        }

        // Location injection errors
        if let injectionError = error as? LocationInjectionError {
            switch injectionError {
            case .timeout:
                return .transient
            case .injectionFailed, .clearFailed:
                return .retryable
            case .deviceNotFound, .tunneldNotRunning:
                return .persistent
            case .developerModeRequired:
                return .fatal
            case .unsupportedIOSVersion:
                return .retryable
            case .invalidCoordinates, .rateLimited, .outputSizeExceeded:
                return .retryable
            }
        }

        // Network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost:
                return .transient
            case .notConnectedToInternet, .cannotFindHost:
                return .persistent
            default:
                return .retryable
            }
        }

        // Default classification
        return .retryable
    }
}

// MARK: - Connection Recovery State

enum ConnectionRecoveryState: Equatable {
    case connected
    case disconnected
    case reconnecting(attempt: Int, maxAttempts: Int)
    case failed(reason: String)
    case suspended

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Not connected"
        case .reconnecting(let attempt, let max): return "Reconnecting… (\(attempt)/\(max))"
        case .failed(let reason): return "Couldn’t reconnect: \(reason)"
        case .suspended: return "Suspended"
        }
    }
}

// MARK: - Reliability Manager

/// Manages connection reliability, auto-reconnection, and session persistence
@MainActor
class ReliabilityManager: ObservableObject {
    // MARK: Published State
    @Published var recoveryState: ConnectionRecoveryState = .disconnected
    @Published var lastConnectionTime: Date?
    @Published var connectionUptime: TimeInterval = 0
    @Published var reconnectionAttempts: Int = 0
    @Published var isAutoReconnectEnabled: Bool = true
    @Published var circuitBreakerOpen: Bool = false
    @Published var persistentFailureDetected: Bool = false

    // MARK: Configuration
    var strategy: ReconnectionStrategy = .default

    // MARK: Circuit Breaker (REL-001)
    let circuitBreaker = CircuitBreaker()

    // MARK: Failure Tracking (REL-001)
    private var consecutiveFailures: Int = 0
    private var failureHistory: [Date] = []
    private let persistentFailureThreshold = 10
    private let failureHistoryWindow: TimeInterval = 300 // 5 minutes

    // MARK: Callbacks
    var onReconnect: (() async throws -> Bool)?
    var onConnectionLost: (() -> Void)?
    var onReconnectionFailed: ((String) -> Void)?
    var onPersistentFailure: ((String) -> Void)?

    // MARK: Private
    private var reconnectionTask: Task<Void, Never>?
    private var uptimeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Initialization

    init() {
        startUptimeTracking()
    }

    deinit {
        uptimeTimer?.invalidate()
    }

    // MARK: Connection Events

    func connectionEstablished() {
        recoveryState = .connected
        lastConnectionTime = Date()
        reconnectionAttempts = 0
        consecutiveFailures = 0
        persistentFailureDetected = false
        reconnectionTask?.cancel()
        reconnectionTask = nil
    }

    func connectionLost() {
        guard recoveryState == .connected else { return }

        recoveryState = .disconnected
        onConnectionLost?()

        if isAutoReconnectEnabled {
            startReconnection()
        }
    }

    func suspend() {
        reconnectionTask?.cancel()
        reconnectionTask = nil
        recoveryState = .suspended
    }

    func resume() {
        if recoveryState == .suspended {
            recoveryState = .disconnected
            if isAutoReconnectEnabled {
                startReconnection()
            }
        }
    }

    // MARK: Reconnection

    func startReconnection() {
        guard reconnectionTask == nil else { return }

        reconnectionTask = Task {
            var attempt = 0

            while attempt < strategy.maxAttempts && !Task.isCancelled {
                // Check circuit breaker (REL-001)
                let shouldAllow = await circuitBreaker.shouldAllowRequest()
                if !shouldAllow {
                    await MainActor.run { circuitBreakerOpen = true }
                    Logger.info("Circuit breaker is open, waiting for reset", category: .session)
                    try? await Task.sleep(nanoseconds: UInt64(CircuitBreaker.Config.default.resetTimeout * 1_000_000_000))
                    continue
                }
                await MainActor.run { circuitBreakerOpen = false }

                attempt += 1
                reconnectionAttempts = attempt
                recoveryState = .reconnecting(attempt: attempt, maxAttempts: strategy.maxAttempts)

                do {
                    if let reconnect = onReconnect {
                        if try await reconnect() {
                            // Record success with circuit breaker
                            await circuitBreaker.recordSuccess()
                            connectionEstablished()
                            return
                        }
                    }
                    // Reconnect returned false
                    await recordFailure(nil)
                } catch {
                    // Reconnection attempt failed
                    await recordFailure(error)
                }

                // Wait before next attempt with jitter (REL-001)
                let delay = strategy.delayForAttempt(attempt)
                Logger.debug("Reconnection delay: \(String(format: "%.2f", delay))s (attempt \(attempt))", category: .session)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            // All attempts failed
            if !Task.isCancelled {
                recoveryState = .failed(reason: "Max reconnection attempts reached")
                onReconnectionFailed?("Failed to reconnect after \(strategy.maxAttempts) attempts")
                checkPersistentFailure()
            }
        }
    }

    /// Record a failure and update tracking (REL-001)
    private func recordFailure(_ error: Error?) async {
        consecutiveFailures += 1
        failureHistory.append(Date())
        await circuitBreaker.recordFailure()

        // Clean up old failures
        let cutoff = Date().addingTimeInterval(-failureHistoryWindow)
        failureHistory.removeAll { $0 < cutoff }

        // Log error classification if available
        if let error = error {
            let classification = ErrorClassifier.classify(error)
            Logger.debug("Error classified as \(classification): \(error.localizedDescription)", category: .session)
        }
    }

    /// Check for persistent failure pattern (REL-001)
    private func checkPersistentFailure() {
        if failureHistory.count >= persistentFailureThreshold && !persistentFailureDetected {
            persistentFailureDetected = true
            let message = "Connection has failed \(failureHistory.count) times in the last \(Int(failureHistoryWindow / 60)) minutes"
            Logger.error("Persistent failure detected: \(message)", category: .session)
            onPersistentFailure?(message)
        }
    }

    func cancelReconnection() {
        reconnectionTask?.cancel()
        reconnectionTask = nil
        recoveryState = .disconnected
    }

    func retryNow() {
        cancelReconnection()
        reconnectionAttempts = 0
        consecutiveFailures = 0
        startReconnection()
    }

    /// Reset circuit breaker and failure tracking (REL-001)
    func resetReliabilityState() async {
        await circuitBreaker.reset()
        consecutiveFailures = 0
        failureHistory.removeAll()
        persistentFailureDetected = false
        circuitBreakerOpen = false
    }

    /// Get reliability statistics (REL-001)
    func getReliabilityStats() async -> ReliabilityStats {
        let cbStats = await circuitBreaker.getStats()
        return ReliabilityStats(
            circuitBreakerState: cbStats.state,
            consecutiveFailures: consecutiveFailures,
            failuresInWindow: failureHistory.count,
            persistentFailureDetected: persistentFailureDetected,
            connectionUptime: connectionUptime,
            reconnectionAttempts: reconnectionAttempts
        )
    }

    // MARK: Uptime Tracking

    private func startUptimeTracking() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.recoveryState == .connected,
                      let lastTime = self.lastConnectionTime else { return }
                self.connectionUptime = Date().timeIntervalSince(lastTime)
            }
        }
    }
}

// MARK: - Reliability Statistics (REL-001)

struct ReliabilityStats {
    let circuitBreakerState: CircuitBreaker.State
    let consecutiveFailures: Int
    let failuresInWindow: Int
    let persistentFailureDetected: Bool
    let connectionUptime: TimeInterval
    let reconnectionAttempts: Int

    var summary: String {
        """
        Reliability Stats:
        - Circuit Breaker: \(circuitBreakerState)
        - Consecutive Failures: \(consecutiveFailures)
        - Failures (5 min window): \(failuresInWindow)
        - Persistent Failure: \(persistentFailureDetected)
        - Connection Uptime: \(String(format: "%.1f", connectionUptime))s
        - Reconnection Attempts: \(reconnectionAttempts)
        """
    }
}

// MARK: - Session Persistence

/// Persists session state for app restart recovery
class SessionPersistence {
    private let userDefaults: UserDefaults
    private let sessionKey = "PathChanger.lastSession"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: Persisted Session

    struct PersistedSession: Codable {
        var deviceId: String
        var deviceName: String
        var lastLocation: LocationCoordinate?
        var simulationMode: String
        var timestamp: Date
        var routeCoordinates: [LocationCoordinate]?
        var routeProgress: Double?
    }

    // MARK: Save/Load

    func saveSession(_ session: PersistedSession) {
        do {
            let data = try JSONEncoder().encode(session)
            userDefaults.set(data, forKey: sessionKey)
        } catch {
            Logger.error("Failed to save session: \(error)", category: .session)
        }
    }

    func loadSession() -> PersistedSession? {
        guard let data = userDefaults.data(forKey: sessionKey) else { return nil }

        do {
            let session = try JSONDecoder().decode(PersistedSession.self, from: data)
            // Only return if session is recent (within 1 hour)
            if Date().timeIntervalSince(session.timestamp) < 3600 {
                return session
            }
        } catch {
            Logger.error("Failed to load session: \(error)", category: .session)
        }

        return nil
    }

    func clearSession() {
        userDefaults.removeObject(forKey: sessionKey)
    }
}

// MARK: - Error Handler

/// Centralized error handling with user-friendly messages
class ErrorHandler: ObservableObject {
    @Published var currentError: AppError?
    @Published var errorHistory: [AppError] = []

    private let maxHistorySize = 50

    // MARK: App Error

    struct AppError: Identifiable {
        let id = UUID()
        let type: ErrorType
        let message: String
        let suggestion: String?
        let timestamp: Date
        let isRecoverable: Bool
        let action: ErrorAction?
    }

    enum ErrorType {
        case connection
        case device
        case location
        case permission
        case network
        case system
        case iosVersionUnsupported
    }

    enum ErrorAction {
        case retry
        case openSettings
        case startTunneld
        case enableDeveloperMode
        case checkConnection
    }

    // MARK: Handle Error

    func handle(_ error: Error, context: String? = nil) {
        let appError = createAppError(from: error, context: context)
        currentError = appError
        addToHistory(appError)
    }

    func handle(message: String, type: ErrorType = .system, suggestion: String? = nil, action: ErrorAction? = nil) {
        let appError = AppError(
            type: type,
            message: message,
            suggestion: suggestion,
            timestamp: Date(),
            isRecoverable: action != nil,
            action: action
        )
        currentError = appError
        addToHistory(appError)
    }

    func clearCurrentError() {
        currentError = nil
    }

    func clearHistory() {
        errorHistory.removeAll()
    }

    // MARK: Private

    private func createAppError(from error: Error, context: String?) -> AppError {
        // Device errors
        if let deviceError = error as? DeviceError {
            return AppError(
                type: .device,
                message: deviceError.localizedDescription,
                suggestion: deviceError.recoverySuggestion,
                timestamp: Date(),
                isRecoverable: true,
                action: actionForDeviceError(deviceError)
            )
        }

        // Location injection errors
        if let injectionError = error as? LocationInjectionError {
            return AppError(
                type: .location,
                message: injectionError.localizedDescription,
                suggestion: injectionError.recoverySuggestion,
                timestamp: Date(),
                isRecoverable: true,
                action: actionForInjectionError(injectionError)
            )
        }

        // GPX errors
        if let gpxError = error as? GPXParserError {
            return AppError(
                type: .system,
                message: gpxError.localizedDescription,
                suggestion: nil,
                timestamp: Date(),
                isRecoverable: false,
                action: nil
            )
        }

        // Generic error
        return AppError(
            type: .system,
            message: context != nil ? "\(context!): \(error.localizedDescription)" : error.localizedDescription,
            suggestion: nil,
            timestamp: Date(),
            isRecoverable: false,
            action: nil
        )
    }

    private func actionForDeviceError(_ error: DeviceError) -> ErrorAction? {
        switch error {
        case .tunneldNotRunning: return .startTunneld
        case .developerModeDisabled: return .enableDeveloperMode
        case .connectionFailed, .deviceNotFound: return .checkConnection
        case .pairingRequired, .trustRequired: return .checkConnection
        default: return .retry
        }
    }

    private func actionForInjectionError(_ error: LocationInjectionError) -> ErrorAction? {
        switch error {
        case .tunneldNotRunning: return .startTunneld
        case .developerModeRequired: return .enableDeveloperMode
        case .deviceNotFound: return .checkConnection
        case .unsupportedIOSVersion: return .retry
        default: return .retry
        }
    }

    private func addToHistory(_ error: AppError) {
        errorHistory.insert(error, at: 0)
        if errorHistory.count > maxHistorySize {
            errorHistory.removeLast()
        }
    }
}

// MARK: - USB Fallback Manager

/// Manages fallback to USB connection when wireless fails
@MainActor
class USBFallbackManager: ObservableObject {
    @Published var isWirelessAvailable: Bool = true
    @Published var isUSBConnected: Bool = false
    @Published var preferUSB: Bool = false
    @Published var fallbackAttempts: Int = 0

    private let maxFallbackAttempts = 3

    enum ConnectionMode {
        case wireless
        case usb
        case auto
    }

    var recommendedMode: ConnectionMode {
        if preferUSB && isUSBConnected {
            return .usb
        }
        if !isWirelessAvailable && isUSBConnected {
            return .usb
        }
        if isWirelessAvailable {
            return .wireless
        }
        return .auto
    }

    func wirelessFailed() {
        isWirelessAvailable = false
        fallbackAttempts += 1

        if fallbackAttempts >= maxFallbackAttempts && isUSBConnected {
            preferUSB = true
        }
    }

    func wirelessRestored() {
        isWirelessAvailable = true
        fallbackAttempts = 0
    }

    func usbConnected() {
        isUSBConnected = true
    }

    func usbDisconnected() {
        isUSBConnected = false
        preferUSB = false
    }

    func reset() {
        isWirelessAvailable = true
        fallbackAttempts = 0
        preferUSB = false
    }
}
