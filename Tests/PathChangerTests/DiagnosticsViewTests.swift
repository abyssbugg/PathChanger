import XCTest
@testable import PathChanger

@MainActor
final class DiagnosticsViewTests: XCTestCase {

    func testLocationCapabilityProbeUsesNonMutatingDVTListForDirectUDID() throws {
        let device = Device(
            id: "00008030001234567890123456789012345678ab",
            displayName: "Test iPhone",
            connectionType: .usb,
            productVersion: "17.6"
        )

        let args = DiagnosticsView.locationCapabilityProbeArguments(
            for: device,
            tunnelInfo: nil,
            isTunnelRunning: false
        )

        XCTAssertEqual(args, [
            "-m", "pymobiledevice3",
            "developer", "dvt", "ls",
            "--udid", device.id,
            "/"
        ])
        XCTAssertFalse(args.contains("simulate-location"))
        XCTAssertFalse(args.contains("set"))
        XCTAssertFalse(args.contains("0.0"))
        XCTAssertNoThrow(try CommandStructureValidator.validateCommandStructure(args))
    }

    func testLocationCapabilityProbeUsesNonMutatingDVTListForRSDTunnel() throws {
        let device = Device(
            id: "00008030001234567890123456789012345678ab",
            displayName: "Test iPhone",
            connectionType: .wifi,
            productVersion: "17.6"
        )
        let tunnelInfo = TunnelInfo(
            rsdAddress: "fe80::1",
            rsdPort: 62078,
            mode: .wifi,
            interface: nil,
            processId: nil
        )

        let args = DiagnosticsView.locationCapabilityProbeArguments(
            for: device,
            tunnelInfo: tunnelInfo,
            isTunnelRunning: true
        )

        XCTAssertEqual(args, [
            "-m", "pymobiledevice3",
            "developer", "dvt", "ls",
            "--rsd", "fe80::1", "62078",
            "/"
        ])
        XCTAssertFalse(args.contains("simulate-location"))
        XCTAssertFalse(args.contains("set"))
        XCTAssertFalse(args.contains("0.0"))
        XCTAssertNoThrow(try CommandStructureValidator.validateCommandStructure(args))
    }

    func testLocationCapabilityProbeUsesNonMutatingDVTListForTunnelDeviceSelector() throws {
        let device = Device(
            id: "00008030001234567890123456789012345678ab",
            displayName: "Test iPhone",
            connectionType: .wifi,
            productVersion: "17.6"
        )

        let args = DiagnosticsView.locationCapabilityProbeArguments(
            for: device,
            tunnelInfo: nil,
            isTunnelRunning: true
        )

        XCTAssertEqual(args, [
            "-m", "pymobiledevice3",
            "developer", "dvt", "ls",
            "--tunnel", device.id,
            "/"
        ])
        XCTAssertFalse(args.contains("simulate-location"))
        XCTAssertFalse(args.contains("set"))
        XCTAssertFalse(args.contains("0.0"))
        XCTAssertNoThrow(try CommandStructureValidator.validateCommandStructure(args))
    }

    func testDiagnosticCommandErrorDescriptionsAreMeaningful() {
        let errors: [DiagnosticCommandError] = [
            .invalidExecutable("/tmp/python"),
            .invalidArguments("-m bad"),
            .launchFailed("permission denied"),
            .timedOut(seconds: 12),
            .outputSizeExceeded(maxBytes: 1024),
            .exited(code: 2, output: "boom")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testDiagnosticCommandValidationRejectsUnapprovedExecutable() {
        XCTAssertThrowsError(
            try DiagnosticsView.validateDiagnosticCommand(
                path: "/tmp/python3",
                args: ["--version"]
            )
        ) { error in
            XCTAssertTrue(error is DiagnosticCommandError)
        }
    }

    func testDiagnosticCommandValidationRejectsUnexpectedArguments() throws {
        let pythonPath = try XCTUnwrap(SubprocessPolicy.allowedPythonPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        })

        XCTAssertThrowsError(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pythonPath,
                args: ["-c", "print('unsafe')"]
            )
        ) { error in
            XCTAssertTrue(error is DiagnosticCommandError)
        }
    }

    func testDiagnosticCommandValidationAllowsPythonVersionProbe() throws {
        let pythonPath = try XCTUnwrap(SubprocessPolicy.allowedPythonPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        })

        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pythonPath,
                args: ["--version"]
            )
        )
    }

    func testDiagnosticCommandValidationAllowsPyenvVersionPython() throws {
        let pyenvPython = "\(NSHomeDirectory())/.pyenv/versions/3.12.11/bin/python3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: pyenvPython), "pyenv 3.12.11 is not installed on this host")

        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pyenvPython,
                args: ["--version"]
            )
        )
    }

    func testDiagnosticCommandValidationAllowsPyenvPymobiledevice3Checks() throws {
        let pyenvPython = "\(NSHomeDirectory())/.pyenv/versions/3.12.11/bin/python3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: pyenvPython), "pyenv 3.12.11 is not installed on this host")

        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pyenvPython,
                args: ["-m", "pymobiledevice3", "version"]
            )
        )
        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pyenvPython,
                args: ["-m", "pymobiledevice3", "--no-color", "usbmux", "list"]
            )
        )
    }

    func testRunCommandReturnsPyenvPythonVersionOutput() async throws {
        let pyenvPython = "\(NSHomeDirectory())/.pyenv/versions/3.12.11/bin/python3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: pyenvPython), "pyenv 3.12.11 is not installed on this host")
        let view = DiagnosticsView()

        let output = try await view.runCommand(pyenvPython, args: ["--version"])
        XCTAssertTrue(output.contains("Python 3.12.11"), output)
    }

    func testDiagnosticCommandValidationAllowsExistingPymobiledevice3Checks() throws {
        let pythonPath = try XCTUnwrap(SubprocessPolicy.allowedPythonPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        })

        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pythonPath,
                args: ["-m", "pymobiledevice3", "version"]
            )
        )
        XCTAssertNoThrow(
            try DiagnosticsView.validateDiagnosticCommand(
                path: pythonPath,
                args: ["-m", "pymobiledevice3", "--no-color", "usbmux", "list"]
            )
        )
    }

    func testRunCommandReturnsPythonVersionOutput() async throws {
        let pythonPath = try XCTUnwrap(SubprocessPolicy.allowedPythonPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        })
        let view = DiagnosticsView()

        let output = try await view.runCommand(pythonPath, args: ["--version"])
        XCTAssertTrue(output.lowercased().contains("python"), output)
    }

    func testRunCommandReturnsPythonVersionOutputRepeatedly() async throws {
        let pythonPath = try XCTUnwrap(SubprocessPolicy.allowedPythonPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        })
        let view = DiagnosticsView()

        for _ in 0..<25 {
            let output = try await view.runCommand(pythonPath, args: ["--version"])
            XCTAssertTrue(output.lowercased().contains("python"), output)
        }
    }
}
