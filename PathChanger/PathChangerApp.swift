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

    /// `isAwaitingAutomaticReconnect`: PathChanger is waiting for the lost phone to reapply
    /// its held location (PRODUCT_REQUIREMENTS 7.3). The connection then reads Reconnecting,
    /// not Lost, and Clear stays usable: it is how the user stops the wait.
    init(
        state: LocationSessionState,
        deviceVisible: Bool,
        hasUnresolvedClear: Bool = false,
        isAwaitingAutomaticReconnect: Bool = false
    ) {
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
            connectionLabel = isAwaitingAutomaticReconnect
                ? Self.localizedStatus("location.status.connection.reconnecting", comment: "Connection reconnecting")
                : Self.localizedStatus("location.status.connection.failed", comment: "Connection failed")
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
            // Something may be on the device: a receipt, or an application that is not
            // idle. A selected or staged point alone was never sent (PRODUCT_REQUIREMENTS 5.2).
            let deviceMayHoldLocation: Bool = {
                if case .idle = state.application { return state.lastAcknowledgedReceipt != nil }
                return true
            }()
            canClear = hasUnresolvedClear || isAwaitingAutomaticReconnect || (ready != nil && deviceMayHoldLocation)
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

/// How the map marks the location (PRODUCT_REQUIREMENTS 5.2): spoofed when the device
/// holds it (a current applied receipt), uncertain when it was applied but the session
/// that holds it is lost or not confirmed, staged when it is only planned and nothing was
/// sent, such as the last spot a Clear left behind.
struct LocationMarker: Equatable {
    enum Style: Equatable {
        case spoofed
        case uncertain
        case staged
    }

    let coordinate: LocationCoordinate
    let style: Style

    var accessibilityLabel: String {
        switch style {
        case .spoofed: return "Spoofed location"
        case .uncertain: return "Location uncertain"
        case .staged: return "Staged location"
        }
    }

    /// The applied point when there is one; else the last acknowledged point the phone may
    /// still hold (uncertain); else the start a Clear staged (where the next Move leaves
    /// from, also once a Two-Spot destination is picked); else the selected point. Nil when
    /// there is nothing to mark.
    static func resolve(
        applied: LocationCoordinate?,
        uncertain: LocationCoordinate? = nil,
        stagedStart: LocationCoordinate?,
        desired: LocationCoordinate?
    ) -> LocationMarker? {
        if let applied { return LocationMarker(coordinate: applied, style: .spoofed) }
        if let uncertain { return LocationMarker(coordinate: uncertain, style: .uncertain) }
        return (stagedStart ?? desired).map { LocationMarker(coordinate: $0, style: .staged) }
    }
}

@main
struct PathChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppState(
            startBackgroundServices: AppRuntimeEnvironment.allowsAutomaticStartup,
            locationInjector: LocationInjectorFactory.make(),
            ddiPreparerFactory: { DeveloperDiskImagePreparer.live(deviceManager: $0) },
            roadRouter: MapKitRoadRouter(),
            placeNameResolver: PlaceNameResolver(geocoder: CLGeocoderReverseGeocoder())
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
            hasUnresolvedClear: unresolvedClearSession != nil,
            isAwaitingAutomaticReconnect: isAwaitingAutomaticReconnect
        )
    }

    /// The Connection chip's words. With no device selected and nothing applied it reads
    /// Unavailable, except while PathChanger waits for the lost phone: discovery has
    /// deselected it then, and the chip says Reconnecting (PRODUCT_REQUIREMENTS 7.3).
    var connectionChipLabel: String {
        let status = locationPresentation
        guard selectedDevice == nil, status.appliedCoordinate == nil, !isAwaitingAutomaticReconnect else {
            return status.connectionLabel
        }
        return NSLocalizedString("location.status.connection.unavailable", comment: "No device connection state")
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
    /// The last spoofed coordinate a confirmed Clear left as the start for the next mode
    /// (PRODUCT_REQUIREMENTS 5.2). It is staged, never applied: nothing is sent until the
    /// user starts a mode. Ends when any location is applied or a new point is staged.
    @Published private(set) var stagedStartAfterClear: LocationCoordinate?
    static let clearWithoutConnectionText =
        "The phone is not connected, so it could not be cleared. It may keep the spoofed location until it reconnects or restarts. To clear it, press Reconnect when the phone is back, then Clear."
    /// A Clear of a session this Mac never held, after the helper confirmed it holds no
    /// connection to the phone: the held session ended with that connection.
    static let clearAfterConnectionEndedText =
        "The connection to the phone had ended, which ends the spoofed location. If the phone still shows it, reconnect and press Clear again."
    /// A Clear of a session this Mac never held when this app session could not start or
    /// adopt its location helper while the helper's record lists a held session: nobody
    /// could confirm the connection ended.
    static let clearHelperUnreachableText =
        "PathChanger could not reach its location helper, which may still hold the location. Quit and reopen PathChanger, then Clear."

    /// The line logged before Clear closes the helper's connection after a probe that did
    /// not report it connected. A timed-out probe may only have been slow, and closing it
    /// can trip the tunnel's health probe, so that case reads distinctly.
    static func unheldClearClosingLogLine(for status: HelperConnectionStatus) -> String {
        let timedOut = PersistentLocationBridge.PersistentBridgeError.timeout.localizedDescription
        if status == .notConnected(timedOut) {
            return "[Clear] Probe did not answer (timed out); closing the helper's connection, which ends any location held over it"
        }
        return "[Clear] No session on this Mac and the helper's connection is not live (" +
            LogRedaction.redactingDeviceIdentifiers(String(describing: status)) +
            "); closing it, which ends any location held over it"
    }
    /// Where the next Move leaves from: the applied location, or the start a Clear staged.
    var moveStartCoordinate: LocationCoordinate? {
        locationPresentation.appliedCoordinate ?? stagedStartAfterClear
    }
    var locationMarker: LocationMarker? {
        let presentation = locationPresentation
        return LocationMarker.resolve(
            applied: presentation.appliedCoordinate,
            // A receipt exists but is not current (lost, uncertain, older session): the
            // phone may still hold that point. Never "Staged": that says nothing was sent.
            uncertain: locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate,
            stagedStart: stagedStartAfterClear,
            desired: presentation.desiredCoordinate
        )
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
            let changed = simulation.activeMode != newValue
            simulation.activeMode = newValue
            // A stop run belongs to its mode: leaving the mode ends it and holds the
            // stop (Auto jump used to keep running and jump back to stop 1 with no Move).
            if let run = stopRun, run.mode != newValue { endStopRun("left \(run.mode.rawValue)") }
            if changed { resetRouteStopProgress() }
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
    /// Compatibility view of Jump's stop settings (Go through = every stop).
    var autoJump: Bool {
        get { stopTravelSettings(for: .jump).progression == .automatic }
        set {
            var settings = stopTravelSettings(for: .jump)
            settings.progression = newValue ? .automatic : .onePerMove
            setStopTravelSettings(settings, for: .jump)
        }
    }
    /// Compatibility view of Jump's At each stop time; the Auto jump pause stays 1-60 s.
    var autoJumpPauseSeconds: TimeInterval {
        get { stopTravelSettings(for: .jump).holdSeconds }
        set {
            var settings = stopTravelSettings(for: .jump)
            settings.holdSeconds = min(max(newValue, 1), 60)
            setStopTravelSettings(settings, for: .jump)
        }
    }
    /// Distance per route update: the shown travel speed divided by the update rate, so
    /// Two-Spot and Multi-Spot travel at the speed the card displays.
    var routeStepMeters: Double {
        effectiveMetersPerSecond / max(updateFrequencyHz, 1)
    }

    // MARK: Stop-by-stop options (PRODUCT_REQUIREMENTS 3.6)

    /// Fetches the road path of one leg just before the run reaches it. Nil means
    /// straight lines (tests, previews).
    var legPathProvider: (@Sendable (LocationCoordinate, LocationCoordinate, SimulationSpeed) async -> LegPath)?

    /// Names the spoofed location on the map (PRODUCT_REQUIREMENTS 3.5). Nil in tests
    /// and previews, so nothing reaches Apple's geocoder there.
    let placeNameResolver: PlaceNameResolver?
    /// Adapts a road router to the engine's leg seam: the road path, whether it follows
    /// roads, and the note the card shows when it does not.
    nonisolated static func roadLegPathProvider(
        _ router: any RoadRouting
    ) -> @Sendable (LocationCoordinate, LocationCoordinate, SimulationSpeed) async -> LegPath {
        { from, to, travel in
            let road = await router.route(from: from, to: to, travel: travel)
            return LegPath(points: road.points, followsRoads: road.followsRoads, note: road.note)
        }
    }

    /// The running stop run's next stop, time left and hold countdown; nil when no run
    /// is active.
    @Published private(set) var stopProgress: StopProgress?

    /// Two-Spot / Multi-Spot: the next stop of a one-stop-per-Move run.
    var routeStopIndex: Int { route.routeStopCursor.nextIndex }

    /// The stop cursor of `mode` (Jump's hop index and direction, or the Two-Spot /
    /// Multi-Spot cursor), for the card's "At stop" readout. Read-only.
    func displayStopCursor(for mode: AppMode) -> StopCursor {
        stopCursor(for: mode)
    }

    /// The stops the card's "At stop" and completion readouts index for `mode`: the
    /// cursor indexes the run's stops, which for Two-Spot with one spot start at the held
    /// location (review 2026-11-02-163337 issue 8). Jump indexes its hops; Two-Spot and
    /// Multi-Spot use the running run's stops, else the stops the latest run remembered
    /// (reset with the stop index and on any edit of the stops), else the route.
    /// Read-only.
    func displayStops(for mode: AppMode) -> [LocationCoordinate] {
        guard mode != .jump else { return currentRoute }
        if let run = stopRun, run.mode == mode { return run.stops }
        return routeRunStops ?? currentRoute
    }

    func stopTravelSettings(for mode: AppMode) -> StopTravelSettings {
        route.stopTravelSettings(for: mode)
    }

    /// Changing a mode's options during its run ends the run and holds.
    func setStopTravelSettings(_ settings: StopTravelSettings, for mode: AppMode) {
        guard route.stopTravelSettings(for: mode) != settings else { return }
        route.setStopTravelSettings(settings, for: mode)
        if let run = stopRun, run.mode == mode { endStopRun("\(mode.rawValue) options changed") }
    }

    /// Pause a running stop run: the latest applied point holds, a hold countdown stops.
    func pauseMovement() {
        guard stopRun != nil, !isPaused else { return }
        pauseSimulation()
        Logger.info("[Stops] Paused", category: .session)
    }

    /// Resume a paused stop run from the latest acknowledged point and the step it was on.
    func resumeMovement() {
        guard stopRun != nil, isPaused, canBeginLocationOperation else { return }
        simulation.resumeSimulation()
        if case .paused(let mode) = locationSessionCoordinator.state.movement {
            locationSessionCoordinator.beginMovement(mode)
        }
        route.resumePlayback()
        Logger.info("[Stops] Resumed", category: .session)
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
    /// Compatibility view of the Two-Spot / Multi-Spot Repeat option (Loop or One way).
    var loopRoute: Bool {
        get { stopTravelSettings(for: loopMode).repeatMode != .oneWay }
        set {
            var settings = stopTravelSettings(for: loopMode)
            guard (settings.repeatMode != .oneWay) != newValue else { return }
            settings.repeatMode = newValue ? .loop : .oneWay
            setStopTravelSettings(settings, for: loopMode)
        }
    }
    private var loopMode: AppMode { activeMode == .twospot ? .twospot : .route }

    // MARK: Joystick State (forwarded to `simulation`)
    var joystickDirection: CGPoint {
        get { simulation.joystickDirection }
        set { simulation.joystickDirection = newValue }
    }
    var joystickSpeed: Double {
        get { simulation.joystickSpeed }
        set { simulation.setJoystickSpeed(newValue) }
    }
    /// Heading of the last acknowledged joystick step. Releasing or disengaging the stick
    /// keeps it shown; the next movement replaces it and a successful Clear forgets it
    /// (PRODUCT_REQUIREMENTS 3.5, owner decision 2026-11-02).
    @Published private(set) var lastJoystickHeadingDegrees: Double?

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
    /// Requests in flight: the mode that applied each, and the stop it arrives at (the
    /// stop index advances only when that receipt is acknowledged).
    private var pendingApplications: [UUID: PendingApplication] = [:]
    private struct PendingApplication {
        let mode: AppMode
        let stopArrival: StopArrival?
    }
    /// Where a run stands once an arrival is acknowledged.
    private struct StopArrival {
        let cursor: StopCursor
        /// The stops when the run began: an arrival on edited stops does not move the index.
        let routeSnapshot: [LocationCoordinate]
    }
    /// The one stop-by-stop run (Jump, Two-Spot, Multi-Spot) in progress.
    private struct StopRun {
        let id: UUID
        let mode: AppMode
        let stops: [LocationCoordinate]
        let routeSnapshot: [LocationCoordinate]
        let settings: StopTravelSettings
    }
    private var stopRun: StopRun?
    /// Two-Spot's stops (which may start at the held location) for the remaining Moves of
    /// a one-stop-per-Move run; reset with the stop index.
    private var routeRunStops: [LocationCoordinate]?
    /// Two-Spot / Multi-Spot: an arrival of the current one-stop-per-Move sequence was
    /// acknowledged, so the next Move continues from the held stop (also when the stop
    /// index wrapped back to the first stop). Reset with the stop index.
    private var routeSequenceArrived = false
    /// A paused run waits here until Resume, Stop, Clear or cancellation.
    private var pauseWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var applicationTasks: [UUID: Task<LocationInjectionReceipt, Error>] = [:]
    @Published private var locationClearTask: Task<Void, Never>?
    @Published private var unresolvedClearSession: LocationSessionIdentity?
    private var locationOperationGeneration: UInt64 = 0
    private var simulationTask: Task<Void, Never>? {
        didSet {
            isMovementEngineRunning = simulationTask != nil
            // Whatever ended the engine (Stop, Clear, a loss, the joystick) ended its run.
            if simulationTask == nil {
                stopRun = nil
                stopProgress = nil
                // Ending a run cancels its task without awaiting it; its last apply may
                // still be at the bridge. The next stop Move waits for it to unwind.
                if let oldValue { unwindingEngineTask = oldValue }
            }
        }
    }
    /// The engine task last ended (cancelled or finished), until a Move has awaited it.
    private var unwindingEngineTask: Task<Void, Never>?
    /// A stop Move is waiting for the previous run's task to unwind.
    private var isAwaitingEngineUnwind = false
    private var routePlaybackID: UUID?
    private var joystickTask: Task<Void, Never>?
    /// The one joystick engagement in flight: a drag sends many direction samples, and
    /// each used to spawn its own start until the first injection returned.
    private var joystickStartTask: Task<Void, Never>?
    /// A Teleport or single Jump hop started by Move is still applying.
    private var isOneShotMoveInFlight = false
    /// A Move is waiting on a Developer Disk Image check or mount that was not cached.
    private var isPreparingDeviceForLocation = false
    /// A route or stop run is running (from Move until it ends). The Move button
    /// shows Stop for this whole time, not only after the first acknowledged point.
    @Published private(set) var isMovementEngineRunning = false
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
    /// Automatic reconnect (PRODUCT_REQUIREMENTS §7.3): waits for a lost phone and runs
    /// one bounded recovery burst when it is visible again (or on a slow fallback timer).
    private let automaticReconnect: AutomaticReconnectEnvironment
    private var automaticReconnectTask: Task<Void, Never>?
    /// Bumped whenever a wait starts or is cancelled, so an ended loop never clears a newer one.
    private var automaticReconnectID: UInt64 = 0
    private let automaticReconnectWaiter = AutoReconnectWaiter()
    /// True from the moment PathChanger waits for the lost phone until its held location
    /// is reapplied (or the wait is cancelled), bursts included.
    @Published private(set) var isAwaitingAutomaticReconnect = false
    /// Stop Tunnel or Clear since the last explicit Start, Move or Reconnect: the user
    /// ended the connection or the location, so nothing reconnects behind their back.
    private(set) var isAutomaticReconnectLatchedByUser = false
    /// Reopens the tunnel itself after a loss the user did not cause (live 2026-11-03),
    /// whether or not a location is held. Clear does not stop it; Stop Tunnel does.
    private let tunnelAutoReconnect: TunnelAutoReconnectEnvironment
    let tunnelAutoReconnector: TunnelAutoReconnector
    /// Reconnect is in flight: the button reads "Reconnecting…" and further clicks do nothing.
    @Published private(set) var isReconnecting = false
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
        stopTravelSettingsDefaults: UserDefaults? = AppRuntimeEnvironment.isHostingTests ? nil : .standard,
        roadRouter: (any RoadRouting)? = nil,
        placeNameResolver: PlaceNameResolver? = nil,
        automaticReconnect: AutomaticReconnectEnvironment? = nil,
        tunnelAutoReconnect: TunnelAutoReconnectEnvironment? = nil,
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
        // Off wherever background services are off (test hosts, previews): only an
        // explicit environment turns it on there.
        self.automaticReconnect = automaticReconnect ?? .live(isEnabled: effectiveBackgroundServices)
        let resolvedTunnelReconnect = tunnelAutoReconnect ?? .live(isEnabled: effectiveBackgroundServices)
        self.tunnelAutoReconnect = resolvedTunnelReconnect
        self.tunnelAutoReconnector = TunnelAutoReconnector(environment: resolvedTunnelReconnect)
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
        // The helper connect hint follows the connection mode; the bridge has no
        // DeviceManager of its own (review 2026-11-01 v3).
        PersistentLocationBridge.shared.connectTransportProvider = { [weak resolvedDDIDeviceManager] device in
            resolvedDDIDeviceManager?.helperConnectTransport(for: device.id)
        }
        self.route = RouteStateManager(
            routeLibrary: RouteLibraryManager(),
            settingsDefaults: stopTravelSettingsDefaults
        )
        self.legPathProvider = roadRouter.map(Self.roadLegPathProvider)
        self.placeNameResolver = placeNameResolver
        self.simulation = SimulationStateManager(
            locationBridge: sharedBridge,
            errorHandler: sharedErrorHandler,
            settingsDefaults: stopTravelSettingsDefaults
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
        for publisher in [device.objectWillChange, route.objectWillChange, simulation.objectWillChange, sessionCoordinator.objectWillChange, tunnelAutoReconnector.objectWillChange] {
            publisher
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        simulation.onStatusMessage = { [weak self] message in
            self?.statusMessage = message
        }

        // Editing the stops (by any path) ends a stop run and holds the stop it reached.
        route.$currentRoute
            .sink { [weak self] newRoute in
                guard let self, newRoute != self.route.currentRoute else { return }
                self.routeRunStops = nil
                self.routeSequenceArrived = false
                if let run = self.stopRun, newRoute != run.routeSnapshot {
                    self.endStopRun("the stops changed")
                }
            }
            .store(in: &cancellables)
        // Anything that lifts the pause (Resume, Stop, Clear, a loss) lets a paused run go;
        // the run's progress shows the pause whichever control set it.
        simulation.$isPaused
            .sink { [weak self] paused in
                guard let self else { return }
                if self.stopProgress != nil { self.stopProgress?.isPaused = paused }
                if !paused { self.releasePauseWaiters() }
            }
            .store(in: &cancellables)

        device.onDeviceSelected = { [weak self] selected in
            guard let self else { return }
            simulationEngine.setDevice(selected)
            self.stopTunnelReconnectIfAnotherPhoneIsSelected(selected)
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

        // The awaited phone is visible again over any live source. A paired placeholder
        // in the device list is not evidence (§7.3); the fallback timer covers sources
        // that never update.
        Publishers.CombineLatest3(device.$usbDirectDeviceIds, device.$wifiDirectDeviceIds, device.$networkAdvertisedDeviceIds)
            .sink { [weak self] usb, wifi, bonjour in
                guard let self else { return }
                // The tunnel reconnect watches the same live sources for the remembered phone.
                self.tunnelAutoReconnector.noteVisibleDevices(usb.union(wifi).union(bonjour))
                guard let awaited = self.device.awaitedReconnectDeviceID,
                      usb.contains(awaited) || wifi.contains(awaited) || bonjour.contains(awaited) else { return }
                self.automaticReconnectWaiter.signalReachable()
            }
            .store(in: &cancellables)

        // Check if onboarding is needed
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboardingCompleted")
        self.showOnboarding = !onboardingCompleted

        guard effectiveBackgroundServices || usesScriptedInjector else {
            return
        }

        // Start replaced a stalled helper connection: a location held on it ended.
        TunneldManager.shared.onHelperConnectionReplaced = { [weak self] deviceId in
            self?.helperConnectionReplaced(deviceId: deviceId)
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
        // An explicit Start lifts a Stop's hold on automatic reconnect; a wait that is
        // already running keeps waiting (the phone may come back through this Start).
        isAutomaticReconnectLatchedByUser = false
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
            defer {
                reconnectTask = nil
                isReconnecting = false
            }
            await runReconnectNow()
        }
        reconnectTask = reconnect
        isReconnecting = true
        await reconnect.value
    }

    private func runReconnectNow() async {
        guard canBeginLocationOperation else { return }
        // Reconnect reapplies only a location the phone held (a receipt). After a confirmed
        // Clear the last spot is staged with no receipt: Reconnect then only reconnects and
        // leaves it staged (PRODUCT_REQUIREMENTS 5.2), and Clear's hold on automatic
        // reconnect stays, because nothing it could defend was reapplied.
        let reappliesHeldLocation = locationSessionCoordinator.state.lastAcknowledgedReceipt != nil
        // Reconnect is explicit: it lifts a Stop's latch and replaces any automatic wait.
        // A Reconnect that does not get the location back waits again (as after a burst).
        if reappliesHeldLocation { isAutomaticReconnectLatchedByUser = false }
        await stopAutomaticReconnect(reason: "Reconnect pressed")
        defer { armAutomaticReconnectIfEligible(afterFailedBurst: true) }
        // Manual reconnect supersedes an in-flight automatic recovery; cancelling
        // first keeps the two paths from driving the coordinator concurrently.
        locationRecoveryTask?.cancel()
        await locationRecoveryTask?.value
        locationRecoveryTask = nil

        await device.refreshDevices()
        if let selectedDevice {
            tunnelQuitController.resumeLocationCommands(for: selectedDevice.id)
        }

        // Reconnect never stops a live tunnel (live 2026-11-03: a click on a running tunnel
        // ended it and the owner needed 2-3 clicks); from idle or error it starts one. In
        // helper modes that start never elevates, so it no longer needs a Start this session.
        let tunnel = tunnelAutoReconnect.tunnel
        if userStartedTunnelInSession
            || (tunnelAutoReconnect.isEnabled && tunnel.preferredMode.usesHelperConnection) {
            await tunnel.reconnectTunnel(deviceId: tunnelTargetDeviceId())
        }

        guard prepareLocationSessionIfNeeded() else {
            statusMessage = "Connect and select an iOS device to reconnect"
            return
        }
        guard reappliesHeldLocation,
              let desired = locationSessionCoordinator.state.desiredLocation else { return }
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
        // Pressing Clear is how the user stops a wait for the lost phone (the GUI offers it
        // while waiting); the outcome is reported in those words below.
        let wasAwaitingReconnect = isAwaitingAutomaticReconnect
        // Clear is the user's "back to real GPS": even a Clear the phone cannot confirm
        // (no connection) must not be undone by an automatic reapply later.
        isAutomaticReconnectLatchedByUser = true
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
            defer {
                // Backstop: no exit from Clear may leave the location phase Clearing. Clear
                // would stay disabled, Move refused and the record restore refused until
                // Stop Tunnel or a relaunch (review 2026-11-02-163337 issue 1).
                if locationSessionCoordinator.state.application == .clearing {
                    Logger.error(
                        "[Clear] Ended with the location phase still Clearing; recording it as a failed Clear",
                        category: .session
                    )
                    locationSessionCoordinator.failClear(reason: "The Clear did not complete")
                }
                locationClearTask = nil
            }
            let producers = [simulationTask, joystickTask, joystickStartTask, locationRecoveryTask, automaticReconnectTask].compactMap { $0 }
            let applications = Array(applicationTasks.values)
            producers.forEach { $0.cancel() }
            applications.forEach { $0.cancel() }
            pendingApplications.removeAll()
            _ = locationSessionCoordinator.cancelPendingApplication()
            simulation.isSimulating = false
            simulation.isPaused = false
            route.pausePlayback()
            locationSessionCoordinator.stopMovement()
            // A step the phone applied while this Clear drained (its receipt is dropped,
            // Clear wins) was the last spoofed point: an applied receipt is device truth.
            var appliedDuringDrain: LocationInjectionReceipt?
            for application in applications {
                if case .success(let receipt) = await application.result, case .applied = receipt.outcome,
                   appliedDuringDrain.map({ receipt.completedAt >= $0.completedAt }) ?? true {
                    appliedDuringDrain = receipt
                }
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

            // The point the device held, read once the producers drained (a step applied
            // during the drain is the newest), staged for the next mode if Clear succeeds.
            let lastSpoofed = appliedDuringDrain?.coordinate
                ?? locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate
                ?? currentLocation

            var clearError = await locationSessionCoordinator.clear(targetSession: sessionToClear)
            // The session the coordinator actually cleared: with none captured above (the
            // connection had failed), a provisional Ready the selection observer published
            // while the producers drained is the one it used.
            let attemptedSession = locationSessionCoordinator.lastClearTarget ?? sessionToClear
            var failureStatus: String?
            if clearError == .noHeldSession, let attemptedSession {
                // Nothing was sent: this Mac's injector holds no session for the one the
                // GUI showed Ready (a provisional session after a loss or a relaunch, live
                // 2026-11-02). Storing it as an unresolved Clear wedged Move: every retry
                // was refused the same way. The managed helper is the only holder of a
                // held DVT session, so it decides.
                switch await endUnheldLocationSession(attemptedSession) {
                case .clearedOverConnection:
                    locationSessionCoordinator.commitConfirmedClear()
                    clearError = nil
                case .connectionEnded:
                    locationSessionCoordinator.commitClearWithoutHeldSession(
                        reason: "The connection to the phone had ended"
                    )
                    unresolvedClearSession = nil
                    simulation.currentLocation = nil
                    routeProgress = 0
                    lastJoystickHeadingDegrees = nil
                    statusMessage = (wasAwaitingReconnect ? "Stopped reconnecting. " : "")
                        + Self.clearAfterConnectionEndedText
                    return
                case .failed(let reason, let status):
                    locationSessionCoordinator.failClear(reason: reason)
                    clearError = .clearFailed
                    failureStatus = status
                }
            }
            if let error = clearError {
                if error == .clearUnavailable, sessionToClear == nil {
                    // No connection to the phone, so nothing could reach it. The location
                    // stays Uncertain (the phone may still hold it) and Move is not blocked:
                    // a retry has no session to clear and would wedge every later Move.
                    Logger.info(
                        "[Clear] Not sent: no connection to the phone"
                            + (wasAwaitingReconnect ? "; stopped waiting for it to come back" : ""),
                        category: .session
                    )
                    statusMessage = (wasAwaitingReconnect ? "Stopped reconnecting. " : "")
                        + Self.clearWithoutConnectionText
                    return
                }
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
                unresolvedClearSession = attemptedSession
                // The user sees the reason the coordinator recorded, not its enum.
                if let failureStatus {
                    statusMessage = failureStatus
                } else if case .failed(let reason) = locationSessionCoordinator.state.application {
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
            lastJoystickHeadingDegrees = nil
            statusMessage = "Location cleared"
            if let lastSpoofed { stageStartAfterConfirmedClear(lastSpoofed) }
        }
        locationClearTask = clearing
        await clearing.value
        if reconcilingConnection {
            await reconcileConnectionAfterConfirmedClear(of: sessionToClear)
        }
    }

    /// After a confirmed Clear the last spoofed point stays as the staged start for the
    /// next mode (PRODUCT_REQUIREMENTS 5.2): selected and targeted, never applied. The
    /// device holds nothing and no receipt exists, so Move is what sends it.
    private func stageStartAfterConfirmedClear(_ coordinate: LocationCoordinate) {
        guard coordinate.isValid else { return }
        stagedStartAfterClear = coordinate
        simulation.targetLocation = coordinate
        locationSessionCoordinator.select(coordinate, mode: activeMode.locationMode ?? .teleport)
        statusMessage = "Location cleared. The last spot is staged for the next mode."
    }

    private enum UnheldClearOutcome {
        /// The helper cleared the phone over its open connection (device truth).
        case clearedOverConnection
        /// The helper holds no connection to the phone (or confirmed it closed one that
        /// no longer answered): the held session ended with it; unconfirmed on the phone.
        case connectionEnded
        /// The helper did not confirm either: a real Clear failure, retried by Clear.
        /// `status` replaces the generic "Press Clear again" message when a retry is not
        /// the advice.
        case failed(String, status: String? = nil)
    }

    /// Ends whatever the managed helper still holds for a session this Mac's injector
    /// never held. Unprivileged and bounded. A live connection is cleared over, not
    /// closed: closing it would fail the tunnel's health probe and report a tunnel error
    /// for a Clear. The Clear over it runs the bridge's normal Clear path, whose
    /// idempotent `connect_device` preflight can reopen the connection (bounded) if the
    /// link dropped after the probe. A connection that does not answer may still be kept
    /// by the helper (a timed-out probe keeps it), so it is closed, which ends any
    /// location held over it.
    /// The probe and the close answer without asking anyone when this app session never
    /// started or adopted the helper, so Clear first tries the unprivileged start/adopt;
    /// a helper it still cannot reach while the record lists a held session is reported
    /// as unconfirmed, never as an ended connection (review 2026-11-02-163337 issue 2).
    private func endUnheldLocationSession(_ session: LocationSessionIdentity) async -> UnheldClearOutcome {
        let deviceID = session.stableDeviceID
        if !managedLocationSessionSource.isHelperRunning {
            do {
                try await managedLocationSessionSource.start()
            } catch {
                Logger.error(
                    "[Clear] No session on this Mac; starting or adopting the location helper failed: " +
                    LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                    category: .session
                )
            }
        }
        guard managedLocationSessionSource.isHelperRunning else {
            if managedLocationSessionSource.hasRecordedHeldSessions {
                Logger.error(
                    "[Clear] No session on this Mac and the location helper, whose record lists a held session, " +
                    "could not be reached; the Clear is unconfirmed",
                    category: .session
                )
                return .failed(
                    Self.clearHelperUnreachableText,
                    status: "Unable to clear location. " + Self.clearHelperUnreachableText
                )
            }
            Logger.info(
                "[Clear] No session on this Mac and no location helper holds one; nothing holds the location here",
                category: .session
            )
            return .connectionEnded
        }
        let status = await managedLocationSessionSource.deviceConnectionStatus(deviceID, transport: session.transport)
        if status == .connected {
            do {
                try await managedLocationSessionSource.clearLocationOverDeviceConnection(
                    deviceID, transport: session.transport, sessionGeneration: session.generation
                )
                Logger.info("[Clear] No session on this Mac; the helper cleared the phone over its open connection", category: .session)
                return .clearedOverConnection
            } catch {
                let reason = error.localizedDescription
                Logger.error(
                    "[Clear] No session on this Mac; the helper's Clear over its open connection failed: " +
                    LogRedaction.redactingDeviceIdentifiers(reason),
                    category: .session
                )
                return .failed(reason)
            }
        }
        Logger.info(Self.unheldClearClosingLogLine(for: status), category: .session)
        guard await managedLocationSessionSource.disconnectDevice(deviceID, transport: session.transport) else {
            Logger.error(
                "[Clear] No session on this Mac; the helper did not confirm its connection to the phone is closed",
                category: .session
            )
            return .failed("The location helper did not confirm that its connection to the phone is closed")
        }
        Logger.info(
            "[Clear] No session on this Mac and the helper holds no connection to the phone (" +
            LogRedaction.redactingDeviceIdentifiers(String(describing: status)) +
            "); the held session ended with the connection",
            category: .session
        )
        return .connectionEnded
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
            if isPreparingDeviceForLocation {
                statusMessage = Self.stillPreparingDeviceForLocationText
                Logger.info("[Move] Not started (\(activeMode)): the iPhone is still being prepared for location", category: .session)
                return
            }
            Logger.info("[Move] Not started (\(activeMode)): a one-shot Move is still applying", category: .session)
            return
        }
        // Move is an explicit user action: it lifts a previous Stop Tunnel's block.
        if let selectedDevice {
            tunnelQuitController.resumeLocationCommands(for: selectedDevice.id)
        }
        // The next movement replaces the joystick's last heading (3.5).
        if activeMode != .joystick { lastJoystickHeadingDegrees = nil }
        // It also lifts Stop's or Clear's hold on automatic reconnect and replaces a wait
        // still running (its burst is awaited, so the two never drive the coordinator).
        isAutomaticReconnectLatchedByUser = false
        // And Stop Tunnel's latch on the tunnel reconnect (review 2026-11-03 issue 7). Not
        // under test hosts and previews, where the tunnel is the shared live manager.
        if tunnelAutoReconnect.isEnabled {
            tunnelAutoReconnect.tunnel.liftStopLatch()
        }
        await stopAutomaticReconnect(reason: "Move pressed")
        // That await can last as long as a helper command already sent (up to its own
        // timeout): the phone, a Clear or the device may have changed meanwhile.
        guard canStartSimulation else {
            Logger.info("[Move] Not started (\(activeMode)): the device is not ready after the reconnect ended", category: .session)
            statusMessage = "The phone is not ready. Keep it unlocked and on this Wi‑Fi or connected by USB, then press Move again."
            return
        }

        // Jump (with stops), Two-Spot and Multi-Spot run stop by stop (3.2-3.4, 3.6).
        switch activeMode {
        case .twospot, .route:
            await startStopMove()
            return
        case .jump where currentRoute.contains(where: \.isValid):
            await startStopMove()
            return
        case .teleport, .jump, .joystick, .settings:
            break
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
        case .teleport: planKind = "teleport"
        case .route(let points): planKind = "route(\(points.count) points)"
        case .joystick: planKind = "joystick"
        case .failed(let message): planKind = "failed(\(message))"
        }
        Logger.info("[Move] \(activeMode): plan \(planKind)", category: .session)

        switch plan {
        case .teleport(let coordinate):
            // A one-shot Move replaces any engine still running (latest intent wins)
            // instead of racing it on the device.
            if isMovementEngineRunning { await stopSimulation() }
            isPaused = false
            isOneShotMoveInFlight = true
            defer { isOneShotMoveInFlight = false }
            await applyPlannedLocation(coordinate, mode: activeMode)
        case .route:
            // Only Two-Spot and Multi-Spot plan routes, and they run stop by stop above.
            Logger.error("[Move] Unexpected route plan for \(activeMode)", category: .session)
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
        mode: AppMode,
        stopArrival: StopArrival? = nil
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
            pendingApplications[request.id] = PendingApplication(mode: mode, stopArrival: stopArrival)

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
                // A check that is not cached can take minutes (a first helper mount
                // downloads and personalizes the image): say so instead of sitting silent
                // (review 2026-11-03 issue 4). A cached image says nothing.
                let showsPreparation = !(await ddiPreparer.isKnownMounted(udid: preparationUDID))
                if showsPreparation {
                    isPreparingDeviceForLocation = true
                    statusMessage = Self.preparingDeviceForLocationText
                    Logger.info("[Preparation] Preparing the iPhone for location: checking the Developer Disk Image (\(mode))", category: .device)
                }
                defer {
                    if showsPreparation {
                        isPreparingDeviceForLocation = false
                        if statusMessage == Self.preparingDeviceForLocationText
                            || statusMessage == Self.stillPreparingDeviceForLocationText {
                            statusMessage = nil
                        }
                    }
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
                pendingApplications.removeValue(forKey: request.id)
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
                pendingApplications.removeValue(forKey: request.id)
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
                    pendingApplications.removeValue(forKey: request.id)
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
            pendingApplications.removeValue(forKey: request.id)
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
                    pendingApplications.removeValue(forKey: ownRequestID)
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
                pendingApplications.removeValue(forKey: requestID)
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

    /// This app session is applying, holding, clearing, moving or recovering a location
    /// itself. A recovery burst (or the wait that runs bursts) owns the session: its
    /// re-selection of the phone must not let the helper-record restore adopt over it.
    private var ownsLocationOperation: Bool {
        if simulationTask != nil || joystickTask != nil || joystickStartTask != nil
            || locationClearTask != nil || !applicationTasks.isEmpty
            || locationRecoveryTask != nil || automaticReconnectTask != nil {
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
        // Undo the adapter's adoption so it does not keep a session the coordinator refused.
        guard clearEpoch == locationOperationGeneration, !ownsLocationOperation else {
            Logger.info("[AppState] Not restoring a recorded location: a Clear or Move started meanwhile", category: .device)
            await locationInjector.abandonAdoptedSession(receipt, stableDeviceID: device.id)
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
            await locationInjector.abandonAdoptedSession(receipt, stableDeviceID: device.id)
            return false
        }

        stagedStartAfterClear = nil
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
        guard let pending = pendingApplications.removeValue(forKey: receipt.requestID) else { return }
        stagedStartAfterClear = nil
        simulation.currentLocation = receipt.coordinate
        simulation.targetLocation = receipt.coordinate
        // A paused run stays paused when the point in flight lands.
        if stopRun == nil { simulation.isPaused = false }
        simulation.isSimulating = true

        // The stop index advances only on the acknowledged arrival at that stop, and only
        // while the mode and its stops are the ones the run began with (appending Jump
        // stops keeps the index).
        if let arrival = pending.stopArrival, activeMode == pending.mode {
            let stopsUnchanged = pending.mode == .jump
                ? currentRoute.starts(with: arrival.routeSnapshot)
                : currentRoute == arrival.routeSnapshot
            if stopsUnchanged {
                setStopCursor(arrival.cursor, for: pending.mode)
                if pending.mode != .jump { routeSequenceArrived = true }
            }
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
        await stopAutomaticReconnectForQuit()
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
        if choice != .cancel {
            await stopAutomaticReconnectForQuit()
        }
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
        // A new point replaces a Clear's staged start, except in Two-Spot while one spot
        // is picked: the staged start is then where the traversal leaves from.
        if mode != .twospot { stagedStartAfterClear = nil }

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
                stagedStartAfterClear = nil
                statusMessage = "Destination spot set"
            } else if currentLocation != nil {
                statusMessage = "Spot set: Move travels there from the current location, or click a second spot"
            } else if stagedStartAfterClear != nil {
                statusMessage = "Spot set: Move travels there from the staged spot, or click a second spot"
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
        if stopRun != nil {
            endStopRun("the stops were reset")
        } else {
            simulationTask?.cancel()
            simulationTask = nil
        }
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

    // MARK: Stop-by-stop engine (Jump, Two-Spot, Multi-Spot; PRODUCT_REQUIREMENTS 3.2-3.4, 3.6)

    /// One Move in a stop mode: the next stop (one stop per Move) or every remaining stop
    /// (every stop automatically), travelled or jumped to per the mode's options.
    private func startStopMove() async {
        // A second Move while a run starts or runs is the double click, not a restart.
        guard !isMovementEngineRunning, stopRun == nil, !isAwaitingEngineUnwind else {
            Logger.info("[Move] Not started: the movement engine is already running", category: .session)
            return
        }
        let mode = activeMode
        // A run that an edit, Stop or a mode change ended is cancelled but may still be
        // finishing its last apply at the bridge: wait for it, so the new run never
        // overlaps it (the race the one-shot path hit). A cancelled run returns promptly:
        // pauses, countdowns and road fetches end on cancellation. A Clear meanwhile wins.
        if let unwinding = unwindingEngineTask {
            isAwaitingEngineUnwind = true
            await unwinding.value
            isAwaitingEngineUnwind = false
            if unwindingEngineTask == unwinding { unwindingEngineTask = nil }
            guard canBeginLocationOperation, activeMode == mode,
                  !isMovementEngineRunning, stopRun == nil else {
                Logger.info("[Move] Not started: a Clear, a mode change or another Move came first", category: .session)
                return
            }
        }
        let settings = stopTravelSettings(for: mode)
        var cursor = stopCursor(for: mode)
        // One stop per Move continues the stop sequence an acknowledged arrival began,
        // also after Loop or Back and forth wrapped the index to the first stop.
        var continuesSequence = mode != .jump && settings.progression == .onePerMove
            && routeSequenceArrived && routeRunStops != nil
        let stops: [LocationCoordinate]
        if continuesSequence, let remembered = routeRunStops {
            stops = remembered
        } else {
            // Two-Spot with one spot leaves from the held location, or from the start a
            // Clear staged (PRODUCT_REQUIREMENTS 3.3, 5.2).
            switch StopTravelPlanner.runStops(mode: mode, route: currentRoute, held: currentLocation ?? stagedStartAfterClear, target: targetLocation) {
            case .success(let resolved):
                stops = resolved
            case .failure(let error):
                failMove(mode, error.message)
                return
            }
        }
        if mode != .jump {
            // A run through every stop replays from the first stop, as routes always did;
            // so does a finished one-way run of one stop per Move.
            if settings.progression == .automatic
                || (settings.repeatMode == .oneWay && StopTravelPlanner.isFinished(cursor, stopCount: stops.count)) {
                cursor = StopCursor()
                route.routeStopCursor = cursor
                routeSequenceArrived = false
                continuesSequence = false
            }
            if !continuesSequence { routeRunStops = stops }
        }
        // Jump leaves from where the device is; Two-Spot and Multi-Spot place the first
        // stop of a new sequence and continue from the stop they reached.
        let origin = mode == .jump || continuesSequence ? currentLocation : nil
        guard let firstLeg = StopTravelPlanner.firstLeg(stops: stops, origin: origin, cursor: cursor, settings: settings) else {
            failMove(mode, "All hops done — add another or clear")
            return
        }
        if let refusal = StopTravelPlanner.straightLineRefusal(
            stops: stops,
            origin: origin,
            cursor: cursor,
            settings: settings,
            metersPerSecond: effectiveMetersPerSecond,
            updateHz: updateFrequencyHz
        ) {
            failMove(mode, refusal.message)
            return
        }

        if StopTravelPlanner.isSingleImmediateJump(firstLeg, settings: settings) {
            // One teleport with no wait: the classic single hop, applied directly.
            Logger.info("[Move] \(mode): stop \(firstLeg.stopIndex + 1) of \(stops.count)", category: .session)
            isPaused = false
            isOneShotMoveInFlight = true
            defer { isOneShotMoveInFlight = false }
            await applyPlannedLocation(
                firstLeg.to,
                mode: mode,
                stopArrival: StopArrival(cursor: firstLeg.cursorAfter, routeSnapshot: currentRoute)
            )
            return
        }
        Logger.info(
            "[Move] \(mode): stop run from stop \(firstLeg.stopIndex + 1) of \(stops.count) " +
            "(\(settings.arrival), \(settings.jumpTiming), hold \(settings.holdSeconds) s, " +
            "\(settings.progression), \(settings.repeatMode))",
            category: .session
        )
        await runStops(mode: mode, stops: stops, firstLeg: firstLeg, settings: settings)
    }

    private func failMove(_ mode: AppMode, _ message: String) {
        Logger.info("[Move] \(mode): \(message)", category: .session)
        lastError = message
        statusMessage = message
    }

    private struct StopRunPace {
        /// One applied point per update.
        let interval: TimeInterval
        let metersPerSecond: Double
        let updateHz: Double
        /// The travel mode the leg's directions are asked for.
        let speed: SimulationSpeed
    }

    /// Runs one stop run to its end (or until Stop, Clear, a loss, a failed step, or a
    /// change of mode, stops or options). The speed and rate are frozen at Move: changing
    /// the rate mid-route changed the travelled speed (review 2026-11-01).
    private func runStops(
        mode: AppMode,
        stops: [LocationCoordinate],
        firstLeg: StopTravelLeg,
        settings: StopTravelSettings
    ) async {
        let operationGeneration = locationOperationGeneration
        let run = StopRun(id: UUID(), mode: mode, stops: stops, routeSnapshot: currentRoute, settings: settings)
        simulationTask?.cancel()
        joystickTask?.cancel()
        joystickTask = nil
        isPaused = false
        stopRun = run
        if mode != .jump {
            isSimulating = false
            route.beginAcknowledgedPlayback()
        }
        await locationBridge.setQueueStrategy(.sequential)
        guard stopRun?.id == run.id, locationClearTask == nil,
              operationGeneration == locationOperationGeneration else {
            if stopRun?.id == run.id { stopRun = nil }
            return
        }

        let pace = StopRunPace(
            interval: 1.0 / max(updateFrequencyHz, 1),
            metersPerSecond: effectiveMetersPerSecond,
            updateHz: updateFrequencyHz,
            speed: SimulationSpeed.directionsTravel(
                autoSpeed: autoSpeed,
                preset: simulationSpeed,
                metersPerSecond: effectiveMetersPerSecond
            )
        )
        let provider = legPathProvider
        routePlaybackID = run.id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.driveStopRun(run, firstLeg: firstLeg, pace: pace, provider: provider)
        }
        simulationTask = task
        await task.value
        if routePlaybackID == run.id {
            simulationTask = nil
            routePlaybackID = nil
        }
    }

    /// The engine: one leg at a time, fetching each leg's path just before it. The held
    /// location, route progress and the stop index follow acknowledged receipts only.
    private func driveStopRun(
        _ run: StopRun,
        firstLeg: StopTravelLeg,
        pace: StopRunPace,
        provider: (@Sendable (LocationCoordinate, LocationCoordinate, SimulationSpeed) async -> LegPath)?
    ) async {
        let movementMode = run.mode.locationMode ?? .multiSpot
        let tracksRouteProgress = run.mode != .jump
        var engaged = false
        var lastApplyStarted: Date?

        func isCurrent() -> Bool {
            !Task.isCancelled && stopRun?.id == run.id
        }

        func publish(
            _ phase: StopProgress.Phase,
            next: Int,
            legSecondsLeft: TimeInterval?,
            holdSecondsLeft: TimeInterval? = nil,
            heldStop: Int? = nil,
            path: LegPath?
        ) {
            guard stopRun?.id == run.id else { return }
            stopProgress = StopProgress(
                nextStopIndex: next,
                totalStops: run.stops.count,
                legSecondsLeft: legSecondsLeft,
                holdSecondsLeft: holdSecondsLeft,
                heldStopIndex: heldStop,
                // A straight line is a fallback only when the router said why (its
                // same-place result has no note: nothing was missing). A road route's
                // own note (a detour, a long route) is shown as information.
                usesStraightLineFallback: path.map { !$0.followsRoads && $0.note != nil } ?? false,
                fallbackNote: path.flatMap { $0.followsRoads ? nil : $0.note },
                isPaused: isPaused,
                routeNote: path.flatMap { $0.followsRoads ? $0.note : nil },
                phase: phase
            )
        }

        // Route progress (Two-Spot, Multi-Spot): acknowledged points over the points of
        // this lap (up to one leg per stop), estimated in straight lines until each leg's
        // path is known.
        var lapAcknowledged = 0
        var lapTotal = 0
        var lapLegsLeft = 0
        func beginLap(at first: StopTravelLeg, restart: Bool) {
            var legs = 0
            var total = 0
            var next: StopTravelLeg? = first
            while let current = next, legs < max(run.stops.count, 1) {
                total += StopTravelPlanner.estimatedPointCount(
                    for: current, settings: run.settings,
                    metersPerSecond: pace.metersPerSecond, updateHz: pace.updateHz
                )
                legs += 1
                next = StopTravelPlanner.leg(after: current, stops: run.stops, settings: run.settings)
            }
            lapAcknowledged = 0
            lapTotal = total
            lapLegsLeft = legs
            if restart {
                route.beginAcknowledgedPlayback()
                // A new lap begun while paused stays paused until Resume.
                if isPaused { route.pausePlayback() }
            }
        }

        /// Ends the run where it stands after a failed step; nothing more is sent. The
        /// run is over, so movement is not left Paused (there is nothing to resume) and a
        /// pause the user set ends with it. The last acknowledged point holds.
        func stopAfterFailure() {
            isSimulating = currentLocation != nil
            switch locationSessionCoordinator.state.movement {
            case .moving, .paused:
                locationSessionCoordinator.stopMovement()
            case .idle, .completed:
                break
            }
            if tracksRouteProgress { route.pausePlayback() }
            stopRun = nil
            stopProgress = nil
            isPaused = false
        }

        /// Waits out `seconds` in ticks of at most 1 s, so Pause stops the countdown.
        func countdown(_ seconds: TimeInterval, report: (TimeInterval) -> Void) async -> Bool {
            var remaining = seconds
            lastApplyStarted = nil
            while remaining > 1e-9 {
                report(remaining)
                await waitWhilePaused()
                guard isCurrent() else { return false }
                let tick = min(remaining, 1)
                await routeDelay(tick)
                guard isCurrent() else { return false }
                remaining -= tick
            }
            return true
        }

        /// Applies one point. An arrival moves the stop index when its receipt is
        /// acknowledged (in `commitAcknowledgedReceipt`, so a late receipt counts too).
        func apply(_ coordinate: LocationCoordinate, arrivalAt arrivalLeg: StopTravelLeg?) async -> Bool {
            await waitWhilePaused()
            guard isCurrent() else { return false }
            // One point per update interval, counted from when the previous step began,
            // so the device round trip does not slow the shown travel speed.
            if let lastApplyStarted {
                let remaining = pace.interval - Date().timeIntervalSince(lastApplyStarted)
                if remaining > 0 { await routeDelay(remaining) }
                await waitWhilePaused()
                guard isCurrent() else { return false }
            }
            lastApplyStarted = Date()
            let arrival = arrivalLeg.map { StopArrival(cursor: $0.cursorAfter, routeSnapshot: run.routeSnapshot) }
            guard await applyPlannedLocation(coordinate, mode: run.mode, stopArrival: arrival) != nil else {
                if isCurrent() { stopAfterFailure() }
                return false
            }
            guard isCurrent() else { return false }
            if !engaged {
                locationSessionCoordinator.beginMovement(movementMode)
                if isPaused { locationSessionCoordinator.pauseMovement() }
                engaged = true
            }
            if tracksRouteProgress {
                lapAcknowledged += 1
                route.acknowledgeWaypoint(at: lapAcknowledged - 1, totalCount: max(lapTotal, lapAcknowledged))
            }
            // Something else moved the stop index: the run no longer knows where it is.
            if let arrivalLeg, stopCursor(for: run.mode) != arrivalLeg.cursorAfter {
                endStopRun("the stop index moved")
                return false
            }
            return true
        }

        if tracksRouteProgress { beginLap(at: firstLeg, restart: false) }
        var leg: StopTravelLeg? = firstLeg
        while let current = leg {
            guard isCurrent() else { return }
            let following = StopTravelPlanner.leg(after: current, stops: run.stops, settings: run.settings)

            // The leg's road path, fetched now (never every leg up front).
            var path: LegPath?
            if StopTravelPlanner.needsPath(current, settings: run.settings), let from = current.from {
                publish(.findingRoute, next: current.stopIndex, legSecondsLeft: nil, path: nil)
                if let provider {
                    path = await provider(from, current.to, pace.speed)
                    guard isCurrent() else { return }
                } else {
                    path = .straight(from: from, to: current.to)
                }
            }

            let steps: [StopTravelStep]
            switch StopTravelPlanner.steps(
                for: current, path: path, settings: run.settings,
                metersPerSecond: pace.metersPerSecond, updateHz: pace.updateHz
            ) {
            case .success(let planned):
                steps = planned
            case .failure(let error):
                lastError = error.message
                statusMessage = error.message
                endStopRun("leg to stop \(current.stopIndex + 1) refused: \(error.message)")
                return
            }

            for step in steps {
                switch step {
                case .travel(let points, _):
                    if tracksRouteProgress {
                        lapTotal += points.count - StopTravelPlanner.estimatedPointCount(
                            for: current, settings: run.settings,
                            metersPerSecond: pace.metersPerSecond, updateHz: pace.updateHz
                        )
                    }
                    for (index, point) in points.enumerated() {
                        publish(
                            .travelling,
                            next: current.stopIndex,
                            legSecondsLeft: Double(points.count - index) * pace.interval,
                            path: path
                        )
                        guard await apply(point, arrivalAt: index == points.count - 1 ? current : nil) else { return }
                    }
                case .jump(let destination, _, let waitBefore):
                    if waitBefore > 0 {
                        let waited = await countdown(waitBefore) { left in
                            publish(.waitingToJump, next: current.stopIndex, legSecondsLeft: left, path: path)
                        }
                        guard waited else { return }
                    }
                    publish(.jumping, next: current.stopIndex, legSecondsLeft: 0, path: path)
                    guard await apply(destination, arrivalAt: current) else { return }
                case .hold(let stop, let seconds):
                    let held = await countdown(seconds) { left in
                        publish(
                            .holding,
                            next: following?.stopIndex ?? stop,
                            legSecondsLeft: nil,
                            holdSecondsLeft: left,
                            heldStop: stop,
                            path: nil
                        )
                    }
                    guard held else { return }
                }
            }

            if tracksRouteProgress {
                lapLegsLeft -= 1
                if lapLegsLeft <= 0, let following { beginLap(at: following, restart: true) }
            }
            leg = following
        }

        // The Move is done; the last stop it reached holds.
        guard isCurrent() else { return }
        if engaged { locationSessionCoordinator.completeMovement() }
        let reachedCursor = stopCursor(for: run.mode)
        if tracksRouteProgress {
            isSimulating = false
            route.completeAcknowledgedPlayback()
            statusMessage = run.settings.progression == .onePerMove
                ? "Holding stop \(min(firstLeg.stopIndex + 1, run.stops.count)) of \(run.stops.count)"
                : "Route playback complete"
        } else if StopTravelPlanner.isFinished(reachedCursor, stopCount: run.stops.count) {
            statusMessage = "All jumps done; holding the last stop"
        }
        Logger.info("[Stops] \(run.mode.rawValue) run complete; holding the last stop", category: .session)
        stopRun = nil
        stopProgress = nil
    }

    /// Ends the running stop run and holds the last applied point.
    private func endStopRun(_ reason: String) {
        guard let run = stopRun else { return }
        Logger.info("[Stops] \(run.mode.rawValue) run ended (\(reason)); holding the last applied point", category: .session)
        simulationTask?.cancel()
        simulationTask = nil
        routePlaybackID = nil
        stopRun = nil
        stopProgress = nil
        isPaused = false
        // Completed only if a stop was actually reached (nothing moved otherwise).
        switch locationSessionCoordinator.state.movement {
        case .moving, .paused:
            locationSessionCoordinator.completeMovement()
        case .idle, .completed:
            break
        }
        if route.playbackState.isActive { route.pausePlayback() }
    }

    /// Waits while paused, without polling; Resume, Stop, Clear or cancellation lets it go.
    private func waitWhilePaused() async {
        while isPaused, !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled || !isPaused {
                        continuation.resume()
                    } else {
                        pauseWaiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.pauseWaiters.removeValue(forKey: id)?.resume()
                }
            }
        }
    }

    private func releasePauseWaiters() {
        let waiters = Array(pauseWaiters.values)
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func stopCursor(for mode: AppMode) -> StopCursor {
        mode == .jump
            ? StopCursor(nextIndex: jumpIndex, reversed: route.jumpReversed)
            : route.routeStopCursor
    }

    private func setStopCursor(_ cursor: StopCursor, for mode: AppMode) {
        if mode == .jump {
            route.jumpIndex = cursor.nextIndex
            route.jumpReversed = cursor.reversed
        } else {
            route.routeStopCursor = cursor
        }
    }

    /// Two-Spot / Multi-Spot one-stop-per-Move progress starts over (mode change).
    private func resetRouteStopProgress() {
        route.routeStopCursor = StopCursor()
        routeRunStops = nil
        routeSequenceArrived = false
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
                    speedMetersPerSecond: self.joystickSpeed,
                    deltaTime: interval
                )
                if next != acknowledged {
                    let receipt = await self.applyPlannedLocation(next, mode: .joystick)
                    if receipt != nil {
                        self.lastJoystickHeadingDegrees = JoystickReadout.degrees(direction)
                    }
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
            pendingApplications.removeValue(forKey: requestID)
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

    /// The speed of the movement under way, for the telemetry readouts: Joystick's own
    /// speed while the joystick moves, the travel speed for other movement, else 0.
    var shownMovementSpeedMetersPerSecond: Double {
        let presentation = locationPresentation
        guard presentation.isMovementActive, !presentation.isMovementPaused else { return 0 }
        if case .moving(.joystick) = locationSessionCoordinator.state.movement { return joystickSpeed }
        return effectiveMetersPerSecond
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
            // Stop Tunnel (or a transport switch) is the user's: nothing reconnects until
            // an explicit Start, Move or Reconnect. Reconnect's own tunnel restart is not
            // a Stop: it is the user asking to reconnect.
            if reconnectTask == nil {
                isAutomaticReconnectLatchedByUser = true
            }
            cancelAutomaticReconnect(reason: "Tunnel stopped")
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
            cancelAutomaticReconnect(reason: event.reason)
            return
        }
        if automaticRecoveryEnabled {
            startLocationRecovery(establishSession: establishRecoverySession)
        }
        // No burst could start now (or a burst is not allowed here): wait for the phone.
        // A burst that did start arms the wait itself if it is exhausted.
        if locationRecoveryTask == nil {
            armAutomaticReconnectIfEligible(afterFailedBurst: false)
        }
    }

    /// Rebuilds the lost session over a verified transport (the burst then reapplies).
    private var establishRecoverySession: @MainActor (Int, LocationSessionIdentity?) async throws -> LocationSessionIdentity {
        { [weak self] _, previous in
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
        // Recovery reapplies a location the device held. A point staged after a Clear (or
        // only selected) has no receipt: it is sent by Move, never automatically
        // (PRODUCT_REQUIREMENTS 5.2).
        guard canBeginLocationOperation,
              locationSessionCoordinator.state.desiredLocation != nil,
              locationSessionCoordinator.state.lastAcknowledgedReceipt != nil,
              locationRecoveryTask == nil else { return }
        let strategy = strategy ?? reliabilityManager.strategy
        // The same Developer Disk Image gate as every Move (`applyPlannedLocation`): a
        // phone that rebooted while away has none mounted, and the reapply would then be
        // acknowledged while the phone stays on its real location.
        let prepareSession: (@MainActor (LocationSessionIdentity) async throws -> Void)?
        if let preparer = ddiPreparer {
            prepareSession = { candidate in
                do {
                    try await preparer.ensureMounted(udid: candidate.stableDeviceID)
                } catch {
                    Logger.error(
                        "[Recovery] DDI mount failed: " + LogRedaction.redactingDeviceIdentifiers("\(error)"),
                        category: .device
                    )
                    throw error
                }
            }
        } else {
            prepareSession = nil
        }
        locationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.locationSessionCoordinator.recover(
                strategy: strategy,
                establishSession: establishSession,
                prepareSession: prepareSession
            )
            self.locationRecoveryTask = nil
            self.reportLocationRecoveryResult(result)
        }
    }

    /// Words for the user instead of the enum ("recoveryExhausted" was shown before).
    /// An exhausted burst after a loss the user did not cause keeps waiting for the phone.
    private func reportLocationRecoveryResult(_ result: LocationSessionTransitionError?) {
        guard let result, result != .recoveryCancelled else { return }
        Logger.info("[Recovery] Burst ended: \(result)", category: .session)
        if result == .recoveryExhausted {
            armAutomaticReconnectIfEligible(afterFailedBurst: true)
        }
        if isAwaitingAutomaticReconnect {
            statusMessage = Self.automaticReconnectWaitingText
        } else {
            lastError = "Couldn't reconnect to the phone. Make sure it is unlocked and on this Wi‑Fi or connected by USB, then press Reconnect."
        }
    }

    // MARK: Automatic reconnect (PRODUCT_REQUIREMENTS §7.3)

    static let automaticReconnectWaitingText =
        "Connection lost — PathChanger reconnects and reapplies the location when the phone is back on Wi‑Fi or USB. Keep it unlocked, or press Reconnect."
    static let automaticReconnectingText =
        "Reconnecting to the phone and reapplying the location…"

    /// PathChanger is reopening the tunnel itself after a loss the user did not cause.
    var isTunnelAutoReconnecting: Bool {
        tunnelAutoReconnector.isReconnecting
    }

    /// The last automatic tunnel attempt's failure while reconnecting, for the notice.
    var tunnelReconnectLastAttemptError: String? {
        tunnelAutoReconnector.lastAttemptError
    }

    /// A Start replaced a stalled helper connection, which ended a location held on it.
    /// While a recovery burst owns the session it is not a new loss (review 2026-11-03
    /// issue 6): the burst is already reconnecting and reapplies over the replacing
    /// connection, and reporting it dropped the burst's pending request, so a reapply the
    /// phone applied was rejected. A burst that already ended has cleared its task first,
    /// so a replacement after its reapply is still reported.
    func helperConnectionReplaced(deviceId: String) {
        guard selectedDevice?.id == deviceId,
              locationSessionCoordinator.state.lastAcknowledgedReceipt != nil else { return }
        guard locationRecoveryTask == nil else {
            Logger.info("[Recovery] The helper connection was replaced during a recovery burst; the burst reapplies over it", category: .session)
            return
        }
        handleLocationSessionLoss(.endpointReplaced)
    }

    /// Stop on the tunnel pill or in Settings while the tunnel reconnects by itself
    /// (review 2026-11-03 issue 1): Stop Tunnel, which latches the tunnel reconnect, and the
    /// same hold on the location reconnect a Stop of a live tunnel sets, whose burst would
    /// otherwise reopen the helper connection behind the Stop. Start, Move or Reconnect
    /// lifts both.
    func stopTunnelReconnect() {
        Logger.info("[TunnelReconnect] Stop pressed while reconnecting", category: .device)
        isAutomaticReconnectLatchedByUser = true
        cancelAutomaticReconnect(reason: "Stop pressed while the tunnel reconnected")
        locationRecoveryTask?.cancel()
        locationRecoveryTask = nil
        tunnelAutoReconnect.tunnel.stopTunnel()
        statusMessage = "Stopped reconnecting. Press Start to connect again."
    }

    /// The user selected another phone while the tunnel reconnects to the lost one: stop
    /// that reconnect instead of reopening a phone nobody selected (review 2026-11-03
    /// issue 9). Only a UDID is compared: an endpoint alias may be the same phone.
    private func stopTunnelReconnectIfAnotherPhoneIsSelected(_ selected: Device) {
        guard tunnelAutoReconnector.isReconnecting,
              ArgumentSanitizer.isValidDeviceUDID(selected.id),
              let reconnecting = tunnelAutoReconnect.tunnel.reconnectDeviceId,
              reconnecting != selected.id else { return }
        Logger.info("[TunnelReconnect] Another phone was selected; stopping the reconnect to the lost one", category: .device)
        tunnelAutoReconnect.tunnel.stopTunnel()
        statusMessage = "Stopped reconnecting to the previous iPhone because you selected \(selected.displayName). Press Start to connect to it."
    }

    static let preparingDeviceForLocationText =
        "Preparing the iPhone for location (this can take up to two minutes the first time)…"
    static let stillPreparingDeviceForLocationText =
        "Still preparing the iPhone for location (this can take up to two minutes the first time). Your Move runs when it is ready."

    /// Plain words for the GUI while PathChanger waits for (or is reconnecting to) the phone.
    var automaticReconnectNotice: String? {
        guard isAwaitingAutomaticReconnect else { return nil }
        let state = locationSessionCoordinator.state
        if case .reconnecting = state.connection { return Self.automaticReconnectingText }
        if case .applying = state.application { return Self.automaticReconnectingText }
        return Self.automaticReconnectWaitingText
    }

    private func automaticReconnectDecision() -> AutoReconnectPolicy.Decision {
        let state = locationSessionCoordinator.state
        return AutoReconnectPolicy.evaluate(AutoReconnectPolicy.Inputs(
            isEnabled: automaticReconnect.isEnabled,
            usesHelperConnection: automaticReconnect.usesHelperConnection(),
            isLatchedByUser: isAutomaticReconnectLatchedByUser,
            hasClearPending: !canBeginLocationOperation,
            application: state.application,
            hasAcknowledgedReceipt: state.lastAcknowledgedReceipt != nil,
            awaitedDeviceID: locationSessionCoordinator.recoverableDeviceID,
            selectedDeviceID: selectedDevice?.id
        ))
    }

    /// Start waiting for the lost phone, when the policy allows it. Idempotent.
    private func armAutomaticReconnectIfEligible(afterFailedBurst: Bool) {
        guard automaticReconnectTask == nil else { return }
        let decision = automaticReconnectDecision()
        guard case .wait(let deviceID) = decision else {
            Logger.debug("[AutoReconnect] Not waiting: \(decision)", category: .session)
            return
        }
        automaticReconnectID &+= 1
        let id = automaticReconnectID
        isAwaitingAutomaticReconnect = true
        // A loss pauses a moving run, but every engine was cancelled: while waiting no
        // movement runs (the location holds), so Movement is not left Paused (§4.4).
        switch locationSessionCoordinator.state.movement {
        case .moving, .paused:
            locationSessionCoordinator.stopMovement()
        case .idle, .completed:
            break
        }
        device.awaitedReconnectDeviceID = deviceID
        automaticReconnectWaiter.discardPendingSignal()
        if isAwaitedDeviceVisible(deviceID) {
            automaticReconnectWaiter.signalReachable()
        }
        statusMessage = Self.automaticReconnectWaitingText
        Logger.info(
            "[AutoReconnect] Waiting for " + LogRedaction.redactingDeviceIdentifiers(deviceID)
                + " to come back" + (afterFailedBurst ? " after an exhausted burst" : ""),
            category: .session
        )
        let lastBurstEnded = afterFailedBurst ? automaticReconnect.now() : nil
        automaticReconnectTask = Task { @MainActor [weak self] in
            await self?.runAutomaticReconnect(
                id: id,
                deviceID: deviceID,
                failedBursts: afterFailedBurst ? 1 : 0,
                lastBurstEnded: lastBurstEnded
            )
        }
    }

    private func isAwaitedDeviceVisible(_ deviceID: String) -> Bool {
        device.usbDirectDeviceIds.contains(deviceID)
            || device.wifiDirectDeviceIds.contains(deviceID)
            || device.networkAdvertisedDeviceIds.contains(deviceID)
    }

    /// Wait for the phone (or the fallback timer), respect the spacing, run one burst;
    /// repeat with backoff until the reapply is acknowledged or the wait is cancelled.
    private func runAutomaticReconnect(
        id: UInt64,
        deviceID: String,
        failedBursts initialFailures: Int,
        lastBurstEnded initialBurstEnd: Date?
    ) async {
        defer {
            if automaticReconnectID == id { finishAutomaticReconnect() }
        }
        var failedBursts = initialFailures
        var lastBurstEnded = initialBurstEnd
        while !Task.isCancelled {
            let wake = await automaticReconnectWaiter.wait(
                timeout: AutoReconnectSchedule.fallbackDelay(afterFailedBursts: failedBursts),
                sleeper: automaticReconnect.sleeper
            )
            guard wake != .cancelled, !Task.isCancelled else { return }
            if let lastBurstEnded {
                let earliest = lastBurstEnded.addingTimeInterval(
                    AutoReconnectSchedule.spacing(afterFailedBursts: failedBursts)
                )
                let remaining = earliest.timeIntervalSince(automaticReconnect.now())
                if remaining > 0 {
                    do {
                        try await automaticReconnect.sleeper.sleep(seconds: remaining)
                    } catch {
                        return
                    }
                }
            }
            guard !Task.isCancelled else { return }
            let decision = automaticReconnectDecision()
            guard case .wait(let current) = decision, current == deviceID else {
                Logger.info(
                    "[AutoReconnect] Stopped waiting: "
                        + LogRedaction.redactingDeviceIdentifiers(String(describing: decision)),
                    category: .session
                )
                // The lost session is another device's now: wait for that one instead.
                if case .wait = decision, automaticReconnectID == id {
                    finishAutomaticReconnect()
                    armAutomaticReconnectIfEligible(afterFailedBurst: false)
                }
                return
            }

            Logger.info(
                "[AutoReconnect] " + (wake == .reachable ? "The phone is visible again" : "Fallback timer")
                    + "; reconnecting (burst \(failedBursts + 1))",
                category: .session
            )
            automaticReconnectWaiter.discardPendingSignal()
            if locationRecoveryTask == nil {
                startLocationRecovery(strategy: automaticReconnect.burstStrategy, establishSession: establishRecoverySession)
            }
            guard let burst = locationRecoveryTask else {
                Logger.info("[AutoReconnect] Stopped waiting: no burst could start", category: .session)
                return
            }
            await withTaskCancellationHandler {
                await burst.value
            } onCancel: {
                burst.cancel()
            }
            guard !Task.isCancelled else { return }
            if locationSessionCoordinator.state.application.isActive {
                Logger.info("[AutoReconnect] Reconnected; the held location is applied again", category: .session)
                statusMessage = "Reconnected — the location is applied again"
                return
            }
            lastBurstEnded = automaticReconnect.now()
            failedBursts += 1
        }
    }

    private func finishAutomaticReconnect() {
        automaticReconnectTask = nil
        isAwaitingAutomaticReconnect = false
        device.awaitedReconnectDeviceID = nil
        automaticReconnectWaiter.discardPendingSignal()
    }

    /// Stop waiting at once (its in-flight burst is cancelled and unwinds on its own).
    private func cancelAutomaticReconnect(reason: String) {
        guard let task = automaticReconnectTask else { return }
        task.cancel()
        automaticReconnectID &+= 1
        finishAutomaticReconnect()
        Logger.info("[AutoReconnect] Stopped waiting: \(reason)", category: .session)
    }

    /// Stop waiting and wait until its burst (if any) has unwound, so the caller is the
    /// only one driving the location session afterwards.
    func stopAutomaticReconnect(reason: String) async {
        guard let task = automaticReconnectTask else { return }
        cancelAutomaticReconnect(reason: reason)
        await task.value
    }

    /// Quit's own stop: cancels the wait and its burst, but waits for the burst at most
    /// `quitReconnectWaitLimit`. A helper command already sent finishes on its own timeout
    /// (40 s connect, 12 s location); Quit shuts the helper down next anyway.
    static let quitReconnectWaitLimit: TimeInterval = 2

    private func stopAutomaticReconnectForQuit() async {
        // Quit stops the tunnel next; nothing may reopen it meanwhile.
        tunnelAutoReconnector.cancel()
        guard let task = automaticReconnectTask else { return }
        cancelAutomaticReconnect(reason: "Quit")
        let finished = await Self.wait(for: task, atMost: Self.quitReconnectWaitLimit)
        if !finished {
            Logger.info("[AutoReconnect] Quit did not wait for the cancelled burst's helper command", category: .session)
        }
    }

    /// True when `task` ended within `seconds`, false when the time ran out first.
    private static func wait(for task: Task<Void, Never>, atMost seconds: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                once.resume(false)
            }
            Task { @MainActor in
                await task.value
                timer.cancel()
                once.resume(true)
            }
        }
    }
}

/// Resumes a continuation with the first value only.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
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
