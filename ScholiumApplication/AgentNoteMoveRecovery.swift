import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    /// Exact inverse of a recorded move. Current link resolution may veto restoration, never rewrite its preimages.
    func agentMoveInverse(evidence: AgentChangeEvidence) async throws -> IncomingLinkRewritePlan {
        guard let move = evidence.move, let beforeData = evidence.beforeData,
              evidence.change.operation == .move, evidence.change.state == .confirmed else { throw AgentChangeError.undoUnavailable(evidence.change.id) }
        let primary = move.primary
        for effect in move.effects {
            let identity = try await resolvedIdentity(for: effect.destination, expectedRevision: effect.afterFingerprint)
            guard identity.id == effect.noteID else { throw AgentChangeError.mismatchedBinding(evidence.change.id) }
        }
        let context = try await freshMovePlanningContext()
        guard let ordinary = IncomingLinkRewriter.planUsingValidatedSnapshot(documents: context.documents,
            catalog: context.catalog, graph: context.graph, moving: primary.destination, to: primary.source) else {
            throw AgentCollaborationError.invalidRequest("The current link scope cannot authorize this move inverse.")
        }
        let expectedSources = Set(move.effects.filter { $0.rewrittenOccurrences > 0 }.map(\.destination))
        guard ordinary.blockedIncomingLinks.isEmpty, Set(ordinary.rewrites.map(\.source)) == expectedSources else {
            throw AgentCollaborationError.invalidRequest("The incoming-link scope changed after the move. Review the current links before restoring it.")
        }
        var restored = context.documents
        guard let primarySource = NoteDocument.decodeUTF8PreservingBOM(beforeData) else { throw AgentChangeError.invalid(evidence.change.id) }
        restored[primary.destination] = nil
        restored[primary.source] = NoteDocument(relativePath: primary.source.relativePath, rawContent: primarySource)
        for linked in move.linkedSources {
            guard let source = NoteDocument.decodeUTF8PreservingBOM(linked.beforeData) else { throw AgentChangeError.invalid(evidence.change.id) }
            restored[linked.effect.source] = NoteDocument(relativePath: linked.effect.source.relativePath, rawContent: source)
        }
        let semantics = restored.mapValues(MarkdownSemanticDocument.init(parsing:))
        let futureCatalog = context.catalog.compactMap { item -> LinkCatalogNote? in
            let id = item.id == primary.destination ? primary.source : item.id
            guard let document = restored[id] else { return nil }
            let derived = LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
            return LinkCatalogNote(id: id, title: derived.title, aliases: item.aliases, headings: derived.headings, blockAnchors: derived.blockAnchors)
        }
        let futureGraph = LinkGraphBuilder.build(generation: context.graph.generation, catalog: futureCatalog,
            documents: semantics, resolutionScope: .workspace)
        for effect in move.effects where effect.rewrittenOccurrences > 0 {
            let currentLinks = (context.graph.outgoing[effect.destination] ?? []).sorted { $0.occurrence.linkSpan.utf16LowerBound < $1.occurrence.linkSpan.utf16LowerBound }
            let futureLinks = (futureGraph.outgoing[effect.source] ?? []).sorted { $0.occurrence.linkSpan.utf16LowerBound < $1.occurrence.linkSpan.utf16LowerBound }
            guard currentLinks.count == futureLinks.count else { throw AgentChangeError.invalid(evidence.change.id) }
            var rewritten = 0
            for (current, future) in zip(currentLinks, futureLinks) {
                guard !current.occurrence.target.utf8.elementsEqual(future.occurrence.target.utf8) else { continue }
                rewritten += 1
                guard current.occurrence.resolution == .resolved(primary.destination), future.occurrence.resolution == .resolved(primary.source),
                      current.occurrence.fragment == future.occurrence.fragment, current.occurrence.syntax == future.occurrence.syntax else {
                    throw AgentCollaborationError.invalidRequest("An original link would resolve differently in the current knowledge base. Its exact bytes cannot be restored safely.")
                }
            }
            guard rewritten == effect.rewrittenOccurrences else { throw AgentChangeError.invalid(evidence.change.id) }
        }
        var rewrites = try move.linkedSources.map { linked -> IncomingLinkRewrite in
            guard let source = NoteDocument.decodeUTF8PreservingBOM(linked.beforeData) else { throw AgentChangeError.invalid(evidence.change.id) }
            return .init(source: linked.effect.destination, expectedRevision: linked.effect.afterFingerprint,
                         updatedSource: source, rewrittenOccurrences: linked.effect.rewrittenOccurrences)
        }
        if primary.rewrittenOccurrences > 0 {
            rewrites.append(.init(source: primary.destination, expectedRevision: primary.afterFingerprint, updatedSource: primarySource,
                                  rewrittenOccurrences: primary.rewrittenOccurrences))
        }
        return .init(movedNote: primary.destination, destination: primary.source, graphGeneration: ordinary.graphGeneration,
                     rewrites: rewrites.sorted { $0.source < $1.source })
    }

    func previewAgentMoveUndo(id: UUID, expectedAfterFingerprint: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        let evidence = try await services.agentChangeStore.evidence(id: id)
        guard let move = evidence.move, let before = evidence.beforeData, let after = evidence.afterData,
              evidence.change.state == .confirmed, evidence.change.afterFingerprint == expectedAfterFingerprint else { throw AgentChangeError.undoUnavailable(id) }
        let target = try await currentAgentNote(noteID: evidence.change.noteID)
        guard target.id == move.primary.destination else { throw AgentCollaborationError.invalidRequest("The Note moved again after this change.") }
        let lease = try await beginSourceMutation(); defer { endSourceMutation(lease) }
        let plan = try await agentMoveInverse(evidence: evidence)
        let coordinator = TriptychMoveCoordinator(triptychID: services.manifest.id, repositories: services.repositories, recoveryStore: services.transactionRecoveryStore)
        try await coordinator.validate(plan, expectedRevision: expectedAfterFingerprint)
        let preview = try await agentMovePreview(plan: plan, noteID: evidence.change.noteID, expectedFingerprint: expectedAfterFingerprint)
        return try agentMoveComparison(preview: preview, before: before, after: after, move: move, reversed: true)
    }

    func undoAgentMove(id: UUID, expectedAfterFingerprint: DocumentFingerprint) async throws -> AgentChangeUndoResult {
        let evidence = try await services.agentChangeStore.evidence(id: id)
        guard let move = evidence.move, evidence.change.state == .confirmed,
              evidence.change.afterFingerprint == expectedAfterFingerprint else { throw AgentChangeError.undoUnavailable(id) }
        let target = try await currentAgentNote(noteID: evidence.change.noteID)
        guard target.id == move.primary.destination else { throw AgentCollaborationError.invalidRequest("The Note moved again after this change.") }
        let result = try await coordinatedMoveDocument(target.id, to: move.primary.source.relativePath,
            expectedRevision: expectedAfterFingerprint, expectedStableNoteID: evidence.change.noteID, undoAgentMoveID: id)
        return .init(changeID: id, noteID: evidence.change.noteID, restoredFingerprint: result.committedValue.committedRevision)
    }

    func confirmAgentMoveUndo(id: UUID, commit: TriptychMoveCommit) async throws {
        do {
            let evidence = try await services.agentChangeStore.evidence(id: id)
            guard let move = evidence.move, commit.movedNote == move.primary.destination, commit.destination == move.primary.source,
                  commit.previousRevision == move.primary.afterFingerprint,
                  commit.rewrites.count == move.linkedSources.count + (move.primary.rewrittenOccurrences > 0 ? 1 : 0) else {
                throw AgentChangeError.mismatchedBinding(id)
            }
            var restored = [move.primary.noteID: commit.committedRevision]
            for linked in move.linkedSources {
                guard let actual = commit.rewrites.first(where: { $0.note == linked.effect.source }),
                      actual.previousRevision == linked.effect.afterFingerprint,
                      actual.rewrittenOccurrences == linked.effect.rewrittenOccurrences else { throw AgentChangeError.mismatchedBinding(id) }
                restored[linked.effect.noteID] = actual.committedRevision
            }
            _ = try await services.agentChangeStore.markUndone(id: id, restoredFingerprint: commit.committedRevision, restoredMoveFingerprints: restored)
        } catch { throw AgentCollaborationError.changeConfirmationUncertain(id) }
    }

    func reviewAgentMove(_ evidence: AgentChangeEvidence) async throws -> AgentChangeReview {
        guard let move = evidence.move else { throw AgentChangeError.invalid(evidence.change.id) }
        let snapshot = try await refresh()
        var state: AgentChangeEndingRevisionState = .current
        for effect in move.effects {
            let matches = snapshot.vaults.flatMap(\.documents).filter { $0.stableIdentity.resolvedID == effect.noteID }
            guard matches.count == 1 else { state = .unavailable; break }
            let current = try await loadDocument(matches[0].id)
            if matches[0].id != effect.destination || current.fingerprint != effect.afterFingerprint { state = .earlierRevision }
        }
        var reason: String?
        if evidence.change.state == .confirmed && state == .current {
            do { _ = try await previewAgentMoveUndo(id: evidence.change.id, expectedAfterFingerprint: move.primary.afterFingerprint) }
            catch { reason = error.localizedDescription }
        }
        let linked = try move.linkedSources.map { linked in
            AgentMoveSourceComparison(effect: linked.effect, comparison: try ExactSourceComparisonBuilder.build(
                startingData: linked.beforeData, endingData: linked.afterData,
                startingRevision: linked.effect.beforeFingerprint, endingRevision: linked.effect.afterFingerprint))
        }
        return try .init(change: evidence.change, comparison: evidence.exactUpdateComparison(), currentCreatedSource: nil,
                         endingRevisionState: state, linkedComparisons: linked, undoUnavailableReason: reason)
    }
}
