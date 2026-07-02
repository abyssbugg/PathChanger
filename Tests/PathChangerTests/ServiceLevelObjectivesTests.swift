//
//  ServiceLevelObjectivesTests.swift
//  PathChangerTests
//
//  CI-enforced checks for production SLO thresholds.
//

import XCTest
@testable import PathChanger

final class ServiceLevelObjectivesTests: XCTestCase {

    func testStartupTimeThresholdIsExplicit() {
        XCTAssertEqual(ServiceLevelObjectives.startupTimeSecondsThreshold, 30.0, accuracy: 0.001)
    }

    func testTunnelAttachLatencyThresholdIsExplicit() {
        XCTAssertEqual(ServiceLevelObjectives.tunnelAttachLatencyMsThreshold, 50.0, accuracy: 0.001)
    }

    func testRecoverySuccessRateThresholdIsExplicit() {
        XCTAssertEqual(ServiceLevelObjectives.recoverySuccessRateThreshold, 0.90, accuracy: 0.0001)
    }

    func testStartupTimeEvaluationBoundaries() {
        XCTAssertTrue(ServiceLevelObjectives.evaluateStartupTime(29.9).passed)
        XCTAssertTrue(ServiceLevelObjectives.evaluateStartupTime(30.0).passed)
        XCTAssertFalse(ServiceLevelObjectives.evaluateStartupTime(30.1).passed)
    }

    func testTunnelAttachLatencyEvaluationBoundaries() {
        XCTAssertTrue(ServiceLevelObjectives.evaluateTunnelAttachLatency(49.9).passed)
        XCTAssertTrue(ServiceLevelObjectives.evaluateTunnelAttachLatency(50.0).passed)
        XCTAssertFalse(ServiceLevelObjectives.evaluateTunnelAttachLatency(50.1).passed)
    }

    func testRecoverySuccessRateEvaluationBoundaries() {
        XCTAssertTrue(
            ServiceLevelObjectives.evaluateRecoverySuccessRate(successfulRecoveries: 9, totalAttempts: 10).passed
        )
        XCTAssertFalse(
            ServiceLevelObjectives.evaluateRecoverySuccessRate(successfulRecoveries: 8, totalAttempts: 10).passed
        )
        XCTAssertTrue(
            ServiceLevelObjectives.evaluateRecoverySuccessRate(successfulRecoveries: 0, totalAttempts: 0).passed
        )
    }

    @MainActor
    func testStartupAcquisitionTimeoutUsesSLOForUserFacingModes() async {
        let manager = TunneldManager.shared
        XCTAssertEqual(manager.startupAcquisitionTimeout(for: .usb), ServiceLevelObjectives.startupTimeSecondsThreshold)
        XCTAssertEqual(manager.startupAcquisitionTimeout(for: .wifi), ServiceLevelObjectives.startupTimeSecondsThreshold)
        XCTAssertEqual(manager.startupAcquisitionTimeout(for: .auto), ServiceLevelObjectives.startupTimeSecondsThreshold)
    }
}
