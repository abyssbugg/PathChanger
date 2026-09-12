import Foundation

struct PersistentBridgeRequestGate {
    private var pending: (requestID: UUID, generation: UInt64)?

    mutating func begin(requestID: UUID, generation: UInt64) throws {
        guard pending == nil else {
            throw PersistentLocationBridge.PersistentBridgeError.requestInProgress
        }
        pending = (requestID, generation)
    }

    func accepts(requestID: UUID, generation: UInt64) -> Bool {
        pending?.requestID == requestID && pending?.generation == generation
    }

    mutating func finish(requestID: UUID, generation: UInt64) {
        guard accepts(requestID: requestID, generation: generation) else { return }
        pending = nil
    }

    mutating func cancel() {
        pending = nil
    }
}

struct PersistentBridgeReadinessGate {
    private(set) var isReady = false

    mutating func consume(ready: Bool) -> Bool {
        guard ready, !isReady else { return false }
        isReady = true
        return true
    }
}

struct PersistentBridgeTerminationEvents {
    private var consumed = false

    mutating func consume(
        exitCode: Int32,
        intentional: Bool,
        session: LocationSessionIdentity?
    ) -> [LocationBridgeEvent] {
        guard !consumed else { return [] }
        consumed = true
        var events: [LocationBridgeEvent] = [.processTerminated(exitCode: exitCode)]
        if let session {
            events.append(.sessionLost(
                session,
                reason: intentional ? "intentional stop" : "unexpected process exit"
            ))
        }
        return events
    }
}

// MARK: - Persistent Location Bridge

/// A high-performance bridge that maintains persistent Python processes
/// for efficient location injection. Significantly reduces overhead for
/// high-frequency operations like joystick control.
///
/// Performance Improvement:
/// - Traditional: ~100ms per location update (process creation overhead)
/// - Persistent: ~10-20ms per location update (reuses process)
@MainActor
final class PersistentLocationBridge: ObservableObject {

    // MARK: - Types

    /// Request to send to Python bridge
    private struct BridgeRequest: Codable {
        let cmd: String
        var request_id: UUID = UUID()
        var session_generation: UInt64 = 0
        var lat: Double?
        var lng: Double?
        var udid: String?
        var rsd_address: String?
        var rsd_port: Int?
    }

    /// Stop the persistent bridge only when its cached connection was RSD/tunnel-backed.
    func stopIfUsingTunnel() async {
        guard usesTunnelTransport else { return }
        await stop()
    }

    /// Response from Python bridge
    private struct BridgeResponse: Codable {
        let success: Bool
        var request_id: UUID?
        var session_generation: UInt64?
        var error: String?
        var message: String?
        var ready: Bool?
    }

    /// Errors specific to persistent bridge
    enum PersistentBridgeError: Error, LocalizedError, Equatable {
        case processNotRunning
        case requestInProgress
        case processStartFailed(String)
        case timeout
        case invalidResponse(String)
        case bridgeError(String)
        case pythonNotFound

        var errorDescription: String? {
            switch self {
            case .processNotRunning:
                return "Python bridge process is not running"
            case .requestInProgress:
                return "Another persistent bridge request is already in progress"
            case .processStartFailed(let reason):
                return "Failed to start Python bridge: \(reason)"
            case .timeout:
                return "Bridge request timed out"
            case .invalidResponse(let response):
                return "Invalid response from bridge: \(response)"
            case .bridgeError(let message):
                return "Bridge error: \(message)"
            case .pythonNotFound:
                return "Python3 not found in PATH"
            }
        }
    }

    // MARK: - Properties

    /// Shared instance for app-wide usage
    static let shared = PersistentLocationBridge()

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

    // This type is `@MainActor`, so `responseBuffer`, `pendingContinuation` and
    // `timeoutTask` are already serialized by actor isolation. An explicit lock would be
    // redundant here and cannot be held safely across an `await`.
    private var responseBuffer: String = ""
    private var pendingContinuation: CheckedContinuation<BridgeResponse, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Bool, Never>?
    private var readyTimeoutTask: Task<Void, Never>?
    private var requestGate = PersistentBridgeRequestGate()
    private var readinessGate = PersistentBridgeReadinessGate()
    private var terminationEvents = PersistentBridgeTerminationEvents()
    private let eventHub = PersistentBridgeEventHub()
    private var currentSession: LocationSessionIdentity?
    private var isIntentionalStop = false
    private var isStarting = false
    private var processGeneration: UInt64 = 0

    private var python3Path: String { PythonPathResolver.path }
    private var bridgeScriptPath: String?

    private let responseTimeout: TimeInterval = 10.0
    private var responseTimeAccumulator: TimeInterval = 0
    private var usesTunnelTransport: Bool = false

    // MARK: - Initialization

    private init() {
        findPaths()
    }

    /// Find Python and bridge script paths
    private func findPaths() {
        // Find bridge script (in app bundle or workspace)
        let bundlePath = Bundle.main.path(forResource: "location_bridge", ofType: "py")
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"

        // Try bundle first, then workspace
        if let bundlePath = bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            bridgeScriptPath = bundlePath
        } else if FileManager.default.fileExists(atPath: workspacePath) {
            bridgeScriptPath = workspacePath
        } else {
            // Try relative to executable
            if let execPath = Bundle.main.executablePath {
                let execDir = (execPath as NSString).deletingLastPathComponent
                let relativePath = (execDir as NSString).appendingPathComponent("../Resources/scripts/location_bridge.py")
                if FileManager.default.fileExists(atPath: relativePath) {
                    bridgeScriptPath = relativePath
                }
            }
        }

        Logger.debug("[PersistentBridge] Python path: \(python3Path)", category: .device)
        Logger.debug("[PersistentBridge] Bridge script: \(bridgeScriptPath ?? "not found")", category: .device)
    }

    // MARK: - Public Methods

    /// Start the persistent Python bridge process
    func start() async throws {
        guard !isRunning else {
            Logger.debug("[PersistentBridge] Already running", category: .device)
            return
        }
        guard !isStarting else {
            throw PersistentBridgeError.requestInProgress
        }
        isStarting = true
        defer { isStarting = false }

        guard PythonPathResolver.isAvailable else {
            throw PersistentBridgeError.pythonNotFound
        }
        let pythonPath = python3Path

        guard let scriptPath = bridgeScriptPath else {
            throw PersistentBridgeError.processStartFailed("Bridge script not found")
        }

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

        newProcess.environment = ProcessEnvironment.configured()

        // Setup output handler
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleOutput(output)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Logger.error("[PersistentBridge] stderr: \(output)", category: .device)
            }
        }

        // Handle process termination
        newProcess.terminationHandler = { [weak self] process in
            guard let strongSelf = self else { return }
            let exitCode = process.terminationStatus
            Task { @MainActor in
                strongSelf.handleTermination(exitCode: exitCode)
            }
        }

        do {
            try newProcess.run()
            processGeneration &+= 1

            self.process = newProcess
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr

            // Wait for ready signal
            let ready = try await waitForReady()
            if !ready {
                throw PersistentBridgeError.processStartFailed("Bridge did not signal ready")
            }

            isRunning = true
            Logger.info("[PersistentBridge] Bridge started successfully", category: .device)
        } catch {
            Logger.error("[PersistentBridge] Failed to start: \(error.localizedDescription)", category: .device)
            cleanup()
            throw PersistentBridgeError.processStartFailed(error.localizedDescription)
        }
    }

    /// Stop the persistent bridge process
    func stop() async {
        guard isRunning else { return }
        isIntentionalStop = true

        Logger.info("[PersistentBridge] Stopping bridge process", category: .device)

        // Send quit command
        do {
            _ = try await sendCommand(BridgeRequest(cmd: "quit"))
        } catch {
            Logger.debug("[PersistentBridge] Quit command failed: \(error)", category: .device)
        }

        // Give process time to exit gracefully
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        if let process = process, process.isRunning {
            process.terminate()
        }

        cleanup()
    }

    /// Set location on device using persistent bridge
    /// - Parameters:
    ///   - coordinate: The location to simulate
    ///   - device: Target device
    /// - Throws: PersistentBridgeError on failure
    func setLocation(_ coordinate: LocationCoordinate, for device: Device, requestID: UUID = UUID(), sessionGeneration: UInt64? = nil) async throws {
        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }

        var request = BridgeRequest(cmd: "set_location")
        request.lat = coordinate.latitude
        request.lng = coordinate.longitude
        request.udid = device.id
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        request.request_id = requestID
        request.session_generation = sessionGeneration ?? processGeneration
        usesTunnelTransport = rsdInfo != nil
        currentSession = LocationSessionIdentity(
            stableDeviceID: device.id,
            transport: device.connectionType == .wifi ? .wifi : .usb,
            endpointClass: rsdInfo == nil ? .direct : .remoteServiceDiscovery,
            generation: request.session_generation
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let response = try await sendCommand(request)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Update stats
        requestCount += 1
        responseTimeAccumulator += duration
        averageResponseTime = responseTimeAccumulator / Double(requestCount)

        if !response.success {
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }

        Logger.debug("[PersistentBridge] Location set in \(String(format: "%.1f", duration * 1000))ms", category: .device)
    }

    /// Clear simulated location on device
    func clearLocation(for device: Device, requestID: UUID = UUID(), sessionGeneration: UInt64? = nil) async throws {
        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }

        var request = BridgeRequest(cmd: "clear_location")
        request.udid = device.id
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        request.request_id = requestID
        request.session_generation = sessionGeneration ?? processGeneration

        let response = try await sendCommand(request)

        if !response.success {
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }
    }

    /// Health check for the bridge
    func ping() async throws -> Bool {
        guard isRunning else { return false }

        let response = try await sendCommand(BridgeRequest(cmd: "ping"))
        return response.success
    }

    // MARK: - Private Methods

    func events() -> AsyncStream<LocationBridgeEvent> {
        eventHub.stream()
    }

    private func emit(_ event: LocationBridgeEvent) {
        eventHub.publish([event])
    }

    /// Wait for ready signal from Python process
    private func waitForReady() async throws -> Bool {
        if readinessGate.isReady { return true }
        return await withCheckedContinuation { continuation in
            readyContinuation = continuation
            readyTimeoutTask?.cancel()
            readyTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self, let pending = self.readyContinuation else { return }
                self.readyContinuation = nil
                self.readyTimeoutTask = nil
                pending.resume(returning: false)
            }
        }
    }

    /// Send command to bridge and wait for response
    private func sendCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
        guard let stdin = stdinPipe else {
            throw PersistentBridgeError.processNotRunning
        }
        try requestGate.begin(requestID: request.request_id, generation: request.session_generation)

        let data = try JSONEncoder().encode(request)
        guard var jsonString = String(data: data, encoding: .utf8),
              let commandData = (jsonString + "\n").data(using: .utf8) else {
            requestGate.finish(requestID: request.request_id, generation: request.session_generation)
            throw PersistentBridgeError.invalidResponse("Failed to encode request")
        }
        jsonString += "\n"
        let timeoutSeconds = responseTimeout

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled, let self, let pending = self.pendingContinuation else { return }
                self.pendingContinuation = nil
                self.timeoutTask = nil
                self.requestGate.finish(requestID: request.request_id, generation: request.session_generation)
                pending.resume(throwing: PersistentBridgeError.timeout)
            }
            do {
                try stdin.fileHandleForWriting.write(contentsOf: commandData)
            } catch {
                pendingContinuation = nil
                timeoutTask?.cancel()
                timeoutTask = nil
                requestGate.finish(requestID: request.request_id, generation: request.session_generation)
                continuation.resume(throwing: PersistentBridgeError.processNotRunning)
            }
        }
    }

    /// Handle output from Python process
    private func handleOutput(_ output: String) {
        responseBuffer += output

        // Check for complete JSON lines
        let lines = responseBuffer.components(separatedBy: "\n")
        responseBuffer = lines.last ?? ""

        for line in lines.dropLast() {
            guard !line.isEmpty else { continue }

            // Try to parse as JSON response
            if let data = line.data(using: .utf8),
               let response = try? JSONDecoder().decode(BridgeResponse.self, from: data) {

                // Check for ready signal
                if response.ready == true {
                    Logger.debug("[PersistentBridge] Received ready signal", category: .device)
                    if readinessGate.consume(ready: true), let pending = readyContinuation {
                        readyContinuation = nil
                        readyTimeoutTask?.cancel()
                        readyTimeoutTask = nil
                        pending.resume(returning: true)
                    }
                    continue
                }

                guard let responseID = response.request_id,
                      let responseGeneration = response.session_generation else {
                    Logger.info("[PersistentBridge] Ignoring response without request identity", category: .device)
                    continue
                }
                guard requestGate.accepts(requestID: responseID, generation: responseGeneration) else {
                    Logger.info("[PersistentBridge] Ignoring stale or mismatched response \(responseID)", category: .device)
                    continue
                }

                if let continuation = pendingContinuation {
                    pendingContinuation = nil
                    timeoutTask?.cancel()
                    timeoutTask = nil
                    requestGate.finish(requestID: responseID, generation: responseGeneration)
                    continuation.resume(returning: response)
                    return
                }
            }
        }
    }

    /// Handle process termination
    private func handleTermination(exitCode: Int32) {
        Logger.info("[PersistentBridge] Process terminated with exit code \(exitCode)", category: .device)

        isRunning = false

        if let pending = readyContinuation {
            readyContinuation = nil
            readyTimeoutTask?.cancel()
            readyTimeoutTask = nil
            pending.resume(returning: false)
        }
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            requestGate.cancel()
            continuation.resume(throwing: PersistentBridgeError.processNotRunning)
        }
        eventHub.publish(terminationEvents.consume(
            exitCode: exitCode,
            intentional: isIntentionalStop,
            session: currentSession
        ))
        cleanup()
    }

    /// Cleanup resources
    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning = false
        responseBuffer = ""

        // Reset stats
        requestCount = 0
        averageResponseTime = 0
        responseTimeAccumulator = 0
        usesTunnelTransport = false
    }
}

@MainActor
final class PersistentBridgeEventHub {
    private var continuations: [UUID: AsyncStream<LocationBridgeEvent>.Continuation] = [:]

    func stream() -> AsyncStream<LocationBridgeEvent> {
        let id = UUID()
        let pair = AsyncStream<LocationBridgeEvent>.makeStream()
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations.removeValue(forKey: id) }
        }
        continuations[id] = pair.continuation
        return pair.stream
    }

    func publish(_ events: [LocationBridgeEvent]) {
        for event in events {
            continuations.values.forEach { $0.yield(event) }
        }
    }
}
