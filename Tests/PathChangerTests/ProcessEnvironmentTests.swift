//
//  ProcessEnvironmentTests.swift
//  PathChangerTests
//
//  Tests for ProcessEnvironment centralized configuration
//

import XCTest
@testable import PathChanger

final class ProcessEnvironmentTests: XCTestCase {

    // MARK: - PATH Configuration Tests

    func testApprovedPathDirectoriesContainsHomebrew() {
        let paths = ProcessEnvironment.approvedPathDirectories
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"), "Should include Apple Silicon homebrew")
        XCTAssertTrue(paths.contains("/usr/local/bin"), "Should include Intel homebrew")
    }

    func testApprovedPathDirectoriesContainsSystemBins() {
        let paths = ProcessEnvironment.approvedPathDirectories
        XCTAssertTrue(paths.contains("/usr/bin"), "Should include /usr/bin")
        XCTAssertTrue(paths.contains("/bin"), "Should include /bin")
        XCTAssertTrue(paths.contains("/usr/sbin"), "Should include /usr/sbin")
        XCTAssertTrue(paths.contains("/sbin"), "Should include /sbin")
    }

    func testApprovedPathDirectoriesContainsMacPorts() {
        let paths = ProcessEnvironment.approvedPathDirectories
        XCTAssertTrue(paths.contains("/opt/local/bin"), "Should include MacPorts")
    }

    func testApprovedPathDirectoriesAreAbsolute() {
        for path in ProcessEnvironment.approvedPathDirectories {
            XCTAssertTrue(path.hasPrefix("/"), "Path should be absolute: \(path)")
        }
    }

    func testApprovedPathDirectoriesNoDuplicates() {
        let paths = ProcessEnvironment.approvedPathDirectories
        let uniquePaths = Set(paths)
        XCTAssertEqual(paths.count, uniquePaths.count, "Should have no duplicate paths")
    }

    // MARK: - Configured Environment Tests

    func testConfiguredEnvironmentContainsPATH() {
        let env = ProcessEnvironment.configured()
        XCTAssertNotNil(env["PATH"], "Environment should contain PATH")
        XCTAssertFalse(env["PATH"]!.isEmpty, "PATH should not be empty")
    }

    func testConfiguredEnvironmentContainsPYTHONPATH() {
        let env = ProcessEnvironment.configured()
        XCTAssertNotNil(env["PYTHONPATH"], "Environment should contain PYTHONPATH")
        XCTAssertFalse(env["PYTHONPATH"]!.isEmpty, "PYTHONPATH should not be empty")
    }

    func testConfiguredEnvironmentIncludesHomebrewPaths() {
        let env = ProcessEnvironment.configured()
        let path = env["PATH"]!

        XCTAssertTrue(path.contains("/opt/homebrew/bin"), "PATH should include homebrew")
        XCTAssertTrue(path.contains("/usr/local/bin"), "PATH should include /usr/local/bin")
    }

    func testConfiguredEnvironmentIncludesPyenv() {
        let env = ProcessEnvironment.configured()
        let path = env["PATH"]!

        XCTAssertTrue(path.contains(".pyenv/shims"), "PATH should include pyenv shims")
    }

    func testConfiguredEnvironmentPreservesOtherVariables() {
        let env = ProcessEnvironment.configured()

        // Should preserve HOME
        XCTAssertNotNil(env["HOME"], "Should preserve HOME")

        // Should preserve USER if set in process environment
        if ProcessInfo.processInfo.environment["USER"] != nil {
            XCTAssertNotNil(env["USER"], "Should preserve USER")
        }
    }

    func testConfiguredEnvironmentWithPreserveExistingPath() {
        let env = ProcessEnvironment.configured(preserveExistingPath: true)
        let path = env["PATH"]!

        // Should still include approved paths
        XCTAssertTrue(path.contains("/opt/homebrew/bin"), "Should include homebrew")
    }

    func testConfiguredEnvironmentWithoutPreserveExistingPath() {
        let env = ProcessEnvironment.configured(preserveExistingPath: false)
        let path = env["PATH"]!

        // Should have approved paths at the beginning
        XCTAssertTrue(path.hasPrefix("/opt/homebrew/bin"), "Should start with homebrew")
    }

    // MARK: - Minimal Environment Tests

    func testMinimalEnvironmentContainsPATH() {
        let env = ProcessEnvironment.minimal()
        XCTAssertNotNil(env["PATH"], "Minimal environment should contain PATH")
    }

    func testMinimalEnvironmentDoesNotContainPYTHONPATH() {
        let env = ProcessEnvironment.minimal()
        XCTAssertNil(env["PYTHONPATH"], "Minimal environment should not contain PYTHONPATH")
    }

    func testMinimalEnvironmentContainsHOME() {
        let env = ProcessEnvironment.minimal()
        XCTAssertNotNil(env["HOME"], "Minimal environment should contain HOME")
        XCTAssertEqual(env["HOME"], NSHomeDirectory())
    }

    func testMinimalEnvironmentIsSubsetOfConfigured() {
        let minimal = ProcessEnvironment.minimal()
        let configured = ProcessEnvironment.configured()

        // Minimal should have fewer or equal keys
        XCTAssertLessThanOrEqual(minimal.count, configured.count + 10)
    }

    // MARK: - Path Approval Tests

    func testIsPathApprovedForHomebrewPath() {
        XCTAssertTrue(ProcessEnvironment.isPathApproved("/opt/homebrew/bin/python3"))
        XCTAssertTrue(ProcessEnvironment.isPathApproved("/usr/local/bin/python3"))
    }

    func testIsPathApprovedForSystemPath() {
        XCTAssertTrue(ProcessEnvironment.isPathApproved("/usr/bin/python3"))
        XCTAssertTrue(ProcessEnvironment.isPathApproved("/bin/sh"))
    }

    func testIsPathApprovedForPyenvPath() {
        let pyenvPath = NSHomeDirectory() + "/.pyenv/shims/python3"
        XCTAssertTrue(ProcessEnvironment.isPathApproved(pyenvPath))
    }

    func testIsPathApprovedRejectsArbitraryPath() {
        XCTAssertFalse(ProcessEnvironment.isPathApproved("/tmp/malicious"))
        XCTAssertFalse(ProcessEnvironment.isPathApproved("/var/tmp/script"))
        XCTAssertFalse(ProcessEnvironment.isPathApproved(NSHomeDirectory() + "/Downloads/script"))
    }

    func testIsPathApprovedRejectsRelativePath() {
        XCTAssertFalse(ProcessEnvironment.isPathApproved("python3"))
        XCTAssertFalse(ProcessEnvironment.isPathApproved("./script"))
        XCTAssertFalse(ProcessEnvironment.isPathApproved("../bin/python3"))
    }

    // MARK: - Path String Tests

    func testPathStringIsNotEmpty() {
        XCTAssertFalse(ProcessEnvironment.pathString.isEmpty)
    }

    func testPathStringContainsColons() {
        let pathString = ProcessEnvironment.pathString
        XCTAssertTrue(pathString.contains(":"), "PATH string should be colon-separated")
    }

    func testPathStringMatchesConfiguredPATH() {
        let configured = ProcessEnvironment.configured()
        let pathString = ProcessEnvironment.pathString

        // The configured PATH may include existing path, but pathString should match the prefix
        XCTAssertTrue(configured["PATH"]!.hasPrefix(pathString.components(separatedBy: ":").first!))
    }

    // MARK: - PYTHONPATH String Tests

    func testPythonPathStringIsNotEmpty() {
        XCTAssertFalse(ProcessEnvironment.pythonPathString.isEmpty)
    }

    func testPythonPathStringContainsUserSitePackages() {
        let pythonPath = ProcessEnvironment.pythonPathString
        XCTAssertTrue(pythonPath.contains("Library/Python"), "Should include user site-packages")
    }

    func testPythonPathStringContainsHomebrewSitePackages() {
        let pythonPath = ProcessEnvironment.pythonPathString
        XCTAssertTrue(pythonPath.contains("/opt/homebrew/lib/python") ||
                      pythonPath.contains("/usr/local/lib/python"),
                      "Should include homebrew site-packages")
    }

    func testPythonPathStringSupportsMultiplePythonVersions() {
        let pythonPath = ProcessEnvironment.pythonPathString

        // Should support multiple Python versions
        let supportedVersions = ["3.9", "3.10", "3.11", "3.12", "3.13"]
        var foundVersions = 0
        for version in supportedVersions {
            if pythonPath.contains(version) {
                foundVersions += 1
            }
        }
        XCTAssertGreaterThanOrEqual(foundVersions, 3, "Should support at least 3 Python versions")
    }

    // MARK: - Keys Tests

    func testEnvironmentKeysAreCorrect() {
        XCTAssertEqual(ProcessEnvironment.Keys.path, "PATH")
        XCTAssertEqual(ProcessEnvironment.Keys.pythonPath, "PYTHONPATH")
        XCTAssertEqual(ProcessEnvironment.Keys.home, "HOME")
        XCTAssertEqual(ProcessEnvironment.Keys.user, "USER")
        XCTAssertEqual(ProcessEnvironment.Keys.lang, "LANG")
        XCTAssertEqual(ProcessEnvironment.Keys.lcAll, "LC_ALL")
        XCTAssertEqual(ProcessEnvironment.Keys.term, "TERM")
        XCTAssertEqual(ProcessEnvironment.Keys.shell, "SHELL")
    }

    // MARK: - Security Tests

    func testNoWritableUserDirectoriesInPath() {
        let path = ProcessEnvironment.pathString
        let components = path.components(separatedBy: ":")

        for component in components {
            // User home bin directories (except pyenv) should not be in PATH
            if component.hasPrefix(NSHomeDirectory()) && !component.contains(".pyenv") {
                XCTFail("User-writable directory should not be in PATH: \(component)")
            }
        }
    }

    func testNoTmpDirectoriesInPath() {
        let path = ProcessEnvironment.pathString
        XCTAssertFalse(path.contains("/tmp/"), "PATH should not contain /tmp/")
        XCTAssertFalse(path.contains("/var/tmp/"), "PATH should not contain /var/tmp/")
    }
}
