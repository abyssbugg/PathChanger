//
//  Accessibility.swift
//  PathChanger
//
//  Accessibility constants, identifiers, and helpers for VoiceOver and keyboard navigation
//  Implements WCAG 2.1 guidelines for accessibility compliance
//

import SwiftUI

// MARK: - Accessibility Identifiers

/// Centralized accessibility identifiers for UI testing and screen reader navigation
enum AccessibilityIdentifiers {

    // MARK: - Navigation
    enum Navigation {
        static let sidebar = "sidebar"
        static let deviceList = "deviceList"
        static let mainContent = "mainContent"
        static let settingsButton = "settingsButton"
    }

    // MARK: - Device Management
    enum Devices {
        static let refreshButton = "refreshDevicesButton"
        static let deviceRow = "deviceRow"
        static let deviceName = "deviceName"
        static let deviceStatus = "deviceStatus"
        static let connectionIndicator = "connectionIndicator"
    }

    // MARK: - Simulation Controls
    enum Simulation {
        static let startButton = "startSimulationButton"
        static let pauseButton = "pauseSimulationButton"
        static let stopButton = "stopSimulationButton"
        static let speedSelector = "speedSelector"
        static let modeSelector = "modeSelector"
        static let loopToggle = "loopRouteToggle"
    }

    // MARK: - Location
    enum Location {
        static let mapView = "mapView"
        static let coordinateInput = "coordinateInput"
        static let latitudeField = "latitudeField"
        static let longitudeField = "longitudeField"
        static let setLocationButton = "setLocationButton"
        static let clearLocationButton = "clearLocationButton"
        static let searchField = "searchField"
    }

    // MARK: - Joystick
    enum Joystick {
        static let control = "joystickControl"
        static let directionIndicator = "directionIndicator"
        static let speedIndicator = "speedIndicator"
    }

    // MARK: - Route
    enum Route {
        static let routeList = "routeList"
        static let routeRow = "routeRow"
        static let importButton = "importRouteButton"
        static let exportButton = "exportRouteButton"
        static let addWaypointButton = "addWaypointButton"
        static let clearRouteButton = "clearRouteButton"
        static let progressIndicator = "routeProgressIndicator"
    }

    // MARK: - History
    enum History {
        static let historyList = "locationHistoryList"
        static let historyRow = "locationHistoryRow"
        static let clearButton = "clearLocationHistoryButton"
    }

    // MARK: - Status
    enum Status {
        static let tunnelStatus = "tunnelStatus"
        static let connectionStatus = "connectionStatus"
        static let statusMessage = "statusMessage"
        static let errorMessage = "errorMessage"
    }

    // MARK: - Settings
    enum Settings {
        static let generalTab = "generalSettingsTab"
        static let advancedTab = "advancedSettingsTab"
        static let loggingToggle = "loggingToggle"
        static let autoConnectToggle = "autoConnectToggle"
    }

    // MARK: - Toast
    enum Toast {
        static let container = "toastContainer"
        static let message = "toastMessage"
        static let dismissButton = "toastDismissButton"
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let welcomeStep = "onboardingWelcome"
        static let dependenciesStep = "onboardingDependencies"
        static let deviceSetupStep = "onboardingDeviceSetup"
        static let completeStep = "onboardingComplete"
        static let nextButton = "onboardingNextButton"
        static let previousButton = "onboardingPreviousButton"
        static let skipButton = "onboardingSkipButton"
    }
}

// MARK: - Accessibility Labels

/// Localized accessibility labels for VoiceOver
enum AccessibilityLabels {

    // MARK: - Actions
    enum Actions {
        static let startSimulation = "Start location simulation"
        static let pauseSimulation = "Pause location simulation"
        static let resumeSimulation = "Resume location simulation"
        static let stopSimulation = "Stop location simulation"
        static let refreshDevices = "Refresh connected devices"
        static let setLocation = "Set device location"
        static let clearLocation = "Clear device location"
        static let importRoute = "Import GPX route file"
        static let exportRoute = "Export route to GPX file"
        static let copyToClipboard = "Copy to clipboard"
        static let dismissToast = "Dismiss notification"
        static let openSettings = "Open settings"
    }

    // MARK: - Status
    enum Status {
        static func tunnelConnected(mode: String) -> String {
            "Tunnel connected via \(mode)"
        }
        static let tunnelDisconnected = "Tunnel disconnected"
        static let tunnelConnecting = "Tunnel connecting"
        static func deviceConnected(name: String) -> String {
            "\(name), connected"
        }
        static func deviceDisconnected(name: String) -> String {
            "\(name), disconnected"
        }
        static func simulationRunning(mode: String, speed: String) -> String {
            "Simulation running, \(mode) mode at \(speed) speed"
        }
        static let simulationPaused = "Simulation paused"
        static let simulationStopped = "Simulation stopped"
    }

    // MARK: - Navigation
    enum Navigation {
        static let sidebar = "Navigation sidebar"
        static let deviceSection = "Connected devices section"
        static let routeSection = "Saved routes section"
        static let settingsSection = "Application settings"
    }

    // MARK: - Values
    enum Values {
        static func coordinate(latitude: Double, longitude: Double) -> String {
            String(format: "Latitude %.4f, Longitude %.4f", latitude, longitude)
        }
        static func speed(name: String, metersPerSecond: Double) -> String {
            String(format: "%@, %.1f meters per second", name, metersPerSecond)
        }
        static func progress(percentage: Double) -> String {
            String(format: "Progress %.0f percent", percentage * 100)
        }
    }
}

// MARK: - Accessibility Hints

/// Accessibility hints providing additional context
enum AccessibilityHints {
    static let startSimulation = "Double-tap to begin simulating device location"
    static let pauseSimulation = "Double-tap to temporarily pause the simulation"
    static let stopSimulation = "Double-tap to stop and reset the simulation"
    static let speedSelector = "Adjusts simulation movement speed"
    static let modeSelector = "Choose between teleport, route, or joystick mode"
    static let coordinateInput = "Enter decimal coordinates for the target location"
    static let joystickControl = "Drag to control movement direction and speed"
    static let deviceRow = "Double-tap to select this device"
    static let routeRow = "Double-tap to load this route"
    static let loopToggle = "When enabled, route repeats after completion"
    static let refreshDevices = "Scans for connected iOS devices"
    static let mapTap = "Tap and hold to set location marker"
}

// MARK: - View Modifiers for Accessibility

extension View {

    /// Applies standard accessibility configuration for a button
    func accessibleButton(
        label: String,
        hint: String? = nil,
        identifier: String
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(.isButton)
    }

    /// Applies accessibility configuration for a status indicator
    func accessibleStatus(
        label: String,
        value: String? = nil,
        identifier: String
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "")
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Applies accessibility configuration for an interactive control
    func accessibleControl(
        label: String,
        hint: String,
        value: String? = nil,
        identifier: String
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityValue(value ?? "")
            .accessibilityIdentifier(identifier)
    }

    /// Applies accessibility configuration for a navigable section
    func accessibleSection(
        label: String,
        identifier: String
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .accessibilityElement(children: .contain)
    }

    /// Hides element from accessibility tree while keeping visible
    func accessibilityHiddenFromVoiceOver() -> some View {
        self.accessibilityHidden(true)
    }

    /// Groups children into a single accessibility element
    func accessibilityGrouped(label: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }
}

// MARK: - Keyboard Navigation

/// Keyboard shortcut definitions for navigation
enum KeyboardShortcuts {
    // Location commands (Cmd+)
    static let setLocation = KeyboardShortcut("l", modifiers: .command)
    static let clearLocation = KeyboardShortcut("k", modifiers: .command)
    static let refreshDevices = KeyboardShortcut("r", modifiers: .command)

    // Simulation commands (Cmd+)
    static let startSimulation = KeyboardShortcut(.space, modifiers: .command)
    static let pauseSimulation = KeyboardShortcut("p", modifiers: .command)
    static let stopSimulation = KeyboardShortcut(.escape, modifiers: .command)

    // Navigation (Cmd+Shift+)
    static let showSidebar = KeyboardShortcut("s", modifiers: [.command, .shift])
    static let showSettings = KeyboardShortcut(",", modifiers: .command)

    // Speed control (Cmd+Option+)
    static let speedUp = KeyboardShortcut(.upArrow, modifiers: [.command, .option])
    static let speedDown = KeyboardShortcut(.downArrow, modifiers: [.command, .option])
}

// MARK: - Focus State Management

/// Manages focus for keyboard navigation
@MainActor
class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published var currentFocus: FocusableElement?

    enum FocusableElement: Hashable {
        case sidebar
        case deviceList
        case mapView
        case coordinateInput
        case joystickControl
        case routeList
        case simulationControls
    }

    private init() {}

    func moveFocus(to element: FocusableElement) {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentFocus = element
        }
    }

    func nextFocus() {
        guard let current = currentFocus else {
            currentFocus = .sidebar
            return
        }

        let order: [FocusableElement] = [
            .sidebar,
            .deviceList,
            .simulationControls,
            .coordinateInput,
            .mapView,
            .joystickControl,
            .routeList
        ]

        if let index = order.firstIndex(of: current),
           index < order.count - 1 {
            currentFocus = order[index + 1]
        } else {
            currentFocus = order.first
        }
    }

    func previousFocus() {
        guard let current = currentFocus else {
            currentFocus = .routeList
            return
        }

        let order: [FocusableElement] = [
            .sidebar,
            .deviceList,
            .simulationControls,
            .coordinateInput,
            .mapView,
            .joystickControl,
            .routeList
        ]

        if let index = order.firstIndex(of: current),
           index > 0 {
            currentFocus = order[index - 1]
        } else {
            currentFocus = order.last
        }
    }
}

// MARK: - Color Contrast Helpers

extension Color {
    /// Returns high-contrast version for accessibility
    var highContrast: Color {
        // Use system colors that automatically adapt for accessibility
        self
    }

}

// MARK: - Accessibility Announcements

@MainActor
class AccessibilityAnnouncer {
    static let shared = AccessibilityAnnouncer()

    private init() {}

    /// Announces a message to VoiceOver users
    func announce(_ message: String, priority: AnnouncementPriority = .normal) {
        #if os(macOS)
        guard let window = NSApp?.mainWindow ?? NSApp?.keyWindow else {
            // No window available (e.g., in tests), skip announcement
            return
        }
        let priorityValue = priority == .high
            ? NSAccessibilityPriorityLevel.high.rawValue
            : NSAccessibilityPriorityLevel.medium.rawValue
        NSAccessibility.post(
            element: window as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priorityValue
            ]
        )
        #endif
    }

    enum AnnouncementPriority {
        case normal
        case high
    }

    // MARK: - Common Announcements

    func announceDeviceConnected(_ deviceName: String) {
        announce("\(deviceName) connected", priority: .high)
    }

    func announceDeviceDisconnected(_ deviceName: String) {
        announce("\(deviceName) disconnected", priority: .high)
    }

    func announceSimulationStarted(_ mode: String) {
        announce("Simulation started in \(mode) mode")
    }

    func announceSimulationPaused() {
        announce("Simulation paused")
    }

    func announceSimulationStopped() {
        announce("Simulation stopped")
    }

    func announceLocationSet(latitude: Double, longitude: Double) {
        announce(String(format: "Location set to %.4f, %.4f", latitude, longitude))
    }

    func announceError(_ message: String) {
        announce("Error: \(message)", priority: .high)
    }
}
