import XCTest
@testable import PathChanger

final class LocationConnectionArgumentsTests: XCTestCase {
    func testStartTunnelUsesRsdNotTunnelFlag() {
        XCTAssertEqual(
            LocationConnectionArguments.make(
                deviceId: "00008130-000C5144019A001C",
                isDaemonTunneld: false,
                rsdAddress: "fddf:4f3f:cd60::1",
                rsdPort: 52569
            ),
            ["--rsd", "fddf:4f3f:cd60::1", "52569"]
        )
    }

    func testDaemonUsesTunnelFlag() {
        XCTAssertEqual(
            LocationConnectionArguments.make(
                deviceId: "00008130-000C5144019A001C",
                isDaemonTunneld: true,
                rsdAddress: "fddf:4f3f:cd60::1",
                rsdPort: 52569
            ),
            ["--tunnel", "00008130-000C5144019A001C"]
        )
    }

    func testFallbackToUdidWhenNoRsd() {
        XCTAssertEqual(
            LocationConnectionArguments.make(
                deviceId: "00008130-000C5144019A001C",
                isDaemonTunneld: false,
                rsdAddress: nil,
                rsdPort: nil
            ),
            ["--udid", "00008130-000C5144019A001C"]
        )
    }
}
