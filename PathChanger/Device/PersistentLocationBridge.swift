import CryptoKit
import Darwin
import Foundation

@MainActor
protocol ManagedLocationSessionSource: AnyObject {
    var adoptedHelperID: UUID? { get }
    var adoptedHelperSessions: [ManagedLocationHelperSession] { get }

    func start() async throws
    func refreshAdoptedHelperSessions() async throws
    func shutdownHelper() async throws
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
        responseType: Response.Type
    ) async throws -> Response {
        try await Task.detached(priority: .userInitiated) {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw ClientError.connectFailed(errno)
            }
            defer { Darwin.close(descriptor) }

            var timeout = timeval(tv_sec: 5, tv_usec: 0)
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
              let parsedTransport = LocationTransport(rawValue: physicalTransport),
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
            }
        }
    }

    private let paths: ManagedLocationHelperPaths
    private let pythonPath: String
    private let bridgePath: String
    private let fileManager: FileManager
    private var launchedProcess: Process?
    private var activeConnection: ManagedLocationHelperConnection?

    init(
        paths: ManagedLocationHelperPaths,
        pythonPath: String,
        bridgePath: String,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.pythonPath = pythonPath
        self.bridgePath = bridgePath
        self.fileManager = fileManager
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
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessEnvironment.configured()

        do {
            try process.run()
        } catch {
            throw ControllerError.launchFailed(error.localizedDescription)
        }
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
final class PersistentLocationBridge: ObservableObject, ManagedLocationSessionSource {

    // MARK: - Types

    /// Request to send to Python bridge
    private typealias BridgeRequest = PersistentBridgeWireRequest

    /// Stop the persistent bridge only when its cached connection was RSD/tunnel-backed.
    func stopIfUsingTunnel() async {
        guard usesTunnelTransport else { return }
        await stop()
    }

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
            case .pythonNotFound:
                return "Python3 not found in PATH"
            }
        }
    }

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
    private var readinessGate = PersistentBridgeReadinessGate()
    private var terminationEvents = PersistentBridgeTerminationEvents()
    private let eventHub = PersistentBridgeEventHub()
    private var currentSession: LocationSessionIdentity?
    private var isIntentionalStop = false
    private var isStarting = false
    private var processGeneration: UInt64 = 0
    private var helperController: ManagedLocationHelperController?
    private var helperConnection: ManagedLocationHelperConnection?

    private var python3Path: String { PythonPathResolver.path }
    private var bridgeScriptPath: String?

    private let responseTimeout: TimeInterval = 10.0
    private var responseTimeAccumulator: TimeInterval = 0
    private var usesTunnelTransport: Bool = false

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
        guard let scriptPath = bridgeScriptPath else {
            throw PersistentBridgeError.processStartFailed("Bridge script not found")
        }

        let controller: ManagedLocationHelperController
        if let helperController {
            controller = helperController
        } else {
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
            controller = ManagedLocationHelperController(
                paths: paths,
                pythonPath: python3Path,
                bridgePath: scriptPath
            )
            helperController = controller
        }

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
            throw PersistentBridgeError.processNotRunning
        }
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
            invalidateManagedHelperState(after: error)
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

    func shutdownHelper() async throws {
        guard isRunning else { return }
        guard let helperController else {
            throw PersistentBridgeError.processNotRunning
        }
        isIntentionalStop = true
        try await helperController.shutdown()
        helperConnection = nil
        isRunning = false
        usesTunnelTransport = false
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

        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }

        let physicalTransport: LocationTransport = device.connectionType == .wifi ? .wifi : .usb
        let pythonConnectionType = device.connectionType == .wifi ? "Network" : "USB"

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
        let response = try await sendCommand(request)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        // Update stats
        requestCount += 1
        responseTimeAccumulator += duration
        averageResponseTime = responseTimeAccumulator / Double(requestCount)

        if !response.success {
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }

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

        // Auto-start if not running
        if !isRunning {
            try await start()
        }

        let rsdInfo = await MainActor.run {
            TunneldManager.shared.getRsdInfo(for: device.id)
        }
        let physicalTransport: LocationTransport = device.connectionType == .wifi ? .wifi : .usb

        var request = BridgeRequest(cmd: "clear_location")
        request.udid = device.id
        request.connection_type = device.connectionType == .wifi ? "Network" : "USB"
        request.rsd_address = rsdInfo?.rsdAddress
        request.rsd_port = rsdInfo.map { Int($0.rsdPort) }
        request.request_id = requestID
        request.session_generation = sessionGeneration ?? processGeneration

        let response = try await sendCommand(request)

        if !response.success {
            throw PersistentBridgeError.bridgeError(response.error ?? "Unknown error")
        }

        let acknowledgement = try response.acknowledgement(physicalTransport: physicalTransport)
        usesTunnelTransport = acknowledgement.endpointClass == .remoteServiceDiscovery
        try await refreshAdoptedHelperSessions()
        try confirmDurableClear(for: device.id)
        currentSession = nil
        return acknowledgement
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
            throw PersistentBridgeError.invalidResponse(
                "Managed helper did not persist the acknowledged location session"
            )
        }
    }

    private func confirmDurableClear(for deviceID: String) throws {
        guard adoptedHelperID != nil else {
            throw PersistentBridgeError.invalidResponse("Managed helper identity is unavailable")
        }
        guard !adoptedHelperSessions.contains(where: { $0.matches(deviceID: deviceID) }) else {
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

    private func invalidateManagedHelperState(after error: Error) {
        helperConnection = nil
        isRunning = false
        usesTunnelTransport = false
        currentSession = nil
        adoptedHelperID = nil
        adoptedHelperSessions = []
        requestGate = PersistentBridgeRequestGate()
        readinessGate = PersistentBridgeReadinessGate()
        lastError = error
    }

    /// Send one authenticated command through the managed helper socket.
    private func sendCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
        guard let helperConnection else {
            throw PersistentBridgeError.processNotRunning
        }
        try requestGate.begin(requestID: request.request_id, generation: request.session_generation)
        defer {
            requestGate.finish(
                requestID: request.request_id,
                generation: request.session_generation
            )
        }

        do {
            let response = try await helperConnection.client.send(
                request,
                responseType: BridgeResponse.self
            )
            if response.invalidatesManagedHelperState {
                let error = PersistentBridgeError.bridgeError(
                    response.error ?? "Managed helper authentication failed"
                )
                invalidateManagedHelperState(after: error)
                throw error
            }
            return response
        } catch let error as PersistentBridgeError {
            throw error
        } catch let error as ManagedLocationHelperClient.ClientError {
            if error.isResponseTimeout,
               request.cmd == "set_location" || request.cmd == "clear_location" {
                return try await reconcileTimedOutCommand(request)
            }
            if error.invalidatesManagedHelperState {
                invalidateManagedHelperState(after: error)
            } else {
                lastError = error
            }
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        } catch let error as EncodingError {
            lastError = error
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        } catch {
            invalidateManagedHelperState(after: error)
            throw PersistentBridgeError.invalidResponse(error.localizedDescription)
        }
    }

    private func reconcileTimedOutCommand(_ request: BridgeRequest) async throws -> BridgeResponse {
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
        invalidateManagedHelperState(after: error)
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
