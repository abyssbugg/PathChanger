//
//  CompanionHostService.swift
//  PathChanger
//
//  Host service for Mac app to communicate with iPhone companion
//

import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Companion Message (shared)

/// Messages exchanged between Mac app and iPhone companion
enum CompanionMessage: Codable {
    case status(SpoofingStatus)
    case emergencyStop
    case ping
    case pong
    case locationUpdate(latitude: Double, longitude: Double)
    case connectionState(isConnected: Bool)
}

/// Current spoofing status to send to companion
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

// MARK: - Companion Host Service

/// Mac-side service for companion app communication
@MainActor
class CompanionHostService: NSObject, ObservableObject {
    // MARK: Published State
    @Published var isRunning: Bool = false
    @Published var isCompanionConnected: Bool = false
    @Published var companionName: String?
    @Published var lastError: String?
    
    // MARK: Callbacks
    var onEmergencyStop: (() -> Void)?
    
    // MARK: MultipeerConnectivity
    private var peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private let serviceType = "locspoof-comp"
    
    // MARK: Status Update Timer
    private var statusUpdateTimer: Timer?
    private var currentStatus: SpoofingStatus?
    
    // MARK: Initialization
    
    override init() {
        self.peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        super.init()
    }
    
    // MARK: Service Management
    
    func start() {
        guard !isRunning else { return }
        
        // Create session
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Advertise as host
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        // Also browse for companions
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        isRunning = true
        
        // Start status update timer
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendStatusUpdate()
            }
        }
    }
    
    func stop() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
        
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        
        advertiser = nil
        browser = nil
        session = nil
        
        isRunning = false
        isCompanionConnected = false
        companionName = nil
    }
    
    // MARK: Status Updates
    
    func updateStatus(_ status: SpoofingStatus) {
        currentStatus = status
        if isCompanionConnected {
            send(message: .status(status))
        }
    }
    
    func sendLocationUpdate(latitude: Double, longitude: Double) {
        send(message: .locationUpdate(latitude: latitude, longitude: longitude))
    }
    
    private func sendStatusUpdate() {
        guard isCompanionConnected, let status = currentStatus else { return }
        send(message: .status(status))
    }
    
    // MARK: Message Sending
    
    private func send(message: CompanionMessage) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = "Failed to send: \(error.localizedDescription)"
        }
    }
    
    // MARK: Message Receiving
    
    private func handleReceivedMessage(_ message: CompanionMessage, from peer: MCPeerID) {
        switch message {
        case .emergencyStop:
            onEmergencyStop?()
            // Acknowledge
            send(message: .emergencyStop)
            
        case .ping:
            send(message: .pong)
            
        default:
            break
        }
    }
}

// MARK: - MCSession Delegate

extension CompanionHostService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                isCompanionConnected = true
                companionName = peerID.displayName
                // Send initial status
                if let status = currentStatus {
                    send(message: .status(status))
                }
                
            case .notConnected:
                if companionName == peerID.displayName {
                    isCompanionConnected = false
                    companionName = nil
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
                lastError = "Failed to decode: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiser Delegate

extension CompanionHostService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept invitations from companion
            invitationHandler(true, session)
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            lastError = "Advertise failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowser Delegate

extension CompanionHostService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // Auto-invite discovered companions
            guard let session = session else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            lastError = "Browse failed: \(error.localizedDescription)"
        }
    }
}
