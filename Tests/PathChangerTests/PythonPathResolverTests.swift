//
//  PythonPathResolverTests.swift
//  PathChangerTests
//
//  Unit tests for PythonPathResolver
//

import XCTest
@testable import PathChanger

final class PythonPathResolverTests: XCTestCase {

    private var managedPythonPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PathChanger/runtime/location/bin/python3")
            .path
    }

    func testCandidatePolicyUsesOnlyManagedRuntime() {
        XCTAssertEqual(PythonPathResolver.candidatePaths, [managedPythonPath])
    }

    func testResolverChoosesManagedRuntime() {
        XCTAssertEqual(
            PythonPathResolver.resolvePath { $0 == self.managedPythonPath },
            managedPythonPath
        )
    }

    func testResolverRejectsHomebrewAndAppleInterpreters() {
        let externalPaths: Set<String> = [
            "/opt/homebrew/opt/python@3.13/bin/python3.13",
            "/usr/bin/python3",
        ]
        XCTAssertNil(PythonPathResolver.resolvePath { externalPaths.contains($0) })
    }

    func testResolverReturnsNilWhenManagedRuntimeIsNotExecutable() {
        XCTAssertNil(PythonPathResolver.resolvePath { _ in false })
    }

    func testManagedInstallUpgradesToRollingLatestPymobiledevice3() {
        let arguments = PythonPathResolver.pymobiledevice3InstallArguments(
            for: managedPythonPath
        )
        XCTAssertEqual(arguments, ["-m", "pip", "install", "-U", "pymobiledevice3"])
        XCTAssertFalse(arguments.contains("--require-hashes"))
        XCTAssertFalse(arguments.contains("-r"))
        XCTAssertFalse(arguments.contains("--user"))
        XCTAssertFalse(arguments.contains("--break-system-packages"))
    }

    func testBootstrapCandidatesPreferNewestPyenvInterpreter() throws {
        let pyenvRoot = try Self.createTemporaryPyenvRoot(versions: ["3.12.11", "3.13.14", "3.14.1"])
        let candidates = PythonPathResolver.bootstrapPythonCandidates(
            pyenvRoot: pyenvRoot,
            homebrewRoots: ["/opt/homebrew/opt"]
        )
        XCTAssertEqual(candidates.first, pyenvRoot + "/versions/3.14.1/bin/python3")
        XCTAssertTrue(candidates.contains("/opt/homebrew/opt/python@3.13/bin/python3.13"))

        let belowFloor = try Self.createTemporaryPyenvRoot(versions: ["3.12.11"])
        let fallback = PythonPathResolver.bootstrapPythonCandidates(
            pyenvRoot: belowFloor,
            homebrewRoots: ["/opt/homebrew/opt"]
        )
        XCTAssertTrue(
            fallback.first?.hasPrefix("/opt/homebrew/opt") == true,
            "Below-floor pyenv versions must fall back to Homebrew"
        )
    }

    private static func createTemporaryPyenvRoot(versions: [String]) throws -> String {
        let root = NSTemporaryDirectory() + "pyenv-test-\(UUID().uuidString)"
        for version in versions {
            try FileManager.default.createDirectory(
                atPath: root + "/versions/\(version)/bin",
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(
                atPath: root + "/versions/\(version)/bin/python3",
                contents: nil
            )
        }
        return root
    }

    func testInstallPlannerRejectsExternalInterpreters() {
        XCTAssertEqual(
            PythonPathResolver.pymobiledevice3InstallArguments(
                for: "/opt/homebrew/opt/python@3.13/bin/python3.13"
            ),
            []
        )
        XCTAssertEqual(
            PythonPathResolver.pymobiledevice3InstallArguments(for: "/usr/bin/python3"),
            []
        )
    }

    func testFuturePythonVersionsMeetCapabilityFloor() {
        XCTAssertTrue(PythonPathResolver.isSupportedPythonVersion(major: 3, minor: 14))
        XCTAssertTrue(PythonPathResolver.isSupportedPythonVersion(major: 4, minor: 0))
        XCTAssertFalse(PythonPathResolver.isSupportedPythonVersion(major: 3, minor: 12))
    }

    func testFuturePymobiledeviceVersionIsAcceptedWhenCapabilitiesArePresent() throws {
        XCTAssertNoThrow(
            try PythonPathResolver.validatePymobiledevice3Capabilities(
                version: "99.0.0",
                available: PythonPathResolver.requiredPymobiledevice3Capabilities
            )
        )
    }

    func testAnyPymobiledeviceVersionIsRejectedWhenCapabilityIsMissing() {
        var available = PythonPathResolver.requiredPymobiledevice3Capabilities
        available.remove("preferred_rsd_tunnel")

        XCTAssertThrowsError(
            try PythonPathResolver.validatePymobiledevice3Capabilities(
                version: ManagedLocationRuntimeContract.pymobiledevice3MinimumVersion,
                available: available
            )
        ) { error in
            guard case PythonResolverError.pymobiledevice3CapabilitiesMissing(
                let version,
                let missing
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, ManagedLocationRuntimeContract.pymobiledevice3MinimumVersion)
            XCTAssertEqual(missing, ["preferred_rsd_tunnel"])
        }
    }

    func testPymobiledevice3FloorRemainsDiagnosticOnly() {
        XCTAssertEqual(ManagedLocationRuntimeContract.pymobiledevice3MinimumVersion, "11.12.5")
    }

    func testCapabilityProbeUsesTheSameProviderModulesAsLocationBridge() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolverSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PathChanger/Core/PythonPathResolver.swift"),
            encoding: .utf8
        )
        let bridgeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/location_bridge.py"),
            encoding: .utf8
        )
        let requiredModules = [
            "pymobiledevice3.services.dvt.instruments.dvt_provider",
            "pymobiledevice3.remote.rsd_tunnel",
        ]

        for module in requiredModules {
            XCTAssertTrue(resolverSource.contains(module), "Resolver probe must import \(module)")
            XCTAssertTrue(bridgeSource.contains(module), "Bridge must import \(module)")
        }
        XCTAssertFalse(resolverSource.contains("pymobiledevice3.services.dvt.dvt_secure_socket_proxy"))
        XCTAssertFalse(resolverSource.contains("pymobiledevice3.tunneld.server\", \"PreferredRsdTunnel"))
    }

    func testPathIsNotEmpty() {
        let path = PythonPathResolver.path
        XCTAssertFalse(path.isEmpty, "Python path should not be empty")
    }

    func testPathIsAbsolute() {
        let path = PythonPathResolver.path
        XCTAssertTrue(path.hasPrefix("/"), "Python path should be absolute")
    }

    func testIsAvailable() {
        // On most macOS systems, Python 3 should be available
        // This test may fail on systems without Python 3 installed
        XCTAssertTrue(PythonPathResolver.isAvailable, "Python 3 should be available on this system")
    }

    func testRefreshReturnsPath() {
        let path = PythonPathResolver.refresh()
        XCTAssertFalse(path.isEmpty, "Refresh should return a valid path")
    }

    func testConsistentPath() {
        let path1 = PythonPathResolver.path
        let path2 = PythonPathResolver.path
        XCTAssertEqual(path1, path2, "Path should be consistent between calls")
    }

    func testVersionAsync() async {
        let version = await PythonPathResolver.version()

        if PythonPathResolver.isAvailable {
            XCTAssertNotNil(version, "Version should be available if Python is installed")
            XCTAssertTrue(version?.contains("Python") ?? false, "Version should contain 'Python'")
        }
    }
}
