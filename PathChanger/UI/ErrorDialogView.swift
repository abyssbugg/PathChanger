//
//  ErrorDialogView.swift
//  PathChanger
//
//  User-friendly error dialogs with actionable guidance
//

import SwiftUI

// MARK: - Error Dialog View

struct ErrorDialogView: View {
    let error: ErrorHandler.AppError
    let onDismiss: () -> Void
    let onAction: ((ErrorHandler.ErrorAction) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: iconForType(error.type))
                .font(.system(size: 48))
                .foregroundColor(colorForType(error.type))

            // Title
            Text(titleForType(error.type))
                .font(.headline)

            // Message
            Text(error.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Suggestion
            if let suggestion = error.suggestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to fix:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                if let action = error.action, let onAction = onAction {
                    Button(actionButtonTitle(action)) {
                        onAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
    }

    private func iconForType(_ type: ErrorHandler.ErrorType) -> String {
        switch type {
        case .connection: return "wifi.exclamationmark"
        case .device: return "iphone.slash"
        case .location: return "location.slash"
        case .permission: return "lock.shield"
        case .network: return "network.slash"
        case .system: return "exclamationmark.triangle"
        case .iosVersionUnsupported: return "exclamationmark.triangle.fill"
        }
    }

    private func colorForType(_ type: ErrorHandler.ErrorType) -> Color {
        switch type {
        case .connection, .network: return .orange
        case .device: return .red
        case .location: return .blue
        case .permission: return .purple
        case .system: return .gray
        case .iosVersionUnsupported: return .orange
        }
    }

    private func titleForType(_ type: ErrorHandler.ErrorType) -> String {
        switch type {
        case .connection: return "Connection Error"
        case .device: return "Device Error"
        case .location: return "Location Error"
        case .permission: return "Permission Required"
        case .network: return "Network Error"
        case .system: return "Error"
        case .iosVersionUnsupported: return "Keep the tunnel running"
        }
    }

    private func actionButtonTitle(_ action: ErrorHandler.ErrorAction) -> String {
        switch action {
        case .retry: return "Retry"
        case .openSettings: return "Open Settings"
        case .startTunneld: return "Start Tunnel"
        case .enableDeveloperMode: return "Enable Developer Mode"
        case .checkConnection: return "Check Connection"
        }
    }

    private func helpURLForType(_ type: ErrorHandler.ErrorType) -> URL? {
        // Link to relevant documentation based on error type
        let baseURL = "https://github.com/PathChanger/docs/wiki/"
        switch type {
        case .connection:
            return URL(string: baseURL + "Troubleshooting#connection-issues")
        case .device:
            return URL(string: baseURL + "Troubleshooting#device-issues")
        case .location:
            return URL(string: baseURL + "Troubleshooting#location-errors")
        case .permission:
            return URL(string: baseURL + "Setup#permissions")
        case .network:
            return URL(string: baseURL + "Troubleshooting#network-issues")
        case .system:
            return URL(string: baseURL + "Troubleshooting")
        case .iosVersionUnsupported:
            return URL(string: "https://github.com/doronz88/pymobiledevice3/issues")
        }
    }
}

// MARK: - Enhanced Error Dialog with Recovery Actions

struct EnhancedErrorDialogView: View {
    let error: ErrorHandler.AppError
    let onDismiss: () -> Void
    let onAction: ((ErrorHandler.ErrorAction) -> Void)?
    let onLearnMore: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Icon with animation
            Image(systemName: iconForType(error.type))
                .font(.system(size: 48))
                .foregroundColor(colorForType(error.type))
                .symbolEffect(.pulse, isActive: error.type == .connection)

            // Title
            Text(titleForType(error.type))
                .font(.headline)

            // Message
            Text(error.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Suggestion with recovery steps
            if let suggestion = error.suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How to fix:", systemImage: "lightbulb.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Actions with Learn More
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)

                    if let action = error.action, let onAction = onAction {
                        Button(actionButtonTitle(action)) {
                            onAction(action)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Learn More link
                Button(action: {
                    if let url = helpURLForType(error.type) {
                        onLearnMore?(url)
                    }
                }) {
                    Label("Learn More", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
    }

    private func iconForType(_ type: ErrorHandler.ErrorType) -> String {
        switch type {
        case .connection: return "wifi.exclamationmark"
        case .device: return "iphone.slash"
        case .location: return "location.slash"
        case .permission: return "lock.shield"
        case .network: return "network.slash"
        case .system: return "exclamationmark.triangle"
        case .iosVersionUnsupported: return "exclamationmark.triangle.fill"
        }
    }

    private func colorForType(_ type: ErrorHandler.ErrorType) -> Color {
        switch type {
        case .connection, .network: return .orange
        case .device: return .red
        case .location: return .blue
        case .permission: return .purple
        case .system: return .gray
        case .iosVersionUnsupported: return .orange
        }
    }

    private func titleForType(_ type: ErrorHandler.ErrorType) -> String {
        switch type {
        case .connection: return "Connection Error"
        case .device: return "Device Error"
        case .location: return "Location Error"
        case .permission: return "Permission Required"
        case .network: return "Network Error"
        case .system: return "Error"
        case .iosVersionUnsupported: return "Keep the tunnel running"
        }
    }

    private func actionButtonTitle(_ action: ErrorHandler.ErrorAction) -> String {
        switch action {
        case .retry: return "Retry"
        case .openSettings: return "Open Settings"
        case .startTunneld: return "Start Tunnel"
        case .enableDeveloperMode: return "Enable Developer Mode"
        case .checkConnection: return "Check Connection"
        }
    }

    private func helpURLForType(_ type: ErrorHandler.ErrorType) -> URL? {
        let baseURL = "https://github.com/PathChanger/docs/wiki/"
        switch type {
        case .connection:
            return URL(string: baseURL + "Troubleshooting#connection-issues")
        case .device:
            return URL(string: baseURL + "Troubleshooting#device-issues")
        case .location:
            return URL(string: baseURL + "Troubleshooting#location-errors")
        case .permission:
            return URL(string: baseURL + "Setup#permissions")
        case .network:
            return URL(string: baseURL + "Troubleshooting#network-issues")
        case .system:
            return URL(string: baseURL + "Troubleshooting")
        case .iosVersionUnsupported:
            return URL(string: "https://github.com/doronz88/pymobiledevice3/issues")
        }
    }
}

// MARK: - iOS 18+ Warning Dialog

struct IOS18WarningDialogView: View {
    let deviceVersion: String
    let onDismiss: () -> Void
    let onLearnMore: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
                .symbolEffect(.pulse)

            // Title
            Text("iOS \(deviceVersion) — keep the tunnel running")
                .font(.headline)

            // Message
            Text("PathChanger will attempt location injection on this iOS version. If the pin snaps back, restart the tunnel and leave the app open.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Downgrade instructions
            VStack(alignment: .leading, spacing: 8) {
                Label("If spoofing fails:", systemImage: "lightbulb.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Start Tunnel from PathChanger and enter your Mac password")
                    Text("2. Use USB or the same Wi-Fi as this Mac")
                    Text("3. Leave PathChanger open while the spoof is active")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            // Actions
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Learn More") {
                        if let url = URL(string: "https://github.com/doronz88/pymobiledevice3/issues") {
                            onLearnMore?(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(action: {
                    if let url = URL(string: "https://ipsw.me") {
                        onLearnMore?(url)
                    }
                }) {
                    Label("Download iOS 17.6 IPSW", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
    }
}

// MARK: - Connection Status Banner

struct ConnectionStatusBanner: View {
    @ObservedObject var reliabilityManager: ReliabilityManager

    var body: some View {
        Group {
            switch reliabilityManager.recoveryState {
            case .connected:
                EmptyView()

            case .disconnected:
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Disconnected")
                    Spacer()
                    Button("Reconnect") {
                        reliabilityManager.retryNow()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)

            case .reconnecting(let attempt, let max):
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reconnecting (\(attempt)/\(max))...")
                    Spacer()
                    Button("Cancel") {
                        reliabilityManager.cancelReconnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)

            case .failed(let reason):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(reason)
                    Spacer()
                    Button("Retry") {
                        reliabilityManager.retryNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)

            case .suspended:
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.gray)
                    Text("Connection suspended")
                    Spacer()
                    Button("Resume") {
                        reliabilityManager.resume()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Tunneld Status View

struct TunneldStatusView: View {
    let isRunning: Bool
    let onStartRequest: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isRunning ? "tunneld running" : "tunneld not running")
                .font(.caption)

            if !isRunning {
                Button("Start") {
                    onStartRequest()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }
}

// MARK: - Start Tunneld Sheet

struct StartTunneldSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Start tunneld")
                .font(.headline)

            Text("The selected provider requires an RSD-capable tunnel to inject location.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Use Start Tunnel in PathChanger. The selected Python runs with your user account.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 400)
    }

}

// MARK: - Developer Mode Guide Sheet

struct DeveloperModeGuideSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("Enable Developer Mode")
                .font(.headline)

            Text("Developer Mode is required for location simulation on iOS 16+.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Open Settings on your iPhone")
                StepRow(number: 2, text: "Go to Privacy & Security")
                StepRow(number: 3, text: "Scroll down and tap Developer Mode")
                StepRow(number: 4, text: "Toggle Developer Mode ON")
                StepRow(number: 5, text: "Restart your device when prompted")
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)
        }
    }
}

#if DEBUG
struct ErrorDialogView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorDialogView(
            error: ErrorHandler.AppError(
                type: .device,
                message: "No usable RSD tunnel is running for the selected provider.",
                suggestion: "Use Start Tunnel in PathChanger.",
                timestamp: Date(),
                isRecoverable: true,
                action: .startTunneld
            ),
            onDismiss: {},
            onAction: { _ in }
        )
    }
}
#endif
