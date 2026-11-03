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

extension LocationTransport {
    /// The value exchanged with `scripts/location_bridge.py`: Swift sends it as
    /// the request's `connection_type` (pymobiledevice3/usbmux vocabulary) and
    /// the helper echoes it back verbatim as `physical_transport` in
    /// `helper.json`. This is the single Swift<->Python transport mapping —
    /// the Swift raw values (`usb`/`wifi`) are NOT the wire vocabulary.
    var helperWireValue: String {
        switch self {
        case .usb: return "USB"
        case .wifi: return "Network"
        }
    }

    /// Parses a helper wire value. Case-insensitive; also accepts the Swift
    /// raw values so records written by older builds remain readable.
    init?(helperWireValue value: String) {
        switch value.lowercased() {
        case "usb": self = .usb
        case "network", "wifi": self = .wifi
        default: return nil
        }
    }
}

// MARK: - LocationEndpointClass

enum LocationEndpointClass: String, Codable, Sendable {
    case unresolved
    case direct
    case remoteServiceDiscovery
}

struct LocationDVTChannel: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    static let usbLockdown = Self(rawValue: "usbLockdown")
    static let networkLockdown = Self(rawValue: "networkLockdown")
    /// Direct usbmux lane (USB or Network visibility) — the proven primary
    /// injection lane on iOS 17+ (live 2026-10-31). Python emits this string.
    static let usbmuxDirect = Self(rawValue: "usbmuxDirect")
    static let explicitRSD = Self(rawValue: "explicitRSD")
    static let nativeRSD = Self(rawValue: "nativeRSD")
    static let userspaceRSD = Self(rawValue: "userspaceRSD")
    /// Helper lane 4: userspace tunnel over a mobdev2 (Bonjour, TCP) lockdown, used
    /// when usbmux lists no device (live 2026-11-01). Python emits this string.
    static let mobdev2RSD = Self(rawValue: "mobdev2RSD")
    /// Helper remote pairing lane: userspace tunnel over a RemotePairing service found
    /// by Bonjour at any Wi-Fi address, no usbmuxd (live read-only 2026-11-02). Python
    /// emits this string.
    static let remotePairingRSD = Self(rawValue: "remotePairingRSD")
    static let managedTunneldRSD = Self(rawValue: "managedTunneldRSD")

    var isSupported: Bool {
        Self.supportedChannels.contains(self)
    }

    /// The helper reaches the phone over Bonjour on this lane. Its link-local tunnel ends
    /// shortly after the app that launched the helper quits (live 2026-11-03: 0.85 s), so
    /// a location held on it does not survive Preserve and Quit.
    var endsWithTheLaunchingApp: Bool {
        self == .remotePairingRSD || self == .mobdev2RSD
    }

    var endpointClass: LocationEndpointClass? {
        switch self {
        case .usbLockdown, .networkLockdown, .usbmuxDirect:
            return .direct
        case .explicitRSD, .nativeRSD, .userspaceRSD, .mobdev2RSD, .remotePairingRSD, .managedTunneldRSD:
            return .remoteServiceDiscovery
        default:
            return nil
        }
    }

    private static let supportedChannels: Set<Self> = [
        .usbLockdown, .networkLockdown, .usbmuxDirect, .explicitRSD,
        .nativeRSD, .userspaceRSD, .mobdev2RSD, .remotePairingRSD, .managedTunneldRSD,
    ]

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct LocationProviderAcknowledgement: Equatable, Sendable {
    let requestID: UUID
    let sessionGeneration: UInt64
    let physicalTransport: LocationTransport
    let channel: LocationDVTChannel
    let endpointClass: LocationEndpointClass

    init?(
        requestID: UUID,
        sessionGeneration: UInt64,
        physicalTransport: LocationTransport,
        channel: LocationDVTChannel,
        endpointClass: LocationEndpointClass
    ) {
        guard channel.isSupported, channel.endpointClass == endpointClass else { return nil }
        self.requestID = requestID
        self.sessionGeneration = sessionGeneration
        self.physicalTransport = physicalTransport
        self.channel = channel
        self.endpointClass = endpointClass
    }
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
    let actualChannel: LocationDVTChannel?
    let endpointClass: LocationEndpointClass
    let sessionGeneration: UInt64
    let completedAt: Date
    let outcome: LocationInjectionOutcome

    init(
        requestID: UUID,
        session: UUID,
        coordinate: LocationCoordinate,
        transport: LocationTransport = .usb,
        actualChannel: LocationDVTChannel? = nil,
        endpointClass: LocationEndpointClass = .direct,
        sessionGeneration: UInt64 = 1,
        completedAt: Date,
        outcome: LocationInjectionOutcome
    ) {
        self.requestID = requestID
        self.session = session
        self.coordinate = coordinate
        self.transport = transport
        self.actualChannel = actualChannel
        self.endpointClass = endpointClass
        self.sessionGeneration = sessionGeneration
        self.completedAt = completedAt
        self.outcome = outcome
    }

    init(
        session: UUID,
        acknowledgedCoordinate: LocationCoordinate,
        acknowledgement: LocationProviderAcknowledgement,
        completedAt: Date,
        outcome: LocationInjectionOutcome
    ) {
        self.init(
            requestID: acknowledgement.requestID,
            session: session,
            coordinate: acknowledgedCoordinate,
            transport: acknowledgement.physicalTransport,
            actualChannel: acknowledgement.channel,
            endpointClass: acknowledgement.endpointClass,
            sessionGeneration: acknowledgement.sessionGeneration,
            completedAt: completedAt,
            outcome: outcome
        )
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

extension LocationConnectionPhase {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

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
    /// While `.applying`: the receipt that was active when this application began, i.e.
    /// the location still held on the device until the new receipt replaces it. Nil when
    /// the previous phase was not `.active` (a failed step, a loss, a first application):
    /// then nothing is known to be held (review 2026-11-01).
    var heldWhileApplying: LocationInjectionReceipt? = nil
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
    /// The coordinator's session generation when the request was made. The bridge
    /// never acknowledges on an older one: after a loss the coordinator moves ahead
    /// first, and a bridge left behind made every reapply "stale" (review 2026-11-01).
    var sessionGeneration: UInt64? = nil
}
