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

    func testManagedInstallUsesOnlyBundledHashLock() {
        let arguments = PythonPathResolver.pymobiledevice3InstallArguments(
            for: managedPythonPath
        )
        XCTAssertEqual(Array(arguments.prefix(4)), ["-m", "pip", "install", "--require-hashes"])
        XCTAssertTrue(arguments.contains("-r"))
        XCTAssertTrue(arguments.last?.hasSuffix("requirements-location.lock") == true)
        XCTAssertFalse(arguments.contains("--user"))
        XCTAssertFalse(arguments.contains("--break-system-packages"))
        XCTAssertFalse(arguments.contains("--upgrade"))
        XCTAssertFalse(arguments.contains("pymobiledevice3"))
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
                version: ManagedLocationRuntimeContract.pymobiledevice3SnapshotVersion,
                available: available
            )
        ) { error in
            guard case PythonResolverError.pymobiledevice3CapabilitiesMissing(
                let version,
                let missing
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, ManagedLocationRuntimeContract.pymobiledevice3SnapshotVersion)
            XCTAssertEqual(missing, ["preferred_rsd_tunnel"])
        }
    }

    func testReleaseSnapshotVersionRemainsDiagnosticOnly() {
        XCTAssertEqual(ManagedLocationRuntimeContract.pymobiledevice3SnapshotVersion, "11.12.5")
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
