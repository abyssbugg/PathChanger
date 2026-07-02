//
//  TunnelHealthMonitor.swift
//  PathChanger
//
//  Monitors tunnel connection health and manages persistent connections
//  Target: <50ms latency, automatic failover, connection pooling
//

import Foundation
import Combine

// MARK: - Tunnel Health Status

enum TunnelHealthStatus: Equatable {
    case healthy
    case degraded(reason: String)
    case critical(reason: String)
    case disconnected

    var isHealthy: Bool {
        if case .healthy = self {
            return true
        }
        return false
    }
}

// MARK: - Connection Metrics

struct ConnectionMetrics {
    var averageLatencyMs: Double = 0
    var maxLatencyMs: Double = 0
    var minLatencyMs: Double = Double.infinity
    var successfulPings: Int = 0
    var failedPings: Int = 0
    var consecutiveFailures: Int = 0
    var lastPingTime: Date?
    var uptime: TimeInterval = 0

    var successRate: Double {
        let total = successfulPings + failedPings
        guard total > 0 else { return 0 }
        return Double(successfulPings) / Double(total) * 100
    }

    mutating func recordPing(latencyMs: Double, success: Bool) {
        if success {
            successfulPings += 1
            consecutiveFailures = 0

            // Update latency stats
            if latencyMs > maxLatencyMs {
                maxLatencyMs = latencyMs
            }
            if latencyMs < minLatencyMs {
                minLatencyMs = latencyMs
            }

            // Rolling average
            let alpha = 0.2 // Weight for new value
            if averageLatencyMs == 0 {
                averageLatencyMs = latencyMs
            } else {
                averageLatencyMs = averageLatencyMs * (1 - alpha) + latencyMs * alpha
            }
        } else {
            failedPings += 1
            consecutiveFailures += 1
        }

        lastPingTime = Date()
    }

    mutating func reset() {
        averageLatencyMs = 0
        maxLatencyMs = 0
        minLatencyMs = Double.infinity
        successfulPings = 0
        failedPings = 0
        consecutiveFailures = 0
        lastPingTime = nil
        uptime = 0
    }
}

// MARK: - Tunnel Health Monitor

@MainActor
class TunnelHealthMonitor: ObservableObject {
    @Published private(set) var healthStatus: TunnelHealthStatus = .disconnected
    @Published private(set) var metrics: ConnectionMetrics = ConnectionMetrics()
    @Published private(set) var recommendUSBFallback: Bool = false

    private var healthCheckTask: Task<Void, Never>?
    private var connectionStartTime: Date?
    private let healthCheckInterval: TimeInterval = 2.0 // Check every 2 seconds (reduced from 5s for faster detection)
    private let latencyThreshold: Double = ServiceLevelObjectives.tunnelAttachLatencyMsThreshold
    private let degradedLatencyThreshold: Double = ServiceLevelObjectives.tunnelAttachLatencyMsThreshold * 2
    private let maxConsecutiveFailures: Int = 3

    // MARK: Failure notification
    private var onFailureDetected: (() -> Void)?

    // MARK: Monitoring Control

    func startMonitoring() {
        stopMonitoring()
        connectionStartTime = Date()

        healthCheckTask = Task {
            while !Task.isCancelled {
                await performHealthCheck()

                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        connectionStartTime = nil
        healthStatus = .disconnected
    }

    // MARK: Failure Notification

    func setFailureNotificationHandler(_ handler: @escaping () -> Void) {
        onFailureDetected = handler
    }

    // MARK: Health Check

    private func performHealthCheck() async {
        guard TunneldManager.shared.isRunning else {
            healthStatus = .disconnected
            metrics.reset()
            return
        }

        // Update uptime
        if let startTime = connectionStartTime {
            metrics.uptime = Date().timeIntervalSince(startTime)
        }

        // Perform ping by checking tunnel info availability
        let startTime = Date()
        let pingSuccessful = await checkTunnelConnectivity()
        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Record metrics
        metrics.recordPing(latencyMs: latencyMs, success: pingSuccessful)

        // Evaluate health status
        evaluateHealthStatus(latencyMs: latencyMs, pingSuccess: pingSuccessful)
    }

    private func checkTunnelConnectivity() async -> Bool {
        // Mode-aware health: in daemon mode the live RSD is served per-device
        // from the tunneld HTTP API (deviceTunnelInfo), not the legacy
        // log-parsed tunnelInfo. Delegating keeps the USB and daemon paths
        // correct from a single source of truth and avoids false
        // "connectivity lost" flips while injection still works.
        return TunneldManager.shared.currentTunnelConnectivityHealthy()
    }

    private func evaluateHealthStatus(latencyMs: Double, pingSuccess: Bool) {
        if !pingSuccess {
            if metrics.consecutiveFailures >= maxConsecutiveFailures {
                healthStatus = .critical(reason: "\(metrics.consecutiveFailures) consecutive ping failures")
                recommendUSBFallback = true
                // Immediately notify of critical failure
                onFailureDetected?()
                Logger.error("🔴 CRITICAL: Tunnel connectivity lost after \(metrics.consecutiveFailures) failed pings", category: .device)
            } else {
                healthStatus = .degraded(reason: "Ping failed (attempt \(metrics.consecutiveFailures)/\(maxConsecutiveFailures))")
                Logger.error("🟡 Tunnel connectivity degraded: \(metrics.consecutiveFailures)/\(maxConsecutiveFailures) failures", category: .device)
            }
            return
        }

        // Reset USB fallback recommendation on success
        if recommendUSBFallback && metrics.consecutiveFailures == 0 {
            recommendUSBFallback = false
        }

        // Evaluate latency
        if latencyMs > degradedLatencyThreshold {
            healthStatus = .degraded(reason: String(format: "High latency: %.1fms", latencyMs))

            // Recommend USB fallback for WiFi connections with high latency
            if TunneldManager.shared.activeMode == .wifi {
                recommendUSBFallback = true
            }
        } else if latencyMs > latencyThreshold {
            healthStatus = .degraded(reason: String(format: "Elevated latency: %.1fms", latencyMs))
        } else {
            healthStatus = .healthy
        }
    }

    // MARK: Statistics

    func getHealthReport() -> String {
        var report = """
        Tunnel Health Report
        ====================
        Status: \(healthStatus)
        Uptime: \(String(format: "%.1f", metrics.uptime))s

        Latency Stats:
        - Average: \(String(format: "%.1f", metrics.averageLatencyMs))ms
        - Min: \(String(format: "%.1f", metrics.minLatencyMs))ms
        - Max: \(String(format: "%.1f", metrics.maxLatencyMs))ms

        Ping Stats:
        - Success Rate: \(String(format: "%.1f", metrics.successRate))%
        - Successful: \(metrics.successfulPings)
        - Failed: \(metrics.failedPings)
        - Consecutive Failures: \(metrics.consecutiveFailures)
        """

        if recommendUSBFallback {
            report += "\n\n⚠️  USB fallback recommended for better performance"
        }

        return report
    }

    func resetMetrics() {
        metrics.reset()
        recommendUSBFallback = false
    }
}
