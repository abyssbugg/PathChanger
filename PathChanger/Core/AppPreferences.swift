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

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Newer iOS Warning Banner State

    private func newerIOSWarningDismissedKey(for deviceId: String) -> String {
        "dismissedNewerIOSWarning_\(deviceId)"
    }

    /// Check if the newer-iOS warning banner has been dismissed for a specific device
    func isNewerIOSWarningDismissed(for deviceId: String) -> Bool {
        defaults.bool(forKey: newerIOSWarningDismissedKey(for: deviceId))
    }

    /// Mark the newer-iOS warning banner as dismissed for a specific device
    func setNewerIOSWarningDismissed(for deviceId: String) {
        defaults.set(true, forKey: newerIOSWarningDismissedKey(for: deviceId))
    }

    // MARK: - Onboarding State

    var isOnboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }
}
