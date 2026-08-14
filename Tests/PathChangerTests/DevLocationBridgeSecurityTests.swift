//
//  DevLocationBridgeSecurityTests.swift
//  PathChangerTests
//
//  Security tests for subprocess execution in DevLocationBridge
//

import XCTest
@testable import PathChanger

final class DevLocationBridgeSecurityTests: XCTestCase {

    // MARK: - Output Size Limit Tests

    func testMaxOutputSizeLimitIsConfigured() {
        // Verify output size limit is set to a reasonable value
        let limit = DevLocationBridge.maxOutputSizeLimit

        // Should be at least 1KB (practical minimum for any useful output)
        XCTAssertGreaterThanOrEqual(limit, 1024, "Output size limit should be at least 1KB")

        // Should be at most 10MB (prevent memory exhaustion)
        XCTAssertLessThanOrEqual(limit, 10_485_760, "Output size limit should be at most 10MB")

        // Default is 1MB - verify it's set correctly
        XCTAssertEqual(limit, 1_048_576, "Default output size limit should be 1MB")
    }

    // MARK: - Error Type Tests

    func testSubprocessSecurityErrorDescriptions() {
        // Test that all error cases have meaningful descriptions

        let outputExceededError = SubprocessSecurityError.outputSizeExceeded(actualSize: 2_000_000, maxSize: 1_000_000)
        XCTAssertNotNil(outputExceededError.errorDescription)
        XCTAssertTrue(outputExceededError.errorDescription!.contains("exceeded"))
        XCTAssertTrue(outputExceededError.errorDescription!.contains("2000000"))
        XCTAssertTrue(outputExceededError.errorDescription!.contains("1000000"))

        let executionFailedError = SubprocessSecurityError.subprocessExecutionFailed(reason: "Test failure reason")
        XCTAssertNotNil(executionFailedError.errorDescription)
        XCTAssertTrue(executionFailedError.errorDescription!.contains("Test failure reason"))
    }

    func testLocationInjectionOutputSizeExceededError() {
        // Test the new outputSizeExceeded case in LocationInjectionError
        let error = LocationInjectionError.outputSizeExceeded

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("exceeded"))

        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion!.contains("pymobiledevice3"))
    }

    // MARK: - Location Injection Error Coverage Tests

    func testAllLocationInjectionErrorsHaveDescriptions() {
        let errors: [LocationInjectionError] = [
            .invalidCoordinates,
            .tunneldNotRunning,
            .deviceNotFound,
            .injectionFailed("test reason"),
            .clearFailed("test reason"),
            .rateLimited,
            .timeout,
            .developerModeRequired,
            .outputSizeExceeded
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) description should not be empty")
        }
    }

    func testLocationInjectionErrorRecoverySuggestions() {
        // These errors should have recovery suggestions
        let errorsWithSuggestions: [LocationInjectionError] = [
            .tunneldNotRunning,
            .developerModeRequired,
            .deviceNotFound,
            .outputSizeExceeded
        ]

        for error in errorsWithSuggestions {
            XCTAssertNotNil(error.recoverySuggestion, "Error \(error) should have a recovery suggestion")
        }

        // These errors should NOT have recovery suggestions
        let errorsWithoutSuggestions: [LocationInjectionError] = [
            .invalidCoordinates,
            .injectionFailed("test"),
            .clearFailed("test"),
            .rateLimited,
            .timeout
        ]

        for error in errorsWithoutSuggestions {
            XCTAssertNil(error.recoverySuggestion, "Error \(error) should not have a recovery suggestion")
        }
    }

    // MARK: - Injection Stats Tests

    func testInjectionStatsInitialization() {
        let stats = InjectionStats()

        XCTAssertEqual(stats.totalInjections, 0)
        XCTAssertEqual(stats.successfulInjections, 0)
        XCTAssertEqual(stats.failedInjections, 0)
        XCTAssertEqual(stats.averageLatencyMs, 0)
        XCTAssertNil(stats.lastInjectionTime)
        XCTAssertEqual(stats.successRate, 0)
    }

    func testInjectionStatsRecordSuccess() {
        var stats = InjectionStats()

        stats.recordSuccess(latencyMs: 100)

        XCTAssertEqual(stats.totalInjections, 1)
        XCTAssertEqual(stats.successfulInjections, 1)
        XCTAssertEqual(stats.failedInjections, 0)
        XCTAssertNotNil(stats.lastInjectionTime)
        XCTAssertEqual(stats.successRate, 100.0)
    }

    func testInjectionStatsRecordFailure() {
        var stats = InjectionStats()

        stats.recordFailure()

        XCTAssertEqual(stats.totalInjections, 1)
        XCTAssertEqual(stats.successfulInjections, 0)
        XCTAssertEqual(stats.failedInjections, 1)
        XCTAssertNotNil(stats.lastInjectionTime)
        XCTAssertEqual(stats.successRate, 0)
    }

    func testInjectionStatsSuccessRate() {
        var stats = InjectionStats()

        // 2 successes, 1 failure = 66.67% success rate
        stats.recordSuccess(latencyMs: 50)
        stats.recordSuccess(latencyMs: 50)
        stats.recordFailure()

        XCTAssertEqual(stats.totalInjections, 3)
        XCTAssertEqual(stats.successfulInjections, 2)
        XCTAssertEqual(stats.failedInjections, 1)
        XCTAssertEqual(stats.successRate, 100.0 * 2.0 / 3.0, accuracy: 0.01)
    }

    func testInjectionStatsRollingAverageLatency() {
        var stats = InjectionStats()

        // First injection sets baseline
        stats.recordSuccess(latencyMs: 100)
        XCTAssertEqual(stats.averageLatencyMs, 10.0, accuracy: 0.01) // alpha=0.1, so 0*0.9 + 100*0.1 = 10

        // Second injection updates rolling average
        stats.recordSuccess(latencyMs: 100)
        // Expected: 10*0.9 + 100*0.1 = 9 + 10 = 19
        XCTAssertEqual(stats.averageLatencyMs, 19.0, accuracy: 0.01)
    }

    // MARK: - Validation Error Tests

    func testValidationErrorDescriptions() {
        let coordError = ValidationError.invalidCoordinates(latitude: 91.0, longitude: 0.0)
        XCTAssertNotNil(coordError.errorDescription)
        XCTAssertTrue(coordError.errorDescription!.contains("91"))

        let udidError = ValidationError.invalidDeviceUDID("invalid")
        XCTAssertNotNil(udidError.errorDescription)
        XCTAssertTrue(udidError.errorDescription!.contains("invalid"))

        let argError = ValidationError.invalidArgument("dangerous;arg")
        XCTAssertNotNil(argError.errorDescription)
        XCTAssertTrue(argError.errorDescription!.contains("dangerous;arg"))

        let pathError = ValidationError.pathTraversalAttempt("../../../etc/passwd")
        XCTAssertNotNil(pathError.errorDescription)
        XCTAssertTrue(pathError.errorDescription!.contains("traversal"))
    }

    // MARK: - Command Validation Error Tests

    func testCommandValidationErrorDescriptions() {
        let subcommandError = CommandValidationError.invalidSubcommand("malicious")
        XCTAssertNotNil(subcommandError.errorDescription)
        XCTAssertTrue(subcommandError.errorDescription!.contains("malicious"))
        XCTAssertTrue(subcommandError.errorDescription!.contains("allowlist"))

        let flagError = CommandValidationError.invalidFlag("--evil")
        XCTAssertNotNil(flagError.errorDescription)
        XCTAssertTrue(flagError.errorDescription!.contains("--evil"))
        XCTAssertTrue(flagError.errorDescription!.contains("allowlist"))

        let positionError = CommandValidationError.invalidArgumentPosition("badarg")
        XCTAssertNotNil(positionError.errorDescription)
        XCTAssertTrue(positionError.errorDescription!.contains("badarg"))

        let countError = CommandValidationError.unexpectedArgumentCount(expected: 5, actual: 10)
        XCTAssertNotNil(countError.errorDescription)
        XCTAssertTrue(countError.errorDescription!.contains("5"))
        XCTAssertTrue(countError.errorDescription!.contains("10"))
    }

    // MARK: - SubprocessCommandValidator Tests

    func testValidCommandStructure() {
        // Valid location set command
        let setLocationArgs = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--tunnel", "00008030001234567890123456789012345678ab", "--", "35.6762", "139.6503"]
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(setLocationArgs))

        // Valid location clear command
        let clearArgs = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "clear", "--udid", "00008030001234567890123456789012345678ab"]
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(clearArgs))

        // Valid DVT list command
        let listArgs = ["-m", "pymobiledevice3", "developer", "dvt", "ls", "--tunnel", "00008030001234567890123456789012345678ab"]
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(listArgs))
    }

    func testValidCommandWithRSD() {
        // Valid RSD connection command
        let rsdArgs = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--rsd", "fe80::1", "62078", "--", "35.6762", "139.6503"]
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(rsdArgs))
    }

    func testInvalidSubcommandBlocked() {
        // Attempt to inject unknown subcommand
        let maliciousArgs = ["-m", "pymobiledevice3", "evil", "command"]
        XCTAssertThrowsError(try SubprocessCommandValidator.validateCommandStructure(maliciousArgs)) { error in
            XCTAssertTrue(error is CommandValidationError)
            if case CommandValidationError.invalidSubcommand(let cmd) = error {
                XCTAssertEqual(cmd, "evil")
            } else {
                XCTFail("Expected invalidSubcommand error")
            }
        }
    }

    func testInvalidFlagBlocked() {
        // Attempt to use unknown flag
        let maliciousArgs = ["-m", "pymobiledevice3", "developer", "dvt", "ls", "--execute-malware"]
        XCTAssertThrowsError(try SubprocessCommandValidator.validateCommandStructure(maliciousArgs)) { error in
            XCTAssertTrue(error is CommandValidationError)
            if case CommandValidationError.invalidFlag(let flag) = error {
                XCTAssertEqual(flag, "--execute-malware")
            } else {
                XCTFail("Expected invalidFlag error")
            }
        }
    }

    func testInvalidModulePrefixBlocked() {
        // Command must start with -m pymobiledevice3
        let wrongModuleArgs = ["-m", "evil_module", "command"]
        XCTAssertThrowsError(try SubprocessCommandValidator.validateCommandStructure(wrongModuleArgs))

        // Command missing -m flag
        let noModuleFlagArgs = ["pymobiledevice3", "developer", "dvt", "ls"]
        XCTAssertThrowsError(try SubprocessCommandValidator.validateCommandStructure(noModuleFlagArgs))
    }

    func testCommandInjectionViaCoordinatesBlocked() {
        // Even though ArgumentSanitizer would catch this, validator adds defense-in-depth
        // Non-numeric data after -- should be blocked if it's not a valid data type
        let injectionAttempt = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--tunnel", "00008030001234567890123456789012345678ab", "--", "35.6762; rm -rf /", "139.6503"]
        XCTAssertThrowsError(try SubprocessCommandValidator.validateCommandStructure(injectionAttempt)) { error in
            XCTAssertTrue(error is CommandValidationError)
        }
    }

    func testValidDataArgumentDetection() {
        // Test coordinate detection
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("35.6762"))
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("-122.6503"))
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("0.0"))

        // Test UDID detection
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("00008030001234567890123456789012345678ab"))

        // Test IPv6 detection
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("fe80::1"))
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("::1"))

        // Test port detection
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("62078"))
        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("8080"))

        // Test invalid data
        XCTAssertFalse(SubprocessCommandValidator.isValidDataArgument("malicious"))
        XCTAssertFalse(SubprocessCommandValidator.isValidDataArgument("rm -rf /"))

        XCTAssertTrue(SubprocessCommandValidator.isValidDataArgument("/"))
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure([
            "-m", "pymobiledevice3", "developer", "dvt", "ls",
            "--rsd", "fddf:4f3f:cd60::1", "52569", "/",
        ]))
    }

    func testNegativeCoordinatesAllowed() {
        // Negative coordinates must work (they're valid GPS coordinates)
        let negativeCoordArgs = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--tunnel", "00008030001234567890123456789012345678ab", "--", "-33.8688", "151.2093"]
        XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(negativeCoordArgs))
    }

    func testAllAllowedFlagsAreAccepted() {
        // Test each allowed flag is accepted
        let flags = ["-m", "--tunnel", "--udid", "--rsd", "--no-color", "--", "-h", "--help"]
        for flag in flags {
            let args: [String]
            if flag == "-m" {
                args = ["-m", "pymobiledevice3", "developer", "dvt", "ls"]
            } else if flag == "--" {
                args = ["-m", "pymobiledevice3", "developer", "dvt", "simulate-location", "set", "--tunnel", "00008030001234567890123456789012345678ab", "--", "35.0", "139.0"]
            } else {
                args = ["-m", "pymobiledevice3", "developer", "dvt", "ls", flag, "00008030001234567890123456789012345678ab"]
            }
            XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(args), "Flag \(flag) should be allowed")
        }
    }

    func testAllAllowedSubcommandsAreAccepted() {
        // Test key subcommands are accepted
        let subcommands = ["developer", "dvt", "simulate-location", "set", "clear", "ls"]
        for cmd in subcommands {
            // Build a minimal valid command with this subcommand
            var args = ["-m", "pymobiledevice3"]
            if cmd == "developer" || cmd == "dvt" {
                args.append(contentsOf: ["developer", "dvt", "ls", "--tunnel", "00008030001234567890123456789012345678ab"])
            } else if cmd == "simulate-location" {
                args.append(contentsOf: ["developer", "dvt", "simulate-location", "set", "--tunnel", "00008030001234567890123456789012345678ab", "--", "35.0", "139.0"])
            } else if cmd == "set" || cmd == "clear" {
                args.append(contentsOf: ["developer", "dvt", "simulate-location", cmd, "--tunnel", "00008030001234567890123456789012345678ab"])
                if cmd == "set" {
                    args.append(contentsOf: ["--", "35.0", "139.0"])
                }
            } else if cmd == "ls" {
                args.append(contentsOf: ["developer", "dvt", "ls", "--tunnel", "00008030001234567890123456789012345678ab"])
            }
            XCTAssertNoThrow(try SubprocessCommandValidator.validateCommandStructure(args), "Subcommand \(cmd) should be allowed")
        }
    }
}
