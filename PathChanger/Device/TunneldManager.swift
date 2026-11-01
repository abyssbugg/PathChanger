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
enum TunnelMode: String, CaseIterable, Identifiable, Codable {
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
            return "USB connection held by PathChanger's location helper"
        case .wifi:
            return "Wi-Fi connection held by PathChanger's location helper"
        case .daemon:
            return "Background daemon (remote tunneld)"
        }
    }

    /// Process command for modes that run a tunnel process. USB and Wi-Fi have none:
    /// the managed helper owns that connection (Option A, 2026-11-01) because the
    /// `start-tunnel --native` RSD refused the location service on iOS 27.2.
    var command: [String] {
        switch self {
        case .auto, .usb, .wifi:
            return []
        case .daemon:
            return ["remote", "tunneld"]
        }
    }

    /// True for modes whose connection is the managed helper's userspace tunnel.
    var usesHelperConnection: Bool {
        self != .daemon
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

/// How the app reaches the device for developer services.
enum TunnelChannel: Equatable, Sendable {
    /// An OS-reachable RSD endpoint published by a tunnel process (daemon mode).
    case rsdEndpoint
    /// The managed helper's in-process pymobiledevice3 userspace tunnel. Its RSD is
    /// reachable only inside the helper, so it is never handed to other processes.
    case helperUserspace
}

/// Tunnel connection info (RSD address for device communication)
struct TunnelInfo: Equatable {
    let rsdAddress: String
    let rsdPort: Int
    let mode: TunnelMode
    let interface: String?
    let processId: Int32?
    var channel: TunnelChannel = .rsdEndpoint
    /// Device the helper connection serves (helper channel only).
    var deviceId: String? = nil

    var connectionString: String {
        "--rsd \(rsdAddress) \(rsdPort)"
    }

    /// A tunnel is usable only when it can actually carry developer services: an RSD
    /// endpoint must be real (`127.0.0.1:0` was once manufactured when parsing failed,
    /// which marked the UI "Tunnel live" with nothing behind it); a helper connection
    /// must name its device.
    var isUsable: Bool {
        switch channel {
        case .helperUserspace:
            return deviceId.map { !$0.isEmpty } ?? false
        case .rsdEndpoint:
            return !rsdAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && rsdPort > 0
                && rsdPort <= 65_535
        }
    }

    /// True only for an endpoint other processes may dial with `--rsd`.
    var exposesRSDEndpoint: Bool {
        channel == .rsdEndpoint && isUsable
    }
}

struct HelperDeviceConnection: Equatable, Sendable {
    let helperPID: Int32
    let channel: String
    /// The helper replaced a stalled connection; any location held on it ended.
    var replaced: Bool = false
}

enum HelperConnectionStatus: Equatable, Sendable {
    case connected
    case notConnected(String)
}

/// The app's single connection to a device: the managed location helper's in-process
/// pymobiledevice3 userspace tunnel (Option A, owner decision 2026-11-01). Live on
/// iOS 27.2 the `start-tunnel --native` RSD refused the location service 3/3 while
/// this tunnel served it 3/3. `PersistentLocationBridge.shared` is the production
/// conformer; tests substitute a fake.
@MainActor
protocol DeviceConnectionOpening: AnyObject {
    func connectDevice(_ deviceId: String, transport: LocationTransport) async throws -> HelperDeviceConnection
    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus
    /// PID of the running helper, or nil; never launches one.
    func helperProcessIdentifierIfRunning() -> Int32?
    /// Close the connection. True when the helper confirmed it closed (or no helper,
    /// hence no connection, exists): only then has a held location really ended.
    @discardableResult
    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool
    /// The health probe failed: the next location command must reopen first.
    func markDeviceConnectionUnverified(_ deviceId: String)
    /// Device the last acknowledged location was applied to, if any.
    var activeLocationDeviceId: String? { get }
    /// Refuse new location updates for the device (Stop Tunnel); queued or in-flight
    /// updates must not reopen the connection and re-apply a stopped location.
    func suspendLocationCommands(for deviceId: String)
    /// Lift a Stop after an explicit user action (Start Tunnel, Move, Reconnect).
    func resumeLocationCommands(for deviceId: String)
}

/// Kernel start time of a process. A PID plus its start time identifies one process
/// instance, so a reused PID never matches a recorded tunnel.
struct ProcessStartTime: Codable, Equatable, Sendable {
    let seconds: Int
    let microseconds: Int32

    static func of(pid: Int32) -> ProcessStartTime? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size > 0,
              info.kp_proc.p_pid == pid else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        return ProcessStartTime(seconds: Int(start.tv_sec), microseconds: start.tv_usec)
    }
}

/// The tunnel process PathChanger launched, persisted so a relaunch can prove that a
/// surviving tunnel (kept by Preserve and Quit) is ours before it may be stopped.
/// Tunnels started by anything else are adopted read-only and never signalled.
struct OwnedTunnelRecord: Codable, Equatable, Sendable {
    let pid: Int32
    let startTime: ProcessStartTime
    let mode: TunnelMode

    static let defaultsKey = "ownedTunnelProcess"

    static func load(from defaults: UserDefaults) -> OwnedTunnelRecord? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(OwnedTunnelRecord.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// True only while this exact process instance is still running.
    var isLive: Bool {
        ProcessStartTime.of(pid: pid) == startTime
    }
}

/// Stops one tunnel process and waits for it to exit (SIGTERM, then SIGKILL).
///
/// Quit must not return before the tunnel has exited: AppKit calls `exit()` right
/// after termination is approved, and anything still deferred to a Task never runs
/// (live 2026-11-01: the tunnel outlived every normal quit).
enum TunnelProcessTerminator {
    enum Outcome: Equatable {
        /// The process was signalled and has exited.
        case exited
        /// Nothing to stop: the PID was already gone.
        case notRunning
        /// The PID is no longer the recorded tunnel instance; it was not signalled.
        case refused(String)
        /// The PID is a tunnel this user may not signal (root-owned leftover).
        case notPermitted(String)
        /// Still alive after SIGKILL.
        case stillRunning(String)
    }

    /// - Parameters:
    ///   - expectedStartTime: when set, the PID must still be this exact process
    ///     instance; it is re-checked before SIGTERM and again before SIGKILL.
    ///   - requiredCommandPattern: when set, the PID's command line must contain it.
    static func stop(
        pid: Int32,
        expectedStartTime: ProcessStartTime? = nil,
        requiredCommandPattern: String?,
        isAlive: @escaping () -> Bool,
        termGrace: TimeInterval = 2.0,
        killGrace: TimeInterval = 1.0
    ) async -> Outcome {
        guard pid > 1 else { return .refused("invalid PID \(pid)") }
        guard isAlive() else { return .notRunning }

        func identityHolds() -> Bool {
            if let expectedStartTime, ProcessStartTime.of(pid: pid) != expectedStartTime {
                return false
            }
            if let requiredCommandPattern,
               commandLine(of: pid)?.contains(requiredCommandPattern) != true {
                return false
            }
            return true
        }

        guard identityHolds() else {
            return isAlive() ? .refused("PID \(pid) is not the recorded tunnel process") : .notRunning
        }

        if kill(pid, SIGTERM) != 0 {
            let code = errno
            if code == ESRCH { return .notRunning }
            let message = "PID \(pid) cannot be signalled: \(String(cString: strerror(code)))"
            return code == EPERM ? .notPermitted(message) : .stillRunning(message)
        }
        if await waitForExit(isAlive: isAlive, timeout: termGrace) { return .exited }

        // Re-verify before escalating: never SIGKILL a PID that was reused meanwhile.
        guard identityHolds() else { return .exited }
        if kill(pid, SIGKILL) != 0, errno != ESRCH {
            return .stillRunning("SIGKILL to PID \(pid) failed: \(String(cString: strerror(errno)))")
        }
        if await waitForExit(isAlive: isAlive, timeout: killGrace) { return .exited }
        return .stillRunning("PID \(pid) did not exit after SIGKILL")
    }

    /// Last-chance synchronous stop for `applicationWillTerminate`, where no awaited
    /// work can run. Bounded so app exit is never held up for more than `termGrace`.
    static func stopBeforeExit(pid: Int32, isAlive: () -> Bool, termGrace: TimeInterval = 0.5) {
        guard pid > 1, isAlive(), kill(pid, SIGTERM) == 0 else { return }
        let deadline = Date().addingTimeInterval(termGrace)
        while isAlive(), Date() < deadline {
            usleep(20_000)
        }
        if isAlive() {
            kill(pid, SIGKILL)
        }
    }

    /// Existence check for a PID that is not our child (adopted tunnel).
    /// EPERM means the process exists but belongs to another user.
    static func isAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Full command line of `pid`, or nil when the process is gone.
    static func commandLine(of pid: Int32) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "command=", "-p", String(pid)]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close() }
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let command = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private static func waitForExit(isAlive: () -> Bool, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isAlive() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return true
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
class TunneldManager: ObservableObject, TunnelQuitControlling {
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

    /// True while a Wi-Fi Start waits for the phone to reappear in usbmux. An idle
    /// Wi-Fi phone drops out for seconds to minutes (live 2026-11-01); the GUI shows
    /// "Waiting for iPhone…" and the user can stop the wait.
    @Published private(set) var isWaitingForDevice = false

    struct DeviceVisibilityWait: Equatable {
        var timeout: TimeInterval
        var interval: TimeInterval
        /// Observed gaps reached about 2 minutes with the phone unlocked.
        static let standard = DeviceVisibilityWait(timeout: 150, interval: 2)
    }

    /// How long Start keeps trying while the phone is not visible. Internal for tests.
    var deviceVisibilityWait: DeviceVisibilityWait = .standard

    static let wifiDeviceNotReachableMessage =
        "iPhone is not reachable over Wi‑Fi. Unlock it, keep it on the same Wi‑Fi network as this Mac, then press Start again."

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

    /// Opens and closes the helper-owned device connection. Injectable for tests.
    var deviceConnector: (any DeviceConnectionOpening)?
    private var connector: any DeviceConnectionOpening {
        deviceConnector ?? PersistentLocationBridge.shared
    }

    /// Device the last explicit start targeted, so Reconnect reopens the same device.
    private var lastStartDeviceId: String?

    /// A Stop of the helper connection closes it in the background; quit, restart,
    /// adoption and AppState await it. The task reports whether the close was confirmed.
    private var helperStop: (deviceId: String, task: Task<Bool, Never>)?

    /// Called when Start replaced a stalled helper connection, which ended any location
    /// held on it, so AppState can report the loss and re-apply.
    var onHelperConnectionReplaced: ((String) -> Void)?

    /// The in-flight close started by Stop for `deviceId`, if any.
    func pendingHelperStop(for deviceId: String) -> Task<Bool, Never>? {
        guard let helperStop, helperStop.deviceId == deviceId else { return nil }
        return helperStop.task
    }

    /// An explicit user action (Move, Reconnect) lifts a previous Stop's block.
    func resumeLocationCommands(for deviceId: String) {
        connector.resumeLocationCommands(for: deviceId)
    }

    /// Cancellable for state machine observation
    private var stateMachineCancellable: AnyCancellable?

    /// Serial queue for tunnel operations
    private let tunnelQueue = DispatchQueue(label: "com.pathchanger.tunnelmanager", qos: .userInitiated)

    /// Active process IDs to prevent duplicates (mirrored from state machine context)
    private var activeProcessIds: Set<Int32> {
        get { stateMachine.currentContext.activeProcessIds }
    }

#if DEBUG
    /// Test seam: read a planted tunnel log instead of the user's real one.
    var tunnelLogPathOverride: String?
#endif

    /// Log file in ~/Library/Logs/PathChanger (more secure than /tmp)
    private var logFilePath: String {
#if DEBUG
        if let tunnelLogPathOverride { return tunnelLogPathOverride }
#endif
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

        // App-exit cleanup is AppDelegate.applicationWillTerminate -> stopTunnelBeforeExit()
        // (synchronous). The observer that used to live here only enqueued a Task that
        // never ran before exit().
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
            // Only a tunnel process publishes an RSD in tunnel.log. For the helper
            // connection, parsing would replace it with a stale `--rsd` from an old log.
            guard !(stateMachine.currentContext.activeMode?.usesHelperConnection ?? false) else { return }
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
        // Only the daemon runs a tunnel process. USB and Wi-Fi connections belong to
        // the managed helper (Option A, 2026-11-01).
        switch mode {
        case .daemon:
            return ["-m", "pymobiledevice3", "remote", "tunneld"]
        case .auto, .usb, .wifi:
            return nil
        }
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
        if mayAdoptRunningDaemon, let runningMode = await detectRunningTunnel() {
            resolveAdoptedOwnership(pid: await discoverPid(for: runningMode))
            stateMachine.send(.externalTunnelDetected(mode: runningMode))
            return
        }

        // Try to start tunnel with preferred mode
        await startTunnel(deviceId: deviceId)
    }

    /// Set by Stop, cleared only by an explicit Start: a `remote tunneld` that survives
    /// Stop (one PathChanger did not launch is detached, never signalled) must not be
    /// adopted again by the status poll behind the user's back.
    private(set) var isDaemonAdoptionSuppressedByStop = false

    /// Only Background Daemon mode adopts a running `remote tunneld`, and not after Stop.
    /// Auto, USB and Wi-Fi use the helper's connection and never fall back to the daemon.
    private var mayAdoptRunningDaemon: Bool {
        preferredMode == .daemon && !isDaemonAdoptionSuppressedByStop
    }

    /// Adopt a tunnel process that survived an app relaunch without requesting elevation.
    ///
    /// The RSD tunnel is a root-owned child and can outlive the UI process. Discovery and
    /// log parsing are read-only; if both process and usable endpoint exist, rebuild the
    /// state-machine context so all DVT commands use `--rsd` immediately.
    func adoptRunningTunnelIfPresent() async {
        guard case .idle = state else { return }
        guard mayAdoptRunningDaemon else { return }
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
        resolveAdoptedOwnership(pid: pid)
        stateMachine.send(.connectionEstablished(info: adopted))
    }

    /// Start tunnel with preferred mode (with auto-fallback)
    func startTunnel(deviceId: String? = nil) async {
        // An explicit Start is the only thing that lifts Stop's hold on daemon adoption.
        isDaemonAdoptionSuppressedByStop = false
        // An explicit Start after a failure begins again: the state machine has no
        // error -> starting transition, so Start used to do nothing at all.
        if case .error = stateMachine.currentState {
            stateMachine.reset()
        }

        // Check state via state machine
        guard !stateMachine.isActive && !stateMachine.isTransitioning else {
            Logger.debug(
                "Ignoring startTunnel request because state is already \(stateMachine.currentState)",
                category: .device
            )
            return
        }

        lastError = nil
        lastStartDeviceId = deviceId

        let modesToTry: [TunnelMode]

        if preferredMode == .auto {
            // Auto: USB when cabled, else Wi-Fi, both through the helper connection.
            // The daemon is not an automatic fallback: it would replace the real
            // Wi-Fi failure reason with an unrelated one.
            modesToTry = [.usb, .wifi]
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

        if !firstMode.usesHelperConnection, let runningMode = await detectRunningTunnel() {
            await parseRsdInfo()
            if let existingInfo = stateMachine.currentContext.tunnelInfo ?? tunnelInfo, existingInfo.isUsable {
                guard stateMachine.currentState == .starting else {
                    return
                }
                Logger.info(
                    "Adopting existing \(runningMode.rawValue) tunnel with usable endpoint",
                    category: .device
                )
                resolveAdoptedOwnership(pid: await discoverPid(for: runningMode))
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

            if mode.usesHelperConnection {
                if await connectHelper(mode: mode, deviceId: deviceId) {
                    return
                }
                guard stateMachine.currentState == .starting else { return }
                if preferredMode != .auto || index == modesToTry.count - 1 {
                    stateMachine.send(.errorOccurred(lastError ?? "Failed to connect to the device"))
                    return
                }
                Logger.debug("Mode \(mode.rawValue) failed, trying next...", category: .device)
                stateMachine.reset()
                continue
            }

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
        isDaemonAdoptionSuppressedByStop = true
        stopTunnel(disconnectHelper: true)
    }

    private func stopTunnel(disconnectHelper: Bool) {
        isTunnelRetainedForExit = false
        // End any Start still waiting for the phone; it must not reconnect after Stop.
        connectAttempt &+= 1
        isWaitingForDevice = false

        // The helper connection has no process here; closing it is the stop. It ends
        // any location held over it (the Stop button confirms that first). In daemon
        // mode the location also rides the helper's connection, so it closes too.
        let daemonLocationDevice = (stateMachine.currentContext.activeMode ?? activeMode) == .daemon
            ? (lastStartDeviceId ?? connector.activeLocationDeviceId)
            : nil
        let helperToClose = currentHelperConnection
            ?? daemonLocationDevice.map { (deviceId: $0, transport: LocationTransport.wifi) }
        if disconnectHelper, let helper = helperToClose {
            let connector = connector
            // Block first, synchronously: an update dequeued after this point must not
            // reopen the connection the Stop is closing.
            connector.suspendLocationCommands(for: helper.deviceId)
            let previous = helperStop?.task
            helperStop = (helper.deviceId, Task { @MainActor in
                _ = await previous?.value
                return await connector.disconnectDevice(helper.deviceId, transport: helper.transport)
            })
        }

        // Send stop event to state machine
        stateMachine.send(.stopRequested)

        monitorTask?.cancel()
        monitorTask = nil

        // Terminate only the concrete Process instance launched by this manager.
        terminateOwnedTunnelProcess()

        // A tunnel PathChanger started in an earlier session (Preserve and Quit) has no
        // Process handle; stop it by its recorded PID + start time. Tunnels started by
        // anything else are only detached, never signalled.
        if let record = adoptedOwnedTunnel {
            let stop = Task { @MainActor [weak self] () -> TunnelProcessTerminator.Outcome in
                let outcome = await Self.stopRecordedTunnel(record)
                switch outcome {
                case .notPermitted(let reason), .stillRunning(let reason):
                    self?.lastError = "Tunnel did not stop: \(reason)"
                    Logger.error("[SECURITY] Adopted tunnel did not stop: \(reason)", category: .security)
                case .exited, .notRunning, .refused:
                    self?.clearOwnedTunnelRecord(ifMatching: record)
                }
                return outcome
            }
            inFlightAdoptedStop = (record, stop)
        }
        adoptedOwnedTunnel = nil

        tunneldProcess = nil
        outputPipe = nil
        errorPipe = nil
        tunnelInfo = nil
        activeMode = nil

        // Mark process as stopped
        stateMachine.send(.processStopped)
    }

    // MARK: - Quit Teardown

    /// Where the owned-tunnel record persists. Internal so tests use an isolated suite.
    var ownedTunnelDefaults: UserDefaults = .standard

    /// The PathChanger-started tunnel adopted from an earlier session (PID + start time
    /// matched the persisted record). Nil for tunnels started by anything else.
    private var adoptedOwnedTunnel: OwnedTunnelRecord?

    /// An explicit Stop of an adopted tunnel escalates in the background; quit awaits it.
    private var inFlightAdoptedStop: (record: OwnedTunnelRecord, task: Task<TunnelProcessTerminator.Outcome, Never>)?

    /// Set when the user chose Preserve and Quit: the preserved location is held by
    /// the helper over this tunnel's RSD endpoint, so the tunnel must outlive the app.
    private(set) var isTunnelRetainedForExit = false

    func retainTunnelForPreservedLocation() {
        isTunnelRetainedForExit = true
        Logger.info("[Tunnel] Retaining tunnel past app exit for a preserved location", category: .device)
    }

    /// Stops the tunnel PathChanger started (this session, or adopted by record) and
    /// returns only after its process exited. On failure, tunnel state is left as-is so
    /// the UI and a retried quit still see the surviving process.
    func stopTunnelForQuit() async -> TunnelQuitStopResult {
        isTunnelRetainedForExit = false

        _ = await helperStop?.task.value
        if let helper = currentHelperConnection {
            // No process to kill: closing the helper's connection is the stop. When the
            // quit flow already shut the helper down this is a no-op.
            await connector.disconnectDevice(helper.deviceId, transport: helper.transport)
            stopTunnel(disconnectHelper: false)
            return .stopped
        }

        if let inFlight = inFlightAdoptedStop {
            let outcome = await inFlight.task.value
            inFlightAdoptedStop = nil
            if case .notPermitted(let reason) = outcome { return .failed(reason) }
            if case .stillRunning(let reason) = outcome { return .failed(reason) }
        }

        let outcome: TunnelProcessTerminator.Outcome?
        if let process = tunneldProcess {
            outcome = await TunnelProcessTerminator.stop(
                pid: process.processIdentifier,
                requiredCommandPattern: nil,
                isAlive: { process.isRunning }
            )
        } else if let record = adoptedOwnedTunnel {
            outcome = await Self.stopRecordedTunnel(record)
        } else {
            outcome = nil
        }

        switch outcome {
        case .notPermitted(let reason), .stillRunning(let reason):
            Logger.error("[SECURITY] Tunnel did not stop at quit: \(reason)", category: .security)
            lastError = "Tunnel did not stop: \(reason)"
            return .failed(reason)
        case nil, .exited, .notRunning, .refused:
            break
        }

        // The process has exited; clear lifecycle state exactly as an explicit Stop
        // does, without re-signalling anything. A tunnel PathChanger did not start is
        // only detached.
        if isRunning, adoptedOwnedTunnel == nil, tunneldProcess == nil {
            Logger.info("[Tunnel] Leaving a tunnel PathChanger did not start running at quit", category: .device)
        }
        tunneldProcess = nil
        adoptedOwnedTunnel = nil
        OwnedTunnelRecord.clear(from: ownedTunnelDefaults)
        stopTunnel()
        return .stopped
    }

    /// Synchronous backstop for `applicationWillTerminate` (quit paths that never ran
    /// `stopTunnelForQuit`, e.g. termination before a window appeared).
    func stopTunnelBeforeExit() {
        guard !isTunnelRetainedForExit else {
            Logger.info("[Tunnel] Leaving retained tunnel running at exit", category: .device)
            return
        }
        if let process = tunneldProcess {
            TunnelProcessTerminator.stopBeforeExit(
                pid: process.processIdentifier,
                isAlive: { process.isRunning }
            )
        } else if let record = adoptedOwnedTunnel, record.isLive {
            TunnelProcessTerminator.stopBeforeExit(
                pid: record.pid,
                isAlive: { record.isLive }
            )
        }
        if !(tunneldProcess?.isRunning ?? false), !(adoptedOwnedTunnel?.isLive ?? false) {
            OwnedTunnelRecord.clear(from: ownedTunnelDefaults)
        }
    }

    /// Records the tunnel this manager just launched so a relaunch can prove ownership.
    private func recordOwnedTunnel(pid: Int32, mode: TunnelMode) {
        guard let startTime = ProcessStartTime.of(pid: pid) else { return }
        OwnedTunnelRecord(pid: pid, startTime: startTime, mode: mode).save(to: ownedTunnelDefaults)
    }

    private func clearOwnedTunnelRecord(ifMatching record: OwnedTunnelRecord) {
        if OwnedTunnelRecord.load(from: ownedTunnelDefaults) == record {
            OwnedTunnelRecord.clear(from: ownedTunnelDefaults)
        }
    }

    /// After adopting a running tunnel at `pid`, decide whether PathChanger owns it.
    private func resolveAdoptedOwnership(pid: Int32?) {
        guard let pid,
              let record = OwnedTunnelRecord.load(from: ownedTunnelDefaults),
              record.pid == pid,
              record.isLive else {
            adoptedOwnedTunnel = nil
            if let record = OwnedTunnelRecord.load(from: ownedTunnelDefaults), !record.isLive {
                OwnedTunnelRecord.clear(from: ownedTunnelDefaults)
            }
            return
        }
        adoptedOwnedTunnel = record
    }

    private static func stopRecordedTunnel(_ record: OwnedTunnelRecord) async -> TunnelProcessTerminator.Outcome {
        await TunnelProcessTerminator.stop(
            pid: record.pid,
            expectedStartTime: record.startTime,
            requiredCommandPattern: record.mode == .auto ? nil : record.mode.processPattern,
            isAlive: { record.isLive }
        )
    }

#if DEBUG
    /// Test seam: install a launched process as this session's owned tunnel.
    func installOwnedTunnelForTesting(_ process: Process, mode: TunnelMode) {
        tunneldProcess = process
        recordOwnedTunnel(pid: process.processIdentifier, mode: mode)
    }

    /// Test seam: run the relaunch ownership decision for an adopted PID.
    func adoptTunnelForTesting(pid: Int32) {
        tunneldProcess = nil
        resolveAdoptedOwnership(pid: pid)
    }

    var adoptedTunnelIsOwnedForTesting: Bool { adoptedOwnedTunnel != nil }
    var hasOwnedTunnelProcessForTesting: Bool { tunneldProcess != nil }

    /// Test seam: replaces the `pgrep` probe for a running `remote tunneld`.
    var runningTunnelDetectorForTesting: (() async -> TunnelMode?)?

    /// Test seam: forget an earlier Stop so a test can isolate the mode gate.
    func allowDaemonAdoptionForTesting() {
        isDaemonAdoptionSuppressedByStop = false
    }
#endif

    /// Restart tunnel
    func restartTunnel() async {
        let deviceId = lastStartDeviceId ?? currentHelperConnection?.deviceId
        stopTunnel()
        _ = await helperStop?.task.value
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
        await startTunnel(deviceId: deviceId)
    }

    // MARK: - Helper-owned device connection

    private static func mayAdoptHelperConnection(from state: TunnelState) -> Bool {
        switch state {
        case .idle, .error:
            return true
        case .starting, .running, .stopping:
            return false
        }
    }

    private var currentHelperConnection: (deviceId: String, transport: LocationTransport)? {
        guard let info = stateMachine.currentContext.tunnelInfo ?? tunnelInfo,
              info.channel == .helperUserspace,
              let deviceId = info.deviceId else {
            return nil
        }
        return (deviceId, info.mode == .usb ? .usb : .wifi)
    }

    private func helperTunnelInfo(mode: TunnelMode, deviceId: String, helperPID: Int32) -> TunnelInfo {
        TunnelInfo(
            rsdAddress: "",
            rsdPort: 0,
            mode: mode,
            interface: nil,
            processId: helperPID,
            channel: .helperUserspace,
            deviceId: deviceId
        )
    }

    /// Open the helper's connection for an explicit start. Returns true when the
    /// state machine reached running (or a stop overtook the start).
    private func connectHelper(mode: TunnelMode, deviceId: String?) async -> Bool {
        guard let deviceId, ArgumentSanitizer.isValidDeviceUDID(deviceId) else {
            lastError = "Select a device before connecting."
            return false
        }
        if mode == .usb {
            guard await usbmuxReportsUSB() else {
                lastError = "USB is not visible to this Mac. Use a data cable, unlock the phone, and tap Trust. Wi‑Fi is still available — pick Wi‑Fi Only to use it."
                return false
            }
        }
        let transport: LocationTransport = mode == .usb ? .usb : .wifi
        // A quick Start after Stop waits for that close, then lifts its block.
        _ = await helperStop?.task.value
        connector.resumeLocationCommands(for: deviceId)
        connectAttempt &+= 1
        let attempt = connectAttempt
        // Still this Start's to finish: no Stop and no newer Start since it began.
        let isCurrent = { self.connectAttempt == attempt && self.stateMachine.currentState == .starting }
        let wait = deviceVisibilityWait
        let deadline = Date().addingTimeInterval(wait.timeout)
        defer { if connectAttempt == attempt { isWaitingForDevice = false } }
        while true {
            do {
                let connection = try await connector.connectDevice(deviceId, transport: transport)
                if connection.replaced {
                    onHelperConnectionReplaced?(deviceId)
                }
                guard isCurrent() else {
                    // Stopped (or superseded) while the connect was in flight.
                    await closeUnownedConnection(deviceId: deviceId, transport: transport)
                    return true
                }
                let info = helperTunnelInfo(mode: mode, deviceId: deviceId, helperPID: connection.helperPID)
                stateMachine.send(.processLaunched(pid: connection.helperPID))
                tunnelInfo = info
                stateMachine.send(.connectionEstablished(info: info))
                Logger.info(
                    "[Tunnel] Device connection open via the location helper (\(connection.channel), helper PID \(connection.helperPID))",
                    category: .device
                )
                return true
            } catch PersistentLocationBridge.PersistentBridgeError.deviceNotVisible(let detail)
                where mode == .wifi {
                guard isCurrent() else { return true }
                guard Date() < deadline else {
                    lastError = Self.wifiDeviceNotReachableMessage
                    Logger.error("[Tunnel] Gave up waiting for the device on Wi‑Fi: \(detail)", category: .device)
                    return false
                }
                if !isWaitingForDevice {
                    isWaitingForDevice = true
                    Logger.info("[Tunnel] Device not visible on Wi‑Fi yet; waiting (\(detail))", category: .device)
                }
                try? await Task.sleep(nanoseconds: UInt64(wait.interval * 1_000_000_000))
                guard isCurrent() else { return true }
            } catch {
                guard isCurrent() else { return true }
                lastError = "Could not connect to the device: \(error.localizedDescription)"
                Logger.error("[Tunnel] \(lastError ?? "Device connection failed")", category: .device)
                return false
            }
        }
    }

    /// Bumped by every helper connect and every Stop; a connect loop whose number is
    /// no longer current stops retrying and claims nothing.
    private var connectAttempt: UInt64 = 0

    /// A connect that finished after Stop, or after a newer Start for another device,
    /// opened a connection no one owns: close it, unless a newer Start for this device
    /// or a held location now uses it (the helper keeps one connection per device).
    /// Registered as `helperStop` so adoption, restart, quit and the next Start wait.
    private func closeUnownedConnection(deviceId: String, transport: LocationTransport) async {
        let ownedByNewerStart: Bool
        switch stateMachine.currentState {
        case .starting, .running:
            ownedByNewerStart = lastStartDeviceId == deviceId
        case .idle, .stopping, .error:
            ownedByNewerStart = false
        }
        guard !ownedByNewerStart, connector.activeLocationDeviceId != deviceId else { return }
        let connector = connector
        let previous = helperStop?.task
        let close = Task { @MainActor in
            _ = await previous?.value
            return await connector.disconnectDevice(deviceId, transport: transport)
        }
        helperStop = (deviceId, close)
        _ = await close.value
    }

    /// Report a connection the helper already holds (opened by Move, or kept by
    /// Preserve and Quit) instead of showing the tunnel as stopped. Never opens one.
    func adoptHelperConnectionIfPresent(deviceId: String, transport: LocationTransport) async {
        // A Stop's disconnect may still be in flight; never re-adopt what it is closing.
        _ = await helperStop?.task.value
        // Daemon mode is a different connection; never report the helper's as it.
        guard preferredMode.usesHelperConnection,
              Self.mayAdoptHelperConnection(from: stateMachine.currentState),
              ArgumentSanitizer.isValidDeviceUDID(deviceId),
              let helperPID = connector.helperProcessIdentifierIfRunning() else {
            return
        }
        guard await connector.deviceConnectionStatus(deviceId, transport: transport) == .connected else {
            return
        }
        guard Self.mayAdoptHelperConnection(from: stateMachine.currentState) else { return }
        if case .error = stateMachine.currentState {
            // Recovery reconnected through the helper after a health failure: report
            // the live connection instead of leaving the pill on Error.
            stateMachine.reset()
        }
        let mode: TunnelMode = transport == .usb ? .usb : .wifi
        guard case .success = stateMachine.send(.startRequested(mode: mode)) else { return }
        let info = helperTunnelInfo(mode: mode, deviceId: deviceId, helperPID: helperPID)
        stateMachine.send(.processLaunched(pid: helperPID))
        tunnelInfo = info
        lastStartDeviceId = deviceId
        stateMachine.send(.connectionEstablished(info: info))
        Logger.info("[Tunnel] Adopted the location helper's open device connection", category: .device)
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
        // USB/Wi-Fi tunnel processes are no longer started (Option A); a leftover
        // `start-tunnel --native` from an older build is not adopted.
        #if DEBUG
        if let runningTunnelDetectorForTesting {
            return await runningTunnelDetectorForTesting()
        }
        #endif
        for mode in [TunnelMode.daemon] {
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
        recordOwnedTunnel(pid: pid, mode: mode)
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
            // Prefer the tunnel PathChanger itself launched when it is among the matches.
            if let recorded = OwnedTunnelRecord.load(from: ownedTunnelDefaults)?.pid, pids.contains(recorded) {
                return recorded
            }
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

    /// Connection flags for DVT / simulate-location after a tunnel is up.
    func locationConnectionArguments(for deviceId: String) -> [String] {
        let info = getRsdInfo(for: deviceId)
        return LocationConnectionArguments.make(
            deviceId: deviceId,
            isDaemonTunneld: activeMode == .daemon,
            rsdAddress: info?.rsdAddress,
            rsdPort: info?.rsdPort
        )
    }

    /// Get RSD info for a specific device by UDID
    /// Returns nil if no tunnel info is available for this device
    func getRsdInfo(for deviceId: String) -> TunnelInfo? {
        // Only endpoints other processes may dial. The helper's in-process tunnel is
        // never handed out: CLI paths then target the device with `--udid`.
        if let info = deviceTunnelInfo[deviceId], info.exposesRSDEndpoint {
            return info
        }
        guard let info = tunnelInfo, info.exposesRSDEndpoint else { return nil }
        return info
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

        // The helper connection's health is the helper's own bounded DVT probe.
        healthMonitor.helperConnectionProbe = { [weak self] info in
            guard let self, let deviceId = info.deviceId else { return false }
            let transport: LocationTransport = info.mode == .usb ? .usb : .wifi
            let alive = await self.connector.deviceConnectionStatus(deviceId, transport: transport) == .connected
            if !alive {
                self.connector.markDeviceConnectionUnverified(deviceId)
            }
            return alive
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
        // AppKit calls exit() as soon as this returns: only synchronous work runs here.
        MainActor.assumeIsolated {
            TunneldManager.shared.stopTunnelBeforeExit()
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
