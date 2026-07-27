import Foundation
import ScholiumContracts
import ScholiumCore

public enum AgentNoteChangeOperationError: LocalizedError, Hashable, Sendable {
    case crossTriptych
    case parentRunNotFound(UUID)
    case parentRunMismatch(UUID)
    case redundantRequest(UUID)
    case invalidCoordinationKey
    case expiredCoordinationKey
    case coordinationRequestAlreadyBound(UUID)

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
        case .invalidCoordinationKey:
            "The Agent coordination key is invalid."
        case .expiredCoordinationKey:
            "The Agent coordination key has expired."
        case .coordinationRequestAlreadyBound(let id):
            "The Agent coordination key is already bound to request \(id.uuidString.lowercased())."
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
        let record = try await submitAgentNoteChangeRequestWithinCoordination(
            request,
            receivedAt: receivedAt,
            validFor: validFor
        )
        return try await applyingStandingPermissionIfPossible(
            to: record,
            decidedAt: receivedAt
        )
    }

    func applyStandingPermissionToAgentNoteChangeRequest(
        id: UUID,
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let record = try await currentAgentNoteChangeRequest(
            id: id,
            now: decidedAt
        )
        return try await applyingStandingPermissionIfPossible(
            to: record,
            decidedAt: decidedAt
        )
    }

    private func submitAgentNoteChangeRequestWithinCoordination(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date,
        validFor: TimeInterval,
        beforeFirstSubmission: (() async throws -> Void)? = nil
    ) async throws -> AgentNoteChangeRequestRecord {
        if let existing = try await services.agentNoteChangeRequestStore
            .recordIfPresent(id: request.id, now: receivedAt) {
            guard existing.request == request else {
                throw AgentNoteChangeRequestStoreError
                    .duplicateRequestPayload(request.id)
            }
            try await beforeFirstSubmission?()
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
        try await beforeFirstSubmission?()
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

    func submitAgentNoteChangeRequestFromBridge(
        _ request: AgentNoteChangeRequest,
        coordinationKey: String,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let execution = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: request.parentRunID,
            requestID: request.id,
            permitsUnboundRequest: true,
            at: receivedAt
        )
        try Task.checkCancellation()
        let grant = try requireCoordinationGrant(execution)
        let record = try await submitAgentNoteChangeRequestWithinCoordination(
            request,
            receivedAt: receivedAt,
            validFor: validFor,
            beforeFirstSubmission: {
                try Task.checkCancellation()
                _ = try await self.services.localResearchExecutionStore
                    .bindAgentCoordinationRequest(
                        runID: request.parentRunID,
                        expectedGrant: grant,
                        requestID: request.id
                    )
            }
        )
        return record
    }

    func resolveAgentNoteChangeRequest(
        id: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        guard state == .allowedSubset
                || state == .continueWithoutChanges
                || state == .cancelled else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }

        let current: AgentNoteChangeRequestRecord
        if state == .cancelled {
            current = try await currentAgentNoteChangeRequestForCancellation(
                id: id,
                now: decidedAt
            )
        } else {
            current = try await currentAgentNoteChangeRequest(id: id, now: decidedAt)
        }
        guard current.isUnresolved else { return current }
        _ = try await evaluateStandingPermission(for: current.request)
        let parentBeforeDecision = try await services.localResearchExecutionStore
            .record(id: current.request.parentRunID)
        let permitsCancelledParent = state == .cancelled
            && parentBeforeDecision.completion?.state == .cancelled
        guard try await isCurrentAgentNoteChangeRequest(
            current.request,
            permittingCancelledParent: permitsCancelledParent
        ) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: decidedAt
            )
        }

        if state == .cancelled {
            let parent = try await services.localResearchExecutionStore.record(
                id: current.request.parentRunID
            )
            if parent.completion == nil {
                try await cancelResearchFunction(runID: current.request.parentRunID)
            }
        }
        return try await services.agentNoteChangeRequestStore.resolve(
            id: id,
            state: state,
            allowedNoteIDs: allowedNoteIDs,
            decidedAt: decidedAt
        )
    }

    /// Recovers the researcher-authored Cancel the Run decision if the parent
    /// cancellation committed but the request-store transition was interrupted.
    /// Other decisions continue to treat a cancelled parent as stale.
    private func currentAgentNoteChangeRequestForCancellation(
        id: UUID,
        now: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        var record = try await services.agentNoteChangeRequestStore.record(
            id: id,
            now: now
        )
        guard record.isUnresolved else { return record }
        let parent = try await services.localResearchExecutionStore.record(
            id: record.request.parentRunID
        )
        let isRecoveringCommittedCancellation = parent.completion?.state == .cancelled
        if !(try await isCurrentAgentNoteChangeRequest(
            record.request,
            permittingCancelledParent: isRecoveringCommittedCancellation
        )) {
            record = try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: now
            )
        }
        return record
    }

    private func applyingStandingPermissionIfPossible(
        to record: AgentNoteChangeRequestRecord,
        decidedAt: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        guard record.isUnresolved else { return record }
        let initialEvaluation = try await evaluateStandingPermission(
            for: record.request
        )
        guard initialEvaluation.disposition == .mayIssueBoundedGrant else {
            return record
        }
        guard try await isCurrentAgentNoteChangeRequest(record.request) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: record.id,
                state: .stale,
                decidedAt: max(decidedAt, record.receivedAt)
            )
        }
        let finalEvaluation = try await evaluateStandingPermission(
            for: record.request
        )
        guard finalEvaluation == initialEvaluation,
              finalEvaluation.disposition == .mayIssueBoundedGrant else {
            return record
        }
        guard try await isCurrentAgentNoteChangeRequest(record.request) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: record.id,
                state: .stale,
                decidedAt: max(decidedAt, record.receivedAt)
            )
        }
        return try await services.agentNoteChangeRequestStore.resolve(
            id: record.id,
            state: .allowedSubset,
            allowedNoteIDs: record.request.targets.map(\.noteID),
            decidedAt: max(decidedAt, record.receivedAt)
        )
    }

    func agentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let stored = try await services.agentNoteChangeRequestStore
            .recordForAuthentication(id: id)
        _ = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: stored.request.parentRunID,
            requestID: id,
            permitsUnboundRequest: false,
            at: now
        )
        try Task.checkCancellation()
        return try await currentAgentNoteChangeRequest(id: id, now: now)
    }

    func cancelAgentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let stored = try await services.agentNoteChangeRequestStore
            .recordForAuthentication(id: id)
        _ = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: stored.request.parentRunID,
            requestID: id,
            permitsUnboundRequest: false,
            at: now
        )
        try Task.checkCancellation()
        guard stored.isUnresolved else { return stored }
        return try await services.agentNoteChangeRequestStore.resolve(
            id: id,
            state: .cancelled,
            decidedAt: now
        )
    }

    private func authenticateCoordinationKey(
        _ key: String,
        parentRunID: UUID,
        requestID: UUID,
        permitsUnboundRequest: Bool,
        at date: Date
    ) async throws -> LocalResearchExecutionRecord {
        guard key.utf8.count == 73,
              let execution = try await services.localResearchExecutionStore
                .recordIfPresent(id: parentRunID),
              let grant = execution.agentCoordinationGrant,
              execution.triptychID == grant.triptychID,
              services.manifest.id == grant.triptychID,
              execution.id == grant.parentRunID,
              parentRunID == grant.parentRunID,
              let actionSnapshot = execution.snapshot.actionSnapshot,
              try AgentNoteChangeActionRevision(actionSnapshot: actionSnapshot)
                == grant.actionRevision else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        guard date < grant.expiresAt else {
            throw AgentNoteChangeOperationError.expiredCoordinationKey
        }
        let candidate = try grant.boundKeyDigest(coordinationKey: key)
        guard Self.constantTimeEqual(candidate, grant.keyDigest) else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        if let boundID = execution.agentCoordinationRequestID,
           boundID != requestID {
            throw AgentNoteChangeOperationError
                .coordinationRequestAlreadyBound(boundID)
        }
        if !permitsUnboundRequest,
           execution.agentCoordinationRequestID != requestID {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        return execution
    }

    private func requireCoordinationGrant(
        _ execution: LocalResearchExecutionRecord
    ) throws -> AgentCoordinationGrant {
        guard let grant = execution.agentCoordinationGrant else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        return grant
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(left.count ^ right.count)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            difference |= l ^ r
        }
        return difference == 0
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
        _ request: AgentNoteChangeRequest,
        permittingCancelledParent: Bool = false
    ) async throws -> Bool {
        do {
            try await authenticateParent(of: request)
        } catch is AgentNoteChangeOperationError {
            return false
        }
        guard let parent = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID),
              Self.parentPermitsChangeRequest(parent)
                || (permittingCancelledParent
                    && parent.completion?.state == .cancelled) else {
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

    public func submitAgentNoteChangeRequestFromBridge(
        _ request: AgentNoteChangeRequest,
        coordinationKey: String,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().submitAgentNoteChangeRequestFromBridge(
            request,
            coordinationKey: coordinationKey,
            receivedAt: receivedAt,
            validFor: validFor
        )
    }

    public func agentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().agentNoteChangeRequestFromBridge(
            id: id,
            coordinationKey: coordinationKey,
            now: now
        )
    }

    public func cancelAgentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().cancelAgentNoteChangeRequestFromBridge(
            id: id,
            coordinationKey: coordinationKey,
            now: now
        )
    }

    public func resolveAgentNoteChangeRequest(
        id: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().resolveAgentNoteChangeRequest(
            id: id,
            state: state,
            allowedNoteIDs: allowedNoteIDs,
            decidedAt: decidedAt
        )
    }

    public func applyStandingPermissionToAgentNoteChangeRequest(
        id: UUID,
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle()
            .applyStandingPermissionToAgentNoteChangeRequest(
                id: id,
                decidedAt: decidedAt
            )
    }
}
