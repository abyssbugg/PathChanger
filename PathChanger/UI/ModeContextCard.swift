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
    /// Where ContentView places the card in the map area: below the search row, with a
    /// bottom margin so the footer never touches the window edge.
    static let placementInsets = EdgeInsets(top: 70, leading: 16, bottom: 16, trailing: 16)

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

    private let travelModes: [SimulationSpeed] = [.walking, .cycling, .fast, .driving]

    var body: some View {
        VStack(spacing: 0) {
            header
            // The content scrolls between the pinned header and footer. The card hugs
            // short content and never grows past the height its parent offers (the old
            // `fixedSize` took the full content height and pushed the footer out of the
            // window; the older `maxHeight: 560` stretched short cards).
            ContentHuggingLayout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if mode.showsRouteList {
                            routeBlock
                        }
                        if mode == .teleport {
                            coordBlock
                        }
                        if showsTravelMotion {
                            motionBlock
                        }
                        if StopTravelCardText.showsStopOptions(for: mode) {
                            stopOptionsBlock
                        }
                        if mode == .joystick {
                            joystickBlock
                        }
                        toggleBlock
                        metricsBlock
                        notesBlock
                    }
                    .padding(.horizontal, 13)
                    .padding(.bottom, 2)
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
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.18), radius: 18, y: 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            OrganicGlyphView(glyph: mode.glyph, size: 16)
                .foregroundStyle(Organic.accent800)
                .frame(width: 30, height: 30)
                .background(Organic.accent200)
                .clipShape(Circle())
            Text(mode.cardTitle)
                .font(Organic.heading(15))
                .foregroundStyle(Organic.accent800)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Organic.neutral600)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var routeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("ROUTE")
                    .font(Organic.body(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Organic.accent800)
                Spacer()
                if appState.currentRoute.count >= 2 {
                    Button {
                        appState.reverseRoute(for: mode)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Organic.accent800)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Swap start and destination")
                }
                Button {
                    for stop in appState.currentRoute {
                        favorites.addFavorite(name: stop.formattedShort, coordinate: stop)
                    }
                    appState.statusMessage = "Saved stops to Favorites"
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Organic.accent800)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Save every point to Favorites")
                .accessibilityLabel("Save every point to Favorites")
            }

            if displayStops.isEmpty {
                Text("Click the map to add a stop")
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayStops.enumerated()), id: \.offset) { index, stop in
                        HStack(spacing: 8) {
                            Text(index == 0 && mode != .jump ? "" : "\(mode == .jump ? index + 1 : index)")
                                .font(Organic.body(10, weight: .bold))
                                .foregroundStyle(Organic.neutral100)
                                .frame(width: 20, height: 20)
                                .background(index == 0 && mode != .jump ? Organic.sage600 : Organic.accent600)
                                .clipShape(Circle())
                                .overlay {
                                    if index == 0 && mode != .jump {
                                        Circle().fill(Organic.sage600)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.name)
                                    .font(Organic.body(12, weight: .bold))
                                    .lineLimit(1)
                                Text(stop.coordinate.formattedShort)
                                    .font(Organic.mono(10))
                                    .foregroundStyle(Organic.neutral600)
                            }
                            .accessibilityElement(children: .combine)
                            Spacer(minLength: 0)
                            Button {
                                favorites.toggleFavorite(name: stop.name, coordinate: stop.coordinate)
                            } label: {
                                Image(systemName: favorites.isFavorite(stop.coordinate) ? "star.fill" : "star")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(favorites.isFavorite(stop.coordinate) ? Organic.accent600 : Organic.neutral500)
                            }
                            .buttonStyle(.plain)
                            Button {
                                removeDisplayStop(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Organic.neutral600)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(10)
        .background(Organic.accent100)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.accent300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    private var coordBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                coordField("LATITUDE", text: $latitudeInput)
                coordField("LONGITUDE", text: $longitudeInput)
            }
            if appState.locationPresentation.desiredCoordinate == nil {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("location.teleport.noTarget", comment: "Teleport empty target title"))
                            .font(Organic.body(11, weight: .semibold))
                        Text(NSLocalizedString("location.teleport.targetHint", comment: "Teleport target selection guidance"))
                            .font(Organic.body(10))
                    }
                } icon: {
                    Image(systemName: "mappin.slash")
                }
                .foregroundStyle(Organic.neutral700)
                .accessibilityLabel(NSLocalizedString("location.teleport.noTarget", comment: "Teleport empty target title"))
                .accessibilityHint(NSLocalizedString("location.teleport.targetHint", comment: "Teleport target selection guidance"))
                .accessibilityIdentifier("location.teleport.emptyTarget")
            }
        }
        .padding(10)
        .background(Organic.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    private func coordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Organic.body(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Organic.mono(12))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Organic.neutral100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
                .onSubmit(onCommitCoords)
        }
    }

    private var motionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRAVEL MODE")
                    .font(Organic.body(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Organic.neutral600)
                Spacer()
                Text(StopTravelCardText.travelModeTitle(appState.simulationSpeed, autoSpeed: appState.autoSpeed))
                    .font(Organic.body(10, weight: .bold))
                    .foregroundStyle(Organic.accent800)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                ForEach(travelModes, id: \.self) { speed in
                    // Selected only while the preset is the speed in use (Auto on).
                    let selected = appState.autoSpeed && appState.simulationSpeed == speed
                    Button {
                        appState.selectTravelMode(speed)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: travelIcon(speed))
                                .font(.system(size: 13, weight: .semibold))
                                .frame(height: 16)
                            Text(StopTravelCardText.travelName(speed))
                                .font(Organic.body(9.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Organic.accent800 : Organic.neutral700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selected ? Organic.accent200 : Organic.neutral100)
                        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                                .stroke(selected ? Organic.accent400 : Organic.neutral300, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("\(StopTravelCardText.travelName(speed)), \(String(format: "%.1f", speed.presetMetersPerSecond)) m/s")
                    .accessibilityLabel(StopTravelCardText.travelName(speed))
                    .accessibilityValue(String(format: "%.1f metres per second", speed.presetMetersPerSecond))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            OrganicSliderRow(
                title: "Speed",
                valueLabel: String(format: "%.1f m/s", appState.customSpeedMps),
                value: $appState.customSpeedMps,
                range: 1...30,
                step: 0.1,
                isAuto: appState.autoSpeed,
                onToggleAuto: {
                    appState.autoSpeed.toggle()
                    if appState.autoSpeed {
                        appState.customSpeedMps = appState.mockMetersPerSecond(for: appState.simulationSpeed)
                    }
                }
            )
            if let note = StopTravelCardText.speedNote(settings: stopSettings, isRunActive: isStopRunActive) {
                caption(note, systemImage: isStopRunActive ? "clock.arrow.circlepath" : "info.circle")
            }
        }
        .padding(10)
        .background(Organic.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    /// A short explanation under a control: muted, wrapping, read as one line.
    private func caption(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(Organic.body(10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Organic.neutral600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var joystickBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                readout("HEADING", headingText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(headingAccessibilityLabel)
                readout("SPEED", String(format: "%.1f", appState.locationPresentation.isMovementActive ? appState.joystickSpeed : 0))
                readout("POSITION", (appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate)?.formattedShort ?? "—")
            }
            // Joystick's own speed: travel modes do not apply, so there is no Auto (3.5).
            OrganicSliderRow(
                title: "Speed",
                valueLabel: String(format: "%.1f m/s", appState.joystickSpeed),
                value: $appState.joystickSpeed,
                range: SimulationStateManager.joystickSpeedRange,
                step: 0.1
            )
        }
        .padding(10)
        .background(Organic.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
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

    private var stopOptionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STOPS")
                .font(Organic.body(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
                .accessibilityAddTraits(.isHeader)
            // Controls stay enabled mid-run: see `StopTravelCardText.runEditNote`.
            ForEach(StopTravelCardText.visibleControls(for: mode, settings: stopSettings)) { control in
                stopControlRow(control)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if control == .arrival || control == .jumpTiming,
                   StopTravelCardText.visibleControls(for: mode, settings: stopSettings).last(where: { $0 == .arrival || $0 == .jumpTiming }) == control {
                    // How to get there, then what happens at each stop.
                    Rectangle().fill(Organic.neutral300.opacity(0.7)).frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            if let note = StopTravelCardText.runEditNote(isRunActive: isStopRunActive) {
                caption(note, systemImage: "exclamationmark.circle")
            }
        }
        // Jump timing slides in instead of pushing the rows below in one jump.
        .animation(.easeInOut(duration: 0.18), value: stopSettings.arrival)
        .padding(10)
        .background(Organic.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    @ViewBuilder
    private func stopControlRow(_ control: StopTravelCardText.Control) -> some View {
        switch control {
        case .arrival:
            stopChoices(control, selection: appState.stopSettingBinding(\.arrival, for: mode),
                        options: StopTravelSettings.Arrival.allCases, title: StopTravelCardText.title, icon: Self.icon)
        case .jumpTiming:
            VStack(alignment: .leading, spacing: 5) {
                stopChoices(control, selection: appState.stopSettingBinding(\.jumpTiming, for: mode),
                            options: StopTravelSettings.JumpTiming.allCases, title: StopTravelCardText.title, icon: Self.icon)
                caption(StopTravelCardText.jumpTimingCaption(for: stopSettings), systemImage: "info.circle")
            }
        case .hold:
            stopHoldRow
        case .progression:
            stopChoices(control, selection: appState.stopSettingBinding(\.progression, for: mode),
                        options: StopTravelSettings.Progression.allCases, title: StopTravelCardText.title, icon: Self.icon)
        case .repeatMode:
            stopChoices(control, selection: appState.stopSettingBinding(\.repeatMode, for: mode),
                        options: StopTravelSettings.RepeatMode.allCases, title: StopTravelCardText.title, icon: Self.icon)
        }
    }

    /// A labelled row of Organic choice buttons (the segmented pickers used the system
    /// blue and crowded "One stop per Move" / "Back and forth"). The visible title is
    /// hidden from VoiceOver because the group carries the same label, so it is read once;
    /// each choice reads its title and Selected.
    private func stopChoices<Option: Hashable>(
        _ control: StopTravelCardText.Control,
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> String,
        icon: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(control.label)
                .font(Organic.body(12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: icon(option))
                                .font(.system(size: 11, weight: .semibold))
                                .frame(height: 14)
                                .accessibilityHidden(true)
                            Text(title(option))
                                .font(Organic.body(10.5, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(selected ? Organic.accent800 : Organic.neutral700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selected ? Organic.accent200 : Organic.neutral100)
                        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                                .stroke(selected ? Organic.accent400 : Organic.neutral300, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
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

    private var stopHoldRow: some View {
        let control = StopTravelCardText.Control.hold
        let seconds = stopSettings.holdSeconds
        let applies = StopTravelCardText.holdApplies(stopSettings)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(control.label)
                    .font(Organic.body(12, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
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
                .accessibilityHint(StopTravelCardText.holdNote(stopSettings) ?? "")
                .accessibilityIdentifier(control.accessibilityIdentifier)
                Text(StopTravelCardText.holdLabel(seconds))
                    .font(Organic.mono(11, weight: .bold))
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            // With one stop per Move nothing continues after a stop, so the hold has no
            // effect: shown dimmed and disabled (its value is kept) instead of looking live.
            .disabled(!applies)
            .opacity(applies ? 1 : 0.5)
            if let note = StopTravelCardText.holdNote(stopSettings) {
                caption(note, systemImage: "info.circle")
            }
        }
    }

    /// The running stop run: a headline naming the phase with its countdown, then one
    /// line per remaining fact, each read on its own.
    @ViewBuilder
    private var stopProgressReadout: some View {
        if StopTravelCardText.showsStopOptions(for: mode), let progress = appState.stopProgress {
            let countdown = progress.holdSecondsLeft ?? progress.legSecondsLeft
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: Self.phaseIcon(progress))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(progress.isPaused ? Organic.neutral700 : Organic.accent700)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(StopTravelCardText.phaseTitle(progress))
                        .font(Organic.body(12, weight: .bold))
                        .foregroundStyle(Organic.neutral800)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    if let countdown {
                        Text(StopTravelCardText.clock(countdown))
                            .font(Organic.mono(15, weight: .bold))
                            .foregroundStyle(progress.isPaused ? Organic.neutral600 : Organic.accent800)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(StopTravelCardText.phaseTitle(progress))
                .accessibilityValue(countdown.map { StopTravelCardText.clock($0) } ?? "")
                ForEach(StopTravelCardText.progressLines(progress).filter { [.nextStop, .fallback, .routeNote].contains($0.kind) }) { line in
                    Text(line.text)
                        .font(line.kind == .nextStop ? Organic.body(11, weight: .semibold) : Organic.body(10.5))
                        .foregroundStyle(line.kind == .fallback ? Organic.accent800 : Organic.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 24)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(progress.isPaused ? Organic.neutral200 : Organic.accent100)
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                    .stroke(progress.isPaused ? Organic.neutral400 : Organic.accent300, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stop progress")
            .accessibilityIdentifier(StopTravelCardText.progressIdentifier)
        } else if let done = completionLine {
            Label(done, systemImage: "checkmark.circle.fill")
                .font(Organic.body(11, weight: .semibold))
                .foregroundStyle(Organic.sage800)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Organic.sage100)
                .overlay(
                    RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                        .stroke(Organic.sage300, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                .accessibilityLabel(done)
        }
    }

    private static func phaseIcon(_ progress: StopProgress) -> String {
        if progress.isPaused { return "pause.circle.fill" }
        switch progress.phase {
        case .findingRoute: return "map"
        case .travelling: return "location.north.line.fill"
        case .waitingToJump: return "hourglass"
        case .jumping: return "scope"
        case .holding: return "mappin.and.ellipse"
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
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Organic.body(12, weight: .semibold))
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().tint(Organic.accent600)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 2)
    }

    private var metricsBlock: some View {
        VStack(spacing: 1) {
            if mode.showsDistance {
                // Straight-line sums of the stops: road legs and holds are not included.
                metricRow(system: "mappin.circle", title: mode == .teleport ? "Distance" : "Distance (straight line)", value: routeDistance)
            }
            if mode == .route || mode == .twospot {
                metricRow(system: "clock", title: "Est. time (straight line)", value: routeETA)
            }
            if mode == .jump {
                // The stop the phone holds, not the cursor: after a Loop wrap the cursor
                // reads 0 while the phone holds the last stop.
                metricRow(system: "mappin.and.ellipse", title: "At stop", value: StopTravelCardText.atStopValue(reached: reachedStopIndex, total: appState.displayStops(for: mode).count))
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300.opacity(0.85)).frame(height: 1) }
    }

    private func metricRow(system: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Organic.accent600)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(title)
                .font(Organic.body(12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
            Spacer()
            Text(value)
                .font(Organic.mono(12, weight: .bold))
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notesBlock: some View {
        EmptyView()
    }

    private func note(_ text: String, sage: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(Organic.body(11, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(sage ? Organic.sage800 : Organic.accent800)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sage ? Organic.sage100 : Organic.accent100)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(sage ? Organic.sage300 : Organic.accent300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            stopProgressReadout
            HStack(spacing: 8) {
                if mode == .joystick {
                    Button("Stop movement") {
                        appState.disengageJoystick()
                    }
                    .accessibilityIdentifier("location.action.stopMovement")
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.sage800)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Organic.sage100)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Organic.sage300, lineWidth: 1))
                    .disabled(!appState.locationPresentation.isMovementActive)
                    .opacity(appState.locationPresentation.isMovementActive ? 1 : 0.55)
                } else {
                    Button(action: onMove) {
                        HStack(spacing: 6) {
                            Image(systemName: moveIcon)
                                .font(.system(size: 11, weight: .bold))
                            Text(moveLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(canMove ? Organic.accentInk : Organic.neutral700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(canMove ? Organic.accent : Organic.neutral400)
                    .clipShape(Capsule())
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
                            .font(Organic.body(12, weight: .bold))
                            .foregroundStyle(Organic.sage800)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Capsule().fill(Organic.sage100))
                            .overlay(Capsule().strokeBorder(Organic.sage300, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pause.title)
                        .accessibilityIdentifier(StopTravelCardText.pauseIdentifier)
                    }

                    Button(resetActionLabel) {
                        resetContext()
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
                    .clipShape(Capsule())
                    .disabled(!canResetRoute)
                    .opacity(canResetRoute ? 1 : 0.55)
                }
            }
            if let reason = disabledMoveReason {
                Label(reason, systemImage: "info.circle")
                    .font(Organic.body(11, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .accessibilityLabel(reason)
                    .accessibilityIdentifier("location.action.disabledReason")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300).frame(height: 1) }
    }

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
            return "Move · \(min(appState.jumpIndex + 1, appState.currentRoute.count))/\(appState.currentRoute.count)"
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
        let name: String
        let coordinate: LocationCoordinate
        let fromRoute: Bool
    }

    private var displayStops: [DisplayStop] {
        if mode == .twospot {
            let spots = appState.currentRoute
            if spots.count >= 2 {
                return [
                    DisplayStop(name: "Start", coordinate: spots[0], fromRoute: true),
                    DisplayStop(name: spots[1].formattedShort, coordinate: spots[1], fromRoute: true),
                ]
            }
            var rows: [DisplayStop] = []
            if let current = appState.moveStartCoordinate {
                rows.append(DisplayStop(name: address.isEmpty ? "Start" : address, coordinate: current, fromRoute: false))
            }
            if let dest = appState.currentRoute.last ?? appState.locationPresentation.desiredCoordinate {
                rows.append(DisplayStop(name: dest.formattedShort, coordinate: dest, fromRoute: true))
            }
            return rows
        }
        if mode == .jump || mode == .route {
            return appState.currentRoute.enumerated().map { index, coord in
                DisplayStop(
                    name: index == 0 ? "Start" : (index == appState.currentRoute.count - 1 ? "Finish" : "Stop \(index)"),
                    coordinate: coord,
                    fromRoute: true
                )
            }
        }
        if let target = appState.locationPresentation.desiredCoordinate {
            return [DisplayStop(name: address, coordinate: target, fromRoute: false)]
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Organic.body(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
            Text(value)
                .font(Organic.body(15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Organic.neutral100)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
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

    private static func hms(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

extension AppMode {
    var cardTitle: String {
        switch self {
        case .teleport: return "Teleport"
        case .jump: return "Jump Teleport"
        case .twospot: return "Two-spot Mode"
        case .route: return "Multi-spot Mode"
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
