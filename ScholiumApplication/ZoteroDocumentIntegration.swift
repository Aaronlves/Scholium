import Foundation
import ScholiumContracts

public struct ZoteroDocumentHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Outbound-only adapter for Zotero's official document integration protocol.
/// This is separate from the existing GET-only library/MCP transport.
public actor ZoteroDocumentIntegration: ZoteroDocumentIntegrating {
    public typealias Transport = @Sendable (URLRequest) async throws -> ZoteroDocumentHTTPResponse
    public typealias Handler = @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
    public typealias Authority = @Sendable () async -> ZoteroDocumentAuthority
    public static let shared = ZoteroDocumentIntegration()

    private let transport: Transport
    private let maximumCallbacks: Int
    private let maximumDrainCallbacks: Int
    private var active: (transactionID: String, control: Control)?
    private var applicationTerminationPending = false

    public init() {
        let transport = DocumentTransport()
        self.transport = { try await transport.send($0) }
        maximumCallbacks = 32_768
        maximumDrainCallbacks = 64
    }

    /// Injected transports make protocol tests incapable of opening a socket.
    public init(transport: @escaping Transport) {
        self.transport = transport
        maximumCallbacks = 32_768
        maximumDrainCallbacks = 64
    }

    init(transport: @escaping Transport, maximumCallbacks: Int, maximumDrainCallbacks: Int) {
        self.transport = transport
        self.maximumCallbacks = maximumCallbacks
        self.maximumDrainCallbacks = maximumDrainCallbacks
    }

    /// Cancellation revokes local authority while keeping the callback pump
    /// alive. Cancelling an in-flight picker request would strand Zotero.
    public func cancelCurrentTransaction(transactionID: String) async {
        guard let active, active.transactionID == transactionID else { return }
        await active.control.cancel()
    }

    /// Keeps a live callback pump in its process. An idle adapter instead
    /// closes admission until the application quits or cancels its attempt.
    public func beginApplicationTermination() -> Bool {
        guard active == nil else { return false }
        applicationTerminationPending = true
        return true
    }

    /// A refused save or cancelled quit restores normal citation admission.
    public func cancelApplicationTermination() {
        applicationTerminationPending = false
    }

    public func run(
        transactionID: String,
        command: ZoteroDocumentCommand,
        documentID: String,
        authority: @escaping Authority,
        handler: @escaping Handler
    ) async -> ZoteroDocumentIntegrationResult {
        guard !applicationTerminationPending else { return Self.result(.unavailable) }
        guard active == nil else { return Self.result(.busy) }
        guard Self.validIdentifier(documentID), !transactionID.isEmpty, transactionID.utf8.count <= 128,
            !transactionID.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else {
            return Self.result(.failed, message: "The citation document identity is invalid.")
        }
        guard !Task.isCancelled else { return Self.result(.cancelled) }
        let initialAuthority = await authority()
        guard initialAuthority == .current else {
            return Self.result(initialAuthority == .cancelled ? .cancelled : .unavailable)
        }
        // Another transaction or application quit can enter while the
        // asynchronous authority check runs.
        guard !applicationTerminationPending else { return Self.result(.unavailable) }
        guard active == nil else { return Self.result(.busy) }
        guard !Task.isCancelled else { return Self.result(.cancelled) }
        let control = Control()
        active = (transactionID, control)
        let transport = transport
        let maximumCallbacks = maximumCallbacks
        let maximumDrainCallbacks = maximumDrainCallbacks
        let pump = Task.detached {
            await Self.pump(
                command: command, documentID: documentID, transport: transport,
                control: control, authority: authority, handler: handler,
                maximumCallbacks: maximumCallbacks, maximumDrainCallbacks: maximumDrainCallbacks)
        }
        let outcome = await withTaskCancellationHandler {
            await pump.value
        } onCancel: {
            Task { await control.cancel() }
        }
        active = nil
        return outcome
    }

    private actor Control {
        private(set) var cancelled = false
        func cancel() { cancelled = true }
    }

    private static func result(
        _ status: ZoteroDocumentIntegrationResult.Status,
        cleanup: Bool = false, callbacks: Int = 0, message: String? = nil
    ) -> ZoteroDocumentIntegrationResult {
        .init(status: status, remoteCleanupConfirmed: cleanup, callbackCount: callbacks, message: message)
    }

    private static func pump(
        command: ZoteroDocumentCommand, documentID: String, transport: Transport,
        control: Control, authority: Authority, handler: Handler,
        maximumCallbacks: Int, maximumDrainCallbacks: Int
    ) async -> ZoteroDocumentIntegrationResult {
        var count = 0
        var drainCount = 0
        var stopped: ZoteroDocumentIntegrationResult.Status?
        var failureMessage: String?
        var knownFields = Set<String>()
        do {
            guard !(await control.cancelled) else { return result(.cancelled) }
            var response = try await post(
                .execute, .object(["command": .string(command.rawValue), "docId": .string(documentID)]),
                transport: transport)
            if response.statusCode == 503 { return result(.busy) }
            while true {
                guard response.statusCode == 200 else {
                    return result(.unknown, callbacks: count, message: unknownMessage)
                }
                count += 1
                let currentAuthority = await authority()
                if stopped == nil {
                    if await control.cancelled || currentAuthority == .cancelled {
                        stopped = .cancelled
                    } else if currentAuthority == .unavailable {
                        stopped = .unavailable
                    } else if count > maximumCallbacks {
                        stopped = .failed
                        failureMessage = "Zotero exceeded the citation callback limit."
                    }
                }
                let envelope = try? decodeEnvelope(response.body)
                // Never respond after any complete callback, even a foreign or
                // malformed one. Such a callback cannot prove our cleanup.
                if envelope?.command == "Document.complete" {
                    guard envelope?.arguments == [.string(documentID)] else {
                        return result(.unknown, callbacks: count, message: unknownMessage)
                    }
                    return result(stopped ?? .cleanedUp, cleanup: true, callbacks: count, message: failureMessage)
                }
                var payload: MCPJSONValue
                do {
                    guard stopped == nil else { throw ProtocolError.refused }
                    guard let envelope else { throw ProtocolError.malformed }
                    if envelope.command == "Application.getActiveDocument" {
                        guard envelope.arguments.isEmpty else { throw ProtocolError.malformed }
                        payload = .object([
                            "documentID": .string(documentID), "outputFormat": .string("html"),
                            "supportedNotes": .array([]), "processorName": .string("Scholium"),
                            "supportsImportExport": .bool(false), "supportsTextInsertion": .bool(false),
                            "supportsCitationMerging": .bool(false),
                        ])
                    } else {
                        let callback = try decodeCallback(envelope, documentID: documentID, knownFields: knownFields)
                        let reply = try await handler(callback)
                        // Handler suspension can coincide with tab departure.
                        let afterHandler = await authority()
                        if await control.cancelled || afterHandler == .cancelled {
                            stopped = .cancelled
                        } else if afterHandler == .unavailable {
                            stopped = .unavailable
                        }
                        guard stopped == nil else { throw ProtocolError.refused }
                        payload = try encodeReply(reply, for: callback, knownFields: &knownFields)
                    }
                } catch {
                    if stopped == nil {
                        stopped = .failed
                        failureMessage = "Scholium could not safely apply a Zotero document callback."
                    }
                    payload = .object([
                        "error": .string(stopped == .unavailable ? "Tab Not Available Error" : "Scholium Document Error"),
                        "message": .string("The citation transaction no longer has document authority."),
                    ])
                }
                if stopped != nil {
                    drainCount += 1
                    // An uncooperative peer cannot hold an unbounded loop. This
                    // is an explicit uncertain outcome, never a clean release.
                    guard drainCount <= maximumDrainCallbacks else {
                        return result(.unknown, callbacks: count, message: unknownMessage)
                    }
                }
                response = try await post(.respond, payload, transport: transport)
            }
        } catch {
            // Do not retry a POST whose remote outcome is unknown.
            return result(.unknown, callbacks: count, message: unknownMessage)
        }
    }

    private enum Endpoint: String {
        case execute = "execCommand"
        case respond
    }
    private static let maximumBodyBytes = 16 * 1_024 * 1_024
    private static let maximumStringBytes = 8 * 1_024 * 1_024
    private static let unknownMessage = "Zotero cleanup could not be confirmed. Finish its open dialog or restart Zotero before trying again."

    private static func post(_ endpoint: Endpoint, _ value: MCPJSONValue, transport: Transport) async throws -> ZoteroDocumentHTTPResponse {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maximumBodyBytes else { throw ProtocolError.malformed }
        let url = URL(string: "http://127.0.0.1:23119/connector/document/\(endpoint.rawValue)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A picker interaction is a human wait, unlike the five-second library
        // read transport. Deadline failure is reported as unconfirmed cleanup.
        request.timeoutInterval = 3_600
        request.httpBody = body
        let response = try await transport(request)
        guard response.body.count <= maximumBodyBytes else { throw ProtocolError.malformed }
        return response
    }

    private struct Envelope {
        let command: String
        let arguments: [MCPJSONValue]
    }

    private enum ProtocolError: Error { case malformed, unsupported, refused }

    private static func decodeEnvelope(_ data: Data) throws -> Envelope {
        guard let object = try JSONDecoder().decode(MCPJSONValue.self, from: data).objectValue,
            Set(object.keys) == ["command", "arguments"],
            let command = object["command"]?.stringValue, command.utf8.count <= 128,
            let arguments = object["arguments"]?.arrayValue, arguments.count <= 8
        else { throw ProtocolError.malformed }
        return .init(command: command, arguments: arguments)
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }

    private static func decodeCallback(_ envelope: Envelope, documentID: String, knownFields: Set<String>) throws -> ZoteroDocumentCallback {
        let args = envelope.arguments
        guard args.first == .string(documentID) else { throw ProtocolError.malformed }
        func arity(_ count: Int) throws {
            guard args.count == count else { throw ProtocolError.malformed }
        }
        func string(_ index: Int) throws -> String {
            guard args.indices.contains(index), let value = args[index].stringValue,
                value.utf8.count <= maximumStringBytes
            else { throw ProtocolError.malformed }
            return value
        }
        func field() throws -> String {
            let id = try string(1)
            guard validIdentifier(id), knownFields.contains(id) else { throw ProtocolError.malformed }
            return id
        }
        func httpFieldType(_ index: Int) throws {
            guard try string(index) == "Http" else { throw ProtocolError.unsupported }
        }
        func number(_ index: Int) throws -> Double {
            guard args.indices.contains(index) else { throw ProtocolError.malformed }
            let result: Double
            switch args[index] {
            case .integer(let n): result = Double(n)
            case .double(let n): result = n
            default: throw ProtocolError.malformed
            }
            guard result.isFinite, abs(result) <= 1_000_000 else { throw ProtocolError.malformed }
            return result
        }
        switch envelope.command {
        case "Document.activate":
            try arity(1)
            return .activate
        case "Document.canInsertField":
            try arity(2)
            try httpFieldType(1)
            return .canInsertField
        case "Document.getDocumentData":
            try arity(1)
            return .getDocumentData
        case "Document.setDocumentData":
            try arity(2)
            return .setDocumentData(try string(1))
        case "Document.cursorInField":
            try arity(2)
            try httpFieldType(1)
            return .cursorInField
        case "Document.getFields":
            try arity(2)
            try httpFieldType(1)
            return .getFields
        case "Document.insertField":
            try arity(3)
            try httpFieldType(1)
            guard args[2] == .integer(0) else { throw ProtocolError.unsupported }
            return .insertField
        case "Document.setBibliographyStyle":
            try arity(7)
            guard let stops = args[5].arrayValue, stops.count <= 128,
                args[6].intValue == stops.count
            else { throw ProtocolError.malformed }
            let lineSpacing = try number(3)
            let entrySpacing = try number(4)
            guard lineSpacing > 0, entrySpacing >= 0 else { throw ProtocolError.malformed }
            let tabStops = try stops.map { value -> Double in
                let n: Double
                switch value {
                case .integer(let v): n = Double(v)
                case .double(let v): n = v
                default: throw ProtocolError.malformed
                }
                guard n.isFinite, abs(n) <= 1_000_000 else { throw ProtocolError.malformed }
                return n
            }
            return .setBibliographyStyle(
                try .init(firstLineIndent: number(1), indent: number(2), lineSpacing: lineSpacing, entrySpacing: entrySpacing, tabStops: tabStops))
        case "Document.displayAlert":
            try arity(4)
            guard let icon = args[2].intValue, (0...2).contains(icon),
                let buttons = args[3].intValue, (0...3).contains(buttons)
            else { throw ProtocolError.malformed }
            return .displayAlert(text: try string(1), icon: icon, buttons: buttons)
        case "Field.delete":
            try arity(2)
            return .deleteField(try field())
        case "Field.select":
            try arity(2)
            return .selectField(try field())
        case "Field.removeCode":
            try arity(2)
            return .removeFieldCode(try field())
        case "Field.getText":
            try arity(2)
            return .getFieldText(try field())
        case "Field.setCode":
            try arity(3)
            return .setFieldCode(id: try field(), code: try string(2))
        case "Field.setText":
            try arity(4)
            guard args[3] == .bool(true) else { throw ProtocolError.unsupported }
            return .setFieldText(id: try field(), html: try string(2))
        default: throw ProtocolError.unsupported
        }
    }

    private static func encodeReply(_ reply: ZoteroDocumentReply, for callback: ZoteroDocumentCallback, knownFields: inout Set<String>) throws -> MCPJSONValue {
        func string(_ text: String) throws -> MCPJSONValue {
            guard text.utf8.count <= maximumStringBytes else { throw ProtocolError.malformed }
            return .string(text)
        }
        func field(_ field: ZoteroDocumentField) throws -> MCPJSONValue {
            guard validIdentifier(field.id), field.noteIndex == 0 else { throw ProtocolError.malformed }
            return .object([
                "id": .string(field.id), "code": try string(field.code), "text": try string(field.text),
                "noteIndex": .integer(field.noteIndex), "adjacent": .bool(field.adjacent),
            ])
        }
        switch (callback, reply) {
        case (.canInsertField, .boolean(let value)): return .bool(value)
        case (.getDocumentData, .string(let value)), (.getFieldText, .string(let value)): return try string(value)
        case (.cursorInField, .field(let value)):
            guard let value else { return .null }
            let encoded = try field(value)
            knownFields.insert(value.id)
            return encoded
        case (.insertField, .field(.some(let value))):
            guard !knownFields.contains(value.id) else { throw ProtocolError.malformed }
            let encoded = try field(value)
            knownFields.insert(value.id)
            return encoded
        case (.getFields, .fields(let values)):
            guard values.count <= 4_096, Set(values.map(\.id)).count == values.count else { throw ProtocolError.malformed }
            let encoded = try values.map(field)
            knownFields = Set(values.map(\.id))
            return .array(encoded)
        case (.displayAlert(_, _, let buttons), .alert(let button)):
            let valid: Set<Int> = buttons == 0 ? [1] : buttons == 3 ? [0, 1, 2] : [0, 1]
            guard valid.contains(button) else { throw ProtocolError.malformed }
            return .integer(button)
        case (.deleteField(let id), .none), (.removeFieldCode(let id), .none):
            knownFields.remove(id)
            return .null
        case (.activate, .none), (.setDocumentData, .none), (.setBibliographyStyle, .none),
            (.selectField, .none), (.setFieldText, .none), (.setFieldCode, .none):
            return .null
        default: throw ProtocolError.malformed
        }
    }

    private final class DocumentTransport: Sendable {
        private let session: URLSession

        init() {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3_600
            configuration.timeoutIntervalForResource = 3_600
            configuration.waitsForConnectivity = false
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        }

        func send(_ request: URLRequest) async throws -> ZoteroDocumentHTTPResponse {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse,
                response.url == request.url, response.expectedContentLength <= maximumBodyBytes
            else { throw ProtocolError.malformed }
            var body = Data()
            for try await byte in bytes {
                guard body.count < maximumBodyBytes else { throw ProtocolError.malformed }
                body.append(byte)
            }
            return .init(statusCode: response.statusCode, body: body)
        }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
