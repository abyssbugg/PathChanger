//
//  CloudSync.swift
//  PathChanger
//
//  Cloud synchronization infrastructure for routes and settings
//

import Foundation
import Combine

// MARK: - Cloud Sync Error

/// Errors that can occur during cloud sync operations
enum CloudSyncError: Error, LocalizedError {
    case notAuthenticated
    case networkUnavailable
    case syncFailed(Error)
    case conflictDetected(localVersion: Int, remoteVersion: Int)
    case rateLimited(retryAfter: TimeInterval)
    case quotaExceeded
    case invalidData
    case operationCancelled
    case unauthorized
    case resourceNotFound
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in to sync."
        case .networkUnavailable:
            return "Network unavailable. Changes will sync when online."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .conflictDetected(let local, let remote):
            return "Conflict detected: local v\(local), remote v\(remote)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(Int(retryAfter)) seconds."
        case .quotaExceeded:
            return "Cloud storage quota exceeded."
        case .invalidData:
            return "Invalid sync data received."
        case .operationCancelled:
            return "Sync operation was cancelled."
        case .unauthorized:
            return "Unauthorized. Please re-authenticate."
        case .resourceNotFound:
            return "Resource not found in cloud."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .rateLimited, .serverError:
            return true
        case .notAuthenticated, .conflictDetected, .quotaExceeded, .invalidData,
             .operationCancelled, .unauthorized, .resourceNotFound, .syncFailed:
            return false
        }
    }
}

// MARK: - Sync State

/// Current state of cloud sync
enum SyncState: Equatable {
    case idle
    case syncing
    case uploading(progress: Double)
    case downloading(progress: Double)
    case conflict
    case error(String)
    case offline
    
    var displayName: String {
        switch self {
        case .idle: return "Synced"
        case .syncing: return "Syncing..."
        case .uploading(let progress): return "Uploading \(Int(progress * 100))%"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .conflict: return "Conflict Detected"
        case .error(let msg): return "Error: \(msg)"
        case .offline: return "Offline"
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "checkmark.icloud"
        case .syncing, .uploading, .downloading: return "arrow.triangle.2.circlepath.icloud"
        case .conflict: return "exclamationmark.icloud"
        case .error: return "xmark.icloud"
        case .offline: return "icloud.slash"
        }
    }
}

// MARK: - Syncable Protocol

/// Protocol for items that can be synced to the cloud
protocol CloudSyncable: Identifiable, Codable {
    var id: UUID { get }
    var version: Int { get set }
    var lastModified: Date { get set }
    var isDeleted: Bool { get set }
}

// MARK: - Shareable Route

/// A route that can be shared with others
struct ShareableRoute: CloudSyncable, Equatable {
    let id: UUID
    var version: Int
    var lastModified: Date
    var isDeleted: Bool
    
    var name: String
    var description: String?
    var coordinates: [LocationCoordinate]
    var distance: Double
    var color: String
    var tags: [String]
    
    // Sharing metadata
    var ownerId: String
    var sharedWith: [SharePermission]
    var isPublic: Bool
    var shareCode: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        coordinates: [LocationCoordinate],
        color: String = "blue",
        tags: [String] = [],
        ownerId: String
    ) {
        self.id = id
        self.version = 1
        self.lastModified = Date()
        self.isDeleted = false
        self.name = name
        self.description = description
        self.coordinates = coordinates
        self.distance = Self.calculateDistance(coordinates)
        self.color = color
        self.tags = tags
        self.ownerId = ownerId
        self.sharedWith = []
        self.isPublic = false
        self.shareCode = nil
    }
    
    private static func calculateDistance(_ coords: [LocationCoordinate]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let from = coords[i-1]
            let to = coords[i]
            let R = 6371000.0
            let lat1 = from.latitude * .pi / 180
            let lat2 = to.latitude * .pi / 180
            let dLat = (to.latitude - from.latitude) * .pi / 180
            let dLon = (to.longitude - from.longitude) * .pi / 180
            let a = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
            let c = 2 * atan2(sqrt(a), sqrt(1-a))
            total += R * c
        }
        return total
    }
}

// MARK: - Share Permission

/// Permission level for a shared resource
struct SharePermission: Codable, Equatable, Identifiable {
    let id: UUID
    let userId: String
    let email: String
    let permission: PermissionLevel
    let grantedAt: Date
    var expiresAt: Date?
    
    enum PermissionLevel: String, Codable, CaseIterable {
        case viewer = "viewer"
        case editor = "editor"
        case admin = "admin"
        
        var displayName: String {
            switch self {
            case .viewer: return "Can view"
            case .editor: return "Can edit"
            case .admin: return "Full access"
            }
        }
        
        var canEdit: Bool {
            self == .editor || self == .admin
        }
        
        var canShare: Bool {
            self == .admin
        }
        
        var canDelete: Bool {
            self == .admin
        }
    }
    
    init(
        id: UUID = UUID(),
        userId: String,
        email: String,
        permission: PermissionLevel,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.email = email
        self.permission = permission
        self.grantedAt = Date()
        self.expiresAt = expiresAt
    }
}

// MARK: - Sync Settings

/// Settings for cloud sync behavior
struct CloudSyncSettings: Codable, Equatable {
    var isEnabled: Bool
    var syncOnWiFiOnly: Bool
    var autoSyncInterval: TimeInterval
    var conflictResolution: ConflictResolutionStrategy
    var maxStorageBytes: Int64
    
    enum ConflictResolutionStrategy: String, Codable, CaseIterable {
        case keepLocal = "keep_local"
        case keepRemote = "keep_remote"
        case keepBoth = "keep_both"
        case askUser = "ask_user"
        
        var displayName: String {
            switch self {
            case .keepLocal: return "Keep local version"
            case .keepRemote: return "Keep remote version"
            case .keepBoth: return "Keep both versions"
            case .askUser: return "Ask me each time"
            }
        }
    }
    
    static let `default` = CloudSyncSettings(
        isEnabled: false,
        syncOnWiFiOnly: false,
        autoSyncInterval: 300, // 5 minutes
        conflictResolution: .askUser,
        maxStorageBytes: 100 * 1024 * 1024 // 100 MB
    )
}

// MARK: - Sync Metadata

/// Metadata for tracking sync state
struct SyncMetadata: Codable {
    var lastSyncTime: Date?
    var lastSyncVersion: Int
    var pendingChanges: Int
    var conflictCount: Int
    var bytesUsed: Int64
    var bytesQuota: Int64
    
    var usagePercentage: Double {
        guard bytesQuota > 0 else { return 0 }
        return Double(bytesUsed) / Double(bytesQuota)
    }
    
    static let initial = SyncMetadata(
        lastSyncTime: nil,
        lastSyncVersion: 0,
        pendingChanges: 0,
        conflictCount: 0,
        bytesUsed: 0,
        bytesQuota: 100 * 1024 * 1024
    )
}

// MARK: - Conflict Resolution

/// Represents a sync conflict between local and remote data
struct SyncConflict<T: CloudSyncable>: Identifiable {
    let id: UUID
    let localItem: T
    let remoteItem: T
    let conflictType: ConflictType
    let detectedAt: Date
    
    enum ConflictType {
        case bothModified
        case localDeletedRemoteModified
        case remoteDeletedLocalModified
    }
    
    init(localItem: T, remoteItem: T, conflictType: ConflictType) {
        self.id = UUID()
        self.localItem = localItem
        self.remoteItem = remoteItem
        self.conflictType = conflictType
        self.detectedAt = Date()
    }
}

// MARK: - Cloud Sync Manager

/// Manages cloud synchronization for routes and settings
@MainActor
class CloudSyncManager: ObservableObject {
    
    // MARK: Published State
    @Published var syncState: SyncState = .idle
    @Published var settings: CloudSyncSettings = .default
    @Published var metadata: SyncMetadata = .initial
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: CloudUser?
    @Published var pendingConflicts: [SyncConflict<ShareableRoute>] = []
    
    // MARK: Singleton
    static let shared = CloudSyncManager()
    
    // MARK: Private
    private var syncTask: Task<Void, Never>?
    private var autoSyncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let pendingChangesQueue = DispatchQueue(label: "com.pathchanger.sync.pending", qos: .utility)
    
    // Offline queue for pending changes
    private var pendingOperations: [PendingOperation] = []
    
    // MARK: Initialization
    
    private init() {
        loadSettings()
        loadMetadata()
        setupAutoSync()
    }
    
    // MARK: - Authentication
    
    /// Authenticate with cloud service
    func authenticate(email: String, password: String) async throws {
        syncState = .syncing
        
        // Simulate authentication delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // In a real implementation, this would call an auth API
        currentUser = CloudUser(
            id: UUID().uuidString,
            email: email,
            displayName: email.components(separatedBy: "@").first ?? "User",
            avatarURL: nil
        )
        isAuthenticated = true
        syncState = .idle
        
        // Start initial sync after authentication
        await performSync()
    }
    
    /// Sign out from cloud service
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        syncState = .idle
        pendingOperations.removeAll()
    }
    
    // MARK: - Sync Operations
    
    /// Perform a full sync with the cloud
    func performSync() async {
        guard isAuthenticated else {
            syncState = .error("Not authenticated")
            return
        }
        
        guard await checkNetworkAvailability() else {
            syncState = .offline
            return
        }
        
        syncState = .syncing
        
        do {
            // Process pending offline operations first
            try await processPendingOperations()
            
            // Download remote changes
            syncState = .downloading(progress: 0.3)
            try await downloadRemoteChanges()
            
            // Upload local changes
            syncState = .uploading(progress: 0.7)
            try await uploadLocalChanges()
            
            // Update metadata
            metadata.lastSyncTime = Date()
            metadata.pendingChanges = 0
            saveMetadata()
            
            syncState = .idle
            
            Logger.info("Cloud sync completed successfully", category: .network)
        } catch {
            let errorMessage = (error as? CloudSyncError)?.errorDescription ?? error.localizedDescription
            syncState = .error(errorMessage)
            Logger.error("Cloud sync failed", category: .network, metadata: LogMetadata(additionalInfo: ["error": errorMessage]))
        }
    }
    
    /// Queue a local change for sync
    func queueChange<T: CloudSyncable>(_ item: T, operation: OperationType) {
        let pending = PendingOperation(
            id: UUID(),
            itemId: item.id.uuidString,
            itemType: String(describing: T.self),
            operation: operation,
            timestamp: Date(),
            data: try? JSONEncoder().encode(item)
        )
        
        pendingChangesQueue.sync {
            pendingOperations.append(pending)
        }
        
        metadata.pendingChanges = pendingOperations.count
        saveMetadata()
        
        // Trigger sync if auto-sync is enabled
        if settings.isEnabled {
            Task {
                await performSync()
            }
        }
    }
    
    // MARK: - Sharing
    
    /// Share a route with another user
    func shareRoute(_ route: ShareableRoute, with email: String, permission: SharePermission.PermissionLevel) async throws -> ShareableRoute {
        guard isAuthenticated else {
            throw CloudSyncError.notAuthenticated
        }
        
        var updatedRoute = route
        let newPermission = SharePermission(
            userId: UUID().uuidString, // In real impl, lookup user by email
            email: email,
            permission: permission
        )
        
        updatedRoute.sharedWith.append(newPermission)
        updatedRoute.version += 1
        updatedRoute.lastModified = Date()
        
        queueChange(updatedRoute, operation: .update)
        
        Logger.info("Route shared", category: .network, metadata: LogMetadata(additionalInfo: [
            "route": route.name,
            "sharedWith": email,
            "permission": permission.rawValue
        ]))
        
        return updatedRoute
    }
    
    /// Generate a shareable link for a route
    func generateShareLink(for route: ShareableRoute) async throws -> URL {
        guard isAuthenticated else {
            throw CloudSyncError.notAuthenticated
        }
        
        var updatedRoute = route
        
        // Generate unique share code if not exists
        if updatedRoute.shareCode == nil {
            updatedRoute.shareCode = generateShareCode()
        }
        
        updatedRoute.isPublic = true
        updatedRoute.version += 1
        updatedRoute.lastModified = Date()
        
        queueChange(updatedRoute, operation: .update)
        
        // In real implementation, this would be a server URL
        let shareURL = URL(string: "pathchanger://share/\(updatedRoute.shareCode ?? "")")!
        
        return shareURL
    }
    
    /// Import a route from a share link
    func importFromShareLink(_ url: URL) async throws -> ShareableRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let shareCode = components.path.components(separatedBy: "/").last else {
            throw CloudSyncError.invalidData
        }
        
        // In real implementation, this would fetch from server
        Logger.info("Importing route from share code", category: .network, metadata: LogMetadata(additionalInfo: ["code": shareCode]))
        
        // Placeholder - would return fetched route
        return nil
    }
    
    /// Revoke sharing for a user
    func revokeShare(_ route: ShareableRoute, userId: String) async throws -> ShareableRoute {
        guard isAuthenticated else {
            throw CloudSyncError.notAuthenticated
        }
        
        var updatedRoute = route
        updatedRoute.sharedWith.removeAll { $0.userId == userId }
        updatedRoute.version += 1
        updatedRoute.lastModified = Date()
        
        queueChange(updatedRoute, operation: .update)
        
        return updatedRoute
    }
    
    // MARK: - Conflict Resolution
    
    /// Resolve a sync conflict
    func resolveConflict(_ conflict: SyncConflict<ShareableRoute>, resolution: CloudSyncSettings.ConflictResolutionStrategy) async throws {
        switch resolution {
        case .keepLocal:
            var updated = conflict.localItem
            updated.version = max(conflict.localItem.version, conflict.remoteItem.version) + 1
            queueChange(updated, operation: .update)
            
        case .keepRemote:
            // Remote version is already in cloud, just update local
            // In real implementation, update local storage
            break
            
        case .keepBoth:
            var localCopy = conflict.localItem
            localCopy.name = "\(localCopy.name) (Local)"
            localCopy.version = max(conflict.localItem.version, conflict.remoteItem.version) + 1
            queueChange(localCopy, operation: .create)
            
        case .askUser:
            // Keep in pending conflicts for user decision
            return
        }
        
        pendingConflicts.removeAll { $0.id == conflict.id }
        metadata.conflictCount = pendingConflicts.count
        saveMetadata()
    }
    
    // MARK: - Settings
    
    /// Update sync settings
    func updateSettings(_ newSettings: CloudSyncSettings) {
        settings = newSettings
        saveSettings()
        setupAutoSync()
    }
    
    // MARK: - Private Methods
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "CloudSyncSettings"),
           let decoded = try? JSONDecoder().decode(CloudSyncSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "CloudSyncSettings")
        }
    }
    
    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: "SyncMetadata"),
           let decoded = try? JSONDecoder().decode(SyncMetadata.self, from: data) {
            metadata = decoded
        }
    }
    
    private func saveMetadata() {
        if let encoded = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(encoded, forKey: "SyncMetadata")
        }
    }
    
    private func setupAutoSync() {
        autoSyncTimer?.invalidate()
        
        guard settings.isEnabled && settings.autoSyncInterval > 0 else { return }
        
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: settings.autoSyncInterval, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                await strongSelf.performSync()
            }
        }
    }
    
    private func checkNetworkAvailability() async -> Bool {
        // In real implementation, check network reachability
        return true
    }
    
    private func processPendingOperations() async throws {
        var remaining: [PendingOperation] = []
        
        for operation in pendingOperations {
            do {
                // In real implementation, send to server
                try await Task.sleep(nanoseconds: 10_000_000) // Simulate API call
            } catch {
                remaining.append(operation)
            }
        }
        
        pendingChangesQueue.sync {
            pendingOperations = remaining
        }
    }
    
    private func downloadRemoteChanges() async throws {
        // In real implementation, fetch changes from server
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    private func uploadLocalChanges() async throws {
        // In real implementation, send local changes to server
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    
    private func generateShareCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in characters.randomElement()! })
    }
}

// MARK: - Supporting Types

/// Represents a cloud user
struct CloudUser: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: URL?
}

/// Type of sync operation
enum OperationType: String, Codable {
    case create
    case update
    case delete
}

/// Pending operation for offline queue
struct PendingOperation: Codable, Identifiable {
    let id: UUID
    let itemId: String
    let itemType: String
    let operation: OperationType
    let timestamp: Date
    let data: Data?
}

// MARK: - Collaboration Session

/// Represents a real-time collaboration session
@MainActor
class CollaborationSession: ObservableObject {
    @Published var isActive: Bool = false
    @Published var participants: [CollaborationParticipant] = []
    @Published var sessionCode: String?
    
    private var sessionId: String?
    
    /// Start a new collaboration session
    func startSession() async throws -> String {
        let code = generateSessionCode()
        sessionCode = code
        sessionId = UUID().uuidString
        isActive = true
        
        // Add self as host
        let hostParticipant = CollaborationParticipant(
            id: UUID().uuidString,
            displayName: "You",
            isHost: true,
            cursor: nil
        )
        participants = [hostParticipant]
        
        Logger.info("Collaboration session started", category: .network, metadata: LogMetadata(additionalInfo: ["code": code]))
        
        return code
    }
    
    /// Join an existing collaboration session
    func joinSession(code: String, displayName: String) async throws {
        sessionCode = code
        sessionId = UUID().uuidString // Would be fetched from server
        isActive = true
        
        let participant = CollaborationParticipant(
            id: UUID().uuidString,
            displayName: displayName,
            isHost: false,
            cursor: nil
        )
        participants.append(participant)
        
        Logger.info("Joined collaboration session", category: .network, metadata: LogMetadata(additionalInfo: ["code": code]))
    }
    
    /// Leave the current session
    func leaveSession() {
        isActive = false
        participants.removeAll()
        sessionCode = nil
        sessionId = nil
    }
    
    /// Broadcast a location update to all participants
    func broadcastLocation(_ coordinate: LocationCoordinate) {
        guard isActive else { return }
        // In real implementation, send via WebSocket
    }
    
    private func generateSessionCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}

/// Represents a participant in a collaboration session
struct CollaborationParticipant: Identifiable, Codable {
    let id: String
    let displayName: String
    let isHost: Bool
    var cursor: LocationCoordinate?
    var lastActive: Date = Date()
    
    var isOnline: Bool {
        Date().timeIntervalSince(lastActive) < 60
    }
}

// MARK: - Version Control

/// Represents a version of a route for history tracking
struct RouteVersion: Identifiable, Codable {
    let id: UUID
    let routeId: UUID
    let version: Int
    let timestamp: Date
    let author: String
    let changeDescription: String
    let coordinateSnapshot: [LocationCoordinate]
    
    init(route: ShareableRoute, author: String, description: String) {
        self.id = UUID()
        self.routeId = route.id
        self.version = route.version
        self.timestamp = Date()
        self.author = author
        self.changeDescription = description
        self.coordinateSnapshot = route.coordinates
    }
}

/// Manager for route version history
@MainActor
class RouteVersionManager: ObservableObject {
    @Published var versions: [UUID: [RouteVersion]] = [:]
    
    private let maxVersionsPerRoute = 50
    
    /// Record a new version
    func recordVersion(for route: ShareableRoute, author: String, description: String) {
        let version = RouteVersion(route: route, author: author, description: description)
        
        if versions[route.id] == nil {
            versions[route.id] = []
        }
        
        versions[route.id]?.append(version)
        
        // Trim old versions
        if let count = versions[route.id]?.count, count > maxVersionsPerRoute {
            versions[route.id]?.removeFirst(count - maxVersionsPerRoute)
        }
    }
    
    /// Get version history for a route
    func getHistory(for routeId: UUID) -> [RouteVersion] {
        return versions[routeId]?.sorted { $0.version > $1.version } ?? []
    }
    
    /// Restore a route to a specific version
    func restore(version: RouteVersion) -> ShareableRoute {
        // Create a route from the version snapshot
        return ShareableRoute(
            id: version.routeId,
            name: "Restored from v\(version.version)",
            coordinates: version.coordinateSnapshot,
            ownerId: version.author
        )
    }
}
