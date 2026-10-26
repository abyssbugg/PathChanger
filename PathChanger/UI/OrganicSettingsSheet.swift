//
//  OrganicSettingsSheet.swift
//  PathChanger
//
//  Settings overlay matching the pth mock.
//

import SwiftUI

struct OrganicSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var appearanceRaw: String

    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoReconnectDevice") private var autoReconnect: Bool = true
    @AppStorage("keepLocationCentered") private var keepCentered: Bool = true
    @AppStorage("unitsMetric") private var unitsMetric: Bool = true
    @AppStorage("showStreetLabels") private var showStreetLabels: Bool = true

    var body: some View {
        ZStack(alignment: .trailing) {
            Organic.shadow.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(Organic.heading(20))
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Organic.neutral600)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("Appearance") {
                            HStack(spacing: 2) {
                                ForEach(OrganicAppearance.allCases) { appearance in
                                    Button {
                                        appearanceRaw = appearance.rawValue
                                    } label: {
                                        HStack(spacing: 7) {
                                            OrganicGlyphView(glyph: appearance == .light ? .sun : .moon, size: 14)
                                            Text(appearance == .light ? "Light" : "Dark")
                                        }
                                        .font(Organic.body(11.5, weight: .bold))
                                        .foregroundStyle(
                                            selectedAppearance == appearance
                                                ? Organic.accent800
                                                : Organic.neutral700
                                        )
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(
                                            selectedAppearance == appearance
                                                ? Organic.neutral100
                                                : Color.clear
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(3)
                            .background(Organic.neutral300)
                            .clipShape(Capsule())
                            .padding(.vertical, 12)
                        }

                        section("Connection") {
                            row("Paired device", appState.selectedDevice.map { "\($0.displayName) · iOS \($0.iosVersion)" } ?? "None") {
                                Button("Forget") { appState.selectedDevice = nil }
                                    .buttonStyle(.plain)
                                    .font(Organic.body(12, weight: .bold))
                                    .foregroundStyle(Organic.accent700)
                                    .padding(.horizontal, 14)
                                    .frame(height: 30)
                                    .overlay(Capsule().stroke(Organic.accent400, lineWidth: 1))
                            }
                            Divider().foregroundStyle(Organic.neutral300)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Update frequency")
                                        .font(Organic.body(13, weight: .semibold))
                                    Text("How often location is pushed to the device")
                                        .font(Organic.body(11.5))
                                        .foregroundStyle(Organic.neutral600)
                                }
                                Spacer()
                                segmentedPicker(
                                    options: [("1 Hz", 1.0), ("5 Hz", 5.0), ("10 Hz", 10.0)],
                                    selection: appState.updateFrequencyHz,
                                    action: { appState.updateFrequencyHz = $0 }
                                )
                            }
                            .padding(.vertical, 12)
                            Divider().foregroundStyle(Organic.neutral300)
                            toggleRow("Reconnect automatically", "Re-handshake when the device or transport switches", $autoReconnect)
                        }

                        section("Connection safety") {
                            Text("Location changes become active only after the device acknowledges them.")
                                .font(Organic.body(12))
                                .foregroundStyle(Organic.neutral600)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }

                        section("Movement") {
                            segmentedRow("Units", left: "km", right: "mi", leftSelected: unitsMetric) { unitsMetric = $0 }
                            segmentedModes
                            toggleRow("Smooth turns", "Ease around corners instead of snapping", Binding(
                                get: { appState.smoothTurns },
                                set: { appState.smoothTurns = $0 }
                            ))
                        }

                        section("Map") {
                            HStack {
                                Text("Basemap")
                                    .font(Organic.body(13, weight: .semibold))
                                Spacer()
                                segmentedRowButtons(
                                    left: "Day",
                                    right: "Night",
                                    leftSelected: selectedAppearance == .light,
                                    onPick: {
                                        appearanceRaw = $0
                                            ? OrganicAppearance.light.rawValue
                                            : OrganicAppearance.dark.rawValue
                                    }
                                )
                            }
                            .padding(.vertical, 12)
                            toggleRow("Street labels", "Draw road names over the basemap", $showStreetLabels)
                            toggleRow("Show coordinates overlay", nil, $showCoordinatesOnMap)
                            toggleRow("Keep location centred", "Pan the map to follow the pin while moving", $keepCentered)
                        }

                        section("Saved Data") {
                            savedDataRow(
                                "Built-in places",
                                detail: "\(LocationFavoritesManager.shared.places.count) shown",
                                actionLabel: "Restore",
                                action: LocationFavoritesManager.shared.restoreBuiltInPlaces
                            )
                            Divider().foregroundStyle(Organic.neutral300)
                            savedDataRow(
                                "Location history",
                                detail: historyDetail,
                                actionLabel: "Clear",
                                action: LocationFavoritesManager.shared.clearRecents
                            )
                            Divider().foregroundStyle(Organic.neutral300)
                            savedDataRow(
                                "Favorites",
                                detail: "\(LocationFavoritesManager.shared.favorites.count) saved points",
                                actionLabel: "Clear",
                                action: LocationFavoritesManager.shared.clearFavorites
                            )
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 432)
            .frame(maxHeight: .infinity)
            .background(Organic.neutral100)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                    .stroke(Organic.neutral300, lineWidth: 1)
            )
            .shadow(color: Organic.shadow.opacity(0.55), radius: 32, x: -10)
            .padding(14)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Organic.body(10.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(Organic.accent700)
                .padding(.top, 22)
                .padding(.bottom, 10)
            content()
        }
    }

    private func row(_ title: String, _ subtitle: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Organic.body(13, weight: .semibold))
                Text(subtitle).font(Organic.body(11.5)).foregroundStyle(Organic.neutral600)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 12)
    }

    private func toggleRow(_ title: String, _ subtitle: String?, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Organic.body(13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(Organic.body(11.5)).foregroundStyle(Organic.neutral600)
                }
            }
            Spacer()
            Toggle("", isOn: value).labelsHidden().tint(Organic.accent600)
        }
        .padding(.vertical, 12)
    }

    private func savedDataRow(
        _ title: String,
        detail: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Organic.body(13, weight: .semibold))
                Text(detail)
                    .font(Organic.body(11.5))
                    .foregroundStyle(Organic.neutral600)
            }
            Spacer()
            Button(actionLabel, action: action)
                .buttonStyle(.plain)
                .font(Organic.body(11.5, weight: .bold))
                .foregroundStyle(Organic.accent700)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .overlay(Capsule().stroke(Organic.accent400, lineWidth: 1))
        }
        .padding(.vertical, 12)
    }

    private func segmentedPicker(
        options: [(String, Double)],
        selection: Double,
        action: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button(option.0) { action(option.1) }
                    .buttonStyle(.plain)
                    .font(Organic.body(11, weight: .bold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(selection == option.1 ? Organic.neutral100 : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(3)
        .background(Organic.neutral300)
        .clipShape(Capsule())
    }

    private func segmentedRowButtons(
        left: String,
        right: String,
        leftSelected: Bool,
        onPick: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button(left) { onPick(true) }
                .buttonStyle(.plain)
                .font(Organic.body(11.5, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(leftSelected ? Organic.neutral100 : Color.clear)
                .clipShape(Capsule())
            Button(right) { onPick(false) }
                .buttonStyle(.plain)
                .font(Organic.body(11.5, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(!leftSelected ? Organic.neutral100 : Color.clear)
                .clipShape(Capsule())
        }
        .padding(3)
        .background(Organic.neutral300)
        .clipShape(Capsule())
    }

    private func segmentedRow(_ title: String, left: String, right: String, leftSelected: Bool, onPick: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(Organic.body(13, weight: .semibold))
            Spacer()
            HStack(spacing: 2) {
                Button(left) { onPick(true) }
                    .buttonStyle(.plain)
                    .font(Organic.body(11.5, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(leftSelected ? Organic.neutral100 : Color.clear)
                    .clipShape(Capsule())
                Button(right) { onPick(false) }
                    .buttonStyle(.plain)
                    .font(Organic.body(11.5, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(!leftSelected ? Organic.neutral100 : Color.clear)
                    .clipShape(Capsule())
            }
            .padding(3)
            .background(Organic.neutral300)
            .clipShape(Capsule())
        }
        .padding(.vertical, 12)
    }

    private var segmentedModes: some View {
        HStack {
            Text("Default travel mode")
                .font(Organic.body(13, weight: .semibold))
            Spacer()
            HStack(spacing: 2) {
                ForEach([SimulationSpeed.walking, .running, .cycling, .driving], id: \.self) { speed in
                    Button(settingsTravelLabel(speed)) {
                        appState.setSpeed(speed)
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(11, weight: .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(appState.simulationSpeed == speed ? Organic.neutral100 : Color.clear)
                    .clipShape(Capsule())
                }
            }
            .padding(3)
            .background(Organic.neutral300)
            .clipShape(Capsule())
        }
        .padding(.vertical, 12)
    }

    private var selectedAppearance: OrganicAppearance {
        OrganicAppearance.persisted(appearanceRaw)
    }

    private var historyDetail: String {
        let count = LocationFavoritesManager.shared.recents.count
        return "\(count) \(count == 1 ? "entry" : "entries") · newest 14 kept"
    }

    private func settingsTravelLabel(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "Walk"
        case .running: return "Run"
        case .cycling: return "Cycle"
        case .driving: return "Drive"
        default: return speed.displayName
        }
    }
}
