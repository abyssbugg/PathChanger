//
//  UIComponentTests.swift
//  PathChangerTests
//
//  Tests for UI components, view models, and toast system
//

import XCTest
@testable import PathChanger

// MARK: - Move Disabled Reason Tests

final class MoveDisabledReasonTests: XCTestCase {
    private func reason(
        canMove: Bool = false,
        hasDevice: Bool = true,
        clearBlock: LocationClearBlock? = nil,
        canStartSimulation: Bool = true,
        mode: AppMode = .teleport
    ) -> MoveDisabledReason? {
        MoveDisabledReason.select(
            canMove: canMove,
            hasDevice: hasDevice,
            clearBlock: clearBlock,
            canStartSimulation: canStartSimulation,
            mode: mode
        )
    }

    func testAClearInProgressOrUnresolvedIsNamedInsteadOfDeviceNotReady() {
        // Live 2026-11-01: an unresolved Clear blocked Move while the card said
        // "Wait for the selected device to become ready" on a ready device.
        XCTAssertEqual(reason(clearBlock: .clearInProgress, canStartSimulation: false), .clearInProgress)
        XCTAssertEqual(reason(clearBlock: .clearUnresolved, canStartSimulation: false), .clearUnresolved)
        XCTAssertEqual(reason(clearBlock: nil, canStartSimulation: false), .notReady)
    }

    func testOtherReasonsAreUnchanged() {
        XCTAssertNil(reason(canMove: true, clearBlock: .clearUnresolved))
        XCTAssertEqual(reason(hasDevice: false, clearBlock: .clearUnresolved), .noDevice)
        XCTAssertEqual(reason(mode: .teleport), .selectLocation)
        XCTAssertEqual(reason(mode: .jump), .addWaypoints)
        XCTAssertEqual(reason(mode: .twospot), .addWaypoints)
        XCTAssertEqual(reason(mode: .route), .addWaypoints)
        XCTAssertEqual(reason(mode: .joystick), .selectLocation)
        XCTAssertNil(reason(mode: .settings))
    }

    func testClearReasonsHaveTheirOwnText() {
        let notReady = MoveDisabledReason.notReady.text
        for clearReason in [MoveDisabledReason.clearInProgress, .clearUnresolved] {
            XCTAssertFalse(clearReason.text.isEmpty)
            XCTAssertNotEqual(clearReason.text, notReady)
            XCTAssertFalse(clearReason.text.hasPrefix("location.action."), "Missing string for \(clearReason)")
        }
        XCTAssertNotEqual(MoveDisabledReason.clearInProgress.text, MoveDisabledReason.clearUnresolved.text)
    }

    func testUnconfirmedClearTextDoesNotClaimTheClearFailedAndNamesTheRealButton() throws {
        // The Clear may have finished on the phone; the app only could not confirm it.
        // The Clear button is not localized, so the ja text must say "Clear" too.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let english = try String(
            contentsOf: root.appendingPathComponent("PathChanger/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )
        let japanese = try String(
            contentsOf: root.appendingPathComponent("PathChanger/Resources/ja.lproj/Localizable.strings"),
            encoding: .utf8
        )
        XCTAssertTrue(english.contains(
            "\"location.action.disabled.clearUnresolved\" = " +
            "\"PathChanger could not confirm the last Clear. Press Clear again to enable Move.\";"
        ))
        let jaLine = try XCTUnwrap(japanese.components(separatedBy: "\n")
            .first { $0.hasPrefix("\"location.action.disabled.clearUnresolved\"") })
        XCTAssertTrue(jaLine.contains("「Clear」"), jaLine)
        XCTAssertFalse(jaLine.contains("クリア"), jaLine)
        XCTAssertFalse(jaLine.contains("完了しませんでした"), jaLine)
    }
}

// MARK: - Device Chrome Reachability Text Tests

/// Live 2026-11-01: usbmux did not list the phone for 3.5 minutes while the chip read
/// "iOS 27.2 · trusted · Wi-Fi" from the connection-mode setting.
final class OrganicDeviceChromeTextTests: XCTestCase {
    private let device = Device(
        id: "00008130-0011223344556677", displayName: "iPhone",
        connectionType: .wifi, productType: "iPhone17,1", productVersion: "27.2"
    )

    func testEachReachabilityHasAPlainWord() {
        for mode in DeviceManager.ConnectionMode.allCases {
            XCTAssertEqual(OrganicDeviceChromeText.reachabilityWord(.connected, mode: mode), "connected")
            XCTAssertEqual(OrganicDeviceChromeText.reachabilityWord(.readyUSB, mode: mode), "ready on USB")
            XCTAssertEqual(OrganicDeviceChromeText.reachabilityWord(.readyWiFi, mode: mode), "ready on Wi\u{2011}Fi")
            XCTAssertEqual(OrganicDeviceChromeText.reachabilityWord(.onNetwork, mode: mode), "on Wi\u{2011}Fi network")
        }
    }

    func testNotReachableAdviceFollowsTheConnectionMode() {
        // Review 2026-11-01 (issue 7): in USB mode an unplugged phone was told to unlock
        // and stay on Wi-Fi. USB advice names the cable; Wi-Fi advice only in Wi-Fi/Auto.
        XCTAssertEqual(
            OrganicDeviceChromeText.reachabilityWord(.notReachable, mode: .usb),
            "not reachable — connect the cable and unlock"
        )
        for mode in [DeviceManager.ConnectionMode.wifi, .auto, .random] {
            XCTAssertEqual(
                OrganicDeviceChromeText.reachabilityWord(.notReachable, mode: mode),
                "not reachable — unlock iPhone",
                "\(mode)"
            )
        }
    }

    func testTheSubtitleNamesVersionAndReachabilityWithoutClaimingTrust() {
        XCTAssertEqual(
            OrganicDeviceChromeText.subtitle(device: device, reachability: .notReachable, mode: .wifi),
            "iOS 27.2 · not reachable — unlock iPhone"
        )
        XCTAssertEqual(
            OrganicDeviceChromeText.subtitle(device: device, reachability: .notReachable, mode: .usb),
            "iOS 27.2 · not reachable — connect the cable and unlock"
        )
        XCTAssertEqual(
            OrganicDeviceChromeText.subtitle(device: device, reachability: .readyWiFi, mode: .auto),
            "iOS 27.2 · ready on Wi\u{2011}Fi"
        )
        XCTAssertEqual(OrganicDeviceChromeText.subtitle(device: nil, reachability: .notReachable, mode: .wifi), "No iOS device")
    }

    func testTheTunnelHelpAsksToUnlockOnlyWhenStoppedAndUnreachable() throws {
        for mode in [DeviceManager.ConnectionMode.wifi, .auto, .random] {
            let hint = try XCTUnwrap(
                OrganicDeviceChromeText.unreachableTunnelHelp(reachability: .notReachable, tunnelRunning: false, mode: mode)
            )
            XCTAssertTrue(hint.contains("Unlock"), hint)
            XCTAssertTrue(hint.contains("same Wi\u{2011}Fi"), hint)
        }
        for mode in DeviceManager.ConnectionMode.allCases {
            XCTAssertNil(OrganicDeviceChromeText.unreachableTunnelHelp(reachability: .notReachable, tunnelRunning: true, mode: mode))
            XCTAssertNil(OrganicDeviceChromeText.unreachableTunnelHelp(reachability: .onNetwork, tunnelRunning: false, mode: mode))
        }
    }

    func testUSBModeTunnelHelpAsksForACableUnlockAndTrust() throws {
        let hint = try XCTUnwrap(
            OrganicDeviceChromeText.unreachableTunnelHelp(reachability: .notReachable, tunnelRunning: false, mode: .usb)
        )
        XCTAssertTrue(hint.contains("data cable"), hint)
        XCTAssertTrue(hint.contains("unlock"), hint)
        XCTAssertTrue(hint.contains("Trust"), hint)
        XCTAssertFalse(hint.contains("Wi\u{2011}Fi"), hint)
        XCTAssertFalse(hint.contains("Wi-Fi"), hint)
    }

    /// Source-text check, kept on purpose: it guards only the view binding (that the
    /// title bar and picker rows call the pure text functions above with live
    /// reachability and the connection mode). The wording is tested by behavior above;
    /// rendering `OrganicTitleBar` needs a full AppState and `TunneldManager.shared`, and
    /// the package has no view-inspection dependency.
    func testTheChromeReadsReachabilityInsteadOfTheModeSettingOrATrustClaim() throws {
        let chrome = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PathChanger/UI/OrganicChrome.swift"))
        XCTAssertFalse(chrome.contains("· trusted ·"))
        XCTAssertFalse(chrome.contains("Text(device.isWireless ? \"Wi-Fi\" : \"USB\")"))
        XCTAssertTrue(chrome.contains("OrganicDeviceChromeText.subtitle("))
        XCTAssertTrue(chrome.contains("OrganicDeviceChromeText.reachabilityWord(reachability(of: device), mode: connectionMode)"))
    }
}

// MARK: - Organic Appearance Tests

final class OrganicAppearanceTests: XCTestCase {
    func testPersistedRawValuesAreStable() {
        XCTAssertEqual(OrganicAppearance.light.rawValue, "light")
        XCTAssertEqual(OrganicAppearance.dark.rawValue, "dark")
    }

    func testPersistedAppearanceFallsBackToLight() {
        XCTAssertEqual(OrganicAppearance.persisted(nil), .light)
        XCTAssertEqual(OrganicAppearance.persisted("unknown"), .light)
        XCTAssertEqual(OrganicAppearance.persisted("dark"), .dark)
    }
}

@MainActor
final class LocationFavoritesMockDataTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LocationFavoritesMockDataTests")
        defaults.removePersistentDomain(forName: "LocationFavoritesMockDataTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "LocationFavoritesMockDataTests")
        defaults = nil
        super.tearDown()
    }

    func testFreshStoreContainsCanonicalBuiltInPlaces() {
        let manager = LocationFavoritesManager(defaults: defaults)

        XCTAssertEqual(manager.places.count, 8)
        XCTAssertEqual(manager.places.first?.name, "Marina Road")
        XCTAssertTrue(manager.places.contains { $0.name == "Shibuya Crossing" })
        XCTAssertTrue(manager.places.contains { $0.name == "Opera House" })
    }

    func testRecentHistoryKeepsNewestFourteenEntries() {
        let manager = LocationFavoritesManager(defaults: defaults)

        for index in 0..<20 {
            manager.recordRecent(
                name: "Place \(index)",
                coordinate: LocationCoordinate(latitude: Double(index), longitude: Double(index))
            )
        }

        XCTAssertEqual(manager.recents.count, 14)
        XCTAssertEqual(manager.recents.first?.name, "Place 19")
    }
}

// MARK: - Toast Manager Tests

@MainActor
final class ToastManagerTests: XCTestCase {

    var manager: ToastManager!

    override func setUp() async throws {
        manager = ToastManager.shared
        manager.dismissAll()
    }

    override func tearDown() async throws {
        manager.dismissAll()
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(ToastManager.shared)
    }

    func testInitiallyEmpty() {
        XCTAssertTrue(manager.toasts.isEmpty)
    }

    func testShowAddsToast() {
        let toast = Toast(type: .info, message: "Test message")
        manager.show(toast)

        XCTAssertEqual(manager.toasts.count, 1)
        XCTAssertEqual(manager.toasts.first?.message, "Test message")
    }

    func testSuccessConvenienceMethod() {
        manager.success("Success message")

        XCTAssertEqual(manager.toasts.count, 1)
        XCTAssertEqual(manager.toasts.first?.type, .success)
    }

    func testErrorConvenienceMethod() {
        manager.error("Error message")

        XCTAssertEqual(manager.toasts.count, 1)
        XCTAssertEqual(manager.toasts.first?.type, .error)
    }

    func testWarningConvenienceMethod() {
        manager.warning("Warning message")

        XCTAssertEqual(manager.toasts.count, 1)
        XCTAssertEqual(manager.toasts.first?.type, .warning)
    }

    func testInfoConvenienceMethod() {
        manager.info("Info message")

        XCTAssertEqual(manager.toasts.count, 1)
        XCTAssertEqual(manager.toasts.first?.type, .info)
    }

    func testDismissRemovesToast() {
        let toast = Toast(type: .info, message: "Test")
        manager.show(toast)

        XCTAssertEqual(manager.toasts.count, 1)

        manager.dismiss(toast)

        XCTAssertTrue(manager.toasts.isEmpty)
    }

    func testDismissAllClearsAllToasts() {
        manager.show(Toast(type: .info, message: "1"))
        manager.show(Toast(type: .success, message: "2"))
        manager.show(Toast(type: .error, message: "3"))

        XCTAssertEqual(manager.toasts.count, 3)

        manager.dismissAll()

        XCTAssertTrue(manager.toasts.isEmpty)
    }

    func testDuplicateMessagesNotShown() {
        manager.show(Toast(type: .info, message: "Duplicate"))
        manager.show(Toast(type: .info, message: "Duplicate"))

        XCTAssertEqual(manager.toasts.count, 1)
    }

    func testMaxVisibleToastsEnforced() {
        for i in 1...5 {
            manager.show(Toast(type: .info, message: "Toast \(i)"))
        }

        // Should be limited to maxVisibleToasts (3)
        XCTAssertLessThanOrEqual(manager.toasts.count, 3)
    }
}

// MARK: - Toast Model Tests

final class ToastModelTests: XCTestCase {

    func testToastInitialization() {
        let toast = Toast(type: .success, message: "Test")

        XCTAssertEqual(toast.type, .success)
        XCTAssertEqual(toast.message, "Test")
        XCTAssertEqual(toast.duration, 3.0)
    }

    func testToastCustomDuration() {
        let toast = Toast(type: .error, message: "Error", duration: 5.0)

        XCTAssertEqual(toast.duration, 5.0)
    }

    func testToastIdentifiable() {
        let toast1 = Toast(type: .info, message: "1")
        let toast2 = Toast(type: .info, message: "1")

        // Different IDs even with same content
        XCTAssertNotEqual(toast1.id, toast2.id)
    }

    func testToastEquatable() {
        let toast1 = Toast(type: .info, message: "Test")
        let toast2 = toast1

        XCTAssertEqual(toast1, toast2)
    }
}

// MARK: - Toast Type Tests

final class ToastTypeTests: XCTestCase {

    func testSuccessType() {
        XCTAssertEqual(ToastType.success.icon, "checkmark.circle.fill")
    }

    func testErrorType() {
        XCTAssertEqual(ToastType.error.icon, "xmark.circle.fill")
    }

    func testWarningType() {
        XCTAssertEqual(ToastType.warning.icon, "exclamationmark.triangle.fill")
    }

    func testInfoType() {
        XCTAssertEqual(ToastType.info.icon, "info.circle.fill")
    }

    func testAllTypesHaveDistinctIcons() {
        let icons = [
            ToastType.success.icon,
            ToastType.error.icon,
            ToastType.warning.icon,
            ToastType.info.icon
        ]

        let uniqueIcons = Set(icons)
        XCTAssertEqual(icons.count, uniqueIcons.count)
    }
}

// MARK: - Onboarding Step Tests

final class OnboardingStepTests: XCTestCase {

    func testStepOrder() {
        XCTAssertEqual(OnboardingStep.welcome.rawValue, 0)
        XCTAssertEqual(OnboardingStep.dependencies.rawValue, 1)
        XCTAssertEqual(OnboardingStep.deviceSetup.rawValue, 2)
        XCTAssertEqual(OnboardingStep.complete.rawValue, 3)
    }

    func testAllStepsCasesCount() {
        XCTAssertEqual(OnboardingStep.allCases.count, 4)
    }

    func testStepTitles() {
        XCTAssertEqual(OnboardingStep.welcome.title, "Welcome to PathChanger")
        XCTAssertEqual(OnboardingStep.dependencies.title, "System Dependencies")
        XCTAssertEqual(OnboardingStep.deviceSetup.title, "Device Setup")
        XCTAssertEqual(OnboardingStep.complete.title, "Ready to Go!")
    }

    func testStepIcons() {
        XCTAssertEqual(OnboardingStep.welcome.icon, "hand.wave.fill")
        XCTAssertEqual(OnboardingStep.dependencies.icon, "checkmark.circle.fill")
        XCTAssertEqual(OnboardingStep.deviceSetup.icon, "iphone.gen3")
        XCTAssertEqual(OnboardingStep.complete.icon, "flag.checkered")
    }
}

// MARK: - Onboarding View Model Tests

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    var viewModel: OnboardingViewModel!

    override func setUp() async throws {
        viewModel = OnboardingViewModel()
    }

    func testInitialStep() {
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testNextStep() {
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .dependencies)

        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .deviceSetup)

        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .complete)
    }

    func testPreviousStep() {
        viewModel.currentStep = .complete

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .deviceSetup)

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .dependencies)

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testPreviousStepAtWelcomeStaysAtWelcome() {
        XCTAssertEqual(viewModel.currentStep, .welcome)

        viewModel.previousStep()

        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testNextStepAtCompleteStaysAtComplete() {
        viewModel.currentStep = .complete

        viewModel.nextStep()

        XCTAssertEqual(viewModel.currentStep, .complete)
    }

    func testInitialDependencyResultIsNil() {
        XCTAssertNil(viewModel.dependencyResult)
    }

    func testIsCheckingDependenciesInitiallyFalse() {
        XCTAssertFalse(viewModel.isCheckingDependencies)
    }

    func testShowCopiedToastInitiallyFalse() {
        XCTAssertFalse(viewModel.showCopiedToast)
    }
}

// MARK: - Dependency Check Result Tests

final class DependencyCheckResultTests: XCTestCase {

    func testAllDependenciesMetWhenAllValid() {
        let result = DependencyCheckResult(
            python3Installed: true,
            pythonVersion: "3.11.0",
            pymobiledevice3Installed: true,
            pymobiledevice3Version: "6.1.5",
            pythonVersionValid: true,
            pymobiledevice3VersionValid: true
        )

        XCTAssertTrue(result.allDependenciesMet)
    }

    func testDependenciesNotMetWhenPythonMissing() {
        let result = DependencyCheckResult(
            python3Installed: false,
            pythonVersion: nil,
            pymobiledevice3Installed: true,
            pymobiledevice3Version: "6.1.5",
            pythonVersionValid: false,
            pymobiledevice3VersionValid: true
        )

        XCTAssertFalse(result.allDependenciesMet)
    }

    func testDependenciesNotMetWhenPymobiledevice3Missing() {
        let result = DependencyCheckResult(
            python3Installed: true,
            pythonVersion: "3.11.0",
            pymobiledevice3Installed: false,
            pymobiledevice3Version: nil,
            pythonVersionValid: true,
            pymobiledevice3VersionValid: false
        )

        XCTAssertFalse(result.allDependenciesMet)
    }

    func testDependenciesNotMetWhenVersionsInvalid() {
        let result = DependencyCheckResult(
            python3Installed: true,
            pythonVersion: "3.8.0",
            pymobiledevice3Installed: true,
            pymobiledevice3Version: "5.0.0",
            pythonVersionValid: false,
            pymobiledevice3VersionValid: false
        )

        XCTAssertFalse(result.allDependenciesMet)
    }
}

// MARK: - App Settings Tests

@MainActor
final class AppSettingsTests: XCTestCase {

    func testSharedInstanceExists() {
        XCTAssertNotNil(AppSettings.shared)
    }

    func testDefaultRateLimitCapacity() {
        let settings = AppSettings.shared
        let capacity = settings.rateLimitCapacity

        // Should be within valid range
        XCTAssertGreaterThan(capacity, 0)
        XCTAssertLessThanOrEqual(capacity, 100)
    }

    func testDefaultRefillRate() {
        let settings = AppSettings.shared
        let rate = settings.rateLimitRefillRate

        // Should be within valid range
        XCTAssertGreaterThan(rate, 0)
        XCTAssertLessThanOrEqual(rate, 50.0)
    }

    func testDefaultCommandTimeout() {
        let settings = AppSettings.shared
        let timeout = settings.commandTimeout

        // Should be within valid range
        XCTAssertGreaterThan(timeout, 0)
        XCTAssertLessThanOrEqual(timeout, 60.0)
    }

    func testDefaultTunnelTimeout() {
        let settings = AppSettings.shared
        let timeout = settings.tunnelTimeout

        // Should be within valid range
        XCTAssertGreaterThan(timeout, 0)
        XCTAssertLessThanOrEqual(timeout, 120.0)
    }

    func testResetToDefaults() {
        let settings = AppSettings.shared

        // Modify values
        settings.commandTimeout = 5.0
        settings.tunnelTimeout = 10.0

        // Reset
        settings.resetToDefaults()

        // Should be reset to defaults
        XCTAssertEqual(settings.commandTimeout, AppConstants.Timeout.defaultCommandTimeout)
        XCTAssertEqual(settings.tunnelTimeout, AppConstants.Timeout.defaultTunnelTimeout)
    }
}


final class LegacyLocationSemanticsPresentationTests: XCTestCase {
    func testActiveOrganicUIOmitsRetiredSafeModeCooldownAndDriftControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "PathChanger/UI/OrganicChrome.swift",
            "PathChanger/UI/OrganicSettingsSheet.swift",
        ]

        for path in paths {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(path))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("Safe Mode"), path)
            XCTAssertFalse(source.localizedCaseInsensitiveContains("cooldown"), path)
            XCTAssertFalse(source.localizedCaseInsensitiveContains("GPS drift"), path)
        }
    }

    func testRouteReverseActionDoesNotRestageDestination() throws {
        let source = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        let start = try XCTUnwrap(source.range(of: "Image(systemName: \"arrow.up.arrow.down\")"))
        let prefix = source[..<start.lowerBound]
        let buttonStart = try XCTUnwrap(prefix.range(of: "Button {", options: .backwards))
        let action = String(source[buttonStart.lowerBound..<start.lowerBound])

        XCTAssertTrue(action.contains("appState.reverseRoute(for: mode)"))
        XCTAssertFalse(action.contains("stageLocation"))
    }

    func testQuietBackpressureStatusIsGuarded() throws {
        let source = try sourceFile("PathChanger/Core/StateManagers/SimulationStateManager.swift")
        let start = try XCTUnwrap(source.range(of: "if case .rateLimited = error"))
        let suffix = source[start.lowerBound...]
        let end = try XCTUnwrap(suffix.range(of: "errorHandler.handle(error"))
        let rateLimitedBlock = String(suffix[..<end.lowerBound])

        XCTAssertTrue(rateLimitedBlock.contains("if !quiet {\n                    onStatusMessage?(\"Location update rejected by adapter backpressure\")"))
    }

    func testLiveStatusMetricsExposeLocalizedLabelsAndValues() throws {
        let source = try sourceFile("PathChanger/UI/ContentView.swift")
        let metrics = ["connection", "application", "movement", "coordinate"]

        for metric in metrics {
            XCTAssertTrue(source.contains("localizationKey: \"accessibility.location.status.\(metric)\""), metric)
        }
        XCTAssertTrue(source.contains(".accessibilityLabel(NSLocalizedString(localizationKey"))
        XCTAssertTrue(source.contains(".accessibilityValue(value)"))
    }

    func testStatusChromeUsesNativeTypographyAndSeparatedDomains() throws {
        let design = try sourceFile("PathChanger/UI/DesignSystem.swift")
        let content = try sourceFile("PathChanger/UI/ContentView.swift")
        let chrome = try sourceFile("PathChanger/UI/OrganicChrome.swift")

        XCTAssertTrue(design.contains(".system(size: size, weight: weight, design: .rounded)"))
        XCTAssertFalse(design.contains(".custom(bodyName, size: size).weight(weight)"))
        XCTAssertTrue(content.contains(".frame(maxWidth: LocationPanelMetrics.maxWidth)"), "the location panel is one panel of bounded width")
        XCTAssertTrue(content.contains("private var statusCluster: some View"))
        XCTAssertTrue(content.contains("private var clearLocationButton: some View"))
        XCTAssertTrue(content.contains(".init(titleKey: \"location.status.domain.connection\""), "a separate connection cell")
        XCTAssertTrue(content.contains(".init(titleKey: \"location.status.domain.application\""), "a separate application cell")
        XCTAssertTrue(content.contains(".init(titleKey: \"location.status.domain.movement\""), "a separate movement cell")
        XCTAssertFalse(chrome.contains("Circle().fill(Color(hex: 0xE8695E))"))
        XCTAssertTrue(chrome.contains(".frame(height: 56)"))
    }

    func testNoDeviceChromeDisablesUnavailableActions() throws {
        let chrome = try sourceFile("PathChanger/UI/OrganicChrome.swift")

        XCTAssertTrue(chrome.contains("private var hasSelectedDevice: Bool"))
        // The tunnel pill stays clickable while a Start waits for the phone, so the
        // wait can always be cancelled even if discovery drops the selection; and while
        // the tunnel reconnects by itself (review 2026-11-03 issue 1). The rule itself is
        // `TunnelPillAction.isEnabled` (LocationStatusPresentationTests).
        XCTAssertTrue(chrome.contains(".disabled(!isTunnelPillEnabled)"))
        XCTAssertTrue(chrome.contains("isWaitingForDevice: tunneldManager.isWaitingForDevice,\n            isAutoReconnecting: appState.isTunnelAutoReconnecting"))
        let transportStart = try XCTUnwrap(chrome.range(of: "OrganicSegmented("))
        let transportSuffix = chrome[transportStart.lowerBound...]
        let transportEnd = try XCTUnwrap(transportSuffix.range(of: ".padding(.leading, 12)"))
        let transportBlock = String(transportSuffix[..<transportEnd.lowerBound])
        XCTAssertFalse(transportBlock.contains(".disabled(!hasSelectedDevice)"))
        // GUI arrangement 2026-11-04: the device-count badge beside the name is gone (the
        // picker's header says how many); without a phone the reachability dot is grey.
        XCTAssertTrue(chrome.contains("guard hasDevice else { return Organic.neutral500 }"))
        XCTAssertTrue(chrome.contains("return count == 1 ? \"1 found\" : \"\\(count) found\""))
        XCTAssertTrue(chrome.contains("return \"No iOS device\""))
    }

    func testNoDeviceStatusAndDisabledMoveGuidanceAreTruthful() throws {
        let content = try sourceFile("PathChanger/UI/ContentView.swift")
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        let english = try sourceFile("PathChanger/Resources/en.lproj/Localizable.strings")

        XCTAssertTrue(content.contains("private var displayedConnectionLabel: String"))
        XCTAssertTrue(english.contains("\"location.status.domain.application\" = \"Location\";"))
        XCTAssertTrue(card.contains("private var disabledMoveReason: String?"))
        XCTAssertTrue(card.contains("private var canResetRoute: Bool"))
        XCTAssertTrue(card.contains(".disabled(!canResetRoute)"))
    }

    func testTeleportCardUsesCompactTargetOnlySemantics() throws {
        let source = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        XCTAssertTrue(source.contains("private var showsTravelMotion: Bool"))
        XCTAssertTrue(source.contains("mode == .jump || mode == .twospot || mode == .route"))
        XCTAssertTrue(source.contains("if showsTravelMotion"))
        XCTAssertTrue(source.contains("private var resetActionLabel: String"))
        XCTAssertTrue(source.contains("location.action.clearTarget"))
        XCTAssertTrue(source.contains("location.teleport.noTarget"))
        XCTAssertTrue(source.contains("location.teleport.targetHint"))
        XCTAssertTrue(source.contains("ContentHuggingLayout {"), "the card's content scrolls inside a height ceiling")
        XCTAssertFalse(Self.cardBodyReintroducesFixedSize(source), "fixedSize pushed the footer out of the window")
        XCTAssertTrue(try sourceFile("PathChanger/UI/ContentView.swift").contains(".padding(ModeContextCard.placementInsets)"))
        XCTAssertFalse(source.contains(".frame(maxHeight: 560)"))
    }

    /// True when the card's `body` applies `fixedSize` (vertical or bare) anywhere in its
    /// modifier chain, however the source is formatted (review 2026-11-02-163337 issue 9).
    /// The text views inside the card's blocks keep their own `fixedSize`.
    static func cardBodyReintroducesFixedSize(_ source: String) -> Bool {
        guard let start = source.range(of: "var body: some View {"),
              let end = source.range(of: "private var header: some View", range: start.upperBound..<source.endIndex) else {
            return true // the guard cannot find the card body: fail loudly
        }
        let body = String(source[start.upperBound..<end.lowerBound])
        let fixedSize = #"\.\s*fixedSize\s*\(\s*(horizontal\s*:\s*false\s*,\s*vertical\s*:\s*true\s*)?\)"#
        return body.range(of: fixedSize, options: .regularExpression) != nil
    }

    func testTheFixedSizeGuardSurvivesReformatting() throws {
        let original = """
            var body: some View {
                VStack(spacing: 0) { header; content; footer }
                .frame(width: 336)
                .fixedSize(horizontal: false, vertical: true)
            }

            private var header: some View {
        """
        let sameLine = """
            var body: some View {
                VStack(spacing: 0) { header; content; footer }
                .frame(width: 336).fixedSize(horizontal:false,vertical:true)
            }

            private var header: some View {
        """
        let laterInTheChain = """
            var body: some View {
                VStack(spacing: 0) { header; content; footer }
                .frame(width: 336)
                .background(Organic.neutral100)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            private var header: some View {
        """
        let bare = """
            var body: some View {
                VStack(spacing: 0) { header; content; footer }
                .frame(width: 336)
                .fixedSize()
            }

            private var header: some View {
        """
        let insideABlock = """
            var body: some View {
                VStack(spacing: 0) { header; content; footer }
                .frame(width: 336)
            }

            private var header: some View {
                Text("x").fixedSize(horizontal: false, vertical: true)
            }
        """
        for (name, sample) in [("original", original), ("same line", sameLine), ("later in the chain", laterInTheChain), ("bare", bare)] {
            XCTAssertTrue(Self.cardBodyReintroducesFixedSize(sample), "\(name) is caught")
        }
        XCTAssertFalse(Self.cardBodyReintroducesFixedSize(insideABlock), "a block's text keeps its own fixedSize")
    }

    /// Review 2026-11-02-163337 issue 8: the "At stop" and completion readouts index the
    /// run's stops (Two-Spot with one spot starts at the held location), not the route.
    func testStopReadoutsIndexTheRunsStops() throws {
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        XCTAssertTrue(card.contains("stops: appState.displayStops(for: mode),"))
        XCTAssertTrue(card.contains("totalStops: appState.displayStops(for: mode).count"))
        XCTAssertTrue(card.contains("total: appState.displayStops(for: mode).count"))
        XCTAssertFalse(card.contains("totalStops: appState.currentRoute.count"))
    }

    func testModeSelectorIsLabeledAccessibleAndUsesContrastSafeInk() throws {
        let content = try sourceFile("PathChanger/UI/ContentView.swift")
        let start = try XCTUnwrap(content.range(of: "private var modePill: some View"))
        let end = try XCTUnwrap(content.range(of: "private var handleButton"))
        let selector = String(content[start.lowerBound..<end.lowerBound])
        let design = try sourceFile("PathChanger/UI/DesignSystem.swift")
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")

        XCTAssertTrue(selector.contains("Text(mode.localizedLabel)"))
        XCTAssertTrue(selector.contains("minHeight: 44"))
        XCTAssertTrue(selector.contains("accessibilityLabel(mode.localizedLabel)"))
        XCTAssertTrue(selector.contains("accessibilityValue"))
        XCTAssertTrue(selector.contains("location.savedHistory"))
        XCTAssertTrue(design.contains("static let accentInk"))
        XCTAssertTrue(card.contains("foregroundStyle(canMove ? Organic.accentInk : Organic.neutral700)"))
    }

    func testModeContextCardPairsIdentifiersWithHumanLabels() throws {
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")

        // The Teleport empty-target callout keeps its identifier but reads human text.
        let emptyTarget = try XCTUnwrap(card.range(of: ".accessibilityIdentifier(\"location.teleport.emptyTarget\")"))
        let emptyTargetLabel = try XCTUnwrap(card[..<emptyTarget.lowerBound].range(of: ".accessibilityLabel(", options: .backwards))
        let emptyTargetPairing = String(card[emptyTargetLabel.lowerBound..<emptyTarget.upperBound])
        XCTAssertTrue(emptyTargetPairing.contains("location.teleport.noTarget"), "emptyTarget must pair with the human noTarget label")
        XCTAssertTrue(emptyTargetPairing.contains("location.teleport.targetHint"), "emptyTarget must carry the targetHint guidance")

        // The Move-disabled helper reads the reason text instead of its identifier.
        let disabledReason = try XCTUnwrap(card.range(of: ".accessibilityIdentifier(\"location.action.disabledReason\")"))
        let disabledReasonLabel = try XCTUnwrap(card[..<disabledReason.lowerBound].range(of: ".accessibilityLabel(", options: .backwards))
        let disabledReasonPairing = String(card[disabledReasonLabel.lowerBound..<disabledReason.upperBound])
        XCTAssertTrue(disabledReasonPairing.contains(".accessibilityLabel(reason)"), "disabledReason must pair with the human reason text")

        // The ROUTE header Download icon names what it does instead of its symbol.
        XCTAssertTrue(card.contains(".accessibilityLabel(\"Save every point to Favorites\")"))
    }

    func testJoystickStopMovementRequiresActiveMovement() throws {
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        let stopButton = try XCTUnwrap(card.range(of: "Button(\"Stop movement\")"))
        let suffix = card[stopButton.lowerBound...]
        let end = try XCTUnwrap(suffix.range(of: "} else {"))
        let stopBlock = String(suffix[..<end.lowerBound])

        XCTAssertTrue(stopBlock.contains("appState.disengageJoystick()"))
        XCTAssertTrue(stopBlock.contains(".disabled(!appState.locationPresentation.isMovementActive)"), "Stop movement must be disabled while movement is not active")
    }

    func testMapCanvasControlsExposeHumanAccessibilityLabels() throws {
        let source = try sourceFile("PathChanger/UI/SimulationView.swift")
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Center on device\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Zoom in\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Zoom out\")"))
    }

    func testModeContextCardRowsReadAsDiscreteVoiceOverElements() throws {
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")

        // Each route stop's name and coordinate read as one element, separate from its row buttons.
        let stopName = try XCTUnwrap(card.range(of: "Text(stop.name)"))
        let stopRowStart = try XCTUnwrap(card[..<stopName.lowerBound].range(of: "VStack(alignment: .leading, spacing: 1)", options: .backwards))
        let stopRowSuffix = card[stopRowStart.lowerBound...]
        let stopRowEnd = try XCTUnwrap(stopRowSuffix.range(of: "Spacer(minLength: 0)"))
        let stopRow = String(stopRowSuffix[..<stopRowEnd.lowerBound])
        XCTAssertTrue(stopRow.contains(".accessibilityElement(children: .combine)"), "each route stop reads as one element")

        // The travel-mode header reads together with its current value, separate from the picker buttons.
        let travelHeader = try XCTUnwrap(card.range(of: "Text(\"TRAVEL MODE\")"))
        let travelStart = try XCTUnwrap(card[..<travelHeader.lowerBound].range(of: "HStack {", options: .backwards))
        let travelSuffix = card[travelStart.lowerBound...]
        let travelEnd = try XCTUnwrap(travelSuffix.range(of: "OrganicSliderRow("))
        let travelBlock = String(travelSuffix[..<travelEnd.lowerBound])
        XCTAssertTrue(travelBlock.contains(".accessibilityElement(children: .combine)"), "the travel-mode header reads with its value")

        // Metric rows read title and value as one element with the decorative icon hidden.
        let metricRowStart = try XCTUnwrap(card.range(of: "private func metricRow(system: String, title: String, value: String) -> some View {"))
        let metricRowSuffix = card[metricRowStart.lowerBound...]
        let metricRowEnd = try XCTUnwrap(metricRowSuffix.range(of: "\n    }"))
        let metricRow = String(metricRowSuffix[..<metricRowEnd.lowerBound])
        XCTAssertTrue(metricRow.contains(".accessibilityElement(children: .combine)"), "each metric row reads as one element")
        XCTAssertTrue(metricRow.contains(".accessibilityHidden(true)"), "the metric icon is decorative")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }
}

// MARK: - Tunnel pill (GUI arrangement 2026-11-04)

/// The pill says where the tunnel stands and, separately, what a click does: "Tunnel live"
/// gave no hint that a click stops it, and "Reconnect tunnel" read as a status.
final class TunnelPillModelTests: XCTestCase {
    private func model(
        running: Bool = false, waiting: Bool = false, starting: Bool = false,
        error: Bool = false, reconnecting: Bool = false, device: Bool = true
    ) -> TunnelPillModel {
        TunnelPillModel.resolve(
            isRunning: running, isWaitingForDevice: waiting, isStarting: starting,
            isError: error, isAutoReconnecting: reconnecting, hasSelectedDevice: device
        )
    }

    func testALiveTunnelSaysLiveAndOffersStop() {
        let pill = model(running: true)
        XCTAssertEqual(pill.statusText, "Tunnel live")
        XCTAssertEqual(pill.actionText, "Stop")
        XCTAssertEqual(pill.accessibilityLabel, "Stop tunnel")
        XCTAssertEqual(pill.accessibilityValue, "Tunnel live")
        XCTAssertFalse(pill.showsProgress)
        XCTAssertTrue(pill.isEnabled)
    }

    func testAWaitForThePhoneOffersCancel() {
        let pill = model(waiting: true, starting: true)
        XCTAssertEqual(pill.statusText, "Waiting for iPhone…")
        XCTAssertEqual(pill.actionText, "Cancel")
        XCTAssertEqual(pill.accessibilityLabel, "Cancel waiting for the iPhone")
        XCTAssertTrue(pill.showsProgress)
    }

    func testAnAutomaticReconnectOffersStopReconnecting() {
        for starting in [false, true] {
            let pill = model(starting: starting, error: !starting, reconnecting: true, device: false)
            XCTAssertEqual(pill.statusText, "Reconnecting…")
            XCTAssertEqual(pill.actionText, "Stop")
            XCTAssertEqual(pill.accessibilityLabel, "Stop reconnecting")
            XCTAssertTrue(pill.showsProgress)
            XCTAssertTrue(pill.isEnabled, "the only way to stop the reconnect from the window")
        }
    }

    func testConnectingHasNoAction() {
        let pill = model(starting: true)
        XCTAssertEqual(pill.statusText, "Connecting…")
        XCTAssertNil(pill.actionText)
        XCTAssertEqual(pill.accessibilityLabel, "Connecting…")
        XCTAssertTrue(pill.showsProgress)
    }

    func testAFailedTunnelSaysFailedAndOffersReconnect() {
        let pill = model(error: true)
        XCTAssertEqual(pill.statusText, "Tunnel failed")
        XCTAssertEqual(pill.actionText, "Reconnect")
        XCTAssertEqual(pill.accessibilityLabel, "Reconnect tunnel")
        XCTAssertFalse(pill.showsProgress)
    }

    func testAStoppedTunnelOffersStart() {
        let pill = model()
        XCTAssertEqual(pill.statusText, "Tunnel off")
        XCTAssertEqual(pill.actionText, "Start tunnel")
        XCTAssertEqual(pill.accessibilityLabel, "Start tunnel")
        XCTAssertTrue(pill.isPrimary)
        XCTAssertFalse(model(device: false).isEnabled, "nothing to start without a phone")
    }

    func testTheLastAttemptLineIsItsOwnLabelledLine() {
        let notice = TunnelNotice(text: "Connection to the iPhone lost.\nLast attempt: iPhone is not reachable.\nReapplying…", isError: true)
        XCTAssertEqual(notice.lines, [
            TunnelNotice.Line(label: nil, text: "Connection to the iPhone lost."),
            TunnelNotice.Line(label: "Last attempt", text: "iPhone is not reachable."),
            TunnelNotice.Line(label: nil, text: "Reapplying…"),
        ])
    }
}

// MARK: - Connection choice (GUI arrangement 2026-11-04)

/// USB and Wi-Fi are the two choices the window offers; Auto, Random and Background
/// daemon stay reachable as secondary choices. The control shows the setting in use: in
/// Auto it used to highlight USB or Wi-Fi from the transport it guessed.
final class ConnectionChoiceTests: XCTestCase {
    func testTheChoiceFollowsTheConnectionModeSetting() {
        XCTAssertEqual(ConnectionChoice.current(connectionMode: .usb, tunnelMode: .usb), .usb)
        XCTAssertEqual(ConnectionChoice.current(connectionMode: .wifi, tunnelMode: .wifi), .wifi)
        XCTAssertEqual(ConnectionChoice.current(connectionMode: .auto, tunnelMode: .auto), .auto)
        XCTAssertEqual(ConnectionChoice.current(connectionMode: .random, tunnelMode: .wifi), .random)
    }

    func testBackgroundDaemonIsReadFromTheTunnelMode() {
        for mode in DeviceManager.ConnectionMode.allCases {
            XCTAssertEqual(ConnectionChoice.current(connectionMode: mode, tunnelMode: .daemon), .daemon, "\(mode)")
        }
    }

    func testUSBAndWiFiArePrimaryAndTheRestSecondary() {
        XCTAssertEqual(ConnectionChoice.primary, [.usb, .wifi])
        XCTAssertEqual(ConnectionChoice.secondary, [.auto, .random, .daemon])
        XCTAssertEqual(Set(ConnectionChoice.primary + ConnectionChoice.secondary).count, 5, "every mode stays reachable")
    }

    func testChoicesReadAsWords() {
        XCTAssertEqual(ConnectionChoice.usb.title, "USB")
        XCTAssertEqual(ConnectionChoice.wifi.title, "Wi\u{2011}Fi")
        XCTAssertEqual(ConnectionChoice.auto.title, "Auto")
        XCTAssertEqual(ConnectionChoice.daemon.title, "Background daemon")
        XCTAssertEqual(ConnectionChoice.daemon.shortTitle, "Daemon")
        for choice in ConnectionChoice.primary + ConnectionChoice.secondary {
            XCTAssertFalse(choice.detail.isEmpty, "\(choice) says what it does")
        }
    }
}
