//
//  TunnelHealthMonitorTests.swift
//  PathChangerTests
//
//  Tests that tunnel health checks probe the RSD endpoint, not just the process.
//
//  A --native pymobiledevice3 tunnel process stays alive after the underlying
//  Apple/remotepairingd tunnel dies (phone locked, Wi-Fi dropped); these tests lock
//  the contract that an unreachable RSD endpoint counts exactly like a failed
//  process-liveness check, and that tunnels without usable RSD info keep the
//  process-based verdict.
//

import XCTest
@testable import PathChanger

@MainActor
final class TunnelHealthMonitorTests: XCTestCase {

    var monitor: TunnelHealthMonitor!
    fileprivate var prober: FakeTunnelEndpointProber!

    private let rsdHost = "fd00::1"
    private let rsdPort = 58783

    override func setUpWithError() throws {
        try super.setUpWithError()
        monitor = TunnelHealthMonitor()
        prober = FakeTunnelEndpointProber()
        monitor.endpointProber = prober
    }

    override func tearDownWithError() throws {
        // Restore the shared singleton deterministically for the suites that follow
        // (notably TunneldManagerTests, which drives the same singleton): reset the
        // state machine to idle and clear the tunnel info this harness installed.
        // The real stopTunnel()'s async side effects can outlive the test and bleed
        // into the next suite.
        let mirror = Mirror(reflecting: TunneldManager.shared as TunneldManager)
        if let stateMachine = mirror.children.first(where: { $0.label == "stateMachine" })?.value as? TunnelStateMachine {
            #if DEBUG
            stateMachine.testModeEnabled = true
            defer { stateMachine.testModeEnabled = false }
            #endif
            stateMachine.reset()
        }
        // The connectionEstablished action started the shared manager's OWN monitor;
        // stop it and clear its failure residue so later suites (TunneldManagerTests)
        // start from a clean monitor, not one already at the failure threshold.
        if let sharedMonitor = mirror.children.first(where: { $0.label == "healthMonitor" })?.value as? TunnelHealthMonitor {
            sharedMonitor.stopMonitoring()
            sharedMonitor.resetMetrics()
        }
        TunneldManager.shared.tunnelInfo = nil
        monitor.stopMonitoring()
        monitor = nil
        prober = nil
        try super.tearDownWithError()
    }

    // MARK: - Shared Manager Harness

    /// Puts the shared TunneldManager into `.running` with `info` without launching or
    /// elevating anything — the same Mirror pattern TunneldManagerTests uses to drive
    /// the real state machine.
    private func makeSharedTunnelRunning(with info: TunnelInfo) {
        let mirror = Mirror(reflecting: TunneldManager.shared as TunneldManager)
        guard let stateMachine = mirror.children.first(where: { $0.label == "stateMachine" })?.value
            as? TunnelStateMachine else {
            return XCTFail("could not access TunneldManager's state machine")
        }

        stateMachine.reset()
        #if DEBUG
        stateMachine.testModeEnabled = true
        defer { stateMachine.testModeEnabled = false }
        #endif
        stateMachine.send(.startRequested(mode: .wifi))
        stateMachine.send(.connectionEstablished(info: info))

        // Set immediately so the monitor under test observes the info even before the
        // RunLoop-delivered state sync lands; the sync writes the same context value.
        TunneldManager.shared.tunnelInfo = info
    }

    /// Lets the RunLoop-delivered state sync land (`TunneldManager.state` updates via a
    /// RunLoop.main Combine subscription) and asserts the harness took effect.
    private func settleSharedManagerSync(expect info: TunnelInfo) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(TunneldManager.shared.isRunning, "harness: shared manager should be running")
        XCTAssertEqual(TunneldManager.shared.tunnelInfo, info, "harness: shared tunnelInfo should match the test info")
    }

    private func usableTunnelInfo(processId: Int32?) -> TunnelInfo {
        TunnelInfo(
            rsdAddress: rsdHost,
            rsdPort: rsdPort,
            mode: .wifi,
            interface: "utun9",
            processId: processId
        )
    }

    // MARK: - Endpoint Probe Tests

    func testSuccessfulEndpointProbeIsCadenceBounded() async throws {
        // A probe success answers a full TCP handshake; the very next 2 s check must not
        // open another socket for it. Failures (other tests) still probe every check.
        let info = usableTunnelInfo(processId: ProcessInfo.processInfo.processIdentifier)
        makeSharedTunnelRunning(with: info)
        prober.result = true
        try await settleSharedManagerSync(expect: info)

        await monitor.performHealthCheck()
        await monitor.performHealthCheck()
        await monitor.performHealthCheck()

        XCTAssertEqual(prober.probes.count, 1, "a successful endpoint probe must bound re-probing")
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 0)
    }

    func testUnreachableEndpointFiresFailureHandlerAtThreshold() async throws {
        makeSharedTunnelRunning(with: usableTunnelInfo(processId: nil))
        prober.result = false
        try await settleSharedManagerSync(expect: usableTunnelInfo(processId: nil))

        var failureCount = 0
        monitor.setFailureNotificationHandler { failureCount += 1 }

        // Below the threshold the monitor degrades but does not notify.
        for _ in 0..<(monitor.maxConsecutiveFailures - 1) {
            await monitor.performHealthCheck()
        }

        if case .degraded = monitor.healthStatus {} else {
            XCTFail("expected degraded below threshold, got \(monitor.healthStatus)")
        }
        XCTAssertEqual(failureCount, 0)
        XCTAssertFalse(monitor.recommendUSBFallback)

        // The next unreachable endpoint crosses the threshold: same treatment as a
        // failed process-liveness check.
        await monitor.performHealthCheck()

        if case .critical = monitor.healthStatus {} else {
            XCTFail("expected critical at threshold, got \(monitor.healthStatus)")
        }
        XCTAssertEqual(failureCount, 1)
        XCTAssertTrue(monitor.recommendUSBFallback)
        XCTAssertEqual(monitor.metrics.consecutiveFailures, monitor.maxConsecutiveFailures)

        // The endpoint prober ran once per check against the tunnel's RSD address.
        XCTAssertEqual(prober.probes.count, monitor.maxConsecutiveFailures)
        XCTAssertEqual(prober.probes.first?.host, rsdHost)
        XCTAssertEqual(prober.probes.first?.port, rsdPort)
    }

    func testReachableEndpointKeepsStatusHealthy() async throws {
        makeSharedTunnelRunning(with: usableTunnelInfo(processId: nil))
        prober.result = true
        try await settleSharedManagerSync(expect: usableTunnelInfo(processId: nil))

        var failureCount = 0
        monitor.setFailureNotificationHandler { failureCount += 1 }

        await monitor.performHealthCheck()
        await monitor.performHealthCheck()
        await monitor.performHealthCheck()

        XCTAssertEqual(monitor.healthStatus, .healthy)
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 0)
        XCTAssertEqual(failureCount, 0)
        XCTAssertFalse(monitor.recommendUSBFallback)

        // Success-cadence contract: the first healthy probe answers the handshake; the
        // immediate follow-up checks must not open further sockets for a healthy endpoint.
        XCTAssertEqual(prober.probes.count, 1)
        XCTAssertEqual(prober.probes.first?.host, rsdHost)
        XCTAssertEqual(prober.probes.first?.port, rsdPort)
    }

    func testReachableEndpointResetsConsecutiveFailures() async throws {
        makeSharedTunnelRunning(with: usableTunnelInfo(processId: nil))
        try await settleSharedManagerSync(expect: usableTunnelInfo(processId: nil))

        var failureCount = 0
        monitor.setFailureNotificationHandler { failureCount += 1 }

        prober.result = false
        await monitor.performHealthCheck()
        await monitor.performHealthCheck()
        if case .degraded = monitor.healthStatus {} else {
            XCTFail("expected degraded during failures, got \(monitor.healthStatus)")
        }

        prober.result = true
        await monitor.performHealthCheck()

        XCTAssertEqual(monitor.healthStatus, .healthy)
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 0)
        XCTAssertEqual(failureCount, 0)
    }

    func testNoUsableRSDInfoFallsBackToProcessLiveness() async throws {
        // A manufactured placeholder endpoint (port 0, per the TunnelInfo.isUsable
        // contract) carries no usable RSD: the check must stay on process liveness and
        // never consult the endpoint prober. This test's own PID is a live process.
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let info = TunnelInfo(
            rsdAddress: "127.0.0.1",
            rsdPort: 0,
            mode: .wifi,
            interface: nil,
            processId: ownPid
        )
        makeSharedTunnelRunning(with: info)
        prober.result = false  // would fail the check if the prober were consulted
        try await settleSharedManagerSync(expect: info)

        var failureCount = 0
        monitor.setFailureNotificationHandler { failureCount += 1 }

        await monitor.performHealthCheck()

        // The verdict must come from process liveness, never the endpoint prober. Latency
        // of the ps check is machine-load-dependent (observed 65 ms > the 50 ms degraded
        // threshold), so accept healthy or latency-degraded — but never critical/disconnected.
        switch monitor.healthStatus {
        case .healthy, .degraded:
            break
        case .critical, .disconnected:
            XCTFail("process liveness is satisfied; status must not be \(monitor.healthStatus)")
        }
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 0)
        XCTAssertEqual(failureCount, 0)
        XCTAssertTrue(prober.probes.isEmpty, "endpoint prober must not run without usable RSD info")
    }

    func testMissingTunnelInfoIsUnhealthyWithoutProbing() async throws {
        makeSharedTunnelRunning(with: usableTunnelInfo(processId: nil))
        prober.result = true
        try await settleSharedManagerSync(expect: usableTunnelInfo(processId: nil))
        TunneldManager.shared.tunnelInfo = nil

        var failureCount = 0
        monitor.setFailureNotificationHandler { failureCount += 1 }

        await monitor.performHealthCheck()

        if case .degraded = monitor.healthStatus {} else {
            XCTFail("expected degraded without tunnel info, got \(monitor.healthStatus)")
        }
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 1)
        XCTAssertEqual(failureCount, 0)
        XCTAssertTrue(prober.probes.isEmpty)
    }

    func testDeadProcessWithUsableEndpointShortCircuitsBeforeProbing() async throws {
        // Int32.max cannot exist, so the process-liveness check fails first; even a
        // reachable endpoint cannot revive a dead process.
        makeSharedTunnelRunning(with: usableTunnelInfo(processId: Int32.max))
        prober.result = true
        try await settleSharedManagerSync(expect: usableTunnelInfo(processId: Int32.max))

        await monitor.performHealthCheck()

        if case .degraded = monitor.healthStatus {} else {
            XCTFail("expected degraded for a dead process, got \(monitor.healthStatus)")
        }
        XCTAssertEqual(monitor.metrics.consecutiveFailures, 1)
        XCTAssertTrue(prober.probes.isEmpty, "dead process must short-circuit before the endpoint probe")
    }
}

/// Records endpoint probes and returns a canned verdict.
private final class FakeTunnelEndpointProber: TunnelEndpointProbing {
    var result = true
    private(set) var probes: [(host: String, port: Int, timeoutSeconds: Double)] = []

    func isReachable(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        probes.append((host, port, timeoutSeconds))
        return result
    }
}
