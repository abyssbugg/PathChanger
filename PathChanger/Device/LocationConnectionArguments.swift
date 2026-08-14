//
//  LocationConnectionArguments.swift
//  PathChanger
//
//  How to talk to DVT after a tunnel is up.
//  lockdown/wifi start-tunnel → --rsd HOST PORT
//  remote tunneld daemon     → --tunnel UDID
//

import Foundation

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
}
