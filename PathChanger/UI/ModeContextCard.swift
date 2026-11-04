//
//  ModeContextCard.swift
//  PathChanger
//
//  Floating 336px mode card from the pctnhc mock.
//

import SwiftUI

/// Why Move is disabled, chosen without the view so it can be tested.
enum MoveDisabledReason: Equatable {
    case noDevice
    case clearInProgress
    case clearUnresolved
    case notReady
    case selectLocation
    case addWaypoints

    static func select(
        canMove: Bool,
        hasDevice: Bool,
        clearBlock: LocationClearBlock?,
        canStartSimulation: Bool,
        mode: AppMode
    ) -> MoveDisabledReason? {
        guard !canMove else { return nil }
        guard hasDevice else { return .noDevice }
        switch clearBlock {
        case .clearInProgress: return .clearInProgress
        case .clearUnresolved: return .clearUnresolved
        case nil: break
        }
        guard canStartSimulation else { return .notReady }
        switch mode {
        case .teleport, .joystick: return .selectLocation
        case .jump, .twospot, .route: return .addWaypoints
        case .settings: return nil
        }
    }

    var text: String {
        switch self {
        case .noDevice:
            return NSLocalizedString("location.action.disabled.noDevice", comment: "Move disabled without a device")
        case .clearInProgress:
            return NSLocalizedString("location.action.disabled.clearing", comment: "Move disabled while Clear runs")
        case .clearUnresolved:
            return NSLocalizedString("location.action.disabled.clearUnresolved", comment: "Move disabled after a Clear PathChanger could not confirm")
        case .notReady:
            return NSLocalizedString("location.action.disabled.notReady", comment: "Move disabled while device is not ready")
        case .selectLocation:
            return NSLocalizedString("location.action.disabled.selectLocation", comment: "Teleport or Joystick needs a location")
        case .addWaypoints:
            return NSLocalizedString("location.action.disabled.addWaypoints", comment: "Route mode needs waypoints")
        }
    }
}

/// Takes its child's ideal height when that fits, else the height offered: a scroll view
/// inside it hugs short content and scrolls tall content, with no measuring pass (so no
/// first-frame jump).
struct ContentHuggingLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let height = min(ideal.height, proposal.height ?? ideal.height)
        return CGSize(width: proposal.width ?? ideal.width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

struct ModeContextCard: View {
    /// Where ContentView places the card in the map area: 12 pt below the location panel,
    /// on the panel's left edge, with a bottom margin so the footer never touches the
    /// window edge.
    static let placementInsets = EdgeInsets(
        top: Organic.space4 + LocationPanelMetrics.height + Organic.space3,
        leading: 16, bottom: 16, trailing: 16
    )

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @ObservedObject private var favorites = LocationFavoritesManager.shared

    @Binding var mode: AppMode
    @Binding var latitudeInput: String
    @Binding var longitudeInput: String
    var address: String
    let onClose: () -> Void
    let onMove: () -> Void
    let onCommitCoords: () -> Void

    /// The card's one gutter: content, header and footer share this left and right edge.
    static let gutter: CGFloat = 14

    var body: some View {
#if DEBUG
        let _ = GUIRenderCounts.modeCard += 1
#endif
        VStack(spacing: 0) {
            header
            hairline
            // The content scrolls between the pinned header and footer. The card hugs
            // short content and never grows past the height its parent offers (the old
            // `fixedSize` took the full content height and pushed the footer out of the
            // window; the older `maxHeight: 560` stretched short cards).
            ContentHuggingLayout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Sections in the order a run is set up: where, how to get there,
                        // how fast, what happens at each stop, then the totals.
                        if mode.showsRouteList {
                            cardSection { routeBlock }
                        }
                        if mode == .teleport {
                            cardSection { coordBlock }
                        }
                        if StopTravelCardText.showsStopOptions(for: mode) {
                            cardSection { arrivalBlock }
                        }
                        if showsTravelMotion {
                            cardSection { motionBlock }
                        }
                        if StopTravelCardText.showsStopOptions(for: mode) {
                            cardSection { stopOptionsBlock }
                        }
                        if mode == .joystick {
                            cardSection {
                                VStack(alignment: .leading, spacing: 10) {
                                    joystickBlock
                                    toggleBlock
                                }
                            }
                        }
                        metricsBlock
                        notesBlock
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
        .frame(width: 336)
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .strokeBorder(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.16), radius: 16, y: 6)
    }

    private var hairline: some View {
        Rectangle().fill(Organic.neutral300).frame(height: 1).accessibilityHidden(true)
    }

    /// One section of the card: its content on the card's gutter, a hairline under it.
    private func cardSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Self.gutter)
                .padding(.vertical, 12)
            Rectangle().fill(Organic.neutral300.opacity(0.7)).frame(height: 1).accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            OrganicGlyphView(glyph: mode.glyph, size: 15)
                .foregroundStyle(Organic.accent800)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Organic.accent200))
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.cardTitle)
                    .font(Organic.heading(15))
                    .foregroundStyle(Organic.accent800)
                Text(mode.description)
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.neutral600)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Organic.neutral600)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Organic.neutral200))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close the \(mode.cardTitle) card")
        }
        .padding(.horizontal, Self.gutter)
        .padding(.vertical, 12)
    }

    private var routeBlock: some View {
        StopListSection(
            appState: appState,
            mode: mode,
            rows: displayStops.enumerated().map { index, stop in
                StopListSection.Row(
                    badge: badge(for: index),
                    name: stop.title,
                    favoriteName: stop.name,
                    coordinate: stop.coordinate,
                    isFavorite: favorites.isFavorite(stop.coordinate)
                )
            },
            routeCount: appState.currentRoute.count,
            maxStops: mode.maxStops,
            onRemove: { removeDisplayStop(at: $0) }
        )
        .equatable()
    }

    /// The stop's badge, numbered as on the map: Jump counts from 1; Two-Spot and
    /// Multi-Spot mark the start and count the stops after it.
    private func badge(for index: Int) -> StopListSection.Badge {
        if index == 0 && mode != .jump { return .start }
        return .number(mode == .jump ? index + 1 : index)
    }

    private var coordBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OrganicGroupHeader(title: "Target")
            HStack(spacing: 8) {
                coordField("Latitude", text: $latitudeInput)
                coordField("Longitude", text: $longitudeInput)
            }
            if appState.locationPresentation.desiredCoordinate == nil {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("location.teleport.noTarget", comment: "Teleport empty target title"))
                            .font(Organic.body(11.5, weight: .semibold))
                        Text(NSLocalizedString("location.teleport.targetHint", comment: "Teleport target selection guidance"))
                            .font(Organic.body(11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "mappin.slash")
                }
                .foregroundStyle(Organic.neutral700)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                        .strokeBorder(Organic.neutral400, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NSLocalizedString("location.teleport.noTarget", comment: "Teleport empty target title"))
                .accessibilityHint(NSLocalizedString("location.teleport.targetHint", comment: "Teleport target selection guidance"))
                .accessibilityIdentifier("location.teleport.emptyTarget")
            }
        }
    }

    private func coordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Organic.body(11, weight: .semibold))
                .foregroundStyle(Organic.neutral600)
                .accessibilityHidden(true)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Organic.mono(12))
                .padding(.horizontal, 10)
                .frame(height: Organic.controlHeight)
                .background(Capsule().fill(Organic.bg))
                .overlay(Capsule().strokeBorder(Organic.neutral400, lineWidth: 1))
                .onSubmit(onCommitCoords)
                .accessibilityLabel(label)
        }
    }

    private var motionBlock: some View {
        TravelSection(
            appState: appState,
            speed: appState.simulationSpeed,
            autoSpeed: appState.autoSpeed,
            customSpeedMps: appState.customSpeedMps,
            note: StopTravelCardText.speedNote(settings: stopSettings, isRunActive: isStopRunActive),
            isRunActive: isStopRunActive
        )
        .equatable()
    }

    private var joystickBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                readout("Heading", headingText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(headingAccessibilityLabel)
                Rectangle().fill(Organic.neutral300).frame(width: 1, height: 30)
                readout("Speed", String(format: "%.1f", appState.locationPresentation.isMovementActive ? appState.joystickSpeed : 0))
                Rectangle().fill(Organic.neutral300).frame(width: 1, height: 30)
                readout("Position", (appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate)?.formattedShort ?? "—")
            }
            .background(
                RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous)
                    .fill(Organic.bg)
            )
            // Joystick's own speed: travel modes do not apply, so there is no Auto (3.5).
            OrganicSliderRow(
                title: "Speed",
                valueLabel: String(format: "%.1f m/s", appState.joystickSpeed),
                value: $appState.joystickSpeed,
                range: SimulationStateManager.joystickSpeedRange,
                step: 0.1
            )
        }
    }

    private var toggleBlock: some View {
        VStack(spacing: 1) {
            if mode == .joystick {
                toggleLine(
                    "Smooth corners",
                    Binding(get: { appState.smoothTurns }, set: { appState.smoothTurns = $0 })
                )
            }
        }
    }

    // MARK: Stop-by-stop options (Jump, Two-Spot, Multi-Spot; PRODUCT_REQUIREMENTS 3.6)

    private var stopSettings: StopTravelSettings { appState.stopTravelSettings(for: mode) }

    /// A stop run (or a route playback) of this mode is running, from Move until it ends.
    private var isStopRunActive: Bool {
        StopTravelCardText.showsStopOptions(for: mode)
            && (appState.stopProgress != nil || appState.isMovementEngineRunning)
    }

    /// Getting there, and Jump timing when the stops are jumped to.
    private var arrivalBlock: some View {
        StopOptionsSection(
            appState: appState,
            mode: mode,
            settings: stopSettings,
            controls: StopTravelCardText.visibleControls(for: mode, settings: stopSettings)
                .filter { $0 == .arrival || $0 == .jumpTiming },
            // Its first row is labelled Getting there already.
            title: nil,
            note: nil
        )
        .equatable()
    }

    /// At each stop, Go through and Repeat.
    private var stopOptionsBlock: some View {
        StopOptionsSection(
            appState: appState,
            mode: mode,
            settings: stopSettings,
            controls: StopTravelCardText.visibleControls(for: mode, settings: stopSettings)
                .filter { $0 != .arrival && $0 != .jumpTiming },
            title: "At the stops",
            // Controls stay enabled mid-run: see `StopTravelCardText.runEditNote`.
            note: StopTravelCardText.runEditNote(isRunActive: isStopRunActive)
        )
        .equatable()
    }

    /// The running stop run: the phase in words with its countdown big, a bar for how far
    /// the countdown has come, what happens next, then the next stop and any route note.
    @ViewBuilder
    private var stopProgressReadout: some View {
        if StopTravelCardText.showsStopOptions(for: mode), let progress = appState.stopProgress {
            StopRunPanel(
                progress: progress,
                explanation: StopTravelCardText.phaseExplanation(
                    progress, settings: stopSettings,
                    travelName: StopTravelCardText.travelModeTitle(appState.simulationSpeed, autoSpeed: appState.autoSpeed)
                )
            )
            .equatable()
        } else if let done = completionLine {
            Label(done, systemImage: "checkmark.circle.fill")
                .font(Organic.body(11.5, weight: .semibold))
                .foregroundStyle(Organic.sage800)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous).fill(Organic.sage100)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous)
                        .strokeBorder(Organic.sage300, lineWidth: 1)
                )
                .accessibilityLabel(done)
        }
    }

    /// The stop the phone holds in this mode's run (nil when it holds no stop of it).
    private var reachedStopIndex: Int? {
        StopTravelCardText.reachedStop(
            stops: appState.displayStops(for: mode),
            cursor: appState.displayStopCursor(for: mode),
            repeatMode: stopSettings.repeatMode,
            held: appState.locationPresentation.appliedCoordinate
        )
    }

    /// A finished run of this mode whose last stop is still held.
    private var completionLine: String? {
        guard StopTravelCardText.showsStopOptions(for: mode) else { return nil }
        return StopTravelCardText.completionLine(
            movement: appState.locationSessionCoordinator.state.movement,
            mode: mode,
            isHeld: appState.locationPresentation.appliedCoordinate != nil,
            reachedStop: reachedStopIndex,
            totalStops: appState.displayStops(for: mode).count
        )
    }

    private func toggleLine(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Organic.body(12, weight: .semibold)).foregroundStyle(Organic.neutral700)
            Spacer()
            Toggle(title, isOn: value).labelsHidden().tint(Organic.accent600).controlSize(.small)
        }
    }

    /// The totals, side by side in one row under the sections.
    @ViewBuilder
    private var metricsBlock: some View {
        let metrics = metricItems
        if !metrics.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    if index > 0 {
                        Rectangle().fill(Organic.neutral300).frame(width: 1, height: 28).accessibilityHidden(true)
                    }
                    metricRow(system: metric.system, title: metric.title, value: metric.value)
                }
            }
            .padding(.horizontal, Self.gutter - 8)
            .padding(.vertical, 10)
        }
    }

    private var metricItems: [(system: String, title: String, value: String)] {
        var items: [(system: String, title: String, value: String)] = []
        if mode.showsDistance {
            // Straight-line sums of the stops: road legs and holds are not included.
            items.append(("mappin.circle", mode == .teleport ? "Distance" : "Distance (straight)", routeDistance))
        }
        if mode == .route || mode == .twospot {
            items.append(("clock", "Est. time (straight)", routeETA))
        }
        if mode == .jump {
            // The stop the phone holds, not the cursor: after a Loop wrap the cursor
            // reads 0 while the phone holds the last stop.
            items.append(("mappin.and.ellipse", "At stop", StopTravelCardText.atStopValue(reached: reachedStopIndex, total: appState.displayStops(for: mode).count)))
        }
        return items
    }

    private func metricRow(system: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Organic.neutral500)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Organic.body(10.5, weight: .semibold))
                    .foregroundStyle(Organic.neutral600)
                    .lineLimit(1)
            }
            Text(value)
                .font(Organic.mono(12.5, weight: .bold))
                .foregroundStyle(Organic.neutral900)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notesBlock: some View {
        EmptyView()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            stopProgressReadout
            if !showsStop, let nextMove = appState.nextMoveSummary(for: mode) {
                // Idle stop modes: what Move will do from where the run stands.
                Label {
                    Text(nextMove)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(Organic.accent600)
                }
                .font(Organic.body(11.5, weight: .semibold))
                .foregroundStyle(Organic.neutral800)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nextMove)
                .accessibilityIdentifier(StopTravelCardText.nextMoveIdentifier)
            }
            HStack(spacing: 8) {
                if mode == .joystick {
                    Button("Stop movement") {
                        appState.disengageJoystick()
                    }
                    .accessibilityIdentifier("location.action.stopMovement")
                    .buttonStyle(.plain)
                    .font(Organic.body(12.5, weight: .bold))
                    .foregroundStyle(Organic.sage800)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.footerButtonHeight)
                    .background(Capsule().fill(Organic.sage100))
                    .overlay(Capsule().strokeBorder(Organic.sage300, lineWidth: 1))
                    .contentShape(Capsule())
                    .disabled(!appState.locationPresentation.isMovementActive)
                    .opacity(appState.locationPresentation.isMovementActive ? 1 : 0.55)
                } else {
                    Button(action: onMove) {
                        HStack(spacing: 6) {
                            Image(systemName: moveIcon)
                                .font(.system(size: 11, weight: .bold))
                            Text(moveLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.footerButtonHeight)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(12.5, weight: .bold))
                    .foregroundStyle(canMove ? Organic.accentInk : Organic.neutral700)
                    .background(Capsule().fill(canMove ? Organic.accent : Organic.neutral300))
                    .disabled(!canMove)
                    .accessibilityIdentifier(showsStop ? "location.action.stopMovement" : "location.action.apply")

                    if let pause = StopTravelCardText.pauseButton(progress: appState.stopProgress, isPaused: appState.isPaused),
                       StopTravelCardText.showsStopOptions(for: mode) {
                        Button {
                            StopTravelCardText.perform(pause.action, on: appState)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: pause.systemImage)
                                    .font(.system(size: 11, weight: .bold))
                                    .accessibilityHidden(true)
                                Text(pause.title)
                            }
                            .font(Organic.body(12.5, weight: .bold))
                            .foregroundStyle(Organic.sage800)
                            .padding(.horizontal, 14)
                            .frame(height: Self.footerButtonHeight)
                            .background(Capsule().fill(Organic.sage100))
                            .overlay(Capsule().strokeBorder(Organic.sage300, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(pause.title)
                        .accessibilityIdentifier(StopTravelCardText.pauseIdentifier)
                    }

                    Button {
                        resetContext()
                    } label: {
                        Text(resetActionLabel)
                            .font(Organic.body(12.5, weight: .bold))
                            .foregroundStyle(Organic.neutral800)
                            .padding(.horizontal, 14)
                            .frame(height: Self.footerButtonHeight)
                            .background(Capsule().fill(Organic.neutral100))
                            .overlay(Capsule().strokeBorder(Organic.neutral400, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .disabled(!canResetRoute)
                    .opacity(canResetRoute ? 1 : 0.55)
                }
            }
            if let reason = disabledMoveReason {
                Label(reason, systemImage: "info.circle")
                    .font(Organic.body(11, weight: .medium))
                    .foregroundStyle(Organic.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(reason)
                    .accessibilityIdentifier("location.action.disabledReason")
            }
        }
        .padding(.horizontal, Self.gutter)
        .padding(.vertical, 12)
        .background(Organic.neutral100)
        .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300).frame(height: 1) }
    }

    static let footerButtonHeight: CGFloat = 36

    private var showsTravelMotion: Bool {
        mode == .jump || mode == .twospot || mode == .route
    }

    private var canResetRoute: Bool {
        if mode == .teleport {
            return appState.locationPresentation.desiredCoordinate != nil
                || !latitudeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !longitudeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !appState.currentRoute.isEmpty
    }

    private var resetActionLabel: String {
        mode == .teleport
            ? NSLocalizedString("location.action.clearTarget", comment: "Clear staged Teleport target")
            : NSLocalizedString("location.action.resetRoute", comment: "Reset route waypoints")
    }

    private func resetContext() {
        appState.clearRoute()
        if mode == .teleport {
            latitudeInput = ""
            longitudeInput = ""
        } else if mode == .twospot, let current = appState.locationPresentation.appliedCoordinate {
            // Two-Spot starts from where the device is; Jump and Multi-Spot start empty
            // (staging the held location as Jump hop 1 re-applied it on the next Move).
            appState.stageLocation(current, for: mode)
        }
    }

    private var disabledMoveReason: String? {
        MoveDisabledReason.select(
            canMove: canMove,
            hasDevice: appState.selectedDevice != nil,
            clearBlock: appState.moveBlockedByClear,
            canStartSimulation: appState.canStartSimulation,
            mode: mode
        )?.text
    }

    private var canMove: Bool {
        // A device exposed directly by usbmux over USB or Network/Wi-Fi is ready without
        // RemoteXPC. The old app worked over Wi-Fi through this exact `--udid` path; gating
        // only on `tunneldManager.isRunning` disabled every mode in the fixed build.
        if showsStop { return true }
        if !appState.canStartSimulation { return false }
        switch mode {
        case .teleport: return appState.locationPresentation.desiredCoordinate != nil
        case .jump:
            return StopTravelCardText.jumpCanMove(
                stops: appState.currentRoute,
                cursor: StopCursor(nextIndex: appState.jumpIndex),
                settings: appState.stopTravelSettings(for: .jump)
            )
        case .twospot: return (appState.moveStartCoordinate != nil && (appState.locationPresentation.desiredCoordinate != nil || !appState.currentRoute.isEmpty)) || appState.currentRoute.count >= 2
        case .route: return appState.currentRoute.count >= 2
        case .joystick: return appState.locationPresentation.desiredCoordinate != nil || appState.locationPresentation.appliedCoordinate != nil
        case .settings: return false
        }
    }

    /// Move acts as Stop while a route or Auto jump runs, from Move until it ends.
    private var showsStop: Bool {
        (appState.locationPresentation.isMovementActive || appState.isMovementEngineRunning)
            && (mode == .route || mode == .twospot || mode == .jump)
    }

    private var moveLabel: String {
        if showsStop {
            return "Stop"
        }
        if mode == .jump, !appState.currentRoute.isEmpty {
            // A finished One way run starts over at stop 1 (owner rule 2026-11-03).
            let count = appState.currentRoute.count
            let next = appState.jumpIndex >= count ? 1 : appState.jumpIndex + 1
            return "Move · \(next)/\(count)"
        }
        return "Move"
    }

    private var moveIcon: String {
        if showsStop { return "stop.fill" }
        return "play.fill"
    }

    private var headingText: String {
        JoystickReadout.headingText(live: appState.joystickDirection, last: appState.lastJoystickHeadingDegrees)
    }

    private var headingAccessibilityLabel: String {
        JoystickReadout.headingAccessibilityLabel(live: appState.joystickDirection, last: appState.lastJoystickHeadingDegrees)
    }

    private var routeDistance: String {
        let coords = metricCoordinates
        guard coords.count > 1 else { return "—" }
        var meters = 0.0
        for index in 1..<coords.count {
            meters += RouteInterpolator.haversineDistance(from: coords[index - 1], to: coords[index])
        }
        return meters < 1000 ? "\(Int(meters)) m" : String(format: "%.2f km", meters / 1000)
    }

    private var routeETA: String {
        let coords = metricCoordinates
        guard coords.count > 1 else { return "00:00:00" }
        var meters = 0.0
        for index in 1..<coords.count {
            meters += RouteInterpolator.haversineDistance(from: coords[index - 1], to: coords[index])
        }
        return Self.hms(meters / max(appState.effectiveMetersPerSecond, 0.1))
    }

    /// The points Move will travel through, in order (Two-Spot from the current
    /// location only while a single spot is picked, exactly as the planner does).
    private var metricCoordinates: [LocationCoordinate] {
        var coords = displayStops.map(\.coordinate)
        if mode == .twospot, appState.currentRoute.count < 2,
           let start = appState.moveStartCoordinate, coords.first != start {
            coords.insert(start, at: 0)
        }
        return coords
    }

    private struct DisplayStop {
        /// What the row says (Start, Stop 2, Destination).
        let title: String
        /// The name a favorite of this stop is saved under.
        let name: String
        let coordinate: LocationCoordinate
        let fromRoute: Bool
    }

    private var displayStops: [DisplayStop] {
        if mode == .twospot {
            let spots = appState.currentRoute
            if spots.count >= 2 {
                return [
                    DisplayStop(title: "Start", name: "Start", coordinate: spots[0], fromRoute: true),
                    DisplayStop(title: "Destination", name: spots[1].formattedShort, coordinate: spots[1], fromRoute: true),
                ]
            }
            var rows: [DisplayStop] = []
            if let current = appState.moveStartCoordinate {
                let name = address.isEmpty ? "Start" : address
                rows.append(DisplayStop(title: name, name: name, coordinate: current, fromRoute: false))
            }
            if let dest = appState.currentRoute.last ?? appState.locationPresentation.desiredCoordinate {
                rows.append(DisplayStop(title: "Destination", name: dest.formattedShort, coordinate: dest, fromRoute: true))
            }
            return rows
        }
        if mode == .jump || mode == .route {
            let count = appState.currentRoute.count
            return appState.currentRoute.enumerated().map { index, coord in
                let name = index == 0 ? "Start" : (index == count - 1 ? "Finish" : "Stop \(index)")
                // Jump numbers every stop from 1, as its badges and Next Move do.
                let title = mode == .jump ? "Stop \(index + 1)" : name
                return DisplayStop(title: title, name: name, coordinate: coord, fromRoute: true)
            }
        }
        if let target = appState.locationPresentation.desiredCoordinate {
            return [DisplayStop(title: address, name: address, coordinate: target, fromRoute: false)]
        }
        return []
    }

    private func removeDisplayStop(at index: Int) {
        if mode == .twospot {
            if appState.currentRoute.count >= 2 {
                appState.removeRouteWaypoint(at: index)
                return
            }
            // One spot picked: row 0 is the current location, which is not removable.
            if index == 0, appState.moveStartCoordinate != nil, displayStops.count > 1 {
                return
            }
            appState.clearRoute()
            return
        }
        appState.removeRouteWaypoint(at: index)
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Organic.body(10.5, weight: .semibold))
                .foregroundStyle(Organic.neutral600)
            Text(value)
                .font(Organic.body(14, weight: .bold))
                .foregroundStyle(Organic.neutral900)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func hms(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

// MARK: - Card sections
//
// Value views: the card re-renders with every AppState change (about twice per
// acknowledged point during a run), and each section below redraws only when what it
// shows changes. Actions go through `appState`, read when a control is used.

/// The stops: one numbered row per stop, with reverse and save in the header.
struct StopListSection: View, Equatable {
    enum Badge: Equatable {
        case start
        case number(Int)
    }

    struct Row: Equatable {
        let badge: Badge
        /// What the row says.
        let name: String
        /// The name a favorite of this stop is saved under.
        let favoriteName: String
        let coordinate: LocationCoordinate
        let isFavorite: Bool
    }

    let appState: AppState
    let mode: AppMode
    let rows: [Row]
    let routeCount: Int
    let maxStops: Int
    let onRemove: (Int) -> Void

    nonisolated static func == (lhs: StopListSection, rhs: StopListSection) -> Bool {
        lhs.mode == rhs.mode && lhs.rows == rhs.rows && lhs.routeCount == rhs.routeCount && lhs.maxStops == rhs.maxStops
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrganicGroupHeader(title: mode == .twospot ? "Spots" : "Stops") {
                HStack(spacing: 2) {
                    Text(countText)
                        .font(Organic.body(11, weight: .medium))
                        .foregroundStyle(Organic.neutral600)
                        .padding(.trailing, 4)
                    if routeCount >= 2 {
                        Button {
                            appState.reverseRoute(for: mode)
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Organic.neutral700)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Swap start and destination")
                        .accessibilityLabel("Reverse the stops")
                    }
                    Button {
                        for stop in appState.currentRoute {
                            LocationFavoritesManager.shared.addFavorite(name: stop.formattedShort, coordinate: stop)
                        }
                        appState.statusMessage = "Saved stops to Favorites"
                    } label: {
                        Image(systemName: "star.square.on.square")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Organic.neutral700)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(rows.isEmpty)
                    .help("Save every point to Favorites")
                    .accessibilityLabel("Save every point to Favorites")
                }
            }

            if rows.isEmpty {
                Text("Click the map to add a stop")
                    .font(Organic.body(11.5))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                            .strokeBorder(Organic.neutral400, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, stop in
                        if index > 0 {
                            Rectangle().fill(Organic.neutral300.opacity(0.6)).frame(height: 1)
                                .padding(.leading, 32)
                                .accessibilityHidden(true)
                        }
                        HStack(spacing: 10) {
                            badge(stop.badge)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.name)
                                    .font(Organic.body(12, weight: .semibold))
                                    .foregroundStyle(Organic.neutral900)
                                    .lineLimit(1)
                                Text(stop.coordinate.formattedShort)
                                    .font(Organic.mono(10.5))
                                    .foregroundStyle(Organic.neutral600)
                            }
                            .accessibilityElement(children: .combine)
                            Spacer(minLength: 0)
                            Button {
                                LocationFavoritesManager.shared.toggleFavorite(name: stop.favoriteName, coordinate: stop.coordinate)
                            } label: {
                                Image(systemName: stop.isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(stop.isFavorite ? Organic.accent600 : Organic.neutral500)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(stop.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                            .accessibilityLabel(stop.isFavorite ? "Remove \(stop.name) from Favorites" : "Add \(stop.name) to Favorites")
                            Button {
                                onRemove(index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Organic.neutral600)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove this stop")
                            .accessibilityLabel("Remove \(stop.name)")
                        }
                        .frame(minHeight: 40)
                    }
                }
            }
        }
    }

    private var countText: String {
        guard mode != .twospot else { return "" }
        return "\(rows.count) of \(maxStops)"
    }

    private func badge(_ badge: Badge) -> some View {
        ZStack {
            switch badge {
            case .start:
                Circle().fill(Organic.sage600)
                Image(systemName: "location.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Organic.neutral100)
            case .number(let number):
                Circle().fill(Organic.accent600)
                Text("\(number)")
                    .font(Organic.body(10.5, weight: .bold))
                    .foregroundStyle(Organic.neutral100)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The travel mode: four presets, the speed, and when the speed applies.
struct TravelSection: View, Equatable {
    let appState: AppState
    let speed: SimulationSpeed
    let autoSpeed: Bool
    let customSpeedMps: Double
    let note: String?
    let isRunActive: Bool

    static let travelModes: [SimulationSpeed] = [.walking, .cycling, .fast, .driving]

    nonisolated static func == (lhs: TravelSection, rhs: TravelSection) -> Bool {
        lhs.speed == rhs.speed && lhs.autoSpeed == rhs.autoSpeed && lhs.customSpeedMps == rhs.customSpeedMps
            && lhs.note == rhs.note && lhs.isRunActive == rhs.isRunActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Travel mode")
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.neutral800)
                Spacer()
                Text(StopTravelCardText.travelModeTitle(speed, autoSpeed: autoSpeed))
                    .font(Organic.body(11.5, weight: .semibold))
                    .foregroundStyle(Organic.accent700)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                ForEach(Self.travelModes, id: \.self) { preset in
                    // Selected only while the preset is the speed in use (Auto on).
                    let selected = autoSpeed && speed == preset
                    Button {
                        appState.selectTravelMode(preset)
                    } label: {
                        ChoiceTileLabel(systemImage: travelIcon(preset), title: StopTravelCardText.travelName(preset), selected: selected)
                    }
                    .buttonStyle(.plain)
                    .help("\(StopTravelCardText.travelName(preset)), \(String(format: "%.1f", preset.presetMetersPerSecond)) m/s")
                    .accessibilityLabel(StopTravelCardText.travelName(preset))
                    .accessibilityValue(String(format: "%.1f metres per second", preset.presetMetersPerSecond))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            OrganicSliderRow(
                title: "Speed",
                valueLabel: String(format: "%.1f m/s", customSpeedMps),
                value: Binding(get: { appState.customSpeedMps }, set: { appState.customSpeedMps = $0 }),
                range: 1...30,
                step: 0.1,
                isAuto: autoSpeed,
                onToggleAuto: {
                    appState.autoSpeed.toggle()
                    if appState.autoSpeed {
                        appState.customSpeedMps = appState.mockMetersPerSecond(for: appState.simulationSpeed)
                    }
                }
            )
            if let note {
                CardCaption(text: note, systemImage: isRunActive ? "clock.arrow.circlepath" : "info.circle")
            }
        }
    }

    private func travelIcon(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .fast: return "scooter"
        default: return speed.icon
        }
    }
}

/// A group of stop options: labelled rows of choice tiles, and At each stop's slider.
struct StopOptionsSection: View, Equatable {
    let appState: AppState
    let mode: AppMode
    let settings: StopTravelSettings
    let controls: [StopTravelCardText.Control]
    let title: String?
    let note: String?

    nonisolated static func == (lhs: StopOptionsSection, rhs: StopOptionsSection) -> Bool {
        lhs.mode == rhs.mode && lhs.settings == rhs.settings && lhs.controls == rhs.controls
            && lhs.title == rhs.title && lhs.note == rhs.note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                OrganicGroupHeader(title: title)
            }
            ForEach(controls) { control in
                row(control)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let note {
                CardCaption(text: note, systemImage: "exclamationmark.circle")
            }
        }
        // Jump timing slides in instead of pushing the rows below in one jump.
        .animation(.easeInOut(duration: 0.18), value: settings.arrival)
    }

    @ViewBuilder
    private func row(_ control: StopTravelCardText.Control) -> some View {
        switch control {
        case .arrival:
            choices(control, selection: appState.stopSettingBinding(\.arrival, for: mode),
                    options: StopTravelSettings.Arrival.allCases, title: StopTravelCardText.title, icon: Self.icon)
        case .jumpTiming:
            VStack(alignment: .leading, spacing: 6) {
                choices(control, selection: appState.stopSettingBinding(\.jumpTiming, for: mode),
                        options: StopTravelSettings.JumpTiming.allCases, title: StopTravelCardText.title, icon: Self.icon)
                CardCaption(text: StopTravelCardText.jumpTimingCaption(for: settings), systemImage: "info.circle")
            }
        case .hold:
            holdRow
        case .progression:
            choices(control, selection: appState.stopSettingBinding(\.progression, for: mode),
                    options: StopTravelSettings.Progression.allCases, title: StopTravelCardText.title, icon: Self.icon)
        case .repeatMode:
            choices(control, selection: appState.stopSettingBinding(\.repeatMode, for: mode),
                    options: StopTravelSettings.RepeatMode.allCases, title: StopTravelCardText.title, icon: Self.icon)
        }
    }

    /// A labelled row of Organic choice buttons. The visible title is hidden from
    /// VoiceOver because the group carries the same label, so it is read once; each choice
    /// reads its title and Selected.
    private func choices<Option: Hashable>(
        _ control: StopTravelCardText.Control,
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> String,
        icon: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(control.label)
                .font(Organic.body(11.5, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        ChoiceTileLabel(systemImage: icon(option), title: title(option), selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title(option))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(control.label)
            .accessibilityIdentifier(control.accessibilityIdentifier)
        }
    }

    private var holdRow: some View {
        let control = StopTravelCardText.Control.hold
        let seconds = settings.holdSeconds
        let applies = StopTravelCardText.holdApplies(settings)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(control.label)
                    .font(Organic.body(11.5, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 84, alignment: .leading)
                    .accessibilityHidden(true)
                Slider(
                    value: appState.stopHoldBinding(for: mode),
                    in: StopTravelCardText.holdRange,
                    step: StopTravelCardText.holdStep
                )
                .tint(Organic.accent600)
                .controlSize(.small)
                .accessibilityLabel(control.label)
                .accessibilityValue(StopTravelCardText.holdAccessibilityValue(seconds))
                .accessibilityHint(StopTravelCardText.holdNote(settings) ?? "")
                .accessibilityIdentifier(control.accessibilityIdentifier)
                Text(StopTravelCardText.holdLabel(seconds))
                    .font(Organic.mono(11.5, weight: .bold))
                    .foregroundStyle(Organic.neutral800)
                    .frame(width: 56, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            // With one stop per Move nothing continues after a stop, so the hold has no
            // effect: shown dimmed and disabled (its value is kept) instead of looking live.
            .disabled(!applies)
            .opacity(applies ? 1 : 0.5)
            if let note = StopTravelCardText.holdNote(settings) {
                CardCaption(text: note, systemImage: "info.circle")
            }
        }
    }

    private static func icon(_ arrival: StopTravelSettings.Arrival) -> String {
        switch arrival {
        case .travel: return "point.topleft.down.to.point.bottomright.curvepath"
        case .jump: return "scope"
        }
    }

    private static func icon(_ timing: StopTravelSettings.JumpTiming) -> String {
        switch timing {
        case .fixed: return "timer"
        case .realistic: return "hourglass"
        }
    }

    private static func icon(_ progression: StopTravelSettings.Progression) -> String {
        switch progression {
        case .automatic: return "forward.fill"
        case .onePerMove: return "hand.tap"
        }
    }

    private static func icon(_ repeatMode: StopTravelSettings.RepeatMode) -> String {
        switch repeatMode {
        case .oneWay: return "arrow.right"
        case .loop: return "repeat"
        case .backAndForth: return "arrow.left.arrow.right"
        }
    }
}

/// The live run: the phase in words, its countdown big with what it counts to, a bar for
/// how far the countdown has come, what happens next, then the next stop and any note.
/// A wait before a Realistic jump says it is a wait and when the jump comes.
struct StopRunPanel: View, Equatable {
    let progress: StopProgress
    let explanation: String?

    var body: some View {
        let countdown = StopTravelCardText.countdown(progress)
        let fraction = StopTravelCardText.phaseFraction(progress)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: Self.phaseIcon(progress))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(progress.isPaused ? Organic.neutral700 : Organic.accent700)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(progress.isPaused ? Organic.neutral300 : Organic.accent200))
                    .accessibilityHidden(true)
                Text(StopTravelCardText.phaseTitle(progress))
                    .font(Organic.body(13, weight: .bold))
                    .foregroundStyle(Organic.neutral900)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let countdown {
                    VStack(alignment: .trailing, spacing: 0) {
                        if let caption = StopTravelCardText.countdownCaption(progress) {
                            Text(caption)
                                .font(Organic.body(10.5, weight: .semibold))
                                .foregroundStyle(Organic.neutral600)
                        }
                        Text(StopTravelCardText.clock(countdown))
                            .font(Organic.mono(22, weight: .bold))
                            .foregroundStyle(progress.isPaused ? Organic.neutral600 : Organic.accent800)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StopTravelCardText.phaseTitle(progress))
            .accessibilityValue(countdown.map { seconds in
                [StopTravelCardText.countdownCaption(progress), StopTravelCardText.clock(seconds)].compactMap { $0 }.joined(separator: " ")
            } ?? "")

            if let fraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(progress.isPaused ? Organic.neutral300 : Organic.accent200)
                        Capsule()
                            .fill(progress.isPaused ? Organic.neutral500 : Organic.accent600)
                            .frame(width: max(proxy.size.width * fraction, 4))
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }

            if let explanation {
                Text(explanation)
                    .font(Organic.body(11.5))
                    .foregroundStyle(Organic.neutral800)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(StopTravelCardText.progressLines(progress).filter { [.nextStop, .fallback, .routeNote].contains($0.kind) }) { line in
                Text(line.text)
                    .font(line.kind == .nextStop ? Organic.body(11, weight: .semibold) : Organic.body(11))
                    .foregroundStyle(line.kind == .fallback ? Organic.accent800 : Organic.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous)
                .fill(progress.isPaused ? Organic.neutral200 : Organic.accent100)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusGroup, style: .continuous)
                .strokeBorder(progress.isPaused ? Organic.neutral400 : Organic.accent300, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stop progress")
        .accessibilityIdentifier(StopTravelCardText.progressIdentifier)
    }

    static func phaseIcon(_ progress: StopProgress) -> String {
        if progress.isPaused { return "pause.fill" }
        switch progress.phase {
        case .findingRoute: return "map"
        case .travelling: return "location.north.line.fill"
        case .waitingToJump: return "hourglass"
        case .jumping: return "scope"
        case .holding: return "mappin.and.ellipse"
        }
    }
}

/// A choice tile's face: an icon over a word, raised and tinted when selected.
struct ChoiceTileLabel: View {
    let systemImage: String
    let title: String
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(height: 15)
                .accessibilityHidden(true)
            Text(title)
                .font(Organic.body(10.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(selected ? Organic.accent800 : Organic.neutral700)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .fill(selected ? Organic.accent100 : Organic.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .strokeBorder(selected ? Organic.accent400 : Organic.neutral300, lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }
}

/// A short explanation under a control: muted, wrapping, read as one line.
struct CardCaption: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(Organic.body(10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Organic.neutral600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension AppMode {
    var cardTitle: String {
        switch self {
        case .teleport: return "Teleport"
        case .jump: return "Jump Teleport"
        case .twospot: return "Two-Spot"
        case .route: return "Multi-Spot"
        case .joystick: return "Joystick"
        case .settings: return "Settings"
        }
    }

    var cardIcon: String {
        switch self {
        case .teleport: return "scope"
        case .jump: return "plus.viewfinder"
        case .twospot: return "arrow.left.and.right"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .joystick: return "gamecontroller"
        case .settings: return "gearshape"
        }
    }

    var maxStops: Int {
        switch self {
        case .teleport, .twospot: return 1
        case .jump: return 12
        case .route: return 24
        case .joystick, .settings: return 0
        }
    }

    var showsRouteList: Bool { self == .jump || self == .twospot || self == .route }
    var showsMotion: Bool { self == .teleport || self == .jump || self == .twospot || self == .route }
    var showsDistance: Bool { self == .teleport || self == .jump || self == .twospot || self == .route }
}
