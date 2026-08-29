import Foundation
import ScholiumApplication

/// Translates the loopback wire operation into one Application runtime call.
/// The server owns transport lifetime; WorkspaceStore owns the process runtime
/// and supplies only its cross-window flush boundary.
@MainActor
final class LocalAgentBridgeRequestRouter {
    typealias EditorFlusher = @MainActor @Sendable (UUID) async throws -> Void

    private let runtime: WorkspaceRuntime
    private let researchAgentPermissionClaims: ResearchAgentPermissionClaimCoordinator
    private let flushEditors: EditorFlusher

    init(
        runtime: WorkspaceRuntime,
        researchAgentPermissionClaims: ResearchAgentPermissionClaimCoordinator,
        flushEditors: @escaping EditorFlusher
    ) {
        self.runtime = runtime
        self.researchAgentPermissionClaims = researchAgentPermissionClaims
        self.flushEditors = flushEditors
    }

    func handle(_ request: LocalAgentBridgeRequest) async throws
        -> LocalAgentBridgeHandlerResult
    {
        try Task.checkCancellation()
        switch request.operation {
        case .preflightAnalysisCreation:
            guard let triptychID = request.triptychID,
                  let preflightRequest = request.analysisCreationPreflightRequest else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .analysisCreationPreflight(
                try await runtime.preflightResearchAgentAnalysisCreation(
                    triptychID: triptychID,
                    request: preflightRequest
                )
            )
        case .start:
            guard let triptychID = request.triptychID,
                  let startRequest = request.startRequest else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let started = try await runtime.startResearchAgentRun(
                triptychID: triptychID,
                request: startRequest
            )
            return .started(receipt: started.receipt, credential: started.credential)
        case .pair:
            guard let run = request.run,
                  let pairingCode = request.pairingCode else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .credential(try await runtime.pairResearchAgent(
                run: run,
                pairingCode: pairingCode
            ))
        case .revokeSession:
            guard let credential = request.credential else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .sessionRevoked(
                try await runtime.revokeResearchAgentSession(credential: credential)
            )
        case .context:
            guard let run = request.run,
                  let credential = request.credential else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let context = try await runtime.researchAgentInitialContext(
                credential: credential,
                run: run
            )
            return context.fold(
                action: LocalAgentBridgeHandlerResult.context,
                methodImprovement:
                    LocalAgentBridgeHandlerResult.methodImprovementContext
            )
        case .query:
            guard let run = request.run,
                  let credential = request.credential,
                  let contextRequest = request.contextRequest else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .researchContext(try await runtime.queryResearchContext(
                credential: credential,
                run: run,
                request: contextRequest
            ))
        case .discussionReply:
            guard let run = request.run,
                  let credential = request.credential,
                  let reply = request.discussionReplyRequest else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run
            )
            try await flushEditors(triptychID)
            return .discussionReply(
                try await runtime.replyToResearchAgentDiscussion(
                    credential: credential,
                    run: run,
                    request: reply
                )
            )
        case .extendWriteSet:
            guard let run = request.run,
                  let credential = request.credential,
                  let intent = request.writeSetIntent else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run
            )
            try await flushEditors(triptychID)
            let delivery = try await runtime.extendResearchWriteSet(
                credential: credential,
                run: run,
                intent: intent
            )
            if let record = delivery.record, record.isUnresolved {
                researchAgentPermissionClaims.receive(
                    .writeSetExtension(record),
                    intent: .submit
                )
            }
            return .writeSet(delivery.result)
        case .writeDocument:
            guard let run = request.run,
                  let credential = request.credential,
                  let intent = request.documentWriteIntent else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .documentWrite(try await runtime.writeResearchDocument(
                credential: credential,
                run: run,
                intent: intent
            ))
        case .writeZoteroBinding:
            guard let run = request.run,
                  let credential = request.credential,
                  let intent = request.zoteroBindingWriteIntent else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .zoteroBindingWrite(
                try await runtime.writeResearchZoteroBinding(
                    credential: credential,
                    run: run,
                    intent: intent
                )
            )
        case .resolveWriteConflict:
            guard let run = request.run,
                  let credential = request.credential,
                  let intent = request.conflictResolutionIntent else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run
            )
            try await flushEditors(triptychID)
            return .conflictResolution(
                try await runtime.resolveResearchWriteConflict(
                    credential: credential,
                    run: run,
                    intent: intent
                )
            )
        case .submitResult:
            guard let run = request.run,
                  let credential = request.credential,
                  let submission = request.resultSubmission else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run,
                allowFinalized: true
            )
            try await flushEditors(triptychID)
            return .resultReceipt(try await runtime.submitResearchAgentResult(
                credential: credential,
                run: run,
                submission: submission
            ))
        case .continueResearch:
            guard let run = request.run,
                  let credential = request.credential,
                  let continuation = request.continuationRequest else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run,
                allowFinalized: true
            )
            try await flushEditors(triptychID)
            let result = try await runtime.continueResearch(
                credential: credential,
                run: run,
                request: continuation
            )
            if result.state == .pendingResearcherDecision {
                let decision = try await runtime.researchContinuationRequest(
                    credential: credential,
                    run: run,
                    request: continuation
                )
                researchAgentPermissionClaims.receive(
                    .continuation(decision),
                    intent: .submit
                )
            }
            return .continuation(result)
        case .methodImprovementContext:
            guard let run = request.run,
                  let credential = request.credential else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .methodImprovementContext(
                try await runtime.researchMethodImprovementContext(
                    credential: credential,
                    run: run
                )
            )
        case .submitMethodImprovement:
            guard let run = request.run,
                  let credential = request.credential,
                  let submission = request.methodImprovementSubmission else {
                throw LocalAgentBridgeError.invalidRequest
            }
            let triptychID = try await runtime.researchAgentWorkspaceID(
                credential: credential,
                run: run,
                allowFinalized: true
            )
            try await flushEditors(triptychID)
            return .methodImprovementReceipt(
                try await runtime.submitResearchMethodImprovement(
                    credential: credential,
                    run: run,
                    submission: submission
                )
            )
        case .end:
            guard let run = request.run,
                  let credential = request.credential else {
                throw LocalAgentBridgeError.invalidRequest
            }
            return .endReceipt(try await runtime.endResearchAgentRun(
                credential: credential,
                run: run
            ))
        }
    }
}
