import Foundation
import ScholiumContracts
import ScholiumCore

public enum AgentNoteChangeOperationError: LocalizedError, Hashable, Sendable {
    case crossTriptych
    case parentRunNotFound(UUID)
    case parentRunMismatch(UUID)
    case redundantRequest(UUID)

    public var errorDescription: String? {
        switch self {
        case .crossTriptych:
            "The Agent Note Change request belongs to another Triptych."
        case .parentRunNotFound(let id):
            "Parent run \(id.uuidString.lowercased()) is not a current local Action run."
        case .parentRunMismatch(let id):
            "Parent run \(id.uuidString.lowercased()) does not match the request's frozen Action revision."
        case .redundantRequest(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) does not expand the parent run's bounded scope."
        }
    }
}

extension WorkspaceHandle {
    func submitAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        if let existing = try await services.agentNoteChangeRequestStore
            .recordIfPresent(id: request.id, now: receivedAt) {
            guard existing.request == request else {
                throw AgentNoteChangeRequestStoreError
                    .duplicateRequestPayload(request.id)
            }
            return try await currentAgentNoteChangeRequest(
                id: request.id,
                now: receivedAt
            )
        }
        try await authenticateParent(of: request)
        guard request.triptychID == services.manifest.id else {
            throw AgentNoteChangeOperationError.crossTriptych
        }
        guard try await requestExpandsParentScope(request) else {
            throw AgentNoteChangeOperationError.redundantRequest(request.id)
        }
        let isCurrent = try await isCurrentAgentNoteChangeRequest(request)
        return try await services.agentNoteChangeRequestStore.submitValidated(
            request,
            isCurrent: isCurrent,
            receivedAt: receivedAt,
            validFor: validFor
        )
    }

    func agentNoteChangeRequest(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        return try await currentAgentNoteChangeRequest(id: id, now: now)
    }

    private func currentAgentNoteChangeRequest(
        id: UUID,
        now: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        var record = try await services.agentNoteChangeRequestStore.record(
            id: id,
            now: now
        )
        if record.isUnresolved,
           !(try await isCurrentAgentNoteChangeRequest(record.request)) {
            record = try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: now
            )
        }
        return record
    }

    func pendingAgentNoteChangeRequests(
        now: Date = Date()
    ) async throws -> [AgentNoteChangeRequestRecord] {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let pending = try await services.agentNoteChangeRequestStore.pending(now: now)
        var current: [AgentNoteChangeRequestRecord] = []
        for record in pending {
            if try await isCurrentAgentNoteChangeRequest(record.request) {
                current.append(record)
            } else {
                _ = try await services.agentNoteChangeRequestStore.resolve(
                    id: record.id,
                    state: .stale,
                    decidedAt: now
                )
            }
        }
        return current
    }

    private func authenticateParent(
        of request: AgentNoteChangeRequest
    ) async throws {
        guard request.triptychID == services.manifest.id else {
            throw AgentNoteChangeOperationError.crossTriptych
        }
        guard let record = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID) else {
            throw AgentNoteChangeOperationError
                .parentRunNotFound(request.parentRunID)
        }
        guard record.triptychID == services.manifest.id,
              let actionSnapshot = record.snapshot.actionSnapshot,
              actionSnapshot.actionID == request.parentAction.definition.id,
              try AgentNoteChangeActionRevision(actionSnapshot: actionSnapshot)
                == request.parentAction else {
            throw AgentNoteChangeOperationError
                .parentRunMismatch(request.parentRunID)
        }
    }

    private func requestExpandsParentScope(
        _ request: AgentNoteChangeRequest
    ) async throws -> Bool {
        guard let record = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID),
              let parent = record.snapshot.actionSnapshot else {
            throw AgentNoteChangeOperationError
                .parentRunNotFound(request.parentRunID)
        }
        let alreadyWritable = Set(parent.authority.writableNotes.map(\.noteID))
        let alreadyAllowedOperations = Set(parent.authority.writeOperations)
        return request.targets.contains {
            !alreadyWritable.contains($0.noteID)
        } || !Set(request.operations).isSubset(of: alreadyAllowedOperations)
            || request.requestedAction.definition != parent.definition
    }

    private func isCurrentAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest
    ) async throws -> Bool {
        do {
            try await authenticateParent(of: request)
        } catch is AgentNoteChangeOperationError {
            return false
        }
        guard let parent = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID),
              Self.parentPermitsChangeRequest(parent) else {
            return false
        }
        var currentTargets: [ResearchActionNoteSnapshot] = []
        var resolvedAction: ResearchActionAvailability?
        for target in request.targets {
            guard let currentTarget = try await currentAgentChangeTarget(
                target
            ) else {
                return false
            }
            currentTargets.append(currentTarget)
            let availability = try await researchActionAvailability(
                for: currentTarget
            )
            guard let action = availability.first(where: {
                $0.id == request.requestedAction.definition.id
            }), action.isEnabled,
            action.definition == request.requestedAction.definition,
            action.profile.origin == request.requestedAction.profileOrigin,
            action.profile.profileRevision
                == request.requestedAction.profileRevision,
            action.profile.profileDocumentRevision
                == request.requestedAction.profileDocumentRevision,
            action.profile.profile.capabilities.candidateWritableRoles
                .contains(currentTarget.role),
            Set(request.operations).isSubset(of: Set(
                action.profile.profile.capabilities.candidateWriteOperations
            )) else {
                return false
            }
            if let resolvedAction, resolvedAction != action {
                return false
            }
            resolvedAction = action
        }
        guard let action = resolvedAction,
              let first = currentTargets.first else { return false }

        let function = try ResearchActionFunctionMapping.function(
            for: action.definition,
            targetRole: first.role
        )
        let method: ResearchSkillBindingResolution
        switch action.profile.origin {
        case .applicationDefault:
            method = try await services.researchSkillStore
                .functionBindingResolution(
                    for: function,
                    actionID: action.id
                )
        case .researcher:
            method = try await services.researchSkillStore
                .profileActionBindingResolution(
                    for: function,
                    actionID: action.id
                )
        }
        guard method.issue == nil,
              let package = method.package,
              package.id == request.requestedAction.packageID,
              package.revision == request.requestedAction.skillRevision else {
            return false
        }

        return true
    }

    private func currentAgentChangeTarget(
        _ target: AgentNoteChangeTarget
    ) async throws -> ResearchActionNoteSnapshot? {
        guard let snapshot = currentSnapshot.document(id: target.note),
                  snapshot.lifecycle == .active,
                  snapshot.stableIdentity.resolvedID == target.noteID,
                  snapshot.fingerprint == target.expectedFingerprint,
                  Self.actionRole(
                    for: try vault(id: target.note.vaultID).role
                  ) == target.role,
                  let identity = try await services.controlStore.identityRecord(
                    vaultID: target.note.vaultID,
                    relativePath: target.note.relativePath
                  ),
                  identity.id == target.noteID else {
            return nil
        }
        let document = try await repository(vaultID: target.note.vaultID)
            .load(relativePath: target.note.relativePath)
        guard document.fingerprint == target.expectedFingerprint else {
            return nil
        }
        return ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            lifecycle: snapshot.lifecycle,
            fingerprint: target.expectedFingerprint,
            title: ResearchNoteTitleResolver.resolve(
                document: snapshot.document,
                vaultRole: snapshot.vaultRole
            ).title
        )
    }

    /// A normal completion may be the provenance for a separately authorized
    /// continuation. Cancellation or stale/incomplete completion evidence may
    /// not keep or revive an unresolved change request.
    private static func parentPermitsChangeRequest(
        _ record: LocalResearchExecutionRecord
    ) -> Bool {
        guard let completion = record.completion else { return true }
        return completion.state == .complete
    }

    private static func actionRole(
        for vaultRole: VaultRole
    ) -> ResearchActionTargetRole? {
        switch vaultRole {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topic
        case .draftProject: .work
        case .other: nil
        }
    }
}

extension ResearchOperations {
    public func submitAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().submitAgentNoteChangeRequest(
            request,
            receivedAt: receivedAt,
            validFor: validFor
        )
    }

    public func agentNoteChangeRequest(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().agentNoteChangeRequest(id: id, now: now)
    }

    public func pendingAgentNoteChangeRequests(
        now: Date = Date()
    ) async throws -> [AgentNoteChangeRequestRecord] {
        try await reference.requireHandle().pendingAgentNoteChangeRequests(now: now)
    }
}
