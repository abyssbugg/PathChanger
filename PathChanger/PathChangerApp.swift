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
                    .frame(minWidth: 1000, minHeight: 700)
                    .onAppear {
                        guard AppRuntimeEnvironment.allowsAutomaticStartup else {
                            return
                        }

                        Task {
                            // Validate dependencies before starting tunnel
                            await dependencyValidator.validateAll()

                            if dependencyValidator.isValid {
                                await tunneldManager.autoStart()
                            }
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
    // MARK: Device State
    @Published var selectedDevice: Device?
    @Published var availableDevices: [Device] = []
    @Published var isTunneldRunning: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: Location State
    @Published var currentLocation: LocationCoordinate?
    @Published var targetLocation: LocationCoordinate?

    // MARK: Simulation State
    @Published var isSimulating: Bool = false
    @Published var isPaused: Bool = false
    @Published var simulationSpeed: SimulationSpeed = .walking
    @Published var activeMode: AppMode = .teleport

    // MARK: Route Playback
    @Published var currentRoute: [LocationCoordinate] = []
    @Published var routeProgress: Double = 0
    @Published var isLoadingRoute: Bool = false

    // MARK: Joystick State
    @Published var joystickDirection: CGPoint = .zero
    @Published var joystickSpeed: Double = 5.0

    // MARK: UI State
    @Published var showLocationInput: Bool = false
    @Published var showRouteImport: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var lastError: String?
    @Published var statusMessage: String?

    // MARK: Statistics
    @Published var injectionStats: InjectionStats = InjectionStats()

    // MARK: iOS 18+ Warning State
    /// Tracks device IDs that have already shown the iOS 18+ toast in this session
    private var shownIOS18WarningDeviceIds: Set<String> = []

    // MARK: Reliability State
    @Published var recoveryState: ConnectionRecoveryState = .disconnected
    @Published var isUSBConnected: Bool = false
    @Published var isWiFiTransportAvailable: Bool = false
    @Published var preferUSBConnection: Bool = false

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
    private let locationBridge = DevLocationBridge()
    private var simulationTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    var canStartSimulation: Bool {
        selectedDevice != nil && isTunneldRunning
    }

    var simulationStatusText: String {
        if !isTunneldRunning {
            return "Tunnel not running"
        }
        if selectedDevice == nil {
            return "No device selected"
        }
        if isSimulating {
            return isPaused ? "Paused" : "Simulating..."
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

    // MARK: Initialization

    init(startBackgroundServices: Bool = true) {
        self.simulationEngine = SimulationEngine(locationBridge: locationBridge)

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
                    self.tunnelHealthMonitor.stopMonitoring()
                    Task { await self.locationBridge.stopHeldSimulation() }
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

        // Only update if devices actually changed
        let currentDeviceIds = Set(availableDevices.map { $0.id })
        let newDeviceIds = Set(uniqueDevices.map { $0.id })

        if currentDeviceIds != newDeviceIds {
            availableDevices = uniqueDevices
        } else {
            // Update device info if same devices but with new data
            availableDevices = uniqueDevices
        }

        if selectedDevice == nil, let first = availableDevices.first {
            selectedDevice = first
            simulationEngine.setDevice(first)
        }

        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable

        connectionStatus = selectedDevice != nil ? .connected : .disconnected

        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }

    func checkTunneldStatus() async {
        await deviceManager.checkTunneldStatus()
        await deviceManager.refreshTransportAvailability()
        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable
        updateTunnelRunning(deviceManager.isTunneldRunning)

        if !isTunneldRunning && !TunneldManager.shared.isStarting {
            await TunneldManager.shared.autoStart()
            updateTunnelRunning(TunneldManager.shared.isRunning, force: true)
        }

        if !isTunneldRunning {
            usbFallbackManager.wirelessFailed()
        } else {
            usbFallbackManager.wirelessRestored()
        }
    }

    func selectDevice(_ device: Device) {
        selectedDevice = device
        simulationEngine.setDevice(device)
        connectionStatus = .connected
        reliabilityManager.connectionEstablished()
    }

    // MARK: Location Control

    func setLocation(
        _ coordinate: LocationCoordinate,
        quiet: Bool = false,
        usePerformanceMode: Bool = false
    ) async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device, action: .checkConnection)
            if !quiet {
                ToastManager.shared.error("No device selected")
            }
            return
        }

        targetLocation = coordinate
        if !quiet {
            statusMessage = "Injecting location..."
        }

        do {
            try await locationBridge.setLocation(
                coordinate,
                for: device,
                priority: quiet ? .high : .normal,
                usePerformanceMode: usePerformanceMode
            )
            currentLocation = coordinate
            isSimulating = true
            lastError = nil
            injectionStats = await locationBridge.getStats()
            errorHandler.clearCurrentError()

            if !quiet {
                let locationStr = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
                statusMessage = "Location spoofed to \(locationStr)"
                ToastManager.shared.success("Location spoofed successfully!")
            }

        } catch let error as LocationInjectionError {
            if case .rateLimited = error, quiet {
                return
            }
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            if !quiet {
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }

            if case .deviceNotFound = error {
                reliabilityManager.connectionLost()
            }
        } catch {
            errorHandler.handle(error, context: "Location injection")
            isSimulating = false
            if !quiet {
                ToastManager.shared.error("Injection failed: \(error.localizedDescription)")
            }
        }
    }

    func clearLocation() async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device)
            return
        }

        do {
            try await locationBridge.clearLocation(for: device)
            currentLocation = nil
            targetLocation = nil
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

    func startSimulation() async {
        guard canStartSimulation else { return }

        switch SimulationPlanner.plan(
            mode: activeMode,
            targetLocation: targetLocation,
            currentLocation: currentLocation,
            route: currentRoute,
            speed: simulationSpeed
        ) {
        case .teleport(let coordinate):
            isPaused = false
            isSimulating = true
            await setLocation(coordinate)
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
        isPaused = true
    }

    func resumeSimulation() {
        isPaused = false
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
        currentRoute = coordinates
        routeProgress = 0
    }

    func addRouteWaypoint(_ coordinate: LocationCoordinate) {
        guard coordinate.isValid else { return }
        currentRoute.append(coordinate)
        targetLocation = coordinate
        routeProgress = 0
        statusMessage = "Spot \(currentRoute.count) added"
    }

    func removeLastRouteWaypoint() {
        guard !currentRoute.isEmpty else { return }
        currentRoute.removeLast()
        targetLocation = currentRoute.last
        routeProgress = 0
        statusMessage = currentRoute.isEmpty ? "All spots cleared" : "\(currentRoute.count) spots remaining"
    }

    func clearRoute() {
        simulationTask?.cancel()
        simulationTask = nil
        currentRoute = []
        routeProgress = 0
        statusMessage = "Spots cleared"
    }

    func importRoute(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let coordinates = try GPXParser().parse(fileURL: url).allCoordinates
            guard coordinates.count >= 2 else {
                lastError = "GPX file needs at least two points"
                statusMessage = lastError
                return
            }
            loadRoute(from: coordinates)
            targetLocation = coordinates.last
            lastError = nil
            statusMessage = "Imported \(coordinates.count) points"
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

                let interval = simulationSpeed.updateInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            if !Task.isCancelled {
                statusMessage = "Route playback complete"
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

        let interval: TimeInterval = 0.1
        joystickTask = Task {
            while !Task.isCancelled {
                if !isPaused {
                    let current = currentLocation ?? start
                    let next = JoystickMovement.nextCoordinate(
                        from: current,
                        direction: joystickDirection,
                        speedMetersPerSecond: simulationSpeed.metersPerSecond,
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
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}
