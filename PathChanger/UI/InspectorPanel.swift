//
//  InspectorPanel.swift
//  PathChanger
//
//  Right inspector from the pth mock: Teleport / Multi-Spot / Joystick.
//

import SwiftUI
import AppKit

struct InspectorPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var mode: AppMode
    @Binding var latitudeInput: String
    @Binding var longitudeInput: String
    var address: String
    let onTeleport: () -> Void
    let onCommitCoords: () -> Void

    private let travelModes: [SimulationSpeed] = [.walking, .cycling, .driving, .fast]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch mode {
                    case .route:
                        multiSpotCards
                    case .joystick:
                        joystickCards
                    default:
                        teleportCards
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 372)
        .background(Organic.bg)
        .overlay(alignment: .leading) {
            Rectangle().fill(Organic.neutral300).frame(width: 1)
        }
        .onChange(of: mode) { _, newMode in
            appState.activeMode = newMode == .settings ? .teleport : newMode
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tab("Teleport", .teleport)
            tab("Multi-Spot", .route)
            tab("Joystick", .joystick)
        }
        .padding(3)
        .background(Organic.neutral300)
        .clipShape(Capsule())
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }
    }

    private func tab(_ title: String, _ value: AppMode) -> some View {
        Button {
            mode = value
            appState.activeMode = value
        } label: {
            Text(title)
                .font(Organic.body(12.5, weight: .bold))
                .foregroundStyle(Organic.text)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(mode == value ? Organic.neutral100 : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Teleport

    private var teleportCards: some View {
        VStack(spacing: 14) {
            inspectorCard {
                cardHeader(icon: "mappin.circle", tint: Organic.accent600, title: "Target location", meta: "editable")
                HStack(spacing: 9) {
                    coordField("LATITUDE", text: $latitudeInput)
                    coordField("LONGITUDE", text: $longitudeInput)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ADDRESS")
                            .font(Organic.body(10.5, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(Organic.neutral600)
                        Text(address)
                            .font(Organic.body(12.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(appState.copiedFeedback ? "Copied" : "Copy") {
                        appState.copyCoordinates()
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(appState.copiedFeedback ? Organic.sage800 : Organic.accent700)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(appState.copiedFeedback ? Organic.sage100 : Color.clear)
                    .overlay(Capsule().stroke(appState.copiedFeedback ? Organic.sage700 : Organic.accent400, lineWidth: 1))
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300.opacity(0.8)).frame(height: 1).padding(.top, -1) }

                if let warning = appState.lastTeleportMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(Organic.accent700)
                        Text(warning)
                            .font(Organic.body(11))
                            .foregroundStyle(Organic.accent800)
                    }
                    .padding(10)
                    .background(Organic.accent100)
                    .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                }

                HStack(spacing: 9) {
                    Button(action: onTeleport) {
                        Text(appState.isSimulating && mode == .teleport ? "Update location" : "Set location")
                    }
                    .buttonStyle(.plain)
                    .primaryButtonStyle(isDisabled: !appState.canStartSimulation)

                    Button("Reset") {
                        Task { await appState.clearLocation() }
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(12.5, weight: .bold))
                    .foregroundStyle(Organic.text)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
                }
                .padding(.top, 14)
            }

            movementCard(modes: travelModes)
        }
    }

    // MARK: Multi-Spot

    private var multiSpotCards: some View {
        VStack(spacing: 14) {
            inspectorCard {
                cardHeader(icon: "point.topleft.down.curvedto.point.bottomright.up", tint: Organic.sage700, title: "Route", meta: "\(appState.currentRoute.count) stops")

                if appState.currentRoute.isEmpty {
                    VStack(spacing: 3) {
                        Text("No stops yet")
                            .font(Organic.body(12.5, weight: .semibold))
                        Text("Click the map to add stops, then drag to reorder.")
                            .font(Organic.body(11))
                            .foregroundStyle(Organic.neutral600)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .background(Organic.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Organic.neutral400)
                    )
                } else {
                    List {
                        ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Organic.neutral500)
                                Text("\(index + 1)")
                                    .font(Organic.body(11, weight: .bold))
                                    .foregroundStyle(Organic.neutral100)
                                    .frame(width: 20, height: 20)
                                    .background(index == 0 ? Organic.sage600 : Organic.accent600)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(coord.formattedShort)
                                        .font(Organic.mono(11.5, weight: .semibold))
                                    Text(index == 0 ? "Start" : (index == appState.currentRoute.count - 1 ? "Finish" : "Stop"))
                                        .font(Organic.body(10.5))
                                        .foregroundStyle(Organic.neutral600)
                                }
                                Spacer()
                                Button {
                                    appState.removeRouteWaypoint(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Organic.neutral700)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { source, destination in
                            guard let from = source.first else { return }
                            appState.moveRouteWaypoint(from: from, to: destination)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: min(212, CGFloat(appState.currentRoute.count) * 52))
                }

                HStack {
                    stat("DISTANCE", routeDistance, unit: " km")
                    stat("EST. TIME", routeETA, unit: "")
                    stat("STOPS", "\(appState.currentRoute.count)", unit: "")
                }
                .padding(.top, 13)
                .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300.opacity(0.8)).frame(height: 1) }

                HStack(spacing: 8) {
                    Button("Import GPX") { appState.showRouteImport = true }
                        .buttonStyle(.plain)
                        .font(Organic.body(12, weight: .bold))
                        .foregroundStyle(Organic.accent700)
                    Spacer()
                    Button("Undo") { appState.removeLastRouteWaypoint() }
                        .buttonStyle(.plain)
                        .font(Organic.body(12, weight: .semibold))
                        .disabled(appState.currentRoute.isEmpty || appState.isSimulating)
                    Button("Clear") { appState.clearRoute() }
                        .buttonStyle(.plain)
                        .font(Organic.body(12, weight: .semibold))
                        .disabled(appState.currentRoute.isEmpty || appState.isSimulating)
                }
                .padding(.top, 8)
            }

            inspectorCard {
                cardHeader(icon: "play.fill", tint: Organic.accent600, title: "Travel & playback", meta: nil)
                travelModeGrid(travelModes)
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
                loopToggle
                if appState.isSimulating && mode == .route {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Playing")
                            Spacer()
                            Text("\(Int(appState.routeProgress * 100))%")
                        }
                        .font(Organic.body(11, weight: .semibold))
                        .foregroundStyle(Organic.neutral700)
                        ProgressView(value: appState.routeProgress)
                            .tint(Organic.accent600)
                    }
                }
                Button {
                    Task { await appState.startSimulation() }
                } label: {
                    Text(appState.isSimulating ? "Pause / continue from Play" : "Run route")
                }
                .buttonStyle(.plain)
                .primaryButtonStyle(isDisabled: !appState.canStartSimulation || appState.currentRoute.count < 2)
                .padding(.top, 8)
                Text(appState.currentRoute.count < 2 ? "Add at least two stops on the map" : "Drag to reorder. Double-click a stop on the map to remove it.")
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Joystick

    private var joystickCards: some View {
        VStack(spacing: 14) {
            inspectorCard {
                cardHeader(icon: "gamecontroller", tint: Organic.accent600, title: "Manual control", meta: appState.isSimulating ? "Live" : "Standby")
                HStack(spacing: 9) {
                    readout("HEADING", headingText)
                    readout("SPEED", String(format: "%.1f", appState.isSimulating ? appState.effectiveMetersPerSecond : 0))
                    readout("POSITION", (appState.currentLocation ?? appState.targetLocation)?.formattedShort ?? "—")
                }
            }

            inspectorCard {
                cardHeader(icon: "arrow.right", tint: Organic.sage700, title: "Travel & speed", meta: nil)
                travelModeGrid(travelModes)
                OrganicSliderRow(
                    title: "Max speed",
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
                safeToggle(
                    title: appState.safeModeJoystick ? "Safe Mode Enabled" : "Safe Mode Off",
                    body: "Smooths acceleration so movement looks human.",
                    isOn: $appState.safeModeJoystick
                )
                Button {
                    Task {
                        if appState.isSimulating {
                            appState.disengageJoystick()
                        } else {
                            await appState.startSimulation()
                        }
                    }
                } label: {
                    Text(appState.isSimulating ? "Disengage" : "Engage joystick")
                }
                .buttonStyle(.plain)
                .primaryButtonStyle(isDisabled: !appState.canStartSimulation && !appState.isSimulating)
                .padding(.top, 8)
                Text("Drag the on-map joystick or use arrow keys")
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Shared bits

    private func movementCard(modes: [SimulationSpeed]) -> some View {
        inspectorCard {
            cardHeader(icon: "arrow.right", tint: Organic.sage700, title: "Movement", meta: nil)
            Text("TRAVEL MODE")
                .font(Organic.body(10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Organic.neutral600)
            travelModeGrid(modes)
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
            OrganicSliderRow(
                title: "Cooldown",
                valueLabel: String(format: "%.1f s", appState.cooldownSeconds),
                value: $appState.cooldownSeconds,
                range: 0...10,
                step: 0.5,
                isAuto: appState.autoCooldown,
                onToggleAuto: {
                    appState.autoCooldown.toggle()
                    if appState.autoCooldown {
                        appState.cooldownSeconds = appState.mockCooldown(for: appState.simulationSpeed)
                    }
                }
            )
            safeToggle(
                title: appState.safeModeTeleport ? "Safe Mode Enabled" : "Safe Mode Off",
                body: "Mimics natural movement and respects cooldown to avoid detection.",
                isOn: $appState.safeModeTeleport
            )
        }
    }

    private func travelModeGrid(_ modes: [SimulationSpeed]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(modes, id: \.self) { speed in
                Button {
                    appState.setSpeed(speed)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: travelIcon(speed))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appState.simulationSpeed == speed ? Organic.accent700 : Organic.neutral700)
                            .frame(width: 28, height: 28)
                            .background(appState.simulationSpeed == speed ? Organic.accent200 : Organic.neutral200)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(travelName(speed))
                                .font(Organic.body(12, weight: .bold))
                            Text(travelSubtitle(speed))
                                .font(Organic.body(10.5))
                                .foregroundStyle(Organic.neutral600)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(appState.simulationSpeed == speed ? Organic.accent100 : Organic.bg)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(appState.simulationSpeed == speed ? Organic.accent500 : Organic.neutral300, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loopToggle: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(Organic.accent700)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loop route")
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.accent900)
                Text("Repeat the path continuously when it reaches the last stop.")
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.accent800)
            }
            Spacer()
            Toggle("", isOn: $appState.loopRoute)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Organic.accent600)
        }
        .padding(12)
        .background(Organic.accent100)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.accent300, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
    }

    private func safeToggle(title: String, body: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(Organic.sage700)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.sage900)
                Text(body)
                    .font(Organic.body(11))
                    .foregroundStyle(Organic.sage800)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Organic.sage600)
        }
        .padding(12)
        .background(isOn.wrappedValue ? Organic.sage100 : Organic.neutral200)
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(isOn.wrappedValue ? Organic.sage300 : Organic.neutral400, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
        .padding(.top, 6)
    }

    private func inspectorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
    }

    private func cardHeader(icon: String, tint: Color, title: String, meta: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(Organic.body(13, weight: .bold))
            Spacer()
            if let meta {
                Text(meta)
                    .font(Organic.body(10.5))
                    .foregroundStyle(Organic.neutral600)
            }
        }
    }

    private func coordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Organic.body(10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Organic.neutral600)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Organic.mono(12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Organic.bg)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
                .onSubmit(onCommitCoords)
        }
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Organic.body(10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Organic.neutral600)
            Text(value)
                .font(Organic.body(15, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Organic.bg)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
    }

    private func stat(_ title: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Organic.body(10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(Organic.neutral600)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Organic.body(15, weight: .bold))
                if !unit.isEmpty {
                    Text(unit)
                        .font(Organic.body(10.5, weight: .semibold))
                        .foregroundStyle(Organic.neutral600)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headingText: String {
        let dir = appState.joystickDirection
        guard hypot(dir.x, dir.y) > 0.05 else { return "—°" }
        let degrees = (atan2(dir.x, dir.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return String(format: "%.0f°", degrees)
    }

    private var routeDistance: String {
        guard appState.currentRoute.count > 1 else { return "0.0" }
        var meters = 0.0
        for index in 1..<appState.currentRoute.count {
            meters += RouteInterpolator.haversineDistance(from: appState.currentRoute[index - 1], to: appState.currentRoute[index])
        }
        return String(format: "%.1f", meters / 1000)
    }

    private var routeETA: String {
        guard appState.currentRoute.count > 1 else { return "0:00" }
        var meters = 0.0
        for index in 1..<appState.currentRoute.count {
            meters += RouteInterpolator.haversineDistance(from: appState.currentRoute[index - 1], to: appState.currentRoute[index])
        }
        let seconds = meters / max(appState.effectiveMetersPerSecond, 0.1)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func travelName(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .fast: return "Transit"
        default: return speed.displayName
        }
    }

    private func travelSubtitle(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "3.5 mph"
        case .cycling: return "12 mph"
        case .driving: return "35 mph"
        case .fast: return "60 mph"
        default: return speed.displayName
        }
    }

    private func travelIcon(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .fast: return "bus.fill"
        default: return speed.icon
        }
    }
}
