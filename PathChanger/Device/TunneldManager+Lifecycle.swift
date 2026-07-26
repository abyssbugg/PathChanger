//
//  TunneldManager+Lifecycle.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func autoStart() async {
        // First check if any tunnel is already running
        if let runningMode = await detectRunningTunnel() {
            stateMachine.send(.externalTunnelDetected(mode: runningMode, info: recoverRsdInfoFromLog()))
            return
        }

        // Try to start tunnel with preferred mode
        await startTunnel()
    }

    /// Start tunnel with preferred mode (with auto-fallback)
    func startTunnel() async {
        await startTunnel(replaceStaleOnMissingRsd: false)
    }

    // swiftlint:disable:next cyclomatic_complexity -- tunnel startup arbitrates mode selection, stale-RSD replacement, and lifecycle guards in one place. Decomposing it touches the privileged path; deferred until the test suite has a green baseline.
    func startTunnel(replaceStaleOnMissingRsd: Bool) async {
        guard !tunnelStartInFlight else {
            Logger.debug("Ignoring duplicate tunnel start request while another start is in progress", category: .device)
            return
        }
        // Check state via state machine
        guard !stateMachine.isActive && !stateMachine.isTransitioning else {
            return
        }
        let generation = advanceTunnelLifecycleGeneration(cancelScheduledRestart: true)
        tunnelStartInFlight = true
        defer {
            tunnelStartInFlight = false
        }

        lastError = nil
        if await attachToRunningTunnelIfAvailable(
            generation: generation,
            replaceStaleOnMissingRsd: replaceStaleOnMissingRsd
        ) {
            return
        }
        guard isCurrentTunnelLifecycle(generation) else { return }

        let modesToTry: [TunnelMode]

        if preferredMode == .auto {
            let availability = await deviceConnectionAvailability()
            let useDaemonForModernWireless = TunnelMode.usesDaemonForModernWireless(
                requested: .auto,
                targetIOSMajorVersion: targetTunnelIOSMajorVersion,
                targetConnectionType: targetTunnelConnectionType
            )
            // Stability fix: on iOS 26+, back the auto path with the persistent
            // `remote tunneld` daemon even for USB-connected devices. A
            // per-session `lockdown start-tunnel` child dies when the device
            // sleeps/locks or the RSD drops, which forces a fresh
            // admin-prompted restart and surfaces "Tunnel Required". The daemon
            // stays alive, auto-recreates per-device tunnels, and exposes the
            // current RSD over its local HTTP API, so recovery is a prompt-free
            // API re-query. Resolve the target UDID first so the daemon can
            // attach to the connected device.
            let prefersPersistentDaemon = TunnelMode.prefersPersistentDaemon(
                forAutoTargetIOSMajorVersion: targetTunnelIOSMajorVersion
            )
            if prefersPersistentDaemon {
                if targetTunnelUDID == nil {
                    targetTunnelUDID = availability.usbUDID ?? availability.networkUDID ?? availability.wifiBrowseUDID
                }
                statusMessage = "Using Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ tunneling."
                modesToTry = [.daemon]
            } else if let targetUDID = targetTunnelUDID, availability.usbUDID == targetUDID {
                modesToTry = [.usb]
            } else if let targetUDID = targetTunnelUDID,
                      availability.networkUDID == targetUDID,
                      targetTunnelConnectionType != .wifi {
                modesToTry = [.usb]
            } else if useDaemonForModernWireless {
                statusMessage = "Using Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ wireless tunneling."
                modesToTry = [.daemon]
            } else if let targetUDID = targetTunnelUDID,
                      availability.wifiBrowseUDID == targetUDID || targetTunnelConnectionType == .wifi {
                targetTunnelUDID = targetUDID
                modesToTry = [.wifi]
            } else if let usbUDID = availability.usbUDID {
                targetTunnelUDID = usbUDID
                modesToTry = [.usb]
            } else if let networkUDID = availability.networkUDID {
                targetTunnelUDID = networkUDID
                modesToTry = [.usb]
            } else if let wifiBrowseUDID = availability.wifiBrowseUDID {
                targetTunnelUDID = wifiBrowseUDID
                modesToTry = [.wifi]
            } else {
                let message = "No USB or same-Wi-Fi device detected. For Wi-Fi, keep the iPhone awake and unlocked on the same network, and trust/pair it with this Mac before retrying."
                lastError = message
                statusMessage = message
                Logger.error(message, category: .device)
                return
            }
        } else {
            // Specific mode requested
            let availability = await deviceConnectionAvailability()
            let requestedMode = preferredMode
            let effectiveMode = TunnelMode.effectiveMode(
                requested: requestedMode,
                targetIOSMajorVersion: targetTunnelIOSMajorVersion,
                targetConnectionType: targetTunnelConnectionType
            )

            if requestedMode == .wifi && effectiveMode == .daemon {
                statusMessage = "Using Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ wireless tunneling. WiFi Only requires legacy manual pairing."
                Logger.info("[Tunnel] Routing WiFi Only request to Background Daemon for iOS \(targetTunnelIOSMajorVersion ?? 26)+ target", category: .device)
            }

            switch effectiveMode {
            case .wifi:
                // BUG FIX (WiFi-Bug-3): Never fall back to availability.networkUDID for
                // WiFi mode. `pmd3 remote start-tunnel -t wifi --udid <X>` filters
                // across Bonjour-discovered devices; passing a usbmux network UDID will
                // never match and the command fails with "No devices were found during
                // bonjour browse". If wifiBrowseUDID is nil after Bug-2's fix, fail with
                // a clear actionable error instead of silently passing a wrong UDID.
                let resolved = targetTunnelUDID ?? availability.wifiBrowseUDID
                if resolved == nil {
                    let message = "No iPhone discovered over Bonjour. On the iPhone: open Settings → Developer and enable wireless pairing for this Mac, then retry. The Mac and iPhone must be on the same Wi-Fi network and the iPhone must be unlocked."
                    lastError = message
                    statusMessage = message
                    Logger.error("[Tunnel] WiFi mode requested but no Bonjour-discoverable iPhone was found", category: .device)
                    stateMachine.send(.errorOccurred(message))
                    return
                }
                targetTunnelUDID = resolved
            case .usb:
                if let targetUDID = targetTunnelUDID, availability.usbUDID == targetUDID {
                    targetTunnelUDID = targetUDID
                } else if let targetUDID = targetTunnelUDID, availability.networkUDID == targetUDID {
                    targetTunnelUDID = targetUDID
                } else {
                    targetTunnelUDID = availability.usbUDID ?? availability.networkUDID
                }
            case .daemon:
                targetTunnelUDID = nil
            case .auto:
                break
            }
            modesToTry = [effectiveMode]
        }
        guard isCurrentTunnelLifecycle(generation) else { return }

        for mode in modesToTry {
            Logger.info("Attempting tunnel mode: \(mode.rawValue)", category: .device)

            // Send start event to state machine
            stateMachine.send(.startRequested(mode: mode))

            let success = await attemptStart(mode: mode)
            guard isCurrentTunnelLifecycle(generation) else {
                if success {
                    killTrackedTunnelProcesses()
                }
                return
            }

            if success {
                // BUG FIX (WiFi-Bug-6): Don't fabricate a 127.0.0.1:0 TunnelInfo
                // when parseRsdInfo can't extract a real address. The old fallback
                // was indistinguishable from a real tunnel to downstream callers,
                // so every later device command would silently fail. Instead we
                // retry parseRsdInfo a few times (the log file is sometimes still
                // being written when we first read it) and only treat tunnel
                // setup as successful once we have a non-loopback / non-zero RSD.
                //
                // If after the retry budget we still can't parse a real address,
                // tear the tunnel down and surface a specific error rather than
                // pretending we have a working tunnel.
                if let info = await waitForValidRsdInfo(mode: mode) {
                    guard isCurrentTunnelLifecycle(generation) else { return }
                    stateMachine.send(.connectionEstablished(info: info))
                } else {
                    guard isCurrentTunnelLifecycle(generation) else { return }
                    let message = "Tunnel started but its RSD address could not be parsed from the tunnel log. The pmd3 output format may have changed; check ~/Library/Logs/PathChanger/tunnel.log and retry."
                    Logger.error("[Tunnel] \(message)", category: .device)
                    lastError = message
                    statusMessage = message
                    // Kill the tunnel process we just spawned — it's running but
                    // useless to us, and leaving it would block future starts.
                    killTrackedTunnelProcesses()
                    stateMachine.send(.errorOccurred(message))
                    return
                }
                return
            }
            if case .error = stateMachine.currentState {
                syncStateWithStateMachine()
                return
            }

            stateMachine.send(.errorOccurred(lastError ?? "Failed to start \(mode.rawValue) tunnel"))
            return
        }

        // All modes failed
        if stateMachine.currentState != .error("") {
            stateMachine.send(.errorOccurred(lastError ?? "Failed to start tunnel. Ensure device is connected and trusted."))
        }
    }

    /// Start tunnel with specific mode
    func startTunnel(mode: TunnelMode) async {
        let previousMode = preferredMode
        preferredMode = mode
        await startTunnel(replaceStaleOnMissingRsd: false)

        // Direct access via state machine
        let running = stateMachine.isActive

        if !running {
            preferredMode = previousMode
        }
    }

    /// Prefer this device for the next USB or Wi-Fi tunnel start.
    func setTargetDevice(_ device: Device?) {
        guard let device else {
            targetTunnelUDID = nil
            targetTunnelConnectionType = nil
            targetTunnelIOSMajorVersion = nil
            return
        }

        guard isSafeUDID(device.id) else {
            Logger.debug("Ignoring unsafe tunnel target UDID", category: .security)
            return
        }

        targetTunnelUDID = device.id
        targetTunnelConnectionType = device.connectionType
        targetTunnelIOSMajorVersion = device.iosMajorVersion
    }

    func recoverFromTransientTransportFailure(reason: String) async -> Bool {
        guard !tunnelStartInFlight else {
            Logger.debug("[Tunnel] Transient recovery skipped because a tunnel start is already in flight", category: .device)
            return false
        }

        let maxAttempts = 3
        let baseDelaySeconds: TimeInterval = 0.75
        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1
            statusMessage = "Recovering tunnel connection… (attempt \(attempt)/\(maxAttempts))"
            Logger.info("[Tunnel] Starting bounded transient recovery attempt \(attempt)/\(maxAttempts): \(reason)", category: .device)

            await startTunnel(replaceStaleOnMissingRsd: true)
            if isRunning {
                lastError = nil
                statusMessage = "Tunnel recovered"
                return true
            }

            guard attempt < maxAttempts else { break }
            let delay = baseDelaySeconds * pow(2.0, Double(attempt - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        statusMessage = "Tunnel recovery failed"
        Logger.error("[Tunnel] Transient recovery exhausted after \(maxAttempts) attempt(s): \(reason)", category: .device)
        return false
    }

    /// Schedule a stop+start when the user changes the preferred mode and a
    /// tunnel is currently running or starting. The previous mode is logged
    /// for diagnostics. If no tunnel is active this is a no-op.
    func scheduleTunnelRestartIfRunning(previousMode: TunnelMode) {
        guard stateMachine.isActive || stateMachine.isTransitioning else {
            Logger.debug("[Tunnel] preferredMode changed (\(previousMode.rawValue) -> \(preferredMode.rawValue)) - no active tunnel, will use new mode on next start", category: .device)
            return
        }

        Logger.info("[Tunnel] preferredMode changed (\(previousMode.rawValue) -> \(preferredMode.rawValue)) while active - restarting with new mode", category: .device)
        statusMessage = "Switching tunnel to \(preferredMode.rawValue)..."
        restartTask?.cancel()
        let generation = tunnelLifecycleGeneration
        restartTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(generation) else {
                return
            }

            self.stopTunnel(invalidateScheduledRestart: false)
            let restartGeneration = self.tunnelLifecycleGeneration
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms grace for processes to exit
            guard !Task.isCancelled,
                  self.isCurrentTunnelLifecycle(restartGeneration) else {
                return
            }

            self.restartTask = nil
            await self.startTunnel()
        }
    }

    /// Stop the tunnel
    func stopTunnel() {
        stopTunnel(invalidateScheduledRestart: true)
    }

    func stopTunnel(invalidateScheduledRestart: Bool) {
        stopTunnel(invalidateScheduledRestart: invalidateScheduledRestart, advanceGeneration: true)
    }

    func stopTunnel(invalidateScheduledRestart: Bool, advanceGeneration: Bool) {
        if advanceGeneration {
            _ = advanceTunnelLifecycleGeneration(cancelScheduledRestart: invalidateScheduledRestart)
        } else {
            cancelScheduledTunnelWork(cancelScheduledRestart: invalidateScheduledRestart)
        }
        // Send stop event to state machine
        stateMachine.send(.stopRequested)

        // Kill tracked tunnel processes (security hardened - PID-based only)
        killTrackedTunnelProcesses()
        cleanupTunnelProcessResources(terminateProcess: true)

        // Mark process as stopped
        stateMachine.send(.processStopped)
    }

    /// Restart tunnel
    func restartTunnel() async {
        stopTunnel(invalidateScheduledRestart: true)
        let generation = tunnelLifecycleGeneration
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms
        guard isCurrentTunnelLifecycle(generation) else { return }
        await startTunnel()
    }

    /// Check if USB device is connected
    func isUSBDeviceConnected() async -> Bool {
        let availability = await deviceConnectionAvailability()
        return availability.usbUDID != nil || availability.networkUDID != nil
    }

}
