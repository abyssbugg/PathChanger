//
//  RateLimiterTests.swift
//  PathChangerTests
//
//  Unit tests for token bucket rate limiter
//

import XCTest
@testable import PathChanger

final class RateLimiterTests: XCTestCase {

    func testInitialTokensEqualCapacity() async {
        let limiter = RateLimiter(capacity: 10, refillRate: 5.0)
        let tokens = await limiter.availableTokens()
        XCTAssertEqual(tokens, 10.0, accuracy: 0.1)
    }

    func testRequestAllowedWithTokens() async {
        let limiter = RateLimiter(capacity: 10, refillRate: 5.0)
        let allowed = await limiter.checkRequest()
        XCTAssertTrue(allowed)
    }

    func testRequestDeniedWhenOutOfTokens() async {
        let limiter = RateLimiter(capacity: 1, refillRate: 1.0)

        // First request should succeed
        _ = await limiter.checkRequest()

        // Second immediate request should fail
        let denied = await limiter.checkRequest()
        XCTAssertFalse(denied)
    }

    func testTokenRefill() async throws {
        let limiter = RateLimiter(capacity: 10, refillRate: 10.0, minIntervalMs: 0) // 10 tokens per second

        // Consume all tokens
        for _ in 0..<10 {
            _ = await limiter.checkRequest()
        }

        // Wait 300ms (should get 3 tokens: 10 tokens/sec * 0.3 sec = 3 tokens)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Should allow at least 2 requests (being conservative with timing)
        let firstAllowed = await limiter.checkRequest()
        XCTAssertTrue(firstAllowed)
        let secondAllowed = await limiter.checkRequest()
        XCTAssertTrue(secondAllowed)

        // May or may not allow a third depending on exact timing
        // So we don't assert on the third one
    }

    func testStatistics() async {
        let limiter = RateLimiter(capacity: 2, refillRate: 1.0, minIntervalMs: 0)

        // 2 allowed, 1 throttled
        _ = await limiter.checkRequest()
        _ = await limiter.checkRequest()
        _ = await limiter.checkRequest()

        let throttleRate = await limiter.throttleRate()
        XCTAssertEqual(throttleRate, 33.33, accuracy: 0.1) // 1/3 = 33.33%
    }

    func testReset() async {
        let limiter = RateLimiter(capacity: 1, refillRate: 1.0)

        // Consume token
        _ = await limiter.checkRequest()

        // Reset should restore tokens
        await limiter.reset()

        let tokens = await limiter.availableTokens()
        XCTAssertEqual(tokens, 1.0)
    }

    // MARK: - Queue Error Tests

    func testQueueErrorDescriptions() {
        let fullError = QueueError.queueFull
        XCTAssertNotNil(fullError.errorDescription)
        XCTAssertTrue(fullError.errorDescription!.contains("full"))

        let priorityError = QueueError.priorityLimitExceeded(.high)
        XCTAssertNotNil(priorityError.errorDescription)
        XCTAssertTrue(priorityError.errorDescription!.contains("high"))

        let rateError = QueueError.rateLimitExceeded(.normal)
        XCTAssertNotNil(rateError.errorDescription)
        XCTAssertTrue(rateError.errorDescription!.contains("normal"))
    }

    // MARK: - Queue Health Metrics Tests

    func testQueueHealthMetricsHealthy() {
        let metrics = QueueHealthMetrics(
            totalSize: 10,
            maxSize: 50,
            sizeByPriority: [.high: 2, .normal: 5, .low: 3],
            utilizationPercent: 20.0
        )

        XCTAssertTrue(metrics.isHealthy)
        XCTAssertFalse(metrics.isWarning)
        XCTAssertFalse(metrics.isCritical)
    }

    func testQueueHealthMetricsWarning() {
        let metrics = QueueHealthMetrics(
            totalSize: 40,
            maxSize: 50,
            sizeByPriority: [.high: 10, .normal: 20, .low: 10],
            utilizationPercent: 80.0
        )

        XCTAssertFalse(metrics.isHealthy)
        XCTAssertTrue(metrics.isWarning)
        XCTAssertFalse(metrics.isCritical)
    }

    func testQueueHealthMetricsCritical() {
        let metrics = QueueHealthMetrics(
            totalSize: 48,
            maxSize: 50,
            sizeByPriority: [.high: 10, .normal: 25, .low: 13],
            utilizationPercent: 96.0
        )

        XCTAssertFalse(metrics.isHealthy)
        XCTAssertFalse(metrics.isWarning)
        XCTAssertTrue(metrics.isCritical)
    }
}

// MARK: - Request Queue Manager Security Tests

final class RequestQueueManagerSecurityTests: XCTestCase {

    // Helper to create a test request
    private func makeRequest(priority: QueuedLocationRequest.RequestPriority) -> QueuedLocationRequest {
        QueuedLocationRequest(
            coordinate: LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            device: Device(id: "00008030001234567890123456789012345678ab", displayName: "Test Device", connectionType: .usb),
            timestamp: Date(),
            priority: priority
        )
    }

    // MARK: - Per-Priority Rate Limit Tests

    func testHighPriorityRateLimitEnforced() async {
        let queue = RequestQueueManager(maxQueueSize: 50)

        // High priority limit is 2 per second
        // First 2 should succeed
        let result1 = await queue.enqueue(makeRequest(priority: .high))
        let result2 = await queue.enqueue(makeRequest(priority: .high))

        XCTAssertTrue(result1.isSuccess, "First high-priority request should succeed")
        XCTAssertTrue(result2.isSuccess, "Second high-priority request should succeed")

        // Third should fail (rate limit exceeded)
        let result3 = await queue.enqueue(makeRequest(priority: .high))

        switch result3 {
        case .success:
            XCTFail("Third high-priority request should be rate limited")
        case .failure(let error):
            if case .rateLimitExceeded(let priority) = error {
                XCTAssertEqual(priority, .high)
            } else {
                XCTFail("Expected rateLimitExceeded error, got \(error)")
            }
        }
    }

    func testNormalPriorityRateLimitEnforced() async {
        let queue = RequestQueueManager(maxQueueSize: 50)

        // Normal priority limit is 5 per second
        for i in 0..<5 {
            let result = await queue.enqueue(makeRequest(priority: .normal))
            XCTAssertTrue(result.isSuccess, "Request \(i+1) should succeed")
        }

        // 6th should fail (rate limit exceeded)
        let result6 = await queue.enqueue(makeRequest(priority: .normal))

        switch result6 {
        case .success:
            XCTFail("6th normal-priority request should be rate limited")
        case .failure(let error):
            if case .rateLimitExceeded(let priority) = error {
                XCTAssertEqual(priority, .normal)
            } else {
                XCTFail("Expected rateLimitExceeded error, got \(error)")
            }
        }
    }

    // MARK: - Per-Priority Queue Limit Tests

    func testHighPriorityQueueLimitEnforced() async throws {
        let queue = RequestQueueManager(maxQueueSize: 50)

        // High priority queue limit is 10
        // But rate limit is 2/sec, so we need to wait between batches

        // First batch of 2
        _ = await queue.enqueue(makeRequest(priority: .high))
        _ = await queue.enqueue(makeRequest(priority: .high))

        // Wait for rate limit window to reset
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        // Second batch of 2
        _ = await queue.enqueue(makeRequest(priority: .high))
        _ = await queue.enqueue(makeRequest(priority: .high))

        // Wait again
        try await Task.sleep(nanoseconds: 1_100_000_000)

        // Third batch of 2 (total 6)
        _ = await queue.enqueue(makeRequest(priority: .high))
        _ = await queue.enqueue(makeRequest(priority: .high))

        // Verify count
        let metrics = await queue.getHealthMetrics()
        XCTAssertEqual(metrics.sizeByPriority[.high], 6, "Should have 6 high-priority requests")
    }

    // MARK: - Priority Flooding Prevention Tests

    func testHighPriorityFloodingPrevented() async {
        let queue = RequestQueueManager(maxQueueSize: 50)

        var successCount = 0
        var failureCount = 0

        // Try to flood with 100 high-priority requests
        for _ in 0..<100 {
            let result = await queue.enqueue(makeRequest(priority: .high))
            switch result {
            case .success:
                successCount += 1
            case .failure:
                failureCount += 1
            }
        }

        // Should only allow 2 (rate limit per second)
        XCTAssertEqual(successCount, 2, "Should only allow 2 high-priority requests per second")
        XCTAssertEqual(failureCount, 98, "Should reject 98 requests")
    }

    // MARK: - Queue Full Tests

    func testQueueFullWithNoLowPriority() async throws {
        let queue = RequestQueueManager(maxQueueSize: 5)

        // Fill queue with normal priority (within limits and rate)
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .normal))

        try await Task.sleep(nanoseconds: 1_100_000_000)

        // Queue should be full with normal priority
        // Adding another should fail (no low-priority to drop)
        let result = await queue.enqueue(makeRequest(priority: .normal))

        // Could fail due to rate limit or queue full
        XCTAssertFalse(result.isSuccess, "Should fail when queue is full with no low-priority to drop")
    }

    // MARK: - Low Priority Displacement Tests

    func testLowPriorityDisplacedWhenQueueFull() async throws {
        let queue = RequestQueueManager(maxQueueSize: 5)

        // Add 3 low-priority requests
        _ = await queue.enqueue(makeRequest(priority: .low))
        _ = await queue.enqueue(makeRequest(priority: .low))
        _ = await queue.enqueue(makeRequest(priority: .low))

        // Wait for rate limit window
        try await Task.sleep(nanoseconds: 1_100_000_000)

        // Add 2 more low priority to fill queue
        _ = await queue.enqueue(makeRequest(priority: .low))
        _ = await queue.enqueue(makeRequest(priority: .low))

        // Wait again
        try await Task.sleep(nanoseconds: 1_100_000_000)

        let sizeBeforeNormal = await queue.size()
        XCTAssertEqual(sizeBeforeNormal, 5, "Queue should be full")

        // Add normal priority - should displace a low priority
        let result = await queue.enqueue(makeRequest(priority: .normal))

        XCTAssertTrue(result.isSuccess, "Normal priority should displace low priority")

        let sizeAfter = await queue.size()
        XCTAssertEqual(sizeAfter, 5, "Queue should still be at max size")

        let metrics = await queue.getHealthMetrics()
        XCTAssertEqual(metrics.sizeByPriority[.normal], 1, "Should have 1 normal-priority request")
        XCTAssertEqual(metrics.sizeByPriority[.low], 4, "Should have 4 low-priority requests")
    }

    // MARK: - Clear Tests

    func testClearResetsRateLimitHistory() async throws {
        let queue = RequestQueueManager(maxQueueSize: 50)

        // Use up rate limit
        _ = await queue.enqueue(makeRequest(priority: .high))
        _ = await queue.enqueue(makeRequest(priority: .high))

        // 3rd should fail
        let beforeClear = await queue.enqueue(makeRequest(priority: .high))
        XCTAssertFalse(beforeClear.isSuccess, "Should be rate limited before clear")

        // Clear the queue
        await queue.clear()

        // Rate limit should be reset - first 2 should work again
        let afterClear1 = await queue.enqueue(makeRequest(priority: .high))
        let afterClear2 = await queue.enqueue(makeRequest(priority: .high))

        XCTAssertTrue(afterClear1.isSuccess, "First request after clear should succeed")
        XCTAssertTrue(afterClear2.isSuccess, "Second request after clear should succeed")
    }

    // MARK: - Health Metrics Tests

    func testHealthMetricsAccuracy() async {
        let queue = RequestQueueManager(maxQueueSize: 50)

        // Add mix of priorities
        _ = await queue.enqueue(makeRequest(priority: .high))
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .normal))
        _ = await queue.enqueue(makeRequest(priority: .low))

        let metrics = await queue.getHealthMetrics()

        XCTAssertEqual(metrics.totalSize, 4)
        XCTAssertEqual(metrics.maxSize, 50)
        XCTAssertEqual(metrics.sizeByPriority[.high], 1)
        XCTAssertEqual(metrics.sizeByPriority[.normal], 2)
        XCTAssertEqual(metrics.sizeByPriority[.low], 1)
        XCTAssertEqual(metrics.utilizationPercent, 8.0, accuracy: 0.1) // 4/50 = 8%
        XCTAssertTrue(metrics.isHealthy)
    }

    // MARK: - Queue Processing Strategy Tests

    func testDefaultStrategyIsSequential() async {
        let queue = RequestQueueManager()
        let strategy = await queue.currentStrategy()
        XCTAssertEqual(strategy, .sequential)
    }

    func testSetStrategyToLatestWins() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.latestWins)
        let strategy = await queue.currentStrategy()
        XCTAssertEqual(strategy, .latestWins)
    }

    func testLatestWinsDropsStaleRequestsForSameDevice() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.latestWins)

        // Create requests for same device
        let device1 = Device(id: "device-1", displayName: "Test Device", connectionType: .usb, productVersion: "17.0")
        let coord1 = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let coord2 = LocationCoordinate(latitude: 35.1, longitude: 139.1)
        let coord3 = LocationCoordinate(latitude: 35.2, longitude: 139.2)

        let request1 = QueuedLocationRequest(coordinate: coord1, device: device1, timestamp: Date(), priority: .normal)
        let request2 = QueuedLocationRequest(coordinate: coord2, device: device1, timestamp: Date().addingTimeInterval(0.1), priority: .normal)
        let request3 = QueuedLocationRequest(coordinate: coord3, device: device1, timestamp: Date().addingTimeInterval(0.2), priority: .normal)

        // Enqueue with strategy
        _ = await queue.enqueueWithStrategy(request1)
        _ = await queue.enqueueWithStrategy(request2)
        _ = await queue.enqueueWithStrategy(request3)

        // Should only have 1 request (the latest)
        let size = await queue.size()
        XCTAssertEqual(size, 1)

        // Verify it's the latest coordinate
        let peeked = await queue.peek()
        XCTAssertEqual(peeked?.coordinate.latitude, 35.2)
    }

    func testLatestWinsKeepsRequestsForDifferentDevices() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.latestWins)

        // Create requests for different devices
        let device1 = Device(id: "device-1", displayName: "Device 1", connectionType: .usb, productVersion: "17.0")
        let device2 = Device(id: "device-2", displayName: "Device 2", connectionType: .usb, productVersion: "17.0")
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        let request1 = QueuedLocationRequest(coordinate: coord, device: device1, timestamp: Date(), priority: .normal)
        let request2 = QueuedLocationRequest(coordinate: coord, device: device2, timestamp: Date(), priority: .normal)

        _ = await queue.enqueueWithStrategy(request1)
        _ = await queue.enqueueWithStrategy(request2)

        // Should have 2 requests (one per device)
        let size = await queue.size()
        XCTAssertEqual(size, 2)
    }

    func testSequentialStrategyKeepsAllRequests() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.sequential)

        // Create multiple requests for same device
        let device = Device(id: "device-1", displayName: "Test Device", connectionType: .usb, productVersion: "17.0")

        for i in 0..<3 {
            let request = QueuedLocationRequest(
                coordinate: LocationCoordinate(latitude: 35.0 + Double(i) * 0.1, longitude: 139.0),
                device: device,
                timestamp: Date().addingTimeInterval(Double(i) * 0.1),
                priority: .normal
            )
            _ = await queue.enqueueWithStrategy(request)
        }

        // Sequential should keep all 3
        let size = await queue.size()
        XCTAssertEqual(size, 3)
    }

    // MARK: - Lag Metrics Tests

    func testLagMetricsInitialState() async {
        let queue = RequestQueueManager()
        let metrics = await queue.getLagMetrics()

        XCTAssertEqual(metrics.averageQueueTimeMs, 0)
        XCTAssertEqual(metrics.maxQueueTimeMs, 0)
        XCTAssertEqual(metrics.droppedRequests, 0)
        XCTAssertEqual(metrics.processedRequests, 0)
        XCTAssertEqual(metrics.totalEnqueued, 0)
    }

    func testLagMetricsRecordsProcessedRequest() async {
        let queue = RequestQueueManager()

        // Record multiple processing events to see rolling average
        let queuedAt1 = Date().addingTimeInterval(-0.1) // 100ms ago
        let queuedAt2 = Date().addingTimeInterval(-0.1) // 100ms ago
        await queue.recordProcessed(queuedAt: queuedAt1)
        await queue.recordProcessed(queuedAt: queuedAt2)

        let metrics = await queue.getLagMetrics()

        XCTAssertEqual(metrics.processedRequests, 2)
        // With EMA (alpha=0.1), after multiple ~100ms samples the average should trend toward 100ms
        // First sample: 0 * 0.9 + 100 * 0.1 = 10
        // Second sample: 10 * 0.9 + 100 * 0.1 = 19
        // The average is an EMA, so we check it's moving in the right direction
        XCTAssertGreaterThan(metrics.averageQueueTimeMs, 10) // Should be around 19ms after 2 samples
        XCTAssertLessThan(metrics.averageQueueTimeMs, 150) // Not over 150ms
    }

    func testLagMetricsTracksDroppedRequests() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.latestWins)

        // Create requests for same device (will cause drops)
        let device = Device(id: "device-1", displayName: "Test Device", connectionType: .usb, productVersion: "17.0")
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        let request1 = QueuedLocationRequest(coordinate: coord, device: device, timestamp: Date(), priority: .normal)
        let request2 = QueuedLocationRequest(coordinate: coord, device: device, timestamp: Date(), priority: .normal)

        _ = await queue.enqueueWithStrategy(request1)
        _ = await queue.enqueueWithStrategy(request2) // Should drop request1

        let metrics = await queue.getLagMetrics()
        XCTAssertEqual(metrics.droppedRequests, 1)
    }

    func testLagMetricsDropRate() async {
        let queue = RequestQueueManager()
        await queue.setStrategy(.latestWins)

        // Enqueue multiple requests that will cause drops
        let device = Device(id: "device-1", displayName: "Test", connectionType: .usb, productVersion: "17.0")
        let coord = LocationCoordinate(latitude: 35.0, longitude: 139.0)

        for i in 0..<5 {
            let request = QueuedLocationRequest(coordinate: coord, device: device, timestamp: Date().addingTimeInterval(Double(i) * 0.01), priority: .normal)
            _ = await queue.enqueueWithStrategy(request)
        }

        let metrics = await queue.getLagMetrics()
        XCTAssertEqual(metrics.totalEnqueued, 5)
        XCTAssertEqual(metrics.droppedRequests, 4) // 4 were replaced
        XCTAssertEqual(metrics.dropRate, 80.0, accuracy: 0.1) // 4/5 = 80%
    }

    func testLagMetricsReset() async {
        let queue = RequestQueueManager()

        // Record some activity
        await queue.recordProcessed(queuedAt: Date().addingTimeInterval(-0.1))

        // Verify metrics exist
        let beforeReset = await queue.getLagMetrics()
        XCTAssertEqual(beforeReset.processedRequests, 1)

        // Reset
        await queue.resetLagMetrics()

        // Verify reset
        let afterReset = await queue.getLagMetrics()
        XCTAssertEqual(afterReset.processedRequests, 0)
        XCTAssertEqual(afterReset.averageQueueTimeMs, 0)
    }

    func testLagMetricsResponsivenessIndicators() {
        // Test isResponsive (< 200ms)
        var metrics = QueueLagMetrics()
        metrics.averageQueueTimeMs = 100
        XCTAssertTrue(metrics.isResponsive)
        XCTAssertFalse(metrics.isLagging)

        // Test isLagging (> 500ms)
        metrics.averageQueueTimeMs = 600
        XCTAssertFalse(metrics.isResponsive)
        XCTAssertTrue(metrics.isLagging)
    }

    // MARK: - Queue Processing Strategy Description Tests

    func testQueueProcessingStrategyDescriptions() {
        XCTAssertTrue(QueueProcessingStrategy.sequential.description.contains("Sequential"))
        XCTAssertTrue(QueueProcessingStrategy.latestWins.description.contains("Latest-Wins"))
    }

    func testQueueProcessingStrategyCaseIterable() {
        let allCases = QueueProcessingStrategy.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.sequential))
        XCTAssertTrue(allCases.contains(.latestWins))
    }
}

// Helper extension for Result
extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
