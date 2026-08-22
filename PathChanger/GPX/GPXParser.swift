//
//  GPXParser.swift
//  PathChanger
//
//  GPX file parsing and creation for route import/export
//

import Foundation
import CoreLocation

// MARK: - GPX Data Models

/// Represents a parsed GPX file
struct GPXFile: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String?
    var author: String?
    var time: Date?
    var waypoints: [GPXWaypoint]
    var tracks: [GPXTrack]
    var routes: [GPXRoute]

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        author: String? = nil,
        time: Date? = nil,
        waypoints: [GPXWaypoint] = [],
        tracks: [GPXTrack] = [],
        routes: [GPXRoute] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.time = time
        self.waypoints = waypoints
        self.tracks = tracks
        self.routes = routes
    }

    /// All coordinates from tracks and routes
    var allCoordinates: [LocationCoordinate] {
        var coords: [LocationCoordinate] = []
        for track in tracks {
            for segment in track.segments {
                coords.append(contentsOf: segment.points.map { $0.coordinate })
            }
        }
        for route in routes {
            coords.append(contentsOf: route.points.map { $0.coordinate })
        }
        return coords
    }

    /// Total number of points
    var totalPoints: Int {
        let trackPoints = tracks.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.points.count } }
        let routePoints = routes.reduce(0) { $0 + $1.points.count }
        return waypoints.count + trackPoints + routePoints
    }

    /// Calculate total distance in meters
    var totalDistance: Double {
        let coords = allCoordinates
        guard coords.count > 1 else { return 0 }

        var distance: Double = 0
        for i in 1..<coords.count {
            let from = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
            let to = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            distance += from.distance(from: to)
        }
        return distance
    }
}

/// A waypoint in GPX
struct GPXWaypoint: Identifiable, Codable {
    let id: UUID
    var coordinate: LocationCoordinate
    var name: String?
    var description: String?
    var elevation: Double?
    var time: Date?
    var symbol: String?

    init(
        id: UUID = UUID(),
        coordinate: LocationCoordinate,
        name: String? = nil,
        description: String? = nil,
        elevation: Double? = nil,
        time: Date? = nil,
        symbol: String? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.description = description
        self.elevation = elevation
        self.time = time
        self.symbol = symbol
    }
}

/// A track in GPX (collection of track segments)
struct GPXTrack: Identifiable, Codable {
    let id: UUID
    var name: String?
    var description: String?
    var segments: [GPXTrackSegment]

    init(id: UUID = UUID(), name: String? = nil, description: String? = nil, segments: [GPXTrackSegment] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.segments = segments
    }
}

/// A track segment (continuous GPS track)
struct GPXTrackSegment: Identifiable, Codable {
    let id: UUID
    var points: [GPXTrackPoint]

    init(id: UUID = UUID(), points: [GPXTrackPoint] = []) {
        self.id = id
        self.points = points
    }
}

/// A point in a track segment
struct GPXTrackPoint: Identifiable, Codable {
    let id: UUID
    var coordinate: LocationCoordinate
    var elevation: Double?
    var time: Date?

    init(id: UUID = UUID(), coordinate: LocationCoordinate, elevation: Double? = nil, time: Date? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
    }
}

/// A route in GPX (planned route, not recorded track)
struct GPXRoute: Identifiable, Codable {
    let id: UUID
    var name: String?
    var description: String?
    var points: [GPXRoutePoint]

    init(id: UUID = UUID(), name: String? = nil, description: String? = nil, points: [GPXRoutePoint] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.points = points
    }
}

/// A point in a route
struct GPXRoutePoint: Identifiable, Codable {
    let id: UUID
    var coordinate: LocationCoordinate
    var name: String?
    var elevation: Double?

    init(id: UUID = UUID(), coordinate: LocationCoordinate, name: String? = nil, elevation: Double? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.elevation = elevation
    }
}

// MARK: - GPX Parser Error

enum GPXParserError: Error, LocalizedError {
    case invalidData
    case parseError(String)
    case emptyFile
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid GPX data"
        case .parseError(let msg): return "GPX parse error: \(msg)"
        case .emptyFile: return "GPX file contains no tracks or routes"
        case .unsupportedVersion: return "Unsupported GPX version"
        }
    }
}

// MARK: - GPX Parser

/// Parser for GPX files using streaming XMLParser delegate pattern
/// Memory-efficient: processes XML elements incrementally without loading entire DOM
class GPXParser: NSObject {
    private var currentGPX: GPXFile?

    /// Track parsing statistics for performance monitoring
    private(set) var parseStats: ParseStatistics?

    struct ParseStatistics {
        let pointCount: Int
        let parseTimeMs: Double
        let peakMemoryBytes: Int64
    }
    private var currentTrack: GPXTrack?
    private var currentSegment: GPXTrackSegment?
    private var currentRoute: GPXRoute?
    private var currentElement: String = ""
    private var currentAttributes: [String: String] = [:]
    private var currentText: String = ""
    private var parseError: Error?

    // ISO8601 date formatters for GPX timestamps (primary with fractional seconds, fallback without)
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private lazy var dateFormatterFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parseTimestamp(_ text: String) -> Date? {
        // Try primary formatter (with fractional seconds)
        if let date = dateFormatter.date(from: text) {
            return date
        }
        // Fallback to standard ISO8601 without fractional seconds
        if let date = dateFormatterFallback.date(from: text) {
            return date
        }
        // Log warning for malformed timestamp
        Logger.debug("Malformed GPX timestamp ignored: \(text)", category: .general)
        return nil
    }

    /// Parse GPX data from Data using streaming XMLParser
    /// - Parameter data: GPX file data
    /// - Returns: Parsed GPXFile
    /// - Note: Uses XMLParser delegate pattern for memory-efficient streaming parse
    func parse(data: Data) throws -> GPXFile {
        guard !data.isEmpty else {
            throw GPXParserError.invalidData
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()

        currentGPX = GPXFile(name: "Untitled")
        currentTrack = nil
        currentSegment = nil
        currentRoute = nil
        currentElement = ""
        currentText = ""
        parseError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        // Security: Disable external entity resolution to prevent XXE attacks
        parser.shouldResolveExternalEntities = false

        if parser.parse() {
            guard let gpx = currentGPX else {
                throw GPXParserError.parseError("Failed to create GPX object")
            }

            if gpx.tracks.isEmpty && gpx.routes.isEmpty && gpx.waypoints.isEmpty {
                throw GPXParserError.emptyFile
            }

            // Record parsing statistics
            let endTime = CFAbsoluteTimeGetCurrent()
            let endMemory = getMemoryUsage()
            parseStats = ParseStatistics(
                pointCount: gpx.totalPoints,
                parseTimeMs: (endTime - startTime) * 1000,
                peakMemoryBytes: max(0, endMemory - startMemory)
            )

            return gpx
        } else {
            throw parseError ?? GPXParserError.parseError("Unknown parse error")
        }
    }

    /// Get current memory usage for performance monitoring
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    /// Parse GPX from file URL
    func parse(fileURL: URL) throws -> GPXFile {
        let data = try Data(contentsOf: fileURL)
        var gpx = try parse(data: data)
        gpx.name = fileURL.deletingPathExtension().lastPathComponent
        return gpx
    }

    /// Parse GPX from string
    func parse(string: String) throws -> GPXFile {
        guard let data = string.data(using: .utf8) else {
            throw GPXParserError.invalidData
        }
        return try parse(data: data)
    }
}

// MARK: - XMLParser Delegate

extension GPXParser: XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentAttributes = attributeDict
        currentText = ""

        switch currentElement {
        case "gpx":
            break

        case "wpt":
            if let lat = attributeDict["lat"].flatMap(Double.init),
               let lon = attributeDict["lon"].flatMap(Double.init) {
                let waypoint = GPXWaypoint(coordinate: LocationCoordinate(latitude: lat, longitude: lon))
                currentGPX?.waypoints.append(waypoint)
            }

        case "trk":
            currentTrack = GPXTrack()

        case "trkseg":
            currentSegment = GPXTrackSegment()

        case "trkpt":
            if let lat = attributeDict["lat"].flatMap(Double.init),
               let lon = attributeDict["lon"].flatMap(Double.init) {
                let point = GPXTrackPoint(coordinate: LocationCoordinate(latitude: lat, longitude: lon))
                currentSegment?.points.append(point)
            }

        case "rte":
            currentRoute = GPXRoute()

        case "rtept":
            if let lat = attributeDict["lat"].flatMap(Double.init),
               let lon = attributeDict["lon"].flatMap(Double.init) {
                let point = GPXRoutePoint(coordinate: LocationCoordinate(latitude: lat, longitude: lon))
                currentRoute?.points.append(point)
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName.lowercased() {
        case "name":
            if currentRoute != nil {
                currentRoute?.name = text
            } else if currentTrack != nil {
                currentTrack?.name = text
            } else if let lastIndex = currentGPX?.waypoints.indices.last {
                currentGPX?.waypoints[lastIndex].name = text
            } else {
                currentGPX?.name = text
            }

        case "desc":
            if currentRoute != nil {
                currentRoute?.description = text
            } else if currentTrack != nil {
                currentTrack?.description = text
            } else {
                currentGPX?.description = text
            }

        case "author":
            currentGPX?.author = text

        case "time":
            if let date = parseTimestamp(text) {
                if currentSegment != nil, let lastIndex = currentSegment?.points.indices.last {
                    currentSegment?.points[lastIndex].time = date
                } else {
                    currentGPX?.time = date
                }
            }

        case "ele":
            if let elevation = Double(text) {
                if currentSegment != nil, let lastIndex = currentSegment?.points.indices.last {
                    currentSegment?.points[lastIndex].elevation = elevation
                } else if currentRoute != nil, let lastIndex = currentRoute?.points.indices.last {
                    currentRoute?.points[lastIndex].elevation = elevation
                } else if let lastIndex = currentGPX?.waypoints.indices.last {
                    currentGPX?.waypoints[lastIndex].elevation = elevation
                }
            }

        case "trkseg":
            if let segment = currentSegment {
                currentTrack?.segments.append(segment)
            }
            currentSegment = nil

        case "trk":
            if let track = currentTrack {
                currentGPX?.tracks.append(track)
            }
            currentTrack = nil

        case "rte":
            if let route = currentRoute {
                currentGPX?.routes.append(route)
            }
            currentRoute = nil

        default:
            break
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = GPXParserError.parseError(parseError.localizedDescription)
    }
}

// MARK: - GPX Writer

/// Writer for creating GPX files
class GPXWriter {
    // Computed rather than a stored static: a stored non-Sendable formatter is a hard error
    // under the Swift 6 language mode, and this is called once per export so the allocation
    // cost is irrelevant.
    private static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    /// Create GPX string from coordinates
    static func createGPX(from coordinates: [LocationCoordinate], name: String = "Route") -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="PathChanger"
             xmlns="http://www.topografix.com/GPX/1/1">
            <metadata>
                <name>\(escapeXML(name))</name>
                <time>\(dateFormatter.string(from: Date()))</time>
            </metadata>
            <trk>
                <name>\(escapeXML(name))</name>
                <trkseg>

        """

        for coord in coordinates {
            xml += "            <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"></trkpt>\n"
        }

        xml += """
                </trkseg>
            </trk>
        </gpx>
        """

        return xml
    }

    /// Escape XML special characters
    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Export GPX to file URL
    /// - Parameters:
    ///   - coordinates: Array of coordinates to export
    ///   - name: Name for the route
    ///   - fileURL: Destination file URL
    /// - Throws: Error if file write fails
    static func exportGPX(coordinates: [LocationCoordinate], name: String = "Route", to fileURL: URL) throws {
        let gpxString = createGPX(from: coordinates, name: name)
        try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Export GPX and return Data
    static func exportGPXData(coordinates: [LocationCoordinate], name: String = "Route") -> Data? {
        let gpxString = createGPX(from: coordinates, name: name)
        return gpxString.data(using: .utf8)
    }

    /// Create GPX from GPXFile object (preserves metadata)
    static func createGPX(from gpxFile: GPXFile) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="PathChanger"
             xmlns="http://www.topografix.com/GPX/1/1">
            <metadata>
                <name>\(escapeXML(gpxFile.name))</name>
        """

        if let description = gpxFile.description {
            xml += "\n        <desc>\(escapeXML(description))</desc>"
        }
        if let author = gpxFile.author {
            xml += "\n        <author><name>\(escapeXML(author))</name></author>"
        }
        xml += "\n        <time>\(dateFormatter.string(from: gpxFile.time ?? Date()))</time>"
        xml += "\n    </metadata>\n"

        // Export waypoints
        for waypoint in gpxFile.waypoints {
            xml += "    <wpt lat=\"\(waypoint.coordinate.latitude)\" lon=\"\(waypoint.coordinate.longitude)\">"
            if let name = waypoint.name {
                xml += "\n        <name>\(escapeXML(name))</name>"
            }
            if let ele = waypoint.elevation {
                xml += "\n        <ele>\(ele)</ele>"
            }
            xml += "\n    </wpt>\n"
        }

        // Export tracks
        for track in gpxFile.tracks {
            xml += "    <trk>\n"
            if let name = track.name {
                xml += "        <name>\(escapeXML(name))</name>\n"
            }
            for segment in track.segments {
                xml += "        <trkseg>\n"
                for point in segment.points {
                    xml += "            <trkpt lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\">"
                    if let ele = point.elevation {
                        xml += "<ele>\(ele)</ele>"
                    }
                    xml += "</trkpt>\n"
                }
                xml += "        </trkseg>\n"
            }
            xml += "    </trk>\n"
        }

        // Export routes
        for route in gpxFile.routes {
            xml += "    <rte>\n"
            if let name = route.name {
                xml += "        <name>\(escapeXML(name))</name>\n"
            }
            for point in route.points {
                xml += "        <rtept lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\">"
                if let name = point.name {
                    xml += "<name>\(escapeXML(name))</name>"
                }
                xml += "</rtept>\n"
            }
            xml += "    </rte>\n"
        }

        xml += "</gpx>"
        return xml
    }
}
