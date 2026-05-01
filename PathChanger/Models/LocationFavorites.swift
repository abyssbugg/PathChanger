//
//  LocationFavorites.swift
//  PathChanger
//
//  User favorite locations with persistence
//

import Foundation
import SwiftUI

/// A saved favorite location
struct FavoriteLocation: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var coordinate: LocationCoordinate
    var createdAt: Date
    var lastUsed: Date?
    var usageCount: Int

    init(id: UUID = UUID(), name: String, coordinate: LocationCoordinate) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.createdAt = Date()
        self.lastUsed = nil
        self.usageCount = 0
    }
}

/// Manager for user's favorite locations
@MainActor
class LocationFavoritesManager: ObservableObject {
    static let shared = LocationFavoritesManager()

    @Published private(set) var favorites: [FavoriteLocation] = []

    private let storageKey = "PathChanger.Favorites"
    private let maxFavorites = 50

    init() {
        loadFavorites()
    }

    // MARK: - Public API

    /// Add a new favorite location
    func addFavorite(name: String, coordinate: LocationCoordinate) {
        guard favorites.count < maxFavorites else {
            Logger.debug("Maximum favorites limit reached (\(maxFavorites))", category: .general)
            return
        }

        // Check for duplicate coordinates
        if favorites.contains(where: { $0.coordinate == coordinate }) {
            Logger.debug("Location already in favorites", category: .general)
            return
        }

        let favorite = FavoriteLocation(name: name, coordinate: coordinate)
        favorites.insert(favorite, at: 0)
        saveFavorites()
    }

    /// Remove a favorite by ID
    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    /// Update favorite name
    func renameFavorite(id: UUID, newName: String) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites[index].name = newName
            saveFavorites()
        }
    }

    /// Record usage of a favorite
    func recordUsage(id: UUID) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites[index].lastUsed = Date()
            favorites[index].usageCount += 1
            saveFavorites()
        }
    }

    /// Get favorites sorted by most recently used
    var recentFavorites: [FavoriteLocation] {
        favorites.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    /// Get favorites sorted by most used
    var frequentFavorites: [FavoriteLocation] {
        favorites.sorted { $0.usageCount > $1.usageCount }
    }

    /// Check if a coordinate is in favorites
    func isFavorite(_ coordinate: LocationCoordinate) -> Bool {
        favorites.contains { $0.coordinate == coordinate }
    }

    /// Toggle favorite status for a coordinate
    func toggleFavorite(name: String, coordinate: LocationCoordinate) {
        if let existing = favorites.first(where: { $0.coordinate == coordinate }) {
            removeFavorite(id: existing.id)
        } else {
            addFavorite(name: name, coordinate: coordinate)
        }
    }

    // MARK: - Persistence

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            favorites = try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            Logger.error("Failed to load favorites: \(error.localizedDescription)", category: .general)
        }
    }

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Logger.error("Failed to save favorites: \(error.localizedDescription)", category: .general)
        }
    }

    /// Export favorites as JSON
    func exportFavorites() -> Data? {
        try? JSONEncoder().encode(favorites)
    }

    /// Import favorites from JSON
    func importFavorites(from data: Data) throws {
        let imported = try JSONDecoder().decode([FavoriteLocation].self, from: data)

        // Merge with existing, avoiding duplicates
        for location in imported {
            if !favorites.contains(where: { $0.coordinate == location.coordinate }) {
                favorites.append(location)
            }
        }

        // Trim to max limit
        if favorites.count > maxFavorites {
            favorites = Array(favorites.prefix(maxFavorites))
        }

        saveFavorites()
    }
}
