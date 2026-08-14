//
//  OrganicSettingsSheet.swift
//  PathChanger
//
//  Settings overlay matching the pth mock.
//

import SwiftUI

struct OrganicSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @Binding var isPresented: Bool
    @Binding var mapStyle: MapStyleType

    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoReconnectDevice") private var autoReconnect: Bool = true
    @AppStorage("keepLocationCentered") private var keepCentered: Bool = true
    @AppStorage("addGPSDrift") private var addGPSDrift: Bool = false
    @AppStorage("smoothTurns") private var smoothTurns: Bool = true
    @AppStorage("cooldownReminder") private var cooldownReminder: Bool = true
    @AppStorage("unitsMetric") private var unitsMetric: Bool = true

    var body: some View {
        ZStack {
            Organic.neutral900.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(Organic.heading(25))
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Organic.neutral700)
                            .frame(width: 28, height: 28)
                            .background(Organic.neutral200)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preferred connection")
                                    .font(Organic.body(13, weight: .semibold))
                                HStack(spacing: 6) {
                                    ForEach(DeviceManager.ConnectionMode.allCases, id: \.self) { mode in
                                        Button(mode.rawValue) {
                                            appState.deviceManager.setConnectionMode(mode)
                                        }
                                        .buttonStyle(.plain)
                                        .font(Organic.body(11.5, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .frame(height: 28)
                                        .background(appState.deviceManager.connectionMode == mode ? Organic.neutral100 : Color.clear)
                                        .clipShape(Capsule())
                                    }
                                }
                                .padding(3)
                                .background(Organic.neutral300)
                                .clipShape(Capsule())
                            }
                            .padding(.vertical, 12)
                            Divider().foregroundStyle(Organic.neutral300)
                            toggleRow("Reconnect automatically", "Re-pair when the device is plugged back in", $autoReconnect)
                        }

                        section("Movement") {
                            segmentedRow("Units", left: "Metric", right: "Imperial", leftSelected: unitsMetric) { unitsMetric = $0 }
                            segmentedModes
                            toggleRow("Add GPS drift for realism", "Subtle natural jitter so movement looks human", $addGPSDrift)
                            toggleRow("Smooth turns", "Ease around corners instead of snapping", $smoothTurns)
                        }

                        section("Map") {
                            HStack {
                                Text("Basemap")
                                    .font(Organic.body(13, weight: .semibold))
                                Spacer()
                                HStack(spacing: 2) {
                                    ForEach(MapStyleType.allCases) { style in
                                        Button(style.rawValue) { mapStyle = style }
                                            .buttonStyle(.plain)
                                            .font(Organic.body(11.5, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .frame(height: 28)
                                            .background(mapStyle == style ? Organic.neutral100 : Color.clear)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(3)
                                .background(Organic.neutral300)
                                .clipShape(Capsule())
                            }
                            .padding(.vertical, 12)
                            toggleRow("Show coordinates overlay", nil, $showCoordinatesOnMap)
                            toggleRow("Keep location centered", "Pan the map to follow the pin while moving", $keepCentered)
                        }

                        section("Safety") {
                            toggleRow("Cooldown reminder", "iOS may rate-limit rapid jumps. We'll suggest a pause between teleports.", $cooldownReminder)
                        }

                        section("About") {
                            HStack(spacing: 13) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 19))
                                    .foregroundStyle(Organic.neutral100)
                                    .frame(width: 38, height: 38)
                                    .background(Organic.accent600)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PathChanger 1.0.0")
                                        .font(Organic.body(13.5, weight: .bold))
                                    Text("iOS 15–27 · keep the tunnel running")
                                        .font(Organic.body(11.5))
                                        .foregroundStyle(Organic.neutral600)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Organic.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                                    .stroke(Organic.neutral300, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
            .frame(width: 620, height: 620)
            .background(Organic.bg)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusLG, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusLG, style: .continuous)
                    .stroke(Organic.neutral400, lineWidth: 1)
            )
            .shadow(color: Organic.neutral900.opacity(0.22), radius: 32, y: 12)
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
                ForEach([SimulationSpeed.walking, .cycling, .driving, .fast], id: \.self) { speed in
                    Button(speed == .fast ? "Transit" : speed.displayName) {
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
}
