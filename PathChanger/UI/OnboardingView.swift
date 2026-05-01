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
    
    private let minPythonVersion = "3.9"
    private let minPymobiledevice3Version = "6.1.5"
    
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
                    
                    // Try to get version string (simplified)
                    pmd3Ver = minPymobiledevice3Version // Placeholder
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 700, height: 550)
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.currentStep.icon)
                .font(.system(size: 48))
                .foregroundColor(.blue)
                .padding(.top, 30)
            
            Text(viewModel.currentStep.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)
        }
        .padding(.bottom, 20)
        .background(Color(NSColor.windowBackgroundColor))
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
            }
            
            Spacer()
            
            if viewModel.currentStep == .complete {
                Button("Get Started") {
                    viewModel.completeOnboarding()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                if viewModel.currentStep == .dependencies {
                    Button("Continue Anyway") {
                        viewModel.nextStep()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isCheckingDependencies)
                } else {
                    Button("Next") {
                        viewModel.nextStep()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.currentStep == .dependencies && viewModel.isCheckingDependencies)
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Step Views
    
    private var welcomeStepView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("Simulate GPS Locations on iOS 17+ Devices")
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "location.fill", title: "GPS Simulation", description: "Set custom locations on your iOS device")
                FeatureRow(icon: "arrow.triangle.2.circlepath", title: "Route Playback", description: "Follow GPX routes with realistic movement")
                FeatureRow(icon: "wifi", title: "USB & WiFi", description: "Connect via USB or wireless tunnel")
                FeatureRow(icon: "lock.shield.fill", title: "Secure", description: "All processing happens locally on your Mac")
            }
            .padding(.vertical)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    private var dependenciesStepView: some View {
        VStack(spacing: 20) {
            if viewModel.isCheckingDependencies {
                Spacer()
                ProgressView("Checking system dependencies...")
                    .scaleEffect(1.2)
                Spacer()
            } else if let result = viewModel.dependencyResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if result.allDependenciesMet {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                Text("All dependencies are installed!")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                Text("Some dependencies are missing")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
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
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("Click Next to check dependencies")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    private var deviceSetupStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Prepare Your iOS Device")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                SetupStep(number: 1, title: "Enable Developer Mode", description: "Settings → Privacy & Security → Developer Mode → ON")
                SetupStep(number: 2, title: "Trust This Computer", description: "Connect via USB and tap 'Trust' when prompted")
                SetupStep(number: 3, title: "Connect Device", description: "Use USB for fastest connection, or WiFi for convenience")
            }
            
            Spacer()
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Developer Mode requires an Apple ID and device restart")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal, 40)
    }
    
    private var completeStepView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("PathChanger is ready to use")
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                QuickTip(icon: "location.circle.fill", text: "Connect your device and start the tunnel")
                QuickTip(icon: "map.fill", text: "Click the map to set a location")
                QuickTip(icon: "arrow.triangle.2.circlepath", text: "Import GPX files for route playback")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    private var copiedToast: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Copied to clipboard")
                .fontWeight(.medium)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: installed && valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(installed && valid ? .green : .red)
                
                Text(title)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let version = version {
                    Text(version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !installed || !valid {
                VStack(alignment: .leading, spacing: 8) {
                    Text(installed ? "Version too old" : "Not installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(installCommand)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        
                        Button {
                            onCopy(installCommand)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct QuickTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
