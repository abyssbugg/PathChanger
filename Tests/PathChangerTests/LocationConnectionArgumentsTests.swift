import XCTest
@testable import PathChanger

final class LocationConnectionArgumentsTests: XCTestCase {
    func testStartTunnelUsesRsdNotTunnelFlag() {
        XCTAssertEqual(
            LocationConnectionArguments.make(
                deviceId: "00000000-0000000000000001",
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
                deviceId: "00000000-0000000000000001",
                isDaemonTunneld: true,
                rsdAddress: "fddf:4f3f:cd60::1",
                rsdPort: 52569
            ),
            ["--tunnel", "00000000-0000000000000001"]
        )
    }

    func testFallbackToUdidWhenNoRsd() {
        XCTAssertEqual(
            LocationConnectionArguments.make(
                deviceId: "00000000-0000000000000001",
                isDaemonTunneld: false,
                rsdAddress: nil,
                rsdPort: nil
            ),
            ["--udid", "00000000-0000000000000001"]
        )
    }

    func testClassifiesDirectAndRemoteConnectionArguments() {
        XCTAssertEqual(
            LocationConnectionArguments.classify(arguments: ["--udid", "device"], physicalTransport: .usb).endpointClass,
            .direct
        )
        XCTAssertEqual(
            LocationConnectionArguments.classify(arguments: ["--rsd", "host", "1234"], physicalTransport: .wifi).endpointClass,
            .remoteServiceDiscovery
        )
        XCTAssertEqual(
            LocationConnectionArguments.classify(arguments: ["--tunnel", "device"], physicalTransport: .wifi).endpointClass,
            .remoteServiceDiscovery
        )
    }

    func testDVTChannelMapsOnlyKnownChannelsToEndpointClasses() {
        XCTAssertEqual(LocationDVTChannel.usbLockdown.endpointClass, .direct)
        XCTAssertEqual(LocationDVTChannel.networkLockdown.endpointClass, .direct)
        XCTAssertEqual(LocationDVTChannel.nativeRSD.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(LocationDVTChannel.userspaceRSD.endpointClass, .remoteServiceDiscovery)
        XCTAssertNil(LocationDVTChannel(rawValue: "future-channel").endpointClass)
    }

    func testDVTChannelDecodesUnknownFutureValueWithoutAcceptingIt() throws {
        let data = Data("\"future-channel\"".utf8)
        let channel = try JSONDecoder().decode(LocationDVTChannel.self, from: data)
        XCTAssertEqual(channel.rawValue, "future-channel")
        XCTAssertFalse(channel.isSupported)
    }

    func testReceiptBuiltFromProviderAcknowledgementUsesActualChannel() throws {
        let requestID = UUID()
        let coordinate = LocationCoordinate(latitude: 37.33182, longitude: -122.03118)
        let acknowledgement = try XCTUnwrap(LocationProviderAcknowledgement(
            requestID: requestID,
            sessionGeneration: 11,
            physicalTransport: .wifi,
            channel: .nativeRSD,
            endpointClass: .remoteServiceDiscovery
        ))

        let receipt = LocationInjectionReceipt(
            session: UUID(),
            acknowledgedCoordinate: coordinate,
            acknowledgement: acknowledgement,
            completedAt: Date(timeIntervalSince1970: 1_789_000_000),
            outcome: .applied
        )

        XCTAssertEqual(receipt.requestID, requestID)
        XCTAssertEqual(receipt.sessionGeneration, 11)
        XCTAssertEqual(receipt.transport, .wifi)
        XCTAssertEqual(receipt.actualChannel, .nativeRSD)
        XCTAssertEqual(receipt.endpointClass, .remoteServiceDiscovery)
        XCTAssertEqual(receipt.coordinate, coordinate)
    }

    func testProviderAcknowledgementRequiresSupportedConsistentChannel() {
        let requestID = UUID()
        let accepted = LocationProviderAcknowledgement(
            requestID: requestID, sessionGeneration: 4, physicalTransport: .wifi,
            channel: .nativeRSD, endpointClass: .remoteServiceDiscovery
        )
        XCTAssertEqual(accepted?.requestID, requestID)
        XCTAssertEqual(accepted?.physicalTransport, .wifi)
        XCTAssertEqual(accepted?.channel, .nativeRSD)
        XCTAssertNil(LocationProviderAcknowledgement(
            requestID: requestID, sessionGeneration: 4, physicalTransport: .wifi,
            channel: .nativeRSD, endpointClass: .direct
        ))
        XCTAssertNil(LocationProviderAcknowledgement(
            requestID: requestID, sessionGeneration: 4, physicalTransport: .wifi,
            channel: LocationDVTChannel(rawValue: "future-channel"),
            endpointClass: .remoteServiceDiscovery
        ))
    }
}
