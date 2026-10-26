import Foundation
import ScholiumContracts
import Subprocess

public enum CodexConnectionError: LocalizedError, Sendable {
    case disconnected, timedOut, invalidMessage, installationChanged
    /// The current outbound operation was refused before queueing or writing.
    /// Previously accepted operations fail as disconnected and remain uncertain.
    case capacityExceeded
    case server(String)
    public var errorDescription: String? {
        switch self {
        case .disconnected: "Codex disconnected. Check the conversation before sending again."
        case .timedOut: "Codex did not confirm the request. Check its outcome before sending again."
        case .invalidMessage: "Codex returned an invalid protocol message."
        case .installationChanged: "The Codex installation changed. Reconnect after checking the installation."
        case .capacityExceeded: "Codex exceeded its transport capacity and disconnected. Check the conversation before sending again."
        case .server(let message): message
        }
    }
}

/// Official App Server transport only. It owns no Agent loop or research state.
public actor CodexAppServer {
    public nonisolated let events: AsyncStream<[String: MCPJSONValue]>
    private let incoming: CodexTransportBuffer<[String: MCPJSONValue]>
    private let limits: CodexTransportLimits
    private struct Outbound: Sendable {
        enum Destination: Sendable {
            case request(Int)
            case message(UUID)
        }
        let destination: Destination
        let data: Data
        var admission: (@Sendable () async -> Bool)? = nil
    }
    private var connectionTask: Task<Void, Never>?
    private var outgoing: CodexTransportBuffer<Outbound>?
    private var startup: [CheckedContinuation<Void, Error>] = []
    private var writes: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var isReady = false
    private var isClosing = false
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<MCPJSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var generation = UUID()
    private static let maximumFrameBytes = 8 * 1_024 * 1_024

    public init() {
        self.init(limits: .standard)
    }

    init(limits: CodexTransportLimits) {
        precondition(limits.pendingOperations > 0)
        self.limits = limits
        let incoming = CodexTransportBuffer<[String: MCPJSONValue]>(
            maximumCount: limits.incomingCount, maximumBytes: limits.incomingBytes)
        self.incoming = incoming
        // Unfolding adds no second buffer. The standard stream owns suspended
        // consumers and cancellation; the bounded owner accounts each dequeue.
        events = AsyncStream(unfolding: { await incoming.next() }, onCancel: { incoming.finish() })
    }

    deinit {
        outgoing?.finish()
        connectionTask?.cancel()
        incoming.finish()
    }

    public func start(
        executable: URL, home: URL, workingDirectory: URL,
        automaticallyDiscovered: Bool = false
    ) async throws {
        // A replacement never overlaps the preceding child's teardown.
        while isClosing, let task = connectionTask { await task.value }
        try Task.checkCancellation()
        if isReady { return }
        if connectionTask == nil {
            try FileManager.default.createDirectory(
                at: home, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let token = UUID()
            generation = token
            let queue = CodexTransportBuffer<Outbound>(
                maximumCount: limits.outgoingCount, maximumBytes: limits.outgoingBytes)
            outgoing = queue
            let environment = Self.processEnvironment(ProcessInfo.processInfo.environment, home: home)
            // Own exactly one task for the connection. All process handles stay inside run.
            connectionTask = Task { [weak self] in
                do {
                    // Discovery happened before workspace preparation. Verify again at
                    // the process boundary, after that suspension.
                    let launchExecutable: URL
                    if automaticallyDiscovered {
                        guard let verified = ScholiumAgentIntegrationResources.verifiedCodexRuntimeURL(at: executable)
                        else { throw CodexConnectionError.installationChanged }
                        launchExecutable = verified
                    } else {
                        launchExecutable = executable
                    }
                    var options = PlatformOptions()
                    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
                    _ = try await Subprocess.run(
                        .path(.init(launchExecutable.path)),
                        arguments: [
                            "app-server", "--stdio", "-c", "analytics.enabled=false",
                            "-c", "project_doc_max_bytes=32768", "-c", "project_root_markers=[]",
                        ],
                        environment: .custom(Dictionary(uniqueKeysWithValues: environment.map { (.init(stringLiteral: $0.key), $0.value) })),
                        workingDirectory: .init(workingDirectory.path),
                        platformOptions: options,
                        input: .inputWriter, output: .sequence, error: .discarded
                    ) { execution in
                        try Task.checkCancellation()
                        await self?.started(token: token)
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask { [weak self] in
                                for try await chunk in execution.standardOutput {
                                    try Task.checkCancellation()
                                    try await self?.receive(Data(buffer: chunk), token: token)
                                }
                                // EOF must also tear down a child that closed stdout but stayed alive.
                                throw CodexConnectionError.disconnected
                            }
                            group.addTask { [weak self] in
                                while let frame = await queue.next() {
                                    try Task.checkCancellation()
                                    guard await self?.admitted(frame, token: token) == true else { continue }
                                    let count = try await execution.standardInputWriter.write(frame.data)
                                    guard count == frame.data.count else { throw CodexConnectionError.disconnected }
                                    await self?.written(frame, token: token)
                                }
                                throw CodexConnectionError.disconnected
                            }
                            // The first failed/ended stream cancels the other, including an idle writer.
                            defer { group.cancelAll() }
                            try await group.next()
                        }
                    }
                    await self?.ended(token: token, error: CodexConnectionError.disconnected)
                } catch {
                    await self?.ended(token: token, error: error)
                }
            }
        }
        let token = generation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                guard startup.count < limits.pendingOperations else {
                    interruptForCapacity()
                    waiter.resume(throwing: CodexConnectionError.capacityExceeded)
                    return
                }
                startup.append(waiter)
            }
        } onCancel: {
            Task { await self.cancelStartup(token: token) }
        }
        try Task.checkCancellation()
    }

    private func started(token: UUID) {
        guard token == generation, !isClosing else { return }
        isReady = true
        let waiters = startup
        startup.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func cancelStartup(token: UUID) async {
        guard token == generation else { return }
        await close()
    }

    /// Preserve the caller's network route without inheriting unrelated credentials.
    static func processEnvironment(_ inherited: [String: String], home: URL) -> [String: String] {
        let allowed: Set<String> = [
            "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SHELL",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        ]
        var result = inherited.filter { allowed.contains($0.key) }
        result["CODEX_HOME"] = home.path
        return result
    }

    public func request(_ method: String, params: [String: MCPJSONValue] = [:]) async throws
        -> MCPJSONValue
    {
        try Task.checkCancellation()
        guard isReady, let outgoing else { throw CodexConnectionError.disconnected }
        try requireOperationCapacity()
        nextID += 1
        let id = nextID
        let data = try encode(["id": .integer(id), "method": .string(method), "params": .object(params)])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { reply in
                if Task.isCancelled {
                    reply.resume(throwing: CancellationError())
                    return
                }
                pending[id] = reply
                guard outgoing.offer(Outbound(destination: .request(id), data: data), bytes: data.count) else {
                    // This request never entered the writer's FIFO. Separate
                    // definite local rejection from accepted, uncertain RPCs.
                    pending.removeValue(forKey: id)
                    interruptForCapacity()
                    reply.resume(throwing: CodexConnectionError.capacityExceeded)
                    return
                }
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    await self?.fail(id: id, error: CodexConnectionError.timedOut)
                }
            }
        } onCancel: {
            Task { await self.fail(id: id, error: CancellationError()) }
        }
    }

    public func notify(_ method: String, params: [String: MCPJSONValue] = [:]) async throws {
        try await write(["method": .string(method), "params": .object(params)])
    }

    public func respond(
        id: MCPJSONValue, result: MCPJSONValue,
        ifAdmitted admission: @escaping @Sendable () async -> Bool
    ) async throws {
        try await write(["id": id, "result": result], admission: admission)
    }

    public func reject(id: MCPJSONValue) async throws {
        try await write([
            "id": id,
            "error": .object([
                "code": .integer(-32601),
                "message": .string("This client does not support this request."),
            ]),
        ])
    }

    private func encode(_ value: [String: MCPJSONValue]) throws -> Data {
        let data = try JSONEncoder().encode(MCPJSONValue.object(value))
        // Several individually valid materials can exceed the incoming 8 MiB
        // ceiling. The complete outgoing envelope, including its newline,
        // uses the independent outgoing queue byte budget.
        guard data.count < limits.outgoingBytes else {
            interruptForCapacity()
            throw CodexConnectionError.capacityExceeded
        }
        return data + Data([10])
    }

    private func write(
        _ value: [String: MCPJSONValue], admission: (@Sendable () async -> Bool)? = nil
    ) async throws {
        try Task.checkCancellation()
        guard isReady, let outgoing else { throw CodexConnectionError.disconnected }
        try requireOperationCapacity()
        let id = UUID()
        let data = try encode(value)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    reply.resume(throwing: CancellationError())
                    return
                }
                writes[id] = reply
                guard outgoing.offer(Outbound(destination: .message(id), data: data, admission: admission), bytes: data.count) else {
                    writes.removeValue(forKey: id)
                    interruptForCapacity()
                    reply.resume(throwing: CodexConnectionError.capacityExceeded)
                    return
                }
            }
        } onCancel: {
            Task { await self.cancelWrite(id: id) }
        }
    }

    private func cancelWrite(id: UUID) {
        writes.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func shouldWrite(_ frame: Outbound, token: UUID) -> Bool {
        guard token == generation, isReady else { return false }
        switch frame.destination {
        case .request(let id): return pending[id] != nil
        case .message(let id): return writes[id] != nil
        }
    }

    private func admitted(_ frame: Outbound, token: UUID) async -> Bool {
        guard shouldWrite(frame, token: token) else { return false }
        // The turn owner revalidates a queued answer or grant immediately before I/O.
        if let admission = frame.admission, await !admission() {
            if case .message(let id) = frame.destination { cancelWrite(id: id) }
            return false
        }
        return shouldWrite(frame, token: token)
    }

    private func written(_ frame: Outbound, token: UUID) {
        guard token == generation else { return }
        if case .message(let id) = frame.destination { writes.removeValue(forKey: id)?.resume() }
    }

    private func receive(_ data: Data, token: UUID) throws {
        guard generation == token, !isClosing else { throw CodexConnectionError.disconnected }
        var scanStart = buffer.endIndex
        buffer.append(data)
        // The preceding buffer has no newline; scan only newly received bytes.
        while let newline = buffer[scanStart...].firstIndex(of: 10) {
            let frame = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            scanStart = buffer.startIndex
            guard !frame.isEmpty else { continue }
            guard frame.count <= Self.maximumFrameBytes,
                let value = try? JSONDecoder().decode(MCPJSONValue.self, from: Data(frame)),
                let object = value.objectValue
            else {
                throw CodexConnectionError.invalidMessage
            }
            if object["method"] != nil {
                guard incoming.offer(object, bytes: frame.count) else {
                    interruptForCapacity()
                    throw CodexConnectionError.capacityExceeded
                }
            } else if let id = object["id"]?.intValue, let callback = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if let error = object["error"]?.objectValue {
                    callback.resume(
                        throwing: CodexConnectionError.server(
                            error["message"]?.stringValue ?? "Codex request failed."))
                } else if let result = object["result"] {
                    callback.resume(returning: result)
                } else {
                    callback.resume(throwing: CodexConnectionError.invalidMessage)
                }
            }
        }
        if buffer.count > Self.maximumFrameBytes { throw CodexConnectionError.invalidMessage }
    }

    private func fail(id: Int, error: Error) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func ended(token: UUID, error: Error) {
        guard token == generation else { return }
        let unexpected = isReady && !isClosing
        clearPending(startupError: error)
        connectionTask = nil
        isClosing = false
        generation = UUID()
        if unexpected { incoming.offerTerminal(["method": .string("scholium/disconnected")]) }
    }

    private func requireOperationCapacity() throws {
        guard pending.count + writes.count < limits.pendingOperations else {
            interruptForCapacity()
            throw CodexConnectionError.capacityExceeded
        }
    }

    private func interruptForCapacity() {
        guard !isClosing else { return }
        let notify = isReady
        isClosing = true
        clearPending(startupError: CodexConnectionError.capacityExceeded)
        connectionTask?.cancel()
        if notify {
            incoming.offerTerminal([
                "method": .string("scholium/disconnected"),
                "params": .object(["reason": .string("capacityExceeded")]),
            ])
        }
    }

    private func clearPending(startupError: Error) {
        isReady = false
        outgoing?.finish()
        outgoing = nil
        let waiters = startup
        startup.removeAll()
        for waiter in waiters { waiter.resume(throwing: startupError) }
        buffer.removeAll()
        for id in Array(pending.keys) { fail(id: id, error: CodexConnectionError.disconnected) }
        let unfinished = writes.values
        writes.removeAll()
        for waiter in unfinished { waiter.resume(throwing: CodexConnectionError.disconnected) }
    }

    public func close() async {
        guard let task = connectionTask else { return }
        isClosing = true
        clearPending(startupError: CancellationError())
        task.cancel()
        // run owns signal escalation, handle closure and reaping; finish all before returning.
        await task.value
    }
}
