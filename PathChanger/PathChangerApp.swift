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
    @Published var targetLocationName: String?
    @Published var locationHistory: [LocationHistoryEntry] = []

    // MARK: Simulation State
    @Published var isSimulating: Bool = false
    @Published var isPaused: Bool = false
    @Published var simulationSpeed: SimulationSpeed = .walking

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

    // MARK: Newer iOS Warning State
    /// Tracks device IDs that have already shown the newer-iOS toast in this session
    private var shownNewerIOSWarningDeviceIds: Set<String> = []

    // MARK: Reliability State
    @Published var recoveryState: ConnectionRecoveryState = .disconnected
    @Published var isUSBConnected: Bool = false
    @Published var isWiFiAvailable: Bool = false
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
    private let locationHistoryStore = LocationHistoryStore()
    private var simulationTask: Task<Void, Never>?
    private var joystickTask: Task<Void, Never>?
    private var joystickBaseLocation: LocationCoordinate?
    private var cancellables = Set<AnyCancellable>()

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
        self.simulationEngine = SimulationEngine(locationBridge: locationBridge)
        UserDefaults.standard.register(defaults: ["autoStartTunneld": false])

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
        showToast: Bool = true,
        performanceMode: Bool = false
    ) async {
        guard let device = selectedDevice else {
            errorHandler.handle(message: "No device selected", type: .device, action: .checkConnection)
            ToastManager.shared.error("No device selected")
            return
        }

        // Show newer-iOS compatibility warning once per device per session.
        if device.hasLocationCompatibilityWarning {
            let versionStr = device.iosVersion

            // Only show toast if we haven't shown it for this device yet
            if !shownNewerIOSWarningDeviceIds.contains(device.id) {
                ToastManager.shared.warning(
                    "iOS \(versionStr) detected - attempting location simulation, but newer iOS may need pymobiledevice3 updates.",
                    duration: 5.0
                )
                shownNewerIOSWarningDeviceIds.insert(device.id)
            }

            // Always log the attempt
            Logger.info(
                "Attempting location injection on newer iOS version with compatibility warning: \(versionStr)",
                category: .device,
                deviceUDID: device.id
            )
        }

        targetLocation = coordinate
        statusMessage = "Injecting location..."

        do {
            try await locationBridge.setLocation(coordinate, for: device, usePerformanceMode: performanceMode)
            currentLocation = coordinate
            isSimulating = true
            lastError = nil
            injectionStats = await locationBridge.getStats()
            errorHandler.clearCurrentError()
            if recordHistory {
                locationHistoryStore.record(coordinate: coordinate, name: name ?? targetLocationName, source: source)
                locationHistory = locationHistoryStore.entries
            }

            // Show success toast
            let locationStr = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
            statusMessage = "Location spoofed to \(locationStr)"
            if showToast {
                ToastManager.shared.success("Location spoofed successfully!")
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
            errorHandler.handle(message: "No device selected", type: .device)
            return
        }

        do {
            try await locationBridge.clearLocation(for: device)
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
        guard canStartSimulation else { return }

        switch mode {
        case .teleport:
            guard let target = targetLocation else {
                lastError = "No target location selected"
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
        joystickBaseLocation = nil

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
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil
        isPaused = false
        isSimulating = true
        routeProgress = 0

        simulationTask = Task {
            let totalPoints = currentRoute.count
            var currentIndex = 0

            while currentIndex < totalPoints && !Task.isCancelled {
                if isPaused {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }

                let coordinate = currentRoute[currentIndex]
                await setLocation(
                    coordinate,
                    source: "Route",
                    name: "Route point \(currentIndex + 1)",
                    recordHistory: currentIndex == 0 || currentIndex == totalPoints - 1,
                    showToast: false,
                    performanceMode: true
                )

                routeProgress = Double(currentIndex + 1) / Double(totalPoints)
                currentIndex += 1

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
    }

    func startJoystickControl() async {
        guard canStartSimulation else { return }

        guard let start = currentLocation ?? targetLocation else {
            lastError = "Select a starting location before using joystick mode"
            return
        }

        simulationTask?.cancel()
        simulationTask = nil
        joystickTask?.cancel()

        joystickBaseLocation = start
        targetLocation = start
        isPaused = false
        isSimulating = true

        await setLocation(
            start,
            source: "Joystick",
            name: targetLocationName ?? "Joystick start",
            recordHistory: true,
            performanceMode: true
        )

        joystickTask = Task {
            while !Task.isCancelled {
                if isPaused {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }

                let direction = joystickDirection
                let magnitude = min(1.0, max(0.0, sqrt(direction.x * direction.x + direction.y * direction.y)))

                guard magnitude > 0.05, let base = joystickBaseLocation ?? currentLocation else {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }

                let interval = max(1.0, simulationSpeed.updateInterval)
                let distanceMeters = simulationSpeed.metersPerSecond * interval * Double(magnitude)
                let eastMeters = Double(direction.x) * distanceMeters
                let northMeters = Double(direction.y) * distanceMeters
                let next = offsetCoordinate(from: base, eastMeters: eastMeters, northMeters: northMeters)

                guard next.isValid else {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }

                joystickBaseLocation = next
                await setLocation(
                    next,
                    source: "Joystick",
                    name: "Joystick movement",
                    recordHistory: false,
                    showToast: false,
                    performanceMode: true
                )

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func offsetCoordinate(from coordinate: LocationCoordinate, eastMeters: Double, northMeters: Double) -> LocationCoordinate {
        let metersPerDegreeLatitude = 111_111.0
        let latitudeRadians = coordinate.latitude * .pi / 180
        let metersPerDegreeLongitude = max(1.0, metersPerDegreeLatitude * cos(latitudeRadians))

        let nextLatitude = coordinate.latitude + (northMeters / metersPerDegreeLatitude)
        let nextLongitude = coordinate.longitude + (eastMeters / metersPerDegreeLongitude)

        return LocationCoordinate(latitude: nextLatitude, longitude: nextLongitude)
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
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}
