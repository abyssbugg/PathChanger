import Foundation
import XCTest
@testable import PathChanger

final class DependencyLockTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testNoPinnedRequirementArtifactsRemain() throws {
        for name in ["requirements-location.in", "requirements-location.lock"] {
            let url = repositoryRoot.appendingPathComponent(name)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "\(name) must not exist: PathChanger tracks rolling-latest pymobiledevice3 (owner policy 2026-10-23), not a pinned snapshot"
            )
        }
    }

    func testManagedInstallerTracksRollingLatestPymobiledevice3() throws {
        let validatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Core/DependencyValidator.swift"),
            encoding: .utf8
        )
        let resolverSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Core/PythonPathResolver.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(validatorSource.contains("requirements-location.lock"), "Installer must not depend on a lock snapshot")
        XCTAssertFalse(validatorSource.contains("--require-hashes"), "Rolling-latest installs are not hash-locked")
        XCTAssertTrue(validatorSource.contains("bootstrapPythonCandidates"), "Installer must use the resolver's bootstrap candidate policy")
        XCTAssertTrue(resolverSource.contains(".pyenv"), "Bootstrap candidates must prefer a pyenv-managed interpreter")
        XCTAssertFalse(resolverSource.contains("--require-hashes"), "Install arguments must not be hash-locked")
    }

    @MainActor
    func testMissingManagedRuntimeOffersDeterministicInstaller() {
        let validator = DependencyValidator.shared
        let originalErrors = validator.errors
        defer { validator.errors = originalErrors }

        validator.errors = [
            DependencyValidator.ValidationError(
                type: .pythonMissing,
                message: "Managed runtime missing",
                suggestion: "Rebuild it"
            )
        ]

        XCTAssertTrue(validator.canInstallPymobiledevice3)
    }

    func testManagedInstallerSerializesAndRejectsSymlinkedRuntimePaths() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Core/DependencyValidator.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "private func rebuildManagedRuntime() async throws -> String")?.lowerBound,
              let end = source.range(of: "private func runInstallerCommand", range: start..<source.endIndex)?.lowerBound else {
            return XCTFail("Missing managed runtime installer implementation")
        }
        let installer = String(source[start..<end])
        XCTAssertTrue(installer.contains("O_CREAT | O_RDWR | O_NOFOLLOW"), "Installer must open a stable non-symlink lock inode")
        XCTAssertTrue(installer.contains("flock(lockDescriptor, LOCK_EX | LOCK_NB)"), "Installer must acquire a non-blocking advisory lock")
        XCTAssertTrue(installer.contains("flock(lockDescriptor, LOCK_UN)"), "Installer must release its advisory lock")
        XCTAssertFalse(installer.contains("O_EXCL"), "Crash-stale exclusive marker files must not block future installs")
        XCTAssertFalse(installer.contains("unlink(installLock.path)"), "Advisory lock inodes must remain stable across contenders")
        XCTAssertTrue(installer.contains("destinationOfSymbolicLink"), "Installer must reject symlinked runtime paths")
    }

    func testBuiltAppContainsRequiredLocationResources() throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.pathchanger.app")
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        for relativePath in [
            "location_bridge.py",
            "en.lproj/Localizable.strings",
            "ja.lproj/Localizable.strings",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resources.appendingPathComponent(relativePath).path),
                "Built application is missing \(relativePath)"
            )
        }
        for (resource, source) in [
            ("location_bridge.py", "scripts/location_bridge.py"),
        ] {
            let bundled = resources.appendingPathComponent(resource)
            if FileManager.default.fileExists(atPath: bundled.path) {
                XCTAssertEqual(
                    try Data(contentsOf: bundled),
                    try Data(contentsOf: repositoryRoot.appendingPathComponent(source)),
                    "Bundled \(resource) must match the verified source"
                )
            }
        }
    }

    func testBundleBuilderIsArtifactOnlyAndHonorsOutputRoot() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("build-app-bundle.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("APP_BUNDLE_BUILD_ROOT=\"${APP_BUNDLE_BUILD_ROOT:-build}\""))
        XCTAssertTrue(source.contains("APP_DIR=\"$APP_BUNDLE_BUILD_ROOT/$APP_BUNDLE_NAME\""))
        XCTAssertFalse(source.contains("/Applications/PathChanger.app"))
        XCTAssertFalse(source.contains("FlowDeck/DerivedData"))
        XCTAssertFalse(source.contains("/private/tmp"))
        XCTAssertFalse(source.contains("lsregister"))
    }

    func testNoLockPackagingRemains() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let bundleScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("build-app-bundle.sh"),
            encoding: .utf8
        )
        XCTAssertFalse(project.contains("requirements-location"), "project.yml must not package a requirements snapshot")
        XCTAssertFalse(bundleScript.contains("requirements-location"), "Bundler must not package a requirements snapshot")
        XCTAssertTrue(bundleScript.contains("location_bridge.py"), "Bundler must still package the persistent bridge script")
    }

    func testPublicDocumentationDescribesFiveModesAndManagedRuntimeTruthfully() throws {
        let root = repositoryRoot
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        for mode in ["Teleport", "Jump", "Two-Spot", "Multi-Spot", "Joystick"] {
            XCTAssertTrue(readme.contains(mode), "README must document \(mode)")
        }
        XCTAssertTrue(readme.contains("Not release-ready"))
        XCTAssertFalse(readme.contains("via.placeholder.com"))
        XCTAssertFalse(readme.contains("python3 -m pip install"))
        XCTAssertFalse(readme.contains("iOS 17+"))
    }

    func testDeploymentAndProductTextAvoidsStaleVersionAndPersonalPathClaims() throws {
        let root = repositoryRoot
        let paths = [
            "DEPLOYMENT/README.md",
            "PathChanger/Documentation.docc/PathChanger.md",
            "PathChanger/PathChangerApp.swift",
            "PathChanger/Device/TunneldManager.swift",
            "PathChanger/Device/DeviceManager.swift",
            "PathChanger/Device/DevLocationBridge.swift",
            "PathChanger/UI/ErrorDialogView.swift",
            "PathChanger/UI/OnboardingView.swift",
            "PathChanger/UI/SettingsView.swift",
            "PathChanger/UI/DiagnosticsView.swift",
        ]
        for path in paths {
            let contents = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(contents.contains("iOS 17+"), "Stale version ceiling in \(path)")
            XCTAssertFalse(contents.contains("iOS 17.0 through"), "Stale bounded compatibility range in \(path)")
            XCTAssertFalse(contents.contains("iOS 18+ Limitations"), "Stale future-version warning in \(path)")
            XCTAssertFalse(contents.contains("Use iOS 17.6"), "Stale fixed-version recommendation in \(path)")
            XCTAssertFalse(contents.contains("/Users/shigeo"), "Personal path in \(path)")
        }
    }

}
