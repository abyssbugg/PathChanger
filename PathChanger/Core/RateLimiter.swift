//
//  RateLimiter.swift
//  PathChanger
//
//  Token bucket rate limiter for location injection requests
//  Prevents overwhelming the device with too many location updates
//

import Foundation

// MARK: - Rate Limiter

/// A token bucket rate limiter for controlling location update frequency.
///
/// `RateLimiter` prevents overwhelming iOS devices with excessive location updates
/// by implementing the token bucket algorithm with configurable burst capacity
/// and refill rate.
///
/// ## Overview
///
/// The rate limiter provides:
/// - **Burst handling**: Allow short bursts up to capacity
/// - **Smooth throttling**: Refill tokens at a steady rate
/// - **Minimum interval**: Enforce minimum time between updates
/// - **Statistics tracking**: Monitor allowed and throttled requests
///
/// ## Token Bucket Algorithm
///
/// The algorithm works as follows:
/// 1. Bucket starts with `capacity` tokens
/// 2. Each request consumes 1 token
/// 3. Tokens refill at `refillRate` per second
/// 4. Requests are denied when bucket is empty
///
/// ```
/// ┌─────────────────────┐
/// │ Tokens: 10/10       │ ← Full bucket
/// │ █████████████████   │
/// └─────────────────────┘
///         │
///         ▼ (3 requests)
/// ┌─────────────────────┐
/// │ Tokens: 7/10        │
/// │ ███████████         │
/// └─────────────────────┘
///         │
///         ▼ (time passes, refill)
/// ┌─────────────────────┐
/// │ Tokens: 9/10        │
/// │ ███████████████     │
/// └─────────────────────┘
/// ```
///
/// ## Getting Started
///
/// ```swift
/// let limiter = RateLimiter(
///     capacity: 10,      // Allow burst of 10 requests
///     refillRate: 2.0,   // Refill 2 tokens per second
///     minIntervalMs: 50  // Minimum 50ms between requests
/// )
///
/// if await limiter.checkRequest() {
///     // Request allowed - proceed with location update
///     await bridge.setLocation(coordinate, for: device)
/// } else {
///     // Request throttled - skip this update
/// }
/// ```
///
/// ## Async Waiting
///
/// Use ``waitForAllowance()`` to block until a request is allowed:
///
/// ```swift
/// // Will wait until rate limit allows
/// await limiter.waitForAllowance()
/// await bridge.setLocation(coordinate, for: device)
/// ```
///
/// ## Statistics
///
/// Track rate limiting effectiveness:
///
/// ```swift
/// let stats = await limiter.statistics
/// print("Total: \(stats.total)")
/// print("Allowed: \(stats.allowed)")
/// print("Throttled: \(stats.throttled)")
/// print("Throttle Rate: \(stats.throttleRate)%")
/// ```
///
/// ## Thread Safety
///
/// `RateLimiter` is implemented as an actor, making it safe for concurrent access
/// from multiple tasks.
///
/// ## Topics
///
/// ### Rate Limiting
///
/// - ``checkRequest()``
/// - ``waitForAllowance()``
///
/// ### Statistics
///
/// - ``statistics``
/// - ``totalRequests``
/// - ``allowedRequests``
/// - ``throttledRequests``
///
/// ### Management
///
/// - ``reset()``
actor RateLimiter {
    // MARK: Configuration
    
    /// Maximum burst capacity (tokens available at once)
    private let capacity: Int
    
    /// Refill rate (tokens per second)
    private let refillRate: Double
    
    /// Minimum interval between updates (milliseconds)
    private let minIntervalMs: Double
    
    // MARK: State
    
    /// Available tokens
    private var tokens: Double
    
    /// Last refill timestamp
    private var lastRefillTime: Date
    
    /// Last allowed request timestamp
    private var lastRequestTime: Date?
    
    // MARK: Statistics
    
    private(set) var totalRequests: Int = 0
    private(set) var allowedRequests: Int = 0
    private(set) var throttledRequests: Int = 0
    
    // MARK: Initialization
    
    /// Create a rate limiter
    /// - Parameters:
    ///   - capacity: Maximum burst capacity (default: AppConstants.RateLimiting.defaultTokenBucketCapacity)
    ///   - refillRate: Tokens per second (default: AppConstants.RateLimiting.defaultTokenRefillRate)
    ///   - minIntervalMs: Minimum milliseconds between updates (default: AppConstants.RateLimiting.defaultMinIntervalMs)
    init(
        capacity: Int = AppConstants.RateLimiting.defaultTokenBucketCapacity,
        refillRate: Double = AppConstants.RateLimiting.defaultTokenRefillRate,
        minIntervalMs: Double = AppConstants.RateLimiting.defaultMinIntervalMs
    ) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.minIntervalMs = minIntervalMs
        self.tokens = Double(capacity) // Start with full capacity
        self.lastRefillTime = Date()
    }
    
    // MARK: Rate Limiting
    
    /// Check if request is allowed under rate limits
    /// - Returns: True if request is allowed, false if throttled
    func checkRequest() -> Bool {
        totalRequests += 1
        
        // Refill tokens based on elapsed time
        refillTokens()
        
        // Check minimum interval
        if let lastRequest = lastRequestTime {
            let elapsedMs = Date().timeIntervalSince(lastRequest) * 1000
            if elapsedMs < minIntervalMs {
                throttledRequests += 1
                return false
            }
        }
        
        // Check token availability
        if tokens >= 1.0 {
            tokens -= 1.0
            lastRequestTime = Date()
            allowedRequests += 1
            return true
        } else {
            throttledRequests += 1
            return false
        }
    }
    
    /// Wait until request is allowed (async version)
    /// - Returns: True when request is allowed
    /// - Throws: Never (always waits until allowed)
    func waitForAllowance() async -> Bool {
        while !checkRequest() {
            // Calculate wait time until next token
            let waitTimeMs = max(minIntervalMs, (1.0 / refillRate) * 1000)
            try? await Task.sleep(nanoseconds: UInt64(waitTimeMs * 1_000_000))
        }
        return true
    }
    
    /// Try to consume tokens for a request
    /// - Parameter count: Number of tokens to consume
    /// - Returns: True if tokens were available and consumed
    func tryConsume(tokens count: Int = 1) -> Bool {
        refillTokens()
        
        if tokens >= Double(count) {
            tokens -= Double(count)
            lastRequestTime = Date()
            allowedRequests += 1
            totalRequests += 1
            return true
        } else {
            throttledRequests += 1
            totalRequests += 1
            return false
        }
    }
    
    // MARK: Token Management
    
    /// Refill tokens based on elapsed time since last refill
    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)
        let tokensToAdd = elapsed * refillRate
        
        tokens = min(Double(capacity), tokens + tokensToAdd)
        lastRefillTime = now
    }
    
    /// Get current token count
    func availableTokens() -> Double {
        refillTokens()
        return tokens
    }
    
    /// Get time until next token (milliseconds)
    func timeUntilNextToken() -> Double {
        if tokens >= 1.0 {
            return 0
        }
        return (1.0 / refillRate) * 1000
    }
    
    // MARK: Statistics
    
    /// Get throttle rate percentage
    func throttleRate() -> Double {
        guard totalRequests > 0 else { return 0 }
        return Double(throttledRequests) / Double(totalRequests) * 100
    }
    
    /// Reset statistics
    func resetStats() {
        totalRequests = 0
        allowedRequests = 0
        throttledRequests = 0
    }
    
    /// Reset limiter state (refill all tokens)
    func reset() {
        tokens = Double(capacity)
        lastRefillTime = Date()
        lastRequestTime = nil
        resetStats()
    }
}

// MARK: - Queue Processing Strategy

/// Strategy for processing queued location requests
///
/// ## Strategies
///
/// - `sequential`: Process all queued requests in order (FIFO within priority).
///   Best for route simulation where every point matters.
///
/// - `latestWins`: Keep only the most recent request per device, dropping intermediate
///   updates. Best for joystick mode where responsiveness matters more than every point.
///
/// ## Usage
///
/// ```swift
/// // For joystick mode - drop stale updates
/// await queueManager.setStrategy(.latestWins)
///
/// // For route simulation - process all points
/// await queueManager.setStrategy(.sequential)
/// ```
enum QueueProcessingStrategy: String, CaseIterable, Hashable {
    /// Process all queued requests in order (default for routes)
    case sequential
    
    /// Keep only latest request per device, drop intermediate (best for joystick)
    case latestWins
    
    var description: String {
        switch self {
        case .sequential:
            return "Sequential (process all requests in order)"
        case .latestWins:
            return "Latest-Wins (drop stale requests, keep most recent)"
        }
    }
}

// MARK: - Queue Lag Metrics

/// Metrics for tracking queue lag and responsiveness
struct QueueLagMetrics {
    /// Average time requests spend in queue (milliseconds)
    var averageQueueTimeMs: Double = 0
    
    /// Maximum observed queue time (milliseconds)
    var maxQueueTimeMs: Double = 0
    
    /// Number of requests dropped due to latest-wins strategy
    var droppedRequests: Int = 0
    
    /// Number of requests processed
    var processedRequests: Int = 0
    
    /// Total requests enqueued
    var totalEnqueued: Int = 0
    
    /// Current queue depth (snapshot)
    var currentDepth: Int = 0
    
    /// Throughput (requests processed per second over last window)
    var throughputPerSecond: Double = 0
    
    /// Drop rate percentage
    var dropRate: Double {
        guard totalEnqueued > 0 else { return 0 }
        return Double(droppedRequests) / Double(totalEnqueued) * 100
    }
    
    /// Whether queue is responsive (low lag)
    var isResponsive: Bool {
        averageQueueTimeMs < 200 // Less than 200ms average
    }
    
    /// Whether queue is experiencing lag
    var isLagging: Bool {
        averageQueueTimeMs > 500 // More than 500ms average
    }
    
    /// Reset metrics
    mutating func reset() {
        averageQueueTimeMs = 0
        maxQueueTimeMs = 0
        droppedRequests = 0
        processedRequests = 0
        totalEnqueued = 0
        currentDepth = 0
        throughputPerSecond = 0
    }
}

// MARK: - Queued Request

/// Represents a queued location update request
struct QueuedLocationRequest {
    let id = UUID()
    let coordinate: LocationCoordinate
    let device: Device
    let timestamp: Date
    let priority: RequestPriority
    
    enum RequestPriority: Int, Comparable, CaseIterable, Hashable {
        case low = 0
        case normal = 1
        case high = 2
        
        static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - Queue Errors

/// Errors that can occur during queue operations
enum QueueError: Error, LocalizedError {
    case queueFull
    case priorityLimitExceeded(QueuedLocationRequest.RequestPriority)
    case rateLimitExceeded(QueuedLocationRequest.RequestPriority)
    
    var errorDescription: String? {
        switch self {
        case .queueFull:
            return "Request queue is full. Try again later."
        case .priorityLimitExceeded(let priority):
            return "Too many \(priority) priority requests queued. Please wait."
        case .rateLimitExceeded(let priority):
            return "Rate limit exceeded for \(priority) priority requests. Slow down."
        }
    }
}

// MARK: - Queue Health Metrics

/// Metrics for monitoring queue health
struct QueueHealthMetrics {
    let totalSize: Int
    let maxSize: Int
    let sizeByPriority: [QueuedLocationRequest.RequestPriority: Int]
    let utilizationPercent: Double
    
    var isHealthy: Bool {
        utilizationPercent < 80.0
    }
    
    var isWarning: Bool {
        utilizationPercent >= 80.0 && utilizationPercent < 95.0
    }
    
    var isCritical: Bool {
        utilizationPercent >= 95.0
    }
}

// MARK: - Request Queue Manager

/// Manages queued location requests with priority ordering and rate limiting
/// Security: Implements per-priority rate limits and queue size limits to prevent DoS
actor RequestQueueManager {
    private var queue: [QueuedLocationRequest] = []
    private let maxQueueSize: Int
    private var isProcessing = false
    
    // MARK: Strategy & Metrics
    
    /// Current queue processing strategy
    private var strategy: QueueProcessingStrategy = .sequential
    
    /// Lag metrics tracking
    private var lagMetrics = QueueLagMetrics()
    
    /// Timestamp tracking for throughput calculation
    private var throughputWindow: [Date] = []
    private let throughputWindowDuration: TimeInterval = 5.0 // 5 second window
    
    // MARK: Per-Priority Configuration
    
    /// Maximum queue slots per priority level (security: prevents priority flooding)
    private let queueLimitsPerPriority: [QueuedLocationRequest.RequestPriority: Int] = [
        .high: AppConstants.PriorityLimits.highPriorityQueueLimit,
        .normal: AppConstants.PriorityLimits.normalPriorityQueueLimit,
        .low: AppConstants.PriorityLimits.lowPriorityQueueLimit
    ]
    
    /// Per-priority rate limits (requests per second)
    private let rateLimitsPerPriority: [QueuedLocationRequest.RequestPriority: Double] = [
        .high: AppConstants.PriorityLimits.highPriorityRateLimit,
        .normal: AppConstants.PriorityLimits.normalPriorityRateLimit,
        .low: AppConstants.PriorityLimits.lowPriorityRateLimit
    ]
    
    /// Tracks enqueue timestamps per priority for rate limiting
    private var enqueueHistory: [QueuedLocationRequest.RequestPriority: [Date]] = [
        .high: [],
        .normal: [],
        .low: []
    ]
    
    /// Rate limiting window duration (1 second)
    private let rateLimitWindowSeconds: TimeInterval = 1.0
    
    init(maxQueueSize: Int = AppConstants.RateLimiting.defaultMaxQueueSize) {
        self.maxQueueSize = maxQueueSize
    }
    
    // MARK: Queue Operations with Security
    
    /// Enqueue a location request with rate limiting and priority limits
    /// Security: Prevents DoS via queue flooding
    /// - Returns: Success or specific error reason
    func enqueue(_ request: QueuedLocationRequest) -> Result<Bool, QueueError> {
        // Security: Check per-priority rate limit
        if !checkPriorityRateLimit(request.priority) {
            Logger.debug("Rate limit exceeded for \(request.priority) priority", category: .security)
            return .failure(.rateLimitExceeded(request.priority))
        }
        
        // Security: Check per-priority queue limit
        let currentPriorityCount = countByPriority()[request.priority] ?? 0
        let priorityLimit = queueLimitsPerPriority[request.priority] ?? 10
        
        if currentPriorityCount >= priorityLimit {
            Logger.debug("Priority limit exceeded: \(request.priority) has \(currentPriorityCount)/\(priorityLimit)", category: .security)
            return .failure(.priorityLimitExceeded(request.priority))
        }
        
        // Check total queue capacity
        if queue.count >= maxQueueSize {
            // Queue full - try to drop oldest low-priority request
            if let lowPriorityIndex = queue.firstIndex(where: { $0.priority == .low }) {
                queue.remove(at: lowPriorityIndex)
                Logger.debug("Dropped low-priority request to make room", category: .device)
            } else {
                Logger.debug("Queue full, no low-priority requests to drop", category: .security)
                return .failure(.queueFull)
            }
        }
        
        // Record enqueue for rate limiting
        recordEnqueue(request.priority)
        
        queue.append(request)
        
        // Sort by priority (high first) then timestamp (oldest first)
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.timestamp < rhs.timestamp
        }
        
        // Log queue health if approaching limits
        let metrics = getHealthMetrics()
        if metrics.isWarning {
            Logger.info("Queue utilization warning: \(Int(metrics.utilizationPercent))%", category: .device)
        }
        
        return .success(true)
    }
    
    /// Legacy enqueue method for backward compatibility
    /// - Returns: True if enqueued, false if rejected
    func enqueueCompat(_ request: QueuedLocationRequest) -> Bool {
        switch enqueue(request) {
        case .success:
            return true
        case .failure:
            return false
        }
    }
    
    // MARK: Strategy Management
    
    /// Set the queue processing strategy
    /// - Parameter newStrategy: The processing strategy to use
    func setStrategy(_ newStrategy: QueueProcessingStrategy) {
        if strategy != newStrategy {
            Logger.info("Queue strategy changed: \(strategy.rawValue) -> \(newStrategy.rawValue)", category: .device)
            strategy = newStrategy
        }
    }
    
    /// Get current processing strategy
    func currentStrategy() -> QueueProcessingStrategy {
        strategy
    }
    
    /// Enqueue with strategy - applies latest-wins logic if strategy is set
    /// - Returns: Success or specific error reason
    func enqueueWithStrategy(_ request: QueuedLocationRequest) -> Result<Bool, QueueError> {
        lagMetrics.totalEnqueued += 1
        lagMetrics.currentDepth = queue.count
        
        if strategy == .latestWins {
            return enqueueLatestWins(request)
        } else {
            return enqueue(request)
        }
    }
    
    /// Latest-wins enqueue - replaces existing request for same device
    /// Only keeps the most recent location for each device
    private func enqueueLatestWins(_ request: QueuedLocationRequest) -> Result<Bool, QueueError> {
        // Security: Check per-priority rate limit
        if !checkPriorityRateLimit(request.priority) {
            Logger.debug("Rate limit exceeded for \(request.priority) priority", category: .security)
            return .failure(.rateLimitExceeded(request.priority))
        }
        
        // Find and remove existing request for same device
        let existingCount = queue.filter { $0.device.id == request.device.id }.count
        if existingCount > 0 {
            queue.removeAll { $0.device.id == request.device.id }
            lagMetrics.droppedRequests += existingCount
            Logger.debug("Latest-wins: Dropped \(existingCount) stale request(s) for device \(request.device.id)", category: .device)
        }
        
        // Record enqueue for rate limiting
        recordEnqueue(request.priority)
        
        queue.append(request)
        
        // Sort by priority (high first) then timestamp (oldest first)
        queue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.timestamp < rhs.timestamp
        }
        
        return .success(true)
    }
    
    // MARK: Lag Metrics
    
    /// Record that a request was processed (call when dequeuing)
    /// - Parameter queuedAt: The timestamp when the request was enqueued
    func recordProcessed(queuedAt: Date) {
        let queueTimeMs = Date().timeIntervalSince(queuedAt) * 1000
        
        lagMetrics.processedRequests += 1
        lagMetrics.maxQueueTimeMs = max(lagMetrics.maxQueueTimeMs, queueTimeMs)
        
        // Update rolling average (exponential moving average)
        let alpha = 0.1
        lagMetrics.averageQueueTimeMs = lagMetrics.averageQueueTimeMs * (1 - alpha) + queueTimeMs * alpha
        
        // Track throughput
        throughputWindow.append(Date())
        updateThroughput()
    }
    
    /// Update throughput calculation
    private func updateThroughput() {
        let cutoff = Date().addingTimeInterval(-throughputWindowDuration)
        throughputWindow = throughputWindow.filter { $0 > cutoff }
        lagMetrics.throughputPerSecond = Double(throughputWindow.count) / throughputWindowDuration
    }
    
    /// Get current lag metrics
    func getLagMetrics() -> QueueLagMetrics {
        var metrics = lagMetrics
        metrics.currentDepth = queue.count
        updateThroughput()
        metrics.throughputPerSecond = lagMetrics.throughputPerSecond
        return metrics
    }
    
    /// Reset lag metrics
    func resetLagMetrics() {
        lagMetrics.reset()
        throughputWindow.removeAll()
    }
    
    // MARK: Rate Limiting
    
    /// Check if enqueue is allowed under per-priority rate limit
    private func checkPriorityRateLimit(_ priority: QueuedLocationRequest.RequestPriority) -> Bool {
        cleanupOldHistory(priority)
        
        let currentCount = enqueueHistory[priority]?.count ?? 0
        let limit = rateLimitsPerPriority[priority] ?? 5.0
        
        return Double(currentCount) < limit
    }
    
    /// Record an enqueue operation for rate limiting
    private func recordEnqueue(_ priority: QueuedLocationRequest.RequestPriority) {
        if enqueueHistory[priority] == nil {
            enqueueHistory[priority] = []
        }
        enqueueHistory[priority]?.append(Date())
    }
    
    /// Remove enqueue records older than rate limit window
    private func cleanupOldHistory(_ priority: QueuedLocationRequest.RequestPriority) {
        let cutoff = Date().addingTimeInterval(-rateLimitWindowSeconds)
        enqueueHistory[priority] = enqueueHistory[priority]?.filter { $0 > cutoff } ?? []
    }
    
    // MARK: Queue Information
    
    /// Count requests by priority level
    func countByPriority() -> [QueuedLocationRequest.RequestPriority: Int] {
        var counts: [QueuedLocationRequest.RequestPriority: Int] = [:]
        for priority in QueuedLocationRequest.RequestPriority.allCases {
            counts[priority] = queue.filter { $0.priority == priority }.count
        }
        return counts
    }
    
    /// Get queue health metrics
    func getHealthMetrics() -> QueueHealthMetrics {
        let total = queue.count
        let utilization = maxQueueSize > 0 ? (Double(total) / Double(maxQueueSize)) * 100.0 : 0.0
        
        return QueueHealthMetrics(
            totalSize: total,
            maxSize: maxQueueSize,
            sizeByPriority: countByPriority(),
            utilizationPercent: utilization
        )
    }
    
    /// Dequeue next request
    func dequeue() -> QueuedLocationRequest? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
    
    /// Peek at next request without removing
    func peek() -> QueuedLocationRequest? {
        queue.first
    }
    
    /// Get current queue size
    func size() -> Int {
        queue.count
    }
    
    /// Clear all queued requests
    func clear() {
        queue.removeAll()
        // Also clear rate limit history
        for priority in QueuedLocationRequest.RequestPriority.allCases {
            enqueueHistory[priority] = []
        }
    }
    
    /// Check if currently processing
    func processing() -> Bool {
        isProcessing
    }
    
    /// Set processing state
    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }
}
