//
//  DevLocationBridge.swift
//  PathChanger
//
//  Bridge to pymobiledevice3 for location injection on iOS 17+
//  Supports both USB (--udid) and WiFi via lockdown tunnel (--rsd)
//

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
            return "Tunnel is not running. This is required for iOS 17+ location injection."
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

// MARK: - Dev Location Bridge

/// Bridge to pymobiledevice3 for iOS 17+ location simulation.
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
actor DevLocationBridge {

    // MARK: Configuration
    private var python3Path: String { PythonPathResolver.path }

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

    private func retainSimulationProcess(_ process: Process, requiresTunnel: Bool) {
        heldSimulationProcess = process
        heldSimulationRequiresTunnel = requiresTunnel
    }

    func stopHeldSimulation() {
        heldSimulationProcess?.terminate()
        heldSimulationProcess = nil
        heldSimulationRequiresTunnel = false
    }

    /// Stop only sessions whose connection disappears with the RemoteXPC tunnel.
    func stopTunnelDependentSimulation() async {
        if heldSimulationRequiresTunnel {
            stopHeldSimulation()
        }
        await PersistentLocationBridge.shared.stopIfUsingTunnel()
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
    func setLocation(_ coordinate: LocationCoordinate, for device: Device, priority: QueuedLocationRequest.RequestPriority = .normal, usePerformanceMode: Bool = false) async throws {
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

            // Use strategy-aware enqueue (latest-wins for joystick, sequential for routes)
            let enqueueResult = await requestQueue.enqueueWithStrategy(queuedRequest)

            switch enqueueResult {
            case .success:
                // Notify user via toast (only if not in performance mode to avoid spam)
                if !usePerformanceMode {
                    await MainActor.run {
                        ToastManager.shared.warning("Location update queued (rate limited)")
                    }
                }

                // Process queue in background
                Task {
                    await processQueue()
                }

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
                try await setLocationViaPersistentBridge(coordinate, for: device)
                let latencyMs = Date().timeIntervalSince(startTime) * 1000
                stats.recordSuccess(latencyMs: latencyMs)
                return
            } catch {
                // Fall back to subprocess mode if persistent bridge fails
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
    }

    /// Set location using the persistent bridge (high-performance mode)
    /// This reuses a long-running Python process for significantly reduced latency
    private func setLocationViaPersistentBridge(_ coordinate: LocationCoordinate, for device: Device) async throws {
        try await PersistentLocationBridge.shared.setLocation(coordinate, for: device)
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
                // Process the queued request directly (bypass rate limiting since we already waited)
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

                stats.recordSuccess(latencyMs: 0) // Queue processing doesn't track individual latency
            } catch {
                Logger.debug("Failed to process queued location request: \(error)", category: .device, deviceUDID: queuedRequest.device.id, iosVersion: queuedRequest.device.productVersion)
            }
        }
    }

    /// Build pymobiledevice3 arguments based on device connection type with validation
    /// iOS 17+ requires tunnel access for developer services
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
        stopHeldSimulation()
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
        heldSessionRequiresTunnel: Bool = false
    ) async throws -> String {
        let timeout = await MainActor.run { timeoutSeconds ?? AppSettings.shared.commandTimeout }

        if keepAlive {
            heldSimulationProcess?.terminate()
            heldSimulationProcess = nil
            heldSimulationRequiresTunnel = false
        }

        // Security: Validate command structure against allowlist (defense-in-depth)
        // This catches any injection attempts that bypass other validation layers
        try SubprocessCommandValidator.validateCommandStructure(arguments)

        // Extract device context for enhanced logging
        let deviceUDID = device?.id
        let iosVersion = device?.productVersion

        // Security: Log full subprocess execution for audit trail with device context
        let fullCommand = "python3 " + arguments.joined(separator: " ")
        Logger.debug("[SECURITY] Subprocess execution: \(fullCommand)", category: .security, deviceUDID: deviceUDID, iosVersion: iosVersion, operation: "subprocess_exec")

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        defer {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if !keepAlive, process.isRunning {
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

                    if keepAlive {
                        // pymobiledevice3 10.x `simulate-location set` applies the pin
                        // then waits for Return so the DVT session stays open.
                        let holdDeadline = Date().addingTimeInterval(min(timeout, 4.0))
                        while process.isRunning && Date() < holdDeadline {
                            Thread.sleep(forTimeInterval: 0.1)
                        }

                        // Only claim the continuation when we are actually going to resume it.
                        // A process that has already exited (every failure case: no device,
                        // tunnel down, DVT error) must fall through to the output-parsing path
                        // below so the caller receives the error instead of hanging forever.
                        var alreadyResumed = false
                        var holdsSession = false
                        resumeLock.lock()
                        if hasResumed {
                            alreadyResumed = true
                        } else if process.isRunning {
                            hasResumed = true
                            holdsSession = true
                        }
                        resumeLock.unlock()

                        if alreadyResumed {
                            return
                        }

                        if holdsSession {
                            Task {
                                await self.retainSimulationProcess(
                                    process,
                                    requiresTunnel: heldSessionRequiresTunnel
                                )
                                // Resume only after actor-isolated ownership has been stored.
                                // Otherwise the caller can immediately clear/replace a session
                                // before `heldSimulationProcess` points at it.
                                continuation.resume(returning: "")
                            }
                            return
                        }
                    } else {
                        process.waitUntilExit()
                    }

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
