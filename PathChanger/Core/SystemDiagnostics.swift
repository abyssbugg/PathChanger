//
//  SystemDiagnostics.swift
//  PathChanger
//
//  The checks behind Settings > Diagnostics. They are read-only: they never send or clear
//  a location, never start or stop a tunnel or the location helper, and never open a
//  device connection. Device state comes from what the app already holds; the only
//  device question asked is the helper's Developer Disk Image status over a connection
//  that is already open. usbmuxd is asked only for its own device list (`usbmux list
//  --simple`, which opens no lockdown session on the phones it lists). Commands run
//  through a bounded runner and a check passes only when its command exited 0.
//

import Foundation

/// Runs one Diagnostics command. `BoundedProcessRunner` is the production conformer.
protocol DiagnosticsCommandRunning: Sendable {
    func run(executable: String, arguments: [String]) async -> BoundedProcessResult
}

extension BoundedProcessRunner: DiagnosticsCommandRunning {}

/// What the app already knows, read once when Diagnostics runs.
struct DiagnosticsSnapshot: Equatable {
    struct SelectedDevice: Equatable {
        let id: String
        let displayName: String
        /// The transport the helper's connection to this device uses.
        let transport: LocationTransport
        let productVersion: String?
    }

    var pythonPath: String
    var selectedDevice: SelectedDevice?
    var desiredCoordinate: LocationCoordinate?
    /// PID of the location helper this app session runs or adopted; nil when none.
    var helperProcessID: Int32?
    var tunnelState: TunnelState
    var tunnelInfo: TunnelInfo?
    /// The DVT lane of the location currently held on the device, if any.
    var heldLocationLane: String?
}

extension DiagnosticsSnapshot {
    /// Reads the live app state. Reads only: nothing is started, opened or sent.
    @MainActor
    static func live(appState: AppState) -> DiagnosticsSnapshot {
        let tunnel = TunneldManager.shared
        let selected = appState.selectedDevice.map { device in
            SelectedDevice(
                id: device.id,
                displayName: device.displayName,
                transport: appState.deviceManager.helperConnectTransport(for: device.id),
                productVersion: device.productVersion
            )
        }
        let coordinatorState = appState.locationSessionCoordinator.state
        let heldReceipt: LocationInjectionReceipt? = {
            if case .active(let receipt) = coordinatorState.application { return receipt }
            return coordinatorState.heldWhileApplying
        }()
        return DiagnosticsSnapshot(
            pythonPath: PythonPathResolver.path,
            selectedDevice: selected,
            desiredCoordinate: appState.locationPresentation.desiredCoordinate,
            helperProcessID: PersistentLocationBridge.shared.helperProcessIdentifierIfRunning(),
            tunnelState: tunnel.state,
            tunnelInfo: tunnel.tunnelInfo,
            heldLocationLane: heldReceipt?.actualChannel?.rawValue
        )
    }
}

@MainActor
struct SystemDiagnostics {
    /// Asks the location helper, over the connection it already holds, whether a
    /// Developer Disk Image is mounted. Must never start the helper or open a connection.
    typealias DiskImageStatusQuery = @MainActor (_ deviceID: String, _ transport: LocationTransport) async -> HelperDiskImageStatus

    nonisolated static let pythonVersionArguments = ["--version"]
    nonisolated static var capabilityProbeArguments: [String] {
        ["-c", PythonPathResolver.pymobiledevice3CapabilityProbeScript]
    }
    /// usbmuxd's device list, one run per connection type. `--simple` lists UDIDs without
    /// connecting to lockdownd (pymobiledevice3 11.49.1); the plain form opened a lockdown
    /// session on every listed phone (review 2026-11-03 issue 5).
    nonisolated static let usbmuxListUSBArguments = ["-m", "pymobiledevice3", "usbmux", "list", "--simple", "--usb"]
    nonisolated static let usbmuxListNetworkArguments = ["-m", "pymobiledevice3", "usbmux", "list", "--simple", "--network"]

    let runner: any DiagnosticsCommandRunning
    let diskImageStatus: DiskImageStatusQuery

    init(runner: any DiagnosticsCommandRunning, diskImageStatus: @escaping DiskImageStatusQuery) {
        self.runner = runner
        self.diskImageStatus = diskImageStatus
    }

    /// The production checks: the bounded runner and the shared helper's read-only query.
    static func live() -> SystemDiagnostics {
        SystemDiagnostics(
            runner: BoundedProcessRunner(),
            diskImageStatus: { deviceID, transport in
                await PersistentLocationBridge.shared.ddiStatus(deviceId: deviceID, transport: transport)
            }
        )
    }

    func run(_ snapshot: DiagnosticsSnapshot) async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        results.append(await checkPython(snapshot))
        results.append(await checkCapabilities(snapshot))
        results.append(checkHelper(snapshot))
        results.append(checkConnection(snapshot))
        results.append(await checkDiskImage(snapshot))
        results.append(await checkUsbmux(snapshot))
        results.append(checkSelectedDevice(snapshot))
        results.append(checkTargetLocation(snapshot))
        return results
    }

    // MARK: - Checks

    private func checkPython(_ snapshot: DiagnosticsSnapshot) async -> DiagnosticResult {
        let name = "Python runtime"
        let result = await runner.run(executable: snapshot.pythonPath, arguments: Self.pythonVersionArguments)
        guard result.succeeded else {
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "The managed Python runtime \(result.failureDescription ?? "failed").",
                recoveryAction: "Use PathChanger’s Install pymobiledevice3 button to rebuild the managed runtime"
            )
        }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return DiagnosticResult(
            name: name,
            status: .success,
            message: version.isEmpty ? "Runs" : version,
            recoveryAction: nil
        )
    }

    private func checkCapabilities(_ snapshot: DiagnosticsSnapshot) async -> DiagnosticResult {
        let name = "pymobiledevice3"
        let recovery = "Use PathChanger’s Install pymobiledevice3 button"
        let result = await runner.run(executable: snapshot.pythonPath, arguments: Self.capabilityProbeArguments)
        guard result.succeeded else {
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "The capability check \(result.failureDescription ?? "failed").",
                recoveryAction: recovery
            )
        }
        guard let report = Self.decodeCapabilityReport(result.output) else {
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "The capability check printed no readable report.",
                recoveryAction: recovery
            )
        }
        do {
            try PythonPathResolver.validatePymobiledevice3Capabilities(
                version: report.version,
                available: Set(report.capabilities)
            )
        } catch {
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: error.localizedDescription,
                recoveryAction: recovery
            )
        }
        let count = PythonPathResolver.requiredPymobiledevice3Capabilities.count
        return DiagnosticResult(
            name: name,
            status: .success,
            message: "Version \(report.version), all \(count) required capabilities present",
            recoveryAction: nil
        )
    }

    private func checkHelper(_ snapshot: DiagnosticsSnapshot) -> DiagnosticResult {
        let name = "Location helper"
        if let pid = snapshot.helperProcessID {
            return DiagnosticResult(name: name, status: .success, message: "Running (PID \(pid))", recoveryAction: nil)
        }
        return DiagnosticResult(
            name: name,
            status: .warning,
            message: "Not running in this session",
            recoveryAction: "Start Tunnel or Move starts it; Diagnostics does not"
        )
    }

    /// The helper's connection to the selected device, when it holds one.
    private func openHelperConnection(_ snapshot: DiagnosticsSnapshot) -> DiagnosticsSnapshot.SelectedDevice? {
        guard let device = snapshot.selectedDevice,
              snapshot.helperProcessID != nil,
              snapshot.tunnelState.isActive,
              let info = snapshot.tunnelInfo,
              info.channel == .helperUserspace,
              info.deviceId == device.id else {
            return nil
        }
        return device
    }

    private func checkConnection(_ snapshot: DiagnosticsSnapshot) -> DiagnosticResult {
        let name = "Device connection"
        if let device = openHelperConnection(snapshot) {
            let transport = device.transport == .usb ? "USB" : "Wi-Fi"
            let lane = snapshot.heldLocationLane.map { "lane \($0)" }
                ?? "lane reported once a location is applied"
            return DiagnosticResult(
                name: name,
                status: .success,
                message: "Open through the location helper over \(transport) (\(lane))",
                recoveryAction: nil
            )
        }
        if snapshot.tunnelState.isActive, let info = snapshot.tunnelInfo, info.exposesRSDEndpoint {
            return DiagnosticResult(
                name: name,
                status: .success,
                message: "Background daemon RSD endpoint \(info.rsdAddress):\(info.rsdPort)",
                recoveryAction: nil
            )
        }
        switch snapshot.tunnelState {
        case .error(let message):
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "Connection failed: \(message)",
                recoveryAction: "Choose Start Tunnel again"
            )
        case .starting:
            return DiagnosticResult(name: name, status: .warning, message: "Opening…", recoveryAction: nil)
        case .stopping:
            return DiagnosticResult(name: name, status: .warning, message: "Closing…", recoveryAction: nil)
        case .running where snapshot.selectedDevice != nil:
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "The open connection is not for the selected device",
                recoveryAction: "Select the connected device, or Start Tunnel for this one"
            )
        case .idle, .running:
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "No device connection is open",
                recoveryAction: "Choose Start Tunnel to open it"
            )
        }
    }

    private func checkDiskImage(_ snapshot: DiagnosticsSnapshot) async -> DiagnosticResult {
        let name = "Developer Disk Image"
        guard let device = openHelperConnection(snapshot) else {
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "Not checked: it is asked over an open device connection, and none is open",
                recoveryAction: nil
            )
        }
        switch await diskImageStatus(device.id, device.transport) {
        case .mounted:
            return DiagnosticResult(name: name, status: .success, message: "Mounted", recoveryAction: nil)
        case .notMounted:
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "Not mounted. A location change does not apply until it is mounted",
                recoveryAction: "PathChanger mounts it before the next location change; keep the phone unlocked"
            )
        case .unavailable(let detail):
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "Could not check: \(LogRedaction.redactingDeviceIdentifiers(detail))",
                recoveryAction: nil
            )
        }
    }

    private func checkUsbmux(_ snapshot: DiagnosticsSnapshot) async -> DiagnosticResult {
        let name = "usbmux"
        var listed: [String: Set<String>] = [:]
        for (arguments, label) in [(Self.usbmuxListUSBArguments, "USB"), (Self.usbmuxListNetworkArguments, "Network")] {
            let result = await runner.run(executable: snapshot.pythonPath, arguments: arguments)
            guard result.succeeded else {
                return DiagnosticResult(
                    name: name,
                    status: .failure,
                    message: "Asking usbmuxd for its \(label) device list \(result.failureDescription ?? "failed").",
                    recoveryAction: nil
                )
            }
            guard let identifiers = Self.usbmuxIdentifiers(result.output) else {
                return DiagnosticResult(
                    name: name,
                    status: .warning,
                    message: "The \(label) device list could not be read",
                    recoveryAction: nil
                )
            }
            for id in identifiers { listed[id, default: []].insert(label) }
        }
        if let id = snapshot.selectedDevice?.id, let types = listed[id], !types.isEmpty {
            return DiagnosticResult(
                name: name,
                status: .success,
                message: "Lists the selected phone over \(types.sorted().joined(separator: " and "))",
                recoveryAction: nil
            )
        }
        let wifiNote = "Over Wi-Fi the location helper can still reach the phone through remote pairing."
        if listed.isEmpty {
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "usbmuxd lists no device. \(wifiNote)",
                recoveryAction: nil
            )
        }
        return DiagnosticResult(
            name: name,
            status: .warning,
            message: "usbmuxd lists \(listed.count) device(s), not the selected phone. \(wifiNote)",
            recoveryAction: nil
        )
    }

    private func checkSelectedDevice(_ snapshot: DiagnosticsSnapshot) -> DiagnosticResult {
        let name = "Device Selected"
        guard let device = snapshot.selectedDevice else {
            return DiagnosticResult(
                name: name,
                status: .failure,
                message: "No device selected",
                recoveryAction: "Select a device from the sidebar"
            )
        }
        let version = device.productVersion.map { " (iOS \($0))" } ?? ""
        return DiagnosticResult(name: name, status: .success, message: "\(device.displayName)\(version)", recoveryAction: nil)
    }

    private func checkTargetLocation(_ snapshot: DiagnosticsSnapshot) -> DiagnosticResult {
        let name = "Target Location"
        guard let coordinate = snapshot.desiredCoordinate else {
            return DiagnosticResult(
                name: name,
                status: .warning,
                message: "No target location set",
                recoveryAction: "Search for a location or click on the map"
            )
        }
        return DiagnosticResult(
            name: name,
            status: .success,
            message: String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude),
            recoveryAction: nil
        )
    }

    // MARK: - Parsing

    nonisolated static func decodeCapabilityReport(_ output: String) -> PythonPathResolver.Pymobiledevice3CapabilityReport? {
        // The report is the last JSON line; a warning may precede it.
        for line in output.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let report = try? JSONDecoder().decode(
                    PythonPathResolver.Pymobiledevice3CapabilityReport.self,
                    from: Data(trimmed.utf8)
                  ) else { continue }
            return report
        }
        return nil
    }

    /// The device identifiers in `usbmux list --simple` output (a JSON array of strings).
    /// Nil when the output holds no readable JSON array.
    nonisolated static func usbmuxIdentifiers(_ output: String) -> [String]? {
        guard let start = output.firstIndex(of: "["),
              let end = output.lastIndex(of: "]"),
              start <= end,
              let items = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [Any] else {
            return nil
        }
        return items.compactMap { $0 as? String }
    }
}
