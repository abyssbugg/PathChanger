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
    private let routeDelay: @MainActor @Sendable (TimeInterval) async -> Void
    private var pendingApplicationModes: [UUID: AppMode] = [:]
    private var simulationTask: Task<Void, Never>?
    private var routePlaybackID: UUID?
    private var joystickTask: Task<Void, Never>?
    private var locationRecoveryTask: Task<Void, Never>?
    private var bridgeEventTask: Task<Void, Never>?
    private var persistentBridgeEventTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        simulation.canStartSimulation
    }

    var simulationStatusText: String {
        simulation.statusText
    }

    // MARK: Initialization

    init(
        startBackgroundServices: Bool = true,
        locationInjector: (any LocationInjecting)? = nil,
        routeDelay: @escaping @MainActor @Sendable (TimeInterval) async -> Void = { seconds in
            guard seconds > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        let sharedBridge = DevLocationBridge()
        let sharedErrorHandler = ErrorHandler()
        let resolvedInjector: any LocationInjecting = locationInjector ?? sharedBridge
        let sessionCoordinator = LocationSessionCoordinator(injector: resolvedInjector)

        self.locationBridge = sharedBridge
        self.locationInjector = resolvedInjector
        self.routeDelay = routeDelay
        self.errorHandler = sharedErrorHandler
        self.locationSessionCoordinator = sessionCoordinator
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
            Task { await self.locationBridge.stopTunnelDependentSimulation() }
        }

        device.onLocationSessionLoss = { [weak self] event in
            self?.handleLocationSessionLoss(event)
        }

        // Check if onboarding is needed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        self.showOnboarding = !onboardingCompleted

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [locationBridge, sessionCoordinator] _ in
            Task { @MainActor in
                sessionCoordinator.submit(.appCancelled)
                await locationBridge.stopHeldSimulation()
            }
        }

        guard startBackgroundServices else {
            return
        }

        bridgeEventTask = Task { [weak self, locationBridge] in
            let events = await locationBridge.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                await self?.handleLocationBridgeEvent(event, heldSubprocessSource: true)
            }
        }
        persistentBridgeEventTask = Task { [weak self] in
            let events = await PersistentLocationBridge.shared.events()
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
        if let error = await locationSessionCoordinator.clear() {
            statusMessage = "Unable to clear location: \(error)"
            return
        }
        pendingApplicationModes.removeAll()
        simulation.currentLocation = nil
        simulation.targetLocation = nil
        simulation.isSimulating = false
        simulation.isPaused = false
        routeProgress = 0
        statusMessage = "Location cleared"
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
            let receipt = try await locationInjector.apply(request)
            guard !Task.isCancelled else {
                _ = locationSessionCoordinator.reject(requestID: request.id, error: CancellationError())
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
        let endpointClass: LocationEndpointClass = transport == .usb ? .direct : .remoteServiceDiscovery
        let lastGeneration = locationSessionCoordinator.state.lastAcknowledgedReceipt?.sessionGeneration ?? 0
        locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: selectedDevice.id,
            transport: transport,
            endpointClass: endpointClass,
            generation: lastGeneration + 1
        ))
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

    func pauseSimulation() {
        simulation.pauseSimulation()
        locationSessionCoordinator.pauseMovement()
        route.pausePlayback()
    }

    func resumeSimulation() {
        guard locationSessionCoordinator.state.application.isActive else { return }
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
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil

        isPaused = false
        isSimulating = false
        route.beginAcknowledgedPlayback()
        await locationBridge.setQueueStrategy(.sequential)

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
                    if smoothTurns {
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
        guard locationSessionCoordinator.state.desiredLocation != nil,
              locationRecoveryTask == nil else { return }

        let strategy = reliabilityManager.strategy
        locationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.locationSessionCoordinator.recover(
                strategy: strategy,
                establishSession: { [weak self] _, previous in
                    guard let self, let previous else {
                        throw LocationSessionTransitionError.noReadySession
                    }
                    return try await self.device.establishRecoverySession(previous: previous)
                }
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
