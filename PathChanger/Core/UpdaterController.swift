//
//  UpdaterController.swift
//  PathChanger
//
//  Sparkle auto-update integration for SwiftUI
//

import Foundation
import Sparkle

/// Controller for managing app updates via Sparkle
///
/// This class wraps SPUStandardUpdaterController for use in SwiftUI.
/// It handles automatic update checks and provides a manual check action.
@MainActor
final class UpdaterController: ObservableObject {

    // MARK: - Properties

    /// The underlying Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Exposes whether the updater can check for updates
    @Published private(set) var canCheckForUpdates: Bool = false

    // MARK: - Initialization

    init() {
        // Initialize the updater controller
        // startingUpdater: true means it will automatically check for updates
        // based on the user's preferences
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe when the updater can check for updates
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    // MARK: - Public Methods

    /// Manually trigger an update check
    /// This opens the Sparkle update window if an update is available
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Get the underlying SPUUpdater for advanced configuration
    var updater: SPUUpdater {
        updaterController.updater
    }
}

