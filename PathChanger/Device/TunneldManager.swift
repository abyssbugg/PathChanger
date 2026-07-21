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
    let stateMachine = TunnelStateMachine()

    /// State derived from state machine
    @Published var state: TunnelState = .idle

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
    var isLoadingPreferredModeFromDefaults: Bool = false

    /// Active tunnel mode (actual running mode)
    @Published var activeMode: TunnelMode?

    /// Presentation-only active transport mode for UI surfaces.
    ///
    /// Runtime ownership still lives in the state machine and active process
    /// tracking. This helper only prevents stale `.usb` presentation from
    /// overriding a running explicit wireless session while the tunnel remains
    /// healthy.
    var presentationActiveMode: TunnelMode? {
        guard isRunning else { return nil }
        if preferredMode == .wifi || preferredMode == .daemon {
            return preferredMode
        }
        if let infoMode = tunnelInfo?.mode,
           infoMode != .auto,
           infoMode != activeMode {
            return infoMode
        }
        return activeMode ?? tunnelInfo?.mode
    }

    /// RSD connection info for device communication (legacy - first device)
    @Published var tunnelInfo: TunnelInfo?

    /// RSD connection info per device UDID (queried from tunneld HTTP API)
    @Published var deviceTunnelInfo: [String: TunnelInfo] = [:]

    /// Tunneld HTTP API endpoint (when using remote tunneld)
    var tunneldAPIEndpoint: String { AppConstants.Tunnel.tunneldAPIEndpoint }

    // MARK: Private Properties
    var tunneldProcess: Process?
    var outputPipe: Pipe?
    var errorPipe: Pipe?
    var monitorTask: Task<Void, Never>?
    var python3Path: String { PythonPathResolver.path }

    /// Health monitor for tunnel connectivity
    let healthMonitor = TunnelHealthMonitor()

    /// Cancellable for state machine observation
    var stateMachineCancellable: AnyCancellable?

    /// Serial queue for tunnel operations
    let tunnelQueue = DispatchQueue(label: "com.pathchanger.tunnelmanager", qos: .userInitiated)
    /// UDID selected for the next tunnel start, populated from usbmux discovery.
    var targetTunnelUDID: String?
    var targetTunnelConnectionType: ConnectionType?
    var targetTunnelIOSMajorVersion: Int?
    var tunnelStartInFlight = false
    var tunnelLifecycleGeneration: UInt64 = 0
    var recoveryTask: Task<Void, Never>?
    var restartTask: Task<Void, Never>?
    var trackedTunnelChildProcessIds: Set<Int32> = []
    var lastTunnelModeForCleanup: TunnelMode?
    var lastTunnelTargetUDIDForCleanup: String?
#if DEBUG
    enum TestKillZeroResult {
        case allowed
        case permissionDenied
        case missing
    }
    var debugProcessCommandOverrides: [Int32: String] = [:]
    var debugProcessUIDOverrides: [Int32: uid_t] = [:]
    var debugProcessStateOverrides: [Int32: String?] = [:]
    var debugKillZeroResultOverrides: [Int32: TestKillZeroResult] = [:]
    var debugLiveProcessIdsOverrides: [String: [Int32]] = [:]
    var debugLiveProcessIdsSequenceOverrides: [String: [[Int32]]] = [:]
    var debugStartupRsdInfoSequence: [TunnelInfo?] = []
    var debugUsesStartupRsdInfoSequence = false
    var debugStartupTimeoutOverride: TimeInterval?
    var debugStartupPollIntervalOverride: TimeInterval?
    var debugWrapperReturnTimeoutOverride: TimeInterval?
    var debugRecoveredRsdInfoFromLogOverride: TunnelInfo?
    var debugRecoveredRsdInfoFromLogOverrideEnabled = false
    var debugPrivilegedWrapperRunner: (@Sendable (String) -> PrivilegedWrapperExecutionResult)?
    var debugSignalHandler: (@MainActor (Int32, Int32) -> Bool)?
#endif

    /// Active process IDs to prevent duplicates (mirrored from state machine context)
    var activeProcessIds: Set<Int32> {
        get { stateMachine.currentContext.activeProcessIds }
    }

    /// Log directory under ~/Library/Logs/PathChanger (not /tmp).
    var privilegedLogsDirectoryPath: String {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/PathChanger").path
    }

    /// Tunnel process log (created via PrivilegedPathSecurity.prepareSecureLogFile before redirect).
    var logFilePath: String {
        "\(privilegedLogsDirectoryPath)/tunnel.log"
    }

    /// Wi-Fi pairing log (PC-D-001: not under NSTemporaryDirectory).
    var pairWiFiLogFilePath: String {
        "\(privilegedLogsDirectoryPath)/pair-wifi.log"
    }

    var startupTraceFilePath: String {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/PathChanger").path
        return "\(logsDir)/startup-trace.jsonl"
    }

    /// Ensure log directory exists
    func ensureLogDirectoryExists() {
        let logsDir = URL(fileURLWithPath: privilegedLogsDirectoryPath, isDirectory: true)
        // Create directory if needed. Parent Library/Logs is a system location.
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        // Best-effort restrictive mode on the app log directory.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: logsDir.path
        )
    }

    /// Synchronize published state with state machine
    func syncStateWithStateMachine() {
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
    func handleStateMachineAction(_ action: TunnelAction) async {
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

    func cancelScheduledTunnelWork(cancelScheduledRestart: Bool) {
        recoveryTask?.cancel()
        recoveryTask = nil
        if cancelScheduledRestart {
            restartTask?.cancel()
            restartTask = nil
        }
    }

    func advanceTunnelLifecycleGeneration(cancelScheduledRestart: Bool = false) -> UInt64 {
        tunnelLifecycleGeneration &+= 1
        cancelScheduledTunnelWork(cancelScheduledRestart: cancelScheduledRestart)
        return tunnelLifecycleGeneration
    }

    func isCurrentTunnelLifecycle(_ generation: UInt64) -> Bool {
        tunnelLifecycleGeneration == generation
    }

    var canAcceptRsdInfo: Bool {
        switch stateMachine.currentState {
        case .starting, .running:
            return true
        case .idle, .stopping, .error:
            return false
        }
    }

    var canServeRsdInfo: Bool {
        stateMachine.currentState == .running
    }

    var canRecoverRsdInfoFromLog: Bool {
        switch stateMachine.currentState {
        case .idle, .starting, .error:
            return true
        case .running, .stopping:
            return false
        }
    }

    func invalidateRsdInfo(reason: String) {
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


}
