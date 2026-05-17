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
/// | WiFi | No | Legacy manual-pairing Wi-Fi for iOS 17/18 |
/// | Daemon | No | Recommended wireless path for iOS 26+ |
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
            return "Legacy manual-pairing Wi-Fi path for iOS 17/18"
        case .daemon:
            return "Recommended wireless mode for iOS 26+"
        }
    }

    var displayName: String {
        switch self {
        case .wifi:
            return "WiFi Only (Legacy)"
        default:
            return rawValue
        }
    }

    static func usesDaemonForModernWireless(
        requested mode: TunnelMode,
        targetIOSMajorVersion: Int?,
        targetConnectionType: ConnectionType?
    ) -> Bool {
        guard let targetIOSMajorVersion, targetIOSMajorVersion >= 26 else {
            return false
        }

        if mode == .wifi {
            return true
        }

        return mode == .auto && targetConnectionType == .wifi
    }

    static func effectiveMode(
        requested mode: TunnelMode,
        targetIOSMajorVersion: Int?,
        targetConnectionType: ConnectionType?
    ) -> TunnelMode {
        usesDaemonForModernWireless(
            requested: mode,
            targetIOSMajorVersion: targetIOSMajorVersion,
            targetConnectionType: targetConnectionType
        ) ? .daemon : mode
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
///     print("Tunnel idle")
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
/// Only allows pre-approved pymobiledevice3 operations to prevent command injection.
///
/// Python-path and forbidden-character lists are sourced from `SubprocessPolicy`
/// (single source of truth). Command-pattern allowlist is kept local because
/// privileged commands are a narrower whitelist than general pmd3 invocations.
struct PrivilegedCommandValidator {

    // MARK: - Security Constants

    /// Allowed system Python executable paths — sourced from SubprocessPolicy.
    private static var allowedPythonPaths: Set<String> { SubprocessPolicy.allowedPythonPaths }

    /// Allowed pymobiledevice3 command patterns (exact subcommand match required).
    /// This is narrower than `SubprocessPolicy.allowedSubcommands` because only
    /// these specific compositions are permitted under privileged execution.
    private static let allowedCommandPatterns: [(module: String, subcommands: [String])] = [
        ("lockdown", ["start-tunnel"]),
        ("remote", ["start-tunnel", "-t", "wifi"]),
        ("remote", ["tunneld"])
    ]

    /// Characters that should NEVER appear in privileged commands — sourced from the
    /// narrower `SubprocessPolicy.privilegedCommandForbiddenCharacters` set.
    ///
    /// This is intentionally narrower than `SubprocessPolicy.forbiddenCharacters`
    /// because privileged shell commands legitimately contain `&` (backgrounding)
    /// and `>` (log redirect) — see SubprocessPolicy doc comment for rationale.
    private static var dangerousCharacters: Set<Character> { SubprocessPolicy.privilegedCommandForbiddenCharacters }

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
/// | WiFi | Legacy manual-pairing Wi-Fi | iOS 17/18 setups |
/// | Daemon | Background service | iOS 26+ wireless use |
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
    private var targetTunnelIOSMajorVersion: Int?
    private var tunnelStartInFlight = false
    private var tunnelLifecycleGeneration: UInt64 = 0
    private var recoveryTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var trackedTunnelChildProcessIds: Set<Int32> = []
    private var lastTunnelModeForCleanup: TunnelMode?
    private var lastTunnelTargetUDIDForCleanup: String?
#if DEBUG
    enum TestKillZeroResult {
        case allowed
        case permissionDenied
        case missing
    }
    private var debugProcessCommandOverrides: [Int32: String] = [:]
    private var debugProcessUIDOverrides: [Int32: uid_t] = [:]
    private var debugProcessStateOverrides: [Int32: String?] = [:]
    private var debugKillZeroResultOverrides: [Int32: TestKillZeroResult] = [:]
    private var debugLiveProcessIdsOverrides: [String: [Int32]] = [:]
    private var debugLiveProcessIdsSequenceOverrides: [String: [[Int32]]] = [:]
    private var debugStartupRsdInfoSequence: [TunnelInfo?] = []
    private var debugUsesStartupRsdInfoSequence = false
    private var debugStartupTimeoutOverride: TimeInterval?
    private var debugStartupPollIntervalOverride: TimeInterval?
    private var debugWrapperReturnTimeoutOverride: TimeInterval?
    private var debugPrivilegedWrapperRunner: (@Sendable (String) -> PrivilegedWrapperExecutionResult)?
    private var debugSignalHandler: (@MainActor (Int32, Int32) -> Bool)?
#endif

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

    private var startupTraceFilePath: String {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/PathChanger").path
        return "\(logsDir)/startup-trace.jsonl"
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
        case .launchProcess(let mode):
            // Normal UI/auto starts remain caller-owned by startTunnel().
            // Recovery starts, however, are emitted by the state machine and
            // must have a real launch owner; otherwise the state could enter
            // `.starting` without an operational launch path.
            guard stateMachine.currentContext.isRecovering else {
                Logger.debug("[Tunnel] Launch action acknowledged for caller-owned start path", category: .device)
                return
            }
            await launchRecoveryTunnel(mode: mode)

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
            scheduleRecovery(after: delay)

        case .logTransition(let from, let to, let event):
            Logger.info("[Tunnel] State transition: \(from) -> \(to) on \(event)", category: .device)

        case .notifyStateChange(let newState):
            // State synchronization handled by Combine subscription
            Logger.debug("[Tunnel] State changed to: \(newState)", category: .device)

        case .cleanupResources:
            cleanupTunnelProcessResources(terminateProcess: true)

        case .invalidateRsdInfo:
            invalidateRsdInfo(reason: "Tunnel lifecycle invalidated RSD ownership")
        }
    }

    private func cancelScheduledTunnelWork(cancelScheduledRestart: Bool) {
        recoveryTask?.cancel()
        recoveryTask = nil
        if cancelScheduledRestart {
            restartTask?.cancel()
            restartTask = nil
        }
    }

    private func advanceTunnelLifecycleGeneration(cancelScheduledRestart: Bool = false) -> UInt64 {
        tunnelLifecycleGeneration &+= 1
        cancelScheduledTunnelWork(cancelScheduledRestart: cancelScheduledRestart)
        return tunnelLifecycleGeneration
    }

    private func isCurrentTunnelLifecycle(_ generation: UInt64) -> Bool {
        tunnelLifecycleGeneration == generation
    }

    private var canAcceptRsdInfo: Bool {
        switch stateMachine.currentState {
        case .starting, .running:
            return true
        case .idle, .stopping, .error:
            return false
        }
    }

    private var canServeRsdInfo: Bool {
        stateMachine.currentState == .running
    }

    private var canRecoverRsdInfoFromLog: Bool {
        switch stateMachine.currentState {
        case .idle, .starting:
            return true
        case .running, .stopping, .error:
            return false
        }
    }

    private func invalidateRsdInfo(reason: String) {
        if tunnelInfo != nil || !deviceTunnelInfo.isEmpty {
            Logger.info("[Tunnel] Invalidating RSD info: \(reason)", category: .device)
        }
        tunnelInfo = nil
        deviceTunnelInfo.removeAll()
    }

    func invalidateActiveTunnelAfterTransportFailure(_ reason: String) {
        let message = "Tunnel transport failed: \(reason)"
        lastError = message
        statusMessage = "Tunnel disconnected"
        invalidateRsdInfo(reason: message)

        guard stateMachine.currentState.isActive else {
            return
        }

        stateMachine.send(.healthCheckFailed)
        syncStateWithStateMachine()
    }

    private func scheduleRecovery(after delay: TimeInterval) {
        recoveryTask?.cancel()
        guard stateMachine.currentContext.isRecovering,
              case .error = stateMachine.currentState else {
            recoveryTask = nil
            return
        }
        let generation = tunnelLifecycleGeneration

        recoveryTask = Task { [weak self] in
            guard let self else { return }
            let clampedDelay = max(0, delay)
            try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
            guard !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(generation),
                  self.stateMachine.currentContext.isRecovering else {
                return
            }
            guard case .error = self.stateMachine.currentState else {
                return
            }
            self.stateMachine.send(.recoveryAttempted)
        }
    }

    private func launchRecoveryTunnel(mode: TunnelMode) async {
        guard !tunnelStartInFlight else {
            Logger.debug("[Tunnel] Recovery launch ignored because another start is already in flight", category: .device)
            return
        }
        guard case .starting = stateMachine.currentState else {
            Logger.debug("[Tunnel] Recovery launch ignored because state is no longer starting", category: .device)
            return
        }

        let generation = tunnelLifecycleGeneration
        tunnelStartInFlight = true
        defer {
            tunnelStartInFlight = false
        }

        let success = await attemptStart(mode: mode)
        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            if success {
                killTrackedTunnelProcesses()
            }
            return
        }

        if success, let info = await waitForValidRsdInfo(mode: mode) {
            guard isCurrentTunnelLifecycle(generation),
                  case .starting = stateMachine.currentState else {
                return
            }
            stateMachine.send(.connectionEstablished(info: info))
            return
        }

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            return
        }

        if success {
            killTrackedTunnelProcesses()
        }
        stateMachine.send(.errorOccurred(lastError ?? "Failed to recover \(mode.rawValue) tunnel"))
    }

    private func cleanupTunnelProcessResources(terminateProcess: Bool) {
        monitorTask?.cancel()
        monitorTask = nil
        healthMonitor.stopMonitoring()

        if terminateProcess, let process = tunneldProcess, process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        tunneldProcess = nil
        outputPipe = nil
        errorPipe = nil
        invalidateRsdInfo(reason: "Tunnel process resources cleaned up")
        activeMode = nil
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
        let generation = advanceTunnelLifecycleGeneration(cancelScheduledRestart: true)
        tunnelStartInFlight = true
        defer {
            tunnelStartInFlight = false
        }

        lastError = nil
        if await attachToRunningTunnelIfAvailable(generation: generation) {
            return
        }
        guard isCurrentTunnelLifecycle(generation) else { return }

        let modesToTry: [TunnelMode]

        if preferredMode == .auto {
            let availability = await deviceConnectionAvailability()
            let useDaemonForModernWireless = TunnelMode.usesDaemonForModernWireless(
                requested: .auto,
                targetIOSMajorVersion: targetTunnelIOSMajorVersion,
                targetConnectionType: targetTunnelConnectionType
            )
            if let targetUDID = targetTunnelUDID, availability.usbUDID == targetUDID {
                modesToTry = [.usb]
            } else if let targetUDID = targetTunnelUDID,
                      availability.networkUDID == targetUDID,
                      targetTunnelConnectionType != .wifi {
                modesToTry = [.usb]
            } else if useDaemonForModernWireless {
                statusMessage = "Using Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ wireless tunneling."
                modesToTry = [.daemon]
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
            let requestedMode = preferredMode
            let effectiveMode = TunnelMode.effectiveMode(
                requested: requestedMode,
                targetIOSMajorVersion: targetTunnelIOSMajorVersion,
                targetConnectionType: targetTunnelConnectionType
            )

            if requestedMode == .wifi && effectiveMode == .daemon {
                statusMessage = "Using Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ wireless tunneling. WiFi Only requires legacy manual pairing."
                Logger.info("[Tunnel] Routing WiFi Only request to Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ target", category: .device)
            }

            switch effectiveMode {
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
            modesToTry = [effectiveMode]
        }
        guard isCurrentTunnelLifecycle(generation) else { return }

        for mode in modesToTry {
            Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

            // Send start event to state machine
            stateMachine.send(.startRequested(mode: mode))

            let success = await attemptStart(mode: mode)
            guard isCurrentTunnelLifecycle(generation) else {
                if success {
                    killTrackedTunnelProcesses()
                }
                return
            }

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
                    guard isCurrentTunnelLifecycle(generation) else { return }
                    stateMachine.send(.connectionEstablished(info: info))
                } else {
                    guard isCurrentTunnelLifecycle(generation) else { return }
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
            if case .error = stateMachine.currentState {
                syncStateWithStateMachine()
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
            targetTunnelIOSMajorVersion = nil
            return
        }

        guard isSafeUDID(device.id) else {
            Logger.debug("Ignoring unsafe tunnel target UDID", category: .security)
            return
        }

        targetTunnelUDID = device.id
        targetTunnelConnectionType = device.connectionType
        targetTunnelIOSMajorVersion = device.iosMajorVersion
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
        restartTask?.cancel()
        let generation = tunnelLifecycleGeneration
        restartTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(generation) else {
                return
            }

            self.stopTunnel(invalidateScheduledRestart: false)
            let restartGeneration = self.tunnelLifecycleGeneration
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms grace for processes to exit
            guard !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(restartGeneration) else {
                return
            }

            self.restartTask = nil
            await self.startTunnel()
        }
    }

    /// Stop the tunnel
    func stopTunnel() {
        stopTunnel(invalidateScheduledRestart: true)
    }

    private func stopTunnel(invalidateScheduledRestart: Bool) {
        stopTunnel(invalidateScheduledRestart: invalidateScheduledRestart, advanceGeneration: true)
    }

    private func stopTunnel(invalidateScheduledRestart: Bool, advanceGeneration: Bool) {
        if advanceGeneration {
            _ = advanceTunnelLifecycleGeneration(cancelScheduledRestart: invalidateScheduledRestart)
        } else {
            cancelScheduledTunnelWork(cancelScheduledRestart: invalidateScheduledRestart)
        }
        // Send stop event to state machine
        stateMachine.send(.stopRequested)

        // Kill tracked tunnel processes (security hardened - PID-based only)
        killTrackedTunnelProcesses()
        cleanupTunnelProcessResources(terminateProcess: true)

        // Mark process as stopped
        stateMachine.send(.processStopped)
    }

    /// Restart tunnel
    func restartTunnel() async {
        stopTunnel(invalidateScheduledRestart: true)
        let generation = tunnelLifecycleGeneration
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
        guard isCurrentTunnelLifecycle(generation) else { return }
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
    private func validateSingleTunnelInstance(mode: TunnelMode, targetUDID: String?) async -> Bool {
        let pids = await liveTunnelProcessIds(for: mode, targetUDID: targetUDID)

        // Get tracked PIDs from state machine context
        let trackedPids = stateMachine.currentContext.activeProcessIds

        // Check if we already know about these PIDs
        let lifecyclePids = trackedPids.union(trackedTunnelChildProcessIds)
        let newPids = pids.filter { !lifecyclePids.contains($0) }

        if newPids.count > 1 {
            // Multiple NEW processes detected - race condition!
            Logger.debug("Detected \(newPids.count) tunnel child processes for \(mode.rawValue), keeping only first", category: .device)

            // Keep only the first PID, kill the rest
            for pid in newPids.dropFirst() {
                _ = sendSignalToValidatedTunnelProcess(pid: pid, signal: SIGKILL, mode: mode, targetUDID: targetUDID)
            }

            // Track the surviving process via state machine event
            if let firstPid = newPids.first {
                trackedTunnelChildProcessIds.insert(firstPid)
                lastTunnelModeForCleanup = mode
                lastTunnelTargetUDIDForCleanup = targetUDID
                stateMachine.send(.processLaunched(pid: firstPid))
            }

            return true
        } else if let pid = newPids.first {
            // Single new process - track it via state machine
            trackedTunnelChildProcessIds.insert(pid)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            stateMachine.send(.processLaunched(pid: pid))
            return true
        } else if !pids.isEmpty {
            // All PIDs are already tracked
            trackedTunnelChildProcessIds.formUnion(pids)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            return true
        }

        return false
    }

    private func liveProcessIds(matching pattern: String) async -> [Int32] {
        liveProcessIdsSync(matching: pattern)
    }

    private func liveProcessIdsSync(matching pattern: String) -> [Int32] {
#if DEBUG
        if var sequence = debugLiveProcessIdsSequenceOverrides[pattern] {
            let pids = sequence.isEmpty ? [] : sequence.removeFirst()
            debugLiveProcessIdsSequenceOverrides[pattern] = sequence
            return Array(Set(pids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        }
        if let overridePids = debugLiveProcessIdsOverrides[pattern] {
            return Array(Set(overridePids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        }
#endif
        do {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-f", pattern]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return []
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            let pids = output
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            return Array(Set(pids))
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .sorted()
        } catch {
            return []
        }
    }

    private func liveTunnelProcessIds(for mode: TunnelMode, targetUDID: String?) async -> [Int32] {
        liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID)
    }

    private func liveTunnelProcessIdsSync(for mode: TunnelMode, targetUDID: String?) -> [Int32] {
        liveProcessIdsSync(matching: mode.processPattern)
            .filter { isValidatedTunnelProcess(pid: $0, mode: mode, targetUDID: targetUDID) }
            .sorted()
    }

    private func recordLaunchedTunnelChildren(mode: TunnelMode, targetUDID: String?, beforeLaunchPids: Set<Int32>) {
        let currentPids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
        let launchedPids = currentPids.subtracting(beforeLaunchPids)

        guard !launchedPids.isEmpty else {
            Logger.debug("[Tunnel] No new pmd3 tunnel child PID detected after \(mode.rawValue) launch", category: .device)
            return
        }

        trackedTunnelChildProcessIds.formUnion(launchedPids)
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID
        Logger.info("[Tunnel] Tracking pmd3 tunnel child PID(s): \(launchedPids.sorted().map(String.init).joined(separator: ", "))", category: .device)
    }

    private func processCommand(pid: Int32) -> String? {
#if DEBUG
        if let override = debugProcessCommandOverrides[pid] {
            return override
        }
        if let stateOverrideIndex = debugProcessStateOverrides.index(forKey: pid),
           debugProcessStateOverrides[stateOverrideIndex].value == nil {
            return nil
        }
#endif
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "command="]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        do {
            try ps.run()
            ps.waitUntilExit()
        } catch {
            return nil
        }

        guard ps.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let command = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private func processUID(pid: Int32) -> uid_t? {
#if DEBUG
        if let override = debugProcessUIDOverrides[pid] {
            return override
        }
        if let stateOverrideIndex = debugProcessStateOverrides.index(forKey: pid),
           debugProcessStateOverrides[stateOverrideIndex].value == nil {
            return nil
        }
#endif
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
            return nil
        }

        guard ps.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let uid = uid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return uid
    }

    private func isValidatedTunnelProcess(pid: Int32, mode: TunnelMode, targetUDID: String?) -> Bool {
        isValidatedTunnelProcess(pid: pid, mode: mode, targetUDID: targetUDID, allowMissingTargetUDID: false)
    }

    private func isValidatedTunnelProcess(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        allowMissingTargetUDID: Bool
    ) -> Bool {
        guard let command = processCommand(pid: pid),
              Self.isSanctionedTunnelChildCommand(
                command,
                mode: mode,
                targetUDID: targetUDID,
                requireTargetUDID: !allowMissingTargetUDID
              ),
              let uid = processUID(pid: pid) else {
            return false
        }

        return uid == getuid() || uid == 0
    }

    private func isValidatedTunnelProcess(pid: Int32, cleanupMode: TunnelMode?, targetUDID: String?) -> Bool {
        isValidatedTunnelProcess(pid: pid, cleanupMode: cleanupMode, targetUDID: targetUDID, allowMissingTargetUDID: false)
    }

    private func isValidatedTunnelProcess(
        pid: Int32,
        cleanupMode: TunnelMode?,
        targetUDID: String?,
        allowMissingTargetUDID: Bool
    ) -> Bool {
        let modes = cleanupMode.map { [$0] } ?? [.usb, .wifi, .daemon]
        return modes.contains {
            isValidatedTunnelProcess(
                pid: pid,
                mode: $0,
                targetUDID: targetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
            )
        }
    }

    nonisolated private static func isSanctionedTunnelChildCommand(_ command: String, mode: TunnelMode, targetUDID: String?) -> Bool {
        isSanctionedTunnelChildCommand(command, mode: mode, targetUDID: targetUDID, requireTargetUDID: true)
    }

    nonisolated private static func isSanctionedTunnelChildCommand(
        _ command: String,
        mode: TunnelMode,
        targetUDID: String?,
        requireTargetUDID: Bool
    ) -> Bool {
        guard mode != .auto else {
            return false
        }

        let normalized = command
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable = normalized.split(separator: " ").first.map(String.init),
              executable.hasSuffix("python3"),
              normalized.contains("-m pymobiledevice3") else {
            return false
        }

        let modeMatches: Bool
        switch mode {
        case .usb:
            modeMatches = normalized.contains("pymobiledevice3 lockdown start-tunnel")
        case .wifi:
            modeMatches = normalized.contains("pymobiledevice3 remote start-tunnel") &&
                normalized.contains("-t wifi")
        case .daemon:
            modeMatches = normalized.contains("pymobiledevice3 remote tunneld")
        case .auto:
            modeMatches = false
        }

        guard modeMatches else {
            return false
        }

        if requireTargetUDID, mode != .daemon, let targetUDID {
            return normalized.contains(targetUDID)
        }

        return true
    }

    private func cleanupCandidateProcessIds(mode: TunnelMode?, targetUDID: String?) -> [Int32] {
        let lifecycleCandidates = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        var candidates = Set(
            lifecycleCandidates
                .filter { isProcessAliveAndNonZombie(pid: $0) }
                .filter {
                    isValidatedTunnelProcess(
                        pid: $0,
                        cleanupMode: mode,
                        targetUDID: targetUDID,
                        allowMissingTargetUDID: true
                    )
                }
        )

        if let mode {
            candidates.formUnion(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
        }

        return candidates
            .filter { isProcessAliveAndNonZombie(pid: $0) }
            .filter {
                isValidatedTunnelProcess(
                    pid: $0,
                    cleanupMode: mode,
                    targetUDID: targetUDID,
                    allowMissingTargetUDID: lifecycleCandidates.contains($0)
                )
            }
            .sorted()
    }

    private func sendSignalToValidatedTunnelProcess(
        pid: Int32,
        signal: Int32,
        mode: TunnelMode?,
        targetUDID: String?,
        allowMissingTargetUDID: Bool = false
    ) -> Bool {
        guard pid > 1,
              signal == SIGTERM || signal == SIGKILL,
              isValidatedTunnelProcess(
                pid: pid,
                cleanupMode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
              ),
              let uid = processUID(pid: pid) else {
            Logger.debug("[SECURITY] Refusing to signal unvalidated tunnel PID \(pid)", category: .security)
            return false
        }
#if DEBUG
        if let debugSignalHandler {
            return debugSignalHandler(pid, signal)
        }
#endif

        if uid == getuid() {
            return sendLocalSignal(signal, to: pid)
        }

        guard uid == 0 else {
            Logger.debug("[SECURITY] Refusing to signal PID \(pid) owned by UID \(uid)", category: .security)
            return false
        }

        return sendPrivilegedSignal(signal, to: pid)
    }

    private func sendLocalSignal(_ signal: Int32, to pid: Int32) -> Bool {
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
        killProcess.arguments = ["-\(signal)", String(pid)]

        do {
            try killProcess.run()
            killProcess.waitUntilExit()
            return killProcess.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func sendPrivilegedSignal(_ signal: Int32, to pid: Int32) -> Bool {
        let command = "/bin/kill -\(signal) \(pid)"
        let script = """
        do shell script "\(command)" with administrator privileges
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }

        appleScript.executeAndReturnError(&error)
        if let error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown privileged kill error"
            Logger.debug("[SECURITY] Privileged kill failed for PID \(pid): \(errorMessage)", category: .security)
            return false
        }

        return true
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
        // BUG FIX (WiFi-Bonjour-Timeout): the prior 3-second `remote browse`
        // window was empirically too short on real networks — a live capture
        // showed `pmd3 remote browse --timeout 5` returning `{"usb":[],"wifi":[]}`
        // while `--timeout 15` found the iPhone immediately. Bumping to 8s
        // gives the responder time to multicast on slow Wi-Fi (and increasing
        // the outer Swift-side timeout to 12s so the subprocess has headroom
        // to flush JSON output before we kill it).
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color",
                "remote", "browse",
                "--timeout", "8"
            ], timeout: 12.0)

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
            let pids = await liveTunnelProcessIds(for: mode, targetUDID: targetTunnelUDID)
            if !pids.isEmpty {
                return mode
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
        if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
            return info
        }
        if let info = tunnelInfo, isUsableTunnelInfo(info) {
            return info
        }
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

    private func startupAcquisitionTimeout(for mode: TunnelMode) -> TimeInterval {
#if DEBUG
        if let debugStartupTimeoutOverride {
            return debugStartupTimeoutOverride
        }
#endif
        switch mode {
        case .daemon:
            return 45
        case .usb, .wifi, .auto:
            return 30
        }
    }

    private var startupAcquisitionPollInterval: TimeInterval {
#if DEBUG
        if let debugStartupPollIntervalOverride {
            return debugStartupPollIntervalOverride
        }
#endif
        return 0.5
    }

    private var handoffStabilizationTimeout: TimeInterval {
        0.75
    }

    private var handoffStabilizationPollInterval: TimeInterval {
#if DEBUG
        if let debugStartupPollIntervalOverride {
            return debugStartupPollIntervalOverride
        }
#endif
        return 0.02
    }

    private func wrapperReturnTimeout(for mode: TunnelMode) -> TimeInterval {
#if DEBUG
        if let debugWrapperReturnTimeoutOverride {
            return debugWrapperReturnTimeoutOverride
        }
#endif
        return max(15, startupAcquisitionTimeout(for: mode) * 3)
    }

    private func logStartupTrace(_ event: String, fields: [String: Any] = [:]) {
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = details.isEmpty ? "" : " \(details)"
        Logger.info("[Tunnel][Startup] \(event) t=\(Date().timeIntervalSince1970)\(suffix)", category: .device)
        appendStartupTrace(event, fields: fields)
    }

    private func appendStartupTrace(_ event: String, fields: [String: Any]) {
        var payload = fields
        payload["event"] = event
        payload["timestamp"] = Date().timeIntervalSince1970
        payload["state"] = "\(stateMachine.currentState)"

        guard JSONSerialization.isValidJSONObject(startupTraceSanitized(payload)),
              let data = try? JSONSerialization.data(withJSONObject: startupTraceSanitized(payload), options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }

        ensureLogDirectoryExists()
        let traceLine = line + "\n"
        if FileManager.default.fileExists(atPath: startupTraceFilePath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: startupTraceFilePath)) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(traceLine.utf8))
            try? handle.close()
        } else {
            try? traceLine.write(toFile: startupTraceFilePath, atomically: true, encoding: .utf8)
        }
    }

    private func startupTraceSanitized(_ value: Any) -> Any {
        if let value = value as? [String: Any] {
            return value.mapValues { startupTraceSanitized($0) }
        }
        if let value = value as? [Any] {
            return value.map { startupTraceSanitized($0) }
        }
        if let value = value as? Set<Int32> {
            return value.sorted().map(Int.init)
        }
        if let value = value as? Int32 {
            return Int(value)
        }
        if let value = value as? UInt64 {
            return String(value)
        }
        if JSONSerialization.isValidJSONObject(["value": value]) {
            return value
        }
        return "\(value)"
    }

    private func waitForAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        handedOffPid: Int32?
    ) async -> TunnelInfo? {
        let timeout = startupAcquisitionTimeout(for: mode)
        let pollInterval = startupAcquisitionPollInterval
        let deadline = Date().addingTimeInterval(timeout)
        var authoritativePid: Int32?
        var pollCount = 0
        let waitStartTime = Date().timeIntervalSince1970

        logStartupTrace("authoritative_wait_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "timeout": timeout,
            "pollInterval": pollInterval,
            "beforeLaunchPids": beforeLaunchPids.sorted(),
            "handedOffPid": handedOffPid as Any
        ])

        if let handedOffPid {
            guard let validatedPid = await waitForStableHandedOffTunnelChild(
                pid: handedOffPid,
                mode: mode,
                targetUDID: targetUDID,
                beforeLaunchPids: beforeLaunchPids,
                startupDeadline: deadline,
                waitStartTime: waitStartTime,
                phase: "handoff"
            ) else {
                await finalizeFailedStartupAcquisition(
                    mode: mode,
                    targetUDID: targetUDID,
                    generation: generation,
                    waitStartTime: waitStartTime,
                    pollCount: pollCount,
                    handedOffPid: handedOffPid,
                    beforeLaunchPids: beforeLaunchPids
                )
                return nil
            }

            authoritativePid = adoptAuthoritativeTunnelChild(
                pid: validatedPid,
                mode: mode,
                targetUDID: targetUDID,
                phase: "handoff"
            )
        }

        if let info = await pollAuthoritativeStartup(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: generation,
            deadline: deadline,
            phase: handedOffPid == nil ? "discovery" : "handoff",
            pollInterval: pollInterval,
            authoritativePid: &authoritativePid,
            pollCount: &pollCount
        ) {
            logStartupTrace("authoritative_wait_ready", fields: [
                "mode": mode.rawValue,
                "phase": handedOffPid == nil ? "discovery" : "handoff",
                "pid": info.processId ?? -1,
                "rsdAddress": info.rsdAddress,
                "rsdPort": info.rsdPort,
                "poll": pollCount,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
            return info
        }

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            logStartupTrace("authoritative_wait_cancelled", fields: [
                "mode": mode.rawValue,
                "state": "\(stateMachine.currentState)",
                "poll": pollCount,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
            return nil
        }
        logStartupTrace("authoritative_wait_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "activeProcessIds": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        await finalizeFailedStartupAcquisition(
            mode: mode,
            targetUDID: targetUDID,
            generation: generation,
            waitStartTime: waitStartTime,
            pollCount: pollCount,
            handedOffPid: handedOffPid,
            beforeLaunchPids: beforeLaunchPids
        )
        return nil
    }

    private func pollAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        deadline: Date,
        phase: String,
        pollInterval: TimeInterval,
        authoritativePid: inout Int32?,
        pollCount: inout Int
    ) async -> TunnelInfo? {
        while Date() < deadline {
            guard isCurrentTunnelLifecycle(generation) else {
                logStartupTrace("authoritative_wait_cancelled_generation_changed", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "poll": pollCount
                ])
                return nil
            }

            guard case .starting = stateMachine.currentState else {
                logStartupTrace("authoritative_wait_cancelled_state_changed", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "state": "\(stateMachine.currentState)",
                    "poll": pollCount
                ])
                return nil
            }

            pollCount += 1
            if authoritativePid == nil {
                authoritativePid = acquireAuthoritativeTunnelChild(
                    mode: mode,
                    targetUDID: targetUDID,
                    beforeLaunchPids: beforeLaunchPids,
                    pollCount: pollCount,
                    phase: phase
                )
            }

            if let authoritativePid,
               let info = await startupRsdInfo(mode: mode, authoritativePid: authoritativePid) {
                let authoritativeInfo = tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
                tunnelInfo = authoritativeInfo
                logStartupTrace("authoritative_poll_ready", fields: [
                    "mode": mode.rawValue,
                    "phase": phase,
                    "pid": authoritativePid,
                    "rsdAddress": authoritativeInfo.rsdAddress,
                    "rsdPort": authoritativeInfo.rsdPort,
                    "poll": pollCount
                ])
                return authoritativeInfo
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.001, pollInterval) * 1_000_000_000))
        }

        return nil
    }

    private func finalizeFailedStartupAcquisition(
        mode: TunnelMode,
        targetUDID: String?,
        generation: UInt64,
        waitStartTime: TimeInterval,
        pollCount: Int,
        handedOffPid: Int32? = nil,
        beforeLaunchPids: Set<Int32> = []
    ) async {
        if let handedOffPid,
           let cleanupPid = await waitForStableHandedOffTunnelChild(
            pid: handedOffPid,
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            startupDeadline: Date().addingTimeInterval(handoffStabilizationTimeout),
            waitStartTime: waitStartTime,
            phase: "cleanup"
           ) {
            trackedTunnelChildProcessIds.insert(cleanupPid)
            lastTunnelModeForCleanup = mode
            lastTunnelTargetUDIDForCleanup = targetUDID
            logStartupTrace("startup_failure_cleanup_handoff_candidate_included", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": cleanupPid,
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])
        }
        logStartupTrace("startup_failure_cleanup_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "poll": pollCount,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "activeProcessIds": stateMachine.currentContext.activeProcessIds.sorted()
        ])
        killTrackedTunnelProcesses()

        let remainingCandidates = cleanupCandidateProcessIds(mode: mode, targetUDID: targetUDID)
        logStartupTrace("startup_failure_cleanup_complete", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "remainingCandidates": remainingCandidates,
            "trackedChildPids": trackedTunnelChildProcessIds.sorted(),
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])
    }

    private func waitForStableHandedOffTunnelChild(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        startupDeadline: Date,
        waitStartTime: TimeInterval,
        phase: String
    ) async -> Int32? {
        let stabilizationDeadline = min(
            startupDeadline,
            Date().addingTimeInterval(handoffStabilizationTimeout)
        )
        var attempt = 0

        logStartupTrace("handoff_stabilization_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "phase": phase,
            "timeout": handoffStabilizationTimeout,
            "pollInterval": handoffStabilizationPollInterval,
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])

        repeat {
            attempt += 1
            if let validatedPid = validateHandedOffTunnelChild(
                pid: pid,
                mode: mode,
                targetUDID: targetUDID,
                beforeLaunchPids: beforeLaunchPids
            ) {
                logStartupTrace("handoff_stabilization_validated", fields: [
                    "mode": mode.rawValue,
                    "targetUDID": targetUDID ?? "nil",
                    "pid": pid,
                    "phase": phase,
                    "attempt": attempt,
                    "elapsed": Date().timeIntervalSince1970 - waitStartTime
                ])
                return validatedPid
            }

            logStartupTrace("handoff_stabilization_retry", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": pid,
                "phase": phase,
                "attempt": attempt,
                "snapshot": processValidationSnapshot(pid: pid),
                "elapsed": Date().timeIntervalSince1970 - waitStartTime
            ])

            guard Date() < stabilizationDeadline else {
                break
            }

            try? await Task.sleep(nanoseconds: UInt64(max(0.001, handoffStabilizationPollInterval) * 1_000_000_000))
        } while Date() < stabilizationDeadline

        logStartupTrace("handoff_stabilization_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "phase": phase,
            "attempts": attempt,
            "snapshot": processValidationSnapshot(pid: pid),
            "elapsed": Date().timeIntervalSince1970 - waitStartTime
        ])
        return nil
    }

    private func validateHandedOffTunnelChild(
        pid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>
    ) -> Int32? {
        let snapshot = processValidationSnapshot(pid: pid)

        func reject(_ reason: String) -> Int32? {
            logStartupTrace("handoff_pid_rejected", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "pid": pid,
                "reason": reason,
                "snapshot": snapshot
            ])
            return nil
        }

        guard pid > 1 else {
            return reject("pid_not_signalable")
        }
        guard !beforeLaunchPids.contains(pid) else {
            return reject("pid_existed_before_launch")
        }
        guard isProcessAliveAndNonZombie(pid: pid) else {
            return reject("pid_not_live_or_zombie")
        }
        guard let command = processCommand(pid: pid) else {
            return reject("command_unavailable")
        }
        guard Self.isSanctionedTunnelChildCommand(
            command,
            mode: mode,
            targetUDID: targetUDID,
            requireTargetUDID: mode != .daemon
        ) else {
            return reject("command_mode_or_udid_mismatch")
        }
        guard let uid = processUID(pid: pid) else {
            return reject("uid_unavailable")
        }
        guard uid == getuid() || uid == 0 else {
            return reject("uid_not_allowed")
        }

        logStartupTrace("handoff_pid_validated", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "pid": pid,
            "snapshot": snapshot
        ])
        return pid
    }

    private func processValidationSnapshot(pid: Int32) -> [String: Any] {
        [
            "pid": pid,
            "command": processCommand(pid: pid) ?? "nil",
            "uid": processUID(pid: pid).map(Int.init) as Any,
            "state": processState(pid: pid) ?? "nil",
            "aliveNonZombie": isProcessAliveAndNonZombie(pid: pid)
        ]
    }

    private func parseHandedOffPid(from output: String) -> Int32? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.allSatisfy({ $0.isNumber }),
                  let value = Int32(trimmed),
                  value > 1 else {
                continue
            }
            return value
        }
        return nil
    }

    private func acquireAuthoritativeTunnelChild(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        pollCount: Int,
        phase: String
    ) -> Int32? {
        let livePids = liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID)
        let lifecyclePids = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        let startupPids = livePids.filter {
            !beforeLaunchPids.contains($0) || lifecyclePids.contains($0)
        }

        logStartupTrace("child_acquisition_poll", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "phase": phase,
            "poll": pollCount,
            "livePids": livePids,
            "startupPids": startupPids,
            "trackedPids": trackedTunnelChildProcessIds.sorted(),
            "statePids": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        guard let authoritativePid = startupPids.first else {
            return nil
        }

        if startupPids.count > 1 {
            for extraPid in startupPids.dropFirst() {
                _ = sendSignalToValidatedTunnelProcess(
                    pid: extraPid,
                    signal: SIGKILL,
                    mode: mode,
                    targetUDID: targetUDID,
                    allowMissingTargetUDID: lifecyclePids.contains(extraPid)
                )
            }
        }

        return adoptAuthoritativeTunnelChild(
            pid: authoritativePid,
            mode: mode,
            targetUDID: targetUDID,
            phase: phase
        )
    }

    private func adoptAuthoritativeTunnelChild(
        pid authoritativePid: Int32,
        mode: TunnelMode,
        targetUDID: String?,
        phase: String
    ) -> Int32 {
        trackedTunnelChildProcessIds.insert(authoritativePid)
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID

        if !stateMachine.currentContext.activeProcessIds.contains(authoritativePid) {
            stateMachine.send(.processLaunched(pid: authoritativePid))
            syncStateWithStateMachine()
        }

        logStartupTrace("child_acquired", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "phase": phase,
            "pid": authoritativePid,
            "trackedPids": trackedTunnelChildProcessIds.sorted(),
            "statePids": stateMachine.currentContext.activeProcessIds.sorted()
        ])

        return authoritativePid
    }

    private func startupRsdInfo(mode: TunnelMode, authoritativePid: Int32) async -> TunnelInfo? {
#if DEBUG
        if debugUsesStartupRsdInfoSequence {
            guard !debugStartupRsdInfoSequence.isEmpty else {
                logStartupTrace("rsd_sequence_exhausted", fields: [
                    "mode": mode.rawValue,
                    "pid": authoritativePid
                ])
                return nil
            }
            guard let info = debugStartupRsdInfoSequence.removeFirst() else {
                logStartupTrace("rsd_not_ready_debug", fields: [
                    "mode": mode.rawValue,
                    "pid": authoritativePid
                ])
                return nil
            }
            let authoritativeInfo = tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
            tunnelInfo = authoritativeInfo
            logStartupTrace("rsd_ready_debug", fields: [
                "mode": mode.rawValue,
                "pid": authoritativePid,
                "rsdAddress": authoritativeInfo.rsdAddress,
                "rsdPort": authoritativeInfo.rsdPort
            ])
            return authoritativeInfo
        }
#endif
        await parseRsdInfo()
        if let info = stateMachine.currentContext.tunnelInfo, isUsableTunnelInfo(info) {
            return tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
        }
        if let info = tunnelInfo, isUsableTunnelInfo(info) {
            return tunnelInfoWithAuthoritativeProcessId(info, pid: authoritativePid)
        }
        return nil
    }

    private func tunnelInfoWithAuthoritativeProcessId(_ info: TunnelInfo, pid: Int32) -> TunnelInfo {
        guard info.processId != pid else {
            return info
        }
        return TunnelInfo(
            rsdAddress: info.rsdAddress,
            rsdPort: info.rsdPort,
            mode: info.mode,
            interface: info.interface,
            processId: pid
        )
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
    private func attachToRunningTunnelIfAvailable(generation: UInt64) async -> Bool {
        guard let runningMode = await detectRunningTunnel() else {
            return false
        }
        guard isCurrentTunnelLifecycle(generation) else { return true }

        // Mode-aware reattach gate: refuse to silently bind to a tunnel that doesn't
        // match the user's explicit preference.
        let desiredMode = TunnelMode.effectiveMode(
            requested: preferredMode,
            targetIOSMajorVersion: targetTunnelIOSMajorVersion,
            targetConnectionType: targetTunnelConnectionType
        )
        let modeMatches = preferredMode == .auto || desiredMode == runningMode
        if !modeMatches {
            Logger.info(
                "[Tunnel] Existing \(runningMode.rawValue) tunnel detected but preferredMode is \(preferredMode.rawValue) (effective \(desiredMode.rawValue)) - stopping it to start fresh in requested mode",
                category: .device
            )
            statusMessage = "Stopping \(runningMode.rawValue) tunnel to switch to \(desiredMode.rawValue)..."
            stopTunnel(invalidateScheduledRestart: true, advanceGeneration: false)
            try? await Task.sleep(nanoseconds: 500_000_000) // grace for processes to exit
            guard isCurrentTunnelLifecycle(generation) else { return true }
            return false
        }

        guard let recoveredInfo = recoverRsdInfoFromLog() else {
            let message = "A tunnel process is already running, but PathChanger could not read its RSD address. Stop the existing tunnel and start it again."
            lastError = message
            statusMessage = message
            Logger.error(message, category: .device)
            return true
        }
        guard isCurrentTunnelLifecycle(generation) else { return true }

        tunnelInfo = recoveredInfo
        lastError = nil
        statusMessage = "Tunnel already running (RSD: \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort))"
        Logger.info("Attached to existing \(runningMode.rawValue) tunnel at \(recoveredInfo.rsdAddress):\(recoveredInfo.rsdPort)", category: .device)
        stateMachine.send(.externalTunnelDetected(mode: runningMode, info: recoveredInfo))
        return true
    }

    private func finalizeWrapperReturnTimeout(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64,
        timeout: TimeInterval
    ) {
        let message = "Privileged \(mode.rawValue) tunnel wrapper did not return a handed-off PID within \(String(format: "%.1f", timeout)) seconds. Startup was failed closed."
        lastError = message
        statusMessage = message
        logStartupTrace("wrapper_return_timeout", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "timeout": timeout,
            "beforeLaunchPids": beforeLaunchPids.sorted()
        ])

        cleanupWrapperStalledLaunch(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: generation
        )

        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            return
        }
        stateMachine.send(.errorOccurred(message))
        syncStateWithStateMachine()
    }

    private func cleanupWrapperStalledLaunch(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        generation: UInt64
    ) {
        guard isCurrentTunnelLifecycle(generation),
              case .starting = stateMachine.currentState else {
            logStartupTrace("wrapper_stall_cleanup_skipped", fields: [
                "mode": mode.rawValue,
                "targetUDID": targetUDID ?? "nil",
                "generationCurrent": isCurrentTunnelLifecycle(generation),
                "state": "\(stateMachine.currentState)"
            ])
            return
        }

        let candidatePids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: targetUDID))
            .subtracting(beforeLaunchPids)
            .sorted()

        logStartupTrace("wrapper_stall_cleanup_begin", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "beforeLaunchPids": beforeLaunchPids.sorted(),
            "candidatePids": candidatePids
        ])

        let remainingPids = terminateLaunchScopedTunnelChildren(
            candidatePids,
            mode: mode,
            targetUDID: targetUDID
        )

        logStartupTrace("wrapper_stall_cleanup_complete", fields: [
            "mode": mode.rawValue,
            "targetUDID": targetUDID ?? "nil",
            "candidatePids": candidatePids,
            "remainingCandidates": remainingPids
        ])
    }

    private func terminateLaunchScopedTunnelChildren(
        _ candidatePids: [Int32],
        mode: TunnelMode,
        targetUDID: String?
    ) -> [Int32] {
        guard !candidatePids.isEmpty else {
            return []
        }

        for pid in candidatePids {
            _ = sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGTERM,
                mode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: false
            )
        }

#if DEBUG
        let gracefulTerminationDelay: useconds_t = debugSignalHandler == nil ? 500_000 : 1_000
#else
        let gracefulTerminationDelay: useconds_t = 500_000
#endif
        usleep(gracefulTerminationDelay)

        for pid in candidatePids where isProcessRunning(pid: pid) {
            _ = sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGKILL,
                mode: mode,
                targetUDID: targetUDID,
                allowMissingTargetUDID: false
            )
        }

#if DEBUG
        let verificationDelay: useconds_t = debugSignalHandler == nil ? 200_000 : 1_000
#else
        let verificationDelay: useconds_t = 200_000
#endif
        usleep(verificationDelay)

        return candidatePids.filter {
            isProcessRunning(pid: $0) &&
            isValidatedTunnelProcess(
                pid: $0,
                mode: mode,
                targetUDID: targetUDID
            )
        }
    }

    /// Attempt to start tunnel with specific mode
    private func attemptStart(mode: TunnelMode) async -> Bool {
        let launchCommand: String
        let udidArgument = targetTunnelUDID.map { " --udid \($0)" } ?? ""

        switch mode {
        case .usb:
            launchCommand = "\(python3Path) -m pymobiledevice3 lockdown start-tunnel\(udidArgument) > \(logFilePath) 2>&1 &"
        case .wifi:
            launchCommand = "\(python3Path) -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp\(udidArgument) > \(logFilePath) 2>&1 &"
        case .daemon:
            launchCommand = "\(python3Path) -m pymobiledevice3 remote tunneld > \(logFilePath) 2>&1 &"
        case .auto:
            return false // Should not reach here
        }
        let privilegedCommand = "\(launchCommand) echo $!"
        let launchTargetUDID = targetTunnelUDID
        let beforeLaunchPids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: launchTargetUDID))
        let generation = tunnelLifecycleGeneration
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = launchTargetUDID
        logStartupTrace("wrapper_launch_prepared", fields: [
            "mode": mode.rawValue,
            "targetUDID": launchTargetUDID ?? "nil",
            "beforeLaunchPids": beforeLaunchPids.sorted()
        ])

        // SECURITY: Validate the pmd3 launch command before adding the static
        // `$!` handoff suffix. The validator intentionally rejects `$`, so the
        // shell handoff wrapper remains hardcoded and is not user-influenced.
        switch PrivilegedCommandValidator.validate(command: launchCommand, pythonPath: python3Path) {
        case .success:
            Logger.info("Security validation passed for \(mode.rawValue) tunnel command", category: .security)
        case .failure(let error):
            Logger.error("SECURITY: Blocked privileged command - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }

        let script = """
        do shell script "\(privilegedCommand)" with administrator privileges
        """

        let wrapperTimeout = wrapperReturnTimeout(for: mode)
        let wrapperResult = await executePrivilegedWrapper(script: script, timeout: wrapperTimeout)

        switch wrapperResult {
        case .returned(let wrapperOutput, let wrapperReturnTime):
            let handedOffPid = parseHandedOffPid(from: wrapperOutput)
            logStartupTrace("wrapper_returned", fields: [
                "mode": mode.rawValue,
                "targetUDID": launchTargetUDID ?? "nil",
                "wrapperReturnTime": wrapperReturnTime,
                "wrapperStdout": wrapperOutput,
                "handedOffPid": handedOffPid as Any
            ])
            if let info = await waitForAuthoritativeStartup(
                mode: mode,
                targetUDID: launchTargetUDID,
                beforeLaunchPids: beforeLaunchPids,
                generation: generation,
                handedOffPid: handedOffPid
            ) {
                tunnelInfo = info
                return true
            }

            await checkLogForErrors(mode: mode)
            if lastError == nil {
                lastError = "Failed to acquire authoritative \(mode.rawValue) tunnel child and RSD readiness before timeout."
            }
            return false

        case .failed(let message):
            lastError = message
            statusMessage = message
            return false

        case .timedOut:
            finalizeWrapperReturnTimeout(
                mode: mode,
                targetUDID: launchTargetUDID,
                beforeLaunchPids: beforeLaunchPids,
                generation: generation,
                timeout: wrapperTimeout
            )
            return false
        }
    }

    private func executePrivilegedWrapper(script: String, timeout: TimeInterval) async -> PrivilegedWrapperExecutionResult {
#if DEBUG
        let debugRunner = debugPrivilegedWrapperRunner
#endif
        return await withCheckedContinuation { continuation in
            let state = PrivilegedWrapperContinuation(continuation: continuation)

            DispatchQueue.global().async {
#if DEBUG
                if let debugRunner {
                    state.resume(debugRunner(script))
                    return
                }
#endif
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    state.resume(.failed(message: "Failed to create AppleScript"))
                    return
                }

                let resultDescriptor = appleScript.executeAndReturnError(&error)
                let wrapperReturnTime = Date().timeIntervalSince1970

                if let error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    if !errorMessage.contains("cancel") {
                        state.resume(.failed(message: "Failed to start tunnel: \(errorMessage)"))
                    } else {
                        state.resume(.failed(message: "Administrator access required"))
                    }
                    return
                }

                state.resume(.returned(
                    output: resultDescriptor.stringValue ?? "",
                    returnTime: wrapperReturnTime
                ))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                state.resume(.timedOut)
            }
        }
    }

    /// Check log file for specific error messages
    private func checkLogForErrors(mode: TunnelMode) async {
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return
        }

        // pmd3 9.x has TWO wireless-tunnel paths and they have different OS
        // requirements:
        //
        //   (A) `remote start-tunnel -t wifi`  (Tunnel Mode = WiFi)
        //       Uses the `_remotepairing-manual-pairing._tcp` Bonjour flow and
        //       a `~/.pymobiledevice3/remote_<UDID>.plist` record. iOS 17 and
        //       18 advertise that service when wireless pairing is toggled,
        //       BUT iOS 26.x stops advertising it and only emits
        //       `_remotepairing._tcp` (paired) + `_remoted._tcp` (NCM). On
        //       those builds path (A) cannot complete.
        //
        //   (B) `remote tunneld`              (Tunnel Mode = Background Daemon)
        //       Uses the `_remoted._tcp` channel + Apple's `remoted`
        //       suspension. Works on iOS 26.x because it reuses the active
        //       lockdown trust record instead of a separate remote pair record.
        //
        // So: when WiFi mode fails, the most likely cause is iOS 26+. We tell
        // the user about the daemon fallback first, and only mention pair_wifi.py
        // for iOS 17/18 setups where it still works.
        let wifiPairingGuidance = """
        Wi-Fi tunnel could not start.

        On iOS 26 and later, switch the Tunnel Mode picker to "Background
        Daemon". That mode uses Apple's `_remoted` channel and reuses the
        existing pair record — no separate Wi-Fi pairing step required.

        On iOS 17 / 18 you can use Wi-Fi mode directly, but the iPhone has to
        be advertising `_remotepairing-manual-pairing._tcp` first:
          1. Unlock the iPhone and put it on the SAME Wi-Fi as this Mac.
          2. Settings → Privacy & Security → Developer Mode must be ON.
          3. Settings → Developer → toggle "Pair Wirelessly" / "Wireless
             Pairing" / "Allow Mac" OFF, then back ON.
          4. While that toggle is fresh (~30s window), in Terminal:
               sudo python3 \(scriptsDirectoryPath)/pair_wifi.py --timeout 30
          5. Confirm the pairing prompt on the iPhone, then retry Wi-Fi mode.
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
        guard canAcceptRsdInfo else {
            invalidateRsdInfo(reason: "Ignoring RSD parse outside active startup/running lifecycle")
            return
        }
        let mode = activeMode ?? stateMachine.currentContext.activeMode
        guard mode != nil else { return }

        do {
            // Give log file time to be written
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard canAcceptRsdInfo else {
                invalidateRsdInfo(reason: "Tunnel lifecycle changed before RSD parse completed")
                return
            }

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
                guard canAcceptRsdInfo else {
                    invalidateRsdInfo(reason: "Tunnel lifecycle changed before parsed RSD could be published")
                    return
                }
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
        guard canAcceptRsdInfo else {
            invalidateRsdInfo(reason: "Ignoring tunneld API RSD outside active startup/running lifecycle")
            return
        }
        guard let url = URL(string: tunneldAPIEndpoint) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard canAcceptRsdInfo else {
                invalidateRsdInfo(reason: "Tunnel lifecycle changed before tunneld API RSD could be published")
                return
            }
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
        guard canServeRsdInfo else {
            invalidateRsdInfo(reason: "RSD requested while tunnel state is \(stateMachine.currentState)")
            return nil
        }
        // First check per-device cache
        if let info = deviceTunnelInfo[deviceId], isUsableTunnelInfo(info) {
            return info
        }

        // Fall back to legacy single tunnel info
        if let tunnelInfo, isUsableTunnelInfo(tunnelInfo) {
            return tunnelInfo
        }

        invalidateRsdInfo(reason: "No usable live RSD exists for device \(deviceId)")
        return nil
    }

    /// Recover RSD info from the tunnel log when an existing lockdown tunnel was detected.
    private func recoverRsdInfoFromLog() -> TunnelInfo? {
        guard canRecoverRsdInfoFromLog else {
            return nil
        }
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

    /// Kill lifecycle-scoped pmd3 tunnel child processes safely using PID + command validation.
    /// Does NOT use global killall behavior or terminate non-tunnel pymobiledevice3 commands.
    ///
    /// Security Features:
    /// - Only terminates state-machine PIDs, lifecycle-discovered child PIDs, or exact mode/UDID matches
    /// - Verifies command line, owner UID, and tunnel mode before termination
    /// - Uses graceful SIGTERM, escalates to SIGKILL, then validates termination
    /// - Does NOT kill system services (e.g., usbmuxd)
    private func killTrackedTunnelProcesses() {
        let cleanupMode = stateMachine.currentContext.activeMode ?? activeMode ?? lastTunnelModeForCleanup
        let cleanupTargetUDID = lastTunnelTargetUDIDForCleanup ?? targetTunnelUDID
        let lifecycleCandidatePids = stateMachine.currentContext.activeProcessIds.union(trackedTunnelChildProcessIds)
        let candidatePids = cleanupCandidateProcessIds(mode: cleanupMode, targetUDID: cleanupTargetUDID)

        Logger.debug("[SECURITY] Terminating \(candidatePids.count) validated tunnel child process(es)", category: .security)

        guard !candidatePids.isEmpty else {
            trackedTunnelChildProcessIds = trackedTunnelChildProcessIds.filter {
                isProcessAliveAndNonZombie(pid: $0)
            }
            Logger.debug("[SECURITY] No validated tunnel child processes to terminate", category: .security)
            return
        }

        // First pass: Send SIGTERM for graceful shutdown
        for pid in candidatePids {
            let allowMissingTargetUDID = lifecycleCandidatePids.contains(pid)
            if sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGTERM,
                mode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
            ) {
                Logger.debug("[SECURITY] Sent SIGTERM to validated tunnel PID \(pid)", category: .security)
            }
        }

        // Brief wait for graceful termination
#if DEBUG
        let gracefulTerminationDelay: useconds_t = debugSignalHandler == nil ? 500_000 : 1_000
#else
        let gracefulTerminationDelay: useconds_t = 500_000
#endif
        usleep(gracefulTerminationDelay)

        // Second pass: Force kill any remaining validated tunnel children.
        for pid in candidatePids {
            let allowMissingTargetUDID = lifecycleCandidatePids.contains(pid)
            if isProcessRunning(pid: pid),
               sendSignalToValidatedTunnelProcess(
                pid: pid,
                signal: SIGKILL,
                mode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: allowMissingTargetUDID
               ) {
                Logger.debug("[SECURITY] Sent SIGKILL to validated tunnel PID \(pid)", category: .security)
            }
        }
#if DEBUG
        let verificationDelay: useconds_t = debugSignalHandler == nil ? 200_000 : 1_000
#else
        let verificationDelay: useconds_t = 200_000
#endif
        usleep(verificationDelay)

        let remainingPids = candidatePids.filter {
            isProcessRunning(pid: $0) &&
            isValidatedTunnelProcess(
                pid: $0,
                cleanupMode: cleanupMode,
                targetUDID: cleanupTargetUDID,
                allowMissingTargetUDID: lifecycleCandidatePids.contains($0)
            )
        }

        if remainingPids.isEmpty {
            trackedTunnelChildProcessIds.subtract(candidatePids)
        } else {
            trackedTunnelChildProcessIds.formUnion(remainingPids)
            Logger.error("[SECURITY] Tunnel child cleanup verification failed for PID(s): \(remainingPids.map(String.init).joined(separator: ", "))", category: .security)
        }

        // Process IDs are cleared by state machine when it transitions to idle
        Logger.debug("[SECURITY] Tunnel child process cleanup complete", category: .security)
    }

    /// Check if process is owned by current user
    /// Returns false if process doesn't exist or ownership cannot be verified
    private func isOwnedProcess(pid: Int32) -> Bool {
        processUID(pid: pid) == getuid()
    }

    /// Check if a process is still running
    private func isProcessRunning(pid: Int32) -> Bool {
        isProcessAliveAndNonZombie(pid: pid)
    }

    func isTunnelProcessAlive(pid: Int32) -> Bool {
        isProcessAliveAndNonZombie(pid: pid)
    }

    private func isProcessAliveAndNonZombie(pid: Int32) -> Bool {
#if DEBUG
        if let overrideIndex = debugProcessStateOverrides.index(forKey: pid) {
            let override = debugProcessStateOverrides[overrideIndex].value
            guard let state = override else { return false }
            return !Self.isZombieProcessState(state)
        }
#endif
        guard processExistsForValidation(pid: pid) else {
            return false
        }

        guard let state = processState(pid: pid) else {
            return false
        }

        return !Self.isZombieProcessState(state)
    }

    private func processExistsForValidation(pid: Int32) -> Bool {
#if DEBUG
        if let override = debugKillZeroResultOverrides[pid] {
            switch override {
            case .allowed, .permissionDenied:
                return true
            case .missing:
                return false
            }
        }
#endif
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func processState(pid: Int32) -> String? {
#if DEBUG
        if let overrideIndex = debugProcessStateOverrides.index(forKey: pid) {
            return debugProcessStateOverrides[overrideIndex].value
        }
#endif
        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "stat="]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice

        do {
            try ps.run()
            ps.waitUntilExit()
        } catch {
            return nil
        }

        guard ps.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let state = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.isEmpty ? nil : state
    }

    nonisolated private static func isZombieProcessState(_ state: String) -> Bool {
        state.uppercased().contains("Z")
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
        let effectiveTimeout = max(0.1, timeout ?? AppSettings.shared.commandTimeout)

        return try await withCheckedThrowingContinuation { continuation in
            let execution = TunneldCommandExecutionState(
                command: command,
                arguments: arguments,
                timeout: effectiveTimeout,
                maxOutputSize: TunneldManager.maxOutputSize,
                continuation: continuation
            )

            execution.pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                if !execution.appendOutput(data) {
                    Logger.error("[SECURITY] Subprocess output exceeded limit (max: \(execution.maxOutputSize) bytes)", category: .security)
                    execution.terminateWithGracePeriod()
                }
            }

            execution.process.terminationHandler = { terminatedProcess in
                execution.finishAfterTermination(terminatedProcess)
            }

            let timeoutItem = execution.makeTimeoutWorkItem()
            execution.installTimeout(timeoutItem)

            do {
                try execution.process.run()
            } catch {
                execution.finish(.failure(error))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + effectiveTimeout, execute: timeoutItem)
        }
    }

    /// Returns the maximum output size limit for testing purposes
    nonisolated static var maxOutputSizeLimit: Int {
        return maxOutputSize
    }
}

enum PrivilegedWrapperExecutionResult: Sendable {
    case returned(output: String, returnTime: TimeInterval)
    case failed(message: String)
    case timedOut
}

private final class PrivilegedWrapperContinuation: @unchecked Sendable {
    private let continuation: CheckedContinuation<PrivilegedWrapperExecutionResult, Never>
    private let lock = NSLock()
    private var hasResumed = false

    init(continuation: CheckedContinuation<PrivilegedWrapperExecutionResult, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: PrivilegedWrapperExecutionResult) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()

        continuation.resume(returning: result)
    }
}
private final class TunneldCommandExecutionState: @unchecked Sendable {
    let process = Process()
    let pipe = Pipe()
    let maxOutputSize: Int

    private let timeout: TimeInterval
    private let continuation: CheckedContinuation<String, Error>
    private let lock = NSLock()
    private var output = Data()
    private var hasFinished = false
    private var outputExceededLimit = false
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        command: String,
        arguments: [String],
        timeout: TimeInterval,
        maxOutputSize: Int,
        continuation: CheckedContinuation<String, Error>
    ) {
        self.timeout = timeout
        self.maxOutputSize = maxOutputSize
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessEnvironment.configured()
    }

    func appendOutput(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }

        lock.lock()
        defer { lock.unlock() }

        guard output.count + data.count <= maxOutputSize else {
            let remainingCapacity = max(0, maxOutputSize - output.count)
            if remainingCapacity > 0 {
                output.append(data.prefix(remainingCapacity))
            }
            outputExceededLimit = true
            return false
        }

        output.append(data)
        return true
    }

    func terminateWithGracePeriod() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.forceKillIfStillRunning()
        }
    }

    func makeTimeoutWorkItem() -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            guard let self else { return }
            terminateWithGracePeriod()
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Command timed out after \(timeout) seconds"]
            )))
        }
    }

    func installTimeout(_ timeoutWorkItem: DispatchWorkItem) {
        lock.lock()
        self.timeoutWorkItem = timeoutWorkItem
        lock.unlock()
    }

    func finishAfterTermination(_ terminatedProcess: Process) {
        guard !isFinished else { return }

        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        _ = appendOutput(remainingData)
        let snapshot = outputSnapshot()

        if snapshot.exceededLimit {
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Output exceeded safety limit (\(maxOutputSize) bytes)"]
            )))
            return
        }

        let text = String(data: snapshot.data, encoding: .utf8) ?? ""
        guard terminatedProcess.terminationStatus == 0 else {
            let diagnostic = boundedDiagnostic(from: snapshot.data)
            finish(.failure(NSError(
                domain: "TunneldManager",
                code: Int(terminatedProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Command exited with status \(terminatedProcess.terminationStatus): \(diagnostic)"]
            )))
            return
        }

        finish(.success(text))
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        let pendingTimeout = timeoutWorkItem
        timeoutWorkItem = nil
        lock.unlock()

        pendingTimeout?.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForReading.close()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasFinished
    }

    private func forceKillIfStillRunning() {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func outputSnapshot() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (output, outputExceededLimit)
    }

    private func boundedDiagnostic(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 4000 {
            return trimmed
        }
        return String(trimmed.suffix(4000))
    }
}
#if DEBUG
@MainActor
extension TunneldManager {
    var testTunnelLifecycleGeneration: UInt64 {
        tunnelLifecycleGeneration
    }

    var testHasScheduledRecovery: Bool {
        recoveryTask != nil
    }

    var testHasScheduledRestart: Bool {
        restartTask != nil
    }

    func testResetTunnelLifecycleForTests() {
        recoveryTask?.cancel()
        recoveryTask = nil
        restartTask?.cancel()
        restartTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        healthMonitor.stopMonitoring()
        cleanupTunnelProcessResources(terminateProcess: true)
        stateMachine.testModeEnabled = true
        stateMachine.reset()
        syncStateWithStateMachine()
        tunnelStartInFlight = false
        tunnelLifecycleGeneration &+= 1
        trackedTunnelChildProcessIds.removeAll()
        lastTunnelModeForCleanup = nil
        lastTunnelTargetUDIDForCleanup = nil
        targetTunnelUDID = nil
        targetTunnelConnectionType = nil
        targetTunnelIOSMajorVersion = nil
        debugProcessCommandOverrides.removeAll()
        debugProcessUIDOverrides.removeAll()
        debugProcessStateOverrides.removeAll()
        debugKillZeroResultOverrides.removeAll()
        debugLiveProcessIdsOverrides.removeAll()
        debugLiveProcessIdsSequenceOverrides.removeAll()
        debugStartupRsdInfoSequence.removeAll()
        debugUsesStartupRsdInfoSequence = false
        debugStartupTimeoutOverride = nil
        debugStartupPollIntervalOverride = nil
        debugWrapperReturnTimeoutOverride = nil
        debugPrivilegedWrapperRunner = nil
        debugSignalHandler = nil
        preferredMode = .auto
    }

    @discardableResult
    func testSendTunnelEvent(_ event: TunnelEvent) -> TransitionResult {
        stateMachine.testModeEnabled = true
        let result = stateMachine.send(event)
        syncStateWithStateMachine()
        return result
    }

    func testScheduleRecovery(after delay: TimeInterval) {
        scheduleRecovery(after: delay)
    }

    var testTrackedTunnelChildProcessIds: Set<Int32> {
        trackedTunnelChildProcessIds
    }

    func testSetTrackedTunnelChildren(_ pids: Set<Int32>, mode: TunnelMode?, targetUDID: String?) {
        trackedTunnelChildProcessIds = pids
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = targetUDID
    }

    func testSetProcessOverride(pid: Int32, command: String, uid: uid_t = getuid(), state: String? = "S") {
        debugProcessCommandOverrides[pid] = command
        debugProcessUIDOverrides[pid] = uid
        debugProcessStateOverrides.updateValue(state, forKey: pid)
    }

    func testSetProcessState(pid: Int32, state: String?) {
        debugProcessStateOverrides.updateValue(state, forKey: pid)
    }

    func testSetKillZeroResult(pid: Int32, result: TestKillZeroResult) {
        debugKillZeroResultOverrides[pid] = result
    }

    func testSetLiveProcessIds(_ pids: [Int32], matching pattern: String) {
        debugLiveProcessIdsOverrides[pattern] = pids
    }
    func testSetLiveProcessIdSequence(_ sequence: [[Int32]], matching pattern: String) {
        debugLiveProcessIdsSequenceOverrides[pattern] = sequence
    }

    func testSetStartupRsdInfoSequence(_ sequence: [TunnelInfo?]) {
        debugStartupRsdInfoSequence = sequence
        debugUsesStartupRsdInfoSequence = true
    }

    func testSetStartupTiming(
        timeout: TimeInterval?,
        pollInterval: TimeInterval?
    ) {
        debugStartupTimeoutOverride = timeout
        debugStartupPollIntervalOverride = pollInterval
    }

    func testSetWrapperReturnTimeout(_ timeout: TimeInterval?) {
        debugWrapperReturnTimeoutOverride = timeout
    }

    func testSetPrivilegedWrapperRunner(_ runner: (@Sendable (String) -> PrivilegedWrapperExecutionResult)?) {
        debugPrivilegedWrapperRunner = runner
    }

    func testSetTargetTunnelUDID(_ udid: String?) {
        targetTunnelUDID = udid
    }

    func testAttemptStart(mode: TunnelMode) async -> Bool {
        await attemptStart(mode: mode)
    }

    func testFinalizeWrapperReturnTimeout(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        timeout: TimeInterval
    ) {
        finalizeWrapperReturnTimeout(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: tunnelLifecycleGeneration,
            timeout: timeout
        )
    }

    var testActiveTunnelProcessIds: Set<Int32> {
        stateMachine.currentContext.activeProcessIds
    }

    func testWaitForAuthoritativeStartup(
        mode: TunnelMode,
        targetUDID: String?,
        beforeLaunchPids: Set<Int32>,
        handedOffPid: Int32? = nil
    ) async -> TunnelInfo? {
        await waitForAuthoritativeStartup(
            mode: mode,
            targetUDID: targetUDID,
            beforeLaunchPids: beforeLaunchPids,
            generation: tunnelLifecycleGeneration,
            handedOffPid: handedOffPid
        )
    }

    func testSetSignalHandler(_ handler: (@MainActor (Int32, Int32) -> Bool)?) {
        debugSignalHandler = handler
    }

    func testCleanupCandidateProcessIds(mode: TunnelMode?, targetUDID: String?) -> [Int32] {
        cleanupCandidateProcessIds(mode: mode, targetUDID: targetUDID)
    }

    func testRecordLaunchedTunnelChildren(mode: TunnelMode, targetUDID: String?, beforeLaunchPids: Set<Int32>) {
        recordLaunchedTunnelChildren(mode: mode, targetUDID: targetUDID, beforeLaunchPids: beforeLaunchPids)
    }

    func testRunTrackedTunnelCleanup() {
        killTrackedTunnelProcesses()
    }

    nonisolated static func testIsZombieProcessState(_ state: String) -> Bool {
        isZombieProcessState(state)
    }

    nonisolated static func testIsSanctionedTunnelChildCommand(
        _ command: String,
        mode: TunnelMode,
        targetUDID: String?,
        requireTargetUDID: Bool = true
    ) -> Bool {
        isSanctionedTunnelChildCommand(
            command,
            mode: mode,
            targetUDID: targetUDID,
            requireTargetUDID: requireTargetUDID
        )
    }
}
#endif

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
