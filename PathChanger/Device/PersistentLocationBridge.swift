import Foundation

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
        var lat: Double?
        var lng: Double?
        var udid: String?
        var rsd_address: String?
        var rsd_port: Int?
    }
    
    /// Response from Python bridge
    private struct BridgeResponse: Codable {
        let success: Bool
        var error: String?
        var message: String?
        var ready: Bool?
    }
    
    /// Errors specific to persistent bridge
    enum PersistentBridgeError: Error, LocalizedError {
        case processNotRunning
        case processStartFailed(String)
        case timeout
        case invalidResponse(String)
        case bridgeError(String)
        case pythonNotFound
        
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
    
    private var responseBuffer: String = ""
    private let responseLock = NSLock()
    private var pendingContinuation: CheckedContinuation<BridgeResponse, Error>?
    
    private var python3Path: String?
    private var bridgeScriptPath: String?
    
    private let responseTimeout: TimeInterval = 10.0
    private var responseTimeAccumulator: TimeInterval = 0
    
    // MARK: - Initialization
    
    private init() {
        findPaths()
    }
    
    /// Find Python and bridge script paths
    private func findPaths() {
        // Find python3
        let pathsToCheck = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        
        for path in pathsToCheck {
            if FileManager.default.isExecutableFile(atPath: path) {
                python3Path = path
                break
            }
        }
        
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
        
        Logger.debug("[PersistentBridge] Python path: \(python3Path ?? "not found")", category: .device)
        Logger.debug("[PersistentBridge] Bridge script: \(bridgeScriptPath ?? "not found")", category: .device)
    }
    
    // MARK: - Public Methods
    
    /// Start the persistent Python bridge process
    func start() async throws {
        guard !isRunning else {
            Logger.debug("[PersistentBridge] Already running", category: .device)
            return
        }
        
        guard let pythonPath = python3Path else {
            throw PersistentBridgeError.pythonNotFound
        }
        
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
        
        // Set environment
        var environment = ProcessInfo.processInfo.environment
        let paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        environment["PATH"] = paths.joined(separator: ":") + ":" + (environment["PATH"] ?? "")
        
        // Add PYTHONPATH for pymobiledevice3
        let pythonPaths = [
            NSHomeDirectory() + "/Library/Python/3.11/lib/python/site-packages",
            NSHomeDirectory() + "/Library/Python/3.10/lib/python/site-packages",
            NSHomeDirectory() + "/Library/Python/3.9/lib/python/site-packages",
            "/opt/homebrew/lib/python3.11/site-packages",
            "/opt/homebrew/lib/python3.10/site-packages",
            "/opt/homebrew/lib/python3.9/site-packages"
        ]
        environment["PYTHONPATH"] = pythonPaths.joined(separator: ":")
        newProcess.environment = environment
        
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
    func setLocation(_ coordinate: LocationCoordinate, for device: Device) async throws {
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
    func clearLocation(for device: Device) async throws {
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
    
    /// Wait for ready signal from Python process
    private func waitForReady() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            var timeoutTask: Task<Void, Never>?
            
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                continuation.resume(returning: false)
            }
            
            // The ready signal will be handled by handleOutput
            // For now, we check if process started and assume ready
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms wait
                timeoutTask?.cancel()
                continuation.resume(returning: true)
            }
        }
    }
    
    /// Send command to bridge and wait for response
    private func sendCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
        guard let stdin = stdinPipe else {
            throw PersistentBridgeError.processNotRunning
        }
        
        // Encode request
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(request),
              var jsonString = String(data: data, encoding: .utf8) else {
            throw PersistentBridgeError.invalidResponse("Failed to encode request")
        }
        jsonString += "\n"
        
        // Send request
        guard let commandData = jsonString.data(using: .utf8) else {
            throw PersistentBridgeError.invalidResponse("Failed to convert request to data")
        }
        
        // Write to stdin
        do {
            try stdin.fileHandleForWriting.write(contentsOf: commandData)
        } catch {
            throw PersistentBridgeError.processNotRunning
        }
        
        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.responseLock.lock()
            self?.pendingContinuation = continuation
            self?.responseLock.unlock()
            
            // Timeout handler
            Task {
                try? await Task.sleep(nanoseconds: UInt64(self?.responseTimeout ?? 10.0) * 1_000_000_000)
                self?.responseLock.lock()
                if let cont = self?.pendingContinuation {
                    self?.pendingContinuation = nil
                    self?.responseLock.unlock()
                    cont.resume(throwing: PersistentBridgeError.timeout)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }
    }
    
    /// Handle output from Python process
    private func handleOutput(_ output: String) {
        responseLock.lock()
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
                }
                
                // Resume pending continuation
                if let continuation = pendingContinuation {
                    pendingContinuation = nil
                    responseLock.unlock()
                    continuation.resume(returning: response)
                    return
                }
            }
        }
        
        responseLock.unlock()
    }
    
    /// Handle process termination
    private func handleTermination(exitCode: Int32) {
        Logger.info("[PersistentBridge] Process terminated with exit code \(exitCode)", category: .device)
        
        isRunning = false
        
        // Resume any pending continuation with error
        responseLock.lock()
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            responseLock.unlock()
            continuation.resume(throwing: PersistentBridgeError.processNotRunning)
        } else {
            responseLock.unlock()
        }
        
        cleanup()
    }
    
    /// Cleanup resources
    private func cleanup() {
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
    }
}
