import XCTest
@testable import PathChanger

@MainActor
final class LocationSessionCoordinatorTests: XCTestCase {

  var coordinator: LocationSessionCoordinator!
  fileprivate var fakeInjector: FakeLocationInjector!

  // MARK: - Persistent-Bridge Error Mapping on Reject

  func test_reject_withPersistentBridgeConnectionLossText_marksConnectionFailed() throws {
    // The default five-mode path surfaces provider failures as PersistentBridgeError
    // with raw provider text; the coordinator must recognize the connection-loss
    // signatures in that text instead of treating them as generic failures
    // (the false-connected defect from the 2026-10-24 live incident).
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()

    _ = coordinator.reject(
      requestID: request.id,
      error: PersistentLocationBridge.PersistentBridgeError.bridgeError("OSError: [Errno 65] No route to host")
    )

    guard case .failed = coordinator.state.connection else {
      return XCTFail("Expected connection .failed for persistent-bridge connection loss")
    }
    guard case .uncertain = coordinator.state.application else {
      return XCTFail("Expected application .uncertain for persistent-bridge connection loss")
    }
  }

  func test_reject_withPersistentBridgeGenericError_keepsConnectionReady() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()

    _ = coordinator.reject(
      requestID: request.id,
      error: PersistentLocationBridge.PersistentBridgeError.bridgeError("some unrelated provider error")
    )

    XCTAssertEqual(coordinator.state.connection, .ready(identity: identity))
    guard case .failed = coordinator.state.application else {
      return XCTFail("Expected application .failed for generic bridge rejection")
    }
  }
  
  override func setUp() {
    super.setUp()
    fakeInjector = FakeLocationInjector()
    coordinator = LocationSessionCoordinator(injector: fakeInjector)
  }
  
  // MARK: - Connection-Loss Propagation on Reject

  func test_reject_withEndpointUnreachable_marksConnectionFailedAndApplicationUncertain() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()

    _ = coordinator.reject(requestID: request.id, error: LocationInjectionError.endpointUnreachable)

    guard case .failed = coordinator.state.connection else {
      return XCTFail("Expected connection .failed after connection-loss rejection")
    }
    guard case .uncertain(let receipt, _) = coordinator.state.application else {
      return XCTFail("Expected application .uncertain after connection-loss rejection")
    }
    XCTAssertNil(receipt)
  }

  func test_reject_withDeviceNotFound_marksConnectionFailedAndApplicationUncertain() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()

    _ = coordinator.reject(requestID: request.id, error: LocationInjectionError.deviceNotFound)

    guard case .failed = coordinator.state.connection else {
      return XCTFail("Expected connection .failed after deviceNotFound rejection")
    }
    guard case .uncertain = coordinator.state.application else {
      return XCTFail("Expected application .uncertain after deviceNotFound rejection")
    }
  }

  func test_reject_withGenericError_keepsConnectionReadyAndApplicationFailed() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()

    _ = coordinator.reject(requestID: request.id, error: LocationInjectionError.injectionFailed("boom"))

    XCTAssertEqual(coordinator.state.connection, .ready(identity: identity))
    guard case .failed = coordinator.state.application else {
      return XCTFail("Expected application .failed for generic rejection")
    }
  }

  // MARK: - State Initialization

  func test_initialState_isIdle() {
    XCTAssertEqual(coordinator.state.application, .idle)
    XCTAssertEqual(coordinator.state.movement, .idle)
    XCTAssertNil(coordinator.state.desiredLocation)
  }
  
  // MARK: - Select Target and Mode
  
  func test_select_withTeleportMode_setsDesiredTargetAndMode() {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    
    coordinator.select(coordinate, mode: .teleport)
    
    XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
    XCTAssertEqual(coordinator.state.application, .idle)
  }
  
  // MARK: - Begin Application After Connection
  
  func test_beginApplication_beforeConnectionReady_throwsNoReadySession() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    XCTAssertThrowsError(try coordinator.beginApplication()) { error in
      XCTAssertEqual(error as? LocationSessionTransitionError, .noReadySession)
    }
  }
  
  func test_beginApplication_withReadySessionButNoDesiredLocation_throwsNoDesiredLocation() throws {
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    XCTAssertThrowsError(try coordinator.beginApplication()) { error in
      XCTAssertEqual(error as? LocationSessionTransitionError, .noDesiredLocation)
    }
  }
  
  func test_beginApplication_afterConnectionReady_returnsRequestWithSelectedTarget() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    
    XCTAssertEqual(request.coordinate, coordinate)
    XCTAssertEqual(request.mode, .teleport)
  }
  
  func test_beginApplication_setsApplicationToApplying() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    
    guard case .applying(let requestID, let targetCoord) = coordinator.state.application else {
      XCTFail("Expected .applying state after beginApplication")
      return
    }
    
    XCTAssertEqual(requestID, request.id)
    XCTAssertEqual(targetCoord, coordinate)
  }
  
  func test_beginApplication_throwsBeginApplicationDuringClearing() async throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    _ = coordinator.accept(receipt)
    
    await fakeInjector.setShouldBlockClear(true)
    let clearTask = Task {
      return await coordinator.clear()
    }
    
    // Wait for clear to enter blocking state
    try await fakeInjector.waitForClearEntered()
    
    XCTAssertThrowsError(try coordinator.beginApplication()) { error in
      XCTAssertEqual(error as? LocationSessionTransitionError, .beginApplicationDuringClearing)
    }
    
    await fakeInjector.releaseClear()
    _ = await clearTask.value
  }
  
  // MARK: - Accept Receipt
  
  func test_accept_afterBeginApplication_activatesApplicationState() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    
    let error = coordinator.accept(receipt)
    
    XCTAssertNil(error)
    guard case .active = coordinator.state.application else {
      XCTFail("Expected .active state after accept")
      return
    }
    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
  }
  
  func test_accept_withRequestMismatch_returnsError() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: UUID(),
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error for request mismatch")
      return
    }
    guard case .requestMismatch = error else {
      XCTFail("Expected .requestMismatch error, got \(error)")
      return
    }
  }
  
  func test_accept_withCoordinateMismatch_returnsCoordinateMismatchError() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let differentCoord = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: differentCoord,
      completedAt: Date(),
      outcome: .applied
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error for coordinate mismatch")
      return
    }
    guard case .coordinateMismatch = error else {
      XCTFail("Expected .coordinateMismatch error, got \(error)")
      return
    }
  }
  
  func test_accept_withQueuedOutcome_doesNotActivate() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .queued
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error for queued outcome")
      return
    }
    guard case .receiptNotApplied = error else {
      XCTFail("Expected .receiptNotApplied error, got \(error)")
      return
    }
    
    // Verify application remains in applying state
    guard case .applying = coordinator.state.application else {
      XCTFail("Expected .applying state to remain after queued receipt")
      return
    }
    
    // Verify pending request is not consumed
    XCTAssertNil(coordinator.state.lastAcknowledgedReceipt)
  }
  
  func test_accept_withFailedOutcome_doesNotActivate() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .failed(code: "Device error")
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error for failed outcome")
      return
    }
    guard case .applicationFailed = error else {
      XCTFail("Expected .applicationFailed error, got \(error)")
      return
    }
    
    // Verify application is set to failed
    guard case .failed = coordinator.state.application else {
      XCTFail("Expected .failed state after failed receipt")
      return
    }
    
    // Verify pending request is consumed
    XCTAssertNil(coordinator.state.lastAcknowledgedReceipt)
  }
  
  func test_accept_withoutPendingRequest_returnsNoPendingRequest() {
    let receipt = LocationInjectionReceipt(
      requestID: UUID(),
      session: UUID(),
      coordinate: LocationCoordinate(latitude: 37.7749, longitude: -122.4194),
      completedAt: Date(),
      outcome: .applied
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error when no pending request")
      return
    }
    guard case .noPendingRequest = error else {
      XCTFail("Expected .noPendingRequest error, got \(error)")
      return
    }
  }
  
  // MARK: - Connection Lost
  
  func test_connectionLost_nilsPendingRequest() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    
    coordinator.connectionLost(reason: "Device disconnected")
    
    // Try to accept after connection lost
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    
    let error = coordinator.accept(receipt)
    guard let error = error else {
      XCTFail("Expected error when pending request is nil after connection lost")
      return
    }
    guard case .noPendingRequest = error else {
      XCTFail("Expected .noPendingRequest error, got \(error)")
      return
    }
  }
  
  // MARK: - Clear and Reentrancy
  
  func test_clear_success_clearsState() async throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    _ = coordinator.accept(receipt)
    
    let error = await coordinator.clear()
    
    XCTAssertNil(error)
    XCTAssertNil(coordinator.state.desiredLocation)
    XCTAssertNil(coordinator.state.lastAcknowledgedReceipt)
    guard case .idle = coordinator.state.application else {
      XCTFail("Expected .idle state after successful clear")
      return
    }
  }
  
  func test_clear_failure_retainsState() async throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    _ = coordinator.accept(receipt)
    
    await fakeInjector.setShouldFailClear(true)
    
    let error = await coordinator.clear()
    
    guard let error = error as? LocationSessionTransitionError else {
      XCTFail("Expected LocationSessionTransitionError")
      return
    }
    guard case .clearFailed = error else {
      XCTFail("Expected .clearFailed error")
      return
    }
    
    guard case .failed = coordinator.state.application else {
      XCTFail("Expected .failed state after clear failure")
      return
    }
    
    XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
  }
  
  func test_clear_withConnectionLossDuringClear_remainsFailedUncertain() async throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    _ = coordinator.accept(receipt)
    
    await fakeInjector.setShouldBlockClear(true)
    
    let clearTask = Task {
      return await coordinator.clear()
    }
    
    // Wait for clear to enter blocking state
    try await fakeInjector.waitForClearEntered()
    
    // Simulate connection loss while clearing
    coordinator.connectionLost(reason: "Device disconnected during clear")
    
    // Verify state is uncertain/failed
    guard case .uncertain = coordinator.state.application else {
      XCTFail("Expected .uncertain state after connection lost during clear")
      await fakeInjector.releaseClear()
      _ = await clearTask.value
      return
    }
    
    await fakeInjector.releaseClear()
    
    let clearError = await clearTask.value
    
    // Clear should return staleGeneration because state changed
    guard let clearError = clearError as? LocationSessionTransitionError else {
      XCTFail("Expected LocationSessionTransitionError from clear")
      return
    }
    guard case .staleGeneration = clearError else {
      XCTFail("Expected .staleGeneration error when state changed during clear")
      return
    }
    
    // Verify state remains uncertain/failed, not overwritten to idle
    guard case .uncertain = coordinator.state.application else {
      XCTFail("Expected .uncertain state to remain after clear returns staleGeneration")
      return
    }
  }
  
  func testAcceptRejectsReceiptFromStaleGeneration() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    coordinator.select(coordinate, mode: .teleport)
    
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .wifi,
      endpointClass: .direct,
      generation: 1
    )
    coordinator.connectionReady(identity)
    
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      sessionGeneration: identity.generation,
      completedAt: Date(),
      outcome: .applied
    )
    
    coordinator.connectionReady(LocationSessionIdentity(
      stableDeviceID: identity.stableDeviceID,
      transport: identity.transport,
      endpointClass: identity.endpointClass,
      generation: 2
    ))

    let error = coordinator.accept(receipt)
    XCTAssertEqual(error, .staleGeneration)
    XCTAssertFalse(coordinator.state.application.isActive)
  }


  func test_cancelPendingApplication_restoresLastAcknowledgedReceipt() throws {
    let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
    let identity = LocationSessionIdentity(stableDeviceID: "device-123", transport: .usb, endpointClass: .direct, generation: 1)
    coordinator.connectionReady(identity)
    coordinator.select(coordinate, mode: .joystick)
    let first = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(requestID: first.id, session: UUID(), coordinate: coordinate, transport: .usb, endpointClass: .direct, sessionGeneration: 1, completedAt: Date(), outcome: .applied)
    XCTAssertNil(coordinator.accept(receipt))
    coordinator.select(LocationCoordinate(latitude: 38, longitude: -123), mode: .joystick)
    let pending = try coordinator.beginApplication()
    XCTAssertNil(coordinator.cancelPendingApplication(requestID: pending.id))
    XCTAssertEqual(coordinator.state.application, .active(receipt: receipt))
    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
  }

  func testAcceptPromotesUnresolvedEndpointFromAppliedProviderReceipt() throws {
    let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
    let provisional = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .usb,
      endpointClass: .unresolved,
      generation: 7
    )
    coordinator.connectionReady(provisional)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: .usb,
      actualChannel: .nativeRSD,
      endpointClass: .remoteServiceDiscovery,
      sessionGeneration: 7,
      completedAt: Date(),
      outcome: .applied
    )

    XCTAssertNil(coordinator.accept(receipt))
    XCTAssertEqual(
      coordinator.state.connection,
      .ready(identity: LocationSessionIdentity(
        stableDeviceID: provisional.stableDeviceID,
        transport: provisional.transport,
        endpointClass: receipt.endpointClass,
        generation: provisional.generation
      ))
    )
    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
  }

  func testAcceptRejectsEndpointReplacementAfterProviderTruthResolved() throws {
    let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
    let resolved = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .usb,
      endpointClass: .direct,
      generation: 8
    )
    coordinator.connectionReady(resolved)
    coordinator.select(coordinate, mode: .teleport)
    let request = try coordinator.beginApplication()
    let receipt = LocationInjectionReceipt(
      requestID: request.id,
      session: UUID(),
      coordinate: coordinate,
      transport: .usb,
      actualChannel: .nativeRSD,
      endpointClass: .remoteServiceDiscovery,
      sessionGeneration: 8,
      completedAt: Date(),
      outcome: .applied
    )

    XCTAssertEqual(coordinator.accept(receipt), .requestMismatch)
    XCTAssertEqual(coordinator.state.connection, .ready(identity: resolved))
    XCTAssertNil(coordinator.state.lastAcknowledgedReceipt)
  }

  func testAdoptHeldSessionRestoresAcknowledgedTruthWithoutMovement() {
    let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
    let identity = LocationSessionIdentity(
      stableDeviceID: "device-123",
      transport: .usb,
      endpointClass: .remoteServiceDiscovery,
      generation: 9
    )
    let receipt = LocationInjectionReceipt(
      requestID: UUID(),
      session: UUID(),
      coordinate: coordinate,
      transport: .usb,
      actualChannel: .explicitRSD,
      endpointClass: .remoteServiceDiscovery,
      sessionGeneration: 9,
      completedAt: Date(),
      outcome: .applied
    )

    let error = coordinator.adoptHeldSession(identity: identity, receipt: receipt)

    XCTAssertNil(error)
    XCTAssertEqual(coordinator.state.connection, .ready(identity: identity))
    XCTAssertEqual(coordinator.state.application, .active(receipt: receipt))
    XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, receipt)
    XCTAssertEqual(coordinator.state.desiredLocation, coordinate)
    XCTAssertEqual(coordinator.state.movement, .idle)
  }
}
