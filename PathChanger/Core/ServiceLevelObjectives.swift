//
//  ServiceLevelObjectives.swift
//  PathChanger
//
//  Explicit production SLO thresholds and check evaluators.
//

import Foundation

enum SLOMetric: String, CaseIterable {
    case startupTime = "startup_time_seconds"
    case tunnelAttachLatency = "tunnel_attach_latency_ms"
    case recoverySuccessRate = "recovery_success_rate"
}

enum SLOComparison {
    case lessThanOrEqual
    case greaterThanOrEqual
}

struct SLOCheckResult: Equatable {
    let metric: SLOMetric
    let measuredValue: Double
    let thresholdValue: Double
    let comparison: SLOComparison
    let passed: Bool
}

enum ServiceLevelObjectives {
    /// Startup acquisition must complete within 30 seconds for user-facing modes.
    static let startupTimeSecondsThreshold: TimeInterval = 30.0

    /// Tunnel attach latency target in milliseconds.
    static let tunnelAttachLatencyMsThreshold: Double = 50.0

    /// Recovery success rate floor for automatic reconnect/recovery attempts.
    static let recoverySuccessRateThreshold: Double = 0.90

    static func evaluateStartupTime(_ seconds: TimeInterval) -> SLOCheckResult {
        let value = Double(seconds)
        return SLOCheckResult(
            metric: .startupTime,
            measuredValue: value,
            thresholdValue: startupTimeSecondsThreshold,
            comparison: .lessThanOrEqual,
            passed: value <= startupTimeSecondsThreshold
        )
    }

    static func evaluateTunnelAttachLatency(_ latencyMs: Double) -> SLOCheckResult {
        SLOCheckResult(
            metric: .tunnelAttachLatency,
            measuredValue: latencyMs,
            thresholdValue: tunnelAttachLatencyMsThreshold,
            comparison: .lessThanOrEqual,
            passed: latencyMs <= tunnelAttachLatencyMsThreshold
        )
    }

    static func evaluateRecoverySuccessRate(successfulRecoveries: Int, totalAttempts: Int) -> SLOCheckResult {
        let rate = totalAttempts == 0 ? 1.0 : Double(successfulRecoveries) / Double(totalAttempts)
        return SLOCheckResult(
            metric: .recoverySuccessRate,
            measuredValue: rate,
            thresholdValue: recoverySuccessRateThreshold,
            comparison: .greaterThanOrEqual,
            passed: rate >= recoverySuccessRateThreshold
        )
    }
}
