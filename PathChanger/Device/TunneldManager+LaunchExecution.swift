//
//  TunneldManager+LaunchExecution.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func attemptStart(mode: TunnelMode) async -> Bool {
        // Ensure log directory exists; actual log open is O_NOFOLLOW as root (Wave 0.1 / A03).
        ensureLogDirectoryExists()
        guard PrivilegedPathSecurity.isShellSafeSingleQuotedPath(logFilePath) else {
            Logger.error("SECURITY: Tunnel log path is unsafe for shell embedding", category: .security)
            lastError = "Secure log path is unsafe for privileged shell embedding"
            return false
        }
        switch PrivilegedPathSecurity.validatePrivilegedLogParentDirectory(forFile: logFilePath) {
        case .failure(let error):
            Logger.error(
                "SECURITY: Tunnel log parent rejected - \(error.localizedDescription)",
                category: .security
            )
            lastError = "Secure log preparation failed: \(error.localizedDescription)"
            return false
        case .success:
            break
        }

        // Wave 0.1 / A07: same interpreter for pin check and elevation (prefer resolver path).
        guard let privilegedPython = PrivilegedPathSecurity.resolvePrivilegedPythonPath(
            preferredUserPath: python3Path
        ) else {
            let message = """
            No acceptable Python 3 interpreter with pinned pymobiledevice3 \(PythonPathResolver.pinnedPymobiledevice3Version) \
            is available for privileged tunnel start. Install the pin on your Python \
            (\(PythonPathResolver.pinnedInstallCommand)), not via unconstrained pip -U. Pyenv is not allowed for elevation.
            """
            Logger.error("SECURITY: \(message)", category: .security)
            lastError = message
            return false
        }
        if privilegedPython != python3Path {
            Logger.info(
                "Using privileged Python \(privilegedPython) (pinned) instead of default resolver path \(python3Path)",
                category: .security
            )
        }

        var moduleArguments: [String] = ["-m", "pymobiledevice3"]
        switch mode {
        case .usb:
            moduleArguments += ["lockdown", "start-tunnel", "--script-mode"]
        case .wifi:
            moduleArguments += ["remote", "start-tunnel", "-t", "wifi", "--protocol", "tcp"]
        case .daemon:
            moduleArguments += ["remote", "tunneld"]
        case .auto:
            return false // Should not reach here
        }
        if let udid = targetTunnelUDID {
            moduleArguments += ["--udid", udid]
        }

        // Legacy pattern allowlist validates a flattened command shape (no shell redirect).
        let shapeCommand = ([privilegedPython] + moduleArguments).joined(separator: " ")
        switch PrivilegedCommandValidator.validate(command: shapeCommand, pythonPath: privilegedPython) {
        case .success:
            break
        case .failure(let error):
            Logger.error("SECURITY: Blocked privileged command - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }
        switch PrivilegedPathSecurity.validatePrivilegedCommandValues(shapeCommand) {
        case .success:
            Logger.info("Security validation passed for \(mode.rawValue) tunnel command", category: .security)
        case .failure(let error):
            Logger.error("SECURITY: Blocked privileged command values - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }

        // Wave 0.1 / A03: O_NOFOLLOW log open inside elevated process (no shell `>` after dialog).
        let privilegedCommand: String
        switch PrivilegedPathSecurity.buildPrivilegedBackgroundTunnelCommand(
            privilegedPython: privilegedPython,
            logPath: logFilePath,
            moduleArguments: moduleArguments
        ) {
        case .success(let cmd):
            privilegedCommand = cmd
        case .failure(let error):
            Logger.error("SECURITY: Failed to build privileged launch - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }

        let launchTargetUDID = targetTunnelUDID
        let beforeLaunchPids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: launchTargetUDID))
        let generation = tunnelLifecycleGeneration
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = launchTargetUDID
        logStartupTrace("wrapper_launch_prepared", fields: [
            "mode": mode.rawValue,
            "targetUDID": launchTargetUDID ?? "nil",
            "beforeLaunchPids": beforeLaunchPids.sorted(),
            "privilegedPython": privilegedPython
        ])

        let script = """
        do shell script "\(privilegedCommand)" with administrator privileges
        """

        let wrapperTimeout = wrapperReturnTimeout(for: mode)
        let wrapperResult = await executePrivilegedWrapper(script: script, timeout: wrapperTimeout)

        switch wrapperResult {
        case .returned(let wrapperOutput, let wrapperReturnTime):
            let handedOffPid = parseHandedOffPid(from: wrapperOutput)
            logStartupTrace("wrapper_returned", fields: [
                "mode": mode.rawValue,
                "targetUDID": launchTargetUDID ?? "nil",
                "wrapperReturnTime": wrapperReturnTime,
                "wrapperStdout": wrapperOutput,
                "handedOffPid": handedOffPid as Any
            ])
            if let info = await waitForAuthoritativeStartup(
                mode: mode,
                targetUDID: launchTargetUDID,
                beforeLaunchPids: beforeLaunchPids,
                generation: generation,
                handedOffPid: handedOffPid
            ) {
                tunnelInfo = info
                return true
            }

            await checkLogForErrors(mode: mode)
            if lastError == nil {
                lastError = "Failed to acquire authoritative \(mode.rawValue) tunnel child and RSD readiness before timeout."
            }
            return false

        case .failed(let message):
            lastError = message
            statusMessage = message
            return false

        case .timedOut:
            finalizeWrapperReturnTimeout(
                mode: mode,
                targetUDID: launchTargetUDID,
                beforeLaunchPids: beforeLaunchPids,
                generation: generation,
                timeout: wrapperTimeout
            )
            return false
        }
    }

    func executePrivilegedWrapper(script: String, timeout: TimeInterval) async -> PrivilegedWrapperExecutionResult {
#if DEBUG
        let debugRunner = debugPrivilegedWrapperRunner
#endif
        return await withCheckedContinuation { continuation in
            let state = PrivilegedWrapperContinuation(continuation: continuation)

            DispatchQueue.global().async {
#if DEBUG
                if let debugRunner {
                    state.resume(debugRunner(script))
                    return
                }
#endif
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    state.resume(.failed(message: "Failed to create AppleScript"))
                    return
                }

                let resultDescriptor = appleScript.executeAndReturnError(&error)
                let wrapperReturnTime = Date().timeIntervalSince1970

                if let error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    if !errorMessage.contains("cancel") {
                        state.resume(.failed(message: "Failed to start tunnel: \(errorMessage)"))
                    } else {
                        state.resume(.failed(message: "Administrator access required"))
                    }
                    return
                }

                state.resume(.returned(
                    output: resultDescriptor.stringValue ?? "",
                    returnTime: wrapperReturnTime
                ))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                state.resume(.timedOut)
            }
        }
    }

    /// Check log file for specific error messages
    func checkLogForErrors(mode: TunnelMode) async {
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return
        }

        // pmd3 9.x has TWO wireless-tunnel paths and they have different OS
        // requirements:
        //
        //   (A) `remote start-tunnel -t wifi`  (Tunnel Mode = WiFi)
        //       Uses the `_remotepairing-manual-pairing._tcp` Bonjour flow and
        //       a `~/.pymobiledevice3/remote_<UDID>.plist` record. iOS 17 and
        //       18 advertise that service when wireless pairing is toggled,
        //       BUT iOS 26.x stops advertising it and only emits
        //       `_remotepairing._tcp` (paired) + `_remoted._tcp` (NCM). On
        //       those builds path (A) cannot complete.
        //
        //   (B) `remote tunneld`              (Tunnel Mode = Background Daemon)
        //       Uses the `_remoted._tcp` channel + Apple's `remoted`
        //       suspension. Works on iOS 26.x because it reuses the active
        //       lockdown trust record instead of a separate remote pair record.
        //
        // So: when WiFi mode fails, the most likely cause is iOS 26+. We tell
        // the user about the daemon fallback first, and only mention pair_wifi.py
        // for iOS 17/18 setups where it still works.
        let wifiPairingGuidance = """
        Wi-Fi tunnel could not start.

        On iOS 26 and later, switch the Tunnel Mode picker to "Background
        Daemon". That mode uses Apple's `_remoted` channel and reuses the
        existing pair record — no separate Wi-Fi pairing step required.

        On iOS 17 / 18 you can use Wi-Fi mode directly, but the iPhone has to
        be advertising `_remotepairing-manual-pairing._tcp` first:
          1. Unlock the iPhone and put it on the SAME Wi-Fi as this Mac.
          2. Settings → Privacy & Security → Developer Mode must be ON.
          3. Settings → Developer → toggle "Pair Wirelessly" / "Wireless
             Pairing" / "Allow Mac" OFF, then back ON.
          4. While that toggle is fresh (~30s window), in Terminal:
               sudo python3 \(scriptsDirectoryPath)/pair_wifi.py --timeout 30
          5. Confirm the pairing prompt on the iPhone, then retry Wi-Fi mode.
        """

        if mode == .wifi && (
            logContent.contains("No devices were found during bonjour browse") ||
            logContent.contains("No remotepairing devices")
        ) {
            lastError = wifiPairingGuidance
            return
        }

        if logContent.contains("Device is not connected") {
            if mode == .wifi {
                lastError = wifiPairingGuidance
            } else {
                lastError = "Device is not connected. Connect and trust the iPhone, then retry."
            }
        } else if logContent.contains("No device connected") || logContent.contains("DeviceNotFoundError") {
            lastError = mode == .wifi
                ? wifiPairingGuidance
                : "No device found. Connect the device via USB, unlock it, and tap Trust."
        } else if logContent.contains("not paired") || logContent.contains("PairingError") {
            lastError = mode == .wifi
                ? wifiPairingGuidance
                : "Device not paired. Unlock the device, trust this computer over USB."
        } else if logContent.contains("Developer Mode") {
            lastError = "Developer Mode required. Enable in Settings > Privacy & Security."
        } else if logContent.contains("timeout") || logContent.contains("timed out") {
            lastError = "Connection timed out. Keep the device awake, verify both devices are on the same Wi-Fi, and retry."
        }
    }

    /// Best-effort path to the bundled scripts directory, used in error messages so we can
    /// tell the user where pair_wifi.py lives in their app bundle.
    var scriptsDirectoryPath: String {
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL.appendingPathComponent("scripts", isDirectory: true).path
        }
        return "<PathChanger.app>/Contents/Resources/scripts"
    }

    /// Allow only paths that are safe to embed inside `do shell script "..." with
    /// administrator privileges` after single-quoting. Disallows apostrophes,
    /// shell metacharacters, AppleScript-quoting characters, and embedded newlines.
    func isShellSafePath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let bad: Set<Character> = ["'", "\\", "\"", "`", "$", ";", "|", "&", "\n", "\r", "<", ">"]
        return !path.contains(where: { bad.contains($0) })
    }

    /// Resolve the absolute on-disk path of `pair_wifi.py`, walking from the app bundle's
    /// Resources/scripts/ first and then the SwiftPM dev workspace as a fallback for
    /// `swift run` builds. Returns nil if the script can't be found.
    func resolvePairWiFiScriptPath() -> String? {
        let fileManager = FileManager.default

        // 1. Bundled in PathChanger.app/Contents/Resources/scripts/pair_wifi.py
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("scripts/pair_wifi.py").path
            if fileManager.isReadableFile(atPath: bundled) {
                return bundled
            }
        }

        // 2. Dev / repo layout: <repo>/scripts/pair_wifi.py — useful when running
        //    via `swift run` from a clone.
        let cwdScript = fileManager.currentDirectoryPath + "/scripts/pair_wifi.py"
        if fileManager.isReadableFile(atPath: cwdScript) {
            return cwdScript
        }

        return nil
    }

    // MARK: - Public WiFi Pairing API

    /// Probe the local network for iPhones that are advertising the
    /// `_remotepairing._tcp` Bonjour service via `pmd3 remote browse`. Updates
    /// `bonjourVisibleUDIDs` so the UI can show "iPhone visible over Bonjour: X"
    /// before the user attempts a WiFi tunnel start.
    ///
    /// This is the preflight check that surfaces the silent failure mode users
    /// would otherwise hit: if no iPhone advertises Bonjour, WiFi tunnel start
    /// will fail no matter what (Bug 2/3 fixes don't help if there's nothing
    /// to discover).
    func probeBonjourWiFiDevices() async {
        bonjourProbeInProgress = true
        defer { bonjourProbeInProgress = false }

        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color",
                "remote", "browse",
                "--timeout", "5"
            ], timeout: 8.0)

            let candidates = extractWiFiUDIDsFromRemoteBrowseOutput(output)
            bonjourVisibleUDIDs = candidates
            Logger.info("[Tunnel] Bonjour probe found \(candidates.count) WiFi-discoverable device(s)", category: .device)
        } catch {
            bonjourVisibleUDIDs = []
            Logger.debug("[Tunnel] Bonjour probe failed: \(error.localizedDescription)", category: .device)
        }
    }

    /// Run the bundled `scripts/pair_wifi.py` helper with administrator
    /// privileges. Drives a longer (default 30s) Bonjour browse window than
    /// `pmd3 remote pair` and pairs **exactly one** device (PC-F-001).
    ///
    /// Selection (implemented in `pair_wifi.py`, fail closed):
    /// - 1 advertising device and no filter → pair that device
    /// - 2+ devices without a unique `--name` → script error (does not pair all)
    /// - `nameFilter` exact or unique substring match → pair that one device
    ///
    /// This is the iOS-side prerequisite for legacy WiFi mode. After this runs,
    /// the pair record is on disk and `pmd3 remote start-tunnel -t wifi` can
    /// connect without the user touching Terminal.
    ///
    /// - Parameters:
    ///   - timeout: Bonjour browse window in seconds (default 30).
    ///   - nameFilter: Exact Bonjour name or unique substring; required when
    ///     multiple devices are advertising. Prefer the selected device name.
    func pairOverWiFi(timeout: TimeInterval = 30.0, nameFilter: String? = nil) async -> WiFiPairingResult {
        guard !wifiPairingInProgress else {
            return .scriptError("WiFi pairing is already in progress.")
        }

        // Wave 0.1 / A07: same pinned interpreter as tunnel elevation.
        guard let privilegedPython = PrivilegedPathSecurity.resolvePrivilegedPythonPath(
            preferredUserPath: python3Path
        ) else {
            let message = "Refusing to run pair_wifi.py: no acceptable Python with pinned pymobiledevice3 \(PythonPathResolver.pinnedPymobiledevice3Version)."
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        guard let scriptPath = resolvePairWiFiScriptPath() else {
            let message = "pair_wifi.py was not found in the app bundle (expected at \(scriptsDirectoryPath)/pair_wifi.py)."
            Logger.error(message, category: .device)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptMissing
            return .scriptMissing
        }

        // Wave 0.1 / A08: bundle Resources path + owner self/root + not group/other-writable
        // (no uid-0 requirement — drag-drop install.sh remains usable).
        if let scriptError = PrivilegedPathSecurity.validatePrivilegedPairScriptPath(scriptPath) {
            let message = "Refusing to run pair_wifi.py: \(scriptError.localizedDescription)"
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }
        guard isShellSafePath(scriptPath),
              isShellSafePath(privilegedPython),
              PrivilegedPathSecurity.shellSingleQuotedPath(scriptPath) != nil,
              PrivilegedPathSecurity.shellSingleQuotedPath(privilegedPython) != nil else {
            let message = "Refusing to run pair_wifi.py: resolved path is unsafe for shell embedding (\(scriptPath))."
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        // Clamp the timeout to a sane window. Anything outside [5, 120] is a UI bug.
        let timeoutSec = max(5, min(120, Int(timeout.rounded())))

        wifiPairingInProgress = true
        wifiPairingLog = ""
        statusMessage = "Pairing over Wi-Fi (browsing Bonjour for up to \(timeoutSec)s)…"
        defer { wifiPairingInProgress = false }

        ensureLogDirectoryExists()
        let logFile = pairWiFiLogFilePath
        guard PrivilegedPathSecurity.isShellSafeSingleQuotedPath(logFile) else {
            let message = "Refusing to run pair_wifi.py: log path is unsafe for shell embedding."
            Logger.error(message, category: .security)
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }
        switch PrivilegedPathSecurity.validatePrivilegedLogParentDirectory(forFile: logFile) {
        case .failure(let error):
            let message = "Refusing to run pair_wifi.py: secure log parent rejected (\(error.localizedDescription))."
            Logger.error(message, category: .security)
            wifiPairingLog = message
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        case .success:
            break
        }

        var extraArguments = ["--timeout", "\(timeoutSec)"]
        if let nameFilter, !nameFilter.isEmpty,
           nameFilter.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }) {
            // nameFilter may contain spaces — encode as single argv only if no spaces,
            // otherwise reject (shell-unsafe for our builder). Prefer underscore form.
            if nameFilter.contains(" ") {
                let message = "Refusing to run pair_wifi.py: device name filter must not contain spaces for privileged embedding."
                Logger.error(message, category: .security)
                lastWiFiPairingResult = .scriptError(message)
                return .scriptError(message)
            }
            extraArguments += ["--name", nameFilter]
        }

        let inner: String
        switch PrivilegedPathSecurity.buildPrivilegedForegroundPairCommand(
            privilegedPython: privilegedPython,
            scriptPath: scriptPath,
            logPath: logFile,
            extraArguments: extraArguments
        ) {
        case .success(let cmd):
            inner = cmd
        case .failure(let error):
            let message = "Refusing to run pair_wifi.py: \(error.localizedDescription)"
            Logger.error(message, category: .security)
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        let script = """
        do shell script "\(inner)" with administrator privileges
        """

        let outcome: WiFiPairingResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var asError: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: .scriptError("Could not create AppleScript wrapper"))
                    return
                }
                _ = appleScript.executeAndReturnError(&asError)

                // Read the log file regardless of error so we can show the user
                // the script's own diagnostic output.
                let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
                let truncated = logContent.count > 8000 ? String(logContent.suffix(8000)) : logContent

                if let asError {
                    let errorMessage = asError[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    if errorMessage.lowercased().contains("cancel") {
                        Task { @MainActor in self.wifiPairingLog = truncated }
                        continuation.resume(returning: .userCancelled)
                    } else {
                        Task { @MainActor in self.wifiPairingLog = truncated }
                        continuation.resume(returning: .scriptError(errorMessage))
                    }
                    return
                }

                Task { @MainActor in self.wifiPairingLog = truncated }

                if logContent.contains("Pair record written") {
                    // PC-F-001: script pairs exactly one device even if browse found more.
                    let pairedOne = logContent.contains("Selected single device")
                    var browseCount = 0
                    for line in logContent.components(separatedBy: .newlines) where line.hasPrefix("[pair-wifi] Found ") {
                        let parts = line.split(separator: " ")
                        if parts.count > 2, let n = Int(parts[2]) {
                            browseCount = n
                            break
                        }
                    }
                    continuation.resume(returning: .success(deviceCount: pairedOne ? 1 : max(browseCount, 1)))
                } else if logContent.contains("multiple devices found; refusing to pair all") {
                    continuation.resume(returning: .scriptError(
                        "Multiple devices are advertising. Select one device in PathChanger or re-run with a unique device name."
                    ))
                } else if logContent.contains("no device matched --name") {
                    continuation.resume(returning: .scriptError(
                        "No advertising device matched the selected name. Check the iPhone Bonjour name or selection."
                    ))
                } else if logContent.contains("no _remotepairing-manual-pairing instances found") {
                    continuation.resume(returning: .noDevicesFound)
                } else {
                    continuation.resume(returning: .scriptError("pair_wifi.py exited without writing a pair record. See log for details."))
                }
            }
        }

        await MainActor.run { self.lastWiFiPairingResult = outcome }

        switch outcome {
        case .success(let count):
            statusMessage = "Wi-Fi pairing succeeded (\(count) device(s))."
        case .noDevicesFound:
            statusMessage = "Wi-Fi pairing failed: no iPhone advertising _remotepairing-manual-pairing on this network."
        case .scriptError(let message):
            statusMessage = "Wi-Fi pairing failed: \(message)"
        case .userCancelled:
            statusMessage = "Wi-Fi pairing cancelled."
        case .scriptMissing:
            statusMessage = "Wi-Fi pairing helper script not found in app bundle."
        }

        return outcome
    }

    /// Parse RSD address and port from tunnel log
}
