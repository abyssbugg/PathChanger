//
//  UIComponentTests.swift
//  PathChangerTests
//
//  Tests for UI components, view models, and toast system
//

import XCTest
@testable import PathChanger

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
        XCTAssertTrue(content.contains(".frame(maxWidth: 360"))
        XCTAssertTrue(content.contains("private var statusCluster: some View"))
        XCTAssertTrue(content.contains("private var clearLocationButton: some View"))
        XCTAssertTrue(content.contains("statusChip(titleKey: \"location.status.domain.connection\""))
        XCTAssertTrue(content.contains("statusChip(titleKey: \"location.status.domain.application\""))
        XCTAssertTrue(content.contains("statusChip(titleKey: \"location.status.domain.movement\""))
        XCTAssertFalse(chrome.contains("Circle().fill(Color(hex: 0xE8695E))"))
        XCTAssertTrue(chrome.contains(".frame(height: 56)"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }
}
