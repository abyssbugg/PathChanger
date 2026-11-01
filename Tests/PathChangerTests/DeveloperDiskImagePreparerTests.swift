import XCTest
@testable import PathChanger

final class DeveloperDiskImagePreparerTests: XCTestCase {
    func testMountStatusEmptyArrayMeansNotMounted() async throws {
        let preparer = DeveloperDiskImagePreparer(runner: { _ in "[]" })
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: "00008130-001234567890ABCD")
        XCTAssertFalse(mounted)
    }

    func testMountStatusWithEntryMeansMounted() async throws {
        let preparer = DeveloperDiskImagePreparer(
            runner: { _ in "[{\"image\":\"DeveloperDiskImage\"}]" })
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: "00008130-001234567890ABCD")
        XCTAssertTrue(mounted)
    }

    func testEnsureMountedRunsAutoMountWhenNotMounted() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("list") { return "[]" }
            return "DeveloperDiskImage mounted successfully"
        })
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        XCTAssertTrue(commands.contains { $0.contains("auto-mount") })
    }

    func testEnsureMountedSkipsAutoMountWhenAlreadyMounted() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("list") { return "[{\"image\":\"DeveloperDiskImage\"}]" }
            return ""
        })
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        XCTAssertFalse(commands.contains { $0.contains("auto-mount") })
    }

    func testEnsureMountedCachesPerUDID() async throws {
        var listCalls = 0
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            if command.contains("list") { listCalls += 1; return "[]" }
            return "DeveloperDiskImage mounted successfully"
        })
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        XCTAssertEqual(listCalls, 1)  // second call served from cache
    }

    func testAlreadyMountedStatusIsCachedUntilForgotten() async throws {
        // Live 2026-11-01: an already-mounted image was never cached, so every Jump hop,
        // route point and joystick tick ran `mounter list` first (measured 1.1-1.2 s).
        var listCalls = 0
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            if command.contains("list") { listCalls += 1; return "[{\"ImageType\": \"Personalized\"}]" }
            XCTFail("must not mount an already-mounted image: \(command)")
            return ""
        })
        let udid = "00008130-001234567890ABCD"
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(listCalls, 1)

        // A lost connection (e.g. a reboot unmounts the image) re-checks next time.
        await preparer.forget(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(listCalls, 2)
    }
}
