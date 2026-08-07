import Darwin
import Foundation
import ScholiumContracts

public enum LocalAgentBridgeOperation: String, Codable, Sendable {
    case pair
    case context
    case query
    case extendWriteSet = "extend_write_set"
    case writeDocument = "write_document"
    case resolveWriteConflict = "resolve_write_conflict"
    case submitResult = "submit_result"
    case continueResearch = "continue_research"
    case methodImprovementContext = "method_improvement_context"
    case submitMethodImprovement = "submit_method_improvement"
    case end
}

/// The bridge is the only JSON boundary allowed to unwrap a Session
/// credential. Keeping this adapter private prevents the bearer value from
/// becoming a generally Codable domain contract.
private struct LocalAgentBridgeWireCredential: Codable {
    let value: ResearchConnectionCredential

    init(_ value: ResearchConnectionCredential) {
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sessionID = "session_id"
        case secret
    }

    init(from decoder: Decoder) throws {
        try LocalAgentBridgeWireCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(UUID.self, forKey: .sessionID)
        let secret = try container.decode(String.self, forKey: .secret)
        do {
            value = try ResearchConnectionCredential(
                sessionID: sessionID,
                secret: secret
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .secret,
                in: container,
                debugDescription: "The protected Session credential is invalid."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.sessionID, forKey: .sessionID)
        try container.encode(value.secret, forKey: .secret)
    }
}

public struct LocalAgentBridgeRequest: Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 9

    public let schemaVersion: Int
    public let correlationID: UUID
    public let operation: LocalAgentBridgeOperation
    public let run: ResearchRunLocator?
    public let pairingCode: ResearchPairingCode?
    public let credential: ResearchConnectionCredential?
    public let contextRequest: ResearchContextRequest?
    public let writeSetIntent: ResearchWriteSetExtensionIntent?
    public let documentWriteIntent: ResearchDocumentWriteIntent?
    public let conflictResolutionIntent: ResearchWriteConflictResolutionIntent?
    public let resultSubmission: ResearchAgentResultSubmission?
    public let continuationRequest: ResearchContinuationRequest?
    public let methodImprovementSubmission: ResearchMethodImprovementSubmission?

    public init(
        correlationID: UUID = UUID(),
        operation: LocalAgentBridgeOperation,
        run: ResearchRunLocator? = nil,
        pairingCode: ResearchPairingCode? = nil,
        credential: ResearchConnectionCredential? = nil,
        contextRequest: ResearchContextRequest? = nil,
        writeSetIntent: ResearchWriteSetExtensionIntent? = nil,
        documentWriteIntent: ResearchDocumentWriteIntent? = nil,
        conflictResolutionIntent: ResearchWriteConflictResolutionIntent? = nil,
        resultSubmission: ResearchAgentResultSubmission? = nil,
        continuationRequest: ResearchContinuationRequest? = nil,
        methodImprovementSubmission: ResearchMethodImprovementSubmission? = nil
    ) throws {
        let shapeIsValid = switch operation {
        case .pair:
            run != nil && pairingCode != nil && credential == nil
                && contextRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .context:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .query:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest != nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .extendWriteSet:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent != nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .writeDocument:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent != nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .resolveWriteConflict:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent != nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .submitResult:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission != nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .continueResearch:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest != nil
                && methodImprovementSubmission == nil
        case .methodImprovementContext:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .submitMethodImprovement:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission != nil
        case .end:
            run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        }
        guard shapeIsValid else {
            throw LocalAgentBridgeError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.operation = operation
        self.run = run
        self.pairingCode = pairingCode
        self.credential = credential
        self.contextRequest = contextRequest
        self.writeSetIntent = writeSetIntent
        self.documentWriteIntent = documentWriteIntent
        self.conflictResolutionIntent = conflictResolutionIntent
        self.resultSubmission = resultSubmission
        self.continuationRequest = continuationRequest
        self.methodImprovementSubmission = methodImprovementSubmission
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case operation
        case run
        case pairingCode = "pairing_code"
        case credential
        case contextRequest = "context_request"
        case writeSetIntent = "write_set_intent"
        case documentWriteIntent = "document_write_intent"
        case conflictResolutionIntent = "conflict_resolution_intent"
        case resultSubmission = "result_submission"
        case continuationRequest = "continuation_request"
        case methodImprovementSubmission = "method_improvement_submission"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(correlationID, forKey: .correlationID)
        try container.encode(operation, forKey: .operation)
        try container.encodeIfPresent(run, forKey: .run)
        try container.encodeIfPresent(pairingCode?.rawValue, forKey: .pairingCode)
        try container.encodeIfPresent(
            credential.map(LocalAgentBridgeWireCredential.init),
            forKey: .credential
        )
        try container.encodeIfPresent(contextRequest, forKey: .contextRequest)
        try container.encodeIfPresent(writeSetIntent, forKey: .writeSetIntent)
        try container.encodeIfPresent(documentWriteIntent, forKey: .documentWriteIntent)
        try container.encodeIfPresent(
            conflictResolutionIntent,
            forKey: .conflictResolutionIntent
        )
        try container.encodeIfPresent(resultSubmission, forKey: .resultSubmission)
        try container.encodeIfPresent(continuationRequest, forKey: .continuationRequest)
        try container.encodeIfPresent(
            methodImprovementSubmission,
            forKey: .methodImprovementSubmission
        )
    }

    public init(from decoder: Decoder) throws {
        try LocalAgentBridgeWireCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw LocalAgentBridgeError.unsupportedVersion(version)
        }
        let pairingCode: ResearchPairingCode?
        if let rawPairingCode = try container.decodeIfPresent(
            String.self,
            forKey: .pairingCode
        ) {
            guard let validated = ResearchPairingCode(rawValue: rawPairingCode) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .pairingCode,
                    in: container,
                    debugDescription: "The one-time Pairing Code is invalid."
                )
            }
            pairingCode = validated
        } else {
            pairingCode = nil
        }
        let credential = try container.decodeIfPresent(
            LocalAgentBridgeWireCredential.self,
            forKey: .credential
        )?.value
        try self.init(
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            operation: container.decode(LocalAgentBridgeOperation.self, forKey: .operation),
            run: container.decodeIfPresent(ResearchRunLocator.self, forKey: .run),
            pairingCode: pairingCode,
            credential: credential,
            contextRequest: container.decodeIfPresent(
                ResearchContextRequest.self,
                forKey: .contextRequest
            ),
            writeSetIntent: container.decodeIfPresent(
                ResearchWriteSetExtensionIntent.self,
                forKey: .writeSetIntent
            ),
            documentWriteIntent: container.decodeIfPresent(
                ResearchDocumentWriteIntent.self,
                forKey: .documentWriteIntent
            ),
            conflictResolutionIntent: container.decodeIfPresent(
                ResearchWriteConflictResolutionIntent.self,
                forKey: .conflictResolutionIntent
            ),
            resultSubmission: container.decodeIfPresent(
                ResearchAgentResultSubmission.self,
                forKey: .resultSubmission
            ),
            continuationRequest: container.decodeIfPresent(
                ResearchContinuationRequest.self,
                forKey: .continuationRequest
            ),
            methodImprovementSubmission: container.decodeIfPresent(
                ResearchMethodImprovementSubmission.self,
                forKey: .methodImprovementSubmission
            )
        )
    }

    public var description: String {
        "<redacted local Agent bridge request \(operation.rawValue) \(correlationID.uuidString.lowercased())>"
    }

    public var debugDescription: String { description }
}

public enum LocalAgentBridgeErrorCode: String, Codable, Sendable {
    case unavailable
    case invalidFrame = "invalid_frame"
    case invalidRequest = "invalid_request"
    case unsupportedVersion = "unsupported_version"
    case permissionDenied = "permission_denied"
    case timeout
    case outcomeUnknown = "outcome_unknown"
    case operationFailed = "operation_failed"
}

public struct LocalAgentBridgeErrorPayload: Codable, Hashable, Sendable {
    public let code: LocalAgentBridgeErrorCode
    public let message: String

    public init(code: LocalAgentBridgeErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, message
    }

    public init(from decoder: Decoder) throws {
        try LocalAgentBridgeWireCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let message = try container.decode(String.self, forKey: .message)
        guard !message.isEmpty, message.utf8.count <= 1_024 else {
            throw LocalAgentBridgeError.invalidResponse
        }
        code = try container.decode(LocalAgentBridgeErrorCode.self, forKey: .code)
        self.message = message
    }
}

public struct LocalAgentBridgeResponse: Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 11

    public let schemaVersion: Int
    public let correlationID: UUID
    public let credential: ResearchConnectionCredential?
    public let context: ResearchAuthenticatedRunContext?
    public let researchContext: ResearchContextResponse?
    public let writeSetResult: ResearchWriteSetExtensionResult?
    public let documentWriteResult: ResearchDocumentWriteResult?
    public let conflictResolutionResult: ResearchWriteConflictResolutionResult?
    public let resultReceipt: ResearchAgentResultReceipt?
    public let continuationResult: ResearchContinuationResult?
    public let methodImprovementContext: ResearchMethodImprovementContext?
    public let methodImprovementReceipt: ResearchMethodImprovementReceipt?
    public let endReceipt: ResearchRunEndReceipt?
    public let error: LocalAgentBridgeErrorPayload?

    public init(
        correlationID: UUID,
        credential: ResearchConnectionCredential? = nil,
        context: ResearchAuthenticatedRunContext? = nil,
        researchContext: ResearchContextResponse? = nil,
        writeSetResult: ResearchWriteSetExtensionResult? = nil,
        documentWriteResult: ResearchDocumentWriteResult? = nil,
        conflictResolutionResult: ResearchWriteConflictResolutionResult? = nil,
        resultReceipt: ResearchAgentResultReceipt? = nil,
        continuationResult: ResearchContinuationResult? = nil,
        methodImprovementContext: ResearchMethodImprovementContext? = nil,
        methodImprovementReceipt: ResearchMethodImprovementReceipt? = nil,
        endReceipt: ResearchRunEndReceipt? = nil,
        error: LocalAgentBridgeErrorPayload? = nil
    ) throws {
        let payloadCount = [
            credential != nil,
            context != nil,
            researchContext != nil,
            writeSetResult != nil,
            documentWriteResult != nil,
            conflictResolutionResult != nil,
            resultReceipt != nil,
            continuationResult != nil,
            methodImprovementContext != nil,
            methodImprovementReceipt != nil,
            endReceipt != nil,
            error != nil,
        ]
            .filter { $0 }.count
        guard payloadCount == 1 else {
            throw LocalAgentBridgeError.invalidResponse
        }
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.credential = credential
        self.context = context
        self.researchContext = researchContext
        self.writeSetResult = writeSetResult
        self.documentWriteResult = documentWriteResult
        self.conflictResolutionResult = conflictResolutionResult
        self.resultReceipt = resultReceipt
        self.continuationResult = continuationResult
        self.methodImprovementContext = methodImprovementContext
        self.methodImprovementReceipt = methodImprovementReceipt
        self.endReceipt = endReceipt
        self.error = error
        if researchContext != nil,
           try LocalAgentBridgeWireCoding.encode(self).count
                > LocalAgentBridgeLocation.maximumFrameByteCount {
            throw LocalAgentBridgeError.frameTooLarge
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case credential, context
        case researchContext = "research_context"
        case writeSetResult = "write_set_result"
        case documentWriteResult = "document_write_result"
        case conflictResolutionResult = "conflict_resolution_result"
        case resultReceipt = "result_receipt"
        case continuationResult = "continuation_result"
        case methodImprovementContext = "method_improvement_context"
        case methodImprovementReceipt = "method_improvement_receipt"
        case endReceipt = "end_receipt"
        case error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(correlationID, forKey: .correlationID)
        try container.encodeIfPresent(
            credential.map(LocalAgentBridgeWireCredential.init),
            forKey: .credential
        )
        try container.encodeIfPresent(context, forKey: .context)
        try container.encodeIfPresent(researchContext, forKey: .researchContext)
        try container.encodeIfPresent(writeSetResult, forKey: .writeSetResult)
        try container.encodeIfPresent(documentWriteResult, forKey: .documentWriteResult)
        try container.encodeIfPresent(
            conflictResolutionResult,
            forKey: .conflictResolutionResult
        )
        try container.encodeIfPresent(resultReceipt, forKey: .resultReceipt)
        try container.encodeIfPresent(continuationResult, forKey: .continuationResult)
        try container.encodeIfPresent(
            methodImprovementContext,
            forKey: .methodImprovementContext
        )
        try container.encodeIfPresent(
            methodImprovementReceipt,
            forKey: .methodImprovementReceipt
        )
        try container.encodeIfPresent(endReceipt, forKey: .endReceipt)
        try container.encodeIfPresent(error, forKey: .error)
    }

    public init(from decoder: Decoder) throws {
        try LocalAgentBridgeWireCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw LocalAgentBridgeError.unsupportedVersion(version)
        }
        try self.init(
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            credential: container.decodeIfPresent(
                LocalAgentBridgeWireCredential.self,
                forKey: .credential
            )?.value,
            context: container.decodeIfPresent(
                ResearchAuthenticatedRunContext.self,
                forKey: .context
            ),
            researchContext: container.decodeIfPresent(
                ResearchContextResponse.self,
                forKey: .researchContext
            ),
            writeSetResult: container.decodeIfPresent(
                ResearchWriteSetExtensionResult.self,
                forKey: .writeSetResult
            ),
            documentWriteResult: container.decodeIfPresent(
                ResearchDocumentWriteResult.self,
                forKey: .documentWriteResult
            ),
            conflictResolutionResult: container.decodeIfPresent(
                ResearchWriteConflictResolutionResult.self,
                forKey: .conflictResolutionResult
            ),
            resultReceipt: container.decodeIfPresent(
                ResearchAgentResultReceipt.self,
                forKey: .resultReceipt
            ),
            continuationResult: container.decodeIfPresent(
                ResearchContinuationResult.self,
                forKey: .continuationResult
            ),
            methodImprovementContext: container.decodeIfPresent(
                ResearchMethodImprovementContext.self,
                forKey: .methodImprovementContext
            ),
            methodImprovementReceipt: container.decodeIfPresent(
                ResearchMethodImprovementReceipt.self,
                forKey: .methodImprovementReceipt
            ),
            endReceipt: container.decodeIfPresent(
                ResearchRunEndReceipt.self,
                forKey: .endReceipt
            ),
            error: container.decodeIfPresent(
                LocalAgentBridgeErrorPayload.self,
                forKey: .error
            )
        )
    }

    public var description: String {
        "<redacted local Agent bridge response \(correlationID.uuidString.lowercased())>"
    }

    public var debugDescription: String { description }
}

public enum LocalAgentBridgeError: LocalizedError, Hashable, Sendable {
    case unavailable
    case invalidFrame
    case invalidRequest
    case invalidResponse
    case unsupportedVersion(Int)
    case permissionDenied
    case timeout
    case outcomeUnknown
    case frameTooLarge
    case unsafeLocation
    case socketPathTooLong
    case alreadyRunning
    case systemCall(String, Int32)
    case remote(LocalAgentBridgeErrorPayload)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Scholium is not running or its local Agent bridge is unavailable."
        case .invalidFrame: "The local Agent bridge frame was invalid."
        case .invalidRequest: "The local Agent bridge request was invalid."
        case .invalidResponse: "The local Agent bridge response was invalid."
        case .unsupportedVersion(let version):
            "Local Agent bridge schema version \(version) is unsupported."
        case .permissionDenied: "The local Agent bridge rejected the peer identity."
        case .timeout: "The local Agent bridge operation timed out."
        case .outcomeUnknown:
            "The Agent request outcome is unknown. Query the same request ID before retrying."
        case .frameTooLarge: "The local Agent bridge frame exceeded its size limit."
        case .unsafeLocation: "The local Agent bridge storage location is unsafe."
        case .socketPathTooLong: "The local Agent bridge socket path is too long."
        case .alreadyRunning: "Another Scholium Agent bridge already owns this location."
        case .systemCall(let operation, let code):
            "The local Agent bridge could not \(operation) (errno \(code))."
        case .remote(let payload): payload.message
        }
    }
}

public enum LocalAgentBridgeLocation {
    public static let maximumFrameByteCount = 1024 * 1024
    public static let timeout: TimeInterval = 5
    public static let clientTimeout: TimeInterval = 6
    public static let cancellationGrace: TimeInterval = 1

    public static func socketURL(applicationSupportURL: URL) throws -> URL {
        let url = applicationSupportURL
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("s", isDirectory: false)
        guard url.path.utf8.count + 1 <= MemoryLayout.size(
            ofValue: sockaddr_un().sun_path
        ) else {
            throw LocalAgentBridgeError.socketPathTooLong
        }
        return url
    }
}

public final class LocalAgentBridgeClient: @unchecked Sendable {
    private let socketURL: URL
    private let timeout: TimeInterval

    public init(
        applicationSupportURL: URL,
        timeout: TimeInterval = LocalAgentBridgeLocation.clientTimeout
    ) throws {
        socketURL = try LocalAgentBridgeLocation.socketURL(
            applicationSupportURL: applicationSupportURL.standardizedFileURL
        )
        self.timeout = min(max(timeout, 0.1), 30)
    }

    public func send(_ request: LocalAgentBridgeRequest) throws -> LocalAgentBridgeResponse {
        try LocalAgentBridgeIO.validateClientLocation(socketURL)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LocalAgentBridgeError.systemCall("create its socket", errno)
        }
        defer { Darwin.close(descriptor) }
        try LocalAgentBridgeIO.configure(descriptor, timeout: timeout)
        let address = try LocalAgentBridgeIO.address(for: socketURL.path)
        let result = LocalAgentBridgeIO.withSockAddr(address) { pointer, length in
            Darwin.connect(descriptor, pointer, length)
        }
        guard result == 0 else {
            if [ENOENT, ECONNREFUSED].contains(errno) {
                throw LocalAgentBridgeError.unavailable
            }
            throw LocalAgentBridgeError.systemCall("connect", errno)
        }
        var peerUID = uid_t.max
        var peerGID = gid_t.max
        guard getpeereid(descriptor, &peerUID, &peerGID) == 0,
              peerUID == geteuid() else {
            throw LocalAgentBridgeError.permissionDenied
        }
        let responseData: Data
        do {
            let requestData = try LocalAgentBridgeWireCoding.encode(request)
            try LocalAgentBridgeIO.writeFrame(requestData, to: descriptor)
            responseData = try LocalAgentBridgeIO.readFrame(from: descriptor)
        } catch LocalAgentBridgeError.timeout {
            // Once connected, a send/read deadline cannot establish whether
            // the server durably handled the request. Preserve idempotent
            // convergence semantics instead of inviting a new request ID.
            throw LocalAgentBridgeError.outcomeUnknown
        }
        let response = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: responseData
        )
        guard response.correlationID == request.correlationID else {
            throw LocalAgentBridgeError.invalidResponse
        }
        if let error = response.error {
            throw LocalAgentBridgeError.remote(error)
        }
        return response
    }
}

public enum LocalAgentBridgeHandlerResult: Sendable {
    case credential(ResearchConnectionCredential)
    case context(ResearchAuthenticatedRunContext)
    case researchContext(ResearchContextResponse)
    case writeSet(ResearchWriteSetExtensionResult)
    case documentWrite(ResearchDocumentWriteResult)
    case conflictResolution(ResearchWriteConflictResolutionResult)
    case resultReceipt(ResearchAgentResultReceipt)
    case continuation(ResearchContinuationResult)
    case methodImprovementContext(ResearchMethodImprovementContext)
    case methodImprovementReceipt(ResearchMethodImprovementReceipt)
    case endReceipt(ResearchRunEndReceipt)
}

public final class LocalAgentBridgeServer: @unchecked Sendable {
    public typealias Handler = @Sendable (LocalAgentBridgeRequest) async throws
        -> LocalAgentBridgeHandlerResult

    private let queue = DispatchQueue(label: "com.scholium.agent-bridge")
    private let socketURL: URL
    private let ownerURL: URL
    private let handler: Handler
    private let timeout: TimeInterval
    private let cancellationGrace: TimeInterval
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var ownerDescriptor: Int32 = -1
    private var stopping = false
    private var currentHandlerID: UUID?
    private var currentHandlerTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    public init(
        applicationSupportURL: URL,
        timeout: TimeInterval = LocalAgentBridgeLocation.timeout,
        cancellationGrace: TimeInterval = LocalAgentBridgeLocation.cancellationGrace,
        handler: @escaping Handler
    ) throws {
        let supportURL = applicationSupportURL.standardizedFileURL
        socketURL = try LocalAgentBridgeLocation.socketURL(
            applicationSupportURL: supportURL
        )
        ownerURL = socketURL.deletingLastPathComponent()
            .appendingPathComponent("o", isDirectory: false)
        self.timeout = min(max(timeout, 0.1), 30)
        self.cancellationGrace = min(max(cancellationGrace, 0.1), 5)
        self.handler = handler
        do {
            try start()
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    public func stop() {
        _ = beginStopping()
    }

    /// Stops accepting work and waits for the one owned request handler to
    /// observe cancellation. The serial accept loop never starts another
    /// request while a timed-out handler remains alive.
    public func stopAndWait(
        timeout: TimeInterval = LocalAgentBridgeLocation.timeout
    ) async -> Bool {
        let stopTask = beginStopping()
        let boundedTimeout = min(max(timeout, 0.1), 30)
        return await withCheckedContinuation { continuation in
            let waiter = LocalAgentBridgeStopWaiter(continuation)
            Task {
                await stopTask.value
                waiter.resolve(true)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + boundedTimeout
            ) {
                waiter.resolve(false)
            }
        }
    }

    private func beginStopping() -> Task<Void, Never> {
        lock.lock()
        if let stopTask {
            lock.unlock()
            return stopTask
        }
        stopping = true
        let listener = self.listener
        self.listener = -1
        let ownerDescriptor = self.ownerDescriptor
        self.ownerDescriptor = -1
        if listener >= 0 {
            Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
        }
        LocalAgentBridgeIO.removeOwnedSocketIfPresent(socketURL)
        let handlerTask = currentHandlerTask
        let handlerID = currentHandlerID
        let stopTask = Task.detached { [weak self] in
            handlerTask?.cancel()
            await handlerTask?.value
            if let handlerID {
                self?.clearCurrentHandler(id: handlerID)
            }
            if ownerDescriptor >= 0 {
                flock(ownerDescriptor, LOCK_UN)
                Darwin.close(ownerDescriptor)
            }
        }
        self.stopTask = stopTask
        lock.unlock()
        return stopTask
    }

    private func start() throws {
        try LocalAgentBridgeIO.preparePrivateDirectory(ownerURL)
        ownerDescriptor = Darwin.open(ownerURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard ownerDescriptor >= 0 else {
            throw LocalAgentBridgeError.systemCall("open its owner lock", errno)
        }
        guard flock(ownerDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(ownerDescriptor)
            ownerDescriptor = -1
            throw LocalAgentBridgeError.alreadyRunning
        }
        LocalAgentBridgeIO.removeOwnedSocketIfPresent(socketURL)

        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw LocalAgentBridgeError.systemCall("create its listener", errno)
        }
        try LocalAgentBridgeIO.configure(
            listener,
            timeout: timeout
        )
        let address = try LocalAgentBridgeIO.address(for: socketURL.path)
        let bindResult = LocalAgentBridgeIO.withSockAddr(address) { pointer, length in
            Darwin.bind(listener, pointer, length)
        }
        guard bindResult == 0 else {
            throw LocalAgentBridgeError.systemCall("bind", errno)
        }
        guard chmod(socketURL.path, 0o600) == 0 else {
            throw LocalAgentBridgeError.systemCall("protect its socket", errno)
        }
        guard Darwin.listen(listener, 8) == 0 else {
            throw LocalAgentBridgeError.systemCall("listen", errno)
        }
        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let descriptor = listener
            let shouldStop = stopping
            lock.unlock()
            guard !shouldStop, descriptor >= 0 else { return }

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
            try LocalAgentBridgeIO.configure(
                peer,
                timeout: timeout
            )
            var peerUID = uid_t.max
            var peerGID = gid_t.max
            guard getpeereid(peer, &peerUID, &peerGID) == 0,
                  peerUID == geteuid() else {
                throw LocalAgentBridgeError.permissionDenied
            }
            let data = try LocalAgentBridgeIO.readFrame(from: peer)
            let request = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: data
            )
            correlationID = request.correlationID
            let semaphore = DispatchSemaphore(value: 0)
            let result = LocalAgentBridgeResultBox()
            let handlerID = UUID()
            let operationHandler = handler
            lock.lock()
            guard !stopping else {
                lock.unlock()
                throw LocalAgentBridgeError.unavailable
            }
            let handlerTask = Task {
                do {
                    try Task.checkCancellation()
                    let record = try await operationHandler(request)
                    try Task.checkCancellation()
                    result.value = .success(record)
                }
                catch { result.value = .failure(error) }
                semaphore.signal()
            }
            currentHandlerID = handlerID
            currentHandlerTask = handlerTask
            lock.unlock()

            let finishedInTime = semaphore.wait(timeout: .now() + timeout)
                == .success
            if !finishedInTime {
                handlerTask.cancel()
                let reaped = semaphore.wait(
                    timeout: .now() + cancellationGrace
                ) == .success
                if !reaped {
                    // A cancellation-insensitive handler must never accumulate
                    // behind new requests. Permanently close this listener and
                    // retain its owner lock until that handler finally exits.
                    _ = beginStopping()
                } else {
                    clearCurrentHandler(id: handlerID)
                }
            } else {
                clearCurrentHandler(id: handlerID)
            }
            guard finishedInTime else {
                throw LocalAgentBridgeError.outcomeUnknown
            }
            let outcome = try result.value?.get() ?? {
                throw LocalAgentBridgeError.invalidResponse
            }()
            let response: LocalAgentBridgeResponse = switch outcome {
            case .credential(let credential):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    credential: credential
                )
            case .context(let context):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    context: context
                )
            case .researchContext(let context):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    researchContext: context
                )
            case .writeSet(let result):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    writeSetResult: result
                )
            case .documentWrite(let result):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    documentWriteResult: result
                )
            case .conflictResolution(let result):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    conflictResolutionResult: result
                )
            case .resultReceipt(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    resultReceipt: receipt
                )
            case .continuation(let result):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    continuationResult: result
                )
            case .methodImprovementContext(let context):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    methodImprovementContext: context
                )
            case .methodImprovementReceipt(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    methodImprovementReceipt: receipt
                )
            case .endReceipt(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    endReceipt: receipt
                )
            }
            try LocalAgentBridgeIO.writeFrame(
                LocalAgentBridgeWireCoding.encode(response),
                to: peer
            )
        } catch {
            let payload = LocalAgentBridgeWireCoding.errorPayload(error)
            if let response = try? LocalAgentBridgeResponse(
                correlationID: correlationID,
                error: payload
            ), let data = try? LocalAgentBridgeWireCoding.encode(response) {
                try? LocalAgentBridgeIO.writeFrame(data, to: peer)
            }
        }
    }

    private func clearCurrentHandler(id: UUID) {
        lock.lock()
        if currentHandlerID == id {
            currentHandlerID = nil
            currentHandlerTask = nil
        }
        lock.unlock()
    }
}

private final class LocalAgentBridgeStopWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ result: Bool) {
        let continuation = lock.withLock {
            let pending = self.continuation
            self.continuation = nil
            return pending
        }
        continuation?.resume(returning: result)
    }
}

private final class LocalAgentBridgeResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<LocalAgentBridgeHandlerResult, Error>?
    var value: Result<LocalAgentBridgeHandlerResult, Error>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

enum LocalAgentBridgeWireCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(type, from: data)
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let permitted = Set(allowed)
        guard raw.allKeys.allSatisfy({ permitted.contains($0.stringValue) }) else {
            throw LocalAgentBridgeError.invalidRequest
        }
    }

    static func errorPayload(_ error: Error) -> LocalAgentBridgeErrorPayload {
        let code: LocalAgentBridgeErrorCode
        switch error {
        case LocalAgentBridgeError.unavailable:
            code = .unavailable
        case LocalAgentBridgeError.permissionDenied,
             ResearchAgentSessionError.sessionRejected,
             ResearchAgentSessionError.pairingRejected:
            code = .permissionDenied
        case LocalAgentBridgeError.timeout: code = .timeout
        case LocalAgentBridgeError.outcomeUnknown: code = .outcomeUnknown
        case LocalAgentBridgeError.unsupportedVersion(_): code = .unsupportedVersion
        case LocalAgentBridgeError.invalidFrame,
             LocalAgentBridgeError.frameTooLarge:
            code = .invalidFrame
        case LocalAgentBridgeError.invalidRequest,
             is DecodingError:
            code = .invalidRequest
        default: code = .operationFailed
        }
        let message = switch code {
        case .unavailable: "Scholium is unavailable."
        case .invalidFrame: "The bridge frame was invalid."
        case .invalidRequest: "The bridge request was invalid."
        case .unsupportedVersion: "The bridge schema version is unsupported."
        case .permissionDenied: "The bridge request was not authorized."
        case .timeout: "The bridge operation timed out."
        case .outcomeUnknown:
            "The Agent request outcome is unknown. Query the same request ID before retrying."
        case .operationFailed: "Scholium could not complete the bridge operation."
        }
        return LocalAgentBridgeErrorPayload(code: code, message: message)
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }
        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

private enum LocalAgentBridgeIO {
    static func validateClientLocation(_ socketURL: URL) throws {
        let directory = socketURL.deletingLastPathComponent()
        var directoryInfo = stat()
        var socketInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0 else {
            if errno == ENOENT { throw LocalAgentBridgeError.unavailable }
            throw LocalAgentBridgeError.unsafeLocation
        }
        guard directoryInfo.st_uid == geteuid(),
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              (directoryInfo.st_mode & 0o077) == 0 else {
            throw LocalAgentBridgeError.unsafeLocation
        }
        guard lstat(socketURL.path, &socketInfo) == 0 else {
            if errno == ENOENT { throw LocalAgentBridgeError.unavailable }
            throw LocalAgentBridgeError.unsafeLocation
        }
        guard socketInfo.st_uid == geteuid(),
              (socketInfo.st_mode & S_IFMT) == S_IFSOCK,
              (socketInfo.st_mode & 0o177) == 0 else {
            throw LocalAgentBridgeError.unsafeLocation
        }
    }

    static func preparePrivateDirectory(_ ownerURL: URL) throws {
        let directory = ownerURL.deletingLastPathComponent()
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw LocalAgentBridgeError.systemCall("create its directory", errno)
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw LocalAgentBridgeError.unsafeLocation
        }
        guard chmod(directory.path, 0o700) == 0 else {
            throw LocalAgentBridgeError.systemCall("protect its directory", errno)
        }
    }

    static func removeOwnedSocketIfPresent(_ url: URL) {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        guard info.st_uid == geteuid(),
              (info.st_mode & S_IFMT) == S_IFSOCK else { return }
        _ = unlink(url.path)
    }

    static func configure(_ descriptor: Int32, timeout: TimeInterval) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout.size(ofValue: enabled))
        ) == 0 else {
            throw LocalAgentBridgeError.systemCall("configure its socket", errno)
        }
        var value = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                option,
                &value,
                socklen_t(MemoryLayout.size(ofValue: value))
            ) == 0 else {
                throw LocalAgentBridgeError.systemCall("set its timeout", errno)
            }
        }
    }

    static func address(for path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw LocalAgentBridgeError.socketPathTooLong
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: bytes)
        }
        let length = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + bytes.count
        address.sun_len = UInt8(length)
        return address
    }

    static func withSockAddr<T>(
        _ address: sockaddr_un,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) rethrows -> T {
        var address = address
        let length = socklen_t(address.sun_len)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, length)
            }
        }
    }

    static func readFrame(from descriptor: Int32) throws -> Data {
        let header = try readExactly(4, from: descriptor)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0 else { throw LocalAgentBridgeError.invalidFrame }
        guard length <= LocalAgentBridgeLocation.maximumFrameByteCount else {
            throw LocalAgentBridgeError.frameTooLarge
        }
        return try readExactly(Int(length), from: descriptor)
    }

    static func writeFrame(_ data: Data, to descriptor: Int32) throws {
        guard !data.isEmpty else { throw LocalAgentBridgeError.invalidFrame }
        guard data.count <= LocalAgentBridgeLocation.maximumFrameByteCount else {
            throw LocalAgentBridgeError.frameTooLarge
        }
        let length = UInt32(data.count)
        let header = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ])
        try writeAll(header, to: descriptor)
        try writeAll(data, to: descriptor)
    }

    private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = data.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset)
            }
            if readCount == 0 { throw LocalAgentBridgeError.invalidFrame }
            if readCount < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw LocalAgentBridgeError.timeout
                }
                throw LocalAgentBridgeError.systemCall("read", errno)
            }
            offset += readCount
        }
        return data
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw LocalAgentBridgeError.timeout
                }
                throw LocalAgentBridgeError.systemCall("write", errno)
            }
            offset += written
        }
    }
}
