//
//  TunneldManager+RSDResolution.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func parseRsdInfo() async {
        guard canAcceptRsdInfo else {
            invalidateRsdInfo(reason: "Ignoring RSD parse outside active startup/running lifecycle")
            return
        }
        let mode = activeMode ?? stateMachine.currentContext.activeMode
        guard mode != nil else { return }

        do {
            // Give log file time to be written
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard canAcceptRsdInfo else {
                invalidateRsdInfo(reason: "Tunnel lifecycle changed before RSD parse completed")
                return
            }

            let logContent = try String(contentsOfFile: logFilePath, encoding: .utf8)

            // Try multiple parsing strategies in order of preference
            var rsdAddress: String?
            var rsdPort: Int?
            var interface: String?

            // Strategy 1: Parse iOS 27 script-mode output: "HOST PORT"
            (rsdAddress, rsdPort) = parseScriptModeRsdLine(from: logContent)

            // Strategy 2: Parse "--rsd" hint line (legacy reliable format)
            if rsdAddress == nil || rsdPort == nil {
                (rsdAddress, rsdPort) = parseRsdHintLine(from: logContent)
            }

            // Strategy 3: Parse from structured log lines
            if rsdAddress == nil || rsdPort == nil {
                (rsdAddress, rsdPort, interface) = parseStructuredLogLines(from: logContent)
            }
            // Strategy 4: Parse from JSON output if available
            if rsdAddress == nil || rsdPort == nil {
                if let result = try? parseJsonOutput(from: logContent) {
                    rsdAddress = result.address
                    rsdPort = result.port
                    interface = result.interface
                }
            }

            // Validate parsed values
            if let address = rsdAddress, isValidRsdAddress(address), let port = rsdPort, isValidRsdPort(port) {
                guard canAcceptRsdInfo else {
                    invalidateRsdInfo(reason: "Tunnel lifecycle changed before parsed RSD could be published")
                    return
                }
                // Get process ID from state machine context
                let processId = stateMachine.currentContext.activeProcessIds.first
                let tunnelMode = mode ?? .auto

                tunnelInfo = TunnelInfo(
                    rsdAddress: address,
                    rsdPort: port,
                    mode: tunnelMode,
                    interface: interface,
                    processId: processId
                )
                Logger.info("✅ Parsed tunnel info: \(address):\(port) (PID: \(processId?.description ?? "unknown"))", category: .device)
            } else if mode == .daemon {
                // Daemon mode sources the live RSD from the tunneld HTTP API
                // (queryTunneldAPI below), not the uvicorn log. The log having
                // no parseable RSD line is expected here, so this is a normal
                // debug note rather than an error — avoids spurious
                // "Failed to parse RSD from log" noise that previously looked
                // like a connectivity failure.
                Logger.debug("Daemon mode: RSD not in tunnel log; sourcing from tunneld API", category: .device)
            } else {
                Logger.error("⚠️ Failed to parse valid RSD address/port from log", category: .device)
                if let address = rsdAddress {
                    Logger.debug("  Parsed address '\(address)' - validation: \(isValidRsdAddress(address) ? "valid" : "invalid")", category: .device)
                }
                if let port = rsdPort {
                    Logger.debug("  Parsed port \(port) - validation: \(isValidRsdPort(port) ? "valid" : "invalid")", category: .device)
                }
            }

            // Also query the tunneld HTTP API for per-device RSD info. In daemon
            // mode this is the authoritative source for the current per-device
            // RSD (which rotates as the daemon re-creates tunnels).
            await queryTunneldAPI()
        } catch {
            Logger.debug("Could not read tunnel log: \(error.localizedDescription)", category: .device)
            // Still try the HTTP API even if log parsing fails
            await queryTunneldAPI()
        }
    }

    /// Parse RSD info from `pymobiledevice3 lockdown start-tunnel --script-mode`.
    ///
    /// iOS 27 live testing showed script mode emits a bare line such as:
    /// `fd14:d8b0:f31e::1 52064`
    /// or, for IPv4 transports:
    /// `192.168.1.50 52064`
    func parseScriptModeRsdLine(from content: String) -> (address: String?, port: Int?) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let tokens = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)

            guard tokens.count == 2 else {
                continue
            }

            let address = tokens[0]
            guard isValidRsdAddress(address),
                  let port = Int(tokens[1]),
                  isValidRsdPort(port) else {
                continue
            }

            Logger.debug("📍 Parsed RSD from script-mode output: \(address):\(port)", category: .device)
            return (address, port)
        }
        return (nil, nil)
    }

    /// Parse RSD info from "--rsd" hint line (most reliable format)
    func parseRsdHintLine(from content: String) -> (address: String?, port: Int?) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("--rsd") {
                let parts = line.components(separatedBy: .whitespaces)
                if let rsdIndex = parts.firstIndex(of: "--rsd"),
                   rsdIndex + 2 < parts.count {
                    let address = parts[rsdIndex + 1]
                    if let port = Int(parts[rsdIndex + 2]) {
                        Logger.debug("📍 Parsed RSD from hint line: \(address):\(port)", category: .device)
                        return (address, port)
                    }
                }
            }
        }
        return (nil, nil)
    }

    /// Parse RSD info from structured log lines
    func parseStructuredLogLines(from content: String) -> (address: String?, port: Int?, interface: String?) {
        let lines = content.components(separatedBy: .newlines)
        var rsdAddress: String?
        var rsdPort: Int?
        var interface: String?

        for line in lines {
            // Parse Interface
            if line.contains("Interface:") && interface == nil {
                let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    interface = parts[1]
                }
            }

            // Parse RSD Address (multiple formats supported)
            if (line.contains("RSD Address:") || line.contains("address:")) && rsdAddress == nil {
                let parts = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespaces)
                let addressCandidates = parts.components(separatedBy: .whitespaces)
                for candidate in addressCandidates {
                    if isValidRsdAddress(candidate) {
                        rsdAddress = candidate
                        Logger.debug("📍 Parsed RSD address from log: \(candidate)", category: .device)
                        break
                    }
                }
            }

            // Parse RSD Port (multiple formats supported)
            if (line.contains("RSD Port:") || line.contains("port:") || line.contains("Port:")) && rsdPort == nil {
                let parts = line.components(separatedBy: .whitespaces)
                // Look from the end backwards for a valid port number
                for part in parts.reversed() {
                    let cleanPart = part.trimmingCharacters(in: .punctuationCharacters)
                    if let port = Int(cleanPart), isValidRsdPort(port) {
                        rsdPort = port
                        Logger.debug("📍 Parsed RSD port from log: \(port)", category: .device)
                        break
                    }
                }
            }

            // Early exit if we found both
            if rsdAddress != nil && rsdPort != nil {
                break
            }
        }

        return (rsdAddress, rsdPort, interface)
    }

    /// Parse RSD info from JSON output if available
    func parseJsonOutput(from content: String) throws -> (address: String?, port: Int?, interface: String?) {
        // Try to find and parse JSON in the log
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).starts(with: "{") {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    if let rsdAddress = json["rsd-address"] as? String,
                       let rsdPort = json["rsd-port"] as? Int {
                        let interface = json["interface"] as? String
                        Logger.debug("📍 Parsed RSD from JSON output", category: .device)
                        return (rsdAddress, rsdPort, interface)
                    }
                }
            }
        }
        return (nil, nil, nil)
    }

    /// Validate RSD address format (IPv4, IPv6, or localhost)
    func isValidRsdAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        // Check for localhost variations
        if trimmed == "localhost" || trimmed == "127.0.0.1" || trimmed == "::1" {
            return true
        }
        return ArgumentSanitizer.isValidRsdAddress(trimmed)
    }

    /// Validate RSD port range (1-65535)
    func isValidRsdPort(_ port: Int) -> Bool {
        return port > 0 && port <= 65535
    }

    /// Resolve the first usable port from a tunneld API entry, preferring native
    /// numeric values over their string representations across all keys.
    ///
    /// Written as an explicit search rather than a chain of `as? Int ?? Int(... as? String ?? "")`
    /// coalescing operators: that form mixes optional casts and failable `Int` inits across six
    /// terms, which exceeds the Swift type checker's expression budget and fails the release
    /// build with "unable to type-check this expression in reasonable time".
    nonisolated static func firstPort(in entry: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = entry[key] as? Int {
                return value
            }
        }
        for key in keys {
            if let text = entry[key] as? String, let value = Int(text) {
                return value
            }
        }
        return nil
    }

    /// Query the tunneld HTTP API to get RSD info for all connected devices
    /// API returns: {"UDID": [{"tunnel-address": "...", "tunnel-port": ..., "interface": "..."}], ...}
    func queryTunneldAPI() async {
        guard canAcceptRsdInfo else {
            invalidateRsdInfo(reason: "Ignoring tunneld API RSD outside active startup/running lifecycle")
            return
        }
        guard let url = URL(string: tunneldAPIEndpoint) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard canAcceptRsdInfo else {
                invalidateRsdInfo(reason: "Tunnel lifecycle changed before tunneld API RSD could be published")
                return
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] {
                var updatedInfo = deviceTunnelInfo

                for (udid, entries) in json {
                    guard isSafeUDID(udid), let entry = entries.first else { continue }

                    let address = entry["tunnel-address"] as? String ??
                        entry["rsd-address"] as? String ??
                        entry["address"] as? String
                    let port = Self.firstPort(in: entry, keys: ["tunnel-port", "rsd-port", "port"])
                    let interface = entry["interface"] as? String

                    guard let address,
                          isValidRsdAddress(address),
                          let port,
                          isValidRsdPort(port) else {
                        continue
                    }

                    updatedInfo[udid] = TunnelInfo(
                        rsdAddress: address,
                        rsdPort: port,
                        mode: activeMode ?? stateMachine.currentContext.activeMode ?? .auto,
                        interface: interface,
                        processId: stateMachine.currentContext.activeProcessIds.first
                    )
                }

                deviceTunnelInfo = updatedInfo
                Logger.debug("📍 Successfully queried tunneld API for \(updatedInfo.count) device tunnel(s)", category: .device)
            }
        } catch {
            Logger.debug("Could not query tunneld API: \(error.localizedDescription)", category: .device)
        }
    }

    /// Get RSD info for a specific device by UDID
    /// Returns nil if no tunnel info is available for this device
    func getRsdInfo(for deviceId: String) -> TunnelInfo? {
        guard canServeRsdInfo else {
            invalidateRsdInfo(reason: "RSD requested while tunnel state is \(stateMachine.currentState)")
            return nil
        }
        // First check per-device cache
        if let info = deviceTunnelInfo[deviceId], isUsableTunnelInfo(info) {
            return info
        }

        // Fall back to legacy single tunnel info
        if let tunnelInfo, isUsableTunnelInfo(tunnelInfo) {
            return tunnelInfo
        }

        invalidateRsdInfo(reason: "No usable live RSD exists for device \(deviceId)")
        return nil
    }

    /// Recover RSD info from the tunnel log when an existing lockdown tunnel was detected.
    func recoverRsdInfoFromLog() -> TunnelInfo? {
        guard canRecoverRsdInfoFromLog else {
            return nil
        }
#if DEBUG
        if debugRecoveredRsdInfoFromLogOverrideEnabled {
            return debugRecoveredRsdInfoFromLogOverride
        }
        if !debugLiveProcessIdsOverrides.isEmpty || !debugLiveProcessIdsSequenceOverrides.isEmpty {
            return nil
        }
#endif
        guard let logContent = try? String(contentsOfFile: logFilePath, encoding: .utf8) else {
            return nil
        }

        var rsdAddress: String?
        var rsdPort: Int?
        var interface: String?

        (rsdAddress, rsdPort) = parseScriptModeRsdLine(from: logContent)

        if rsdAddress == nil || rsdPort == nil {
            (rsdAddress, rsdPort) = parseRsdHintLine(from: logContent)
        }

        if rsdAddress == nil || rsdPort == nil {
            (rsdAddress, rsdPort, interface) = parseStructuredLogLines(from: logContent)
        }

        if rsdAddress == nil || rsdPort == nil,
           let jsonResult = try? parseJsonOutput(from: logContent) {
            rsdAddress = jsonResult.address
            rsdPort = jsonResult.port
            interface = jsonResult.interface
        }

        guard let address = rsdAddress,
              isValidRsdAddress(address),
              let port = rsdPort,
              isValidRsdPort(port) else {
            return nil
        }

        let info = TunnelInfo(
            rsdAddress: address,
            rsdPort: port,
            mode: activeMode ?? stateMachine.currentContext.activeMode ?? .usb,
            interface: interface,
            processId: stateMachine.currentContext.activeProcessIds.first
        )
        Logger.info("Recovered tunnel RSD info from log: \(address):\(port)", category: .device)
        return info
    }

    /// Refresh device RSD info from tunneld API
    func refreshDeviceRsdInfo() async {
        await queryTunneldAPI()
    }
}
