//
//  PathChangerApp.swift
//  PathChanger
//
//  iOS 17+ Location Injection macOS Application
//  Modern Pro UI with full backend integration
//

import SwiftUI
import Combine

@main
struct PathChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
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
                    .frame(minWidth: 760, idealWidth: 1000, minHeight: 560, idealHeight: 700)
                    .onAppear {
                        Task {
                            // Validate dependencies before device/tunnel workflows.
                            await dependencyValidator.validateAll()

                            if dependencyValidator.isValid {
                                await appState.refreshDevices()

                                if UserDefaults.standard.object(forKey: "autoStartTunneld") as? Bool == true {
                                    await tunneldManager.autoStart()
                                }
                            }
                        }
                    }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            // "Check for Updates…" menu item was removed in Milestone 5
            // alongside the stale upstream Sparkle SUFeedURL/SUPublicEDKey
            // pair. Restore this CommandGroup once a current appcast URL
            // and matching Ed25519 public key are configured in Info.plist.

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
    // MARK: - Composed Sub-Stores (Milestone 4)
    //
    // AppState's state surface is decomposed into six domain sub-stores
    // (`Models/AppStateStores.swift`). Each `@Published` sub-store
    // field below is the canonical owner of its state domain. The
    // legacy property names that used to be individual `@Published`
    // vars are now computed facade properties that read/write into
    // these stores, preserving the public surface SwiftUI views bind
    // to.
    //
    // Mutation flow:
    //   - External code reads/writes via legacy names
    //     (`selectedDevice`, `targetLocation`, `statusMessage`, …) →
    //     facade routes to the underlying sub-store field →
    //     `@Published` publishes the new sub-store value →
    //     `objectWillChange` fires on AppState.
    //   - Internal AppState methods may either go through facades or
    //     write the sub-store directly (`device.selected = X`); both
    //     produce identical publish semantics.
    //
    // Sub-store fields are `private(set)`: external code can read the
    // whole sub-store (for SwiftUI observation), but cannot mutate it
    // directly. All mutations go through AppState's facade setters or
    // explicit public mutation methods, preserving the single-writer
    // rule (AAD §5.2).
    @Published private(set) var device: DeviceStore = .empty
    @Published private(set) var tunnel: TunnelStore = .empty
    @Published private(set) var simulation: SimulationStore = .empty
    @Published private(set) var route: RouteStore = .empty
    @Published private(set) var joystick: JoystickStore = .empty
    @Published private(set) var ui: UIStore = .empty

    // MARK: - SwiftUI-Bound Direct @Published Vars
    //
    // The following three flags must remain direct `@Published` vars
    // on AppState (not inside a sub-store) because SwiftUI's
    // `$appState.X` projected-value binding mechanism only projects
    // from `@Published` properties of the `ObservableObject` itself —
    // it does not project through a nested struct field.
    //
    // Call sites:
    //   - `$appState.showRouteImport`     (SimulationView.swift)
    //   - `$appState.showOnboarding`      (ContentView.swift)
    //   - `$appState.preferUSBConnection` (SettingsView.swift,
    //                                      also receives Combine
    //                                      `assign(to: &$…)` from
    //                                      `usbFallbackManager`).
    @Published var showRouteImport: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var preferUSBConnection: Bool = false

    // MARK: - Facade Properties (Device)
    var selectedDevice: Device? {
        get { device.selected }
        set { device.selected = newValue }
    }
    var availableDevices: [Device] {
        get { device.available }
        set { device.available = newValue }
    }
    var connectionStatus: ConnectionStatus {
        get { device.connectionStatus }
        set { device.connectionStatus = newValue }
    }
    var isUSBConnected: Bool {
        get { device.isUSBConnected }
        set { device.isUSBConnected = newValue }
    }
    var isWiFiAvailable: Bool {
        get { device.isWiFiAvailable }
        set { device.isWiFiAvailable = newValue }
    }
    var recoveryState: ConnectionRecoveryState {
        get { device.recoveryState }
        set { device.recoveryState = newValue }
    }

    // MARK: - Facade Properties (Tunnel)
    var isTunneldRunning: Bool {
        get { tunnel.isRunning }
        set { tunnel.isRunning = newValue }
    }

    // MARK: - Facade Properties (Simulation)
    var currentLocation: LocationCoordinate? {
        get { simulation.currentLocation }
        set { simulation.currentLocation = newValue }
    }
    var targetLocation: LocationCoordinate? {
        get { simulation.targetLocation }
        set { simulation.targetLocation = newValue }
    }
    var targetLocationName: String? {
        get { simulation.targetLocationName }
        set { simulation.targetLocationName = newValue }
    }
    var locationHistory: [LocationHistoryEntry] {
        get { simulation.history }
        set { simulation.history = newValue }
    }
    var isSimulating: Bool {
        get { simulation.isSimulating }
        set { simulation.isSimulating = newValue }
    }
    var isPaused: Bool {
        get { simulation.isPaused }
        set { simulation.isPaused = newValue }
    }
    var simulationSpeed: SimulationSpeed {
        get { simulation.speed }
        set { simulation.speed = newValue }
    }
    var injectionStats: InjectionStats {
        get { simulation.injectionStats }
        set { simulation.injectionStats = newValue }
    }

    // MARK: - Facade Properties (Route)
    var currentRoute: [LocationCoordinate] {
        get { route.waypoints }
        set { route.waypoints = newValue }
    }
    var routeProgress: Double {
        get { route.progress }
        set { route.progress = newValue }
    }
    var isLoadingRoute: Bool {
        get { route.isLoading }
        set { route.isLoading = newValue }
    }

    // MARK: - Facade Properties (Joystick)
    var joystickDirection: CGPoint {
        get { joystick.direction }
        set { joystick.direction = newValue }
    }
    var joystickSpeed: Double {
        get { joystick.speed }
        set { joystick.speed = newValue }
    }

    // MARK: - Facade Properties (UI)
    var showLocationInput: Bool {
        get { ui.showLocationInput }
        set { ui.showLocationInput = newValue }
    }
    var lastError: String? {
        get { ui.lastError }
        set { ui.lastError = newValue }
    }
    var statusMessage: String? {
        get { ui.statusMessage }
        set { ui.statusMessage = newValue }
    }

    // MARK: Debouncing for UI Stability
    private var lastTunnelStateChange: Date = .distantPast
    private var lastUSBStateChange: Date = .distantPast
    private let stateDebounceInterval: TimeInterval = 2.5  // Increased from 0.5 to reduce flickering

    // MARK: Shared Managers
    let deviceManager = DeviceManager()
    let simulationEngine: SimulationEngine
    let reliabilityManager = ReliabilityManager()
    let errorHandler = ErrorHandler()
    let usbFallbackManager = USBFallbackManager()
    let routeLibrary = RouteLibraryManager()
    let tunnelHealthMonitor = TunnelHealthMonitor()

    // MARK: Private
    //
    // Location injection routes through `LocationBridge.shared` — the sole
    // authoritative bridge after Milestone 2. AppState no longer owns its
    // own `DevLocationBridge` instance; that actor is now a private
    // implementation detail of `LocationBridge`.
    //
    // Motion progression (route playback timer, joystick tick loop, geographic
    // offset math) is owned by `SimulationEngine` — the sole simulation
    // authority after Milestone 3. AppState is the lifecycle/state authority
    // only: it issues commands to the engine and mirrors engine published
    // state into its own UI-facing properties. The former `simulationTask`,
    // `joystickTask`, `joystickBaseLocation`, and `offsetCoordinate` were
    // deleted in Milestone 3 because they represented simulation-authority
    // leakage into the state hub.
    private let locationHistoryStore = LocationHistoryStore()
    private var cancellables = Set<AnyCancellable>()
    private var simulationTransitionTail: Task<Void, Never>?
    private var simulationTransitionSerial: UInt64 = 0

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        // BUG FIX (WiFi-Bug-8): Read tunnel state from TunneldManager.shared.isRunning
        // directly. The previous code read AppState.isTunneldRunning, which is
        // a debounced @Published mirror that can lag the state machine — and
        // historically was clobbered to false every 5 seconds by the polling
        // timer that didn't recognise WiFi tunnels. Reading the state machine
        // directly gives us a single source of truth for "can we drive the
        // device right now".
        return selectedDevice != nil && TunneldManager.shared.isRunning
    }

    var simulationStatusText: String {
        if !isTunneldRunning {
            return "Preparing connection…"
        }
        if selectedDevice == nil {
            return "Connect an iPhone to begin"
        }
        if isSimulating {
            if isPaused { return "Paused" }
            // Per-mode active text from the §5 lexicon. Reads existing
            // engine state via the existing `simulationEngine.currentMode`
            // mirror; no behavioural change beyond the returned string.
            switch simulationEngine.currentMode {
            case .teleport: return "Teleporting…"
            case .route:    return "Following route"
            case .joystick: return "Joystick active"
            }
        }
        return "Ready"
    }

    // MARK: Debounced State Updates

    private func updateTunnelRunning(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastTunnelStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isTunneldRunning != newValue {
            isTunneldRunning = newValue
            lastTunnelStateChange = now
        }
    }

    private func updateUSBConnected(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastUSBStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isUSBConnected != newValue {
            isUSBConnected = newValue
            lastUSBStateChange = now
        }
    }

    private func syncConnectionAvailability(from devices: [Device]) {
        let usbAvailable = devices.contains { $0.connectionType == .usb }
        let wifiAvailable = devices.contains { $0.connectionType == .wifi }

        updateUSBConnected(usbAvailable, force: true)

        if isWiFiAvailable != wifiAvailable {
            isWiFiAvailable = wifiAvailable
        }

        if usbFallbackManager.isUSBConnected != usbAvailable {
            if usbAvailable {
                usbFallbackManager.usbConnected()
            } else {
                usbFallbackManager.usbDisconnected()
            }
        }

        if wifiAvailable {
            usbFallbackManager.wirelessRestored()
        } else {
            usbFallbackManager.isWirelessAvailable = false
        }
    }

    // MARK: Initialization

    init() {
        self.simulationEngine = SimulationEngine()
        UserDefaults.standard.register(defaults: ["autoStartTunneld": false])
        AppPreferences.registerUIDefaults()

        // Check if onboarding is needed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        self.showOnboarding = !onboardingCompleted
        self.locationHistory = locationHistoryStore.entries

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await checkTunneldStatus()
            await refreshDevices()
        }

        // Sync with TunneldManager
        TunneldManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.updateTunnelRunning(state.isActive, force: true)

                if state.isActive {
                    // Start health monitoring when tunnel is active
                    self.tunnelHealthMonitor.startMonitoring()
                    Task { await self.refreshDevices() }
                } else {
                    // Stop health monitoring when tunnel is inactive
                    self.tunnelHealthMonitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        // Auto-refresh
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.checkTunneldStatus() }
            }
            .store(in: &cancellables)

        setupReliabilityManager()
        setupErrorHandler()
        setupUSBFallback()
        setupSimulationEngineMirrors()
    }

    /// Subscribe to `SimulationEngine` published state so AppState mirrors
    /// remain in lockstep with the engine’s actual motion progression.
    ///
    /// AppState owns lifecycle flags (`isSimulating`, `isPaused`,
    /// `currentLocation`, `routeProgress`, `statusMessage`); the engine owns
    /// the underlying motion timer/loop. These subscriptions translate engine
    /// state transitions into AppState mirror updates. Added in Milestone 3.
    private func setupSimulationEngineMirrors() {
        simulationEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] engineState in
                guard let self = self else { return }
                switch engineState {
                case .running:
                    self.isSimulating = true
                    self.isPaused = false
                case .paused:
                    self.isSimulating = true
                    self.isPaused = true
                case .completed:
                    // Final-waypoint history recording: when a route finishes
                    // naturally, persist the last waypoint to history. Prior
                    // to Milestone 3 this was inlined in AppState’s route
                    // playback loop.
                    if self.simulationEngine.currentMode == .route,
                       let last = self.currentRoute.last {
                        self.locationHistoryStore.record(
                            coordinate: last,
                            name: "Route end",
                            source: "Route"
                        )
                        self.locationHistory = self.locationHistoryStore.entries
                        self.statusMessage = "Route playback complete"
                    }
                    self.isSimulating = false
                    self.isPaused = false
                case .idle:
                    self.isSimulating = false
                    self.isPaused = false
                case .error(let message):
                    self.isSimulating = false
                    self.isPaused = false
                    self.lastError = message
                }
            }
            .store(in: &cancellables)

        simulationEngine.$currentCoordinate
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] coordinate in
                self?.currentLocation = coordinate
            }
            .store(in: &cancellables)

        simulationEngine.$routeProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.routeProgress = progress
            }
            .store(in: &cancellables)
    }

    // MARK: Manager Setup

    private func setupReliabilityManager() {
        reliabilityManager.onReconnect = { [weak self] in
            guard let self = self else { return false }
            await self.refreshDevices()
            return self.selectedDevice != nil && self.isTunneldRunning
        }

        reliabilityManager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.connectionStatus = .disconnected
                self?.statusMessage = "Connection lost, attempting to reconnect..."
            }
        }

        reliabilityManager.onReconnectionFailed = { [weak self] reason in
            Task { @MainActor in
                self?.lastError = reason
                self?.connectionStatus = .error
            }
        }
    }

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

    private func setupUSBFallback() {
        usbFallbackManager.$isUSBConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.updateUSBConnected(connected)
            }
            .store(in: &cancellables)

        usbFallbackManager.$preferUSB
            .assign(to: &$preferUSBConnection)
    }

    // MARK: Device Management

    func refreshDevices() async {
        await deviceManager.refreshDevices()

        // Deduplicate devices by UDID and ensure no duplicates in the list
        var seenUDIDs = Set<String>()
        var uniqueDevices: [Device] = []

        for device in deviceManager.devices {
            if !seenUDIDs.contains(device.id) {
                uniqueDevices.append(device)
                seenUDIDs.insert(device.id)
            }
        }
        syncConnectionAvailability(from: uniqueDevices)

        if availableDevices != uniqueDevices {
            availableDevices = uniqueDevices
        }

        if let selected = selectedDevice {
            if let updatedSelection = availableDevices.first(where: { $0.id == selected.id }) {
                if selected != updatedSelection {
                    selectedDevice = updatedSelection
                    simulationEngine.setDevice(updatedSelection)
                    TunneldManager.shared.setTargetDevice(updatedSelection)
                }
            } else if let first = availableDevices.first {
                selectedDevice = first
                simulationEngine.setDevice(first)
                TunneldManager.shared.setTargetDevice(first)
            } else {
                selectedDevice = nil
            }
        } else if let first = availableDevices.first {
            selectedDevice = first
            simulationEngine.setDevice(first)
            TunneldManager.shared.setTargetDevice(first)
        }

        connectionStatus = selectedDevice != nil ? .connected : .disconnected

        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }

    func checkTunneldStatus() async {
        // BUG FIX (WiFi-Bug-2): tunnel-running truth lives in TunneldManager,
        // not DeviceManager. The previous code routed through
        // `deviceManager.checkTunneldStatus()` which (before Bug-1B fix) didn't
        // know about the WiFi process pattern, and the result kept clobbering
        // the state-machine-derived value via the 5s timer.
        //
        // Now we ask TunneldManager itself two questions:
        //   1. Does its state machine think a tunnel is up? (`isRunning`)
        //   2. As a self-heal, does pgrep find any pmd3 tunnel process that the
        //      state machine missed? (`detectRunningTunnelMode()`)
        // The OR of those is the single tunnel-truth signal AppState publishes.
        let stateMachineRunning = TunneldManager.shared.isRunning
        let externallyDetectedMode = await TunneldManager.shared.detectRunningTunnelMode()
        let isRunning = stateMachineRunning || externallyDetectedMode != nil
        updateTunnelRunning(isRunning, force: true)

        if UserDefaults.standard.object(forKey: "autoStartTunneld") as? Bool == true,
           !isRunning && !TunneldManager.shared.isStarting {
            await TunneldManager.shared.autoStart()
            updateTunnelRunning(TunneldManager.shared.isRunning, force: true)
        }

        if isWiFiAvailable {
            usbFallbackManager.wirelessRestored()
        } else if !isTunneldRunning {
            usbFallbackManager.wirelessFailed()
        }
    }

    func selectDevice(_ device: Device) {
        selectedDevice = device
        simulationEngine.setDevice(device)
        TunneldManager.shared.setTargetDevice(device)
        connectionStatus = .connected
        reliabilityManager.connectionEstablished()
    }

    // MARK: Location Control

    func setLocation(
        _ coordinate: LocationCoordinate,
        source: String = "Manual",
        name: String? = nil,
        recordHistory: Bool = true,
        showToast: Bool = true
    ) async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "Connect an iPhone to begin", type: .device, action: .checkConnection)
            ToastManager.shared.error("Connect an iPhone to begin")
            return
        }

        // Show newer-iOS compatibility warning once per device per session.
        if device.hasLocationCompatibilityWarning {
            let versionStr = device.iosVersion

            // Only show toast if we haven't shown it for this device yet
            if !simulation.shownIOSWarningDeviceIds.contains(device.id) {
                ToastManager.shared.warning(
                    "iOS \(versionStr) detected - attempting location simulation, but newer iOS may need pymobiledevice3 updates.",
                    duration: 5.0
                )
                simulation.shownIOSWarningDeviceIds.insert(device.id)
            }

            // Always log the attempt
            Logger.info(
                "Attempting location injection on newer iOS version with compatibility warning: \(versionStr)",
                category: .device,
                deviceUDID: device.id
            )
        }

        targetLocation = coordinate
        statusMessage = "Teleporting…"

        do {
            try await LocationBridge.shared.setLocation(coordinate, for: device)
            currentLocation = coordinate
            isSimulating = true
            lastError = nil
            injectionStats = await LocationBridge.shared.getStats()
            errorHandler.clearCurrentError()
            if recordHistory {
                locationHistoryStore.record(coordinate: coordinate, name: name ?? targetLocationName, source: source)
                locationHistory = locationHistoryStore.entries
            }

            // Show success toast
            let locationStr = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
            statusMessage = "Location set to \(locationStr)"
            if showToast {
                ToastManager.shared.success("Location set successfully")
            }

        } catch let error as LocationInjectionError {
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            ToastManager.shared.error("Injection failed: \(error.localizedDescription)")

            if case .deviceNotFound = error {
                reliabilityManager.connectionLost()
            }
        } catch {
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
        }
    }

    func clearLocation() async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "Connect an iPhone to begin", type: .device)
            return
        }

        do {
            try await LocationBridge.shared.clearLocation(for: device)
            currentLocation = nil
            targetLocation = nil
            targetLocationName = nil
            isSimulating = false
            isPaused = false
            lastError = nil
            statusMessage = "Location cleared"
            errorHandler.clearCurrentError()
        } catch {
            errorHandler.handle(error, context: "Clear location")
        }
    }

    // MARK: Simulation Control
    func canStartSimulation(for mode: AppMode) -> Bool {
        guard canStartSimulation else { return false }

        switch mode {
        case .teleport:
            return targetLocation != nil
        case .route:
            return currentRoute.count >= 2
        case .joystick:
            return currentLocation != nil || targetLocation != nil
        case .settings:
            return false
        }
    }

    func startSimulation() async {
        await startSimulation(mode: .teleport)
    }

    func startSimulation(mode: AppMode) async {
        await runSimulationTransition { [weak self] in
            guard let self = self else { return }
            await self.performStartSimulation(mode: mode)
        }
    }

    private func performStartSimulation(mode: AppMode) async {
        guard canStartSimulation else { return }

        switch mode {
        case .teleport:
            guard let target = targetLocation else {
                lastError = "Pick a location"
                return
            }
            isPaused = false
            await setLocation(target, source: "Teleport", name: targetLocationName)
        case .route:
            await startRoutePlayback()
        case .joystick:
            await startJoystickControl()
        case .settings:
            return
        }
    }

    func pauseSimulation() {
        guard simulationTransitionTail == nil else { return }
        // Delegate to the simulation authority. The engine flips its state
        // machine to .paused which our mirror subscription propagates back
        // to AppState.isPaused.
        simulationEngine.pause()
        if simulationEngine.state == .paused {
            isPaused = true
        }
    }

    func resumeSimulation() {
        guard simulationTransitionTail == nil else { return }
        // Delegate to the simulation authority.
        simulationEngine.resume()
        if simulationEngine.state == .running {
            isPaused = false
        }
    }

    func stopSimulation() async {
        await runSimulationTransition { [weak self] in
            guard let self = self else { return }
            await self.performStopSimulation()
        }
    }

    private func performStopSimulation() async {
        // Delegate to the simulation authority. The engine cancels its timer,
        // stops its mode, and clears the device location.
        await simulationEngine.stop()
        resetLocalSimulationStateAfterEngineStop()
    }

    private func runSimulationTransition(_ operation: @escaping @MainActor () async -> Void) async {
        let previousTail = simulationTransitionTail
        simulationTransitionSerial &+= 1
        let serial = simulationTransitionSerial

        let transitionTask = Task { @MainActor in
            await previousTail?.value
            await operation()
        }
        simulationTransitionTail = transitionTask

        await transitionTask.value

        if simulationTransitionSerial == serial {
            simulationTransitionTail = nil
        }
    }

    private func resetLocalSimulationStateAfterEngineStop() {
        currentLocation = nil
        targetLocation = nil
        targetLocationName = nil
        isPaused = false
        isSimulating = false
        routeProgress = 0
        joystickDirection = .zero
        lastError = nil
        statusMessage = "Location cleared"
        errorHandler.clearCurrentError()
    }

    // MARK: Route Playback

    func loadRoute(from coordinates: [LocationCoordinate]) {
        currentRoute = coordinates
        routeProgress = 0
        targetLocation = coordinates.first
        targetLocationName = coordinates.isEmpty ? nil : "Route start"
    }

    func addRoutePoint(_ coordinate: LocationCoordinate? = nil) {
        guard let point = coordinate ?? targetLocation, point.isValid else {
            lastError = "Select a valid location before adding a waypoint"
            return
        }

        currentRoute.append(point)
        routeProgress = 0
        targetLocation = point
        targetLocationName = "Waypoint \(currentRoute.count)"
        statusMessage = "Added waypoint \(currentRoute.count)"
    }

    func removeRoutePoint(at index: Int) {
        guard currentRoute.indices.contains(index) else { return }
        currentRoute.remove(at: index)
        routeProgress = 0
    }

    func moveRoutePoint(from sourceIndex: Int, to destinationIndex: Int) {
        guard currentRoute.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex < currentRoute.count,
              sourceIndex != destinationIndex else {
            return
        }

        let point = currentRoute.remove(at: sourceIndex)
        currentRoute.insert(point, at: destinationIndex)
        routeProgress = 0
    }

    func clearRoute() {
        currentRoute.removeAll()
        routeProgress = 0
        statusMessage = "Route cleared"
    }

    func startRoutePlayback() async {
        guard canStartSimulation else { return }

        guard currentRoute.count >= 2 else {
            lastError = "Add at least two route points"
            return
        }

        // Fire the iOS-18-compatibility warning toast once for the active
        // device, preserving the per-session de-duplication behavior that
        // used to live inside AppState.setLocation’s per-tick path.
        if let device = selectedDevice {
            warnIfNewerIOSDeviceOnce(device: device)
        }

        // Record the start-of-route waypoint in history before handing off to
        // the engine. Previously this was done inside the per-tick loop with
        // `recordHistory: index == 0`. The end-of-route waypoint is recorded
        // by `setupSimulationEngineMirrors` when engine.state transitions to
        // .completed.
        if let first = currentRoute.first {
            locationHistoryStore.record(
                coordinate: first,
                name: "Route start",
                source: "Route"
            )
            locationHistory = locationHistoryStore.entries
        }

        // Hand off motion progression to the simulation authority. The engine
        // owns the per-tick timer, RouteInterpolator integration, and
        // LocationBridge calls from here on. AppState only observes.
        isPaused = false
        isSimulating = true
        routeProgress = 0
        simulationEngine.speed = simulationSpeed
        await simulationEngine.startRoute(waypoints: currentRoute)
    }

    // MARK: Joystick Mode

    /// Update the user-facing joystick direction binding and forward the
    /// vector to the simulation authority.
    ///
    /// `joystickDirection` remains the SwiftUI-bindable source of truth for
    /// the joystick control view. The simulation engine consumes the vector
    /// at its boundary (converting to a compass bearing internally).
    func updateJoystickDirection(_ direction: CGPoint) {
        joystickDirection = direction
        simulationEngine.updateJoystickDirection(direction)
    }

    func startJoystickControl() async {
        guard canStartSimulation else { return }

        guard let start = currentLocation ?? targetLocation else {
            lastError = "Pick a starting location"
            return
        }

        // Fire the iOS-18-compatibility warning toast once for the active
        // device (per-session de-duplication preserved from the per-tick path).
        if let device = selectedDevice {
            warnIfNewerIOSDeviceOnce(device: device)
        }

        // Persist the starting position to history once. Before Milestone 3
        // this was the first invocation of the per-tick setLocation loop.
        locationHistoryStore.record(
            coordinate: start,
            name: targetLocationName ?? "Joystick start",
            source: "Joystick"
        )
        locationHistory = locationHistoryStore.entries

        // Hand off motion progression to the simulation authority. The engine
        // owns the per-tick joystick loop and LocationBridge calls.
        targetLocation = start
        isPaused = false
        isSimulating = true
        simulationEngine.speed = simulationSpeed
        simulationEngine.updateJoystickDirection(joystickDirection)
        await simulationEngine.startJoystick(at: start)
    }

    /// Show the iOS-18+ compatibility warning toast at most once per device
    /// per session.
    ///
    /// Extracted in Milestone 3 from the prior per-tick `setLocation` path
    /// so it can fire exactly once at simulation start instead of every tick.
    private func warnIfNewerIOSDeviceOnce(device: Device) {
        guard device.hasLocationCompatibilityWarning else { return }
        let versionStr = device.iosVersion

        if !simulation.shownIOSWarningDeviceIds.contains(device.id) {
            ToastManager.shared.warning(
                "iOS \(versionStr) detected - attempting location simulation, but newer iOS may need pymobiledevice3 updates.",
                duration: 5.0
            )
            simulation.shownIOSWarningDeviceIds.insert(device.id)
        }

        Logger.info(
            "Attempting location injection on newer iOS version with compatibility warning: \(versionStr)",
            category: .device,
            deviceUDID: device.id
        )
    }

    // MARK: Location History

    func selectHistoryEntry(_ entry: LocationHistoryEntry) {
        targetLocation = entry.coordinate
        targetLocationName = entry.displayName
        statusMessage = "Selected recent location: \(entry.displayName)"
    }

    func removeHistoryEntry(_ entry: LocationHistoryEntry) {
        locationHistoryStore.remove(entry)
        locationHistory = locationHistoryStore.entries
    }

    func clearLocationHistory() {
        locationHistoryStore.clear()
        locationHistory = locationHistoryStore.entries
    }

    // MARK: Speed Control

    func setSpeed(_ speed: SimulationSpeed) {
        simulationSpeed = speed
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
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error: return "Connection lost"
        }
    }
}
