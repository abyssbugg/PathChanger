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
}
