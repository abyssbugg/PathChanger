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
        let launchCommand: String
        let udidArgument = targetTunnelUDID.map { " --udid \($0)" } ?? ""

        switch mode {
        case .usb:
            launchCommand = "\(python3Path) -m pymobiledevice3 lockdown start-tunnel --script-mode\(udidArgument) > \(logFilePath) 2>&1 &"
        case .wifi:
            launchCommand = "\(python3Path) -m pymobiledevice3 remote start-tunnel -t wifi --protocol tcp\(udidArgument) > \(logFilePath) 2>&1 &"
        case .daemon:
            launchCommand = "\(python3Path) -m pymobiledevice3 remote tunneld > \(logFilePath) 2>&1 &"
        case .auto:
            return false // Should not reach here
        }
        let privilegedCommand = "\(launchCommand) echo $!"
        let launchTargetUDID = targetTunnelUDID
        let beforeLaunchPids = Set(liveTunnelProcessIdsSync(for: mode, targetUDID: launchTargetUDID))
        let generation = tunnelLifecycleGeneration
        lastTunnelModeForCleanup = mode
        lastTunnelTargetUDIDForCleanup = launchTargetUDID
        logStartupTrace("wrapper_launch_prepared", fields: [
            "mode": mode.rawValue,
            "targetUDID": launchTargetUDID ?? "nil",
            "beforeLaunchPids": beforeLaunchPids.sorted()
        ])

        // SECURITY: Validate the pmd3 launch command before adding the static
        // `$!` handoff suffix. The validator intentionally rejects `$`, so the
        // shell handoff wrapper remains hardcoded and is not user-influenced.
        switch PrivilegedCommandValidator.validate(command: launchCommand, pythonPath: python3Path) {
        case .success:
            Logger.info("Security validation passed for \(mode.rawValue) tunnel command", category: .security)
        case .failure(let error):
            Logger.error("SECURITY: Blocked privileged command - \(error.localizedDescription)", category: .security)
            lastError = "Security validation failed: \(error.localizedDescription)"
            return false
        }

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
    /// `pmd3 remote pair` and pairs the first discovered iPhone (or matches
    /// against `nameFilter` if provided).
    ///
    /// This is the iOS-side prerequisite for WiFi mode. After this runs, the
    /// pair record is on disk and `pmd3 remote start-tunnel -t wifi` can
    /// connect without the user touching Terminal.
    ///
    /// - Parameters:
    ///   - timeout: Bonjour browse window in seconds (default 30).
    ///   - nameFilter: Optional substring to match the iPhone's Bonjour name.
    func pairOverWiFi(timeout: TimeInterval = 30.0, nameFilter: String? = nil) async -> WiFiPairingResult {
        guard !wifiPairingInProgress else {
            return .scriptError("WiFi pairing is already in progress.")
        }

        // SECURITY: validate python path against the same allowlist used for tunnel
        // launch commands so we can never call an attacker-controlled binary as root.
        guard PrivilegedCommandValidator.isPythonPathAllowed(python3Path) else {
            let message = "Refusing to run pair_wifi.py: python3 path is not in the security allowlist (\(python3Path))."
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

        // SECURITY: paths must end in the expected suffix and contain only safe
        // characters before we string-concat them into a shell command. This
        // closes the gap that PrivilegedCommandValidator can't (its allowlist is
        // for tunnel commands only).
        guard scriptPath.hasSuffix("/scripts/pair_wifi.py"),
              isShellSafePath(scriptPath),
              isShellSafePath(python3Path) else {
            let message = "Refusing to run pair_wifi.py: resolved path is unsafe (\(scriptPath))."
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

        // Build the inner command that runs as root via osascript. All
        // user-influenced segments are validated above; the only remaining
        // free-form input is `nameFilter` which is restricted to alnum/dash/
        // underscore/space. We single-quote inputs for the shell.
        let logFile = "\(NSTemporaryDirectory())pathchanger-pair-wifi.log"
        guard isShellSafePath(logFile) else {
            let message = "Refusing to run pair_wifi.py: temporary log path is unsafe."
            Logger.error(message, category: .security)
            lastWiFiPairingResult = .scriptError(message)
            return .scriptError(message)
        }

        var inner = "'\(python3Path)' '\(scriptPath)' --timeout \(timeoutSec)"
        if let nameFilter, !nameFilter.isEmpty,
           nameFilter.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " }) {
            inner += " --name '\(nameFilter)'"
        }
        inner += " > '\(logFile)' 2>&1"

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
                    // Count how many devices the script reported.
                    var deviceCount = 0
                    for line in logContent.components(separatedBy: .newlines) where line.hasPrefix("[pair-wifi] Found ") {
                        let parts = line.split(separator: " ")
                        if parts.count > 2, let n = Int(parts[2]) {
                            deviceCount = n
                            break
                        }
                    }
                    continuation.resume(returning: .success(deviceCount: max(deviceCount, 1)))
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
