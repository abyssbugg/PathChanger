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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = documentsPath.appendingPathComponent("PathChanger/location-history.json")

        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

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
