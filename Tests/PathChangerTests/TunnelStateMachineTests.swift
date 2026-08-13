//
//  TunnelStateMachineTests.swift
//  PathChangerTests
//
//  Tests for formal tunnel state machine with validated transitions.
//

import XCTest
@testable import PathChanger

@MainActor
final class TunnelStateMachineTests: XCTestCase {

    var stateMachine: TunnelStateMachine!
    var recordedActions: [TunnelAction] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        stateMachine = TunnelStateMachine()
        stateMachine.testModeEnabled = true  // Disable debouncing for tests
        recordedActions = []

        // Set up action handler to record actions
        stateMachine.actionHandler = { [weak self] action in
            self?.recordedActions.append(action)
        }
    }

    override func tearDownWithError() throws {
        stateMachine = nil
        recordedActions = []
        try super.tearDownWithError()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsIdle() {
        XCTAssertEqual(stateMachine.currentState, .idle)
        XCTAssertFalse(stateMachine.isActive)
        XCTAssertFalse(stateMachine.isTransitioning)
    }

    func testInitialContextIsEmpty() {
        let context = stateMachine.currentContext
        XCTAssertNil(context.activeMode)
        XCTAssertNil(context.tunnelInfo)
        XCTAssertTrue(context.activeProcessIds.isEmpty)
        XCTAssertNil(context.lastError)
        XCTAssertEqual(context.retryCount, 0)
    }

    // MARK: - Idle State Transitions

    func testIdleToStartingOnStartRequested() {
        let result = stateMachine.send(.startRequested(mode: .usb))

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .starting)
            XCTAssertEqual(stateMachine.currentState, .starting)
            XCTAssertTrue(stateMachine.isTransitioning)

            // Check actions include launch
            XCTAssertTrue(actions.contains(where: {
                if case .launchProcess(let mode) = $0 { return mode == .usb }
                return false
            }))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testIdleToRunningOnExternalDetected() {
        let result = stateMachine.send(.externalTunnelDetected(mode: .daemon))

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .running)
            XCTAssertEqual(stateMachine.currentState, .running)
            XCTAssertTrue(stateMachine.isActive)
            XCTAssertEqual(stateMachine.currentContext.activeMode, .daemon)

            // Should start health monitor
            XCTAssertTrue(actions.contains(.startHealthMonitor))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testIdleIgnoresStopRequested() {
        let result = stateMachine.send(.stopRequested)

        if case .ignored = result {
            XCTAssertEqual(stateMachine.currentState, .idle)
        } else {
            XCTFail("Expected ignored result")
        }
    }

    func testIdleIgnoresProcessStopped() {
        let result = stateMachine.send(.processStopped)

        if case .ignored = result {
            XCTAssertEqual(stateMachine.currentState, .idle)
        } else {
            XCTFail("Expected ignored result")
        }
    }

    // MARK: - Starting State Transitions

    func testStartingTracksProcessOnLaunched() {
        stateMachine.send(.startRequested(mode: .wifi))

        let result = stateMachine.send(.processLaunched(pid: 12345))

        if case .success(let newState, _) = result {
            // Still starting until connection established
            XCTAssertEqual(newState, .starting)
            XCTAssertTrue(stateMachine.currentContext.activeProcessIds.contains(12345))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingUntracksExactExitedProcess() {
        stateMachine.send(.startRequested(mode: .wifi))
        stateMachine.send(.processLaunched(pid: 12345))

        let result = stateMachine.send(.processExited(pid: 12345))

        if case .success(let newState, _) = result {
            XCTAssertEqual(newState, .error("Tunnel process exited"))
            XCTAssertFalse(stateMachine.currentContext.activeProcessIds.contains(12345))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingAdoptsExternallyDetectedTunnel() {
        stateMachine.send(.startRequested(mode: .usb))

        let result = stateMachine.send(.externalTunnelDetected(mode: .daemon))

        if case .success(let newState, _) = result {
            XCTAssertEqual(newState, .running)
            XCTAssertEqual(stateMachine.currentContext.activeMode, .daemon)
            XCTAssertTrue(stateMachine.currentContext.activeProcessIds.isEmpty)
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingToRunningOnConnectionEstablished() {
        stateMachine.send(.startRequested(mode: .usb))

        let tunnelInfo = TunnelInfo(
            rsdAddress: "192.168.1.100",
            rsdPort: 55000,
            mode: .usb,
            interface: "en0",
            processId: 12345
        )

        let result = stateMachine.send(.connectionEstablished(info: tunnelInfo))

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .running)
            XCTAssertEqual(stateMachine.currentContext.tunnelInfo, tunnelInfo)
            XCTAssertTrue(actions.contains(.startHealthMonitor))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingToErrorOnErrorOccurred() {
        stateMachine.send(.startRequested(mode: .wifi))

        let result = stateMachine.send(.errorOccurred("Device not found"))

        if case .success(let newState, _) = result {
            if case .error(let message) = newState {
                XCTAssertEqual(message, "Device not found")
                XCTAssertEqual(stateMachine.lastError, "Device not found")
            } else {
                XCTFail("Expected error state")
            }
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingToErrorOnConnectionTimeout() {
        stateMachine.send(.startRequested(mode: .daemon))

        let result = stateMachine.send(.connectionTimeout)

        if case .success(let newState, let actions) = result {
            if case .error(let message) = newState {
                XCTAssertEqual(message, "Connection timeout")
            } else {
                XCTFail("Expected error state")
            }
            // Should terminate processes on timeout
            XCTAssertTrue(actions.contains(.terminateProcesses))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingToStoppingOnStopRequested() {
        stateMachine.send(.startRequested(mode: .usb))

        let result = stateMachine.send(.stopRequested)

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .stopping)
            XCTAssertTrue(actions.contains(.terminateProcesses))
            XCTAssertTrue(actions.contains(.stopHealthMonitor))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStartingRejectsDoubleStart() {
        stateMachine.send(.startRequested(mode: .usb))

        let result = stateMachine.send(.startRequested(mode: .wifi))

        if case .invalidTransition(let reason) = result {
            XCTAssertTrue(reason.contains("start"))
        } else {
            XCTFail("Expected invalid transition")
        }
    }

    // MARK: - Running State Transitions

    func testRunningToStoppingOnStopRequested() {
        // Set up running state
        stateMachine.send(.startRequested(mode: .usb))
        let info = TunnelInfo(rsdAddress: "127.0.0.1", rsdPort: 50000, mode: .usb, interface: nil, processId: nil)
        stateMachine.send(.connectionEstablished(info: info))

        let result = stateMachine.send(.stopRequested)

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .stopping)
            XCTAssertTrue(actions.contains(.terminateProcesses))
            XCTAssertTrue(actions.contains(.stopHealthMonitor))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testRunningToErrorOnHealthCheckFailed() {
        // Set up running state
        stateMachine.send(.startRequested(mode: .usb))
        let info = TunnelInfo(rsdAddress: "127.0.0.1", rsdPort: 50000, mode: .usb, interface: nil, processId: nil)
        stateMachine.send(.connectionEstablished(info: info))

        let result = stateMachine.send(.healthCheckFailed)

        if case .success(let newState, let actions) = result {
            if case .error = newState {
                XCTAssertTrue(stateMachine.currentContext.isRecovering)
            } else {
                XCTFail("Expected error state")
            }
            // Should schedule recovery for first failure
            XCTAssertTrue(actions.contains(where: {
                if case .scheduleRecovery = $0 { return true }
                return false
            }))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testRunningRejectsStartRequest() {
        // Set up running state
        stateMachine.send(.startRequested(mode: .usb))
        let info = TunnelInfo(rsdAddress: "127.0.0.1", rsdPort: 50000, mode: .usb, interface: nil, processId: nil)
        stateMachine.send(.connectionEstablished(info: info))

        let result = stateMachine.send(.startRequested(mode: .wifi))

        if case .invalidTransition(let reason) = result {
            XCTAssertTrue(reason.contains("running"))
        } else {
            XCTFail("Expected invalid transition")
        }
    }

    // MARK: - Stopping State Transitions

    func testStoppingToIdleOnProcessStopped() {
        // Set up stopping state
        stateMachine.send(.startRequested(mode: .usb))
        let info = TunnelInfo(rsdAddress: "127.0.0.1", rsdPort: 50000, mode: .usb, interface: nil, processId: nil)
        stateMachine.send(.connectionEstablished(info: info))
        stateMachine.send(.stopRequested)

        let result = stateMachine.send(.processStopped)

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .idle)
            XCTAssertNil(stateMachine.currentContext.activeMode)
            XCTAssertNil(stateMachine.currentContext.tunnelInfo)
            XCTAssertTrue(actions.contains(.cleanupResources))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testStoppingRejectsStartRequest() {
        // Set up stopping state
        stateMachine.send(.startRequested(mode: .usb))
        stateMachine.send(.stopRequested)

        let result = stateMachine.send(.startRequested(mode: .wifi))

        if case .invalidTransition(let reason) = result {
            XCTAssertTrue(reason.contains("stopping"))
        } else {
            XCTFail("Expected invalid transition")
        }
    }

    // MARK: - Error State Transitions

    func testErrorToStartingOnRecoveryAttempted() {
        // Set up error state
        stateMachine.send(.startRequested(mode: .wifi))
        stateMachine.send(.errorOccurred("Connection failed"))

        let result = stateMachine.send(.recoveryAttempted)

        if case .success(let newState, let actions) = result {
            XCTAssertEqual(newState, .starting)
            XCTAssertEqual(stateMachine.currentContext.retryCount, 1)
            XCTAssertTrue(actions.contains(where: {
                if case .launchProcess(let mode) = $0 { return mode == .wifi }
                return false
            }))
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testErrorExhaustsRetries() {
        stateMachine.send(.startRequested(mode: .usb))

        // Retry until exhausted (maxRetries = 3, so we can retry 3 times)
        // Attempt 0: fail
        stateMachine.send(.errorOccurred("Failure 0"))
        stateMachine.send(.recoveryAttempted) // retryCount = 1

        // Attempt 1: fail
        stateMachine.send(.errorOccurred("Failure 1"))
        stateMachine.send(.recoveryAttempted) // retryCount = 2

        // Attempt 2: fail
        stateMachine.send(.errorOccurred("Failure 2"))
        stateMachine.send(.recoveryAttempted) // retryCount = 3

        // Attempt 3: fail - this should be the last allowed retry
        stateMachine.send(.errorOccurred("Failure 3"))

        // Fourth recovery should fail since retryCount (3) >= maxRetries (3)
        let result = stateMachine.send(.recoveryAttempted)

        if case .invalidTransition(let reason) = result {
            XCTAssertTrue(reason.contains("retries"))
        } else {
            XCTFail("Expected invalid transition after max retries")
        }
    }

    func testErrorToStoppingOnStopRequested() {
        stateMachine.send(.startRequested(mode: .usb))
        stateMachine.send(.errorOccurred("Test error"))

        let result = stateMachine.send(.stopRequested)

        if case .success(let newState, _) = result {
            XCTAssertEqual(newState, .stopping)
            XCTAssertFalse(stateMachine.currentContext.isRecovering)
        } else {
            XCTFail("Expected success transition")
        }
    }

    func testErrorToIdleOnProcessStopped() {
        stateMachine.send(.startRequested(mode: .usb))
        stateMachine.send(.errorOccurred("Test error"))

        let result = stateMachine.send(.processStopped)

        if case .success(let newState, _) = result {
            XCTAssertEqual(newState, .idle)
        } else {
            XCTFail("Expected success transition")
        }
    }

    // MARK: - Context Tests

    func testContextTracksActiveMode() {
        stateMachine.send(.startRequested(mode: .daemon))
        XCTAssertEqual(stateMachine.currentContext.activeMode, .daemon)
    }

    func testContextClearsOnReset() {
        // Set up some state
        stateMachine.send(.startRequested(mode: .usb))
        stateMachine.send(.processLaunched(pid: 12345))

        stateMachine.reset()

        XCTAssertEqual(stateMachine.currentState, .idle)
        XCTAssertNil(stateMachine.currentContext.activeMode)
        XCTAssertTrue(stateMachine.currentContext.activeProcessIds.isEmpty)
    }

    func testContextUpdatesStatusMessage() {
        stateMachine.send(.startRequested(mode: .wifi))
        XCTAssertNotNil(stateMachine.statusMessage)
        XCTAssertTrue(stateMachine.statusMessage?.contains("WiFi") ?? false)
    }

    // MARK: - Event Equality Tests

    func testEventEquality() {
        XCTAssertEqual(
            TunnelEvent.startRequested(mode: .usb),
            TunnelEvent.startRequested(mode: .usb)
        )
        XCTAssertNotEqual(
            TunnelEvent.startRequested(mode: .usb),
            TunnelEvent.startRequested(mode: .wifi)
        )
        XCTAssertEqual(TunnelEvent.stopRequested, TunnelEvent.stopRequested)
        XCTAssertEqual(
            TunnelEvent.errorOccurred("test"),
            TunnelEvent.errorOccurred("test")
        )
    }

    // MARK: - Action Tests

    func testActionsAreEmitted() async throws {
        stateMachine.send(.startRequested(mode: .usb))

        // Wait for async action handler
        try await Task.sleep(nanoseconds: 100_000_000)

        // Should have emitted launchProcess action
        XCTAssertTrue(recordedActions.contains(where: {
            if case .launchProcess(let mode) = $0 { return mode == .usb }
            return false
        }))
    }

    // MARK: - Complete Lifecycle Tests

    func testCompleteSuccessfulLifecycle() {
        // Start tunnel
        let startResult = stateMachine.send(.startRequested(mode: .usb))
        XCTAssertEqual(stateMachine.currentState, .starting)

        // Process launches
        stateMachine.send(.processLaunched(pid: 54321))
        XCTAssertTrue(stateMachine.currentContext.activeProcessIds.contains(54321))

        // Connection established
        let info = TunnelInfo(
            rsdAddress: "192.168.1.1",
            rsdPort: 62078,
            mode: .usb,
            interface: "en0",
            processId: 54321
        )
        stateMachine.send(.connectionEstablished(info: info))
        XCTAssertEqual(stateMachine.currentState, .running)
        XCTAssertTrue(stateMachine.isActive)

        // Stop requested
        stateMachine.send(.stopRequested)
        XCTAssertEqual(stateMachine.currentState, .stopping)

        // Process stops
        stateMachine.send(.processStopped)
        XCTAssertEqual(stateMachine.currentState, .idle)
        XCTAssertFalse(stateMachine.isActive)
    }

    func testCompleteFailureRecoveryLifecycle() {
        // Start tunnel
        stateMachine.send(.startRequested(mode: .wifi))
        XCTAssertEqual(stateMachine.currentState, .starting)

        // First failure
        stateMachine.send(.errorOccurred("No device"))
        if case .error = stateMachine.currentState {
            XCTAssertEqual(stateMachine.currentContext.retryCount, 0)
        } else {
            XCTFail("Expected error state")
        }

        // First recovery
        stateMachine.send(.recoveryAttempted)
        XCTAssertEqual(stateMachine.currentState, .starting)
        XCTAssertEqual(stateMachine.currentContext.retryCount, 1)

        // Success on retry
        let info = TunnelInfo(rsdAddress: "127.0.0.1", rsdPort: 50000, mode: .wifi, interface: nil, processId: nil)
        stateMachine.send(.connectionEstablished(info: info))
        XCTAssertEqual(stateMachine.currentState, .running)

        // Retry count should reset on success
        XCTAssertEqual(stateMachine.currentContext.retryCount, 0)
    }

    // MARK: - Thread Safety Tests (MainActor)

    func testMainActorIsolation() {
        // This test verifies that the state machine properly isolates on MainActor
        // The fact that this compiles and runs without data races is the test

        Task { @MainActor in
            let machine = TunnelStateMachine()
            machine.send(.startRequested(mode: .usb))
            XCTAssertEqual(machine.currentState, .starting)
        }
    }

    // MARK: - Debugging Support Tests

    #if DEBUG
    func testEventHistoryIsRecorded() {
        stateMachine.send(.startRequested(mode: .usb))
        stateMachine.send(.processLaunched(pid: 123))
        stateMachine.send(.stopRequested)

        let history = stateMachine.testEventHistory
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0], .startRequested(mode: .usb))
        XCTAssertEqual(history[1], .processLaunched(pid: 123))
        XCTAssertEqual(history[2], .stopRequested)
    }

    func testTransitionHistoryIsRecorded() {
        stateMachine.send(.startRequested(mode: .usb))

        let history = stateMachine.testTransitionHistory
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history[0].from, .idle)
        XCTAssertEqual(history[0].to, .starting)
    }
    #endif
}
