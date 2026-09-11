import Foundation
import ScholiumContracts

public enum CodexConnectionError: LocalizedError, Sendable {
  case disconnected, timedOut, invalidMessage
  case server(String)
  public var errorDescription: String? {
    switch self {
    case .disconnected: "Codex disconnected. Check the conversation before sending again."
    case .timedOut: "Codex did not confirm the request. Check its outcome before sending again."
    case .invalidMessage: "Codex returned an invalid protocol message."
    case .server(let message): message
    }
  }
}

/// Official App Server transport only. It owns no Agent loop or research state.
public actor CodexAppServer {
  public nonisolated let events: AsyncStream<[String: MCPJSONValue]>
  private let continuation: AsyncStream<[String: MCPJSONValue]>.Continuation
  private var process: Process?
  private var input: FileHandle?
  private var reader: Task<Void, Never>?
  private var buffer = Data()
  private var nextID = 0
  private var pending: [Int: CheckedContinuation<MCPJSONValue, Error>] = [:]
  private var timeouts: [Int: Task<Void, Never>] = [:]
  private var generation = UUID()
  private static let maximumFrameBytes = 8 * 1_024 * 1_024

  public init() {
    let stream = AsyncStream<[String: MCPJSONValue]>.makeStream()
    events = stream.stream
    continuation = stream.continuation
  }

  public func start(executable: URL, home: URL) throws {
    guard process == nil else { return }
    try FileManager.default.createDirectory(
      at: home, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let child = Process()
    let stdout = Pipe()
    let stdin = Pipe()
    let stderr = Pipe()
    child.executableURL = executable
    child.arguments = ["app-server", "--stdio", "-c", "analytics.enabled=false",
      "-c", "project_doc_max_bytes=0", "-c", "project_root_markers=[]"]
    child.environment = Self.processEnvironment(ProcessInfo.processInfo.environment, home: home)
    child.currentDirectoryURL = home
    child.standardInput = stdin
    child.standardOutput = stdout
    child.standardError = stderr
    let token = UUID()
    generation = token
    try child.run()
    process = child
    input = stdin.fileHandleForWriting
    let output = stdout.fileHandleForReading
    let chunks = AsyncStream<Data>.makeStream()
    // FileHandle reads are blocking: keep them off Swift's cooperative pool.
    DispatchQueue.global(qos: .utility).async {
      while true {
        let data = output.availableData
        guard !data.isEmpty else { break }
        chunks.continuation.yield(data)
      }
      try? output.close()
      chunks.continuation.finish()
    }
    reader = Task { [weak self] in
      for await data in chunks.stream {
        guard !Task.isCancelled else { break }
        await self?.receive(data, token: token)
      }
      await self?.ended(token: token)
    }
    // Drain stderr without logging research text or credentials.
    let errors = stderr.fileHandleForReading
    DispatchQueue.global(qos: .utility).async {
      while !errors.availableData.isEmpty {}
      try? errors.close()
    }
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
    guard input != nil else { throw CodexConnectionError.disconnected }
    nextID += 1
    let id = nextID
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { reply in
        if Task.isCancelled {
          reply.resume(throwing: CancellationError())
          return
        }
        pending[id] = reply
        do {
          try write(["id": .integer(id), "method": .string(method), "params": .object(params)])
          timeouts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            await self?.fail(id: id, error: CodexConnectionError.timedOut)
          }
        } catch { fail(id: id, error: error) }
      }
    } onCancel: {
      Task { await self.fail(id: id, error: CancellationError()) }
    }
  }

  public func notify(_ method: String, params: [String: MCPJSONValue] = [:]) throws {
    try write(["method": .string(method), "params": .object(params)])
  }

  public func respond(id: MCPJSONValue, result: MCPJSONValue) throws {
    try write(["id": id, "result": result])
  }

  public func reject(id: MCPJSONValue) throws {
    try write([
      "id": id,
      "error": .object([
        "code": .integer(-32601),
        "message": .string("This client does not support this request."),
      ]),
    ])
  }

  private func write(_ value: [String: MCPJSONValue]) throws {
    guard let input else { throw CodexConnectionError.disconnected }
    let data = try JSONEncoder().encode(MCPJSONValue.object(value))
    try input.write(contentsOf: data + Data([10]))
  }

  private func receive(_ data: Data, token: UUID) {
    guard generation == token else { return }
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 10) {
      let frame = buffer.prefix(upTo: newline)
      buffer.removeSubrange(...newline)
      guard !frame.isEmpty else { continue }
      guard frame.count <= Self.maximumFrameBytes,
        let value = try? JSONDecoder().decode(MCPJSONValue.self, from: Data(frame)),
        let object = value.objectValue
      else {
        ended(token: token)
        return
      }
      if object["method"] != nil {
        continuation.yield(object)
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
    if buffer.count > Self.maximumFrameBytes { ended(token: token) }
  }

  private func fail(id: Int, error: Error) {
    timeouts.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(throwing: error)
  }

  private func ended(token: UUID) {
    guard token == generation else { return }
    close()
    continuation.yield(["method": .string("scholium/disconnected")])
  }

  public func close() {
    generation = UUID()
    let child = process
    process = nil
    try? input?.close()
    input = nil
    reader?.cancel()
    reader = nil
    buffer.removeAll()
    for id in Array(pending.keys) { fail(id: id, error: CodexConnectionError.disconnected) }
    if let child, child.isRunning {
      child.terminate()
      Task.detached {
        try? await Task.sleep(for: .seconds(2))
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
      }
    }
  }
}
