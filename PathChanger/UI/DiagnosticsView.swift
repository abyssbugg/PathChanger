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
            case .success: return .green
            case .warning: return .orange
            case .failure: return .red
            case .checking: return .gray
            }
        }
    }
}

/// Diagnostics view for troubleshooting
struct DiagnosticsView: View {
    @EnvironmentObject var appState: AppState

    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false
    /// Bumped by Run Diagnostics; the run is the `.task(id:)` for it, which SwiftUI
    /// cancels when the sheet closes (review 2026-11-03 issue 6).
    @State private var diagnosticsRun = 0
    @State private var isExportingLogs = false
    @State private var exportedLogURL: URL?
    @State private var showExportSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                Text("System Diagnostics")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    Task { await exportDiagnosticLogs() }
                } label: {
                    Label(isExportingLogs ? "Exporting..." : "Export Logs", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(isExportingLogs)

                Button {
                    // `.task(id:)` below runs it, so closing the sheet cancels the run.
                    diagnosticsRun += 1
                } label: {
                    Label(isRunning ? "Running..." : "Run Diagnostics", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Location session")
                    .font(.headline)
                Text(appState.locationPresentation.sessionDiagnostic)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("location.diagnostics.session")
                Text(appState.locationPresentation.deviceLifecycleLabel + " · " + appState.locationPresentation.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Results
            if results.isEmpty && !isRunning {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Click 'Run Diagnostics' to check your setup")
                        .foregroundColor(.secondary)
                    Text("Diagnostics only reads. It never changes the phone's location or the connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ProgressView("Running read-only checks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(results) { result in
                            DiagnosticResultRow(result: result)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Summary
            if !results.isEmpty {
                Divider()

                let failures = results.filter { $0.status == .failure }.count
                let warnings = results.filter { $0.status == .warning }.count

                HStack {
                    if failures > 0 {
                        Label("\(failures) issues found", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    } else if warnings > 0 {
                        Label("\(warnings) warnings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Label("All checks passed!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Spacer()

                    if failures > 0 {
                        Text("Fix the issues above to enable location spoofing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .task(id: diagnosticsRun) {
            guard diagnosticsRun > 0 else { return }
            await runDiagnostics()
        }
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

        // Log the last diagnostic outcome (check names and statuses only) before export
        let summary = results.map { "\($0.name): \($0.status)" }.joined(separator: ", ")
        Logger.info("Exporting diagnostic logs - last diagnostics: \(summary.isEmpty ? "not run" : summary)", category: .general)

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

    /// Read-only: see `SystemDiagnostics`. Nothing here sends a location or starts or
    /// stops a tunnel or the location helper. Cancelled with its `.task` (sheet closed):
    /// the command in flight is stopped and no partial results are shown.
    @MainActor
    func runDiagnostics() async {
        isRunning = true
        defer { isRunning = false }
        results = []
        let snapshot = DiagnosticsSnapshot.live(appState: appState)
        let finished = await SystemDiagnostics.live().run(snapshot)
        guard !Task.isCancelled else { return }
        results = finished
    }
}

struct DiagnosticResultRow: View {
    let result: DiagnosticResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.status.icon)
                .foregroundColor(result.status.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .fontWeight(.medium)

                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let recovery = result.recoveryAction {
                    Text(recovery)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
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
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal)
            .padding(.top, 12)

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
