//
//  LegacyDocumentsMigration.swift
//  PathChanger
//
//  One-shot migration helper for app-managed files that previously lived in
//  ~/Documents/PathChanger.
//

import Foundation

enum LegacyDocumentsMigration {
    static func migrateFileIfNeeded(
        legacyURL: URL,
        destinationURL: URL,
        markerURL: URL
    ) throws {
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: destinationURL.path),
              !fileManager.fileExists(atPath: markerURL.path) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.copyItem(at: legacyURL, to: destinationURL)
        }

        fileManager.createFile(atPath: markerURL.path, contents: Data())
    }
}
