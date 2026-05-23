//
//  MapShellTests.swift
//  PathChangerTests
//
//  Smoke tests for the new map-shell UI: ensures the AppPreferences sidebar
//  persistence works and the new design tokens are available.
//
//  Note: SwiftUI view-graph testing is intentionally minimal here. The shell's
//  surface area is well tested by manual launch verification in both system
//  appearances; this file just locks down the wiring that backs the shell.
//

import XCTest
import SwiftUI
@testable import PathChanger

final class MapShellPreferencesTests: XCTestCase {
    private let key = "mapShell.sidebarExpanded"

    override func setUp() {
        super.setUp()
        // Ensure UI defaults are registered (first-launch default = true).
        AppPreferences.registerUIDefaults()
    }

    override func tearDown() {
        // Restore default-true so other tests don't see leaked false state.
        UserDefaults.standard.set(true, forKey: key)
        super.tearDown()
    }

    func testRegisterUIDefaultsSetsSidebarExpandedTrue() {
        // Clear any previously persisted user value so we're testing the
        // registered default rather than a stored preference.
        UserDefaults.standard.removeObject(forKey: key)
        AppPreferences.registerUIDefaults()

        XCTAssertTrue(AppPreferences.shared.isSidebarExpanded,
                      "Fresh installs should default to an expanded sidebar")
    }

    func testSidebarExpandedRoundTrip() {
        let prefs = AppPreferences.shared

        prefs.isSidebarExpanded = false
        XCTAssertFalse(prefs.isSidebarExpanded)

        prefs.isSidebarExpanded = true
        XCTAssertTrue(prefs.isSidebarExpanded)
    }

    func testSidebarExpandedPersistsAcrossNewReads() {
        let prefs = AppPreferences.shared
        prefs.isSidebarExpanded = false

        // The same UserDefaults read by an unrelated reader should reflect
        // the latest write (this asserts we're using the standard suite,
        // not an isolated copy).
        XCTAssertEqual(UserDefaults.standard.bool(forKey: key), false)

        prefs.isSidebarExpanded = true
        XCTAssertEqual(UserDefaults.standard.bool(forKey: key), true)
    }
}

// MARK: - Source wiring

final class MapShellSourceWiringTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testExpandedSidebarHasVisibleCollapseAffordance() throws {
        let sidebar = try readProjectFile("PathChanger/UI/Components/CollapsibleSidebar.swift")
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")

        XCTAssertTrue(sidebar.contains("var onCollapse: () -> Void"))
        XCTAssertTrue(sidebar.contains("mapShellSidebarCollapseButton"))
        XCTAssertTrue(sidebar.contains("Hide sidebar"))
        XCTAssertTrue(shell.contains("onCollapse: toggleSidebar"))
        XCTAssertTrue(shell.contains("SidebarToggleButton"))
    }

    func testMapShellSettingsSheetHasExplicitDismissalAndDeterministicSize() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")

        XCTAssertTrue(shell.contains("SettingsSheetContainer"))
        XCTAssertTrue(shell.contains("mapShellSettingsDoneButton"))
        XCTAssertTrue(shell.contains("SettingsView(showsHeader: false)"))
        XCTAssertTrue(shell.contains(".frame(width: 760, height: 620)"))
    }

    func testSidebarSearchIsModeAwareForRouteAndJoystick() throws {
        let sidebar = try readProjectFile("PathChanger/UI/Components/CollapsibleSidebar.swift")

        XCTAssertTrue(sidebar.contains("switch selectedMode"))
        XCTAssertTrue(sidebar.contains("case .route:"))
        XCTAssertTrue(sidebar.contains("appState.addRoutePoint(coordinate)"))
        XCTAssertTrue(sidebar.contains("select(coordinate: entry.coordinate, name: entry.displayName, source: .recent)"))
        XCTAssertTrue(sidebar.contains("case .joystick:"))
        XCTAssertTrue(sidebar.contains("as joystick start"))
    }

    func testModePanelsExposeCompactStateSummaries() throws {
        // Lock-down: each mode panel must keep its named summary surface and
        // a single short empty-state hint. Width and joystick-radius asserts
        // are kept tight so accidental regressions to the pre-refinement
        // (bulky) sizes will fail this test.
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")
        let joystick = try readProjectFile("PathChanger/UI/JoystickControlView.swift")

        XCTAssertTrue(simulationView.contains("routeSelectedTargetSummary"))
        XCTAssertTrue(simulationView.contains("Search the sidebar or tap the map to add spots."))
        // Refined Teleport panel width (was 260/304/328 — surgically tightened
        // to drop unused inspector slack).
        XCTAssertTrue(simulationView.contains(".frame(minWidth: 260, idealWidth: 296, maxWidth: 312)"))
        // Refined Multi-Spot panel width (was 260/332/380 — brought in to align
        // with Teleport/Joystick for cross-mode consistency).
        XCTAssertTrue(simulationView.contains(".frame(minWidth: 280, idealWidth: 312, maxWidth: 332)"))
        XCTAssertTrue(joystick.contains("joystickStartLocationSummary"))
        // Dead "tap a start point first" caption dropped — the N/S/E/W dial
        // already conveys movement, and startLocationSummary provides the
        // empty-state hint ("No start selected" / "Use sidebar search...").
        // Refined joystick dial (was 58 — reduced to 56 so the joystick fits
        // cleanly inside the refined 312-wide panel without dead space).
        XCTAssertTrue(joystick.contains("private let outerRadius: CGFloat = 56"))
    }
}

// MARK: - Design tokens

final class MapShellDesignTokenTests: XCTestCase {
    func testDynamicTokensExist() {
        // Just ensure the symbols resolve at runtime — the actual color value
        // is appearance-dependent and isn't checked here.
        _ = Color.pcTextDynamic
        _ = Color.pcTextMutedDynamic
        _ = Color.pcOutlineDynamic
        _ = Color.pcSurfaceTintDynamic
        _ = Color.pcSystemBlue
        _ = Color.pcSystemIndigo
        _ = AppActionGradient.primary
        _ = AppActionGradient.avatar
    }

    func testActionGradientsAreUsable() {
        // AppCapsuleActionStyle should construct cleanly for all tones.
        _ = AppCapsuleActionStyle(tone: .accent)
        _ = AppCapsuleActionStyle(tone: .warning)
        _ = AppCapsuleActionStyle(tone: .danger)
    }
}
