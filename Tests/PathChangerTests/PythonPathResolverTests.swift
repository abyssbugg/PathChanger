//
//  PythonPathResolverTests.swift
//  PathChangerTests
//
//  Unit tests for PythonPathResolver
//

import XCTest
@testable import PathChanger

final class PythonPathResolverTests: XCTestCase {
    
    func testPathIsNotEmpty() {
        let path = PythonPathResolver.path
        XCTAssertFalse(path.isEmpty, "Python path should not be empty")
    }
    
    func testPathIsAbsolute() {
        let path = PythonPathResolver.path
        XCTAssertTrue(path.hasPrefix("/"), "Python path should be absolute")
    }
    
    func testIsAvailable() {
        // On most macOS systems, Python 3 should be available
        // This test may fail on systems without Python 3 installed
        XCTAssertTrue(PythonPathResolver.isAvailable, "Python 3 should be available on this system")
    }
    
    func testRefreshReturnsPath() {
        let path = PythonPathResolver.refresh()
        XCTAssertFalse(path.isEmpty, "Refresh should return a valid path")
    }
    
    func testConsistentPath() {
        let path1 = PythonPathResolver.path
        let path2 = PythonPathResolver.path
        XCTAssertEqual(path1, path2, "Path should be consistent between calls")
    }
    
    func testVersionAsync() async {
        let version = await PythonPathResolver.version()
        
        if PythonPathResolver.isAvailable {
            XCTAssertNotNil(version, "Version should be available if Python is installed")
            XCTAssertTrue(version?.contains("Python") ?? false, "Version should contain 'Python'")
        }
    }
}
