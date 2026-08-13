// Tests/PathChangerTests/FileDescriptorLeakTests.swift
// Unit tests for file descriptor leak prevention

import XCTest
@testable import PathChanger

final class FileDescriptorLeakTests: XCTestCase {

    /// Monitor open file descriptors
    private var initialFDCount: Int32 = 0

    override func setUp() {
        super.setUp()
        // Record initial FD count
        initialFDCount = Int32(Darwin.getdtablesize())
    }

    /// Test that file descriptor counts remain stable
    func testFileDescriptorCountStability() async throws {
        // This test verifies that running operations multiple times doesn't accumulate FDs

        // App-hosted tests render the map in parallel. Let GeoServices finish opening
        // its long-lived resource packs before taking the leak-test baseline.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let initialDescriptors = getOpenFileDescriptors()

        // Simulate multiple coordinate operations (which internally work with FDs)
        for i in 0..<10 {
            let coord = LocationCoordinate(latitude: Double(i), longitude: Double(i * 2))
            _ = coord.formattedString

            autoreleasepool {
                // Keep the test's own Process descriptors deterministic.
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/echo")
                task.arguments = ["test_\(i)"]
                task.standardInput = FileHandle.nullDevice
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    // Ignore process errors, we're just testing FD cleanup
                }
            }
        }

        // Allow some time for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let finalDescriptors = getOpenFileDescriptors()
        let leakedDescriptors = finalDescriptors.subtracting(initialDescriptors).sorted()
        let leakedDescriptions = leakedDescriptors.map(describeFileDescriptor)

        // FD count should not grow significantly
        // Allow some tolerance (5 FDs) for system variations
        XCTAssertLessThanOrEqual(
            leakedDescriptors.count,
            5,
            "File descriptors leaked during operations: \(leakedDescriptions)"
        )
    }

    private func getOpenFileDescriptors() -> Set<Int32> {
        Set((0..<Int32(Darwin.getdtablesize())).filter { fd in
            var statInfo = stat()
            return fstat(fd, &statInfo) == 0
        })
    }

    private func describeFileDescriptor(_ fd: Int32) -> String {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        if fcntl(fd, F_GETPATH, &path) == 0 {
            return "\(fd):\(String(cString: path))"
        }

        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0 else {
            return "\(fd):closed"
        }

        switch statInfo.st_mode & S_IFMT {
        case S_IFIFO:
            return "\(fd):pipe"
        case S_IFSOCK:
            return "\(fd):socket"
        case S_IFCHR:
            return "\(fd):character-device"
        default:
            return "\(fd):mode-\(statInfo.st_mode & S_IFMT)"
        }
    }
}
