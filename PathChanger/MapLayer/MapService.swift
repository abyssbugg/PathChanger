//
//  MapService.swift
//  PathChanger
//
//  Map service abstraction protocol with full MapKit integration
//

import Foundation
import MapKit
import SwiftUI
import Combine

// MARK: - Map Annotation Model

/// Custom annotation for map markers
class LocationAnnotation: NSObject, MKAnnotation, Identifiable {
    let id = UUID()
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    var annotationType: AnnotationType
    
    enum AnnotationType {
        case spoofedLocation
        case waypoint
        case destination
        case searchResult
    }
    
    init(
        coordinate: CLLocationCoordinate2D,
        title: String? = nil,
        subtitle: String? = nil,
        type: AnnotationType = .waypoint
    ) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.annotationType = type
        super.init()
    }
}

// MARK: - Route Model

/// Route representation for map display
struct MapRoute: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let name: String
    let color: NSColor
    let lineWidth: CGFloat
    
    init(
        coordinates: [CLLocationCoordinate2D],
        name: String = "Route",
        color: NSColor = .systemBlue,
        lineWidth: CGFloat = 4.0
    ) {
        self.coordinates = coordinates
        self.name = name
        self.color = color
        self.lineWidth = lineWidth
    }
    
    var polyline: MKPolyline {
        MKPolyline(coordinates: coordinates, count: coordinates.count)
    }
    
    var totalDistance: CLLocationDistance {
        guard coordinates.count > 1 else { return 0 }
        var distance: CLLocationDistance = 0
        for i in 1..<coordinates.count {
            let from = CLLocation(latitude: coordinates[i-1].latitude, longitude: coordinates[i-1].longitude)
            let to = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            distance += from.distance(from: to)
        }
        return distance
    }
}

// MARK: - Protocol

/// Protocol for map service providers
protocol MapServiceProtocol: AnyObject {
    var region: MKCoordinateRegion { get set }
    var annotations: [LocationAnnotation] { get }
    var routes: [MapRoute] { get }
    
    func setRegion(_ region: MKCoordinateRegion, animated: Bool)
    func centerOn(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan?, animated: Bool)
    func addAnnotation(_ annotation: LocationAnnotation)
    func removeAnnotation(_ annotation: LocationAnnotation)
    func removeAllAnnotations()
    func addRoute(_ route: MapRoute)
    func removeRoute(_ route: MapRoute)
    func clearAllRoutes()
    func searchLocation(query: String) async throws -> [MKMapItem]
}

/// Map provider types
enum MapProvider: String, CaseIterable, Identifiable {
    case mapKit = "Apple Maps"
    case mapbox = "Mapbox"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .mapKit: return "map"
        case .mapbox: return "globe"
        }
    }
}

// MARK: - MapKit Implementation

/// Full MapKit implementation of MapService
class MapKitService: MapServiceProtocol, ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published private(set) var annotations: [LocationAnnotation] = []
    @Published private(set) var routes: [MapRoute] = []
    
    private var routeOverlays: [UUID: MKPolyline] = [:]
    
    init(initialRegion: MKCoordinateRegion? = nil) {
        self.region = initialRegion ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    func setRegion(_ region: MKCoordinateRegion, animated: Bool = true) {
        self.region = region
    }
    
    func centerOn(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        let newSpan = span ?? region.span
        region = MKCoordinateRegion(center: coordinate, span: newSpan)
    }
    
    func addAnnotation(_ annotation: LocationAnnotation) {
        annotations.append(annotation)
    }
    
    func removeAnnotation(_ annotation: LocationAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
    }
    
    func removeAllAnnotations() {
        annotations.removeAll()
    }
    
    func addRoute(_ route: MapRoute) {
        routes.append(route)
        routeOverlays[route.id] = route.polyline
    }
    
    func removeRoute(_ route: MapRoute) {
        routes.removeAll { $0.id == route.id }
        routeOverlays.removeValue(forKey: route.id)
    }
    
    func clearAllRoutes() {
        routes.removeAll()
        routeOverlays.removeAll()
    }
    
    func searchLocation(query: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }
    
    /// Calculate route between two points
    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        return response.routes.first
    }
}

// MARK: - Mapbox Placeholder

/// Mapbox placeholder implementation
/// Note: Requires MapboxMaps SDK integration when enabled
class MapboxService: MapServiceProtocol, ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published private(set) var annotations: [LocationAnnotation] = []
    @Published private(set) var routes: [MapRoute] = []
    
    init() {
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    
    func setRegion(_ region: MKCoordinateRegion, animated: Bool = true) {
        self.region = region
    }
    
    func centerOn(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        let newSpan = span ?? region.span
        region = MKCoordinateRegion(center: coordinate, span: newSpan)
    }
    
    func addAnnotation(_ annotation: LocationAnnotation) {
        annotations.append(annotation)
    }
    
    func removeAnnotation(_ annotation: LocationAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
    }
    
    func removeAllAnnotations() {
        annotations.removeAll()
    }
    
    func addRoute(_ route: MapRoute) {
        routes.append(route)
    }
    
    func removeRoute(_ route: MapRoute) {
        routes.removeAll { $0.id == route.id }
    }
    
    func clearAllRoutes() {
        routes.removeAll()
    }
    
    func searchLocation(query: String) async throws -> [MKMapItem] {
        // Mapbox Geocoding API would be used here
        // For now, fall back to MapKit search
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }
}

// MARK: - Map Manager

/// Map manager for switching between providers and managing map state
@MainActor
class MapManager: ObservableObject {
    @Published var currentProvider: MapProvider = .mapKit
    @Published var mapStyle: MapStyleType = .standard
    @Published var showsUserLocation: Bool = false
    @Published var selectedAnnotation: LocationAnnotation?
    
    private let mapKitService = MapKitService()
    private let mapboxService = MapboxService()
    
    enum MapStyleType: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case satellite = "Satellite"
        case hybrid = "Hybrid"
        
        var id: String { rawValue }
        
        var mapStyle: MapStyle {
            switch self {
            case .standard: return .standard
            case .satellite: return .imagery
            case .hybrid: return .hybrid
            }
        }
    }
    
    var currentService: MapServiceProtocol {
        switch currentProvider {
        case .mapKit:
            return mapKitService
        case .mapbox:
            return mapboxService
        }
    }
    
    var region: MKCoordinateRegion {
        get { currentService.region }
        set { currentService.setRegion(newValue, animated: true) }
    }
    
    var annotations: [LocationAnnotation] {
        currentService.annotations
    }
    
    var routes: [MapRoute] {
        currentService.routes
    }
    
    func switchProvider(to provider: MapProvider) {
        // Transfer state to new provider
        let currentRegion = currentService.region
        let currentAnnotations = currentService.annotations
        let currentRoutes = currentService.routes
        
        currentProvider = provider
        
        // Apply state to new provider
        currentService.setRegion(currentRegion, animated: false)
        currentAnnotations.forEach { currentService.addAnnotation($0) }
        currentRoutes.forEach { currentService.addRoute($0) }
    }
    
    func centerOn(_ coordinate: LocationCoordinate, zoomLevel: Double = 0.01) {
        let span = MKCoordinateSpan(latitudeDelta: zoomLevel, longitudeDelta: zoomLevel)
        currentService.centerOn(coordinate: coordinate.clLocationCoordinate2D, span: span, animated: true)
    }
    
    func addSpoofedLocationMarker(at coordinate: LocationCoordinate) {
        // Remove existing spoofed location marker
        currentService.annotations
            .filter { $0.annotationType == .spoofedLocation }
            .forEach { currentService.removeAnnotation($0) }
        
        // Add new marker
        let annotation = LocationAnnotation(
            coordinate: coordinate.clLocationCoordinate2D,
            title: "Spoofed Location",
            subtitle: coordinate.formattedString,
            type: .spoofedLocation
        )
        currentService.addAnnotation(annotation)
    }
    
    func search(query: String) async -> [MKMapItem] {
        do {
            return try await currentService.searchLocation(query: query)
        } catch {
            Logger.error("Search failed: \(error)", category: .map)
            return []
        }
    }
}
