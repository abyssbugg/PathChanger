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

    // MARK: - Wave 2 Hardening Tests

    func testParserSkipsOutOfRangeCoordinates() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk><trkseg>
                <trkpt lat="35.0" lon="139.0"></trkpt>
                <trkpt lat="120.0" lon="500.0"></trkpt>
                <trkpt lat="36.0" lon="140.0"></trkpt>
            </trkseg></trk>
        </gpx>
        """
        let gpx = try parser.parse(string: gpxString)
        XCTAssertEqual(gpx.tracks.first?.segments.first?.points.count, 2, "out-of-range point must be skipped")
        XCTAssertEqual(parser.skippedInvalidCoordinateCount, 1)
    }

    func testRoutePointNameDoesNotOverwriteRouteName() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <rte>
                <name>My Route</name>
                <rtept lat="35.0" lon="139.0"><name>Start</name></rtept>
                <rtept lat="36.0" lon="140.0"><name>End</name></rtept>
            </rte>
        </gpx>
        """
        let gpx = try parser.parse(string: gpxString)
        XCTAssertEqual(gpx.routes.first?.name, "My Route")
        XCTAssertEqual(gpx.routes.first?.points.first?.name, "Start")
        XCTAssertEqual(gpx.routes.first?.points.last?.name, "End")
    }

    func testNestedAuthorNameSetsAuthorNotGPXName() throws {
        let gpxString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <metadata>
                <name>Doc Name</name>
                <author><name>Jane</name></author>
            </metadata>
            <wpt lat="1.0" lon="2.0"></wpt>
        </gpx>
        """
        let gpx = try parser.parse(string: gpxString)
        XCTAssertEqual(gpx.name, "Doc Name")
        XCTAssertEqual(gpx.author, "Jane")
    }

    func testOversizedDataIsRejected() {
        // A data blob just over the cap must be rejected before parsing.
        let oversized = Data(count: GPXParser.maxDataBytes + 1)
        XCTAssertThrowsError(try parser.parse(data: oversized)) { error in
            guard case GPXParserError.fileTooLarge = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
        }
    }
}
