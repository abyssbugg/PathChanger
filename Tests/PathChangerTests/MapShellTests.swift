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
        // Redesigned shell hosts the visible toggle in its topbar.
        XCTAssertTrue(shell.contains("mapShellSidebarToggle"))
    }

    func testMapShellSettingsSheetHasExplicitDismissalAndDeterministicSize() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")

        XCTAssertTrue(shell.contains("SettingsSheetContainer"))
        XCTAssertTrue(shell.contains("mapShellSettingsDoneButton"))
        XCTAssertTrue(shell.contains("SettingsView(showsHeader: false)"))
        XCTAssertTrue(shell.contains(".frame(width: DS.Metrics.settingsContentMaxWidth, height: DS.Metrics.settingsSheetHeight)"))
    }

    func testMainWindowLifecycleIsRecoverableAfterDeviceRefresh() throws {
        let app = try readProjectFile("PathChanger/PathChangerApp.swift")
        let delegate = try readProjectFile("PathChanger/AppDelegate.swift")

        XCTAssertTrue(app.contains("WindowGroup(id: \"main\")"))
        XCTAssertTrue(app.contains("@Environment(\\.openWindow)"))
        XCTAssertTrue(app.contains("@Environment(\\.scenePhase)"))
        XCTAssertTrue(app.contains("openWindow(id: \"main\")"))
        XCTAssertTrue(app.contains("main_window_lifecycle"))

        XCTAssertTrue(delegate.contains("applicationShouldHandleReopen"))
        XCTAssertTrue(delegate.contains("makeKeyAndOrderFront"))
        XCTAssertTrue(delegate.contains("applicationShouldTerminateAfterLastWindowClosed"))
        XCTAssertTrue(delegate.contains("return false"))
        XCTAssertTrue(delegate.contains("window_lifecycle"))
    }

    func testSidebarSearchIsModeAwareForRouteAndJoystick() throws {
        let sidebar = try readProjectFile("PathChanger/UI/Components/CollapsibleSidebar.swift")

        XCTAssertTrue(sidebar.contains("switch selectedMode"))
        XCTAssertTrue(sidebar.contains("case .route:"))
        XCTAssertTrue(sidebar.contains("Selected \\(name) as route spot. Use Add Waypoint to include it in the route."))
        XCTAssertTrue(sidebar.contains("select(coordinate: entry.coordinate, name: entry.displayName)"))
        XCTAssertFalse(sidebar.contains("appState.addRoutePoint(coordinate)"))
        XCTAssertFalse(sidebar.contains("source: .recent"))
        XCTAssertTrue(sidebar.contains("case .joystick:"))
        XCTAssertTrue(sidebar.contains("as joystick start"))
    }
    func testSidebarShortcutWiringUsesCommandBackslashEverywhere() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")
        let accessibility = try readProjectFile("PathChanger/UI/Accessibility.swift")
        let readme = try readProjectFile("README.md")

        XCTAssertTrue(shell.contains(".keyboardShortcut(\"\\\\\", modifiers: .command)"))
        XCTAssertTrue(accessibility.contains("static let showSidebar = KeyboardShortcut(\"\\\\\", modifiers: .command)"))
        XCTAssertTrue(readme.contains("| `⌘\\` | Toggle sidebar |"))
        XCTAssertFalse(accessibility.contains("KeyboardShortcut(\"s\", modifiers: [.command, .shift])"))
        XCTAssertFalse(readme.contains("| `⌘⇧S` | Toggle sidebar |"))
    }

    func testAuthorityCopyNamesCanonicalShellReadinessAndExecutionOwners() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")
        let primary = try readProjectFile("PathChanger/UI/Components/PrimaryActionPill.swift")
        let device = try readProjectFile("PathChanger/UI/Components/DeviceTunnelPill.swift")
        let connection = try readProjectFile("PathChanger/UI/Components/ConnectionPill.swift")
        let content = try readProjectFile("PathChanger/UI/ContentView.swift")

        XCTAssertTrue(shell.contains("MainMapShell is the single production shell layout authority."))
        XCTAssertTrue(primary.contains("PrimaryActionPill is the SOLE production T0 execution authority."))
        // Governed top-bar swap: readiness authority reassigned to ConnectionPill.
        XCTAssertTrue(connection.contains("ConnectionPill is the SOLE production Phase-1 readiness authority."))
        XCTAssertTrue(device.contains("SUPERSEDED"))
        XCTAssertFalse(device.contains("DeviceTunnelPill is the SOLE production Phase-1 readiness authority."))
        XCTAssertTrue(content.contains("PrimaryActionPill remains the sole production T0 execution"))
        XCTAssertTrue(content.contains("ConnectionPill remains the sole production"))
        XCTAssertFalse(content.contains("DeviceTunnelPill remains the sole production"))
    }

    func testTopBarMountsRedesignClusterAndRetiresLegacyPill() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")

        // The redesigned shell renders a fixed mockup topbar (brand block +
        // connection pill + device dropdown + theme toggle) and must not
        // remount the superseded DeviceTunnelPill.
        XCTAssertTrue(shell.contains("private var topBar"))
        XCTAssertTrue(shell.contains("ConnectionPill()"))
        XCTAssertTrue(shell.contains("DeviceDropdown()"))
        XCTAssertTrue(shell.contains("ThemeToggle()"))
        XCTAssertFalse(shell.contains("DeviceTunnelPill()"))
    }

    func testShellRendersMockupFourRegionLayout() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")
        let panel = try readProjectFile("PathChanger/UI/Components/ModeControlPanel.swift")

        // Topbar / (rail | embedded map | mode panel) / footer.
        XCTAssertTrue(shell.contains("SimulationView(mode: selectedMode, embedded: true)"))
        XCTAssertTrue(shell.contains("ModeControlPanel(selectedMode: $selectedMode)"))
        XCTAssertTrue(shell.contains("TelemetryBar()"))
        // Panel docks the execution authority full-width and owns the tabs.
        XCTAssertTrue(panel.contains("PrimaryActionPill(mode: selectedMode, fullWidth: true)"))
        XCTAssertTrue(panel.contains("modeTabStrip"))
        XCTAssertTrue(panel.contains("SOLE production T0 execution"))
        XCTAssertFalse(panel.contains("startSimulation("))
        XCTAssertFalse(panel.contains("stopSimulation("))
    }

    func testLibraryFlyoutIsMountedAndSubordinate() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")
        let flyout = try readProjectFile("PathChanger/UI/Components/LibraryFlyout.swift")
        let sidebar = try readProjectFile("PathChanger/UI/Components/CollapsibleSidebar.swift")

        // Mounted from the shell, opened via sidebar Library nav items.
        XCTAssertTrue(shell.contains("LibraryFlyout("))
        XCTAssertTrue(shell.contains("selectLibraryPlace"))
        XCTAssertTrue(sidebar.contains("mapShellHistoryButton"))
        XCTAssertTrue(sidebar.contains("mapShellFavoritesButton"))

        // Subordinate guarantee: the flyout must never grow execution
        // gestures — selection is target-only.
        XCTAssertFalse(flyout.contains("startSimulation("))
        XCTAssertFalse(flyout.contains("stopSimulation("))
        XCTAssertFalse(flyout.contains("setLocation("))
        XCTAssertTrue(flyout.contains("SOLE production T0 execution"))

        // Interaction parity with the mockup flyout: scrim dismiss, close
        // button, Escape.
        XCTAssertTrue(flyout.contains("onTapGesture { close() }"))
        XCTAssertTrue(flyout.contains("libraryFlyoutClose"))
        XCTAssertTrue(flyout.contains(".keyboardShortcut(.cancelAction)"))
    }

    func testTelemetryBarIsMountedAndDisplayOnly() throws {
        let shell = try readProjectFile("PathChanger/UI/MainMapShell.swift")
        let telemetry = try readProjectFile("PathChanger/UI/Components/TelemetryBar.swift")

        XCTAssertTrue(shell.contains("TelemetryBar()"))
        // Display-only guarantee: the telemetry strip must not grow execution
        // gestures — PrimaryActionPill is the SOLE production T0 execution
        // authority (stop included).
        XCTAssertFalse(telemetry.contains("stopSimulation"))
        XCTAssertFalse(telemetry.contains("startSimulation"))
        XCTAssertFalse(telemetry.contains("setLocation"))
        XCTAssertTrue(telemetry.contains("PrimaryActionPill is the SOLE production T0 execution"))
    }

    func testPrimaryActionPillUsesModeSpecificDeviceMutationLabels() throws {
        let primary = try readProjectFile("PathChanger/UI/Components/PrimaryActionPill.swift")

        XCTAssertTrue(primary.contains("ready(label: \"Apply to Device\""))
        XCTAssertTrue(primary.contains("ready(label: \"Start Route\""))
        XCTAssertTrue(primary.contains("ready(label: \"Start Joystick\""))
        XCTAssertTrue(primary.contains("Applies the selected target to the device"))
        XCTAssertFalse(primary.contains("return \"Set Location\""))
    }

    func testSimulationPanelCopyDistinguishesTargetFromDeviceMutation() throws {
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")

        XCTAssertTrue(simulationView.contains("Label(\"Set Target\", systemImage: \"mappin\")"))
        XCTAssertTrue(simulationView.contains("Selected target: %.4f, %.4f. Use the primary action pill to apply it to the device."))
        XCTAssertTrue(simulationView.contains("Selected \\(result.name) as target. Use the primary action pill to apply it to the device."))
        XCTAssertTrue(simulationView.contains("Select a spot first"))
        XCTAssertTrue(simulationView.contains("Enter valid decimal coordinates"))
        XCTAssertTrue(simulationView.contains("Latitude must be -90...90; longitude -180...180"))
        XCTAssertFalse(simulationView.contains("Press Play or Apply to set."))
        XCTAssertFalse(simulationView.contains("Press Play to apply it."))
    }

    func testRouteWaypointRowsUseIndexedAccessibilityIdentifiers() throws {
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")
        let accessibility = try readProjectFile("PathChanger/UI/Accessibility.swift")

        XCTAssertTrue(accessibility.contains("static func routeRow(index: Int) -> String"))
        XCTAssertTrue(simulationView.contains(".accessibilityIdentifier(AccessibilityIdentifiers.Route.routeRow(index: index))"))
        XCTAssertFalse(simulationView.contains(".accessibilityIdentifier(AccessibilityIdentifiers.Route.routeRow)"))
    }

    func testW1ConvergenceValidatorTargetsLiveSidebarComponent() throws {
        let validator = try readProjectFile("scripts/validate-w1-convergence-lock.sh")

        XCTAssertTrue(
            validator.contains("PathChanger/UI/Components/CollapsibleSidebar.swift"),
            "W1 validation must inspect the live production sidebar component used by MainMapShell."
        )
        XCTAssertFalse(
            validator.contains("PathChanger/UI/SidebarView.swift"),
            "W1 validation must not target the deleted legacy SidebarView path."
        )
    }

    func testModePanelsExposeCompactStateSummaries() throws {
        // Lock-down: each mode panel must keep its named summary surface and
        // a single short empty-state hint. Width and joystick-radius asserts
        // are kept tight so accidental regressions to the pre-refinement
        // (bulky) sizes will fail this test.
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")
        let joystick = try readProjectFile("PathChanger/UI/JoystickControlView.swift")

        XCTAssertTrue(simulationView.contains("routeSelectedTargetSummary"))
        XCTAssertTrue(simulationView.contains("Select a spot, then Add Waypoint."))
        // Refined Teleport panel width is now tokenized in DS metrics.
        XCTAssertTrue(simulationView.contains("minWidth: DS.Metrics.mapTeleportPanelMinWidth"))
        XCTAssertTrue(simulationView.contains("idealWidth: DS.Metrics.mapTeleportPanelIdealWidth"))
        XCTAssertTrue(simulationView.contains("maxWidth: DS.Metrics.mapTeleportPanelMaxWidth"))
        // Refined Multi-Spot panel width is now tokenized in DS metrics.
        XCTAssertTrue(simulationView.contains("minWidth: DS.Metrics.mapRoutePanelMinWidth"))
        XCTAssertTrue(simulationView.contains("idealWidth: DS.Metrics.mapRoutePanelIdealWidth"))
        XCTAssertTrue(simulationView.contains("maxWidth: DS.Metrics.mapRoutePanelMaxWidth"))
        XCTAssertTrue(joystick.contains("joystickStartLocationSummary"))
        // Dead "tap a start point first" caption dropped — the N/S/E/W dial
        // already conveys movement, and startLocationSummary provides the
        // empty-state hint ("No start selected" / "Use sidebar search...").
        // Refined joystick dial size is tokenized in DS metrics.
        XCTAssertTrue(joystick.contains("private let outerRadius: CGFloat = DS.Metrics.joystickOuterRadius"))
    }

    func testP0RouteTypeControlIsNotShownUntilFunctional() throws {
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")

        XCTAssertTrue(simulationView.contains("Route Type control is intentionally hidden until it is wired to route playback behavior."))
        XCTAssertFalse(simulationView.contains("@State private var routeType"))
        XCTAssertFalse(simulationView.contains("Picker(\"Route Type\""))
        XCTAssertFalse(simulationView.contains("enum RouteType"))
    }

    func testP0MultiSpotUsesSelectThenAddWaypointModelEverywhere() throws {
        let sidebar = try readProjectFile("PathChanger/UI/Components/CollapsibleSidebar.swift")
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")

        XCTAssertTrue(sidebar.contains("Selected \\(name) as route spot. Use Add Waypoint to include it in the route."))
        XCTAssertFalse(sidebar.contains("case .route:\n            appState.addRoutePoint(coordinate)"))
        XCTAssertTrue(simulationView.contains("Label(\"Set Route Spot\", systemImage: \"mappin\")"))
        XCTAssertFalse(simulationView.contains("appState.addRoutePoint(action.coordinate)"))
        XCTAssertFalse(simulationView.contains("mapContextAddWaypointButton"))
    }

    func testP0ModePanelsExposeCompactStateStrips() throws {
        let simulationView = try readProjectFile("PathChanger/UI/SimulationView.swift")
        let joystick = try readProjectFile("PathChanger/UI/JoystickControlView.swift")
        let panel = try readProjectFile("PathChanger/UI/FloatingControlPanel.swift")

        XCTAssertTrue(panel.contains("struct PanelStateStrip"))
        XCTAssertTrue(simulationView.contains("teleportPanelStateStrip"))
        XCTAssertTrue(simulationView.contains("routePanelStateStrip"))
        XCTAssertTrue(joystick.contains("joystickPanelStateStrip"))
        XCTAssertTrue(simulationView.contains("Target selected · Not applied"))
        XCTAssertTrue(simulationView.contains("Ready to start"))
        XCTAssertTrue(joystick.contains("Not live"))
    }

    func testP0JoystickPreStartStateIsVisiblyNonLive() throws {
        let joystick = try readProjectFile("PathChanger/UI/JoystickControlView.swift")

        XCTAssertTrue(joystick.contains("private var joystickIsLive: Bool"))
        XCTAssertTrue(joystick.contains("Start Joystick to send movement to the device."))
        XCTAssertTrue(joystick.contains(".allowsHitTesting(joystickIsLive)"))
        XCTAssertTrue(joystick.contains("Preview only"))
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
