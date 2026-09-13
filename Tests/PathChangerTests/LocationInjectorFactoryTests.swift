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
}
