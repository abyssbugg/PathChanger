//
//  LocationConnectionArguments.swift
//  PathChanger
//
//  How to talk to DVT after a tunnel is up.
//  directly reachable (usbmux USB/Network) → --udid UDID (pymobiledevice3 self-tunnels)
//  not directly reachable + lockdown/wifi start-tunnel → --rsd HOST PORT
//  remote tunneld daemon     → --tunnel UDID
//

import Foundation

struct LocationConnectionDescriptor: Equatable, Sendable {
    let arguments: [String]
    let transport: LocationTransport
    let endpointClass: LocationEndpointClass
}

enum LocationConnectionArguments {
    static func make(
        deviceId: String,
        isDaemonTunneld: Bool,
        rsdAddress: String?,
        rsdPort: Int?,
        deviceDirectlyReachable: Bool = false
    ) -> [String] {
        if isDaemonTunneld {
            return ["--tunnel", deviceId]
        }
        // Directly-reachable devices (usbmux USB/Network visibility) always use the
        // direct `--udid` path: pymobiledevice3 self-tunnels developer commands on
        // iOS 17+ (no-root userspace fallback), while the native tunnel's RSD
        // endpoint refuses its allocated DVT service port on iOS 27.2 (verified
        // live 2026-10-24: RSD handshake OK, DVT port refused, --udid works).
        if !deviceDirectlyReachable,
           let rsdAddress, let rsdPort, rsdPort > 0, rsdPort <= 65535 {
            return ["--rsd", rsdAddress, String(rsdPort)]
        }
        return ["--udid", deviceId]
    }

    static func classify(
        arguments: [String],
        physicalTransport: LocationTransport
    ) -> LocationConnectionDescriptor {
        LocationConnectionDescriptor(
            arguments: arguments,
            transport: physicalTransport,
            endpointClass: ["--rsd", "--tunnel"].contains(arguments.first) ? .remoteServiceDiscovery : .direct
        )
    }

    static func describe(
        deviceId: String,
        physicalTransport: LocationTransport,
        isDaemonTunneld: Bool,
        rsdAddress: String?,
        rsdPort: Int?,
        deviceDirectlyReachable: Bool = false
    ) -> LocationConnectionDescriptor {
        let arguments = make(
            deviceId: deviceId,
            isDaemonTunneld: isDaemonTunneld,
            rsdAddress: rsdAddress,
            rsdPort: rsdPort,
            deviceDirectlyReachable: deviceDirectlyReachable
        )
        return classify(arguments: arguments, physicalTransport: physicalTransport)
    }
}
