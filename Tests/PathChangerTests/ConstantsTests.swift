//
//  ConstantsTests.swift
//  PathChangerTests
//
//  Tests for Constants.swift (CODE-001)
//

import XCTest
@testable import PathChanger

// MARK: - Rate Limiting Constants Tests

final class RateLimitingConstantsTests: XCTestCase {

    func testTokenBucketCapacityIsPositive() {
        XCTAssertGreaterThan(AppConstants.RateLimiting.tokenBucketCapacity, 0)
    }

    func testTokenRefillRateIsPositive() {
        XCTAssertGreaterThan(AppConstants.RateLimiting.tokenRefillRate, 0)
    }

    func testMinimumIntervalIsPositive() {
        XCTAssertGreaterThan(AppConstants.RateLimiting.minimumIntervalMs, 0)
    }

    func testMaxQueueSizeIsReasonable() {
        XCTAssertGreaterThan(AppConstants.RateLimiting.maxQueueSize, 0)
        XCTAssertLessThanOrEqual(AppConstants.RateLimiting.maxQueueSize, 1000)
    }

    func testQueueThresholdsAreOrdered() {
        XCTAssertLessThan(
            AppConstants.RateLimiting.queueWarningThreshold,
            AppConstants.RateLimiting.queueCriticalThreshold
        )
    }
}

// MARK: - Priority Limits Constants Tests

final class PriorityLimitsConstantsTests: XCTestCase {

    func testPriorityLimitsArePositive() {
        XCTAssertGreaterThan(AppConstants.PriorityLimits.highPriorityMaxCount, 0)
        XCTAssertGreaterThan(AppConstants.PriorityLimits.normalPriorityMaxCount, 0)
        XCTAssertGreaterThan(AppConstants.PriorityLimits.lowPriorityMaxCount, 0)
    }

    func testHighPriorityIsLimited() {
        // High priority should be most limited to prevent abuse
        XCTAssertLessThan(
            AppConstants.PriorityLimits.highPriorityMaxCount,
            AppConstants.PriorityLimits.normalPriorityMaxCount
        )
    }

    func testPriorityRateLimitsArePositive() {
        XCTAssertGreaterThan(AppConstants.PriorityLimits.highPriorityRateLimit, 0)
        XCTAssertGreaterThan(AppConstants.PriorityLimits.normalPriorityRateLimit, 0)
        XCTAssertGreaterThan(AppConstants.PriorityLimits.lowPriorityRateLimit, 0)
    }
}

// MARK: - Tunnel Constants Tests

final class TunnelConstantsTests: XCTestCase {

    func testDefaultPortIsInUserRange() {
        XCTAssertGreaterThanOrEqual(
            AppConstants.Tunnel.defaultPort,
            AppConstants.Tunnel.minUserPort
        )
        XCTAssertLessThanOrEqual(
            AppConstants.Tunnel.defaultPort,
            AppConstants.Tunnel.maxPort
        )
    }

    func testPortRangeIsValid() {
        XCTAssertLessThan(AppConstants.Tunnel.minUserPort, AppConstants.Tunnel.maxPort)
        XCTAssertEqual(AppConstants.Tunnel.maxPort, 65535)
    }

    func testTimeoutsArePositive() {
        XCTAssertGreaterThan(AppConstants.Tunnel.connectionTimeout, 0)
        XCTAssertGreaterThan(AppConstants.Tunnel.retryDelay, 0)
    }
}

// MARK: - Health Monitoring Constants Tests

final class HealthMonitoringConstantsTests: XCTestCase {

    func testHealthCheckIntervalIsPositive() {
        XCTAssertGreaterThan(AppConstants.HealthMonitoring.healthCheckInterval, 0)
    }

    func testMaxConsecutiveFailuresIsPositive() {
        XCTAssertGreaterThan(AppConstants.HealthMonitoring.maxConsecutiveFailures, 0)
    }

    func testHealthCheckTimeoutExceedsInterval() {
        XCTAssertGreaterThan(
            AppConstants.HealthMonitoring.healthCheckTimeout,
            AppConstants.HealthMonitoring.healthCheckInterval
        )
    }
}

// MARK: - Process Management Constants Tests

final class ProcessManagementConstantsTests: XCTestCase {

    func testTimeoutsArePositive() {
        XCTAssertGreaterThan(AppConstants.ProcessManagement.defaultTimeout, 0)
        XCTAssertGreaterThan(AppConstants.ProcessManagement.extendedTimeout, 0)
    }

    func testExtendedTimeoutExceedsDefault() {
        XCTAssertGreaterThan(
            AppConstants.ProcessManagement.extendedTimeout,
            AppConstants.ProcessManagement.defaultTimeout
        )
    }

    func testMaxOutputSizeIsReasonable() {
        XCTAssertGreaterThan(AppConstants.ProcessManagement.maxOutputSize, 1024)
        XCTAssertLessThanOrEqual(AppConstants.ProcessManagement.maxOutputSize, 100 * 1024 * 1024)
    }
}

// MARK: - Validation Constants Tests

final class ValidationConstantsTests: XCTestCase {

    func testCoordinateRangesAreValid() {
        XCTAssertEqual(AppConstants.Validation.latitudeMin, -90.0)
        XCTAssertEqual(AppConstants.Validation.latitudeMax, 90.0)
        XCTAssertEqual(AppConstants.Validation.longitudeMin, -180.0)
        XCTAssertEqual(AppConstants.Validation.longitudeMax, 180.0)
    }

    func testUdidLengthsAreValid() {
        XCTAssertEqual(AppConstants.Validation.legacyUdidLength, 40)
        XCTAssertEqual(AppConstants.Validation.modernUdidLength, 25)
    }

    func testMaxLengthsArePositive() {
        XCTAssertGreaterThan(AppConstants.Validation.maxArgumentLength, 0)
        XCTAssertGreaterThan(AppConstants.Validation.maxPathLength, 0)
    }
}

// MARK: - Simulation Constants Tests

final class SimulationConstantsTests: XCTestCase {

    func testEarthRadiusIsCorrect() {
        // Earth's mean radius is approximately 6,371 km
        XCTAssertEqual(AppConstants.Simulation.earthRadiusMeters, 6_371_000.0, accuracy: 1000)
    }

    func testMaxMoveDistanceIsReasonable() {
        XCTAssertGreaterThan(AppConstants.Simulation.maxMoveDistanceMeters, 0)
        XCTAssertLessThanOrEqual(AppConstants.Simulation.maxMoveDistanceMeters, 200_000) // Max 200km
    }

    func testUpdateIntervalsAreValid() {
        XCTAssertGreaterThan(AppConstants.Simulation.defaultUpdateInterval, 0)
        XCTAssertGreaterThan(AppConstants.Simulation.minimumUpdateInterval, 0)
        XCTAssertLessThanOrEqual(
            AppConstants.Simulation.minimumUpdateInterval,
            AppConstants.Simulation.defaultUpdateInterval
        )
    }
}

// MARK: - Reliability Constants Tests

final class ReliabilityConstantsTests: XCTestCase {

    func testReconnectionConfigIsValid() {
        XCTAssertGreaterThan(AppConstants.Reliability.maxReconnectionAttempts, 0)
        XCTAssertGreaterThan(AppConstants.Reliability.initialReconnectionDelay, 0)
        XCTAssertGreaterThan(AppConstants.Reliability.maxReconnectionDelay, 0)
    }

    func testMaxDelayExceedsInitial() {
        XCTAssertGreaterThan(
            AppConstants.Reliability.maxReconnectionDelay,
            AppConstants.Reliability.initialReconnectionDelay
        )
    }

    func testBackoffMultiplierIsValid() {
        XCTAssertGreaterThan(AppConstants.Reliability.backoffMultiplier, 1.0)
    }

    func testJitterFactorIsInRange() {
        XCTAssertGreaterThanOrEqual(AppConstants.Reliability.jitterFactor, 0.0)
        XCTAssertLessThanOrEqual(AppConstants.Reliability.jitterFactor, 1.0)
    }

    func testCircuitBreakerConfigIsValid() {
        XCTAssertGreaterThan(AppConstants.Reliability.circuitBreakerFailureThreshold, 0)
        XCTAssertGreaterThan(AppConstants.Reliability.circuitBreakerSuccessThreshold, 0)
        XCTAssertGreaterThan(AppConstants.Reliability.circuitBreakerResetTimeout, 0)
    }
}

// MARK: - Device Cache Constants Tests

final class DeviceCacheConstantsTests: XCTestCase {

    func testCacheTTLsArePositive() {
        XCTAssertGreaterThan(AppConstants.DeviceCache.deviceInfoTTL, 0)
        XCTAssertGreaterThan(AppConstants.DeviceCache.deviceListTTL, 0)
    }

    func testDeviceInfoTTLExceedsListTTL() {
        // Device info should be cached longer than the list
        XCTAssertGreaterThanOrEqual(
            AppConstants.DeviceCache.deviceInfoTTL,
            AppConstants.DeviceCache.deviceListTTL
        )
    }

    func testMaxCacheEntriesIsReasonable() {
        XCTAssertGreaterThan(AppConstants.DeviceCache.maxCacheEntries, 0)
        XCTAssertLessThanOrEqual(AppConstants.DeviceCache.maxCacheEntries, 1000)
    }
}

// MARK: - UI Constants Tests

final class UIConstantsTests: XCTestCase {

    func testToastDurationIsReasonable() {
        XCTAssertGreaterThan(AppConstants.UI.toastDuration, 0)
        XCTAssertLessThanOrEqual(AppConstants.UI.toastDuration, 10)
    }

    func testAnimationDurationIsShort() {
        XCTAssertGreaterThan(AppConstants.UI.animationDuration, 0)
        XCTAssertLessThanOrEqual(AppConstants.UI.animationDuration, 1.0)
    }

    func testMaxRecentLocationsIsReasonable() {
        XCTAssertGreaterThan(AppConstants.UI.maxRecentLocations, 0)
        XCTAssertLessThanOrEqual(AppConstants.UI.maxRecentLocations, 100)
    }
}

// MARK: - Security Constants Tests

final class SecurityConstantsTests: XCTestCase {

    func testAllowedPythonPathsAreAbsolute() {
        for path in SecurityConstants.allowedPythonPaths {
            XCTAssertTrue(path.hasPrefix("/"), "Python path should be absolute: \(path)")
        }
    }

    func testAllowedSubcommandsExist() {
        XCTAssertFalse(SecurityConstants.allowedSubcommands.isEmpty)
        XCTAssertTrue(SecurityConstants.allowedSubcommands.contains("developer"))
    }

    func testDangerousCharactersIncludesShellMetachars() {
        let dangerous = SecurityConstants.dangerousCharacters

        XCTAssertTrue(";".unicodeScalars.allSatisfy { dangerous.contains($0) })
        XCTAssertTrue("|".unicodeScalars.allSatisfy { dangerous.contains($0) })
        XCTAssertTrue("&".unicodeScalars.allSatisfy { dangerous.contains($0) })
        XCTAssertTrue("$".unicodeScalars.allSatisfy { dangerous.contains($0) })
    }

    func testMaxSecureOutputSizeIsReasonable() {
        XCTAssertGreaterThan(SecurityConstants.maxSecureOutputSize, 0)
        XCTAssertLessThanOrEqual(SecurityConstants.maxSecureOutputSize, 50 * 1024 * 1024)
    }
}
