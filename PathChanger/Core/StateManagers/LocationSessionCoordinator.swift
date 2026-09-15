import Foundation
import Combine

/// Typed errors for location session transitions.
enum LocationSessionTransitionError: Error, Equatable {
  case noDesiredLocation
  case noReadySession
  case noSelectedMode
  case noPendingRequest
  case requestMismatch
  case staleGeneration
  case clearUnavailable
  case clearFailed
  case beginApplicationDuringClearing
  case receiptNotApplied
  case applicationFailed
  case coordinateMismatch
  case recoveryExhausted
  case recoveryCancelled
  case stableDeviceMismatch
}

enum LocationSessionLossEvent: Equatable, Sendable {
  case bridgeTerminated(exitCode: Int32)
  case heldProcessExited
  case tunnelHealthLost
  case selectedDeviceLost(stableDeviceID: String)
  case endpointReplaced
  case appCancelled

  var reason: String {
    switch self {
    case .bridgeTerminated(let exitCode): return "Location bridge terminated (exit \(exitCode))"
    case .heldProcessExited: return "Held location process exited"
    case .tunnelHealthLost: return "Tunnel health lost"
    case .selectedDeviceLost: return "Selected device lost"
    case .endpointReplaced: return "Location endpoint replaced"
    case .appCancelled: return "Application cancelled recovery"
    }
  }
}

/// Main actor-safe location session coordinator.
/// Manages the state machine for location injection via a LocationInjecting adapter.
/// State is the sole source of truth.
@MainActor
final class LocationSessionCoordinator: ObservableObject {
  @Published private(set) var state: LocationSessionState = LocationSessionState()

  private let injector: any LocationInjecting

  // Implementation context (private)
  private var selectedMode: LocationMode?
  private var currentReadySession: LocationSessionIdentity?
  private var currentReadySessionSnapshot: LocationSessionIdentity?
  private var previousSession: LocationSessionIdentity?
  private var pendingRequest: LocationApplicationRequest?
  private var movementBeforeRecovery: LocationMovementPhase?

  init(injector: any LocationInjecting) {
    self.injector = injector
  }

  /// Lifecycle and receipt events emitted by the configured injection adapter.
  func events() async -> AsyncStream<LocationBridgeEvent> {
    await injector.events()
  }

  // MARK: - Public API

  /// Select a target coordinate and desired mode (app inactive).
  func select(_ coordinate: LocationCoordinate, mode: LocationMode) {
    self.state.desiredLocation = coordinate
    self.selectedMode = mode
  }

  /// Begin application after connection is ready.
  /// Throws typed errors if no ready session, desired location, or selected mode.
  /// Throws beginApplicationDuringClearing if application state is clearing.
  func beginApplication() throws -> LocationApplicationRequest {
    if case .clearing = state.application {
      throw LocationSessionTransitionError.beginApplicationDuringClearing
    }

    guard let currentReadySession else {
      throw LocationSessionTransitionError.noReadySession
    }
    guard let desiredLocation = state.desiredLocation else {
      throw LocationSessionTransitionError.noDesiredLocation
    }
    guard let selectedMode else {
      throw LocationSessionTransitionError.noSelectedMode
    }

    let target = LocationInjectionTarget(
      stableDeviceID: currentReadySession.stableDeviceID,
      transport: currentReadySession.transport
    )

    let request = LocationApplicationRequest(
      id: UUID(),
      target: target,
      coordinate: desiredLocation,
      mode: selectedMode
    )

    self.pendingRequest = request
    self.state.application = .applying(requestID: request.id, coordinate: desiredLocation)

    return request
  }

  /// Accept a receipt matching the pending request.
  /// Validates requestID AND receipt.coordinate equals pendingRequest.coordinate.
  /// Only outcome `.applied` may activate. `.queued` must not activate or acknowledge.
  /// `.failed(code)` must not activate; sets application failed, consumes pending.
  /// Returns typed errors for mismatches.
  @discardableResult
  func accept(_ receipt: LocationInjectionReceipt) -> LocationSessionTransitionError? {
    guard let pendingRequest else {
      return .noPendingRequest
    }

    guard receipt.requestID == pendingRequest.id else {
      return .requestMismatch
    }

    guard receipt.coordinate == pendingRequest.coordinate else {
      return .coordinateMismatch
    }

    guard let currentReadySession,
          receipt.sessionGeneration == currentReadySession.generation else {
      return .staleGeneration
    }

    guard receipt.transport == currentReadySession.transport else {
      return .requestMismatch
    }
    guard currentReadySession.endpointClass == .unresolved
            || receipt.endpointClass == currentReadySession.endpointClass else {
      return .requestMismatch
    }

    // Validate outcome
    switch receipt.outcome {
    case .applied:
      // Only provider acknowledgement may resolve a provisional endpoint.
      if currentReadySession.endpointClass == .unresolved {
        self.state.connection = .ready(identity: LocationSessionIdentity(
          stableDeviceID: currentReadySession.stableDeviceID,
          transport: currentReadySession.transport,
          endpointClass: receipt.endpointClass,
          generation: currentReadySession.generation
        ))
      }
      self.state.application = .active(receipt: receipt)
      self.state.lastAcknowledgedReceipt = receipt
      self.pendingRequest = nil
      return nil
    case .queued:
      // .queued must not activate or acknowledge; leave applying/pending and return error
      return .receiptNotApplied
    case .failed(let code):
      // .failed must not activate; set application failed, consume pending
      self.state.application = .failed(code)
      self.pendingRequest = nil
      return .applicationFailed
    }
  }

  /// Cancel only an in-flight proposal and restore the last acknowledged truth.
  @discardableResult
  func cancelPendingApplication(requestID: UUID? = nil) -> LocationSessionTransitionError? {
    guard let pendingRequest else { return .noPendingRequest }
    if let requestID, requestID != pendingRequest.id { return .requestMismatch }
    self.pendingRequest = nil
    state.application = state.lastAcknowledgedReceipt.map(LocationApplicationPhase.active) ?? .idle
    return nil
  }

  /// Reject a request by ID, setting application to failed with error text.
  /// Returns requestMismatch if the ID doesn't match the pending request.
  @discardableResult
  func reject(requestID: UUID, error: Error) -> LocationSessionTransitionError? {
    guard let pendingRequest else {
      return .noPendingRequest
    }

    guard requestID == pendingRequest.id else {
      return .requestMismatch
    }

    let errorText = error.localizedDescription
    self.state.application = .failed(errorText)
    self.pendingRequest = nil
    return nil
  }

  /// Begin movement, changing movement phase to moving.
  func beginMovement(_ mode: LocationMode) {
    self.state.movement = .moving(mode)
  }

  /// Pause movement, changing movement phase to paused.
  func pauseMovement() {
    if case .moving(let mode) = self.state.movement {
      self.state.movement = .paused(mode)
    }
  }

  /// Stop movement, returning movement to idle.
  func stopMovement() {
    self.state.movement = .idle
  }

  /// Complete movement, deriving mode from current moving/paused first, else selected mode.
  func completeMovement() {
    let derivedMode: LocationMode?
    if case .moving(let mode) = self.state.movement {
      derivedMode = mode
    } else if case .paused(let mode) = self.state.movement {
      derivedMode = mode
    } else {
      derivedMode = selectedMode
    }

    if let derivedMode = derivedMode {
      self.state.movement = .completed(derivedMode)
    } else {
      self.state.movement = .idle
    }
  }

  func submit(_ event: LocationSessionLossEvent) {
    connectionLost(reason: event.reason)
  }

  /// Signal connection ready, storing the session identity for later use.
  func connectionReady(_ session: LocationSessionIdentity) {
    self.currentReadySession = session
    self.state.connection = .ready(identity: session)
  }

  /// Signal connection lost, preserving desired state.
  /// Nils pendingRequest so late accept/reject returns noPending.
  func connectionLost(reason: String) {
    self.previousSession = self.currentReadySession ?? self.previousSession
    self.currentReadySession = nil
    self.pendingRequest = nil
    self.state.connection = .failed(reason)

    if case .moving(let mode) = self.state.movement {
      self.movementBeforeRecovery = self.state.movement
      self.state.movement = .paused(mode)
    }

    self.state.application = .uncertain(
      lastReceipt: self.state.lastAcknowledgedReceipt,
      reason: reason
    )
  }

  /// Reconnects the same stable device and reapplies the desired coordinate.
  /// Movement paused by connection loss resumes only after a current-generation applied receipt.
  func recover(
    strategy: ReconnectionStrategy,
    sleeper: any RecoverySleeping = TaskRecoverySleeper(),
    establishSession: @escaping @MainActor (
      _ attempt: Int,
      _ previousSession: LocationSessionIdentity?
    ) async throws -> LocationSessionIdentity
  ) async -> LocationSessionTransitionError? {
    guard state.desiredLocation != nil else { return .noDesiredLocation }
    guard let originalSession = previousSession else { return .noReadySession }
    guard strategy.maxAttempts > 0 else {
      finishRecoveryFailure(reason: "Recovery exhausted")
      return .recoveryExhausted
    }

    for attempt in 1...strategy.maxAttempts {
      if Task.isCancelled {
        finishRecoveryFailure(reason: "Recovery cancelled")
        return .recoveryCancelled
      }

      beginRecovery(attempt: attempt)

      do {
        let previous = previousSession ?? originalSession
        let candidate = try await establishSession(attempt, previous)
        guard candidate.stableDeviceID == originalSession.stableDeviceID else {
          throw LocationSessionTransitionError.stableDeviceMismatch
        }
        guard candidate.generation > previous.generation else {
          throw LocationSessionTransitionError.staleGeneration
        }

        connectionReady(candidate)
        let request = try beginApplication()
        let receipt = try await injector.apply(request)
        if let transitionError = accept(receipt) {
          throw transitionError
        }

        if case .moving(let mode) = movementBeforeRecovery {
          state.movement = .moving(mode)
        }
        movementBeforeRecovery = nil
        return nil
      } catch is CancellationError {
        finishRecoveryFailure(reason: "Recovery cancelled")
        return .recoveryCancelled
      } catch {
        if currentReadySession != nil {
          connectionLost(reason: error.localizedDescription)
        } else {
          state.application = .uncertain(
            lastReceipt: state.lastAcknowledgedReceipt,
            reason: error.localizedDescription
          )
        }
      }

      guard attempt < strategy.maxAttempts else { break }
      do {
        try await sleeper.sleep(seconds: strategy.delayForAttempt(attempt))
      } catch {
        finishRecoveryFailure(reason: "Recovery cancelled")
        return .recoveryCancelled
      }
    }

    finishRecoveryFailure(reason: "Recovery exhausted")
    return .recoveryExhausted
  }

  private func finishRecoveryFailure(reason: String) {
    currentReadySession = nil
    pendingRequest = nil
    state.connection = .failed(reason)
    state.application = .uncertain(
      lastReceipt: state.lastAcknowledgedReceipt,
      reason: reason
    )
  }

  /// Begin recovery with exact attempt number.
  func beginRecovery(attempt: Int) {
    self.state.connection = .reconnecting(previousGeneration: previousSession?.generation, attempt: attempt)
  }

  /// Restore provider-acknowledged held truth after adopting a managed helper.
  /// Movement engines are never resumed automatically after relaunch.
  @discardableResult
  func adoptHeldSession(
    identity: LocationSessionIdentity,
    receipt: LocationInjectionReceipt
  ) -> LocationSessionTransitionError? {
    guard case .applied = receipt.outcome else { return .receiptNotApplied }
    guard receipt.sessionGeneration == identity.generation else { return .staleGeneration }
    guard receipt.transport == identity.transport,
          receipt.endpointClass == identity.endpointClass else {
      return .requestMismatch
    }
    guard let actualChannel = receipt.actualChannel,
          actualChannel.isSupported,
          actualChannel.endpointClass == identity.endpointClass else {
      return .requestMismatch
    }

    currentReadySession = identity
    previousSession = nil
    pendingRequest = nil
    selectedMode = .teleport
    state.connection = .ready(identity: identity)
    state.desiredLocation = receipt.coordinate
    state.lastAcknowledgedReceipt = receipt
    state.application = .active(receipt: receipt)
    state.movement = .idle
    return nil
  }

  /// Clear state and target.
  /// Uses a target captured before delivery quiescence, or the current ready session.
  /// A captured target does not restore connection readiness.
  /// Sets clearing phase before awaiting injector.
  /// Snapshots ready session and marks `.clearing`.
  /// Prevents `beginApplication` while clearing with a typed transition error.
  /// After await, before success/failure mutation, verifies the operation is still current:
  /// same ready identity and state remains clearing. If connection/mode/application state changed,
  /// does not overwrite newer state; returns a typed superseded/stale error.
  /// Connection loss during clear must remain failed/uncertain when clear returns.
  /// On success: sets desiredLocation=nil, lastAcknowledgedReceipt=nil, application=.idle, pending=nil.
  /// On failure: retains desired/ack/connection/movement, sets failed, returns clearFailed.
  func clear(targetSession: LocationSessionIdentity? = nil) async -> LocationSessionTransitionError? {
    guard let currentReadySession = targetSession ?? self.currentReadySession else {
      return .clearUnavailable
    }

    // Snapshot ready session and mark clearing
    self.currentReadySessionSnapshot = currentReadySession
    self.state.application = .clearing

    do {
      let target = LocationInjectionTarget(
        stableDeviceID: currentReadySession.stableDeviceID,
        transport: currentReadySession.transport
      )
      try await injector.clear(target: target, session: currentReadySession)

      // After await, verify operation is still current
      guard self.currentReadySessionSnapshot == currentReadySession else {
        // Ready session changed, do not overwrite newer state
        return .staleGeneration
      }

      guard case .clearing = self.state.application else {
        // State changed (e.g., connection lost), do not overwrite
        return .staleGeneration
      }

      self.state.desiredLocation = nil
      self.state.lastAcknowledgedReceipt = nil
      self.state.application = .idle
      self.pendingRequest = nil
      self.currentReadySessionSnapshot = nil
      return nil
    } catch {
      self.state.application = .failed(error.localizedDescription)
      self.currentReadySessionSnapshot = nil
      return .clearFailed
    }
  }
}
