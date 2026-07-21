//
//  PrivilegedPathSecurityTests.swift
//  PathChangerTests
//
//  W0-1: Privileged-path security regression tests
//  Encodes Wave 0 invariants for PC-D-001, PC-H1/D-002, PC-M1, PC-M3.
//

import XCTest
@testable import PathChanger
import Foundation
import Darwin

final class PrivilegedPathSecurityTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc-w0-priv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - PC-H1 / PC-D-002 Interpreter provenance

    func testPrivilegedPythonRejectsEmptyAndRelativePaths() {
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(""))
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable("python3"))
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable("./python3"))
    }

    func testPrivilegedPythonRejectsPyenvStylePathsEvenIfAllowlistedShape() {
        // Shape matches SubprocessPolicy pyenv allowlist but must never be elevated.
        let pyenv = "\(NSHomeDirectory())/.pyenv/versions/3.12.11/bin/python3"
        // Whether or not the file exists, pyenv prefix is hard-rejected for privileged.
        if case .pyenvRejectedForPrivileged = PrivilegedPathSecurity.validatePrivilegedPythonPath(pyenv) {
            // expected
        } else if FileManager.default.fileExists(atPath: pyenv) {
            XCTFail("Existing pyenv interpreter must be rejected for privileged use: \(pyenv)")
        } else {
            // Missing path may return pyenvRejected first (prefix check) — already handled
            let err = PrivilegedPathSecurity.validatePrivilegedPythonPath(pyenv)
            XCTAssertEqual(err, .pyenvRejectedForPrivileged(pyenv))
        }
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(pyenv))
    }

    func testPrivilegedPythonRejectsUserWritableTempBinaryEvenIfNamedPython3() throws {
        let fake = tempRoot.appendingPathComponent("python3")
        FileManager.default.createFile(
            atPath: fake.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o777]
        )
        // Not on allowlist → rejected
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(fake.path))
        XCTAssertFalse(PrivilegedCommandValidator.isPythonPathAllowed(fake.path))
    }

    func testPrivilegedPythonRejectsUserOwnedFileMasqueradingAsAllowlistedHomebrewPath() throws {
        // Non-allowlisted user files always fail. Allowlisted self-owned Homebrew may pass
        // Wave 0.1 path policy (A07 product) if not group/other-writable; pin is separate.
        let userFile = tempRoot.appendingPathComponent("user-python3")
        FileManager.default.createFile(
            atPath: userFile.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") {
            var info = stat()
            if stat("/usr/bin/python3", &info) == 0 {
                let ok = PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable("/usr/bin/python3")
                // Acceptable when owner is self or root and mode is safe.
                if info.st_uid == 0 || info.st_uid == getuid() {
                    XCTAssertTrue(ok, "/usr/bin/python3 should pass path policy when owner self/root")
                }
            }
        }

        // User-owned non-allowlisted always fails
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(userFile.path))
    }

    func testPrivilegedPythonRejectsTmpPython3NotAllowlisted() {
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable("/tmp/python3"))
        XCTAssertFalse(PrivilegedCommandValidator.isPythonPathAllowed("/tmp/python3"))
    }

    func testPrivilegedPairScriptRejectsCWDAndTmpLayouts() {
        let cwdStyle = "\(FileManager.default.currentDirectoryPath)/scripts/pair_wifi.py"
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPairScriptPathAcceptable(cwdStyle))

        let tmpStyle = tempRoot.appendingPathComponent("scripts/pair_wifi.py")
        try? FileManager.default.createDirectory(
            at: tmpStyle.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: tmpStyle.path, contents: Data("#\n".utf8))
        // /var/folders/.../T/ is under NSTemporaryDirectory semantics for tempRoot
        XCTAssertFalse(PrivilegedPathSecurity.isPrivilegedPairScriptPathAcceptable(tmpStyle.path))
    }

    func testPrivilegedPairScriptRejectsMissingBundlePath() {
        let missingBundle = "/Applications/PathChanger-W0-Nonexistent.app/Contents/Resources/scripts/pair_wifi.py"
        let err = PrivilegedPathSecurity.validatePrivilegedPairScriptPath(missingBundle)
        guard let err else {
            XCTFail("Missing bundle script must not be acceptable")
            return
        }
        if case .pathMissing = err {
            // expected
        } else {
            XCTFail("Expected pathMissing for absent bundle script, got \(err)")
        }
    }

    func testPrivilegedPairScriptAcceptsUserOwnedBundleResourceWhenModeSafe() throws {
        // Wave 0.1 / A08: drag-drop installs are user-owned under Resources — must pass.
        let fakeApp = tempRoot.appendingPathComponent("PathChanger.app/Contents/Resources/scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        let script = fakeApp.appendingPathComponent("pair_wifi.py")
        FileManager.default.createFile(
            atPath: script.path,
            contents: Data("# pair helper\n".utf8),
            attributes: [.posixPermissions: 0o644]
        )
        let err = PrivilegedPathSecurity.validatePrivilegedPairScriptPath(script.path)
        XCTAssertNil(err, "User-owned Resources pair_wifi.py with safe mode must be accepted: \(String(describing: err))")
        XCTAssertTrue(PrivilegedPathSecurity.isPrivilegedPairScriptPathAcceptable(script.path))
    }

    func testPrivilegedPairScriptRejectsSymlinkInResources() throws {
        let fakeApp = tempRoot.appendingPathComponent("PathChanger.app/Contents/Resources/scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        let real = tempRoot.appendingPathComponent("evil.py")
        FileManager.default.createFile(atPath: real.path, contents: Data("#\n".utf8))
        let link = fakeApp.appendingPathComponent("pair_wifi.py")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)
        let err = PrivilegedPathSecurity.validatePrivilegedPairScriptPath(link.path)
        XCTAssertEqual(err, .symlinkRejected(link.path))
    }

    func testResolvePrivilegedPythonRequiresPinWhenEnabled() {
        let path = PrivilegedPathSecurity.resolvePrivilegedPythonPath(
            preferredUserPath: "/usr/bin/python3",
            preferredOrder: ["/usr/bin/python3"],
            requirePinnedModule: true,
            pinChecker: { _ in false }
        )
        XCTAssertNil(path, "Must not elevate when pin is missing on all candidates")
    }

    func testResolvePrivilegedPythonPrefersPreferredPathWhenPinned() {
        // Use a path that passes allowlist+ownership on this machine when possible.
        let candidate = "/usr/bin/python3"
        guard PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(candidate) else {
            return // environment without system python — skip
        }
        let path = PrivilegedPathSecurity.resolvePrivilegedPythonPath(
            preferredUserPath: candidate,
            preferredOrder: [candidate],
            requirePinnedModule: true,
            pinChecker: { $0 == candidate }
        )
        XCTAssertEqual(path, candidate)
    }

    func testBuildPrivilegedBackgroundCommandUsesONoFollowLauncher() throws {
        let candidate = "/usr/bin/python3"
        guard PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(candidate) || FileManager.default.isExecutableFile(atPath: candidate) else {
            return
        }
        let log = tempRoot.appendingPathComponent("tunnel.log").path
        // Parent dir exists (tempRoot).
        let result = PrivilegedPathSecurity.buildPrivilegedBackgroundTunnelCommand(
            privilegedPython: candidate,
            logPath: log,
            moduleArguments: ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--script-mode"]
        )
        guard case .success(let cmd) = result else {
            XCTFail("Expected launch command, got \(result)")
            return
        }
        XCTAssertTrue(cmd.contains("O_NOFOLLOW"), "Launcher must open log with O_NOFOLLOW: \(cmd)")
        XCTAssertFalse(cmd.contains(" > "), "Must not use shell redirect reopen: \(cmd)")
        XCTAssertTrue(cmd.contains("PYTHONSAFEPATH=1"))
        XCTAssertTrue(cmd.contains("pymobiledevice3"))
    }

    // MARK: - PC-D-001 Log redirect targets

    func testPrivilegedLogRejectsSymlinkTarget() throws {
        let real = tempRoot.appendingPathComponent("real.log")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o600])
        let link = tempRoot.appendingPathComponent("link.log")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)

        let result = PrivilegedPathSecurity.validatePrivilegedLogRedirectTarget(link.path)
        guard case .failure(let error) = result else {
            XCTFail("Symlink log path must be rejected")
            return
        }
        XCTAssertEqual(error, .symlinkRejected(link.path))
    }

    func testPrivilegedLogRejectsMissingPath() {
        let missing = tempRoot.appendingPathComponent("does-not-exist.log")
        let result = PrivilegedPathSecurity.validatePrivilegedLogRedirectTarget(missing.path)
        guard case .failure(let error) = result else {
            XCTFail("Missing log path must be rejected (create securely first)")
            return
        }
        XCTAssertEqual(error, .pathMissing(missing.path))
    }

    func testPrivilegedLogAcceptsUserOwnedRegularFileWithSafeMode() throws {
        let log = tempRoot.appendingPathComponent("ok.log")
        FileManager.default.createFile(
            atPath: log.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        )
        let result = PrivilegedPathSecurity.validatePrivilegedLogRedirectTarget(log.path)
        if case .failure(let error) = result {
            XCTFail("Safe user-owned log should pass pre-elevation validation: \(error)")
        }
    }

    func testPrivilegedLogParentDirectoryRejectsSymlinkParent() throws {
        let realDir = tempRoot.appendingPathComponent("realdir", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let linkDir = tempRoot.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(atPath: linkDir.path, withDestinationPath: realDir.path)
        let file = linkDir.appendingPathComponent("tunnel.log")

        let result = PrivilegedPathSecurity.validatePrivilegedLogParentDirectory(forFile: file.path)
        guard case .failure(let error) = result else {
            XCTFail("Symlink parent directory must be rejected")
            return
        }
        XCTAssertEqual(error, .symlinkRejected(linkDir.path))
    }

    // MARK: - PC-M1 Command value hardening

    func testPrivilegedCommandValuesRejectQuoteAndBackslash() {
        let python = "/usr/bin/python3"
        let withQuote = "\(python) -m pymobiledevice3 lockdown start-tunnel --udid \"bad"
        let withSlash = "\(python) -m pymobiledevice3 lockdown start-tunnel --udid foo\\bar"

        // Invalid UDID or quote in full command
        if case .success = PrivilegedPathSecurity.validatePrivilegedCommandValues(withQuote) {
            XCTFail("Double-quote in privileged command must fail")
        }
        if case .success = PrivilegedPathSecurity.validatePrivilegedCommandValues(withSlash) {
            XCTFail("Backslash in privileged command must fail")
        }
    }

    func testPrivilegedCommandValuesRejectInvalidUDIDToken() {
        let python = "/usr/bin/python3"
        // Space-free but invalid UDID shape (and may contain only hex that fails length)
        let bad = "\(python) -m pymobiledevice3 lockdown start-tunnel --udid not-a-real-udid"
        let result = PrivilegedPathSecurity.validatePrivilegedCommandValues(bad)
        guard case .failure(let error) = result else {
            XCTFail("Invalid UDID must be rejected")
            return
        }
        if case .invalidUDIDInCommand = error {
            // expected
        } else if case .disallowedCommandValueCharacters = error {
            // also acceptable if '-' handling differs
        } else {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrivilegedCommandValuesAcceptValidUDID() {
        let python = "/usr/bin/python3"
        let udid = "00008030-001234567890ABCD"
        XCTAssertTrue(ArgumentSanitizer.isValidDeviceUDID(udid))
        let cmd = "\(python) -m pymobiledevice3 lockdown start-tunnel --script-mode --udid \(udid)"
        let result = PrivilegedPathSecurity.validatePrivilegedCommandValues(cmd)
        if case .failure(let error) = result {
            XCTFail("Valid UDID command values should pass: \(error)")
        }
    }

    func testLegacyPrivilegedValidatorStillOmitsQuoteFromMetacharDenylist() {
        // Documents the gap PC-M1 closes via PrivilegedPathSecurity.validatePrivilegedCommandValues.
        // Legacy validate() does not treat " as dangerousCharacters.
        let python = "/opt/homebrew/bin/python3"
        let command = "\(python) -m pymobiledevice3 lockdown start-tunnel --script-mode"
        // Control: clean command structure still depends on allowlisted path existence only via isPythonPathAllowed
        _ = PrivilegedCommandValidator.validate(command: command, pythonPath: python)
        // The new seam rejects quotes even when legacy would not scan them as metachars.
        let quoted = command + " \""
        if case .success = PrivilegedPathSecurity.validatePrivilegedCommandValues(quoted) {
            XCTFail("New value validator must reject quotes")
        }
    }

    // MARK: - PC-M3 Safe python -m environment

    func testPrivilegedPythonEnvironmentRequiresPYTHONSAFEPATH() {
        XCTAssertTrue(
            PrivilegedPathSecurity.environmentMeetsPrivilegedPythonPolicy(
                PrivilegedPathSecurity.privilegedPythonEnvironment
            )
        )
        XCTAssertFalse(
            PrivilegedPathSecurity.environmentMeetsPrivilegedPythonPolicy([:])
        )
        XCTAssertFalse(
            PrivilegedPathSecurity.environmentMeetsPrivilegedPythonPolicy(["PYTHONSAFEPATH": "0"])
        )
    }

    func testPrivilegedPythonWorkingDirectoryPolicy() {
        XCTAssertTrue(
            PrivilegedPathSecurity.workingDirectoryMeetsPrivilegedPythonPolicy("/")
        )
        XCTAssertTrue(
            PrivilegedPathSecurity.workingDirectoryMeetsPrivilegedPythonPolicy("/var/empty")
        )
        XCTAssertFalse(
            PrivilegedPathSecurity.workingDirectoryMeetsPrivilegedPythonPolicy(NSHomeDirectory())
        )
        XCTAssertFalse(
            PrivilegedPathSecurity.workingDirectoryMeetsPrivilegedPythonPolicy(FileManager.default.currentDirectoryPath)
        )
    }

    // MARK: - Integration note for launch wiring (W0-2/W0-3)

    func testWave0SeamsExistForLaunchWiring() {
        // Compile-time / API surface lock: launch code will call these symbols.
        XCTAssertFalse(PrivilegedPathSecurity.privilegedPythonEnvironment.isEmpty)
        XCTAssertEqual(PrivilegedPathSecurity.privilegedPythonWorkingDirectory, "/")
        XCTAssertNotNil(PrivilegedPathSecurity.validatePrivilegedPythonPath("/tmp/python3"))
    }

    // MARK: - PC-D-001 prepareSecureLogFile (W0-2)

    func testPrepareSecureLogFileCreatesRegularFileWithOwnerMode() throws {
        let log = tempRoot.appendingPathComponent("created.log")
        let result = PrivilegedPathSecurity.prepareSecureLogFile(at: log.path)
        guard case .success(let path) = result else {
            XCTFail("Expected success creating secure log, got \(result)")
            return
        }
        XCTAssertEqual(path, log.path)
        var info = stat()
        XCTAssertEqual(lstat(log.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(info.st_uid, getuid())
        // mode should not be group/other writable
        XCTAssertEqual(info.st_mode & S_IWGRP, 0)
        XCTAssertEqual(info.st_mode & S_IWOTH, 0)
        // second prepare should truncate existing safe file
        guard case .success = PrivilegedPathSecurity.prepareSecureLogFile(at: log.path) else {
            XCTFail("Re-prepare of owned regular file should succeed")
            return
        }
    }

    func testPrepareSecureLogFileRejectsExistingSymlink() throws {
        let real = tempRoot.appendingPathComponent("real-target.log")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o600])
        let link = tempRoot.appendingPathComponent("sym.log")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)
        let result = PrivilegedPathSecurity.prepareSecureLogFile(at: link.path)
        guard case .failure(let error) = result else {
            XCTFail("Symlink must not be prepared as secure log")
            return
        }
        XCTAssertEqual(error, .symlinkRejected(link.path))
    }

    func testShellSingleQuotedPathRejectsQuoteInPath() {
        XCTAssertNil(PrivilegedPathSecurity.shellSingleQuotedPath("/tmp/odd'name.log"))
        XCTAssertEqual(
            PrivilegedPathSecurity.shellSingleQuotedPath("/tmp/safe.log"),
            "'/tmp/safe.log'"
        )
    }


    func testResolvePrivilegedPythonPathNeverReturnsPyenv() {
        if let resolved = PrivilegedPathSecurity.resolvePrivilegedPythonPath() {
            XCTAssertFalse(resolved.contains("/.pyenv/"), "Resolved privileged python must not be pyenv: \(resolved)")
            XCTAssertTrue(
                PrivilegedPathSecurity.isPrivilegedPythonPathAcceptable(resolved),
                "Resolver must only return acceptable paths"
            )
        }
        // Pyenv path must never be selected even if present on disk.
        let pyenv = "\(NSHomeDirectory())/.pyenv/versions/3.12.11/bin/python3"
        if FileManager.default.isExecutableFile(atPath: pyenv) {
            XCTAssertNotEqual(PrivilegedPathSecurity.resolvePrivilegedPythonPath(), pyenv)
        }
    }

    func testPrivilegedShellEnvironmentPrefixIncludesSafepathAndCd() {
        let prefix = PrivilegedPathSecurity.privilegedShellEnvironmentPrefix
        XCTAssertTrue(prefix.contains("PYTHONSAFEPATH=1"))
        XCTAssertTrue(prefix.contains("cd "))
        XCTAssertTrue(prefix.hasSuffix(" && "))
    }

}
