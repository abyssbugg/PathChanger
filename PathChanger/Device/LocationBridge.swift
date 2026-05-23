import Foundation
import Darwin

// MARK: - Location Bridge

/// Authoritative public bridge for location injection.
///
/// `LocationBridge` is the **sole public type** callers should use to inject
/// or clear simulated GPS locations on iOS devices. It encapsulates two
/// internal execution surfaces:
///
/// 1. A long-lived Python helper (NDJSON over stdin/stdout) that holds DVT
///    + LocationSimulation context managers open per device, providing
///    ~10–20 ms per update after first-call cold start.
/// 2. A private `DevLocationBridge` executor (held as `executor` below) that
///    preserves rate limiting, request queueing, pre-flight checks, retry
///    policy, and InjectionStats accounting before delegating into the
///    NDJSON path above.
///
/// The public facade methods on this type — `setLocation`, `clearLocation`,
/// `getStats` — are the only API external callers should invoke. The
/// `setLocationViaNDJSON` / `clearLocationViaNDJSON` methods are reserved
/// for the internal executor and tests.
///
/// Established by ADR-001 (Python bridge architecture, revised) and the
/// Milestone-2 architectural consolidation.
@MainActor
final class LocationBridge: ObservableObject {

    // MARK: - Types

    /// Request to send to Python bridge
    private struct BridgeRequest: Codable {
        let request_id: String
        let cmd: String
        var lat: Double?
        var lng: Double?
        var udid: String?
        var rsd_address: String?
        var rsd_port: Int?

        init(cmd: String, requestID: String = UUID().uuidString) {
            self.request_id = requestID
            self.cmd = cmd
        }
    }

    /// Response from Python bridge
    private struct BridgeResponse: Codable {
        let request_id: String?
        let success: Bool?
        var error: String?
        var message: String?
        var ready: Bool?
        var fatal: Bool?
    }

    /// Errors specific to persistent bridge
    enum LocationBridgeError: Error, LocalizedError {
        case processNotRunning
        case processStartFailed(String)
        case timeout
        case invalidResponse(String)
        case bridgeError(String)
        case processExited(exitCode: Int32, details: String)
        case pythonNotFound
        case tunnelInvalidated(String)

        var errorDescription: String? {
            switch self {
            case .processNotRunning:
                return "Python bridge process is not running"
            case .processStartFailed(let reason):
                return "Failed to start Python bridge: \(reason)"
            case .timeout:
                return "Bridge request timed out"
            case .invalidResponse(let response):
                return "Invalid response from bridge: \(response)"
            case .bridgeError(let message):
                return "Bridge error: \(message)"
            case .processExited(let exitCode, let details):
                return "Bridge process exited with code \(exitCode): \(details)"
            case .pythonNotFound:
                return "Python3 not found in PATH"
            case .tunnelInvalidated(let reason):
                return "Tunnel invalidated: \(reason)"
            }
        }
    }

    // MARK: - Properties

    /// Shared instance for app-wide usage
    static let shared = LocationBridge()

    /// Whether the bridge process is currently running
    @Published private(set) var isRunning: Bool = false

    /// Last error encountered
    @Published private(set) var lastError: Error?

    /// Performance statistics
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var averageResponseTime: TimeInterval = 0

    // Private properties
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var responseBuffer: String = ""
    private var hasReceivedReady: Bool = false
    private var readyContinuation: CheckedContinuation<Bool, Error>?
    private var readyTimeoutTask: Task<Void, Never>?
    private var pendingContinuations: [String: CheckedContinuation<BridgeResponse, Error>] = [:]
    private var pendingTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var startTask: Task<Void, Error>?
    private var bridgeLifecycleGeneration: UInt64 = 0
    private var isStoppingBridge: Bool = false
    private var stderrBuffer: String = ""

    private var python3Path: String?
    private var bridgeScriptPath: String?

    private var readyTimeout: TimeInterval = 5.0
    private var responseTimeout: TimeInterval = 10.0
    private let maxResponseBufferBytes = 1_048_576
    private let maxDiagnosticBytes = 65_536
    private var responseTimeAccumulator: TimeInterval = 0

    /// Internal subprocess executor.
    ///
    /// Preserves rate limiting, request queueing, pre-flight checks, retry
    /// behaviour, and `InjectionStats` accounting. The executor delegates
    /// real wire I/O back into this `LocationBridge` via
    /// `setLocationViaNDJSON` / `clearLocationViaNDJSON`.
    ///
    /// Held as a private detail: external consumers must call the public
    /// facade methods (`setLocation`, `clearLocation`, `getStats`) instead
    /// of touching the executor directly.
    private let executor = DevLocationBridge()

    // MARK: - Initialization

    private init() {
        findPaths()
    }

    // MARK: - Public Facade API
    //
    // These are the only methods external callers (AppState, SimulationEngine,
    // MultiDeviceCoordinator, etc.) should use. They route through the
    // internal `executor` so that rate limiting, queueing, pre-flight, and
    // stats remain in force.

    /// Inject a simulated GPS location on the specified device.
    ///
    /// This is the **sole** entry point for location injection. It enforces
    /// rate limits, queues overflow requests, performs pre-flight checks,
    /// and records InjectionStats before delegating to the persistent
    /// NDJSON path.
    ///
    /// - Parameters:
    ///   - coordinate: GPS coordinate to inject. Must be valid per
    ///     `LocationCoordinate.validated()`.
    ///   - device: Target iOS device.
    /// - Throws: `LocationInjectionError` on failure.
    func setLocation(_ coordinate: LocationCoordinate, for device: Device) async throws {
        try await executor.setLocation(
            coordinate,
            for: device,
            priority: .normal,
            usePerformanceMode: true
        )
    }

    /// Clear the simulated location on the specified device.
    ///
    /// - Parameter device: Target iOS device.
    /// - Throws: `LocationInjectionError` on failure.
    func clearLocation(for device: Device) async throws {
        try await executor.clearLocation(for: device)
    }

    /// Current InjectionStats snapshot from the executor.
    func getStats() async -> InjectionStats {
        await executor.getStats()
    }

    nonisolated static func isTunnelInvalidationError(_ error: Error) -> Bool {
        switch error {
        case LocationBridgeError.tunnelInvalidated(_),
             LocationBridgeError.timeout,
             LocationBridgeError.processNotRunning:
            return true
        case LocationBridgeError.bridgeError(let message):
            return isTunnelTransportFailureMessage(message)
        case LocationBridgeError.processExited(_, let details):
            return isTunnelTransportFailureMessage(details)
        case let injectionError as LocationInjectionError:
            switch injectionError {
            case .tunneldNotRunning, .timeout:
                return true
            case .injectionFailed(let message), .clearFailed(let message):
                return isTunnelTransportFailureMessage(message)
            default:
                return false
            }
        default:
            return isTunnelTransportFailureMessage(error.localizedDescription)
        }
    }

    nonisolated static func isRecoverableTransportDisruption(_ message: String) -> Bool {
        guard isTunnelTransportFailureMessage(message) else {
            return false
        }

        let lowercased = message.lowercased()
        let terminalMarkers = [
            "security violation",
            "resolved path is unsafe",
            "developermodeerror",
            "developer mode disabled",
            "pairingerror",
            "not paired",
            "python3 not found",
            "invalid response from bridge",
            "unknown subcommand"
        ]
        return !terminalMarkers.contains { lowercased.contains($0) }
    }

    nonisolated private static func isTunnelTransportFailureMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        let markers = [
            "no route to host",
            "connectionterminatederror",
            "channel is closed",
            "brokenpipe",
            "broken pipe",
            "connection reset",
            "connection refused",
            "network is unreachable",
            "unable to connect to tunneld",
            "tunnel is not running",
            "no valid live rsd exists",
            "bridge request timed out",
            "timed out",
            "timeout"
        ]
        return markers.contains { lowercased.contains($0) }
    }

    /// Find Python and bridge script paths
    private func findPaths() {
        // Find python3 using the same pyenv/Homebrew-aware resolver as the rest of the app.
        let resolvedPythonPath = PythonPathResolver.path
        if FileManager.default.isExecutableFile(atPath: resolvedPythonPath) {
            python3Path = resolvedPythonPath
        }

        bridgeScriptPath = Self.resolveBridgeScriptPath()

        Logger.debug("[PersistentBridge] Python path: \(python3Path ?? "not found")", category: .device)
        Logger.debug("[PersistentBridge] Bridge script: \(bridgeScriptPath ?? "not found")", category: .device)
    }

    /// Resolve the bridge script path across packaged-app, dev-checkout, and SwiftPM-binary layouts.
    private static func resolveBridgeScriptPath() -> String? {
        let fileManager = FileManager.default

        // 1) Packaged app bundle: Contents/Resources/scripts/location_bridge.py
        if let resourceURL = Bundle.main.resourceURL {
            let bundledPath = resourceURL
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("location_bridge.py")
                .path
            if fileManager.isReadableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        // 2) SwiftPM Bundle.main.path lookups (top-level Resources or scripts subdirectory).
        if let directPath = Bundle.main.path(forResource: "location_bridge", ofType: "py") {
            return directPath
        }
        if let scriptsPath = Bundle.main.path(
            forResource: "location_bridge",
            ofType: "py",
            inDirectory: "scripts"
        ) {
            return scriptsPath
        }

        // 3) Workspace fallback for `swift run` and dev launches from the repo root.
        let workspacePath = fileManager.currentDirectoryPath + "/scripts/location_bridge.py"
        if fileManager.isReadableFile(atPath: workspacePath) {
            return workspacePath
        }

        // 4) Walk up from the executable looking for a Resources/scripts/ sibling.
        if let execPath = Bundle.main.executablePath {
            let candidates = [
                (execPath as NSString)
                    .deletingLastPathComponent
                    + "/../Resources/scripts/location_bridge.py",
                (execPath as NSString)
                    .deletingLastPathComponent
                    + "/../../Resources/scripts/location_bridge.py"
            ]
            for candidate in candidates {
                let normalized = (candidate as NSString).standardizingPath
                if fileManager.isReadableFile(atPath: normalized) {
                    return normalized
                }
            }
        }

        return nil
    }

    // MARK: - Public Methods

    /// Start the persistent Python bridge process
    func start() async throws {
        guard !isRunning else {
            Logger.debug("[PersistentBridge] Already running", category: .device)
            return
        }
        if let startTask {
            Logger.debug("[PersistentBridge] Awaiting bridge start already in progress", category: .device)
            try await startTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performStart()
        }
        startTask = task

        do {
            try await task.value
            startTask = nil
        } catch {
            startTask = nil
            throw error
        }
    }

    private func performStart() async throws {
        guard !isRunning else {
            Logger.debug("[PersistentBridge] Already running", category: .device)
            return
        }

        guard let pythonPath = python3Path else {
            throw LocationBridgeError.pythonNotFound
        }

        guard let scriptPath = bridgeScriptPath else {
            throw LocationBridgeError.processStartFailed("Bridge script not found")
        }
        let generation = advanceBridgeLifecycleGeneration()
        isStoppingBridge = false
        stderrBuffer = ""
        responseBuffer = ""
        hasReceivedReady = false

        Logger.info("[PersistentBridge] Starting bridge process", category: .device)

        let newProcess = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: pythonPath)
        newProcess.arguments = ["-u", scriptPath]  // -u for unbuffered output
        newProcess.standardInput = stdin
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr

        // Set environment
        newProcess.environment = ProcessEnvironment.configured(preserveExistingPath: true)

        // Setup output handler
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleOutput(output, generation: generation)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logger.error("[PersistentBridge] stderr: \(output)", category: .device)
                guard let strongSelf = self else { return }
                Task { @MainActor in
                    strongSelf.handleStderr(output, generation: generation)
                }
            }
        }

        // Handle process termination
        newProcess.terminationHandler = { [weak self] process in
            guard let strongSelf = self else { return }
            let exitCode = process.terminationStatus
            let reason = process.terminationReason
            Task { @MainActor in
                strongSelf.handleTermination(
                    exitCode: exitCode,
                    reason: reason,
                    generation: generation,
                    process: process
                )
            }
        }

        do {
            self.process = newProcess
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            try newProcess.run()

            // Wait for ready signal
            let ready = try await waitForReady(generation: generation)
            if !ready {
                throw LocationBridgeError.processStartFailed("Bridge did not signal ready")
            }
            guard isCurrentBridgeLifecycle(generation), process === newProcess else {
                throw LocationBridgeError.processNotRunning
            }

            isRunning = true
            lastError = nil
            Logger.info("[PersistentBridge] Bridge started successfully", category: .device)
        } catch {
            Logger.error("[PersistentBridge] Failed to start: \(error.localizedDescription)", category: .device)
            cleanup(terminateProcess: true, error: error)
            throw LocationBridgeError.processStartFailed(error.localizedDescription)
        }
    }

    /// Stop the persistent bridge process
    func stop() async {
        guard isRunning || process != nil || startTask != nil || readyContinuation != nil || !pendingContinuations.isEmpty else { return }

        Logger.info("[PersistentBridge] Stopping bridge process", category: .device)
        isStoppingBridge = true
        isRunning = false
        startTask?.cancel()
        startTask = nil

        let stopError = LocationBridgeError.processNotRunning
        completeReady(.failure(stopError))
        failPendingContinuations(with: stopError)
        let processToStop = process

        // Send quit command
        do {
            _ = try await sendCommand(BridgeRequest(cmd: "quit"))
        } catch {
            Logger.debug("[PersistentBridge] Quit command failed: \(error)", category: .device)
        }

        // Give process time to exit gracefully
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        if let processToStop, processToStop.isRunning {
            processToStop.terminate()
            try? await Task.sleep(nanoseconds: 250_000_000)
            if processToStop.isRunning {
                Darwin.kill(processToStop.processIdentifier, SIGKILL)
            }
        }

        cleanup(terminateProcess: false)
        _ = advanceBridgeLifecycleGeneration()
        isStoppingBridge = false
    }

    // MARK: - Internal NDJSON Methods
    //
    // These are called by the internal `executor` (DevLocationBridge) after
    // it has run rate limiting, queueing, pre-flight, and stats. External
    // callers must NOT invoke these directly — use `setLocation` /
    // `clearLocation` above. Visibility remains module-internal so tests
    // and the executor can reach them.

    /// Set location on device via the persistent NDJSON Python helper.
    ///
    /// Internal entry point. Use the public `setLocation(_:for:)` facade
    /// from outside the bridge.
    ///
    /// - Throws: `LocationBridgeError` on failure.
    func setLocationViaNDJSON(_ coordinate: LocationCoordinate, for device: Device) async throws {
        let rsdInfo = try await rsdInfoForBridgeRequest(for: device)
        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        var request = BridgeRequest(cmd: "set_location")
        request.lat = coordinate.latitude
        request.lng = coordinate.longitude
        request.udid = device.id
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }

        let startTime = CFAbsoluteTimeGetCurrent()
        let response: BridgeResponse
        do {
            response = try await sendCommand(request)
        } catch {
            if Self.isTunnelInvalidationError(error) {
                await invalidateTunnelAndResetBridge(after: error, device: device, operation: "set_location")
            }
            throw error
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Update stats
        requestCount += 1
        responseTimeAccumulator += duration
        averageResponseTime = responseTimeAccumulator / Double(requestCount)

        if response.success != true {
            let error = LocationBridgeError.bridgeError(response.error ?? "Unknown error")
            if Self.isTunnelInvalidationError(error) {
                await invalidateTunnelAndResetBridge(after: error, device: device, operation: "set_location")
            }
            throw error
        }

        Logger.debug("[LocationBridge] Location set in \(String(format: "%.1f", duration * 1000))ms", category: .device)
    }

    /// Clear simulated location via the persistent NDJSON Python helper.
    ///
    /// Internal entry point. Use the public `clearLocation(for:)` facade
    /// from outside the bridge.
    func clearLocationViaNDJSON(for device: Device) async throws {
        let rsdInfo = try await rsdInfoForBridgeRequest(for: device)
        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        var request = BridgeRequest(cmd: "clear_location")
        request.udid = device.id
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        let response: BridgeResponse
        do {
            response = try await sendCommand(request)
        } catch {
            if Self.isTunnelInvalidationError(error) {
                await invalidateTunnelAndResetBridge(after: error, device: device, operation: "clear_location")
            }
            throw error
        }

        if response.success != true {
            let error = LocationBridgeError.bridgeError(response.error ?? "Unknown error")
            if Self.isTunnelInvalidationError(error) {
                await invalidateTunnelAndResetBridge(after: error, device: device, operation: "clear_location")
            }
            throw error
        }
    }

    /// Health check for the bridge
    func ping() async throws -> Bool {
        guard isRunning else { return false }

        let response = try await sendCommand(BridgeRequest(cmd: "ping"))
        return response.success == true
    }

    // MARK: - Private Methods
    private func advanceBridgeLifecycleGeneration() -> UInt64 {
        bridgeLifecycleGeneration &+= 1
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
        for task in pendingTimeoutTasks.values {
            task.cancel()
        }
        pendingTimeoutTasks.removeAll()
        return bridgeLifecycleGeneration
    }

    private func isCurrentBridgeLifecycle(_ generation: UInt64) -> Bool {
        bridgeLifecycleGeneration == generation
    }

    private func rsdInfoForBridgeRequest(for device: Device) async throws -> TunnelInfo? {
        let rsdInfo = TunneldManager.shared.getRsdInfo(for: device.id)
        guard rsdInfo == nil, requiresLiveRsdInfo(for: device) else {
            return rsdInfo
        }

        let reason = "No valid live RSD exists for \(device.displayName) (\(device.id))"
        await resetBridgeAfterTunnelInvalidation(reason: reason)
        throw LocationBridgeError.tunnelInvalidated(reason)
    }

    private func requiresLiveRsdInfo(for device: Device) -> Bool {
        if device.connectionType == .wifi {
            return true
        }
        return (device.iosMajorVersion ?? 0) >= 17
    }

    private func invalidateTunnelAndResetBridge(
        after error: Error,
        device: Device,
        operation: String
    ) async {
        let reason = "\(operation) failed for \(device.displayName) (\(device.id)): \(error.localizedDescription)"
        TunneldManager.shared.invalidateActiveTunnelAfterTransportFailure(reason)
        await resetBridgeAfterTunnelInvalidation(reason: reason)
    }

    private func resetBridgeAfterTunnelInvalidation(reason: String) async {
        Logger.info("[PersistentBridge] Resetting bridge after tunnel invalidation: \(reason)", category: .device)
        await stop()
    }

    /// Wait for ready signal from Python process
    private func waitForReady(generation: UInt64) async throws -> Bool {
        if hasReceivedReady {
            return true
        }

        guard readyContinuation == nil else {
            throw LocationBridgeError.processStartFailed("Bridge readiness wait already in progress")
        }
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            readyTimeoutTask?.cancel()
            readyTimeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.readyTimeout * 1_000_000_000))
                guard self.isCurrentBridgeLifecycle(generation) else { return }
                self.completeReady(.failure(LocationBridgeError.timeout))
            }
        }
    }

    /// Send command to bridge and wait for response
    private func sendCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
        guard let stdin = stdinPipe, let process, process.isRunning else {
            throw LocationBridgeError.processNotRunning
        }
        let generation = bridgeLifecycleGeneration

        // Encode request
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(request),
              var jsonString = String(data: data, encoding: .utf8) else {
            throw LocationBridgeError.invalidResponse("Failed to encode request")
        }
        jsonString += "\n"

        // Send request
        guard let commandData = jsonString.data(using: .utf8) else {
            throw LocationBridgeError.invalidResponse("Failed to convert request to data")
        }


        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            let requestID = request.request_id
            setPendingContinuation(continuation, for: requestID)
            pendingTimeoutTasks[requestID] = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.responseTimeout * 1_000_000_000))
                guard self.isCurrentBridgeLifecycle(generation) else { return }
                self.timeoutPendingContinuation(for: requestID)
            }

            do {
                try stdin.fileHandleForWriting.write(contentsOf: commandData)
            } catch {
                completePendingContinuation(for: requestID, with: .failure(LocationBridgeError.processNotRunning))
            }
        }
    }

    private func setPendingContinuation(
        _ continuation: CheckedContinuation<BridgeResponse, Error>,
        for requestID: String
    ) {
        pendingContinuations[requestID] = continuation
    }

    private func timeoutPendingContinuation(for requestID: String) {
        completePendingContinuation(for: requestID, with: .failure(LocationBridgeError.timeout))
    }

    private func completeReady(_ result: Result<Bool, Error>) {
        guard let continuation = readyContinuation else {
            return
        }

        readyContinuation = nil
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil

        switch result {
        case .success(let ready):
            continuation.resume(returning: ready)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func completePendingContinuation(
        for requestID: String,
        with result: Result<BridgeResponse, Error>
    ) {
        guard let continuation = pendingContinuations.removeValue(forKey: requestID) else {
            return
        }

        pendingTimeoutTasks.removeValue(forKey: requestID)?.cancel()

        switch result {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func failPendingContinuations(with error: Error) {
        let requestIDs = Array(pendingContinuations.keys)
        for requestID in requestIDs {
            completePendingContinuation(for: requestID, with: .failure(error))
        }
    }

    private func failBridge(with error: Error, generation: UInt64) {
        guard isCurrentBridgeLifecycle(generation) else { return }
        lastError = error
        Logger.error("[PersistentBridge] Failing bridge: \(error.localizedDescription)", category: .device)
        cleanup(terminateProcess: true, error: error)
    }

    /// Handle output from Python process
    private func handleOutput(_ output: String, generation: UInt64) {
        guard isCurrentBridgeLifecycle(generation) else {
            Logger.debug("[PersistentBridge] Ignoring output from stale bridge generation", category: .device)
            return
        }
        responseBuffer += output
        guard responseBuffer.utf8.count <= maxResponseBufferBytes else {
            failBridge(
                with: LocationBridgeError.invalidResponse("Bridge output exceeded \(maxResponseBufferBytes) bytes without a complete frame"),
                generation: generation
            )
            return
        }

        // Check for complete JSON lines
        let lines = responseBuffer.components(separatedBy: "\n")
        responseBuffer = lines.last ?? ""

        for line in lines.dropLast() {
            guard !line.isEmpty else { continue }

            // Try to parse as JSON response
            guard let data = line.data(using: .utf8) else {
                failBridge(with: LocationBridgeError.invalidResponse(line), generation: generation)
                return
            }

            let response: BridgeResponse
            do {
                response = try JSONDecoder().decode(BridgeResponse.self, from: data)
            } catch {
                failBridge(with: LocationBridgeError.invalidResponse(line), generation: generation)
                return
            }

            // Check for ready signal
            if response.ready == true {
                guard !isStoppingBridge else {
                    Logger.debug("[PersistentBridge] Ignoring ready signal while bridge is stopping", category: .device)
                    continue
                }
                hasReceivedReady = true
                Logger.debug("[PersistentBridge] Received ready signal", category: .device)
                completeReady(.success(true))
                continue
            }

            if response.fatal == true {
                failBridge(
                    with: LocationBridgeError.bridgeError(response.error ?? "Fatal bridge error"),
                    generation: generation
                )
                return
            }

            guard let requestID = response.request_id, !requestID.isEmpty else {
                failBridge(
                    with: LocationBridgeError.invalidResponse("Bridge response missing request_id: \(line)"),
                    generation: generation
                )
                return
            }

            completePendingContinuation(for: requestID, with: .success(response))
        }
    }
    private func handleStderr(_ output: String, generation: UInt64) {
        guard isCurrentBridgeLifecycle(generation) else { return }
        appendDiagnostic(output)
    }

    /// Handle process termination
    private func handleTermination(
        exitCode: Int32,
        reason: Process.TerminationReason,
        generation: UInt64,
        process terminatedProcess: Process
    ) {
        guard isCurrentBridgeLifecycle(generation), process === terminatedProcess else {
            Logger.debug("[PersistentBridge] Ignoring stale bridge process termination", category: .device)
            return
        }

        Logger.info("[PersistentBridge] Process terminated with exit code \(exitCode)", category: .device)
        isRunning = false

        if isStoppingBridge && exitCode == 0 {
            cleanup(terminateProcess: false, invalidateLifecycle: false)
            return
        }

        let error = bridgeExitError(exitCode: exitCode, reason: reason)
        lastError = error
        cleanup(terminateProcess: false, error: error)
    }

    /// Cleanup resources
    private func cleanup(
        terminateProcess: Bool,
        error: Error? = nil,
        invalidateLifecycle: Bool = true
    ) {
        if let error {
            completeReady(.failure(error))
            failPendingContinuations(with: error)
        } else {
            completeReady(.failure(LocationBridgeError.processNotRunning))
            failPendingContinuations(with: LocationBridgeError.processNotRunning)
        }
        let processToCleanup = process
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if terminateProcess, let processToCleanup, processToCleanup.isRunning {
            processToCleanup.terminate()
            let pid = processToCleanup.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                if processToCleanup.isRunning {
                    Darwin.kill(pid, SIGKILL)
                }
            }
        }

        stdinPipe?.fileHandleForWriting.closeFile()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
        readyContinuation = nil

        for task in pendingTimeoutTasks.values {
            task.cancel()
        }
        pendingTimeoutTasks.removeAll()
        pendingContinuations.removeAll()

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning = false
        isStoppingBridge = false
        startTask = nil
        responseBuffer = ""
        hasReceivedReady = false
        stderrBuffer = ""

        // Reset stats
        requestCount = 0
        averageResponseTime = 0
        responseTimeAccumulator = 0

        if invalidateLifecycle {
            _ = advanceBridgeLifecycleGeneration()
        }
    }

    private func bridgeExitError(exitCode: Int32, reason: Process.TerminationReason) -> LocationBridgeError {
        var details = terminationReasonDescription(reason)
        let diagnostic = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !diagnostic.isEmpty {
            details += "; diagnostics: \(boundedDiagnostic(diagnostic))"
        }
        return .processExited(exitCode: exitCode, details: details)
    }

    private func terminationReasonDescription(_ reason: Process.TerminationReason) -> String {
        switch reason {
        case .exit:
            return "process exited"
        case .uncaughtSignal:
            return "process terminated by signal"
        @unknown default:
            return "process terminated"
        }
    }

    private func appendDiagnostic(_ output: String) {
        stderrBuffer += output
        while stderrBuffer.utf8.count > maxDiagnosticBytes {
            stderrBuffer.removeFirst()
        }
    }

    private func boundedDiagnostic(_ diagnostic: String) -> String {
        if diagnostic.count <= 4000 {
            return diagnostic
        }
        return String(diagnostic.suffix(4000))
    }

    #if DEBUG
    func testOverrideBridgeConfiguration(
        bridgeScriptPath: String,
        readyTimeout: TimeInterval = 5.0,
        responseTimeout: TimeInterval = 10.0
    ) {
        self.bridgeScriptPath = bridgeScriptPath
        self.readyTimeout = readyTimeout
        self.responseTimeout = responseTimeout
        self.hasReceivedReady = false
    }

    func testRestoreBridgeConfiguration() {
        findPaths()
        readyTimeout = 5.0
        responseTimeout = 10.0
        hasReceivedReady = false
        lastError = nil
    }

    func testInjectBridgeOutput(_ output: String) {
        handleOutput(output, generation: bridgeLifecycleGeneration)
    }

    var testBridgeLifecycleGeneration: UInt64 {
        bridgeLifecycleGeneration
    }

    var testHasStartInProgress: Bool {
        startTask != nil
    }
    #endif
}
