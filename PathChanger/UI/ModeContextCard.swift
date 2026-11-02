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

struct ModeContextCard: View {
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
            footer
        }
        .frame(width: 336)
        .fixedSize(horizontal: false, vertical: true)
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
                Text(travelName(appState.simulationSpeed))
                    .font(Organic.body(10, weight: .bold))
                    .foregroundStyle(Organic.accent800)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                ForEach(travelModes, id: \.self) { speed in
                    Button {
                        appState.setSpeed(speed)
                    } label: {
                        Image(systemName: travelIcon(speed))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appState.simulationSpeed == speed ? Organic.accent800 : Organic.neutral700)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(appState.simulationSpeed == speed ? Organic.accent200 : Organic.neutral100)
                            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                                    .stroke(appState.simulationSpeed == speed ? Organic.accent400 : Organic.neutral300, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(travelName(speed))
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
        }
        .padding(10)
        .background(Organic.bg)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
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
        VStack(alignment: .leading, spacing: 9) {
            Text("STOPS")
                .font(Organic.body(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
                .accessibilityAddTraits(.isHeader)
            // Controls stay enabled mid-run: see `StopTravelCardText.runEditNote`.
            ForEach(StopTravelCardText.visibleControls(for: mode, settings: stopSettings)) { control in
                stopControlRow(control)
            }
            if let note = StopTravelCardText.runEditNote(isRunActive: isStopRunActive) {
                Text(note)
                    .font(Organic.body(10))
                    .foregroundStyle(Organic.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private func stopControlRow(_ control: StopTravelCardText.Control) -> some View {
        switch control {
        case .arrival:
            stopSegmented(control, selection: appState.stopSettingBinding(\.arrival, for: mode),
                          options: StopTravelSettings.Arrival.allCases, title: StopTravelCardText.title)
        case .jumpTiming:
            VStack(alignment: .leading, spacing: 4) {
                stopSegmented(control, selection: appState.stopSettingBinding(\.jumpTiming, for: mode),
                              options: StopTravelSettings.JumpTiming.allCases, title: StopTravelCardText.title)
                Text(StopTravelCardText.jumpTimingCaption)
                    .font(Organic.body(10))
                    .foregroundStyle(Organic.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .hold:
            stopHoldRow
        case .progression:
            stopSegmented(control, selection: appState.stopSettingBinding(\.progression, for: mode),
                          options: StopTravelSettings.Progression.allCases, title: StopTravelCardText.title)
        case .repeatMode:
            stopSegmented(control, selection: appState.stopSettingBinding(\.repeatMode, for: mode),
                          options: StopTravelSettings.RepeatMode.allCases, title: StopTravelCardText.title)
        }
    }

    /// A labelled segmented picker. The visible title is hidden from VoiceOver because
    /// the picker carries the same label, so it is read once.
    private func stopSegmented<Option: Hashable>(
        _ control: StopTravelCardText.Control,
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(control.label)
                .font(Organic.body(12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .accessibilityHidden(true)
            Picker(control.label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(control.label)
            .accessibilityIdentifier(control.accessibilityIdentifier)
        }
    }

    private var stopHoldRow: some View {
        let control = StopTravelCardText.Control.hold
        let seconds = stopSettings.holdSeconds
        return HStack(spacing: 10) {
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
            .accessibilityIdentifier(control.accessibilityIdentifier)
            Text(StopTravelCardText.holdLabel(seconds))
                .font(Organic.mono(11, weight: .bold))
                .frame(width: 52, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// The running stop run: one line per fact, each read on its own.
    @ViewBuilder
    private var stopProgressReadout: some View {
        if StopTravelCardText.showsStopOptions(for: mode), let progress = appState.stopProgress {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(StopTravelCardText.progressLines(progress)) { line in
                    Text(line.text)
                        .font(line.kind == .fallback || line.kind == .routeNote ? Organic.body(11) : Organic.body(11, weight: .semibold))
                        .foregroundStyle(line.kind == .fallback ? Organic.accent800 : Organic.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Stop progress")
            .accessibilityIdentifier(StopTravelCardText.progressIdentifier)
        }
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
                metricRow(system: "mappin.circle", title: "Distance", value: routeDistance)
            }
            if mode == .route || mode == .twospot {
                metricRow(system: "clock", title: "Duration", value: routeETA)
            }
            if mode == .jump {
                metricRow(system: "arrow.up.right", title: "Hop", value: "\(min(appState.jumpIndex, appState.currentRoute.count))/\(appState.currentRoute.count)")
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
                        }
                        .buttonStyle(.plain)
                        .font(Organic.body(12, weight: .bold))
                        .foregroundStyle(Organic.sage800)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Organic.sage100)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Organic.sage300, lineWidth: 1))
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
        case .twospot: return (appState.locationPresentation.appliedCoordinate != nil && (appState.locationPresentation.desiredCoordinate != nil || !appState.currentRoute.isEmpty)) || appState.currentRoute.count >= 2
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
           let start = appState.locationPresentation.appliedCoordinate, coords.first != start {
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
            if let current = appState.locationPresentation.appliedCoordinate {
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
            if index == 0, appState.locationPresentation.appliedCoordinate != nil, displayStops.count > 1 {
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

    private func travelName(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        case .fast: return "Riding"
        default: return speed.displayName
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
