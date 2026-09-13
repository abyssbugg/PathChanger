import XCTest
@testable import PathChanger

final class LocationInjectorFactoryTests: XCTestCase {
    func testShippingBuildIgnoresScriptedInjectorEnvironment() {
        let injector = LocationInjectorFactory.make(environment: [ProcessEnvironment.Keys.testLocationInjector: "1"], buildFlavor: .shipping)
        XCTAssertTrue(injector is DevLocationBridge)
    }

    func testReleaseTestingCanSelectScriptedInjector() {
        let injector = LocationInjectorFactory.make(environment: [ProcessEnvironment.Keys.testLocationInjector: "1"], buildFlavor: .releaseTesting)
        XCTAssertTrue(injector is ScriptedLocationInjector)
    }

    func testReleaseTestingDefaultsToRealInjectorWithoutEnvironmentFlag() {
        let injector = LocationInjectorFactory.make(environment: [:], buildFlavor: .releaseTesting)
        XCTAssertTrue(injector is DevLocationBridge)
    }

    @MainActor
    func testScriptedInjectorSeedsSyntheticReadyDevice() {
        let appState = AppState(
            startBackgroundServices: false,
            locationInjector: ScriptedLocationInjector()
        )
        let stableDeviceID = ScriptedLocationInjector.sessionIdentity.stableDeviceID

        XCTAssertEqual(appState.device.selectedDevice?.id, stableDeviceID)
        XCTAssertTrue(appState.device.usbDirectDeviceIds.contains(stableDeviceID))
        XCTAssertTrue(appState.canStartSimulation)
    }
}
