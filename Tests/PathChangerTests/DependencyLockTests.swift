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

    func testLocationInputPinsExactSupportedVersion() throws {
        let url = repositoryRoot.appendingPathComponent("requirements-location.in")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing requirements-location.in")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(content, "pymobiledevice3==11.12.5")
    }

    func testLocationLockPinsAndHashesEveryDistribution() throws {
        let url = repositoryRoot.appendingPathComponent("requirements-location.lock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing requirements-location.lock")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let content = try String(contentsOf: url, encoding: .utf8)
        var records: [String] = []
        var current = ""

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("--"), !line.hasPrefix("--hash=") { continue }
            current += line.hasSuffix("\\") ? String(line.dropLast()) : line
            if !line.hasSuffix("\\") {
                records.append(current)
                current = ""
            }
        }

        XCTAssertTrue(records.contains { $0.hasPrefix("pymobiledevice3==11.12.5") })
        XCTAssertGreaterThan(records.count, 1, "Expected a complete transitive lock")
        for record in records {
            XCTAssertTrue(record.contains("=="), "Unpinned requirement: \(record)")
            XCTAssertTrue(record.contains("--hash=sha256:"), "Unhashed requirement: \(record)")
        }
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
            "requirements-location.lock",
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
            ("requirements-location.lock", "requirements-location.lock"),
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

    func testLocationLockIsPackagedByEveryAppBuildPath() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let bundleScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("build-app-bundle.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("requirements-location.lock"))
        XCTAssertTrue(bundleScript.contains("requirements-location.lock"))
    }
}
