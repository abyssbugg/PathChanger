//
//  GPXParserTests.swift
//  PathChangerTests
//
//  Unit tests for GPX parsing functionality
//

import XCTest
@testable import PathChanger

final class GPXParserTests: XCTestCase {

    var parser: GPXParser!

    override func setUp() {
        super.setUp()
        parser = GPXParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Basic Parsing Tests

    func testParseSimpleGPX() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test">
            <metadata>
                <name>Test Route</name>
            </metadata>
            <trk>
                <name>Track 1</name>
                <trkseg>
                    <trkpt lat="35.6762" lon="139.6503"></trkpt>
                    <trkpt lat="35.6770" lon="139.6510"></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)

        XCTAssertEqual(gpx.name, "Test Route")
        XCTAssertEqual(gpx.tracks.count, 1)
        XCTAssertEqual(gpx.tracks.first?.segments.count, 1)
        XCTAssertEqual(gpx.tracks.first?.segments.first?.points.count, 2)
    }

    func testParseRoute() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <rte>
                <name>Test Route</name>
                <rtept lat="35.6762" lon="139.6503"></rtept>
                <rtept lat="35.6770" lon="139.6510"></rtept>
                <rtept lat="35.6780" lon="139.6520"></rtept>
            </rte>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)

        XCTAssertEqual(gpx.routes.count, 1)
        XCTAssertEqual(gpx.routes.first?.points.count, 3)
        XCTAssertEqual(gpx.routes.first?.name, "Test Route")
    }

    func testParseWaypoints() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <wpt lat="35.6762" lon="139.6503">
                <name>Tokyo Tower</name>
            </wpt>
            <wpt lat="40.7128" lon="-74.0060">
                <name>New York</name>
            </wpt>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)

        XCTAssertEqual(gpx.waypoints.count, 2)
        XCTAssertEqual(gpx.waypoints[0].name, "Tokyo Tower")
        XCTAssertEqual(gpx.waypoints[1].name, "New York")
    }

    // MARK: - Coordinate Extraction Tests

    func testAllCoordinatesFromTrack() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk>
                <trkseg>
                    <trkpt lat="35.6762" lon="139.6503"></trkpt>
                    <trkpt lat="35.6770" lon="139.6510"></trkpt>
                </trkseg>
                <trkseg>
                    <trkpt lat="35.6780" lon="139.6520"></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)
        let coords = gpx.allCoordinates

        XCTAssertEqual(coords.count, 3)
    }

    // MARK: - Error Handling Tests

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try parser.parse(data: Data())) { error in
            XCTAssertTrue(error is GPXParserError)
        }
    }

    func testEmptyGPXThrows() {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
        </gpx>
        """

        XCTAssertThrowsError(try parser.parse(string: gpxString)) { error in
            guard let gpxError = error as? GPXParserError else {
                XCTFail("Expected GPXParserError")
                return
            }
            if case .emptyFile = gpxError {
                // Expected
            } else {
                XCTFail("Expected emptyFile error")
            }
        }
    }

    func testInvalidXMLThrows() {
        let invalidXML = "not valid xml <>"

        XCTAssertThrowsError(try parser.parse(string: invalidXML)) { error in
            XCTAssertTrue(error is GPXParserError)
        }
    }

    // MARK: - Distance Calculation Tests

    func testTotalDistance() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk>
                <trkseg>
                    <trkpt lat="35.6762" lon="139.6503"></trkpt>
                    <trkpt lat="35.6862" lon="139.6603"></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)

        // Roughly 1.4km between these points
        XCTAssertGreaterThan(gpx.totalDistance, 1000)
        XCTAssertLessThan(gpx.totalDistance, 2000)
    }

    // MARK: - Total Points Tests

    func testTotalPoints() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <wpt lat="0" lon="0"></wpt>
            <trk>
                <trkseg>
                    <trkpt lat="0" lon="0"></trkpt>
                    <trkpt lat="0" lon="0"></trkpt>
                </trkseg>
            </trk>
            <rte>
                <rtept lat="0" lon="0"></rtept>
            </rte>
        </gpx>
        """

        let gpx = try parser.parse(string: gpxString)

        XCTAssertEqual(gpx.totalPoints, 4) // 1 waypoint + 2 track points + 1 route point
    }
}

// MARK: - Import limits and coordinate validation (audit R5)

/// A GPX document with one track of `points` (lat, lon attribute text, as written).
private func gpxTrack(_ points: [(String, String)]) -> String {
    let body = points.map { "      <trkpt lat=\"\($0.0)\" lon=\"\($0.1)\"></trkpt>" }.joined(separator: "\n")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Test">
      <trk><trkseg>
    \(body)
      </trkseg></trk>
    </gpx>
    """
}

/// A file in the temporary directory, removed by the caller.
private func temporaryGPXFile(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tmp_rovodev_gpx-\(UUID().uuidString).gpx")
    try Data(contents.utf8).write(to: url)
    return url
}

final class GPXParserLimitTests: XCTestCase {
    func testTheDefaultLimitsAreTheNamedConstants() {
        XCTAssertEqual(GPXParser.maximumFileBytes, 20 * 1024 * 1024)
        XCTAssertEqual(GPXParser.maximumPointCount, 200_000)
    }

    func testAFileOverTheByteLimitIsRefusedBeforeItIsRead() throws {
        // A sparse file one byte over the limit: refused from its size, nothing parsed.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_gpx-large-\(UUID().uuidString).gpx")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(GPXParser.maximumFileBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try GPXParser().parse(fileURL: url)) { error in
            guard case GPXParserError.fileTooLarge(let bytes, let limit) = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
            XCTAssertEqual(bytes, GPXParser.maximumFileBytes + 1)
            XCTAssertEqual(limit, GPXParser.maximumFileBytes)
            XCTAssertTrue(error.localizedDescription.contains("too large"), error.localizedDescription)
        }
    }

    func testAFileAtTheByteLimitIsRead() throws {
        let document = gpxTrack([("35.0", "139.0"), ("35.1", "139.1")])
        let url = try temporaryGPXFile(document)
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = GPXParser(maximumFileBytes: document.utf8.count)
        XCTAssertEqual(try parser.parse(fileURL: url).allCoordinates.count, 2)
        XCTAssertThrowsError(try GPXParser(maximumFileBytes: document.utf8.count - 1).parse(fileURL: url)) { error in
            guard case GPXParserError.fileTooLarge = error else { return XCTFail("Expected fileTooLarge, got \(error)") }
        }
    }

    func testDataOverTheByteLimitIsRefused() {
        let data = Data(gpxTrack([("35.0", "139.0"), ("35.1", "139.1")]).utf8)
        XCTAssertThrowsError(try GPXParser(maximumFileBytes: data.count - 1).parse(data: data)) { error in
            guard case GPXParserError.fileTooLarge = error else { return XCTFail("Expected fileTooLarge, got \(error)") }
        }
    }

    func testMorePointsThanTheLimitAreRefused() throws {
        let three = gpxTrack([("35.0", "139.0"), ("35.1", "139.1"), ("35.2", "139.2")])
        XCTAssertEqual(try GPXParser(maximumPointCount: 3).parse(string: three).allCoordinates.count, 3)

        let four = gpxTrack([("35.0", "139.0"), ("35.1", "139.1"), ("35.2", "139.2"), ("35.3", "139.3")])
        XCTAssertThrowsError(try GPXParser(maximumPointCount: 3).parse(string: four)) { error in
            guard case GPXParserError.tooManyPoints(let limit) = error else {
                return XCTFail("Expected tooManyPoints, got \(error)")
            }
            XCTAssertEqual(limit, 3)
            XCTAssertTrue(error.localizedDescription.contains("3"), error.localizedDescription)
        }
    }

    func testWaypointsAndRoutePointsCountTowardTheLimit() {
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <wpt lat="1" lon="1"></wpt>
          <rte><rtept lat="2" lon="2"></rtept></rte>
          <trk><trkseg><trkpt lat="3" lon="3"></trkpt></trkseg></trk>
        </gpx>
        """
        XCTAssertThrowsError(try GPXParser(maximumPointCount: 2).parse(string: document)) { error in
            guard case GPXParserError.tooManyPoints = error else { return XCTFail("Expected tooManyPoints, got \(error)") }
        }
    }

    func testAnInvalidCoordinateIsRefusedNamingItsElementAndLine() {
        let cases: [(lat: String, lon: String, mentions: String)] = [
            ("nan", "139.0", "latitude"),
            ("35.0", "inf", "longitude"),
            ("-infinity", "139.0", "latitude"),
            ("90.5", "139.0", "latitude"),
            ("35.0", "-180.5", "longitude"),
            ("abc", "139.0", "latitude"),
        ]
        for item in cases {
            // The bad point is the second track point, on line 5 of the document.
            let document = gpxTrack([("35.0", "139.0"), (item.lat, item.lon), ("35.2", "139.2")])
            XCTAssertThrowsError(try GPXParser().parse(string: document), "\(item)") { error in
                guard case GPXParserError.invalidCoordinate(let element, let line, _) = error else {
                    return XCTFail("Expected invalidCoordinate for \(item), got \(error)")
                }
                XCTAssertEqual(element, "trkpt", "\(item)")
                XCTAssertEqual(line, 5, "\(item)")
                let message = error.localizedDescription
                XCTAssertTrue(message.contains("<trkpt>"), message)
                XCTAssertTrue(message.contains("line 5"), message)
                XCTAssertTrue(message.contains(item.mentions), message)
            }
        }
    }

    func testAPointWithoutCoordinatesIsRefused() {
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <rte>
            <rtept lat="35.0"></rtept>
          </rte>
        </gpx>
        """
        XCTAssertThrowsError(try GPXParser().parse(string: document)) { error in
            guard case GPXParserError.invalidCoordinate(let element, let line, _) = error else {
                return XCTFail("Expected invalidCoordinate, got \(error)")
            }
            XCTAssertEqual(element, "rtept")
            XCTAssertEqual(line, 4)
            XCTAssertTrue(error.localizedDescription.contains("longitude"), error.localizedDescription)
        }
    }

    func testTheEdgesOfTheValidRangeAreAccepted() throws {
        let document = gpxTrack([("-90", "-180"), ("90", "180"), (" 35.5 ", "139.5")])
        let coordinates = try GPXParser().parse(string: document).allCoordinates
        XCTAssertEqual(coordinates.map(\.latitude), [-90, 90, 35.5])
        XCTAssertEqual(coordinates.map(\.longitude), [-180, 180, 139.5])
    }

    func testExternalEntitiesAreNotResolved() throws {
        let secret = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_gpx-secret-\(UUID().uuidString).txt")
        try Data("SECRET-CONTENTS".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE gpx [<!ENTITY xxe SYSTEM "\(secret.absoluteString)">]>
        <gpx version="1.1">
          <metadata><name>&xxe;</name></metadata>
          <trk><trkseg><trkpt lat="1" lon="1"></trkpt><trkpt lat="2" lon="2"></trkpt></trkseg></trk>
        </gpx>
        """
        if let gpx = try? GPXParser().parse(string: document) {
            XCTAssertFalse(gpx.name.contains("SECRET"), "the external entity must not be read")
        }
    }
}

// MARK: - Route import (audit R5)

@MainActor
final class GPXRouteImportTests: XCTestCase {
    private let a = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let b = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let c = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)

    private func multiSpotState() -> AppState {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector(), routeDelay: { _ in })
        state.activeMode = .route
        for stop in [a, b, c] { state.stageLocation(stop, for: .route) }
        return state
    }

    func testTheFileIsParsedOffTheMainThread() async throws {
        let route = RouteStateManager(routeLibrary: RouteLibraryManager())
        route.switchStops(to: .route)
        let onMain = LockedFlag()
        let (a, b) = (self.a, self.b)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tmp_rovodev_unused.gpx")
        let count = try await route.importRoute(from: url) { _ in
            onMain.set(Thread.isMainThread)
            return [a, b]
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(onMain.value, false, "the GPX file is read and parsed off the main thread")
        XCTAssertEqual(route.currentRoute, [a, b])
    }

    func testTheDefaultImportParsesTheGPXFile() async throws {
        let url = try temporaryGPXFile(gpxTrack([("35.0", "139.0"), ("35.1", "139.1")]))
        defer { try? FileManager.default.removeItem(at: url) }
        let state = multiSpotState()
        await state.importRoute(from: url)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.currentRoute, [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.1),
        ])
        XCTAssertEqual(state.statusMessage, "Imported 2 points")
    }

    func testAFailedImportKeepsTheCurrentRoute() async throws {
        let invalid = try temporaryGPXFile(gpxTrack([("35.0", "139.0"), ("nan", "139.1"), ("35.2", "139.2")]))
        let single = try temporaryGPXFile(gpxTrack([("35.0", "139.0")]))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("tmp_rovodev_missing-\(UUID().uuidString).gpx")
        defer {
            try? FileManager.default.removeItem(at: invalid)
            try? FileManager.default.removeItem(at: single)
        }
        let state = multiSpotState()
        let cursor = state.displayStopCursor(for: .route)
        let epoch = state.route.stopProgressEpoch(for: .route)

        await state.importRoute(from: invalid)
        XCTAssertEqual(state.currentRoute, [a, b, c], "an invalid coordinate leaves the route unchanged")
        XCTAssertTrue(state.lastError?.contains("line 5") ?? false, state.lastError ?? "no error")

        await state.importRoute(from: single)
        XCTAssertEqual(state.currentRoute, [a, b, c], "a one-point file leaves the route unchanged")
        XCTAssertEqual(state.lastError, "GPX file needs at least two points")

        await state.importRoute(from: missing)
        XCTAssertEqual(state.currentRoute, [a, b, c], "an unreadable file leaves the route unchanged")
        XCTAssertNotNil(state.lastError)

        XCTAssertEqual(state.displayStopCursor(for: .route), cursor, "and its progress")
        XCTAssertEqual(state.route.stopProgressEpoch(for: .route), epoch)
    }

    func testAnOversizedFileLeavesTheCurrentRouteUnchanged() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmp_rovodev_gpx-large-\(UUID().uuidString).gpx")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(GPXParser.maximumFileBytes + 1))
        try handle.close()

        let state = multiSpotState()
        await state.importRoute(from: url)
        XCTAssertEqual(state.currentRoute, [a, b, c])
        XCTAssertTrue(state.lastError?.contains("too large") ?? false, state.lastError ?? "no error")
    }

    /// Import keeps every point, also past the mode's on-map stop limit (Multi-Spot holds
    /// 24 clicked stops): a track is not simplified or cut (behavior kept, audit R5).
    func testImportKeepsEveryPointOfATrackLongerThanTheStopLimit() async throws {
        let count = AppMode.route.maxStops + 6
        let points = (0..<count).map { ("\(35 + Double($0) * 0.001)", "139.0") }
        let url = try temporaryGPXFile(gpxTrack(points))
        defer { try? FileManager.default.removeItem(at: url) }
        let state = multiSpotState()
        await state.importRoute(from: url)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.currentRoute.count, count, "no point is dropped or merged")
        XCTAssertEqual(state.statusMessage, "Imported \(count) points")
    }

    /// The route is published when parsing ends: a mode change while the file was read
    /// drops the import instead of replacing the newly shown mode's stops.
    func testAnImportFinishingAfterAModeChangeIsDropped() async throws {
        let route = RouteStateManager(routeLibrary: RouteLibraryManager())
        route.switchStops(to: .route)
        route.addWaypoint(a)
        route.addWaypoint(b)
        let release = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let (b, c) = (self.b, self.c)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tmp_rovodev_unused.gpx")
        let importing = Task { @MainActor in
            try await route.importRoute(from: url) { _ in
                entered.signal()
                // Bounded: a parse on the main actor would otherwise deadlock the test.
                _ = release.wait(timeout: .now() + 5)
                return [c, b, c]
            }
        }
        let didEnter = await Task.detached { entered.wait(timeout: .now() + 10) == .success }.value
        XCTAssertTrue(didEnter, "the reader ran")
        route.switchStops(to: .jump)
        let jumpStops = route.currentRoute
        release.signal()
        do {
            _ = try await importing.value
            XCTFail("the import is dropped")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(route.currentRoute, jumpStops, "the shown mode's stops are untouched")
        XCTAssertEqual(route.stops(for: .route), [a, self.b], "and so are the mode's it began in")
    }
}

/// A Bool written from a background thread and read on the main actor.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    var value: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
}

// MARK: - Writer -> parser round trip (audit R6)

final class GPXRoundTripTests: XCTestCase {
    private func roundTrip(_ file: GPXFile) throws -> GPXFile {
        try GPXParser().parse(string: GPXWriter.createGPX(from: file))
    }

    private func sampleFile() -> GPXFile {
        GPXFile(
            name: "Morning <Loop> & Co",
            description: "Along the river",
            author: "Ada Lovelace",
            time: Date(timeIntervalSince1970: 1_789_000_000),
            waypoints: [
                GPXWaypoint(coordinate: LocationCoordinate(latitude: 35.1, longitude: 139.1), name: "Cafe", elevation: 12.5),
                GPXWaypoint(coordinate: LocationCoordinate(latitude: 35.2, longitude: 139.2), name: "Bridge"),
            ],
            tracks: [
                GPXTrack(name: "Track One", segments: [
                    GPXTrackSegment(points: [
                        GPXTrackPoint(coordinate: LocationCoordinate(latitude: 35.3, longitude: 139.3), elevation: 4),
                        GPXTrackPoint(coordinate: LocationCoordinate(latitude: 35.4, longitude: 139.4)),
                    ]),
                    GPXTrackSegment(points: [
                        GPXTrackPoint(coordinate: LocationCoordinate(latitude: 35.5, longitude: 139.5)),
                    ]),
                ]),
            ],
            routes: [
                GPXRoute(name: "Route One", points: [
                    GPXRoutePoint(coordinate: LocationCoordinate(latitude: 35.6, longitude: 139.6), name: "Start"),
                    GPXRoutePoint(coordinate: LocationCoordinate(latitude: 35.7, longitude: 139.7), name: "End"),
                ]),
            ]
        )
    }

    func testTheTitleAndAuthorSurviveARoundTrip() throws {
        let parsed = try roundTrip(sampleFile())
        XCTAssertEqual(parsed.name, "Morning <Loop> & Co", "the author's name must not replace the title")
        XCTAssertEqual(parsed.author, "Ada Lovelace", "the author is read from <author><name>")
        XCTAssertEqual(parsed.description, "Along the river")
        XCTAssertEqual(parsed.time, Date(timeIntervalSince1970: 1_789_000_000))
    }

    func testWaypointsSurviveARoundTrip() throws {
        let parsed = try roundTrip(sampleFile())
        XCTAssertEqual(parsed.waypoints.map(\.coordinate), sampleFile().waypoints.map(\.coordinate))
        XCTAssertEqual(parsed.waypoints.map(\.name), ["Cafe", "Bridge"])
        XCTAssertEqual(parsed.waypoints.map(\.elevation), [12.5, nil])
    }

    func testTracksSurviveARoundTrip() throws {
        let parsed = try roundTrip(sampleFile())
        XCTAssertEqual(parsed.tracks.count, 1)
        XCTAssertEqual(parsed.tracks.first?.name, "Track One")
        XCTAssertEqual(parsed.tracks.first?.segments.map { $0.points.map(\.coordinate) },
                       sampleFile().tracks.first?.segments.map { $0.points.map(\.coordinate) })
        XCTAssertEqual(parsed.tracks.first?.segments.first?.points.map(\.elevation), [4, nil])
    }

    func testRoutesSurviveARoundTrip() throws {
        let parsed = try roundTrip(sampleFile())
        XCTAssertEqual(parsed.routes.count, 1)
        XCTAssertEqual(parsed.routes.first?.name, "Route One", "a route point's name must not replace the route's")
        XCTAssertEqual(parsed.routes.first?.points.map(\.coordinate), sampleFile().routes.first?.points.map(\.coordinate))
        XCTAssertEqual(parsed.routes.first?.points.map(\.name), ["Start", "End"])
        XCTAssertEqual(parsed.allCoordinates, sampleFile().allCoordinates)
    }

    func testAFileWithoutAuthorOrDescriptionRoundTrips() throws {
        var file = sampleFile()
        file.author = nil
        file.description = nil
        let parsed = try roundTrip(file)
        XCTAssertEqual(parsed.name, file.name)
        XCTAssertNil(parsed.author)
        XCTAssertNil(parsed.description)
    }

    func testTheCoordinateWriterRoundTripsItsName() throws {
        let coordinates = [LocationCoordinate(latitude: 1, longitude: 2), LocationCoordinate(latitude: 3, longitude: 4)]
        let parsed = try GPXParser().parse(string: GPXWriter.createGPX(from: coordinates, name: "Walk"))
        XCTAssertEqual(parsed.name, "Walk")
        XCTAssertEqual(parsed.tracks.first?.name, "Walk")
        XCTAssertEqual(parsed.allCoordinates, coordinates)
    }

    /// GPX 1.0 has <name>, <desc> and a text <author> directly under <gpx>.
    func testGPX10TopLevelMetadataIsStillRead() throws {
        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.0" creator="Test">
          <name>Old Title</name>
          <desc>Old description</desc>
          <author>Grace Hopper</author>
          <wpt lat="1" lon="2"><name>Point</name><desc>Point description</desc></wpt>
        </gpx>
        """
        let parsed = try GPXParser().parse(string: document)
        XCTAssertEqual(parsed.name, "Old Title")
        XCTAssertEqual(parsed.description, "Old description", "a waypoint's desc must not replace the file's")
        XCTAssertEqual(parsed.author, "Grace Hopper")
        XCTAssertEqual(parsed.waypoints.first?.name, "Point")
        XCTAssertEqual(parsed.waypoints.first?.description, "Point description")
    }
}
