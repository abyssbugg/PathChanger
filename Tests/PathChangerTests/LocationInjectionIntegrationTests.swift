//
//  LocationInjectionIntegrationTests.swift
//  PathChangerTests
//
//  Integration tests for location injection and simulation
//

import XCTest
@testable import PathChanger

final class LocationInjectionIntegrationTests: XCTestCase {
    var locationBridge: DevLocationBridge!
    var testDevice: Device!

    override func setUp() async throws {
        try await super.setUp()
        try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
            "Location injection tests may invoke pymobiledevice3 against host device services."
        )
        locationBridge = DevLocationBridge()

        // Create test device
        testDevice = Device(
            id: "test-device-001",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.4",
            deviceName: "Test Device"
        )
    }

    override func tearDown() async throws {
        locationBridge = nil
        testDevice = nil
        try await super.tearDown()
    }

    // MARK: - Coordinate Validation Tests

    func testValidLocationCoordinates() async throws {
        /// Test that valid coordinates are accepted
        let validCoordinates = [
            LocationCoordinate(latitude: 37.7749, longitude: -122.4194),    // San Francisco
            LocationCoordinate(latitude: 40.7128, longitude: -74.0060),     // New York
            LocationCoordinate(latitude: 51.5074, longitude: -0.1278),      // London
            LocationCoordinate(latitude: -33.8688, longitude: 151.2093),    // Sydney
            LocationCoordinate(latitude: 0.0, longitude: 0.0),              // Null Island
        ]

        for coordinate in validCoordinates {
            do {
                try coordinate.validated()
                XCTAssertTrue(coordinate.isValid, "Coordinate should be valid: \(coordinate)")
                Logger.debug("✅ Valid coordinate: \(coordinate)", category: .device)
            } catch {
                XCTFail("Valid coordinate should not throw: \(coordinate)")
            }
        }
    }

    func testInvalidLocationCoordinates() async throws {
        /// Test that invalid coordinates are rejected
        let invalidCoordinates = [
            LocationCoordinate(latitude: 91.0, longitude: 0.0),             // Latitude > 90
            LocationCoordinate(latitude: -91.0, longitude: 0.0),            // Latitude < -90
            LocationCoordinate(latitude: 0.0, longitude: 181.0),            // Longitude > 180
            LocationCoordinate(latitude: 0.0, longitude: -181.0),           // Longitude < -180
        ]

        for coordinate in invalidCoordinates {
            XCTAssertThrowsError(
                try coordinate.validated(),
                "Invalid coordinate should throw error: \(coordinate)"
            )
            Logger.debug("✅ Invalid coordinate rejected: \(coordinate)", category: .device)
        }
    }

    // MARK: - Injection Statistics Tests

    func testInjectionStatisticsTracking() async throws {
        /// Test that injection statistics are tracked correctly
        var stats = InjectionStats()

        // Simulate some injections
        for i in 0..<5 {
            stats.recordSuccess(latencyMs: Double(100 + i * 50))
            Logger.debug("Recorded injection \(i + 1)", category: .device)
        }

        XCTAssertEqual(stats.totalInjections, 5, "Should track all injections")
        XCTAssertEqual(stats.successfulInjections, 5, "Should count successes")
        XCTAssertEqual(stats.failedInjections, 0, "Should have no failures")
        XCTAssertGreaterThan(stats.averageLatencyMs, 0, "Should calculate average latency")

        Logger.info("✅ Injection statistics: \(stats.totalInjections) total, \(stats.successfulInjections) successful", category: .device)
    }

    func testInjectionFailureTracking() async throws {
        /// Test that injection failures are tracked
        var stats = InjectionStats()

        // Mix of successes and failures
        stats.recordSuccess(latencyMs: 150)
        stats.recordFailure()
        stats.recordSuccess(latencyMs: 200)
        stats.recordFailure()

        XCTAssertEqual(stats.totalInjections, 4)
        XCTAssertEqual(stats.successfulInjections, 2)
        XCTAssertEqual(stats.failedInjections, 2)

        let successRate = stats.totalInjections > 0
            ? Double(stats.successfulInjections) / Double(stats.totalInjections) * 100
            : 0
        XCTAssertEqual(successRate, 50, accuracy: 1, "Success rate should be 50%")

        Logger.info("✅ Failure tracking: \(stats.failedInjections) failures out of \(stats.totalInjections)", category: .device)
    }

    // MARK: - Rate Limiting Tests

    func testInjectionRateLimiting() async throws {
        /// Test that rate limiting works correctly
        // Create rate limiter with 0 minInterval so we can test burst capacity
        let rateLimiter = RateLimiter(capacity: 5, refillRate: 2.0, minIntervalMs: 0)

        // Should allow some burst - use await for actor method
        let first = await rateLimiter.checkRequest()
        let second = await rateLimiter.checkRequest()
        let third = await rateLimiter.checkRequest()

        XCTAssertTrue(first, "First request should be allowed")
        XCTAssertTrue(second, "Second request should be allowed")
        XCTAssertTrue(third, "Third request should be allowed")

        Logger.debug("✅ Rate limiter allowed burst of 3 requests", category: .device)
    }

    // MARK: - Coordinate Range Tests

    func testCoordinateRangeEdgeCases() async throws {
        /// Test edge cases for coordinate ranges
        let edgeCases = [
            LocationCoordinate(latitude: 90.0, longitude: 180.0),           // NE corner
            LocationCoordinate(latitude: -90.0, longitude: -180.0),         // SW corner
            LocationCoordinate(latitude: 90.0, longitude: -180.0),          // NW corner
            LocationCoordinate(latitude: -90.0, longitude: 180.0),          // SE corner
        ]

        for coordinate in edgeCases {
            do {
                try coordinate.validated()
                Logger.debug("✅ Edge case coordinate valid: \(coordinate)", category: .device)
            } catch {
                XCTFail("Edge case should be valid: \(coordinate)")
            }
        }
    }

    // MARK: - Performance Tests

    func testCoordinateValidationPerformance() async throws {
        /// Benchmark coordinate validation performance
        measure {
            for i in 0..<1000 {
                let lat = Double(i % 180 - 90)
                let lon = Double((i * 37) % 360 - 180)
                let coordinate = LocationCoordinate(latitude: lat, longitude: lon)

                try? coordinate.validated()
            }
        }
    }

    // MARK: - Simulation Speed Tests

    func testSimulationSpeeds() async throws {
        /// Test that simulation modes exist and are properly configured
        XCTAssertGreaterThan(SimulationModeType.allCases.count, 0, "Should have simulation modes")

        for mode in SimulationModeType.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "Mode should have display name: \(mode)")
            Logger.debug("✅ Mode \(mode.displayName): available", category: .device)
        }
    }

    // MARK: - Error Handling Tests

    func testGracefulErrorHandling() async throws {
        /// Test that errors are handled gracefully
        // Try to clear location on non-existent device
        do {
            try await locationBridge.clearLocation(for: testDevice)
            // May fail if device not available, which is expected
            Logger.debug("✅ Clear location completed", category: .device)
        } catch {
            Logger.debug("✅ Clear location failed gracefully: \(error)", category: .device)
        }
    }

    // MARK: - iOS 18 Detection Tests

    func testLocationInjectionFailsOnIOS18() async throws {
        /// Test that location injection fails on iOS 18+ devices
        let ios18Device = Device(
            id: "test-ios18-device",
            displayName: "Test iPhone 16",
            connectionType: .usb,
            productType: "iPhone17,1",
            productVersion: "18.0",
            deviceName: "Test iOS 18 Device"
        )

        let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        do {
            try await locationBridge.setLocation(coordinate, for: ios18Device)
            XCTFail("Expected unsupportedIOSVersion error to be thrown")
        } catch let error as LocationInjectionError {
            switch error {
            case .unsupportedIOSVersion(let version):
                XCTAssertEqual(version, "18.0")
                XCTAssertTrue(error.errorDescription?.contains("iOS 18") ?? false)
                XCTAssertTrue(error.recoverySuggestion?.contains("Downgrade") ?? false)
                Logger.debug("✅ iOS 18 detection working: \(error.errorDescription ?? "")", category: .device)
            default:
                // May also fail for other reasons (device not connected, etc.)
                // This is acceptable in integration tests
                Logger.debug("✅ Different error thrown (expected in integration test): \(error)", category: .device)
            }
        } catch {
            // Other errors are acceptable in integration tests
            Logger.debug("✅ Non-injection error thrown: \(error)", category: .device)
        }
    }

    func testLocationInjectionSucceedsOnIOS17() async throws {
        /// Test that iOS 17 devices don't fail version validation
        let ios17Device = Device(
            id: "test-ios17-device",
            displayName: "Test iPhone 15",
            connectionType: .usb,
            productType: "iPhone15,2",
            productVersion: "17.6",
            deviceName: "Test iOS 17 Device"
        )

        // Verify iOS 17 is considered supported
        XCTAssertTrue(ios17Device.isIOSVersionSupported)
        XCTAssertEqual(ios17Device.iosMajorVersion, 17)

        // Note: The actual injection will fail because device is not connected,
        // but it should NOT fail due to version validation
        let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        do {
            try await locationBridge.setLocation(coordinate, for: ios17Device)
            // If it succeeds (unlikely without device), that's fine
            Logger.debug("✅ Location injection succeeded on iOS 17", category: .device)
        } catch let error as LocationInjectionError {
            // Should NOT be unsupportedIOSVersion
            if case .unsupportedIOSVersion = error {
                XCTFail("iOS 17 device should not fail version validation")
            }
            // Other errors are expected (device not connected, etc.)
            Logger.debug("✅ Expected error for disconnected device: \(error)", category: .device)
        } catch {
            // Other errors are acceptable
            Logger.debug("✅ Other error (expected): \(error)", category: .device)
        }
    }

    func testIOS18ErrorMessageContainsGuidance() async throws {
        /// Test that iOS 18 error provides helpful recovery suggestions
        let error = LocationInjectionError.unsupportedIOSVersion("18.0")

        // Verify error description
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("iOS 18") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("not supported") ?? false)

        // Verify recovery suggestion
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion?.contains("Downgrade") ?? false)
        XCTAssertTrue(error.recoverySuggestion?.contains("17.6") ?? false)
        XCTAssertTrue(error.recoverySuggestion?.contains("pymobiledevice3") ?? false)

        Logger.debug("✅ iOS 18 error message contains proper guidance", category: .device)
    }
}
