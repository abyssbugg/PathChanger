//
//  ReliabilityManagerTests.swift
//  PathChangerTests
//
//  Tests for ReliabilityManager (REL-001)
//

import XCTest
@testable import PathChanger

// MARK: - Reconnection Strategy Tests

final class ReconnectionStrategyTests: XCTestCase {

    func testDefaultStrategyValues() {
        let strategy = ReconnectionStrategy.default

        XCTAssertEqual(strategy.maxAttempts, 5)
        XCTAssertEqual(strategy.initialDelaySeconds, 1.0)
        XCTAssertEqual(strategy.maxDelaySeconds, 30.0)
        XCTAssertEqual(strategy.backoffMultiplier, 2.0)
        XCTAssertEqual(strategy.jitterFactor, 0.25)
    }

    func testAggressiveStrategyValues() {
        let strategy = ReconnectionStrategy.aggressive

        XCTAssertEqual(strategy.maxAttempts, 10)
        XCTAssertEqual(strategy.initialDelaySeconds, 0.5)
        XCTAssertEqual(strategy.maxDelaySeconds, 60.0)
        XCTAssertEqual(strategy.backoffMultiplier, 1.5)
        XCTAssertEqual(strategy.jitterFactor, 0.2)
    }

    func testConservativeStrategyValues() {
        let strategy = ReconnectionStrategy.conservative

        XCTAssertEqual(strategy.maxAttempts, 3)
        XCTAssertEqual(strategy.initialDelaySeconds, 2.0)
        XCTAssertEqual(strategy.maxDelaySeconds, 15.0)
        XCTAssertEqual(strategy.backoffMultiplier, 2.0)
        XCTAssertEqual(strategy.jitterFactor, 0.3)
    }

    func testExponentialBackoff() {
        let strategy = ReconnectionStrategy(
            maxAttempts: 5,
            initialDelaySeconds: 1.0,
            maxDelaySeconds: 100.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0 // No jitter for deterministic test
        )

        // Base delays without jitter: 1, 2, 4, 8, 16
        XCTAssertEqual(strategy.delayForAttempt(1), 1.0, accuracy: 0.001)
        XCTAssertEqual(strategy.delayForAttempt(2), 2.0, accuracy: 0.001)
        XCTAssertEqual(strategy.delayForAttempt(3), 4.0, accuracy: 0.001)
        XCTAssertEqual(strategy.delayForAttempt(4), 8.0, accuracy: 0.001)
        XCTAssertEqual(strategy.delayForAttempt(5), 16.0, accuracy: 0.001)
    }

    func testMaxDelayCap() {
        let strategy = ReconnectionStrategy(
            maxAttempts: 10,
            initialDelaySeconds: 1.0,
            maxDelaySeconds: 10.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0
        )

        // Attempt 5 would be 16s but capped at 10s
        XCTAssertEqual(strategy.delayForAttempt(5), 10.0, accuracy: 0.001)
        XCTAssertEqual(strategy.delayForAttempt(6), 10.0, accuracy: 0.001)
    }

    func testJitterApplied() {
        let strategy = ReconnectionStrategy(
            maxAttempts: 5,
            initialDelaySeconds: 10.0,
            maxDelaySeconds: 100.0,
            backoffMultiplier: 1.0, // Keep base delay constant
            jitterFactor: 0.2
        )

        // With 20% jitter on 10s delay, should be 8-12s
        var delays: [Double] = []
        for _ in 0..<100 {
            delays.append(strategy.delayForAttempt(1))
        }

        let minDelay = delays.min()!
        let maxDelay = delays.max()!

        XCTAssertGreaterThanOrEqual(minDelay, 7.9, "Min delay should be around 8s")
        XCTAssertLessThanOrEqual(maxDelay, 12.1, "Max delay should be around 12s")

        // Should have some variation
        let uniqueDelays = Set(delays.map { Int($0 * 100) })
        XCTAssertGreaterThan(uniqueDelays.count, 10, "Jitter should produce varied delays")
    }

    func testMinimumDelayFloor() {
        let strategy = ReconnectionStrategy(
            maxAttempts: 5,
            initialDelaySeconds: 0.2,
            maxDelaySeconds: 1.0,
            backoffMultiplier: 0.5, // Will decrease
            jitterFactor: 0.5
        )

        // Even with reduction, delay should be at least 0.1s
        for _ in 0..<50 {
            let delay = strategy.delayForAttempt(1)
            XCTAssertGreaterThanOrEqual(delay, 0.1, "Delay should never go below 0.1s")
        }
    }
}

// MARK: - Circuit Breaker Tests

final class CircuitBreakerTests: XCTestCase {

    func testInitialStateIsClosed() async {
        let breaker = CircuitBreaker()
        let stats = await breaker.getStats()

        XCTAssertEqual(stats.state, .closed)
    }

    func testAllowsRequestsWhenClosed() async {
        let breaker = CircuitBreaker()

        let allowed = await breaker.shouldAllowRequest()

        XCTAssertTrue(allowed)
    }

    func testOpensAfterFailureThreshold() async {
        let config = CircuitBreaker.Config(
            failureThreshold: 3,
            successThreshold: 2,
            resetTimeout: 30.0,
            monitoringWindow: 60.0
        )
        let breaker = CircuitBreaker(config: config)

        // Record failures
        await breaker.recordFailure()
        await breaker.recordFailure()

        var stats = await breaker.getStats()
        XCTAssertEqual(stats.state, .closed, "Should still be closed with 2 failures")

        await breaker.recordFailure() // 3rd failure

        stats = await breaker.getStats()
        XCTAssertEqual(stats.state, .open, "Should be open after 3 failures")
    }

    func testBlocksRequestsWhenOpen() async {
        let config = CircuitBreaker.Config(
            failureThreshold: 1,
            successThreshold: 1,
            resetTimeout: 30.0,
            monitoringWindow: 60.0
        )
        let breaker = CircuitBreaker(config: config)

        await breaker.recordFailure() // Opens the circuit

        let allowed = await breaker.shouldAllowRequest()

        XCTAssertFalse(allowed, "Should block requests when open")
    }

    func testResetClearsState() async {
        let config = CircuitBreaker.Config(
            failureThreshold: 2,
            successThreshold: 1,
            resetTimeout: 30.0,
            monitoringWindow: 60.0
        )
        let breaker = CircuitBreaker(config: config)

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        var stats = await breaker.getStats()
        XCTAssertEqual(stats.state, .open)

        // Reset
        await breaker.reset()

        stats = await breaker.getStats()
        XCTAssertEqual(stats.state, .closed, "Should be closed after reset")
        XCTAssertEqual(stats.failureCount, 0)
    }

    func testSuccessResetsFailureCount() async {
        let config = CircuitBreaker.Config(
            failureThreshold: 3,
            successThreshold: 1,
            resetTimeout: 30.0,
            monitoringWindow: 60.0
        )
        let breaker = CircuitBreaker(config: config)

        await breaker.recordFailure()
        await breaker.recordFailure()

        var stats = await breaker.getStats()
        XCTAssertEqual(stats.failureCount, 2)

        await breaker.recordSuccess()

        stats = await breaker.getStats()
        XCTAssertEqual(stats.failureCount, 0, "Success should reset failure count")
    }

    func testDefaultConfigValues() {
        let config = CircuitBreaker.Config.default

        XCTAssertEqual(config.failureThreshold, 5)
        XCTAssertEqual(config.successThreshold, 2)
        XCTAssertEqual(config.resetTimeout, 30.0)
        XCTAssertEqual(config.monitoringWindow, 60.0)
    }
}

// MARK: - Error Classification Tests

final class ErrorClassificationTests: XCTestCase {

    func testTransientErrorClassification() {
        XCTAssertTrue(ErrorClassification.transient.shouldRetry)
        XCTAssertEqual(ErrorClassification.transient.suggestedDelay, 0.5)
    }

    func testRetryableErrorClassification() {
        XCTAssertTrue(ErrorClassification.retryable.shouldRetry)
        XCTAssertEqual(ErrorClassification.retryable.suggestedDelay, 2.0)
    }

    func testPersistentErrorClassification() {
        XCTAssertFalse(ErrorClassification.persistent.shouldRetry)
        XCTAssertEqual(ErrorClassification.persistent.suggestedDelay, 10.0)
    }

    func testFatalErrorClassification() {
        XCTAssertFalse(ErrorClassification.fatal.shouldRetry)
        XCTAssertEqual(ErrorClassification.fatal.suggestedDelay, 0)
    }

    func testDeviceErrorClassification() {
        // Timeout should be transient
        let timeoutClass = ErrorClassifier.classify(DeviceError.timeout)
        XCTAssertEqual(timeoutClass, .transient)

        // Connection failed should be retryable
        let connFailClass = ErrorClassifier.classify(DeviceError.connectionFailed("test"))
        XCTAssertEqual(connFailClass, .retryable)

        // Device not found should be persistent
        let notFoundClass = ErrorClassifier.classify(DeviceError.deviceNotFound)
        XCTAssertEqual(notFoundClass, .persistent)

        // Developer mode should be fatal
        let devModeClass = ErrorClassifier.classify(DeviceError.developerModeDisabled)
        XCTAssertEqual(devModeClass, .fatal)
    }

    func testLocationInjectionErrorClassification() {
        // Timeout should be transient
        let timeoutClass = ErrorClassifier.classify(LocationInjectionError.timeout)
        XCTAssertEqual(timeoutClass, .transient)

        // Rate limited should be retryable
        let rateLimitClass = ErrorClassifier.classify(LocationInjectionError.rateLimited)
        XCTAssertEqual(rateLimitClass, .retryable)

        // Tunneld not running should be persistent
        let tunnelClass = ErrorClassifier.classify(LocationInjectionError.tunneldNotRunning)
        XCTAssertEqual(tunnelClass, .persistent)

        // Developer mode required should be fatal
        let devModeClass = ErrorClassifier.classify(LocationInjectionError.developerModeRequired)
        XCTAssertEqual(devModeClass, .fatal)
    }
}

// MARK: - Connection Recovery State Tests

final class ConnectionRecoveryStateTests: XCTestCase {

    func testConnectedState() {
        let state = ConnectionRecoveryState.connected

        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.displayText, "Connected")
    }

    func testDisconnectedState() {
        let state = ConnectionRecoveryState.disconnected

        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(state.displayText, "Disconnected")
    }

    func testReconnectingState() {
        let state = ConnectionRecoveryState.reconnecting(attempt: 2, maxAttempts: 5)

        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(state.displayText, "Reconnecting (2/5)...")
    }

    func testFailedState() {
        let state = ConnectionRecoveryState.failed(reason: "Network error")

        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(state.displayText, "Failed: Network error")
    }

    func testSuspendedState() {
        let state = ConnectionRecoveryState.suspended

        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(state.displayText, "Suspended")
    }

    func testStateEquality() {
        XCTAssertEqual(ConnectionRecoveryState.connected, ConnectionRecoveryState.connected)
        XCTAssertNotEqual(ConnectionRecoveryState.connected, ConnectionRecoveryState.disconnected)
        XCTAssertEqual(
            ConnectionRecoveryState.reconnecting(attempt: 1, maxAttempts: 3),
            ConnectionRecoveryState.reconnecting(attempt: 1, maxAttempts: 3)
        )
    }
}

// MARK: - Reliability Stats Tests

final class ReliabilityStatsTests: XCTestCase {

    func testStatsSummaryFormat() {
        let stats = ReliabilityStats(
            circuitBreakerState: .closed,
            consecutiveFailures: 2,
            failuresInWindow: 5,
            persistentFailureDetected: false,
            connectionUptime: 120.5,
            reconnectionAttempts: 3
        )

        let summary = stats.summary

        XCTAssertTrue(summary.contains("Circuit Breaker: closed"))
        XCTAssertTrue(summary.contains("Consecutive Failures: 2"))
        XCTAssertTrue(summary.contains("Failures (5 min window): 5"))
        XCTAssertTrue(summary.contains("Persistent Failure: false"))
        XCTAssertTrue(summary.contains("Connection Uptime:"))
        XCTAssertTrue(summary.contains("Reconnection Attempts: 3"))
    }
}

// MARK: - ReliabilityManager Integration Tests

final class ReliabilityManagerIntegrationTests: XCTestCase {

    @MainActor
    func testInitialState() async {
        let manager = ReliabilityManager()

        XCTAssertEqual(manager.recoveryState, .disconnected)
        XCTAssertTrue(manager.isAutoReconnectEnabled)
        XCTAssertFalse(manager.circuitBreakerOpen)
        XCTAssertFalse(manager.persistentFailureDetected)
    }

    @MainActor
    func testConnectionEstablished() async {
        let manager = ReliabilityManager()

        manager.connectionEstablished()

        XCTAssertEqual(manager.recoveryState, .connected)
        XCTAssertNotNil(manager.lastConnectionTime)
        XCTAssertEqual(manager.reconnectionAttempts, 0)
    }

    @MainActor
    func testSuspendAndResume() async {
        let manager = ReliabilityManager()
        manager.connectionEstablished()

        manager.suspend()
        XCTAssertEqual(manager.recoveryState, .suspended)

        manager.isAutoReconnectEnabled = false // Prevent actual reconnection
        manager.resume()
        XCTAssertEqual(manager.recoveryState, .disconnected)
    }

    @MainActor
    func testResetReliabilityState() async {
        let manager = ReliabilityManager()

        await manager.resetReliabilityState()

        XCTAssertFalse(manager.circuitBreakerOpen)
        XCTAssertFalse(manager.persistentFailureDetected)
    }

    @MainActor
    func testGetReliabilityStats() async {
        let manager = ReliabilityManager()

        let stats = await manager.getReliabilityStats()

        XCTAssertEqual(stats.circuitBreakerState, .closed)
        XCTAssertEqual(stats.consecutiveFailures, 0)
        XCTAssertFalse(stats.persistentFailureDetected)
    }
}
