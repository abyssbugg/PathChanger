//
//  TunneldManager.swift
//  PathChanger
//
//  The device connection lifecycle. USB and Wi-Fi (the user's Preferred Connection) are
//  both the managed location helper's unprivileged connection (Option A, 2026-11-01);
//  Background Daemon mode was removed 2026-11-06.
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
/// | USB | Yes | Over the cable |
/// | WiFi | No | Over this Mac's Wi-Fi network (the default) |
///
/// ## Example
///
/// ```swift
/// let manager = TunneldManager()
/// manager.preferredMode = .wifi  // Set preferred mode
/// await manager.startTunnel()  // tries exactly the preferred mode
/// ```
enum TunnelMode: String, CaseIterable, Identifiable, Codable {
    case usb = "USB (Lockdown)"
    case wifi = "WiFi Only"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .usb:
            return "USB connection held by PathChanger's location helper"
        case .wifi:
            return "Wi-Fi connection held by PathChanger's location helper"
        }
    }

    /// The tunnel process an earlier PathChanger build ran for this mode. Both modes now
    /// use the managed helper's connection (Option A, 2026-11-01) and start no process;
    /// a recorded tunnel from an older build is stopped only when its command matches.
    var processPattern: String {
        switch self {
        case .usb:
            return "pymobiledevice3 lockdown start-tunnel"
        case .wifi:
            return "pymobiledevice3 remote start-tunnel"
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
    /// An OS-reachable RSD endpoint published by a tunnel process (none is started now;
    /// kept for endpoints recorded by earlier builds).
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
/// - **Two modes**: USB and Wi-Fi, the user's Preferred Connection
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
///                 Task { await tunnelManager.startTunnel(mode: .wifi) }
///             }
///         }
///     }
/// }
/// ```
///
/// ## Tunnel Modes
///
/// The user chooses USB or Wi-Fi; Start tries exactly that mode:
///
/// | Mode | Description |
/// |------|-------------|
/// | USB | The helper's connection over the cable |
/// | WiFi | The helper's connection over this Mac's Wi-Fi network |
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
///
/// ### Lifecycle Control
///
/// - ``startTunnel(mode:)``
/// - ``stopTunnel()``
/// - ``checkIfRunning()``
@MainActor
class TunneldManager: ObservableObject, TunnelQuitControlling, TunnelReconnectControlling {
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
        /// An automatic reconnect attempt must not sit in "starting" for minutes; its own
        /// retry schedule covers a phone that takes longer.
        static let automatic = DeviceVisibilityWait(timeout: 10, interval: 2)
    }

    /// How long Start keeps trying while the phone is not visible. Internal for tests.
    var deviceVisibilityWait: DeviceVisibilityWait = .standard

    /// The same wait for an automatic reconnect attempt. Internal for tests.
    var automaticDeviceVisibilityWait: DeviceVisibilityWait = .automatic

    /// The helper reported that macOS refuses its mDNS queries (Local Network privacy):
    /// the phone may be right there, but no Wi‑Fi lane can see it until PathChanger is
    /// allowed (live 2026-11-02/03).
    nonisolated static let localNetworkBlockedMessage =
        "macOS is blocking PathChanger from the local network. Allow PathChanger in System Settings > Privacy & Security > Local Network."

    nonisolated static let wifiDeviceNotReachableMessage =
        "iPhone is not reachable over Wi‑Fi. Unlock it, keep it on the same Wi‑Fi network as this Mac, then press Start again."

    /// The phone answered over Wi‑Fi (mobdev2 Bonjour found its paired lockdown) but
    /// usbmuxd does not list it. Live 2026-11-02: after the phone's private Wi‑Fi
    /// address rotated, usbmuxd listed nothing for hours while the phone was unlocked
    /// on the same network, so the reachability advice above was false.
    nonisolated static let wifiUnlistedByUsbmuxMessage =
        "Your iPhone answers on this Mac's network, but macOS has not picked it up for developer connections (this can happen after the phone's Wi‑Fi address changes). Connect it with a cable once, keep it unlocked, then press Start again."

    /// The helper's remote pairing lane finds the phone at any Wi‑Fi address without
    /// usbmuxd, but only with a RemotePairing record holding the phone's altIRK. A
    /// missing or older record is fixed by Prepare for Wi‑Fi over the cable (a refresh,
    /// not USB mode).
    nonisolated static let wifiRemotePairingRefreshMessage =
        "This Mac's Wi‑Fi pairing with your iPhone needs a refresh. Connect the iPhone with a cable once, keep it unlocked, press Prepare for Wi‑Fi, then unplug it and press Start again. Wi‑Fi mode stays on."

    /// Lane names and the classes that mean "this lane did not see the phone", as
    /// written by `DeviceLanesUnavailable` in scripts/location_bridge.py
    /// ("<lane>: <ErrorClass>: <message>", lanes joined by "; ").
    private nonisolated static let usbmuxLanes: Set<String> = ["userspace tunnel", "usbmux direct", "preferred RSD"]
    private nonisolated static let mobdev2Lane = "mobdev2"
    private nonisolated static let remotePairingLane = "remote pairing"
    private nonisolated static let usbmuxAbsentErrors: Set<String> = ["DeviceNotFoundError", "NoDeviceConnectedError"]
    /// mobdev2 failures from before a paired lockdown was found (the browse wraps its
    /// OSErrors in Mobdev2BrowseError), or that observed nothing.
    private nonisolated static let mobdev2NotReachedErrors: Set<String> = [
        "Mobdev2DeviceNotFoundError", "Mobdev2BrowseError", "LaneUnsupportedError", "LanesTimedOutError",
    ]
    /// Remote pairing failures from before a pair-verified service was found, or that
    /// observed nothing (the record check runs before any browse).
    private nonisolated static let remotePairingNotReachedErrors: Set<String> = [
        "RemotePairingDeviceNotFoundError", "RemotePairingBrowseError", "RemotePairingRecordStaleError",
        "LaneUnsupportedError", "LanesTimedOutError",
    ]
    private nonisolated static let remotePairingRecordStaleError = "RemotePairingRecordStaleError"
    private nonisolated static let laneFailurePattern =
        "[(;]\\s*(userspace tunnel|usbmux direct|preferred RSD|remote pairing|mobdev2): ([A-Za-z_][A-Za-z0-9_]*):"

    /// The Wi‑Fi give-up message for the helper's last per-lane detail. A remote pairing
    /// lane that had no usable record asks for the Prepare for Wi‑Fi refresh. When every
    /// usbmux-backed lane missed the phone and a Wi‑Fi lane (remote pairing or mobdev2)
    /// reached it, the phone is on the network but unlisted by usbmuxd; anything else
    /// (including a detail this cannot read) keeps the reachability advice.
    nonisolated static func wifiGaveUpMessage(detail: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: laneFailurePattern) else {
            return wifiDeviceNotReachableMessage
        }
        let text = detail as NSString
        var errorByLane: [String: String] = [:]
        for match in pattern.matches(in: detail, range: NSRange(location: 0, length: text.length)) {
            let lane = text.substring(with: match.range(at: 1))
            guard errorByLane[lane] == nil else { return wifiDeviceNotReachableMessage }
            errorByLane[lane] = text.substring(with: match.range(at: 2))
        }
        if errorByLane[remotePairingLane] == remotePairingRecordStaleError {
            return wifiRemotePairingRefreshMessage
        }
        let usbmuxMissedThePhone = usbmuxLanes.allSatisfy { lane in
            errorByLane[lane].map(usbmuxAbsentErrors.contains) ?? false
        }
        let mobdev2ReachedThePhone = errorByLane[mobdev2Lane].map { !mobdev2NotReachedErrors.contains($0) } ?? false
        let remotePairingReachedThePhone = errorByLane[remotePairingLane]
            .map { !remotePairingNotReachedErrors.contains($0) } ?? false
        return usbmuxMissedThePhone && (mobdev2ReachedThePhone || remotePairingReachedThePhone)
            ? wifiUnlistedByUsbmuxMessage
            : wifiDeviceNotReachableMessage
    }

    /// Log lines for the Wi-Fi device wait. The helper's detail can carry the UDID, so
    /// both redact it.
    nonisolated static func wifiWaitingLogLine(detail: String) -> String {
        "[Tunnel] Device not visible on Wi‑Fi yet; waiting (\(LogRedaction.redactingDeviceIdentifiers(detail)))"
    }

    nonisolated static func wifiGaveUpLogLine(detail: String) -> String {
        "[Tunnel] Gave up waiting for the device on Wi‑Fi: \(LogRedaction.redactingDeviceIdentifiers(detail))"
    }

    /// Where the tunnel mode is stored (`AppPreferences.store`: never
    /// the app's own preferences domain inside the test host). Internal so a test can use
    /// its own throwaway suite.
    var settings: UserDefaults = AppPreferences.store

    /// Current tunnel mode (user preference)
    @Published var preferredMode: TunnelMode = .wifi {
        didSet {
            settings.set(preferredMode.rawValue, forKey: ConnectionSettingsMigration.tunnelModeKey)
            // A mode switch restarts an automatic reconnect's decision at once.
            reconnectControlSubject.send()
        }
    }

    /// Mode changes, Stop Tunnel and the Stop latch lifting, for `TunnelAutoReconnector`.
    private let reconnectControlSubject = PassthroughSubject<Void, Never>()

    /// Active tunnel mode (actual running mode)
    @Published var activeMode: TunnelMode?

    /// RSD connection info for device communication (legacy - first device)
    @Published var tunnelInfo: TunnelInfo?


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
        if let mode = Self.loadPreferredMode(from: settings) {
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

    /// The stored tunnel mode, read only after the connection settings migration has
    /// rewritten both stored settings to one transport.
    nonisolated static func loadPreferredMode(from settings: UserDefaults) -> TunnelMode? {
        ConnectionSettingsMigration.prepare(settings)
        return settings.string(forKey: ConnectionSettingsMigration.tunnelModeKey)
            .flatMap(TunnelMode.init(rawValue:))
    }

    /// Handle actions emitted by the state machine
    private func handleStateMachineAction(_ action: TunnelAction) async {
        switch action {
        case .launchProcess:
            // No mode launches a tunnel process; only a recorded one from an earlier
            // build is ever stopped (`stopRecordedTunnel`).
            break

        case .terminateProcesses:
            terminateOwnedTunnelProcess()

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

    /// Set by Stop Tunnel; cleared only by an explicit Start or Move. While set, neither
    /// the location nor the tunnel reconnects automatically (`startTunnelAutomatically`,
    /// `TunnelAutoReconnector`, `AutomaticReconnectPolicy`).
    private(set) var isStoppedByUser = false

    /// Start the tunnel in the preferred mode. There is no fallback to another mode.
    func startTunnel(deviceId: String? = nil) async {
        await startTunnel(deviceId: deviceId, visibilityWait: deviceVisibilityWait)
    }

    private func startTunnel(deviceId: String?, visibilityWait: DeviceVisibilityWait) async {
        // An explicit Start (or Move) is the only thing that lifts Stop's hold.
        isStoppedByUser = false
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

        let mode = preferredMode

        // Reserve startup synchronously before the first suspension point.
        guard case .success = stateMachine.send(.startRequested(mode: mode)) else {
            return
        }

        Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

        // Both modes are the managed helper's unprivileged connection (Option A).
        if await connectHelper(mode: mode, deviceId: deviceId, wait: visibilityWait) {
            return
        }
        guard stateMachine.currentState == .starting else { return }
        stateMachine.send(.errorOccurred(lastError ?? "Failed to connect to the device"))
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
        isStoppedByUser = true
        stopTunnel(disconnectHelper: true)
        // From idle the state machine ignores the Stop: the reconnect learns of it here.
        reconnectControlSubject.send()
    }

    private func stopTunnel(disconnectHelper: Bool) {
        isTunnelRetainedForExit = false
        // End any Start still waiting for the phone; it must not reconnect after Stop.
        connectAttempt &+= 1
        isWaitingForDevice = false

        // The helper connection has no process here; closing it is the stop. It ends
        // any location held over it (the Stop button confirms that first).
        if disconnectHelper, let helper = currentHelperConnection {
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
    var ownedTunnelDefaults: UserDefaults = AppPreferences.store

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

#if DEBUG
    /// Test seam: a root-owned stand-in process for a leftover tunnel cannot have a real
    /// tunnel's command line, so the quit-failure test skips that one check.
    static var skipsRecordedTunnelCommandCheckForTesting = false
#endif

    private static func stopRecordedTunnel(_ record: OwnedTunnelRecord) async -> TunnelProcessTerminator.Outcome {
        var requiredCommandPattern: String? = record.mode.processPattern
#if DEBUG
        if skipsRecordedTunnelCommandCheckForTesting { requiredCommandPattern = nil }
#endif
        return await TunnelProcessTerminator.stop(
            pid: record.pid,
            expectedStartTime: record.startTime,
            requiredCommandPattern: requiredCommandPattern,
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

#endif

    /// Restart tunnel
    func restartTunnel() async {
        let deviceId = lastStartDeviceId ?? currentHelperConnection?.deviceId
        stopTunnel()
        _ = await helperStop?.task.value
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
        await startTunnel(deviceId: deviceId)
    }

    // MARK: - Reconnect (live 2026-11-03)

    var lifecycleState: TunnelState { stateMachine.currentState }

    var lifecycleStatePublisher: AnyPublisher<TunnelState, Never> {
        stateMachine.$state.eraseToAnyPublisher()
    }

    var reconnectDeviceId: String? { lastStartDeviceId ?? currentHelperConnection?.deviceId }

    var reconnectControlChanges: AnyPublisher<Void, Never> {
        reconnectControlSubject.eraseToAnyPublisher()
    }

    /// Move is an explicit user action: it lifts Stop Tunnel's latch like Start does, so a
    /// later loss reconnects the tunnel as well as the location (review 2026-11-03 issue 7).
    func liftStopLatch() {
        guard isStoppedByUser else { return }
        isStoppedByUser = false
        Logger.info("[Tunnel] Move lifted the Stop latch", category: .device)
        reconnectControlSubject.send()
    }

    /// An automatic attempt (TunnelAutoReconnector): only in helper modes, never after Stop,
    /// only from idle or error, with the short visibility wait. It opens the helper's
    /// unprivileged connection like Start, so it never elevates.
    func startTunnelAutomatically(deviceId: String) async {
        guard !isStoppedByUser,
              ArgumentSanitizer.isValidDeviceUDID(deviceId) else { return }
        switch stateMachine.currentState {
        case .idle, .error:
            break
        case .starting, .running, .stopping:
            return
        }
        await startTunnel(deviceId: deviceId, visibilityWait: automaticDeviceVisibilityWait)
    }

    /// Reconnect never stops a live tunnel (live 2026-11-03: a click on a running tunnel
    /// went running -> stopping -> idle and ended the held location). From idle or error it
    /// starts the remembered device (no stop first); a Start or Stop in flight is left alone.
    func reconnectTunnel(deviceId: String?) async {
        switch stateMachine.currentState {
        case .running:
            Logger.info("[Tunnel] Reconnect: the tunnel is already live; not restarting it", category: .device)
            return
        case .starting, .stopping:
            return
        case .idle, .error:
            break
        }
        await startTunnel(deviceId: deviceId ?? reconnectDeviceId)
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
    private func connectHelper(mode: TunnelMode, deviceId: String?, wait: DeviceVisibilityWait) async -> Bool {
        guard let deviceId, ArgumentSanitizer.isValidDeviceUDID(deviceId) else {
            lastError = "Select a device before connecting."
            return false
        }
        if mode == .usb {
            guard await usbmuxReportsUSB() else {
                lastError = "USB is not visible to this Mac. Use a data cable, unlock the phone, and tap Trust. Wi‑Fi is still available — choose Wi‑Fi to use it."
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
        let deadline = Date().addingTimeInterval(wait.timeout)
        // Once any attempt shows the phone answering while usbmuxd does not list it, a
        // later attempt that only missed Bonjour must not bring back the "not reachable"
        // advice (review 2026-11-02-173842 issue 3).
        var phoneAnsweredUnlisted = false
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
                let message = Self.wifiGaveUpMessage(detail: detail)
                if message == Self.wifiUnlistedByUsbmuxMessage { phoneAnsweredUnlisted = true }
                guard Date() < deadline else {
                    // The refresh advice wins: it is the fix for any address. Otherwise an
                    // earlier attempt's proof that the phone answers is kept.
                    lastError = phoneAnsweredUnlisted && message == Self.wifiDeviceNotReachableMessage
                        ? Self.wifiUnlistedByUsbmuxMessage
                        : message
                    Logger.error(Self.wifiGaveUpLogLine(detail: detail), category: .device)
                    return false
                }
                if !isWaitingForDevice {
                    isWaitingForDevice = true
                    Logger.info(Self.wifiWaitingLogLine(detail: detail), category: .device)
                }
                try? await Task.sleep(nanoseconds: UInt64(wait.interval * 1_000_000_000))
                guard isCurrent() else { return true }
            } catch PersistentLocationBridge.PersistentBridgeError.localNetworkBlocked(let detail) {
                // Waiting for the phone cannot help while macOS blocks the network.
                guard isCurrent() else { return true }
                lastError = Self.localNetworkBlockedMessage
                Logger.error(
                    "[Tunnel] macOS blocks the location helper's local network access: "
                        + LogRedaction.redactingDeviceIdentifiers(detail),
                    category: .device
                )
                return false
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
        guard Self.mayAdoptHelperConnection(from: stateMachine.currentState),
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

    /// Connection flags for DVT / simulate-location after a tunnel is up.
    func locationConnectionArguments(for deviceId: String) -> [String] {
        let info = getRsdInfo(for: deviceId)
        return LocationConnectionArguments.make(
            deviceId: deviceId,
            rsdAddress: info?.rsdAddress,
            rsdPort: info?.rsdPort
        )
    }

    /// Get RSD info for a specific device by UDID
    /// Returns nil if no tunnel info is available for this device
    func getRsdInfo(for deviceId: String) -> TunnelInfo? {
        // Only endpoints other processes may dial. The helper's in-process tunnel is
        // never handed out: CLI paths then target the device with `--udid`.
        guard let info = tunnelInfo, info.exposesRSDEndpoint else { return nil }
        return info
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
            // A location held over a Bonjour lane ends when PathChanger quits: the text
            // must not promise that Preserve and Quit keeps it.
            alert.informativeText = terminationHandler.preservedLocationEndsAfterQuit
                ? NSLocalizedString(
                    "quit.location.message.endsAfterQuit",
                    comment: "Quit while a location is held over Wi-Fi (Bonjour), which ends when the app quits"
                )
                : NSLocalizedString(
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
