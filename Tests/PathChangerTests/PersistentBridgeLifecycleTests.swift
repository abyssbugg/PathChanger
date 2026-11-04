import XCTest
@testable import PathChanger

@MainActor
final class PersistentBridgeLifecycleTests: XCTestCase {
    func testRequestGateRejectsOverlapAndWrongIdentity() throws {
        var gate = PersistentBridgeRequestGate()
        let first = UUID()
        let second = UUID()

        try gate.begin(requestID: first, generation: 7)
        XCTAssertThrowsError(try gate.begin(requestID: second, generation: 7)) { error in
            XCTAssertEqual(error as? PersistentLocationBridge.PersistentBridgeError, .requestInProgress)
        }
        XCTAssertFalse(gate.accepts(requestID: second, generation: 7))
        XCTAssertFalse(gate.accepts(requestID: first, generation: 8))
        XCTAssertTrue(gate.accepts(requestID: first, generation: 7))
        gate.finish(requestID: first, generation: 7)
        XCTAssertNoThrow(try gate.begin(requestID: second, generation: 8))
    }

    func testReadinessRequiresReadyProtocolMessage() {
        var gate = PersistentBridgeReadinessGate()
        XCTAssertFalse(gate.consume(ready: false))
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.consume(ready: true))
        XCTAssertTrue(gate.isReady)
    }

    func testTerminationEventsAreOrderedExactlyOnce() {
        let session = LocationSessionIdentity(
            stableDeviceID: "persistent-device",
            transport: .wifi,
            endpointClass: .remoteServiceDiscovery,
            generation: 4
        )
        var events = PersistentBridgeTerminationEvents()

        XCTAssertEqual(
            events.consume(exitCode: 9, intentional: false, session: session),
            [.processTerminated(exitCode: 9), .sessionLost(session, reason: "unexpected process exit")]
        )
        XCTAssertTrue(events.consume(exitCode: 9, intentional: false, session: session).isEmpty)

        var intentional = PersistentBridgeTerminationEvents()
        XCTAssertEqual(
            intentional.consume(exitCode: 0, intentional: true, session: session),
            [.processTerminated(exitCode: 0), .sessionLost(session, reason: "intentional stop")]
        )
    }

    func testEventHubPublishesTerminationThenSessionLoss() async {
        let session = LocationSessionIdentity(
            stableDeviceID: "stream-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 2
        )
        let expected: [LocationBridgeEvent] = [
            .processTerminated(exitCode: 7),
            .sessionLost(session, reason: "unexpected process exit")
        ]
        let hub = PersistentBridgeEventHub()
        let stream = hub.stream()
        let collected = Task { () -> [LocationBridgeEvent] in
            var result: [LocationBridgeEvent] = []
            for await event in stream {
                result.append(event)
                if result.count == expected.count { break }
            }
            return result
        }

        hub.publish(expected)
        let values = await collected.value
        XCTAssertEqual(values, expected)
    }

    func testAnIntentionalStopReportsAnIntentionalSessionLoss() {
        let session = LocationSessionIdentity(
            stableDeviceID: "intent-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 5
        )
        var events = PersistentBridgeTerminationEvents()
        let intentionalStop = events.consume(exitCode: 0, intentional: true, session: session)
        XCTAssertTrue(intentionalStop.contains { event in
            if case .sessionLost(_, reason: let reason) = event {
                return reason == "intentional stop"
            }
            return false
        })
    }

    // MARK: - The live wait, termination and relaunch path (managed helper socket)
    //
    // The bridge talks to the managed helper over its authenticated socket; the old stdio
    // cleanup()/waitForReady() path has no callers. These tests drive the real bridge and
    // controller against a local fake helper (no device, no tunnel): a command waiting for
    // the slot is cancelled, the helper dies under the command in flight, and the next
    // start launches a new helper that answers.

    /// A local stand-in for `scripts/location_bridge.py`: the same launch arguments, record
    /// and authenticated NDJSON socket protocol, answering only `ping` and `quit`. With a
    /// `hold-next-command` file in its directory it keeps the next command unanswered
    /// (writing `holding`) until a `die` file appears, then exits at once without replying
    /// or cleaning up, as a crashed helper would. Every command received is appended to
    /// `commands.log`.
    private static let fakeHelperSource = #"""
    import asyncio, hashlib, hmac, json, os, sys, uuid

    def argument(name):
        return sys.argv[sys.argv.index(name) + 1]

    socket_path = argument("--socket")
    record_path = argument("--record-file")
    with open(argument("--token-file"), encoding="utf-8") as source:
        token = source.read().strip()
    base = os.path.dirname(socket_path)
    helper_id = str(uuid.uuid4())

    def sha256(path):
        with open(path, "rb") as source:
            return hashlib.sha256(source.read()).hexdigest()

    def note(cmd):
        with open(os.path.join(base, "commands.log"), "a", encoding="utf-8") as log:
            log.write(f"{helper_id} {cmd}\n")

    async def client(reader, writer):
        while True:
            line = await reader.readline()
            if not line:
                break
            request = json.loads(line.decode())
            if not hmac.compare_digest(str(request.get("auth_token", "")), token):
                response = {"success": False, "error": "Invalid helper authentication", "code": "UNAUTHORIZED"}
            else:
                cmd = request.get("cmd")
                note(cmd)
                hold = os.path.join(base, "hold-next-command")
                if os.path.exists(hold):
                    os.unlink(hold)
                    open(os.path.join(base, "holding"), "w").close()
                    while not os.path.exists(os.path.join(base, "die")):
                        await asyncio.sleep(0.02)
                    os._exit(3)
                response = {"success": True, "message": "pong"}
            for key in ("request_id", "session_generation"):
                if key in request:
                    response[key] = request[key]
            response["helper_id"] = helper_id
            writer.write((json.dumps(response) + "\n").encode())
            await writer.drain()
            if request.get("cmd") == "quit" and response["success"]:
                for path in (record_path, socket_path):
                    try:
                        os.unlink(path)
                    except FileNotFoundError:
                        pass
                os._exit(0)
        writer.close()

    async def main():
        server = await asyncio.start_unix_server(client, path=socket_path)
        os.chmod(socket_path, 0o600)
        record = {
            "protocol_version": 1, "helper_id": helper_id, "pid": os.getpid(),
            "socket_path": socket_path,
            "python_path": os.path.realpath(sys.executable), "python_sha256": sha256(sys.executable),
            "bridge_path": os.path.realpath(__file__), "bridge_sha256": sha256(__file__),
            "token_sha256": hashlib.sha256(token.encode()).hexdigest(),
            "active_sessions": [], "recent_results": [],
        }
        temporary = record_path + ".tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
            json.dump(record, destination)
        os.replace(temporary, record_path)
        async with server:
            await asyncio.Event().wait()

    asyncio.run(main())
    """#

    private struct FakeHelper {
        let root: URL
        let scriptDirectory: URL
        let controller: ManagedLocationHelperController
        let bridge: PersistentLocationBridge

        func touch(_ name: String) {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: nil)
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
        }

        /// The commands each helper received, oldest first: (helper ID, command).
        func commands() -> [(helperID: String, cmd: String)] {
            let log = (try? String(contentsOf: root.appendingPathComponent("commands.log"), encoding: .utf8)) ?? ""
            return log.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: " ")
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            }
        }

        func waitFor(_ name: String, seconds: Double = 10) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if exists(name) { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return exists(name)
        }
    }

    private func makeFakeHelper(_ label: String) throws -> FakeHelper {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        // A short /private/tmp path: a Unix socket path is limited to 104 bytes.
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-\(label)-\(UUID().uuidString.prefix(8))")
        let paths = ManagedLocationHelperPaths(baseDirectory: root)
        _ = try paths.prepare()
        // The script lives outside /private: Foundation's symlink resolution drops the
        // /private prefix that Python's realpath keeps, so a script there would fail the
        // controller's bridge_path adoption check.
        let scriptDirectory = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("PathChangerTests-\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        let script = scriptDirectory.appendingPathComponent("fake_helper.py")
        try Data(Self.fakeHelperSource.utf8).write(to: script)
        let controller = ManagedLocationHelperController(
            paths: paths,
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: script.path
        )
        return FakeHelper(
            root: root, scriptDirectory: scriptDirectory, controller: controller,
            bridge: PersistentLocationBridge(helperController: controller)
        )
    }

    private func tearDown(_ helper: FakeHelper) async {
        helper.touch("die")
        try? await helper.controller.shutdown()
        // A helper still holding a command exits on `die`; give it a moment, then remove
        // its directory (and with it any record or socket a crashed helper left).
        try? await Task.sleep(nanoseconds: 100_000_000)
        try? FileManager.default.removeItem(at: helper.root)
        try? FileManager.default.removeItem(at: helper.scriptDirectory)
    }

    func testACommandWaitingBehindAnotherIsCancelledOnceAndNeverSent() async throws {
        let helper = try makeFakeHelper("wait-cancel")
        do {
            try await helper.bridge.start()
            helper.touch("hold-next-command")
            let inFlight = Task { @MainActor () -> Result<Bool, Error> in
                do { return .success(try await helper.bridge.ping()) } catch { return .failure(error) }
            }
            let held = await helper.waitFor("holding")
            XCTAssertTrue(held, "the helper holds the first command")
            let sentBefore = helper.commands().count

            var waiterOutcomes: [Result<Bool, Error>] = []
            let waiting = Task { @MainActor () -> Result<Bool, Error> in
                do { return .success(try await helper.bridge.ping()) } catch { return .failure(error) }
            }
            for _ in 0..<20 { await Task.yield() }
            waiting.cancel()
            waiterOutcomes.append(await waiting.value)
            try? await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(waiterOutcomes.count, 1)
            guard case .failure(let error) = waiterOutcomes[0] else {
                return XCTFail("a command cancelled while it waits must not run")
            }
            XCTAssertTrue(error is CancellationError, "resumed with cancellation, got \(error)")
            XCTAssertEqual(helper.commands().count, sentBefore, "the cancelled command never reached the helper")

            helper.touch("die")
            if case .success = await inFlight.value { XCTFail("the held command fails when its helper dies") }
        } catch {
            await tearDown(helper)
            throw error
        }
        await tearDown(helper)
    }

    func testTheHelperDyingUnderACommandFailsItOnceAndTheNextStartLaunchesANewHelper() async throws {
        let helper = try makeFakeHelper("helper-death")
        do {
            try await helper.bridge.start()
            let firstHelper = try XCTUnwrap(helper.bridge.adoptedHelperID)
            let firstPing = try await helper.bridge.ping()
            XCTAssertTrue(firstPing)

            helper.touch("hold-next-command")
            var outcomes: [Result<Bool, Error>] = []
            let inFlight = Task { @MainActor () -> Result<Bool, Error> in
                do { return .success(try await helper.bridge.ping()) } catch { return .failure(error) }
            }
            let held = await helper.waitFor("holding")
            XCTAssertTrue(held, "the helper holds the command")
            XCTAssertTrue(helper.bridge.isRunning)

            helper.touch("die")
            outcomes.append(await inFlight.value)
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(outcomes.count, 1)
            guard case .failure(let error) = outcomes[0] else {
                return XCTFail("the command in flight fails when its helper dies")
            }
            XCTAssertNotNil(error as? PersistentLocationBridge.PersistentBridgeError, "\(error)")
            XCTAssertFalse(helper.bridge.isRunning, "the dead helper's state is cleared")
            XCTAssertNil(helper.bridge.adoptedHelperID)

            // The next generation: a new helper, which answers.
            try FileManager.default.removeItem(at: helper.root.appendingPathComponent("die"))
            try await helper.bridge.start()
            XCTAssertTrue(helper.bridge.isRunning)
            let secondHelper = try XCTUnwrap(helper.bridge.adoptedHelperID)
            XCTAssertNotEqual(secondHelper, firstHelper, "a new helper was launched")
            let secondPing = try await helper.bridge.ping()
            XCTAssertTrue(secondPing, "the new generation answers")
            XCTAssertEqual(helper.commands().last?.helperID, secondHelper.uuidString.lowercased())
        } catch {
            await tearDown(helper)
            throw error
        }
        await tearDown(helper)
    }

    /// Source-shape check of scripts/location_bridge.py (it reads the text, runs nothing).
    func testSourceShapeBridgeScriptWakesAPendingStdinReadOnShutdown() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/location_bridge.py"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("run_in_executor(None, sys.stdin.readline)"))
        XCTAssertTrue(source.contains("_shutdown_event"))
        XCTAssertTrue(source.contains("connect_read_pipe"))
        XCTAssertTrue(source.contains("return_when=asyncio.FIRST_COMPLETED"))
        XCTAssertTrue(source.contains("read_task.cancel()"))
    }
}
