//
//  LocationSessionState.swift
//  PathChanger
//
//  Created by Rovo Dev on 2026-09-12.
//

import Foundation

// MARK: - LocationMode

enum LocationMode: String, CaseIterable, Codable, Sendable {
    case teleport
    case jumpTeleport
    case twoSpot
    case multiSpot
    case joystick
}

// MARK: - LocationTransport

enum LocationTransport: String, Codable, Sendable {
    case usb
    case wifi
}

// MARK: - LocationEndpointClass

enum LocationEndpointClass: String, Codable, Sendable {
    case direct
    case remoteServiceDiscovery
}

// MARK: - LocationSessionIdentity

struct LocationSessionIdentity: Equatable, Sendable {
    let stableDeviceID: String
    let transport: LocationTransport
    let endpointClass: LocationEndpointClass
    let generation: UInt64
}

// MARK: - LocationInjectionOutcome

enum LocationInjectionOutcome: Equatable, Sendable {
    case applied
    case queued
    case failed(code: String)
}

// MARK: - LocationInjectionReceipt

struct LocationInjectionReceipt: Equatable, Sendable {
    let requestID: UUID
    let session: UUID
    let coordinate: LocationCoordinate
    let transport: LocationTransport
    let endpointClass: LocationEndpointClass
    let sessionGeneration: UInt64
    let completedAt: Date
    let outcome: LocationInjectionOutcome

    init(
        requestID: UUID,
        session: UUID,
        coordinate: LocationCoordinate,
        transport: LocationTransport = .usb,
        endpointClass: LocationEndpointClass = .direct,
        sessionGeneration: UInt64 = 1,
        completedAt: Date,
        outcome: LocationInjectionOutcome
    ) {
        self.requestID = requestID
        self.session = session
        self.coordinate = coordinate
        self.transport = transport
        self.endpointClass = endpointClass
        self.sessionGeneration = sessionGeneration
        self.completedAt = completedAt
        self.outcome = outcome
    }
}

// MARK: - LocationConnectionPhase

enum LocationConnectionPhase: Equatable, Sendable {
    case unavailable
    case ready(identity: LocationSessionIdentity)
    case reconnecting(previousGeneration: UInt64?, attempt: Int)
    case failed(String)
}

// MARK: - LocationApplicationPhase

enum LocationApplicationPhase: Equatable, Sendable {
    case idle
    case applying(requestID: UUID, coordinate: LocationCoordinate)
    case active(receipt: LocationInjectionReceipt)
    case uncertain(lastReceipt: LocationInjectionReceipt?, reason: String)
    case lost(String)
    case clearing
    case failed(String)
    
    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }
}

// MARK: - LocationMovementPhase

enum LocationMovementPhase: Equatable, Sendable {
    case idle
    case moving(LocationMode)
    case paused(LocationMode)
    case completed(LocationMode)
}

// MARK: - LocationSessionState

struct LocationSessionState: Equatable, Sendable {
    var desiredLocation: LocationCoordinate?
    var lastAcknowledgedReceipt: LocationInjectionReceipt?
    var connection: LocationConnectionPhase = .unavailable
    var application: LocationApplicationPhase = .idle
    var movement: LocationMovementPhase = .idle
}

// MARK: - LocationInjectionTarget

struct LocationInjectionTarget: Equatable, Sendable {
    let stableDeviceID: String
    let transport: LocationTransport
}

// MARK: - LocationApplicationRequest

struct LocationApplicationRequest: Equatable, Sendable {
    let id: UUID
    let target: LocationInjectionTarget
    let coordinate: LocationCoordinate
    let mode: LocationMode
}
