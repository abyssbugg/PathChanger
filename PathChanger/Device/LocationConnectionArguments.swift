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
        rsdPort: Int?
    ) -> [String] {
        if isDaemonTunneld {
            return ["--tunnel", deviceId]
        }
        // Single tunnel owner (2026-11-01): a usable app tunnel (TunneldManager) is
        // the one channel for every DVT command, so GUI connection truth and the
        // injection lane can never diverge. The 2026-10-24 "DVT port refused"
        // finding that preferred `--udid` was confounded by an unmounted Developer
        // Disk Image. Without a tunnel, `--udid` lets pymobiledevice3 self-tunnel.
        if let rsdAddress, let rsdPort, rsdPort > 0, rsdPort <= 65535 {
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
        rsdPort: Int?
    ) -> LocationConnectionDescriptor {
        let arguments = make(
            deviceId: deviceId,
            isDaemonTunneld: isDaemonTunneld,
            rsdAddress: rsdAddress,
            rsdPort: rsdPort
        )
        return classify(arguments: arguments, physicalTransport: physicalTransport)
    }
}
