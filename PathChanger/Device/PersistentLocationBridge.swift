import CryptoKit
import Darwin
import Foundation

@MainActor
protocol ManagedLocationSessionSource: AnyObject {
    var adoptedHelperID: UUID? { get }
    var adoptedHelperSessions: [ManagedLocationHelperSession] { get }
    /// True when a live helper's identity record lists held location sessions, even if
    /// this app session has not started, adopted, or restored them yet.
    var hasRecordedHeldSessions: Bool { get }
    /// True when this app session started or adopted the helper. While false, the
    /// connection probe and `disconnectDevice` answer without asking any helper, so their
    /// answers are not evidence about a helper an earlier session left running.
    var isHelperRunning: Bool { get }

    /// Bounded liveness probe of the helper's device connection. Never starts it.
    func deviceConnectionStatus(_ deviceId: String, transport: LocationTransport) async -> HelperConnectionStatus

    func start() async throws
    func refreshAdoptedHelperSessions() async throws
    func shutdownHelper() async throws

    /// Clear the simulated location over the helper's device connection, for a device
    /// this app's injector holds no session for (a relaunch, or a provisional session
    /// after a loss). Throws unless the helper confirmed the Clear. The caller probes the
    /// connection first; this still runs the bridge's normal Clear path, which starts the
    /// helper if needed and sends the idempotent `connect_device` preflight (cheap on a
    /// live connection, at most the 40 s connect budget if the link dropped after the
    /// probe). `sessionGeneration` is the GUI session's generation (nil: the bridge's).
    func clearLocationOverDeviceConnection(
        _ deviceId: String,
        transport: LocationTransport,
        sessionGeneration: UInt64?
    ) async throws
    /// Close the helper's device connection, which ends any location held over it. True
    /// when the helper confirmed it (or no helper, hence no connection, exists). Never
    /// starts the helper.
    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool

    /// The held session a replaced helper listed for `deviceID` (its connection is gone,
    /// so the phone no longer holds it), handed out once so the coordinate can be
    /// reapplied over the new helper. Nil when there is none.
    func takeInheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession?
    /// The same session without handing it out (nil when there is none).
    func inheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession?
    /// Drop every held session inherited from a replaced helper, for every device. Clear,
    /// Stop Tunnel and an explicit Move supersede what that helper held, whether or not
    /// they reached the phone (review 2026-11-03 reconnect-audit issue 1).
    func discardInheritedHeldSessions()
    /// The counter AppState advances on every Clear, read when a replaced helper's held
    /// sessions are inherited and stamped on them (`ManagedLocationInheritedSession.clearEpoch`).
    func setInheritedSessionClearEpochSource(_ source: @escaping @MainActor () -> UInt64)
}

extension ManagedLocationSessionSource {
    func takeInheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession? { nil }
    func inheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession? { nil }
    func discardInheritedHeldSessions() {}
    func setInheritedSessionClearEpochSource(_ source: @escaping @MainActor () -> UInt64) {}
}

/// A held session read from the record of a foreign helper the app replaced.
struct ManagedLocationInheritedSession: Equatable {
    let helperID: UUID
    let session: ManagedLocationHelperSession
    /// AppState's Clear counter when the session was inherited; nil when no source was
    /// set. A Clear since then makes the session stale.
    var clearEpoch: UInt64? = nil
}

struct ManagedLocationHelperPaths {
    let baseDirectory: URL
    let socketURL: URL
    let tokenURL: URL
    let recordURL: URL

    enum PathError: LocalizedError {
        case unsafeDirectory
        case unsafeToken
        case invalidToken

        var errorDescription: String? {
            switch self {
            case .unsafeDirectory:
                return "Location helper directory is not an owner-only regular directory"
            case .unsafeToken:
                return "Location helper token is not an owner-only regular file"
            case .invalidToken:
                return "Location helper token is invalid"
            }
        }
    }

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        socketURL = baseDirectory.appendingPathComponent("helper.sock")
        tokenURL = baseDirectory.appendingPathComponent("token")
        recordURL = baseDirectory.appendingPathComponent("helper.json")
    }

    func prepare(fileManager: FileManager = .default) throws -> String {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            let attributes = try fileManager.attributesOfItem(atPath: baseDirectory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw PathError.unsafeDirectory
            }
        } else {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: baseDirectory.path
        )

        if fileManager.fileExists(atPath: tokenURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: tokenURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else {
                throw PathError.unsafeToken
            }
            let token = try String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decoded = Data(base64Encoded: token), decoded.count >= 32 else {
                throw PathError.invalidToken
            }
            return token
        }

        var generator = SystemRandomNumberGenerator()
        let tokenData = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let token = tokenData.base64EncodedString()
        try Data(token.utf8).write(to: tokenURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: tokenURL.path
        )
        return token
    }
}

struct ManagedLocationHelperCommand: Codable, Sendable {
    let cmd: String
    let requestID: UUID
    let sessionGeneration: UInt64

    init(cmd: String, requestID: UUID = UUID(), sessionGeneration: UInt64 = 0) {
        self.cmd = cmd
        self.requestID = requestID
        self.sessionGeneration = sessionGeneration
    }

    enum CodingKeys: String, CodingKey {
        case cmd
        case requestID = "request_id"
        case sessionGeneration = "session_generation"
    }
}

struct ManagedLocationHelperPingResponse: Codable, Sendable {
    let success: Bool
    let helperID: String

    enum CodingKeys: String, CodingKey {
        case success
        case helperID = "helper_id"
    }
}

struct ManagedLocationHelperClient: Sendable {
    let socketPath: String
    let token: String

    enum ClientError: LocalizedError {
        case invalidSocketPath
        case connectFailed(Int32)
        case encodeFailed
        case writeFailed(Int32)
        case readFailed(Int32)
        case responseTooLarge
        case emptyResponse

        var isResponseTimeout: Bool {
            guard case let .readFailed(code) = self else { return false }
            return code == EAGAIN || code == EWOULDBLOCK
        }

        var invalidatesManagedHelperState: Bool {
            if case .encodeFailed = self { return false }
            return !isResponseTimeout
        }

        var errorDescription: String? {
            switch self {
            case .invalidSocketPath:
                return "Location helper socket path is invalid"
            case let .connectFailed(code):
                return "Location helper connection failed (errno \(code))"
            case .encodeFailed:
                return "Location helper request must encode as an object"
            case let .writeFailed(code):
                return "Location helper write failed (errno \(code))"
            case let .readFailed(code):
                return "Location helper read failed (errno \(code))"
            case .responseTooLarge:
                return "Location helper response exceeded its size limit"
            case .emptyResponse:
                return "Location helper closed without a response"
            }
        }
    }

    func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ request: Request,
        responseType: Response.Type,
        timeoutSeconds: Int = 5
    ) async throws -> Response {
        try await Task.detached(priority: .userInitiated) {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw ClientError.connectFailed(errno)
            }
            defer { Darwin.close(descriptor) }

            var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
            _ = withUnsafePointer(to: &timeout) { pointer in
                setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    pointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
            _ = withUnsafePointer(to: &timeout) { pointer in
                setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_SNDTIMEO,
                    pointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }

            let socketBytes = Array(self.socketPath.utf8CString).map { UInt8(bitPattern: $0) }
            var address = sockaddr_un()
            guard socketBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw ClientError.invalidSocketPath
            }
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.copyBytes(from: socketBytes)
            }
            let connectResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else {
                throw ClientError.connectFailed(errno)
            }

            let encodedRequest = try JSONEncoder().encode(request)
            guard var object = try JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any] else {
                throw ClientError.encodeFailed
            }
            object["auth_token"] = self.token
            var requestData = try JSONSerialization.data(withJSONObject: object)
            requestData.append(0x0A)
            try requestData.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var written = 0
                while written < rawBuffer.count {
                    let count = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: written),
                        rawBuffer.count - written
                    )
                    if count > 0 {
                        written += count
                    } else if count < 0, errno == EINTR {
                        continue
                    } else {
                        throw ClientError.writeFailed(errno)
                    }
                }
            }

            let maximumResponseSize = 1_048_576
            var responseData = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            readLoop: while responseData.count < maximumResponseSize {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    if let newlineIndex = buffer[..<count].firstIndex(of: 0x0A) {
                        responseData.append(contentsOf: buffer[..<newlineIndex])
                        break readLoop
                    }
                    responseData.append(contentsOf: buffer[..<count])
                } else if count == 0 {
                    break readLoop
                } else if errno == EINTR {
                    continue
                } else {
                    throw ClientError.readFailed(errno)
                }
            }
            guard responseData.count < maximumResponseSize else {
                throw ClientError.responseTooLarge
            }
            guard !responseData.isEmpty else {
                throw ClientError.emptyResponse
            }
            return try JSONDecoder().decode(responseType, from: responseData)
        }.value
    }
}

struct ManagedLocationHelperCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct ManagedLocationHelperResult: Codable, Equatable {
    let command: String
    let deviceIDSHA256: String
    let requestID: String
    let sessionGeneration: UInt64
    let success: Bool
    let error: String?
    let code: String?
    let physicalTransport: String
    let actualChannel: String?
    let endpointClass: String?
    let coordinate: ManagedLocationHelperCoordinate?
    let completedAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case command = "cmd"
        case deviceIDSHA256 = "device_id_sha256"
        case requestID = "request_id"
        case sessionGeneration = "session_generation"
        case success, error, code
        case physicalTransport = "physical_transport"
        case actualChannel = "actual_channel"
        case endpointClass = "endpoint_class"
        case coordinate
        case completedAt = "completed_at"
    }

    func matches(deviceID: String, requestID: UUID, generation: UInt64) -> Bool {
        deviceIDSHA256 == ManagedLocationHelperSession.deviceIDHash(deviceID)
            && self.requestID.caseInsensitiveCompare(requestID.uuidString) == .orderedSame
            && sessionGeneration == generation
    }

    func wireResponse() throws -> PersistentBridgeWireResponse {
        guard let parsedRequestID = UUID(uuidString: requestID) else {
            throw PersistentLocationBridge.PersistentBridgeError.invalidResponse(
                "Managed helper journal contains an invalid request identifier"
            )
        }
        return PersistentBridgeWireResponse(
            success: success,
            request_id: parsedRequestID,
            session_generation: sessionGeneration,
            error: error,
            code: code,
            message: nil,
            ready: nil,
            channel: actualChannel,
            endpoint_class: endpointClass
        )
    }
}

struct ManagedLocationHelperSession: Codable, Equatable {
    let deviceIDSHA256: String
    let requestID: String
    let sessionGeneration: UInt64
    let physicalTransport: String
    let actualChannel: String
    let endpointClass: String
    let coordinate: ManagedLocationHelperCoordinate
    let acknowledgedAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceIDSHA256 = "device_id_sha256"
        case requestID = "request_id"
        case sessionGeneration = "session_generation"
        case physicalTransport = "physical_transport"
        case actualChannel = "actual_channel"
        case endpointClass = "endpoint_class"
        case coordinate
        case acknowledgedAt = "acknowledged_at"
    }

    static func deviceIDHash(_ deviceID: String) -> String {
        SHA256.hash(data: Data(deviceID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func matches(deviceID: String) -> Bool {
        deviceIDSHA256 == Self.deviceIDHash(deviceID)
    }

    func locationReceipt(helperID: UUID) -> LocationInjectionReceipt? {
        guard let parsedRequestID = UUID(uuidString: requestID),
              let parsedTransport = LocationTransport(helperWireValue: physicalTransport),
              let parsedEndpoint = LocationEndpointClass(rawValue: endpointClass),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              (-90.0...90.0).contains(coordinate.latitude),
              (-180.0...180.0).contains(coordinate.longitude),
              acknowledgedAt.isFinite,
              acknowledgedAt >= 0 else {
            return nil
        }

        let channel = LocationDVTChannel(rawValue: actualChannel)
        guard let acknowledgement = LocationProviderAcknowledgement(
            requestID: parsedRequestID,
            sessionGeneration: sessionGeneration,
            physicalTransport: parsedTransport,
            channel: channel,
            endpointClass: parsedEndpoint
        ) else {
            return nil
        }

        return LocationInjectionReceipt(
            session: helperID,
            acknowledgedCoordinate: LocationCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            acknowledgement: acknowledgement,
            completedAt: Date(timeIntervalSince1970: acknowledgedAt),
            outcome: .applied
        )
    }
}

struct ManagedLocationHelperExpectation: Equatable {
    var socketPath: String
    var pythonPath: String
    var pythonSHA256: String
    var bridgePath: String
    var bridgeSHA256: String
    var tokenSHA256: String
}

struct ManagedLocationHelperRecord: Codable, Equatable {
    let protocolVersion: Int
    let helperID: UUID
    let pid: Int32
    let socketPath: String
    let pythonPath: String
    let pythonSHA256: String
    let bridgePath: String
    let bridgeSHA256: String
    let tokenSHA256: String
    let activeSessions: [ManagedLocationHelperSession]
    var recentResults: [ManagedLocationHelperResult]? = nil

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case helperID = "helper_id"
        case pid
        case socketPath = "socket_path"
        case pythonPath = "python_path"
        case pythonSHA256 = "python_sha256"
        case bridgePath = "bridge_path"
        case bridgeSHA256 = "bridge_sha256"
        case tokenSHA256 = "token_sha256"
        case activeSessions = "active_sessions"
        case recentResults = "recent_results"
    }

    enum AdoptionError: LocalizedError, Equatable {
        case unsupportedProtocol(Int)
        case invalidPID
        case evidenceMismatch(String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedProtocol(version):
                return "Unsupported location helper protocol version: \(version)"
            case .invalidPID:
                return "Location helper record has an invalid process identifier"
            case let .evidenceMismatch(field):
                return "Location helper adoption evidence does not match: \(field)"
            }
        }
    }

    func validateForAdoption(expectation: ManagedLocationHelperExpectation) throws {
        guard protocolVersion == 1 else { throw AdoptionError.unsupportedProtocol(protocolVersion) }
        guard pid > 0 else { throw AdoptionError.invalidPID }
        let evidence: [(String, String, String)] = [
            ("socket_path", socketPath, expectation.socketPath),
            ("python_path", pythonPath, expectation.pythonPath),
            ("python_sha256", pythonSHA256, expectation.pythonSHA256),
            ("bridge_path", bridgePath, expectation.bridgePath),
            ("bridge_sha256", bridgeSHA256, expectation.bridgeSHA256),
            ("token_sha256", tokenSHA256, expectation.tokenSHA256),
        ]
        if let mismatch = evidence.first(where: { $0.1 != $0.2 }) {
            throw AdoptionError.evidenceMismatch(mismatch.0)
        }
    }
}

/// The managed helper's stderr log (`~/Library/Logs/PathChanger`, never /tmp).
///
/// The helper outlives the app (it is adopted on relaunch), so it writes to a file it
/// holds open, not to a pipe the app would have to drain. The cap is enforced at each
/// launch (a log over `maxBytes` is renamed to `.1` once, replacing an older `.1`), at
/// each adoption (`capInPlace`), and in place at most once per `periodicCapInterval`
/// while one helper runs (on helper-record refresh and the connection health probe),
/// so a helper that runs for days cannot grow it without bound.
enum ManagedLocationHelperStderrLog {
    static let maxBytes: UInt64 = 1_048_576
    static let periodicCapInterval: TimeInterval = 60

    static func isPeriodicCapDue(
        lastCap: Date?,
        now: Date,
        interval: TimeInterval = ManagedLocationHelperStderrLog.periodicCapInterval
    ) -> Bool {
        guard let lastCap else { return true }
        let elapsed = now.timeIntervalSince(lastCap)
        // A wall clock set back would otherwise postpone the cap until it caught up.
        return elapsed >= interval || elapsed < 0
    }

    enum LogError: LocalizedError {
        case unsafeFile(String)
        case openFailed(Int32)

        var errorDescription: String? {
            switch self {
            case let .unsafeFile(path):
                return "Location helper stderr log is not an owner-only regular file: \(path)"
            case let .openFailed(code):
                return "Location helper stderr log could not be opened: \(String(cString: strerror(code)))"
            }
        }
    }

    static var defaultURL: URL? {
        // Not `.log`: FileLogger's age sweep deletes every `*.log` in this directory
        // and would unlink the file the helper holds open.
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/PathChanger", isDirectory: true)
            .appendingPathComponent("location-helper-stderr.txt")
    }

    /// Cap the log of a helper that is still running (adopted on relaunch): it holds the
    /// file open with O_APPEND, so a rename would leave it growing the renamed file.
    /// Keeps the newest `maxBytes` in `.1` and truncates the live file in place; the
    /// helper's next write starts it again. A missing file is left alone.
    static func capInPlace(
        at url: URL,
        maxBytes: UInt64 = ManagedLocationHelperStderrLog.maxBytes,
        fileManager: FileManager = .default
    ) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw LogError.unsafeFile(url.path)
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > maxBytes else { return }

        let descriptor = Darwin.open(url.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LogError.openFailed(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.seek(toOffset: size - maxBytes)
        let tail = try handle.readToEnd() ?? Data()

        let rotated = URL(fileURLWithPath: url.path + ".1")
        try? fileManager.removeItem(at: rotated)
        let rotatedDescriptor = Darwin.open(
            rotated.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard rotatedDescriptor >= 0 else { throw LogError.openFailed(errno) }
        let rotatedHandle = FileHandle(fileDescriptor: rotatedDescriptor, closeOnDealloc: true)
        try rotatedHandle.write(contentsOf: tail)
        try rotatedHandle.close()

        guard ftruncate(descriptor, 0) == 0 else { throw LogError.openFailed(errno) }
        try handle.close()
    }

    /// Open the log for appending with owner-only permissions. Refuses symlinks and
    /// files owned by another user.
    static func open(
        at url: URL,
        maxBytes: UInt64 = ManagedLocationHelperStderrLog.maxBytes,
        fileManager: FileManager = .default
    ) throws -> FileHandle {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                throw LogError.unsafeFile(url.path)
            }
            if ((attributes[.size] as? NSNumber)?.uint64Value ?? 0) > maxBytes {
                let rotated = URL(fileURLWithPath: url.path + ".1")
                try? fileManager.removeItem(at: rotated)
                try fileManager.moveItem(at: url, to: rotated)
            }
        }
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw LogError.openFailed(errno) }
        guard fchmod(descriptor, 0o600) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw LogError.openFailed(code)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

struct ManagedLocationHelperConnection: Sendable {
    let client: ManagedLocationHelperClient
    let record: ManagedLocationHelperRecord
    let launchedNewHelper: Bool
}

@MainActor
final class ManagedLocationHelperController {
    enum ControllerError: LocalizedError {
        case invalidRecord
        case unsafeRecord
        case unsafeExistingSocket
        case helperNotRunning
        case helperIdentityMismatch
        case launchFailed(String)
        case startupTimedOut
        case shutdownTimedOut
        case foreignHelperStillRunning

        var errorDescription: String? {
            switch self {
            case .invalidRecord:
                return "Location helper identity record is invalid"
            case .unsafeRecord:
                return "Location helper identity record is not an owner-only regular file"
            case .unsafeExistingSocket:
                return "Location helper socket exists without trustworthy adoption evidence"
            case .helperNotRunning:
                return "Recorded location helper process is not running"
            case .helperIdentityMismatch:
                return "Authenticated location helper identity does not match its record"
            case let .launchFailed(reason):
                return "Failed to launch location helper: \(reason)"
            case .startupTimedOut:
                return "Location helper did not become ready before the startup deadline"
            case .shutdownTimedOut:
                return "Location helper did not shut down before the deadline"
            case .foreignHelperStillRunning:
                return "The location helper an earlier PathChanger started is still running"
            }
        }
    }

    private let paths: ManagedLocationHelperPaths
    private let pythonPath: String
    private let bridgePath: String
    private let fileManager: FileManager
    /// Where the helper's stderr goes; nil discards it (tests that launch helpers).
    private let stderrLogURL: URL?
    private let stderrLogMaxBytes: UInt64
    private let now: () -> Date
    /// When the stderr log was last capped (launch rotation, adoption or periodic).
    private var lastStderrCap: Date?
    private var launchedProcess: Process?
    private var activeConnection: ManagedLocationHelperConnection?
    /// The parent PID of a process, or nil when it cannot be read (gone). Injected in tests.
    private let parentProcessID: (Int32) -> Int32?

    init(
        paths: ManagedLocationHelperPaths,
        pythonPath: String,
        bridgePath: String,
        fileManager: FileManager = .default,
        stderrLogURL: URL? = nil,
        stderrLogMaxBytes: UInt64 = ManagedLocationHelperStderrLog.maxBytes,
        now: @escaping () -> Date = Date.init,
        parentProcessID: @escaping (Int32) -> Int32? = ManagedLocationHelperController.liveParentProcessID
    ) {
        self.paths = paths
        self.pythonPath = pythonPath
        self.bridgePath = bridgePath
        self.fileManager = fileManager
        self.stderrLogURL = stderrLogURL
        self.stderrLogMaxBytes = stderrLogMaxBytes
        self.now = now
        self.parentProcessID = parentProcessID
    }

    /// The kernel's parent PID of `pid` (sysctl KERN_PROC_PID), or nil when it is gone.
    nonisolated static func liveParentProcessID(_ pid: Int32) -> Int32? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size > 0,
              info.kp_proc.p_pid == pid else {
            return nil
        }
        return info.kp_eproc.e_ppid
    }

    /// True when the recorded helper is not this app run's own child: launched by an
    /// earlier PathChanger (orphaned, parent PID 1) or by another one still running.
    /// macOS attributes a process's local network access to the app that launched it,
    /// so an orphan is denied it (live 2026-11-03: EHOSTUNREACH on every mDNS send).
    func isForeign(_ record: ManagedLocationHelperRecord) -> Bool {
        if let launchedProcess, launchedProcess.processIdentifier == record.pid { return false }
        return parentProcessID(record.pid) != getpid()
    }

    /// The record of the helper this controller launched or adopted, if any.
    var activeRecord: ManagedLocationHelperRecord? { activeConnection?.record }

    /// The adopted helper is foreign (see `isForeign`).
    var activeConnectionIsForeign: Bool {
        activeConnection.map { isForeign($0.record) } ?? false
    }

    /// Stop the adopted foreign helper and launch this app run's own. Asks it to quit over
    /// its socket; if it cannot be asked, SIGTERM (then SIGKILL) goes only to the PID its
    /// validated record names, while its command line still serves this helper socket.
    func replaceForeignHelper() async throws -> ManagedLocationHelperConnection {
        if let foreign = activeConnection, isForeign(foreign.record) {
            do {
                try await shutdown()
            } catch {
                Logger.error(
                    "[PersistentBridge] The earlier helper did not quit when asked (\(error.localizedDescription)); terminating its recorded process",
                    category: .device
                )
                await terminate(foreign.record)
            }
            activeConnection = nil
            launchedProcess = nil
        }
        let connection = try await connectOrLaunch()
        guard !isForeign(connection.record) else { throw ControllerError.foreignHelperStillRunning }
        return connection
    }

    private func terminate(_ adopted: ManagedLocationHelperRecord) async {
        // The record on disk must still name the helper this app adopted and validated.
        if let current = try? currentRecord(),
           current.helperID != adopted.helperID || current.pid != adopted.pid {
            return
        }
        let pid = adopted.pid
        // Every managed helper is launched with this socket path; a reused PID is not.
        let outcome = await TunnelProcessTerminator.stop(
            pid: pid,
            requiredCommandPattern: "--socket \(paths.socketURL.path)",
            isAlive: { TunnelProcessTerminator.isAlive(pid: pid) }
        )
        Logger.info("[PersistentBridge] Earlier helper PID \(pid): \(outcome)", category: .device)
        if !TunnelProcessTerminator.isAlive(pid: pid) {
            try? removeStaleArtifacts()
        }
    }

    /// Cap the running helper's stderr log in place, at most once per
    /// `periodicCapInterval`. When not due this costs one clock read, so it may sit on
    /// the location update path.
    func capStderrLogIfDue() {
        guard stderrLogURL != nil,
              ManagedLocationHelperStderrLog.isPeriodicCapDue(lastCap: lastStderrCap, now: now()) else {
            return
        }
        capStderrLogInPlace(of: "running")
    }

    /// The helper holds the log open, so it is capped in place (an adopted helper never
    /// gets the launch-time rotation). Failure only loses log history.
    private func capStderrLogInPlace(of helperDescription: String) {
        guard let stderrLogURL else { return }
        // Recorded before the attempt: a failing cap is retried once per interval, not
        // on every call.
        lastStderrCap = now()
        do {
            try ManagedLocationHelperStderrLog.capInPlace(
                at: stderrLogURL,
                maxBytes: stderrLogMaxBytes,
                fileManager: fileManager
            )
        } catch {
            Logger.error(
                "[PersistentBridge] Could not cap the \(helperDescription) helper's stderr log: \(error.localizedDescription)",
                category: .device
            )
        }
    }

    func connectOrLaunch() async throws -> ManagedLocationHelperConnection {
        if let activeConnection {
            return activeConnection
        }

        let token = try paths.prepare(fileManager: fileManager)
        let expectation = try makeExpectation(token: token)

        if fileManager.fileExists(atPath: paths.recordURL.path) {
            let record = try loadRecord()
            if processIsAlive(record.pid) {
                try record.validateForAdoption(expectation: expectation)
                let connection = try await authenticate(
                    record: record,
                    token: token,
                    launchedNewHelper: false
                )
                capStderrLogInPlace(of: "adopted")
                activeConnection = connection
                return connection
            }
            try removeStaleArtifacts()
        } else if fileManager.fileExists(atPath: paths.socketURL.path) {
            throw ControllerError.unsafeExistingSocket
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-B", bridgePath,
            "--socket", paths.socketURL.path,
            "--token-file", paths.tokenURL.path,
            "--record-file", paths.recordURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        var stderrLog: FileHandle?
        if let stderrLogURL {
            do {
                stderrLog = try ManagedLocationHelperStderrLog.open(
                    at: stderrLogURL,
                    maxBytes: stderrLogMaxBytes,
                    fileManager: fileManager
                )
                // Opening rotated an oversized log: the new helper starts under the cap.
                lastStderrCap = now()
            } catch {
                Logger.error(
                    "[PersistentBridge] Helper stderr will be discarded: \(error.localizedDescription)",
                    category: .device
                )
            }
        }
        process.standardError = stderrLog ?? FileHandle.nullDevice
        process.environment = ProcessEnvironment.configured()

        do {
            try process.run()
        } catch {
            try? stderrLog?.close()
            throw ControllerError.launchFailed(error.localizedDescription)
        }
        // The child holds its own copy of the descriptor.
        try? stderrLog?.close()
        launchedProcess = process

        do {
            for _ in 0..<250 {
                if !process.isRunning {
                    throw ControllerError.launchFailed("process exited with status \(process.terminationStatus)")
                }
                if fileManager.fileExists(atPath: paths.recordURL.path),
                   fileManager.fileExists(atPath: paths.socketURL.path) {
                    let record = try loadRecord()
                    try record.validateForAdoption(expectation: expectation)
                    let connection = try await authenticate(
                        record: record,
                        token: token,
                        launchedNewHelper: true
                    )
                    activeConnection = connection
                    return connection
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            throw ControllerError.startupTimedOut
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            launchedProcess = nil
            try? removeOwnedArtifacts()
            throw error
        }
    }

    func refreshConnection() async throws -> ManagedLocationHelperConnection {
        let token = try paths.prepare(fileManager: fileManager)
        let expectation = try makeExpectation(token: token)
        guard fileManager.fileExists(atPath: paths.recordURL.path) else {
            throw ControllerError.invalidRecord
        }
        let record = try loadRecord()
        guard processIsAlive(record.pid) else {
            try removeStaleArtifacts()
            throw ControllerError.helperNotRunning
        }
        try record.validateForAdoption(expectation: expectation)
        let connection = try await authenticate(
            record: record,
            token: token,
            launchedNewHelper: false
        )
        if let activeConnection,
           activeConnection.record.helperID != connection.record.helperID {
            throw ControllerError.helperIdentityMismatch
        }
        activeConnection = connection
        capStderrLogIfDue()
        return connection
    }

    func shutdown() async throws {
        let connection: ManagedLocationHelperConnection
        if let activeConnection {
            connection = activeConnection
        } else {
            guard fileManager.fileExists(atPath: paths.recordURL.path) else { return }
            let token = try paths.prepare(fileManager: fileManager)
            let expectation = try makeExpectation(token: token)
            let record = try loadRecord()
            guard processIsAlive(record.pid) else {
                try removeStaleArtifacts()
                return
            }
            try record.validateForAdoption(expectation: expectation)
            connection = try await authenticate(
                record: record,
                token: token,
                launchedNewHelper: false
            )
        }

        let response: ManagedLocationHelperPingResponse = try await connection.client.send(
            ManagedLocationHelperCommand(cmd: "quit"),
            responseType: ManagedLocationHelperPingResponse.self
        )
        guard response.success,
              UUID(uuidString: response.helperID) == connection.record.helperID else {
            throw ControllerError.helperIdentityMismatch
        }

        for _ in 0..<250 {
            let recordExists = fileManager.fileExists(atPath: paths.recordURL.path)
            let socketExists = fileManager.fileExists(atPath: paths.socketURL.path)
            if !recordExists, !socketExists {
                activeConnection = nil
                launchedProcess = nil
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ControllerError.shutdownTimedOut
    }

    func currentRecord() throws -> ManagedLocationHelperRecord? {
        guard fileManager.fileExists(atPath: paths.recordURL.path) else { return nil }
        return try loadRecord()
    }

    /// Held sessions listed by a helper whose recorded process is still alive.
    func liveRecordedSessions() -> [ManagedLocationHelperSession] {
        guard let record = try? currentRecord(), processIsAlive(record.pid) else { return [] }
        return record.activeSessions
    }

    private func authenticate(
        record: ManagedLocationHelperRecord,
        token: String,
        launchedNewHelper: Bool
    ) async throws -> ManagedLocationHelperConnection {
        let client = ManagedLocationHelperClient(socketPath: paths.socketURL.path, token: token)
        let ping: ManagedLocationHelperPingResponse = try await client.send(
            ManagedLocationHelperCommand(cmd: "ping"),
            responseType: ManagedLocationHelperPingResponse.self
        )
        guard ping.success, UUID(uuidString: ping.helperID) == record.helperID else {
            throw ControllerError.helperIdentityMismatch
        }
        return ManagedLocationHelperConnection(
            client: client,
            record: record,
            launchedNewHelper: launchedNewHelper
        )
    }

    private func makeExpectation(token: String) throws -> ManagedLocationHelperExpectation {
        let canonicalPythonPath = URL(fileURLWithPath: pythonPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalBridgePath = URL(fileURLWithPath: bridgePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        return ManagedLocationHelperExpectation(
            socketPath: paths.socketURL.path,
            pythonPath: canonicalPythonPath,
            pythonSHA256: try sha256(fileAtPath: canonicalPythonPath),
            bridgePath: canonicalBridgePath,
            bridgeSHA256: try sha256(fileAtPath: canonicalBridgePath),
            tokenSHA256: sha256(data: Data(token.utf8))
        )
    }

    private func loadRecord() throws -> ManagedLocationHelperRecord {
        let values = try paths.recordURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ControllerError.unsafeRecord }
        let attributes = try fileManager.attributesOfItem(atPath: paths.recordURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else {
            throw ControllerError.unsafeRecord
        }
        do {
            let data = try Data(contentsOf: paths.recordURL)
            return try JSONDecoder().decode(ManagedLocationHelperRecord.self, from: data)
        } catch let error as ControllerError {
            throw error
        } catch {
            throw ControllerError.invalidRecord
        }
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private func removeStaleArtifacts() throws {
        if fileManager.fileExists(atPath: paths.socketURL.path) {
            try fileManager.removeItem(at: paths.socketURL)
        }
        if fileManager.fileExists(atPath: paths.recordURL.path) {
            try fileManager.removeItem(at: paths.recordURL)
        }
    }

    private func removeOwnedArtifacts() throws {
        try removeStaleArtifacts()
    }

    private func sha256(fileAtPath path: String) throws -> String {
        try sha256(data: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe))
    }

    private func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// FIFO admission for location commands (PRODUCT_REQUIREMENTS 8: serialize persistent
/// bridge requests). A second caller waits its turn; the single-slot gate alone threw
/// "request in progress" at it (a double click on Move, a queued update meeting a
/// direct one).
@MainActor
final class PersistentBridgeRequestSerializer {
    private var busy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    /// Waits for the slot. A caller cancelled while waiting leaves the queue and throws
    /// CancellationError: its command must never reach the device (review 2026-11-01).
    func acquire() async throws {
        try Task.checkCancellation()
        guard busy else {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await enqueue(id)
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(id) }
        }
    }

    private func enqueue(_ id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiters.append((id, continuation))
        }
    }

    /// Hands the slot to the next waiter, in arrival order.
    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

struct PersistentBridgeRequestGate {
    private var pending: (requestID: UUID, generation: UInt64)?

    mutating func begin(requestID: UUID, generation: UInt64) throws {
        guard pending == nil else {
            throw PersistentLocationBridge.PersistentBridgeError.requestInProgress
        }
        pending = (requestID, generation)
    }

    func accepts(requestID: UUID, generation: UInt64) -> Bool {
        pending?.requestID == requestID && pending?.generation == generation
    }

    mutating func finish(requestID: UUID, generation: UInt64) {
        guard accepts(requestID: requestID, generation: generation) else { return }
        pending = nil
    }

    mutating func cancel() {
        pending = nil
    }
}

struct PersistentBridgeReadinessGate {
    private(set) var isReady = false

    mutating func consume(ready: Bool) -> Bool {
        guard ready, !isReady else { return false }
        isReady = true
        return true
    }
}

struct PersistentBridgeTerminationEvents {
    private var consumed = false

    mutating func consume(
        exitCode: Int32,
        intentional: Bool,
        session: LocationSessionIdentity?
    ) -> [LocationBridgeEvent] {
        guard !consumed else { return [] }
        consumed = true
        var events: [LocationBridgeEvent] = [.processTerminated(exitCode: exitCode)]
        if let session {
            events.append(.sessionLost(
                session,
                reason: intentional ? "intentional stop" : "unexpected process exit"
            ))
        }
        return events
    }
}

struct PersistentBridgeWireRequest: Codable {
    let cmd: String
    var request_id: UUID = UUID()
    var session_generation: UInt64 = 0
    var lat: Double?
    var lng: Double?
    var udid: String?
    var rsd_address: String?
    var rsd_port: Int?
    var connection_type: String?
}

struct PersistentBridgeWireResponse: Codable, Sendable {
    let success: Bool
    var request_id: UUID?
    var session_generation: UInt64?
    var error: String?
    var code: String?
    var message: String?
    var ready: Bool?
    var channel: String?
    var endpoint_class: String?
    /// Device-connection commands (connect_device / connection_status).
    var connected: Bool?
    var reason: String?
    var replaced: Bool?
    /// Developer Disk Image commands (ddi_status / ddi_mount).
    var mounted: Bool?

    /// The Python helper emits `actual_channel` on socket responses
    /// (scripts/location_bridge.py set_location/clear_location success
    /// payloads). The Swift property stays `channel`; only the wire key
    /// changes. Pinned by the golden-fixture test.
    enum CodingKeys: String, CodingKey {
        case success
        case request_id
        case session_generation
        case error
        case code
        case message
        case ready
        case channel = "actual_channel"
        case endpoint_class
        case connected
        case reason
        case replaced
        case mounted
    }

    var invalidatesManagedHelperState: Bool {
        code == "UNAUTHORIZED"
    }

    func acknowledgement(
        physicalTransport: LocationTransport
    ) throws -> LocationProviderAcknowledgement {
        guard success,
              let requestID = request_id,
              let generation = session_generation,
              let channel,
              let endpoint_class,
              let endpointClass = LocationEndpointClass(rawValue: endpoint_class),
              let acknowledgement = LocationProviderAcknowledgement(
                  requestID: requestID,
                  sessionGeneration: generation,
                  physicalTransport: physicalTransport,
                  channel: LocationDVTChannel(rawValue: channel),
                  endpointClass: endpointClass
              ) else {
            throw PersistentLocationBridge.PersistentBridgeError.invalidResponse(
                error ?? "Missing or inconsistent provider acknowledgement"
            )
        }
        return acknowledgement
    }
}

// MARK: - Persistent Location Bridge

/// A high-performance bridge that maintains persistent Python processes
/// for efficient location injection. Significantly reduces overhead for
/// high-frequency operations like joystick control.
///
/// Performance Improvement:
/// - Traditional: ~100ms per location update (process creation overhead)
/// - Persistent: ~10-20ms per location update (reuses process)
@MainActor
final class PersistentLocationBridge: ObservableObject, ManagedLocationSessionSource, DeviceConnectionOpening {

    // MARK: - Types

    /// Request to send to Python bridge
    private typealias BridgeRequest = PersistentBridgeWireRequest

    /// Response from Python bridge
    private typealias BridgeResponse = PersistentBridgeWireResponse

    /// Errors specific to persistent bridge
    enum PersistentBridgeError: Error, LocalizedError, Equatable {
        case processNotRunning
        case requestInProgress
        case processStartFailed(String)
        case timeout
        case invalidResponse(String)
        case bridgeError(String)
        /// usbmux does not list the phone right now (an idle or locked Wi-Fi phone
        /// drops out); waiting can succeed. Carries the helper's per-lane detail.
        case deviceNotVisible(String)
        /// macOS refused every mDNS query the helper sent (Local Network privacy), so its
        /// Wi-Fi lanes could not see the phone; waiting cannot help. The helper's detail.
        case localNetworkBlocked(String)
        case pythonNotFound

        var errorDescription: String? {
            switch self {
            case .processNotRunning:
                return "Python bridge process is not running"
            case .requestInProgress:
                return "Another persistent bridge request is already in progress"
            case .processStartFailed(let reason):
                return "Failed to start Python bridge: \(reason)"
            case .timeout:
                return "Bridge request timed out"
            case .invalidResponse(let response):
                return "Invalid response from bridge: \(response)"
            case .bridgeError(let message):
                return "Bridge error: \(message)"
            case .deviceNotVisible(let detail):
                // Transport-neutral; the detail keeps the provider markers
                // (DeviceNotFoundError) the connection-loss classifier matches.
                return "The iPhone is not visible to this Mac right now (\(detail))"
            case .localNetworkBlocked(let detail):
                return "macOS is blocking PathChanger from the local network (\(detail))"
            case .pythonNotFound:
                return "Python3 not found in PATH"
            }
        }
    }

    /// What to do with the adopted helper before opening a device connection through it.
    enum ForeignHelperDecision: Equatable {
        case keep
        /// Foreign (an earlier PathChanger's) and holding no live connection: macOS may
        /// deny it the local network, so a new helper under this app opens the connection.
        case replace
    }

    nonisolated static func foreignHelperDecision(
        isForeign: Bool,
        status: HelperConnectionStatus
    ) -> ForeignHelperDecision {
        // An orphan with a live connection keeps it (usbmux lanes survive a relaunch).
        isForeign && status != .connected ? .replace : .keep
    }

    /// Maps a failed `connect_device` reply to the error the app acts on. The helper's
    /// typed `local_network_blocked` code wins over its "not visible" reason.
    static func connectFailure(error: String?, reason: String?, code: String? = nil) -> PersistentBridgeError {
        let detail = error ?? "Device connection failed"
        if code == localNetworkBlockedCode { return .localNetworkBlocked(detail) }
        return reason == "device_not_visible" ? .deviceNotVisible(detail) : .bridgeError(detail)
    }

    /// The helper's `connect_device` code for a Local Network block (scripts/location_bridge.py).
    nonisolated static let localNetworkBlockedCode = "local_network_blocked"

    // MARK: - Properties

    /// Shared instance for app-wide usage
    static let shared = PersistentLocationBridge()

    /// Whether the bridge process is currently running
    @Published private(set) var isRunning: Bool = false

    /// Last error encountered
    @Published private(set) var lastError: Error?

    /// Performance statistics
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var averageResponseTime: TimeInterval = 0

    /// Sessions recovered from a validated managed-helper identity record.
    @Published private(set) var adoptedHelperID: UUID?
    @Published private(set) var adoptedHelperSessions: [ManagedLocationHelperSession] = []

    // Private properties
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    // This type is `@MainActor`, so `responseBuffer`, `pendingContinuation` and
    // `timeoutTask` are already serialized by actor isolation. An explicit lock would be
    // redundant here and cannot be held safely across an `await`.
    private var responseBuffer: String = ""
    private var pendingContinuation: CheckedContinuation<BridgeResponse, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var readyContinuation: CheckedContinuation<Bool, Never>?
    private var readyTimeoutTask: Task<Void, Never>?
    private var requestGate = PersistentBridgeRequestGate()
    private let requestSerializer = PersistentBridgeRequestSerializer()
    private var readinessGate = PersistentBridgeReadinessGate()
    private var terminationEvents = PersistentBridgeTerminationEvents()
    private let eventHub = PersistentBridgeEventHub()
    private var currentSession: LocationSessionIdentity?
    private var isIntentionalStop = false
    private var isStarting = false
    private var processGeneration: UInt64 = 0
    private var helperController: ManagedLocationHelperController?
    private var helperConnection: ManagedLocationHelperConnection?
    /// Held sessions a replaced foreign helper listed (see `takeInheritedHeldSession`),
    /// with AppState's Clear counter when they were inherited.
    private var inheritedHeldSessions: (helperID: UUID, sessions: [ManagedLocationHelperSession], clearEpoch: UInt64?)?
    private var inheritedSessionClearEpochSource: (@MainActor () -> UInt64)?
    /// A foreign-helper replacement in flight; concurrent connects wait for it.
    private var helperReplacement: Task<Void, Error>?

    private var python3Path: String { PythonPathResolver.path }
    private var bridgeScriptPath: String?

    private let responseTimeout: TimeInterval = 10.0
    private var responseTimeAccumulator: TimeInterval = 0
    private var usesTunnelTransport: Bool = false

    /// Tunnel process PID backing the cached tunnel-transport session. When the
    /// live tunnel PID diverges, the cached RSD endpoint belongs to a dead
    /// tunnel and must be invalidated before the next request is built
    /// (live root cause 2026-10-24/31: stale endpoints dialled after reconnect).
    private var cachedTunnelPID: pid_t?

    /// Detects a cached tunnel-transport session whose backing tunnel process
    /// was replaced (reconnect/relaunch). Known cached PID vs nil live PID =
    /// tunnel gone = stale; nil cached PID with a known live PID is also stale
    /// (the cached session predates PID knowledge — conservatively invalidated).
    nonisolated static func isStaleTunnelSession(
        cachedPID: pid_t?,
        livePID: pid_t?,
        usesTunnel: Bool
    ) -> Bool {
        guard usesTunnel else { return false }
        guard cachedPID != livePID else { return false }
        return cachedPID != nil || livePID != nil
    }

    // MARK: - Initialization

    private init() {
        findPaths()
    }

    init(helperController: ManagedLocationHelperController) {
        self.helperController = helperController
        findPaths()
    }

    /// Find Python and bridge script paths
    private func findPaths() {
        // Find bridge script (in app bundle or workspace)
        let bundlePath = Bundle.main.path(forResource: "location_bridge", ofType: "py")
        let workspacePath = FileManager.default.currentDirectoryPath + "/scripts/location_bridge.py"

        // Try bundle first, then workspace
        if let bundlePath = bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
            bridgeScriptPath = bundlePath
        } else if FileManager.default.fileExists(atPath: workspacePath) {
            bridgeScriptPath = workspacePath
        } else {
            // Try relative to executable
            if let execPath = Bundle.main.executablePath {
                let execDir = (execPath as NSString).deletingLastPathComponent
                let relativePath = (execDir as NSString).appendingPathComponent("../Resources/scripts/location_bridge.py")
                if FileManager.default.fileExists(atPath: relativePath) {
                    bridgeScriptPath = relativePath
                }
            }
        }

        Logger.debug("[PersistentBridge] Python path: \(python3Path)", category: .device)
        Logger.debug("[PersistentBridge] Bridge script: \(bridgeScriptPath ?? "not found")", category: .device)
    }

    // MARK: - Public Methods

    /// Start or adopt the authenticated managed location helper.
    func start() async throws {
        guard !isRunning else {
            Logger.debug("[PersistentBridge] Already running", category: .device)
            return
        }
        guard !isStarting else {
            throw PersistentBridgeError.requestInProgress
        }
        isStarting = true
        defer { isStarting = false }

        guard PythonPathResolver.isAvailable else {
            throw PersistentBridgeError.pythonNotFound
        }
        let controller = try resolveHelperController()

        Logger.info("[PersistentBridge] Starting or adopting managed helper", category: .device)
        do {
            let connection = try await controller.connectOrLaunch()
            helperConnection = connection
            adoptedHelperID = connection.record.helperID
            adoptedHelperSessions = connection.record.activeSessions
            let adoptedGeneration = connection.record.activeSessions
                .map(\.sessionGeneration)
                .max() ?? 0
            processGeneration = max(processGeneration &+ 1, adoptedGeneration &+ 1)
            isIntentionalStop = false
            isRunning = true
            lastError = nil
            Logger.info(
                connection.launchedNewHelper
                    ? "[PersistentBridge] Managed helper started"
                    : "[PersistentBridge] Managed helper adopted",
                category: .device
            )
        } catch {
            helperConnection = nil
            isRunning = false
            lastError = error
            Logger.error(
                "[PersistentBridge] Managed helper unavailable: \(error.localizedDescription)",
                category: .device
            )
            throw PersistentBridgeError.processStartFailed(error.localizedDescription)
        }
    }

    func refreshAdoptedHelperSessions() async throws {
        guard isRunning, let helperController else {
            Logger.error("[PersistentBridge] Cannot refresh helper sessions: the helper is not running", category: .device)
            throw PersistentBridgeError.processNotRunning
        }
        let refreshedConnection = helperConnection
        do {
            let connection = try await helperController.refreshConnection()
            if let adoptedHelperID,
               adoptedHelperID != connection.record.helperID {
                throw ManagedLocationHelperController.ControllerError.helperIdentityMismatch
            }
            helperConnection = connection
            adoptedHelperID = connection.record.helperID
            adoptedHelperSessions = connection.record.activeSessions
        } catch {
            Logger.error(
                "[PersistentBridge] Refreshing helper sessions failed: " +
                LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .device
            )
            invalidateManagedHelperState(after: error, failedOn: refreshedConnection)
            throw error
        }
    }

    /// Stop the managed helper through its authenticated control channel.
    func stop() async {
        do {
            try await shutdownHelper()
        } catch {
            lastError = error
            Logger.error(
                "[PersistentBridge] Managed helper shutdown failed: \(error.localizedDescription)",
                category: .device
            )
        }
    }

    /// The managed-helper controller (injected in tests, otherwise built once for the
    /// production Application Support location).
    private func resolveHelperController() throws -> ManagedLocationHelperController {
        if let helperController {
            return helperController
        }
        guard let scriptPath = bridgeScriptPath else {
            throw PersistentBridgeError.processStartFailed("Bridge script not found")
        }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersistentBridgeError.processStartFailed("Application Support is unavailable")
        }
        let paths = ManagedLocationHelperPaths(
            baseDirectory: applicationSupport
                .appendingPathComponent("PathChanger", isDirectory: true)
                .appendingPathComponent("location-helper", isDirectory: true)
        )
        let controller = ManagedLocationHelperController(
            paths: paths,
            pythonPath: python3Path,
            bridgePath: scriptPath,
            stderrLogURL: ManagedLocationHelperStderrLog.defaultURL
        )
        helperController = controller
        return controller
    }

    var hasRecordedHeldSessions: Bool {
        guard let controller = try? resolveHelperController() else { return false }
        return !controller.liveRecordedSessions().isEmpty
    }

    func shutdownHelper() async throws {
        guard isRunning else {
            // This session never started or adopted the helper, but one left by an
            // earlier session may still be running; the controller adopts it from its
            // validated identity record and stops it (no record = nothing to stop).
            // This session never relied on it, so a failure here (for example a record
            // written by a different build) is logged and must not block quit.
            guard let controller = try? resolveHelperController() else { return }
            isIntentionalStop = true
            do {
                try await controller.shutdown()
                Logger.info("[PersistentBridge] Managed helper from an earlier session stopped", category: .device)
            } catch {
                Logger.error(
                    "[PersistentBridge] Helper from an earlier session was left running: \(error.localizedDescription)",
                    category: .device
                )
            }
            return
        }
        guard let helperController else {
            throw PersistentBridgeError.processNotRunning
        }
        isIntentionalStop = true
        try await helperController.shutdown()
        helperConnection = nil
        isRunning = false
        usesTunnelTransport = false
        cachedTunnelPID = nil
        currentSession = nil
        adoptedHelperID = nil
        adoptedHelperSessions = []
        requestGate = PersistentBridgeRequestGate()
        readinessGate = PersistentBridgeReadinessGate()
        Logger.info("[PersistentBridge] Managed helper stopped", category: .device)
    }

    /// Set location on device using persistent bridge
    /// - Parameters:
    ///   - coordinate: The location to simulate
    ///   - device: Target device
    /// - Throws: PersistentBridgeError on failure
    func setLocation(
        _ coordinate: LocationCoordinate,
        for device: Device,
        requestID: UUID = UUID(),
        sessionGeneration: UInt64? = nil
    ) async throws -> LocationProviderAcknowledgement {
        try ArgumentSanitizer.validateDeviceUDID(device.id)
        guard !suspendedDeviceIDs.contains(device.id) else {
            throw PersistentBridgeError.bridgeError(
                "The device connection was stopped. Press Move or Start Tunnel to connect again."
            )
        }

        // Auto-start if not running (waiting out a start already in flight)
        try await startIfNeeded()

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }

        let physicalTransport: LocationTransport = device.connectionType == .wifi ? .wifi : .usb
        let pythonConnectionType = physicalTransport.helperWireValue
        try await ensureDeviceConnection(for: device)

        let liveTunnelPID = rsdInfo?.processId
        if Self.isStaleTunnelSession(
            cachedPID: cachedTunnelPID,
            livePID: liveTunnelPID,
            usesTunnel: usesTunnelTransport
        ) {
            // Tunnel process was replaced (reconnect/relaunch): the cached RSD
            // endpoint belongs to a dead tunnel (live root cause 2026-10-24/31).
            Logger.error(
                "[PersistentBridge] Tunnel PID changed \(String(describing: cachedTunnelPID)) -> \(String(describing: liveTunnelPID)); invalidating stale RSD session",
                category: .device
            )
            currentSession = nil
            usesTunnelTransport = false
        }
        cachedTunnelPID = liveTunnelPID

        var request = BridgeRequest(cmd: "set_location")
        request.lat = coordinate.latitude
        request.lng = coordinate.longitude
        request.udid = device.id
        request.connection_type = pythonConnectionType
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        request.request_id = requestID
        request.session_generation = sessionGeneration ?? processGeneration
        usesTunnelTransport = rsdInfo != nil
        currentSession = LocationSessionIdentity(
            stableDeviceID: device.id,
            transport: device.connectionType == .wifi ? .wifi : .usb,
            endpointClass: rsdInfo == nil ? .direct : .remoteServiceDiscovery,
            generation: request.session_generation
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let response: BridgeResponse
        do {
            response = try await sendCommand(request)
        } catch {
            currentSession = nil
            throw error
        }
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Update stats
        requestCount += 1
        responseTimeAccumulator += duration
        averageResponseTime = responseTimeAccumulator / Double(requestCount)

        if !response.success {
            // The helper closes the connection a location command failed on.
            currentSession = nil
            Logger.error(
                "[PersistentBridge] set_location failed (generation \(request.session_generation)): " +
                LogRedaction.redactingDeviceIdentifiers(response.error ?? "Unknown error"),
                category: .device,
                repeatKey: "PersistentBridge.set_location"
            )
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }
        // The command reached the device: end the failure run under this key (shared by
        // the transport-failure line in `logCommandFailure` and the line above).
        Logger.endRepeats(key: "PersistentBridge.set_location", category: .device)

        let acknowledgement = try response.acknowledgement(physicalTransport: physicalTransport)
        usesTunnelTransport = acknowledgement.endpointClass == .remoteServiceDiscovery
        currentSession = LocationSessionIdentity(
            stableDeviceID: device.id,
            transport: acknowledgement.physicalTransport,
            endpointClass: acknowledgement.endpointClass,
            generation: acknowledgement.sessionGeneration
        )

        try await refreshAdoptedHelperSessions()
        try confirmDurableApplication(
            acknowledgement,
            coordinate: coordinate,
            deviceID: device.id
        )

        Logger.debug("[PersistentBridge] Location set in \(String(format: "%.1f", duration * 1000))ms", category: .device)
        return acknowledgement
    }

    /// Clear simulated location on device and acknowledge the channel that reset it.
    func clearLocation(
        for device: Device,
        requestID: UUID = UUID(),
        sessionGeneration: UInt64? = nil
    ) async throws -> LocationProviderAcknowledgement {
        try ArgumentSanitizer.validateDeviceUDID(device.id)

        // Auto-start if not running (waiting out a start already in flight)
        try await startIfNeeded()

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }
        let physicalTransport: LocationTransport = device.connectionType == .wifi ? .wifi : .usb
        try await ensureDeviceConnection(for: device)

        let liveTunnelPID = rsdInfo?.processId
        if Self.isStaleTunnelSession(
            cachedPID: cachedTunnelPID,
            livePID: liveTunnelPID,
            usesTunnel: usesTunnelTransport
        ) {
            // Tunnel process was replaced (reconnect/relaunch): the cached RSD
            // endpoint belongs to a dead tunnel (live root cause 2026-10-24/31).
            Logger.error(
                "[PersistentBridge] Tunnel PID changed \(String(describing: cachedTunnelPID)) -> \(String(describing: liveTunnelPID)); invalidating stale RSD session",
                category: .device
            )
            currentSession = nil
            usesTunnelTransport = false
        }
        cachedTunnelPID = liveTunnelPID

        var request = BridgeRequest(cmd: "clear_location")
        request.udid = device.id
        request.connection_type = physicalTransport.helperWireValue
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        request.request_id = requestID
        request.session_generation = sessionGeneration ?? processGeneration

        let response = try await sendCommand(request)

        if !response.success {
            Logger.error(
                "[PersistentBridge] clear_location failed (generation \(request.session_generation)): " +
                LogRedaction.redactingDeviceIdentifiers(response.error ?? "Unknown error"),
                category: .device
            )
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }

        let acknowledgement = try response.acknowledgement(physicalTransport: physicalTransport)
        usesTunnelTransport = acknowledgement.endpointClass == .remoteServiceDiscovery
        do {
            try await refreshAdoptedHelperSessions()
            try confirmDurableClear(for: device.id)
        } catch {
            Logger.error(
                "[PersistentBridge] The helper reported the Clear done, but confirming it failed: " +
                LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .device
            )
            throw error
        }
        currentSession = nil
        return acknowledgement
    }

    /// The helper's Clear over its own device connection, for a device the injector holds
    /// no session for. The helper keeps one connection per device whatever the transport
    /// hint, and its Clear is idempotent and device-wide. The caller probes first
    /// (`deviceConnectionStatus`), but this is the normal Clear path: after a relaunch
    /// `currentSession` is nil, so `ensureDeviceConnection` sends `connect_device` before
    /// the Clear. That is cheap on the live connection the probe found; if the link or
    /// the helper died after the probe it can start the helper and wait out the 40 s
    /// connect budget. Unprivileged and bounded either way.
    func clearLocationOverDeviceConnection(
        _ deviceId: String,
        transport: LocationTransport,
        sessionGeneration: UInt64?
    ) async throws {
        let device = Device(
            id: deviceId,
            displayName: deviceId,
            connectionType: transport == .wifi ? .wifi : .usb
        )
        _ = try await clearLocation(for: device, sessionGeneration: sessionGeneration)
    }

    var isHelperRunning: Bool { isRunning }

    // MARK: - Device connection (the app's single connection to the device)

    /// Opening a userspace tunnel takes ~1-2 s on a healthy link and is bounded at
    /// 30 s inside the helper; the reply must be awaited at least that long.
    private static let connectResponseTimeoutSeconds = 40
    /// The helper bounds its liveness probe at 5 s.
    private static let statusResponseTimeoutSeconds = 8
    /// The helper bounds a location command on an open connection at 10 s.
    private static let locationResponseTimeoutSeconds = 12
    /// The helper bounds a Developer Disk Image status check at 10 s and an auto-mount
    /// (download and personalization included) at 120 s.
    private static let diskImageStatusResponseTimeoutSeconds = 13
    private static let diskImageMountResponseTimeoutSeconds = 130

    /// Open (or reuse) the helper's connection to the device. Idempotent: the helper
    /// reuses an open connection, so this is also the preflight before every Move.
    func connectDevice(
        _ deviceId: String,
        transport: LocationTransport
    ) async throws -> HelperDeviceConnection {
        try ArgumentSanitizer.validateDeviceUDID(deviceId)
        try await startIfNeeded()
        try await replaceForeignHelperIfDisconnected(deviceId, transport: transport)
        do {
            return try await sendConnectDevice(deviceId, transport: transport)
        } catch PersistentBridgeError.localNetworkBlocked where helperController?.activeConnectionIsForeign == true {
            // An orphan kept for its live connection lost it and is denied the network.
            try await replaceForeignHelper(because: "macOS blocks its local network access")
            return try await sendConnectDevice(deviceId, transport: transport)
        }
    }

    /// Never open a device connection through a helper an earlier PathChanger launched
    /// unless it still holds a live one (live 2026-11-03: the orphan was denied the local
    /// network and lost its RemotePairing tunnel 0.85 s after its app exited). Its held
    /// sessions are read first, so the coordinate can be reapplied.
    func replaceForeignHelperIfDisconnected(_ deviceId: String, transport: LocationTransport) async throws {
        if let helperReplacement {
            try await helperReplacement.value
            return
        }
        guard let helperController, helperController.activeConnectionIsForeign else { return }
        let status = await deviceConnectionStatus(deviceId, transport: transport)
        guard Self.foreignHelperDecision(isForeign: helperController.activeConnectionIsForeign,
                                         status: status) == .replace else { return }
        try await replaceForeignHelper(because: "holds no device connection (\(status))")
    }

    private func replaceForeignHelper(because reason: String) async throws {
        if let helperReplacement {
            try await helperReplacement.value
            return
        }
        let replacement = Task { @MainActor in try await self.performForeignHelperReplacement(because: reason) }
        helperReplacement = replacement
        defer { helperReplacement = nil }
        try await replacement.value
    }

    private func performForeignHelperReplacement(because reason: String) async throws {
        // The controller's record, not the bridge's: a failed probe of a dead socket
        // already reset the bridge's view of the helper.
        guard let helperController, let adopted = helperController.activeRecord,
              helperController.isForeign(adopted) else { return }
        let current = try? helperController.currentRecord()
        let record = current?.helperID == adopted.helperID ? current ?? adopted : adopted
        Logger.info(
            "[PersistentBridge] The location helper (PID \(record.pid)) was started by an earlier PathChanger and "
                + LogRedaction.redactingDeviceIdentifiers(reason) + "; starting a new one under this app",
            category: .device
        )
        do {
            let fresh = try await helperController.replaceForeignHelper()
            helperConnection = fresh
            adoptedHelperID = fresh.record.helperID
            adoptedHelperSessions = fresh.record.activeSessions
            currentSession = nil
            usesTunnelTransport = false
            cachedTunnelPID = nil
            requestGate = PersistentBridgeRequestGate()
            readinessGate = PersistentBridgeReadinessGate()
            let inheritedGeneration = record.activeSessions.map(\.sessionGeneration).max() ?? 0
            processGeneration = max(processGeneration &+ 1, inheritedGeneration &+ 1)
            if !record.activeSessions.isEmpty {
                inheritedHeldSessions = (record.helperID, record.activeSessions, inheritedSessionClearEpochSource?())
            }
            isRunning = true
            Logger.info("[PersistentBridge] Managed helper started (replacing an earlier one)", category: .device)
        } catch {
            helperConnection = nil
            isRunning = false
            adoptedHelperID = nil
            adoptedHelperSessions = []
            currentSession = nil
            lastError = error
            Logger.error(
                "[PersistentBridge] Replacing the earlier helper failed: \(error.localizedDescription)",
                category: .device
            )
            throw PersistentBridgeError.processStartFailed(error.localizedDescription)
        }
    }

    func takeInheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession? {
        guard let inherited = inheritedHeldSessions,
              let index = inherited.sessions.firstIndex(where: { $0.matches(deviceID: deviceID) }) else {
            return nil
        }
        var remaining = inherited.sessions
        let session = remaining.remove(at: index)
        inheritedHeldSessions = remaining.isEmpty ? nil : (inherited.helperID, remaining, inherited.clearEpoch)
        return ManagedLocationInheritedSession(
            helperID: inherited.helperID,
            session: session,
            clearEpoch: inherited.clearEpoch
        )
    }

    func discardInheritedHeldSessions() {
        inheritedHeldSessions = nil
    }

    func inheritedHeldSession(for deviceID: String) -> ManagedLocationInheritedSession? {
        guard let inherited = inheritedHeldSessions,
              let session = inherited.sessions.first(where: { $0.matches(deviceID: deviceID) }) else {
            return nil
        }
        return ManagedLocationInheritedSession(
            helperID: inherited.helperID,
            session: session,
            clearEpoch: inherited.clearEpoch
        )
    }

    func setInheritedSessionClearEpochSource(_ source: @escaping @MainActor () -> UInt64) {
        inheritedSessionClearEpochSource = source
    }

    /// A location this app applied or cleared supersedes what a replaced helper held.
    private func discardInheritedHeldSessions(for deviceID: String) {
        guard let inherited = inheritedHeldSessions else { return }
        let remaining = inherited.sessions.filter { !$0.matches(deviceID: deviceID) }
        inheritedHeldSessions = remaining.isEmpty ? nil : (inherited.helperID, remaining, inherited.clearEpoch)
    }

    private func sendConnectDevice(
        _ deviceId: String,
        transport: LocationTransport
    ) async throws -> HelperDeviceConnection {
        var request = BridgeRequest(cmd: "connect_device")
        request.udid = deviceId
        request.connection_type = transport.helperWireValue
        let response = try await sendControlCommand(
            request,
            timeoutSeconds: Self.connectResponseTimeoutSeconds
        )
        guard response.success, response.connected == true else {
            Logger.error(
                "[PersistentBridge] connect_device failed: " +
                LogRedaction.redactingDeviceIdentifiers(response.error ?? response.reason ?? "not connected"),
                category: .device,
                repeatKey: "PersistentBridge.connect_device"
            )
            throw Self.connectFailure(error: response.error, reason: response.reason, code: response.code)
        }
        Logger.endRepeats(key: "PersistentBridge.connect_device", category: .device)
        guard let helperPID = helperConnection?.record.pid else {
            throw PersistentBridgeError.processNotRunning
        }
        return HelperDeviceConnection(
            helperPID: helperPID,
            channel: response.channel ?? "",
            replaced: response.replaced ?? false
        )
    }

    /// Start or adopt the helper, waiting for a start already in flight (a Move and
    /// Start Tunnel can race) instead of failing with `requestInProgress`.
    private func startIfNeeded() async throws {
        while isStarting {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if !isRunning {
            try await start()
        }
    }

    /// Open the device connection under the connect budget before the first location
    /// command on it: opening on demand inside a location request could outlast that
    /// request's reply timeout, leaving the GUI reporting failure while the helper
    /// later applied the location.
    /// The connection is opened with the mode-derived hint (`connectTransport(for:)`), not
    /// the row's type: a row last merged over USB kept a reopen after the cable was pulled
    /// in Auto mode off the helper's mobdev2 lane (review 2026-11-01 v3).
    private func ensureDeviceConnection(for device: Device) async throws {
        guard currentSession?.stableDeviceID != device.id else { return }
        do {
            _ = try await connectDevice(device.id, transport: connectTransport(for: device))
            Logger.endRepeats(key: "PersistentBridge.ensureDeviceConnection", category: .device)
        } catch {
            Logger.error(
                "[PersistentBridge] Opening the device connection failed: " +
                LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .device,
                repeatKey: "PersistentBridge.ensureDeviceConnection"
            )
            throw error
        }
    }

    /// Bounded liveness probe of the device connection. Never starts the helper.
    func deviceConnectionStatus(
        _ deviceId: String,
        transport: LocationTransport
    ) async -> HelperConnectionStatus {
        guard isRunning else { return .notConnected("location helper is not running") }
        // The probe runs every few seconds even while a held location is not moving, so
        // a long-running helper's stderr log stays capped (rate-limited inside).
        helperController?.capStderrLogIfDue()
        var request = BridgeRequest(cmd: "connection_status")
        request.udid = deviceId
        request.connection_type = transport.helperWireValue
        do {
            let response = try await sendControlCommand(
                request,
                timeoutSeconds: Self.statusResponseTimeoutSeconds
            )
            if response.success, response.connected == true {
                return .connected
            }
            return .notConnected(response.reason ?? response.error ?? "not connected")
        } catch {
            return .notConnected(error.localizedDescription)
        }
    }

    /// The helper's reply to `ddi_status`, in the preparer's terms. Any failure (no held
    /// connection, or the helper could not ask) leaves the decision to the command path.
    nonisolated static func diskImageStatus(from response: PersistentBridgeWireResponse) -> HelperDiskImageStatus {
        guard response.success else {
            return .unavailable(response.error ?? "Developer Disk Image status failed")
        }
        switch response.mounted {
        case true?: return .mounted
        case false?: return .notMounted
        case nil: return .unavailable("Developer Disk Image status reply had no mount status")
        }
    }

    /// The helper's reply to `ddi_mount`. Only "not connected" and `RSDRequiredError` let the
    /// command path try; any other mount the helper attempted and lost is a preparation
    /// failure. `auto_mount` over the usbmux-direct lockdown raises `RSDRequiredError` on
    /// iOS 27+, and the CLI `auto-mount` answers exactly that by retrying over a tunnel
    /// (review 2026-11-03 issue 10).
    nonisolated static func diskImageMountResult(from response: PersistentBridgeWireResponse) -> HelperDiskImageMountResult {
        if response.success, response.mounted == true { return .mounted }
        if !response.success, response.error == HelperDiskImageStatus.notConnectedDetail {
            return .unavailable(HelperDiskImageStatus.notConnectedDetail)
        }
        if !response.success, let error = response.error, error.hasPrefix("RSDRequiredError") {
            return .unavailable(error)
        }
        return .failed(response.error ?? "Developer Disk Image mount reply did not report a mounted image")
    }

    /// Open the helper's device connection so its Developer Disk Image commands can run
    /// (review 2026-11-03 issue 3). The same unprivileged `connect_device` path as Start and
    /// every Move; never while Stop Tunnel has blocked this device's location commands.
    func openDeviceConnectionForDiskImage(_ deviceId: String, transport: LocationTransport) async -> Bool {
        guard !suspendedDeviceIDs.contains(deviceId) else { return false }
        do {
            _ = try await connectDevice(deviceId, transport: transport)
            return true
        } catch {
            Logger.error(
                "[PersistentBridge] Opening the device connection for the Developer Disk Image check failed: "
                    + LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .device
            )
            return false
        }
    }

    /// Ask the helper, over the device connection it holds, whether a Developer Disk Image
    /// is mounted. Never starts the helper and never opens a connection.
    func ddiStatus(deviceId: String, transport: LocationTransport) async -> HelperDiskImageStatus {
        guard isRunning else { return .unavailable(HelperDiskImageStatus.helperNotRunningDetail) }
        guard (try? ArgumentSanitizer.validateDeviceUDID(deviceId)) != nil else {
            return .unavailable("invalid device identifier")
        }
        var request = BridgeRequest(cmd: "ddi_status")
        request.udid = deviceId
        request.connection_type = transport.helperWireValue
        do {
            let response = try await sendControlCommand(
                request,
                timeoutSeconds: Self.diskImageStatusResponseTimeoutSeconds
            )
            let status = Self.diskImageStatus(from: response)
            if case .unavailable(let detail) = status, detail != HelperDiskImageStatus.notConnectedDetail {
                Logger.error(
                    "[PersistentBridge] ddi_status failed: " + LogRedaction.redactingDeviceIdentifiers(detail),
                    category: .device,
                    repeatKey: "PersistentBridge.ddi_status"
                )
            }
            return status
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Auto-mount the Developer Disk Image over the helper's device connection. Never
    /// starts the helper. A helper that does not answer in time is a failed mount (it may
    /// still be mounting), never a reason to start a second mount over the command path.
    func ddiMount(deviceId: String, transport: LocationTransport) async -> HelperDiskImageMountResult {
        guard isRunning else { return .unavailable(HelperDiskImageStatus.helperNotRunningDetail) }
        guard (try? ArgumentSanitizer.validateDeviceUDID(deviceId)) != nil else {
            return .unavailable("invalid device identifier")
        }
        var request = BridgeRequest(cmd: "ddi_mount")
        request.udid = deviceId
        request.connection_type = transport.helperWireValue
        let result: HelperDiskImageMountResult
        do {
            let response = try await sendControlCommand(
                request,
                timeoutSeconds: Self.diskImageMountResponseTimeoutSeconds
            )
            result = Self.diskImageMountResult(from: response)
        } catch {
            result = .failed(error.localizedDescription)
        }
        if case .failed(let detail) = result {
            Logger.error(
                "[PersistentBridge] ddi_mount failed: " + LogRedaction.redactingDeviceIdentifiers(detail),
                category: .device
            )
        }
        return result
    }

    /// The health probe found the connection dead or stalled: reopen it under the
    /// connect budget before the next location command (the helper replaces it).
    func markDeviceConnectionUnverified(_ deviceId: String) {
        if currentSession?.stableDeviceID == deviceId {
            currentSession = nil
        }
    }

    /// PID of the running helper, or nil. Used to adopt an existing connection
    /// without ever launching a helper.
    func helperProcessIdentifierIfRunning() -> Int32? {
        isRunning ? helperConnection?.record.pid : nil
    }

    /// Close the helper's device connection. This ends any location held over it.
    /// Never starts the helper: with no helper there is no connection to close. When this
    /// app session never started or adopted the helper (`isRunning == false`) it returns
    /// true without asking anyone; callers that need evidence check `isHelperRunning`.
    @discardableResult
    func disconnectDevice(_ deviceId: String, transport: LocationTransport) async -> Bool {
        guard isRunning else { return true }
        var request = BridgeRequest(cmd: "disconnect_device")
        request.udid = deviceId
        request.connection_type = transport.helperWireValue
        let confirmed: Bool
        do {
            let response = try await sendControlCommand(
                request,
                timeoutSeconds: Self.statusResponseTimeoutSeconds
            )
            confirmed = response.success
        } catch {
            Logger.error(
                "[PersistentBridge] Device disconnect failed: \(error.localizedDescription)",
                category: .device
            )
            confirmed = false
        }
        if confirmed {
            currentSession = nil
            usesTunnelTransport = false
        }
        return confirmed
    }

    /// Devices whose location updates are refused until an explicit user action.
    private var suspendedDeviceIDs: Set<String> = []

    /// The transport hint for opening the helper's device connection, which decides
    /// whether the helper may try its mobdev2 lane. AppState wires it to the connection
    /// mode (`DeviceManager.helperConnectTransport(for:)`); nil keeps the row's type.
    var connectTransportProvider: (@MainActor (Device) -> LocationTransport?)?

    /// The hint `connect_device` sends. Location commands keep sending the session's
    /// transport, so each receipt's `physical_transport` is what that request asked;
    /// the helper keeps one connection per device whatever the hint.
    func connectTransport(for device: Device) -> LocationTransport {
        connectTransportProvider?(device) ?? (device.connectionType == .wifi ? .wifi : .usb)
    }

    var activeLocationDeviceId: String? { currentSession?.stableDeviceID }

    func suspendLocationCommands(for deviceId: String) {
        suspendedDeviceIDs.insert(deviceId)
    }

    func resumeLocationCommands(for deviceId: String) {
        suspendedDeviceIDs.remove(deviceId)
    }

    /// Connection commands bypass the single-flight location gate: the helper serves
    /// each socket client concurrently, and a liveness probe must not wait behind (or
    /// fail because of) an in-flight location update.
    private func sendControlCommand(
        _ request: BridgeRequest,
        timeoutSeconds: Int
    ) async throws -> BridgeResponse {
        guard let helperConnection else {
            throw PersistentBridgeError.processNotRunning
        }
        do {
            let response = try await helperConnection.client.send(
                request,
                responseType: BridgeResponse.self,
                timeoutSeconds: timeoutSeconds
            )
            if response.invalidatesManagedHelperState {
                let error = PersistentBridgeError.bridgeError(
                    response.error ?? "Managed helper authentication failed"
                )
                invalidateManagedHelperState(after: error, failedOn: helperConnection)
                throw error
            }
            return response
        } catch let error as PersistentBridgeError {
            throw error
        } catch let error as ManagedLocationHelperClient.ClientError {
            if error.invalidatesManagedHelperState {
                invalidateManagedHelperState(after: error, failedOn: helperConnection)
            }
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        }
    }

    /// Health check for the bridge
    func ping() async throws -> Bool {
        guard isRunning else { return false }

        let response = try await sendCommand(BridgeRequest(cmd: "ping"))
        return response.success
    }

    // MARK: - Private Methods

    private func confirmDurableApplication(
        _ acknowledgement: LocationProviderAcknowledgement,
        coordinate: LocationCoordinate,
        deviceID: String
    ) throws {
        discardInheritedHeldSessions(for: deviceID)
        guard let helperID = adoptedHelperID else {
            throw PersistentBridgeError.invalidResponse("Managed helper identity is unavailable")
        }
        let matches = adoptedHelperSessions.filter { $0.matches(deviceID: deviceID) }
        guard matches.count == 1,
              let persisted = matches.first?.locationReceipt(helperID: helperID),
              persisted.requestID == acknowledgement.requestID,
              persisted.sessionGeneration == acknowledgement.sessionGeneration,
              persisted.transport == acknowledgement.physicalTransport,
              persisted.actualChannel == acknowledgement.channel,
              persisted.endpointClass == acknowledgement.endpointClass,
              persisted.coordinate == coordinate else {
            Logger.error(
                "[PersistentBridge] Durable-application check failed after provider success: " +
                "matchingSessions=\(matches.count) " +
                "recordTransport=\(matches.first?.physicalTransport ?? "nil") " +
                "recordChannel=\(matches.first?.actualChannel ?? "nil") " +
                "receiptParsed=\(matches.first?.locationReceipt(helperID: helperID) != nil) " +
                "ackChannel=\(acknowledgement.channel.rawValue)",
                category: .device
            )
            throw PersistentBridgeError.invalidResponse(
                "Managed helper did not persist the acknowledged location session"
            )
        }
    }

    private func confirmDurableClear(for deviceID: String) throws {
        discardInheritedHeldSessions(for: deviceID)
        guard adoptedHelperID != nil else {
            Logger.error("[PersistentBridge] Durable-clear check failed: helper identity unavailable", category: .device)
            throw PersistentBridgeError.invalidResponse("Managed helper identity is unavailable")
        }
        let remaining = adoptedHelperSessions.filter { $0.matches(deviceID: deviceID) }.count
        guard remaining == 0 else {
            Logger.error(
                "[PersistentBridge] Durable-clear check failed: the helper record still lists " +
                "\(remaining) active session(s) for the device",
                category: .device
            )
            throw PersistentBridgeError.invalidResponse(
                "Managed helper still reports an active location session after Clear"
            )
        }
    }

    func events() -> AsyncStream<LocationBridgeEvent> {
        eventHub.stream()
    }

    private func emit(_ event: LocationBridgeEvent) {
        eventHub.publish([event])
    }

    /// Wait for ready signal from Python process
    private func waitForReady() async throws -> Bool {
        if readinessGate.isReady { return true }
        return await withCheckedContinuation { continuation in
            readyContinuation = continuation
            readyTimeoutTask?.cancel()
            readyTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self, let pending = self.readyContinuation else { return }
                self.readyContinuation = nil
                self.readyTimeoutTask = nil
                pending.resume(returning: false)
            }
        }
    }

    /// A request failed in a way that means the helper it was sent to is gone or not ours.
    /// `failedOn` is the connection that request used (nil: no connection was held).
    func invalidateManagedHelperState(after error: Error, failedOn connection: ManagedLocationHelperConnection?) {
        // A late failure from a helper this bridge has since replaced (a request still in
        // flight when the orphan quit) is about that helper, not the current one (review
        // 2026-11-03 issue 2).
        if let connection, let current = helperConnection,
           current.record.helperID != connection.record.helperID {
            Logger.info(
                "[PersistentBridge] Ignoring a failure from the replaced helper (PID \(connection.record.pid)): "
                    + LogRedaction.redactingDeviceIdentifiers(error.localizedDescription),
                category: .device
            )
            return
        }
        helperConnection = nil
        isRunning = false
        usesTunnelTransport = false
        cachedTunnelPID = nil
        currentSession = nil
        adoptedHelperID = nil
        adoptedHelperSessions = []
        requestGate = PersistentBridgeRequestGate()
        readinessGate = PersistentBridgeReadinessGate()
        lastError = error
    }

    /// Send one authenticated command through the managed helper socket.
    private func sendCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
        try await requestSerializer.acquire()
        defer { requestSerializer.release() }
        // Handed the slot just as it was cancelled: still never send.
        try Task.checkCancellation()
        guard let helperConnection else {
            Logger.error("[PersistentBridge] \(request.cmd) not sent: the helper is not running", category: .device)
            throw PersistentBridgeError.processNotRunning
        }
        do {
            try requestGate.begin(requestID: request.request_id, generation: request.session_generation)
        } catch {
            Logger.error(
                "[PersistentBridge] \(request.cmd) not sent: another request is in flight",
                category: .device
            )
            throw error
        }
        defer {
            requestGate.finish(
                requestID: request.request_id,
                generation: request.session_generation
            )
        }

        do {
            // The helper bounds a location command at 10 s; wait longer so its own
            // honest error arrives instead of a client-side timeout.
            let response = try await helperConnection.client.send(
                request,
                responseType: BridgeResponse.self,
                timeoutSeconds: Self.locationResponseTimeoutSeconds
            )
            if response.invalidatesManagedHelperState {
                let error = PersistentBridgeError.bridgeError(
                    response.error ?? "Managed helper authentication failed"
                )
                invalidateManagedHelperState(after: error, failedOn: helperConnection)
                throw error
            }
            return response
        } catch let error as PersistentBridgeError {
            Self.logCommandFailure(request.cmd, error.localizedDescription)
            throw error
        } catch let error as ManagedLocationHelperClient.ClientError {
            if error.isResponseTimeout,
               request.cmd == "set_location" || request.cmd == "clear_location" {
                Logger.error("[PersistentBridge] \(request.cmd) timed out; reconciling from the helper record", category: .device)
                return try await reconcileTimedOutCommand(request, sentOn: helperConnection)
            }
            Self.logCommandFailure(request.cmd, error.localizedDescription)
            if error.invalidatesManagedHelperState {
                invalidateManagedHelperState(after: error, failedOn: helperConnection)
            } else {
                lastError = error
            }
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        } catch let error as EncodingError {
            Logger.error("[PersistentBridge] \(request.cmd) could not be encoded: \(error.localizedDescription)", category: .device)
            lastError = error
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        } catch {
            Self.logCommandFailure(request.cmd, error.localizedDescription)
            invalidateManagedHelperState(after: error, failedOn: helperConnection)
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        }
    }

    /// A failed command's line, with UDID-shaped tokens redacted. set_location failures
    /// are repeat-suppressed: the joystick retries at its update rate.
    private static func logCommandFailure(_ command: String, _ text: String) {
        let line = "[PersistentBridge] \(command) failed: " + LogRedaction.redactingDeviceIdentifiers(text)
        if command == "set_location" {
            Logger.error(line, category: .device, repeatKey: "PersistentBridge.set_location")
        } else {
            Logger.error(line, category: .device)
        }
    }

    private func reconcileTimedOutCommand(
        _ request: BridgeRequest,
        sentOn: ManagedLocationHelperConnection
    ) async throws -> BridgeResponse {
        guard let deviceID = request.udid,
              let controller = helperController else {
            throw PersistentBridgeError.timeout
        }

        var lastReconciliationError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            do {
                let connection = try await controller.refreshConnection()
                if let adoptedHelperID,
                   adoptedHelperID != connection.record.helperID {
                    throw ManagedLocationHelperController.ControllerError.helperIdentityMismatch
                }
                helperConnection = connection
                adoptedHelperID = connection.record.helperID
                adoptedHelperSessions = connection.record.activeSessions
                if let result = connection.record.recentResults?.last(where: {
                    $0.matches(
                        deviceID: deviceID,
                        requestID: request.request_id,
                        generation: request.session_generation
                    )
                }) {
                    lastError = nil
                    return try result.wireResponse()
                }
            } catch {
                lastReconciliationError = error
            }
        }

        let error = lastReconciliationError ?? PersistentBridgeError.timeout
        invalidateManagedHelperState(after: error, failedOn: sentOn)
        throw PersistentBridgeError.timeout
    }

    /// Handle output from Python process
    private func handleOutput(_ output: String) {
        responseBuffer += output

        // Check for complete JSON lines
        let lines = responseBuffer.components(separatedBy: "\n")
        responseBuffer = lines.last ?? ""

        for line in lines.dropLast() {
            guard !line.isEmpty else { continue }

            // Try to parse as JSON response
            if let data = line.data(using: .utf8),
               let response = try? JSONDecoder().decode(BridgeResponse.self, from: data) {

                // Check for ready signal
                if response.ready == true {
                    Logger.debug("[PersistentBridge] Received ready signal", category: .device)
                    if readinessGate.consume(ready: true), let pending = readyContinuation {
                        readyContinuation = nil
                        readyTimeoutTask?.cancel()
                        readyTimeoutTask = nil
                        pending.resume(returning: true)
                    }
                    continue
                }

                guard let responseID = response.request_id,
                      let responseGeneration = response.session_generation else {
                    Logger.info("[PersistentBridge] Ignoring response without request identity", category: .device)
                    continue
                }
                guard requestGate.accepts(requestID: responseID, generation: responseGeneration) else {
                    Logger.info("[PersistentBridge] Ignoring stale or mismatched response \(responseID)", category: .device)
                    continue
                }

                if let continuation = pendingContinuation {
                    pendingContinuation = nil
                    timeoutTask?.cancel()
                    timeoutTask = nil
                    requestGate.finish(requestID: responseID, generation: responseGeneration)
                    continuation.resume(returning: response)
                    return
                }
            }
        }
    }

    /// Handle process termination
    private func handleTermination(exitCode: Int32) {
        Logger.info("[PersistentBridge] Process terminated with exit code \(exitCode)", category: .device)

        isRunning = false

        if let pending = readyContinuation {
            readyContinuation = nil
            readyTimeoutTask?.cancel()
            readyTimeoutTask = nil
            pending.resume(returning: false)
        }
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            requestGate.cancel()
            continuation.resume(throwing: PersistentBridgeError.processNotRunning)
        }
        eventHub.publish(terminationEvents.consume(
            exitCode: exitCode,
            intentional: isIntentionalStop,
            session: currentSession
        ))
        cleanup()
    }

    /// Cleanup resources and reset gates for next generation
    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        stdinPipe?.fileHandleForReading.closeFile()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.closeFile()
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.closeFile()

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning = false
        responseBuffer = ""

        // Reset gates for next process generation while preserving semantics
        readinessGate = PersistentBridgeReadinessGate()
        terminationEvents = PersistentBridgeTerminationEvents()

        // Reset stats
        requestCount = 0
        averageResponseTime = 0
        responseTimeAccumulator = 0
        usesTunnelTransport = false
        cachedTunnelPID = nil
    }
}

@MainActor
final class PersistentBridgeEventHub {
    private var continuations: [UUID: AsyncStream<LocationBridgeEvent>.Continuation] = [:]

    func stream() -> AsyncStream<LocationBridgeEvent> {
        let id = UUID()
        let pair = AsyncStream<LocationBridgeEvent>.makeStream()
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations.removeValue(forKey: id) }
        }
        continuations[id] = pair.continuation
        return pair.stream
    }

    func publish(_ events: [LocationBridgeEvent]) {
        for event in events {
            continuations.values.forEach { $0.yield(event) }
        }
    }
}
