//
//  StopTravelCardText.swift
//  PathChanger
//
//  What the mode card shows for the stop-by-stop options of Jump, Two-Spot and
//  Multi-Spot (PRODUCT_REQUIREMENTS 3.2-3.4 and 3.6), chosen without the view so it
//  can be tested.
//

import SwiftUI

enum StopTravelCardText {
    /// One stop option row in the card, in display order.
    enum Control: String, CaseIterable, Identifiable {
        case arrival, jumpTiming, hold, progression, repeatMode

        var id: String { rawValue }

        var label: String {
            switch self {
            case .arrival: return "Getting there"
            case .jumpTiming: return "Jump timing"
            case .hold: return "At each stop"
            case .progression: return "Go through"
            case .repeatMode: return "Repeat"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .arrival: return "location.stops.arrival"
            case .jumpTiming: return "location.stops.jumpTiming"
            case .hold: return "location.stops.hold"
            case .progression: return "location.stops.progression"
            case .repeatMode: return "location.stops.repeat"
            }
        }
    }

    static let progressIdentifier = "location.stops.progress"
    static let pauseIdentifier = "location.action.pauseMovement"

    static let holdRange: ClosedRange<Double> = StopTravelSettings.holdRange
    static let holdStep: Double = 1

    static let jumpTimingCaption =
        "Realistic waits the trip time at the travel speed (road distance when known)."
    static let defaultFallbackNote = "No road route found; travelling in a straight line"

    // MARK: Which controls show

    /// Teleport and Joystick have no stops; only Jump, Two-Spot and Multi-Spot do.
    static func showsStopOptions(for mode: AppMode) -> Bool {
        RouteStateManager.stopModes.contains(mode)
    }

    /// The rows to show: Jump timing only applies when Getting there is Jump.
    static func visibleControls(for mode: AppMode, settings: StopTravelSettings) -> [Control] {
        guard showsStopOptions(for: mode) else { return [] }
        return Control.allCases.filter { $0 != .jumpTiming || settings.arrival == .jump }
    }

    // MARK: Option titles

    static func title(_ arrival: StopTravelSettings.Arrival) -> String {
        switch arrival {
        case .travel: return "Travel"
        case .jump: return "Jump"
        }
    }

    static func title(_ timing: StopTravelSettings.JumpTiming) -> String {
        switch timing {
        case .fixed: return "Fixed"
        case .realistic: return "Realistic"
        }
    }

    static func title(_ progression: StopTravelSettings.Progression) -> String {
        switch progression {
        case .automatic: return "Automatically"
        case .onePerMove: return "One stop per Move"
        }
    }

    static func title(_ repeatMode: StopTravelSettings.RepeatMode) -> String {
        switch repeatMode {
        case .oneWay: return "One way"
        case .loop: return "Loop"
        case .backAndForth: return "Back and forth"
        }
    }

    // MARK: At each stop

    static func holdLabel(_ seconds: Double) -> String {
        let whole = wholeSeconds(seconds)
        return whole == 0 ? "No wait" : "\(whole) s"
    }

    static func holdAccessibilityValue(_ seconds: Double) -> String {
        switch wholeSeconds(seconds) {
        case 0: return "0 seconds, no wait"
        case 1: return "1 second"
        case let whole: return "\(whole) seconds"
        }
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int(seconds.rounded())
    }

    // MARK: Live readout

    struct ProgressLine: Equatable, Identifiable {
        enum Kind: String, Equatable {
            case paused, holding, nextStop, timeLeft, fallback, routeNote
        }

        let kind: Kind
        let text: String

        var id: String { kind.rawValue }
    }

    /// One line per fact, each its own accessibility element: Paused, the hold
    /// countdown, the next stop (1-based), the time left in the leg, the straight-line
    /// note when the leg has no road route, and the road route's own note (a detour or
    /// a long route) when it has one.
    static func progressLines(_ progress: StopProgress) -> [ProgressLine] {
        var lines: [ProgressLine] = []
        if progress.isPaused {
            lines.append(ProgressLine(kind: .paused, text: "Paused"))
        }
        if let holdLeft = progress.holdSecondsLeft {
            let held = (progress.heldStopIndex ?? max(progress.nextStopIndex - 1, 0)) + 1
            lines.append(ProgressLine(kind: .holding, text: "Holding stop \(held): \(roundedUpSeconds(holdLeft))s"))
        }
        let total = max(progress.totalStops, 0)
        let next = min(max(progress.nextStopIndex, 0) + 1, max(total, 1))
        lines.append(ProgressLine(kind: .nextStop, text: "Next stop: \(next) of \(total)"))
        if let legLeft = progress.legSecondsLeft {
            lines.append(ProgressLine(kind: .timeLeft, text: "Time left: \(clock(legLeft))"))
        }
        if progress.usesStraightLineFallback {
            lines.append(ProgressLine(kind: .fallback, text: progress.fallbackNote ?? defaultFallbackNote))
        }
        if let routeNote = progress.routeNote, !routeNote.isEmpty {
            lines.append(ProgressLine(kind: .routeNote, text: routeNote))
        }
        return lines
    }

    /// m:ss, rounded up so a countdown reaches 0:00 only when the time is up.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = roundedUpSeconds(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func roundedUpSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds - 1e-9).rounded(.up))
    }

    // MARK: Move gating

    /// Jump's Move is possible while the planner has a next hop for these stops: a
    /// finished One way run cannot continue, but Loop and Back and forth can.
    static func jumpCanMove(stops: [LocationCoordinate], cursor: StopCursor, settings: StopTravelSettings) -> Bool {
        StopTravelPlanner.firstLeg(stops: stops.filter(\.isValid), origin: nil, cursor: cursor, settings: settings) != nil
    }

    // MARK: Pause / Resume

    struct PauseButton: Equatable {
        enum Action: Equatable { case pause, resume }

        let title: String
        let systemImage: String
        let action: Action
    }

    /// Shown only while a stop run is active (`stopProgress` is set).
    static func pauseButton(progress: StopProgress?, isPaused: Bool) -> PauseButton? {
        guard progress != nil else { return nil }
        return isPaused
            ? PauseButton(title: "Resume", systemImage: "play.fill", action: .resume)
            : PauseButton(title: "Pause", systemImage: "pause.fill", action: .pause)
    }

    @MainActor
    static func perform(_ action: PauseButton.Action, on appState: AppState) {
        switch action {
        case .pause: appState.pauseMovement()
        case .resume: appState.resumeMovement()
        }
    }

    // MARK: Editing during a run

    /// The options stay editable during a run. The engine runs on the options it took
    /// at Move (`StopRun.settings`), and `AppState.setStopTravelSettings` ends a run of
    /// that mode when its options change, holding the last acknowledged point
    /// (PRODUCT_REQUIREMENTS 3.2: turning Auto jump off ends the sequence and holds).
    /// That is safe, so the card says so instead of disabling the controls.
    static func runEditNote(isRunActive: Bool) -> String? {
        isRunActive ? "Changing an option ends this run and holds the current location." : nil
    }
}

extension AppState {
    /// A binding to one stop option of `mode`, written through `setStopTravelSettings`.
    func stopSettingBinding<Value>(
        _ keyPath: WritableKeyPath<StopTravelSettings, Value>,
        for mode: AppMode
    ) -> Binding<Value> {
        Binding(
            get: { self.stopTravelSettings(for: mode)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.stopTravelSettings(for: mode)
                settings[keyPath: keyPath] = newValue
                self.setStopTravelSettings(settings, for: mode)
            }
        )
    }

    /// The At each stop slider: whole seconds, 0-60 (0 = no wait).
    func stopHoldBinding(for mode: AppMode) -> Binding<Double> {
        let hold = stopSettingBinding(\.holdSeconds, for: mode)
        return Binding(
            get: { hold.wrappedValue },
            set: { hold.wrappedValue = $0.isFinite ? $0.rounded() : 0 }
        )
    }
}
