//
//  OnboardingView.swift
//  PathChanger
//
//  First-run onboarding with dependency validation and setup guidance
//

import SwiftUI
import AppKit

// MARK: - Onboarding State

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case dependencies = 1
    case deviceSetup = 2
    case complete = 3

    var title: String {
        switch self {
        case .welcome: return "Welcome to PathChanger"
        case .dependencies: return "System Dependencies"
        case .deviceSetup: return "Device Setup"
        case .complete: return "Ready to Go!"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .dependencies: return "checkmark.circle.fill"
        case .deviceSetup: return "iphone.gen3"
        case .complete: return "flag.checkered"
        }
    }
}

// MARK: - Dependency Check Result

struct DependencyCheckResult {
    let python3Installed: Bool
    let pythonVersion: String?
    let pymobiledevice3Installed: Bool
    let pymobiledevice3Version: String?
    let pythonVersionValid: Bool
    let pymobiledevice3VersionValid: Bool

    var allDependenciesMet: Bool {
        python3Installed && pythonVersionValid &&
        pymobiledevice3Installed && pymobiledevice3VersionValid
    }
}

// MARK: - Onboarding View Model

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var dependencyResult: DependencyCheckResult?
    @Published var isCheckingDependencies = false
    @Published var showCopiedToast = false

    func nextStep() {
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation {
                currentStep = nextStep
            }

            if currentStep == .dependencies {
                Task { await checkDependencies() }
            }
        }
    }

    func previousStep() {
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation {
                currentStep = prevStep
            }
        }
    }

    func checkDependencies() async {
        isCheckingDependencies = true
        defer { isCheckingDependencies = false }

        // Check Python
        var pythonInstalled = false
        var pythonVer: String? = nil
        var pythonValid = false

        do {
            try await PythonPathResolver.validateInstallation()
            pythonInstalled = true

            if let version = await PythonPathResolver.version() {
                pythonVer = version
                // Parse version and validate
                try await PythonPathResolver.checkPythonVersion()
                pythonValid = true
            }
        } catch {
            Logger.debug("Python validation failed: \(error)", category: .general)
        }

        // Check pymobiledevice3
        var pmd3Installed = false
        var pmd3Ver: String? = nil
        var pmd3Valid = false

        if pythonInstalled {
            pmd3Installed = await PythonPathResolver.isPymobiledevice3Installed()

            if pmd3Installed {
                do {
                    try await PythonPathResolver.validatePymobiledevice3()
                    pmd3Valid = true
                    pmd3Ver = await PythonPathResolver.pymobiledevice3Version()
                } catch {
                    Logger.debug("pymobiledevice3 validation failed: \(error)", category: .general)
                }
            }
        }

        dependencyResult = DependencyCheckResult(
            python3Installed: pythonInstalled,
            pythonVersion: pythonVer,
            pymobiledevice3Installed: pmd3Installed,
            pymobiledevice3Version: pmd3Ver,
            pythonVersionValid: pythonValid,
            pymobiledevice3VersionValid: pmd3Valid
        )
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(DS.Metrics.two)) {
            withAnimation {
                self.showCopiedToast = false
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        UserDefaults.standard.set(Date(), forKey: "onboardingCompletedDate")
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView

                // Content
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Footer
                footerView
            }

            // Copied toast
            if viewModel.showCopiedToast {
                VStack {
                    Spacer()
                    copiedToast
                        .padding(.bottom, DS.Metrics.onboardingToastBottomInset)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(
            minWidth: DS.Metrics.onboardingMinWidth,
            idealWidth: DS.Metrics.onboardingIdealWidth,
            maxWidth: DS.Metrics.onboardingMaxWidth,
            minHeight: DS.Metrics.onboardingMinHeight,
            idealHeight: DS.Metrics.onboardingIdealHeight,
            maxHeight: DS.Metrics.onboardingMaxHeight
        )
        .accessibilityIdentifier(identifierForCurrentStep)
    }

    private var headerView: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: viewModel.currentStep.icon)
                .font(DS.Typography.iconLarge)
                .foregroundColor(.pcPrimary)
                .padding(.top, DS.Metrics.onboardingHeaderTopPadding)

            Text(viewModel.currentStep.title)
                .font(AppFont.title)
                .fontWeight(.bold)

            // Progress indicator
            HStack(spacing: AppSpacing.xs) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(
                            step.rawValue <= viewModel.currentStep.rawValue
                                ? Color.pcPrimary
                                : Color.pcTextMuted.opacity(DS.Opacity.progressIndicatorFill)
                        )
                        .frame(width: DS.Metrics.stepIndicatorSize, height: DS.Metrics.stepIndicatorSize)
                }
            }
            .padding(.top, AppSpacing.xs)
        }
        .padding(.bottom, DS.Metrics.sheetStepBadgeSize)
        .background(Color.pcBackground)
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeStepView
        case .dependencies:
            dependenciesStepView
        case .deviceSetup:
            deviceSetupStepView
        case .complete:
            completeStepView
        }
    }

    private var footerView: some View {
        HStack {
            if viewModel.currentStep != .welcome {
                Button("Back") {
                    viewModel.previousStep()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                .accessibleButton(
                    label: "Back",
                    hint: "Returns to the previous onboarding step",
                    identifier: AccessibilityIdentifiers.Onboarding.previousButton
                )
            }

            Spacer()

            if viewModel.currentStep == .complete {
                Button("Get Started") {
                    viewModel.completeOnboarding()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                .accessibleButton(
                    label: "Get started",
                    hint: "Completes onboarding and opens PathChanger",
                    identifier: AccessibilityIdentifiers.Onboarding.nextButton
                )
            } else {
                if viewModel.currentStep == .dependencies {
                    Button("Continue Anyway") {
                        viewModel.nextStep()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isCheckingDependencies)
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .accessibleButton(
                        label: "Continue anyway",
                        hint: "Continues onboarding even if dependency checks are incomplete",
                        identifier: AccessibilityIdentifiers.Onboarding.nextButton
                    )
                } else {
                    Button("Next") {
                        viewModel.nextStep()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.currentStep == .dependencies && viewModel.isCheckingDependencies)
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    .accessibleButton(
                        label: "Next",
                        hint: "Advances to the next onboarding step",
                        identifier: AccessibilityIdentifiers.Onboarding.nextButton
                    )
                }
            }
        }
        .padding()
        .background(Color.pcBackground)
    }

    // MARK: - Step Views

    private var welcomeStepView: some View {
        VStack(spacing: DS.Metrics.sheetStepBadgeSize) {
            Spacer()

            Text("Simulate GPS Locations on iOS 17+ Devices")
                .font(AppFont.heading)
                .multilineTextAlignment(.center)
                .foregroundColor(.pcTextMuted)

            VStack(alignment: .leading, spacing: DS.Metrics.dependencyActionHPadding) {
                FeatureRow(icon: "location.fill", title: "GPS Simulation", description: "Set custom locations on your iOS device")
                FeatureRow(icon: "arrow.triangle.2.circlepath", title: "Route Playback", description: "Follow GPX routes with realistic movement")
                FeatureRow(icon: "wifi", title: "USB & WiFi", description: "Connect via USB or wireless tunnel")
                FeatureRow(icon: "lock.shield.fill", title: "Secure", description: "All processing happens locally on your Mac")
            }
            .padding(.vertical)

            Spacer()
        }
        .padding(.horizontal, DS.Metrics.onboardingHorizontalPadding)
    }

    private var dependenciesStepView: some View {
        VStack(spacing: DS.Metrics.sheetStepBadgeSize) {
            if viewModel.isCheckingDependencies {
                Spacer()
                ProgressView("Checking system dependencies...")
                    .scaleEffect(DS.Metrics.onboardingProgressScale)
                Spacer()
            } else if let result = viewModel.dependencyResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if result.allDependenciesMet {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.pcSecondary)
                                    .font(AppFont.heading)
                                Text("All dependencies are installed!")
                                    .font(AppFont.heading)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.pcSecondary.opacity(DS.Opacity.selectionTint))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.pcWarning)
                                    .font(AppFont.heading)
                                Text("Some dependencies are missing")
                                    .font(AppFont.heading)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.pcWarning.opacity(DS.Opacity.warningPanelTint))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }

                        // Python 3
                        DependencyCard(
                            title: "Python 3.9+",
                            installed: result.python3Installed,
                            valid: result.pythonVersionValid,
                            version: result.pythonVersion,
                            installCommand: "brew install python3",
                            onCopy: { viewModel.copyToClipboard($0) }
                        )

                        // pymobiledevice3
                        DependencyCard(
                            title: "pymobiledevice3",
                            installed: result.pymobiledevice3Installed,
                            valid: result.pymobiledevice3VersionValid,
                            version: result.pymobiledevice3Version,
                            installCommand: "pip3 install pymobiledevice3",
                            onCopy: { viewModel.copyToClipboard($0) }
                        )

                        Button("Re-check Dependencies") {
                            Task { await viewModel.checkDependencies() }
                        }
                        .padding(.top)
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("Click Next to check dependencies")
                    .foregroundColor(.pcTextMuted)
                Spacer()
            }
        }
    }

    private var deviceSetupStepView: some View {
        VStack(alignment: .leading, spacing: DS.Metrics.sheetStepBadgeSize) {
            Text("Prepare Your iOS Device")
                .font(AppFont.heading)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SetupStep(number: 1, title: "Enable Developer Mode", description: "Settings → Privacy & Security → Developer Mode → ON")
                SetupStep(number: 2, title: "Trust This Computer", description: "Connect via USB and tap 'Trust' when prompted")
                SetupStep(number: 3, title: "Connect Device", description: "Use USB for fastest connection, or WiFi for convenience")
            }

            Spacer()

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.pcPrimary)
                Text("Developer Mode requires an Apple ID and device restart")
                    .font(AppFont.metadata)
                    .foregroundColor(.pcTextMuted)
            }
            .padding()
            .background(Color.pcPrimary.opacity(DS.Opacity.selectionTint))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .padding(.horizontal, DS.Metrics.onboardingHorizontalPadding)
    }

    private var completeStepView: some View {
        VStack(spacing: DS.Metrics.sheetStepBadgeSize) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(DS.Typography.iconXLarge)
                .foregroundColor(.pcSecondary)

            Text("You're All Set!")
                .font(AppFont.title)
                .fontWeight(.bold)

            Text("PathChanger is ready to use")
                .foregroundColor(.pcTextMuted)

            Spacer()

            VStack(alignment: .leading, spacing: DS.Metrics.dependencyActionHPadding) {
                QuickTip(icon: "location.circle.fill", text: "Connect your device and start the tunnel")
                QuickTip(icon: "map.fill", text: "Click the map to set a location")
                QuickTip(icon: "arrow.triangle.2.circlepath", text: "Import GPX files for route playback")
            }
            .padding()
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))

            Spacer()
        }
        .padding(.horizontal, DS.Metrics.onboardingHorizontalPadding)
    }

    private var copiedToast: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.pcSecondary)
            Text("Copied to clipboard")
                .fontWeight(.medium)
        }
        .padding()
        .background(Color.pcSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .shadow(radius: DS.Metrics.mapSearchResultsShadowRadius)
    }

    private var identifierForCurrentStep: String {
        switch viewModel.currentStep {
        case .welcome:
            return AccessibilityIdentifiers.Onboarding.welcomeStep
        case .dependencies:
            return AccessibilityIdentifiers.Onboarding.dependenciesStep
        case .deviceSetup:
            return AccessibilityIdentifiers.Onboarding.deviceSetupStep
        case .complete:
            return AccessibilityIdentifiers.Onboarding.completeStep
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: DS.Metrics.dependencyActionHPadding) {
            Image(systemName: icon)
                .font(AppFont.heading)
                .foregroundColor(.pcPrimary)
                .frame(width: DS.Metrics.featureRowIconWidth)

            VStack(alignment: .leading, spacing: DS.Metrics.two) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(AppFont.metadata)
                    .foregroundColor(.pcTextMuted)
            }
        }
    }
}

struct DependencyCard: View {
    let title: String
    let installed: Bool
    let valid: Bool
    let version: String?
    let installCommand: String
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Metrics.dependencyActionHPadding) {
            HStack {
                Image(systemName: installed && valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(installed && valid ? .pcSecondary : .pcDanger)

                Text(title)
                    .font(AppFont.label)

                Spacer()

                if let version = version {
                    Text(version)
                        .font(AppFont.metadata)
                        .foregroundColor(.pcTextMuted)
                }
            }

            if !installed || !valid {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(installed ? "Version too old" : "Not installed")
                        .font(AppFont.metadata)
                        .foregroundColor(.pcTextMuted)

                    HStack {
                        Text(installCommand)
                            .font(AppFont.monospace)
                            .padding(AppSpacing.xs)
                            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

                        Button {
                            onCopy(installCommand)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .accessibleButton(
                            label: "Copy \(title) install command",
                            hint: "Copies the command to the clipboard",
                            identifier: "copy\(title.replacingOccurrences(of: " ", with: ""))InstallCommandButton"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.idleRow))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.pcPrimary)
                    .frame(width: DS.Metrics.setupStepCircleSize, height: DS.Metrics.setupStepCircleSize)
                Text("\(number)")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(AppFont.metadata)
                    .foregroundColor(.pcTextMuted)
            }
        }
    }
}

struct QuickTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Metrics.dependencyActionHPadding) {
            Image(systemName: icon)
                .foregroundColor(.pcPrimary)
                .frame(width: DS.Metrics.quickTipIconWidth)
            Text(text)
                .font(AppFont.body)
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
