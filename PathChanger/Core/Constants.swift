//
//  Constants.swift
//  PathChanger
//
//  Centralized configuration constants (CODE-001)
//  All magic numbers extracted to named, documented constants
//

import Foundation

// MARK: - App Configuration

/// Application-wide configuration constants
enum AppConstants {

    // MARK: - Rate Limiting Configuration

    /// Rate limiting configuration for location injection requests
    enum RateLimiting {
        /// Maximum burst capacity for token bucket (number of requests)
        static let tokenBucketCapacity: Int = 10
        /// Alias for default parameter value
        static let defaultTokenBucketCapacity: Int = tokenBucketCapacity

        /// Token refill rate (tokens per second) for sustained throughput
        static let tokenRefillRate: Double = 5.0
        /// Alias for default parameter value
        static let defaultTokenRefillRate: Double = tokenRefillRate

        /// Minimum interval between location updates (milliseconds)
        static let minimumIntervalMs: Double = 100.0
        /// Alias for default parameter value
        static let defaultMinIntervalMs: Double = minimumIntervalMs

        /// Maximum queue size for pending location requests
        static let maxQueueSize: Int = 50
        /// Alias for default parameter value
        static let defaultMaxQueueSize: Int = maxQueueSize

        /// Rate limiting window duration (seconds)
        static let rateLimitWindowSeconds: TimeInterval = 1.0

        /// Queue utilization warning threshold (percentage)
        static let queueWarningThreshold: Double = 80.0

        /// Queue utilization critical threshold (percentage)
        static let queueCriticalThreshold: Double = 95.0

        /// Minimum capacity for rate limiting (user setting)
        static let minCapacity: Int = 5

        /// Maximum capacity for rate limiting (user setting)
        static let maxCapacity: Int = 50

        /// Minimum refill rate for rate limiting (user setting)
        static let minRefillRate: Double = 1.0

        /// Maximum refill rate for rate limiting (user setting)
        static let maxRefillRate: Double = 20.0
    }

    /// Per-priority queue configuration
    enum PriorityLimits {
        /// Maximum high-priority requests in queue (limited to prevent abuse)
        static let highPriorityMaxCount: Int = 10
        /// Alias for queue limit
        static let highPriorityQueueLimit: Int = highPriorityMaxCount

        /// Maximum normal-priority requests in queue
        static let normalPriorityMaxCount: Int = 25
        /// Alias for queue limit
        static let normalPriorityQueueLimit: Int = normalPriorityMaxCount

        /// Maximum low-priority requests in queue (can be displaced)
        static let lowPriorityMaxCount: Int = 15
        /// Alias for queue limit
        static let lowPriorityQueueLimit: Int = lowPriorityMaxCount

        /// High-priority rate limit (requests per second)
        static let highPriorityRateLimit: Double = 2.0

        /// Normal-priority rate limit (requests per second)
        static let normalPriorityRateLimit: Double = 5.0

        /// Low-priority rate limit (requests per second)
        static let lowPriorityRateLimit: Double = 10.0
    }

    // MARK: - Timeout Configuration

    /// Timeout configuration for various operations
    enum Timeout {
        /// Default command timeout (seconds)
        static let defaultCommandTimeout: TimeInterval = 30.0

        /// Minimum command timeout (seconds)
        static let commandTimeoutMin: TimeInterval = 10.0

        /// Maximum command timeout (seconds)
        static let commandTimeoutMax: TimeInterval = 120.0

        /// Default tunnel timeout (seconds)
        static let defaultTunnelTimeout: TimeInterval = 45.0

        /// Minimum tunnel timeout (seconds)
        static let tunnelTimeoutMin: TimeInterval = 15.0

        /// Maximum tunnel timeout (seconds)
        static let tunnelTimeoutMax: TimeInterval = 180.0
    }

    // MARK: - Tunnel Configuration

    /// Tunnel management configuration
    enum Tunnel {
        /// State debounce interval (seconds) - prevents rapid state changes
        static let stateDebounceInterval: TimeInterval = 0.3

        /// Default port for tunnel connections
        static let defaultPort: Int = 49152

        /// Tunneld HTTP API port (used by pymobiledevice3 remote tunneld)
        static let tunneldAPIPort: Int = 49151

        /// Base URL for tunneld HTTP API
        static var tunneldAPIEndpoint: String { "http://127.0.0.1:\(tunneldAPIPort)/" }

        /// Maximum port range for tunnel connections
        static let maxPort: Int = 65535

        /// Minimum port for user-space connections
        static let minUserPort: Int = 1024

        /// Connection timeout for tunnel establishment (seconds)
        static let connectionTimeout: TimeInterval = 30.0

        /// Retry delay after tunnel failure (seconds)
        static let retryDelay: TimeInterval = 2.0
    }

    // MARK: - Health Monitoring Configuration

    /// Health check and monitoring configuration
    enum HealthMonitoring {
        /// Health check interval (seconds)
        static let healthCheckInterval: TimeInterval = 2.0

        /// Maximum consecutive failures before unhealthy
        static let maxConsecutiveFailures: Int = 3

        /// Health check timeout (seconds)
        static let healthCheckTimeout: TimeInterval = 5.0

        /// Ping interval for connection keepalive (seconds)
        static let pingInterval: TimeInterval = 30.0
    }

    // MARK: - Process Management Configuration

    /// Process execution configuration
    enum ProcessManagement {
        /// Default command timeout (seconds)
        static let defaultTimeout: TimeInterval = 30.0

        /// Extended timeout for slow operations (seconds)
        static let extendedTimeout: TimeInterval = 60.0

        /// Maximum output size to prevent memory issues (bytes)
        static let maxOutputSize: Int = 10 * 1024 * 1024 // 10 MB

        /// Grace period before force kill (seconds)
        static let gracefulTerminationDelay: TimeInterval = 0.5

        /// Maximum tracked process IDs
        static let maxTrackedProcessIds: Int = 100
    }

    // MARK: - Input Validation Configuration

    /// Input validation rules and limits
    enum Validation {
        /// Expected UDID length for legacy devices
        static let legacyUdidLength: Int = 40

        /// Minimum UDID length for new-format devices
        static let modernUdidLength: Int = 25

        /// Maximum coordinate precision (decimal places)
        static let coordinatePrecision: Int = 6

        /// Latitude range: -90 to +90
        static let latitudeMin: Double = -90.0
        static let latitudeMax: Double = 90.0

        /// Longitude range: -180 to +180
        static let longitudeMin: Double = -180.0
        static let longitudeMax: Double = 180.0

        /// Maximum argument length for security
        static let maxArgumentLength: Int = 1024

        /// Maximum path length
        static let maxPathLength: Int = 4096
    }

    // MARK: - Simulation Configuration

    /// Simulation engine configuration
    enum Simulation {
        /// Maximum distance for a single move (meters) - prevents erratic jumps
        static let maxMoveDistanceMeters: Double = 100_000  // 100 km

        /// Earth radius for haversine calculations (meters)
        static let earthRadiusMeters: Double = 6_371_000.0

        /// Default simulation speed update interval (seconds)
        static let defaultUpdateInterval: TimeInterval = 1.0

        /// Minimum update interval for fast modes (seconds)
        static let minimumUpdateInterval: TimeInterval = 0.1
    }

    // MARK: - Reliability Configuration

    /// Connection reliability and recovery configuration
    enum Reliability {
        /// Maximum reconnection attempts
        static let maxReconnectionAttempts: Int = 5

        /// Initial reconnection delay (seconds)
        static let initialReconnectionDelay: TimeInterval = 1.0

        /// Maximum reconnection delay (seconds)
        static let maxReconnectionDelay: TimeInterval = 30.0

        /// Backoff multiplier for exponential backoff
        static let backoffMultiplier: Double = 2.0

        /// Jitter factor for randomizing delays (0.0-1.0)
        static let jitterFactor: Double = 0.25

        /// Circuit breaker failure threshold
        static let circuitBreakerFailureThreshold: Int = 5

        /// Circuit breaker success threshold to close
        static let circuitBreakerSuccessThreshold: Int = 2

        /// Circuit breaker reset timeout (seconds)
        static let circuitBreakerResetTimeout: TimeInterval = 30.0

        /// Failure monitoring window (seconds)
        static let monitoringWindowSeconds: TimeInterval = 60.0
    }

    // MARK: - Device Cache Configuration

    /// Device discovery caching configuration
    enum DeviceCache {
        /// Time-to-live for cached device info (seconds)
        static let deviceInfoTTL: TimeInterval = 60.0

        /// Time-to-live for cached device list (seconds)
        static let deviceListTTL: TimeInterval = 30.0

        /// Maximum cached entries
        static let maxCacheEntries: Int = 50

        /// Discovery timeout (seconds)
        static let discoveryTimeout: TimeInterval = 10.0
    }

    // MARK: - UI Configuration

    /// User interface configuration
    enum UI {
        /// Toast notification duration (seconds)
        static let toastDuration: TimeInterval = 3.0

        /// Animation duration for transitions (seconds)
        static let animationDuration: TimeInterval = 0.3

        /// Debounce interval for search input (seconds)
        static let searchDebounceInterval: TimeInterval = 0.3

        /// Maximum recent locations to display
        static let maxRecentLocations: Int = 10

        /// Map default zoom level
        static let defaultMapZoom: Double = 0.01
    }
}

// MARK: - Security Constants

/// Security-related constants (separate for audit clarity)
enum SecurityConstants {

    /// Allowed Python executable paths
    static let allowedPythonPaths: Set<String> = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
        "/opt/homebrew/bin/python3.11",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.13",
        "/usr/local/bin/python3.11",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.13"
    ]

    /// Allowed pymobiledevice3 subcommands
    static let allowedSubcommands: Set<String> = [
        "developer",
        "usbmux",
        "remote"
    ]

    /// Allowed pymobiledevice3 flags
    static let allowedFlags: Set<String> = [
        "--rsd",
        "--udid",
        "-t",
        "--tunnel",
        "--help",
        "-h"
    ]

    /// Dangerous characters blocked in arguments
    static let dangerousCharacters: CharacterSet = CharacterSet(charactersIn: ";|&$`\\\"'<>(){}[]!#")

    /// Maximum output size before truncation (security limit)
    static let maxSecureOutputSize: Int = 5 * 1024 * 1024 // 5 MB
}
