//
//  PathChangerApp.swift
//  PathChanger
//
//  capability-compatible iOS Location Injection macOS Application
//  Modern Pro UI with full backend integration
//

import SwiftUI
import Combine
import AppKit

struct LocationStatusPresentation: Equatable {
    let connectionLabel: String
    let applicationLabel: String
    let movementLabel: String
    let desiredCoordinateLabel: String
    let appliedCoordinateLabel: String
    let deviceLifecycleLabel: String
    let sessionDiagnostic: String
    let isSpoofing: Bool
    let isMovementActive: Bool
    let isMovementPaused: Bool
    let desiredCoordinate: LocationCoordinate?
    let appliedCoordinate: LocationCoordinate?
    let canApply: Bool
    let canMove: Bool
    let canClear: Bool

    init(state: LocationSessionState, deviceVisible: Bool, hasUnresolvedClear: Bool = false) {
        let ready: LocationSessionIdentity? = { if case .ready(let value) = state.connection { return value }; return nil }()
        let active: LocationInjectionReceipt? = {
            switch state.application {
            case .active(let value):
                return value
            case .applying:
                // A movement step is in flight: the location that was active when it
                // began is still the one held on the device until the next receipt
                // replaces it. Showing Applying for every step flickered Location, the
                // Applied chip and the map pin up to five times a second (live
                // 2026-11-01). After a failure or loss nothing is held (the helper
                // closed the connection), and the first application still reads Applying.
                return state.heldWhileApplying
            case .idle, .uncertain, .lost, .clearing, .failed:
                return nil
            }
        }()
        let current: LocationInjectionReceipt? = active.flatMap { receipt -> LocationInjectionReceipt? in
            guard let ready, receipt.sessionGeneration == ready.generation,
                  receipt.transport == ready.transport, receipt.endpointClass == ready.endpointClass,
                  receipt.outcome == .applied else { return nil }
            return receipt
        }
        isSpoofing = current != nil
        isMovementActive = {
            if case .moving = state.movement { return true }
            if case .paused = state.movement { return true }
            return false
        }()
        isMovementPaused = { if case .paused = state.movement { return true }; return false }()
        desiredCoordinate = state.desiredLocation
        appliedCoordinate = current?.coordinate
        switch state.connection {
        case .unavailable:
            connectionLabel = Self.localizedStatus("location.status.connection.unavailable", comment: "Connection unavailable")
        case .ready(let identity):
            let transport = identity.transport == .usb ? "usb" : "wifi"
            let key = "location.status.connection.ready.\(transport)"
            connectionLabel = Self.localizedStatus(key, comment: "Connection ready")
        case .reconnecting:
            connectionLabel = Self.localizedStatus("location.status.connection.reconnecting", comment: "Connection reconnecting")
        case .failed:
            connectionLabel = Self.localizedStatus("location.status.connection.failed", comment: "Connection failed")
        }
        switch state.application {
        case .idle:
            applicationLabel = Self.localizedStatus("location.status.application.idle", comment: "Application idle")
        case .applying:
            applicationLabel = isSpoofing
                ? Self.localizedStatus("location.status.application.active.spoofing", comment: "Application active")
                : Self.localizedStatus("location.status.application.applying", comment: "Application applying")
        case .active:
            let key = isSpoofing ? "location.status.application.active.spoofing" : "location.status.application.active.uncertain"
            applicationLabel = Self.localizedStatus(key, comment: "Application active")
        case .uncertain:
            applicationLabel = Self.localizedStatus("location.status.application.uncertain", comment: "Application uncertain")
        case .lost:
            applicationLabel = Self.localizedStatus("location.status.application.lost", comment: "Application lost")
        case .clearing:
            applicationLabel = Self.localizedStatus("location.status.application.clearing", comment: "Application clearing")
        case .failed:
            applicationLabel = Self.localizedStatus("location.status.application.failed", comment: "Application failed")
        }
        switch state.movement {
        case .idle:
            movementLabel = Self.localizedStatus("location.status.movement.idle", comment: "Movement idle")
        case .moving:
            movementLabel = Self.localizedStatus("location.status.movement.moving", comment: "Movement moving")
        case .paused:
            movementLabel = Self.localizedStatus("location.status.movement.paused", comment: "Movement paused")
        case .completed:
            movementLabel = Self.localizedStatus("location.status.movement.completed", comment: "Movement completed")
        }
        desiredCoordinateLabel = state.desiredLocation?.formattedShort ?? "—"
        appliedCoordinateLabel = current?.coordinate.formattedShort ?? (state.lastAcknowledgedReceipt == nil ? "—" : "Uncertain")
        deviceLifecycleLabel = deviceVisible ? "Device visible" : "No visible device"
        canApply = !hasUnresolvedClear && ready != nil && state.desiredLocation != nil && !Self.isBusy(state.application)
        canMove = !hasUnresolvedClear && isSpoofing && ready != nil
        if case .clearing = state.application {
            canClear = false
        } else {
            canClear = hasUnresolvedClear ||
                (ready != nil && (state.desiredLocation != nil || state.lastAcknowledgedReceipt != nil))
        }
        let source = ready?.stableDeviceID ?? "unknown"
        let checksum = source.utf8.reduce(UInt32(5381)) { (($0 << 5) &+ $0) &+ UInt32($1) } & 0xFFFF
        let alias = String(format: "Device-%04X", checksum)
        let transport = ready.map { Self.transportName($0.transport) } ?? "Unavailable"
        let endpoint = ready.map { $0.endpointClass == .direct ? "Direct" : "RSD" } ?? "Unavailable"
        let generation = ready?.generation ?? state.lastAcknowledgedReceipt?.sessionGeneration ?? 0
        let request = state.lastAcknowledgedReceipt.map { String($0.requestID.uuidString.suffix(4)) } ?? "—"
        let acknowledged = state.lastAcknowledgedReceipt.map { ISO8601DateFormatter().string(from: $0.completedAt) } ?? "—"
        sessionDiagnostic = "\(alias) · \(transport) · \(endpoint) · generation \(generation) · request …\(request) · acknowledged \(acknowledged)"
    }

    private static let statusFallbacks: [String: String] = [
        "location.status.connection.unavailable": "Unavailable",
        "location.status.connection.ready.usb": "Ready over USB",
        "location.status.connection.ready.wifi": "Ready over Wi-Fi",
        "location.status.connection.reconnecting": "Reconnecting",
        "location.status.connection.failed": "Lost",
        "location.status.application.idle": "Idle",
        "location.status.application.applying": "Applying",
        "location.status.application.active.spoofing": "Active / Held",
        "location.status.application.active.uncertain": "Uncertain",
        "location.status.application.uncertain": "Uncertain",
        "location.status.application.lost": "Lost",
        "location.status.application.clearing": "Clearing",
        "location.status.application.failed": "Failed",
        "location.status.movement.idle": "Idle",
        "location.status.movement.moving": "Moving",
        "location.status.movement.paused": "Paused",
        "location.status.movement.completed": "Completed",
    ]

    private static func localizedStatus(_ key: String, comment: String) -> String {
        let localized = NSLocalizedString(key, comment: comment)
        return localized == key ? (statusFallbacks[key] ?? key) : localized
    }

    private static func isBusy(_ phase: LocationApplicationPhase) -> Bool {
        if case .applying = phase { return true }; if case .clearing = phase { return true }; return false
    }
    private static func transportName(_ value: LocationTransport) -> String { value == .usb ? "USB" : "Wi-Fi" }
}

@main
struct PathChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppState(
            startBackgroundServices: AppRuntimeEnvironment.allowsAutomaticStartup,
            locationInjector: LocationInjectorFactory.make(),
            ddiPreparerFactory: { DeveloperDiskImagePreparer.live(deviceManager: $0) }
        ))
    }
    @StateObject private var tunneldManager = TunneldManager.shared
    @StateObject private var dependencyValidator = DependencyValidator.shared

    var body: some Scene {
        WindowGroup {
            if dependencyValidator.validationStatus == .invalid {
                DependencyErrorView(validator: dependencyValidator)
                    .onAppear {
                        appDelegate.terminationHandler = appState
                    }
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(tunneldManager)
                    .frame(minWidth: 1100, minHeight: 740)
                    .onAppear {
                        appDelegate.terminationHandler = appState
                        guard AppRuntimeEnvironment.allowsAutomaticStartup else {
                            return
                        }

                        Task {
                            await dependencyValidator.validateAll()
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Check for Updates menu item (in App menu after About)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appDelegate.updaterController.checkForUpdates()
                }
            }

            CommandMenu("Location") {
                Button("Set Location...") {
                    appState.showLocationInput = true
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Clear Location") {
                    Task {
                        await appState.clearLocation()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Refresh Devices") {
                    Task {
                        await appState.refreshDevices()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("Simulation") {
                Button("Start Simulation") {
                    Task { await appState.startSimulation() }
                }
                .keyboardShortcut(.space, modifiers: .command)
                .disabled(!appState.canStartSimulation)

                Button("Pause Simulation") {
                    appState.pauseSimulation()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!appState.isSimulating)

                Button("Stop Simulation") {
                    Task { await appState.stopSimulation() }
                }
                .keyboardShortcut(.escape, modifiers: .command)
                .disabled(!appState.isSimulating)

                Divider()

                Menu("Speed") {
                    ForEach(SimulationSpeed.allCases, id: \.self) { speed in
                        Button(speed.displayName) {
                            appState.setSpeed(speed)
                        }
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

}

// MARK: - Quit Policy

enum LocationQuitChoice: Equatable, Sendable {
    case clearAndQuit
    case preserveAndQuit
    case cancel
}

enum LocationQuitPreparationResult: Equatable, Sendable {
    case terminate
    case cancel
    case failed(String)
}

@MainActor
protocol LocationTerminationHandling: AnyObject {
    var requiresLocationQuitDecision: Bool { get }
    func prepareForQuitWithoutLocation() async -> LocationQuitPreparationResult
    func prepareForQuit(_ choice: LocationQuitChoice) async -> LocationQuitPreparationResult
}

enum TunnelQuitStopResult: Equatable, Sendable {
    case stopped
    case failed(String)
}

/// Tunnel teardown used by the quit flow. `TunneldManager.shared` is the only
/// production conformer; tests substitute a fake.
@MainActor
protocol TunnelQuitControlling: AnyObject {
    /// Stops the tunnel and returns only after its process has exited.
    func stopTunnelForQuit() async -> TunnelQuitStopResult
    /// Keeps the tunnel running past app exit for a preserved location session.
    func retainTunnelForPreservedLocation()
    /// The close Stop Tunnel started for `deviceId`; true once the helper confirmed it.
    func pendingHelperStop(for deviceId: String) -> Task<Bool, Never>?
    /// An explicit user action (Move, Reconnect) lifts a previous Stop's block.
    func resumeLocationCommands(for deviceId: String)
}

// MARK: - App State

/// Global application state with full simulation control
@MainActor
class AppState: ObservableObject, LocationTerminationHandling {

    // MARK: Domain State Managers
    //
    // AppState is becoming a composition root (ARCH-002). Device state has moved to
    // `device`; the properties below forward to it so views and tests keep working
    // unchanged. Views can migrate to observing the manager directly, one at a time.
    let device: DeviceStateManager
    let route: RouteStateManager
    let simulation: SimulationStateManager

    // MARK: Device State (forwarded to `device`)
    var selectedDevice: Device? {
        get { device.selectedDevice }
        set { device.selectedDevice = newValue }
    }
    var availableDevices: [Device] {
        get { device.availableDevices }
        set { device.availableDevices = newValue }
    }
    var isTunneldRunning: Bool {
        get { device.isTunneldRunning }
        set { device.isTunneldRunning = newValue }
    }
    var connectionStatus: ConnectionStatus {
        get { device.connectionStatus }
        set { device.connectionStatus = newValue }
    }

    var locationPresentation: LocationStatusPresentation {
        var presentationState = locationSessionCoordinator.state
        if locationClearTask != nil {
            presentationState.application = .clearing
            presentationState.movement = .idle
        }
        return LocationStatusPresentation(
            state: presentationState,
            deviceVisible: selectedDevice != nil,
            hasUnresolvedClear: unresolvedClearSession != nil
        )
    }

    // MARK: Location State (forwarded to `simulation`)
    var currentLocation: LocationCoordinate? {
        get { simulation.currentLocation }
        set { simulation.currentLocation = newValue }
    }
    var targetLocation: LocationCoordinate? {
        get { simulation.targetLocation }
        set { simulation.targetLocation = newValue }
    }

    // MARK: Simulation State (forwarded to `simulation`)
    var isSimulating: Bool {
        get { simulation.isSimulating }
        set { simulation.isSimulating = newValue }
    }
    var isPaused: Bool {
        get { simulation.isPaused }
        set { simulation.isPaused = newValue }
    }
    var simulationSpeed: SimulationSpeed {
        get { simulation.simulationSpeed }
        set { simulation.simulationSpeed = newValue }
    }
    var activeMode: AppMode {
        get { simulation.activeMode }
        set {
            simulation.activeMode = newValue
            // Auto jump belongs to Jump: leaving the mode ends it and holds the stop
            // (it used to keep running and jump back to stop 1 with no Move).
            if newValue != .jump { endAutoJumpIfRunning() }
        }
    }
    var autoSpeed: Bool {
        get { simulation.autoSpeed }
        set { simulation.autoSpeed = newValue }
    }
    var customSpeedMps: Double {
        get { simulation.customSpeedMps }
        set { simulation.customSpeedMps = newValue }
    }
    var updateFrequencyHz: Double {
        get { simulation.updateFrequencyHz }
        set { simulation.updateFrequencyHz = newValue }
    }
    var smoothTurns: Bool {
        get { simulation.smoothTurns }
        set { simulation.smoothTurns = newValue }
    }

    @Published var copiedFeedback: Bool = false

    // Jump-mode state lives with the route it indexes into.
    var jumpIndex: Int {
        get { route.jumpIndex }
        set { route.jumpIndex = newValue }
    }
    var autoJump: Bool {
        get { route.autoJump }
        set {
            route.autoJump = newValue
            if !newValue { endAutoJumpIfRunning() }
        }
    }
    var autoJumpPauseSeconds: TimeInterval {
        get { route.autoJumpPauseSeconds }
        set { route.autoJumpPauseSeconds = min(max(newValue, 1), 60) }
    }
    /// Distance per route update: the shown travel speed divided by the update rate, so
    /// Two-Spot and Multi-Spot travel at the speed the card displays.
    var routeStepMeters: Double {
        effectiveMetersPerSecond / max(updateFrequencyHz, 1)
    }


    // MARK: Route Playback (forwarded to `route`)
    var currentRoute: [LocationCoordinate] {
        get { route.currentRoute }
        set { route.currentRoute = newValue }
    }
    var routeProgress: Double {
        get { route.progress }
        set { route.progress = newValue }
    }
    var isLoadingRoute: Bool { route.isLoading }
    var loopRoute: Bool {
        get { route.loopEnabled }
        set { route.loopEnabled = newValue }
    }

    // MARK: Joystick State (forwarded to `simulation`)
    var joystickDirection: CGPoint {
        get { simulation.joystickDirection }
        set { simulation.joystickDirection = newValue }
    }
    var joystickSpeed: Double {
        get { simulation.joystickSpeed }
        set { simulation.joystickSpeed = newValue }
    }

    // MARK: UI State
    @Published var showLocationInput: Bool = false
    @Published var showRouteImport: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var lastError: String? {
        // Every assignment, wherever it is made, reaches the log (live 2026-11-01:
        // a failed Clear left no trace).
        didSet {
            if let lastError, lastError != oldValue {
                Logger.error("[Error] " + LogRedaction.redactingDeviceIdentifiers(lastError), category: .session)
            }
        }
    }
    @Published var statusMessage: String? {
        didSet {
            if let statusMessage, statusMessage != oldValue {
                Logger.info("[Status] " + LogRedaction.redactingDeviceIdentifiers(statusMessage), category: .session)
            }
        }
    }

    // MARK: Statistics (forwarded to `simulation`)
    var injectionStats: InjectionStats {
        get { simulation.injectionStats }
        set { simulation.injectionStats = newValue }
    }

    // MARK: iOS 18+ Warning State
    /// Tracks device IDs that have already shown the iOS 18+ toast in this session
    private var shownIOS18WarningDeviceIds: Set<String> = []

    // MARK: Reliability State (forwarded to `device`)
    var recoveryState: ConnectionRecoveryState {
        get { device.recoveryState }
        set { device.recoveryState = newValue }
    }
    var isUSBConnected: Bool {
        get { device.isUSBConnected }
        set { device.isUSBConnected = newValue }
    }
    var isWiFiTransportAvailable: Bool {
        get { device.isWiFiTransportAvailable }
        set { device.isWiFiTransportAvailable = newValue }
    }
    var preferUSBConnection: Bool {
        get { device.preferUSBConnection }
        set { device.preferUSBConnection = newValue }
    }

    // MARK: Shared Managers
    let simulationEngine: SimulationEngine
    let errorHandler: ErrorHandler
    let locationSessionCoordinator: LocationSessionCoordinator

    var routeLibrary: RouteLibraryManager { route.routeLibrary }

    // Forwarded so existing call sites keep resolving.
    var deviceManager: DeviceManager { device.deviceManager }
    var reliabilityManager: ReliabilityManager { device.reliabilityManager }
    var usbFallbackManager: USBFallbackManager { device.usbFallbackManager }

    // MARK: Private
    private let locationBridge: DevLocationBridge
    private let locationInjector: any LocationInjecting
    private let managedLocationSessionSource: any ManagedLocationSessionSource
    private let tunnelQuitController: any TunnelQuitControlling
    private let routeDelay: @MainActor @Sendable (TimeInterval) async -> Void
    /// DDI mount gate for the injection path. Armed via `ddiPreparerFactory`
    /// at the production entry point; nil in tests/previews so no device
    /// commands run outside the real app.
    private let ddiPreparer: DeveloperDiskImagePreparer?
    private var pendingApplicationModes: [UUID: AppMode] = [:]
    private var applicationTasks: [UUID: Task<LocationInjectionReceipt, Error>] = [:]
    @Published private var locationClearTask: Task<Void, Never>?
    @Published private var unresolvedClearSession: LocationSessionIdentity?
    private var locationOperationGeneration: UInt64 = 0
    private var simulationTask: Task<Void, Never>? {
        didSet { isMovementEngineRunning = simulationTask != nil }
    }
    private var routePlaybackID: UUID?
    private var joystickTask: Task<Void, Never>?
    /// The one joystick engagement in flight: a drag sends many direction samples, and
    /// each used to spawn its own start until the first injection returned.
    private var joystickStartTask: Task<Void, Never>?
    /// A Teleport or single Jump hop started by Move is still applying.
    private var isOneShotMoveInFlight = false
    /// A route or Auto jump engine is running (from Move until it ends). The Move button
    /// shows Stop for this whole time, not only after the first acknowledged point.
    @Published private(set) var isMovementEngineRunning = false
    private var autoJumpPlaybackID: UUID?
    private var isStartingJoystick = false
    /// Bumped by Stop movement: a start still in flight must not engage afterwards.
    private var joystickEngagementID: UInt64 = 0
    private var joystickDeliveryID: UUID?
    private let automaticRecoveryEnabled: Bool
    private var locationRecoveryTask: Task<Void, Never>?
    private var bridgeEventTask: Task<Void, Never>?
    private var persistentBridgeEventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// True once the user explicitly started a tunnel this session (tunnel button or
    /// error-dialog action). One-tap reconnect may then restart it; launch-time and
    /// adopted tunnels never gain that permission.
    private var userStartedTunnelInSession = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        canBeginLocationOperation && simulation.canStartSimulation
    }

    private var canBeginLocationOperation: Bool {
        locationClearTask == nil && unresolvedClearSession == nil
    }

    /// Why a Clear blocks Move, if it does: the GUI must say so instead of claiming the
    /// device is not ready (live 2026-11-01).
    var moveBlockedByClear: LocationClearBlock? {
        if locationClearTask != nil { return .clearInProgress }
        if unresolvedClearSession != nil { return .clearUnresolved }
        return nil
    }

    var simulationStatusText: String {
        simulation.statusText
    }

    // MARK: Initialization

    init(
        startBackgroundServices: Bool = true,
        locationInjector: (any LocationInjecting)? = nil,
        managedLocationSessionSource: (any ManagedLocationSessionSource)? = nil,
        deviceManager: DeviceManager? = nil,
        ddiPreparerFactory: ((DeviceManager) -> DeveloperDiskImagePreparer)? = nil,
        tunnelQuitController: (any TunnelQuitControlling)? = nil,
        routeDelay: @escaping @MainActor @Sendable (TimeInterval) async -> Void = { seconds in
            guard seconds > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        let sharedBridge = DevLocationBridge()
        let sharedErrorHandler = ErrorHandler()
        let resolvedInjector: any LocationInjecting = locationInjector ?? sharedBridge
        let resolvedManagedSessionSource: any ManagedLocationSessionSource =
            managedLocationSessionSource ?? PersistentLocationBridge.shared
        let sessionCoordinator = LocationSessionCoordinator(injector: resolvedInjector)
#if DEBUG
        let usesScriptedInjector = resolvedInjector is ScriptedLocationInjector
#else
        let usesScriptedInjector = false
#endif
        let effectiveBackgroundServices = startBackgroundServices && !usesScriptedInjector

        self.locationBridge = sharedBridge
        self.locationInjector = resolvedInjector
        self.managedLocationSessionSource = resolvedManagedSessionSource
        self.tunnelQuitController = tunnelQuitController ?? TunneldManager.shared
        self.routeDelay = routeDelay
        self.automaticRecoveryEnabled = effectiveBackgroundServices
        self.errorHandler = sharedErrorHandler
        self.locationSessionCoordinator = sessionCoordinator
        self.device = DeviceStateManager(
            deviceManager: deviceManager,
            startBackgroundServices: effectiveBackgroundServices
        )
        let resolvedDDIDeviceManager = device.deviceManager
        self.ddiPreparer = ddiPreparerFactory.map { factory in
            factory(resolvedDDIDeviceManager)
        }
        self.route = RouteStateManager(routeLibrary: RouteLibraryManager())
        self.simulation = SimulationStateManager(
            locationBridge: sharedBridge,
            errorHandler: sharedErrorHandler
        )
        self.simulationEngine = SimulationEngine(locationBridge: sharedBridge)
        if usesScriptedInjector {
#if DEBUG
            sessionCoordinator.connectionReady(ScriptedLocationInjector.sessionIdentity)
#endif
        }

        // Cross-manager references.
        simulation.setDeviceStateManager(device)
        route.setSimulationStateManager(simulation)

        // Re-publish the managers' changes so views observing AppState still update.
        for publisher in [device.objectWillChange, route.objectWillChange, simulation.objectWillChange, sessionCoordinator.objectWillChange] {
            publisher
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        simulation.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }

        device.onDeviceSelected = { [weak self] selected in
            guard let self else { return }
            simulationEngine.setDevice(selected)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if await self.restorePublishedManagedLocationSession(for: selected) {
                    return
                }

                let transport: LocationTransport = selected.connectionType == .usb ? .usb : .wifi
                let endpointClass: LocationEndpointClass = .unresolved
                if case .ready(let current) = self.locationSessionCoordinator.state.connection {
                    if current.stableDeviceID == selected.id,
                       current.transport == transport {
                        return
                    }

                    switch self.locationSessionCoordinator.state.application {
                    case .applying, .active, .clearing:
                        let reason = current.stableDeviceID == selected.id
                            ? "Device transport changed during an active location operation"
                            : "Selected device changed during an active location operation"
                        self.locationSessionCoordinator.connectionLost(reason: reason)
                        return
                    case .idle, .uncertain, .lost, .failed:
                        break
                    }
                }

                let generation: UInt64
                if case .ready(let current) = self.locationSessionCoordinator.state.connection {
                    generation = current.generation &+ 1
                } else {
                    generation = (self.locationSessionCoordinator.state.lastAcknowledgedReceipt?.sessionGeneration ?? 0) &+ 1
                }
                self.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
                    stableDeviceID: selected.id,
                    transport: transport,
                    endpointClass: endpointClass,
                    generation: generation
                ))
            }
        }

#if DEBUG
        if usesScriptedInjector {
            let stableDeviceID = ScriptedLocationInjector.sessionIdentity.stableDeviceID
            let scriptedDevice = Device(
                id: stableDeviceID,
                displayName: "Scripted iPhone",
                connectionType: .usb,
                productType: "iPhone16,2",
                productVersion: "18.0",
                deviceName: "Scripted iPhone"
            )
            device.availableDevices = [scriptedDevice]
            device.usbDirectDeviceIds = [stableDeviceID]
            device.selectDevice(scriptedDevice)
        }
#endif

        device.onConnectionLost = { [weak self] in
            self?.statusMessage = "Connection lost, attempting to reconnect..."
        }

        device.onReconnectionFailed = { [weak self] reason in
            self?.lastError = reason
        }

        device.onTunnelActiveChanged = { [weak self] isActive in
            guard let self, !isActive else { return }
            Task { await self.locationBridge.stopTunnelDependentSimulation() }
        }

        device.onLocationSessionLoss = { [weak self] event in
            self?.handleLocationSessionLoss(event)
        }

        // Check if onboarding is needed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        self.showOnboarding = !onboardingCompleted

        guard effectiveBackgroundServices || usesScriptedInjector else {
            return
        }

        // Start replaced a stalled helper connection: a location held on it ended.
        TunneldManager.shared.onHelperConnectionReplaced = { [weak self] deviceId in
            guard let self, self.selectedDevice?.id == deviceId,
                  self.locationSessionCoordinator.state.lastAcknowledgedReceipt != nil else { return }
            self.handleLocationSessionLoss(.endpointReplaced)
        }

        if !usesScriptedInjector {
            bridgeEventTask = Task { [weak self, locationBridge] in
                let events = await locationBridge.events()
                for await event in events {
                    guard !Task.isCancelled else { break }
                    await self?.handleLocationBridgeEvent(event, heldSubprocessSource: true)
                }
            }
        }
        persistentBridgeEventTask = Task { [weak self, sessionCoordinator] in
            let events = await sessionCoordinator.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                await self?.handleLocationBridgeEvent(event, heldSubprocessSource: false)
            }
        }

        setupErrorHandler()
    }

    // MARK: Manager Setup

    private func setupErrorHandler() {
        errorHandler.$currentError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.lastError = error.message
                if let suggestion = error.suggestion {
                    self?.lastError? += "\n\n\(suggestion)"
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Device Management (delegated to `device`)

    func refreshDevices() async {
        await device.refreshDevices()
        guard automaticRecoveryEnabled else { return }
        _ = await restoreManagedLocationSessionFromSource()
    }

    func checkTunneldStatus() async {
        await device.checkTunneldStatus()
    }

    func selectDevice(_ selected: Device) {
        device.selectDevice(selected)
    }

    /// Prepare the selected trusted USB device for cold-start Wi-Fi discovery.
    func prepareSelectedDeviceForWiFi() async {
        guard let selectedDevice else {
            statusMessage = "Connect and select an iOS device first"
            return
        }

        statusMessage = "Enabling Wi-Fi connections…"
        do {
            try await deviceManager.prepareWiFi(for: selectedDevice)
            deviceManager.setConnectionMode(.wifi)
            statusMessage = "Wi-Fi pairing ready — the cable can now be disconnected"
            await refreshDevices()
        } catch {
            errorHandler.handle(error, context: "Prepare Wi-Fi")
            statusMessage = error.localizedDescription
        }
    }

    /// Start the selected tunnel mode against the selected device, when available.
    func startSelectedTunnel() async {
        userStartedTunnelInSession = true
        await TunneldManager.shared.startTunnel(deviceId: tunnelTargetDeviceId())
    }

    /// Resolve the best device ID for tunnel startup.
    ///
    /// Wi‑Fi discovery can surface transport endpoints (IPv4/IPv6) alongside the actual
    /// device UDID. `remote start-tunnel` must receive a UDID; endpoint IDs make
    /// pymobiledevice3 report "Device is not connected".
    func tunnelTargetDeviceId() -> String? {
        guard let selectedDevice else { return nil }

        if ArgumentSanitizer.isValidDeviceUDID(selectedDevice.id) {
            return selectedDevice.id
        }

        // Prefer a matching discovered device that carries a real UDID.
        if let matched = availableDevices.first(where: {
            guard ArgumentSanitizer.isValidDeviceUDID($0.id) else { return false }
            return $0.deviceName == selectedDevice.deviceName
                || ($0.displayName == selectedDevice.displayName
                    && $0.productType == selectedDevice.productType
                    && $0.productVersion == selectedDevice.productVersion)
        }) {
            return matched.id
        }

        // If exactly one UDID is currently visible, it is the safest fallback.
        let visibleUDIDs = Set(
            availableDevices
                .map(\.id)
                .filter { ArgumentSanitizer.isValidDeviceUDID($0) }
        )
        if visibleUDIDs.count == 1 {
            return visibleUDIDs.first
        }

        // Final fallback: a previously prepared device UDID from Wi‑Fi bootstrap.
        if let preparedUDID = UserDefaults.standard.string(forKey: "lastPreparedDeviceUDID"),
           ArgumentSanitizer.isValidDeviceUDID(preparedUDID) {
            return preparedUDID
        }

        return selectedDevice.id
    }

    /// One-tap recovery after the connection phase reports failed: refresh device
    /// discovery, restart the tunnel when the user started one in this session,
    /// restore a ready location session for the selected device, and reapply the
    /// desired coordinate through the normal apply path. Safe to tap repeatedly:
    /// an in-flight reconnect is awaited rather than duplicated, and a Clear in
    /// progress is never interrupted.
    func reconnectNow() async {
        if let reconnectTask {
            await reconnectTask.value
            return
        }
        let reconnect = Task { @MainActor in
            defer { reconnectTask = nil }
            await runReconnectNow()
        }
        reconnectTask = reconnect
        await reconnect.value
    }

    private func runReconnectNow() async {
        guard canBeginLocationOperation else { return }
        // Manual reconnect supersedes an in-flight automatic recovery; cancelling
        // first keeps the two paths from driving the coordinator concurrently.
        locationRecoveryTask?.cancel()
        await locationRecoveryTask?.value
        locationRecoveryTask = nil

        await device.refreshDevices()
        if let selectedDevice {
            tunnelQuitController.resumeLocationCommands(for: selectedDevice.id)
        }

        if userStartedTunnelInSession {
            await TunneldManager.shared.restartTunnel()
        }

        guard prepareLocationSessionIfNeeded() else {
            statusMessage = "Connect and select an iOS device to reconnect"
            return
        }
        guard let desired = locationSessionCoordinator.state.desiredLocation else { return }
        await applyPlannedLocation(desired, mode: .teleport)
    }

    // MARK: Location Control

    func setLocation(
        _ coordinate: LocationCoordinate,
        quiet: Bool = false,
        usePerformanceMode: Bool = false
    ) async {
        await simulation.setLocation(
            coordinate,
            quiet: quiet,
            usePerformanceMode: usePerformanceMode
        )
    }

    /// Clears the simulated location. `reconcilingConnection` runs the post-Clear helper
    /// probe (`reconcileConnectionAfterConfirmedClear`); quit skips it, because it shuts
    /// the probed connection down right after the Clear (review 2026-11-01).
    func clearLocation(reconcilingConnection: Bool = true) async {
        if let locationClearTask {
            await locationClearTask.value
            return
        }
        locationOperationGeneration &+= 1
        let sessionToClear: LocationSessionIdentity?
        if let unresolvedClearSession {
            sessionToClear = unresolvedClearSession
        } else if case .ready(let session) = locationSessionCoordinator.state.connection {
            sessionToClear = session
        } else {
            sessionToClear = nil
        }
        Logger.info(
            "[Clear] Start: " + (sessionToClear.map {
                "generation=\($0.generation) transport=\($0.transport) endpoint=\($0.endpointClass)"
            } ?? "no session")
                + (unresolvedClearSession != nil ? " (retrying an unresolved Clear)" : ""),
            category: .session
        )
        let clearing = Task { @MainActor in
            defer { locationClearTask = nil }
            let producers = [simulationTask, joystickTask, joystickStartTask, locationRecoveryTask].compactMap { $0 }
            let applications = Array(applicationTasks.values)
            producers.forEach { $0.cancel() }
            applications.forEach { $0.cancel() }
            pendingApplicationModes.removeAll()
            _ = locationSessionCoordinator.cancelPendingApplication()
            simulation.isSimulating = false
            simulation.isPaused = false
            route.pausePlayback()
            locationSessionCoordinator.stopMovement()
            for application in applications {
                _ = await application.result
            }
            for producer in producers {
                await producer.value
            }
            simulationTask = nil
            routePlaybackID = nil
            joystickTask = nil
            joystickDeliveryID = nil
            locationRecoveryTask = nil
            simulation.isSimulating = false
            simulation.isPaused = false
            simulation.resetJoystick()
            joystickDirection = .zero
            route.pausePlayback()
            locationSessionCoordinator.stopMovement()

            if let error = await locationSessionCoordinator.clear(targetSession: sessionToClear) {
                let detail: String
                switch locationSessionCoordinator.state.application {
                case .failed(let reason): detail = "application failed: \(reason)"
                case .uncertain(_, let reason): detail = "application uncertain: \(reason)"
                case .lost(let reason): detail = "application lost: \(reason)"
                case .idle: detail = "application idle"
                case .applying: detail = "application applying"
                case .active: detail = "application active"
                case .clearing: detail = "application clearing"
                }
                Logger.error(
                    "[Clear] Failed with \(error); " + LogRedaction.redactingDeviceIdentifiers(detail) +
                    ". Move stays blocked until Clear succeeds.",
                    category: .session
                )
                unresolvedClearSession = sessionToClear
                // The user sees the reason the coordinator recorded, not its enum.
                if case .failed(let reason) = locationSessionCoordinator.state.application {
                    statusMessage = "Unable to clear location: \(reason). Press Clear again."
                } else {
                    statusMessage = "Unable to clear location. Press Clear again."
                }
                return
            }
            Logger.info("[Clear] Succeeded; the device is back on its real location", category: .session)
            unresolvedClearSession = nil
            simulation.currentLocation = nil
            simulation.targetLocation = nil
            routeProgress = 0
            statusMessage = "Location cleared"
        }
        locationClearTask = clearing
        await clearing.value
        if reconcilingConnection {
            await reconcileConnectionAfterConfirmedClear(of: sessionToClear)
        }
    }

    /// A loss reported while a Clear was out (a replaced helper connection, a transport
    /// change, a discovery gap) leaves the connection Lost, although the helper confirmed
    /// the Clear over that connection. After the Clear, the helper's own bounded probe
    /// decides: a live (replaced or reopened) connection is Ready again on the next
    /// generation, a dead one stays Lost. Never opens a connection.
    private func reconcileConnectionAfterConfirmedClear(of session: LocationSessionIdentity?) async {
        guard let session, unresolvedClearSession == nil,
              case .failed = locationSessionCoordinator.state.connection,
              let device = selectedDevice, device.id == session.stableDeviceID else {
            return
        }
        // The transport the device is selected on now (a replacement may have moved it).
        let transport: LocationTransport = device.connectionType == .usb ? .usb : .wifi
        let clearEpoch = locationOperationGeneration
        // The failure this probe may repair. A newer one (the health monitor, the bridge)
        // reported while the probe is out also leaves the connection failed; its epoch
        // tells them apart, so a probe answered just before the link died cannot publish
        // Ready over it.
        let failureEpoch = locationSessionCoordinator.connectionFailureEpoch
        let status = await managedLocationSessionSource.deviceConnectionStatus(
            session.stableDeviceID,
            transport: transport
        )
        guard status == .connected else {
            Logger.info(
                "[Clear] The connection stays lost after the Clear: " +
                LogRedaction.redactingDeviceIdentifiers(String(describing: status)),
                category: .session
            )
            return
        }
        // The probe awaited: a newer Clear, a Move, a re-selection or a newer loss may
        // have moved on.
        guard clearEpoch == locationOperationGeneration,
              failureEpoch == locationSessionCoordinator.connectionFailureEpoch,
              canBeginLocationOperation,
              !ownsLocationOperation,
              case .failed = locationSessionCoordinator.state.connection,
              selectedDevice?.id == session.stableDeviceID,
              (selectedDevice?.connectionType == .usb ? LocationTransport.usb : .wifi) == transport else { return }
        locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: session.stableDeviceID,
            transport: transport,
            endpointClass: .unresolved,
            generation: session.generation &+ 1
        ))
        Logger.info("[Clear] The helper's device connection is live; the connection is ready again", category: .session)
    }

    // MARK: Simulation Control

    func startSimulation() async {
        guard canStartSimulation else {
            let reason: String
            switch moveBlockedByClear {
            case .clearInProgress: reason = "a Clear is in progress"
            case .clearUnresolved: reason = "the last Clear is unconfirmed"
            case nil: reason = "the selected device is not ready"
            }
            Logger.info("[Move] Not started (\(activeMode)): \(reason)", category: .session)
            return
        }
        // A one-shot Move (Teleport, one Jump hop) still applying: a second click raced
        // it, replaced its pending request and hit the bridge's request gate.
        guard !isOneShotMoveInFlight else {
            Logger.info("[Move] Not started (\(activeMode)): a one-shot Move is still applying", category: .session)
            return
        }
        // Move is an explicit user action: it lifts a previous Stop Tunnel's block.
        if let selectedDevice {
            tunnelQuitController.resumeLocationCommands(for: selectedDevice.id)
        }

        let plan = SimulationPlanner.plan(
            mode: activeMode,
            targetLocation: targetLocation,
            currentLocation: currentLocation,
            route: currentRoute,
            speed: simulationSpeed,
            jumpIndex: jumpIndex,
            stepMeters: routeStepMeters
        )
        let planKind: String
        switch plan {
        case .teleport where activeMode == .jump && autoJump && !currentRoute.isEmpty: planKind = "autoJump"
        case .teleport: planKind = "teleport"
        case .route(let points): planKind = "route(\(points.count) points)"
        case .joystick: planKind = "joystick"
        case .failed(let message): planKind = "failed(\(message))"
        }
        Logger.info("[Move] \(activeMode): plan \(planKind)", category: .session)

        switch plan {
        case .teleport where activeMode == .jump && autoJump && !currentRoute.isEmpty:
            // A second Move while the engine starts is the double click, not a restart.
            guard !isMovementEngineRunning else {
                Logger.info("[Move] Not started: the movement engine is already running", category: .session)
                return
            }
            await playAutoJump()
        case .teleport(let coordinate):
            // A one-shot Move replaces any engine still running (latest intent wins)
            // instead of racing it on the device.
            if isMovementEngineRunning { await stopSimulation() }
            isPaused = false
            isOneShotMoveInFlight = true
            defer { isOneShotMoveInFlight = false }
            await applyPlannedLocation(coordinate, mode: activeMode)
        case .route(let points):
            guard !isMovementEngineRunning else {
                Logger.info("[Move] Not started: the movement engine is already running", category: .session)
                return
            }
            await playRoute(points)
        case .joystick(let start):
            await startJoystick(at: start)
        case .failed(let message):
            lastError = message
            statusMessage = message
        }
    }

    @discardableResult
    private func applyPlannedLocation(
        _ coordinate: LocationCoordinate,
        mode: AppMode
    ) async -> LocationInjectionReceipt? {
        guard canBeginLocationOperation else {
            Logger.info("[Apply] Skipped (\(mode)): a Clear is in progress or unresolved", category: .session)
            return nil
        }
        let operationGeneration = locationOperationGeneration
        let locationMode = mode.locationMode ?? .teleport
        locationSessionCoordinator.select(coordinate, mode: locationMode)

        guard prepareLocationSessionIfNeeded() else {
            Logger.info("[Apply] Skipped (\(mode)): no ready location session", category: .session)
            isSimulating = false
            statusMessage = "No ready location session"
            return nil
        }

        // The caller's own request: a cancelled step must not cancel a newer one.
        var ownRequestID: UUID?
        do {
            let request = try locationSessionCoordinator.beginApplication()
            ownRequestID = request.id
            pendingApplicationModes[request.id] = mode

            // Device-readiness gate before injection: with no mounted
            // personalized Developer Disk Image, DVT injection completes
            // without error but silently does not apply (live-proven
            // 2026-10-31 on iOS 27.2). A mount failure is a preparation
            // failure, not a connection loss — it must surface through the
            // honest rejection path below, never as connection state.
            if let ddiPreparer {
                guard let preparationUDID = selectedDevice?.id else {
                    throw DeviceError.deviceNotFound
                }
                do {
                    try await ddiPreparer.ensureMounted(udid: preparationUDID)
                } catch {
                    Logger.error("[Preparation] DDI mount failed: \(error)", category: .device)
                    throw error
                }
            }

            // Stop, Clear or a mode change during the mount check: nothing was sent, so
            // nothing may be sent now (the phone used to move once more after Stop).
            if Task.isCancelled || locationClearTask != nil
                || operationGeneration != locationOperationGeneration {
                Logger.info("[Apply] Not sent (\(mode)): Stop, Clear or a mode change during preparation", category: .session)
                _ = locationSessionCoordinator.cancelPendingApplication(requestID: request.id)
                pendingApplicationModes.removeValue(forKey: request.id)
                return nil
            }

            let application = Task { try await locationInjector.apply(request) }
            applicationTasks[request.id] = application
            defer { applicationTasks.removeValue(forKey: request.id) }
            let receipt = try await withTaskCancellationHandler {
                try await application.value
            } onCancel: {
                application.cancel()
            }
            guard locationClearTask == nil,
                  operationGeneration == locationOperationGeneration else {
                Logger.info("[Apply] Receipt dropped (\(mode)): Clear or a newer operation started", category: .session)
                _ = locationSessionCoordinator.cancelPendingApplication(requestID: request.id)
                pendingApplicationModes.removeValue(forKey: request.id)
                return nil
            }
            if Task.isCancelled {
                // Stop or a mode change cancelled the producer mid round trip, but the
                // helper finished the command: an applied receipt is what the phone now
                // holds, so it is committed as held. Clear (above) still wins. Returning
                // nil ends the producer without resuming movement.
                if case .applied = receipt.outcome,
                   locationSessionCoordinator.accept(receipt) == nil {
                    Logger.info("[Apply] Cancelled after the device applied it (\(mode)); holding that point", category: .session)
                    commitAcknowledgedReceipt(receipt)
                } else {
                    Logger.info("[Apply] Cancelled (\(mode)); receipt outcome \(receipt.outcome)", category: .session)
                    _ = locationSessionCoordinator.cancelPendingApplication(requestID: request.id)
                    pendingApplicationModes.removeValue(forKey: request.id)
                }
                return nil
            }
            let result = locationSessionCoordinator.accept(receipt)

            if result == nil {
                commitAcknowledgedReceipt(receipt)
                return receipt
            }
            if result == .noPendingRequest,
               locationSessionCoordinator.state.lastAcknowledgedReceipt?.requestID == receipt.requestID {
                commitAcknowledgedReceipt(receipt)
                return receipt
            }
            if result == .receiptNotApplied {
                Logger.info(
                    "[Apply] Queued (\(mode)); awaiting acknowledgement",
                    category: .session,
                    repeatKey: "AppState.apply.queued"
                )
                isSimulating = currentLocation != nil
                statusMessage = "Location update queued; awaiting acknowledgement"
                return nil
            }

            Logger.error(
                "[Apply] Receipt rejected (\(mode)): \(String(describing: result)); " +
                "receipt generation=\(receipt.sessionGeneration) transport=\(receipt.transport) " +
                "endpoint=\(receipt.endpointClass) outcome=\(receipt.outcome)",
                category: .session
            )
            pendingApplicationModes.removeValue(forKey: request.id)
            isSimulating = currentLocation != nil
            statusMessage = "Location update rejected: \(String(describing: result))"
            return nil
        } catch {
            guard locationClearTask == nil,
                  operationGeneration == locationOperationGeneration else {
                Logger.info(
                    "[Apply] Error ignored (\(mode)): Clear or a newer operation started: " +
                    LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                    category: .session
                )
                return nil
            }
            if error is CancellationError {
                // Cancelled before the command reached the device (Stop, mode change,
                // loss): nothing was applied, so the previous truth stands.
                Logger.info("[Apply] Cancelled before reaching the device (\(mode))", category: .session)
                if let ownRequestID {
                    _ = locationSessionCoordinator.cancelPendingApplication(requestID: ownRequestID)
                    pendingApplicationModes.removeValue(forKey: ownRequestID)
                }
                return nil
            }
            Logger.error(
                "[Apply] Failed (\(mode)): " + LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .session,
                repeatKey: "AppState.apply.failed"
            )
            // Only this caller's own request; a newer one may already be pending.
            if let requestID = ownRequestID ?? {
                if case .applying(let current, _) = locationSessionCoordinator.state.application { return current }
                return nil
            }() {
                _ = locationSessionCoordinator.reject(requestID: requestID, error: error)
                pendingApplicationModes.removeValue(forKey: requestID)
            }
            isSimulating = currentLocation != nil
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func prepareLocationSessionIfNeeded() -> Bool {
        if case .ready = locationSessionCoordinator.state.connection {
            return true
        }
        guard let selectedDevice else { return false }

        let transport: LocationTransport = selectedDevice.connectionType == .usb ? .usb : .wifi
        let endpointClass: LocationEndpointClass = .unresolved
        let lastGeneration = locationSessionCoordinator.state.lastAcknowledgedReceipt?.sessionGeneration ?? 0
        locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: selectedDevice.id,
            transport: transport,
            endpointClass: endpointClass,
            generation: lastGeneration + 1
        ))
        return true
    }

    /// Start or adopt the managed helper and restore the single session matching
    /// the currently selected device. Failure leaves the existing state unchanged.
    @discardableResult
    func restoreManagedLocationSessionFromSource() async -> Bool {
        do {
            try await managedLocationSessionSource.start()
        } catch {
            Logger.error(
                "[AppState] Managed helper unavailable during session restoration: \(error.localizedDescription)",
                category: .device
            )
            return false
        }

        guard let selectedDevice else { return false }
        return await restorePublishedManagedLocationSession(for: selectedDevice)
    }

    private func restorePublishedManagedLocationSession(for device: Device) async -> Bool {
        // Adopting the helper's record is for a relaunch or Preserve, when this app
        // session holds no location of its own. Run on every discovery sync, it dropped
        // the in-flight hop and set Movement to Idle in every moving mode (live
        // 2026-11-01).
        guard !ownsLocationOperation else { return false }
        // A Clear during the probe or adoption below makes the record read here stale:
        // adopting it showed a held location the phone no longer had.
        let clearEpoch = locationOperationGeneration
        guard let helperID = managedLocationSessionSource.adoptedHelperID else {
            return false
        }
        let matches = managedLocationSessionSource.adoptedHelperSessions.filter {
            $0.matches(deviceID: device.id)
        }
        guard matches.count == 1, let session = matches.first else {
            if matches.count > 1 {
                Logger.error(
                    "[AppState] Refusing ambiguous managed helper sessions for selected device",
                    category: .device
                )
            }
            return false
        }
        // The record can outlive a silently dropped link: restore only a location the
        // helper's connection still carries.
        let transport: LocationTransport = device.connectionType == .usb ? .usb : .wifi
        let status = await managedLocationSessionSource.deviceConnectionStatus(device.id, transport: transport)
        guard status == .connected else {
            Logger.info("[AppState] Not restoring a recorded location: \(status)", category: .device)
            return false
        }
        // The probe awaited; this session may have started its own operation meanwhile,
        // or run a whole Clear (which leaves it owning nothing again).
        guard !ownsLocationOperation, clearEpoch == locationOperationGeneration else { return false }
        return await restoreManagedHelperSession(
            session,
            helperID: helperID,
            for: device,
            expectedClearEpoch: clearEpoch
        )
    }

    /// This app session is applying, holding, clearing or moving a location itself.
    private var ownsLocationOperation: Bool {
        if simulationTask != nil || joystickTask != nil || joystickStartTask != nil
            || locationClearTask != nil || !applicationTasks.isEmpty {
            return true
        }
        switch locationSessionCoordinator.state.application {
        case .applying, .active, .clearing:
            return true
        case .idle, .uncertain, .lost, .failed:
            return false
        }
    }

    /// Restore provider-acknowledged held truth from an authenticated managed helper.
    /// This never resumes a route or joystick engine after relaunch.
    @discardableResult
    func restoreManagedHelperSession(
        _ session: ManagedLocationHelperSession,
        helperID: UUID,
        for device: Device,
        expectedClearEpoch: UInt64? = nil
    ) async -> Bool {
        guard selectedDevice?.id == device.id,
              session.matches(deviceID: device.id),
              let receipt = session.locationReceipt(helperID: helperID) else {
            return false
        }
        // An operation this session owns makes the record stale: refuse before the adapter
        // call, which writes the receipt into the adapter's generation tracker (a refusal
        // after it left adapter and coordinator disagreeing, review 2026-11-01). The caller
        // that read the record passes the Clear counter it saw then.
        let clearEpoch = expectedClearEpoch ?? locationOperationGeneration
        guard clearEpoch == locationOperationGeneration, !ownsLocationOperation else {
            Logger.info("[AppState] Not restoring a recorded location: this session owns a location operation", category: .device)
            return false
        }
        do {
            try await locationInjector.adoptManagedSession(
                receipt: receipt,
                stableDeviceID: device.id
            )
        } catch {
            Logger.error(
                "[AppState] Refusing managed session rejected by location adapter: \(error.localizedDescription)",
                category: .device
            )
            return false
        }
        // The adapter awaited: a Clear or a Move begun meanwhile owns the location now.
        guard clearEpoch == locationOperationGeneration, !ownsLocationOperation else {
            Logger.info("[AppState] Not restoring a recorded location: a Clear or Move started meanwhile", category: .device)
            return false
        }

        let identity = LocationSessionIdentity(
            stableDeviceID: device.id,
            transport: receipt.transport,
            endpointClass: receipt.endpointClass,
            generation: receipt.sessionGeneration
        )
        guard locationSessionCoordinator.adoptHeldSession(
            identity: identity,
            receipt: receipt
        ) == nil else {
            return false
        }

        simulation.currentLocation = receipt.coordinate
        simulation.targetLocation = receipt.coordinate
        simulation.isPaused = false
        simulation.isSimulating = true
        statusMessage = "Restored held location from managed helper"
        return true
    }

    private func commitAcknowledgedReceipt(_ receipt: LocationInjectionReceipt) {
        // A success ends any run of repeated apply failures: write its count now.
        Logger.endRepeats(key: "AppState.apply.failed", category: .session)
        Logger.endRepeats(key: "AppState.apply.queued", category: .session)
        guard let mode = pendingApplicationModes.removeValue(forKey: receipt.requestID) else { return }
        simulation.currentLocation = receipt.coordinate
        simulation.targetLocation = receipt.coordinate
        simulation.isPaused = false
        simulation.isSimulating = true

        if mode == .jump {
            jumpIndex = SimulationPlanner.jumpIndexAfterAcknowledging(
                currentIndex: jumpIndex,
                routeCount: currentRoute.count
            )
        }
    }

    var requiresLocationQuitDecision: Bool {
        hasCoordinatorHeldLocation || managedLocationSessionSource.hasRecordedHeldSessions
    }

    /// A location this app session applied or restored (as opposed to one only listed
    /// in the helper record, e.g. before a Preserve relaunch found its device).
    private var hasCoordinatorHeldLocation: Bool {
        locationSessionCoordinator.state.lastAcknowledgedReceipt != nil
            || locationSessionCoordinator.state.application.isActive
            || !canBeginLocationOperation
    }

    func prepareForQuitWithoutLocation() async -> LocationQuitPreparationResult {
        await stopSimulation()
        await locationBridge.stopHeldSimulation()
        do {
            try await managedLocationSessionSource.shutdownHelper()
        } catch {
            return .failed("Managed helper shutdown failed: \(error.localizedDescription)")
        }
        return await stopTunnelBeforeTerminating()
    }

    /// Quit must leave nothing running unless the user chose Preserve: the tunnel is
    /// stopped and awaited here, before AppKit is allowed to exit.
    private func stopTunnelBeforeTerminating() async -> LocationQuitPreparationResult {
        switch await tunnelQuitController.stopTunnelForQuit() {
        case .stopped:
            return .terminate
        case .failed(let reason):
            return .failed("The device tunnel did not stop: \(reason)")
        }
    }

    func prepareForQuit(_ choice: LocationQuitChoice) async -> LocationQuitPreparationResult {
        switch choice {
        case .cancel:
            return .cancel

        case .preserveAndQuit:
            await stopSimulation()
            if !hasCoordinatorHeldLocation, managedLocationSessionSource.hasRecordedHeldSessions {
                // Preserved by an earlier session and not restored yet: leave the helper
                // and its tunnel exactly as they are.
                tunnelQuitController.retainTunnelForPreservedLocation()
                return .terminate
            }
            do {
                try await managedLocationSessionSource.start()
                try await managedLocationSessionSource.refreshAdoptedHelperSessions()
            } catch {
                return .failed("Unable to verify managed location ownership: \(error.localizedDescription)")
            }

            guard let selectedDevice,
                  let helperID = managedLocationSessionSource.adoptedHelperID,
                  let currentReceipt = locationSessionCoordinator.state.lastAcknowledgedReceipt else {
                return .failed("No acknowledged managed location session is available to preserve")
            }
            let matches = managedLocationSessionSource.adoptedHelperSessions.filter {
                $0.matches(deviceID: selectedDevice.id)
            }
            guard matches.count == 1,
                  let persistedReceipt = matches[0].locationReceipt(helperID: helperID),
                  persistedReceipt.requestID == currentReceipt.requestID,
                  persistedReceipt.sessionGeneration == currentReceipt.sessionGeneration,
                  persistedReceipt.coordinate == currentReceipt.coordinate,
                  persistedReceipt.transport == currentReceipt.transport,
                  persistedReceipt.actualChannel == currentReceipt.actualChannel,
                  persistedReceipt.endpointClass == currentReceipt.endpointClass else {
                return .failed("Managed helper ownership does not match the acknowledged location session")
            }
            // The helper process holds the location over its own connection; keep the
            // tunnel bookkeeping as-is so a relaunch adopts both again.
            tunnelQuitController.retainTunnelForPreservedLocation()
            return .terminate

        case .clearAndQuit:
            if hasCoordinatorHeldLocation {
                // No post-Clear connection probe: the helper is shut down next.
                await clearLocation(reconcilingConnection: false)
                guard locationSessionCoordinator.state.lastAcknowledgedReceipt == nil,
                      !locationSessionCoordinator.state.application.isActive,
                      canBeginLocationOperation else {
                    return .failed(lastError ?? "Location Clear was not acknowledged")
                }
            } else {
                await stopSimulation()
            }
            // For a session this app never restored, stopping the helper ends its held
            // DVT session: that is the real Clear.
            do {
                try await managedLocationSessionSource.shutdownHelper()
            } catch {
                return .failed("Location cleared, but managed helper shutdown failed: \(error.localizedDescription)")
            }
            guard !managedLocationSessionSource.hasRecordedHeldSessions else {
                return .failed("The location helper is still holding a location; it could not be cleared")
            }
            return await stopTunnelBeforeTerminating()
        }
    }

    func pauseSimulation() {
        simulation.pauseSimulation()
        locationSessionCoordinator.pauseMovement()
        route.pausePlayback()
    }

    func resumeSimulation() {
        guard canBeginLocationOperation,
              locationSessionCoordinator.state.application.isActive else { return }
        simulation.resumeSimulation()
        if let mode = activeMode.locationMode {
            locationSessionCoordinator.beginMovement(mode)
        }
        route.resumePlayback()
    }

    func stopSimulation() async {
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil
        routePlaybackID = nil
        joystickTask = nil

        isPaused = false
        isSimulating = false
        joystickDirection = .zero
        locationSessionCoordinator.completeMovement()
        if route.playbackState.isActive {
            route.pausePlayback()
        }
    }

    // MARK: Route Playback

    func loadRoute(from coordinates: [LocationCoordinate]) {
        route.loadRoute(from: coordinates)
    }

    /// A route is playing or paused mid-route: its stops must not change under it.
    private var isRouteMovementActive: Bool {
        switch locationSessionCoordinator.state.movement {
        case .moving, .paused:
            return simulationTask != nil || isPaused
        case .idle, .completed:
            return false
        }
    }

    /// Updates only local planning state. Device injection remains exclusively in
    /// `startSimulation`, which is invoked by the explicit Move action.
    func stageLocation(_ coordinate: LocationCoordinate, for mode: AppMode) {
        guard coordinate.isValid else { return }
        targetLocation = coordinate
        if let locationMode = mode.locationMode {
            locationSessionCoordinator.select(coordinate, mode: locationMode)
        }

        switch mode {
        case .teleport, .settings:
            loadRoute(from: [coordinate])
        case .jump:
            // Adding a stop never interrupts a Jump: each Move applies one hop.
            // (`isSimulating` is true after ANY applied location, so the old guard
            // silently dropped every stop clicked after a Teleport.) A route that
            // another mode is playing must not change under it.
            guard !isRouteMovementActive else { return }
            guard currentRoute.count < mode.maxStops else {
                statusMessage = "Jump holds 12 stops"
                return
            }
            addRouteWaypoint(coordinate)
        case .twospot:
            // Two endpoints (PRODUCT_REQUIREMENTS 3.3): the first click is the start,
            // the second the destination; later clicks move the destination.
            guard !isRouteMovementActive else { return }
            if currentRoute.count >= 2 {
                route.removeLastWaypoint()
            }
            addRouteWaypoint(coordinate)
            if currentRoute.count >= 2 {
                statusMessage = "Destination spot set"
            } else if currentLocation != nil {
                statusMessage = "Spot set: Move travels there from the current location, or click a second spot"
            } else {
                statusMessage = "Start spot set: click the destination"
            }
        case .route:
            guard !isRouteMovementActive else { return }
            guard currentRoute.count < mode.maxStops else {
                statusMessage = "Multi-spot holds 24 stops"
                return
            }
            addRouteWaypoint(coordinate)
        case .joystick:
            routeProgress = 0
            statusMessage = String(
                format: "Start set: %.4f, %.4f",
                coordinate.latitude,
                coordinate.longitude
            )
        }

        isPaused = false
    }

    /// Reverses the planned route and updates the selected destination without
    /// adding, replacing, or removing any waypoint.
    func reverseRoute(for mode: AppMode) {
        route.reverseRoute()
        guard let destination = currentRoute.last else { return }
        targetLocation = destination
        if let locationMode = mode.locationMode {
            locationSessionCoordinator.select(destination, mode: locationMode)
        }
        isPaused = false
    }

    func addRouteWaypoint(_ coordinate: LocationCoordinate) {
        guard route.addWaypoint(coordinate) else { return }
        targetLocation = coordinate
        statusMessage = "Spot \(currentRoute.count) added"
    }

    func removeRouteWaypoint(at index: Int) {
        guard route.removeWaypoint(at: index) else { return }
        targetLocation = currentRoute.last
    }

    func moveRouteWaypoint(from source: Int, to destination: Int) {
        route.moveWaypoint(from: source, to: destination)
    }

    func removeLastRouteWaypoint() {
        guard let remaining = route.removeLastWaypoint() else { return }
        targetLocation = currentRoute.last
        statusMessage = remaining == 0 ? "All spots cleared" : "\(remaining) spots remaining"
    }

    func clearRoute() {
        simulationTask?.cancel()
        simulationTask = nil
        route.clearRoute()
        statusMessage = "Spots cleared"
    }


    func importRoute(from url: URL) {
        do {
            let count = try route.importRoute(from: url)
            targetLocation = currentRoute.last
            lastError = nil
            statusMessage = "Imported \(count) points"
        } catch RouteLibraryError.emptyRoute {
            lastError = "GPX file needs at least two points"
            statusMessage = lastError
        } catch {
            lastError = error.localizedDescription
            statusMessage = lastError
        }
    }

    func startRoutePlayback() async {
        guard canStartSimulation else { return }

        switch SimulationPlanner.plan(
            mode: .route,
            targetLocation: targetLocation,
            currentLocation: currentLocation,
            route: currentRoute,
            speed: simulationSpeed,
            stepMeters: routeStepMeters
        ) {
        case .route(let points):
            await playRoute(points)
        case .failed(let message):
            lastError = message
            statusMessage = message
        default:
            lastError = "No route loaded"
            statusMessage = lastError
        }
    }

    private func playRoute(_ points: [LocationCoordinate]) async {
        let operationGeneration = locationOperationGeneration
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil

        isPaused = false
        isSimulating = false
        route.beginAcknowledgedPlayback()
        await locationBridge.setQueueStrategy(.sequential)
        guard locationClearTask == nil,
              operationGeneration == locationOperationGeneration else { return }

        let mode = activeMode
        let movementMode = mode.locationMode ?? .multiSpot
        // Frozen with the step distance planned at Move: changing the rate mid-route
        // changed the travelled speed (review 2026-11-01).
        let interval = 1.0 / max(updateFrequencyHz, 1)
        let playbackID = UUID()
        routePlaybackID = playbackID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.route.beginAcknowledgedPlayback()
                for (index, coordinate) in points.enumerated() {
                    guard !Task.isCancelled else { return }
                    while self.isPaused && !Task.isCancelled {
                        await self.routeDelay(0.1)
                    }
                    guard !Task.isCancelled else { return }

                    let stepStarted = Date()
                    guard await self.applyPlannedLocation(coordinate, mode: mode) != nil else {
                        self.isSimulating = self.currentLocation != nil
                        self.locationSessionCoordinator.pauseMovement()
                        self.route.pausePlayback()
                        return
                    }
                    if index == 0 {
                        self.locationSessionCoordinator.beginMovement(movementMode)
                    }
                    self.route.acknowledgeWaypoint(at: index, totalCount: points.count)

                    // One point per update interval, counted from when the step began, so
                    // the device round trip does not slow the shown travel speed.
                    let remaining = interval - Date().timeIntervalSince(stepStarted)
                    await self.routeDelay(max(remaining, 0))
                }
            } while self.loopRoute && !Task.isCancelled

            guard !Task.isCancelled else { return }
            self.isSimulating = false
            self.locationSessionCoordinator.completeMovement()
            self.route.completeAcknowledgedPlayback()
            self.statusMessage = "Route playback complete"
        }
        simulationTask = task
        await task.value
        if routePlaybackID == playbackID {
            simulationTask = nil
            routePlaybackID = nil
        }
    }

    /// Auto jump (owner decision 2026-11-01): one Move jumps through every remaining
    /// stop, holding each for `autoJumpPauseSeconds`. The index still advances only on
    /// an acknowledged injection; the last stop holds; Stop ends it and holds.
    private func playAutoJump() async {
        let operationGeneration = locationOperationGeneration
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil
        isPaused = false
        guard locationClearTask == nil,
              operationGeneration == locationOperationGeneration else { return }

        // The stops this run jumps through; editing them, leaving Jump or turning Auto
        // jump off ends the run (holding the last applied stop).
        let hops = currentRoute
        let playbackID = UUID()
        routePlaybackID = playbackID
        autoJumpPlaybackID = playbackID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var engaged = false
            // The engine's own position; anything else moving the index ends the run.
            var expectedIndex = self.jumpIndex
            let stillWanted = {
                self.autoJump && self.activeMode == .jump && self.currentRoute == hops
                    && self.jumpIndex == expectedIndex
            }
            while !Task.isCancelled, stillWanted(), self.jumpIndex < hops.count {
                while self.isPaused && !Task.isCancelled {
                    await self.routeDelay(0.1)
                }
                guard !Task.isCancelled, stillWanted() else { break }
                let hop = hops[self.jumpIndex]
                guard await self.applyPlannedLocation(hop, mode: .jump) != nil else {
                    self.isSimulating = self.currentLocation != nil
                    self.locationSessionCoordinator.pauseMovement()
                    return
                }
                expectedIndex += 1
                if !engaged {
                    self.locationSessionCoordinator.beginMovement(.jumpTeleport)
                    engaged = true
                }
                guard self.jumpIndex < hops.count else { break }
                await self.routeDelay(self.autoJumpPauseSeconds)
            }
            guard !Task.isCancelled else { return }
            if engaged {
                self.locationSessionCoordinator.completeMovement()
            }
            if self.jumpIndex >= hops.count {
                self.statusMessage = "All jumps done; holding the last stop"
            }
        }
        simulationTask = task
        await task.value
        if routePlaybackID == playbackID {
            simulationTask = nil
            routePlaybackID = nil
        }
        if autoJumpPlaybackID == playbackID {
            autoJumpPlaybackID = nil
        }
    }

    /// Ends a running Auto jump and holds the last applied stop.
    private func endAutoJumpIfRunning() {
        guard let playbackID = autoJumpPlaybackID, routePlaybackID == playbackID else { return }
        simulationTask?.cancel()
        simulationTask = nil
        routePlaybackID = nil
        autoJumpPlaybackID = nil
        isPaused = false
        // Completed only if a hop was actually reached (nothing moved otherwise).
        switch locationSessionCoordinator.state.movement {
        case .moving, .paused:
            locationSessionCoordinator.completeMovement()
        case .idle, .completed:
            break
        }
    }

    // MARK: Joystick Mode

    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction

        // A location applied earlier (isSimulating) must not stop the stick from
        // engaging; only a running or starting joystick loop does.
        let engaged = hypot(direction.x, direction.y) >= JoystickMovement.deadZone
        guard engaged,
              joystickTask == nil,
              joystickStartTask == nil,
              !isStartingJoystick,
              simulationTask == nil,
              canStartSimulation,
              activeMode == .joystick,
              (targetLocation ?? currentLocation) != nil else {
            return
        }

        joystickStartTask = Task { @MainActor [weak self] in
            await self?.startSimulation()
            self?.joystickStartTask = nil
        }
    }

    private func startJoystick(at start: LocationCoordinate) async {
        // Single flight: the Move button, the stick and the arrow keys can all start it.
        guard !isStartingJoystick else { return }
        isStartingJoystick = true
        defer { isStartingJoystick = false }
        let engagementID = joystickEngagementID
        let operationGeneration = locationOperationGeneration
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil
        routePlaybackID = nil
        joystickTask = nil
        joystickDeliveryID = nil

        isPaused = false
        isSimulating = false
        await locationBridge.setQueueStrategy(.latestWins)
        guard locationClearTask == nil,
              operationGeneration == locationOperationGeneration else { return }

        guard await applyPlannedLocation(start, mode: .joystick) != nil,
              operationGeneration == locationOperationGeneration,
              engagementID == joystickEngagementID,
              locationClearTask == nil,
              locationSessionCoordinator.state.application.isActive else {
            return
        }
        locationSessionCoordinator.beginMovement(.joystick)

        let deliveryID = UUID()
        joystickDeliveryID = deliveryID
        let interval: TimeInterval = 1.0 / max(updateFrequencyHz, 1)
        joystickTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.joystickDeliveryID == deliveryID {
                guard !self.isPaused else {
                    await self.routeDelay(interval)
                    continue
                }
                var direction = self.joystickDirection
                guard hypot(direction.x, direction.y) >= JoystickMovement.deadZone else {
                    await self.routeDelay(interval)
                    continue
                }
                if self.smoothTurns {
                    direction = self.smoothedDirection(direction)
                }
                guard let acknowledged = self.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate else {
                    await self.routeDelay(interval)
                    continue
                }
                let next = JoystickMovement.nextCoordinate(
                    from: acknowledged,
                    direction: direction,
                    speedMetersPerSecond: self.effectiveMetersPerSecond,
                    deltaTime: interval
                )
                if next != acknowledged {
                    let receipt = await self.applyPlannedLocation(next, mode: .joystick)
                    if receipt == nil,
                       case .ready = self.locationSessionCoordinator.state.connection {
                        await self.routeDelay(interval)
                        continue
                    }
                    guard self.locationSessionCoordinator.state.connection.isReady else { break }
                }
                await self.routeDelay(interval)
            }
            if self.joystickDeliveryID == deliveryID {
                self.joystickTask = nil
                self.joystickDeliveryID = nil
            }
        }
    }

    func disengageJoystick() {
        // A start still in flight applies its start point but does not engage.
        joystickEngagementID &+= 1
        joystickTask?.cancel()
        joystickTask = nil
        joystickDeliveryID = nil
        if case .applying(let requestID, _) = locationSessionCoordinator.state.application {
            _ = locationSessionCoordinator.cancelPendingApplication(requestID: requestID)
            pendingApplicationModes.removeValue(forKey: requestID)
        }
        isSimulating = false
        isPaused = false
        simulation.resetJoystick()
        joystickDirection = .zero
        locationSessionCoordinator.completeMovement()
        statusMessage = "Joystick disengaged; location held"
    }

    var effectiveMetersPerSecond: Double {
        simulation.effectiveMetersPerSecond
    }

    // These forward to `SimulationSpeed`, which now owns the preset tables. They remain as
    // methods so existing call sites and tests keep working; they will be removed when
    // AppState is decomposed and views read the speed data directly.
    func mockMetersPerSecond(for speed: SimulationSpeed) -> Double {
        speed.presetMetersPerSecond
    }

    // MARK: Speed Control

    func setSpeed(_ speed: SimulationSpeed) {
        simulation.setSpeed(speed)
    }

    func copyCoordinates() {
        let location = targetLocation ?? currentLocation
        let text = location.map { String(format: "%.6f, %.6f", $0.latitude, $0.longitude) } ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copiedFeedback = false
        }
    }

    private func smoothedDirection(_ raw: CGPoint) -> CGPoint {
        simulation.smoothedDirection(raw)
    }

    func submitLocationBridgeEvent(_ event: LocationBridgeEvent) {
        handleLocationBridgeEvent(event, heldSubprocessSource: false)
    }

    private func handleLocationBridgeEvent(
        _ event: LocationBridgeEvent,
        heldSubprocessSource: Bool
    ) {
        switch event {
        case .sessionReady(let identity):
            locationSessionCoordinator.connectionReady(identity)
        case .sessionLost(_, let reason):
            handleLocationSessionLoss(.bridgeTerminated(exitCode: -1), reason: reason)
        case .processTerminated(let exitCode):
            if heldSubprocessSource {
                handleLocationSessionLoss(.heldProcessExited)
            } else {
                handleLocationSessionLoss(.bridgeTerminated(exitCode: exitCode))
            }
        case .receipt(let receipt):
            guard locationClearTask == nil else { return }
            let result = locationSessionCoordinator.accept(receipt)
            if result == nil {
                commitAcknowledgedReceipt(receipt)
            }
        }
    }

    private func handleLocationSessionLoss(
        _ event: LocationSessionLossEvent,
        reason: String? = nil
    ) {
        // The device may have rebooted (which unmounts the Developer Disk Image):
        // check the mount again before the next injection. Discovery clears the
        // selection before reporting the lost device, so prefer the event's ID.
        let lostDeviceID: String? = {
            if case .selectedDeviceLost(let stableDeviceID) = event { return stableDeviceID }
            return selectedDevice?.id
        }()
        if let ddiPreparer, let lostDeviceID {
            Task { await ddiPreparer.forget(udid: lostDeviceID) }
        }
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil
        routePlaybackID = nil
        joystickTask = nil
        joystickDeliveryID = nil
        isSimulating = false
        isPaused = false
        simulation.resetJoystick()
        joystickDirection = .zero

        if case .tunnelStoppedByUser = event {
            locationSessionCoordinator.stopMovement()
            locationRecoveryTask?.cancel()
            locationRecoveryTask = nil
            // The location ended only if the helper confirmed it closed the connection
            // the location was held on; otherwise saying "real location" would be false.
            let heldDevice = selectedDevice?.id
            guard let heldDevice,
                  let close = tunnelQuitController.pendingHelperStop(for: heldDevice) else {
                if locationSessionCoordinator.state.lastAcknowledgedReceipt != nil {
                    locationSessionCoordinator.connectionLost(reason: event.reason)
                }
                return
            }
            Task { @MainActor [weak self] in
                let ended = await close.value
                guard let self else { return }
                if ended {
                    self.locationSessionCoordinator.locationEndedByStop()
                    self.simulation.currentLocation = nil
                    self.statusMessage = "Tunnel stopped — the device is back on its real location"
                } else {
                    self.locationSessionCoordinator.connectionLost(
                        reason: "Tunnel stopped, but the device connection did not confirm it closed"
                    )
                }
            }
            return
        } else if let reason {
            locationSessionCoordinator.connectionLost(reason: reason)
        } else {
            locationSessionCoordinator.submit(event)
        }

        guard event.startsAutomaticRecovery else {
            locationRecoveryTask?.cancel()
            locationRecoveryTask = nil
            return
        }
        guard automaticRecoveryEnabled else { return }
        startLocationRecovery { [weak self] _, previous in
            guard let self, let previous else {
                throw LocationSessionTransitionError.noReadySession
            }
            return try await self.device.establishRecoverySession(previous: previous)
        }
    }

    func startLocationRecovery(
        strategy: ReconnectionStrategy? = nil,
        establishSession: @escaping @MainActor (Int, LocationSessionIdentity?) async throws -> LocationSessionIdentity
    ) {
        guard canBeginLocationOperation,
              locationSessionCoordinator.state.desiredLocation != nil,
              locationRecoveryTask == nil else { return }
        let strategy = strategy ?? reliabilityManager.strategy
        locationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.locationSessionCoordinator.recover(
                strategy: strategy,
                establishSession: establishSession
            )
            if let result, result != .recoveryCancelled {
                self.lastError = String(describing: result)
            }
            self.locationRecoveryTask = nil
        }
    }
}

// MARK: - Connection Status

/// A Clear that keeps Move blocked: one still running, or one PathChanger could not confirm.
enum LocationClearBlock: Equatable {
    case clearInProgress
    case clearUnresolved
}

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error

    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .error: return .red
        }
    }

    var text: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}
