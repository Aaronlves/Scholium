import Foundation
import ScholiumContracts
import ScholiumCore

struct AgentMoveAuthorization: Sendable {
    let changeID: UUID
    let planFingerprint: DocumentFingerprint
}

extension WorkspaceHandle {
    func moveAgentNote(noteID: UUID, expectedFingerprint: DocumentFingerprint, to path: String,
                       expectedPlanFingerprint: DocumentFingerprint) async throws -> AgentNoteMoveResult {
        guard (try? MarkdownRelativePath(path)) != nil, WorkspaceLibraryVisibility.includes(path) else {
            throw AgentCollaborationError.invalidRequest("Choose an exact same-vault Note path outside attachment storage.")
        }
        let target = try await currentAgentNote(noteID: noteID)
        guard target.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: target.fingerprint)
        }
        guard target.id.relativePath != path else { throw AgentCollaborationError.noChanges }
        let changeID = UUID()
        let outcome = try await coordinatedMoveDocument(target.id, to: path, expectedRevision: expectedFingerprint,
            expectedStableNoteID: noteID, agentMove: .init(changeID: changeID, planFingerprint: expectedPlanFingerprint))
        guard let change = try? await services.agentChangeStore.change(id: changeID), change.state == .confirmed else {
            throw AgentCollaborationError.changeConfirmationUncertain(changeID)
        }
        return .init(change: change, commit: outcome.committedValue, derivedRefreshWarning: outcome.derivedRefreshWarning)
    }

    func captureAgentMove(plan: IncomingLinkRewritePlan, noteID: UUID, expectedFingerprint: DocumentFingerprint,
                          expectedPlanFingerprint: DocumentFingerprint) async throws -> (preview: AgentNoteMovePreview, beforeData: Data, afterData: Data, move: AgentMoveEvidence) {
        let preview = try await agentMovePreview(plan: plan, noteID: noteID, expectedFingerprint: expectedFingerprint)
        guard preview.planFingerprint == expectedPlanFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedPlanFingerprint, current: preview.planFingerprint)
        }
        guard preview.blockers.isEmpty else { throw AgentCollaborationError.invalidRequest("The move has unresolved incoming-link effects.") }
        guard preview.effects.count <= AgentMoveEvidence.maximumAffectedNotes else { throw AgentChangeError.sourceTooLarge }
        var linked: [AgentMoveLinkedSource] = []
        var primaryBefore: Data?
        var primaryAfter: Data?
        var total = 0
        for effect in preview.effects {
            let current = try await loadDocument(effect.source)
            guard current.fingerprint == effect.beforeFingerprint else {
                throw AgentCollaborationError.staleRevision(expected: effect.beforeFingerprint, current: current.fingerprint)
            }
            let after = plan.rewrites.first { $0.source == effect.source }.map { Data($0.updatedSource.utf8) } ?? current.sourceBytes
            total += current.sourceBytes.count + after.count
            guard total <= AgentMoveEvidence.maximumSourceByteCount,
                  current.sourceBytes.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
                  after.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount else { throw AgentChangeError.sourceTooLarge }
            if effect.noteID == noteID { primaryBefore = current.sourceBytes; primaryAfter = after }
            else { linked.append(.init(effect: effect, beforeData: current.sourceBytes, afterData: after)) }
        }
        guard let primary = preview.effects.first(where: { $0.noteID == noteID }), let primaryBefore, let primaryAfter else {
            throw AgentCollaborationError.invalidRequest("The move has no exact primary Note evidence.")
        }
        let move = AgentMoveEvidence(primary: primary, linkedSources: linked)
        return (preview, primaryBefore, primaryAfter, move)
    }

    func prepareAgentMoveEvidence(plan: IncomingLinkRewritePlan, noteID: UUID, expectedFingerprint: DocumentFingerprint,
                                  authorization: AgentMoveAuthorization) async throws {
        let captured = try await captureAgentMove(plan: plan, noteID: noteID, expectedFingerprint: expectedFingerprint,
            expectedPlanFingerprint: authorization.planFingerprint)
        try Task.checkCancellation()
        _ = try await services.agentChangeStore.prepare(id: authorization.changeID, operation: .move, noteID: noteID,
            role: captured.preview.role, originalRelativePath: plan.movedNote.relativePath, finalRelativePath: plan.destination.relativePath,
            beforeData: captured.beforeData, afterData: captured.afterData, move: captured.move)
    }

    func confirmAgentMoveEvidence(id: UUID, commit: TriptychMoveCommit) async throws {
        do {
            let evidence = try await services.agentChangeStore.evidence(id: id)
            guard let move = evidence.move, move.primary.source == commit.movedNote, move.primary.destination == commit.destination,
                  move.primary.beforeFingerprint == commit.previousRevision else { throw AgentChangeError.mismatchedBinding(id) }
            var observed = [move.primary.noteID: commit.committedRevision]
            for linked in move.linkedSources {
                guard let rewrite = commit.rewrites.first(where: { $0.note == linked.effect.destination }),
                      rewrite.previousRevision == linked.effect.beforeFingerprint,
                      rewrite.rewrittenOccurrences == linked.effect.rewrittenOccurrences else { throw AgentChangeError.mismatchedBinding(id) }
                observed[linked.effect.noteID] = rewrite.committedRevision
            }
            guard commit.rewrites.count == move.linkedSources.count + (move.primary.rewrittenOccurrences > 0 ? 1 : 0) else {
                throw AgentChangeError.mismatchedBinding(id)
            }
            _ = try await services.agentChangeStore.confirm(id: id, observedAfterFingerprint: commit.committedRevision, observedMoveFingerprints: observed)
        } catch {
            _ = try? await services.agentChangeStore.markOutcomeUncertain(id: id)
            throw AgentCollaborationError.changeConfirmationUncertain(id)
        }
    }

    func previewAgentMoveMutation(noteID: UUID, expectedFingerprint: DocumentFingerprint, to path: String,
                                  expectedPlanFingerprint: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        let checked = try await previewAgentNoteMove(noteID: noteID, expectedFingerprint: expectedFingerprint, to: path)
        guard checked.planFingerprint == expectedPlanFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedPlanFingerprint, current: checked.planFingerprint)
        }
        let lease = try await beginSourceMutation(); defer { endSourceMutation(lease) }
        let plan = try await workspaceMovePlan(moving: checked.source, to: checked.destination)
        let captured = try await captureAgentMove(plan: plan, noteID: noteID, expectedFingerprint: expectedFingerprint,
            expectedPlanFingerprint: expectedPlanFingerprint)
        return try agentMoveComparison(preview: captured.preview, before: captured.beforeData, after: captured.afterData, move: captured.move)
    }

    func agentMoveComparison(preview: AgentNoteMovePreview, before: Data, after: Data, move: AgentMoveEvidence, reversed: Bool = false) throws -> AgentNoteUpdatePreview {
        func comparison(_ before: Data, _ after: Data) throws -> ExactSourceComparison {
            let start = reversed ? after : before; let end = reversed ? before : after
            return try ExactSourceComparisonBuilder.build(startingData: start, endingData: end,
                startingRevision: DocumentFingerprint(data: start), endingRevision: DocumentFingerprint(data: end))
        }
        return try .init(noteID: preview.noteID, relativePath: preview.source.relativePath, comparison: comparison(before, after), movePreview: preview,
            linkedComparisons: move.linkedSources.map { .init(effect: $0.effect, comparison: try comparison($0.beforeData, $0.afterData)) })
    }

    func previewAgentNoteMove(noteID: UUID, expectedFingerprint: DocumentFingerprint, to relativePath: String) async throws -> AgentNoteMovePreview {
        try Task.checkCancellation()
        guard (try? MarkdownRelativePath(relativePath)) != nil, WorkspaceLibraryVisibility.includes(relativePath) else {
            throw AgentCollaborationError.invalidRequest("Choose an exact Note path in its current role vault, outside attachment storage.")
        }
        let target = try await currentAgentNote(noteID: noteID)
        guard target.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: target.fingerprint)
        }
        guard target.id.relativePath != relativePath else {
            throw AgentCollaborationError.noChanges
        }
        let lease = try await beginSourceMutation()
        defer { endSourceMutation(lease) }
        let identity = try await resolvedIdentity(for: target.id, expectedRevision: expectedFingerprint)
        guard identity.id == noteID else { throw AgentCollaborationError.noteAmbiguous(noteID) }
        let destination = VaultQualifiedNoteID(vaultID: target.id.vaultID, relativePath: relativePath)
        let plan = try await workspaceMovePlan(moving: target.id, to: destination)
        let coordinator = TriptychMoveCoordinator(triptychID: services.manifest.id,
            repositories: services.repositories, recoveryStore: services.transactionRecoveryStore)
        // Keep blocked links visible, while still checking source, path and valid rewrites.
        let preflight = IncomingLinkRewritePlan(movedNote: plan.movedNote, destination: plan.destination,
            graphGeneration: plan.graphGeneration, rewrites: plan.rewrites)
        try await coordinator.validate(preflight, expectedRevision: expectedFingerprint)
        return try await agentMovePreview(plan: plan, noteID: noteID, expectedFingerprint: expectedFingerprint)
    }

    func agentMovePreview(plan: IncomingLinkRewritePlan, noteID: UUID, expectedFingerprint: DocumentFingerprint) async throws -> AgentNoteMovePreview {
        var effects: [AgentNoteMoveEffect] = []
        let sourceIDs = Set(plan.rewrites.map(\.source)).union([plan.movedNote])
        for source in sourceIDs.sorted() {
            try Task.checkCancellation()
            let rewrite = plan.rewrites.first { $0.source == source }
            let expected = rewrite?.expectedRevision ?? expectedFingerprint
            let identity = try await resolvedIdentity(for: source, expectedRevision: expected)
            let role = try vault(id: source.vaultID).role
            guard role != .other else { throw AgentCollaborationError.invalidRequest("Move effects must remain within the Triptych roles.") }
            effects.append(.init(noteID: identity.id, role: role, source: source,
                destination: source == plan.movedNote ? plan.destination : source,
                beforeFingerprint: expected, afterFingerprint: rewrite.map { DocumentFingerprint(content: $0.updatedSource) } ?? expected,
                rewrittenOccurrences: rewrite?.rewrittenOccurrences ?? 0))
        }
        var blockers: [AgentNoteMoveBlockedLink] = []
        for block in plan.blockedIncomingLinks {
            let identity = try await resolvedIdentity(for: block.source, expectedRevision: block.sourceFingerprint)
            blockers.append(.init(noteID: identity.id, role: try vault(id: block.source.vaultID).role, link: block))
        }
        return try .init(noteID: noteID, role: try vault(id: plan.movedNote.vaultID).role, source: plan.movedNote,
            destination: plan.destination, expectedFingerprint: expectedFingerprint, effects: effects, blockers: blockers)
    }
}
