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
    @Binding var appearanceRaw: String
    let onRefresh: () -> Void
    @State private var transportTick = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0xE8695E)).frame(width: 11, height: 11)
                Circle().fill(Color(hex: 0xE0AC3C)).frame(width: 11, height: 11)
                Circle().fill(Color(hex: 0x5AAB52)).frame(width: 11, height: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                deviceCluster
                tunnelButton
            }

            HStack(spacing: 8) {
                safeModeButton
                Button {
                    appearanceRaw = appearance == .dark
                        ? OrganicAppearance.light.rawValue
                        : OrganicAppearance.dark.rawValue
                } label: {
                    OrganicGlyphView(glyph: appearance == .dark ? .sun : .moon, size: 15)
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 32, height: 32)
                        .background(Organic.neutral100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Organic.neutral400, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(appearance == .dark ? "Switch to light" : "Switch to dark")
                Button { showSettings.toggle() } label: {
                    OrganicGlyphView(glyph: .settings, size: 15)
                        .foregroundStyle(showSettings ? Organic.accent700 : Organic.neutral700)
                        .frame(width: 32, height: 32)
                        .background(showSettings ? Organic.accent100 : Organic.neutral100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(showSettings ? Organic.accent400 : Organic.neutral400, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 40)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Organic.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Organic.neutral400).frame(height: 1)
        }
    }

    private var appearance: OrganicAppearance {
        OrganicAppearance.persisted(appearanceRaw)
    }

    private var deviceCluster: some View {
        HStack(spacing: 9) {
            Button { showDeviceMenu.toggle() } label: {
                HStack(spacing: 9) {
                    OrganicGlyphView(glyph: .phone, size: 15)
                        .foregroundStyle(Organic.sage700)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.selectedDevice?.chromeTitle ?? "No device")
                            .font(Organic.body(12, weight: .bold))
                            .lineLimit(1)
                        Text(deviceSubtitle)
                            .font(Organic.body(10))
                            .foregroundStyle(Organic.neutral600)
                            .lineLimit(1)
                    }
                    Text("\(max(appState.availableDevices.count, appState.selectedDevice == nil ? 0 : 1))")
                        .font(Organic.mono(10, weight: .bold))
                        .foregroundStyle(Organic.neutral100)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Organic.sage600)
                        .clipShape(Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Organic.neutral500)
                        .rotationEffect(.degrees(showDeviceMenu ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDeviceMenu, arrowEdge: .bottom) {
                devicePopover
            }

            HStack(spacing: 2) {
                transportChip("USB-C", selected: transportIsUSB) {
                    appState.deviceManager.setConnectionMode(.usb)
                    transportTick += 1
                }
                transportChip("Wi-Fi", selected: !transportIsUSB) {
                    appState.deviceManager.setConnectionMode(.wifi)
                    transportTick += 1
                }
            }
            .padding(2)
            .background(Organic.neutral300)
            .clipShape(Capsule())
        }
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .frame(height: 34)
        .background(Organic.neutral100)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Organic.neutral400, lineWidth: 1))
    }

    private func transportChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Organic.body(10, weight: .bold))
                .foregroundStyle(selected ? Organic.accent800 : Organic.neutral700)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Organic.neutral100 : Color.clear)
                .clipShape(Capsule())
                .shadow(color: selected ? Organic.shadow.opacity(0.08) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var safeModeButton: some View {
        let on = appState.safeModeTeleport && appState.safeModeJoystick
        return Button {
            let next = !on
            appState.safeModeTeleport = next
            appState.safeModeJoystick = next
            appState.statusMessage = next
                ? "Safe Mode on — speed clamped, cooldown enforced"
                : "Safe Mode off — no speed ceiling, no jump guard"
        } label: {
            HStack(spacing: 5) {
                OrganicGlyphView(glyph: .shieldCheck, size: 15)
                Circle()
                    .fill(on ? Organic.sage600 : Organic.neutral500)
                    .frame(width: 7, height: 7)
            }
            .foregroundStyle(on ? Organic.sage800 : Organic.neutral700)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(on ? Organic.sage100 : Organic.neutral200)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Organic.sage300 : Organic.neutral400, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Safe Mode clamps speed, enforces cooldown and confirms absurd jumps")
    }

    private var tunnelButton: some View {
        Button {
            if tunneldManager.isRunning {
                tunneldManager.stopTunnel()
            } else if !tunneldManager.isStarting {
                Task { await appState.startSelectedTunnel() }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tunnelDot)
                    .frame(width: 7, height: 7)
                Text(tunnelLabel)
                    .font(Organic.body(12, weight: .bold))
            }
            .foregroundStyle(tunnelInk)
            .padding(.horizontal, 15)
            .frame(height: 32)
            .background(tunnelFill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tunnelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(connectionHelp)
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
                                Text(device.chromeTitle)
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
                Task { await appState.prepareSelectedDeviceForWiFi() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                    Text("Prepare Wi-Fi")
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
        .shadow(color: Organic.shadow.opacity(0.16), radius: 16, y: 8)
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

    private var deviceSubtitle: String {
        let link = transportIsUSB ? "USB-C" : "Wi-Fi"
        guard let device = appState.selectedDevice else {
            return "No iOS device · \(link)"
        }
        return "iOS \(device.iosVersion) · trusted · \(link)"
    }

    private var transportIsUSB: Bool {
        _ = transportTick
        switch appState.deviceManager.connectionMode {
        case .usb: return true
        case .wifi: return false
        default: return appState.isUSBConnected || !appState.isWiFiTransportAvailable
        }
    }

    private var tunnelLabel: String {
        if tunneldManager.isStarting { return "Connecting…" }
        if tunneldManager.isRunning { return "Tunnel live" }
        if case .error = tunneldManager.state { return "Tunnel error" }
        return "Start tunnel"
    }

    private var tunnelDot: Color {
        if tunneldManager.isStarting { return Organic.accent600 }
        if tunneldManager.isRunning { return Organic.sage600 }
        if case .error = tunneldManager.state { return Organic.accent600 }
        return Organic.neutral100.opacity(0.75)
    }

    private var tunnelInk: Color {
        if tunneldManager.isRunning { return Organic.sage800 }
        if tunneldManager.isStarting { return Organic.neutral700 }
        if case .error = tunneldManager.state { return Organic.accent800 }
        return Organic.neutral100
    }

    private var tunnelFill: Color {
        if tunneldManager.isRunning { return Organic.sage100 }
        if tunneldManager.isStarting { return Organic.neutral200 }
        if case .error = tunneldManager.state { return Organic.accent100 }
        return Organic.accent
    }

    private var tunnelStroke: Color {
        if tunneldManager.isRunning { return Organic.sage300 }
        if tunneldManager.isStarting { return Organic.neutral400 }
        if case .error = tunneldManager.state { return Organic.accent300 }
        return Color.clear
    }

    private var directTransportReady: Bool {
        appState.device.selectedDirectTransportAvailable
    }

    private var connectionHelp: String {
        if tunneldManager.isRunning { return "Stop RemoteXPC tunnel" }
        if case .error = tunneldManager.state { return "Retry RemoteXPC tunnel start" }
        if directTransportReady {
            return appState.selectedDevice?.isWireless == true
                ? "Direct Wi-Fi connection ready. Click to start RemoteXPC tunnel."
                : "Direct USB connection ready. Click to start RemoteXPC tunnel."
        }
        return "Start RemoteXPC tunnel"
    }
}

struct OrganicRail: View {
    @ObservedObject var favorites = LocationFavoritesManager.shared
    @Binding var openPanel: RailPanel?
    var mode: AppMode = .teleport
    let onSelect: (LocationCoordinate, String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                railButton(.favorites, icon: "star", label: "Favorites")
                railButton(.places, icon: "mappin.circle", label: "Places")
                railButton(.recent, icon: "clock", label: "Recent")
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.horizontal, 8)
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(Organic.surface)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Organic.neutral300).frame(width: 1)
            }

            if let panel = openPanel {
                flyout(for: panel)
                    .frame(width: 218, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 520, alignment: .top)
                    .padding(.leading, 84)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .frame(width: 76, alignment: .leading)
        .zIndex(40)
        .animation(.easeInOut(duration: 0.18), value: openPanel)
    }

    private func railButton(_ panel: RailPanel, icon: String, label: String) -> some View {
        let selected = openPanel == panel
        let ink: Color = (selected && panel == .recent) ? Organic.sage800 : (selected ? Organic.accent700 : Organic.neutral700)
        return Button {
            openPanel = selected ? nil : panel
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(Organic.body(10, weight: .bold))
            }
            .foregroundStyle(ink)
            .frame(width: 58)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .background(selected ? Organic.accent100 : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                    .stroke(selected ? Organic.accent400 : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func flyout(for panel: RailPanel) -> some View {
        let items: [FavoriteLocation] = {
            switch panel {
            case .favorites: return favorites.favorites
            case .places: return favorites.places
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
        let hint = mode == .route ? "Tap to add a stop" : "Tap to set location"

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
                .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

            VStack(spacing: 1) {
                if items.isEmpty && panel == .favorites {
                    Text("No favorites yet. Star a place, or use the star on the map.")
                        .font(Organic.body(11))
                        .foregroundStyle(Organic.neutral600)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 16)
                } else if !items.isEmpty {
                    ScrollView {
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
                                            .foregroundStyle(favorites.isFavorite(item.coordinate) ? Organic.accent600 : Organic.neutral500)
                                            .frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Favorite")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
                Text(hint)
                    .font(Organic.body(9.5))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 3)
            }
            .padding(5)
        }
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.16), radius: 16, y: 8)
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
                Text(appState.isSimulating ? appState.simulationStatusText : "Standby")
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
        // Reads the same accessor as InspectorPanel and ModeContextCard. Previously this used
        // the raw `simulationSpeed.metersPerSecond`, so the telemetry bar showed 1.4 m/s while
        // the other panels showed 1.6 m/s for the same Walking preset.
        String(format: "%.1f m/s", appState.isSimulating && !appState.isPaused ? appState.effectiveMetersPerSecond : 0)
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
