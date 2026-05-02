//
//  SidebarView.swift
//  PathChanger
//
//  Modern Pro UI - Navigation Sidebar
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedMode: AppMode?
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "location.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.pcPrimary)
                Text("PathChanger")
                    .font(AppFont.heading)
                    .foregroundStyle(Color.pcText)
                Spacer()
            }
            .padding(AppSpacing.lg)
            .background(Color.pcSurface.opacity(0.35), in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 16) {
                    // Mode Selection
                    VStack(spacing: 8) {
                        ForEach(AppMode.allCases) { mode in
                            SidebarButton(mode: mode, isSelected: selectedMode == mode) {
                                selectedMode = mode
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.modeSelector)
                    .accessibilityLabel("Simulation mode selector")

                    Divider()
                        .padding(.horizontal)

                    // Device Section
                    deviceSection

                    Divider()
                        .padding(.horizontal)

                    // Location History
                    locationHistorySection
                }
                .padding()
            }

            Spacer()

            // Tunnel Status
            tunnelStatusBar

            // Footer / Version
            Text("v1.0.0 Pro")
                .font(AppFont.caption)
                .foregroundStyle(Color.pcTextMuted)
                .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [Color.pcBackground, Color.pcSurface.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .accessibleSection(
            label: AccessibilityLabels.Navigation.sidebar,
            identifier: AccessibilityIdentifiers.Navigation.sidebar
        )
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .appSectionLabel()

                Spacer()

                Button {
                    Task { await appState.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
                .accessibleButton(
                    label: AccessibilityLabels.Actions.refreshDevices,
                    hint: AccessibilityHints.refreshDevices,
                    identifier: AccessibilityIdentifiers.Devices.refreshButton
                )
            }

            if appState.availableDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(Color.pcTextMuted)
                    Text("No devices found")
                        .font(.caption)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(appState.availableDevices) { device in
                    SidebarDeviceRow(
                        device: device,
                        isSelected: appState.selectedDevice?.id == device.id,
                        isConnected: tunneldManager.isRunning
                    ) {
                        appState.selectDevice(device)
                    }
                }
            }
        }
        .accessibleSection(
            label: AccessibilityLabels.Navigation.deviceSection,
            identifier: AccessibilityIdentifiers.Navigation.deviceList
        )
    }

    // MARK: - Location History

    private var locationHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location History")
                    .appSectionLabel()

                Spacer()

                if !appState.locationHistory.isEmpty {
                    Button("Clear") {
                        appState.clearLocationHistory()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.pcTextMuted)
                    .accessibleButton(
                        label: "Clear location history",
                        hint: "Removes all saved recent locations",
                        identifier: AccessibilityIdentifiers.History.clearButton
                    )
                }
            }

            if appState.locationHistory.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.pcTextMuted)
                    Text("Successful locations appear here")
                        .font(.caption)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.locationHistory.prefix(6)) { entry in
                        locationHistoryRow(entry)
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.History.historyList)
                .accessibilityLabel("Recent location history")
            }
        }
        .accessibleSection(
            label: "Location history",
            identifier: AccessibilityIdentifiers.History.historyList
        )
    }

    private func locationHistoryRow(_ entry: LocationHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(Color.pcPrimary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.pcText)
                        .lineLimit(1)

                    Text(entry.coordinate.formattedShort)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.pcTextMuted)

                    Text("\(entry.source) • \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Color.pcTextMuted.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    appState.removeHistoryEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.pcTextMuted)
                .accessibilityLabel("Remove recent location \(entry.displayName)")
            }

            HStack(spacing: 8) {
                Button("Select") {
                    appState.selectHistoryEntry(entry)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("Select recent location \(entry.displayName)")
                .accessibilityHint("Sets this history entry as the target location without applying it")

                Button("Apply") {
                    Task {
                        appState.selectHistoryEntry(entry)
                        await appState.setLocation(entry.coordinate, source: "History", name: entry.displayName)
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(!appState.canStartSimulation)
                .accessibilityLabel("Apply recent location \(entry.displayName)")
            }
        }
        .padding(10)
        .background(Color.pcSurfaceHigh.opacity(0.45), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent location \(entry.displayName), \(entry.coordinate.formattedShort)")
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyRow)
    }

    // MARK: - Tunnel Status Bar

    private var tunnelStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tunneldManager.isRunning ? Color.pcSecondary : Color.pcDanger)
                .frame(width: 8, height: 8)

            Text(tunneldManager.isRunning ? "Tunnel Active" : "Tunnel Inactive")
                .font(.caption2)
                .foregroundStyle(Color.pcTextMuted)

            Spacer()

            if !tunneldManager.isRunning {
                Button("Start") {
                    Task { await tunneldManager.startTunnel() }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibleButton(
                    label: "Start device tunnel",
                    hint: "Starts the tunnel required for location simulation",
                    identifier: "startTunnelButton"
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: 0.1, shadowOpacity: 0.08)
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.xs)
        .accessibleStatus(
            label: tunneldManager.isRunning ? AccessibilityLabels.Status.tunnelConnected(mode: "selected connection") : AccessibilityLabels.Status.tunnelDisconnected,
            value: tunneldManager.isRunning ? "Active" : "Inactive",
            identifier: AccessibilityIdentifiers.Status.tunnelStatus
        )
    }
}

// MARK: - Sidebar Device Row

struct SidebarDeviceRow: View {
    let device: Device
    let isSelected: Bool
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.pcPrimary : Color.pcTextMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(Color.pcText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)

                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(Color.pcTextMuted)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.pcSecondary)
                }
            }
            .padding(AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isSelected ? Color.pcAccent.opacity(0.12) : Color.pcSurfaceHigh.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isSelected ? Color.pcAccent.opacity(0.32) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.displayName), \(statusText)")
        .accessibilityHint(AccessibilityHints.deviceRow)
        .accessibilityIdentifier(AccessibilityIdentifiers.Devices.deviceRow)
    }

    private var statusColor: Color {
        if !isSelected { return .pcTextMuted }
        return isConnected ? .pcSecondary : .pcWarning
    }

    private var statusText: String {
        if !isSelected { return "Tap to select" }
        return isConnected ? "Connected" : "Connecting..."
    }
}

struct SidebarButton: View {
    let mode: AppMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.pcPrimary : Color.pcTextMuted)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(AppFont.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.pcText : Color.pcText.opacity(0.9))

                    Text(mode.description)
                        .font(.caption2)
                        .foregroundStyle(Color.pcTextMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.pcPrimary)
                }
            }
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(isSelected ? Color.pcAccent.opacity(0.16) : Color.pcSurfaceHigh.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.pcPrimary.opacity(0.32) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.pcPrimary : Color.pcText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.rawValue), \(mode.description)")
        .accessibilityHint("Selects \(mode.rawValue) mode")
    }
}

#if DEBUG
struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView(selectedMode: .constant(.teleport))
            .environmentObject(AppState())
            .environmentObject(TunneldManager.shared)
            .frame(width: 280)
    }
}
#endif
