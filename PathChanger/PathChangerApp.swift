//
//  PathChangerApp.swift
//  PathChanger
//
//  iOS 17+ Location Injection macOS Application
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
        let active: LocationInjectionReceipt? = { if case .active(let value) = state.application { return value }; return nil }()
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
            applicationLabel = Self.localizedStatus("location.status.application.applying", comment: "Application applying")
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
            locationInjector: LocationInjectorFactory.make()
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
        set { simulation.activeMode = newValue }
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
        set { route.autoJump = newValue }
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
    @Published var lastError: String?
    @Published var statusMessage: String?

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
    var tunnelHealthMonitor: TunnelHealthMonitor { device.tunnelHealthMonitor }

    // MARK: Private
    private let locationBridge: DevLocationBridge
    private let locationInjector: any LocationInjecting
    private let managedLocationSessionSource: any ManagedLocationSessionSource
    private let routeDelay: @MainActor @Sendable (TimeInterval) async -> Void
    private var pendingApplicationModes: [UUID: AppMode] = [:]
    private var applicationTasks: [UUID: Task<LocationInjectionReceipt, Error>] = [:]
    @Published private var locationClearTask: Task<Void, Never>?
    @Published private var unresolvedClearSession: LocationSessionIdentity?
    private var locationOperationGeneration: UInt64 = 0
    private var simulationTask: Task<Void, Never>?
    private var routePlaybackID: UUID?
    private var joystickTask: Task<Void, Never>?
    private var joystickDeliveryID: UUID?
    private let automaticRecoveryEnabled: Bool
    private var locationRecoveryTask: Task<Void, Never>?
    private var bridgeEventTask: Task<Void, Never>?
    private var persistentBridgeEventTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        canBeginLocationOperation && simulation.canStartSimulation
    }

    private var canBeginLocationOperation: Bool {
        locationClearTask == nil && unresolvedClearSession == nil
    }

    var simulationStatusText: String {
        simulation.statusText
    }

    // MARK: Initialization

    init(
        startBackgroundServices: Bool = true,
        locationInjector: (any LocationInjecting)? = nil,
        managedLocationSessionSource: (any ManagedLocationSessionSource)? = nil,
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
        self.routeDelay = routeDelay
        self.automaticRecoveryEnabled = effectiveBackgroundServices
        self.errorHandler = sharedErrorHandler
        self.locationSessionCoordinator = sessionCoordinator
        self.device = DeviceStateManager(startBackgroundServices: effectiveBackgroundServices)
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

    func clearLocation() async {
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
        let clearing = Task { @MainActor in
            defer { locationClearTask = nil }
            let producers = [simulationTask, joystickTask, locationRecoveryTask].compactMap { $0 }
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
                unresolvedClearSession = sessionToClear
                statusMessage = "Unable to clear location: \(error)"
                return
            }
            unresolvedClearSession = nil
            simulation.currentLocation = nil
            simulation.targetLocation = nil
            routeProgress = 0
            statusMessage = "Location cleared"
        }
        locationClearTask = clearing
        await clearing.value
    }

    // MARK: Simulation Control

    func startSimulation() async {
        guard canStartSimulation else { return }

        switch SimulationPlanner.plan(
            mode: activeMode,
            targetLocation: targetLocation,
            currentLocation: currentLocation,
            route: currentRoute,
            speed: simulationSpeed,
            jumpIndex: jumpIndex
        ) {
        case .teleport(let coordinate):
            isPaused = false
            await applyPlannedLocation(coordinate, mode: activeMode)
        case .route(let points):
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
        guard canBeginLocationOperation else { return nil }
        let operationGeneration = locationOperationGeneration
        let locationMode = mode.locationMode ?? .teleport
        locationSessionCoordinator.select(coordinate, mode: locationMode)

        guard prepareLocationSessionIfNeeded() else {
            isSimulating = false
            statusMessage = "No ready location session"
            return nil
        }

        do {
            let request = try locationSessionCoordinator.beginApplication()
            pendingApplicationModes[request.id] = mode
            let application = Task { try await locationInjector.apply(request) }
            applicationTasks[request.id] = application
            defer { applicationTasks.removeValue(forKey: request.id) }
            let receipt = try await withTaskCancellationHandler {
                try await application.value
            } onCancel: {
                application.cancel()
            }
            guard !Task.isCancelled,
                  locationClearTask == nil,
                  operationGeneration == locationOperationGeneration else {
                _ = locationSessionCoordinator.cancelPendingApplication(requestID: request.id)
                pendingApplicationModes.removeValue(forKey: request.id)
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
                isSimulating = currentLocation != nil
                statusMessage = "Location update queued; awaiting acknowledgement"
                return nil
            }

            pendingApplicationModes.removeValue(forKey: request.id)
            isSimulating = currentLocation != nil
            statusMessage = "Location update rejected: \(String(describing: result))"
            return nil
        } catch {
            guard locationClearTask == nil,
                  operationGeneration == locationOperationGeneration else { return nil }
            if case .applying(let requestID, _) = locationSessionCoordinator.state.application {
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
        return await restoreManagedHelperSession(session, helperID: helperID, for: device)
    }

    /// Restore provider-acknowledged held truth from an authenticated managed helper.
    /// This never resumes a route or joystick engine after relaunch.
    @discardableResult
    func restoreManagedHelperSession(
        _ session: ManagedLocationHelperSession,
        helperID: UUID,
        for device: Device
    ) async -> Bool {
        guard selectedDevice?.id == device.id,
              session.matches(deviceID: device.id),
              let receipt = session.locationReceipt(helperID: helperID) else {
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
        locationSessionCoordinator.state.lastAcknowledgedReceipt != nil
            || locationSessionCoordinator.state.application.isActive
            || !canBeginLocationOperation
    }

    func prepareForQuitWithoutLocation() async -> LocationQuitPreparationResult {
        await stopSimulation()
        do {
            try await managedLocationSessionSource.shutdownHelper()
            return .terminate
        } catch {
            return .failed("Managed helper shutdown failed: \(error.localizedDescription)")
        }
    }

    func prepareForQuit(_ choice: LocationQuitChoice) async -> LocationQuitPreparationResult {
        switch choice {
        case .cancel:
            return .cancel

        case .preserveAndQuit:
            await stopSimulation()
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
            return .terminate

        case .clearAndQuit:
            await clearLocation()
            guard locationSessionCoordinator.state.lastAcknowledgedReceipt == nil,
                  !locationSessionCoordinator.state.application.isActive,
                  canBeginLocationOperation else {
                return .failed(lastError ?? "Location Clear was not acknowledged")
            }
            do {
                try await managedLocationSessionSource.shutdownHelper()
                return .terminate
            } catch {
                return .failed("Location cleared, but managed helper shutdown failed: \(error.localizedDescription)")
            }
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
            guard !isSimulating else { return }
            guard currentRoute.count < mode.maxStops else {
                statusMessage = "Jump holds 12 stops"
                return
            }
            addRouteWaypoint(coordinate)
        case .twospot:
            loadRoute(from: [coordinate])
        case .route:
            guard !isSimulating else { return }
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
            speed: simulationSpeed
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

                    let interval = 1.0 / max(self.updateFrequencyHz, 1)
                    await self.routeDelay(interval)
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

    // MARK: Joystick Mode

    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction

        let engaged = hypot(direction.x, direction.y) >= JoystickMovement.deadZone
        guard engaged,
              !isSimulating,
              joystickTask == nil,
              canStartSimulation,
              activeMode == .joystick,
              (targetLocation ?? currentLocation) != nil else {
            return
        }

        Task { await startSimulation() }
    }

    private func startJoystick(at start: LocationCoordinate) async {
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

        if let reason {
            locationSessionCoordinator.connectionLost(reason: reason)
        } else {
            locationSessionCoordinator.submit(event)
        }

        if case .appCancelled = event {
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
