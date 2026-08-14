//
//  OrganicChrome.swift
//  PathChanger
//
//  Title bar, favorites rail, and telemetry strip from the pth mock.
//

import SwiftUI

enum RailPanel: String {
    case favorites
    case places
    case recent
}

struct OrganicTitleBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @Binding var showDeviceMenu: Bool
    @Binding var showSettings: Bool
    let onToggleMapStyle: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 68, height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("PathChanger")
                    .font(Organic.heading(15))
                    .foregroundStyle(Organic.text)
                Text("1.0.0")
                    .font(Organic.mono(11))
                    .foregroundStyle(Organic.neutral600)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                connectionPill
                deviceMenu
                chromeIconButton(system: "arrow.clockwise", title: "Re-establish tunnel", action: onRefresh)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onToggleMapStyle) {
                    Image(systemName: "map")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Basemap")

                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Organic.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Organic.neutral300).frame(height: 1)
        }
    }

    private var connectionPill: some View {
        Button {
            cycleConnectionMode()
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(connectionDot)
                    .frame(width: 8, height: 8)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(connectionTitle)
                        .font(Organic.body(12, weight: .semibold))
                    Text(connectionSubtitle)
                        .font(Organic.body(10.5))
                        .foregroundStyle(Organic.neutral600)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(Organic.neutral100)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deviceMenu: some View {
        Button {
            showDeviceMenu.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(appState.selectedDevice?.displayName ?? "No device")
                    .font(Organic.body(12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Organic.neutral600)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Organic.neutral100)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDeviceMenu, arrowEdge: .bottom) {
            devicePopover
        }
    }

    private var devicePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PAIRED DEVICES")
                    .font(Organic.body(11, weight: .bold))
                    .foregroundStyle(Organic.neutral600)
                    .tracking(0.8)
                Spacer()
                Text("\(appState.availableDevices.count)")
                    .font(Organic.mono(10.5, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Organic.neutral200)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

            VStack(spacing: 2) {
                if appState.availableDevices.isEmpty {
                    Text("No devices yet")
                        .font(Organic.body(11.5))
                        .foregroundStyle(Organic.neutral600)
                        .padding(12)
                }
                ForEach(appState.availableDevices) { device in
                    Button {
                        appState.selectDevice(device)
                        showDeviceMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: device.isWireless ? "wifi" : "cable.connector")
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(Organic.body(12.5, weight: .semibold))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("iOS \(device.iosVersion)")
                                        .font(Organic.body(10.5))
                                        .foregroundStyle(Organic.neutral600)
                                    Text(device.isWireless ? "Wi-Fi" : "USB")
                                        .font(Organic.body(10.5, weight: .semibold))
                                        .foregroundStyle(Organic.accent700)
                                }
                            }
                            Spacer()
                            if appState.selectedDevice?.id == device.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Organic.accent600)
                            }
                        }
                        .foregroundStyle(Organic.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)

            Button {
                Task { await appState.refreshDevices() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                    Text("Pair a new device")
                        .font(Organic.body(12, weight: .bold))
                }
                .foregroundStyle(Organic.accent700)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(Organic.neutral300).frame(height: 1) }
        }
        .frame(width: 260)
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.neutral900.opacity(0.16), radius: 16, y: 8)
    }

    private func chromeIconButton(system: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .frame(width: 28, height: 28)
                .background(Organic.neutral100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Organic.neutral400, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var connectionTitle: String {
        if !tunneldManager.isRunning { return "Tunnel off" }
        if appState.isUSBConnected { return "USB active" }
        if appState.isWiFiTransportAvailable { return "Wi-Fi active" }
        return "Connecting"
    }

    private var connectionSubtitle: String {
        appState.deviceManager.connectionMode.rawValue
    }

    private var connectionDot: Color {
        if tunneldManager.isStarting { return Organic.accent400 }
        if tunneldManager.isRunning { return Organic.sage600 }
        return Organic.neutral500
    }

    private func cycleConnectionMode() {
        let modes = DeviceManager.ConnectionMode.allCases
        let current = appState.deviceManager.connectionMode
        let next = modes[((modes.firstIndex(of: current) ?? 0) + 1) % modes.count]
        appState.deviceManager.setConnectionMode(next)
    }
}

struct OrganicRail: View {
    @ObservedObject var favorites = LocationFavoritesManager.shared
    @Binding var openPanel: RailPanel?
    let onSelect: (LocationCoordinate, String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                railButton(.favorites, icon: "star", label: "Favorites")
                railButton(.places, icon: "mappin", label: "Places")
                railButton(.recent, icon: "clock", label: "Recent")
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(width: 76)
            .background(Organic.surface)

            if let panel = openPanel {
                flyout(for: panel)
                    .frame(width: 220)
                    .padding(10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Organic.neutral300).frame(width: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: openPanel)
    }

    private func railButton(_ panel: RailPanel, icon: String, label: String) -> some View {
        let selected = openPanel == panel
        return Button {
            openPanel = selected ? nil : panel
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(Organic.body(10, weight: .bold))
            }
            .foregroundStyle(selected ? Organic.accent700 : Organic.neutral700)
            .frame(width: 60, height: 54)
            .background(selected ? Organic.accent100 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func flyout(for panel: RailPanel) -> some View {
        let items: [FavoriteLocation] = {
            switch panel {
            case .favorites, .places: return favorites.favorites
            case .recent: return favorites.recents
            }
        }()
        let title: String = {
            switch panel {
            case .favorites: return "Favorites"
            case .places: return "Places"
            case .recent: return "Recent"
            }
        }()

        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Organic.body(12, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Button { openPanel = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 20, height: 20)
                        .background(Organic.neutral200)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

            ScrollView {
                if items.isEmpty {
                    Text(panel == .recent ? "No recent places yet." : "No favorites yet. Star a place, or use the star on the map.")
                        .font(Organic.body(11))
                        .foregroundStyle(Organic.neutral600)
                        .multilineTextAlignment(.center)
                        .padding(16)
                } else {
                    VStack(spacing: 1) {
                        ForEach(items) { item in
                            HStack(spacing: 2) {
                                Button {
                                    onSelect(item.coordinate, item.name)
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                            .font(Organic.body(11.5, weight: .semibold))
                                            .lineLimit(1)
                                        Text(item.coordinate.formattedShort)
                                            .font(Organic.mono(9.5))
                                            .foregroundStyle(Organic.neutral600)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 8)
                                    .padding(.vertical, 7)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    favorites.toggleFavorite(name: item.name, coordinate: item.coordinate)
                                } label: {
                                    Image(systemName: favorites.isFavorite(item.coordinate) ? "star.fill" : "star")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Organic.accent600)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(5)
                }
            }
        }
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.neutral900.opacity(0.16), radius: 16, y: 8)
    }
}

struct OrganicTelemetryBar: View {
    @EnvironmentObject var appState: AppState
    let mode: AppMode

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isSimulating ? Organic.sage600 : Organic.neutral500)
                    .frame(width: 8, height: 8)
                Text(appState.simulationStatusText)
                    .font(Organic.body(12.5, weight: .bold))
                    .lineLimit(1)
                Text((appState.currentLocation ?? appState.targetLocation)?.formattedShort ?? "—")
                    .font(Organic.mono(11.5))
                    .foregroundStyle(Organic.neutral700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Organic.neutral200)
                    .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
                    .clipShape(Capsule())
                Text(mode.rawValue)
                    .font(Organic.body(11, weight: .bold))
                    .foregroundStyle(Organic.accent800)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Organic.accent200)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 8)
            metric("ACCURACY", "5.0 m")
            metric("ALTITUDE", "12.4 m")
            metric("SPEED", speedText)
            Button {
                Task { await appState.stopSimulation() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stop")
                        .font(Organic.body(12, weight: .bold))
                }
                .foregroundStyle(appState.isSimulating ? Organic.neutral100 : Organic.neutral700)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(appState.isSimulating ? Organic.accent600 : Organic.neutral200)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isSimulating)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Organic.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Organic.neutral300).frame(height: 1)
        }
    }

    private var speedText: String {
        String(format: "%.1f m/s", appState.isSimulating && !appState.isPaused ? appState.simulationSpeed.metersPerSecond : 0)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Organic.body(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
            Text(value)
                .font(Organic.mono(12, weight: .semibold))
        }
    }
}
