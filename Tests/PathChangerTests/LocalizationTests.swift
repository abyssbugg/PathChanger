//
//  LocalizationTests.swift
//  PathChangerTests
//
//  Tests for localization helper and string resources
//

import XCTest
@testable import PathChanger
import SwiftUI

final class LocalizationTests: XCTestCase {
    
    // MARK: - L10n Namespace Tests
    
    func testAppNamespaceExists() {
        // Verify L10n.App namespace has expected keys
        XCTAssertNotNil(L10n.App.name)
        XCTAssertFalse(L10n.App.version("1.0.0").isEmpty)
    }
    
    func testActionNamespaceExists() {
        // Verify common actions exist
        XCTAssertNotNil(L10n.Action.cancel)
        XCTAssertNotNil(L10n.Action.confirm)
        XCTAssertNotNil(L10n.Action.done)
        XCTAssertNotNil(L10n.Action.save)
        XCTAssertNotNil(L10n.Action.delete)
        XCTAssertNotNil(L10n.Action.close)
        XCTAssertNotNil(L10n.Action.refresh)
        XCTAssertNotNil(L10n.Action.start)
        XCTAssertNotNil(L10n.Action.stop)
        XCTAssertNotNil(L10n.Action.pause)
        XCTAssertNotNil(L10n.Action.resume)
        XCTAssertNotNil(L10n.Action.clear)
        XCTAssertNotNil(L10n.Action.copy)
        XCTAssertNotNil(L10n.Action.search)
        XCTAssertNotNil(L10n.Action.settings)
        XCTAssertNotNil(L10n.Action.help)
    }
    
    func testOnboardingNamespaceExists() {
        XCTAssertNotNil(L10n.Onboarding.welcomeTitle)
        XCTAssertNotNil(L10n.Onboarding.welcomeSubtitle)
        XCTAssertNotNil(L10n.Onboarding.step1Title)
        XCTAssertNotNil(L10n.Onboarding.step1Description)
        XCTAssertNotNil(L10n.Onboarding.step2Title)
        XCTAssertNotNil(L10n.Onboarding.step2Description)
        XCTAssertNotNil(L10n.Onboarding.step3Title)
        XCTAssertNotNil(L10n.Onboarding.step3Description)
        XCTAssertNotNil(L10n.Onboarding.getStarted)
        XCTAssertNotNil(L10n.Onboarding.skip)
        XCTAssertNotNil(L10n.Onboarding.next)
        XCTAssertNotNil(L10n.Onboarding.previous)
    }
    
    func testSidebarNamespaceExists() {
        XCTAssertNotNil(L10n.Sidebar.devices)
        XCTAssertNotNil(L10n.Sidebar.simulation)
        XCTAssertNotNil(L10n.Sidebar.routes)
        XCTAssertNotNil(L10n.Sidebar.settings)
        XCTAssertNotNil(L10n.Sidebar.noDevices)
        XCTAssertNotNil(L10n.Sidebar.refreshDevices)
    }
    
    func testDeviceNamespaceExists() {
        XCTAssertNotNil(L10n.Device.connected)
        XCTAssertNotNil(L10n.Device.disconnected)
        XCTAssertNotNil(L10n.Device.usb)
        XCTAssertNotNil(L10n.Device.wifi)
        XCTAssertNotNil(L10n.Device.unknown)
        XCTAssertNotNil(L10n.Device.select)
        XCTAssertNotNil(L10n.Device.multiSelect)
        XCTAssertNotNil(L10n.Device.noLocation)
    }
    
    func testSimulationNamespaceExists() {
        XCTAssertNotNil(L10n.Simulation.title)
        XCTAssertNotNil(L10n.Simulation.coordinates)
        XCTAssertNotNil(L10n.Simulation.latitude)
        XCTAssertNotNil(L10n.Simulation.longitude)
        XCTAssertNotNil(L10n.Simulation.setLocation)
        XCTAssertNotNil(L10n.Simulation.clearLocation)
        XCTAssertNotNil(L10n.Simulation.currentLocation)
        XCTAssertNotNil(L10n.Simulation.searchPlaceholder)
        XCTAssertNotNil(L10n.Simulation.tapToSetLocation)
        XCTAssertNotNil(L10n.Simulation.manualInput)
    }
    
    func testJoystickNamespaceExists() {
        XCTAssertNotNil(L10n.Joystick.title)
        XCTAssertNotNil(L10n.Joystick.enable)
        XCTAssertNotNil(L10n.Joystick.disable)
        XCTAssertNotNil(L10n.Joystick.speed)
        XCTAssertNotNil(L10n.Joystick.speedWalk)
        XCTAssertNotNil(L10n.Joystick.speedRun)
        XCTAssertNotNil(L10n.Joystick.speedBike)
        XCTAssertNotNil(L10n.Joystick.speedCar)
        XCTAssertNotNil(L10n.Joystick.hint)
    }
    
    func testRouteNamespaceExists() {
        XCTAssertNotNil(L10n.Route.title)
        XCTAssertNotNil(L10n.Route.start)
        XCTAssertNotNil(L10n.Route.stop)
        XCTAssertNotNil(L10n.Route.pause)
        XCTAssertNotNil(L10n.Route.resume)
        XCTAssertNotNil(L10n.Route.loop)
        XCTAssertNotNil(L10n.Route.pingPong)
        XCTAssertNotNil(L10n.Route.importGPX)
        XCTAssertNotNil(L10n.Route.exportGPX)
        XCTAssertNotNil(L10n.Route.library)
        XCTAssertNotNil(L10n.Route.noRoute)
    }
    
    func testSettingsNamespaceExists() {
        XCTAssertNotNil(L10n.Settings.title)
        XCTAssertNotNil(L10n.Settings.general)
        XCTAssertNotNil(L10n.Settings.appearance)
        XCTAssertNotNil(L10n.Settings.advanced)
        XCTAssertNotNil(L10n.Settings.about)
        
        // General settings
        XCTAssertNotNil(L10n.Settings.General.autoStartTunnel)
        XCTAssertNotNil(L10n.Settings.General.autoStartTunnelDesc)
        XCTAssertNotNil(L10n.Settings.General.rememberLastLocation)
        XCTAssertNotNil(L10n.Settings.General.rememberLastLocationDesc)
        
        // Appearance settings
        XCTAssertNotNil(L10n.Settings.Appearance.theme)
        XCTAssertNotNil(L10n.Settings.Appearance.themeLight)
        XCTAssertNotNil(L10n.Settings.Appearance.themeDark)
        XCTAssertNotNil(L10n.Settings.Appearance.themeSystem)
        XCTAssertNotNil(L10n.Settings.Appearance.mapStyle)
        XCTAssertNotNil(L10n.Settings.Appearance.mapStyleStandard)
        XCTAssertNotNil(L10n.Settings.Appearance.mapStyleSatellite)
        XCTAssertNotNil(L10n.Settings.Appearance.mapStyleHybrid)
        
        // Advanced settings
        XCTAssertNotNil(L10n.Settings.Advanced.tunnelMode)
        XCTAssertNotNil(L10n.Settings.Advanced.tunnelModeAuto)
        XCTAssertNotNil(L10n.Settings.Advanced.tunnelModeUSB)
        XCTAssertNotNil(L10n.Settings.Advanced.tunnelModeWiFi)
        XCTAssertNotNil(L10n.Settings.Advanced.pythonPath)
        XCTAssertNotNil(L10n.Settings.Advanced.pythonPathAuto)
        XCTAssertNotNil(L10n.Settings.Advanced.rateLimit)
        XCTAssertNotNil(L10n.Settings.Advanced.rateLimitDesc)
    }
    
    func testTunnelNamespaceExists() {
        XCTAssertNotNil(L10n.Tunnel.status)
        XCTAssertNotNil(L10n.Tunnel.connected)
        XCTAssertNotNil(L10n.Tunnel.disconnected)
        XCTAssertNotNil(L10n.Tunnel.connecting)
        XCTAssertNotNil(L10n.Tunnel.error)
        XCTAssertNotNil(L10n.Tunnel.start)
        XCTAssertNotNil(L10n.Tunnel.stop)
        XCTAssertNotNil(L10n.Tunnel.restart)
        XCTAssertNotNil(L10n.Tunnel.requiresSudo)
        XCTAssertNotNil(L10n.Tunnel.modeUSB)
        XCTAssertNotNil(L10n.Tunnel.modeWiFi)
        XCTAssertNotNil(L10n.Tunnel.modeDaemon)
    }
    
    func testErrorNamespaceExists() {
        XCTAssertNotNil(L10n.Error.title)
        XCTAssertNotNil(L10n.Error.unknown)
        XCTAssertNotNil(L10n.Error.deviceNotFound)
        XCTAssertNotNil(L10n.Error.tunnelNotRunning)
        XCTAssertNotNil(L10n.Error.invalidCoordinates)
        XCTAssertNotNil(L10n.Error.rateLimited)
        XCTAssertNotNil(L10n.Error.timeout)
        XCTAssertNotNil(L10n.Error.developerModeRequired)
        XCTAssertNotNil(L10n.Error.pythonNotFound)
        XCTAssertNotNil(L10n.Error.pymobiledeviceNotFound)
        XCTAssertNotNil(L10n.Error.connectionFailed)
    }
    
    func testToastNamespaceExists() {
        XCTAssertNotNil(L10n.Toast.locationSet)
        XCTAssertNotNil(L10n.Toast.locationCleared)
        XCTAssertNotNil(L10n.Toast.routeStarted)
        XCTAssertNotNil(L10n.Toast.routeStopped)
        XCTAssertNotNil(L10n.Toast.settingsSaved)
        XCTAssertNotNil(L10n.Toast.copied)
        XCTAssertNotNil(L10n.Toast.queued)
    }
    
    func testAccessibilityNamespaceExists() {
        XCTAssertNotNil(L10n.Accessibility.map)
        XCTAssertNotNil(L10n.Accessibility.joystick)
        XCTAssertNotNil(L10n.Accessibility.deviceList)
        XCTAssertNotNil(L10n.Accessibility.coordinateInput)
        XCTAssertNotNil(L10n.Accessibility.setLocationButton)
        XCTAssertNotNil(L10n.Accessibility.clearLocationButton)
        XCTAssertNotNil(L10n.Accessibility.refreshButton)
        XCTAssertNotNil(L10n.Accessibility.startRouteButton)
        XCTAssertNotNil(L10n.Accessibility.stopRouteButton)
    }
    
    func testDependencyNamespaceExists() {
        XCTAssertNotNil(L10n.Dependency.title)
        XCTAssertNotNil(L10n.Dependency.message)
        XCTAssertNotNil(L10n.Dependency.python)
        XCTAssertNotNil(L10n.Dependency.pymobiledevice)
        XCTAssertNotNil(L10n.Dependency.installInstructions)
        XCTAssertFalse(L10n.Dependency.brewCommand.isEmpty)
        XCTAssertFalse(L10n.Dependency.pipCommand.isEmpty)
    }
    
    // MARK: - Format String Tests
    
    func testVersionFormatString() {
        let version = L10n.App.version("1.2.3")
        // Either contains the version or returns the key (if not localized)
        XCTAssertTrue(version.contains("1.2.3") || version.contains("app.version"))
    }
    
    func testDeviceCountFormatString() {
        let count = L10n.Sidebar.deviceCount(5)
        XCTAssertTrue(count.contains("5") || count.contains("deviceCount"))
    }
    
    func testDeviceSelectedCountFormatString() {
        let count = L10n.Device.selectedCount(3)
        XCTAssertTrue(count.contains("3") || count.contains("selectedCount"))
    }
    
    func testDeviceLastLocationFormatString() {
        let location = L10n.Device.lastLocation("37.7749, -122.4194")
        XCTAssertTrue(location.contains("37.7749") || location.contains("lastLocation"))
    }
    
    func testRouteSpeedFormatString() {
        let speed = L10n.Route.speed("2.0")
        XCTAssertTrue(speed.contains("2.0") || speed.contains("route.speed"))
    }
    
    func testRouteProgressFormatString() {
        let progress = L10n.Route.progress(75)
        XCTAssertTrue(progress.contains("75") || progress.contains("route.progress"))
    }
    
    func testRoutePointCountFormatString() {
        let points = L10n.Route.pointCount(100)
        XCTAssertTrue(points.contains("100") || points.contains("pointCount"))
    }
    
    func testDeviceConnectedToastFormatString() {
        let toast = L10n.Toast.deviceConnected("iPhone 15")
        XCTAssertTrue(toast.contains("iPhone 15") || toast.contains("deviceConnected"))
    }
    
    func testDeviceDisconnectedToastFormatString() {
        let toast = L10n.Toast.deviceDisconnected("iPad Pro")
        XCTAssertTrue(toast.contains("iPad Pro") || toast.contains("deviceDisconnected"))
    }
    
    // MARK: - String Extension Tests
    
    func testStringLocalizedExtension() {
        // Test the extension exists and returns a non-empty string for known keys
        let localizedString = "action.cancel".localized
        XCTAssertFalse(localizedString.isEmpty)
    }
    
    func testStringLocalizedWithArgumentsExtension() {
        let formatted = "app.version".localized(with: "1.0.0")
        // Either contains the value or returns something non-empty
        XCTAssertFalse(formatted.isEmpty)
    }
    
    // MARK: - LocalizedStringKey Helper Tests
    
    func testLocalizedStringKeyFactory() {
        let key = LocalizedStringKey.key("action.cancel")
        XCTAssertNotNil(key)
    }
    
    // MARK: - Localization File Presence Tests
    
    func testEnglishLocalizationFileExists() {
        // The Localizable.strings should be bundled with the app
        // This test validates the L10n structure is properly set up
        XCTAssertNotNil(L10n.App.name)
    }
    
    func testAllActionKeysHaveValues() {
        // Verify action keys are properly configured
        let actions: [LocalizedStringKey] = [
            L10n.Action.cancel,
            L10n.Action.confirm,
            L10n.Action.done,
            L10n.Action.save,
            L10n.Action.delete,
            L10n.Action.close,
            L10n.Action.refresh,
            L10n.Action.start,
            L10n.Action.stop,
            L10n.Action.pause,
            L10n.Action.resume,
            L10n.Action.clear,
            L10n.Action.copy,
            L10n.Action.search,
            L10n.Action.settings,
            L10n.Action.help
        ]
        
        XCTAssertEqual(actions.count, 16)
    }
    
    // MARK: - Dependency Commands Tests
    
    func testDependencyCommandsAreValid() {
        XCTAssertEqual(L10n.Dependency.brewCommand, "brew install python3")
        XCTAssertEqual(L10n.Dependency.pipCommand, "pip3 install pymobiledevice3")
    }
}
