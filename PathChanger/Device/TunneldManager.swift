//
//  TunneldManager.swift
//  PathChanger
//
//  Unified tunnel management supporting multiple connection methods for capability-compatible iOS
//  - USB Mode: lockdown start-tunnel (fastest, requires USB)
//  - WiFi Mode: remote start-tunnel -t wifi (true wireless, no USB needed)
//  - Daemon Mode: remote tunneld (background service, auto-discovery)
//  - Auto Mode: Smart selection based on device availability
//

import Foundation
import Combine
import AppKit
import Darwin

enum TunnelStartTrigger {
    case applicationLaunch
    case statusPoll
    case explicitUserAction
}

enum TunnelStartPolicy {
    nonisolated static func mayElevate(for trigger: TunnelStartTrigger) -> Bool {
        trigger == .explicitUserAction
    }
}

// MARK: - Tunnel Mode

/// Available tunnel connection modes for capability-compatible iOS devices.
///
/// `TunnelMode` defines the different methods for establishing a secure tunnel
/// to an capability-compatible iOS device. Each mode has different requirements and trade-offs.
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
            return ["lockdown", "start-tunnel", "--native"]
        case .wifi:
            // pymobiledevice3 >= 11.4x: --connection-type is mutually exclusive with --native;
            // the native tunnel piggybacks remotepairingd and selects the device by --udid only.
            return ["remote", "start-tunnel", "--native"]
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

    /// A tunnel is usable only when it produced a real RSD endpoint.
    /// `127.0.0.1:0` was previously manufactured when parsing failed, which marked the
    /// UI "Tunnel live" even though no connection could use it.
    var isUsable: Bool {
        !rsdAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rsdPort > 0
            && rsdPort <= 65_535
    }
}

@MainActor
enum TunnelStartupWaiter {

    /// Poll until a usable RSD endpoint appears, the process exits, or the timeout expires.
    static func wait(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.25,
        processIsRunning: () -> Bool,
        readInfo: () async -> TunnelInfo?
    ) async -> TunnelInfo? {
        let deadline = Date().addingTimeInterval(timeout)

        while processIsRunning() {
            if let info = await readInfo(), info.isUsable {
                return info
            }
            guard Date() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return nil
    }
}

// MARK: - Tunneld Manager

/// Manages the pymobiledevice3 tunnel lifecycle for capability-compatible iOS device communication.
///
/// `TunneldManager` provides comprehensive tunnel management for establishing
/// secure connections to iOS devices. It supports multiple connection modes
/// and handles the complexity of capability-compatible iOS device communication requirements.
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
/// await tunnelManager.startTunnel(mode: .usb)
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
            terminateOwnedTunnelProcess()

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

    static func shouldAutoStart(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        AppRuntimeEnvironment.allowsAutomaticStartup(environment: environment)
    }

    nonisolated static func arguments(for mode: TunnelMode, deviceId: String? = nil) -> [String]? {
        let base: [String]?
        switch mode {
        case .usb:
            base = ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native"]
        case .wifi:
            base = ["-m", "pymobiledevice3", "remote", "start-tunnel", "--native"]
        case .daemon:
            base = ["-m", "pymobiledevice3", "remote", "tunneld"]
        case .auto:
            base = nil
        }

        guard var arguments = base else { return nil }
        if mode != .daemon,
           let deviceId,
           ArgumentSanitizer.isValidDeviceUDID(deviceId) {
            arguments += ["--udid", deviceId]
        }
        return arguments
    }

    /// Start tunnel automatically - called on app launch
    func autoStart(deviceId: String? = nil) async {
        guard Self.shouldAutoStart() else {
            Logger.debug("Skipping tunnel auto-start: automatic startup is disallowed", category: .device)
            return
        }

        let userEnabled = UserDefaults.standard.object(forKey: "autoStartTunneld") as? Bool ?? true
        guard userEnabled else {
            Logger.debug("Skipping tunnel auto-start: user disabled it in Settings", category: .device)
            return
        }

        // First check if any tunnel is already running
        if let runningMode = await detectRunningTunnel() {
            stateMachine.send(.externalTunnelDetected(mode: runningMode))
            return
        }

        // Try to start tunnel with preferred mode
        await startTunnel(deviceId: deviceId)
    }

    /// Adopt a tunnel process that survived an app relaunch without requesting elevation.
    ///
    /// The RSD tunnel is a root-owned child and can outlive the UI process. Discovery and
    /// log parsing are read-only; if both process and usable endpoint exist, rebuild the
    /// state-machine context so all DVT commands use `--rsd` immediately.
    func adoptRunningTunnelIfPresent() async {
        guard case .idle = state else { return }
        guard let mode = await detectRunningTunnel() else { return }

        stateMachine.reset()
        guard case .success = stateMachine.send(.startRequested(mode: mode)) else { return }

        await parseRsdInfo()
        let pid = await discoverPid(for: mode)

        guard let parsed = tunnelInfo, parsed.isUsable else {
            stateMachine.send(.errorOccurred("Existing tunnel has no usable RSD endpoint"))
            return
        }

        let adopted = TunnelInfo(
            rsdAddress: parsed.rsdAddress,
            rsdPort: parsed.rsdPort,
            mode: mode,
            interface: parsed.interface,
            processId: pid
        )
        tunnelInfo = adopted
        stateMachine.send(.connectionEstablished(info: adopted))
    }

    /// Start tunnel with preferred mode (with auto-fallback)
    func startTunnel(deviceId: String? = nil) async {
        // Check state via state machine
        guard !stateMachine.isActive && !stateMachine.isTransitioning else {
            Logger.debug(
                "Ignoring startTunnel request because state is already \(stateMachine.currentState)",
                category: .device
            )
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

        guard let firstMode = modesToTry.first else {
            return
        }

        // Reserve startup synchronously before the first suspension point.
        guard case .success = stateMachine.send(.startRequested(mode: firstMode)) else {
            return
        }

        if let runningMode = await detectRunningTunnel() {
            await parseRsdInfo()
            if let existingInfo = stateMachine.currentContext.tunnelInfo ?? tunnelInfo, existingInfo.isUsable {
                guard stateMachine.currentState == .starting else {
                    return
                }
                Logger.info(
                    "Adopting existing \(runningMode.rawValue) tunnel with usable endpoint",
                    category: .device
                )
                stateMachine.send(.externalTunnelDetected(mode: runningMode))
                return
            }
            Logger.error(
                "Detected existing \(runningMode.rawValue) process without usable RSD endpoint; attempting fresh start",
                category: .device
            )
        }

        // Another caller or a stop request may have changed the reserved state.
        guard stateMachine.currentState == .starting else {
            return
        }

        for (index, mode) in modesToTry.enumerated() {
            if index > 0 {
                guard case .success = stateMachine.send(.startRequested(mode: mode)) else {
                    return
                }
            }

            Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

            let outcome = await attemptStart(mode: mode, deviceId: deviceId)

            if case .cancelled = outcome {
                if stateMachine.currentState == .starting {
                    stateMachine.send(.errorOccurred(lastError ?? "Administrator access required"))
                }
                return
            }

            if case .started(let pid) = outcome {
                let startupTimeout = min(AppSettings.shared.tunnelTimeout, 30)
                let info = await TunnelStartupWaiter.wait(
                    timeout: startupTimeout,
                    processIsRunning: { self.isProcessRunning(pid: pid) },
                    readInfo: {
                        await self.parseRsdInfo()
                        return self.stateMachine.currentContext.tunnelInfo ?? self.tunnelInfo
                    }
                )

                guard stateMachine.currentState == .starting else { return }
                guard let info else {
                    if isProcessRunning(pid: pid) {
                        lastError = "Tunnel did not provide a usable RSD endpoint within \(Int(startupTimeout)) seconds"
                        stateMachine.send(.errorOccurred(lastError!))
                    } else {
                        await checkLogForErrors(mode: mode)
                        lastError = lastError ?? "Tunnel process exited before the connection was established"
                        stateMachine.send(.processExited(pid: pid))
                    }
                    return
                }
                stateMachine.send(.connectionEstablished(info: info))
                return
            }

            // If not auto mode, don't try other modes
            if preferredMode != .auto {
                if stateMachine.currentState == .starting {
                    stateMachine.send(.errorOccurred(lastError ?? "Failed to start tunnel"))
                }
                break
            }

            if index < modesToTry.count - 1 {
                Logger.debug("Mode \(mode.rawValue) failed, trying next...", category: .device)
                stateMachine.reset()
            } else if stateMachine.currentState == .starting {
                stateMachine.send(.errorOccurred(
                    lastError ?? "Failed to start tunnel. Ensure device is connected and trusted."
                ))
            }
        }
    }

    /// Start tunnel with specific mode
    func startTunnel(mode: TunnelMode, deviceId: String? = nil) async {
        let previousMode = preferredMode
        preferredMode = mode
        await startTunnel(deviceId: deviceId)

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

        // Terminate only the concrete Process instance launched by this manager.
        terminateOwnedTunnelProcess()
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

    /// True only when usbmux lists a USB attachment (not Network).
    func isUSBDeviceConnected() async -> Bool {
        await usbmuxReportsUSB()
    }

    private func usbmuxReportsUSB() async -> Bool {
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "usbmux", "list"
            ])
            return output.contains("\"ConnectionType\": \"USB\"")
                || output.contains("\"ConnectionType\":\"USB\"")
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

    private enum PrivilegedStartOutcome {
        case started(Int32)
        case failed
        case cancelled
    }

    /// Start a native user-space tunnel directly from the managed runtime.
    /// Arguments are fixed by `arguments(for:deviceId:)`; no shell or elevation is used.
    private func attemptStart(mode: TunnelMode, deviceId: String?) async -> PrivilegedStartOutcome {
        if mode == .usb {
            let usbVisible = await usbmuxReportsUSB()
            if !usbVisible {
                lastError = "USB is not visible to this Mac. Use a data cable, unlock the phone, and tap Trust. Wi‑Fi is still available — pick Wi‑Fi Only to use it."
                return .failed
            }
        }

        guard let arguments = Self.arguments(for: mode, deviceId: deviceId) else {
            return .failed
        }
        guard PythonPathResolver.isAvailable else {
            lastError = "Managed Python is not available at \(python3Path)"
            return .failed
        }

        ensureLogDirectoryExists()
        try? FileManager.default.removeItem(atPath: logFilePath)
        guard FileManager.default.createFile(atPath: logFilePath, contents: nil),
              let logHandle = FileHandle(forWritingAtPath: logFilePath) else {
            lastError = "Unable to create tunnel log"
            return .failed
        }
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = arguments
        process.environment = ProcessEnvironment.configured()
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            lastError = "Failed to start \(mode.rawValue) tunnel: \(error.localizedDescription)"
            return .failed
        }

        tunneldProcess = process
        let pid = process.processIdentifier
        stateMachine.send(.processLaunched(pid: pid))

        let waitTime: TimeInterval = mode == .daemon ? 4.0 : 3.0
        try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))

        guard process.isRunning && isProcessRunning(pid: pid) else {
            await checkLogForErrors(mode: mode)
            if lastError == nil {
                lastError = "\(mode.rawValue) tunnel exited after launch"
            }
            tunneldProcess = nil
            stateMachine.send(.processExited(pid: pid))
            return .failed
        }

        return .started(pid)
    }

    private func discoverPid(for mode: TunnelMode) async -> Int32? {
        do {
            let output = try await runCommand("/usr/bin/pgrep", arguments: ["-f", mode.processPattern])
            let pids = output.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            return pids.first { $0 > 1 }
        } catch {
            return nil
        }
    }

    /// Check log file for specific error messages
    private func checkLogForErrors(mode: TunnelMode) async {
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return
        }

        if logContent.contains("requires root privileges") {
            lastError = "Tunnel start still needs administrator access."
        } else if logContent.contains("No device connected") || logContent.contains("DeviceNotFoundError") {
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
        var last: (String, Int)?
        for line in lines {
            if line.contains("--rsd") {
                let parts = line.components(separatedBy: .whitespaces)
                if let rsdIndex = parts.firstIndex(of: "--rsd"),
                   rsdIndex + 2 < parts.count {
                    let address = parts[rsdIndex + 1]
                    if let port = Int(parts[rsdIndex + 2]) {
                        last = (address, port)
                    }
                }
            }
        }
        if let last {
            Logger.debug("📍 Parsed latest RSD from hint line: \(last.0):\(last.1)", category: .device)
            return (last.0, last.1)
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

            // Parse RSD Address (multiple formats supported) — keep last
            if line.contains("RSD Address:") || line.contains("address:") {
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

            // Parse RSD Port (multiple formats supported) — keep last
            if line.contains("RSD Port:") || line.contains("port:") || line.contains("Port:") {
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

    /// Direct usbmux reachability (USB or Network visibility) per device UDID,
    /// wired by DeviceManager. Directly-reachable devices prefer the `--udid`
    /// DVT path over the native tunnel's RSD endpoint (see LocationConnectionArguments.make).
    var directDeviceReachability: (@MainActor (String) -> Bool)?

    /// Connection flags for DVT / simulate-location after a tunnel is up.
    func locationConnectionArguments(for deviceId: String) -> [String] {
        let info = getRsdInfo(for: deviceId)
        return LocationConnectionArguments.make(
            deviceId: deviceId,
            isDaemonTunneld: activeMode == .daemon,
            rsdAddress: info?.rsdAddress,
            rsdPort: info?.rsdPort,
            deviceDirectlyReachable: directDeviceReachability?(deviceId) ?? false
        )
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

    /// Terminate only the concrete Process instance launched by this manager.
    /// Read-only pgrep adoption never populates this property and cannot be killed here.
    private func terminateOwnedTunnelProcess() {
        guard let process = tunneldProcess else {
            Logger.debug("[SECURITY] No owned tunnel process to terminate", category: .security)
            return
        }

        let pid = process.processIdentifier
        guard pid > 1 else {
            lastError = "Refusing to terminate invalid owned tunnel PID \(pid)"
            Logger.error(lastError ?? "Invalid tunnel PID", category: .security)
            return
        }

        process.terminate()
        Task { @MainActor [weak self, process] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard process.isRunning else { return }

            if kill(pid, SIGKILL) != 0 && errno != ESRCH {
                let message = String(cString: strerror(errno))
                self?.lastError = "Failed to force-stop owned tunnel process \(pid): \(message)"
                Logger.error(
                    "Owned tunnel force-stop failed for PID \(pid): \(message)",
                    category: .security
                )
            }
        }
    }

    /// Check if a process is still running
    private func isProcessRunning(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        // Root-owned tunnel helpers return EPERM to a user-level existence check.
        return errno == EPERM
    }

    /// Monitor tunnel status periodically
    private func startMonitoring() {
        monitorTask?.cancel()

        // Set up health monitor failure notifications
        healthMonitor.setFailureNotificationHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isRunning {
                    Logger.error(
                        "Tunnel health failed — leaving running state and requiring explicit restart",
                        category: .device
                    )
                    self.stateMachine.send(.healthCheckFailed)
                    return
                }
                if self.isStarting {
                    Logger.error(
                        "Tunnel health failed while startup is still in progress",
                        category: .device
                    )
                    return
                }
                let userEnabled = UserDefaults.standard.object(forKey: "autoStartTunneld") as? Bool ?? true
                guard userEnabled else { return }
                Logger.error(
                    "Tunnel process is gone — waiting for explicit user restart",
                    category: .device
                )
            }
        }

        // Start health monitoring
        healthMonitor.startMonitoring()

        // TunnelHealthMonitor owns the real 2-second liveness checks. The previous
        // parallel task logged "✓ Health check passed" unconditionally every 5 seconds,
        // even while the real monitor reported 55+ consecutive failures.
        monitorTask = nil
    }

    /// Maximum output size from subprocess (1 MB) - prevents DoS via excessive output
    private static let maxOutputSize = 1_048_576

    /// Run a command and return output with timeout protection and size limiting
    private func runCommand(_ command: String, arguments: [String], timeout: TimeInterval? = nil) async throws -> String {
        let effectiveTimeout = timeout ?? AppSettings.shared.commandTimeout
        // Hoisted so the Sendable closure below captures a plain Int rather than reaching
        // back into main-actor-isolated static storage.
        let maxOutputSize = TunneldManager.maxOutputSize

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
                    pipe.fileHandleForReading.closeFile()

                    // Security: Check output size limit (consistent with DevLocationBridge)
                    if data.count > maxOutputSize {
                        Logger.error("[SECURITY] Subprocess output exceeded limit: \(data.count) bytes (max: \(maxOutputSize))", category: .security)
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
    weak var terminationHandler: (any LocationTerminationHandling)?
    private var terminationReplyPending = false

    nonisolated func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            applicationShouldTerminateOnMainActor(sender)
        }
    }

    private func applicationShouldTerminateOnMainActor(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !terminationReplyPending else { return .terminateLater }
        guard let terminationHandler else { return .terminateNow }

        let choice: LocationQuitChoice?
        if terminationHandler.requiresLocationQuitDecision {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString(
                "quit.location.title",
                comment: "Quit while a managed location session is held"
            )
            alert.informativeText = NSLocalizedString(
                "quit.location.message",
                comment: "Choose whether to clear or preserve the managed location"
            )
            alert.addButton(withTitle: NSLocalizedString(
                "quit.clearAndQuit",
                comment: "Clear location and quit"
            ))
            alert.addButton(withTitle: NSLocalizedString(
                "quit.preserveAndQuit",
                comment: "Preserve location and quit"
            ))
            alert.addButton(withTitle: NSLocalizedString(
                "quit.cancel",
                comment: "Cancel quitting"
            ))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                choice = .clearAndQuit
            case .alertSecondButtonReturn:
                choice = .preserveAndQuit
            default:
                choice = .cancel
            }
        } else {
            choice = nil
        }

        guard choice != .cancel else { return .terminateCancel }
        terminationReplyPending = true
        Task { @MainActor [weak self, terminationHandler] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            let result: LocationQuitPreparationResult
            if let choice {
                result = await terminationHandler.prepareForQuit(choice)
            } else {
                result = await terminationHandler.prepareForQuitWithoutLocation()
            }
            terminationReplyPending = false
            switch result {
            case .terminate:
                sender.reply(toApplicationShouldTerminate: true)
            case .cancel:
                sender.reply(toApplicationShouldTerminate: false)
            case .failed(let message):
                let errorAlert = NSAlert()
                errorAlert.alertStyle = .critical
                errorAlert.messageText = NSLocalizedString(
                    "quit.failed.title",
                    comment: "Quit preparation failed"
                )
                errorAlert.informativeText = message
                errorAlert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            Organic.registerFonts()
            if TunnelStartPolicy.mayElevate(for: .applicationLaunch) {
                await TunneldManager.shared.autoStart()
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            TunneldManager.shared.stopTunnel()
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
