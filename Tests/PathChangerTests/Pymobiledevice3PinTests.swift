//
//  Pymobiledevice3PinTests.swift
//  PathChangerTests
//
//  W0-4 / PC-G-001: exact pin gate for pymobiledevice3
//

import XCTest
@testable import PathChanger

final class Pymobiledevice3PinTests: XCTestCase {

    func testPinnedVersionConstantIsNonEmptySemverLike() {
        let pin = PythonPathResolver.pinnedPymobiledevice3Version
        XCTAssertFalse(pin.isEmpty)
        XCTAssertTrue(pin.contains("."), "Pin should look like major.minor.patch, got \(pin)")
    }

    func testApprovedVersionAcceptsExactPinOnly() {
        let pin = PythonPathResolver.pinnedPymobiledevice3Version
        XCTAssertTrue(PythonPathResolver.isApprovedPymobiledevice3Version(pin))
        XCTAssertFalse(PythonPathResolver.isApprovedPymobiledevice3Version("unknown"))
        XCTAssertFalse(PythonPathResolver.isApprovedPymobiledevice3Version(""))
        XCTAssertFalse(PythonPathResolver.isApprovedPymobiledevice3Version("6.1.5"))
        XCTAssertFalse(PythonPathResolver.isApprovedPymobiledevice3Version("9.36.0"))
        XCTAssertFalse(PythonPathResolver.isApprovedPymobiledevice3Version(pin + ".1"))
    }

    func testPinnedInstallCommandDoesNotUseUnconstrainedUpgrade() {
        let cmd = PythonPathResolver.pinnedInstallCommand
        XCTAssertTrue(cmd.contains("requirements-pathchanger.txt"))
        XCTAssertFalse(cmd.contains(" -U"))
        XCTAssertFalse(cmd.contains("--upgrade"))
    }

    func testVersionMismatchErrorMessageIncludesExpectedPin() {
        let err = PythonResolverError.pymobiledevice3VersionMismatch(
            found: "9.36.0",
            expected: PythonPathResolver.pinnedPymobiledevice3Version
        )
        let text = err.errorDescription ?? ""
        XCTAssertTrue(text.contains("9.36.0"))
        XCTAssertTrue(text.contains(PythonPathResolver.pinnedPymobiledevice3Version))
        let recovery = err.recoverySuggestion ?? ""
        XCTAssertTrue(recovery.contains("requirements-pathchanger.txt"))
        XCTAssertFalse(recovery.contains("pip install -U"))
    }
}
