//
//  AccessibilityTests.swift
//  PathChangerTests
//
//  Tests for accessibility identifiers, labels, hints, and keyboard navigation
//  Validates WCAG 2.1 compliance requirements
//

import XCTest
@testable import PathChanger

// MARK: - Accessibility Identifier Tests

final class AccessibilityIdentifierTests: XCTestCase {
    
    func testNavigationIdentifiersAreUnique() {
        let identifiers = [
            AccessibilityIdentifiers.Navigation.sidebar,
            AccessibilityIdentifiers.Navigation.deviceList,
            AccessibilityIdentifiers.Navigation.mainContent,
            AccessibilityIdentifiers.Navigation.settingsButton
        ]
        
        let uniqueIdentifiers = Set(identifiers)
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "Navigation identifiers must be unique")
    }
    
    func testDeviceIdentifiersAreUnique() {
        let identifiers = [
            AccessibilityIdentifiers.Devices.refreshButton,
            AccessibilityIdentifiers.Devices.deviceRow,
            AccessibilityIdentifiers.Devices.deviceName,
            AccessibilityIdentifiers.Devices.deviceStatus,
            AccessibilityIdentifiers.Devices.connectionIndicator
        ]
        
        let uniqueIdentifiers = Set(identifiers)
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "Device identifiers must be unique")
    }
    
    func testSimulationIdentifiersAreUnique() {
        let identifiers = [
            AccessibilityIdentifiers.Simulation.startButton,
            AccessibilityIdentifiers.Simulation.pauseButton,
            AccessibilityIdentifiers.Simulation.stopButton,
            AccessibilityIdentifiers.Simulation.speedSelector,
            AccessibilityIdentifiers.Simulation.modeSelector,
            AccessibilityIdentifiers.Simulation.loopToggle
        ]
        
        let uniqueIdentifiers = Set(identifiers)
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "Simulation identifiers must be unique")
    }
    
    func testLocationIdentifiersAreUnique() {
        let identifiers = [
            AccessibilityIdentifiers.Location.mapView,
            AccessibilityIdentifiers.Location.coordinateInput,
            AccessibilityIdentifiers.Location.latitudeField,
            AccessibilityIdentifiers.Location.longitudeField,
            AccessibilityIdentifiers.Location.setLocationButton,
            AccessibilityIdentifiers.Location.clearLocationButton,
            AccessibilityIdentifiers.Location.searchField
        ]
        
        let uniqueIdentifiers = Set(identifiers)
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "Location identifiers must be unique")
    }
    
    func testAllIdentifiersAreNonEmpty() {
        // Navigation
        XCTAssertFalse(AccessibilityIdentifiers.Navigation.sidebar.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Navigation.deviceList.isEmpty)
        
        // Devices
        XCTAssertFalse(AccessibilityIdentifiers.Devices.refreshButton.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Devices.deviceRow.isEmpty)
        
        // Simulation
        XCTAssertFalse(AccessibilityIdentifiers.Simulation.startButton.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Simulation.pauseButton.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Simulation.stopButton.isEmpty)
        
        // Location
        XCTAssertFalse(AccessibilityIdentifiers.Location.mapView.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Location.coordinateInput.isEmpty)
    }
}

// MARK: - Accessibility Label Tests

final class AccessibilityLabelTests: XCTestCase {
    
    func testActionLabelsAreDescriptive() {
        // Action labels should be verbs or verb phrases
        XCTAssertTrue(AccessibilityLabels.Actions.startSimulation.contains("Start"))
        XCTAssertTrue(AccessibilityLabels.Actions.pauseSimulation.contains("Pause"))
        XCTAssertTrue(AccessibilityLabels.Actions.stopSimulation.contains("Stop"))
        XCTAssertTrue(AccessibilityLabels.Actions.refreshDevices.contains("Refresh"))
        XCTAssertTrue(AccessibilityLabels.Actions.setLocation.contains("Set"))
        XCTAssertTrue(AccessibilityLabels.Actions.clearLocation.contains("Clear"))
    }
    
    func testStatusLabelsIncludeContext() {
        let connectedLabel = AccessibilityLabels.Status.tunnelConnected(mode: "USB")
        XCTAssertTrue(connectedLabel.contains("connected"))
        XCTAssertTrue(connectedLabel.contains("USB"))
        
        let deviceLabel = AccessibilityLabels.Status.deviceConnected(name: "iPhone 15")
        XCTAssertTrue(deviceLabel.contains("iPhone 15"))
        XCTAssertTrue(deviceLabel.contains("connected"))
    }
    
    func testCoordinateValueFormatting() {
        let label = AccessibilityLabels.Values.coordinate(latitude: 35.6762, longitude: 139.6503)
        XCTAssertTrue(label.contains("Latitude"))
        XCTAssertTrue(label.contains("Longitude"))
        XCTAssertTrue(label.contains("35.6762"))
        XCTAssertTrue(label.contains("139.6503"))
    }
    
    func testSpeedValueFormatting() {
        let label = AccessibilityLabels.Values.speed(name: "Walking", metersPerSecond: 1.4)
        XCTAssertTrue(label.contains("Walking"))
        XCTAssertTrue(label.contains("1.4"))
        XCTAssertTrue(label.contains("meters per second"))
    }
    
    func testProgressValueFormatting() {
        let label = AccessibilityLabels.Values.progress(percentage: 0.75)
        XCTAssertTrue(label.contains("75"))
        XCTAssertTrue(label.contains("percent"))
    }
}

// MARK: - Accessibility Hint Tests

final class AccessibilityHintTests: XCTestCase {
    
    func testHintsAreActionOriented() {
        // Hints should describe what happens on interaction
        XCTAssertTrue(AccessibilityHints.startSimulation.lowercased().contains("tap") ||
                     AccessibilityHints.startSimulation.lowercased().contains("click"))
        
        XCTAssertTrue(AccessibilityHints.pauseSimulation.lowercased().contains("tap") ||
                     AccessibilityHints.pauseSimulation.lowercased().contains("click"))
    }
    
    func testHintsProvideContext() {
        XCTAssertFalse(AccessibilityHints.speedSelector.isEmpty)
        XCTAssertFalse(AccessibilityHints.modeSelector.isEmpty)
        XCTAssertFalse(AccessibilityHints.coordinateInput.isEmpty)
        XCTAssertFalse(AccessibilityHints.joystickControl.isEmpty)
    }
    
    func testHintsAreNotTooLong() {
        // Hints should be concise (under 100 characters recommended)
        XCTAssertLessThan(AccessibilityHints.startSimulation.count, 100)
        XCTAssertLessThan(AccessibilityHints.pauseSimulation.count, 100)
        XCTAssertLessThan(AccessibilityHints.stopSimulation.count, 100)
        XCTAssertLessThan(AccessibilityHints.deviceRow.count, 100)
    }
}

// MARK: - Keyboard Shortcut Tests

final class KeyboardShortcutTests: XCTestCase {
    
    func testLocationShortcutsUseCommandModifier() {
        XCTAssertTrue(KeyboardShortcuts.setLocation.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.clearLocation.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.refreshDevices.modifiers.contains(.command))
    }
    
    func testSimulationShortcutsUseCommandModifier() {
        XCTAssertTrue(KeyboardShortcuts.startSimulation.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.pauseSimulation.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.stopSimulation.modifiers.contains(.command))
    }
    
    func testNavigationShortcutsUseMultipleModifiers() {
        XCTAssertTrue(KeyboardShortcuts.showSidebar.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.showSidebar.modifiers.contains(.shift))
    }
    
    func testSpeedControlShortcutsUseMultipleModifiers() {
        XCTAssertTrue(KeyboardShortcuts.speedUp.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.speedUp.modifiers.contains(.option))
        XCTAssertTrue(KeyboardShortcuts.speedDown.modifiers.contains(.command))
        XCTAssertTrue(KeyboardShortcuts.speedDown.modifiers.contains(.option))
    }
}

// MARK: - Focus Manager Tests

@MainActor
final class FocusManagerTests: XCTestCase {
    
    func testInitialFocusIsNil() {
        let manager = FocusManager.shared
        // Reset focus for testing
        manager.moveFocus(to: .sidebar)
        manager.currentFocus = nil
        XCTAssertNil(manager.currentFocus)
    }
    
    func testMoveFocusUpdatesCurrentFocus() {
        let manager = FocusManager.shared
        
        manager.moveFocus(to: .deviceList)
        XCTAssertEqual(manager.currentFocus, .deviceList)
        
        manager.moveFocus(to: .mapView)
        XCTAssertEqual(manager.currentFocus, .mapView)
    }
    
    func testNextFocusCyclesThroughElements() {
        let manager = FocusManager.shared
        
        manager.currentFocus = nil
        manager.nextFocus()
        XCTAssertEqual(manager.currentFocus, .sidebar)
        
        manager.nextFocus()
        XCTAssertEqual(manager.currentFocus, .deviceList)
    }
    
    func testPreviousFocusCyclesBackward() {
        let manager = FocusManager.shared
        
        manager.moveFocus(to: .deviceList)
        manager.previousFocus()
        XCTAssertEqual(manager.currentFocus, .sidebar)
    }
    
    func testFocusableElementsAreHashable() {
        let elements: Set<FocusManager.FocusableElement> = [
            .sidebar,
            .deviceList,
            .mapView,
            .coordinateInput,
            .joystickControl,
            .routeList,
            .simulationControls
        ]
        
        XCTAssertEqual(elements.count, 7)
    }
}

// MARK: - Accessibility Announcer Tests

@MainActor
final class AccessibilityAnnouncerTests: XCTestCase {
    
    func testSharedInstanceExists() {
        let announcer = AccessibilityAnnouncer.shared
        XCTAssertNotNil(announcer)
    }
    
    func testAnnouncementPriorityValues() {
        // Just verify the enum values exist
        let normal = AccessibilityAnnouncer.AnnouncementPriority.normal
        let high = AccessibilityAnnouncer.AnnouncementPriority.high
        
        XCTAssertNotEqual(String(describing: normal), String(describing: high))
    }
    
    func testDeviceAnnouncementMethods() {
        let announcer = AccessibilityAnnouncer.shared
        
        // These should not crash
        announcer.announceDeviceConnected("Test iPhone")
        announcer.announceDeviceDisconnected("Test iPhone")
    }
    
    func testSimulationAnnouncementMethods() {
        let announcer = AccessibilityAnnouncer.shared
        
        // These should not crash
        announcer.announceSimulationStarted("Route")
        announcer.announceSimulationPaused()
        announcer.announceSimulationStopped()
    }
    
    func testLocationAnnouncementMethod() {
        let announcer = AccessibilityAnnouncer.shared
        
        // This should not crash
        announcer.announceLocationSet(latitude: 35.6762, longitude: 139.6503)
    }
    
    func testErrorAnnouncementMethod() {
        let announcer = AccessibilityAnnouncer.shared
        
        // This should not crash
        announcer.announceError("Test error message")
    }
}

// MARK: - Toast Type Accessibility Tests

final class ToastAccessibilityTests: XCTestCase {
    
    func testToastTypesHaveIcons() {
        XCTAssertFalse(ToastType.success.icon.isEmpty)
        XCTAssertFalse(ToastType.error.icon.isEmpty)
        XCTAssertFalse(ToastType.warning.icon.isEmpty)
        XCTAssertFalse(ToastType.info.icon.isEmpty)
    }
    
    func testToastTypesHaveDistinctColors() {
        // Colors should be different for each type for visual distinction
        XCTAssertNotEqual(String(describing: ToastType.success.color), String(describing: ToastType.error.color))
        XCTAssertNotEqual(String(describing: ToastType.warning.color), String(describing: ToastType.info.color))
    }
    
    func testToastIdentifiersExist() {
        XCTAssertFalse(AccessibilityIdentifiers.Toast.container.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Toast.message.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Toast.dismissButton.isEmpty)
    }
}

// MARK: - Onboarding Accessibility Tests

final class OnboardingAccessibilityTests: XCTestCase {
    
    func testOnboardingStepTitlesAreDescriptive() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "Step \(step) should have a title")
            XCTAssertGreaterThan(step.title.count, 5, "Step title should be descriptive")
        }
    }
    
    func testOnboardingStepsHaveIcons() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.icon.isEmpty, "Step \(step) should have an icon")
        }
    }
    
    func testOnboardingIdentifiersExist() {
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.welcomeStep.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.dependenciesStep.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.deviceSetupStep.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.completeStep.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.nextButton.isEmpty)
        XCTAssertFalse(AccessibilityIdentifiers.Onboarding.previousButton.isEmpty)
    }
}

// MARK: - Simulation Type Accessibility Tests

final class SimulationTypeAccessibilityTests: XCTestCase {
    
    func testSimulationSpeedsHaveDisplayNames() {
        for speed in SimulationSpeed.allCases {
            XCTAssertFalse(speed.displayName.isEmpty, "Speed \(speed) should have display name")
        }
    }
    
    func testSimulationSpeedsHaveIcons() {
        for speed in SimulationSpeed.allCases {
            XCTAssertFalse(speed.icon.isEmpty, "Speed \(speed) should have icon")
        }
    }
}

// MARK: - WCAG 2.1 Compliance Tests

final class WCAGComplianceTests: XCTestCase {
    
    func testInteractiveElementsHaveLabels() {
        // Verify all interactive element identifiers have corresponding labels defined
        XCTAssertFalse(AccessibilityLabels.Actions.startSimulation.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Actions.pauseSimulation.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Actions.stopSimulation.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Actions.refreshDevices.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Actions.setLocation.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Actions.clearLocation.isEmpty)
    }
    
    func testStatusMessagesAreDescriptive() {
        // Status messages should provide meaningful information
        let tunnelStatus = AccessibilityLabels.Status.tunnelDisconnected
        XCTAssertTrue(tunnelStatus.lowercased().contains("disconnect"))
        
        let simStatus = AccessibilityLabels.Status.simulationPaused
        XCTAssertTrue(simStatus.lowercased().contains("pause"))
    }
    
    func testNavigationLabelsExist() {
        XCTAssertFalse(AccessibilityLabels.Navigation.sidebar.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Navigation.deviceSection.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Navigation.routeSection.isEmpty)
        XCTAssertFalse(AccessibilityLabels.Navigation.settingsSection.isEmpty)
    }
    
    func testAccessibilityShortcutsExist() {
        // Verify keyboard shortcuts are defined
        XCTAssertNotNil(KeyboardShortcuts.setLocation)
        XCTAssertNotNil(KeyboardShortcuts.clearLocation)
        XCTAssertNotNil(KeyboardShortcuts.refreshDevices)
        XCTAssertNotNil(KeyboardShortcuts.startSimulation)
        XCTAssertNotNil(KeyboardShortcuts.pauseSimulation)
        XCTAssertNotNil(KeyboardShortcuts.stopSimulation)
        XCTAssertNotNil(KeyboardShortcuts.showSidebar)
        XCTAssertNotNil(KeyboardShortcuts.showSettings)
    }
}
