//
//  AppState+Testing.swift
//  PathChanger
//

import SwiftUI
import Combine

#if DEBUG
@MainActor
extension AppState {
    func testSetTransientRecoveryHandler(_ handler: @escaping (String) async -> Bool) {
        debugTransientRecoveryHandler = handler
    }

    func testSetSkipsDeviceRefreshDuringTransientRecovery(_ skip: Bool) {
        debugSkipDeviceRefreshDuringTransientRecovery = skip
    }

    func testCaptureResumableSessionSnapshot(mode: SimulationModeType) {
        captureResumableSessionSnapshot(mode: mode)
    }

    func testBeginTransientTransportRecovery(reason: String) {
        beginTransientTransportRecovery(reason: reason)
    }

    var testHasTransientRecoveryTask: Bool {
        transientRecoveryTask != nil
    }
}
#endif