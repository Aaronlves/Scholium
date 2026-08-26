import Darwin
import Foundation
import ScholiumContracts
import ScholiumCore

public enum LocalAgentBridgeOperation: String, Codable, Sendable {
    case preflightAnalysisCreation = "preflight_analysis_creation"
    case start
    case pair
    case revokeSession = "revoke_session"
    case context
    case query
    case discussionReply = "discussion_reply"
    case discussionFinish = "discussion_finish"
    case extendWriteSet = "extend_write_set"
    case writeDocument = "write_document"
    case writeZoteroBinding = "write_zotero_binding"
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
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        try LocalAgentBridgeWireCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionID = try container.decode(UUID.self, forKey: .sessionID)
        let secret = try container.decode(String.self, forKey: .secret)
        let expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        do {
            value = try ResearchConnectionCredential(
                sessionID: sessionID,
                secret: secret,
                expiresAt: expiresAt
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
        try container.encode(value.expiresAt, forKey: .expiresAt)
    }
}

public struct LocalAgentBridgeRequest: Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 20

    public let schemaVersion: Int
    public let correlationID: UUID
    public let operation: LocalAgentBridgeOperation
    public let triptychID: UUID?
    public let run: ResearchRunLocator?
    public let analysisCreationPreflightRequest:
        ResearchAgentAnalysisCreationPreflightRequest?
    public let startRequest: ResearchAgentStartRequest?
    public let pairingCode: ResearchPairingCode?
    public let credential: ResearchConnectionCredential?
    public let contextRequest: ResearchContextRequest?
    public let discussionReplyRequest: ResearchAgentDiscussionReplyRequest?
    public let writeSetIntent: ResearchWriteSetExtensionIntent?
    public let documentWriteIntent: ResearchDocumentWriteIntent?
    public let zoteroBindingWriteIntent: ResearchZoteroBindingWriteIntent?
    public let conflictResolutionIntent: ResearchWriteConflictResolutionIntent?
    public let resultSubmission: ResearchAgentResultSubmission?
    public let continuationRequest: ResearchContinuationRequest?
    public let methodImprovementSubmission: ResearchMethodImprovementSubmission?

    public init(
        correlationID: UUID = UUID(),
        operation: LocalAgentBridgeOperation,
        triptychID: UUID? = nil,
        run: ResearchRunLocator? = nil,
        analysisCreationPreflightRequest:
            ResearchAgentAnalysisCreationPreflightRequest? = nil,
        startRequest: ResearchAgentStartRequest? = nil,
        pairingCode: ResearchPairingCode? = nil,
        credential: ResearchConnectionCredential? = nil,
        contextRequest: ResearchContextRequest? = nil,
        discussionReplyRequest: ResearchAgentDiscussionReplyRequest? = nil,
        writeSetIntent: ResearchWriteSetExtensionIntent? = nil,
        documentWriteIntent: ResearchDocumentWriteIntent? = nil,
        zoteroBindingWriteIntent: ResearchZoteroBindingWriteIntent? = nil,
        conflictResolutionIntent: ResearchWriteConflictResolutionIntent? = nil,
        resultSubmission: ResearchAgentResultSubmission? = nil,
        continuationRequest: ResearchContinuationRequest? = nil,
        methodImprovementSubmission: ResearchMethodImprovementSubmission? = nil
    ) throws {
        let shapeIsValid = switch operation {
        case .preflightAnalysisCreation:
            triptychID != nil && analysisCreationPreflightRequest != nil
                && run == nil && startRequest == nil && pairingCode == nil
                && credential == nil && contextRequest == nil
                && discussionReplyRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil && resultSubmission == nil
                && continuationRequest == nil && methodImprovementSubmission == nil
        case .start:
            triptychID != nil && startRequest != nil && run == nil
                && pairingCode == nil && credential == nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil && resultSubmission == nil
                && continuationRequest == nil && methodImprovementSubmission == nil
        case .pair:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode != nil && credential == nil
                && contextRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .revokeSession:
            triptychID == nil && startRequest == nil
                && run == nil && pairingCode == nil && credential != nil
                && contextRequest == nil && discussionReplyRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .context:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .query:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest != nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .discussionReply:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil
                && discussionReplyRequest != nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .discussionFinish:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && discussionReplyRequest == nil
                && writeSetIntent == nil && documentWriteIntent == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && resultSubmission == nil && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .extendWriteSet:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent != nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .writeDocument:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent != nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .writeZoteroBinding:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil
                && zoteroBindingWriteIntent != nil
                && resultSubmission == nil && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .resolveWriteConflict:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent != nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .submitResult:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission != nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .continueResearch:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest != nil
                && methodImprovementSubmission == nil
        case .methodImprovementContext:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        case .submitMethodImprovement:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission != nil
        case .end:
            triptychID == nil && startRequest == nil
                && run != nil && pairingCode == nil && credential != nil
                && contextRequest == nil && writeSetIntent == nil
                && documentWriteIntent == nil && resultSubmission == nil
                && zoteroBindingWriteIntent == nil
                && conflictResolutionIntent == nil
                && continuationRequest == nil
                && methodImprovementSubmission == nil
        }
        guard shapeIsValid,
              (operation == .preflightAnalysisCreation
                  ? analysisCreationPreflightRequest != nil
                  : analysisCreationPreflightRequest == nil),
              (operation == .discussionReply
                  ? discussionReplyRequest != nil
                  : discussionReplyRequest == nil) else {
            throw LocalAgentBridgeError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.operation = operation
        self.triptychID = triptychID
        self.run = run
        self.analysisCreationPreflightRequest = analysisCreationPreflightRequest
        self.startRequest = startRequest
        self.pairingCode = pairingCode
        self.credential = credential
        self.contextRequest = contextRequest
        self.discussionReplyRequest = discussionReplyRequest
        self.writeSetIntent = writeSetIntent
        self.documentWriteIntent = documentWriteIntent
        self.zoteroBindingWriteIntent = zoteroBindingWriteIntent
        self.conflictResolutionIntent = conflictResolutionIntent
        self.resultSubmission = resultSubmission
        self.continuationRequest = continuationRequest
        self.methodImprovementSubmission = methodImprovementSubmission
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case correlationID = "correlation_id"
        case operation
        case triptychID = "triptych_id"
        case run
        case analysisCreationPreflightRequest = "analysis_creation_preflight_request"
        case startRequest = "start_request"
        case pairingCode = "pairing_code"
        case credential
        case contextRequest = "context_request"
        case discussionReplyRequest = "discussion_reply_request"
        case writeSetIntent = "write_set_intent"
        case documentWriteIntent = "document_write_intent"
        case zoteroBindingWriteIntent = "zotero_binding_write_intent"
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
        try container.encodeIfPresent(triptychID, forKey: .triptychID)
        try container.encodeIfPresent(run, forKey: .run)
        try container.encodeIfPresent(
            analysisCreationPreflightRequest,
            forKey: .analysisCreationPreflightRequest
        )
        try container.encodeIfPresent(startRequest, forKey: .startRequest)
        try container.encodeIfPresent(pairingCode?.rawValue, forKey: .pairingCode)
        try container.encodeIfPresent(
            credential.map(LocalAgentBridgeWireCredential.init),
            forKey: .credential
        )
        try container.encodeIfPresent(contextRequest, forKey: .contextRequest)
        try container.encodeIfPresent(
            discussionReplyRequest,
            forKey: .discussionReplyRequest
        )
        try container.encodeIfPresent(writeSetIntent, forKey: .writeSetIntent)
        try container.encodeIfPresent(documentWriteIntent, forKey: .documentWriteIntent)
        try container.encodeIfPresent(
            zoteroBindingWriteIntent,
            forKey: .zoteroBindingWriteIntent
        )
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
            triptychID: container.decodeIfPresent(UUID.self, forKey: .triptychID),
            run: container.decodeIfPresent(ResearchRunLocator.self, forKey: .run),
            analysisCreationPreflightRequest: container.decodeIfPresent(
                ResearchAgentAnalysisCreationPreflightRequest.self,
                forKey: .analysisCreationPreflightRequest
            ),
            startRequest: container.decodeIfPresent(
                ResearchAgentStartRequest.self,
                forKey: .startRequest
            ),
            pairingCode: pairingCode,
            credential: credential,
            contextRequest: container.decodeIfPresent(
                ResearchContextRequest.self,
                forKey: .contextRequest
            ),
            discussionReplyRequest: container.decodeIfPresent(
                ResearchAgentDiscussionReplyRequest.self,
                forKey: .discussionReplyRequest
            ),
            writeSetIntent: container.decodeIfPresent(
                ResearchWriteSetExtensionIntent.self,
                forKey: .writeSetIntent
            ),
            documentWriteIntent: container.decodeIfPresent(
                ResearchDocumentWriteIntent.self,
                forKey: .documentWriteIntent
            ),
            zoteroBindingWriteIntent: container.decodeIfPresent(
                ResearchZoteroBindingWriteIntent.self,
                forKey: .zoteroBindingWriteIntent
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
    case sessionExpired = "session_expired"
    case staleProjection = "stale_projection"
    case staleRun = "stale_run"
    case missingSourceEvidence = "missing_source_evidence"
    case pathOccupied = "path_occupied"
    case identityOccupied = "identity_occupied"
    case identitySourceMissingOrTrashed = "identity_source_missing_or_trashed"
    case sourceUnreadable = "source_unreadable"
    case replayConflict = "replay_conflict"
    case timeout
    case outcomeUnknown = "outcome_unknown"
    case operationFailed = "operation_failed"
}

public struct LocalAgentBridgeErrorPayload: Codable, Hashable, Sendable {
    public let code: LocalAgentBridgeErrorCode
    public let message: String
    public let recovery: AgentOperationRecovery

    public init(
        code: LocalAgentBridgeErrorCode,
        message: String,
        recovery: AgentOperationRecovery? = nil
    ) {
        self.code = code
        self.message = message
        self.recovery = recovery ?? Self.defaultRecovery(for: code)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code, message, recovery
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
        recovery = try container.decode(AgentOperationRecovery.self, forKey: .recovery)
    }

    static func outcomeUnknownRecovery(
        for request: LocalAgentBridgeRequest
    ) -> AgentOperationRecovery {
        switch request.operation {
        case .preflightAnalysisCreation:
            AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .rerunCreationPreflight
            )
        case .start where request.startRequest?.newAnalysis != nil:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .rerunCreationPreflight
            )
        case .context, .query, .methodImprovementContext:
            AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .retryExactRequest
            )
        case .discussionReply, .extendWriteSet, .writeDocument,
             .writeZoteroBinding, .resolveWriteConflict, .submitResult,
             .continueResearch, .submitMethodImprovement:
            AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .retryExactRequest
            )
        case .discussionFinish, .revokeSession, .end:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .stopAndReport
            )
        case .pair:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .copyNewHandoffAndPairSameRun
            )
        case .start:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .stopAndReport
            )
        }
    }

    static func defaultRecovery(
        for code: LocalAgentBridgeErrorCode
    ) -> AgentOperationRecovery {
        switch code {
        case .pathOccupied:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .requestResearcherDistinctFilenameAndPreflight
            )
        case .identityOccupied:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .startExistingAnalysis
            )
        case .identitySourceMissingOrTrashed:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .requestResearcherRecoveryChoice,
                creationBranches: [
                    AgentCreationRecoveryBranch(
                        kind: .restoreOriginalSource,
                        mustReuseRequestIdentity: true,
                        nextStep: .retryExactRequest
                    ),
                    AgentCreationRecoveryBranch(
                        kind: .explicitlyCreateAtDistinctDestination,
                        mustReuseRequestIdentity: false,
                        nextStep: .requestResearcherDistinctFilenameAndPreflight
                    ),
                ]
            )
        case .sourceUnreadable:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .resolveSourceAccess
            )
        case .staleProjection:
            AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .retryExactRequest
            )
        case .replayConflict:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .inspectOriginalRequestState
            )
        case .sessionExpired:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .copyNewHandoffAndPairSameRun
            )
        case .outcomeUnknown, .timeout:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .stopAndReport
            )
        case .staleRun:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .startNewActionFromCurrentRevision
            )
        case .invalidFrame, .invalidRequest, .unsupportedVersion:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .correctRequest
            )
        case .missingSourceEvidence:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .correctRequest
            )
        case .unavailable, .permissionDenied, .operationFailed:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .stopAndReport
            )
        }
    }
}

public struct LocalAgentBridgeResponse: Codable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let currentSchemaVersion = 23

    public let schemaVersion: Int
    public let correlationID: UUID
    public let analysisCreationPreflight: ResearchAgentAnalysisCreationPreflight?
    public let credential: ResearchConnectionCredential?
    public let startReceipt: ResearchAgentStartReceipt?
    public let sessionRevocationReceipt: ResearchAgentSessionRevocationReceipt?
    public let context: ResearchAuthenticatedRunContext?
    public let researchContext: ResearchContextResponse?
    public let discussionReplyReceipt: ResearchAgentDiscussionReplyReceipt?
    public let discussionFinishReceipt: ResearchAgentDiscussionFinishReceipt?
    public let writeSetResult: ResearchWriteSetExtensionResult?
    public let documentWriteResult: ResearchDocumentWriteResult?
    public let zoteroBindingWriteResult: ResearchZoteroBindingWriteResult?
    public let conflictResolutionResult: ResearchWriteConflictResolutionResult?
    public let resultReceipt: ResearchAgentResultReceipt?
    public let continuationResult: ResearchContinuationResult?
    public let methodImprovementContext: ResearchMethodImprovementContext?
    public let methodImprovementReceipt: ResearchMethodImprovementReceipt?
    public let endReceipt: ResearchRunEndReceipt?
    public let error: LocalAgentBridgeErrorPayload?

    public init(
        correlationID: UUID,
        analysisCreationPreflight: ResearchAgentAnalysisCreationPreflight? = nil,
        credential: ResearchConnectionCredential? = nil,
        startReceipt: ResearchAgentStartReceipt? = nil,
        sessionRevocationReceipt: ResearchAgentSessionRevocationReceipt? = nil,
        context: ResearchAuthenticatedRunContext? = nil,
        researchContext: ResearchContextResponse? = nil,
        discussionReplyReceipt: ResearchAgentDiscussionReplyReceipt? = nil,
        discussionFinishReceipt: ResearchAgentDiscussionFinishReceipt? = nil,
        writeSetResult: ResearchWriteSetExtensionResult? = nil,
        documentWriteResult: ResearchDocumentWriteResult? = nil,
        zoteroBindingWriteResult: ResearchZoteroBindingWriteResult? = nil,
        conflictResolutionResult: ResearchWriteConflictResolutionResult? = nil,
        resultReceipt: ResearchAgentResultReceipt? = nil,
        continuationResult: ResearchContinuationResult? = nil,
        methodImprovementContext: ResearchMethodImprovementContext? = nil,
        methodImprovementReceipt: ResearchMethodImprovementReceipt? = nil,
        endReceipt: ResearchRunEndReceipt? = nil,
        error: LocalAgentBridgeErrorPayload? = nil
    ) throws {
        let payloadCount = [
            analysisCreationPreflight != nil,
            credential != nil && startReceipt == nil,
            startReceipt != nil,
            sessionRevocationReceipt != nil,
            context != nil,
            researchContext != nil,
            discussionReplyReceipt != nil,
            discussionFinishReceipt != nil,
            writeSetResult != nil,
            documentWriteResult != nil,
            zoteroBindingWriteResult != nil,
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
        guard startReceipt == nil || credential != nil else {
            throw LocalAgentBridgeError.invalidResponse
        }
        schemaVersion = Self.currentSchemaVersion
        self.correlationID = correlationID
        self.analysisCreationPreflight = analysisCreationPreflight
        self.credential = credential
        self.startReceipt = startReceipt
        self.sessionRevocationReceipt = sessionRevocationReceipt
        self.context = context
        self.researchContext = researchContext
        self.discussionReplyReceipt = discussionReplyReceipt
        self.discussionFinishReceipt = discussionFinishReceipt
        self.writeSetResult = writeSetResult
        self.documentWriteResult = documentWriteResult
        self.zoteroBindingWriteResult = zoteroBindingWriteResult
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
        case analysisCreationPreflight = "analysis_creation_preflight"
        case credential, startReceipt = "start_receipt", context
        case sessionRevocationReceipt = "session_revocation_receipt"
        case researchContext = "research_context"
        case discussionReplyReceipt = "discussion_reply_receipt"
        case discussionFinishReceipt = "discussion_finish_receipt"
        case writeSetResult = "write_set_result"
        case documentWriteResult = "document_write_result"
        case zoteroBindingWriteResult = "zotero_binding_write_result"
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
            analysisCreationPreflight,
            forKey: .analysisCreationPreflight
        )
        try container.encodeIfPresent(
            credential.map(LocalAgentBridgeWireCredential.init),
            forKey: .credential
        )
        try container.encodeIfPresent(startReceipt, forKey: .startReceipt)
        try container.encodeIfPresent(
            sessionRevocationReceipt,
            forKey: .sessionRevocationReceipt
        )
        try container.encodeIfPresent(context, forKey: .context)
        try container.encodeIfPresent(researchContext, forKey: .researchContext)
        try container.encodeIfPresent(
            discussionReplyReceipt,
            forKey: .discussionReplyReceipt
        )
        try container.encodeIfPresent(
            discussionFinishReceipt,
            forKey: .discussionFinishReceipt
        )
        try container.encodeIfPresent(writeSetResult, forKey: .writeSetResult)
        try container.encodeIfPresent(documentWriteResult, forKey: .documentWriteResult)
        try container.encodeIfPresent(
            zoteroBindingWriteResult,
            forKey: .zoteroBindingWriteResult
        )
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
            analysisCreationPreflight: container.decodeIfPresent(
                ResearchAgentAnalysisCreationPreflight.self,
                forKey: .analysisCreationPreflight
            ),
            credential: container.decodeIfPresent(
                LocalAgentBridgeWireCredential.self,
                forKey: .credential
            )?.value,
            startReceipt: container.decodeIfPresent(
                ResearchAgentStartReceipt.self,
                forKey: .startReceipt
            ),
            sessionRevocationReceipt: container.decodeIfPresent(
                ResearchAgentSessionRevocationReceipt.self,
                forKey: .sessionRevocationReceipt
            ),
            context: container.decodeIfPresent(
                ResearchAuthenticatedRunContext.self,
                forKey: .context
            ),
            researchContext: container.decodeIfPresent(
                ResearchContextResponse.self,
                forKey: .researchContext
            ),
            discussionReplyReceipt: container.decodeIfPresent(
                ResearchAgentDiscussionReplyReceipt.self,
                forKey: .discussionReplyReceipt
            ),
            discussionFinishReceipt: container.decodeIfPresent(
                ResearchAgentDiscussionFinishReceipt.self,
                forKey: .discussionFinishReceipt
            ),
            writeSetResult: container.decodeIfPresent(
                ResearchWriteSetExtensionResult.self,
                forKey: .writeSetResult
            ),
            documentWriteResult: container.decodeIfPresent(
                ResearchDocumentWriteResult.self,
                forKey: .documentWriteResult
            ),
            zoteroBindingWriteResult: container.decodeIfPresent(
                ResearchZoteroBindingWriteResult.self,
                forKey: .zoteroBindingWriteResult
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

public enum LocalAgentBridgeError: LocalizedError, Hashable, Sendable,
    AgentCommandErrorCodeProviding
{
    case unavailable
    case invalidFrame
    case invalidRequest
    case invalidResponse
    case unsupportedVersion(Int)
    case permissionDenied
    case timeout
    case outcomeUnknown(AgentOperationRecovery)
    case frameTooLarge
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
        case .outcomeUnknown(let recovery):
            "The Agent request outcome is unknown. Follow \(recovery.nextStep.rawValue); do not invent a new operation identity."
        case .frameTooLarge: "The local Agent bridge frame exceeded its size limit."
        case .alreadyRunning: "Another Scholium Agent bridge already owns this location."
        case .systemCall(let operation, let code):
            "The local Agent bridge could not \(operation) (errno \(code))."
        case .remote(let payload): payload.message
        }
    }

    public var agentCommandErrorCode: String {
        structuredCode.rawValue
    }

    private var structuredCode: LocalAgentBridgeErrorCode {
        switch self {
        case .remote(let payload): payload.code
        case .unavailable, .alreadyRunning, .systemCall: .unavailable
        case .invalidFrame, .invalidResponse, .frameTooLarge: .invalidFrame
        case .invalidRequest: .invalidRequest
        case .unsupportedVersion: .unsupportedVersion
        case .permissionDenied: .permissionDenied
        case .timeout: .timeout
        case .outcomeUnknown: .outcomeUnknown
        }
    }

    public var agentCommandRecovery: AgentOperationRecovery? {
        if case .remote(let payload) = self { return payload.recovery }
        if case .outcomeUnknown(let recovery) = self { return recovery }
        return LocalAgentBridgeErrorPayload.defaultRecovery(for: structuredCode)
    }
}

public enum LocalAgentBridgeLocation {
    public static let maximumFrameByteCount = 1024 * 1024
    public static let timeout: TimeInterval = 5
    public static let clientTimeout: TimeInterval = 6
    public static let cancellationGrace: TimeInterval = 1
    public static let host = "127.0.0.1"
    private static let firstPrivatePort: UInt16 = 49_152
    private static let privatePortCount: UInt64 = 16_384

    /// Derives one stable private-range loopback port from the existing bridge
    /// namespace. Production App and CLI resolve the same namespace; isolated
    /// tests can select independent ports without a machine-global registry.
    public static func port(applicationSupportURL: URL) -> UInt16 {
        let bytes = applicationSupportURL.standardizedFileURL.path.utf8
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return firstPrivatePort + UInt16(hash % privatePortCount)
    }
}

public final class LocalAgentBridgeClient: @unchecked Sendable {
    private let port: UInt16
    private let timeout: TimeInterval

    public init(
        applicationSupportURL: URL,
        timeout: TimeInterval = LocalAgentBridgeLocation.clientTimeout
    ) throws {
        port = LocalAgentBridgeLocation.port(
            applicationSupportURL: applicationSupportURL
        )
        self.timeout = min(max(timeout, 0.1), 30)
    }

    public func send(_ request: LocalAgentBridgeRequest) throws -> LocalAgentBridgeResponse {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LocalAgentBridgeError.systemCall("create its socket", errno)
        }
        defer { Darwin.close(descriptor) }
        try LocalAgentBridgeIO.configure(descriptor, timeout: timeout)
        let address = LocalAgentBridgeIO.address(port: port)
        let result = LocalAgentBridgeIO.withSockAddr(address) { pointer, length in
            Darwin.connect(descriptor, pointer, length)
        }
        guard result == 0 else {
            if [ECONNREFUSED, ETIMEDOUT].contains(errno) {
                throw LocalAgentBridgeError.unavailable
            }
            throw LocalAgentBridgeError.systemCall("connect", errno)
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
            throw LocalAgentBridgeError.outcomeUnknown(
                LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(for: request)
            )
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
    case analysisCreationPreflight(ResearchAgentAnalysisCreationPreflight)
    case started(
        receipt: ResearchAgentStartReceipt,
        credential: ResearchConnectionCredential
    )
    case credential(ResearchConnectionCredential)
    case sessionRevoked(ResearchAgentSessionRevocationReceipt)
    case context(ResearchAuthenticatedRunContext)
    case researchContext(ResearchContextResponse)
    case discussionReply(ResearchAgentDiscussionReplyReceipt)
    case discussionFinish(ResearchAgentDiscussionFinishReceipt)
    case writeSet(ResearchWriteSetExtensionResult)
    case documentWrite(ResearchDocumentWriteResult)
    case zoteroBindingWrite(ResearchZoteroBindingWriteResult)
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
    private let port: UInt16
    private let handler: Handler
    private let timeout: TimeInterval
    private let cancellationGrace: TimeInterval
    private let lock = NSLock()
    private var listener: Int32 = -1
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
        port = LocalAgentBridgeLocation.port(
            applicationSupportURL: applicationSupportURL
        )
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
        if listener >= 0 {
            Darwin.shutdown(listener, SHUT_RDWR)
        }
        let handlerTask = currentHandlerTask
        let handlerID = currentHandlerID
        let stopTask = Task.detached { [weak self] in
            handlerTask?.cancel()
            await handlerTask?.value
            if let handlerID {
                self?.clearCurrentHandler(id: handlerID)
            }
            if listener >= 0 {
                Darwin.close(listener)
            }
        }
        self.stopTask = stopTask
        lock.unlock()
        return stopTask
    }

    private func start() throws {
        listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw LocalAgentBridgeError.systemCall("create its listener", errno)
        }
        try LocalAgentBridgeIO.configure(
            listener,
            timeout: timeout
        )
        let address = LocalAgentBridgeIO.address(port: port)
        let bindResult = LocalAgentBridgeIO.withSockAddr(address) { pointer, length in
            Darwin.bind(listener, pointer, length)
        }
        guard bindResult == 0 else {
            if errno == EADDRINUSE {
                throw LocalAgentBridgeError.alreadyRunning
            }
            throw LocalAgentBridgeError.systemCall("bind", errno)
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
                throw LocalAgentBridgeError.outcomeUnknown(
                    LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(for: request)
                )
            }
            let outcome = try result.value?.get() ?? {
                throw LocalAgentBridgeError.invalidResponse
            }()
            let response: LocalAgentBridgeResponse = switch outcome {
            case .analysisCreationPreflight(let preflight):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    analysisCreationPreflight: preflight
                )
            case .started(let receipt, let credential):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    credential: credential,
                    startReceipt: receipt
                )
            case .credential(let credential):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    credential: credential
                )
            case .sessionRevoked(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    sessionRevocationReceipt: receipt
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
            case .discussionReply(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    discussionReplyReceipt: receipt
                )
            case .discussionFinish(let receipt):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    discussionFinishReceipt: receipt
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
            case .zoteroBindingWrite(let result):
                try LocalAgentBridgeResponse(
                    correlationID: request.correlationID,
                    zoteroBindingWriteResult: result
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
             ResearchAgentSessionError.pairingRejected:
            code = .permissionDenied
        case ResearchAgentSessionError.sessionRejected:
            code = .sessionExpired
        case ScholiumApplicationError.operationCommittedButRefreshFailed,
             ScholiumApplicationError.workspaceStillLoading:
            code = .staleProjection
        case ResearchAgentConnectionError.runStale,
             ResearchActionRunContractError.targetUnavailable,
             ResearchActionRunContractError.targetChanged,
             ResearchActionRunContractError.targetIdentityChanged,
             ResearchActionRunContractError.materialChanged:
            code = .staleRun
        case ResearchActionRunContractError.sourceAccessUnavailable(let failure):
            code = sourceAccessBridgeCode(for: failure.code)
        case ResearchAgentConnectionError.analysisPathOccupied,
             VaultRepositoryError.fileAlreadyExists,
             VaultRepositoryError.pathCollision:
            code = .pathOccupied
        case ResearchAgentConnectionError.analysisIdentityOccupied,
             DocumentCreationError.portableIdentityAlreadyExists:
            code = .identityOccupied
        case ResearchAgentConnectionError.analysisIdentitySourceMissingOrTrashed:
            code = .identitySourceMissingOrTrashed
        case ResearchAgentConnectionError.analysisSourceUnreadable:
            code = .sourceUnreadable
        case ResearchAgentConnectionError.newAnalysisReplayConflict,
             AgentAnalysisCreationReservationStoreError.reservationAlreadyExists,
             AgentAnalysisCreationReservationStoreError.reservationNotFound,
             AgentAnalysisCreationReservationStoreError.reservationMismatch:
            code = .replayConflict
        case LocalAgentBridgeError.timeout: code = .timeout
        case LocalAgentBridgeError.outcomeUnknown: code = .outcomeUnknown
        case LocalAgentBridgeError.unsupportedVersion(_): code = .unsupportedVersion
        case LocalAgentBridgeError.invalidFrame,
             LocalAgentBridgeError.frameTooLarge:
            code = .invalidFrame
        case LocalAgentBridgeError.invalidRequest,
             ResearchAgentConnectionError.invalidAnalysisCreationMetadata,
             DocumentCreationError.invalidMetadata,
             DocumentCreationError.invalidAuthoredYAML,
             DocumentCreationError.inapplicableAnalysisProperty,
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
        case .sessionExpired:
            "The Connection Session expired or was revoked. In Scholium, copy a new handoff for the unfinished Run, then pair again with the returned Run locator."
        case .staleProjection:
            "Authoritative state may already be committed, but the Workspace projection is stale. Do not create or write again; reload, then retry only the exact same idempotent request when instructed."
        case .staleRun:
            "The exact Target, Material, or formal source boundary changed. This Run is stale and authorizes no further submission or write. Inspect the current Note in Scholium and start a new Action from the current revision."
        case .missingSourceEvidence:
            "Analyze has no valid frozen source route. Provide a current Scholium source, a bound Zotero route, or explicitly start with source_route=researcher_provided."
        case .pathOccupied:
            "The resolved Analysis root filename is occupied. Scholium did not overwrite it or invent a retry filename. Ask the researcher for a distinct root filename and run preflight as a new creation request."
        case .identityOccupied:
            "The resolved path already belongs to a portable Analysis identity. Start the existing Note or ask the researcher for a distinct root filename."
        case .identitySourceMissingOrTrashed:
            "A portable Analysis identity remains but its source is missing or in the system Trash. Scholium did not recreate, overwrite, delete the identity, or invent another file."
        case .sourceUnreadable:
            "Scholium cannot verify the authoritative source state at the resolved Analysis destination. Restore access and rerun creation preflight."
        case .replayConflict:
            "The request identity belongs to different or terminal creation evidence. Scholium preserved current source, identity, relationship, Run, and recovery state and made no new change."
        case .timeout: "The bridge operation timed out."
        case .outcomeUnknown:
            "The Agent request outcome is unknown. Follow the attached operation-specific recovery.next_step without changing any required identity."
        case .operationFailed: "Scholium could not complete the bridge operation."
        }
        return LocalAgentBridgeErrorPayload(
            code: code,
            message: message,
            recovery: (error as? any AgentCommandErrorCodeProviding)?
                .agentCommandRecovery
        )
    }

    private static func sourceAccessBridgeCode(
        for failure: ResearchSourceAccessFailureCode
    ) -> LocalAgentBridgeErrorCode {
        switch failure {
        case .missingBinding, .sourceMissing, .zoteroAttachmentMissing:
            return .missingSourceEvidence
        case .sourceChanged:
            return .staleRun
        case .corruptBinding, .bookmarkUnavailable, .bookmarkStale,
             .sourceUnreadable, .sourceNotRegular, .sourceIsSymbolicLink,
             .zoteroUnavailable, .zoteroIdentityMismatch:
            return .sourceUnreadable
        }
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
        var reuseAddress: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout.size(ofValue: reuseAddress))
        ) == 0 else {
            throw LocalAgentBridgeError.systemCall("configure address reuse", errno)
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

    static func address(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(LocalAgentBridgeLocation.host))
        return address
    }

    static func withSockAddr<T>(
        _ address: sockaddr_in,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) rethrows -> T {
        var address = address
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
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
