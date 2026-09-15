//
//  HealthCheckServerTests.swift
//  PathChangerTests
//
//  Tests for the health check server (OBS-001).
//

import XCTest
@testable import PathChanger

// MARK: - Health Check Response Tests

final class HealthCheckResponseTests: XCTestCase {

    func testHealthStatusValues() {
        XCTAssertEqual(HealthCheckResponse.HealthStatus.healthy.rawValue, "healthy")
        XCTAssertEqual(HealthCheckResponse.HealthStatus.degraded.rawValue, "degraded")
        XCTAssertEqual(HealthCheckResponse.HealthStatus.unhealthy.rawValue, "unhealthy")
    }

    func testHealthResponseEncoding() throws {
        let response = HealthCheckResponse(
            status: .healthy,
            tunnel: HealthCheckResponse.TunnelHealth(
                mode: "usb",
                connected: true,
                uptime: 3600,
                state: "running"
            ),
            devices: HealthCheckResponse.DeviceHealth(count: 1),
            lastInjection: "2025-12-11T06:30:00Z",
            version: "1.0.0",
            uptime: 3600,
            timestamp: "2025-12-11T07:30:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(response)
        XCTAssertNotNil(data)

        // Verify decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthCheckResponse.self, from: data)

        XCTAssertEqual(decoded.status, .healthy)
        XCTAssertEqual(decoded.tunnel.mode, "usb")
        XCTAssertTrue(decoded.tunnel.connected)
        XCTAssertEqual(decoded.tunnel.uptime, 3600)
        XCTAssertEqual(decoded.tunnel.state, "running")
        XCTAssertEqual(decoded.devices.count, 1)
        XCTAssertEqual(decoded.lastInjection, "2025-12-11T06:30:00Z")
        XCTAssertEqual(decoded.version, "1.0.0")
    }

    func testTunnelHealthEncoding() throws {
        let tunnelHealth = HealthCheckResponse.TunnelHealth(
            mode: "wifi",
            connected: false,
            uptime: nil,
            state: "idle"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(tunnelHealth)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthCheckResponse.TunnelHealth.self, from: data)

        XCTAssertEqual(decoded.mode, "wifi")
        XCTAssertFalse(decoded.connected)
        XCTAssertNil(decoded.uptime)
        XCTAssertEqual(decoded.state, "idle")
    }

    func testDeviceHealthEncoding() throws {
        let deviceHealth = HealthCheckResponse.DeviceHealth(count: 3)

        let encoder = JSONEncoder()
        let data = try encoder.encode(deviceHealth)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthCheckResponse.DeviceHealth.self, from: data)

        XCTAssertEqual(decoded.count, 3)
    }
}

// MARK: - Health Check Server Tests

final class HealthCheckServerTests: XCTestCase {

    @MainActor
    func testServerInitialState() async {
        let server = HealthCheckServer()

        XCTAssertFalse(server.isRunning)
        XCTAssertEqual(server.port, HealthCheckConfig.defaultPort)
        XCTAssertNil(server.lastRequestTime)
        XCTAssertEqual(server.requestCount, 0)
    }

    @MainActor
    func testPortConstants() {
        XCTAssertEqual(HealthCheckConfig.minPort, 1024)
        XCTAssertEqual(HealthCheckConfig.maxPort, 65535)
        XCTAssertEqual(HealthCheckConfig.defaultPort, 8080)
    }

    @MainActor
    func testInvalidPortThrows() async {
        let server = HealthCheckServer()

        // Port below minimum
        XCTAssertThrowsError(try server.start(port: 80)) { error in
            guard case HealthCheckError.invalidPort = error else {
                XCTFail("Expected invalidPort error")
                return
            }
        }

        // Port 0 is invalid
        XCTAssertThrowsError(try server.start(port: 0)) { error in
            guard case HealthCheckError.invalidPort = error else {
                XCTFail("Expected invalidPort error")
                return
            }
        }
    }

    @MainActor
    func testServerStopWhenNotRunning() async {
        let server = HealthCheckServer()

        // Should not crash when stopping a non-running server
        server.stop()

        XCTAssertFalse(server.isRunning)
    }

    @MainActor
    func testServerClosuresConfiguration() async {
        let server = HealthCheckServer()

        // Configure closures
        server.getTunnelState = { .running }
        server.getActiveMode = { .usb }
        server.getDeviceCount = { 2 }
        server.getLastInjectionTime = { Date() }

        // Verify closures are set
        XCTAssertNotNil(server.getTunnelState)
        XCTAssertNotNil(server.getActiveMode)
        XCTAssertNotNil(server.getDeviceCount)
        XCTAssertNotNil(server.getLastInjectionTime)

        // Test closure returns
        XCTAssertEqual(server.getTunnelState?(), .running)
        XCTAssertEqual(server.getActiveMode?(), .usb)
        XCTAssertEqual(server.getDeviceCount?(), 2)
    }
}

// MARK: - Health Check Error Tests

final class HealthCheckErrorTests: XCTestCase {

    func testInvalidPortErrorDescription() {
        let error = HealthCheckError.invalidPort(80)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("80"))
        XCTAssertTrue(error.errorDescription!.contains("1024"))
        XCTAssertTrue(error.errorDescription!.contains("65535"))
    }

    func testListenerCreationFailedErrorDescription() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = HealthCheckError.listenerCreationFailed(underlyingError)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("listener"))
    }

    func testServerAlreadyRunningErrorDescription() {
        let error = HealthCheckError.serverAlreadyRunning

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("already running"))
    }
}

// MARK: - Tunnel State Display Name Tests

final class TunnelStateDisplayNameTests: XCTestCase {

    func testTunnelStateDisplayNames() {
        XCTAssertEqual(TunnelState.idle.displayName, "idle")
        XCTAssertEqual(TunnelState.starting.displayName, "starting")
        XCTAssertEqual(TunnelState.running.displayName, "running")
        XCTAssertEqual(TunnelState.stopping.displayName, "stopping")
        XCTAssertEqual(TunnelState.error("test").displayName, "error")
    }

    func testTunnelStateIsActive() {
        XCTAssertFalse(TunnelState.idle.isActive)
        XCTAssertFalse(TunnelState.starting.isActive)
        XCTAssertTrue(TunnelState.running.isActive)
        XCTAssertFalse(TunnelState.stopping.isActive)
        XCTAssertFalse(TunnelState.error("test").isActive)
    }
}

final class HealthCheckSecurityContractTests: XCTestCase {
    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("PathChanger/Core/HealthCheckServer.swift"),
            encoding: .utf8
        )
    }

    func testListenerIsLoopbackOnlyAndBounded() throws {
        let source = try source()

        XCTAssertTrue(source.contains("parameters.requiredLocalEndpoint"))
        XCTAssertTrue(source.contains("127.0.0.1"))
        XCTAssertTrue(source.contains("maximumRequestBytes"))
        XCTAssertTrue(source.contains("maximumConcurrentConnections"))
    }

    func testHealthPayloadAndHeadersDoNotExposeDeviceIdentityOrWildcardCORS() throws {
        let source = try source()

        XCTAssertFalse(source.contains("connectedUDIDs"))
        XCTAssertFalse(source.contains("getDeviceUDIDs"))
        XCTAssertFalse(source.contains("Access-Control-Allow-Origin: *"))
    }

    func testRequestReceiveAccumulatesHeadersBeforeParsing() throws {
        let source = try source()

        XCTAssertTrue(source.contains("accumulatedData: Data = Data()"))
        XCTAssertTrue(source.contains("headerTerminator"))
        XCTAssertTrue(source.contains("receiveRequest(from: connection, accumulatedData:"))
    }

    func testConnectionIsRemovedOnlyByTerminalCleanup() throws {
        let source = try source()

        XCTAssertTrue(source.contains("finishConnection(connection)"))
        XCTAssertTrue(source.contains("private func finishConnection(_ connection: NWConnection)"))
        XCTAssertTrue(source.contains("self?.finishConnection(connection)"))
    }
}
