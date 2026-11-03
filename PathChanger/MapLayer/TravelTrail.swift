//
//  TravelTrail.swift
//  PathChanger
//
//  The acknowledged positions a stop mode travelled through, for the map (owner ask
//  2026-11-03). Fed from acknowledged receipts only (PRODUCT_REQUIREMENTS 4). It belongs
//  to one mode and lasts as long as that mode's stop progress: every Move of the
//  sequence extends it; a stop edit (not an append), Reset Route or a confirmed Clear
//  erases it, and another mode's travel starts a new one.
//
//  It is a list of lines: travel that leaves from somewhere other than the trail's end
//  (after a Teleport, a Joystick drive or a Jump arrival) starts a new line, so the map
//  never joins two travels with a line the phone did not drive.
//

import Foundation

@MainActor
final class TravelTrail: ObservableObject {
    /// Most points kept across every segment; past it each segment is halved (keeping
    /// its first and newest point) and, if that is not enough, the oldest segments go.
    static let capacity = 2_000

    @Published private(set) var segments: [[LocationCoordinate]] = []
    /// The stop mode whose travel drew `segments`; nil when there is no trail.
    private(set) var mode: AppMode?

    /// Every point of every segment, in order.
    var points: [LocationCoordinate] { segments.flatMap { $0 } }

    /// Adds an acknowledged point `mode` travelled through, reached from `held` (the
    /// location held before it). It extends the trail only when `held` is the trail's
    /// end; otherwise it starts a new segment. A point of another mode starts a new trail.
    func record(_ coordinate: LocationCoordinate, mode: AppMode, after held: LocationCoordinate?) {
        guard coordinate.isValid else { return }
        if self.mode != mode {
            self.mode = mode
            segments = []
        }
        let startsSegment = held == nil || held != segments.last?.last
        let updated = Self.appending(coordinate, to: segments, startsSegment: startsSegment, capacity: Self.capacity)
        if updated != segments { segments = updated }
    }

    /// The trail as `mode` draws it: only the mode that travelled it shows it.
    func segments(for mode: AppMode) -> [[LocationCoordinate]] {
        self.mode == mode ? segments : []
    }

    func reset() {
        mode = nil
        if !segments.isEmpty { segments = [] }
    }

    /// `segments` with `coordinate` added: as a new segment when `startsSegment` (or
    /// there is none), else to the last one (not when it repeats its last point). Past
    /// `capacity` points in all, every segment is halved, then the oldest segments are
    /// dropped until it fits; the newest point always stays.
    nonisolated static func appending(
        _ coordinate: LocationCoordinate,
        to segments: [[LocationCoordinate]],
        startsSegment: Bool,
        capacity: Int
    ) -> [[LocationCoordinate]] {
        var result = segments
        if startsSegment || result.isEmpty {
            result.append([coordinate])
        } else {
            guard result[result.count - 1].last != coordinate else { return segments }
            result[result.count - 1].append(coordinate)
        }
        let limit = max(capacity, 2)
        guard pointCount(result) > limit else { return result }
        result = result.map(downsampled)
        while pointCount(result) > limit, result.count > 1 { result.removeFirst() }
        if pointCount(result) > limit, let only = result.first { result = [downsampled(only)] }
        return result
    }

    nonisolated private static func pointCount(_ segments: [[LocationCoordinate]]) -> Int {
        segments.reduce(0) { $0 + $1.count }
    }

    /// Every other point, from the first, plus the last point.
    nonisolated static func downsampled(_ points: [LocationCoordinate]) -> [LocationCoordinate] {
        guard points.count > 2 else { return points }
        var result = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}
