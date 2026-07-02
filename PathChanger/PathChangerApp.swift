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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var tunneldManager = TunneldManager.shared
    @StateObject private var dependencyValidator = DependencyValidator.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            if dependencyValidator.validationStatus == .invalid {
                DependencyErrorView(validator: dependencyValidator)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(tunneldManager)
                    .frame(minWidth: 760, idealWidth: 1000, minHeight: 560, idealHeight: 700)
                    .onAppear {
                        // Re-apply the persisted theme override (dark/light/system)
                        // before any long-running startup work so the window paints
                        // with the user's chosen appearance from the first frame.
                        AppTheme.applySaved()

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
                    .onAppear {
                        Logger.info(
                            "main_window_lifecycle appear",
                            category: .general,
                            metadata: LogMetadata(operationType: "main_window_lifecycle")
                        )
                    }
                    .onDisappear {
                        Logger.info(
                            "main_window_lifecycle disappear",
                            category: .general,
                            metadata: LogMetadata(operationType: "main_window_lifecycle")
                        )
                    }
            }
        }
        // Mockup-parity window chrome: the shell draws its own topbar row, so
        // the system title bar is hidden and the native traffic lights overlay
        // the shell's topbar (which reserves leading space for them).
        .windowStyle(.hiddenTitleBar)
        .onChange(of: scenePhase) { _, newPhase in
            Logger.info(
                "main_window_lifecycle scenePhase=\(String(describing: newPhase))",
                category: .general,
                metadata: LogMetadata(operationType: "main_window_lifecycle")
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Show PathChanger") {
                    Logger.info(
                        "main_window_lifecycle show command",
                        category: .general,
                        metadata: LogMetadata(operationType: "main_window_lifecycle")
                    )
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("n", modifiers: .command)
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
    @Published var device: DeviceStore = .empty
    @Published var tunnel: TunnelStore = .empty
    @Published var simulation: SimulationStore = .empty
    @Published var route: RouteStore = .empty
    @Published var joystick: JoystickStore = .empty
    @Published var ui: UIStore = .empty

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
    var lastTunnelStateChange: Date = .distantPast
    var lastUSBStateChange: Date = .distantPast
    // W1 Slice R1 (responsiveness remediation): tightened from the previous
    // 2.5 s anti-flicker default to 0.4 s. The runtime regression report
    // identified the 2.5 s value as the single largest contributor to UI
    // tunnel-state lag without a corresponding correctness benefit: the
    // TunnelStateMachine already provides its own 0.3 s anti-flicker gate
    // and `force: true` mirror updates bypass this debounce on every
    // canonical state-machine transition. 0.4 s preserves anti-flicker for
    // legacy non-forced callers (e.g. `checkTunneldStatus` background poll)
    // while restoring perceived responsiveness.
    let stateDebounceInterval: TimeInterval = 0.4

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
    let locationHistoryStore = LocationHistoryStore()
    var cancellables = Set<AnyCancellable>()
    var simulationTransitionTail: Task<Void, Never>?
    var simulationTransitionSerial: UInt64 = 0
    var resumableSessionSnapshot: ResumableSessionSnapshot?
    var transientRecoveryTask: Task<Void, Never>?
    var transientRecoverySerial: UInt64 = 0
#if DEBUG
    var debugTransientRecoveryHandler: ((String) async -> Bool)?
    var debugSkipDeviceRefreshDuringTransientRecovery = false
#endif
    let tunnelStatusFallbackPollingKey = "tunnelStatusFallbackPollingEnabled"

    /// RSD endpoint ("address:port") of the last successfully-applied location
    /// injection. Used to detect daemon tunnel RSD rotation so a held Teleport
    /// spoof can be re-applied before the device silently reverts.
    var lastAppliedRsdKey: String?

    struct ResumableSessionSnapshot {
        let device: Device
        let mode: SimulationModeType
        let coordinate: LocationCoordinate?
        let targetLocation: LocationCoordinate?
        let targetLocationName: String?
        let routeWaypoints: [LocationCoordinate]
        let routeProgress: Double
        let joystickDirection: CGPoint
        let wasPaused: Bool
        let wasSimulating: Bool
        let speed: SimulationSpeed
    }

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

    func updateTunnelRunning(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastTunnelStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isTunneldRunning != newValue {
            isTunneldRunning = newValue
            lastTunnelStateChange = now
        }
    }

    func updateUSBConnected(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastUSBStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isUSBConnected != newValue {
            isUSBConnected = newValue
            lastUSBStateChange = now
        }
    }

    /// Resolve whether Wi-Fi connectivity should be presented as available.
    ///
    /// Wi-Fi is available when discovery labelled the device as `.wifi`, OR a
    /// wireless tunnel transport (background daemon / Wi-Fi) is currently the
    /// active tunnel. The latter is the authoritative signal: in Auto mode with
    /// a cable connected, usbmux labels the device `.usb` and the merged device
    /// list never carries a `.wifi` entry, so the previous discovery-only check
    /// wrongly showed "Wi-Fi Unavailable" while the daemon (wireless) tunnel was
    /// active. Pure + side-effect free for unit testing.
    static func resolveWiFiAvailability(
        wifiDiscovered: Bool,
        isTunnelRunning: Bool,
        activeTransport: TunnelMode?
    ) -> Bool {
        if wifiDiscovered { return true }
        guard isTunnelRunning else { return false }
        return activeTransport == .wifi || activeTransport == .daemon
    }

    func syncConnectionAvailability(from devices: [Device]) {
        let usbAvailable = devices.contains { $0.connectionType == .usb }
        let wifiAvailable = AppState.resolveWiFiAvailability(
            wifiDiscovered: devices.contains { $0.connectionType == .wifi },
            isTunnelRunning: TunneldManager.shared.isRunning,
            activeTransport: TunneldManager.shared.presentationActiveMode
        )

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
        UserDefaults.standard.register(defaults: [
            "autoStartTunneld": false,
            tunnelStatusFallbackPollingKey: false
        ])
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

        // Temporary recovery fallback only: enabled explicitly via defaults.
        if UserDefaults.standard.bool(forKey: tunnelStatusFallbackPollingKey) {
            Timer.publish(every: 5.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { await self?.checkTunneldStatus() }
                }
                .store(in: &cancellables)
        }

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

}
