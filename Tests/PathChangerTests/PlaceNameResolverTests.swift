//
//  PlaceNameResolverTests.swift
//  PathChangerTests
//
//  The place or street name of the spoofed location (PRODUCT_REQUIREMENTS §3.5, owner
//  decision 2026-11-02). Every test injects the geocoder, clock and sleep, so nothing
//  here reaches the network or waits in real time.
//

import XCTest
@testable import PathChanger

// MARK: - Formatter

final class PlaceNameFormatterTests: XCTestCase {
    func testStreetAddressWithNumberAndLocality() {
        let place = PlaceDescription(
            name: "107 Forest Retreat Rd",
            subThoroughfare: "107",
            thoroughfare: "Forest Retreat Rd",
            locality: "Hendersonville",
            administrativeArea: "NC"
        )
        XCTAssertEqual(PlaceNameFormatter.name(for: place), "107 Forest Retreat Rd, Hendersonville")
    }

    func testStreetWithoutNumber() {
        let place = PlaceDescription(thoroughfare: "Main St", locality: "Springfield")
        XCTAssertEqual(PlaceNameFormatter.name(for: place), "Main St, Springfield")
    }

    func testStreetWithoutLocalityUsesTheAdministrativeArea() {
        let place = PlaceDescription(thoroughfare: "Main St", administrativeArea: "NC")
        XCTAssertEqual(PlaceNameFormatter.name(for: place), "Main St, NC")
    }

    func testStreetAlone() {
        XCTAssertEqual(PlaceNameFormatter.name(for: PlaceDescription(thoroughfare: "Main St")), "Main St")
    }

    func testNamedPlaceWithoutStreet() {
        let place = PlaceDescription(name: "Central Park", locality: "New York", administrativeArea: "NY")
        XCTAssertEqual(PlaceNameFormatter.name(for: place), "Central Park, New York")
    }

    func testRepeatedPartsAreNotShownTwice() {
        let place = PlaceDescription(name: "Hendersonville", locality: "Hendersonville", administrativeArea: "NC")
        XCTAssertEqual(PlaceNameFormatter.name(for: place), "Hendersonville, NC")
    }

    func testAdministrativeAreaAlone() {
        XCTAssertEqual(PlaceNameFormatter.name(for: PlaceDescription(administrativeArea: "NC")), "NC")
    }

    func testBlankPlaceHasNoName() {
        XCTAssertNil(PlaceNameFormatter.name(for: PlaceDescription()))
        XCTAssertNil(PlaceNameFormatter.name(for: PlaceDescription(name: "  ", thoroughfare: "", locality: " ")))
    }
}

// MARK: - Resolver

@MainActor
final class PlaceNameResolverTests: XCTestCase {
    // Hendersonville, NC. At this latitude 0.001° of latitude is about 111 m.
    private let home = LocationCoordinate(latitude: 35.3187, longitude: -82.4610)
    private let homePlace = PlaceDescription(subThoroughfare: "107", thoroughfare: "Forest Retreat Rd", locality: "Hendersonville")
    private let homeName = "107 Forest Retreat Rd, Hendersonville"

    private func north(_ meters: Double, of point: LocationCoordinate? = nil) -> LocationCoordinate {
        let base = point ?? home
        return LocationCoordinate(latitude: base.latitude + meters / 111_000, longitude: base.longitude)
    }

    private func makeResolver(
        geocoder: FakeReverseGeocoder,
        clock: PlaceNameTestClock,
        cacheLimit: Int = 64
    ) -> PlaceNameResolver {
        PlaceNameResolver(
            geocoder: geocoder,
            minimumInterval: 4,
            minimumDistance: 30,
            fallbackRadius: 200,
            cacheLimit: cacheLimit,
            now: { clock.now },
            sleep: { seconds in await clock.sleep(seconds) }
        )
    }

    private func settle(_ resolver: PlaceNameResolver) async {
        await resolver.pendingLookup?.value
    }

    func testShowsTheNameOfTheAppliedCoordinate() async {
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)

        resolver.update(for: home)
        await settle(resolver)

        XCTAssertEqual(resolver.placeName, homeName)
        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home])
    }

    func testNoAppliedCoordinateShowsNoName() async {
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        resolver.update(for: nil)

        XCTAssertNil(resolver.placeName)
        let requests = await geocoder.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testClearingWhileALookupRunsDropsItsResult() async {
        let geocoder = FakeReverseGeocoder(holdsCalls: true)
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        let lookup = resolver.pendingLookup
        let reached1 = await geocoder.waitForRequests(1)
        XCTAssertTrue(reached1, "the geocoder never got request 1")

        resolver.update(for: nil)
        await geocoder.releaseAll()
        await lookup?.value

        XCTAssertNil(resolver.placeName)
    }

    func testSmallMoveDoesNotLookUpAgain() async {
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        clock.advance(10)
        resolver.update(for: north(10))
        await settle(resolver)

        XCTAssertEqual(resolver.placeName, homeName)
        let requests = await geocoder.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testSecondLookupWaitsForTheThrottleInterval() async {
        let away = north(500)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.success(PlaceDescription(thoroughfare: "Church St", locality: "Hendersonville")), near: away)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        clock.advance(1)
        resolver.update(for: away)

        XCTAssertNil(resolver.placeName, "the old name is 500 m away: show nothing rather than the wrong street")
        await settle(resolver)
        XCTAssertEqual(resolver.placeName, "Church St, Hendersonville")
        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, away])
        XCTAssertEqual(clock.sleeps.count, 1)
        XCTAssertEqual(clock.sleeps.first ?? 0, 3, accuracy: 1e-9, "waits only for the rest of the 4 s interval")
    }

    func testRapidMovementSendsOneLookupForTheNewestPoint() async {
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        var point = home
        for _ in 0..<10 {
            clock.advance(0.1)
            point = north(50, of: point)
            resolver.update(for: point)
        }
        await settle(resolver)

        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, point], "one throttled lookup, for the newest point")
    }

    func testNewestWinsOverAStaleInFlightResult() async {
        let away = north(2_000)
        let geocoder = FakeReverseGeocoder(holdsCalls: true)
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.success(PlaceDescription(name: "Jump Off Rock")), near: away)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        let staleLookup = resolver.pendingLookup
        let reached1 = await geocoder.waitForRequests(1)
        XCTAssertTrue(reached1, "the geocoder never got request 1")

        resolver.update(for: away)
        await geocoder.releaseAll()
        await staleLookup?.value

        XCTAssertNotEqual(resolver.placeName, homeName, "the result for the old point must not show for the new one")

        let reached2 = await geocoder.waitForRequests(2)
        XCTAssertTrue(reached2, "the geocoder never got request 2")
        await geocoder.releaseAll()
        await settle(resolver)
        XCTAssertEqual(resolver.placeName, "Jump Off Rock")
    }

    func testCachedPlaceShowsAtOnceWithoutARequest() async {
        let away = north(2_000)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.success(PlaceDescription(name: "Jump Off Rock")), near: away)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)
        clock.advance(5)
        resolver.update(for: away)
        await settle(resolver)

        clock.advance(1)
        resolver.update(for: home)

        XCTAssertEqual(resolver.placeName, homeName, "shown without waiting for the throttle")
        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, away])
    }

    func testCacheEvictsTheLeastRecentlyUsedPlace() async {
        let second = north(2_000)
        let third = north(4_000)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.success(PlaceDescription(name: "Second")), near: second)
        await geocoder.setResult(.success(PlaceDescription(name: "Third")), near: third)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock, cacheLimit: 2)

        for point in [home, second, home, third] {   // home is touched again before third
            resolver.update(for: point)
            await settle(resolver)
            clock.advance(5)
        }
        resolver.update(for: home)                    // still cached
        await settle(resolver)
        clock.advance(5)
        resolver.update(for: second)                  // evicted by third
        await settle(resolver)

        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, second, third, second])
        XCTAssertEqual(resolver.placeName, "Second")
    }

    func testFailedLookupKeepsTheLastNameWithinTheFallbackRadius() async {
        let nearby = north(100)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.failure(ReverseGeocodingError.network), near: nearby)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        clock.advance(5)
        resolver.update(for: nearby)
        await settle(resolver)

        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, nearby])
        XCTAssertEqual(resolver.placeName, homeName)
    }

    func testFailedLookupDropsANameBeyondTheFallbackRadius() async {
        let farther = north(300)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.failure(ReverseGeocodingError.throttled), near: farther)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        clock.advance(5)
        resolver.update(for: farther)
        await settle(resolver)

        XCTAssertNil(resolver.placeName)
    }

    func testPlaceWithoutAUsableNameCountsAsNoResult() async {
        let nearby = north(100)
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.success(homePlace), near: home)
        await geocoder.setResult(.success(PlaceDescription()), near: nearby)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)

        clock.advance(5)
        resolver.update(for: nearby)
        await settle(resolver)

        XCTAssertEqual(resolver.placeName, homeName, "falls back like any other miss")
    }

    /// Review 2026-11-02 finding 13: at joystick or driving speed every 30 m move used to
    /// cancel the lookup in flight, so no name ever showed. A lookup whose point is still
    /// near the dot finishes and shows; only the newest point is looked up next.
    func testMovingWhileALookupRunsLetsItFinishAndLooksUpTheNewestPointNext() async {
        let geocoder = FakeReverseGeocoder(holdsCalls: true)
        await geocoder.setResult(.success(homePlace), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        let firstLookup = resolver.pendingLookup
        let reached1 = await geocoder.waitForRequests(1)
        XCTAssertTrue(reached1, "the geocoder never got request 1")

        var point = home
        for _ in 0..<3 {
            clock.advance(1)
            point = north(50, of: point)
            resolver.update(for: point)
        }
        await geocoder.setResult(.success(PlaceDescription(thoroughfare: "Church St", locality: "Hendersonville")), near: point)
        await geocoder.releaseAll()
        await firstLookup?.value

        XCTAssertEqual(resolver.placeName, homeName, "the dot is 150 m from home: its name still applies")

        let reached2 = await geocoder.waitForRequests(2)
        XCTAssertTrue(reached2, "the newest point is looked up next")
        await geocoder.releaseAll()
        await settle(resolver)
        let requests = await geocoder.requests
        XCTAssertEqual(requests, [home, point], "one request per point that matters, the newest last")
        XCTAssertEqual(resolver.placeName, "Church St, Hendersonville")
    }

    func testFailedPointIsRetriedOnTheNextUpdate() async {
        let geocoder = FakeReverseGeocoder()
        await geocoder.setResult(.failure(ReverseGeocodingError.network), near: home)
        let clock = PlaceNameTestClock()
        let resolver = makeResolver(geocoder: geocoder, clock: clock)
        resolver.update(for: home)
        await settle(resolver)
        XCTAssertNil(resolver.placeName)

        await geocoder.setResult(.success(homePlace), near: home)
        clock.advance(1)
        resolver.update(for: north(5))
        await settle(resolver)

        XCTAssertEqual(resolver.placeName, homeName)
        let requests = await geocoder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(clock.sleeps.first ?? 0, 3, accuracy: 1e-9, "the retry still respects the 4 s interval")
    }
}

// MARK: - Fakes

@MainActor
final class PlaceNameTestClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private(set) var sleeps: [TimeInterval] = []

    func advance(_ seconds: TimeInterval) {
        now += seconds
    }

    /// Records the wait and moves time on at once.
    func sleep(_ seconds: TimeInterval) {
        sleeps.append(seconds)
        now += seconds
    }
}

actor FakeReverseGeocoder: ReverseGeocoding {
    private(set) var requests: [LocationCoordinate] = []
    private var results: [(point: LocationCoordinate, result: Result<PlaceDescription, Error>)] = []
    private let holdsCalls: Bool
    private var held: [CheckedContinuation<Void, Never>] = []

    init(holdsCalls: Bool = false) {
        self.holdsCalls = holdsCalls
    }

    func setResult(_ result: Result<PlaceDescription, Error>, near point: LocationCoordinate) {
        results.removeAll { Geo.distance(from: $0.point, to: point) < 1 }
        results.append((point, result))
    }

    func reverseGeocode(_ coordinate: LocationCoordinate) async throws -> PlaceDescription {
        requests.append(coordinate)
        if holdsCalls {
            await withCheckedContinuation { held.append($0) }
        }
        let match = results.min { Geo.distance(from: $0.point, to: coordinate) < Geo.distance(from: $1.point, to: coordinate) }
        guard let match, Geo.distance(from: match.point, to: coordinate) < 25 else {
            throw ReverseGeocodingError.noResult
        }
        return try match.result.get()
    }

    /// Polls instead of suspending so a regression fails the test instead of hanging the suite.
    @discardableResult
    func waitForRequests(_ count: Int, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while requests.count < count {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    func releaseAll() {
        let calls = held
        held.removeAll()
        calls.forEach { $0.resume() }
    }
}
