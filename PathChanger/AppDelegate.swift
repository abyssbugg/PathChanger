//
//  AppDelegate.swift
//  PathChanger
//

import Foundation
import AppKit

// MARK: - App Delegate for Lifecycle Management

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Tunnel startup is manual by default to avoid unexpected administrator prompts on launch.
        Task { @MainActor in
            Logger.info(
                "window_lifecycle didFinishLaunching",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
        }
    }

    nonisolated func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            Logger.info(
                "window_lifecycle didBecomeActive visibleWindows=\(NSApp.windows.filter { $0.isVisible }.count)",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
            restoreVisibleMainWindowIfPossible()
        }
    }

    nonisolated func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            Logger.info(
                "window_lifecycle didResignActive visibleWindows=\(NSApp.windows.filter { $0.isVisible }.count)",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
        }
    }

    nonisolated func applicationDidHide(_ notification: Notification) {
        Task { @MainActor in
            Logger.info(
                "window_lifecycle didHide visibleWindows=\(NSApp.windows.filter { $0.isVisible }.count)",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Handled by TunneldManager's notification observer
        Task { @MainActor in
            Logger.info(
                "window_lifecycle willTerminate",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Task { @MainActor in
            Logger.info(
                "window_lifecycle lastWindowClosed keepRunning",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
        }
        return false
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            Logger.info(
                "window_lifecycle shouldHandleReopen hasVisibleWindows=\(flag)",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
            restoreVisibleMainWindowIfPossible()
        }

        // If there are no existing windows for us to restore, allow SwiftUI's
        // WindowGroup machinery to create the main window again.
        let hasRestorableWindow = MainActor.assumeIsolated {
            sender.windows.contains { $0.canBecomeMain }
        }
        return hasRestorableWindow ? false : true
    }

    private func restoreVisibleMainWindowIfPossible() {
        let restorableWindows = NSApp.windows.filter { $0.canBecomeMain }
        guard !restorableWindows.isEmpty else {
            Logger.info(
                "window_lifecycle noRestorableMainWindow",
                category: .general,
                metadata: LogMetadata(operationType: "window_lifecycle")
            )
            return
        }

        for window in restorableWindows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
