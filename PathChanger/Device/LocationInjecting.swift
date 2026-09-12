//
//  LocationInjecting.swift
//  PathChanger
//
//  Created by Rovo Dev on 2026-09-12.
//

import Foundation

protocol LocationInjecting: Sendable {
    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt
    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws
}
