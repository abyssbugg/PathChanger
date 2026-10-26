//
//  PrivilegedTunnelCommandTests.swift
//  PathChangerTests
//

import XCTest
@testable import PathChanger

final class PrivilegedTunnelCommandTests: XCTestCase {

    func testAllowedArgumentListsMatchFixedTunnelModes() {
        XCTAssertEqual(PrivilegedTunnelCommand.allowedArgumentLists, [
            ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native"],
            ["-m", "pymobiledevice3", "remote", "start-tunnel", "--native"],
            ["-m", "pymobiledevice3", "remote", "tunneld"],
        ])
    }

    func testStartCommandAcceptsValidatedDeviceTarget() {
        let udid = "00000000-0000000000000001"
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: PythonPathResolver.managedPythonPath,
            arguments: [
                "-m", "pymobiledevice3", "remote", "start-tunnel", "--native",
                "--udid", udid,
            ],
            logFilePath: "/Users/test/Library/Logs/PathChanger/tunnel.log"
        )

        guard case .success(let command) = result else {
            return XCTFail("expected a validated per-device tunnel command")
        }
        XCTAssertTrue(command.contains("'--udid' '\(udid)'"))
    }

    func testStartCommandRejectsMalformedDeviceTarget() {
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: PythonPathResolver.managedPythonPath,
            arguments: [
                "-m", "pymobiledevice3", "remote", "start-tunnel", "--native",
                "--udid", "not-a-udid",
            ],
            logFilePath: "/Users/test/Library/Logs/PathChanger/tunnel.log"
        )

        guard case .failure(.unapprovedArguments) = result else {
            return XCTFail("expected malformed target rejection")
        }
    }

    func testStartCommandQuotesManagedPythonAndLog() {
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: PythonPathResolver.managedPythonPath,
            arguments: ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native"],
            logFilePath: "/Users/datamatics/Library/Logs/PathChanger/tunnel.log"
        )

        guard case .success(let command) = result else {
            return XCTFail("expected approved start command")
        }

        XCTAssertEqual(
            command,
            "HOME='\(NSHomeDirectory())' '\(PythonPathResolver.managedPythonPath)' '-m' 'pymobiledevice3' 'lockdown' 'start-tunnel' '--native' > '/Users/datamatics/Library/Logs/PathChanger/tunnel.log' 2>&1 & echo $!"
        )
        XCTAssertFalse(command.contains("pip"))
        XCTAssertFalse(command.contains("sudo"))
    }

    func testEveryElevatedTunnelCommandPreservesPairingRecordHome() {
        for arguments in PrivilegedTunnelCommand.allowedArgumentLists {
            let result = PrivilegedTunnelCommand.startShellCommand(
                pythonPath: PythonPathResolver.managedPythonPath,
                arguments: arguments,
                logFilePath: "/Users/test/Library/Logs/PathChanger/tunnel.log"
            )

            guard case .success(let command) = result else {
                return XCTFail("expected an approved command for \(arguments)")
            }

            XCTAssertTrue(
                command.hasPrefix("HOME='\(NSHomeDirectory())' "),
                "Elevated pymobiledevice3 must read the logged-in user's iOS pairing records"
            )
        }
    }

    func testStartCommandRejectsUnknownPython() {
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: "/Users/datamatics/.pyenv/shims/python3",
            arguments: ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native"],
            logFilePath: "/tmp/tunnel.log"
        )

        guard case .failure(.unapprovedPythonPath(let path)) = result else {
            return XCTFail("expected pyenv path to be rejected")
        }
        XCTAssertEqual(path, "/Users/datamatics/.pyenv/shims/python3")
    }

    func testStartCommandRejectsInstallArguments() {
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: PythonPathResolver.managedPythonPath,
            arguments: ["-m", "pip", "install", "--upgrade", "pymobiledevice3"],
            logFilePath: "/tmp/tunnel.log"
        )

        guard case .failure(.unapprovedArguments) = result else {
            return XCTFail("expected pip install to be rejected")
        }
    }

    func testStartCommandRejectsShellMetacharactersInPath() {
        let result = PrivilegedTunnelCommand.startShellCommand(
            pythonPath: PythonPathResolver.managedPythonPath,
            arguments: ["-m", "pymobiledevice3", "lockdown", "start-tunnel", "--native"],
            logFilePath: "/tmp/tunnel'.log"
        )

        guard case .failure(.unsafePath) = result else {
            return XCTFail("expected quoted-path rejection")
        }
    }

    func testStopCommandOnlyAcceptsTrackedPids() {
        let success = PrivilegedTunnelCommand.stopShellCommand(pids: [4242, 4243])
        guard case .success(let command) = success else {
            return XCTFail("expected stop command")
        }
        XCTAssertEqual(command, "/bin/kill -15 4242 4243; /bin/sleep 0.2; /bin/kill -9 4242 4243")

        let rejected = PrivilegedTunnelCommand.stopShellCommand(pids: [1, 4242])
        guard case .failure(.unapprovedProcessIds) = rejected else {
            return XCTFail("expected pid 1 to be rejected")
        }
    }

    func testParseLaunchedPid() {
        XCTAssertEqual(PrivilegedTunnelCommand.parseLaunchedPid(from: "70248\n"), 70248)
        XCTAssertNil(PrivilegedTunnelCommand.parseLaunchedPid(from: "0"))
        XCTAssertNil(PrivilegedTunnelCommand.parseLaunchedPid(from: "not-a-pid"))
    }
}
