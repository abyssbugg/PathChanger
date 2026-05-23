import Foundation
import XCTest

final class ReleaseConfigurationTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testReleaseConfigurationValidationScriptPasses() throws {
        let process = Process()
        process.currentDirectoryURL = projectRoot
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/validate-release-config.sh"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("Release configuration validation passed."), text)
    }

    func testWorkflowsDoNotContainToleratedFailures() throws {
        let ci = try readProjectFile(".github/workflows/ci.yml")
        let release = try readProjectFile(".github/workflows/release.yml")

        XCTAssertFalse(ci.contains("|| true"))
        XCTAssertFalse(release.contains("|| true"))
    }

    func testReleaseWorkflowRequiresProductionSigningAndNotarization() throws {
        let release = try readProjectFile(".github/workflows/release.yml")

        XCTAssertTrue(release.contains("scripts/validate-release-config.sh"))
        XCTAssertTrue(release.contains("REQUIRE_PRODUCTION_SIGNING=1"))
        XCTAssertTrue(release.contains("MACOS_CERTIFICATE_P12_BASE64"))
        XCTAssertTrue(release.contains("MACOS_DEVELOPER_ID_APPLICATION"))
        XCTAssertTrue(release.contains("xcrun notarytool submit"))
        XCTAssertTrue(release.contains("xcrun stapler staple"))
        XCTAssertTrue(release.contains("xcrun stapler validate"))
        XCTAssertTrue(release.contains("SPARKLE_PRIVATE_KEY"))
        XCTAssertTrue(release.contains("sparkle-tools/bin/sign_update"))
        XCTAssertTrue(release.contains("SIGN_UPDATE_OUTPUT"))
        XCTAssertTrue(release.contains("sparkle:edSignature"))
        XCTAssertTrue(release.contains("test -s \"$DMG_PATH\""))
        XCTAssertFalse(release.contains("create-dmg"))
    }

    func testBundleScriptHasDeterministicOutputAndProductionGates() throws {
        let bundleScript = try readProjectFile("build-app-bundle.sh")

        XCTAssertTrue(bundleScript.contains("APP_BUNDLE_BUILD_ROOT=\"${APP_BUNDLE_BUILD_ROOT:-${TMPDIR:-/tmp}/pathchanger-app-build}\""))
        XCTAssertTrue(bundleScript.contains("REQUIRE_PRODUCTION_SIGNING=\"${REQUIRE_PRODUCTION_SIGNING:-0}\""))
        XCTAssertTrue(bundleScript.contains("Production bundle builds require a Developer ID signing identity"))
        XCTAssertTrue(bundleScript.contains("Developer ID signing identity not available in the current keychain"))
        XCTAssertTrue(bundleScript.contains("Sparkle.framework not found; production app bundle cannot be validated"))
        XCTAssertTrue(bundleScript.contains("Production app bundle signing requires $ENTITLEMENTS_FILE"))
        XCTAssertTrue(bundleScript.contains("Production app bundle is missing hardened runtime"))
    }

    func testBuildWrapperSanitizesDistMetadataBeforeValidation() throws {
        let buildWrapper = try readProjectFile("build.sh")

        XCTAssertTrue(buildWrapper.contains("xattr -dr com.apple.FinderInfo"))
        XCTAssertTrue(buildWrapper.contains("xattr -dr \"com.apple.fileprovider.fpfs#P\""))
        XCTAssertTrue(buildWrapper.contains("find \"$bundle\" -print0"))
        XCTAssertTrue(buildWrapper.contains("xattr -d com.apple.FinderInfo \"$path\""))
        XCTAssertTrue(buildWrapper.contains("xattr -d \"com.apple.fileprovider.fpfs#P\" \"$path\""))
        XCTAssertTrue(buildWrapper.contains("DIST_BUILD_ROOT=\"${APP_BUNDLE_DIST_ROOT:-$HOME/Library/Caches/PathChanger/InternalBuild}\""))
        XCTAssertTrue(buildWrapper.contains("ln -s \"$DIST_BUILD_ROOT/PathChanger.app\" dist/PathChanger.app"))
        XCTAssertTrue(buildWrapper.contains("dot_clean -m \"$DIST_BUILD_ROOT/PathChanger.app\""))
    }

    func testReleaseValidatorChecksConfigurationAndEntitlementRisk() throws {
        let validator = try readProjectFile("scripts/validate-release-config.sh")

        XCTAssertTrue(validator.contains("CFBundleShortVersionString"))
        XCTAssertTrue(validator.contains("CFBundleVersion"))
        XCTAssertTrue(validator.contains("com.apple.security.get-task-allow"))
        XCTAssertTrue(validator.contains("com.apple.security.cs.allow-unsigned-executable-memory"))
        XCTAssertTrue(validator.contains("com.apple.security.cs.disable-library-validation"))
        XCTAssertTrue(validator.contains("com.apple.security.cs.allow-dyld-environment-variables"))
        XCTAssertTrue(validator.contains("xcrun notarytool submit"))
        XCTAssertTrue(validator.contains("xcrun stapler staple"))
        XCTAssertTrue(validator.contains("xcrun stapler validate"))
        XCTAssertTrue(validator.contains("CI/release workflows must not contain tolerated failures"))
    }

    func testPreDeploymentVerificationRunsReleaseConfigGate() throws {
        let preDeployment = try readProjectFile("DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh")

        XCTAssertTrue(preDeployment.contains("scripts/validate-release-config.sh"))
        XCTAssertTrue(preDeployment.contains("REQUIRE_PRODUCTION_SIGNING"))
        XCTAssertTrue(preDeployment.contains("Resources/Info.plist"))
        XCTAssertTrue(preDeployment.contains("No Developer ID certificates found for production verification"))
        XCTAssertFalse(preDeployment.contains("PathChanger/Info.plist"))
    }
}
