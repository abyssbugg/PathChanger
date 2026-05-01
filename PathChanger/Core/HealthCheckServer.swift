//
//  HealthCheckServer.swift
//  PathChanger
//
//  Local HTTP health check endpoint for monitoring and automation (OBS-001).
//

import Foundation
import Network

// MARK: - Health Check Response

/// Health check response model
struct HealthCheckResponse: Codable {
    let status: HealthStatus
    let tunnel: TunnelHealth
    let devices: DeviceHealth
    let lastInjection: String?
    let version: String
    let uptime: TimeInterval
    let timestamp: String

    enum HealthStatus: String, Codable {
        case healthy
        case degraded
        case unhealthy
    }

    struct TunnelHealth: Codable {
        let mode: String
        let connected: Bool
        let uptime: TimeInterval?
        let state: String
    }

    struct DeviceHealth: Codable {
        let count: Int
        let connectedUDIDs: [String]
    }
}

// MARK: - Health Check Configuration

/// Configuration for the health check server
enum HealthCheckConfig {
    /// Minimum port number allowed (user-space ports only)
    static let minPort: UInt16 = 1024

    /// Maximum port number
    static let maxPort: UInt16 = 65535

    /// Default health check port
    static let defaultPort: UInt16 = 8080
}

// MARK: - Health Check Server

/// Local HTTP server for health check endpoint
///
/// Provides a simple HTTP endpoint for monitoring the application's health status.
/// This is useful for:
/// - Automation and scripting integration
/// - Monitoring and alerting systems
/// - Debugging and troubleshooting
///
/// ## Usage
///
/// ```swift
/// let server = HealthCheckServer()
/// try server.start(port: 8080)
///
/// // Access: http://localhost:8080/health
/// ```
///
/// ## Response Format
///
/// The `/health` endpoint returns JSON:
/// ```json
/// {
///   "status": "healthy",
///   "tunnel": {
///     "mode": "usb",
///     "connected": true,
///     "uptime": 3600
///   },
///   "devices": {
///     "count": 1,
///     "connectedUDIDs": ["device-udid"]
///   },
///   "lastInjection": "2025-12-11T06:30:00Z",
///   "version": "1.0.0"
/// }
/// ```
@MainActor
class HealthCheckServer: ObservableObject {

    // MARK: Published Properties

    @Published var isRunning: Bool = false
    @Published var port: UInt16 = HealthCheckConfig.defaultPort
    @Published var lastRequestTime: Date?
    @Published var requestCount: Int = 0

    // MARK: Private Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.pathchanger.healthcheck")
    private let startTime = Date()

    // MARK: Health Data Providers (closures set by owner)

    /// Closure to get tunnel state
    var getTunnelState: (() -> TunnelState)?

    /// Closure to get active tunnel mode
    var getActiveMode: (() -> TunnelMode?)?

    /// Closure to get device count
    var getDeviceCount: (() -> Int)?

    /// Closure to get device UDIDs
    var getDeviceUDIDs: (() -> [String])?

    /// Closure to get last injection time
    var getLastInjectionTime: (() -> Date?)?

    // MARK: Lifecycle

    init() {
        // Default initialization
    }

    // MARK: Server Control

    /// Start the health check server on the specified port
    /// - Parameter port: The port to listen on (default: 8080)
    func start(port: UInt16 = HealthCheckConfig.defaultPort) throws {
        guard !isRunning else {
            Logger.info("Health check server already running on port \(self.port)", category: .network)
            return
        }

        // Validate port range
        guard port >= HealthCheckConfig.minPort && port <= HealthCheckConfig.maxPort else {
            throw HealthCheckError.invalidPort(port)
        }

        self.port = port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            throw HealthCheckError.listenerCreationFailed(error)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleListenerStateChange(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleNewConnection(connection)
            }
        }

        listener?.start(queue: queue)

        Logger.info("Health check server starting on port \(port)", category: .network)
    }

    /// Stop the health check server
    func stop() {
        guard isRunning else { return }

        listener?.cancel()
        listener = nil

        connections.forEach { $0.cancel() }
        connections.removeAll()

        isRunning = false

        Logger.info("Health check server stopped", category: .network)
    }

    // MARK: Connection Handling

    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            Logger.info("Health check server ready on port \(port)", category: .network)
        case .failed(let error):
            isRunning = false
            Logger.error("Health check server failed: \(error.localizedDescription)", category: .network)
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection = connection else { return }

            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.receiveRequest(from: connection)
                case .failed, .cancelled:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    Logger.debug("Health check connection error: \(error.localizedDescription)", category: .network)
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                self.lastRequestTime = Date()
                self.requestCount += 1

                // Parse HTTP request
                let request = String(data: data, encoding: .utf8) ?? ""
                let response = self.handleHTTPRequest(request)

                // Send response
                let responseData = response.data(using: .utf8) ?? Data()
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    // MARK: HTTP Request Handling

    private func handleHTTPRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return buildHTTPResponse(statusCode: 400, statusText: "Bad Request", body: "Invalid request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return buildHTTPResponse(statusCode: 400, statusText: "Bad Request", body: "Invalid request line")
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Only allow GET requests
        guard method == "GET" else {
            return buildHTTPResponse(statusCode: 405, statusText: "Method Not Allowed", body: "Only GET is supported")
        }

        // Route handling
        switch path {
        case "/health", "/health/":
            return handleHealthEndpoint()
        case "/", "/status":
            return buildHTTPResponse(statusCode: 200, statusText: "OK", body: "PathChanger Health Server")
        default:
            return buildHTTPResponse(statusCode: 404, statusText: "Not Found", body: "Endpoint not found")
        }
    }

    private func handleHealthEndpoint() -> String {
        let health = buildHealthResponse()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let jsonData = try? encoder.encode(health),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return buildHTTPResponse(statusCode: 500, statusText: "Internal Server Error", body: "Failed to encode response")
        }

        return buildHTTPResponse(statusCode: 200, statusText: "OK", body: jsonString, contentType: "application/json")
    }

    private func buildHealthResponse() -> HealthCheckResponse {
        let tunnelState = getTunnelState?() ?? .idle
        let isTunnelConnected = tunnelState.isActive
        let tunnelMode = getActiveMode?()?.rawValue ?? "none"
        let tunnelStateName = tunnelState.displayName

        let deviceCount = getDeviceCount?() ?? 0
        let connectedUDIDs = getDeviceUDIDs?() ?? []

        let lastInjection = getLastInjectionTime?().map { iso8601String(from: $0) }

        let status: HealthCheckResponse.HealthStatus
        if isTunnelConnected && deviceCount > 0 {
            status = .healthy
        } else if isTunnelConnected || deviceCount > 0 {
            status = .degraded
        } else {
            status = .unhealthy
        }

        let uptime = Date().timeIntervalSince(startTime)

        return HealthCheckResponse(
            status: status,
            tunnel: HealthCheckResponse.TunnelHealth(
                mode: tunnelMode,
                connected: isTunnelConnected,
                uptime: isTunnelConnected ? uptime : nil,
                state: tunnelStateName
            ),
            devices: HealthCheckResponse.DeviceHealth(
                count: deviceCount,
                connectedUDIDs: connectedUDIDs
            ),
            lastInjection: lastInjection,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            uptime: uptime,
            timestamp: iso8601String(from: Date())
        )
    }

    private func buildHTTPResponse(
        statusCode: Int,
        statusText: String,
        body: String,
        contentType: String = "text/plain"
    ) -> String {
        let contentLength = body.utf8.count

        return """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(contentLength)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        X-Content-Type-Options: nosniff\r
        \r
        \(body)
        """
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Health Check Error

/// Errors that can occur with the health check server
enum HealthCheckError: LocalizedError {
    case invalidPort(UInt16)
    case listenerCreationFailed(Error)
    case serverAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid port: \(port). Must be between \(HealthCheckConfig.minPort) and \(HealthCheckConfig.maxPort)."
        case .listenerCreationFailed(let error):
            return "Failed to create listener: \(error.localizedDescription)"
        case .serverAlreadyRunning:
            return "Health check server is already running"
        }
    }
}

// MARK: - Tunnel State Extension

extension TunnelState {
    /// Display name for the tunnel state
    var displayName: String {
        switch self {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .running:
            return "running"
        case .stopping:
            return "stopping"
        case .error:
            return "error"
        }
    }
}
