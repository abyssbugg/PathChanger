//
//  TunnelInfo.swift
//  PathChanger
//

import Foundation

// MARK: - Tunnel Info

/// Tunnel connection info (RSD address for device communication)
struct TunnelInfo: Equatable {
    let rsdAddress: String
    let rsdPort: Int
    let mode: TunnelMode
    let interface: String?
    let processId: Int32?

    var connectionString: String {
        "--rsd \(rsdAddress) \(rsdPort)"
    }
}

