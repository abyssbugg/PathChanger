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
  /// The injector refused the Clear before sending anything: it holds no session for
  /// the identity. The application phase stays `.clearing` for the caller to commit.
  case noHeldSession
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
  case tunnelStoppedByUser
  case selectedDeviceLost(stableDeviceID: String)
  case endpointReplaced
  case appCancelled

  var reason: String {
    switch self {
    case .bridgeTerminated(let exitCode): return "Location bridge terminated (exit \(exitCode))"
    case .heldProcessExited: return "Held location process exited"
    case .tunnelHealthLost: return "Tunnel health lost"
    case .tunnelStoppedByUser: return "Tunnel stopped"
    case .selectedDeviceLost: return "Selected device lost"
    case .endpointReplaced: return "Location endpoint replaced"
    case .appCancelled: return "Application cancelled recovery"
    }
  }

  /// A loss the user caused (Stop Tunnel, Reconnect, transport switch, app cancel) is
  /// not repaired behind their back: automatic recovery would re-apply the location
  /// through the helper and undo the Stop.
  var startsAutomaticRecovery: Bool {
    switch self {
    case .tunnelStoppedByUser, .appCancelled:
      return false
    case .bridgeTerminated, .heldProcessExited, .tunnelHealthLost, .selectedDeviceLost, .endpointReplaced:
      return true
    }
  }
}

/// Main actor-safe location session coordinator.
/// Manages the state machine for location injection via a LocationInjecting adapter.
/// State is the sole source of truth.
@MainActor
final class LocationSessionCoordinator: ObservableObject {
  @Published private(set) var state: LocationSessionState = LocationSessionState()
  /// Advances on every connection failure (a loss or a failed recovery), even one with
  /// the same reason text, so a caller that awaited can tell a newer failure from the one
  /// it started with.
  private(set) var connectionFailureEpoch: UInt64 = 0

  private let injector: any LocationInjecting

  // Implementation context (private)
  private var selectedMode: LocationMode?
  private var currentReadySession: LocationSessionIdentity?
  /// The session the latest `clear` tried to clear (its target, or the ready session it
  /// read at the start), nil when it had none. A caller that captured no session (the
  /// connection had failed) reads it to commit a `noHeldSession` outcome: a provisional
  /// Ready can be published between the caller's capture and the call (review
  /// 2026-11-02-163337 issue 1).
  private(set) var lastClearTarget: LocationSessionIdentity?
  private var previousSession: LocationSessionIdentity?
  private var pendingRequest: LocationApplicationRequest?
  /// The application phase when the current run of `.applying` began; a cancelled
  /// application restores it.
  private var phaseBeforeApplying: LocationApplicationPhase?

  init(injector: any LocationInjecting) {
    self.injector = injector
  }

  /// The stable device of the session the last loss ended (the one `recover` reconnects).
  var recoverableDeviceID: String? {
    (previousSession ?? currentReadySession)?.stableDeviceID
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
      mode: selectedMode,
      sessionGeneration: currentReadySession.generation
    )

    // What is held on the device while this application is in flight: the active
    // receipt, or the one an in-flight application was already carrying (a joystick
    // step replacing a pending step). Nothing after a failure, loss or Clear.
    switch self.state.application {
    case .active(let receipt):
      self.state.heldWhileApplying = receipt
      self.phaseBeforeApplying = self.state.application
    case .applying:
      break
    case .idle, .uncertain, .lost, .clearing, .failed:
      self.state.heldWhileApplying = nil
      self.phaseBeforeApplying = self.state.application
    }
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
          receipt.sessionGeneration >= currentReadySession.generation else {
      return .staleGeneration
    }
    // The bridge started a newer session for this exact request (it does after a
    // Clear, so older acknowledgements cannot reactivate). The receipt proves the
    // location applied on that session; the session is adopted below.
    let adoptsNewerSession = receipt.sessionGeneration > currentReadySession.generation

    guard receipt.transport == currentReadySession.transport else {
      return .requestMismatch
    }
    guard adoptsNewerSession
            || currentReadySession.endpointClass == .unresolved
            || receipt.endpointClass == currentReadySession.endpointClass else {
      return .requestMismatch
    }

    // Validate outcome
    switch receipt.outcome {
    case .applied:
      if adoptsNewerSession {
        // Same provisional endpoint rule as below: only the published connection
        // carries the acknowledged class; later lane fallbacks stay acceptable.
        self.currentReadySession = LocationSessionIdentity(
          stableDeviceID: currentReadySession.stableDeviceID,
          transport: currentReadySession.transport,
          endpointClass: currentReadySession.endpointClass,
          generation: receipt.sessionGeneration
        )
        self.state.connection = .ready(identity: LocationSessionIdentity(
          stableDeviceID: currentReadySession.stableDeviceID,
          transport: currentReadySession.transport,
          endpointClass: receipt.endpointClass,
          generation: receipt.sessionGeneration
        ))
      } else if currentReadySession.endpointClass == .unresolved {
        // Only provider acknowledgement may resolve a provisional endpoint.
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
    // Restore what was true before this application: the active location it began
    // over, or the earlier phase. Restoring the last receipt as active after a failure
    // claimed a location the helper had already ended (review 2026-11-01).
    state.application = phaseBeforeApplying
      ?? state.lastAcknowledgedReceipt.map(LocationApplicationPhase.active)
      ?? .idle
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
    // Connection-class rejections are not one-off failures: the channel to the
    // device is gone, so the connection becomes failed and the application
    // becomes uncertain while the last receipt is preserved (PRODUCT_REQUIREMENTS §4.2, §7.3).
    if let injectionError = error as? LocationInjectionError {
      switch injectionError {
      case .tunneldNotRunning, .deviceNotFound, .endpointUnreachable:
        connectionLost(reason: errorText)
        return nil
      default:
        break
      }
    }
    // The phone dropped out of usbmux: connection loss by definition.
    switch error as? PersistentLocationBridge.PersistentBridgeError {
    case .deviceNotVisible?, .localNetworkBlocked?:
      // Not visible, or macOS blocks the helper's local network: no path to the phone.
      connectionLost(reason: errorText)
      return nil
    default:
      break
    }
    // The default five-mode path surfaces provider failures as PersistentBridgeError
    // carrying raw provider text (the socket helper does not type them). Recognize the
    // connection-loss signatures in that text so the primary path cannot report a
    // healthy connection over a dead endpoint (2026-10-24 false-connected incident;
    // found blocking by independent review 2026-10-25).
    if let bridgeError = error as? PersistentLocationBridge.PersistentBridgeError,
       let classified = DevLocationBridge.classifyProviderOutput(bridgeError.localizedDescription),
       classified.isConnectionLoss {
      connectionLost(reason: errorText)
      return nil
    }
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

  /// The user stopped the device connection, which ended the held location on the
  /// device (closing the DVT session is the real clear). Unlike a loss, the outcome
  /// is known: nothing is applied, there is no receipt to restore, and the desired
  /// location is kept so Move can apply it again.
  func locationEndedByStop() {
    self.pendingRequest = nil
    self.state.lastAcknowledgedReceipt = nil
    self.state.application = .idle
    self.state.movement = .idle
  }

  /// Signal connection lost, preserving desired state.
  /// Nils pendingRequest so late accept/reject returns noPending.
  /// During a Clear only the connection dimension changes: the Clear owns the location
  /// dimension until it returns (it commits idle when the injector confirmed it, failed
  /// otherwise). A loss that moved the phase off `.clearing` mid-await wedged a Clear the
  /// helper had confirmed and let `beginApplication` past its Clear guard (live 2026-11-01).
  func connectionLost(reason: String) {
    self.previousSession = self.currentReadySession ?? self.previousSession
    self.currentReadySession = nil
    self.pendingRequest = nil
    self.state.connection = .failed(reason)
    self.connectionFailureEpoch &+= 1

    if case .moving(let mode) = self.state.movement {
      self.state.movement = .paused(mode)
    }

    if case .clearing = self.state.application { return }
    self.state.application = .uncertain(
      lastReceipt: self.state.lastAcknowledgedReceipt,
      reason: reason
    )
  }

  /// Reconnects the same stable device and reapplies the desired coordinate.
  /// A movement the loss paused ends (idle) once a current-generation receipt is applied:
  /// AppState cancels every movement engine on a loss, so restoring `.moving` showed a run
  /// with no worker (§4.4). The location holds; the user starts movement again.
  /// `prepareSession` readies the device for injection after the session is rebuilt and
  /// before the reapply (the Developer Disk Image mount: with none mounted the DVT command
  /// completes and the phone does not move). It throwing is a failed attempt; the
  /// connection stays reconnecting until a reapply is acknowledged.
  func recover(
    strategy: ReconnectionStrategy,
    sleeper: any RecoverySleeping = TaskRecoverySleeper(),
    establishSession: @escaping @MainActor (
      _ attempt: Int,
      _ previousSession: LocationSessionIdentity?
    ) async throws -> LocationSessionIdentity,
    prepareSession: (@MainActor (_ candidate: LocationSessionIdentity) async throws -> Void)? = nil
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
        // A burst cancelled while it was rebuilding the session (Clear, Stop, Reconnect,
        // Move) must not send the location afterwards.
        try Task.checkCancellation()
        guard candidate.stableDeviceID == originalSession.stableDeviceID else {
          throw LocationSessionTransitionError.stableDeviceMismatch
        }
        guard candidate.generation > previous.generation else {
          throw LocationSessionTransitionError.staleGeneration
        }
        if let prepareSession {
          try await prepareSession(candidate)
          // Clear, Stop, Reconnect or Move during the preparation: send nothing.
          try Task.checkCancellation()
        }

        connectionReady(candidate)
        let request = try beginApplication()
        let receipt = try await injector.apply(request)
        if let transitionError = accept(receipt) {
          throw transitionError
        }

        switch state.movement {
        case .moving, .paused:
          state.movement = .idle
        case .idle, .completed:
          break
        }
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

    // A burst cancelled while its last helper command was out (Move, Reconnect, Clear,
    // Quit) did not run out of attempts: whoever cancelled it owns what happens next, so
    // it must not re-arm automatic reconnect behind them.
    if Task.isCancelled {
      finishRecoveryFailure(reason: "Recovery cancelled")
      return .recoveryCancelled
    }
    finishRecoveryFailure(reason: "Recovery exhausted")
    return .recoveryExhausted
  }

  private func finishRecoveryFailure(reason: String) {
    currentReadySession = nil
    pendingRequest = nil
    state.connection = .failed(reason)
    connectionFailureEpoch &+= 1
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

    // The helper picks its own lane; a restored session must accept a later receipt
    // over another one (review 2026-11-01). The published connection keeps the
    // restored class until a receipt says otherwise.
    currentReadySession = LocationSessionIdentity(
      stableDeviceID: identity.stableDeviceID,
      transport: identity.transport,
      endpointClass: .unresolved,
      generation: identity.generation
    )
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
  /// A Clear the injector confirmed (it returned without throwing) is device truth: the
  /// device holds no simulated location, so the location dimension becomes idle even if
  /// the ready session changed during the await (a connection loss or a re-selected
  /// device, live 2026-11-01). A connection loss leaves the phase `.clearing`
  /// (`connectionLost`) and only fails the connection dimension, which this method does
  /// not touch. Movement stays as Clear's caller set it.
  /// On success: sets desiredLocation=nil, lastAcknowledgedReceipt=nil, heldWhileApplying=nil,
  /// application=.idle, pending=nil, returns nil.
  /// On failure: retains desired/ack/connection/movement, sets failed, returns clearFailed.
  /// Callers must not begin an application while a Clear is awaited (AppState gates every
  /// path on its Clear task): the confirmed Clear overwrites whatever phase it finds.
  func clear(targetSession: LocationSessionIdentity? = nil) async -> LocationSessionTransitionError? {
    lastClearTarget = targetSession ?? self.currentReadySession
    guard let currentReadySession = lastClearTarget else {
      return .clearUnavailable
    }

    self.state.application = .clearing

    do {
      let target = LocationInjectionTarget(
        stableDeviceID: currentReadySession.stableDeviceID,
        transport: currentReadySession.transport
      )
      try await injector.clear(target: target, session: currentReadySession)
      commitConfirmedClear()
      return nil
    } catch LocationInjectionError.noHeldSession {
      // Nothing was sent: the injector holds no session for this identity. The phase
      // stays `.clearing` for the caller, which asks the helper and commits with
      // `commitConfirmedClear`, `commitClearWithoutHeldSession` or `failClear`.
      return .noHeldSession
    } catch {
      failClear(reason: error.localizedDescription)
      return .clearFailed
    }
  }

  /// The device holds no simulated location (a Clear the injector or the helper
  /// confirmed): the location dimension is idle and nothing is desired or held.
  func commitConfirmedClear() {
    self.state.desiredLocation = nil
    self.state.lastAcknowledgedReceipt = nil
    self.state.heldWhileApplying = nil
    self.state.application = .idle
    self.pendingRequest = nil
    self.phaseBeforeApplying = nil
  }

  /// A Clear of a session this Mac never held, after the helper confirmed it holds no
  /// connection to the phone. The held session ended with that connection, but nothing
  /// confirmed it on the phone, so the location is uncertain with no receipt: nothing is
  /// claimed held, nothing is reapplied (no receipt, no desired location), and Clear
  /// stays available once the phone is connected again (PRODUCT_REQUIREMENTS 4.2, 5.2).
  func commitClearWithoutHeldSession(reason: String) {
    self.state.desiredLocation = nil
    self.state.lastAcknowledgedReceipt = nil
    self.state.heldWhileApplying = nil
    self.state.application = .uncertain(lastReceipt: nil, reason: reason)
    self.pendingRequest = nil
    self.phaseBeforeApplying = nil
  }

  /// A Clear that did not complete: desired, receipt, connection and movement stay.
  func failClear(reason: String) {
    self.state.application = .failed(reason)
  }
}
