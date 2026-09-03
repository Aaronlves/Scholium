import CryptoKit
import Darwin
import Foundation
import ScholiumContracts
import Security

/// One request over the current-user authenticated App bridge. The transport
/// credential proves only that both processes are the current user's
/// Scholium processes; it is not research permission or an Agent identity.
public struct ScholiumAppBridgeRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let correlationID: UUID
    public let mcpRequest: ScholiumMCPBridgeRequest

    public init(
        correlationID: UUID = UUID(),
        mcpRequest: ScholiumMCPBridgeRequest
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.mcpRequest = mcpRequest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case mcpRequest = "mcp_request"
    }

    public init(from decoder: Decoder) throws {
        try AppBridgeCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ScholiumAppBridgeError.unsupportedVersion(version)
        }
        schemaVersion = version
        correlationID = try container.decode(UUID.self, forKey: .correlationID)
        mcpRequest = try container.decode(
            ScholiumMCPBridgeRequest.self,
            forKey: .mcpRequest
        )
    }
}

public struct ScholiumAppBridgeResponse: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let correlationID: UUID
    public let mcpResponse: ScholiumMCPBridgeResponse?
    public let error: ScholiumAppBridgeRemoteError?

    public init(
        correlationID: UUID,
        mcpResponse: ScholiumMCPBridgeResponse? = nil,
        error: ScholiumAppBridgeRemoteError? = nil
    ) throws {
        guard (mcpResponse == nil) != (error == nil) else {
            throw ScholiumAppBridgeError.invalidResponse
        }
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.mcpResponse = mcpResponse
        self.error = error
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case mcpResponse = "mcp_response"
        case error
    }

    public init(from decoder: Decoder) throws {
        try AppBridgeCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ScholiumAppBridgeError.unsupportedVersion(version)
        }
        try self.init(
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            mcpResponse: container.decodeIfPresent(
                ScholiumMCPBridgeResponse.self,
                forKey: .mcpResponse
            ),
            error: container.decodeIfPresent(
                ScholiumAppBridgeRemoteError.self,
                forKey: .error
            )
        )
    }
}

public struct ScholiumAppBridgeRemoteError: Codable, Hashable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ScholiumAppBridgeError: LocalizedError, Hashable, Sendable {
    case unavailable
    case invalidFrame
    case invalidRequest
    case invalidResponse
    case unsupportedVersion(Int)
    case permissionDenied
    case timeout
    case outcomeUnknown
    case alreadyRunning
    case remote(code: String, message: String)
    case systemCall(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "The running Scholium App bridge is unavailable."
        case .invalidFrame: "The Scholium App bridge frame is invalid."
        case .invalidRequest: "The Scholium App bridge request is invalid."
        case .invalidResponse: "The Scholium App bridge response is invalid."
        case .unsupportedVersion(let version):
            "The Scholium App bridge schema version \(version) is unsupported."
        case .permissionDenied:
            "The Scholium App bridge rejected current-user authentication."
        case .timeout: "The Scholium App bridge timed out before sending a request."
        case .outcomeUnknown:
            "The Scholium App bridge cannot determine whether the request completed."
        case .alreadyRunning: "Another Scholium App bridge already owns this endpoint."
        case .remote(_, let message): message
        case .systemCall(let operation, let code):
            "The Scholium App bridge could not \(operation): \(String(cString: strerror(code)))."
        }
    }
}

public enum ScholiumAppBridgeLocation {
    public static let maximumFrameByteCount = 1_024 * 1_024
    public static let timeout: TimeInterval = 5
    public static let operationTimeout: TimeInterval = 25
    public static let clientTimeout: TimeInterval = 30
    public static let authenticationFileName = "app-bridge-auth-v1"
    private static let firstPrivatePort: UInt16 = 49_152
    private static let privatePortCount: UInt64 = 16_384

    public static func port(applicationSupportURL: URL) -> UInt16 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in applicationSupportURL.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return firstPrivatePort + UInt16(hash % privatePortCount)
    }

    public static func authenticationURL(applicationSupportURL: URL) -> URL {
        applicationSupportURL.standardizedFileURL.appendingPathComponent(
            authenticationFileName,
            isDirectory: false
        )
    }
}

public final class ScholiumAppBridgeClient: @unchecked Sendable {
    private let containerURL: URL
    private let port: UInt16
    private let timeout: TimeInterval

    public init(
        applicationSupportURL: URL,
        timeout: TimeInterval = ScholiumAppBridgeLocation.clientTimeout
    ) throws {
        containerURL = applicationSupportURL.standardizedFileURL
        port = ScholiumAppBridgeLocation.port(applicationSupportURL: containerURL)
        self.timeout = min(max(timeout, 0.1), 30)
    }

    public func send(
        _ request: ScholiumAppBridgeRequest
    ) throws -> ScholiumAppBridgeResponse {
        try AppBridgeIO.validatePrivateDirectory(
            at: containerURL,
            createIfMissing: false
        )
        let secret = try AppBridgeIO.readSecret(
            at: ScholiumAppBridgeLocation.authenticationURL(
                applicationSupportURL: containerURL
            )
        )
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ScholiumAppBridgeError.systemCall("create its socket", errno)
        }
        defer { Darwin.close(descriptor) }
        try AppBridgeIO.configure(descriptor, timeout: timeout)
        var address = AppBridgeIO.address(port: port)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard connected == 0 else {
            if [ENOENT, ECONNREFUSED, ETIMEDOUT].contains(errno) {
                throw ScholiumAppBridgeError.unavailable
            }
            throw ScholiumAppBridgeError.systemCall("connect", errno)
        }
        var sent = false
        do {
            let clientNonce = try AppBridgeAuthentication.randomData(count: 32)
            try AppBridgeIO.writeFrame(clientNonce, to: descriptor)
            let challenge = try AppBridgeIO.readFrame(from: descriptor)
            guard challenge.count == 64 else {
                throw ScholiumAppBridgeError.permissionDenied
            }
            let serverNonce = Data(challenge.prefix(32))
            let serverTag = Data(challenge.suffix(32))
            guard AppBridgeAuthentication.verify(
                tag: serverTag,
                role: "server",
                secret: secret,
                clientNonce: clientNonce,
                serverNonce: serverNonce
            ) else { throw ScholiumAppBridgeError.permissionDenied }
            let tag = AppBridgeAuthentication.tag(
                role: "client",
                secret: secret,
                clientNonce: clientNonce,
                serverNonce: serverNonce
            )
            let body = try AppBridgeCoding.encode(request)
            try AppBridgeIO.writeFrame(tag + body, to: descriptor)
            sent = true
            let response = try AppBridgeCoding.decode(
                ScholiumAppBridgeResponse.self,
                from: AppBridgeIO.readFrame(from: descriptor)
            )
            guard response.correlationID == request.correlationID else {
                throw ScholiumAppBridgeError.invalidResponse
            }
            if let error = response.error {
                throw ScholiumAppBridgeError.remote(
                    code: error.code,
                    message: error.message
                )
            }
            return response
        } catch ScholiumAppBridgeError.timeout {
            if sent { throw ScholiumAppBridgeError.outcomeUnknown }
            throw ScholiumAppBridgeError.timeout
        }
    }
}

public final class ScholiumAppBridgeServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ScholiumAppBridgeRequest) async throws
        -> ScholiumMCPBridgeResponse

    private let queue = DispatchQueue(label: "com.scholium.app-bridge")
    private let containerURL: URL
    private let authenticationURL: URL
    private let port: UInt16
    private let timeout: TimeInterval
    private let operationTimeout: TimeInterval
    private let handler: Handler
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var stopping = false
    private var secret = Data()
    private var handlerTask: Task<Void, Never>?

    public init(
        applicationSupportURL: URL,
        timeout: TimeInterval = ScholiumAppBridgeLocation.timeout,
        operationTimeout: TimeInterval = ScholiumAppBridgeLocation.operationTimeout,
        handler: @escaping Handler
    ) throws {
        containerURL = applicationSupportURL.standardizedFileURL
        authenticationURL = ScholiumAppBridgeLocation.authenticationURL(
            applicationSupportURL: containerURL
        )
        port = ScholiumAppBridgeLocation.port(applicationSupportURL: containerURL)
        self.timeout = min(max(timeout, 0.1), 30)
        self.operationTimeout = min(max(operationTimeout, 0.1), 30)
        self.handler = handler
        try start()
    }

    deinit { stop() }

    public func stop() {
        lock.withLock {
            guard !stopping else { return }
            stopping = true
            handlerTask?.cancel()
            if listener >= 0 {
                Darwin.shutdown(listener, SHUT_RDWR)
                Darwin.close(listener)
                listener = -1
            }
            try? AppBridgeIO.removeSecret(at: authenticationURL)
        }
    }

    public func stopAndWait(
        timeout: TimeInterval = ScholiumAppBridgeLocation.timeout
    ) async -> Bool {
        stop()
        let task = lock.withLock { handlerTask }
        guard let task else { return true }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await task.value; return true }
            group.addTask {
                try? await Task.sleep(
                    for: .seconds(min(max(timeout, 0.1), 30))
                )
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func start() throws {
        try AppBridgeIO.validatePrivateDirectory(
            at: containerURL,
            createIfMissing: true
        )
        listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw ScholiumAppBridgeError.systemCall("create its listener", errno)
        }
        try AppBridgeIO.configure(listener, timeout: timeout)
        try AppBridgeIO.configureListener(listener)
        var address = AppBridgeIO.address(port: port)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listener,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(listener)
            listener = -1
            if code == EADDRINUSE { throw ScholiumAppBridgeError.alreadyRunning }
            throw ScholiumAppBridgeError.systemCall("bind", code)
        }
        guard Darwin.listen(listener, 8) == 0 else {
            throw ScholiumAppBridgeError.systemCall("listen", errno)
        }
        secret = try AppBridgeIO.installSecret(at: authenticationURL)
        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let descriptor = lock.withLock { stopping ? -1 : listener }
            guard descriptor >= 0 else { return }
            let peer = Darwin.accept(descriptor, nil, nil)
            if peer < 0 {
                if errno == EINTR { continue }
                return
            }
            handle(peer)
            Darwin.close(peer)
        }
    }

    private func handle(_ peer: Int32) {
        var correlationID = UUID()
        do {
            try AppBridgeIO.configure(peer, timeout: timeout)
            let clientNonce = try AppBridgeIO.readFrame(from: peer)
            guard clientNonce.count == 32 else {
                throw ScholiumAppBridgeError.permissionDenied
            }
            let serverNonce = try AppBridgeAuthentication.randomData(count: 32)
            let serverTag = AppBridgeAuthentication.tag(
                role: "server",
                secret: secret,
                clientNonce: clientNonce,
                serverNonce: serverNonce
            )
            try AppBridgeIO.writeFrame(serverNonce + serverTag, to: peer)
            let authenticated = try AppBridgeIO.readFrame(from: peer)
            guard authenticated.count > 32 else {
                throw ScholiumAppBridgeError.permissionDenied
            }
            let clientTag = Data(authenticated.prefix(32))
            guard AppBridgeAuthentication.verify(
                tag: clientTag,
                role: "client",
                secret: secret,
                clientNonce: clientNonce,
                serverNonce: serverNonce
            ) else { throw ScholiumAppBridgeError.permissionDenied }
            let request = try AppBridgeCoding.decode(
                ScholiumAppBridgeRequest.self,
                from: Data(authenticated.dropFirst(32))
            )
            correlationID = request.correlationID
            let box = AppBridgeResultBox()
            let semaphore = DispatchSemaphore(value: 0)
            let operation = handler
            let task = Task {
                do {
                    try Task.checkCancellation()
                    box.result = .success(try await operation(request))
                } catch {
                    box.result = .failure(error)
                }
                semaphore.signal()
            }
            lock.withLock { handlerTask = task }
            let finished = semaphore.wait(timeout: .now() + operationTimeout) == .success
            lock.withLock { handlerTask = nil }
            guard finished else {
                task.cancel()
                throw ScholiumAppBridgeError.outcomeUnknown
            }
            let result = try box.result?.get() ?? {
                throw ScholiumAppBridgeError.invalidResponse
            }()
            let response = try ScholiumAppBridgeResponse(
                correlationID: correlationID,
                mcpResponse: result
            )
            try AppBridgeIO.writeFrame(
                AppBridgeCoding.encode(response),
                to: peer
            )
        } catch {
            let payload = ScholiumAppBridgeRemoteError(
                code: "bridge_failed",
                message: error.localizedDescription
            )
            if let response = try? ScholiumAppBridgeResponse(
                correlationID: correlationID,
                error: payload
            ), let data = try? AppBridgeCoding.encode(response) {
                try? AppBridgeIO.writeFrame(data, to: peer)
            }
        }
    }
}

private final class AppBridgeResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<ScholiumMCPBridgeResponse, Error>?

    var result: Result<ScholiumMCPBridgeResponse, Error>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private enum AppBridgeCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) })
        else { throw ScholiumAppBridgeError.invalidRequest }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

private enum AppBridgeAuthentication {
    static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ScholiumAppBridgeError.permissionDenied
        }
        return data
    }

    static func tag(
        role: String,
        secret: Data,
        clientNonce: Data,
        serverNonce: Data
    ) -> Data {
        let key = SymmetricKey(data: secret)
        let message = Data(role.utf8) + clientNonce + serverNonce
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    static func verify(
        tag: Data,
        role: String,
        secret: Data,
        clientNonce: Data,
        serverNonce: Data
    ) -> Bool {
        let expected = self.tag(
            role: role,
            secret: secret,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
        return expected.count == tag.count && zip(expected, tag).reduce(0) {
            $0 | ($1.0 ^ $1.1)
        } == 0
    }
}

private enum AppBridgeIO {
    static func validatePrivateDirectory(
        at url: URL,
        createIfMissing: Bool
    ) throws {
        if createIfMissing {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            if errno == ENOENT { throw ScholiumAppBridgeError.unavailable }
            throw ScholiumAppBridgeError.systemCall("inspect its directory", errno)
        }
        guard (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0 else {
            throw ScholiumAppBridgeError.permissionDenied
        }
    }

    static func installSecret(at url: URL) throws -> Data {
        try? removeSecret(at: url)
        let secret = try AppBridgeAuthentication.randomData(count: 32)
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else {
            throw ScholiumAppBridgeError.systemCall("create its credential", errno)
        }
        defer { Darwin.close(descriptor) }
        try writeAll(secret, to: descriptor)
        guard fsync(descriptor) == 0 else {
            throw ScholiumAppBridgeError.systemCall("flush its credential", errno)
        }
        return secret
    }

    static func readSecret(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ScholiumAppBridgeError.unavailable }
            throw ScholiumAppBridgeError.permissionDenied
        }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size == 32 else {
            throw ScholiumAppBridgeError.permissionDenied
        }
        return try readExactly(32, from: descriptor)
    }

    static func removeSecret(at url: URL) throws {
        if unlink(url.path) != 0, errno != ENOENT {
            throw ScholiumAppBridgeError.systemCall("remove its credential", errno)
        }
    }

    static func address(port: UInt16) -> sockaddr_in {
        sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: port.bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )
    }

    static func configure(_ descriptor: Int32, timeout: TimeInterval) throws {
        var noSigPipe: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw ScholiumAppBridgeError.systemCall("configure its socket", errno)
        }
        var interval = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                option,
                &interval,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0 else {
                throw ScholiumAppBridgeError.systemCall("configure its timeout", errno)
            }
        }
    }

    static func configureListener(_ descriptor: Int32) throws {
        var reuseAddress: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw ScholiumAppBridgeError.systemCall(
                "configure listener reuse",
                errno
            )
        }
    }

    static func readFrame(from descriptor: Int32) throws -> Data {
        let header = try readExactly(4, from: descriptor)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0,
              length <= ScholiumAppBridgeLocation.maximumFrameByteCount else {
            throw ScholiumAppBridgeError.invalidFrame
        }
        return try readExactly(Int(length), from: descriptor)
    }

    static func writeFrame(_ data: Data, to descriptor: Int32) throws {
        guard !data.isEmpty,
              data.count <= ScholiumAppBridgeLocation.maximumFrameByteCount else {
            throw ScholiumAppBridgeError.invalidFrame
        }
        let length = UInt32(data.count)
        let header = Data([
            UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
        ])
        try writeAll(header, to: descriptor)
        try writeAll(data, to: descriptor)
    }

    private static func readExactly(
        _ count: Int,
        from descriptor: Int32
    ) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let amount = data.withUnsafeMutableBytes { buffer in
                Darwin.read(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    count - offset
                )
            }
            if amount > 0 { offset += amount; continue }
            if amount == 0 { throw ScholiumAppBridgeError.invalidFrame }
            if errno == EINTR { continue }
            if [EAGAIN, EWOULDBLOCK].contains(errno) {
                throw ScholiumAppBridgeError.timeout
            }
            throw ScholiumAppBridgeError.systemCall("read", errno)
        }
        return data
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let amount = data.withUnsafeBytes { buffer in
                Darwin.write(
                    descriptor,
                    buffer.baseAddress!.advanced(by: offset),
                    data.count - offset
                )
            }
            if amount > 0 { offset += amount; continue }
            if errno == EINTR { continue }
            if [EAGAIN, EWOULDBLOCK].contains(errno) {
                throw ScholiumAppBridgeError.timeout
            }
            throw ScholiumAppBridgeError.systemCall("write", errno)
        }
    }
}
