//
//  TunneldManager+ModeSelection.swift
//  PathChanger
//

import Foundation
import Combine
import AppKit

@MainActor
extension TunneldManager {
    func deviceConnectionAvailability() async -> DeviceConnectionAvailability {
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color", "usbmux", "list"
            ], timeout: 8.0)

            guard let jsonStart = output.firstIndex(of: "["),
                  let jsonEnd = output.lastIndex(of: "]"),
                  let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
                  let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return DeviceConnectionAvailability(usbUDID: nil, networkUDID: nil, wifiBrowseUDID: nil)
            }

            var usbUDID: String?
            var networkUDID: String?

            for item in jsonArray {
                guard let udid = item["UniqueDeviceID"] as? String ?? item["Identifier"] as? String,
                      isSafeUDID(udid),
                      let connectionType = item["ConnectionType"] as? String else {
                    continue
                }

                if connectionType.lowercased().contains("usb"), usbUDID == nil {
                    usbUDID = udid
                } else if connectionType.lowercased().contains("network"), networkUDID == nil {
                    networkUDID = udid
                }
            }

            // BUG FIX (WiFi-Bug-2): Always run Bonjour browse when the user actually
            // wants WiFi (preferredMode == .wifi or .auto). Previously this was gated on
            // BOTH usbUDID AND networkUDID being nil, which meant a single stale
            // ConnectionType: Network entry left in usbmux from any prior USB-with-WiFi-sync
            // pairing would silently skip Bonjour discovery, leaving Bug 3's wrong-UDID
            // fallback as the only path. We still skip the (~3-5s) browse for explicit
            // .usb / .daemon modes since they don't need it.
            let needsWifiBrowse = preferredMode == .wifi || preferredMode == .auto
            let wifiBrowseUDID: String?
            if needsWifiBrowse {
                wifiBrowseUDID = await discoverNetworkUDIDViaRemoteBrowse(preferredUDID: targetTunnelUDID)
            } else {
                wifiBrowseUDID = nil
            }

            return DeviceConnectionAvailability(usbUDID: usbUDID, networkUDID: networkUDID, wifiBrowseUDID: wifiBrowseUDID)
        } catch {
            // usbmux failed entirely — fall through to Bonjour browse only if WiFi/auto.
            let wifiBrowseUDID: String?
            if preferredMode == .wifi || preferredMode == .auto {
                wifiBrowseUDID = await discoverNetworkUDIDViaRemoteBrowse(preferredUDID: targetTunnelUDID)
            } else {
                wifiBrowseUDID = nil
            }
            return DeviceConnectionAvailability(usbUDID: nil, networkUDID: nil, wifiBrowseUDID: wifiBrowseUDID)
        }
    }

    func isSafeUDID(_ value: String) -> Bool {
        let pattern = #"^[A-Fa-f0-9-]{16,64}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    func discoverNetworkUDIDViaRemoteBrowse(preferredUDID: String?) async -> String? {
        // BUG FIX (WiFi-Bonjour-Timeout): the prior 3-second `remote browse`
        // window was empirically too short on real networks — a live capture
        // showed `pmd3 remote browse --timeout 5` returning `{"usb":[],"wifi":[]}`
        // while `--timeout 15` found the iPhone immediately. Bumping to 8s
        // gives the responder time to multicast on slow Wi-Fi (and increasing
        // the outer Swift-side timeout to 12s so the subprocess has headroom
        // to flush JSON output before we kill it).
        do {
            let output = try await runCommand(python3Path, arguments: [
                "-m", "pymobiledevice3", "--no-color",
                "remote", "browse",
                "--timeout", "8"
            ], timeout: 12.0)

            let candidates = extractWiFiUDIDsFromRemoteBrowseOutput(output)
            if let preferredUDID, candidates.contains(preferredUDID) {
                return preferredUDID
            }
            return candidates.first
        } catch {
            return nil
        }
    }

    func extractWiFiUDIDsFromRemoteBrowseOutput(_ output: String) -> [String] {
        guard let jsonStart = output.firstIndex(of: "{"),
              let jsonEnd = output.lastIndex(of: "}"),
              let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json.keys.contains("wifi") || json.keys.contains("usb") else {
            return extractSafeUDIDs(from: output)
        }

        guard let wifiValue = json["wifi"],
              let wifiData = try? JSONSerialization.data(withJSONObject: wifiValue),
              let wifiString = String(data: wifiData, encoding: .utf8) else {
            return []
        }

        return extractSafeUDIDs(from: wifiString)
    }

    func extractSafeUDIDs(from text: String) -> [String] {
        let pattern = #"[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}|[A-Fa-f0-9]{40}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        var results: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let value = String(text[matchRange])
            if isSafeUDID(value), !results.contains(value) {
                results.append(value)
            }
        }

        return results
    }

    /// Detect which tunnel mode is currently running
    func detectRunningTunnel() async -> TunnelMode? {
        for mode in [TunnelMode.usb, .wifi, .daemon] {
            // First prefer strict, lifecycle-safe validation.
            let validatedPids = await liveTunnelProcessIds(for: mode, targetUDID: targetTunnelUDID)
            if !validatedPids.isEmpty {
                return mode
            }

            // Fallback for external-process truth mirroring: detect matching
            // pmd3 tunnel patterns even when the process was not launched by
            // this app (or when tests emulate process table entries).
            // This path is read-only and does not grant process ownership.
            let observedPids = await liveProcessIds(matching: mode.processPattern)
            if !observedPids.isEmpty {
                return mode
            }
        }
        return nil
    }

    /// Public probe that returns the currently-running tunnel mode (USB / WiFi /
    /// Daemon), or nil if no pmd3 tunnel process is alive.
    ///
    /// BUG FIX (WiFi-Bug-2): exposes the same pgrep-based detection that the
    /// internal lifecycle uses, so AppState can stop routing tunnel-running
    /// truth through DeviceManager (which doesn't know about WiFi tunnels) and
    /// instead read directly from this single source.
    func detectRunningTunnelMode() async -> TunnelMode? {
        await detectRunningTunnel()
    }

    /// Repeatedly call `parseRsdInfo` until we have a non-loopback RSD address
    /// and a non-zero port, or the retry budget is exhausted.
    ///
    /// BUG FIX (WiFi-Bug-6): The first read of the tunnel log can race with
    /// pmd3 still flushing its banner output (especially for `remote start-tunnel`
    /// where the bonjour browse and TLS handshake add a couple of seconds before
    /// the `--rsd <addr> <port>` line lands). Retry up to ~5 seconds before
    /// giving up, instead of fabricating a 127.0.0.1:0 placeholder.
}
