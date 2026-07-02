//
//  CompanionApp.swift
//  PathChangerCompanion
//
//  iPhone Companion App for PathChanger
//  Shows status and provides emergency stop functionality
//

import SwiftUI
import SharedCompanionProtocol

@main
struct PathChangerCompanionApp: App {
    @StateObject private var connectionService = CompanionConnectionService()
    var body: some Scene {
        WindowGroup {
            CompanionContentView()
                .environmentObject(connectionService)
        }
    }
}

// MARK: - Main Content View

struct CompanionContentView: View {
    @EnvironmentObject var connectionService: CompanionConnectionService
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Connection status
                ConnectionStatusView()
                Divider()
                // Spoofing status
                if let status = connectionService.status {
                    SpoofingStatusView(status: status)
                } else {
                    WaitingView()
                }
                Spacer()
                // Emergency stop button
                EmergencyStopButton()
                    .disabled(!connectionService.isConnected)
            }
            .padding()
            .navigationTitle("PathChanger")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if connectionService.isPeerDiscoveryActive {
                            connectionService.stop()
                        } else {
                            connectionService.start()
                        }
                    } label: {
                        Image(systemName: peerDiscoveryIconName)
                    }
                }
            }
            .onAppear {
                connectionService.start()
            }
        }
    }

    private var peerDiscoveryIconName: String {
        connectionService.isPeerDiscoveryActive
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
    }
}

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    @EnvironmentObject var connectionService: CompanionConnectionService

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(connectionService.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(connectionService.isConnected ? "Connected" : "Disconnected")
                    .font(.headline)
            }

            if let peerName = connectionService.connectedPeerName {
                Text("Connected to \(peerName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if connectionService.isPeerDiscoveryActive {
                Text("Searching for Mac...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Discovered peers
            if !connectionService.discoveredPeers.isEmpty && !connectionService.isConnected {
                VStack {
                    Text("Available:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(connectionService.discoveredPeers, id: \.displayName) { peer in
                        Button(peer.displayName) {
                            connectionService.connectToPeer(peer)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Spoofing Status View

struct SpoofingStatusView: View {
    let status: SpoofingStatus

    var body: some View {
        VStack(spacing: 16) {
            // Active status
            HStack {
                Image(systemName: status.isActive ? "location.fill" : "location.slash")
                    .foregroundColor(status.isActive ? .blue : .gray)
                    .font(.largeTitle)

                VStack(alignment: .leading) {
                    Text(status.isActive ? (status.isPaused ? "Paused" : "Active") : "Inactive")
                        .font(.headline)

                    if let device = status.deviceName {
                        Text(device)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Current location
            if let lat = status.currentLatitude, let lon = status.currentLongitude {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Location")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.6f, %.6f", lat, lon))
                        .font(.system(.body, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Mode and speed
            HStack {
                Label(status.mode, systemImage: modeIcon(status.mode))
                Spacer()
                Label(status.speed, systemImage: "speedometer")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            // Route progress
            if let progress = status.routeProgress, progress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func modeIcon(_ mode: String) -> String {
        switch mode.lowercased() {
        case "teleport": return "location.fill"
        case "route": return "map.fill"
        case "joystick": return "gamecontroller.fill"
        default: return "location"
        }
    }
}

// MARK: - Waiting View

struct WaitingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Waiting for Status")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Connect to PathChanger on your Mac to see spoofing status here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Emergency Stop Button

struct EmergencyStopButton: View {
    @EnvironmentObject var connectionService: CompanionConnectionService
    @State private var showConfirmation = false

    var body: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack {
                Image(systemName: "exclamationmark.octagon.fill")
                Text("EMERGENCY STOP")
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .cornerRadius(12)
        }
        .confirmationDialog(
            "Stop location spoofing?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Spoofing", role: .destructive) {
                connectionService.sendEmergencyStop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will immediately stop all location simulation on your device.")
        }
    }
}

#if DEBUG
struct CompanionContentView_Previews: PreviewProvider {
    static var previews: some View {
        CompanionContentView()
            .environmentObject(CompanionConnectionService())
    }
}
#endif
