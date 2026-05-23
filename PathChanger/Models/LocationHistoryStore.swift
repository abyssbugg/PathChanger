//
//  LocationHistoryStore.swift
//  PathChanger
//
//  Persistent location history for successful location injections
//

import Foundation

struct LocationHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var coordinate: LocationCoordinate
    var name: String?
    var source: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        coordinate: LocationCoordinate,
        name: String? = nil,
        source: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.source = source
        self.createdAt = createdAt
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return coordinate.formattedShort
    }
}

@MainActor
final class LocationHistoryStore {
    private(set) var entries: [LocationHistoryEntry] = []

    private let storageURL: URL
    private let maxEntries: Int

    init(maxEntries: Int = 50) {
        self.maxEntries = maxEntries
        // Slice F2 (UX remediation): persist location history inside
        // `~/Library/Application Support/PathChanger/` instead of
        // `~/Documents/PathChanger/`. The previous Documents-based path
        // triggered repeated macOS TCC folder-access prompts on every
        // launch for non-sandboxed/ad-hoc-signed builds. Application
        // Support is the canonical macOS location for app-managed user
        // data and is not TCC-protected.
        let appSupportPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = appSupportPath.appendingPathComponent("PathChanger/location-history.json")

        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Slice F2 (UX remediation) — one-shot migration:
        // If the legacy Documents-based file exists and the new Application
        // Support file does not yet exist, copy the legacy file to the new
        // location. The marker makes even a missing legacy file deterministic:
        // the app will not repeatedly probe Documents on every launch just
        // because `location-history.json` never existed there. We deliberately
        // leave the legacy file in place as a non-destructive rollback fallback.
        let legacyDocumentsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyDocumentsPath.appendingPathComponent("PathChanger/location-history.json"),
            destinationURL: storageURL,
            markerURL: directory.appendingPathComponent(".location-history-documents-migration-complete")
        )

        load()
    }

    func record(coordinate: LocationCoordinate, name: String?, source: String) {
        entries.removeAll { existing in
            abs(existing.coordinate.latitude - coordinate.latitude) < 0.000001 &&
            abs(existing.coordinate.longitude - coordinate.longitude) < 0.000001 &&
            existing.name == name
        }

        entries.insert(
            LocationHistoryEntry(
                coordinate: coordinate,
                name: name,
                source: source,
                createdAt: Date()
            ),
            at: 0
        )

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        save()
    }

    func remove(_ entry: LocationHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            entries = try JSONDecoder().decode([LocationHistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL)
        } catch {
            Logger.debug("Failed to save location history: \(error.localizedDescription)", category: .general)
        }
    }
}
