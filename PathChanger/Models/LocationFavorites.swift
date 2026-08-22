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
    @Published private(set) var places: [FavoriteLocation] = []
    @Published private(set) var recents: [FavoriteLocation] = []

    private let storageKey = "PathChanger.Favorites"
    private let placesKey = "PathChanger.Places"
    private let recentsKey = "PathChanger.Recents"
    private let maxFavorites = 50
    private let maxRecents = 14
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFavorites()
        let hadStoredPlaces = loadPlaces()
        loadRecents()
        if !hadStoredPlaces {
            restoreBuiltInPlaces()
        }
    }

    func recordRecent(name: String, coordinate: LocationCoordinate) {
        recents.removeAll { $0.coordinate == coordinate }
        recents.insert(FavoriteLocation(name: name, coordinate: coordinate), at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        saveRecents()
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
        rememberPlace(name: name, coordinate: coordinate)
    }

    /// Saved places stay after unstarring, matching the mock Places list.
    func rememberPlace(name: String, coordinate: LocationCoordinate) {
        if places.contains(where: { $0.coordinate == coordinate }) { return }
        places.insert(FavoriteLocation(name: name, coordinate: coordinate), at: 0)
        if places.count > maxFavorites {
            places = Array(places.prefix(maxFavorites))
        }
        savePlaces()
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

    func clearFavorites() {
        favorites = []
        saveFavorites()
    }

    func clearRecents() {
        recents = []
        saveRecents()
    }

    func clearPlaces() {
        places = []
        savePlaces()
    }

    func removePlace(id: UUID) {
        places.removeAll { $0.id == id }
        savePlaces()
    }

    func removeRecent(id: UUID) {
        recents.removeAll { $0.id == id }
        saveRecents()
    }

    func restoreBuiltInPlaces() {
        let builtInCoordinates = Set(Self.builtInPlaces.map(\.coordinate))
        let customPlaces = places.filter { !builtInCoordinates.contains($0.coordinate) }
        places = Self.builtInPlaces + customPlaces
        savePlaces()
    }

    // MARK: - Persistence

    private func loadFavorites() {
        guard let data = defaults.data(forKey: storageKey) else { return }

        do {
            favorites = try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            Logger.error("Failed to load favorites: \(error.localizedDescription)", category: .general)
        }
    }

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(favorites)
            defaults.set(data, forKey: storageKey)
        } catch {
            Logger.error("Failed to save favorites: \(error.localizedDescription)", category: .general)
        }
    }

    @discardableResult
    private func loadPlaces() -> Bool {
        guard let data = defaults.data(forKey: placesKey) else { return false }
        places = (try? JSONDecoder().decode([FavoriteLocation].self, from: data)) ?? []
        return true
    }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: placesKey)
        }
    }

    private func loadRecents() {
        guard let data = defaults.data(forKey: recentsKey) else { return }
        recents = (try? JSONDecoder().decode([FavoriteLocation].self, from: data)) ?? []
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: recentsKey)
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

    private static let builtInPlaces: [FavoriteLocation] = [
        FavoriteLocation(name: "Marina Road", coordinate: .init(latitude: 6.4474, longitude: 3.3903)),
        FavoriteLocation(name: "Shibuya Crossing", coordinate: .init(latitude: 35.6595, longitude: 139.7006)),
        FavoriteLocation(name: "Times Square", coordinate: .init(latitude: 40.7580, longitude: -73.9855)),
        FavoriteLocation(name: "Soho Square", coordinate: .init(latitude: 51.5153, longitude: -0.1323)),
        FavoriteLocation(name: "Louvre", coordinate: .init(latitude: 48.8606, longitude: 2.3376)),
        FavoriteLocation(name: "Ferry Building", coordinate: .init(latitude: 37.7954, longitude: -122.3936)),
        FavoriteLocation(name: "Opera House", coordinate: .init(latitude: -33.8568, longitude: 151.2153)),
        FavoriteLocation(name: "Dubai Marina", coordinate: .init(latitude: 25.0804, longitude: 55.1403))
    ]
}
