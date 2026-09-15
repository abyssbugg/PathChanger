//
//  ModeContextCard.swift
//  PathChanger
//
//  Floating 336px mode card from the pctnhc mock.
//

import SwiftUI

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
                    if mode.showsMotion {
                        motionBlock
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
        .frame(maxHeight: 560)
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
        HStack(spacing: 9) {
            coordField("LATITUDE", text: $latitudeInput)
            coordField("LONGITUDE", text: $longitudeInput)
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
            if mode == .route || mode == .twospot {
                HStack(spacing: 9) {
                    Text("Repeat")
                        .font(Organic.body(12, weight: .semibold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 56, alignment: .leading)
                    Toggle("Loop", isOn: $appState.loopRoute)
                        .toggleStyle(.switch)
                        .tint(Organic.accent600)
                        .labelsHidden()
                    Text(appState.loopRoute ? "Loop around" : "One way")
                        .font(Organic.body(12, weight: .semibold))
                    Spacer()
                }
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

    private var joystickBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                readout("HEADING", headingText)
                readout("SPEED", String(format: "%.1f", appState.locationPresentation.isMovementActive ? appState.effectiveMetersPerSecond : 0))
                readout("POSITION", (appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate)?.formattedShort ?? "—")
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

    private var toggleBlock: some View {
        VStack(spacing: 1) {
            if mode == .joystick {
                toggleLine(
                    "Smooth corners",
                    Binding(get: { appState.smoothTurns }, set: { appState.smoothTurns = $0 })
                )
            }
            if mode == .jump {
                toggleLine(
                    "Auto jump after each applied waypoint",
                    Binding(get: { appState.autoJump }, set: { appState.autoJump = $0 })
                )
            }
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
            Text(title)
                .font(Organic.body(12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
            Spacer()
            Text(value)
                .font(Organic.mono(12, weight: .bold))
        }
        .frame(height: 28)
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
                .foregroundStyle(Organic.neutral100)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(canMove ? Organic.accent : Organic.neutral400)
                .clipShape(Capsule())
                .disabled(!canMove)
                .accessibilityIdentifier(appState.locationPresentation.isMovementActive ? "location.action.stopMovement" : "location.action.apply")

                Button("Reset Route") {
                    appState.clearRoute()
                    if let current = appState.locationPresentation.appliedCoordinate { appState.stageLocation(current, for: mode) }
                }
                .buttonStyle(.plain)
                .font(Organic.body(12, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300).frame(height: 1) }
    }

    private var canMove: Bool {
        // A device exposed directly by usbmux over USB or Network/Wi-Fi is ready without
        // RemoteXPC. The old app worked over Wi-Fi through this exact `--udid` path; gating
        // only on `tunneldManager.isRunning` disabled every mode in the fixed build.
        if !appState.canStartSimulation { return false }
        switch mode {
        case .teleport: return appState.locationPresentation.desiredCoordinate != nil
        case .jump: return !appState.currentRoute.isEmpty && appState.jumpIndex < appState.currentRoute.count
        case .twospot: return (appState.locationPresentation.appliedCoordinate != nil && (appState.locationPresentation.desiredCoordinate != nil || !appState.currentRoute.isEmpty)) || appState.currentRoute.count >= 2
        case .route: return appState.currentRoute.count >= 2
        case .joystick: return appState.locationPresentation.desiredCoordinate != nil || appState.locationPresentation.appliedCoordinate != nil
        case .settings: return false
        }
    }

    private var moveLabel: String {
        if appState.locationPresentation.isMovementActive, mode == .route || mode == .twospot {
            return "Stop"
        }
        if mode == .jump, !appState.currentRoute.isEmpty {
            return "Move · \(min(appState.jumpIndex + 1, appState.currentRoute.count))/\(appState.currentRoute.count)"
        }
        return "Move"
    }

    private var moveIcon: String {
        if appState.locationPresentation.isMovementActive, mode == .route || mode == .twospot { return "stop.fill" }
        return "play.fill"
    }

    private var headingText: String {
        let dir = appState.joystickDirection
        guard hypot(dir.x, dir.y) > 0.05 else { return "—" }
        let degrees = (atan2(dir.x, dir.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return String(format: "%.0f°", degrees)
    }

    private var routeDistance: String {
        let points = displayStops.map(\.coordinate)
        guard points.count + (appState.locationPresentation.appliedCoordinate == nil ? 0 : 0) >= 1 else { return "—" }
        var coords = points
        if mode == .twospot, let start = appState.locationPresentation.appliedCoordinate, coords.first != start {
            coords.insert(start, at: 0)
        }
        guard coords.count > 1 else { return "—" }
        var meters = 0.0
        for index in 1..<coords.count {
            meters += RouteInterpolator.haversineDistance(from: coords[index - 1], to: coords[index])
        }
        return meters < 1000 ? "\(Int(meters)) m" : String(format: "%.2f km", meters / 1000)
    }

    private var routeETA: String {
        let points = displayStops.map(\.coordinate)
        var coords = points
        if mode == .twospot, let start = appState.locationPresentation.appliedCoordinate, coords.first != start {
            coords.insert(start, at: 0)
        }
        guard coords.count > 1 else { return "00:00:00" }
        var meters = 0.0
        for index in 1..<coords.count {
            meters += RouteInterpolator.haversineDistance(from: coords[index - 1], to: coords[index])
        }
        return Self.hms(meters / max(appState.effectiveMetersPerSecond, 0.1))
    }

    private struct DisplayStop {
        let name: String
        let coordinate: LocationCoordinate
        let fromRoute: Bool
    }

    private var displayStops: [DisplayStop] {
        if mode == .twospot {
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
            if index == 0, appState.locationPresentation.appliedCoordinate != nil, displayStops.count > 1 {
                return
            }
            appState.clearRoute()
            if let current = appState.locationPresentation.appliedCoordinate { appState.stageLocation(current, for: mode) }
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
