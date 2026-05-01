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
