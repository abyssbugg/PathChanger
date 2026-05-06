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

    /// Allowed system Python executable paths (prevents path injection attacks)
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
        if !isPythonPathAllowed(pythonPath) {
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
        if allowedPythonPaths.contains(path) {
            return true
        }
        let pyenvShimsPath = "\(NSHomeDirectory())/.pyenv/shims/python3"
        if path == pyenvShimsPath && FileManager.default.isExecutableFile(atPath: path) {
            return true
        }

        let pyenvVersionsPrefix = "\(NSHomeDirectory())/.pyenv/versions/"
        return path.hasPrefix(pyenvVersionsPrefix) &&
               path.hasSuffix("/bin/python3") &&
               FileManager.default.isExecutableFile(atPath: path)
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

    // MARK: WiFi Pairing State (drives the new WiFi Pairing card in SettingsView)

    /// True while `scripts/pair_wifi.py` is being executed via AppleScript.
    @Published var wifiPairingInProgress: Bool = false

    /// Most recent stdout/stderr captured from `pair_wifi.py`. Truncated to a
    /// reasonable size for UI display.
    @Published var wifiPairingLog: String = ""

    /// Result of the last in-app pair attempt, if any.
    @Published var lastWiFiPairingResult: WiFiPairingResult?

    /// UDIDs that are currently visible over Bonjour (`pmd3 remote browse`).
    /// Empty until `probeBonjourWiFiDevices()` is called.
    @Published var bonjourVisibleUDIDs: [String] = []

    /// True while a Bonjour probe is in flight.
    @Published var bonjourProbeInProgress: Bool = false

    /// Outcome of an in-app `pair_wifi.py` run.
    enum WiFiPairingResult: Equatable {
        case success(deviceCount: Int)
        case noDevicesFound
        case scriptError(String)
        case userCancelled
        case scriptMissing
    }

    /// Current tunnel mode (user preference)
    @Published var preferredMode: TunnelMode = .auto {
        didSet {
            UserDefaults.standard.set(preferredMode.rawValue, forKey: "tunnelMode")
            // If the user changed modes while a tunnel is active, restart it so the
            // new mode takes effect. Without this, switching the picker silently
            // keeps the old transport (e.g. picking WiFi but staying on USB).
            guard !isLoadingPreferredModeFromDefaults,
                  oldValue != preferredMode else { return }
            scheduleTunnelRestartIfRunning(previousMode: oldValue)
        }
    }

    /// Suppresses the didSet auto-restart when seeding `preferredMode` from UserDefaults during init.
    private var isLoadingPreferredModeFromDefaults: Bool = false

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
    /// UDID selected for the next tunnel start, populated from usbmux discovery.
    private var targetTunnelUDID: String?
    private var targetTunnelConnectionType: ConnectionType?
    private var tunnelStartInFlight = false

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

        // Load saved preference (suppress auto-restart side effect during init)
        isLoadingPreferredModeFromDefaults = true
        if let savedMode = UserDefaults.standard.string(forKey: "tunnelMode"),
           let mode = TunnelMode(rawValue: savedMode) {
            preferredMode = mode
        }
        isLoadingPreferredModeFromDefaults = false

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
            stateMachine.send(.externalTunnelDetected(mode: runningMode, info: recoverRsdInfoFromLog()))
            return
        }

        // Try to start tunnel with preferred mode
        await startTunnel()
    }

    /// Start tunnel with preferred mode (with auto-fallback)
    func startTunnel() async {
        guard !tunnelStartInFlight else {
            Logger.debug("Ignoring duplicate tunnel start request while another start is in progress", category: .device)
            return
        }
        // Check state via state machine
        guard !stateMachine.isActive && !stateMachine.isTransitioning else {
            return
        }
        tunnelStartInFlight = true
        defer {
            tunnelStartInFlight = false
        }

        lastError = nil

        if await attachToRunningTunnelIfAvailable() {
            return
        }

        let modesToTry: [TunnelMode]

        if preferredMode == .auto {
            let availability = await deviceConnectionAvailability()
            if let targetUDID = targetTunnelUDID, availability.usbUDID == targetUDID {
                modesToTry = [.usb]
            } else if let targetUDID = targetTunnelUDID,
                      availability.networkUDID == targetUDID,
                      targetTunnelConnectionType != .wifi {
                modesToTry = [.usb]
            } else if let targetUDID = targetTunnelUDID,
                      availability.wifiBrowseUDID == targetUDID || targetTunnelConnectionType == .wifi {
                targetTunnelUDID = targetUDID
                modesToTry = [.wifi]
            } else if let usbUDID = availability.usbUDID {
                targetTunnelUDID = usbUDID
                modesToTry = [.usb]
            } else if let networkUDID = availability.networkUDID {
                targetTunnelUDID = networkUDID
                modesToTry = [.usb]
            } else if let wifiBrowseUDID = availability.wifiBrowseUDID {
                targetTunnelUDID = wifiBrowseUDID
                modesToTry = [.wifi]
            } else {
                let message = "No USB or same-Wi-Fi device detected. For Wi-Fi, keep the iPhone awake and unlocked on the same network, and trust/pair it with this Mac before retrying."
                lastError = message
                statusMessage = message
                Logger.error(message, category: .device)
                return
            }
        } else {
            // Specific mode requested
            let availability = await deviceConnectionAvailability()
            switch preferredMode {
            case .wifi:
                // BUG FIX (WiFi-Bug-3): Never fall back to availability.networkUDID for
                // WiFi mode. `pmd3 remote start-tunnel -t wifi --udid <X>` filters
                // across Bonjour-discovered devices; passing a usbmux network UDID will
                // never match and the command fails with "No devices were found during
                // bonjour browse". If wifiBrowseUDID is nil after Bug-2's fix, fail with
                // a clear actionable error instead of silently passing a wrong UDID.
                let resolved = targetTunnelUDID ?? availability.wifiBrowseUDID
                if resolved == nil {
                    let message = "No iPhone discovered over Bonjour. On the iPhone: open Settings → Developer and enable wireless pairing for this Mac, then retry. The Mac and iPhone must be on the same Wi-Fi network and the iPhone must be unlocked."
                    lastError = message
                    statusMessage = message
                    Logger.error("[Tunnel] WiFi mode requested but no Bonjour-discoverable iPhone was found", category: .device)
                    stateMachine.send(.errorOccurred(message))
                    return
                }
                targetTunnelUDID = resolved
            case .usb:
                if let targetUDID = targetTunnelUDID, availability.usbUDID == targetUDID {
                    targetTunnelUDID = targetUDID
                } else if let targetUDID = targetTunnelUDID, availability.networkUDID == targetUDID {
                    targetTunnelUDID = targetUDID
                } else {
                    targetTunnelUDID = availability.usbUDID ?? availability.networkUDID
                }
            case .daemon:
                targetTunnelUDID = nil
            case .auto:
                break
            }
            modesToTry = [preferredMode]
        }

        for mode in modesToTry {
            Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

            // Send start event to state machine
            stateMachine.send(.startRequested(mode: mode))

            let success = await attemptStart(mode: mode)

            if success {
                // BUG FIX (WiFi-Bug-6): Don't fabricate a 127.0.0.1:0 TunnelInfo
                // when parseRsdInfo can't extract a real address. The old fallback
                // was indistinguishable from a real tunnel to downstream callers,
                // so every later device command would silently fail. Instead we
                // retry parseRsdInfo a few times (the log file is sometimes still
                // being written when we first read it) and only treat tunnel
                // setup as successful once we have a non-loopback / non-zero RSD.
                //
                // If after the retry budget we still can't parse a real address,
                // tear the tunnel down and surface a specific error rather than
                // pretending we have a working tunnel.
                if let info = await waitForValidRsdInfo(mode: mode) {
                    stateMachine.send(.connectionEstablished(info: info))
                } else {
                    let message = "Tunnel started but its RSD address could not be parsed from the tunnel log. The pmd3 output format may have changed; check ~/Library/Logs/PathChanger/tunnel.log and retry."
                    Logger.error("[Tunnel] \(message)", category: .device)
                    lastError = message
                    statusMessage = message
                    // Kill the tunnel process we just spawned — it's running but
                    // useless to us, and leaving it would block future starts.
                    killTrackedTunnelProcesses()
                    stateMachine.send(.errorOccurred(message))
                    return
                }
                return
            }

            stateMachine.send(.errorOccurred(lastError ?? "Failed to start \(mode.rawValue) tunnel"))
            return
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

    /// Prefer this device for the next USB or Wi-Fi tunnel start.
    func setTargetDevice(_ device: Device?) {
        guard let device else {
            targetTunnelUDID = nil
            targetTunnelConnectionType = nil
            return
        }

        guard isSafeUDID(device.id) else {
            Logger.debug("Ignoring unsafe tunnel target UDID", category: .security)
            return
        }

        targetTunnelUDID = device.id
        targetTunnelConnectionType = device.connectionType
    }

    /// Schedule a stop+start when the user changes the preferred mode and a
    /// tunnel is currently running or starting. The previous mode is logged
    /// for diagnostics. If no tunnel is active this is a no-op.
    private func scheduleTunnelRestartIfRunning(previousMode: TunnelMode) {
        guard stateMachine.isActive || stateMachine.isTransitioning else {
            Logger.debug("[Tunnel] preferredMode changed (\(previousMode.rawValue) -> \(preferredMode.rawValue)) - no active tunnel, will use new mode on next start", category: .device)
            return
        }

        Logger.info("[Tunnel] preferredMode changed (\(previousMode.rawValue) -> \(preferredMode.rawValue)) while active - restarting with new mode", category: .device)
        statusMessage = "Switching tunnel to \(preferredMode.rawValue)..."

        Task { @MainActor in
            stopTunnel()
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms grace for processes to exit
            await startTunnel()
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
        let availability = await deviceConnectionAvailability()
        return availability.usbUDID != nil || availability.networkUDID != nil
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

    private struct DeviceConnectionAvailability {
        let usbUDID: String?
        let networkUDID: String?
        let wifiBrowseUDID: String?
    }

    private func deviceConnectionAvailability() async -> DeviceConnectionAvailability {
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color", "usbmux", "list"
            ], timeout: 8.0)

            guard let jsonStart = output.firstIndex(of: "["),
                  let jsonEnd = output.lastIndex(of: "]"),
                  let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
                  let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return DeviceConnectionAvailability(usbUDID: nil, networkUDID: nil, wifiBrowseUDID: nil)
            }

            var usbUDID: String?
            var networkUDID: String?

            for item in jsonArray {
                guard let udid = item["UniqueDeviceID"] as? String ?? item["Identifier"] as? String,
                      isSafeUDID(udid),
                      let connectionType = item["ConnectionType"] as? String else {
                    continue
                }

                if connectionType.lowercased().contains("usb"), usbUDID == nil {
                    usbUDID = udid
                } else if connectionType.lowercased().contains("network"), networkUDID == nil {
                    networkUDID = udid
                }
            }

            // BUG FIX (WiFi-Bug-2): Always run Bonjour browse when the user actually
            // wants WiFi (preferredMode == .wifi or .auto). Previously this was gated on
            // BOTH usbUDID AND networkUDID being nil, which meant a single stale
            // ConnectionType: Network entry left in usbmux from any prior USB-with-WiFi-sync
            // pairing would silently skip Bonjour discovery, leaving Bug 3's wrong-UDID
            // fallback as the only path. We still skip the (~3-5s) browse for explicit
            // .usb / .daemon modes since they don't need it.
            let needsWifiBrowse = preferredMode == .wifi || preferredMode == .auto
            let wifiBrowseUDID: String?
            if needsWifiBrowse {
                wifiBrowseUDID = await discoverNetworkUDIDViaRemoteBrowse(preferredUDID: targetTunnelUDID)
            } else {
                wifiBrowseUDID = nil
            }

            return DeviceConnectionAvailability(usbUDID: usbUDID, networkUDID: networkUDID, wifiBrowseUDID: wifiBrowseUDID)
        } catch {
            // usbmux failed entirely — fall through to Bonjour browse only if WiFi/auto.
            let wifiBrowseUDID: String?
            if preferredMode == .wifi || preferredMode == .auto {
                wifiBrowseUDID = await discoverNetworkUDIDViaRemoteBrowse(preferredUDID: targetTunnelUDID)
            } else {
                wifiBrowseUDID = nil
            }
            return DeviceConnectionAvailability(usbUDID: nil, networkUDID: nil, wifiBrowseUDID: wifiBrowseUDID)
        }
    }

    private func isSafeUDID(_ value: String) -> Bool {
        let pattern = #"^[A-Fa-f0-9-]{16,64}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private func discoverNetworkUDIDViaRemoteBrowse(preferredUDID: String?) async -> String? {
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color",
                "remote", "browse",
                "--timeout", "3"
            ], timeout: 5.0)

            let candidates = extractWiFiUDIDsFromRemoteBrowseOutput(output)
            if let preferredUDID, candidates.contains(preferredUDID) {
                return preferredUDID
            }
            return candidates.first
        } catch {
            return nil
        }
    }

    private func extractWiFiUDIDsFromRemoteBrowseOutput(_ output: String) -> [String] {
        guard let jsonStart = output.firstIndex(of: "{"),
              let jsonEnd = output.lastIndex(of: "}"),
              let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json.keys.contains("wifi") || json.keys.contains("usb") else {
            return extractSafeUDIDs(from: output)
        }

        guard let wifiValue = json["wifi"],
              let wifiData = try? JSONSerialization.data(withJSONObject: wifiValue),
              let wifiString = String(data: wifiData, encoding: .utf8) else {
            return []
        }

        return extractSafeUDIDs(from: wifiString)
    }

    private func extractSafeUDIDs(from text: String) -> [String] {
        let pattern = #"[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}|[A-Fa-f0-9]{40}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        var results: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let value = String(text[matchRange])
            if isSafeUDID(value), !results.contains(value) {
                results.append(value)
            }
        }

        return results
    }

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

    /// Public probe that returns the currently-running tunnel mode (USB / WiFi /
    /// Daemon), or nil if no pmd3 tunnel process is alive.
    ///
    /// BUG FIX (WiFi-Bug-2): exposes the same pgrep-based detection that the
    /// internal lifecycle uses, so AppState can stop routing tunnel-running
    /// truth through DeviceManager (which doesn't know about WiFi tunnels) and
    /// instead read directly from this single source.
    func detectRunningTunnelMode() async -> TunnelMode? {
        await detectRunningTunnel()
    }

    /// Repeatedly call `parseRsdInfo` until we have a non-loopback RSD address
    /// and a non-zero port, or the retry budget is exhausted.
    ///
    /// BUG FIX (WiFi-Bug-6): The first read of the tunnel log can race with
    /// pmd3 still flushing its banner output (especially for `remote start-tunnel`
    /// where the bonjour browse and TLS handshake add a couple of seconds before
    /// the `--rsd <addr> <port>` line lands). Retry up to ~5 seconds before
    /// giving up, instead of fabricating a 127.0.0.1:0 placeholder.
    private func waitForValidRsdInfo(mode: TunnelMode) async -> TunnelInfo? {
        let maxAttempts = 4
        for attempt in 0..<maxAttempts {
            await parseRsdInfo()
            if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
                return info
            }
            if let info = tunnelInfo, isUsableTunnelInfo(info) {
                return info
            }
            // Don't sleep after the last attempt.
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
        }

        // Last-ditch: query the tunneld HTTP API once more in case the daemon
        // already has a usable record even when log parsing failed.
        await queryTunneldAPI()
        if let firstDeviceInfo = deviceTunnelInfo.values.first(where: { isUsableTunnelInfo($0) }) {
            tunnelInfo = firstDeviceInfo
            return firstDeviceInfo
        }

        Logger.error("[Tunnel] waitForValidRsdInfo gave up for mode \(mode.rawValue) after \(maxAttempts) attempts", category: .device)
        return nil
    }

    /// True only when a TunnelInfo can actually be used to talk to the device.
    /// Rejects the legacy 127.0.0.1:0 placeholder and any zero-port info.
    private func isUsableTunnelInfo(_ info: TunnelInfo) -> Bool {
        guard info.rsdPort > 0, info.rsdPort <= 65_535 else { return false }
        if info.rsdAddress == "127.0.0.1" { return false }
        if info.rsdAddress.isEmpty { return false }
        return isValidRsdAddress(info.rsdAddress)
    }

    /// Attach to an already-running tunnel instead of launching another privileged process.
    ///
    /// Returns `true` only if a running tunnel exists AND it matches the user's `preferredMode`
    /// (or `preferredMode == .auto`). When the user picks a specific mode different from what's
    /// running (e.g. WiFi while a USB tunnel is up), this returns `false` so the caller will
    /// proceed to stop the mismatching tunnel and start fresh in the requested mode.
    private func attachToRunningTunnelIfAvailable() async -> Bool {
        guard let runningMode = await detectRunningTunnel() else {
            return false
        }

        // Mode-aware reattach gate: refuse to silently bind to a tunnel that doesn't
        // match the user's explicit preference.
        let modeMatches = preferredMode == .auto || preferredMode == runningMode
        if !modeMatches {
            Logger.info(
                "[Tunnel] Existing \(runningMode.rawValue) tunnel detected but preferredMode is \(preferredMode.rawValue) - stopping it to start fresh in requested mode",
                category: .device
            )
            statusMessage = "Stopping \(runningMode.rawValue) tunnel to switch to \(preferredMode.rawValue)..."
            stopTunnel()
            try? await Task.sleep(nanoseconds: 500_000_000) // grace for processes to exit
            return false
        }

        guard let recoveredInfo = recoverRsdInfoFromLog() else {
            let message = "A tunnel process is already running, but PathChanger could not read its RSD address. Stop the existing tunnel and start it again."
            lastError = message
            statusMessage = message
            Logger.error(message, category: .device)
            return true
        }

        tunnelInfo = recoveredInfo
        lastError = nil
        statusMessage = "Tunnel already running (RSD: \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort))"
        Logger.info("Attached to existing \(runningMode.rawValue) tunnel at \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort)", category: .device)
        stateMachine.send(.externalTunnelDetected(mode: runningMode, info: recoveredInfo))
        return true
    }

    /// Attempt to start tunnel with specific mode
    private func attemptStart(mode: TunnelMode) async -> Bool {
        let command: String
        let udidArgument = targetTunnelUDID.map { " --udid \($0)" } ?? ""

        switch mode {
        case .usb:
            command = "\(python3Path) -m pymobiledevice3 lockdown start-tunnel\(udidArgument) > \(logFilePath) 2>&1 &"
        case .wifi:
            command = "\(python3Path) -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp\(udidArgument) > \(logFilePath) 2>&1 &"
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

        // The most common WiFi-mode failure: pmd3 found no _remotepairing-manual-pairing
        // Bonjour service. That means the iPhone hasn't been put into wireless-pairing mode
        // yet. There is no Mac-side workaround; the user must enable it in iOS Settings.
        let wifiPairingGuidance = """
        Wi-Fi pairing not configured. On the iPhone:
          1. Make sure it is UNLOCKED and on the SAME Wi-Fi as this Mac.
          2. Settings → Privacy & Security → Developer Mode must be ON.
          3. Settings → Developer → enable wireless pairing for this Mac
             (the toggle name varies by iOS version: "Pair Wirelessly",
             "Wireless Pairing", or "Allow Mac").
          4. Then run, in Terminal:
               sudo python3 \(scriptsDirectoryPath)/pair_wifi.py --timeout 30
             and confirm the pairing prompt on the iPhone.
          5. Retry Start in Wi-Fi mode.
        """

        if mode == .wifi && (
            logContent.contains("No devices were found during bonjour browse") ||
            logContent.contains("No remotepairing devices")
        ) {
            lastError = wifiPairingGuidance
            return
        }

        if logContent.contains("Device is not connected") {
            if mode == .wifi {
                lastError = wifiPairingGuidance
            } else {
                lastError = "Device is not connected. Connect and trust the iPhone, then retry."
            }
        } else if logContent.contains("No device connected") || logContent.contains("DeviceNotFoundError") {
            lastError = mode == .wifi
                ? wifiPairingGuidance
                : "No device found. Connect the device via USB, unlock it, and tap Trust."
        } else if logContent.contains("not paired") || logContent.contains("PairingError") {
            lastError = mode == .wifi
                ? wifiPairingGuidance
                : "Device not paired. Unlock the device, trust this computer over USB."
        } else if logContent.contains("Developer Mode") {
            lastError = "Developer Mode required. Enable in Settings > Privacy & Security."
        } else if logContent.contains("timeout") || logContent.contains("timed out") {
            lastError = "Connection timed out. Keep the device awake, verify both devices are on the same Wi-Fi, and retry."
        }
    }

    /// Best-effort path to the bundled scripts directory, used in error messages so we can
    /// tell the user where pair_wifi.py lives in their app bundle.
    private var scriptsDirectoryPath: String {
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL.appendingPathComponent("scripts", isDirectory: true).path
        }
        return "<PathChanger.app>/Contents/Resources/scripts"
    }

    /// Allow only paths that are safe to embed inside `do shell script "..." with
    /// administrator privileges` after single-quoting. Disallows apostrophes,
    /// shell metacharacters, AppleScript-quoting characters, and embedded newlines.
    private func isShellSafePath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let bad: Set<Character> = ["'", "\\", "\"", "`", "$", ";", "|", "&", "\n", "\r", "<", ">"]
        return !path.contains(where: { bad.contains($0) })
    }

    /// Resolve the absolute on-disk path of `pair_wifi.py`, walking from the app bundle's
    /// Resources/scripts/ first and then the SwiftPM dev workspace as a fallback for
    /// `swift run` builds. Returns nil if the script can't be found.
    private func resolvePairWiFiScriptPath() -> String? {
        let fileManager = FileManager.default

        // 1. Bundled in PathChanger.app/Contents/Resources/scripts/pair_wifi.py
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("scripts/pair_wifi.py").path
            if fileManager.isReadableFile(atPath: bundled) {
                return bundled
            }
        }

        // 2. Dev / repo layout: <repo>/scripts/pair_wifi.py — useful when running
        //    via `swift run` from a clone.
        let cwdScript = fileManager.currentDirectoryPath + "/scripts/pair_wifi.py"
        if fileManager.isReadableFile(atPath: cwdScript) {
            return cwdScript
        }

        return nil
    }

    // MARK: - Public WiFi Pairing API

    /// Probe the local network for iPhones that are advertising the
    /// `_remotepairing._tcp` Bonjour service via `pmd3 remote browse`. Updates
    /// `bonjourVisibleUDIDs` so the UI can show "iPhone visible over Bonjour: X"
    /// before the user attempts a WiFi tunnel start.
    ///
    /// This is the preflight check that surfaces the silent failure mode users
    /// would otherwise hit: if no iPhone advertises Bonjour, WiFi tunnel start
    /// will fail no matter what (Bug 2/3 fixes don't help if there's nothing
    /// to discover).
    func probeBonjourWiFiDevices() async {
        bonjourProbeInProgress = true
        defer { bonjourProbeInProgress = false }

        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color",
                "remote", "browse",
                "--timeout", "5"
            ], timeout: 8.0)

            let candidates = extractWiFiUDIDsFromRemoteBrowseOutput(output)
            bonjourVisibleUDIDs = candidates
            Logger.info("[Tunnel] Bonjour probe found \(candidates.count) WiFi-discoverable device(s)", category: .device)
        } catch {
            bonjourVisibleUDIDs = []
            Logger.debug("[Tunnel] Bonjour probe failed: \(error.localizedDescription)", category: .device)
        }
    }

    /// Run the bundled `scripts/pair_wifi.py` helper with administrator
    /// privileges. Drives a longer (default 30s) Bonjour browse window than
    /// `pmd3 remote pair` and pairs the first discovered iPhone (or matches
    /// against `nameFilter` if provided).
    ///
    /// This is the iOS-side prerequisite for WiFi mode. After this runs, the
    /// pair record is on disk and `pmd3 remote start-tunnel -t wifi` can
    /// connect without the user touching Terminal.
    ///
    /// - Parameters:
    ///   - timeout: Bonjour browse window in seconds (default 30).
    ///   - nameFilter: Optional substring to match the iPhone's Bonjour name.
    func pairOverWiFi(timeout: TimeInterval = 30.0, nameFilter: String? = nil) async -> WiFiPairingResult {
        guard !wifiPairingInProgress else {
            return .scriptError("WiFi pairing is already in progress.")
        }

        // SECURITY: validate python path against the same allowlist used for tunnel
        // launch commands so we can never call an attacker-controlled binary as root.
        guard PrivilegedCommandValidator.isPythonPathAllowed(python3Path) else {
            let message = "Refusing to run pair_wifi.py: python3 path is not in the security allowlist (\(python3Path))."
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        guard let scriptPath = resolvePairWiFiScriptPath() else {
            let message = "pair_wifi.py was not found in the app bundle (expected at \(scriptsDirectoryPath)/pair_wifi.py)."
            Logger.error(message, category: .device)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptMissing
            return .scriptMissing
        }

        // SECURITY: paths must end in the expected suffix and contain only safe
        // characters before we string-concat them into a shell command. This
        // closes the gap that PrivilegedCommandValidator can't (its allowlist is
        // for tunnel commands only).
        guard scriptPath.hasSuffix("/scripts/pair_wifi.py"),
              isShellSafePath(scriptPath),
              isShellSafePath(python3Path) else {
            let message = "Refusing to run pair_wifi.py: resolved path is unsafe (\(scriptPath))."
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        // Clamp the timeout to a sane window. Anything outside [5, 120] is a UI bug.
        let timeoutSec = max(5, min(120, Int(timeout.rounded())))

        wifiPairingInProgress = true
        wifiPairingLog = ""
        statusMessage = "Pairing over Wi-Fi (browsing Bonjour for up to \(timeoutSec)s)…"
        defer { wifiPairingInProgress = false }

        // Build the inner command that runs as root via osascript. All
        // user-influenced segments are validated above; the only remaining
        // free-form input is `nameFilter` which is restricted to alnum/dash/
        // underscore/space. We single-quote inputs for the shell.
        let logFile = "\(NSTemporaryDirectory())pathchanger-pair-wifi.log"
        guard isShellSafePath(logFile) else {
            let message = "Refusing to run pair_wifi.py: temporary log path is unsafe."
            Logger.error(message, category: .security)
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        var inner = "'\(python3Path)' '\(scriptPath)' --timeout \(timeoutSec)"
        if let nameFilter, !nameFilter.isEmpty,
           nameFilter.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }) {
            inner += " --name '\(nameFilter)'"
        }
        inner += " > '\(logFile)' 2>&1"

        let script = """
        do shell script "\(inner)" with administrator privileges
        """

        let outcome: WiFiPairingResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var asError: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: .scriptError("Could not create AppleScript wrapper"))
                    return
                }
                _ = appleScript.executeAndReturnError(&asError)

                // Read the log file regardless of error so we can show the user
                // the script's own diagnostic output.
                let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
                let truncated = logContent.count > 8000 ? String(logContent.suffix(8000)) : logContent

                if let asError {
                    let errorMessage = asError[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    if errorMessage.lowercased().contains("cancel") {
                        Task { @MainActor in self.wifiPairingLog = truncated }
                        continuation.resume(returning: .userCancelled)
                    } else {
                        Task { @MainActor in self.wifiPairingLog = truncated }
                        continuation.resume(returning: .scriptError(errorMessage))
                    }
                    return
                }

                Task { @MainActor in self.wifiPairingLog = truncated }

                if logContent.contains("Pair record written") {
                    // Count how many devices the script reported.
                    var deviceCount = 0
                    for line in logContent.components(separatedBy: .newlines) where line.hasPrefix("[pair-wifi] Found ") {
                        let parts = line.split(separator: " ")
                        if parts.count > 2, let n = Int(parts[2]) {
                            deviceCount = n
                            break
                        }
                    }
                    continuation.resume(returning: .success(deviceCount: max(deviceCount, 1)))
                } else if logContent.contains("no _remotepairing-manual-pairing instances found") {
                    continuation.resume(returning: .noDevicesFound)
                } else {
                    continuation.resume(returning: .scriptError("pair_wifi.py exited without writing a pair record. See log for details."))
                }
            }
        }

        await MainActor.run { self.lastWiFiPairingResult = outcome }

        switch outcome {
        case .success(let count):
            statusMessage = "Wi-Fi pairing succeeded (\(count) device(s))."
        case .noDevicesFound:
            statusMessage = "Wi-Fi pairing failed: no iPhone advertising _remotepairing-manual-pairing on this network."
        case .scriptError(let message):
            statusMessage = "Wi-Fi pairing failed: \(message)"
        case .userCancelled:
            statusMessage = "Wi-Fi pairing cancelled."
        case .scriptMissing:
            statusMessage = "Wi-Fi pairing helper script not found in app bundle."
        }

        return outcome
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
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] {
                var updatedInfo = deviceTunnelInfo

                for (udid, entries) in json {
                    guard isSafeUDID(udid), let entry = entries.first else { continue }

                    let address = entry["tunnel-address"] as? String ??
                        entry["rsd-address"] as? String ??
                        entry["address"] as? String
                    let port = entry["tunnel-port"] as? Int ??
                        entry["rsd-port"] as? Int ??
                        entry["port"] as? Int ??
                        Int(entry["tunnel-port"] as? String ?? "") ??
                        Int(entry["rsd-port"] as? String ?? "") ??
                        Int(entry["port"] as? String ?? "")
                    let interface = entry["interface"] as? String

                    guard let address,
                          isValidRsdAddress(address),
                          let port,
                          isValidRsdPort(port) else {
                        continue
                    }

                    updatedInfo[udid] = TunnelInfo(
                        rsdAddress: address,
                        rsdPort: port,
                        mode: activeMode ?? stateMachine.currentContext.activeMode ?? .auto,
                        interface: interface,
                        processId: stateMachine.currentContext.activeProcessIds.first
                    )
                }

                deviceTunnelInfo = updatedInfo
                Logger.debug("📍 Successfully queried tunneld API for \(updatedInfo.count) device tunnel(s)", category: .device)
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
        if tunnelInfo == nil, let recoveredInfo = recoverRsdInfoFromLog() {
            tunnelInfo = recoveredInfo
        }

        // Fall back to legacy single tunnel info
        return tunnelInfo
    }

    /// Recover RSD info from the tunnel log when an existing lockdown tunnel was detected.
    private func recoverRsdInfoFromLog() -> TunnelInfo? {
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return nil
        }

        var rsdAddress: String?
        var rsdPort: Int?
        var interface: String?

        (rsdAddress, rsdPort) = parseRsdHintLine(from: logContent)

        if rsdAddress == nil || rsdPort == nil {
            (rsdAddress, rsdPort, interface) = parseStructuredLogLines(from: logContent)
        }

        if rsdAddress == nil || rsdPort == nil,
           let jsonResult = try? parseJsonOutput(from: logContent) {
            rsdAddress = jsonResult.address
            rsdPort = jsonResult.port
            interface = jsonResult.interface
        }

        guard let address = rsdAddress,
              isValidRsdAddress(address),
              let port = rsdPort,
              isValidRsdPort(port) else {
            return nil
        }

        let info = TunnelInfo(
            rsdAddress: address,
            rsdPort: port,
            mode: activeMode ?? stateMachine.currentContext.activeMode ?? .usb,
            interface: interface,
            processId: stateMachine.currentContext.activeProcessIds.first
        )
        Logger.info("Recovered tunnel RSD info from log: \(address):\(port)", category: .device)
        return info
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
                guard let self = self else { return }
                Logger.error("🔴 Tunnel connectivity lost; automatic privileged restart is disabled", category: .device)
                self.lastError = "Tunnel connection lost. Reconnect the device and click Start to retry."
                self.statusMessage = "Tunnel disconnected"
                self.monitorTask?.cancel()
                self.monitorTask = nil
                self.healthMonitor.stopMonitoring()
                self.stateMachine.send(.healthCheckFailed)
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
    nonisolated private static let maxOutputSize = 1_048_576

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
    nonisolated static var maxOutputSizeLimit: Int {
        return maxOutputSize
    }
}

// MARK: - App Delegate for Lifecycle Management

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sparkle updater controller for auto-updates
    lazy var updaterController = UpdaterController()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Tunnel startup is manual by default to avoid unexpected administrator prompts on launch.
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Handled by TunneldManager's notification observer
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
