import ScholiumContracts
import Foundation
import Darwin

public enum ZoteroMCPTransportLocator {
    /// Locates the configured executable without launching it. The currently
    /// running `scholium` binary is accepted so source builds can probe their
    /// own first-party server before installing it on PATH.
    public static func report(
        descriptor: ZoteroMCPTransportDescriptor = .supportedLocal,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ZoteroMCPTransportReport {
        let path = executableURL(descriptor: descriptor, environment: environment)
        if let path {
            return ZoteroMCPTransportReport(
                descriptorID: descriptor.identifier,
                state: .commandAvailable,
                commandPath: path.path,
                note: "The first-party executable is present; use `status --probe` for Scholium's data-free initialize check or configure an external MCP client to launch it."
            )
        }
        return ZoteroMCPTransportReport(
            descriptorID: descriptor.identifier,
            state: .notConfigured,
            note: "Build or install the optional Scholium CLI transport and configure it in the external agent. The protected Skill remains available without a live connection."
        )
    }

    /// Performs an explicit, read-only MCP lifecycle probe against the
    /// configured stdio command. The probe sends only `initialize` and
    /// `notifications/initialized`; it does not list tools, inspect Zotero,
    /// import records, or write any external data. The external process is
    /// terminated after the handshake so this remains a status check rather
    /// than an embedded MCP client.
    public static func probe(
        descriptor: ZoteroMCPTransportDescriptor = .supportedLocal,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 5
    ) async -> ZoteroMCPTransportReport {
        guard let commandURL = executableURL(descriptor: descriptor, environment: environment) else {
            return report(descriptor: descriptor, environment: environment)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        // The probe deliberately does not expose server diagnostics. Drain
        // them to /dev/null so a verbose optional server cannot fill an
        // undrained stderr pipe and make the read-only handshake time out.
        let diagnostics = FileHandle.nullDevice
        process.executableURL = commandURL
        process.arguments = descriptor.clientConfiguration.arguments
        process.environment = environment.merging(
            descriptor.clientConfiguration.environment,
            uniquingKeysWith: { _, configured in configured }
        )
        process.standardInput = input
        process.standardOutput = output
        process.standardError = diagnostics

        do {
            try process.run()
        } catch {
            return failedReport(
                descriptor: descriptor,
                commandPath: commandURL.path,
                note: "The configured MCP command could not be started."
            )
        }

        defer {
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.closeFile()
            diagnostics.closeFile()
            if process.isRunning {
                process.terminate()
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
        }

        do {
            try writeJSON(InitializeRequest(), to: input.fileHandleForWriting)
            let response = try await readInitializeResponse(
                from: output.fileHandleForReading,
                timeout: timeout
            )
            guard response.id == InitializeRequest.requestID,
                  let result = response.result,
                  let protocolVersion = result.protocolVersion,
                  !protocolVersion.isEmpty else {
                throw ProbeFailure.invalidResponse
            }

            try writeJSON(InitializedNotification(), to: input.fileHandleForWriting)
            input.fileHandleForWriting.closeFile()

            return ZoteroMCPTransportReport(
                descriptorID: descriptor.identifier,
                state: .handshakeSucceeded,
                commandPath: commandURL.path,
                liveHandshakePerformed: true,
                serverProtocolVersion: protocolVersion,
                serverName: result.serverInfo?.name,
                serverVersion: result.serverInfo?.version,
                capabilities: result.capabilities?.map(\.key) ?? [],
                note: "The configured MCP server completed initialize. No Zotero data was read or written."
            )
        } catch let failure as ProbeFailure {
            return failedReport(
                descriptor: descriptor,
                commandPath: commandURL.path,
                note: failure.note
            )
        } catch {
            return failedReport(
                descriptor: descriptor,
                commandPath: commandURL.path,
                note: "The configured MCP server did not complete the initialize handshake."
            )
        }
    }

    private static func executableURL(
        descriptor: ZoteroMCPTransportDescriptor,
        environment: [String: String]
    ) -> URL? {
        if descriptor.command.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: descriptor.command)
            return FileManager.default.isExecutableFile(atPath: absolute.path) ? absolute : nil
        }
        if let searchPath = environment["PATH"] {
            let candidates = searchPath.split(separator: ":").map { component in
                URL(fileURLWithPath: String(component))
                    .appendingPathComponent(descriptor.command)
            }
            if let executable = candidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0.path)
            }) {
                return executable
            }
        }
        if descriptor.identifier == ZoteroMCPTransportDescriptor.supportedLocal.identifier,
           let currentArgument = ProcessInfo.processInfo.arguments.first {
            let current = URL(fileURLWithPath: currentArgument).standardizedFileURL
            if current.lastPathComponent == descriptor.command,
               FileManager.default.isExecutableFile(atPath: current.path) {
                return current
            }
        }
        return nil
    }

    private static func failedReport(
        descriptor: ZoteroMCPTransportDescriptor,
        commandPath: String,
        note: String
    ) -> ZoteroMCPTransportReport {
        ZoteroMCPTransportReport(
            descriptorID: descriptor.identifier,
            state: .handshakeFailed,
            commandPath: commandPath,
            liveHandshakePerformed: true,
            note: note
        )
    }

    private static func writeJSON<T: Encodable>(_ value: T, to handle: FileHandle) throws {
        let data = try JSONEncoder().encode(value) + Data([0x0A])
        handle.write(data)
    }

    private static func readInitializeResponse(
        from handle: FileHandle,
        timeout: TimeInterval
    ) async throws -> InitializeResponse {
        try await withThrowingTaskGroup(of: InitializeResponse.self) { group in
            group.addTask {
                var line = Data()
                for try await byte in handle.bytes {
                    line.append(byte)
                    guard byte == 0x0A else {
                        if line.count > 256 * 1024 { throw ProbeFailure.outputTooLarge }
                        continue
                    }
                    if let response = try? JSONDecoder().decode(InitializeResponse.self, from: line) {
                        return response
                    }
                    line.removeAll(keepingCapacity: true)
                }
                throw ProbeFailure.noResponse
            }
            group.addTask {
                let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw ProbeFailure.timeout
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else {
                throw ProbeFailure.noResponse
            }
            return response
        }
    }
}

private enum ProbeFailure: Error {
    case timeout
    case noResponse
    case invalidResponse
    case outputTooLarge

    var note: String {
        switch self {
        case .timeout:
            "The configured MCP server did not answer initialize before the probe timed out."
        case .noResponse, .invalidResponse:
            "The configured MCP server returned no valid initialize response."
        case .outputTooLarge:
            "The configured MCP server returned an unexpectedly large initialize response."
        }
    }
}

private struct InitializeRequest: Encodable {
    static let requestID = 1
    let jsonrpc = "2.0"
    let id = Self.requestID
    let method = "initialize"
    let params = Parameters()

    struct Parameters: Encodable {
        let protocolVersion = "2025-11-25"
        let capabilities: [String: String] = [:]
        let clientInfo = ClientInfo()
    }

    struct ClientInfo: Encodable {
        let name = "Scholium"
        let version = "0.1.0"
    }
}

private struct InitializedNotification: Encodable {
    let jsonrpc = "2.0"
    let method = "notifications/initialized"
    let params: [String: String] = [:]
}

private struct InitializeResponse: Decodable, Sendable {
    let id: Int?
    let result: Result?

    struct Result: Decodable, Sendable {
        let protocolVersion: String?
        let capabilities: [String: JSONValue]?
        let serverInfo: ServerInfo?
    }

    struct ServerInfo: Decodable, Sendable {
        let name: String?
        let version: String?
    }
}

private enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }
}
