//
//  PythonPathResolverTests.swift
//  PathChangerTests
//
//  Unit tests for PythonPathResolver
//

import XCTest
@testable import PathChanger

final class PythonPathResolverTests: XCTestCase {

    func testCandidateOrderIsHomebrewFirstAndAppleLast() {
        XCTAssertEqual(PythonPathResolver.candidatePaths, [
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.14",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3",
            "/usr/local/bin/python3.14",
            "/usr/local/bin/python3.13",
            "/usr/local/bin/python3.12",
            "/usr/bin/python3",
        ])
    }

    func testResolverChoosesFirstExecutableCandidate() {
        let executablePaths: Set<String> = [
            "/opt/homebrew/bin/python3.13",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        XCTAssertEqual(
            PythonPathResolver.resolvePath { executablePaths.contains($0) },
            "/opt/homebrew/bin/python3.13"
        )
    }

    func testResolverFallsBackToAppleLast() {
        XCTAssertEqual(
            PythonPathResolver.resolvePath { $0 == "/usr/bin/python3" },
            "/usr/bin/python3"
        )
    }

    func testResolverReturnsNilWhenNoCandidateIsExecutable() {
        XCTAssertNil(PythonPathResolver.resolvePath { _ in false })
    }

    func testHomebrewInstallUsesBreakSystemPackages() {
        let arguments = PythonPathResolver.pymobiledevice3InstallArguments(
            for: "/opt/homebrew/bin/python3"
        )

        XCTAssertEqual(arguments, [
            "-m", "pip", "install", "--upgrade", "--break-system-packages", "pymobiledevice3",
        ])
        XCTAssertFalse(arguments.contains("--user"))
    }

    func testIntelHomebrewInstallUsesBreakSystemPackages() {
        let arguments = PythonPathResolver.pymobiledevice3InstallArguments(
            for: "/usr/local/bin/python3.14"
        )

        XCTAssertTrue(arguments.contains("--break-system-packages"))
        XCTAssertFalse(arguments.contains("--user"))
    }

    func testAppleInstallUsesUserSite() {
        let arguments = PythonPathResolver.pymobiledevice3InstallArguments(
            for: "/usr/bin/python3"
        )

        XCTAssertEqual(arguments, [
            "-m", "pip", "install", "--upgrade", "--user", "pymobiledevice3",
        ])
        XCTAssertFalse(arguments.contains("--break-system-packages"))
    }

    func testPolicyContainsNoFrameworkOrPyenvCandidates() {
        XCTAssertFalse(PythonPathResolver.candidatePaths.contains {
            $0.contains("Python.framework") || $0.contains(".pyenv")
        })
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
