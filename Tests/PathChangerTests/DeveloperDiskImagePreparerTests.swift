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

    // MARK: - usbmux miss → mobdev2 retry (live 2026-11-01: usbmux lost the Wi-Fi phone
    // for 3.5 min while Bonjour still reached it; `mounter list --mobdev2` worked).

    private let udid = "00008130-001234567890ABCD"
    private let usbmuxMiss =
        "pymobiledevice3.exceptions.DeviceNotFoundError: Device not found: usbmux has no device matching udid 00008130-001234567890ABCD"

    func testStatusRetriesOverMobdev2WhenUsbmuxCannotFindTheDevice() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { [usbmuxMiss] command in
            commands.append(command)
            if command.contains("--mobdev2") { return "[{\"ImageType\": \"Personalized\"}]" }
            return usbmuxMiss
        })
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: udid)
        XCTAssertTrue(mounted)
        XCTAssertEqual(commands, [
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            DevicePreparationPlanner.ddiMountStatusMobdev2Command(udid: udid),
        ])
    }

    func testStatusRetriesOverMobdev2WhenTheRunnerThrowsUsbmuxNotFound() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("--mobdev2") { return "[]" }
            throw DeviceError.commandFailed("NoDeviceConnectedError")
        })
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: udid)
        XCTAssertFalse(mounted)
        XCTAssertEqual(commands.last, DevicePreparationPlanner.ddiMountStatusMobdev2Command(udid: udid))
    }

    func testMountRetriesOverMobdev2WhenUsbmuxCannotFindTheDevice() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { [usbmuxMiss] command in
            commands.append(command)
            if command.contains("list") { return "[]" }
            if command.contains("--mobdev2") { return "DeveloperDiskImage mounted successfully" }
            return usbmuxMiss
        })
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
            DevicePreparationPlanner.ddiMountMobdev2Command(udid: udid),
        ])
    }

    func testOtherStatusFailuresAreNotRetried() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            return "InvalidServiceError: mobile_image_mounter unavailable"
        })
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected statusUnparseable")
        } catch DeveloperDiskImagePreparer.PreparationError.statusUnparseable(let output) {
            XCTAssertTrue(output.contains("InvalidServiceError"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [DevicePreparationPlanner.ddiMountStatusCommand(udid: udid)])
    }

    func testOtherThrownStatusErrorsAreNotRetried() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            throw DeviceError.commandFailed("Command timed out after 240.0 seconds")
        })
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected the runner error")
        } catch DeviceError.commandFailed(let message) {
            XCTAssertTrue(message.contains("timed out"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands.count, 1)
    }

    func testOtherMountFailuresAreNotRetried() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("list") { return "[]" }
            return "PersonalizationError: TSS request failed"
        })
        do {
            try await preparer.ensureMounted(udid: udid)
            XCTFail("expected mountFailed")
        } catch DeveloperDiskImagePreparer.PreparationError.mountFailed(let output) {
            XCTAssertTrue(output.contains("TSS request failed"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertFalse(commands.contains { $0.contains("--mobdev2") })
    }

    func testFailedMobdev2StatusRetrySurfacesTheRetryOutput() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { [usbmuxMiss] command in
            commands.append(command)
            if command.contains("--mobdev2") { return "NoDeviceConnectedError: mobdev2 found nothing" }
            return usbmuxMiss
        })
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected statusUnparseable")
        } catch DeveloperDiskImagePreparer.PreparationError.statusUnparseable(let output) {
            XCTAssertTrue(output.contains("mobdev2 found nothing"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands.count, 2)  // retried once, not again
    }

    func testFailedMobdev2MountRetrySurfacesTheRetryOutput() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { [usbmuxMiss] command in
            commands.append(command)
            if command.contains("list") { return "[]" }
            if command.contains("--mobdev2") { return "mobdev2 mount refused" }
            return usbmuxMiss
        })
        do {
            try await preparer.ensureMounted(udid: udid)
            XCTFail("expected mountFailed")
        } catch DeveloperDiskImagePreparer.PreparationError.mountFailed(let output) {
            XCTAssertTrue(output.contains("mobdev2 mount refused"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands.filter { $0.contains("auto-mount") }.count, 2)
    }

    func testMobdev2StatusResultIsCachedLikeAUsbmuxResult() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { [usbmuxMiss] command in
            commands.append(command)
            if command.contains("--mobdev2") { return "[{\"ImageType\": \"Personalized\"}]" }
            return usbmuxMiss
        })
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands.count, 2)  // one usbmux miss + one mobdev2 check, then cached
    }

    // MARK: - USB-only mode keeps the DDI gate off the network (review 2026-11-01 v2
    // issue 5: the mobdev2 retry ran in every mode, so a USB-only Move could reach the
    // phone over Wi-Fi). With the fallback disallowed a usbmux miss fails as before.

    func testStatusDoesNotRetryOverMobdev2WhenNetworkFallbackIsDisallowed() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { [usbmuxMiss] command in
                commands.append(command)
                if command.contains("--mobdev2") { return "[{\"ImageType\": \"Personalized\"}]" }
                return usbmuxMiss
            },
            allowsNetworkFallback: { false }
        )
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected statusUnparseable")
        } catch DeveloperDiskImagePreparer.PreparationError.statusUnparseable(let output) {
            XCTAssertTrue(output.contains("usbmux has no device matching udid"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [DevicePreparationPlanner.ddiMountStatusCommand(udid: udid)])
    }

    func testThrownStatusMissIsRethrownWhenNetworkFallbackIsDisallowed() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in
                commands.append(command)
                if command.contains("--mobdev2") { return "[]" }
                throw DeviceError.commandFailed("NoDeviceConnectedError")
            },
            allowsNetworkFallback: { false }
        )
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected the runner error")
        } catch DeviceError.commandFailed(let message) {
            XCTAssertTrue(message.contains("NoDeviceConnectedError"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [DevicePreparationPlanner.ddiMountStatusCommand(udid: udid)])
    }

    func testMountDoesNotRetryOverMobdev2WhenNetworkFallbackIsDisallowed() async {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { [usbmuxMiss] command in
                commands.append(command)
                if command.contains("list") { return "[]" }
                if command.contains("--mobdev2") { return "DeveloperDiskImage mounted successfully" }
                return usbmuxMiss
            },
            allowsNetworkFallback: { false }
        )
        do {
            try await preparer.ensureMounted(udid: udid)
            XCTFail("expected mountFailed")
        } catch DeveloperDiskImagePreparer.PreparationError.mountFailed(let output) {
            XCTAssertTrue(output.contains("usbmux has no device matching udid"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
        ])
    }

    func testStatusAndMountRetryOverMobdev2WhenNetworkFallbackIsAllowed() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { [usbmuxMiss] command in
                commands.append(command)
                if command.contains("--mobdev2") {
                    return command.contains("list") ? "[]" : "DeveloperDiskImage mounted successfully"
                }
                return usbmuxMiss
            },
            allowsNetworkFallback: { true }
        )
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            DevicePreparationPlanner.ddiMountStatusMobdev2Command(udid: udid),
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
            DevicePreparationPlanner.ddiMountMobdev2Command(udid: udid),
        ])
    }

    func testNetworkFallbackIsDecidedWhenUsbmuxMisses() async throws {
        // The live predicate reads the current connection mode, so a switch to USB-only
        // between Moves must take effect on the next check, not when the preparer was built.
        let mode = FallbackSwitch(allowed: true)
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { [usbmuxMiss] command in
                commands.append(command)
                if command.contains("--mobdev2") { return "[]" }
                return usbmuxMiss
            },
            allowsNetworkFallback: { await mode.allowed }
        )
        _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
        XCTAssertEqual(commands.count, 2)

        await mode.set(false)
        commands.removeAll()
        do {
            _ = try await preparer.isDeveloperDiskImageMounted(udid: udid)
            XCTFail("expected statusUnparseable")
        } catch DeveloperDiskImagePreparer.PreparationError.statusUnparseable {
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [DevicePreparationPlanner.ddiMountStatusCommand(udid: udid)])
    }

    // MARK: - Helper first (live 2026-11-03: the helper held the phone over its remote
    // pairing lane, usbmuxd listed nothing and the phone refused the image mounter over
    // mobdev2, so every Move failed at this gate; over the helper's RSD it answered).

    func testHelperSaysMountedSoNoCommandRuns() async throws {
        let helper = FakeDiskImageHelper(status: .mounted)
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in commands.append(command); return "" },
            helper: helper.channel
        )
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [])
        let calls = await helper.calls
        XCTAssertEqual(calls, ["status \(udid)"], "a mounted image is cached like before")
    }

    func testHelperSaysNotMountedSoTheHelperMounts() async throws {
        let helper = FakeDiskImageHelper(status: .notMounted, mount: .mounted)
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in commands.append(command); return "" },
            helper: helper.channel
        )
        try await preparer.ensureMounted(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [])
        let calls = await helper.calls
        XCTAssertEqual(calls, ["status \(udid)", "mount \(udid)"])
    }

    func testHelperMountFailureIsAPreparationFailure() async {
        let helper = FakeDiskImageHelper(status: .notMounted, mount: .failed("RuntimeError: TSS refused"))
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in commands.append(command); return "" },
            helper: helper.channel
        )
        do {
            try await preparer.ensureMounted(udid: udid)
            XCTFail("expected mountFailed")
        } catch DeveloperDiskImagePreparer.PreparationError.mountFailed(let output) {
            XCTAssertTrue(output.contains("TSS refused"), output)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(commands, [], "a mount the helper tried is not repeated over the CLI")
        // Not cached: the next Move asks again.
        try? await preparer.ensureMounted(udid: udid)
        let calls = await helper.calls
        XCTAssertEqual(calls.filter { $0.hasPrefix("status") }.count, 2)
    }

    func testHelperNotConnectedFallsBackToTheCommandPath() async throws {
        let helper = FakeDiskImageHelper(status: .unavailable("not connected"))
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in
                commands.append(command)
                return command.contains("list") ? "[]" : "DeveloperDiskImage mounted successfully"
            },
            helper: helper.channel
        )
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [
            DevicePreparationPlanner.ddiMountStatusCommand(udid: udid),
            DevicePreparationPlanner.ddiMountCommand(udid: udid),
        ])
        let calls = await helper.calls
        XCTAssertEqual(calls, ["status \(udid)"], "no helper mount without a helper status")
    }

    func testHelperConnectionGoneBeforeTheMountFallsBackToTheMountCommand() async throws {
        let helper = FakeDiskImageHelper(status: .notMounted, mount: .unavailable("not connected"))
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(
            runner: { command in commands.append(command); return "DeveloperDiskImage mounted successfully" },
            helper: helper.channel
        )
        try await preparer.ensureMounted(udid: udid)
        XCTAssertEqual(commands, [DevicePreparationPlanner.ddiMountCommand(udid: udid)])
    }

    func testForgetAsksTheHelperAgain() async throws {
        let helper = FakeDiskImageHelper(status: .mounted)
        let preparer = DeveloperDiskImagePreparer(runner: { _ in "" }, helper: helper.channel)
        try await preparer.ensureMounted(udid: udid)
        await preparer.forget(udid: udid)
        try await preparer.ensureMounted(udid: udid)
        let calls = await helper.calls
        XCTAssertEqual(calls, ["status \(udid)", "status \(udid)"])
    }
}

private actor FakeDiskImageHelper {
    private(set) var calls: [String] = []
    private let statusReply: HelperDiskImageStatus
    private let mountReply: HelperDiskImageMountResult

    init(status: HelperDiskImageStatus, mount: HelperDiskImageMountResult = .failed("unexpected mount")) {
        statusReply = status
        mountReply = mount
    }

    func status(_ udid: String) -> HelperDiskImageStatus {
        calls.append("status \(udid)")
        return statusReply
    }

    func mount(_ udid: String) -> HelperDiskImageMountResult {
        calls.append("mount \(udid)")
        return mountReply
    }

    nonisolated var channel: HelperDiskImageChannel {
        HelperDiskImageChannel(
            status: { await self.status($0) },
            mount: { await self.mount($0) }
        )
    }
}

private actor FallbackSwitch {
    private(set) var allowed: Bool
    init(allowed: Bool) { self.allowed = allowed }
    func set(_ value: Bool) { allowed = value }
}
