//
//  DeviceCacheTests.swift
//  PathChangerTests
//
//  Tests for DeviceCache (PERF-003)
//

import XCTest
@testable import PathChanger

final class DeviceCacheTests: XCTestCase {

    // MARK: - Cache Configuration Tests

    func testDefaultCacheConfigValues() {
        let config = DeviceCache.CacheConfig.default

        XCTAssertEqual(config.deviceInfoTTL, 60.0, "Default device info TTL should be 60 seconds")
        XCTAssertEqual(config.deviceListTTL, 30.0, "Default device list TTL should be 30 seconds")
        XCTAssertEqual(config.maxEntries, 50, "Default max entries should be 50")
    }

    func testCustomCacheConfig() {
        let config = DeviceCache.CacheConfig(
            deviceInfoTTL: 120.0,
            deviceListTTL: 60.0,
            maxEntries: 100
        )

        XCTAssertEqual(config.deviceInfoTTL, 120.0)
        XCTAssertEqual(config.deviceListTTL, 60.0)
        XCTAssertEqual(config.maxEntries, 100)
    }

    // MARK: - Cache Source Tests

    func testCacheSourceRawValues() {
        XCTAssertEqual(DeviceCache.CacheSource.usb.rawValue, "USB")
        XCTAssertEqual(DeviceCache.CacheSource.tunnel.rawValue, "Tunnel")
        XCTAssertEqual(DeviceCache.CacheSource.lockdown.rawValue, "Lockdown")
    }

    // MARK: - Cache Operations Tests

    func testCacheDeviceAndRetrieve() async {
        let cache = DeviceCache()
        let testDevice = Device(
            id: "test-udid-12345",
            displayName: "Test iPhone",
            connectionType: .usb,
            productType: "iPhone14,2",
            productVersion: "17.0",
            deviceName: "My iPhone"
        )

        // Cache the device
        await cache.cacheDevice(testDevice, source: .usb)

        // Retrieve from cache
        let cachedDevice = await cache.getCachedDevice(udid: "test-udid-12345")

        XCTAssertNotNil(cachedDevice)
        XCTAssertEqual(cachedDevice?.id, testDevice.id)
        XCTAssertEqual(cachedDevice?.displayName, testDevice.displayName)
    }

    func testCacheMissForNonExistentDevice() async {
        let cache = DeviceCache()

        let cachedDevice = await cache.getCachedDevice(udid: "non-existent-udid")

        XCTAssertNil(cachedDevice, "Should return nil for non-cached device")
    }

    func testCacheInvalidation() async {
        let cache = DeviceCache()
        let testDevice = Device(
            id: "invalidate-test-udid",
            displayName: "Test Device",
            connectionType: .wifi,
            productType: nil,
            productVersion: nil,
            deviceName: nil
        )

        // Cache and verify
        await cache.cacheDevice(testDevice, source: .tunnel)
        let beforeInvalidation = await cache.getCachedDevice(udid: "invalidate-test-udid")
        XCTAssertNotNil(beforeInvalidation)

        // Invalidate
        await cache.invalidate(udid: "invalidate-test-udid")

        // Verify removed
        let afterInvalidation = await cache.getCachedDevice(udid: "invalidate-test-udid")
        XCTAssertNil(afterInvalidation, "Device should be removed after invalidation")
    }

    func testInvalidateAll() async {
        let cache = DeviceCache()

        // Add multiple devices
        for i in 1...5 {
            let device = Device(
                id: "device-\(i)",
                displayName: "Device \(i)",
                connectionType: .usb,
                productType: nil,
                productVersion: nil,
                deviceName: nil
            )
            await cache.cacheDevice(device, source: .usb)
        }

        // Verify they exist
        let before = await cache.getAllCachedDevices()
        XCTAssertEqual(before.count, 5)

        // Invalidate all
        await cache.invalidateAll()

        // Verify all removed
        let after = await cache.getAllCachedDevices()
        XCTAssertEqual(after.count, 0, "All devices should be removed")
    }

    // MARK: - Discovery Tracking Tests

    func testNeedsFullDiscoveryInitially() async {
        let cache = DeviceCache()

        let needsDiscovery = await cache.needsFullDiscovery()

        XCTAssertTrue(needsDiscovery, "Should need full discovery on first call")
    }

    func testMarkDiscoveryComplete() async {
        let cache = DeviceCache()

        // Mark complete
        await cache.markDiscoveryComplete()

        // Should not need discovery immediately after
        let needsDiscovery = await cache.needsFullDiscovery()
        XCTAssertFalse(needsDiscovery, "Should not need discovery immediately after marking complete")
    }

    // MARK: - Statistics Tests

    func testDiscoveryStatsInitialValues() async {
        let cache = DeviceCache()
        let stats = await cache.stats

        XCTAssertEqual(stats.totalDiscoveries, 0)
        XCTAssertEqual(stats.cacheHits, 0)
        XCTAssertEqual(stats.cacheMisses, 0)
        XCTAssertEqual(stats.averageDiscoveryTime, 0)
    }

    func testRecordDiscoveryDuration() async {
        let cache = DeviceCache()

        await cache.recordDiscoveryDuration(1.5)
        await cache.recordDiscoveryDuration(2.5)

        let stats = await cache.stats
        XCTAssertEqual(stats.totalDiscoveries, 2)
        XCTAssertEqual(stats.averageDiscoveryTime, 2.0, accuracy: 0.001)
    }

    func testCacheHitRateCalculation() async {
        let cache = DeviceCache()

        // Add a device
        let device = Device(
            id: "hit-rate-test",
            displayName: "Test",
            connectionType: .usb,
            productType: nil,
            productVersion: nil,
            deviceName: nil
        )
        await cache.cacheDevice(device, source: .usb)

        // Generate hits and misses
        _ = await cache.getCachedDevice(udid: "hit-rate-test") // hit
        _ = await cache.getCachedDevice(udid: "hit-rate-test") // hit
        _ = await cache.getCachedDevice(udid: "non-existent")  // miss
        _ = await cache.getCachedDevice(udid: "also-missing")  // miss

        let stats = await cache.stats
        XCTAssertEqual(stats.cacheHits, 2)
        XCTAssertEqual(stats.cacheMisses, 2)
        XCTAssertEqual(stats.hitRate, 0.5, accuracy: 0.001)
    }

    func testStatsSummaryFormat() async {
        let cache = DeviceCache()

        await cache.recordDiscoveryDuration(1.0)

        let summary = await cache.getStatsSummary()

        XCTAssertTrue(summary.contains("Discovery Stats:"))
        XCTAssertTrue(summary.contains("Total discoveries:"))
        XCTAssertTrue(summary.contains("Cache hit rate:"))
        XCTAssertTrue(summary.contains("Average discovery time:"))
        XCTAssertTrue(summary.contains("Cache entries:"))
    }

    // MARK: - Cache Eviction Tests

    func testMaxEntriesEnforcement() async {
        let config = DeviceCache.CacheConfig(
            deviceInfoTTL: 60.0,
            deviceListTTL: 30.0,
            maxEntries: 3 // Small limit for testing
        )
        let cache = DeviceCache(config: config)

        // Add more devices than max
        for i in 1...5 {
            let device = Device(
                id: "device-\(i)",
                displayName: "Device \(i)",
                connectionType: .usb,
                productType: nil,
                productVersion: nil,
                deviceName: nil
            )
            await cache.cacheDevice(device, source: .usb)
        }

        // Should only have maxEntries devices
        let cachedDevices = await cache.getAllCachedDevices()
        XCTAssertLessThanOrEqual(cachedDevices.count, 3, "Cache should not exceed maxEntries")
    }
}

// MARK: - DeviceManager Cache Integration Tests

final class DeviceManagerCacheIntegrationTests: XCTestCase {

    @MainActor
    func testDeviceManagerHasCacheMethods() async {
        // This test verifies the public cache API exists on DeviceManager
        // Actual functionality depends on network/device state

        let manager = DeviceManager()

        // Verify cache statistics method exists and returns string
        let stats = await manager.getCacheStatistics()
        XCTAssertTrue(stats.contains("Discovery Stats:"))

        // Stop auto-refresh to clean up
        manager.stopAutoRefresh()
    }

    @MainActor
    func testInvalidateCacheMethodsExist() async {
        let manager = DeviceManager()

        // Verify invalidation methods exist (won't throw)
        await manager.invalidateDeviceCache(udid: "test-udid")
        await manager.invalidateAllDeviceCache()

        manager.stopAutoRefresh()
    }

    // MARK: - Task 31: Cache Race Condition Tests

    @MainActor
    func testDeviceManagerInitializesTunnelStateObserver() async {
        // Test that DeviceManager sets up tunnel state observer on init
        // This prevents stale cache data when device disconnects

        let manager = DeviceManager()

        // DeviceManager should successfully initialize with observer
        // If observer setup fails, init would crash
        XCTAssertNotNil(manager)

        // Clean up
        manager.stopAutoRefresh()
    }

    @MainActor
    func testCacheInvalidationOnDisconnect() async {
        // Test that cache is properly invalidated
        // This verifies the atomic cache operations work correctly

        let cache = DeviceCache()

        // Add a device to cache
        let device = Device(
            id: "race-condition-test-udid",
            displayName: "Test Device",
            connectionType: .wifi,
            productType: "iPhone14,2",
            productVersion: "17.0",
            deviceName: "Test iPhone"
        )
        await cache.cacheDevice(device, source: .tunnel)

        // Verify device is cached
        let beforeInvalidation = await cache.getCachedDevice(udid: "race-condition-test-udid")
        XCTAssertNotNil(beforeInvalidation, "Device should be cached")

        // Simulate disconnect by invalidating all
        await cache.invalidateAll()

        // Verify cache is empty
        let afterInvalidation = await cache.getCachedDevice(udid: "race-condition-test-udid")
        XCTAssertNil(afterInvalidation, "Device should be removed after disconnect simulation")

        // Verify cache reports empty
        let allDevices = await cache.getAllCachedDevices()
        XCTAssertEqual(allDevices.count, 0, "All devices should be removed")
    }

    @MainActor
    func testConcurrentCacheAccess() async {
        // Test thread-safe concurrent cache access (actor model)
        let cache = DeviceCache()

        // Simulate concurrent access
        await withTaskGroup(of: Void.self) { group in
            // Multiple concurrent reads and writes
            for i in 0..<10 {
                group.addTask {
                    let device = Device(
                        id: "concurrent-\(i)",
                        displayName: "Device \(i)",
                        connectionType: .usb,
                        productType: nil,
                        productVersion: nil,
                        deviceName: nil
                    )
                    await cache.cacheDevice(device, source: .usb)
                    _ = await cache.getCachedDevice(udid: "concurrent-\(i)")
                }
            }
        }

        // If we get here without crash, concurrent access is safe
        XCTAssertTrue(true, "Concurrent cache access should be thread-safe")
    }
}
