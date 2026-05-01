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
                    .foregroundStyle(Color.blue)
                Text("PathChanger")
                    .font(AppFont.heading)
                Spacer()
            }
            .padding()
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

                    Divider()
                        .padding(.horizontal)

                    // Device Section
                    deviceSection
                }
                .padding()
            }

            Spacer()

            // Tunnel Status
            tunnelStatusBar

            // Footer / Version
            Text("v1.0.0 Pro")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .background(Color.appSurface.opacity(0.5))
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    Task { await appState.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
            }

            if appState.availableDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(.secondary)
                    Text("No devices found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    // MARK: - Tunnel Status Bar

    private var tunnelStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tunneldManager.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(tunneldManager.isRunning ? "Tunnel Active" : "Tunnel Inactive")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if !tunneldManager.isRunning {
                Button("Start") {
                    Task { await tunneldManager.startTunnel() }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.1))
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
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)

                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if !isSelected { return .gray }
        return isConnected ? .green : .yellow
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
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(AppFont.body)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text(mode.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .blue : .primary)
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
