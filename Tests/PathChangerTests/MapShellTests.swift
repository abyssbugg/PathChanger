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
