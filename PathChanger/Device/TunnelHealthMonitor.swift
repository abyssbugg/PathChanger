//
//  TunnelHealthMonitor.swift
//  PathChanger
//
//  Monitors tunnel connection health and manages persistent connections
//  Target: <50ms latency, automatic failover, connection pooling
//

import Foundation
import Combine
import Network

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

// MARK: - Tunnel Endpoint Probing

/// Probes whether a tunnel's RSD endpoint is actually reachable.
///
/// A `--native` pymobiledevice3 tunnel process can stay alive after the underlying
/// Apple/remotepairingd tunnel dies (phone locked, Wi-Fi dropped), so a live PID does
/// not mean a usable tunnel. Health checks probe the RSD endpoint when tunnel info
/// carries one and treat an unreachable endpoint exactly like a failed liveness check.
protocol TunnelEndpointProbing {
    func isReachable(host: String, port: Int, timeoutSeconds: Double) async -> Bool
}

/// TCP reachability probe built on Network.framework.
///
/// Opens a connection to the endpoint and lets the TCP handshake be the probe — no
/// payload is sent. Resolves `true` from `.ready`; `false` from `.failed`, `.waiting`,
/// or the timeout, whichever comes first. All completion paths run on one serial queue
/// so the continuation is resumed exactly once.
struct NWConnectionEndpointProber: TunnelEndpointProbing {
    func isReachable(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }

        let connection = NWConnection(
            to: NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: .tcp
        )
        let probeQueue = DispatchQueue(label: "com.pathchanger.tunnelhealth.endpointprobe")

        return await withCheckedContinuation { continuation in
            var completed = false
            func complete(_ reachable: Bool) {
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(returning: reachable)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    complete(true)
                case .failed, .waiting:
                    complete(false)
                case .setup, .preparing, .cancelled:
                    break
                @unknown default:
                    break
                }
            }

            probeQueue.asyncAfter(deadline: .now() + timeoutSeconds) {
                complete(false)
            }

            connection.start(queue: probeQueue)
        }
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
    private let latencyThreshold: Double = 50.0 // Target <50ms
    private let degradedLatencyThreshold: Double = 100.0 // >100ms is degraded
    private let endpointProbeTimeout: TimeInterval = 1.0 // Probe deadline; must resolve inside the 2s check interval
    let maxConsecutiveFailures: Int = 3 // Internal for tests: failed checks before the failure handler fires

    /// Endpoint probes open real sockets. A success means the endpoint completed a full
    /// TCP handshake; re-probing it on every 2 s check is needless descriptor churn
    /// across long sessions. Successes are cadence-bounded; failures keep probing every
    /// check so a dead endpoint still crosses the failure threshold at full speed.
    private var lastSuccessfulEndpointProbeAt: Date?
    private let endpointProbeSuccessInterval: TimeInterval = 5.0

    /// Endpoint prober used by the health check when tunnel info carries a usable RSD
    /// endpoint. Injectable for tests; the default opens a real TCP connection.
    var endpointProber: TunnelEndpointProbing = NWConnectionEndpointProber()

    // MARK: Failure notification
    private var onFailureDetected: (() -> Void)?

    // MARK: Monitoring Control

    func startMonitoring() {
        stopMonitoring()
        connectionStartTime = Date()

        // [weak self] or the task retains the monitor forever: every discarded owner
        // (e.g. an AppState in a test, or a replaced DeviceStateManager) would leave an
        // immortal monitor ticking /bin/ps and endpoint probes every 2 s — the root
        // cause of the suite's file-descriptor exhaustion and ghost health reports.
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.performHealthCheck()
                try? await Task.sleep(nanoseconds: UInt64(self.healthCheckInterval * 1_000_000_000))
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

    /// Runs one health-check cycle. Internal for tests.
    func performHealthCheck() async {
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
        // Check if tunnel info is available and valid
        guard let tunnelInfo = TunneldManager.shared.tunnelInfo else {
            return false
        }

        // Verify process is still running if we have a PID
        if let pid = tunnelInfo.processId {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-p", String(pid)]

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    return false
                }
            } catch {
                return false
            }
        } else {
            // If no PID, just verify tunnel is marked as running
            guard TunneldManager.shared.isRunning else {
                return false
            }
        }

        // A live process is not a usable tunnel: with --native, the pymobiledevice3
        // process stays alive after the underlying Apple/remotepairingd tunnel dies
        // (phone locked, Wi-Fi dropped), so the RSD endpoint must be probed. An
        // unreachable endpoint counts exactly like a failed liveness check. Without a
        // usable RSD endpoint there is nothing to probe — keep the process verdict.
        guard tunnelInfo.isUsable else {
            return true
        }

        if let lastSuccess = lastSuccessfulEndpointProbeAt,
           Date().timeIntervalSince(lastSuccess) < endpointProbeSuccessInterval {
            return true
        }

        let reachable = await endpointProber.isReachable(
            host: tunnelInfo.rsdAddress,
            port: tunnelInfo.rsdPort,
            timeoutSeconds: endpointProbeTimeout
        )

        if reachable {
            lastSuccessfulEndpointProbeAt = Date()
        } else {
            lastSuccessfulEndpointProbeAt = nil
            Logger.debug(
                "Tunnel endpoint \(tunnelInfo.rsdAddress):\(tunnelInfo.rsdPort) unreachable — reporting unhealthy despite a live process",
                category: .device
            )
        }

        return reachable
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
