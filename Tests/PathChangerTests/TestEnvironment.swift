//
//  TestEnvironment.swift
//  PathChangerTests
//
//  Shared test-environment helpers.
//

import XCTest

enum PathChangerTestEnvironment {
    static var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true"
    }

    static var runsDeviceIntegrationTests: Bool {
        ProcessInfo.processInfo.environment["PATHCHANGER_RUN_DEVICE_TESTS"] == "1"
    }

    static func skipDeviceIntegrationTestsUnlessEnabled(_ reason: String) throws {
        if isCI && !runsDeviceIntegrationTests {
            throw XCTSkip("""
            Skipping device/privileged integration test in CI. \(reason)
            Set PATHCHANGER_RUN_DEVICE_TESTS=1 on a prepared macOS runner with device access to enable it.
            """)
        }
    }
}
