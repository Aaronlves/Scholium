import Foundation
import ScholiumContracts

/// CLI-facing client for the authenticated App-owned local bridge. It owns no
/// Run, Session, Search, write-set, or research state of its own.
public actor AgentBridgeOperations: AgentBridgeUseCases {
    private let client: LocalAgentBridgeClient

    public init(applicationSupportURL: URL) throws {
        client = try LocalAgentBridgeClient(
            applicationSupportURL: applicationSupportURL
        )
    }

    public func pair(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode
    ) throws -> ResearchConnectionCredential {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .pair,
            run: run,
            pairingCode: pairingCode
        ))
        guard let credential = response.credential else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return credential
    }

    public func context(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) throws -> ResearchAuthenticatedRunContext {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .context,
            run: run,
            credential: credential
        ))
        guard let context = response.context else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return context
    }

    public func query(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        request: ResearchContextRequest
    ) throws -> ResearchContextResponse {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .query,
            run: run,
            credential: credential,
            contextRequest: request
        ))
        guard let context = response.researchContext else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return context
    }

    public func extendWriteSet(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchWriteSetExtensionIntent
    ) throws -> ResearchWriteSetExtensionResult {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .extendWriteSet,
            run: run,
            credential: credential,
            writeSetIntent: intent
        ))
        guard let result = response.writeSetResult else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return result
    }

    public func writeDocument(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchDocumentWriteIntent
    ) throws -> ResearchDocumentWriteResult {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .writeDocument,
            run: run,
            credential: credential,
            documentWriteIntent: intent
        ))
        guard let result = response.documentWriteResult else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return result
    }

    public func resolveWriteConflict(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchWriteConflictResolutionIntent
    ) throws -> ResearchWriteConflictResolutionResult {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .resolveWriteConflict,
            run: run,
            credential: credential,
            conflictResolutionIntent: intent
        ))
        guard let result = response.conflictResolutionResult else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return result
    }

    public func submitResult(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        submission: ResearchAgentResultSubmission
    ) throws -> ResearchAgentResultReceipt {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .submitResult,
            run: run,
            credential: credential,
            resultSubmission: submission
        ))
        guard let receipt = response.resultReceipt else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return receipt
    }

    public func continueResearch(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        request: ResearchContinuationRequest
    ) throws -> ResearchContinuationResult {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .continueResearch,
            run: run,
            credential: credential,
            continuationRequest: request
        ))
        guard let result = response.continuationResult else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return result
    }

    public func methodImprovementContext(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) throws -> ResearchMethodImprovementContext {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .methodImprovementContext,
            run: run,
            credential: credential
        ))
        guard let context = response.methodImprovementContext else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return context
    }

    public func submitMethodImprovement(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        submission: ResearchMethodImprovementSubmission
    ) throws -> ResearchMethodImprovementReceipt {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .submitMethodImprovement,
            run: run,
            credential: credential,
            methodImprovementSubmission: submission
        ))
        guard let receipt = response.methodImprovementReceipt else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return receipt
    }

    public func end(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) throws -> ResearchRunEndReceipt {
        let response = try client.send(try LocalAgentBridgeRequest(
            operation: .end,
            run: run,
            credential: credential
        ))
        guard let receipt = response.endReceipt else {
            throw LocalAgentBridgeError.invalidResponse
        }
        return receipt
    }
}
