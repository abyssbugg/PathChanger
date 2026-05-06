//
//  DiagnosticsView.swift
//  PathChanger
//
//  Comprehensive system diagnostics to identify setup issues
//

import SwiftUI
import AppKit

/// Diagnostic result for each check
struct DiagnosticResult: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let message: String
    let recoveryAction: String?

    enum Status {
        case success, warning, failure, checking

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.circle.fill"
            case .checking: return "circle.dotted"
            }
        }

        var color: Color {
            switch self {
            case .success: return .pcSecondary
            case .warning: return .pcWarning
            case .failure: return .pcDanger
            case .checking: return .pcTextMuted
            }
        }
    }
}

/// Diagnostics view for troubleshooting
struct DiagnosticsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var tunneldManager = TunneldManager.shared

    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false
    @State private var pythonVersion: String = ""
    @State private var pymobiledevice3Version: String = ""
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showExportSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .font(AppFont.heading)
                    .foregroundStyle(Color.pcTextMuted)
                Text("System Diagnostics")
                    .font(AppFont.title)
                    .foregroundStyle(Color.pcText)

                Spacer()

                Button {
                    Task { await exportDiagnosticLogs() }
                } label: {
                    Label(isExportingLogs ? "Exporting..." : "Export Logs", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                .disabled(isExportingLogs)

                Button {
                    Task { await runDiagnostics() }
                } label: {
                    Label(isRunning ? "Running..." : "Run Diagnostics", systemImage: "play.fill")
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                .disabled(isRunning)
            }
            Divider().overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))

            // Results
            if results.isEmpty && !isRunning {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.pcTextMuted)
                    Text("Click 'Run Diagnostics' to check your setup")
                        .font(AppFont.body)
                        .foregroundColor(.pcTextMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(results) { result in
                            DiagnosticResultRow(result: result)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Summary
            if !results.isEmpty {
                Divider().overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))

                let failures = results.filter { $0.status == .failure }.count
                let warnings = results.filter { $0.status == .warning }.count

                HStack {
                    if failures > 0 {
                        Label("\(failures) issues found", systemImage: "xmark.circle.fill")
                            .foregroundColor(.pcDanger)
                    } else if warnings > 0 {
                        Label("\(warnings) warnings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.pcWarning)
                    } else {
                        Label("All checks passed!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.pcSecondary)
                    }

                    Spacer()

                    if failures > 0 {
                        Text("Fix the issues above to enable location spoofing")
                            .font(AppFont.metadata)
                            .foregroundColor(.pcTextMuted)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Color.pcBackground)
        .frame(minWidth: 500, minHeight: 400)
        .alert("Logs Exported", isPresented: $showExportSuccess) {
            Button("Show in Finder") {
                if let url = exportedLogURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let url = exportedLogURL {
                Text("Logs exported to:\n\(url.path)")
            }
        }
    }

    @MainActor
    func exportDiagnosticLogs() async {
        isExportingLogs = true

        // Log current diagnostic state before export
        Logger.info("Exporting diagnostic logs - Python: \(pythonVersion), pymobiledevice3: \(pymobiledevice3Version)", category: .general)

        if let url = await Logger.exportLogs() {
            exportedLogURL = url
            showExportSuccess = true
            Logger.info("Diagnostic logs exported successfully to: \(url.path)", category: .general)
        } else {
            // Show error if export failed
            Logger.error("Failed to export diagnostic logs", category: .general)
        }

        isExportingLogs = false
    }

    @MainActor
    func runDiagnostics() async {
        isRunning = true
        results = []

        // Check 1: Python3 installation
        results.append(DiagnosticResult(
            name: "Python 3",
            status: .checking,
            message: "Checking...",
            recoveryAction: nil
        ))
        let pythonResult = await checkPython()
        results[results.count - 1] = pythonResult

        // Check 2: pymobiledevice3 installation
        results.append(DiagnosticResult(
            name: "pymobiledevice3",
            status: .checking,
            message: "Checking...",
            recoveryAction: nil
        ))
        let pmd3Result = await checkPymobiledevice3()
        results[results.count - 1] = pmd3Result

        // Check 3: Tunnel status
        results.append(DiagnosticResult(
            name: "Tunnel Status",
            status: .checking,
            message: "Checking...",
            recoveryAction: nil
        ))
        let tunnelResult = await checkTunnel()
        results[results.count - 1] = tunnelResult

        // Check 4: Device connection
        results.append(DiagnosticResult(
            name: "Device Connected",
            status: .checking,
            message: "Checking...",
            recoveryAction: nil
        ))
        let deviceResult = await checkDevice()
        results[results.count - 1] = deviceResult

        // Check 5: Device selection
        results.append(DiagnosticResult(
            name: "Device Selected",
            status: appState.selectedDevice != nil ? .success : .failure,
            message: appState.selectedDevice != nil ? "Device: \(appState.selectedDevice!.displayName)" : "No device selected",
            recoveryAction: appState.selectedDevice == nil ? "Select a device from the sidebar" : nil
        ))

        // Check 6: Target location
        results.append(DiagnosticResult(
            name: "Target Location",
            status: appState.targetLocation != nil ? .success : .warning,
            message: appState.targetLocation != nil ?
                String(format: "%.4f, %.4f", appState.targetLocation!.latitude, appState.targetLocation!.longitude) :
                "No target location set",
            recoveryAction: appState.targetLocation == nil ? "Search for a location or click on the map" : nil
        ))

        // Check 7: Location injection test (only if all previous passed)
        if pythonResult.status == .success &&
           pmd3Result.status == .success &&
           tunnelResult.status == .success &&
           appState.selectedDevice != nil {
            results.append(DiagnosticResult(
                name: "Location Injection",
                status: .checking,
                message: "Testing...",
                recoveryAction: nil
            ))
            let injectionResult = await checkLocationInjection()
            results[results.count - 1] = injectionResult
        }

        isRunning = false
    }

    func checkPython() async -> DiagnosticResult {
        do {
            let output = try await runCommand(PythonPathResolver.path, args: ["--version"])
            pythonVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return DiagnosticResult(
                name: "Python 3",
                status: .success,
                message: pythonVersion,
                recoveryAction: nil
            )
        } catch {
            return DiagnosticResult(
                name: "Python 3",
                status: .failure,
                message: "Python 3 not found",
                recoveryAction: "Install Python 3: brew install python3"
            )
        }
    }

    func checkPymobiledevice3() async -> DiagnosticResult {
        do {
            let output = try await runCommand(PythonPathResolver.path, args: ["-m", "pymobiledevice3", "version"])
            pymobiledevice3Version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return DiagnosticResult(
                name: "pymobiledevice3",
                status: .success,
                message: "Version: \(pymobiledevice3Version)",
                recoveryAction: nil
            )
        } catch {
            return DiagnosticResult(
                name: "pymobiledevice3",
                status: .failure,
                message: "pymobiledevice3 not installed or not working",
                recoveryAction: "Install: python3 -m pip install -U pymobiledevice3"
            )
        }
    }

    func checkTunnel() async -> DiagnosticResult {
        let isRunning = tunneldManager.isRunning

        if isRunning {
            let rsdInfo = tunneldManager.tunnelInfo
            let message = rsdInfo != nil ?
                "Running - RSD: \(rsdInfo!.rsdAddress):\(rsdInfo!.rsdPort)" :
                "Running (RSD info not parsed)"

            return DiagnosticResult(
                name: "Tunnel Status",
                status: rsdInfo != nil ? .success : .warning,
                message: message,
                recoveryAction: rsdInfo == nil ? "Restart tunnel to refresh RSD info" : nil
            )
        } else {
            return DiagnosticResult(
                name: "Tunnel Status",
                status: .failure,
                message: "Tunnel not running - required for iOS 17+",
                recoveryAction: "Go to Settings > Start Tunnel, or run: sudo python3 -m pymobiledevice3 lockdown start-tunnel"
            )
        }
    }

    func checkDevice() async -> DiagnosticResult {
        do {
            let output = try await runCommand(PythonPathResolver.path, args: [
                "-m", "pymobiledevice3", "--no-color", "usbmux", "list"
            ])

            // Check for various device identifiers (supports both USB and WiFi/Network connections)
            let hasDevice = output.contains("Identifier") ||
                           output.contains("UniqueDeviceID") ||
                           output.contains("SerialNumber") ||
                           output.contains("UDID") ||
                           output.contains("DeviceName") ||
                           output.contains("ProductType") ||
                           output.contains("ConnectionType")

            if hasDevice {
                // Detect connection type
                let isWiFi = output.contains("\"Network\"") || output.contains("ConnectionType\": \"Network")
                let isUSB = output.contains("\"USB\"") || output.contains("ConnectionType\": \"USB")
                let connectionType = isWiFi ? "WiFi" : (isUSB ? "USB" : "USB/WiFi")

                return DiagnosticResult(
                    name: "Device Connected",
                    status: .success,
                    message: "Device found via \(connectionType)",
                    recoveryAction: nil
                )
            } else {
                return DiagnosticResult(
                    name: "Device Connected",
                    status: .failure,
                    message: "No devices found",
                    recoveryAction: "Connect iOS device via USB and tap 'Trust' when prompted"
                )
            }
        } catch {
            return DiagnosticResult(
                name: "Device Connected",
                status: .failure,
                message: "Failed to list devices: \(error.localizedDescription)",
                recoveryAction: "Ensure device is connected and trusted"
            )
        }
    }

    func checkLocationInjection() async -> DiagnosticResult {
        guard let device = appState.selectedDevice else {
            return DiagnosticResult(
                name: "Location Injection",
                status: .failure,
                message: "No device selected",
                recoveryAction: "Select a device first"
            )
        }

        // Get iOS version for display and checking
        let iosVersion = device.productVersion ?? "Unknown"
        let iosVersionDisplay = "iOS \(iosVersion)"
        let hasCompatibilityWarning = device.hasLocationCompatibilityWarning

        // Test with actual simulate-location set command using test coordinates (0.0, 0.0)
        do {
            var args = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set"]

            // Add device connection arguments based on tunnel status
            if tunneldManager.isRunning, let rsdInfo = tunneldManager.tunnelInfo {
                args.append(contentsOf: ["--rsd", rsdInfo.rsdAddress, String(rsdInfo.rsdPort)])
            } else if tunneldManager.isRunning {
                args.append(contentsOf: ["--tunnel", device.id])
            } else {
                args.append(contentsOf: ["--udid", device.id])
            }

            // Add test coordinates
            args.append(contentsOf: ["--", "0.0", "0.0"])

            let output = try await runCommand(PythonPathResolver.path, args: args)
            let outputLower = output.lowercased()

            // Check for specific error patterns that indicate failure
            let hasInvalidServiceError = outputLower.contains("invalidserviceerror")
            let hasDeveloperModeError = outputLower.contains("developermodeerror") || outputLower.contains("developer mode")
            let hasDeviceNotFoundError = outputLower.contains("devicenotfounderror")
            let hasServiceNotAvailable = outputLower.contains("servicenotavailableerror") || output.contains("-402653150")

            if hasDeveloperModeError {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Developer Mode not enabled",
                    recoveryAction: "Enable Developer Mode: Settings > Privacy & Security > Developer Mode"
                )
            } else if hasDeviceNotFoundError {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Device not found",
                    recoveryAction: "Reconnect device and ensure it's trusted"
                )
            } else if hasInvalidServiceError || hasServiceNotAvailable {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Location simulation service unavailable",
                    recoveryAction: "Ensure Developer Mode is enabled and device is unlocked"
                )
            } else if outputLower.contains("error") || outputLower.contains("failed") || outputLower.contains("exception") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - DVT connection error",
                    recoveryAction: "Ensure device is unlocked, Developer Mode is ON, and device is trusted"
                )
            } else {
                // No error messages detected - consider it a success
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .success,
                    message: hasCompatibilityWarning
                        ? "\(iosVersionDisplay) - Location simulation command succeeded; newer iOS may still be less reliable"
                        : "\(iosVersionDisplay) - Location simulation test successful (used test coordinates 0.0, 0.0)",
                    recoveryAction: nil
                )
            }
        } catch {
            let errorStr = "\(error)".lowercased()
            // Check for newer-iOS service unavailable errors
            if errorStr.contains("servicenotavailableerror") || errorStr.contains("-402653150") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Location simulation service unavailable",
                    recoveryAction: "Update pymobiledevice3, retry with a fresh tunnel, and report the exact DVT error upstream if it persists"
                )
            } else if errorStr.contains("developer mode") || errorStr.contains("developermode") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Developer Mode not enabled on device",
                    recoveryAction: "Enable: Settings > Privacy & Security > Developer Mode > ON, then restart device"
                )
            } else if errorStr.contains("trusted") || errorStr.contains("pair") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Device not trusted",
                    recoveryAction: "Unlock device, tap 'Trust' when prompted, enter passcode"
                )
            } else if errorStr.contains("tunnel") || errorStr.contains("rsd") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .failure,
                    message: "\(iosVersionDisplay) - Tunnel connection failed",
                    recoveryAction: "Restart tunnel in Settings"
                )
            } else if errorStr.contains("timeout") {
                return DiagnosticResult(
                    name: "Location Injection",
                    status: .warning,
                    message: "\(iosVersionDisplay) - DVT connection timed out",
                    recoveryAction: "Device may be slow to respond - try again or restart tunnel"
                )
            }

            return DiagnosticResult(
                name: "Location Injection",
                status: .failure,
                message: "\(iosVersionDisplay) - DVT connection failed",
                recoveryAction: "Check: 1) Developer Mode ON, 2) Device trusted, 3) Device unlocked"
            )
        }
    }

    func runCommand(_ path: String, args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessEnvironment.configured(preserveExistingPath: true)

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: output)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct DiagnosticResultRow: View {
    let result: DiagnosticResult

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: result.status.icon)
                .foregroundColor(result.status.color)
                .font(AppFont.heading)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(result.name)
                    .font(AppFont.label)
                    .foregroundColor(.pcText)

                Text(result.message)
                    .font(AppFont.metadata)
                    .foregroundColor(.pcTextMuted)

                if let recovery = result.recoveryAction {
                    Text(recovery)
                        .font(AppFont.metadata)
                        .foregroundColor(.pcPrimary)
                        .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(AppSpacing.sm)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
    }
}

/// Wrapper for presenting DiagnosticsView as a dismissible sheet
struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.heading)
                        .foregroundColor(.pcTextMuted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)

            DiagnosticsView()
                .environmentObject(appState)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#if DEBUG
struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsView()
            .environmentObject(AppState())
    }
}
#endif
