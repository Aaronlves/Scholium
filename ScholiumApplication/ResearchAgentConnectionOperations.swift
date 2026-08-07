import Darwin
import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceRuntime {
    public func researchAgentWorkspaceID(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        allowFinalized: Bool = false
    ) async throws -> UUID {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        return try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: allowFinalized
        ).triptychID
    }

    public func pairResearchAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval = 8 * 60 * 60
    ) async throws -> ResearchConnectionCredential {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let credential = try await sessions.exchange(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        do {
            let handle = try await openWorkspace(id: authenticated.triptychID)
            try await handle.validateActiveResearchAgentRun(authenticated.runID)
            return credential
        } catch {
            await sessions.revokeSession(credential.sessionID)
            throw error
        }
    }

    public func researchAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.authenticatedResearchAgentContext(
            credential: credential,
            run: run
        )
    }

    public func queryResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest
    ) async throws -> ResearchContextResponse {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.authenticatedResearchContext(
            credential: credential,
            run: run,
            request: request
        )
    }

    public func endResearchAgentRun(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchRunEndReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.endResearchAgentRun(
            credential: credential,
            run: run
        )
    }
}

extension ResearchOperations {
    public func issueAgentHandoff(
        runID: UUID,
        validity: TimeInterval = 10 * 60
    ) async throws -> ResearchAgentHandoff {
        let handle = try await reference.requireHandle()
        return try await handle.issueResearchAgentHandoff(
            runID: runID,
            validity: validity
        )
    }

    public func pairAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval = 8 * 60 * 60
    ) async throws -> ResearchConnectionCredential {
        let handle = try await reference.requireHandle()
        return try await handle.pairResearchAgent(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
    }

    public func authenticatedAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        let handle = try await reference.requireHandle()
        return try await handle.authenticatedResearchAgentContext(
            credential: credential,
            run: run
        )
    }

    public func queryAgentResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest
    ) async throws -> ResearchContextResponse {
        let handle = try await reference.requireHandle()
        return try await handle.authenticatedResearchContext(
            credential: credential,
            run: run,
            request: request
        )
    }

    public func revokeAgentSession(_ sessionID: UUID) async throws {
        let handle = try await reference.requireHandle()
        guard let sessions = handle.services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        await sessions.revokeSession(sessionID)
    }
}

extension WorkspaceHandle {
    func validateActiveResearchAgentRun(_ runID: UUID) async throws {
        try requireActive()
        if let record = try await services.localResearchExecutionStore
            .recordIfPresent(id: runID) {
            _ = try activeAction(in: record)
            return
        }
        let improvement = try await services.localResearchExecutionStore
            .methodImprovement(id: runID)
        guard improvement.state == .prepared || improvement.state == .writing else {
            throw ResearchAgentConnectionError.runUnavailable
        }
    }

    func issueResearchAgentHandoff(
        runID: UUID,
        validity: TimeInterval
    ) async throws -> ResearchAgentHandoff {
        try requireActive()
        let record = try await services.localResearchExecutionStore.record(id: runID)
        let action = try activeAction(in: record)
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        return try await sessions.issuePairing(
            runID: runID,
            triptychID: services.manifest.id,
            canWrite: !action.authority.writableNotes.isEmpty,
            validity: validity
        )
    }

    func pairResearchAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval
    ) async throws -> ResearchConnectionCredential {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let credential = try await sessions.exchange(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == services.manifest.id else {
            await sessions.revokeSession(credential.sessionID)
            throw ResearchAgentSessionError.sessionRejected
        }
        try await validateActiveResearchAgentRun(authenticated.runID)
        return credential
    }

    func authenticatedResearchAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let coreProtocol = try BundledResearchSkillResources.coreProtocol()
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false
        )
        guard authenticated.triptychID == services.manifest.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let record = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        let action: ResearchActionSnapshot
        do {
            action = try activeAction(in: record)
        } catch {
            await sessions.revokeRun(authenticated.runID)
            throw error
        }
        guard action.target.noteID == record.snapshot.request.target.noteID else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        let platform = try requiredPlatformAction(action.actionID)
        let purpose: String? = if case .freeText(let text)? =
            action.academicInputs.values["research-request"] { text } else { nil }
        return ResearchAuthenticatedRunContext(
            coreProtocol: authenticated.shouldDeliverCoreProtocol
                ? coreProtocol
                : nil,
            brief: ResearchRunBrief(
                run: run,
                actionID: action.actionID,
                initialObjectTitle: action.target.title,
                initialObjectRole: action.target.role,
                academicPurpose: purpose,
                capabilities: Self.capabilities(platform)
            ),
            method: ResearchMethodContext(snapshot: action.method),
            resultContract: action.resultContract,
            boundedWriteSet: record.boundedWriteSet.entries.map(
                ResearchBoundedWriteSetViewEntry.init
            ),
            continuationHandoff: record.snapshot.continuationHandoff
        )
    }

    func authenticatedResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest,
        provider: any ResearchContextProviding = FoundationResearchContextProvider()
    ) async throws -> ResearchContextResponse {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == services.manifest.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let record = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        let action = try activeAction(in: record)
        let platform = try requiredPlatformAction(action.actionID)
        try Self.validateResearchContextCapability(
            request,
            platform: platform
        )
        let query = try ResearchContextQuery(
            request: request,
            runID: authenticated.runID,
            triptychID: authenticated.triptychID
        )
        let snapshot = currentSnapshot
        let response = try await provider.response(
            for: query,
            action: action,
            workspace: snapshot,
            access: ResearchContextOwnerAccess(
                search: { [weak self] request in
                    guard let self else {
                        throw ResearchAgentConnectionError.runUnavailable
                    }
                    return try await self.search(request)
                },
                loadDocument: { [weak self] note in
                    guard let self else {
                        throw ResearchAgentConnectionError.runUnavailable
                    }
                    return try await self.loadDocument(note)
                }
            )
        )
        return response
    }

    func endResearchAgentRun(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchRunEndReceipt {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == services.manifest.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        if let improvement = try? await services.localResearchExecutionStore
            .methodImprovement(id: authenticated.runID) {
            let recoveryRetained = improvement.state == .writing
            await sessions.revokeRun(authenticated.runID)
            return try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: recoveryRetained,
                message: recoveryRetained
                    ? "The Method improvement Run ended. Its in-progress exact-revision outcome remains recorded for recovery; no new Agent operation is authorized."
                    : "The Method improvement Run ended and no new Agent operation is authorized."
            )
        }
        let record = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        if let completion = record.completion,
           [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            await sessions.revokeRun(authenticated.runID)
            return try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: false,
                message: "The completed Run's local Session access ended; its Result, Record, confirmed changes, conflicts, and recovery evidence remain unchanged."
            )
        }
        _ = try activeAction(in: record)
        let recoveryRetained = record.documentWriteRecords.contains {
            $0.state == .writing || $0.state == .recoveryRequired
        } || record.boundedWriteSet.entries.contains {
            $0.state == .writing || $0.state == .recoveryRequired
        }
        try await researchFunctionCoordinator.cancelAction(
            runID: authenticated.runID,
            host: self
        )
        return try ResearchRunEndReceipt(
            run: run,
            recoveryRetained: recoveryRetained,
            message: recoveryRetained
                ? "The Run ended and refuses new Agent operations. Confirmed changes, conflicts, and unresolved recovery duties remain in Scholium."
                : "The Run ended and refuses new Agent operations. Confirmed changes and conflicts remain in Scholium."
        )
    }

    private func activeAction(
        in record: LocalResearchExecutionRecord
    ) throws -> ResearchActionSnapshot {
        guard record.triptychID == services.manifest.id,
              let action = record.snapshot.actionSnapshot else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        if let completion = record.completion,
           [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return action
    }

    private func requiredPlatformAction(
        _ actionID: ResearchActionID
    ) throws -> PlatformActionDefinition {
        guard let definition = PlatformActionCatalog.definition(for: actionID) else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return definition
    }

    private static func capabilities(
        _ definition: PlatformActionDefinition
    ) -> ResearchRunCapabilityAvailability {
        let operations = Set(definition.operations)
        return ResearchRunCapabilityAvailability(
            search: operations.contains(.search),
            read: operations.contains(.read),
            relations: operations.contains(.inspectRelations),
            properties: operations.contains(.inspectProperties),
            records: operations.contains(.queryRecords),
            researchState: operations.contains(.queryRecords),
            zotero: operations.contains(.useZotero),
            writeInitialObject: operations.contains(.modifyInitialNote),
            extendWriteSet: operations.contains(.extendWriteSet),
            continueResearch: operations.contains(.continueResearch)
        )
    }

    private static func validateResearchContextCapability(
        _ request: ResearchContextRequest,
        platform: PlatformActionDefinition
    ) throws {
        let operations = Set(platform.operations)
        for clause in request.clauses {
            let permitted = switch clause.kind {
            case .discoverNote: operations.contains(.search)
            case .readNote: operations.contains(.read)
            case .inspectRelations: operations.contains(.inspectRelations)
            case .inspectProperties: operations.contains(.inspectProperties)
            case .inspectRecords, .inspectResearcherState:
                operations.contains(.queryRecords)
            }
            guard permitted else {
                throw ResearchAgentConnectionError.capabilityUnavailable
            }
        }
    }

}

public enum ResearchAgentConnectionError: LocalizedError, Hashable, Sendable {
    case secureRandomUnavailable
    case runUnavailable
    case capabilityUnavailable

    public var errorDescription: String? {
        switch self {
        case .secureRandomUnavailable:
            "Scholium could not initialize its cryptographic local-session boundary; no handoff was issued."
        case .runUnavailable:
            "The Research Run is unavailable, ended, or no longer matches its frozen Action."
        case .capabilityUnavailable:
            "This Research Context channel is not available for the frozen Action."
        }
    }
}
