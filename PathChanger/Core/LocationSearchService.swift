//
//  LocationSearchService.swift
//  PathChanger
//
//  Address and place name search using MapKit
//

import Foundation
import MapKit
import Combine

/// Search result for a location
struct LocationSearchResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: LocationCoordinate
    let mapItem: MKMapItem

    static func == (lhs: LocationSearchResult, rhs: LocationSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// Service for searching locations by address or place name
@MainActor
class LocationSearchService: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [LocationSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?

    private var searchCompleter: MKLocalSearchCompleter
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        searchCompleter = MKLocalSearchCompleter()
        searchCompleter.resultTypes = [.address, .pointOfInterest]

        // Debounce search text changes
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    /// Search for locations matching the query
    func performSearch(query: String) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        // Check if it's a coordinate input (e.g., "37.7749, -122.4194")
        if let coordinate = parseCoordinateString(trimmedQuery) {
            searchResults = [
                LocationSearchResult(
                    name: "Coordinates",
                    subtitle: String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude),
                    coordinate: coordinate,
                    mapItem: MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )))
                )
            ]
            isSearching = false
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task {
            do {
                let results = try await search(query: trimmedQuery)

                guard !Task.isCancelled else { return }

                searchResults = results
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }

                searchResults = []
                isSearching = false
                errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    /// Perform MapKit local search
    private func search(query: String) async throws -> [LocationSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.compactMap { item -> LocationSearchResult? in
            guard let location = item.placemark.location else { return nil }

            let coordinate = LocationCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            return LocationSearchResult(
                name: item.name ?? "Unknown",
                subtitle: formatAddress(item.placemark),
                coordinate: coordinate,
                mapItem: item
            )
        }
    }

    /// Parse coordinate string (e.g., "37.7749, -122.4194")
    private func parseCoordinateString(_ text: String) -> LocationCoordinate? {
        // Remove common prefixes
        let cleanText = text
            .replacingOccurrences(of: "lat:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "lon:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "lng:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try comma-separated format
        let components = cleanText.components(separatedBy: CharacterSet(charactersIn: ",; "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]),
              lat >= -90, lat <= 90,
              lon >= -180, lon <= 180 else {
            return nil
        }

        return LocationCoordinate(latitude: lat, longitude: lon)
    }

    /// Format address from placemark
    private func formatAddress(_ placemark: MKPlacemark) -> String {
        var parts: [String] = []

        if let thoroughfare = placemark.thoroughfare {
            parts.append(thoroughfare)
        }
        if let locality = placemark.locality {
            parts.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }
        if let country = placemark.country, parts.isEmpty {
            parts.append(country)
        }

        return parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ")
    }

    /// Clear search
    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        isSearching = false
        errorMessage = nil
    }
}
