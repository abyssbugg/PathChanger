//
//  CompanionConnectionService.swift
//  PathChangerCompanion
//
//  MultipeerConnectivity service for iPhone companion communication
//

import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Companion Message

/// Messages exchanged between Mac app and iPhone companion
enum CompanionMessage: Codable {
    case status(SpoofingStatus)
    case emergencyStop
    case ping
    case pong
    case locationUpdate(latitude: Double, longitude: Double)
    case connectionState(isConnected: Bool)
}

/// Current spoofing status from Mac app
struct SpoofingStatus: Codable {
    var isActive: Bool
    var isPaused: Bool
    var currentLatitude: Double?
    var currentLongitude: Double?
    var targetLatitude: Double?
    var targetLongitude: Double?
    var deviceName: String?
    var mode: String
    var speed: String
    var routeProgress: Double?
}

// MARK: - Companion Connection Service

/// Handles MultipeerConnectivity for iPhone companion app
@MainActor
class CompanionConnectionService: NSObject, ObservableObject {
    // MARK: Published State
    @Published var isConnected: Bool = false
    @Published var isPeerDiscoveryActive: Bool = false
    @Published var connectedPeerName: String?
    @Published var status: SpoofingStatus?
    @Published var lastError: String?
    @Published var discoveredPeers: [MCPeerID] = []
    
    // MARK: MultipeerConnectivity
    private var peerID: MCPeerID
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    
    private let serviceType = "locspoof-comp" // Max 15 chars, alphanumeric and hyphen
    
    // MARK: Initialization
    
    override init() {
        #if os(iOS)
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        self.peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #endif
        super.init()
    }
    
    // MARK: Connection Management
    
    func start() {
        // Create session
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Start browsing for peers (Mac app)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        // Also advertise for incoming connections
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        isPeerDiscoveryActive = true
    }
    
    func stop() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        
        browser = nil
        advertiser = nil
        session = nil
        
        isPeerDiscoveryActive = false
        isConnected = false
        connectedPeerName = nil
        discoveredPeers = []
    }
    
    func connectToPeer(_ peer: MCPeerID) {
        guard let session = session, let browser = browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }
    
    // MARK: Message Sending
    
    func sendEmergencyStop() {
        send(message: .emergencyStop)
    }
    
    func sendPing() {
        send(message: .ping)
    }
    
    private func send(message: CompanionMessage) {
        guard let session = session, !session.connectedPeers.isEmpty else {
            lastError = "Not connected to any peer"
            return
        }
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    // MARK: Message Receiving
    
    private func handleReceivedMessage(_ message: CompanionMessage, from peer: MCPeerID) {
        switch message {
        case .status(let spoofingStatus):
            self.status = spoofingStatus
            
        case .ping:
            send(message: .pong)
            
        case .pong:
            // Connection alive
            break
            
        case .locationUpdate(let lat, let lon):
            if var currentStatus = status {
                currentStatus.currentLatitude = lat
                currentStatus.currentLongitude = lon
                self.status = currentStatus
            }
            
        case .connectionState(let connected):
            if !connected {
                self.status = nil
            }
            
        case .emergencyStop:
            // Mac app acknowledging stop
            if var currentStatus = status {
                currentStatus.isActive = false
                self.status = currentStatus
            }
        }
    }
}

// MARK: - MCSession Delegate

extension CompanionConnectionService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                isConnected = true
                connectedPeerName = peerID.displayName
                
            case .notConnected:
                if connectedPeerName == peerID.displayName {
                    isConnected = false
                    connectedPeerName = nil
                    status = nil
                }
                
            case .connecting:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(CompanionMessage.self, from: data)
            Task { @MainActor in
                handleReceivedMessage(message, from: peerID)
            }
        } catch {
            Task { @MainActor in
                lastError = "Failed to decode message: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowser Delegate

extension CompanionConnectionService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !discoveredPeers.contains(peerID) {
                discoveredPeers.append(peerID)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredPeers.removeAll { $0 == peerID }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            lastError = "Failed to start browsing: \(error.localizedDescription)"
            isPeerDiscoveryActive = false
        }
    }
}

// MARK: - MCNearbyServiceAdvertiser Delegate

extension CompanionConnectionService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from Mac app
        Task { @MainActor in
            invitationHandler(true, session)
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            lastError = "Failed to start advertising: \(error.localizedDescription)"
        }
    }
}
