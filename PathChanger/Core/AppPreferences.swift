//
//  AppPreferences.swift
//  PathChanger
//
//  Centralized UserDefaults access for app preferences
//

import Foundation

/// Centralized helper for managing app preferences via UserDefaults
final class AppPreferences {
    static let shared = AppPreferences()

    /// Where every preference lives: the app's own domain, except in the app-hosted test
    /// process, which shares that domain with the running app. There it is one throwaway
    /// suite, emptied when the process first uses it, so no test writes the user's
    /// preferences. Production code names this, never `UserDefaults.standard`
    /// (`PreferencesStoreSourceTests`).
    static let store: UserDefaults = store(isHostingTests: AppRuntimeEnvironment.isHostingTests)

    static let testHostSuiteName = "com.pathchanger.app.test-host"

    static func store(isHostingTests: Bool) -> UserDefaults {
        guard isHostingTests else { return .standard }
        guard let store = UserDefaults(suiteName: testHostSuiteName) else {
            preconditionFailure("the test-host suite name is not a valid UserDefaults suite")
        }
        store.removePersistentDomain(forName: testHostSuiteName)
        return store
    }

    private let defaults = AppPreferences.store

    private init() {}

    // MARK: - iOS 18 Warning Banner State

    private func ios18WarningDismissedKey(for deviceId: String) -> String {
        "dismissedIOS18Warning_\(deviceId)"
    }

    /// Check if the iOS 18 warning banner has been dismissed for a specific device
    func isIOS18WarningDismissed(for deviceId: String) -> Bool {
        defaults.bool(forKey: ios18WarningDismissedKey(for: deviceId))
    }

    /// Mark the iOS 18 warning banner as dismissed for a specific device
    func setIOS18WarningDismissed(for deviceId: String) {
        defaults.set(true, forKey: ios18WarningDismissedKey(for: deviceId))
    }

    // MARK: - Onboarding State

    var isOnboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }
}
