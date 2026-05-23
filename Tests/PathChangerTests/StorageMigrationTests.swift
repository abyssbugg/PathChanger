import XCTest
@testable import PathChanger

final class StorageMigrationTests: XCTestCase {
    func testMissingLegacyFileIsMarkedMigratedAndNotCopiedOnLaterLaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-storage-migration-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("Documents/PathChanger/routes.json")
        let destinationURL = root.appendingPathComponent("Application Support/PathChanger/routes.json")
        let markerURL = root.appendingPathComponent("Application Support/PathChanger/.routes-documents-migration-complete")
        defer { try? FileManager.default.removeItem(at: root) }

        try LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyURL,
            destinationURL: destinationURL,
            markerURL: markerURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))

        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"late":"legacy"}"#.write(to: legacyURL, atomically: true, encoding: .utf8)

        try LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyURL,
            destinationURL: destinationURL,
            markerURL: markerURL
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationURL.path),
            "Once the missing legacy file is marked migrated, later launches must not re-probe/copy Documents."
        )
    }

    func testExistingLegacyFileCopiesOnceAndPreservesDestinationOnLaterLaunch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pathchanger-storage-migration-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("Documents/PathChanger/location-history.json")
        let destinationURL = root.appendingPathComponent("Application Support/PathChanger/location-history.json")
        let markerURL = root.appendingPathComponent("Application Support/PathChanger/.location-history-documents-migration-complete")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"first":"legacy"}"#.write(to: legacyURL, atomically: true, encoding: .utf8)

        try LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyURL,
            destinationURL: destinationURL,
            markerURL: markerURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(try String(contentsOf: destinationURL), #"{"first":"legacy"}"#)

        try #"{"second":"legacy"}"#.write(to: legacyURL, atomically: true, encoding: .utf8)

        try LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyURL,
            destinationURL: destinationURL,
            markerURL: markerURL
        )

        XCTAssertEqual(
            try String(contentsOf: destinationURL),
            #"{"first":"legacy"}"#,
            "Existing Application Support data must remain authoritative after migration is marked complete."
        )
    }
}
