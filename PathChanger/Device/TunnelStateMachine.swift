//
//  TunnelStateMachine.swift
//  PathChanger
//
//  Formal state machine for tunnel lifecycle management.
//  Centralizes all state transitions with validation, logging, and event emission.
//

import Foundation
import Combine

// MARK: - State Machine Events

/// Events that trigger state transitions in the tunnel state machine.
///
/// These events represent actions or conditions that can cause the tunnel
/// to change from one state to another.
///
/// ## Event Categories
///
/// - **User Actions**: Events triggered by user commands
/// - **System Events**: Events from the underlying tunnel process
/// - **Error Events**: Events indicating failure conditions
///
/// ## Example
///
/// ```swift
/// stateMachine.send(.startRequested(mode: .usb))
/// ```
enum TunnelEvent: Equatable, CustomStringConvertible {
    /// User or system requested tunnel start
    case startRequested(mode: TunnelMode)

    /// Tunnel process has been successfully launched
    case processLaunched(pid: Int32?)

    /// Tunnel has established connection (RSD parsed)
    case connectionEstablished(info: TunnelInfo)

    /// User or system requested tunnel stop
    case stopRequested

    /// Tunnel process has terminated gracefully
    case processStopped

    /// Process or connection failed
    case errorOccurred(String)

    /// Process health check failed
    case healthCheckFailed

    /// Recovery attempt completed
    case recoveryAttempted

    /// Timeout waiting for connection
    case connectionTimeout

    /// External detection found tunnel already running
    case externalTunnelDetected(mode: TunnelMode, info: TunnelInfo?)

    var description: String {
        switch self {
        case .startRequested(let mode):
            return "startRequested(\(mode.rawValue))"
        case .processLaunched(let pid):
            return "processLaunched(pid: \(pid?.description ?? "nil"))"
        case .connectionEstablished(let info):
            return "connectionEstablished(\(info.rsdAddress):\(info.rsdPort))"
        case .stopRequested:
            return "stopRequested"
        case .processStopped:
            return "processStopped"
        case .errorOccurred(let message):
            return "errorOccurred(\(message.prefix(50))...)"
        case .healthCheckFailed:
            return "healthCheckFailed"
        case .recoveryAttempted:
            return "recoveryAttempted"
        case .connectionTimeout:
            return "connectionTimeout"
        case .externalTunnelDetected(let mode, let info):
            if let info = info {
                return "externalTunnelDetected(\(mode.rawValue), \(info.rsdAddress):\(info.rsdPort))"
            }
            return "externalTunnelDetected(\(mode.rawValue))"
        }
    }

    // Required for Equatable with associated values
    static func == (lhs: TunnelEvent, rhs: TunnelEvent) -> Bool {
        switch (lhs, rhs) {
        case (.startRequested(let m1), .startRequested(let m2)):
            return m1 == m2
        case (.processLaunched(let p1), .processLaunched(let p2)):
            return p1 == p2
        case (.connectionEstablished(let i1), .connectionEstablished(let i2)):
            return i1 == i2
        case (.stopRequested, .stopRequested):
            return true
        case (.processStopped, .processStopped):
            return true
        case (.errorOccurred(let e1), .errorOccurred(let e2)):
            return e1 == e2
        case (.healthCheckFailed, .healthCheckFailed):
            return true
        case (.recoveryAttempted, .recoveryAttempted):
            return true
        case (.connectionTimeout, .connectionTimeout):
            return true
        case (.externalTunnelDetected(let m1, let i1), .externalTunnelDetected(let m2, let i2)):
            return m1 == m2 && i1 == i2
        default:
            return false
        }
    }
}

// MARK: - State Machine Context

/// Context data maintained by the state machine.
///
/// Contains all auxiliary state information needed for tunnel operations
/// that doesn't fit in the primary state enum.
struct TunnelContext: Equatable {
    /// Currently active tunnel mode
    var activeMode: TunnelMode?

    /// RSD connection information
    var tunnelInfo: TunnelInfo?

    /// Tracked process IDs
    var activeProcessIds: Set<Int32> = []

    /// Last error message
    var lastError: String?

    /// Retry count for auto-recovery
    var retryCount: Int = 0

    /// Maximum retries before giving up
    let maxRetries: Int = 3

    /// Whether recovery is in progress
    var isRecovering: Bool = false

    /// Timestamp of last state change
    var lastStateChangeTime: Date = .distantPast

    /// Human-readable status message
    var statusMessage: String?

    /// Reset context for a fresh start
    mutating func reset() {
        activeMode = nil
        tunnelInfo = nil
        activeProcessIds.removeAll()
        lastError = nil
        retryCount = 0
        isRecovering = false
        statusMessage = nil
    }

    /// Track a new process ID
    mutating func trackProcess(_ pid: Int32) {
        activeProcessIds.insert(pid)
    }

    /// Remove tracked process
    mutating func removeProcess(_ pid: Int32) {
        activeProcessIds.remove(pid)
    }
}

// MARK: - State Transition Result

/// Result of a state transition attempt.
enum TransitionResult {
    /// Transition succeeded
    case success(newState: TunnelState, actions: [TunnelAction])

    /// Transition was invalid from current state
    case invalidTransition(reason: String)

    /// Transition was ignored (e.g., duplicate event)
    case ignored
}

// MARK: - State Machine Actions

/// Side-effect actions to perform after state transitions.
///
/// These actions represent work that should be performed by the
/// TunneldManager after a state transition completes.
enum TunnelAction: Equatable, CustomStringConvertible {
    /// Launch tunnel process with specified mode
    case launchProcess(mode: TunnelMode)

    /// Terminate tracked processes
    case terminateProcesses

    /// Parse RSD info from logs
    case parseRsdInfo

    /// Start health monitoring
    case startHealthMonitor

    /// Stop health monitoring
    case stopHealthMonitor

    /// Schedule recovery attempt
    case scheduleRecovery(delay: TimeInterval)

    /// Log state transition for debugging
    case logTransition(from: TunnelState, to: TunnelState, event: TunnelEvent)

    /// Notify observers of state change
    case notifyStateChange(state: TunnelState)

    /// Clean up resources
    case cleanupResources

    var description: String {
        switch self {
        case .launchProcess(let mode):
            return "launchProcess(\(mode.rawValue))"
        case .terminateProcesses:
            return "terminateProcesses"
        case .parseRsdInfo:
            return "parseRsdInfo"
        case .startHealthMonitor:
            return "startHealthMonitor"
        case .stopHealthMonitor:
            return "stopHealthMonitor"
        case .scheduleRecovery(let delay):
            return "scheduleRecovery(\(delay)s)"
        case .logTransition(let from, let to, let event):
            return "logTransition(\(from) -> \(to) on \(event))"
        case .notifyStateChange(let state):
            return "notifyStateChange(\(state))"
        case .cleanupResources:
            return "cleanupResources"
        }
    }
}

// MARK: - Tunnel State Machine

/// Formal state machine for tunnel lifecycle management.
///
/// `TunnelStateMachine` provides a centralized, validated approach to
/// tunnel state transitions. It ensures:
///
/// - **Validated transitions**: Only valid state changes are allowed
/// - **Event-driven**: All changes flow through discrete events
/// - **Action emission**: Side effects are explicitly defined
/// - **Testability**: Pure state transitions can be unit tested
///
/// ## Architecture
///
/// The state machine follows a reducer-style architecture:
///
/// ```
/// (State, Context, Event) -> (NewState, NewContext, [Actions])
/// ```
///
/// ## State Diagram
///
/// ```
/// ┌────────────────────────────────────────────────────┐
/// │                                                    │
/// ▼                                                    │
/// idle ─────────────────────┐                          │
///  │                        │                          │
///  │ startRequested         │ externalTunnelDetected   │
///  ▼                        │                          │
/// starting ─────────────────┼──────────────────────────┤
///  │  │                     │                          │
///  │  │ errorOccurred/      │                          │
///  │  │ connectionTimeout   │                          │
///  │  ▼                     │                          │
///  │ error ─────────────────┼──────────────────────────┤
///  │  │                     │ stopRequested            │
///  │  │ recoveryAttempted   │                          │
///  │  └────► starting       │                          │
///  │                        │                          │
///  │ processLaunched +      │                          │
///  │ connectionEstablished  │                          │
///  ▼                        │                          │
/// running ──────────────────┤                          │
///  │  │                     │                          │
///  │  │ healthCheckFailed/  │                          │
///  │  │ errorOccurred       │                          │
///  │  ▼                     │                          │
///  │ error ─► recovery      │                          │
///  │                        │                          │
///  │ stopRequested          │                          │
///  ▼                        ▼                          │
/// stopping ─────────────────┤                          │
///  │                        │                          │
///  │ processStopped         │                          │
///  └────────────────────────┴──────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// let stateMachine = TunnelStateMachine()
///
/// // Attempt a state transition
/// let result = stateMachine.send(.startRequested(mode: .usb))
///
/// switch result {
/// case .success(let newState, let actions):
///     // Perform actions
///     for action in actions {
///         await performAction(action)
///     }
/// case .invalidTransition(let reason):
///     print("Cannot transition: \(reason)")
/// case .ignored:
///     // Event was a no-op
///     break
/// }
/// ```
@MainActor
final class TunnelStateMachine: ObservableObject {

    // MARK: - Published State

    /// Current tunnel state
    @Published private(set) var state: TunnelState = .idle

    /// State context with additional data
    @Published private(set) var context: TunnelContext = TunnelContext()

    // MARK: - Event History (for debugging)

    /// Recent events for debugging (circular buffer)
    private var eventHistory: [TunnelEvent] = []
    private let maxHistorySize = 50

    /// Recent transitions for debugging
    private var transitionHistory: [(from: TunnelState, to: TunnelState, event: TunnelEvent)] = []

    // MARK: - Callbacks

    /// Callback for performing actions
    var actionHandler: ((TunnelAction) async -> Void)?

    // MARK: - Configuration

    /// Debounce interval for rapid state changes
    private var debounceInterval: TimeInterval = 0.3

    #if DEBUG
    /// Test mode flag to disable debouncing
    var testModeEnabled: Bool = false
    #endif

    // MARK: - Initialization

    init() {
        Logger.debug("[StateMachine] Initialized in state: \(state)", category: .device)
    }

    // MARK: - Public API

    /// Send an event to the state machine.
    ///
    /// This is the primary interface for triggering state transitions.
    /// The state machine will validate the transition and return the result.
    ///
    /// - Parameter event: The event to process
    /// - Returns: Result of the transition attempt
    @discardableResult
    func send(_ event: TunnelEvent) -> TransitionResult {
        // Record event in history
        recordEvent(event)

        // Check debounce (skipped in test mode)
        let now = Date()
        #if DEBUG
        let shouldDebounce = !testModeEnabled
        #else
        let shouldDebounce = true
        #endif

        if shouldDebounce && now.timeIntervalSince(context.lastStateChangeTime) < debounceInterval {
            // Allow critical events through debounce
            let criticalEvents: [TunnelEvent] = [.stopRequested, .processStopped]
            if !criticalEvents.contains(event) && !isErrorEvent(event) {
                Logger.debug("[StateMachine] Event debounced: \(event)", category: .device)
                return .ignored
            }
        }

        // Calculate transition
        let result = transition(from: state, event: event)

        switch result {
        case .success(let newState, let actions):
            // Update state and context
            let oldState = state
            state = newState
            context.lastStateChangeTime = now

            // Record transition
            recordTransition(from: oldState, to: newState, event: event)

            // Log transition
            Logger.info("[StateMachine] \(oldState) -> \(newState) on \(event)", category: .device)

            // Execute actions
            Task {
                for action in actions {
                    await performAction(action)
                }
            }

            return result

        case .invalidTransition(let reason):
            Logger.debug("[StateMachine] Invalid transition: \(event) from \(state) - \(reason)", category: .device)
            return result

        case .ignored:
            return result
        }
    }

    /// Get current state for external queries
    var currentState: TunnelState {
        state
    }

    /// Get current context for external queries
    var currentContext: TunnelContext {
        context
    }

    /// Check if tunnel is active
    var isActive: Bool {
        state.isActive
    }

    /// Check if tunnel is in transition
    var isTransitioning: Bool {
        state.isTransitioning
    }

    /// Get last error message
    var lastError: String? {
        context.lastError
    }

    /// Get status message
    var statusMessage: String? {
        context.statusMessage
    }

    /// Reset to initial state (for testing or recovery)
    func reset() {
        state = .idle
        context.reset()
        eventHistory.removeAll()
        transitionHistory.removeAll()
        Logger.debug("[StateMachine] Reset to initial state", category: .device)
    }

    // MARK: - State Transition Logic

    /// Core transition function.
    ///
    /// This is a pure function that determines the next state and actions
    /// based on the current state and incoming event.
    private func transition(from currentState: TunnelState, event: TunnelEvent) -> TransitionResult {
        switch (currentState, event) {

        // MARK: From Idle
        case (.idle, .startRequested(let mode)):
            context.activeMode = mode
            context.statusMessage = "Starting \(mode.rawValue) tunnel..."
            return .success(
                newState: .starting,
                actions: [
                    .logTransition(from: .idle, to: .starting, event: event),
                    .notifyStateChange(state: .starting),
                    .launchProcess(mode: mode)
                ]
            )

        case (.idle, .externalTunnelDetected(let mode, let info)):
            context.activeMode = mode
            context.tunnelInfo = info
            if let info = info {
                context.statusMessage = "Tunnel already running (\(mode.rawValue), RSD: \(info.rsdAddress):\(info.rsdPort))"
            } else {
                context.statusMessage = "Tunnel already running (\(mode.rawValue))"
            }
            return .success(
                newState: .running,
                actions: [
                    .logTransition(from: .idle, to: .running, event: event),
                    .notifyStateChange(state: .running),
                    .parseRsdInfo,
                    .startHealthMonitor
                ]
            )

        // MARK: From Starting
        case (.starting, .processLaunched(let pid)):
            if let pid = pid {
                context.trackProcess(pid)
            }
            context.statusMessage = "Process launched, establishing connection..."
            // Stay in starting until connection is established
            return .success(
                newState: .starting,
                actions: [
                    .parseRsdInfo
                ]
            )

        case (.starting, .connectionEstablished(let info)):
            context.tunnelInfo = info
            context.statusMessage = "\(context.activeMode?.rawValue ?? "Tunnel") active (RSD: \(info.rsdAddress):\(info.rsdPort))"
            context.retryCount = 0
            context.isRecovering = false
            return .success(
                newState: .running,
                actions: [
                    .logTransition(from: .starting, to: .running, event: event),
                    .notifyStateChange(state: .running),
                    .startHealthMonitor
                ]
            )

        case (.starting, .errorOccurred(let message)):
            context.lastError = message
            context.statusMessage = "Failed: \(message)"
            return .success(
                newState: .error(message),
                actions: [
                    .logTransition(from: .starting, to: .error(message), event: event),
                    .notifyStateChange(state: .error(message)),
                    .cleanupResources,
                    shouldAttemptRecovery() ? .scheduleRecovery(delay: recoveryDelay()) : .cleanupResources
                ]
            )

        case (.starting, .connectionTimeout):
            let message = "Connection timeout"
            context.lastError = message
            context.statusMessage = message
            return .success(
                newState: .error(message),
                actions: [
                    .logTransition(from: .starting, to: .error(message), event: event),
                    .notifyStateChange(state: .error(message)),
                    .terminateProcesses,
                    .cleanupResources
                ]
            )

        case (.starting, .stopRequested):
            context.statusMessage = "Stopping..."
            return .success(
                newState: .stopping,
                actions: [
                    .logTransition(from: .starting, to: .stopping, event: event),
                    .stopHealthMonitor,
                    .terminateProcesses,
                    .notifyStateChange(state: .stopping)
                ]
            )

        // MARK: From Running
        case (.running, .stopRequested):
            context.statusMessage = "Stopping tunnel..."
            return .success(
                newState: .stopping,
                actions: [
                    .logTransition(from: .running, to: .stopping, event: event),
                    .stopHealthMonitor,
                    .terminateProcesses,
                    .notifyStateChange(state: .stopping)
                ]
            )

        case (.running, .healthCheckFailed):
            let message = "Health check failed"
            context.lastError = message
            context.isRecovering = true
            return .success(
                newState: .error(message),
                actions: [
                    .logTransition(from: .running, to: .error(message), event: event),
                    .notifyStateChange(state: .error(message)),
                    .stopHealthMonitor,
                    shouldAttemptRecovery() ? .scheduleRecovery(delay: recoveryDelay()) : .terminateProcesses
                ]
            )

        case (.running, .errorOccurred(let message)):
            context.lastError = message
            context.statusMessage = "Error: \(message)"
            return .success(
                newState: .error(message),
                actions: [
                    .logTransition(from: .running, to: .error(message), event: event),
                    .notifyStateChange(state: .error(message)),
                    .stopHealthMonitor,
                    shouldAttemptRecovery() ? .scheduleRecovery(delay: recoveryDelay()) : .terminateProcesses
                ]
            )

        // MARK: From Stopping
        case (.stopping, .processStopped):
            context.reset()
            context.statusMessage = "Tunnel stopped"
            return .success(
                newState: .idle,
                actions: [
                    .logTransition(from: .stopping, to: .idle, event: event),
                    .notifyStateChange(state: .idle),
                    .cleanupResources
                ]
            )

        // MARK: From Error
        case (.error, .stopRequested):
            context.statusMessage = "Stopping..."
            context.isRecovering = false
            return .success(
                newState: .stopping,
                actions: [
                    .stopHealthMonitor,
                    .terminateProcesses,
                    .notifyStateChange(state: .stopping)
                ]
            )

        case (.error, .recoveryAttempted):
            guard shouldAttemptRecovery() else {
                return .invalidTransition(reason: "Max retries exceeded")
            }
            context.retryCount += 1
            context.statusMessage = "Attempting recovery (\(context.retryCount)/\(context.maxRetries))..."
            let mode = context.activeMode ?? .auto
            return .success(
                newState: .starting,
                actions: [
                    .logTransition(from: .error(""), to: .starting, event: event),
                    .notifyStateChange(state: .starting),
                    .launchProcess(mode: mode)
                ]
            )

        case (.error, .processStopped):
            context.reset()
            context.statusMessage = "Tunnel stopped after error"
            return .success(
                newState: .idle,
                actions: [
                    .notifyStateChange(state: .idle),
                    .cleanupResources
                ]
            )

        // MARK: Invalid/Ignored Transitions
        case (.idle, .stopRequested),
             (.idle, .processStopped):
            return .ignored

        case (.running, .startRequested):
            return .invalidTransition(reason: "Cannot start while already running")

        case (.starting, .startRequested):
            return .invalidTransition(reason: "Cannot start while starting")

        case (.stopping, .startRequested):
            return .invalidTransition(reason: "Cannot start while stopping")

        default:
            return .invalidTransition(reason: "Unhandled transition: \(currentState) + \(event)")
        }
    }

    // MARK: - Helper Methods

    private func isErrorEvent(_ event: TunnelEvent) -> Bool {
        switch event {
        case .errorOccurred, .healthCheckFailed, .connectionTimeout:
            return true
        default:
            return false
        }
    }

    private func shouldAttemptRecovery() -> Bool {
        UserDefaults.standard.bool(forKey: "autoRecoverTunneld") && context.retryCount < context.maxRetries
    }

    private func recoveryDelay() -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s
        pow(2.0, Double(context.retryCount))
    }

    private func recordEvent(_ event: TunnelEvent) {
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst()
        }
    }

    private func recordTransition(from: TunnelState, to: TunnelState, event: TunnelEvent) {
        transitionHistory.append((from: from, to: to, event: event))
        if transitionHistory.count > maxHistorySize {
            transitionHistory.removeFirst()
        }
    }

    private func performAction(_ action: TunnelAction) async {
        Logger.debug("[StateMachine] Performing action: \(action)", category: .device)
        await actionHandler?(action)
    }
}

// MARK: - Debug Description

extension TunnelStateMachine: CustomDebugStringConvertible {
    nonisolated var debugDescription: String {
        // Use a simple description since we can't access MainActor properties synchronously
        "TunnelStateMachine"
    }
}

// MARK: - State Machine Testing Support

#if DEBUG
extension TunnelStateMachine {
    /// Get event history for testing
    var testEventHistory: [TunnelEvent] {
        eventHistory
    }

    /// Get transition history for testing
    var testTransitionHistory: [(from: TunnelState, to: TunnelState, event: TunnelEvent)] {
        transitionHistory
    }

    /// Force set state for testing (bypasses validation)
    func testSetState(_ newState: TunnelState) {
        state = newState
    }

    /// Force set context for testing
    func testSetContext(_ newContext: TunnelContext) {
        context = newContext
    }
}
#endif
