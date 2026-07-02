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
        VStack(spacing: AppSpacing.sm) {
            // Icon
            Image(systemName: iconForType(error.type))
                .font(DS.Typography.iconLarge)
                .foregroundColor(colorForType(error.type))

            // Title
            Text(titleForType(error.type))
                .font(AppFont.heading)

            // Message
            Text(error.message)
                .font(AppFont.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.pcTextMuted)
            // Suggestion
            if let suggestion = error.suggestion {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("How to fix:")
                        .font(AppFont.metadata)
                        .fontWeight(.semibold)

                    Text(suggestion)
                        .font(AppFont.metadata)
                        .foregroundColor(.pcTextMuted)
                }
                .padding()
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
                .cornerRadius(AppRadius.sm)
            }

            // Actions
            HStack(spacing: DS.Metrics.dependencyActionHPadding) {
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))

                if let action = error.action, let onAction = onAction {
                    Button(actionButtonTitle(action)) {
                        onAction(action)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: DS.Metrics.dialogWidth)
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
        case .connection, .network: return .pcWarning
        case .device: return .pcDanger
        case .location: return .pcPrimary
        case .permission: return .pcAccent
        case .system: return .pcTextMuted
        case .iosVersionUnsupported: return .pcWarning
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
        case .iosVersionUnsupported: return "iOS Compatibility Warning"
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
        switch type {
        case .connection, .device, .location, .network:
            return URL(string: "https://github.com/doronz88/pymobiledevice3")
        case .permission:
            return URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")
        case .system:
            return nil
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
        VStack(spacing: AppSpacing.sm) {
            // Icon with animation
            Image(systemName: iconForType(error.type))
                .font(DS.Typography.iconLarge)
                .foregroundColor(colorForType(error.type))
                .symbolEffect(.pulse, isActive: error.type == .connection)

            // Title
            Text(titleForType(error.type))
                .font(AppFont.heading)

            // Message
            Text(error.message)
                .font(AppFont.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.pcTextMuted)

            // Suggestion with recovery steps
            if let suggestion = error.suggestion {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Label("How to fix:", systemImage: "lightbulb.fill")
                        .font(AppFont.metadata)
                        .fontWeight(.semibold)
                        .foregroundColor(.pcWarning)

                    Text(suggestion)
                        .font(AppFont.metadata)
                        .foregroundColor(.pcTextMuted)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pcWarning.opacity(DS.Opacity.warningPanelTint))
                .cornerRadius(AppRadius.sm)
            }

            // Actions with Learn More
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: DS.Metrics.dependencyActionHPadding) {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))

                    if let action = error.action, let onAction = onAction {
                        Button(actionButtonTitle(action)) {
                            onAction(action)
                        }
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    }
                }

                // Learn More link
                if let helpURL = helpURLForType(error.type) {
                    Button(action: {
                        onLearnMore?(helpURL)
                    }) {
                        Label("Learn More", systemImage: "questionmark.circle")
                            .font(AppFont.metadata)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.pcPrimary)
                    .accessibleButton(
                        label: "Learn more about this error",
                        hint: "Opens related setup or troubleshooting documentation",
                        identifier: "errorDialogLearnMoreButton"
                    )
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: DS.Metrics.dialogWidth)
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
        case .connection, .network: return .pcWarning
        case .device: return .pcDanger
        case .location: return .pcPrimary
        case .permission: return .pcAccent
        case .system: return .pcTextMuted
        case .iosVersionUnsupported: return .pcWarning
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
        case .iosVersionUnsupported: return "iOS Compatibility Warning"
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
        switch type {
        case .connection, .device, .location, .network:
            return URL(string: "https://github.com/doronz88/pymobiledevice3")
        case .permission:
            return URL(string: "https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device")
        case .system:
            return nil
        case .iosVersionUnsupported:
            return URL(string: "https://github.com/doronz88/pymobiledevice3/issues")
        }
    }
}

// MARK: - Newer iOS Compatibility Warning Dialog

struct IOSCompatibilityWarningDialogView: View {
    let deviceVersion: String
    let onDismiss: () -> Void
    let onLearnMore: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Typography.iconLarge)
                .foregroundColor(.pcWarning)
                .symbolEffect(.pulse)

            // Title
            Text("iOS \(deviceVersion) Compatibility Warning")
                .font(AppFont.heading)

            // Message
            Text("Newer iOS versions may change Apple's DVT location service. PathChanger will still attempt location simulation instead of blocking.")
                .font(AppFont.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.pcTextMuted)

            // Compatibility notes
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label("What to try:", systemImage: "lightbulb.fill")
                    .font(AppFont.metadata)
                    .fontWeight(.semibold)
                    .foregroundColor(.pcWarning)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("1. Keep pymobiledevice3 updated")
                    Text("2. Start the tunnel, then try location simulation")
                    Text("3. If it fails, copy the exact DVT error for upstream tracking")
                }
                .font(AppFont.metadata)
                .foregroundColor(.pcTextMuted)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pcWarning.opacity(DS.Opacity.warningPanelTint))
            .cornerRadius(AppRadius.sm)

            // Actions
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: DS.Metrics.dependencyActionHPadding) {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))

                    Button("Learn More") {
                        if let url = URL(string: "https://github.com/doronz88/pymobiledevice3/issues") {
                            onLearnMore?(url)
                        }
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                }

            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: DS.Metrics.dialogWidth)
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
                    Text("Connection lost")
                    Spacer()
                    Button("Reconnect") {
                        reliabilityManager.retryNow()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .controlSize(.small)
                }
                .padding()
                .background(Color.pcWarning.opacity(DS.Opacity.warningPanelTint))
                .cornerRadius(AppRadius.sm)

            case .reconnecting(let attempt, let max):
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reconnecting (\(attempt)/\(max))...")
                    Spacer()
                    Button("Cancel") {
                        reliabilityManager.cancelReconnection()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .controlSize(.small)
                }
                .padding()
                .background(Color.pcWarning.opacity(DS.Opacity.warningPanelTint))
                .cornerRadius(AppRadius.sm)

            case .failed(let reason):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.pcDanger)
                    Text(reason)
                    Spacer()
                    Button("Retry") {
                        reliabilityManager.retryNow()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    .controlSize(.small)
                }
                .padding()
                .background(Color.pcDanger.opacity(DS.Opacity.warningPanelTint))
                .cornerRadius(AppRadius.sm)

            case .suspended:
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.pcTextMuted)
                    Text("Connection suspended")
                    Spacer()
                    Button("Resume") {
                        reliabilityManager.resume()
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .controlSize(.small)
                }
                .padding()
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
                .cornerRadius(AppRadius.sm)
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
                .fill(isRunning ? Color.pcSecondary : Color.pcDanger)
                .frame(width: DS.Metrics.stepIndicatorSize, height: DS.Metrics.stepIndicatorSize)

            Text(isRunning ? "Tunnel ready" : "Tunnel offline")
                .font(AppFont.metadata)

            if !isRunning {
                Button("Start") {
                    onStartRequest()
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcPrimary))
                .font(AppFont.metadata)
            }
        }
    }
}

// MARK: - Start Tunneld Sheet

struct StartTunneldSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: DS.Metrics.sheetStepBadgeSize) {
            Image(systemName: "terminal.fill")
                .font(DS.Typography.iconLarge)
                .foregroundColor(.pcPrimary)

            Text("Start Tunnel")
                .font(AppFont.heading)

            Text("Location injection on iOS 17+ requires the tunnel to be running.")
                .font(AppFont.body)
                .foregroundColor(.pcTextMuted)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Run this command in Terminal:")
                    .font(AppFont.metadata)
                    .fontWeight(.semibold)

                HStack {
                    Text("sudo python3 -m pymobiledevice3 remote tunneld")
                        .font(AppFont.monospace)
                        .padding(AppSpacing.xs)
                        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField))
                        .cornerRadius(DS.Metrics.smallCornerRadius)

                    Button {
                        copyToClipboard("sudo python3 -m pymobiledevice3 remote tunneld")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
            .cornerRadius(AppRadius.sm)

            Text("Keep the Terminal window open while using PathChanger.")
                .font(AppFont.metadata)
                .foregroundColor(.pcTextMuted)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
        }
        .padding(AppSpacing.md)
        .frame(width: DS.Metrics.dialogWidth)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Developer Mode Guide Sheet

struct DeveloperModeGuideSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: DS.Metrics.sheetStepBadgeSize) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(DS.Typography.iconLarge)
                .foregroundColor(.pcAccent)

            Text("Enable Developer Mode")
                .font(AppFont.heading)

            Text("Developer Mode is required for location simulation on iOS 16+.")
                .font(AppFont.body)
                .foregroundColor(.pcTextMuted)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: DS.Metrics.dependencyActionHPadding) {
                StepRow(number: 1, text: "Open Settings on your iPhone")
                StepRow(number: 2, text: "Go to Privacy & Security")
                StepRow(number: 3, text: "Scroll down and tap Developer Mode")
                StepRow(number: 4, text: "Toggle Developer Mode ON")
                StepRow(number: 5, text: "Restart your device when prompted")
            }
            .padding()
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
            .cornerRadius(AppRadius.sm)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
        }
        .padding(AppSpacing.md)
        .frame(width: DS.Metrics.dialogWidth)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Metrics.dependencyActionHPadding) {
            Text("\(number)")
                .font(AppFont.metadata)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: DS.Metrics.sheetStepBadgeSize, height: DS.Metrics.sheetStepBadgeSize)
                .background(Color.pcPrimary)
                .clipShape(Circle())

            Text(text)
                .font(AppFont.body)
        }
    }
}

#if DEBUG
struct ErrorDialogView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorDialogView(
            error: ErrorHandler.AppError(
                type: .device,
                message: "tunneld is not running. This is required for iOS 17+ location injection.",
                suggestion: "Run in Terminal:\nsudo python3 -m pymobiledevice3 remote tunneld",
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
