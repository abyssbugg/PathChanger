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
        runsDeviceIntegrationTests(environment: ProcessInfo.processInfo.environment)
    }

    static func runsDeviceIntegrationTests(environment: [String: String]) -> Bool {
        environment["PATHCHANGER_RUN_DEVICE_TESTS"] == "1"
    }

    static func skipDeviceIntegrationTestsUnlessEnabled(
        _ reason: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if !runsDeviceIntegrationTests(environment: environment) {
            throw XCTSkip("""
            Skipping device/privileged integration test. \(reason)
            Set PATHCHANGER_RUN_DEVICE_TESTS=1 on a prepared macOS host with device access to enable it.
            """)
        }
    }
}

final class PathChangerTestEnvironmentTests: XCTestCase {
    func testDeviceIntegrationRequiresExactOptIn() {
        XCTAssertFalse(PathChangerTestEnvironment.runsDeviceIntegrationTests(environment: [:]))
        XCTAssertFalse(PathChangerTestEnvironment.runsDeviceIntegrationTests(environment: [
            "PATHCHANGER_RUN_DEVICE_TESTS": "true",
        ]))
        XCTAssertTrue(PathChangerTestEnvironment.runsDeviceIntegrationTests(environment: [
            "PATHCHANGER_RUN_DEVICE_TESTS": "1",
        ]))
    }

    func testDeviceIntegrationSkipsByDefaultOnLocalHosts() {
        XCTAssertThrowsError(
            try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
                "Requires device access.",
                environment: [:]
            )
        ) { error in
            XCTAssertTrue(error is XCTSkip)
        }
    }

    func testDeviceIntegrationRunsWhenExplicitlyEnabled() {
        XCTAssertNoThrow(
            try PathChangerTestEnvironment.skipDeviceIntegrationTestsUnlessEnabled(
                "Requires device access.",
                environment: ["PATHCHANGER_RUN_DEVICE_TESTS": "1"]
            )
        )
    }
}
