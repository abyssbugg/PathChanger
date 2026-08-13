//
//  LocalizationHelper.swift
//  PathChanger
//
//  Provides localization utilities and extensions for SwiftUI
//

import SwiftUI

// MARK: - Localized String Keys

/// Namespace for all localization string keys organized by category
enum L10n {
    // MARK: - App
    enum App {
        static let name = LocalizedStringKey("app.name")
        static func version(_ version: String) -> String {
            String(format: NSLocalizedString("app.version", comment: ""), version)
        }
    }

    // MARK: - Common Actions
    enum Action {
        static let cancel = LocalizedStringKey("action.cancel")
        static let confirm = LocalizedStringKey("action.confirm")
        static let done = LocalizedStringKey("action.done")
        static let save = LocalizedStringKey("action.save")
        static let delete = LocalizedStringKey("action.delete")
        static let close = LocalizedStringKey("action.close")
        static let refresh = LocalizedStringKey("action.refresh")
        static let start = LocalizedStringKey("action.start")
        static let stop = LocalizedStringKey("action.stop")
        static let pause = LocalizedStringKey("action.pause")
        static let resume = LocalizedStringKey("action.resume")
        static let clear = LocalizedStringKey("action.clear")
        static let copy = LocalizedStringKey("action.copy")
        static let search = LocalizedStringKey("action.search")
        static let settings = LocalizedStringKey("action.settings")
        static let help = LocalizedStringKey("action.help")
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let welcomeTitle = LocalizedStringKey("onboarding.welcome.title")
        static let welcomeSubtitle = LocalizedStringKey("onboarding.welcome.subtitle")
        static let step1Title = LocalizedStringKey("onboarding.step1.title")
        static let step1Description = LocalizedStringKey("onboarding.step1.description")
        static let step2Title = LocalizedStringKey("onboarding.step2.title")
        static let step2Description = LocalizedStringKey("onboarding.step2.description")
        static let step3Title = LocalizedStringKey("onboarding.step3.title")
        static let step3Description = LocalizedStringKey("onboarding.step3.description")
        static let getStarted = LocalizedStringKey("onboarding.getStarted")
        static let skip = LocalizedStringKey("onboarding.skip")
        static let next = LocalizedStringKey("onboarding.next")
        static let previous = LocalizedStringKey("onboarding.previous")
    }

    // MARK: - Sidebar
    enum Sidebar {
        static let devices = LocalizedStringKey("sidebar.devices")
        static let simulation = LocalizedStringKey("sidebar.simulation")
        static let routes = LocalizedStringKey("sidebar.routes")
        static let settings = LocalizedStringKey("sidebar.settings")
        static let noDevices = LocalizedStringKey("sidebar.noDevices")
        static let refreshDevices = LocalizedStringKey("sidebar.refreshDevices")
        static func deviceCount(_ count: Int) -> String {
            String(format: NSLocalizedString("sidebar.deviceCount", comment: ""), count)
        }
    }

    // MARK: - Device
    enum Device {
        static let connected = LocalizedStringKey("device.connected")
        static let disconnected = LocalizedStringKey("device.disconnected")
        static let usb = LocalizedStringKey("device.usb")
        static let wifi = LocalizedStringKey("device.wifi")
        static let unknown = LocalizedStringKey("device.unknown")
        static let select = LocalizedStringKey("device.select")
        static let multiSelect = LocalizedStringKey("device.multiSelect")
        static func selectedCount(_ count: Int) -> String {
            String(format: NSLocalizedString("device.selectedCount", comment: ""), count)
        }
        static func lastLocation(_ location: String) -> String {
            String(format: NSLocalizedString("device.lastLocation", comment: ""), location)
        }
        static let noLocation = LocalizedStringKey("device.noLocation")
    }

    // MARK: - Simulation
    enum Simulation {
        static let title = LocalizedStringKey("simulation.title")
        static let coordinates = LocalizedStringKey("simulation.coordinates")
        static let latitude = LocalizedStringKey("simulation.latitude")
        static let longitude = LocalizedStringKey("simulation.longitude")
        static let setLocation = LocalizedStringKey("simulation.setLocation")
        static let clearLocation = LocalizedStringKey("simulation.clearLocation")
        static let currentLocation = LocalizedStringKey("simulation.currentLocation")
        static let searchPlaceholder = LocalizedStringKey("simulation.searchPlaceholder")
        static let tapToSetLocation = LocalizedStringKey("simulation.tapToSetLocation")
        static let manualInput = LocalizedStringKey("simulation.manualInput")
    }

    // MARK: - Joystick
    enum Joystick {
        static let title = LocalizedStringKey("joystick.title")
        static let enable = LocalizedStringKey("joystick.enable")
        static let disable = LocalizedStringKey("joystick.disable")
        static let speed = LocalizedStringKey("joystick.speed")
        static let speedWalk = LocalizedStringKey("joystick.speedWalk")
        static let speedRun = LocalizedStringKey("joystick.speedRun")
        static let speedBike = LocalizedStringKey("joystick.speedBike")
        static let speedCar = LocalizedStringKey("joystick.speedCar")
        static let hint = LocalizedStringKey("joystick.hint")
    }

    // MARK: - Route
    enum Route {
        static let title = LocalizedStringKey("route.title")
        static let start = LocalizedStringKey("route.start")
        static let stop = LocalizedStringKey("route.stop")
        static let pause = LocalizedStringKey("route.pause")
        static let resume = LocalizedStringKey("route.resume")
        static func speed(_ multiplier: String) -> String {
            String(format: NSLocalizedString("route.speed", comment: ""), multiplier)
        }
        static func progress(_ percent: Int) -> String {
            String(format: NSLocalizedString("route.progress", comment: ""), percent)
        }
        static let loop = LocalizedStringKey("route.loop")
        static let pingPong = LocalizedStringKey("route.pingPong")
        static let importGPX = LocalizedStringKey("route.import")
        static let exportGPX = LocalizedStringKey("route.export")
        static let library = LocalizedStringKey("route.library")
        static let noRoute = LocalizedStringKey("route.noRoute")
        static func pointCount(_ count: Int) -> String {
            String(format: NSLocalizedString("route.pointCount", comment: ""), count)
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = LocalizedStringKey("settings.title")
        static let general = LocalizedStringKey("settings.general")
        static let appearance = LocalizedStringKey("settings.appearance")
        static let advanced = LocalizedStringKey("settings.advanced")
        static let about = LocalizedStringKey("settings.about")

        enum General {
            static let autoStartTunnel = LocalizedStringKey("settings.general.autoStartTunnel")
            static let autoStartTunnelDesc = LocalizedStringKey("settings.general.autoStartTunnelDesc")
            static let rememberLastLocation = LocalizedStringKey("settings.general.rememberLastLocation")
            static let rememberLastLocationDesc = LocalizedStringKey("settings.general.rememberLastLocationDesc")
        }

        enum Appearance {
            static let theme = LocalizedStringKey("settings.appearance.theme")
            static let themeLight = LocalizedStringKey("settings.appearance.themeLight")
            static let themeDark = LocalizedStringKey("settings.appearance.themeDark")
            static let themeSystem = LocalizedStringKey("settings.appearance.themeSystem")
            static let mapStyle = LocalizedStringKey("settings.appearance.mapStyle")
            static let mapStyleStandard = LocalizedStringKey("settings.appearance.mapStyleStandard")
            static let mapStyleSatellite = LocalizedStringKey("settings.appearance.mapStyleSatellite")
            static let mapStyleHybrid = LocalizedStringKey("settings.appearance.mapStyleHybrid")
        }

        enum Advanced {
            static let tunnelMode = LocalizedStringKey("settings.advanced.tunnelMode")
            static let tunnelModeAuto = LocalizedStringKey("settings.advanced.tunnelModeAuto")
            static let tunnelModeUSB = LocalizedStringKey("settings.advanced.tunnelModeUSB")
            static let tunnelModeWiFi = LocalizedStringKey("settings.advanced.tunnelModeWiFi")
            static let pythonPath = LocalizedStringKey("settings.advanced.pythonPath")
            static let pythonPathAuto = LocalizedStringKey("settings.advanced.pythonPathAuto")
            static let rateLimit = LocalizedStringKey("settings.advanced.rateLimit")
            static let rateLimitDesc = LocalizedStringKey("settings.advanced.rateLimitDesc")
        }
    }

    // MARK: - Tunnel
    enum Tunnel {
        static let status = LocalizedStringKey("tunnel.status")
        static let connected = LocalizedStringKey("tunnel.connected")
        static let disconnected = LocalizedStringKey("tunnel.disconnected")
        static let connecting = LocalizedStringKey("tunnel.connecting")
        static let error = LocalizedStringKey("tunnel.error")
        static let start = LocalizedStringKey("tunnel.start")
        static let stop = LocalizedStringKey("tunnel.stop")
        static let restart = LocalizedStringKey("tunnel.restart")
        static let modeUSB = LocalizedStringKey("tunnel.modeUSB")
        static let modeWiFi = LocalizedStringKey("tunnel.modeWiFi")
        static let modeDaemon = LocalizedStringKey("tunnel.modeDaemon")
    }

    // MARK: - Errors
    enum Error {
        static let title = LocalizedStringKey("error.title")
        static let unknown = LocalizedStringKey("error.unknown")
        static let deviceNotFound = LocalizedStringKey("error.deviceNotFound")
        static let tunnelNotRunning = LocalizedStringKey("error.tunnelNotRunning")
        static let invalidCoordinates = LocalizedStringKey("error.invalidCoordinates")
        static let rateLimited = LocalizedStringKey("error.rateLimited")
        static let timeout = LocalizedStringKey("error.timeout")
        static let developerModeRequired = LocalizedStringKey("error.developerModeRequired")
        static let pythonNotFound = LocalizedStringKey("error.pythonNotFound")
        static let pymobiledeviceNotFound = LocalizedStringKey("error.pymobiledeviceNotFound")
        static let connectionFailed = LocalizedStringKey("error.connectionFailed")
    }

    // MARK: - Toasts
    enum Toast {
        static let locationSet = LocalizedStringKey("toast.locationSet")
        static let locationCleared = LocalizedStringKey("toast.locationCleared")
        static func deviceConnected(_ name: String) -> String {
            String(format: NSLocalizedString("toast.deviceConnected", comment: ""), name)
        }
        static func deviceDisconnected(_ name: String) -> String {
            String(format: NSLocalizedString("toast.deviceDisconnected", comment: ""), name)
        }
        static let routeStarted = LocalizedStringKey("toast.routeStarted")
        static let routeStopped = LocalizedStringKey("toast.routeStopped")
        static let settingsSaved = LocalizedStringKey("toast.settingsSaved")
        static let copied = LocalizedStringKey("toast.copied")
        static let queued = LocalizedStringKey("toast.queued")
    }

    // MARK: - Accessibility
    enum Accessibility {
        static let map = LocalizedStringKey("accessibility.map")
        static let joystick = LocalizedStringKey("accessibility.joystick")
        static let deviceList = LocalizedStringKey("accessibility.deviceList")
        static let coordinateInput = LocalizedStringKey("accessibility.coordinateInput")
        static let setLocationButton = LocalizedStringKey("accessibility.setLocationButton")
        static let clearLocationButton = LocalizedStringKey("accessibility.clearLocationButton")
        static let refreshButton = LocalizedStringKey("accessibility.refreshButton")
        static let startRouteButton = LocalizedStringKey("accessibility.startRouteButton")
        static let stopRouteButton = LocalizedStringKey("accessibility.stopRouteButton")
    }

    // MARK: - Dependencies
    enum Dependency {
        static let title = LocalizedStringKey("dependency.title")
        static let message = LocalizedStringKey("dependency.message")
        static let python = LocalizedStringKey("dependency.python")
        static let pymobiledevice = LocalizedStringKey("dependency.pymobiledevice")
        static let installInstructions = LocalizedStringKey("dependency.installInstructions")
    }
}

// MARK: - String Extension for Localization

extension String {
    /// Returns the localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns the localized version with format arguments
    func localized(with arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

// MARK: - LocalizedStringKey Helpers

extension LocalizedStringKey {
    /// Creates a LocalizedStringKey from a string key
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}

// MARK: - View Extension for Localized Accessibility

extension View {
    /// Adds a localized accessibility label
    func localizedAccessibilityLabel(_ key: LocalizedStringKey) -> some View {
        self.accessibilityLabel(key)
    }

    /// Adds a localized accessibility hint
    func localizedAccessibilityHint(_ key: LocalizedStringKey) -> some View {
        self.accessibilityHint(key)
    }
}
