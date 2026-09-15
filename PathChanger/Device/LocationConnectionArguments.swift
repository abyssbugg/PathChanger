//
//  LocationConnectionArguments.swift
//  PathChanger
//
//  How to talk to DVT after a tunnel is up.
//  lockdown/wifi start-tunnel → --rsd HOST PORT
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
