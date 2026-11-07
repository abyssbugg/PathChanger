//
//  ContentView.swift
//  PathChanger
//
//  Map-first Organic shell from the pctnhc mock.
//

import SwiftUI
import MapKit
import Combine
import AppKit

/// The notice under the tunnel pill. A failed tunnel's error comes first: a reconnect
/// notice shown alone hid why Start failed (review 2026-11-02); with both, both show.
struct TunnelNotice: Equatable {
    let text: String
    let isError: Bool

    static let waitingForDeviceText =
        "Waiting for your iPhone on Wi‑Fi. Unlock it and keep it on this network. Click the tunnel button to cancel."

    static let tunnelReconnectingText =
        "Connection to the iPhone lost. PathChanger keeps trying to reconnect, waiting at most 30 seconds between attempts, until the phone is back or you click the tunnel button to stop. Keep it unlocked and on this Wi‑Fi, or connect the cable."

    static func resolve(
        isWaitingForDevice: Bool,
        isTunnelReconnecting: Bool,
        lastReconnectAttemptError: String? = nil,
        automaticReconnectNotice: String?,
        tunnelError: String?
    ) -> TunnelNotice? {
        // PathChanger reopens the tunnel itself (live 2026-11-03): its own words win over
        // the device wait inside an automatic attempt. The retries never end, so the last
        // attempt's failure shows under them (review 2026-11-03 issue 2): a refusal that
        // lasts hours is visible, not hidden behind "Reconnecting…".
        if isTunnelReconnecting {
            var lines = [tunnelReconnectingText]
            if let lastReconnectAttemptError { lines.append("Last attempt: \(lastReconnectAttemptError)") }
            if let automaticReconnectNotice { lines.append(automaticReconnectNotice) }
            return TunnelNotice(text: lines.joined(separator: "\n"), isError: lastReconnectAttemptError != nil)
        }
        return resolve(isWaitingForDevice: isWaitingForDevice, automaticReconnectNotice: automaticReconnectNotice,
                       tunnelError: tunnelError)
    }

    static func resolve(
        isWaitingForDevice: Bool,
        automaticReconnectNotice: String?,
        tunnelError: String?
    ) -> TunnelNotice? {
        if isWaitingForDevice {
            return TunnelNotice(text: waitingForDeviceText, isError: false)
        }
        if let tunnelError {
            let text = automaticReconnectNotice.map { "\(tunnelError)\n\($0)" } ?? tunnelError
            return TunnelNotice(text: text, isError: true)
        }
        // After a loss the user did not cause, PathChanger waits for the phone itself.
        return automaticReconnectNotice.map { TunnelNotice(text: $0, isError: false) }
    }
}

/// What a click on the tunnel pill does, and whether it can be clicked. The pill (with
/// Settings) owns the tunnel: Start, Reconnect tunnel, Stop Reconnecting and Stop. The
/// location area never controls it (owner decision 2026-11-03).
enum TunnelPillAction: Equatable {
    case confirmStop
    case stop
    case stopReconnecting
    /// The tunnel failed: reopen it without stopping anything (`AppState.reconnectTunnel`).
    case reconnect
    case start
    case none

    static func resolve(
        isRunning: Bool,
        requiresLocationQuitDecision: Bool,
        isWaitingForDevice: Bool,
        isStarting: Bool,
        isAutoReconnecting: Bool,
        isError: Bool = false
    ) -> TunnelPillAction {
        if isRunning { return requiresLocationQuitDecision ? .confirmStop : .stop }
        // Between attempts (idle or error) and inside one (starting), the click stops the
        // automatic reconnect (review 2026-11-03 issue 1).
        if isAutoReconnecting { return .stopReconnecting }
        if isWaitingForDevice { return .stop }
        if isStarting { return .none }
        return isError ? .reconnect : .start
    }

    /// The pill stays clickable while reconnecting even after discovery dropped the lost
    /// phone from the selection: it is the only way to stop the reconnect from the window.
    static func isEnabled(hasSelectedDevice: Bool, isWaitingForDevice: Bool, isAutoReconnecting: Bool) -> Bool {
        hasSelectedDevice || isWaitingForDevice || isAutoReconnecting
    }
}

/// Whether the location area's Reapply location can run, and the plain reason when it
/// cannot (owner decision 2026-11-03: the location area reapplies over the current
/// connection and never controls the tunnel).
enum LocationReapplyAvailability: Equatable {
    case available
    case unavailable(reason: String)

    static let tunnelNotLiveReason = "Connect first: the tunnel is not live"
    static let nothingHeldReason = "Nothing to reapply: no location is held"
    static let clearingReason = "Clearing the location: wait for Clear to finish"
    static let clearUnresolvedReason = "PathChanger could not confirm the last Clear: press Clear again"
    static let reapplyingReason = "Reapplying the location…"

    static func resolve(
        isReapplying: Bool,
        clearBlock: LocationClearBlock?,
        isTunnelLive: Bool,
        hasHeldLocation: Bool
    ) -> LocationReapplyAvailability {
        if isReapplying { return .unavailable(reason: reapplyingReason) }
        switch clearBlock {
        case .clearInProgress: return .unavailable(reason: clearingReason)
        case .clearUnresolved: return .unavailable(reason: clearUnresolvedReason)
        case nil: break
        }
        // Without a live connection nothing can reach the phone, held location or not.
        guard isTunnelLive else { return .unavailable(reason: tunnelNotLiveReason) }
        guard hasHeldLocation else { return .unavailable(reason: nothingHeldReason) }
        return .available
    }

    /// Offered where the held location may not be on the phone: the connection failed,
    /// or the location is uncertain or lost. A recovery burst (Reconnecting) reapplies by
    /// itself, and a location held over a ready connection needs nothing.
    static func isOffered(connection: LocationConnectionPhase, application: LocationApplicationPhase) -> Bool {
        if case .failed = connection { return true }
        switch application {
        case .uncertain, .lost: return true
        case .idle, .applying, .active, .clearing, .failed: return false
        }
    }

    var isAvailable: Bool { self == .available }

    var disabledReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// What the tunnel pill says. An automatic reconnect reads Reconnecting, never Error
/// (live 2026-11-03).
enum TunnelPillPhase: Equatable {
    case waitingForDevice
    case connecting
    case reconnecting
    case live
    case error
    case stopped

    static func resolve(
        isWaitingForDevice: Bool,
        isStarting: Bool,
        isRunning: Bool,
        isError: Bool,
        isAutoReconnecting: Bool
    ) -> TunnelPillPhase {
        if isRunning { return .live }
        if isAutoReconnecting { return .reconnecting }
        if isWaitingForDevice { return .waitingForDevice }
        if isStarting { return .connecting }
        if isError { return .error }
        return .stopped
    }

    var label: String {
        switch self {
        case .waitingForDevice: return "Waiting for iPhone…"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .live: return "Tunnel live"
        // The notice under the pill says what failed; the pill offers the way back.
        case .error: return "Reconnect tunnel"
        case .stopped: return "Start tunnel"
        }
    }
}

/// What the tunnel pill shows: where the tunnel stands (`statusText`) and, apart from it,
/// what a click does (`actionText`, `action`). The title bar builds the model from live
/// state on every render and acts on its `action`, so a location held over the tunnel
/// still asks before Stop (`.confirmStop`).
struct TunnelPillModel: Equatable {
    let phase: TunnelPillPhase
    let action: TunnelPillAction
    let isEnabled: Bool
    let hasSelectedDevice: Bool

    static func resolve(
        isRunning: Bool,
        requiresLocationQuitDecision: Bool,
        isWaitingForDevice: Bool,
        isStarting: Bool,
        isError: Bool,
        isAutoReconnecting: Bool,
        hasSelectedDevice: Bool
    ) -> TunnelPillModel {
        TunnelPillModel(
            phase: TunnelPillPhase.resolve(
                isWaitingForDevice: isWaitingForDevice, isStarting: isStarting, isRunning: isRunning,
                isError: isError, isAutoReconnecting: isAutoReconnecting
            ),
            action: TunnelPillAction.resolve(
                isRunning: isRunning, requiresLocationQuitDecision: requiresLocationQuitDecision,
                isWaitingForDevice: isWaitingForDevice,
                isStarting: isStarting, isAutoReconnecting: isAutoReconnecting, isError: isError
            ),
            isEnabled: TunnelPillAction.isEnabled(
                hasSelectedDevice: hasSelectedDevice, isWaitingForDevice: isWaitingForDevice,
                isAutoReconnecting: isAutoReconnecting
            ),
            hasSelectedDevice: hasSelectedDevice
        )
    }

    var statusText: String {
        switch phase {
        case .waitingForDevice: return "Waiting for iPhone…"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .live: return "Tunnel live"
        case .error: return "Tunnel failed"
        case .stopped: return "Tunnel off"
        }
    }

    /// The click's words; nil while a Start runs (the click does nothing then).
    var actionText: String? {
        switch action {
        case .confirmStop, .stop: return phase == .waitingForDevice ? "Cancel" : "Stop"
        case .stopReconnecting: return "Stop"
        case .reconnect: return "Reconnect"
        case .start: return "Start tunnel"
        case .none: return nil
        }
    }

    /// VoiceOver reads the button by what it does, then where the tunnel stands.
    var accessibilityLabel: String {
        switch action {
        case .confirmStop, .stop: return phase == .waitingForDevice ? "Cancel waiting for the iPhone" : "Stop tunnel"
        case .stopReconnecting: return "Stop reconnecting"
        case .reconnect: return "Reconnect tunnel"
        case .start: return "Start tunnel"
        case .none: return statusText
        }
    }

    var accessibilityValue: String { statusText }

    /// Something is under way: a spinner instead of the status dot.
    var showsProgress: Bool {
        switch phase {
        case .waitingForDevice, .connecting, .reconnecting: return true
        case .live, .error, .stopped: return false
        }
    }

    /// A stopped tunnel is the one filled call to action in the title bar.
    var isPrimary: Bool { phase == .stopped }
}

extension TunnelNotice {
    /// One line of the notice; the reconnect's "Last attempt" line carries its label apart.
    struct Line: Equatable, Hashable {
        let label: String?
        let text: String
    }

    var lines: [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map { raw in
            let line = String(raw)
            let prefix = "Last attempt: "
            if line.hasPrefix(prefix) {
                return Line(label: "Last attempt", text: String(line.dropFirst(prefix.count)))
            }
            return Line(label: nil, text: line)
        }
    }
}

enum AppMode: String, CaseIterable, Identifiable {
    case teleport = "Teleport"
    case jump = "Jump"
    case twospot = "Two-spot"
    case route = "Multi-Spot"
    case joystick = "Joystick"
    case settings = "Settings"

    var id: String { rawValue }

    static var mapModes: [AppMode] { [.teleport, .jump, .twospot, .route, .joystick] }

    var glyph: OrganicGlyph {
        switch self {
        case .teleport: return .teleport
        case .jump: return .jump
        case .twospot: return .twoSpot
        case .route: return .multiSpot
        case .joystick: return .joystick
        case .settings: return .settings
        }
    }

    /// Legacy system-symbol name for views outside the canonical map-first shell.
    var icon: String {
        switch self {
        case .teleport: return "scope"
        case .jump: return "plus.viewfinder"
        case .twospot: return "arrow.left.and.right"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .joystick: return "figure.stand"
        case .settings: return "gear"
        }
    }

    var description: String {
        switch self {
        case .teleport: return "One acknowledged hop"
        case .jump: return "Numbered hops, one at a time"
        case .twospot: return "Travel between two points"
        case .route: return "Route through many stops"
        case .joystick: return "Steer by hand"
        case .settings: return "App settings"
        }
    }

    var locationMode: LocationMode? {
        switch self {
        case .teleport: return .teleport
        case .jump: return .jumpTeleport
        case .twospot: return .twoSpot
        case .route: return .multiSpot
        case .joystick: return .joystick
        case .settings: return nil
        }
    }
}

extension AppMode {
    var localizedLabel: String {
        NSLocalizedString(locationAccessibilityIdentifier, comment: "Location mode label")
    }

    var locationAccessibilityIdentifier: String {
        switch self {
        case .teleport: return "location.mode.teleport"
        case .jump: return "location.mode.jump"
        case .twospot: return "location.mode.twoSpot"
        case .route: return "location.mode.multiSpot"
        case .joystick: return "location.mode.joystick"
        case .settings: return "location.mode.settings"
        }
    }
}

/// What the window shows when it first appears. The app always opens in Teleport with the
/// card closed (`.standard`); the offscreen GUI snapshots open other states.
struct ContentViewInitialState: Equatable {
    var mode: AppMode = .teleport
    var cardOpen = false
    var showSettings = false

    static let standard = ContentViewInitialState()
}

#if DEBUG
/// Body evaluations of the mounted chrome, for the GUI load benchmark (`GUIUpdateLoadTests`).
enum GUIRenderCounts {
    static var contentView = 0
    static var titleBar = 0
    static var modeCard = 0
    static var statusPanel = 0
}
#endif

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @StateObject private var searchService = LocationSearchService()
    @ObservedObject private var favorites = LocationFavoritesManager.shared

    @State private var selectedMode: AppMode = .teleport
    @State private var showSettings = false
    @State private var showDeviceMenu = false
    @State private var mapStyle: MapStyleType = .standard
    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    @State private var addressText: String = "Tap the map"
    @State private var currentError: ErrorHandler.AppError?
    @State private var showClearConfirmation = false
    @State private var showErrorDialog = false
    @State private var cardOpen = false
    @State private var savedOpen = false
    @State private var savedTab: SavedTab = .favorites
    @State private var showSearchResults = false
    @AppStorage("PathChanger.Appearance") private var appearanceRaw = OrganicAppearance.light.rawValue
    @AppStorage("dismissedCoach") private var dismissedCoach = false
    @State private var coachOpen = true
    private let initialState: ContentViewInitialState

    init(initialState: ContentViewInitialState = .standard) {
        self.initialState = initialState
        // The map's first appearance sets the active mode from this, so it must start as
        // the initial mode (a run of that mode would otherwise end on appear).
        _selectedMode = State(initialValue: initialState.mode)
        _cardOpen = State(initialValue: initialState.cardOpen)
        _showSettings = State(initialValue: initialState.showSettings)
    }

    var body: some View {
#if DEBUG
        let _ = GUIRenderCounts.contentView += 1
#endif
        ZStack {
            Organic.neutral300.ignoresSafeArea()

            VStack(spacing: 0) {
                OrganicTitleBar(
                    appState: appState,
                    showDeviceMenu: $showDeviceMenu,
                    showSettings: $showSettings,
                    appearanceRaw: $appearanceRaw,
                    onRefresh: {
                        Task {
                            await appState.refreshDevices()
                            await appState.checkTunneldStatus()
                        }
                    }
                )
                .equatable()
                .zIndex(2)

                if let notice = tunnelNotice {
                    TunnelNoticeView(text: notice.text, isError: notice.isError)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }

                ZStack(alignment: .topLeading) {
                    SimulationView(
                        mode: selectedMode,
                        mapStyle: $mapStyle,
                        latitudeInput: $latitudeInput,
                        longitudeInput: $longitudeInput,
                        addressText: $addressText,
                        onPickLocation: applyPlace
                    )

                    mapChrome
                }
            }
            .background(Organic.bg)

            if showSettings {
                OrganicSettingsSheet(
                    isPresented: $showSettings,
                    appearanceRaw: $appearanceRaw
                )
                    .zIndex(30)
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Organic.bg)
        .preferredColorScheme(OrganicAppearance.persisted(appearanceRaw).colorScheme)
        .onAppear {
            selectedMode = initialState.mode
            appState.activeMode = initialState.mode
            cardOpen = initialState.cardOpen
            showSettings = initialState.showSettings
            appState.isSettingsPanelShown = showSettings
            Organic.registerFonts()
            syncCoordFields()
            coachOpen = !dismissedCoach && initialState == .standard
        }
        .onChange(of: showSettings) { _, shown in
            appState.isSettingsPanelShown = shown
        }
        .onDisappear { appState.isSettingsPanelShown = false }
        .onChange(of: selectedMode) { oldMode, newMode in
            if newMode != .settings {
                appState.activeMode = newMode
            }
            guard oldMode != newMode else { return }
            // Each mode keeps its own stops: `activeMode` shows the new mode's and keeps
            // every stop mode's progress (owner rule 2026-11-03). It used to truncate the
            // shared list to the new mode's stop limit and clear it for Joystick, which
            // reset every stop mode.
            cardOpen = true
            savedOpen = false
            coachOpen = false
        }
        .onChange(of: appState.locationPresentation.desiredCoordinate) { _, _ in
            syncCoordFields()
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showErrorDialog) {
            if let error = currentError {
                if error.type == .iosVersionUnsupported {
                    IOS18WarningDialogView(
                        deviceVersion: appState.selectedDevice?.iosVersion ?? "18+",
                        onDismiss: {
                            showErrorDialog = false
                            appState.errorHandler.clearCurrentError()
                        },
                        onLearnMore: { url in
                            NSWorkspace.shared.open(url)
                        }
                    )
                } else {
                    EnhancedErrorDialogView(
                        error: error,
                        onDismiss: {
                            showErrorDialog = false
                            appState.errorHandler.clearCurrentError()
                        },
                        onAction: { action in
                            handleErrorAction(action)
                            showErrorDialog = false
                        },
                        onLearnMore: { url in
                            NSWorkspace.shared.open(url)
                        }
                    )
                }
            }
        }
        .onReceive(appState.errorHandler.$currentError) { error in
            if let error = error {
                currentError = error
                showErrorDialog = true
            }
        }
        .withToasts()
    }

    private var mapChrome: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                locationPanel
                if showSearchResults && !searchService.searchResults.isEmpty {
                    searchResults
                }
                Spacer().allowsHitTesting(false)
            }
            .padding(.horizontal, Organic.space4)
            .padding(.top, Organic.space4)
            .zIndex(27)

            if savedOpen {
                SavedPlacesCard(tab: $savedTab, onSelect: applyPlace, onClose: { savedOpen = false })
                    .padding(.leading, ModeContextCard.placementInsets.leading)
                    .padding(.top, ModeContextCard.placementInsets.top)
                    .zIndex(26)
            } else if cardOpen {
                ModeContextCard(
                    mode: $selectedMode,
                    latitudeInput: $latitudeInput,
                    longitudeInput: $longitudeInput,
                    address: addressText,
                    onClose: { cardOpen = false },
                    onMove: performMove,
                    onCommitCoords: commitTeleport
                )
                .padding(ModeContextCard.placementInsets)
                .zIndex(25)
            }

            VStack {
                Spacer().allowsHitTesting(false)
                HStack {
                    handleButton
                    Spacer().allowsHitTesting(false)
                }
                Spacer().allowsHitTesting(false)
            }

            if coachOpen && !cardOpen && !savedOpen {
                coachToast
            }
        }
    }

    /// One panel for finding a place, choosing a mode and reading where the phone stands:
    /// the search field and the mode switcher on top, then Connection, Location, Movement
    /// and the applied coordinate, with Reapply and Clear at the end of that row.
    private var locationPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: Organic.space2) {
                searchField
                modePill
            }
            .padding(LocationPanelMetrics.inset)
            .frame(height: LocationPanelMetrics.topRowHeight)
            Rectangle().fill(Organic.neutral300).frame(height: 1)
            HStack(spacing: Organic.space2) {
                statusCluster
                Spacer(minLength: Organic.space2)
                if let reapply = reapplyLocationButton {
                    reapply
                }
                clearLocationButton
            }
            .padding(.leading, LocationPanelMetrics.inset)
            .padding(.trailing, LocationPanelMetrics.inset + 2)
            .frame(height: LocationPanelMetrics.statusRowHeight)
        }
        .frame(maxWidth: LocationPanelMetrics.maxWidth)
        .background(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .fill(Organic.neutral100)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .strokeBorder(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.10), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Organic.neutral500)
                .accessibilityHidden(true)
            TextField("Search a place or coordinates", text: $searchService.searchText)
                .textFieldStyle(.plain)
                .font(Organic.body(12.5, weight: .medium))
                .onChange(of: searchService.searchText) { _, newValue in
                    showSearchResults = !newValue.isEmpty
                }
                .onSubmit { commitSearch() }
                .accessibilityLabel("Search for a place")
            if searchService.isSearching {
                ProgressView().controlSize(.mini)
            }
            Button(action: commitSearch) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Organic.accentInk)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Organic.accent))
            }
            .buttonStyle(.plain)
            .help("Go to location")
            .accessibilityLabel("Go to location")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minWidth: 220, maxWidth: .infinity)
        .frame(height: 44)
        .background(Capsule().fill(Organic.bg))
        .overlay(Capsule().strokeBorder(Organic.neutral300, lineWidth: 1))
    }

    private var searchResults: some View {
        VStack(spacing: 1) {
            ForEach(searchService.searchResults.prefix(6)) { result in
                Button {
                    applyPlace(result.coordinate, name: result.name)
                    searchService.clearSearch()
                    showSearchResults = false
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "mappin.circle")
                            .foregroundStyle(Organic.accent600)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.name)
                                .font(Organic.body(12, weight: .bold))
                                .lineLimit(1)
                            Text(result.subtitle)
                                .font(Organic.mono(10))
                                .foregroundStyle(Organic.neutral600)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: 360)
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .strokeBorder(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.16), radius: 10, y: 4)
    }

    /// Why the tunnel is not live, in words, without hovering: the pill alone only
    /// said "Tunnel error".
    private var tunnelNotice: (text: String, isError: Bool)? {
        let errorText: String? = {
            if case .error = tunneldManager.state { return tunneldManager.lastError }
            return nil
        }()
        return TunnelNotice.resolve(
            isWaitingForDevice: tunneldManager.isWaitingForDevice,
            isTunnelReconnecting: appState.isTunnelAutoReconnecting && !tunneldManager.isRunning,
            lastReconnectAttemptError: appState.tunnelReconnectLastAttemptError,
            automaticReconnectNotice: appState.automaticReconnectNotice,
            tunnelError: errorText
        ).map { ($0.text, $0.isError) }
    }

    private var displayedConnectionLabel: String {
        appState.connectionChipLabel
    }

    /// The connection phase the chip's color follows: a wait for the lost phone reads as
    /// reconnecting, like its label.
    private var displayedConnectionPhase: LocationConnectionPhase {
        let phase = appState.locationSessionCoordinator.state.connection
        if appState.isAwaitingAutomaticReconnect, case .failed = phase {
            return .reconnecting(previousGeneration: nil, attempt: 0)
        }
        return phase
    }

    /// Connection, Location, Movement and the applied coordinate: three separate states
    /// and the receipt's coordinate, never one combined light. A value view, so the window's
    /// renders redraw it only when one of them changes.
    private var statusCluster: some View {
        let status = appState.locationPresentation
        let state = appState.locationSessionCoordinator.state
        return LocationStatusStrip(cells: [
            .init(titleKey: "location.status.domain.connection", value: displayedConnectionLabel,
                  tone: connectionTone(for: displayedConnectionPhase),
                  localizationKey: "accessibility.location.status.connection", id: "location.status.connection"),
            .init(titleKey: "location.status.domain.application", value: status.applicationLabel,
                  tone: status.isSpoofing ? Organic.sage600 : applicationTone(for: state.application),
                  localizationKey: "accessibility.location.status.application", id: "location.status.application"),
            .init(titleKey: "location.status.domain.movement", value: status.movementLabel,
                  tone: movementTone(for: state.movement),
                  localizationKey: "accessibility.location.status.movement", id: "location.status.movement"),
            // Shown only from an acknowledged receipt; the cell keeps its place without one.
            .init(titleKey: "location.status.domain.applied",
                  value: status.appliedCoordinate != nil ? status.appliedCoordinateLabel : LocationStatusStrip.noCoordinate,
                  tone: status.appliedCoordinate != nil ? Organic.sage600 : Organic.neutral400,
                  localizationKey: "accessibility.location.status.coordinate", id: "location.status.coordinate",
                  isCoordinate: true),
        ])
        .equatable()
    }

    /// The location area's only recovery control: it reapplies the held location over the
    /// current connection and never starts, restarts or stops the tunnel (the tunnel pill
    /// does). Offered only where the held location may not be on the phone; disabled with
    /// a plain reason when the tunnel is not live or nothing is held.
    private var reapplyLocationButton: AnyView? {
        let state = appState.locationSessionCoordinator.state
        guard LocationReapplyAvailability.isOffered(connection: state.connection, application: state.application) else {
            return nil
        }
        let availability = appState.locationReapplyAvailability
        let enabled = availability.isAvailable
        return AnyView(Button {
            Task { await appState.reapplyLocation() }
        } label: {
            Label("Reapply location", systemImage: "arrow.clockwise")
                .font(Organic.body(11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(enabled ? Organic.accent700 : Organic.neutral600)
                .padding(.horizontal, 12)
                .frame(height: LocationPanelMetrics.actionHeight)
                .background(Capsule().fill(enabled ? Organic.accent100 : Organic.neutral200))
                .overlay(Capsule().strokeBorder(enabled ? Organic.accent300 : Organic.neutral300, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!enabled)
        .help(availability.disabledReason ?? "Send the held location to the iPhone again over the current connection")
        .accessibilityLabel("Reapply location")
        .accessibilityHint(availability.disabledReason ?? "Sends the held location to the iPhone again over the current connection")
        .accessibilityIdentifier("location.action.reapply"))
    }

    private var clearLocationButton: some View {
        let canClear = appState.locationPresentation.canClear
        return Button { showClearConfirmation = true } label: {
            Label("Clear", systemImage: "xmark.circle")
                .font(Organic.body(11.5, weight: .bold))
                .foregroundStyle(canClear ? Organic.accent700 : Organic.neutral500)
                .padding(.horizontal, 12)
                .frame(height: LocationPanelMetrics.actionHeight)
                .background(Capsule().fill(canClear ? Organic.accent100 : Organic.neutral200))
                .overlay(Capsule().strokeBorder(canClear ? Organic.accent400 : Organic.neutral300, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!canClear)
        .help(canClear ? "Return the iPhone to its real location" : "Nothing to clear: no simulated location is held")
        .accessibilityLabel("Clear")
        .accessibilityHint("Returns the iPhone to its real location")
        .accessibilityIdentifier("location.action.clear")
        .confirmationDialog("Return to real GPS?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear simulated location", role: .destructive) { Task { await appState.clearLocation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the only action that removes the applied location.")
        }
    }

    private func connectionTone(for phase: LocationConnectionPhase) -> Color {
        switch phase {
        case .ready: return Organic.sage600
        case .reconnecting: return Organic.accent
        case .failed: return Organic.danger
        case .unavailable: return Organic.neutral500
        }
    }

    private func applicationTone(for phase: LocationApplicationPhase) -> Color {
        switch phase {
        case .active: return Organic.sage600
        case .applying, .uncertain, .clearing: return Organic.accent
        case .lost, .failed: return Organic.danger
        case .idle: return Organic.neutral500
        }
    }

    private func movementTone(for phase: LocationMovementPhase) -> Color {
        switch phase {
        case .moving: return Organic.sage600
        case .paused: return Organic.accent
        case .idle, .completed: return Organic.neutral500
        }
    }

    /// The five modes as one segmented row (every label in full), then Saved & History.
    private var modePill: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.mapModes) { mode in
                let isActive = selectedMode == mode && cardOpen
                let isSelected = selectedMode == mode
                Button {
                    if selectedMode == mode {
                        cardOpen.toggle()
                        savedOpen = false
                    } else {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        OrganicGlyphView(glyph: mode.glyph, size: 14)
                        Text(mode.localizedLabel)
                            .font(Organic.body(11.5, weight: isSelected ? .bold : .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isActive ? Organic.accentInk : (isSelected ? Organic.accent800 : Organic.neutral700))
                    .padding(.horizontal, 11)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        Capsule().fill(isActive ? Organic.accent : (isSelected ? Organic.accent100 : Color.clear))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(mode.description)
                .accessibilityLabel(mode.localizedLabel)
                .accessibilityValue(
                    NSLocalizedString(
                        isActive ? "location.mode.state.selected" : "location.mode.state.notSelected",
                        comment: "Location mode selection state"
                    )
                )
                .accessibilityIdentifier(mode.locationAccessibilityIdentifier)
            }
            Rectangle()
                .fill(Organic.neutral300)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 4)
            Button {
                savedOpen.toggle()
                if savedOpen {
                    cardOpen = false
                    coachOpen = false
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(savedOpen ? Organic.accentInk : Organic.neutral700)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(savedOpen ? Organic.accent : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("location.savedHistory", comment: "Saved places and location history"))
            .accessibilityLabel(NSLocalizedString("location.savedHistory", comment: "Saved places and location history"))
        }
        .fixedSize()
        .background(Capsule().fill(Organic.neutral200))
    }

    private var handleButton: some View {
        Button {
            if savedOpen {
                savedOpen = false
                cardOpen = true
            } else if cardOpen {
                cardOpen = false
            } else {
                cardOpen = true
                coachOpen = false
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Organic.neutral600)
                .rotationEffect(.degrees(cardOpen || savedOpen ? 0 : 180))
                .frame(width: 17, height: 46)
                .background(Organic.neutral100)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
                        .stroke(Organic.neutral300, lineWidth: 1)
                )
                .shadow(color: Organic.shadow.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help(cardOpen || savedOpen ? "Hide panel" : "Show \(selectedMode.cardTitle) panel")
    }

    private var coachToast: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Organic.accent400)
                    Text(appState.canStartSimulation
                         ? "Click the map to set a destination — the card comes to you."
                         : "Connect a device or start the tunnel, then click the map.")
                        .font(Organic.body(12, weight: .semibold))
                        .foregroundStyle(Organic.neutral100)
                    Button("Got it") {
                        coachOpen = false
                        dismissedCoach = true
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(10, weight: .bold))
                    .foregroundStyle(Organic.accent400)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Organic.neutral100.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 9)
                .background(Organic.neutral900)
                .clipShape(Capsule())
                .shadow(color: Organic.shadow.opacity(0.24), radius: 12, y: 6)
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .allowsHitTesting(true)
    }

    private func cycleMapStyle() {
        switch mapStyle {
        case .standard: mapStyle = .satellite
        case .satellite: mapStyle = .hybrid
        case .hybrid: mapStyle = .standard
        }
    }

    private func syncCoordFields() {
        if let location = appState.locationPresentation.desiredCoordinate ?? appState.locationPresentation.appliedCoordinate {
            latitudeInput = String(format: "%.6f", location.latitude)
            longitudeInput = String(format: "%.6f", location.longitude)
        }
    }

    private func applyPlace(_ coordinate: LocationCoordinate, name: String) {
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        addressText = name
        appState.stageLocation(coordinate, for: selectedMode)

        cardOpen = true
        savedOpen = false
        coachOpen = false
        showSearchResults = false
    }

    private func commitSearch() {
        if let first = searchService.searchResults.first {
            applyPlace(first.coordinate, name: first.name)
            searchService.clearSearch()
            showSearchResults = false
        }
    }

    private func commitTeleport() {
        guard let lat = Double(latitudeInput), let lon = Double(longitudeInput) else {
            appState.statusMessage = "Invalid coordinates"
            return
        }
        let coordinate = LocationCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else {
            appState.statusMessage = "Coordinates out of range"
            return
        }
        applyPlace(coordinate, name: addressText)
    }

    private func performMove() {
        if appState.locationPresentation.isMovementActive || appState.isMovementEngineRunning,
           selectedMode == .route || selectedMode == .twospot || selectedMode == .jump {
            Task { await appState.stopSimulation() }
            return
        }
        appState.activeMode = selectedMode == .settings ? .teleport : selectedMode
        let plan = SimulationPlanner.plan(
            mode: appState.activeMode,
            targetLocation: appState.locationPresentation.desiredCoordinate,
            currentLocation: appState.locationPresentation.appliedCoordinate,
            route: appState.currentRoute,
            speed: appState.simulationSpeed,
            jumpIndex: appState.jumpIndex
        )
        if LocationHistoryPolicy.shouldRecord(
            canStartSimulation: appState.canStartSimulation,
            plan: plan
        ), let coordinate = LocationHistoryPolicy.coordinate(for: plan) {
            let name = coordinate == appState.locationPresentation.desiredCoordinate ? addressText : coordinate.formattedShort
            LocationFavoritesManager.shared.recordRecent(name: name, coordinate: coordinate)
            LocationFavoritesManager.shared.rememberPlace(name: name, coordinate: coordinate)
        }
        Task { await appState.startSimulation() }
    }

    private func handleErrorAction(_ action: ErrorHandler.ErrorAction) {
        switch action {
        case .retry:
            Task { await appState.refreshDevices() }
        case .openSettings:
            showSettings = true
        case .startTunneld:
            Task { await appState.startSelectedTunnel() }
        case .enableDeveloperMode:
            break
        case .checkConnection:
            Task { await appState.checkTunneldStatus() }
        }
    }
}

/// The location panel's fixed geometry: the mode card is placed right under it.
enum LocationPanelMetrics {
    static let maxWidth: CGFloat = 820
    static let inset: CGFloat = 6
    /// 44 pt search field and mode buttons, plus the inset above and below.
    static let topRowHeight: CGFloat = 56
    static let statusRowHeight: CGFloat = 46
    static let actionHeight: CGFloat = 30
    /// Top row, hairline, status row.
    static let height: CGFloat = topRowHeight + 1 + statusRowHeight
}

/// Connection, Location, Movement and Applied, side by side, split by hairlines: a dot in
/// the state's tone, a small label, the value. Equatable on what it shows.
struct LocationStatusStrip: View, Equatable {
    struct Cell: Equatable {
        let titleKey: String
        let value: String
        let tone: Color
        let localizationKey: String
        let id: String
        var isCoordinate = false
    }

    static let noCoordinate = "None"

    let cells: [Cell]

    var body: some View {
#if DEBUG
        let _ = GUIRenderCounts.statusPanel += 1
#endif
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                if index > 0 {
                    Rectangle().fill(Organic.neutral300).frame(width: 1, height: 24)
                        .accessibilityHidden(true)
                }
                statusChip(titleKey: cell.titleKey, value: cell.value, tone: cell.tone,
                           localizationKey: cell.localizationKey, id: cell.id, isCoordinate: cell.isCoordinate)
            }
        }
        .fixedSize()
    }

    private func statusChip(
        titleKey: String,
        value: String,
        tone: Color,
        localizationKey: String,
        id: String,
        isCoordinate: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(NSLocalizedString(titleKey, comment: "Location status domain"))
                .font(Organic.body(10, weight: .semibold))
                .foregroundStyle(Organic.neutral600)
            HStack(spacing: 6) {
                Circle().fill(tone).frame(width: 7, height: 7)
                Text(value)
                    .font(isCoordinate && value != Self.noCoordinate ? Organic.mono(11.5, weight: .semibold) : Organic.body(12, weight: .semibold))
                    .foregroundStyle(value == Self.noCoordinate ? Organic.neutral600 : Organic.neutral900)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(id)
        .accessibilityLabel(NSLocalizedString(localizationKey, comment: "Location status field"))
        .accessibilityValue(value)
    }
}

/// Why the tunnel is not live, in words, as a strip right under the title bar (the tunnel
/// pill's own row): the first line says what is happening, a reconnect's "Last attempt"
/// line carries its label, and nothing hides behind a hover.
struct TunnelNoticeView: View {
    let text: String
    let isError: Bool

    var body: some View {
        let lines = TunnelNotice(text: text, isError: isError).lines
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isError ? Organic.danger : Organic.neutral700)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    lineText(line, isFirst: index == 0)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(isError ? Organic.accent100 : Organic.neutral200)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isError ? Organic.accent300 : Organic.neutral300).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tunnel.notice")
    }

    private func lineText(_ line: TunnelNotice.Line, isFirst: Bool) -> Text {
        let body = Text(line.text)
            .font(isFirst ? Organic.body(12, weight: .medium) : Organic.body(11.5))
            .foregroundColor(isFirst ? Organic.text : Organic.neutral700)
        guard let label = line.label else { return body }
        return Text("\(label)  ")
            .font(Organic.body(11.5, weight: .bold))
            .foregroundColor(isError ? Organic.accent800 : Organic.neutral800)
            + body
    }
}

struct IOS18WarningBanner: View {
    let device: Device
    @State private var isExpanded = false
    @State private var showDialog = false
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed && !AppPreferences.shared.isIOS18WarningDismissed(for: device.id) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Organic.accent600)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iOS \(device.iosVersion) — keep the tunnel running")
                        .font(Organic.body(13, weight: .semibold))
                    if isExpanded {
                        Text("If the pin snaps back, start the tunnel again and leave PathChanger open.")
                            .font(Organic.body(11))
                            .foregroundStyle(Organic.neutral600)
                    }
                }
                Spacer()
                Button("Learn More") { showDialog = true }
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.accent700)
                Button {
                    AppPreferences.shared.setIOS18WarningDismissed(for: device.id)
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Organic.neutral600)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Organic.accent100)
            .sheet(isPresented: $showDialog) {
                IOS18WarningDialogView(
                    deviceVersion: device.iosVersion,
                    onDismiss: { showDialog = false },
                    onLearnMore: { url in NSWorkspace.shared.open(url) }
                )
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
#endif
