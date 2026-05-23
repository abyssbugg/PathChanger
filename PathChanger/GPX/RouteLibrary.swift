//
//  RouteLibrary.swift
//  PathChanger
//
//  Route library management with persistence
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Saved Route

/// A saved route in the library
struct SavedRoute: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String?
    var coordinates: [LocationCoordinate]
    var distance: Double
    var isFavorite: Bool
    var lastUsed: Date?
    var createdAt: Date
    var color: RouteColor

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        coordinates: [LocationCoordinate],
        isFavorite: Bool = false,
        color: RouteColor = .blue
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.coordinates = coordinates
        self.distance = Self.calculateDistance(coordinates)
        self.isFavorite = isFavorite
        self.lastUsed = nil
        self.createdAt = Date()
        self.color = color
    }

    var formattedDistance: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }

    var pointCount: Int { coordinates.count }

    private static func calculateDistance(_ coords: [LocationCoordinate]) -> Double {
        guard coords.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let from = coords[i-1]
            let to = coords[i]
            total += haversineDistance(from: from, to: to)
        }
        return total
    }

    private static func haversineDistance(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }
}

// MARK: - Route Color

enum RouteColor: String, CaseIterable, Codable, Identifiable {
    case blue, red, green, orange, purple, yellow, cyan, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .yellow: return .yellow
        case .cyan: return .cyan
        case .pink: return .pink
        }
    }
}

// MARK: - Route Library Manager

/// Errors that can occur in RouteLibrary operations
enum RouteLibraryError: Error, LocalizedError {
    case routeNotFound
    case saveFailed(Error)
    case loadFailed(Error)
    case importFailed(Error)
    case exportFailed(Error)
    case emptyRoute

    var errorDescription: String? {
        switch self {
        case .routeNotFound: return "Route not found in library"
        case .saveFailed(let error): return "Failed to save routes: \(error.localizedDescription)"
        case .loadFailed(let error): return "Failed to load routes: \(error.localizedDescription)"
        case .importFailed(let error): return "Failed to import GPX: \(error.localizedDescription)"
        case .exportFailed(let error): return "Failed to export route: \(error.localizedDescription)"
        case .emptyRoute: return "Route has no coordinates"
        }
    }
}

@MainActor
class RouteLibraryManager: ObservableObject {
    @Published var routes: [SavedRoute] = []
    @Published var recentRoutes: [SavedRoute] = []
    @Published var favoriteRoutes: [SavedRoute] = []
    @Published var isLoading: Bool = false
    @Published var lastError: RouteLibraryError?

    /// Clear the last error (call after displaying error to user)
    func clearError() {
        lastError = nil
    }

    private let storageURL: URL
    private let maxRecent: Int = 10

    init() {
        // Slice F2 (UX remediation): persist route library inside
        // `~/Library/Application Support/PathChanger/` instead of
        // `~/Documents/PathChanger/`. The previous Documents-based path
        // triggered repeated macOS TCC folder-access prompts on every
        // launch for non-sandboxed/ad-hoc-signed builds. Application
        // Support is the canonical macOS location for app-managed user
        // data and is not TCC-protected.
        let appSupportPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = appSupportPath.appendingPathComponent("PathChanger/routes.json")

        // Ensure directory exists
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Slice F2 (UX remediation) — one-shot migration:
        // If the legacy Documents-based file exists and the new Application
        // Support file does not yet exist, copy the legacy file to the new
        // location. The marker makes even a missing legacy file deterministic:
        // the app will not repeatedly probe Documents on every launch just
        // because `routes.json` never existed there. We deliberately leave the
        // legacy file in place as a non-destructive rollback fallback.
        let legacyDocumentsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? LegacyDocumentsMigration.migrateFileIfNeeded(
            legacyURL: legacyDocumentsPath.appendingPathComponent("PathChanger/routes.json"),
            destinationURL: storageURL,
            markerURL: directory.appendingPathComponent(".routes-documents-migration-complete")
        )

        loadRoutes()
    }

    // MARK: - CRUD Operations

    func addRoute(_ route: SavedRoute) {
        routes.append(route)
        updateDerivedLists()
        saveRoutes()
    }

    /// Update an existing route. Returns true if the route was found and updated.
    @discardableResult
    func updateRoute(_ route: SavedRoute) -> Bool {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else {
            lastError = .routeNotFound
            return false
        }
        routes[index] = route
        updateDerivedLists()
        saveRoutes()
        return true
    }

    /// Delete a route. Returns true if the route was found and deleted.
    @discardableResult
    func deleteRoute(_ route: SavedRoute) -> Bool {
        let initialCount = routes.count
        routes.removeAll { $0.id == route.id }
        if routes.count == initialCount {
            lastError = .routeNotFound
            return false
        }
        updateDerivedLists()
        saveRoutes()
        return true
    }

    func deleteRoutes(at offsets: IndexSet) {
        routes.remove(atOffsets: offsets)
        updateDerivedLists()
        saveRoutes()
    }

    /// Toggle a route's favorite status. Returns true if the route was found.
    @discardableResult
    func toggleFavorite(_ route: SavedRoute) -> Bool {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else {
            lastError = .routeNotFound
            return false
        }
        routes[index].isFavorite.toggle()
        updateDerivedLists()
        saveRoutes()
        return true
    }

    /// Mark a route as recently used. Returns true if the route was found.
    @discardableResult
    func markAsUsed(_ route: SavedRoute) -> Bool {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else {
            lastError = .routeNotFound
            return false
        }
        routes[index].lastUsed = Date()
        updateDerivedLists()
        saveRoutes()
        return true
    }

    // MARK: - Import/Export

    func importGPX(from url: URL) async throws -> SavedRoute {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let parser = GPXParser()
            let gpx = try parser.parse(fileURL: url)
            let coords = gpx.allCoordinates

            guard !coords.isEmpty else {
                let error = GPXParserError.emptyFile
                lastError = .importFailed(error)
                throw error
            }

            let route = SavedRoute(
                name: gpx.name,
                description: gpx.description,
                coordinates: coords
            )

            addRoute(route)
            return route
        } catch let error as RouteLibraryError {
            lastError = error
            throw error
        } catch {
            lastError = .importFailed(error)
            throw error
        }
    }

    func importGPX(from data: Data, name: String) async throws -> SavedRoute {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let parser = GPXParser()
            let gpx = try parser.parse(data: data)
            let coords = gpx.allCoordinates

            guard !coords.isEmpty else {
                let error = GPXParserError.emptyFile
                lastError = .importFailed(error)
                throw error
            }

            let route = SavedRoute(
                name: gpx.name.isEmpty ? name : gpx.name,
                description: gpx.description,
                coordinates: coords
            )

            addRoute(route)
            return route
        } catch let error as RouteLibraryError {
            lastError = error
            throw error
        } catch {
            lastError = .importFailed(error)
            throw error
        }
    }

    func exportGPX(route: SavedRoute) -> String {
        GPXWriter.createGPX(from: route.coordinates, name: route.name)
    }

    func exportToFile(route: SavedRoute, to url: URL) throws {
        lastError = nil
        do {
            let gpx = exportGPX(route: route)
            try gpx.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = .exportFailed(error)
            throw error
        }
    }

    // MARK: - Persistence

    private func loadRoutes() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            routes = try JSONDecoder().decode([SavedRoute].self, from: data)
            updateDerivedLists()
        } catch {
            lastError = .loadFailed(error)
        }
    }

    private func saveRoutes() {
        do {
            let data = try JSONEncoder().encode(routes)
            try data.write(to: storageURL)
        } catch {
            lastError = .saveFailed(error)
        }
    }

    private func updateDerivedLists() {
        favoriteRoutes = routes.filter { $0.isFavorite }
        recentRoutes = routes
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(maxRecent)
            .map { $0 }
    }

    // MARK: - Sample Routes

    func addSampleRoutes() {
        let samples: [(String, [(Double, Double)])] = [
            ("Tokyo Imperial Palace Loop", [
                (35.6841, 139.7530), (35.6845, 139.7555), (35.6838, 139.7580),
                (35.6815, 139.7590), (35.6795, 139.7575), (35.6788, 139.7545),
                (35.6800, 139.7520), (35.6820, 139.7515), (35.6841, 139.7530)
            ]),
            ("Central Park North Loop", [
                (40.7829, -73.9654), (40.7860, -73.9620), (40.7890, -73.9600),
                (40.7920, -73.9620), (40.7935, -73.9654), (40.7920, -73.9688),
                (40.7890, -73.9700), (40.7860, -73.9688), (40.7829, -73.9654)
            ]),
            ("San Francisco Embarcadero", [
                (37.7956, -122.3933), (37.7940, -122.3900), (37.7920, -122.3880),
                (37.7900, -122.3870), (37.7880, -122.3880), (37.7865, -122.3900)
            ])
        ]

        for (name, points) in samples {
            let coords = points.map { LocationCoordinate(latitude: $0.0, longitude: $0.1) }
            let route = SavedRoute(name: name, coordinates: coords)
            addRoute(route)
        }
    }
}

// MARK: - GPX Document Type

struct GPXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml, UTType(filenameExtension: "gpx") ?? .xml] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
