import Foundation
import ScholiumContracts

@MainActor
extension AgentChatController {
    /// A demand-driven metadata read bound to the selected, visible, admitted turn.
    /// It grants no source-read, editor-flush or navigation authority.
    func handleCurrentStateObservation(_ request: ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse {
        var operation: (conversation: UUID, turn: String)?
        var operationIsCurrent: (@MainActor () -> Bool)?
        func record(_ status: AgentChatActivity.Status) {
            guard let operation else { return }
            recordActivity(
                .init(kind: .tool, status: status, source: .scholium),
                id: "bridge:\(request.requestID)", conversationID: operation.conversation, turnID: operation.turn)
            persist()
        }
        do {
            guard Set(request.arguments.keys) == ["triptych_id", "window_id", "conversation_id"],
                let requestedTriptych = request.arguments["triptych_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                let requestedWindow = request.arguments["window_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                let requestedConversation = request.arguments["conversation_id"]?.stringValue.flatMap(UUID.init(uuidString:))
            else { throw ScholiumMCPFailure.chatObservation(.invalidRequest) }
            guard !Task.isCancelled, isLoaded, connectionState == .ready,
                let token = request.conversationToken, let owner = executionID(for: token), selectedID == owner,
                let context = request.runtimeContext, context == runtimeContext(for: token),
                let connection = connectionID, let admission = executions[owner]?.admissionID,
                let scope = executions[owner]?.displayScope, displayWindow(owner) == scope,
                executions[owner]?.state == .working, conversation(owner)?.isAvailable == true
            else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
            guard requestedTriptych == triptychID, requestedConversation == owner, requestedWindow == scope.windowID else {
                throw ScholiumMCPFailure.chatObservation(.invalidRequest)
            }
            guard !context.threadID.isEmpty, context.threadID.utf8.count <= 512,
                !context.turnID.isEmpty, context.turnID.utf8.count <= 512
            else { throw ScholiumMCPFailure.chatObservation(.internalError) }
            let departureEpoch = selectionDepartureEpoch
            let admitted: @MainActor () -> Bool = { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled && self.connectionID == connection && self.connectionState == .ready
                    && self.selectedID == owner && self.selectionDepartureEpoch == departureEpoch
                    && self.executions[owner]?.state == .working && self.executions[owner]?.admissionID == admission
                    && self.runtimeContext(for: token) == context && self.conversation(owner)?.isAvailable == true
                    && self.executions[owner]?.displayScope == scope && self.displayWindow(owner) == scope
            }
            operation = (owner, context.turnID)
            operationIsCurrent = admitted
            record(.running)
            guard admitted() else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
            let document = try await observeCurrentState(scope, owner, admitted)
            guard admitted(), let current = conversation(owner), let execution = executions[owner] else {
                throw ScholiumMCPFailure.chatObservation(.workspaceNotReady)
            }
            guard let documentValue = document.jsonValue.objectValue,
                Set(documentValue.keys) == ["document_surface", "active_note"],
                (document.surface == .triptychNote) == (document.activeNote != nil),
                document.errorCodes.allSatisfy({ $0 == "document_save" || $0 == "document_conflict" })
            else { throw ScholiumMCPFailure.chatObservation(.internalError) }
            var errors = document.errorCodes
            if connectionError != nil { errors.append("connection") }
            if localHistoryError != nil { errors.append("history_load") }
            if historySaveError != nil { errors.append("history_save") }
            if materialCleanupError != nil { errors.append("material_cleanup") }
            if execution.error != nil {
                switch execution.recovery {
                case .historyRefreshFailed: errors.append("history_refresh")
                case .queuedInputBlocked: errors.append("queued_input")
                default: errors.append("execution")
                }
            }
            if materialErrors[owner] != nil { errors.append("execution") }
            var result = documentValue
            result["schema_version"] = .integer(ScholiumMCPContract.currentToolSchemaVersion)
            result["status"] = .string("ok")
            result["triptych_id"] = .string(triptychID.uuidString.lowercased())
            result["window_id"] = .string(scope.windowID.uuidString.lowercased())
            result["conversation_id"] = .string(owner.uuidString.lowercased())
            result["observed_at"] = .string(ISO8601DateFormatter().string(from: Date()))
            result["chat"] = .object([
                "thread_id": .string(context.threadID), "turn_id": .string(context.turnID), "state": .string("working"),
                "pending_delivery": .bool(current.pendingMessageID != nil), "queued_message_count": .integer(current.queuedMessages.count),
                "approval_count": .integer(approvalCount(in: owner)), "question_count": .integer(questionCount(in: owner)),
                "errors": .array(Set(errors).sorted().map(MCPJSONValue.string)),
            ])
            let value = MCPJSONValue.object(result)
            guard try JSONEncoder().encode(value).count <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount else {
                throw ScholiumMCPFailure.chatObservation(.internalError)
            }
            record(.completed)
            guard admitted() else { throw ScholiumMCPFailure.chatObservation(.workspaceNotReady) }
            return try .init(requestID: request.requestID, result: value)
        } catch {
            record(Task.isCancelled || operationIsCurrent?() == false ? .interrupted : .failed)
            let code = (error as? ScholiumMCPFailure)?.code ?? (error is CancellationError ? .workspaceNotReady : .internalError)
            return try! .init(requestID: request.requestID, error: .chatObservation(code))
        }
    }
}
