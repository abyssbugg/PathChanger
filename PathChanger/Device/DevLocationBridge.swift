//
//  DevLocationBridge.swift
//  PathChanger
//
//  Bridge to pymobiledevice3 for location injection on capability-compatible iOS
//  Supports both USB (--udid) and WiFi via lockdown tunnel (--rsd)
//

import Darwin
import Foundation
import Combine

// MARK: - Command Validation Error

/// Errors for command structure validation (defense-in-depth)
enum CommandValidationError: Error, LocalizedError {
    case invalidSubcommand(String)
    case invalidFlag(String)
    case invalidArgumentPosition(String)
    case unexpectedArgumentCount(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSubcommand(let cmd):
            return "Security violation: Unknown subcommand '\(cmd)' not in allowlist"
        case .invalidFlag(let flag):
            return "Security violation: Unknown flag '\(flag)' not in allowlist"
        case .invalidArgumentPosition(let arg):
            return "Security violation: Argument '\(arg)' in unexpected position"
        case .unexpectedArgumentCount(let expected, let actual):
            return "Security violation: Expected \(expected) arguments, got \(actual)"
        }
    }
}

// MARK: - Subprocess Command Validator

/// Defense-in-depth command structure validation for pymobiledevice3 subprocess calls
/// This provides allowlist validation on top of ArgumentSanitizer's character filtering
struct SubprocessCommandValidator {

    /// Allowed pymobiledevice3 subcommands (only commands we actually use)
    private static let allowedSubcommands: Set<String> = [
        // Location simulation commands
        "developer", "dvt", "simulate-location", "set", "clear",
        // Tunnel management commands
        "lockdown", "start-tunnel", "tunneld",
        // Device listing commands
        "usbmux", "list", "remote", "ls"
    ]

    /// Allowed command-line flags (only flags we actually use)
    private static let allowedFlags: Set<String> = [
        "-m",           // Python module flag
        "--tunnel",     // Use tunneld for connection
        "--udid",       // Target device by UDID
        "--rsd",        // Remote Service Discovery address
        "--no-color",   // Disable colored output
        "--",           // Argument separator
        "-h", "--help"  // Help flags (safe to allow)
    ]

    /// The expected module name for pymobiledevice3
    private static let expectedModule = "pymobiledevice3"

    // MARK: - Validation Methods

    /// Validate the entire command structure against allowlists
    /// - Parameter arguments: Array of command arguments (excluding python3 path)
    /// - Throws: CommandValidationError if validation fails
    static func validateCommandStructure(_ arguments: [String]) throws {
        // Log validation attempt
        Logger.debug("Validating command structure: \(arguments.count) arguments", category: .security)

        // Validate module flag is first
        guard arguments.count >= 2,
              arguments[0] == "-m",
              arguments[1] == expectedModule else {
            Logger.error("Command validation failed: Expected -m pymobiledevice3 prefix", category: .security)
            throw CommandValidationError.invalidSubcommand(arguments.prefix(2).joined(separator: " "))
        }

        // Validate each argument
        var foundArgumentSeparator = false

        for (index, arg) in arguments.enumerated() {
            // Skip the validated module prefix
            if index < 2 { continue }

            // After --, everything is data arguments (coordinates, etc.)
            if arg == "--" {
                foundArgumentSeparator = true
                continue
            }

            if foundArgumentSeparator {
                // Data arguments after -- must be valid data types
                guard isValidDataArgument(arg) else {
                    Logger.error("Invalid data argument after separator: \(arg)", category: .security)
                    throw CommandValidationError.invalidArgumentPosition(arg)
                }
                continue
            }

            // Check if it's a flag
            if arg.starts(with: "-") {
                try validateFlag(arg)
            } else {
                // Check if it's a subcommand or data argument
                try validateArgument(arg, at: index)
            }
        }

        Logger.debug("Command validation passed", category: .security)
    }

    /// Validate a flag argument
    private static func validateFlag(_ flag: String) throws {
        // Handle flags with values (e.g., --flag=value)
        let flagName = flag.contains("=") ? String(flag.prefix(while: { $0 != "=" })) : flag

        guard allowedFlags.contains(flagName) else {
            Logger.error("Blocked unknown flag: \(flag)", category: .security)
            throw CommandValidationError.invalidFlag(flag)
        }
    }

    /// Validate a non-flag argument (subcommand or data)
    private static func validateArgument(_ arg: String, at index: Int) throws {
        // First check if it's a valid data argument
        if isValidDataArgument(arg) {
            return // Data arguments are allowed
        }

        // Otherwise it must be a known subcommand
        guard allowedSubcommands.contains(arg) else {
            Logger.error("Blocked unknown subcommand: \(arg) at index \(index)", category: .security)
            throw CommandValidationError.invalidSubcommand(arg)
        }
    }

    /// Check if argument is a valid data type (coordinate, UDID, address, port)
    /// - Parameter arg: The argument to check
    /// - Returns: true if it's a recognized data format
    static func isValidDataArgument(_ arg: String) -> Bool {
        // Coordinate: decimal number (including negative)
        if let _ = Double(arg), arg.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            return true
        }

        // Device UDID: 40-character hexadecimal
        if ArgumentSanitizer.isValidDeviceUDID(arg) {
            return true
        }

        // IPv6 address (for RSD connections)
        if ArgumentSanitizer.isValidIPv6Address(arg) {
            return true
        }

        // Port number: numeric only
        if let port = Int(arg), ArgumentSanitizer.isValidPort(port) {
            return true
        }

        // Absolute path for `developer dvt ls /`
        if arg.hasPrefix("/"), arg.allSatisfy({ $0.isLetter || $0.isNumber || "/._-".contains($0) }) {
            return true
        }

        return false
    }
}

// MARK: - Subprocess Security Error

/// Security errors for subprocess execution
enum SubprocessSecurityError: Error, LocalizedError {
    case outputSizeExceeded(actualSize: Int, maxSize: Int)
    case subprocessExecutionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .outputSizeExceeded(let actualSize, let maxSize):
            return "Subprocess output exceeded safety limit: \(actualSize) bytes (max: \(maxSize) bytes)"
        case .subprocessExecutionFailed(let reason):
            return "Subprocess execution failed: \(reason)"
        }
    }
}

// MARK: - Location Injection Error

/// Error types for location injection
enum LocationInjectionError: Error, LocalizedError {
    case invalidCoordinates
    case tunneldNotRunning
    case deviceNotFound
    case injectionFailed(String)
    case clearFailed(String)
    case rateLimited
    case timeout
    case developerModeRequired
    case outputSizeExceeded
    case unsupportedIOSVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Invalid GPS coordinates. Latitude must be -90 to 90, longitude -180 to 180."
        case .tunneldNotRunning:
            return "The selected provider requires an RSD-capable tunnel, but no usable tunnel is running."
        case .deviceNotFound:
            return "Target device not found or disconnected."
        case .injectionFailed(let reason):
            return "Location injection failed: \(reason)"
        case .clearFailed(let reason):
            return "Failed to clear simulated location: \(reason)"
        case .rateLimited:
            return "Location updates are being sent too quickly. Slow down the update rate."
        case .timeout:
            return "Location injection timed out. Check device connection."
        case .developerModeRequired:
            return "Developer Mode must be enabled on the device for location simulation."
        case .outputSizeExceeded:
            return "Subprocess output exceeded safety limit. This may indicate a malicious response."
        case .unsupportedIOSVersion(let version):
            return "Location injection failed on iOS \(version). Keep USB or Wi-Fi tunnel running and retry."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tunneldNotRunning:
            return "Open PathChanger Settings and choose Start Tunnel."
        case .developerModeRequired:
            return "Settings > Privacy & Security > Developer Mode > Enable"
        case .deviceNotFound:
            return "1. Check USB connection or Wi-Fi\n2. Trust this computer on the device\n3. Refresh device list"
        case .outputSizeExceeded:
            return "If this persists, check pymobiledevice3 installation or report a bug."
        case .unsupportedIOSVersion:
            return "Start Tunnel from PathChanger, keep the device on USB or the same Wi-Fi, and retry. Keep the tunnel running and the app open while a spoof is active."
        default:
            return nil
        }
    }
}

// MARK: - Injection Statistics

/// Statistics for location injection performance
struct InjectionStats {
    var totalInjections: Int = 0
    var successfulInjections: Int = 0
    var failedInjections: Int = 0
    var averageLatencyMs: Double = 0
    var lastInjectionTime: Date?

    var successRate: Double {
        guard totalInjections > 0 else { return 0 }
        return Double(successfulInjections) / Double(totalInjections) * 100
    }

    mutating func recordSuccess(latencyMs: Double) {
        totalInjections += 1
        successfulInjections += 1
        lastInjectionTime = Date()

        // Update rolling average
        let alpha = 0.1
        averageLatencyMs = averageLatencyMs * (1 - alpha) + latencyMs * alpha
    }

    mutating func recordFailure() {
        totalInjections += 1
        failedInjections += 1
        lastInjectionTime = Date()
    }
}

struct LocationBridgeSession: Equatable, Sendable {
    let sessionID: UUID
    let generation: UInt64
}

struct LocationSessionGenerationTracker: Sendable {
    private struct Record: Sendable {
        var session: LocationBridgeSession
        var transport: LocationTransport
        var endpointClass: LocationEndpointClass
        var lost: Bool
    }
    private var records: [String: Record] = [:]

    mutating func resolve(
        stableDeviceID: String,
        transport: LocationTransport,
        endpointClass: LocationEndpointClass
    ) -> LocationBridgeSession {
        if var record = records[stableDeviceID] {
            if record.lost || record.transport != transport || record.endpointClass != endpointClass {
                record.session = LocationBridgeSession(sessionID: UUID(), generation: record.session.generation + 1)
                record.transport = transport
                record.endpointClass = endpointClass
                record.lost = false
                records[stableDeviceID] = record
            }
            return record.session
        }
        let session = LocationBridgeSession(sessionID: UUID(), generation: 1)
        records[stableDeviceID] = Record(
            session: session, transport: transport, endpointClass: endpointClass, lost: false
        )
        return session
    }

    enum AdoptionError: Error, Equatable {
        case missingSession
        case staleAcknowledgement
        case transportMismatch
        case endpointMismatch
    }

    @discardableResult
    mutating func restore(
        receipt: LocationInjectionReceipt,
        stableDeviceID: String
    ) throws -> LocationBridgeSession {
        guard receipt.outcome == .applied else {
            throw AdoptionError.missingSession
        }
        if let existing = records[stableDeviceID] {
            guard existing.session.generation <= receipt.sessionGeneration else {
                throw AdoptionError.staleAcknowledgement
            }
            if existing.session.generation == receipt.sessionGeneration {
                guard existing.transport == receipt.transport else {
                    throw AdoptionError.transportMismatch
                }
                guard existing.endpointClass == receipt.endpointClass else {
                    throw AdoptionError.endpointMismatch
                }
            }
        }

        let session = LocationBridgeSession(
            sessionID: receipt.session,
            generation: receipt.sessionGeneration
        )
        records[stableDeviceID] = Record(
            session: session,
            transport: receipt.transport,
            endpointClass: receipt.endpointClass,
            lost: false
        )
        return session
    }

    mutating func beginClear(_ identity: LocationSessionIdentity) throws {
        guard let record = records[identity.stableDeviceID], !record.lost else {
            throw AdoptionError.missingSession
        }
        guard record.session.generation == identity.generation else {
            throw AdoptionError.staleAcknowledgement
        }
        guard record.transport == identity.transport else {
            throw AdoptionError.transportMismatch
        }
        guard record.endpointClass == identity.endpointClass else {
            throw AdoptionError.endpointMismatch
        }
    }

    mutating func completeClear(_ identity: LocationSessionIdentity) throws {
        try beginClear(identity)
        guard var record = records[identity.stableDeviceID] else {
            throw AdoptionError.missingSession
        }
        record.lost = true
        records[identity.stableDeviceID] = record
    }

    mutating func adopt(
        _ acknowledgement: LocationProviderAcknowledgement,
        stableDeviceID: String,
        sessionID: UUID
    ) throws -> LocationBridgeSession {
        guard var record = records[stableDeviceID], !record.lost else {
            throw AdoptionError.missingSession
        }
        guard record.session.sessionID == sessionID,
              record.session.generation == acknowledgement.sessionGeneration else {
            throw AdoptionError.staleAcknowledgement
        }
        guard record.transport == acknowledgement.physicalTransport else {
            throw AdoptionError.transportMismatch
        }

        record.endpointClass = acknowledgement.endpointClass
        records[stableDeviceID] = record
        return record.session
    }

    mutating func markLost(stableDeviceID: String) {
        records[stableDeviceID]?.lost = true
    }
}

enum LocationApplicationAcknowledgementRouter {
    enum RoutingError: Error, Equatable {
        case requestMismatch
    }

    static func accept(
        request: LocationApplicationRequest,
        provisionalSession: LocationBridgeSession,
        acknowledgement: LocationProviderAcknowledgement,
        generationTracker: inout LocationSessionGenerationTracker,
        completedAt: Date = Date()
    ) throws -> LocationInjectionReceipt {
        guard acknowledgement.requestID == request.id else {
            throw RoutingError.requestMismatch
        }
        let adoptedSession = try generationTracker.adopt(
            acknowledgement,
            stableDeviceID: request.target.stableDeviceID,
            sessionID: provisionalSession.sessionID
        )
        return LocationInjectionReceipt(
            session: adoptedSession.sessionID,
            acknowledgedCoordinate: request.coordinate,
            acknowledgement: acknowledgement,
            completedAt: completedAt,
            outcome: .applied
        )
    }
}

extension LocationInjectionReceipt {
    static func accepted(
        request: LocationApplicationRequest,
        endpointClass: LocationEndpointClass,
        session: LocationBridgeSession,
        outcome: LocationInjectionOutcome,
        completedAt: Date = Date()
    ) -> LocationInjectionReceipt {
        LocationInjectionReceipt(
            requestID: request.id,
            session: session.sessionID,
            coordinate: request.coordinate,
            transport: request.target.transport,
            endpointClass: endpointClass,
            sessionGeneration: session.generation,
            completedAt: completedAt,
            outcome: outcome
        )
    }
}

// MARK: - Dev Location Bridge

/// Bridge to pymobiledevice3 for capability-compatible iOS location simulation.
///
/// `DevLocationBridge` is the core component for injecting simulated GPS coordinates
/// onto iOS devices. It uses Apple's DVT (Developer Tools) simulate-location service
/// via the pymobiledevice3 Python library.
///
/// ## Overview
///
/// This actor provides thread-safe location injection with built-in rate limiting,
/// request queuing, and comprehensive error handling. It supports both USB and WiFi
/// connections through the tunneld service.
///
/// ## Usage Example
///
/// ```swift
/// let bridge = DevLocationBridge()
/// let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
///
/// do {
///     try await bridge.setLocation(coordinate, for: device)
///     print("Location set successfully")
/// } catch {
///     print("Failed: \(error)")
/// }
/// ```
///
/// ## Connection Modes
///
/// - **USB Mode**: Uses `--udid` flag for direct USB connection
/// - **WiFi Mode**: Uses `--rsd` with tunnel address from TunneldManager
/// - **Tunnel Mode**: Uses `--tunnel` when tunneld service is running
///
/// ## Performance Modes
///
/// - **Standard Mode**: Creates new subprocess for each location update
/// - **Performance Mode**: Uses persistent Python process for lower latency
///
/// ## Security Features
///
/// - Command structure validation against allowlist
/// - Input sanitization for all coordinates and device IDs
/// - Output size limiting to prevent DoS
/// - Rate limiting to protect device stability
///
/// - Note: Developer Mode must be enabled on the iOS device.
/// - Important: Requires pymobiledevice3 to be installed.
actor DevLocationBridge: LocationInjecting {

    // MARK: Configuration
    private let pythonExecutablePath: String
    private let keepAliveObservationWindow: TimeInterval
    private var python3Path: String { pythonExecutablePath }

    init(
        pythonExecutablePath: String = PythonPathResolver.path,
        keepAliveObservationWindow: TimeInterval = 4.0
    ) {
        self.pythonExecutablePath = pythonExecutablePath
        self.keepAliveObservationWindow = max(0, keepAliveObservationWindow)
    }

    /// Whether to use persistent bridge for high-frequency operations
    /// This significantly reduces overhead for joystick mode
    private var usePersistentBridge: Bool = true

    // MARK: Security Configuration

    /// Maximum output size from subprocess (1 MB) - prevents DoS via excessive output
    /// Typical pymobiledevice3 responses are <10KB, so this is very generous
    private static let maxOutputSize = 1_048_576

    /// Minimum allowed output size (safety check for configuration)
    private static let minOutputSize = 1024

    // MARK: Rate Limiting
    private let rateLimiter = RateLimiter(capacity: 10, refillRate: 5.0, minIntervalMs: 100)
    private let requestQueue = RequestQueueManager(maxQueueSize: 50)

    // MARK: Statistics
    private(set) var stats = InjectionStats()

    /// `developer dvt simulate-location set` must stay running or iOS snaps back.
    private var heldSimulationProcess: Process?
    private var heldSimulationRequiresTunnel: Bool = false
    private var heldSessionDeviceID: String?
    private var generationTracker = LocationSessionGenerationTracker()
    private var eventContinuations: [UUID: AsyncStream<LocationBridgeEvent>.Continuation] = [:]
    private var queuedApplicationContexts: [UUID: QueuedApplicationContext] = [:]
    private var queueProcessingTask: Task<Void, Never>?
    private var clearingDeviceIDs: Set<String> = []

    private struct QueuedApplicationContext: Sendable {
        let request: LocationApplicationRequest
        let endpointClass: LocationEndpointClass
        let session: LocationBridgeSession
    }

    private func retainSimulationProcess(
        _ process: Process,
        requiresTunnel: Bool,
        stableDeviceID: String?
    ) {
        heldSimulationProcess = process
        heldSimulationRequiresTunnel = requiresTunnel
        heldSessionDeviceID = stableDeviceID
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { await self?.heldSimulationProcessTerminated(terminatedProcess) }
        }
    }

    private func heldSimulationProcessTerminated(_ process: Process) {
        guard heldSimulationProcess === process else { return }
        if let heldSessionDeviceID {
            generationTracker.markLost(stableDeviceID: heldSessionDeviceID)
        }
        heldSimulationProcess = nil
        heldSimulationRequiresTunnel = false
        heldSessionDeviceID = nil
        emit(.processTerminated(exitCode: process.terminationStatus))
    }

    func stopHeldSimulation() async {
        guard let process = heldSimulationProcess else {
            heldSimulationRequiresTunnel = false
            heldSessionDeviceID = nil
            return
        }

        process.terminate()
        let terminateDeadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < terminateDeadline {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            process.interrupt()
            let interruptDeadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < interruptDeadline {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1.0)
            while process.isRunning, Date() < killDeadline {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        guard !process.isRunning else {
            Logger.error("Held location process did not exit after SIGKILL", category: .device)
            return
        }

        if heldSimulationProcess === process {
            heldSimulationProcess = nil
            heldSimulationRequiresTunnel = false
            heldSessionDeviceID = nil
        }
    }

    func stopTunnelDependentSimulation() async {
        if heldSimulationRequiresTunnel {
            if let heldSessionDeviceID {
                generationTracker.markLost(stableDeviceID: heldSessionDeviceID)
            }
            await stopHeldSimulation()
        }
        await PersistentLocationBridge.shared.stopIfUsingTunnel()
    }

    func events() async -> AsyncStream<LocationBridgeEvent> {
        let id = UUID()
        let pair = AsyncStream<LocationBridgeEvent>.makeStream()
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }
        eventContinuations[id] = pair.continuation
        return pair.stream
    }

    func adoptManagedSession(
        receipt: LocationInjectionReceipt,
        stableDeviceID: String
    ) async throws {
        try generationTracker.restore(receipt: receipt, stableDeviceID: stableDeviceID)
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func emit(_ event: LocationBridgeEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    private func descriptor(for device: Device) async -> LocationConnectionDescriptor {
        let arguments = await MainActor.run {
            TunneldManager.shared.locationConnectionArguments(for: device.id)
        }
        return LocationConnectionArguments.classify(
            arguments: arguments,
            physicalTransport: device.connectionType == .wifi ? .wifi : .usb
        )
    }

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        guard !clearingDeviceIDs.contains(request.target.stableDeviceID) else {
            throw LocationInjectionError.injectionFailed("Location Clear is in progress for this device")
        }

        let device = Device(
            id: request.target.stableDeviceID,
            displayName: request.target.stableDeviceID,
            connectionType: request.target.transport == .wifi ? .wifi : .usb
        )
        let connection = await descriptor(for: device)
        let session = generationTracker.resolve(
            stableDeviceID: device.id,
            transport: connection.transport,
            endpointClass: connection.endpointClass
        )
        do {
            guard let acknowledgement = try await setLocation(
                request.coordinate,
                for: device,
                usePerformanceMode: true,
                applicationRequest: request,
                applicationSession: session,
                applicationEndpointClass: connection.endpointClass
            ) else {
                throw LocationInjectionError.injectionFailed(
                    "Provider completed without an acknowledgement"
                )
            }
            return try LocationApplicationAcknowledgementRouter.accept(
                request: request,
                provisionalSession: session,
                acknowledgement: acknowledgement,
                generationTracker: &generationTracker
            )
        } catch LocationInjectionError.rateLimited {
            return .accepted(
                request: request,
                endpointClass: connection.endpointClass,
                session: session,
                outcome: .queued
            )
        } catch {
            throw error
        }
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {
        guard let session else {
            throw LocationInjectionError.injectionFailed("Cannot Clear without an acknowledged location session")
        }
        guard session.stableDeviceID == target.stableDeviceID else {
            throw LocationInjectionError.injectionFailed("Clear target does not match the acknowledged session")
        }
        guard clearingDeviceIDs.insert(target.stableDeviceID).inserted else {
            throw LocationInjectionError.injectionFailed("Location Clear is already in progress for this device")
        }
        defer { clearingDeviceIDs.remove(target.stableDeviceID) }

        do {
            try generationTracker.beginClear(session)
        } catch {
            throw LocationInjectionError.injectionFailed("Clear session validation failed: \(error.localizedDescription)")
        }

        let removedRequestIDs = await requestQueue.removeRequests(forDeviceID: target.stableDeviceID)
        for requestID in removedRequestIDs {
            queuedApplicationContexts.removeValue(forKey: requestID)
        }

        if let inFlightRequestID = await requestQueue.inFlightRequestID(
            forDeviceID: target.stableDeviceID
        ) {
            await requestQueue.waitForInFlightRequest(inFlightRequestID)
        }
        if heldSessionDeviceID == target.stableDeviceID {
            await stopHeldSimulation()
        }

        let device = Device(
            id: target.stableDeviceID,
            displayName: target.stableDeviceID,
            connectionType: target.transport == .wifi ? .wifi : .usb
        )
        let acknowledgement = try await PersistentLocationBridge.shared.clearLocation(
            for: device,
            requestID: UUID(),
            sessionGeneration: session.generation
        )
        guard acknowledgement.physicalTransport == session.transport,
              acknowledgement.sessionGeneration == session.generation,
              acknowledgement.endpointClass == session.endpointClass else {
            throw LocationInjectionError.injectionFailed("Clear acknowledgement does not match the active session")
        }
        do {
            try generationTracker.completeClear(session)
        } catch {
            throw LocationInjectionError.injectionFailed(
                "Clear completion could not invalidate the acknowledged session: \(error.localizedDescription)"
            )
        }
    }

    static func connectionRequiresTunnel(_ arguments: [String]) -> Bool {
        arguments.contains("--rsd") || arguments.contains("--tunnel")
    }

    // MARK: - Public API

    /// Sets a simulated GPS location on the specified device.
    ///
    /// This method validates the coordinate, checks rate limits, and injects
    /// the location using pymobiledevice3's DVT simulate-location command.
    ///
    /// - Parameters:
    ///   - coordinate: The GPS coordinate to simulate. Must be valid per ``LocationCoordinate/validated()``.
    ///   - device: The target iOS device. Must have Developer Mode enabled.
    ///   - priority: Request priority for queue ordering. Defaults to `.normal`.
    ///   - usePerformanceMode: If `true`, uses persistent bridge for lower latency.
    ///
    /// - Throws: ``LocationInjectionError`` if injection fails.
    ///
    /// - Note: Requests exceeding the rate limit are automatically queued.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Standard injection
    /// try await bridge.setLocation(coordinate, for: device)
    ///
    /// // High-priority injection (e.g., user-initiated)
    /// try await bridge.setLocation(coordinate, for: device, priority: .high)
    ///
    /// // Performance mode for joystick
    /// try await bridge.setLocation(coordinate, for: device, usePerformanceMode: true)
    /// ```
    func setLocation(
        _ coordinate: LocationCoordinate,
        for device: Device,
        priority: QueuedLocationRequest.RequestPriority = .normal,
        usePerformanceMode: Bool = false,
        applicationRequest: LocationApplicationRequest? = nil,
        applicationSession: LocationBridgeSession? = nil,
        applicationEndpointClass: LocationEndpointClass? = nil
    ) async throws -> LocationProviderAcknowledgement? {
        // Strict coordinate validation
        try coordinate.validated()

        // Validate device UDID
        try ArgumentSanitizer.validateDeviceUDID(device.id)

        // Pre-flight check: Ensure device is properly configured
        try await performPreflight(for: device)

        // Rate limiting with token bucket
        let allowed = await rateLimiter.checkRequest()

        if !allowed {
            // Queue the request if rate limited - use strategy-aware enqueue
            let queuedRequest = QueuedLocationRequest(
                coordinate: coordinate,
                device: device,
                timestamp: Date(),
                priority: priority
            )
            let applicationContext: QueuedApplicationContext?
            if let applicationRequest, let applicationSession, let applicationEndpointClass {
                applicationContext = QueuedApplicationContext(
                    request: applicationRequest,
                    endpointClass: applicationEndpointClass,
                    session: applicationSession
                )
            } else {
                applicationContext = nil
            }

            // Use strategy-aware enqueue (latest-wins for joystick, sequential for routes)
            let enqueueResult = await requestQueue.enqueueWithStrategy(queuedRequest)

            switch enqueueResult {
            case .success:
                if let applicationContext {
                    queuedApplicationContexts[queuedRequest.id] = applicationContext
                }
                let retainedRequestIDs = await requestQueue.queuedRequestIDs()
                queuedApplicationContexts = queuedApplicationContexts.filter {
                    retainedRequestIDs.contains($0.key)
                }

                // Notify user via toast (only if not in performance mode to avoid spam)
                if !usePerformanceMode {
                    await MainActor.run {
                        ToastManager.shared.warning("Location update queued (rate limited)")
                    }
                }

                startQueueProcessingIfNeeded()

                throw LocationInjectionError.rateLimited

            case .failure(let error):
                // Queue rejected - provide specific error message
                switch error {
                case .queueFull:
                    throw LocationInjectionError.injectionFailed("Update queue full. Slow down location changes.")
                case .priorityLimitExceeded(let priority):
                    throw LocationInjectionError.injectionFailed("Too many \(priority) priority requests. Please wait.")
                case .rateLimitExceeded(let priority):
                    throw LocationInjectionError.injectionFailed("Rate limit for \(priority) priority exceeded. Slow down.")
                }
            }
        }

        let startTime = Date()

        // Use persistent bridge for high-frequency/performance mode
        if usePersistentBridge && usePerformanceMode {
            do {
                let acknowledgement = try await setLocationViaPersistentBridge(
                    coordinate,
                    for: device,
                    requestID: applicationRequest?.id ?? UUID(),
                    sessionGeneration: applicationSession?.generation
                )
                let latencyMs = Date().timeIntervalSince(startTime) * 1000
                stats.recordSuccess(latencyMs: latencyMs)
                return acknowledgement
            } catch {
                if applicationRequest != nil {
                    throw error
                }
                // Non-session utility callers retain the legacy fallback during migration.
                Logger.debug("Persistent bridge failed, falling back to subprocess: \(error)", category: .device, deviceUDID: device.id, iosVersion: device.productVersion)
            }
        }

        // Standard subprocess mode
        let arguments = try await buildLocationArguments(
            subcommand: "set",
            device: device,
            extraArgs: [
                "--",
                String(format: "%.6f", coordinate.latitude),
                String(format: "%.6f", coordinate.longitude)
            ]
        )

        // Sanitize all arguments before execution
        let sanitizedArgs = try ArgumentSanitizer.sanitizeSubprocessArgs(arguments)

        let result = try await runPython(
            arguments: sanitizedArgs,
            device: device,
            keepAlive: true,
            heldSessionRequiresTunnel: Self.connectionRequiresTunnel(sanitizedArgs)
        )

        // Check for common errors
        try parseResult(result)

        // Record success
        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        stats.recordSuccess(latencyMs: latencyMs)
        return nil
    }

    /// Set location using the persistent bridge (high-performance mode)
    /// This reuses a long-running Python process for significantly reduced latency
    private func setLocationViaPersistentBridge(
        _ coordinate: LocationCoordinate,
        for device: Device,
        requestID: UUID,
        sessionGeneration: UInt64?
    ) async throws -> LocationProviderAcknowledgement {
        try await PersistentLocationBridge.shared.setLocation(
            coordinate,
            for: device,
            requestID: requestID,
            sessionGeneration: sessionGeneration
        )
    }

    /// Enable or disable persistent bridge mode
    func setPerformanceMode(_ enabled: Bool) {
        usePersistentBridge = enabled
    }

    // MARK: Queue Strategy & Metrics

    /// Set the queue processing strategy
    /// - Parameter strategy: Use `.latestWins` for joystick mode (responsive),
    ///                       `.sequential` for route simulation (complete)
    func setQueueStrategy(_ strategy: QueueProcessingStrategy) async {
        await requestQueue.setStrategy(strategy)
        Logger.info("Queue strategy set to: \(strategy.rawValue)", category: .device)
    }

    /// Get current queue processing strategy
    func getQueueStrategy() async -> QueueProcessingStrategy {
        await requestQueue.currentStrategy()
    }

    /// Get queue lag metrics for monitoring
    func getQueueLagMetrics() async -> QueueLagMetrics {
        await requestQueue.getLagMetrics()
    }

    /// Reset queue lag metrics
    func resetQueueLagMetrics() async {
        await requestQueue.resetLagMetrics()
    }

    // MARK: Queue Processing

    private func startQueueProcessingIfNeeded() {
        guard queueProcessingTask == nil else { return }
        queueProcessingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
            await self.queueProcessingDidFinish()
        }
    }

    private func queueProcessingDidFinish() {
        queueProcessingTask = nil
    }

    /// Process queued location requests
    private func processQueue() async {
        // Prevent concurrent queue processing
        guard !(await requestQueue.processing()) else { return }
        await requestQueue.setProcessing(true)

        defer {
            Task {
                await requestQueue.setProcessing(false)
            }
        }

        while await requestQueue.peek() != nil {
            // Wait for rate limiter to allow request
            _ = await rateLimiter.waitForAllowance()

            // Dequeue and process
            guard let queuedRequest = await requestQueue.dequeue() else { break }

            // Record queue time for lag metrics
            await requestQueue.recordProcessed(queuedAt: queuedRequest.timestamp)

            do {
                if let context = queuedApplicationContexts[queuedRequest.id] {
                    let acknowledgement = try await setLocationViaPersistentBridge(
                        queuedRequest.coordinate,
                        for: queuedRequest.device,
                        requestID: context.request.id,
                        sessionGeneration: context.session.generation
                    )
                    let receipt = try LocationApplicationAcknowledgementRouter.accept(
                        request: context.request,
                        provisionalSession: context.session,
                        acknowledgement: acknowledgement,
                        generationTracker: &generationTracker
                    )
                    queuedApplicationContexts.removeValue(forKey: queuedRequest.id)
                    emit(.receipt(receipt))
                } else {
                    // Non-session utility queue entries retain the legacy one-shot path.
                    let arguments = try await buildLocationArguments(
                        subcommand: "set",
                        device: queuedRequest.device,
                        extraArgs: [
                            "--",
                            String(format: "%.6f", queuedRequest.coordinate.latitude),
                            String(format: "%.6f", queuedRequest.coordinate.longitude)
                        ]
                    )
                    let sanitizedArgs = try ArgumentSanitizer.sanitizeSubprocessArgs(arguments)
                    let result = try await runPython(
                        arguments: sanitizedArgs,
                        device: queuedRequest.device,
                        keepAlive: true,
                        heldSessionRequiresTunnel: Self.connectionRequiresTunnel(sanitizedArgs)
                    )
                    try parseResult(result)
                }

                stats.recordSuccess(latencyMs: 0) // Queue processing doesn't track individual latency
            } catch {
                queuedApplicationContexts.removeValue(forKey: queuedRequest.id)
                Logger.debug("Failed to process queued location request: \(error)", category: .device, deviceUDID: queuedRequest.device.id, iosVersion: queuedRequest.device.productVersion)
            }

            await requestQueue.finishInFlightRequest(queuedRequest.id)
        }
    }

    /// Build pymobiledevice3 arguments based on device connection type with validation
    /// Capability discovery selects direct or RSD access for developer services.
    @MainActor
    private func buildLocationArguments(subcommand: String, device: Device, extraArgs: [String] = []) throws -> [String] {
        var args = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", subcommand]
        try ArgumentSanitizer.validateDeviceUDID(device.id)
        let connection = TunneldManager.shared.locationConnectionArguments(for: device.id)
        if connection.first == "--rsd", connection.count >= 3 {
            guard ArgumentSanitizer.isValidIPv6Address(connection[1]) else {
                throw LocationInjectionError.injectionFailed("Invalid RSD address: \(connection[1])")
            }
            if let port = Int(connection[2]) {
                try ArgumentSanitizer.validatePort(port)
            }
        }
        args.append(contentsOf: connection)
        Logger.debug(
            "Location command uses \(connection.joined(separator: " "))",
            category: .device,
            deviceUDID: device.id,
            iosVersion: device.productVersion
        )
        args.append(contentsOf: extraArgs)
        return args
    }

    // MARK: Clear Location

    /// Clear simulated location (reset to real GPS) with validation
    func clearLocation(for device: Device) async throws {
        try ArgumentSanitizer.validateDeviceUDID(device.id)

        // Ending the held `simulate-location set` session is the real clear.
        let hadHeldSession = heldSimulationProcess != nil
        await stopHeldSimulation()
        if hadHeldSession {
            return
        }

        let arguments = try await buildLocationArguments(subcommand: "clear", device: device)
        let sanitizedArgs = try ArgumentSanitizer.sanitizeSubprocessArgs(arguments)
        let result = try await runPython(arguments: sanitizedArgs, device: device)

        if result.contains("InvalidServiceError") || result.contains("Unable to connect to Tunneld") {
            throw LocationInjectionError.tunneldNotRunning
        }
        if result.contains("DeviceNotFoundError") {
            throw LocationInjectionError.deviceNotFound
        }
        if result.contains("Traceback") || result.contains("rsd_dependency") {
            throw LocationInjectionError.clearFailed("The tunnel address is stale. Start Tunnel again, then clear.")
        }
        if result.contains("DeveloperModeError") {
            throw LocationInjectionError.developerModeRequired
        }
        if result.lowercased().contains("error") && !result.lowercased().contains("warning") {
            throw LocationInjectionError.clearFailed(Self.shortPythonError(result))
        }
    }

    private static func shortPythonError(_ result: String) -> String {
        if result.contains("Traceback") || result.contains("rsd_dependency") {
            return "Could not reach the tunnel. Start Tunnel again."
        }
        let lines = result.split(whereSeparator: \.isNewline).map(String.init)
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "pymobiledevice3 failed"
    }

    // MARK: Batch Injection

    /// Inject multiple coordinates in sequence (for route playback)
    func injectRoute(
        coordinates: [LocationCoordinate],
        for device: Device,
        intervalMs: Double,
        onProgress: @escaping (Int, Int, LocationCoordinate) -> Void
    ) async throws {
        for (index, coordinate) in coordinates.enumerated() {
            try await setLocation(coordinate, for: device)
            onProgress(index + 1, coordinates.count, coordinate)

            // Wait for interval
            if index < coordinates.count - 1 {
                try await Task.sleep(nanoseconds: UInt64(intervalMs * 1_000_000))
            }
        }
    }

    // MARK: Health Check

    /// Check if location injection is available for device
    func checkAvailability(for device: Device) async -> Result<Bool, LocationInjectionError> {
        let arguments = await buildDvtArguments(subcommand: "ls", device: device)

        do {
            let result = try await runPython(arguments: arguments, device: device)

            if result.contains("InvalidServiceError") || result.contains("Unable to connect to Tunneld") {
                return .failure(.tunneldNotRunning)
            }

            if result.contains("DeveloperModeError") {
                return .failure(.developerModeRequired)
            }

            if result.contains("DeviceNotFoundError") {
                return .failure(.deviceNotFound)
            }

            return .success(true)
        } catch {
            return .failure(.injectionFailed(error.localizedDescription))
        }
    }

    /// Build pymobiledevice3 DVT arguments (for general DVT commands like 'ls')
    @MainActor
    private func buildDvtArguments(subcommand: String, device: Device) -> [String] {
        var args = ["-m", "pymobiledevice3", "developer", "dvt", subcommand]
        args.append(contentsOf: TunneldManager.shared.locationConnectionArguments(for: device.id))
        if subcommand == "ls" {
            args.append("/")
        }
        return args
    }

    // MARK: Statistics

    func getStats() -> InjectionStats {
        return stats
    }

    func resetStats() {
        stats = InjectionStats()
    }

    // MARK: Pre-flight Checks

    /// Reachability + Developer Mode. Only a real DeveloperModeError means DM is off.
    private func performPreflight(for device: Device) async throws {
        // A `ConnectionType.wifi` device may be a Network transport reported directly by
        // usbmux. That path supports DVT with `--udid` and requires no RemoteXPC tunnel.
        // Do not hard-block it here; `buildDvtArguments` selects RSD/tunneld when valid
        // tunnel info exists and otherwise falls back to the verified direct `--udid` path.

        do {
            let testArgs = await buildDvtArguments(subcommand: "ls", device: device)
            let result = try await runPython(arguments: testArgs, timeoutSeconds: 15.0, device: device)
            if result.contains("DeveloperModeError") {
                throw LocationInjectionError.developerModeRequired
            }
            Logger.debug(
                "Pre-flight check passed for device \(device.id)",
                category: .device,
                deviceUDID: device.id,
                iosVersion: device.productVersion
            )
        } catch let error as LocationInjectionError {
            throw error
        } catch {
            throw LocationInjectionError.injectionFailed("Device not reachable: \(error.localizedDescription)")
        }
    }

    // MARK: Private Methods

    private func parseResult(_ result: String) throws {
        if result.contains("InvalidServiceError") || result.contains("Unable to connect to Tunneld") {
            stats.recordFailure()
            throw LocationInjectionError.tunneldNotRunning
        }

        if result.contains("DeviceNotFoundError") {
            stats.recordFailure()
            throw LocationInjectionError.deviceNotFound
        }

        if result.contains("DeveloperModeError") {
            stats.recordFailure()
            throw LocationInjectionError.developerModeRequired
        }

        // Handle DVT service error -402653150 (service not available)
        if result.contains("-402653150") || result.contains("402653150") {
            stats.recordFailure()
            throw LocationInjectionError.injectionFailed("DVT service unavailable. Ensure Developer Mode is enabled and device is trusted.")
        }

        // Handle connection/protocol errors
        if result.contains("ConnectionError") || result.contains("BrokenPipeError") {
            stats.recordFailure()
            throw LocationInjectionError.tunneldNotRunning
        }

        if result.contains("Traceback") || result.contains("rsd_dependency") {
            stats.recordFailure()
            throw LocationInjectionError.injectionFailed("Could not reach the tunnel. Start Tunnel again.")
        }

        let lowercased = result.lowercased()
        if lowercased.contains("error") && !lowercased.contains("warning") {
            stats.recordFailure()
            throw LocationInjectionError.injectionFailed(Self.shortPythonError(result))
        }
    }

    /// Run Python command with pymobiledevice3 with proper timeout protection
    /// - Parameters:
    ///   - arguments: Command line arguments for Python
    ///   - timeoutSeconds: Maximum execution time (uses configurable setting by default)
    ///   - device: Optional device for enhanced logging with iOS version context
    /// - Returns: Combined output from stdout and stderr
    /// - Throws: LocationInjectionError if execution fails or times out
    ///
    /// Security Features:
    /// - Command structure validation via SubprocessCommandValidator (defense-in-depth)
    /// - Output size limiting (prevents DoS via excessive output)
    /// - Security audit logging with device iOS version context
    /// - Input validation via ArgumentSanitizer (caller's responsibility)
    private func runPython(
        arguments: [String],
        timeoutSeconds: Double? = nil,
        device: Device? = nil,
        keepAlive: Bool = false,
        heldSessionRequiresTunnel: Bool = false,
        validateCommand: Bool = true
    ) async throws -> String {
        let timeout = await MainActor.run { timeoutSeconds ?? AppSettings.shared.commandTimeout }

        if keepAlive {
            heldSimulationProcess?.terminate()
            heldSimulationProcess = nil
            heldSimulationRequiresTunnel = false
        }

        // Security: Validate command structure against allowlist (defense-in-depth).
        // The internal test seam may disable this only for a controlled local executable.
        if validateCommand {
            try SubprocessCommandValidator.validateCommandStructure(arguments)
        }

        // Extract device context for enhanced logging
        let deviceUDID = device?.id
        let iosVersion = device?.productVersion

        // Security: Log full subprocess execution for audit trail with device context
        let fullCommand = "python3 " + arguments.joined(separator: " ")
        Logger.debug("[SECURITY] Subprocess execution: \(fullCommand)", category: .security, deviceUDID: deviceUDID, iosVersion: iosVersion, operation: "subprocess_exec")

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        var keepAliveProcessRetained = false

        defer {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if process.isRunning && (!keepAlive || !keepAliveProcessRetained) {
                process.terminate()
            }
        }

        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment using centralized configuration
        process.environment = ProcessEnvironment.configured()

        // Capture maxOutputSize and device context for use in closure
        let maxOutputSize = Self.maxOutputSize
        let capturedDeviceUDID = deviceUDID
        let capturedIOSVersion = iosVersion
        let capturedCommand = fullCommand

        if keepAlive {
            do {
                try process.run()
            } catch {
                Logger.error(
                    "Failed to execute python: \(error.localizedDescription)",
                    category: .device,
                    deviceUDID: capturedDeviceUDID,
                    iosVersion: capturedIOSVersion,
                    operation: "subprocess_error"
                )
                throw LocationInjectionError.injectionFailed(
                    "Python execution failed: \(error.localizedDescription)"
                )
            }

            let observationWindow = min(timeout, keepAliveObservationWindow)
            let holdDeadline = Date().addingTimeInterval(observationWindow)
            while process.isRunning && Date() < holdDeadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            if process.isRunning {
                retainSimulationProcess(
                    process,
                    requiresTunnel: heldSessionRequiresTunnel,
                    stableDeviceID: device?.id
                )
                keepAliveProcessRetained = true
                return ""
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let totalSize = outputData.count + errorData.count
            guard totalSize <= maxOutputSize else {
                throw LocationInjectionError.outputSizeExceeded
            }

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            return output + error
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
                do {
                    try process.run()

                    // Track timeout state with thread-safe access via resumeLock
                    var didTimeout = false

                    if !keepAlive {
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                            resumeLock.lock()
                            defer { resumeLock.unlock() }

                            if process.isRunning {
                                didTimeout = true
                                process.terminate()
                            }
                        }
                    }

                    process.waitUntilExit()

                    // Check if we timed out - both read and write are now protected by resumeLock
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        Logger.info("[SECURITY] Subprocess timed out after \(timeout)s for command: \(capturedCommand)", category: .security, deviceUDID: capturedDeviceUDID, iosVersion: capturedIOSVersion, operation: "subprocess_timeout")
                        continuation.resume(throwing: LocationInjectionError.timeout)
                        return
                    }

                    // Read output with size limit to prevent DoS
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    // Security: Check output size limit
                    let totalSize = outputData.count + errorData.count
                    if totalSize > maxOutputSize {
                        Logger.error("[SECURITY] Subprocess output exceeded limit: \(totalSize) bytes (max: \(maxOutputSize)) for command: \(capturedCommand)", category: .security, deviceUDID: capturedDeviceUDID, iosVersion: capturedIOSVersion, operation: "output_exceeded")
                        continuation.resume(throwing: LocationInjectionError.outputSizeExceeded)
                        return
                    }

                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let error = String(data: errorData, encoding: .utf8) ?? ""
                    let exitCode = process.terminationStatus

                    // Log detailed output with device context using structured metadata
                    // Use 2000 char limit for better debugging while staying within log size constraints
                    let truncationLimit = 2000
                    let stdoutTruncated = output.count > truncationLimit
                    let stderrTruncated = error.count > truncationLimit

                    var additionalInfo: [String: String] = [
                        "stdout": output.isEmpty ? "(empty)" : String(output.prefix(truncationLimit)),
                        "stderr": error.isEmpty ? "(empty)" : String(error.prefix(truncationLimit)),
                        "exit_code": "\(exitCode)",
                        "output_size": "\(totalSize)"
                    ]

                    // Add truncation flags when output was truncated
                    if stdoutTruncated {
                        additionalInfo["stdout_truncated"] = "true"
                        additionalInfo["stdout_original_length"] = "\(output.count)"
                    }
                    if stderrTruncated {
                        additionalInfo["stderr_truncated"] = "true"
                        additionalInfo["stderr_original_length"] = "\(error.count)"
                    }

                    let outputMetadata = LogMetadata(
                        deviceUDID: capturedDeviceUDID,
                        iosVersion: capturedIOSVersion,
                        operationType: "location_injection",
                        additionalInfo: additionalInfo
                    )

                    // Log for debugging with device context
                    if !output.isEmpty || !error.isEmpty {
                        Logger.info("Python subprocess completed", category: .device, metadata: outputMetadata)
                    }

                    // Security: Log successful completion with full context
                    Logger.debug("[SECURITY] Subprocess completed, exit_code=\(exitCode), output_size=\(totalSize) bytes", category: .security, deviceUDID: capturedDeviceUDID, iosVersion: capturedIOSVersion, operation: "subprocess_complete")

                    // Combine output and error for analysis
                    continuation.resume(returning: output + error)
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    // Log error with full device context and command info
                    let errorMetadata = LogMetadata(
                        deviceUDID: capturedDeviceUDID,
                        iosVersion: capturedIOSVersion,
                        operationType: "subprocess_error",
                        additionalInfo: [
                            "error": error.localizedDescription,
                            "command": capturedCommand
                        ]
                    )
                    Logger.error("Failed to execute python: \(error.localizedDescription)", category: .device, metadata: errorMetadata)
                    Logger.error("[SECURITY] Subprocess execution failed: \(error.localizedDescription)", category: .security, deviceUDID: capturedDeviceUDID, iosVersion: capturedIOSVersion, operation: "subprocess_error")
                    continuation.resume(throwing: LocationInjectionError.injectionFailed("Python execution failed: \(error.localizedDescription)"))
                }
            }
        }
    }

#if DEBUG
    func runPythonForTesting(
        arguments: [String],
        device: Device? = nil,
        keepAlive: Bool = false
    ) async throws -> String {
        try await runPython(
            arguments: arguments,
            device: device,
            keepAlive: keepAlive,
            validateCommand: false
        )
    }

    func hasHeldSimulationProcessForTesting() -> Bool {
        heldSimulationProcess?.isRunning == true
    }
#endif

    // MARK: - Security Testing Support

    /// Returns the maximum output size limit for testing purposes
    static var maxOutputSizeLimit: Int {
        return maxOutputSize
    }
}

// MARK: - Location Bridge Manager

/// High-level manager for location injection with retry and recovery
@MainActor
class LocationBridgeManager: ObservableObject {
    @Published var isInjecting: Bool = false
    @Published var lastInjectedLocation: LocationCoordinate?
    @Published var lastError: LocationInjectionError?
    @Published var injectionStats: InjectionStats = InjectionStats()

    private let bridge = DevLocationBridge()
    private var retryCount: Int = 0
    private let maxRetries: Int = 3

    func setLocation(_ coordinate: LocationCoordinate, for device: Device) async {
        isInjecting = true
        lastError = nil

        do {
            try await bridge.setLocation(coordinate, for: device)
            lastInjectedLocation = coordinate
            retryCount = 0
            injectionStats = await bridge.getStats()
        } catch let error as LocationInjectionError {
            lastError = error

            // Auto-retry for transient errors
            if retryCount < maxRetries && shouldRetry(error) {
                retryCount += 1
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
                await setLocation(coordinate, for: device)
                return
            }
        } catch {
            lastError = .injectionFailed(error.localizedDescription)
        }

        isInjecting = false
    }

    func clearLocation(for device: Device) async {
        isInjecting = true

        do {
            try await bridge.clearLocation(for: device)
            lastInjectedLocation = nil
            lastError = nil
        } catch let error as LocationInjectionError {
            lastError = error
        } catch {
            lastError = .clearFailed(error.localizedDescription)
        }

        isInjecting = false
    }

    func checkAvailability(for device: Device) async -> Bool {
        let result = await bridge.checkAvailability(for: device)
        switch result {
        case .success:
            return true
        case .failure(let error):
            lastError = error
            return false
        }
    }

    private func shouldRetry(_ error: LocationInjectionError) -> Bool {
        switch error {
        case .timeout, .rateLimited:
            return true
        default:
            return false
        }
    }
}