import XCTest
@testable import PathChanger

@MainActor
final class DiagnosticsViewTests: XCTestCase {

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
