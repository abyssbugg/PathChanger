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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.pcTextMuted)
                Text("PathChanger")
                    .font(AppFont.title)
                    .foregroundStyle(Color.pcText)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Mode Selection
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(AppMode.allCases) { mode in
                            SidebarButton(mode: mode, isSelected: selectedMode == mode) {
                                selectedMode = mode
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.modeSelector)
                    .accessibilityLabel("Simulation mode selector")

                    Divider()
                        .overlay(Color.pcOutline)
                        .padding(.horizontal, AppSpacing.sm)

                    // Device Section
                    deviceSection

                    Divider()
                        .overlay(Color.pcOutline)
                        .padding(.horizontal, AppSpacing.sm)

                    // Location History
                    locationHistorySection
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }

            Spacer()

            // Tunnel Status
            tunnelStatusBar

            // Footer / Version
            Text("v1.0.0 Pro")
                .font(AppFont.metadata)
                .foregroundStyle(Color.pcTextMuted)
                .padding(.bottom, AppSpacing.md)
        }
        .background(Color.pcBackground)
        .accessibleSection(
            label: AccessibilityLabels.Navigation.sidebar,
            identifier: AccessibilityIdentifiers.Navigation.sidebar
        )
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text("Devices")
                    .appSectionLabel()

                Spacer()

                Button {
                    Task { await appState.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .buttonStyle(.plain)
                .appHoverOverlay(cornerRadius: AppRadius.sm)
                .help("Refresh device list")
                .accessibleButton(
                    label: AccessibilityLabels.Actions.refreshDevices,
                    hint: AccessibilityHints.refreshDevices,
                    identifier: AccessibilityIdentifiers.Devices.refreshButton
                )
            }

            if appState.availableDevices.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(Color.pcTextMuted)
                    Text("No devices found")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
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
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text("Location History")
                    .appSectionLabel()

                Spacer()

                if !appState.locationHistory.isEmpty {
                    Button("Clear") {
                        appState.clearLocationHistory()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .accessibleButton(
                        label: "Clear location history",
                        hint: "Removes all saved recent locations",
                        identifier: AccessibilityIdentifiers.History.clearButton
                    )
                }
            }

            if appState.locationHistory.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.pcTextMuted)
                    Text("Successful locations appear here")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppSpacing.sm)
            } else {
                VStack(spacing: AppSpacing.sm) {
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "mappin.and.ellipse")
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(entry.displayName)
                        .font(AppFont.label)
                        .foregroundStyle(Color.pcText)
                        .lineLimit(1)

                    Text(entry.coordinate.formattedShort)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(Color.pcTextMuted)

                    Text("\(entry.source) • \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted.opacity(0.78))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    appState.removeHistoryEntry(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(AppFont.metadata)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.pcTextMuted)
                .accessibilityLabel("Remove recent location \(entry.displayName)")
            }

            HStack(spacing: AppSpacing.sm) {
                Button("Select") {
                    appState.selectHistoryEntry(entry)
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                .accessibilityLabel("Select recent location \(entry.displayName)")
                .accessibilityHint("Sets this history entry as the target location without applying it")

                Button("Apply") {
                    Task {
                        appState.selectHistoryEntry(entry)
                        await appState.setLocation(entry.coordinate, source: "History", name: entry.displayName)
                    }
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
                .disabled(!appState.canStartSimulation)
                .accessibilityLabel("Apply recent location \(entry.displayName)")
            }
        }
        .padding(AppSpacing.sm)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent location \(entry.displayName), \(entry.coordinate.formattedShort)")
        .accessibilityIdentifier(AccessibilityIdentifiers.History.historyRow)
    }

    // MARK: - Tunnel Status Bar

    private var tunnelStatusBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(tunneldManager.isRunning ? Color.pcSecondary : Color.pcDanger)
                .frame(width: 6, height: 6)

            Text(tunneldManager.isRunning ? "Tunnel ready" : "Tunnel offline")
                .font(AppFont.metadata)
                .foregroundStyle(Color.pcTextMuted)

            Spacer()

            if !tunneldManager.isRunning {
                Button {
                    // W1 S2-A deprecation marker:
                    // SidebarView is not instantiated in production layouts.
                    // It remains a W4-deferred compatibility shim.
                    // This harmonization is convergence-only.
                    // No authority expansion is intended.
                    Task { await tunneldManager.autoStart() }
                } label: {
                    Text("Start")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
                .frame(minWidth: 56)
                .accessibleButton(
                    label: "Start device tunnel",
                    hint: "Starts the tunnel required for location simulation",
                    identifier: "startTunnelButton"
                )
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: 0.1, shadowOpacity: 0.08)
        .padding(.horizontal, AppSpacing.xl)
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
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "iphone")
                    .font(AppFont.body)
                    .foregroundStyle(Color.pcTextMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(device.displayName)
                        .font(isSelected ? AppFont.label : AppFont.body)
                        .foregroundStyle(Color.pcText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)

                        Text(statusText)
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcTextMuted)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isSelected ? Color.pcAccent.opacity(AppSurfaceAlpha.idleRow) : Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.idleRow))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(isSelected ? Color.pcAccent.opacity(AppSurfaceAlpha.hoverRow) : Color.pcOutline.opacity(AppSurfaceAlpha.divider), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appHoverOverlay(cornerRadius: AppRadius.md)
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
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: mode.icon)
                    .font(AppFont.body)
                    .foregroundStyle(Color.pcTextMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(mode.rawValue)
                        .font(isSelected ? AppFont.label : AppFont.body)
                        .foregroundStyle(Color.pcText)

                    Text(mode.description)
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(isSelected ? Color.pcAccent.opacity(AppSurfaceAlpha.idleRow) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(isSelected ? Color.pcAccent.opacity(AppSurfaceAlpha.hoverRow) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appHoverOverlay(cornerRadius: AppRadius.lg)
        .foregroundStyle(Color.pcText)
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
