//
//  DeviceListView.swift
//  PathChanger
//
//  Modern Pro UI - Device management list
//

import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected Devices")
                .font(AppFont.heading)
                .padding(.horizontal)

            if appState.availableDevices.isEmpty {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "iphone.slash",
                    description: Text("Connect your iOS device via USB")
                )
                .frame(height: 200)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.availableDevices) { device in
                            DeviceCard(
                                device: device,
                                isSelected: appState.selectedDevice?.id == device.id,
                                isConnected: appState.connectionStatus == .connected
                            ) {
                                appState.selectDevice(device)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Refresh Button
            Button {
                Task { await appState.refreshDevices() }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Device List")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct DeviceCard: View {
    let device: Device
    let isSelected: Bool
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(isSelected ? .blue : .secondary)

                    // Newer iOS compatibility warning badge
                    if device.hasLocationCompatibilityWarning {
                        Circle()
                            .fill(.orange)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Image(systemName: "exclamationmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 16, y: -16)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(AppFont.body)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 6, height: 6)

                        Text(connectionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // iOS version badge (only show if version is known)
                    if device.iosVersion != "Unknown" {
                        HStack(spacing: 4) {
                            if device.hasLocationCompatibilityWarning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text("iOS \(device.iosVersion)")
                                .font(.caption2)
                                .foregroundColor(device.hasLocationCompatibilityWarning ? .orange : .secondary)
                        }
                    }
                }

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var connectionColor: Color {
        if !isSelected { return .gray }
        return isConnected ? .green : .yellow
    }

    private var connectionText: String {
        if !isSelected { return "Tap to select" }
        return isConnected ? "Connected" : "Connecting..."
    }
}

#if DEBUG
struct DeviceListView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceListView()
            .environmentObject(AppState())
            .environmentObject(TunneldManager.shared)
            .frame(width: 300)
    }
}
#endif
