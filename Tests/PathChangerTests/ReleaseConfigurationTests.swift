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
    private func assertNoRegex(
        _ pattern: String,
        in text: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        XCTAssertNil(regex.firstMatch(in: text, range: range), message, file: file, line: line)
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

    func testReleaseWorkflowUsesAdHocGitHubDistribution() throws {
        let release = try readProjectFile(".github/workflows/release.yml")

        XCTAssertTrue(release.contains("scripts/validate-release-config.sh"))
        XCTAssertTrue(release.contains("Create App Bundle (Ad-Hoc)"))
        XCTAssertTrue(release.contains("PathChanger-${VERSION}-macOS.zip"))
        XCTAssertTrue(release.contains("PathChanger-${VERSION}-macOS.sha256"))
        XCTAssertTrue(release.contains("gh release upload"))
        XCTAssertFalse(release.contains("REQUIRE_PRODUCTION_SIGNING=1"))
        XCTAssertFalse(release.contains("MACOS_CERTIFICATE_P12_BASE64"))
        XCTAssertFalse(release.contains("xcrun notarytool submit"))
        XCTAssertFalse(release.contains("xcrun stapler staple"))
        XCTAssertFalse(release.contains("xcrun stapler validate"))
    }

    func testBundleScriptHasDeterministicOutputAndOptionalProductionGates() throws {
        let bundleScript = try readProjectFile("build-app-bundle.sh")

        // Wave 0 (commit 0fe4f99) replaced the fixed workspace default with a
        // per-run mktemp root to close a bundle-substitution TOCTOU, and asserts
        // the workspace is not a symlink, is owned by the caller, and is chmod 700.
        // Assert that hardening rather than the superseded fixed path.
        XCTAssertTrue(bundleScript.contains("mktemp -d \"${TMPDIR:-/tmp}/pathchanger-app-build.XXXXXXXX\""))
        XCTAssertTrue(bundleScript.contains("Build workspace must not be a symlink"))
        XCTAssertTrue(bundleScript.contains("Build workspace must be owned by the current user"))
        XCTAssertTrue(bundleScript.contains("chmod 700 \"$root\""))
        XCTAssertTrue(bundleScript.contains("REQUIRE_PRODUCTION_SIGNING=\"${REQUIRE_PRODUCTION_SIGNING:-0}\""))
        XCTAssertTrue(bundleScript.contains("Production bundle builds require a Developer ID signing identity"))
        XCTAssertTrue(bundleScript.contains("Developer ID signing identity not available in the current keychain"))
        XCTAssertFalse(bundleScript.contains("Sparkle.framework"))
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
        XCTAssertTrue(buildWrapper.contains("DIST_BUILD_ROOT=\"${APP_BUNDLE_DIST_ROOT:-$(pwd)/dist}\""))
        XCTAssertFalse(buildWrapper.contains("ln -s \"$DIST_BUILD_ROOT/PathChanger.app\" dist/PathChanger.app"))
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
        XCTAssertTrue(validator.contains("PathChanger-\\${VERSION}-macOS.zip"))
        XCTAssertTrue(validator.contains("PathChanger-\\${VERSION}-macOS.sha256"))
        XCTAssertTrue(validator.contains("must not require Apple Developer signing/notarization"))
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

    func testW1ConvergenceValidationScriptPassesWithoutMissingFileDiagnostics() throws {
        let process = Process()
        process.currentDirectoryURL = projectRoot
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["scripts/validate-w1-convergence-lock.sh"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("W1 convergence-lock validation passed."), text)
        XCTAssertFalse(text.contains("No such file or directory"), text)
        XCTAssertFalse(text.contains("PathChanger/UI/SidebarView.swift"), text)
    }

    func testInstallDocumentationMatchesCanonicalInstallerTarget() throws {
        let readme = try readProjectFile("README.md")
        let installScript = try readProjectFile("install.sh")

        XCTAssertTrue(installScript.contains("TARGET_APP=\"/Applications/PathChanger.app\""))
        XCTAssertTrue(installScript.contains("-name \"PathChanger*.app\""))
        XCTAssertTrue(readme.contains("/Applications/PathChanger.app"))
        XCTAssertFalse(readme.contains("PathChanger-New.app"))
        XCTAssertFalse(readme.contains("--install-main"))
    }

    func testReleaseDocsDoNotAdvertiseUnsupportedShortcutCommands() throws {
        let readme = try readProjectFile("README.md")
        let settingsView = try readProjectFile("PathChanger/UI/SettingsView.swift")

        for unsupportedShortcut in ["⌘⇧S", "⌘⌥↑", "⌘⌥↓"] {
            XCTAssertFalse(readme.contains(unsupportedShortcut), "README advertises unsupported shortcut \(unsupportedShortcut)")
            XCTAssertFalse(settingsView.contains(unsupportedShortcut), "Settings advertises unsupported shortcut \(unsupportedShortcut)")
        }
    }

    func testDocsAvoidHardCodedXCTestCounts() throws {
        let readme = try readProjectFile("README.md")
        let contributing = try readProjectFile("CONTRIBUTING.md")

        try assertNoRegex(#"\([0-9]+/[0-9]+ tests passing\)"#, in: contributing, "CONTRIBUTING must not hard-code total XCTest counts")
        try assertNoRegex(#"\([0-9]+ tests\)"#, in: readme, "README must not hard-code per-suite XCTest counts")
    }

    func testSampleRouteClaimsRequireSampleRouteAssets() throws {
        let readme = try readProjectFile("README.md")
        let sampleRoutesURL = projectRoot.appendingPathComponent("Resources/sample_routes", isDirectory: true)
        var isDirectory: ObjCBool = false
        let hasSampleRoutes = FileManager.default.fileExists(atPath: sampleRoutesURL.path, isDirectory: &isDirectory) && isDirectory.boolValue

        if !hasSampleRoutes {
            XCTAssertFalse(readme.contains("Resources/sample_routes/"), "README must not claim bundled sample GPX routes without assets")
        }
    }

    func testTunnelLogDocumentationMatchesRuntimePath() throws {
        let readme = try readProjectFile("README.md")
        let tunnelModes = try readProjectFile("DEPLOYMENT/TUNNEL_MODES.md")
        let runtime = try readProjectFile("PathChanger/Device/TunneldManager.swift")

        XCTAssertTrue(runtime.contains("Logs/PathChanger"))
        XCTAssertTrue(runtime.contains("tunnel.log"))

        for doc in [readme, tunnelModes] {
            XCTAssertFalse(doc.contains("/tmp/pathchanger_tunnel.log"))
            XCTAssertFalse(doc.contains("tunneld.log"))
            XCTAssertTrue(doc.contains("~/Library/Logs/PathChanger/tunnel.log"))
        }
    }

    func testGitHubDirectReleaseGuidanceDoesNotMentionNotarizationOrStapling() throws {
        let bundleScript = try readProjectFile("build-app-bundle.sh")

        XCTAssertFalse(bundleScript.contains("xcrun notarytool"))
        XCTAssertFalse(bundleScript.contains("xcrun stapler"))
        XCTAssertFalse(bundleScript.localizedCaseInsensitiveContains("Notarize:"))
        XCTAssertFalse(bundleScript.localizedCaseInsensitiveContains("Staple:"))
    }

    func testTunnelModesDoesNotLinkRemovedLegacyDeploymentDocs() throws {
        let tunnelModes = try readProjectFile("DEPLOYMENT/TUNNEL_MODES.md")

        XCTAssertFalse(tunnelModes.contains("03_SECURITY_VERIFICATION_CHECKLIST.md"))
        XCTAssertFalse(tunnelModes.contains("04_PERFORMANCE_BASELINE.md"))
    }

    func testValidatorCoversReleaseReadinessDocumentationDrift() throws {
        let validator = try readProjectFile("scripts/validate-release-config.sh")

        XCTAssertTrue(validator.contains("Documentation must not advertise PathChanger-New.app"))
        XCTAssertTrue(validator.contains("Documentation must not hard-code XCTest counts"))
        XCTAssertTrue(validator.contains("README must not claim bundled sample GPX routes unless assets exist"))
        XCTAssertTrue(validator.contains("Tunnel log documentation must match ~/Library/Logs/PathChanger/tunnel.log"))
        XCTAssertTrue(validator.contains("Build scripts must not advertise notarization/stapling for GitHub-direct distribution"))
        XCTAssertTrue(validator.contains("Deployment docs must not link removed legacy release documents"))
    }
}
