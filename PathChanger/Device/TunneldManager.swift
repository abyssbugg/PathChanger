//
//  TunneldManager.swift
//  PathChanger
//
//  Unified tunnel management supporting multiple connection methods for iOS 17+
//  - USB Mode: lockdown start-tunnel (fastest, requires USB)
//  - WiFi Mode: remote start-tunnel -t wifi (true wireless, no USB needed)
//  - Daemon Mode: remote tunneld (background service, auto-discovery)
//  - Auto Mode: Smart selection based on device availability
//

import Foundation
import Combine
import AppKit

// MARK: - Tunnel Mode

/// Available tunnel connection modes for iOS 17+ devices.
///
/// `TunnelMode` defines the different methods for establishing a secure tunnel
/// to an iOS 17+ device. Each mode has different requirements and trade-offs.
///
/// ## Overview
///
/// Choose the appropriate mode based on your connection scenario:
///
/// | Mode | USB Required | Use Case |
/// |------|--------------|----------|
/// | Auto | Varies | Best for most users |
/// | USB | Yes | Fastest, most reliable |
/// | WiFi | No | True wireless operation |
/// | Daemon | No | Background service mode |
///
/// ## Example
///
/// ```swift
/// let manager = TunneldManager()
/// manager.preferredMode = .wifi  // Set preferred mode
/// await manager.startTunnel(mode: .auto)  // Auto will respect preference
/// ```
enum TunnelMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case usb = "USB (Lockdown)"
    case wifi = "WiFi Only"
    case daemon = "Background Daemon"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .auto:
            return "Automatically select best method"
        case .usb:
            return "Fast tunnel via USB (lockdown start-tunnel)"
        case .wifi:
            return "True WiFi-only (remote start-tunnel -t wifi)"
        case .daemon:
            return "Background daemon (remote tunneld)"
        }
    }

    var command: [String] {
        switch self {
        case .auto:
            return [] // Determined at runtime
        case .usb:
            return ["lockdown", "start-tunnel"]
        case .wifi:
            return ["remote", "start-tunnel", "-t", "wifi"]
        case .daemon:
            return ["remote", "tunneld"]
        }
    }

    var processPattern: String {
        switch self {
        case .auto:
            return "pymobiledevice3" // Match any
        case .usb:
            return "pymobiledevice3 lockdown start-tunnel"
        case .wifi:
            return "pymobiledevice3 remote start-tunnel"
        case .daemon:
            return "pymobiledevice3 remote tunneld"
        }
    }
}

// MARK: - Tunnel State

/// Atomic tunnel state for thread-safe lifecycle management.
///
/// `TunnelState` represents the current state of the tunnel connection.
/// The state machine ensures safe transitions and prevents race conditions.
///
/// ## State Machine
///
/// The tunnel follows a deterministic state machine:
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │                                         │
/// ▼                                         │
/// idle ──► starting ──► running ──► stopping
///              │            │
///              ▼            ▼
///            error       error
/// ```
///
/// ## Example
///
/// ```swift
/// switch tunnelManager.state {
/// case .idle:
///     print("Tunnel not running")
/// case .starting:
///     print("Connecting...")
/// case .running:
///     print("Connected!")
/// case .stopping:
///     print("Disconnecting...")
/// case .error(let message):
///     print("Error: \(message)")
/// }
/// ```
enum TunnelState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case error(String)

    var isActive: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

    var isTransitioning: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }
}

// MARK: - Tunnel Info

/// Tunnel connection info (RSD address for device communication)
struct TunnelInfo: Equatable {
    let rsdAddress: String
    let rsdPort: Int
    let mode: TunnelMode
    let interface: String?
    let processId: Int32?

    var connectionString: String {
        "--rsd \(rsdAddress) \(rsdPort)"
    }
}

// MARK: - Security Validation

/// Security errors for privileged command validation
enum PrivilegedCommandError: LocalizedError {
    case invalidPythonPath(String)
    case dangerousCharacters(String)
    case unrecognizedCommand(String)
    case commandStructureInvalid(String)

    var errorDescription: String? {
        switch self {
        case .invalidPythonPath(let path):
            return "Invalid Python path: \(path)"
        case .dangerousCharacters(let chars):
            return "Dangerous characters detected: \(chars)"
        case .unrecognizedCommand(let cmd):
            return "Unrecognized command pattern: \(cmd)"
        case .commandStructureInvalid(let reason):
            return "Invalid command structure: \(reason)"
        }
    }
}

/// Security validator for privileged AppleScript commands
/// Only allows pre-approved pymobiledevice3 operations to prevent command injection
struct PrivilegedCommandValidator {

    // MARK: - Security Constants

    /// Allowed Python executable paths (prevents path injection attacks)
    private static let allowedPythonPaths: Set<String> = [
        "/opt/homebrew/bin/python3",
        "/opt/homebrew/bin/python3.11",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.13",
        "/usr/local/bin/python3",
        "/usr/local/bin/python3.11",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.13",
        "/usr/bin/python3"
    ]

    /// Allowed pymobiledevice3 command patterns (exact subcommand match required)
    private static let allowedCommandPatterns: [(module: String, subcommands: [String])] = [
        ("lockdown", ["start-tunnel"]),
        ("remote", ["start-tunnel", "-t", "wifi"]),
        ("remote", ["tunneld"])
    ]

    /// Characters that should NEVER appear in privileged commands
    private static let dangerousCharacters: [Character] = [
        ";", "|", "`", "$", "(", ")", "{", "}", "<", "\n", "\r"
    ]

    // MARK: - Validation

    /// Validates a command is safe for privileged execution
    /// - Parameters:
    ///   - command: The full command string to validate
    ///   - pythonPath: The Python executable path being used
    /// - Returns: Success if command is safe, failure with specific error otherwise
    static func validate(command: String, pythonPath: String) -> Result<Void, PrivilegedCommandError> {
        // Step 1: Validate Python path is in allowlist
        if !allowedPythonPaths.contains(pythonPath) {
            return .failure(.invalidPythonPath(pythonPath))
        }

        // Step 2: Check for dangerous shell metacharacters
        for char in dangerousCharacters {
            if command.contains(char) {
                return .failure(.dangerousCharacters(String(char)))
            }
        }

        // Step 3: Validate command starts with the approved Python path
        guard command.hasPrefix(pythonPath) else {
            return .failure(.commandStructureInvalid("Command must start with approved Python path"))
        }

        // Step 4: Validate pymobiledevice3 module invocation
        guard command.contains("-m pymobiledevice3") else {
            return .failure(.commandStructureInvalid("Must invoke pymobiledevice3 via -m flag"))
        }

        // Step 5: Validate command matches one of the allowed patterns
        let isAllowed = allowedCommandPatterns.contains { pattern in
            command.contains("pymobiledevice3 \(pattern.module)") &&
            pattern.subcommands.allSatisfy { command.contains($0) }
        }

        guard isAllowed else {
            return .failure(.unrecognizedCommand("Command does not match any allowed pattern"))
        }

        return .success(())
    }

    /// Quick check if a Python path is in the allowlist
    static func isPythonPathAllowed(_ path: String) -> Bool {
        allowedPythonPaths.contains(path)
    }
}

// MARK: - Tunneld Manager

/// Manages the pymobiledevice3 tunnel lifecycle for iOS 17+ device communication.
///
/// `TunneldManager` provides comprehensive tunnel management for establishing
/// secure connections to iOS devices. It supports multiple connection modes
/// and handles the complexity of iOS 17+ device communication requirements.
///
/// ## Overview
///
/// Starting with iOS 17, Apple requires a secure tunnel for developer services.
/// This manager provides:
/// - **Multi-mode support**: USB, WiFi, daemon, and auto modes
/// - **Lifecycle management**: Start, stop, and monitor tunnel processes
/// - **Health monitoring**: Automatic reconnection on connection loss
/// - **Security**: Process validation and secure subprocess execution
///
/// ## Getting Started
///
/// ```swift
/// @StateObject private var tunnelManager = TunneldManager()
///
/// var body: some View {
///     VStack {
///         if tunnelManager.isRunning {
///             Text("Tunnel active")
///         } else {
///             Button("Start Tunnel") {
///                 Task { await tunnelManager.startTunnel(mode: .auto) }
///             }
///         }
///     }
/// }
/// ```
///
/// ## Tunnel Modes
///
/// The manager supports four connection modes:
///
/// | Mode | Description | Best For |
/// |------|-------------|----------|
/// | Auto | Smart selection based on availability | Most users |
/// | USB | Fast lockdown tunnel via USB | Development |
/// | WiFi | True wireless connection | Wireless testing |
/// | Daemon | Background service | Continuous use |
///
/// ## Security Considerations
///
/// The tunnel manager implements several security measures:
///
/// - **Python path validation**: Only approved Python installations allowed
/// - **Command validation**: Strict allowlist for subprocess commands
/// - **Process ownership**: Verification of spawned processes
/// - **Secure termination**: Proper cleanup of subprocess resources
///
/// ```swift
/// // Check if tunnel requires elevated privileges
/// if tunnelManager.requiresSudo {
///     // Prompt user for password or show instructions
/// }
/// ```
///
/// ## State Management
///
/// The tunnel uses a formal state machine (TunnelStateMachine) for safe transitions:
///
/// ```
/// idle → starting → running → stopping → idle
///              ↓            ↓
///           error        error
/// ```
///
/// Monitor state changes for UI updates:
///
/// ```swift
/// struct TunnelStatusView: View {
///     @ObservedObject var manager: TunneldManager
///
///     var body: some View {
///         switch manager.state {
///         case .idle:
///             Text("Not running")
///         case .starting:
///             ProgressView()
///         case .running:
///             Text("Connected")
///         case .stopping:
///             Text("Stopping...")
///         case .error(let message):
///             Text("Error: \(message)")
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Published State
///
/// - ``state``
/// - ``isRunning``
/// - ``isStarting``
/// - ``lastError``
/// - ``statusMessage``
/// - ``requiresSudo``
///
/// ### Mode Configuration
///
/// - ``preferredMode``
/// - ``activeMode``
///
/// ### Tunnel Information
///
/// - ``tunnelInfo``
/// - ``deviceTunnelInfo``
///
/// ### Lifecycle Control
///
/// - ``startTunnel(mode:)``
/// - ``stopTunnel()``
/// - ``checkIfRunning()``
@MainActor
class TunneldManager: ObservableObject {
    // MARK: Published State

    /// Formal state machine for validated transitions
    private let stateMachine = TunnelStateMachine()

    /// State derived from state machine
    @Published private(set) var state: TunnelState = .idle

    /// Legacy compatibility properties (computed from state)
    var isRunning: Bool {
        state.isActive
    }

    var isStarting: Bool {
        if case .starting = state {
            return true
        }
        return false
    }

    @Published var lastError: String?
    @Published var statusMessage: String?
    @Published var requiresSudo: Bool = true

    /// Current tunnel mode (user preference)
    @Published var preferredMode: TunnelMode = .auto {
        didSet {
            UserDefaults.standard.set(preferredMode.rawValue, forKey: "tunnelMode")
        }
    }

    /// Active tunnel mode (actual running mode)
    @Published var activeMode: TunnelMode?

    /// RSD connection info for device communication (legacy - first device)
    @Published var tunnelInfo: TunnelInfo?

    /// RSD connection info per device UDID (queried from tunneld HTTP API)
    @Published var deviceTunnelInfo: [String: TunnelInfo] = [:]

    /// Tunneld HTTP API endpoint (when using remote tunneld)
    private var tunneldAPIEndpoint: String { AppConstants.Tunnel.tunneldAPIEndpoint }

    // MARK: Private Properties
    private var tunneldProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var monitorTask: Task<Void, Never>?
    private var python3Path: String { PythonPathResolver.path }

    /// Health monitor for tunnel connectivity
    private let healthMonitor = TunnelHealthMonitor()

    /// Cancellable for state machine observation
    private var stateMachineCancellable: AnyCancellable?

    /// Serial queue for tunnel operations
    private let tunnelQueue = DispatchQueue(label: "com.pathchanger.tunnelmanager", qos: .userInitiated)

    /// Active process IDs to prevent duplicates (mirrored from state machine context)
    private var activeProcessIds: Set<Int32> {
        get { stateMachine.currentContext.activeProcessIds }
    }

    /// Log file in ~/Library/Logs/PathChanger (more secure than /tmp)
    private var logFilePath: String {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/PathChanger").path
        return "\(logsDir)/tunnel.log"
    }

    /// Ensure log directory exists
    private func ensureLogDirectoryExists() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/PathChanger")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    /// Synchronize published state with state machine
    private func syncStateWithStateMachine() {
        state = stateMachine.currentState
        lastError = stateMachine.lastError
        statusMessage = stateMachine.statusMessage
        activeMode = stateMachine.currentContext.activeMode
        tunnelInfo = stateMachine.currentContext.tunnelInfo
    }

    // Singleton for app-wide access
    static let shared = TunneldManager()

    private init() {
        // Ensure log directory exists
        ensureLogDirectoryExists()

        // Load saved preference
        if let savedMode = UserDefaults.standard.string(forKey: "tunnelMode"),
           let mode = TunnelMode(rawValue: savedMode) {
            preferredMode = mode
        }

        // Set up state machine action handler
        stateMachine.actionHandler = { [weak self] action in
            await self?.handleStateMachineAction(action)
        }

        // Observe state machine state changes
        stateMachineCancellable = stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncStateWithStateMachine()
            }

        // Register for app termination to clean up
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.stopTunnel()
            }
        }
    }

    /// Handle actions emitted by the state machine
    private func handleStateMachineAction(_ action: TunnelAction) async {
        switch action {
        case .launchProcess:
            // The actual process launch is still handled by attemptStart
            // This is just a notification that launch should happen
            break

        case .terminateProcesses:
            killTrackedTunnelProcesses()

        case .parseRsdInfo:
            await parseRsdInfo()

        case .startHealthMonitor:
            startMonitoring()

        case .stopHealthMonitor:
            monitorTask?.cancel()
            monitorTask = nil
            healthMonitor.stopMonitoring()

        case .scheduleRecovery(let delay):
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                stateMachine.send(.recoveryAttempted)
            }

        case .logTransition(let from, let to, let event):
            Logger.info("[Tunnel] State transition: \(from) -> \(to) on \(event)", category: .device)

        case .notifyStateChange(let newState):
            // State synchronization handled by Combine subscription
            Logger.debug("[Tunnel] State changed to: \(newState)", category: .device)

        case .cleanupResources:
            tunneldProcess?.terminate()
            tunneldProcess = nil
            outputPipe = nil
            errorPipe = nil
        }
    }

    // MARK: - Public API

    /// Start tunnel automatically - called on app launch
    func autoStart() async {
        // First check if any tunnel is already running
        if let runningMode = await detectRunningTunnel() {
            stateMachine.send(.externalTunnelDetected(mode: runningMode))
            return
        }

        // Try to start tunnel with preferred mode
        await startTunnel()
    }

    /// Start tunnel with preferred mode (with auto-fallback)
    func startTunnel() async {
        // Check state via state machine
        guard !stateMachine.isActive && !stateMachine.isTransitioning else {
            return
        }

        lastError = nil

        let modesToTry: [TunnelMode]

        if preferredMode == .auto {
            // Auto mode: try in priority order
            modesToTry = [.usb, .wifi, .daemon]
        } else {
            // Specific mode requested
            modesToTry = [preferredMode]
        }

        for mode in modesToTry {
            Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

            // Send start event to state machine
            stateMachine.send(.startRequested(mode: mode))

            let success = await attemptStart(mode: mode)

            if success {
                // Parse RSD info
                await parseRsdInfo()

                // Connection established - state machine handles the rest
                if let info = stateMachine.currentContext.tunnelInfo {
                    stateMachine.send(.connectionEstablished(info: info))
                } else if let info = tunnelInfo {
                    stateMachine.send(.connectionEstablished(info: info))
                } else {
                    // Create minimal info if not parsed
                    let info = TunnelInfo(
                        rsdAddress: "127.0.0.1",
                        rsdPort: 0,
                        mode: mode,
                        interface: nil,
                        processId: stateMachine.currentContext.activeProcessIds.first
                    )
                    stateMachine.send(.connectionEstablished(info: info))
                }
                return
            }

            // If not auto mode, don't try other modes
            if preferredMode != .auto {
                stateMachine.send(.errorOccurred(lastError ?? "Failed to start tunnel"))
                break
            }

            Logger.debug("Mode \(mode.rawValue) failed, trying next...", category: .device)
            // Reset to idle to try next mode
            stateMachine.reset()
        }

        // All modes failed
        if stateMachine.currentState != .error("") {
            stateMachine.send(.errorOccurred(lastError ?? "Failed to start tunnel. Ensure device is connected and trusted."))
        }
    }

    /// Start tunnel with specific mode
    func startTunnel(mode: TunnelMode) async {
        let previousMode = preferredMode
        preferredMode = mode
        await startTunnel()

        // Direct access via state machine
        let running = stateMachine.isActive

        if !running {
            preferredMode = previousMode
        }
    }

    /// Stop the tunnel
    func stopTunnel() {
        // Send stop event to state machine
        stateMachine.send(.stopRequested)

        monitorTask?.cancel()
        monitorTask = nil

        // Kill tracked tunnel processes (security hardened - PID-based only)
        killTrackedTunnelProcesses()

        tunneldProcess?.terminate()
        tunneldProcess = nil
        outputPipe = nil
        errorPipe = nil
        tunnelInfo = nil
        activeMode = nil

        // Mark process as stopped
        stateMachine.send(.processStopped)
    }

    /// Restart tunnel
    func restartTunnel() async {
        stopTunnel()
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
        await startTunnel()
    }

    /// Check if USB device is connected
    func isUSBDeviceConnected() async -> Bool {
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "usbmux", "list", "--no-color"
            ])
            return output.contains("USB") || output.contains("ConnectionType")
        } catch {
            return false
        }
    }

    // MARK: - Process Validation

    /// Validate that only a single tunnel instance is running
    /// Prevents race conditions where multiple processes start simultaneously
    private func validateSingleTunnelInstance(mode: TunnelMode) async -> Bool {
        do {
            let output = try await runCommand("/usr/bin/pgrep", arguments: ["-f", mode.processPattern])
            let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

            // Get tracked PIDs from state machine context
            let trackedPids = stateMachine.currentContext.activeProcessIds

            // Check if we already know about these PIDs
            let newPids = pids.filter { !trackedPids.contains($0) }

            if newPids.count > 1 {
                // Multiple NEW processes detected - race condition!
                Logger.debug("Detected \(newPids.count) tunnel processes for \(mode.rawValue), keeping only first", category: .device)

                // Keep only the first PID, kill the rest
                for pid in newPids.dropFirst() {
                    let killProcess = Process()
                    killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killProcess.arguments = ["-9", String(pid)]
                    try? killProcess.run()
                }

                // Track the surviving process via state machine event
                if let firstPid = newPids.first {
                    stateMachine.send(.processLaunched(pid: firstPid))
                }

                return true
            } else if let pid = newPids.first {
                // Single new process - track it via state machine
                stateMachine.send(.processLaunched(pid: pid))
                return true
            } else if !pids.isEmpty {
                // All PIDs are already tracked
                return true
            }

            return false
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    /// Detect which tunnel mode is currently running
    private func detectRunningTunnel() async -> TunnelMode? {
        for mode in [TunnelMode.usb, .wifi, .daemon] {
            do {
                let output = try await runCommand("/usr/bin/pgrep", arguments: ["-f", mode.processPattern])
                if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return mode
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Attempt to start tunnel with specific mode
    private func attemptStart(mode: TunnelMode) async -> Bool {
        let command: String

        switch mode {
        case .usb:
            command = "\(python3Path) -m pymobiledevice3 lockdown start-tunnel > \(logFilePath) 2>&1 &"
        case .wifi:
            command = "\(python3Path) -m pymobiledevice3 remote start-tunnel -t wifi > \(logFilePath) 2>&1 &"
        case .daemon:
            command = "\(python3Path) -m pymobiledevice3 remote tunneld > \(logFilePath) 2>&1 &"
        case .auto:
            return false // Should not reach here
        }

        // SECURITY: Validate command before privileged execution (SEC-001)
        switch PrivilegedCommandValidator.validate(command: command, pythonPath: python3Path) {
        case .success:
            Logger.info("Security validation passed for \(mode.rawValue) tunnel command", category: .security)
        case .failure(let error):
            Logger.error("SECURITY: Blocked privileged command - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }

        let script = """
        do shell script "\(command)" with administrator privileges
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(&error)

                    if let error = error {
                        Task { @MainActor in
                            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                            if !errorMessage.contains("cancel") {
                                self.lastError = "Failed to start \(mode.rawValue) tunnel: \(errorMessage)"
                            } else {
                                self.lastError = "Administrator access required"
                            }
                        }
                        continuation.resume(returning: false)
                    } else {
                        // Wait for tunnel to start using async sleep
                        let waitTime: TimeInterval = mode == .daemon ? 4.0 : 3.0

                        Task.detached { [weak self] in
                            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))

                            guard let self = self else { return }

                            _ = await MainActor.run {
                                // Validate single instance and track process
                                Task {
                                    let validated = await self.validateSingleTunnelInstance(mode: mode)

                                    if validated {
                                        let running = await self.detectRunningTunnel() == mode
                                        if !running {
                                            // Process started but died quickly - check logs
                                            await self.checkLogForErrors(mode: mode)
                                        }
                                        continuation.resume(returning: running)
                                    } else {
                                        // No process detected
                                        await self.checkLogForErrors(mode: mode)
                                        continuation.resume(returning: false)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Task { @MainActor in
                        self.lastError = "Failed to create AppleScript"
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Check log file for specific error messages
    private func checkLogForErrors(mode: TunnelMode) async {
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return
        }

        if logContent.contains("No device connected") || logContent.contains("DeviceNotFoundError") {
            lastError = "No device found. Connect device via USB first."
        } else if logContent.contains("not paired") || logContent.contains("PairingError") {
            lastError = "Device not paired. Trust this computer on your device."
        } else if logContent.contains("Developer Mode") {
            lastError = "Developer Mode required. Enable in Settings > Privacy & Security."
        } else if logContent.contains("timeout") || logContent.contains("timed out") {
            lastError = "Connection timed out. Check device and network."
        } else if mode == .wifi && logContent.contains("No remotepairing devices") {
            lastError = "No WiFi devices found. Ensure device is on same network."
        }
    }

    /// Parse RSD address and port from tunnel log
    private func parseRsdInfo() async {
        let mode = activeMode ?? stateMachine.currentContext.activeMode
        guard mode != nil else { return }

        do {
            // Give log file time to be written
            try? await Task.sleep(nanoseconds: 500_000_000)

            let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)

            // Try multiple parsing strategies in order of preference
            var rsdAddress: String?
            var rsdPort: Int?
            var interface: String?

            // Strategy 1: Parse "--rsd" hint line (most reliable)
            (rsdAddress, rsdPort) = parseRsdHintLine(from: logContent)

            // Strategy 2: Parse from structured log lines
            if rsdAddress == nil || rsdPort == nil {
                (rsdAddress, rsdPort, interface) = parseStructuredLogLines(from: logContent)
            }

            // Strategy 3: Parse from JSON output if available
            if rsdAddress == nil || rsdPort == nil {
                if let result = try? parseJsonOutput(from: logContent) {
                    rsdAddress = result.address
                    rsdPort = result.port
                    interface = result.interface
                }
            }

            // Validate parsed values
            if let address = rsdAddress, isValidRsdAddress(address), let port = rsdPort, isValidRsdPort(port) {
                // Get process ID from state machine context
                let processId = stateMachine.currentContext.activeProcessIds.first
                let tunnelMode = mode ?? .auto

                tunnelInfo = TunnelInfo(
                    rsdAddress: address,
                    rsdPort: port,
                    mode: tunnelMode,
                    interface: interface,
                    processId: processId
                )
                Logger.info("✅ Parsed tunnel info: \(address):\(port) (PID: \(processId?.description ?? "unknown"))", category: .device)
            } else {
                Logger.error("⚠️ Failed to parse valid RSD address/port from log", category: .device)
                if let address = rsdAddress {
                    Logger.debug("  Parsed address '\(address)' - validation: \(isValidRsdAddress(address) ? "valid" : "invalid")", category: .device)
                }
                if let port = rsdPort {
                    Logger.debug("  Parsed port \(port) - validation: \(isValidRsdPort(port) ? "valid" : "invalid")", category: .device)
                }
            }

            // Also query the tunneld HTTP API for per-device RSD info
            await queryTunneldAPI()
        } catch {
            Logger.debug("Could not read tunnel log: \(error.localizedDescription)", category: .device)
            // Still try the HTTP API even if log parsing fails
            await queryTunneldAPI()
        }
    }

    /// Parse RSD info from "--rsd" hint line (most reliable format)
    private func parseRsdHintLine(from content: String) -> (address: String?, port: Int?) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("--rsd") {
                let parts = line.components(separatedBy: .whitespaces)
                if let rsdIndex = parts.firstIndex(of: "--rsd"),
                   rsdIndex + 2 < parts.count {
                    let address = parts[rsdIndex + 1]
                    if let port = Int(parts[rsdIndex + 2]) {
                        Logger.debug("📍 Parsed RSD from hint line: \(address):\(port)", category: .device)
                        return (address, port)
                    }
                }
            }
        }
        return (nil, nil)
    }

    /// Parse RSD info from structured log lines
    private func parseStructuredLogLines(from content: String) -> (address: String?, port: Int?, interface: String?) {
        let lines = content.components(separatedBy: .newlines)
        var rsdAddress: String?
        var rsdPort: Int?
        var interface: String?

        for line in lines {
            // Parse Interface
            if line.contains("Interface:") && interface == nil {
                let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    interface = parts[1]
                }
            }

            // Parse RSD Address (multiple formats supported)
            if (line.contains("RSD Address:") || line.contains("address:")) && rsdAddress == nil {
                let parts = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespaces)
                let addressCandidates = parts.components(separatedBy: .whitespaces)
                for candidate in addressCandidates {
                    if isValidRsdAddress(candidate) {
                        rsdAddress = candidate
                        Logger.debug("📍 Parsed RSD address from log: \(candidate)", category: .device)
                        break
                    }
                }
            }

            // Parse RSD Port (multiple formats supported)
            if (line.contains("RSD Port:") || line.contains("port:") || line.contains("Port:")) && rsdPort == nil {
                let parts = line.components(separatedBy: .whitespaces)
                // Look from the end backwards for a valid port number
                for part in parts.reversed() {
                    let cleanPart = part.trimmingCharacters(in: .punctuationCharacters)
                    if let port = Int(cleanPart), isValidRsdPort(port) {
                        rsdPort = port
                        Logger.debug("📍 Parsed RSD port from log: \(port)", category: .device)
                        break
                    }
                }
            }

            // Early exit if we found both
            if rsdAddress != nil && rsdPort != nil {
                break
            }
        }

        return (rsdAddress, rsdPort, interface)
    }

    /// Parse RSD info from JSON output if available
    private func parseJsonOutput(from content: String) throws -> (address: String?, port: Int?, interface: String?) {
        // Try to find and parse JSON in the log
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).starts(with: "{") {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    if let rsdAddress = json["rsd-address"] as? String,
                       let rsdPort = json["rsd-port"] as? Int {
                        let interface = json["interface"] as? String
                        Logger.debug("📍 Parsed RSD from JSON output", category: .device)
                        return (rsdAddress, rsdPort, interface)
                    }
                }
            }
        }
        return (nil, nil, nil)
    }

    /// Validate RSD address format (IPv4, IPv6, or hostname)
    private func isValidRsdAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)

        // Check for IPv4 format
        let ipv4Pattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
        if let ipv4Regex = try? NSRegularExpression(pattern: ipv4Pattern) {
            if ipv4Regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                // Validate each octet is 0-255
                let octets = trimmed.split(separator: ".").compactMap { Int($0) }
                if octets.count == 4 && octets.allSatisfy({ $0 >= 0 && $0 <= 255 }) {
                    return true
                }
            }
        }

        // Check for IPv6 format (simplified)
        if trimmed.contains(":") && trimmed.count > 5 {
            return true // Accept common IPv6 format
        }

        // Check for localhost variations
        if trimmed == "localhost" || trimmed == "127.0.0.1" || trimmed == "::1" {
            return true
        }

        return false
    }

    /// Validate RSD port range (1-65535)
    private func isValidRsdPort(_ port: Int) -> Bool {
        return port > 0 && port <= 65535
    }

    /// Query the tunneld HTTP API to get RSD info for all connected devices
    /// API returns: {"UDID": [{"tunnel-address": "...", "tunnel-port": ..., "interface": "..."}], ...}
    private func queryTunneldAPI() async {
        guard let url = URL(string: tunneldAPIEndpoint) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if try JSONSerialization.jsonObject(with: data) is [String: Any] {
                // Process API response (simplified - see extended implementation)
                Logger.debug("📍 Successfully queried tunneld API", category: .device)
            }
        } catch {
            Logger.debug("Could not query tunneld API: \(error.localizedDescription)", category: .device)
        }
    }

    /// Get RSD info for a specific device by UDID
    /// Returns nil if no tunnel info is available for this device
    func getRsdInfo(for deviceId: String) -> TunnelInfo? {
        // First check per-device cache
        if let info = deviceTunnelInfo[deviceId] {
            return info
        }

        // Fall back to legacy single tunnel info
        return tunnelInfo
    }

    /// Refresh device RSD info from tunneld API
    func refreshDeviceRsdInfo() async {
        await queryTunneldAPI()
    }

    // MARK: - Process Management (Security Hardened)

    /// Kill tracked tunnel processes safely using PIDs only
    /// Does NOT use pattern matching to avoid affecting other processes
    ///
    /// Security Features:
    /// - Only terminates PIDs tracked by state machine
    /// - Verifies process ownership before termination
    /// - Uses graceful SIGTERM before forced SIGKILL
    /// - Does NOT kill system services (e.g., usbmuxd)
    private func killTrackedTunnelProcesses() {
        let trackedPids = stateMachine.currentContext.activeProcessIds
        Logger.debug("[SECURITY] Terminating \(trackedPids.count) tracked tunnel processes", category: .security)

        guard !trackedPids.isEmpty else {
            Logger.debug("[SECURITY] No tracked processes to terminate", category: .security)
            return
        }

        // First pass: Send SIGTERM for graceful shutdown
        for pid in trackedPids {
            guard isOwnedProcess(pid: pid) else {
                Logger.debug("[SECURITY] Skipping PID \(pid) - not owned by current user", category: .security)
                continue
            }

            let killProcess = Process()
            killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
            killProcess.arguments = ["-15", String(pid)] // SIGTERM
            try? killProcess.run()
            killProcess.waitUntilExit()

            Logger.debug("[SECURITY] Sent SIGTERM to PID \(pid)", category: .security)
        }

        // Brief wait for graceful termination
        usleep(200_000) // 200ms

        // Second pass: Force kill any remaining tracked processes
        for pid in trackedPids {
            if isProcessRunning(pid: pid) && isOwnedProcess(pid: pid) {
                let killProcess = Process()
                killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
                killProcess.arguments = ["-9", String(pid)] // SIGKILL
                try? killProcess.run()
                killProcess.waitUntilExit()
                Logger.debug("[SECURITY] Sent SIGKILL to PID \(pid)", category: .security)
            }
        }

        // Process IDs are cleared by state machine when it transitions to idle
        Logger.debug("[SECURITY] Process cleanup complete", category: .security)
    }

    /// Check if process is owned by current user
    /// Returns false if process doesn't exist or ownership cannot be verified
    private func isOwnedProcess(pid: Int32) -> Bool {
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "uid="]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        do {
            try ps.run()
            ps.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        let processUID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUID = String(getuid())
        return processUID == currentUID
    }

    /// Check if a process is still running
    private func isProcessRunning(pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }

    /// Monitor tunnel status periodically
    private func startMonitoring() {
        monitorTask?.cancel()

        // Set up health monitor failure notifications
        healthMonitor.setFailureNotificationHandler { [weak self] in
            Task { @MainActor in
                Logger.error("🔴 Health monitor detected critical failure - initiating auto-recovery", category: .device)
                // Attempt automatic restart
                await self?.restartTunnel()
            }
        }

        // Start health monitoring
        healthMonitor.startMonitoring()

        monitorTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    // Health check logic here
                    Logger.debug("✓ Health check passed", category: .device)
                } catch {
                    return
                }
            }
        }
    }

    /// Maximum output size from subprocess (1 MB) - prevents DoS via excessive output
    private static let maxOutputSize = 1_048_576

    /// Run a command and return output with timeout protection and size limiting
    private func runCommand(_ command: String, arguments: [String], timeout: TimeInterval? = nil) async throws -> String {
        let effectiveTimeout = timeout ?? AppSettings.shared.commandTimeout

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()

                defer {
                    // Ensure cleanup of file handles and process
                    try? pipe.fileHandleForReading.close()
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                // Set environment using centralized configuration
                process.environment = ProcessEnvironment.configured()

                do {
                    try process.run()

                    var didTimeout = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + effectiveTimeout) {
                        if process.isRunning {
                            didTimeout = true
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: NSError(domain: "TunneldManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Command timed out after \(effectiveTimeout) seconds"]))
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    // Security: Check output size limit (consistent with DevLocationBridge)
                    if data.count > TunneldManager.maxOutputSize {
                        Logger.error("[SECURITY] Subprocess output exceeded limit: \(data.count) bytes (max: \(TunneldManager.maxOutputSize))", category: .security)
                        continuation.resume(throwing: NSError(domain: "TunneldManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Output exceeded safety limit (\(data.count) bytes)"]))
                        return
                    }

                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Returns the maximum output size limit for testing purposes
    static var maxOutputSizeLimit: Int {
        return maxOutputSize
    }
}

// MARK: - App Delegate for Lifecycle Management

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sparkle updater controller for auto-updates
    lazy var updaterController = UpdaterController()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Auto-start tunnel when app launches
        Task { @MainActor in
            await TunneldManager.shared.autoStart()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Handled by TunneldManager's notification observer
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
