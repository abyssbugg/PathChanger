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

@main
struct PathChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState(
        startBackgroundServices: AppRuntimeEnvironment.allowsAutomaticStartup
    )
    @StateObject private var tunneldManager = TunneldManager.shared
    @StateObject private var dependencyValidator = DependencyValidator.shared

    var body: some Scene {
        WindowGroup {
            if dependencyValidator.validationStatus == .invalid {
                DependencyErrorView(validator: dependencyValidator)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(tunneldManager)
                    .frame(minWidth: 1100, minHeight: 740)
                    .onAppear {
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

// MARK: - App State

/// Global application state with full simulation control
@MainActor
class AppState: ObservableObject {

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
    var autoCooldown: Bool {
        get { simulation.autoCooldown }
        set { simulation.autoCooldown = newValue }
    }
    var customSpeedMps: Double {
        get { simulation.customSpeedMps }
        set { simulation.customSpeedMps = newValue }
    }
    var cooldownSeconds: Double {
        get { simulation.cooldownSeconds }
        set { simulation.cooldownSeconds = newValue }
    }
    var updateFrequencyHz: Double {
        get { simulation.updateFrequencyHz }
        set { simulation.updateFrequencyHz = newValue }
    }
    var safeModeTeleport: Bool {
        get { simulation.safeModeTeleport }
        set { simulation.safeModeTeleport = newValue }
    }
    var safeModeJoystick: Bool {
        get { simulation.safeModeJoystick }
        set { simulation.safeModeJoystick = newValue }
    }
    var addGPSDrift: Bool {
        get { simulation.addGPSDrift }
        set { simulation.addGPSDrift = newValue }
    }
    var smoothTurns: Bool {
        get { simulation.smoothTurns }
        set { simulation.smoothTurns = newValue }
    }
    var cooldownReminder: Bool {
        get { simulation.cooldownReminder }
        set { simulation.cooldownReminder = newValue }
    }
    var lastTeleportMessage: String? {
        get { simulation.lastTeleportMessage }
        set { simulation.lastTeleportMessage = newValue }
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

    var routeLibrary: RouteLibraryManager { route.routeLibrary }

    // Forwarded so existing call sites keep resolving.
    var deviceManager: DeviceManager { device.deviceManager }
    var reliabilityManager: ReliabilityManager { device.reliabilityManager }
    var usbFallbackManager: USBFallbackManager { device.usbFallbackManager }
    var tunnelHealthMonitor: TunnelHealthMonitor { device.tunnelHealthMonitor }

    // MARK: Private
    private let locationBridge: DevLocationBridge
    private var simulationTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        simulation.canStartSimulation
    }

    var simulationStatusText: String {
        simulation.statusText
    }

    // MARK: Initialization

    init(startBackgroundServices: Bool = true) {
        let sharedBridge = DevLocationBridge()
        let sharedErrorHandler = ErrorHandler()

        self.locationBridge = sharedBridge
        self.errorHandler = sharedErrorHandler
        self.device = DeviceStateManager(startBackgroundServices: startBackgroundServices)
        self.route = RouteStateManager(routeLibrary: RouteLibraryManager())
        self.simulation = SimulationStateManager(
            locationBridge: sharedBridge,
            errorHandler: sharedErrorHandler
        )
        self.simulationEngine = SimulationEngine(locationBridge: sharedBridge)

        // Cross-manager references.
        simulation.setDeviceStateManager(device)
        route.setSimulationStateManager(simulation)

        // Re-publish the managers' changes so views observing AppState still update.
        for publisher in [device.objectWillChange, route.objectWillChange, simulation.objectWillChange] {
            publisher
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        simulation.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }

        device.onDeviceSelected = { [weak self] selected in
            self?.simulationEngine.setDevice(selected)
        }

        device.onConnectionLost = { [weak self] in
            self?.statusMessage = "Connection lost, attempting to reconnect..."
        }

        device.onReconnectionFailed = { [weak self] reason in
            self?.lastError = reason
        }

        device.onTunnelActiveChanged = { [weak self] isActive in
            guard let self, !isActive else { return }
            Task { await self.locationBridge.stopHeldSimulation() }
        }

        // Check if onboarding is needed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        self.showOnboarding = !onboardingCompleted

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [locationBridge] _ in
            Task {
                await locationBridge.stopHeldSimulation()
            }
        }

        guard startBackgroundServices else {
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await checkTunneldStatus()
            await refreshDevices()
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
    }

    func checkTunneldStatus() async {
        await device.checkTunneldStatus()
    }

    func selectDevice(_ selected: Device) {
        device.selectDevice(selected)
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
        await simulation.clearLocation()
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
            isSimulating = true
            await setLocation(coordinate)
            if activeMode == .jump, currentLocation == coordinate {
                jumpIndex = min(jumpIndex + 1, currentRoute.count)
            }
        case .route(let points):
            await playRoute(points)
        case .joystick(let start):
            await startJoystick(at: start)
        case .failed(let message):
            lastError = message
            statusMessage = message
        }
    }

    func pauseSimulation() {
        simulation.pauseSimulation()
    }

    func resumeSimulation() {
        simulation.resumeSimulation()
    }

    func stopSimulation() async {
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil
        joystickTask = nil

        isPaused = false
        isSimulating = false
        routeProgress = 0
        joystickDirection = .zero

        await clearLocation()
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

    var cooldownRemaining: TimeInterval {
        simulation.cooldownRemaining
    }

    var headerSafeMode: Bool {
        get { simulation.headerSafeMode }
        set { simulation.headerSafeMode = newValue }
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
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil

        isPaused = false
        isSimulating = true
        routeProgress = 0
        await locationBridge.setQueueStrategy(.sequential)

        simulationTask = Task {
            let totalPoints = points.count

            for (index, coordinate) in points.enumerated() {
                if Task.isCancelled { return }

                while isPaused && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if Task.isCancelled { return }

                await setLocation(coordinate, quiet: true, usePerformanceMode: true)
                routeProgress = Double(index + 1) / Double(totalPoints)

                let interval = 1.0 / max(updateFrequencyHz, 1)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            if !Task.isCancelled {
                if loopRoute {
                    await playRoute(points)
                } else {
                    statusMessage = "Route playback complete"
                }
            }
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
        simulationTask?.cancel()
        joystickTask?.cancel()
        simulationTask = nil

        isPaused = false
        isSimulating = true
        await locationBridge.setQueueStrategy(.latestWins)
        await setLocation(start, quiet: true, usePerformanceMode: true)

        let interval: TimeInterval = 1.0 / max(updateFrequencyHz, 1)
        joystickTask = Task {
            while !Task.isCancelled {
                if !isPaused {
                    let current = currentLocation ?? start
                    var direction = joystickDirection
                    if smoothTurns, safeModeJoystick {
                        direction = smoothedDirection(direction)
                    }
                    let next = JoystickMovement.nextCoordinate(
                        from: current,
                        direction: direction,
                        speedMetersPerSecond: effectiveMetersPerSecond,
                        deltaTime: interval
                    )
                    if next != current {
                        await setLocation(next, quiet: true, usePerformanceMode: true)
                    }
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func disengageJoystick() {
        joystickTask?.cancel()
        joystickTask = nil
        isSimulating = false
        isPaused = false
        simulation.resetJoystick()
        statusMessage = "Joystick disengaged"
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

    func mockCooldown(for speed: SimulationSpeed) -> Double {
        speed.defaultCooldownSeconds
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
