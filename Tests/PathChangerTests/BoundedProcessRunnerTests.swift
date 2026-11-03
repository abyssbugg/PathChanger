//
//  BoundedProcessRunnerTests.swift
//  PathChangerTests
//
//  The Diagnostics screen's subprocess boundary: a deadline, a 1 MB output cap, an
//  explicit exit status, cancellation, and never a synchronous wait on the main actor.
//

import XCTest
@testable import PathChanger

final class BoundedProcessRunnerTests: XCTestCase {

    func testZeroExitReturnsTheOutputAsSuccess() async {
        let result = await BoundedProcessRunner(timeout: 5)
            .run(executable: "/bin/sh", arguments: ["-c", "printf 'hello'; printf ' err' >&2"])
        XCTAssertEqual(result.termination, .exited(0))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "hello err")
    }

    func testNonZeroExitIsReportedAndIsNotSuccess() async {
        let result = await BoundedProcessRunner(timeout: 5)
            .run(executable: "/bin/sh", arguments: ["-c", "echo oops; exit 3"])
        XCTAssertEqual(result.termination, .exited(3))
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.output, "oops\n")
    }

    func testDeadlineStopsAHungProcess() async {
        let started = Date()
        let result = await BoundedProcessRunner(timeout: 0.5)
            .run(executable: "/bin/sleep", arguments: ["30"])
        XCTAssertEqual(result.termination, .timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the deadline must end the wait")
    }

    func testOutputOverTheCapIsRefused() async {
        let started = Date()
        // 2 MB of output, more than any pipe buffer: a runner that only reads after exit
        // deadlocks here, one that does not cap returns it all.
        let result = await BoundedProcessRunner(timeout: 10)
            .run(executable: "/bin/sh", arguments: ["-c", "head -c 2000000 /dev/zero; exec sleep 30"])
        XCTAssertEqual(result.termination, .outputLimitExceeded)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThanOrEqual(result.output.utf8.count, BoundedProcessRunner.maxOutputBytes)
        XCTAssertLessThan(Date().timeIntervalSince(started), 8, "an over-cap process must be stopped, not waited for")
    }

    func testDefaultsMatchTheOtherSubprocessBoundaries() {
        XCTAssertEqual(BoundedProcessRunner.maxOutputBytes, 1_048_576)
        XCTAssertEqual(BoundedProcessRunner.defaultTimeout, 15)
        XCTAssertEqual(BoundedProcessRunner().timeout, 15)
    }

    func testMissingExecutableIsALaunchFailure() async {
        let result = await BoundedProcessRunner(timeout: 5)
            .run(executable: "/nonexistent/tmp_rovodev_no_such_binary", arguments: [])
        guard case .launchFailed = result.termination else {
            return XCTFail("expected a launch failure, got \(result.termination)")
        }
        XCTAssertFalse(result.succeeded)
    }

    func testCancellationStopsTheProcess() async {
        let started = Date()
        let task = Task {
            await BoundedProcessRunner(timeout: 30).run(executable: "/bin/sleep", arguments: ["30"])
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.termination, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "cancelling must end the wait")
    }

    func testTheEnvironmentIsTheHardenedSubprocessEnvironment() async {
        let result = await BoundedProcessRunner(timeout: 5)
            .run(executable: "/bin/sh", arguments: ["-c", "printf '%s' \"$PATH\""])
        XCTAssertEqual(result.output, ProcessEnvironment.configured()["PATH"])
    }

    /// The Diagnostics screen runs on the main actor; the runner must not wait for the
    /// process there (the old runner called `waitUntilExit()` on it and froze the window).
    @MainActor
    func testRunningFromTheMainActorDoesNotBlockIt() async {
        let runner = BoundedProcessRunner(timeout: 10)
        let task = Task { @MainActor in
            await runner.run(executable: "/bin/sleep", arguments: ["1.5"])
        }
        let before = Date()
        // This main-actor continuation can only resume once the main actor is free.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let mainActorWait = Date().timeIntervalSince(before)
        XCTAssertLessThan(mainActorWait, 0.8, "the main actor was blocked for \(mainActorWait) s while the process ran")
        let result = await task.value
        XCTAssertEqual(result.termination, .exited(0))
    }
}
