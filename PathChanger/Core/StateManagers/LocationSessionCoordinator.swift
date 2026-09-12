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
  
  init(injector: any LocationInjecting) {
    self.injector = injector
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
    
    // Validate outcome
    switch receipt.outcome {
    case .applied:
      // Only .applied may activate
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
  
  /// Signal connection ready, storing the session identity for later use.
  func connectionReady(_ session: LocationSessionIdentity) {
    self.currentReadySession = session
    self.state.connection = .ready(identity: session)
  }
  
  /// Signal connection lost, preserving desired state.
  /// Nils pendingRequest so late accept/reject returns noPending.
  func connectionLost(reason: String) {
    self.previousSession = self.currentReadySession
    self.currentReadySession = nil
    self.pendingRequest = nil
    self.state.connection = .failed(reason)
    
    // Preserve desired location and last receipt, set application to uncertain
    if let lastReceipt = self.state.lastAcknowledgedReceipt {
      self.state.application = .uncertain(lastReceipt: lastReceipt, reason: reason)
    } else {
      self.state.application = .uncertain(lastReceipt: nil, reason: reason)
    }
  }
  
  /// Begin recovery with exact attempt number.
  func beginRecovery(attempt: Int) {
    self.state.connection = .reconnecting(previousGeneration: previousSession?.generation, attempt: attempt)
  }
  
  /// Clear state and target.
  /// Requires currentReadySession (device/session).
  /// Sets clearing phase before awaiting injector.
  /// Snapshots ready session and marks `.clearing`.
  /// Prevents `beginApplication` while clearing with a typed transition error.
  /// After await, before success/failure mutation, verifies the operation is still current:
  /// same ready identity and state remains clearing. If connection/mode/application state changed,
  /// does not overwrite newer state; returns a typed superseded/stale error.
  /// Connection loss during clear must remain failed/uncertain when clear returns.
  /// On success: sets desiredLocation=nil, lastAcknowledgedReceipt=nil, application=.idle, pending=nil.
  /// On failure: retains desired/ack/connection/movement, sets failed, returns clearFailed.
  func clear() async -> LocationSessionTransitionError? {
    guard let currentReadySession else {
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
