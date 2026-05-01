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
        
        let initialFDs = getOpenFDCount()
        
        // Simulate multiple coordinate operations (which internally work with FDs)
        for i in 0..<10 {
            let coord = LocationCoordinate(latitude: Double(i), longitude: Double(i * 2))
            _ = coord.formattedString
            
            // Simulate doing work that would normally leak FDs if not cleaned up
            let task = Process()
            task.launchPath = "/bin/echo"
            task.arguments = ["test_\(i)"]
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                // Ignore process errors, we're just testing FD cleanup
            }
        }
        
        // Allow some time for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let finalFDs = getOpenFDCount()
        
        // FD count should not grow significantly
        // Allow some tolerance (5 FDs) for system variations
        XCTAssertLessThanOrEqual(finalFDs - initialFDs, 5, "File descriptors leaked during operations")
    }
    
    /// Helper to count open file descriptors
    private func getOpenFDCount() -> Int32 {
        var count: Int32 = 0
        for fd in 0..<Int32(Darwin.getdtablesize()) {
            var stat_info = stat()
            if fstat(fd, &stat_info) == 0 {
                count += 1
            }
        }
        return count
    }
}
