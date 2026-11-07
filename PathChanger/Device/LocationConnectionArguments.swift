//
//  LocationConnectionArguments.swift
//  PathChanger
//
//  How to talk to DVT after a tunnel is up.
//  directly reachable (usbmux USB/Network) → --udid UDID (pymobiledevice3 self-tunnels)
//  an external RSD endpoint recorded for the device → --rsd HOST PORT
//  (the remote tunneld daemon's --tunnel UDID was removed with daemon mode, 2026-11-06)
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
        rsdAddress: String?,
        rsdPort: Int?
    ) -> [String] {
        // The helper's in-process connection is never exposed, so USB/Wi-Fi use --udid
        // unless an external RSD endpoint is recorded.
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
            endpointClass: arguments.first == "--rsd" ? .remoteServiceDiscovery : .direct
        )
    }

    static func describe(
        deviceId: String,
        physicalTransport: LocationTransport,
        rsdAddress: String?,
        rsdPort: Int?
    ) -> LocationConnectionDescriptor {
        let arguments = make(
            deviceId: deviceId,
            rsdAddress: rsdAddress,
            rsdPort: rsdPort
        )
        return classify(arguments: arguments, physicalTransport: physicalTransport)
    }
}
