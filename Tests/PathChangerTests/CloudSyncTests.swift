//
//  CloudSyncTests.swift
//  PathChangerTests
//
//  Tests for cloud sync and collaboration features
//

import XCTest
@testable import PathChanger

// MARK: - Cloud Sync Error Tests

final class CloudSyncErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertNotNil(CloudSyncError.notAuthenticated.errorDescription)
        XCTAssertNotNil(CloudSyncError.networkUnavailable.errorDescription)
        XCTAssertNotNil(CloudSyncError.quotaExceeded.errorDescription)
        XCTAssertNotNil(CloudSyncError.invalidData.errorDescription)
        XCTAssertNotNil(CloudSyncError.operationCancelled.errorDescription)
        XCTAssertNotNil(CloudSyncError.unauthorized.errorDescription)
        XCTAssertNotNil(CloudSyncError.resourceNotFound.errorDescription)
    }

    func testSyncFailedErrorIncludesUnderlyingError() {
        let underlyingError = NSError(domain: "test", code: 123)
        let error = CloudSyncError.syncFailed(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("123") ?? false)
    }

    func testConflictErrorIncludesVersions() {
        let error = CloudSyncError.conflictDetected(localVersion: 5, remoteVersion: 8)
        XCTAssertTrue(error.errorDescription?.contains("5") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("8") ?? false)
    }

    func testRateLimitedErrorIncludesRetryAfter() {
        let error = CloudSyncError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.errorDescription?.contains("30") ?? false)
    }

    func testServerErrorIncludesStatusCode() {
        let error = CloudSyncError.serverError(statusCode: 500)
        XCTAssertTrue(error.errorDescription?.contains("500") ?? false)
    }

    func testRetryableErrors() {
        XCTAssertTrue(CloudSyncError.networkUnavailable.isRetryable)
        XCTAssertTrue(CloudSyncError.rateLimited(retryAfter: 10).isRetryable)
        XCTAssertTrue(CloudSyncError.serverError(statusCode: 503).isRetryable)

        XCTAssertFalse(CloudSyncError.notAuthenticated.isRetryable)
        XCTAssertFalse(CloudSyncError.quotaExceeded.isRetryable)
        XCTAssertFalse(CloudSyncError.invalidData.isRetryable)
    }
}

// MARK: - Sync State Tests

final class SyncStateTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(SyncState.idle.displayName, "Synced")
        XCTAssertEqual(SyncState.syncing.displayName, "Syncing...")
        XCTAssertEqual(SyncState.offline.displayName, "Offline")
        XCTAssertEqual(SyncState.conflict.displayName, "Conflict Detected")
    }

    func testUploadingDisplayName() {
        let state = SyncState.uploading(progress: 0.5)
        XCTAssertEqual(state.displayName, "Uploading 50%")
    }

    func testDownloadingDisplayName() {
        let state = SyncState.downloading(progress: 0.75)
        XCTAssertEqual(state.displayName, "Downloading 75%")
    }

    func testErrorDisplayName() {
        let state = SyncState.error("Connection failed")
        XCTAssertTrue(state.displayName.contains("Connection failed"))
    }

    func testIcons() {
        XCTAssertEqual(SyncState.idle.icon, "checkmark.icloud")
        XCTAssertEqual(SyncState.syncing.icon, "arrow.triangle.2.circlepath.icloud")
        XCTAssertEqual(SyncState.conflict.icon, "exclamationmark.icloud")
        XCTAssertEqual(SyncState.error("test").icon, "xmark.icloud")
        XCTAssertEqual(SyncState.offline.icon, "icloud.slash")
    }

    func testEquality() {
        XCTAssertEqual(SyncState.idle, SyncState.idle)
        XCTAssertEqual(SyncState.uploading(progress: 0.5), SyncState.uploading(progress: 0.5))
        XCTAssertNotEqual(SyncState.idle, SyncState.syncing)
        XCTAssertNotEqual(SyncState.uploading(progress: 0.3), SyncState.uploading(progress: 0.7))
    }
}

// MARK: - Shareable Route Tests

final class ShareableRouteTests: XCTestCase {

    func testInitialization() {
        let coords = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6812, longitude: 139.7671)
        ]

        let route = ShareableRoute(
            name: "Tokyo Route",
            description: "Test route",
            coordinates: coords,
            ownerId: "user123"
        )

        XCTAssertEqual(route.name, "Tokyo Route")
        XCTAssertEqual(route.description, "Test route")
        XCTAssertEqual(route.coordinates.count, 2)
        XCTAssertEqual(route.ownerId, "user123")
        XCTAssertEqual(route.version, 1)
        XCTAssertFalse(route.isDeleted)
        XCTAssertFalse(route.isPublic)
        XCTAssertNil(route.shareCode)
        XCTAssertTrue(route.sharedWith.isEmpty)
    }

    func testDistanceCalculation() {
        let coords = [
            LocationCoordinate(latitude: 35.6762, longitude: 139.6503),
            LocationCoordinate(latitude: 35.6812, longitude: 139.7671) // About 10km apart
        ]

        let route = ShareableRoute(name: "Test", coordinates: coords, ownerId: "user1")

        XCTAssertGreaterThan(route.distance, 0)
    }

    func testCodable() throws {
        let route = ShareableRoute(
            name: "Test Route",
            coordinates: [LocationCoordinate(latitude: 35.0, longitude: 139.0)],
            ownerId: "user1"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(route)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShareableRoute.self, from: data)

        XCTAssertEqual(decoded.name, route.name)
        XCTAssertEqual(decoded.ownerId, route.ownerId)
    }
}

// MARK: - Share Permission Tests

final class SharePermissionTests: XCTestCase {

    func testInitialization() {
        let permission = SharePermission(
            userId: "user123",
            email: "test@example.com",
            permission: .editor
        )

        XCTAssertEqual(permission.userId, "user123")
        XCTAssertEqual(permission.email, "test@example.com")
        XCTAssertEqual(permission.permission, .editor)
        XCTAssertNil(permission.expiresAt)
        XCTAssertNotNil(permission.grantedAt)
    }

    func testPermissionLevelDisplayNames() {
        XCTAssertEqual(SharePermission.PermissionLevel.viewer.displayName, "Can view")
        XCTAssertEqual(SharePermission.PermissionLevel.editor.displayName, "Can edit")
        XCTAssertEqual(SharePermission.PermissionLevel.admin.displayName, "Full access")
    }

    func testPermissionCapabilities() {
        // Viewer
        XCTAssertFalse(SharePermission.PermissionLevel.viewer.canEdit)
        XCTAssertFalse(SharePermission.PermissionLevel.viewer.canShare)
        XCTAssertFalse(SharePermission.PermissionLevel.viewer.canDelete)

        // Editor
        XCTAssertTrue(SharePermission.PermissionLevel.editor.canEdit)
        XCTAssertFalse(SharePermission.PermissionLevel.editor.canShare)
        XCTAssertFalse(SharePermission.PermissionLevel.editor.canDelete)

        // Admin
        XCTAssertTrue(SharePermission.PermissionLevel.admin.canEdit)
        XCTAssertTrue(SharePermission.PermissionLevel.admin.canShare)
        XCTAssertTrue(SharePermission.PermissionLevel.admin.canDelete)
    }

    func testCodable() throws {
        let permission = SharePermission(
            userId: "user1",
            email: "test@test.com",
            permission: .admin,
            expiresAt: Date().addingTimeInterval(86400)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(permission)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SharePermission.self, from: data)

        XCTAssertEqual(decoded.email, permission.email)
        XCTAssertEqual(decoded.permission, permission.permission)
    }
}

// MARK: - Cloud Sync Settings Tests

final class CloudSyncSettingsTests: XCTestCase {

    func testDefaultSettings() {
        let settings = CloudSyncSettings.default

        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.syncOnWiFiOnly)
        XCTAssertEqual(settings.autoSyncInterval, 300)
        XCTAssertEqual(settings.conflictResolution, .askUser)
        XCTAssertEqual(settings.maxStorageBytes, 100 * 1024 * 1024)
    }

    func testConflictResolutionStrategies() {
        let strategies = CloudSyncSettings.ConflictResolutionStrategy.allCases
        XCTAssertEqual(strategies.count, 4)

        for strategy in strategies {
            XCTAssertFalse(strategy.displayName.isEmpty)
        }
    }

    func testCodable() throws {
        var settings = CloudSyncSettings.default
        settings.isEnabled = true
        settings.syncOnWiFiOnly = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CloudSyncSettings.self, from: data)

        XCTAssertEqual(decoded.isEnabled, settings.isEnabled)
        XCTAssertEqual(decoded.syncOnWiFiOnly, settings.syncOnWiFiOnly)
    }
}

// MARK: - Sync Metadata Tests

final class SyncMetadataTests: XCTestCase {

    func testInitialMetadata() {
        let metadata = SyncMetadata.initial

        XCTAssertNil(metadata.lastSyncTime)
        XCTAssertEqual(metadata.lastSyncVersion, 0)
        XCTAssertEqual(metadata.pendingChanges, 0)
        XCTAssertEqual(metadata.conflictCount, 0)
        XCTAssertEqual(metadata.bytesUsed, 0)
    }

    func testUsagePercentage() {
        var metadata = SyncMetadata.initial
        metadata.bytesUsed = 50 * 1024 * 1024 // 50 MB
        metadata.bytesQuota = 100 * 1024 * 1024 // 100 MB

        XCTAssertEqual(metadata.usagePercentage, 0.5, accuracy: 0.001)
    }

    func testUsagePercentageWithZeroQuota() {
        var metadata = SyncMetadata.initial
        metadata.bytesQuota = 0

        XCTAssertEqual(metadata.usagePercentage, 0)
    }
}

// MARK: - Cloud Sync Manager Tests

@MainActor
final class CloudSyncManagerTests: XCTestCase {

    var manager: CloudSyncManager!

    override func setUp() async throws {
        manager = CloudSyncManager.shared
        manager.signOut() // Ensure clean state
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(CloudSyncManager.shared)
    }

    func testInitialState() {
        XCTAssertEqual(manager.syncState, .idle)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testAuthentication() async throws {
        try await manager.authenticate(email: "test@example.com", password: "password")

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertNotNil(manager.currentUser)
        XCTAssertEqual(manager.currentUser?.email, "test@example.com")
    }

    func testSignOut() async throws {
        try await manager.authenticate(email: "test@example.com", password: "password")
        manager.signOut()

        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testPerformSyncRequiresAuthentication() async {
        await manager.performSync()

        if case .error(let message) = manager.syncState {
            XCTAssertTrue(message.contains("authenticated"))
        } else {
            XCTFail("Expected error state")
        }
    }

    func testUpdateSettings() {
        var newSettings = CloudSyncSettings.default
        newSettings.isEnabled = true
        newSettings.syncOnWiFiOnly = true

        manager.updateSettings(newSettings)

        XCTAssertTrue(manager.settings.isEnabled)
        XCTAssertTrue(manager.settings.syncOnWiFiOnly)
    }
}

// MARK: - Collaboration Session Tests

@MainActor
final class CollaborationSessionTests: XCTestCase {

    var session: CollaborationSession!

    override func setUp() async throws {
        session = CollaborationSession()
    }

    func testInitialState() {
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.participants.isEmpty)
        XCTAssertNil(session.sessionCode)
    }

    func testStartSession() async throws {
        let code = try await session.startSession()

        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.sessionCode)
        XCTAssertEqual(session.sessionCode, code)
        XCTAssertEqual(session.participants.count, 1)
        XCTAssertTrue(session.participants.first?.isHost ?? false)
    }

    func testSessionCodeFormat() async throws {
        let code = try await session.startSession()

        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isLetter || $0.isNumber })
    }

    func testJoinSession() async throws {
        try await session.joinSession(code: "ABC123", displayName: "TestUser")

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.sessionCode, "ABC123")
    }

    func testLeaveSession() async throws {
        try await session.startSession()
        session.leaveSession()

        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.participants.isEmpty)
        XCTAssertNil(session.sessionCode)
    }
}

// MARK: - Collaboration Participant Tests

final class CollaborationParticipantTests: XCTestCase {

    func testInitialization() {
        let participant = CollaborationParticipant(
            id: "user123",
            displayName: "Test User",
            isHost: true,
            cursor: nil
        )

        XCTAssertEqual(participant.id, "user123")
        XCTAssertEqual(participant.displayName, "Test User")
        XCTAssertTrue(participant.isHost)
        XCTAssertNil(participant.cursor)
    }

    func testIsOnlineWithRecentActivity() {
        let participant = CollaborationParticipant(
            id: "user1",
            displayName: "User",
            isHost: false,
            cursor: nil
        )

        XCTAssertTrue(participant.isOnline)
    }

    func testCodable() throws {
        let participant = CollaborationParticipant(
            id: "user1",
            displayName: "Test",
            isHost: true,
            cursor: LocationCoordinate(latitude: 35.0, longitude: 139.0)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(participant)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CollaborationParticipant.self, from: data)

        XCTAssertEqual(decoded.displayName, participant.displayName)
        XCTAssertEqual(decoded.isHost, participant.isHost)
    }
}

// MARK: - Route Version Tests

final class RouteVersionTests: XCTestCase {

    func testVersionCreation() {
        let route = ShareableRoute(
            name: "Test Route",
            coordinates: [LocationCoordinate(latitude: 35.0, longitude: 139.0)],
            ownerId: "user1"
        )

        let version = RouteVersion(
            route: route,
            author: "user1",
            description: "Initial version"
        )

        XCTAssertEqual(version.routeId, route.id)
        XCTAssertEqual(version.version, 1)
        XCTAssertEqual(version.author, "user1")
        XCTAssertEqual(version.changeDescription, "Initial version")
        XCTAssertEqual(version.coordinateSnapshot.count, 1)
    }
}

// MARK: - Route Version Manager Tests

@MainActor
final class RouteVersionManagerTests: XCTestCase {

    var manager: RouteVersionManager!

    override func setUp() async throws {
        manager = RouteVersionManager()
    }

    func testRecordVersion() {
        let route = ShareableRoute(
            name: "Test Route",
            coordinates: [LocationCoordinate(latitude: 35.0, longitude: 139.0)],
            ownerId: "user1"
        )

        manager.recordVersion(for: route, author: "user1", description: "Initial")

        let history = manager.getHistory(for: route.id)
        XCTAssertEqual(history.count, 1)
    }

    func testMultipleVersions() {
        var route = ShareableRoute(
            name: "Test Route",
            coordinates: [LocationCoordinate(latitude: 35.0, longitude: 139.0)],
            ownerId: "user1"
        )

        manager.recordVersion(for: route, author: "user1", description: "v1")

        route.version = 2
        manager.recordVersion(for: route, author: "user1", description: "v2")

        route.version = 3
        manager.recordVersion(for: route, author: "user1", description: "v3")

        let history = manager.getHistory(for: route.id)
        XCTAssertEqual(history.count, 3)
        // Should be sorted newest first
        XCTAssertEqual(history.first?.version, 3)
    }

    func testRestore() {
        let route = ShareableRoute(
            name: "Test Route",
            coordinates: [
                LocationCoordinate(latitude: 35.0, longitude: 139.0),
                LocationCoordinate(latitude: 36.0, longitude: 140.0)
            ],
            ownerId: "user1"
        )

        manager.recordVersion(for: route, author: "user1", description: "Original")

        let history = manager.getHistory(for: route.id)
        guard let version = history.first else {
            XCTFail("No version found")
            return
        }

        let restored = manager.restore(version: version)

        XCTAssertEqual(restored.coordinates.count, 2)
        XCTAssertTrue(restored.name.contains("Restored"))
    }

    func testEmptyHistoryForUnknownRoute() {
        let history = manager.getHistory(for: UUID())
        XCTAssertTrue(history.isEmpty)
    }
}

// MARK: - Cloud User Tests

final class CloudUserTests: XCTestCase {

    func testInitialization() {
        let user = CloudUser(
            id: "user123",
            email: "test@example.com",
            displayName: "Test User",
            avatarURL: URL(string: "https://example.com/avatar.png")
        )

        XCTAssertEqual(user.id, "user123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertNotNil(user.avatarURL)
    }

    func testCodable() throws {
        let user = CloudUser(
            id: "user1",
            email: "test@test.com",
            displayName: "Test",
            avatarURL: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(user)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CloudUser.self, from: data)

        XCTAssertEqual(decoded.id, user.id)
        XCTAssertEqual(decoded.email, user.email)
    }
}

// MARK: - Operation Type Tests

final class OperationTypeTests: XCTestCase {

    func testAllOperationTypes() {
        XCTAssertEqual(OperationType.create.rawValue, "create")
        XCTAssertEqual(OperationType.update.rawValue, "update")
        XCTAssertEqual(OperationType.delete.rawValue, "delete")
    }

    func testCodable() throws {
        let operation = OperationType.update

        let encoder = JSONEncoder()
        let data = try encoder.encode(operation)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OperationType.self, from: data)

        XCTAssertEqual(decoded, operation)
    }
}

// MARK: - Pending Operation Tests

final class PendingOperationTests: XCTestCase {

    func testInitialization() {
        let operation = PendingOperation(
            id: UUID(),
            itemId: "item123",
            itemType: "ShareableRoute",
            operation: .create,
            timestamp: Date(),
            data: nil
        )

        XCTAssertEqual(operation.itemId, "item123")
        XCTAssertEqual(operation.itemType, "ShareableRoute")
        XCTAssertEqual(operation.operation, .create)
    }
}
