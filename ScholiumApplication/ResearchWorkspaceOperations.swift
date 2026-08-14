import ScholiumContracts
import Foundation
import ScholiumCore
import OSLog

private let researchRecoveryLogger = Logger(
    subsystem: "com.scholium.app",
    category: "ResearchRecovery"
)

enum ResearchSettlementRecovery {
    static func shouldRollbackNewPin(after error: Error) -> Bool {
        guard let storeError = error as? ResearchRecordStoreV1Error else {
            return false
        }
        if case .replacementNotCommitted = storeError { return true }
        return false
    }
}

private struct CurrentResearchSource {
    let note: VaultQualifiedNoteID
    let document: NoteDocument
}

private enum ResearchRecordUndoPlan {
    case unavailable(noteID: UUID)
    case alreadyRestored(noteID: UUID, revision: DocumentFingerprint)
    case conflict(noteID: UUID, revision: DocumentFingerprint)
    case restore(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint,
        checkpointID: UUID,
        sourceKey: TriptychCheckpointFileKey,
        destinationKey: TriptychCheckpointFileKey
    )

    var affectedVaultID: UUID? {
        guard case .restore(_, let note, _, _, _, _, _) = self else { return nil }
        return note.vaultID
    }
}

#if DEBUG
enum ResearchSettlementReplacementFaultPhaseForTesting: Sendable {
    case beforeRename
    case afterRename
}

struct PortableSettlementProjectionForTesting: Sendable {
    let settlements: [SettlementRecord]
    let issueCount: Int
}

private enum InjectedResearchSettlementReplacementFault: Error {
    case beforeRename
    case afterRename
}
#endif

enum ResearchDiscussionFactory {
    static func make(
        snapshot: ResearchFunctionSnapshot,
        triptychID: UUID
    ) throws -> PortableResearchDiscussion {
        guard let action = snapshot.actionSnapshot,
              action.executionKind == .discussion else {
            throw ResearchFunctionContractError.invalidCompletion(
                "A portable Discussion requires one resolved Discuss Action."
            )
        }
        let request = snapshot.request
        let readableByID = Dictionary(
            uniqueKeysWithValues: action.authority.readableNotes.map { ($0.noteID, $0) }
        )
        let selectedIDs = [request.target.noteID] + request.materials.map(\.noteID)
        var seen: Set<UUID> = []
        let selected = try selectedIDs.compactMap { noteID -> ResearchActionNoteSnapshot? in
            guard seen.insert(noteID).inserted else { return nil }
            guard let note = readableByID[noteID] else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A selected Discussion participant is outside the frozen read authority."
                )
            }
            return note
        }
        let participants = try selected.map { note in
            try PortableResearchNoteRevision(
                noteID: note.noteID,
                note: note.note,
                role: note.role,
                title: note.title,
                startingRevision: note.fingerprint,
                endingRevision: note.fingerprint
            )
        }
        let statement = try PortableResearchStatement(
            id: snapshot.runID,
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: request.instruction ?? "Discuss the current Target.",
            createdAt: snapshot.preparedAt,
            passage: request.scope?.selection
        )
        return try PortableResearchDiscussion(
            id: snapshot.runID,
            triptychID: triptychID,
            primaryNoteID: request.target.noteID,
            action: ResearchActionRecordIdentity(snapshot: action),
            method: try PortableResearchMethodReference(snapshot: action),
            participatingNotes: participants,
            statements: [statement],
            createdAt: snapshot.preparedAt,
            updatedAt: snapshot.preparedAt
        )
    }

    static func activeMatches(
        _ discussion: PortableResearchDiscussion,
        expected: PortableResearchDiscussion
    ) -> Bool {
        discussion.id == expected.id
            && discussion.triptychID == expected.triptychID
            && discussion.primaryNoteID == expected.primaryNoteID
            && discussion.action == expected.action
            && discussion.method == expected.method
            && discussion.participatingNotes == expected.participatingNotes
            && discussion.createdAt <= expected.createdAt
            && expected.statements.first.map(discussion.statements.contains) == true
    }

    static func finishedMatches(
        _ record: PortableResearchRecord,
        expected: PortableResearchDiscussion
    ) -> Bool {
        let finishedByID = Dictionary(
            uniqueKeysWithValues: record.participatingNotes.map { ($0.noteID, $0) }
        )
        return record.kind == .discussion
            && record.primaryNoteID == expected.primaryNoteID
            && record.action == expected.action
            && record.method == expected.method
            && record.startedAt <= expected.createdAt
            && expected.statements.first.map(record.statements.contains) == true
            && finishedByID.count == expected.participatingNotes.count
            && expected.participatingNotes.allSatisfy { expectedNote in
                guard let finishedNote = finishedByID[expectedNote.noteID] else { return false }
                return finishedNote.note == expectedNote.note
                    && finishedNote.role == expectedNote.role
                    && finishedNote.title == expectedNote.title
                    && finishedNote.startingRevision == expectedNote.startingRevision
            }
    }
}

extension WorkspaceHandle {
    // MARK: Settlement and Discussion

    #if DEBUG
    func setResearchSettlementReplacementFaultForTesting(
        _ phase: ResearchSettlementReplacementFaultPhaseForTesting?
    ) async {
        switch phase {
        case .beforeRename:
            await services.portableResearchRecordStore
                .setPostCommitFaultForTesting(nil)
            await services.portableResearchRecordStore
                .setPreCommitFaultForTesting { _ in
                    throw InjectedResearchSettlementReplacementFault.beforeRename
                }
        case .afterRename:
            await services.portableResearchRecordStore
                .setPreCommitFaultForTesting(nil)
            await services.portableResearchRecordStore
                .setPostCommitFaultForTesting { _ in
                    throw InjectedResearchSettlementReplacementFault.afterRename
                }
        case nil:
            await services.portableResearchRecordStore
                .setPreCommitFaultForTesting(nil)
            await services.portableResearchRecordStore
                .setPostCommitFaultForTesting(nil)
        }
    }

    @discardableResult
    func writePortableSettlementWithoutPinForTesting(
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        try await services.portableResearchRecordStore.settle(
            noteID: noteID,
            fingerprint: fingerprint,
            rationale: rationale
        )
    }

    func portableSettlementProjectionForTesting() async throws
        -> PortableSettlementProjectionForTesting {
        let listing = try await services.portableResearchRecordStore
            .settlementListing()
        return PortableSettlementProjectionForTesting(
            settlements: listing.settlements,
            issueCount: listing.issues.count
        )
    }
    #endif

    @discardableResult
    func settle(
        _ noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        try beginResearchRecoveryMutation()
        defer { endResearchRecoveryMutation() }
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        let repository = try repository(vaultID: noteID.vaultID)
        let pin = try await repository.pinSettledSnapshot(
            noteID: context.identity.id,
            note: noteID,
            expectedRevision: expectedRevision
        )
        let settlement: SettlementRecord
        do {
            settlement = try await services.portableResearchRecordStore.settle(
                noteID: context.identity.id,
                fingerprint: expectedRevision,
                rationale: rationale
            )
        } catch {
            // Only a typed failure before rename proves that portable state
            // did not commit. Commit uncertainty, including a later concurrent
            // replacement, always retains the exact-byte pin.
            let replacementDidNotCommit = ResearchSettlementRecovery
                .shouldRollbackNewPin(after: error)
            if pin.wasCreated, replacementDidNotCommit {
                do {
                    _ = try await repository.removeSettledSnapshots([pin.snapshot.id])
                } catch let recoveryError {
                    throw ResearchOperationError.settleRollbackFailed(
                        settleError: error.localizedDescription,
                        recoveryError: recoveryError.localizedDescription
                    )
                }
            }
            throw error
        }
        do {
            let policy = try await completePendingRecoveryPolicyChange()
            let removals = try await repository.settledSnapshotIDsToRemove(
                maximumCount: policy.retention.maximumCount
            )
            _ = try await repository.removeSettledSnapshots(removals)
        } catch {
            researchRecoveryLogger.error(
                "Settle committed, but settled-version retention could not be enforced: \(error.localizedDescription, privacy: .public)"
            )
        }
        try await refreshAfterResearchCommit("The settlement")
        return settlement
    }

    func recoveryPolicy() async throws -> ResearchRecoveryPolicySnapshot {
        try requireActive()
        let stored = try await completePendingRecoveryPolicyChange()
        let snapshots = try await settledSnapshots(noteID: nil)
        let maximum = Dictionary(grouping: snapshots, by: \.noteID)
            .values.map(\.count).max() ?? 0
        return ResearchRecoveryPolicySnapshot(
            retention: stored.retention,
            revision: stored.revision,
            settledSnapshotCount: snapshots.count,
            maximumSnapshotsForOneNote: maximum
        )
    }

    func prepareRecoveryPolicyChange(
        _ retention: SettledSnapshotRetention,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchRecoveryPolicyChangePreview {
        let current = try await recoveryPolicy()
        guard current.revision == expectedRevision else {
            throw ResearchRecoveryPolicyError.staleRevision
        }
        var removalIDs: Set<UUID> = []
        var affectedNoteIDs: Set<UUID> = []
        for repository in services.repositories.values {
            let repositoryRemovalIDs = try await repository
                .settledSnapshotIDsToRemove(maximumCount: retention.maximumCount)
            removalIDs.formUnion(repositoryRemovalIDs)
            let snapshots = try await repository.settledSnapshots(noteID: nil)
            affectedNoteIDs.formUnion(
                snapshots.lazy.filter { repositoryRemovalIDs.contains($0.id) }.map(\.noteID)
            )
        }
        return ResearchRecoveryPolicyChangePreview(
            triptychID: services.manifest.id,
            retention: retention,
            expectedPolicyRevision: expectedRevision,
            snapshotIDsToRemove: removalIDs,
            affectedNoteCount: affectedNoteIDs.count
        )
    }

    func applyRecoveryPolicyChange(
        _ preview: ResearchRecoveryPolicyChangePreview
    ) async throws -> ResearchRecoveryPolicyApplyOutcome {
        try beginResearchRecoveryMutation()
        defer { endResearchRecoveryMutation() }
        guard preview.triptychID == services.manifest.id else {
            throw ResearchRecoveryPolicyError.stalePreview
        }
        let current = try await recoveryPolicy()
        guard current.revision == preview.expectedPolicyRevision else {
            throw ResearchRecoveryPolicyError.staleRevision
        }
        let freshPreview = try await prepareRecoveryPolicyChange(
            preview.retention,
            expectedRevision: preview.expectedPolicyRevision
        )
        guard freshPreview.snapshotIDsToRemove == preview.snapshotIDsToRemove,
              freshPreview.affectedNoteCount == preview.affectedNoteCount else {
            throw ResearchRecoveryPolicyError.stalePreview
        }
        if preview.snapshotIDsToRemove.isEmpty {
            _ = try await services.researchRecoveryPolicyStore.save(
                preview.retention,
                expectedRevision: preview.expectedPolicyRevision
            )
        } else {
            let pending = try await services.researchRecoveryPolicyStore.beginChange(
                preview.retention,
                approvedSnapshotIDsToRemove: preview.snapshotIDsToRemove,
                expectedRevision: preview.expectedPolicyRevision
            )
            do {
                for repository in services.repositories.values {
                    _ = try await repository.removeSettledSnapshots(
                        preview.snapshotIDsToRemove
                    )
                }
                _ = try await services.researchRecoveryPolicyStore.finishPendingChange(
                    retention: preview.retention,
                    approvedSnapshotIDsToRemove: preview.snapshotIDsToRemove,
                    expectedRevision: pending.snapshot.revision
                )
            } catch {
                // The machine-local policy retains the exact researcher-
                // approved removal IDs. A later policy read retries only that
                // bounded set before clearing the durable pending state.
                throw error
            }
        }
        return ResearchRecoveryPolicyApplyOutcome(
            snapshot: try await recoveryPolicy(),
            removedSnapshotCount: preview.snapshotIDsToRemove.count
        )
    }

    private func completePendingRecoveryPolicyChange() async throws
        -> ResearchRecoveryPolicySnapshot {
        let stored = try await services.researchRecoveryPolicyStore.state()
        guard !stored.pendingSnapshotIDsToRemove.isEmpty else {
            return stored.snapshot
        }
        for repository in services.repositories.values {
            _ = try await repository.removeSettledSnapshots(
                stored.pendingSnapshotIDsToRemove
            )
        }
        return try await services.researchRecoveryPolicyStore.finishPendingChange(
            retention: stored.snapshot.retention,
            approvedSnapshotIDsToRemove: stored.pendingSnapshotIDsToRemove,
            expectedRevision: stored.snapshot.revision
        )
    }

    func settledSnapshots(noteID: UUID?) async throws -> [SettledRevisionSnapshot] {
        try requireActive()
        var snapshots: [SettledRevisionSnapshot] = []
        for repository in services.repositories.values {
            snapshots.append(contentsOf: try await repository.settledSnapshots(noteID: noteID))
        }
        return snapshots.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func activeDiscussions(noteID: UUID?) async throws -> [PortableResearchDiscussion] {
        try requireActive()
        let listing = try await services.portableResearchRecordStore.activeDiscussions(
            noteID: noteID
        )
        guard listing.issues.isEmpty else {
            throw ScholiumApplicationError.researchStoreUnavailable(
                listing.issues.map(\.reason).joined(separator: "\n")
            )
        }
        return listing.discussions
    }

    func activeDiscussion(id: UUID) async throws -> PortableResearchDiscussion {
        try requireActive()
        return try await services.portableResearchRecordStore.activeDiscussion(id: id)
    }

    func activeDiscussionIfPresent(id: UUID) async throws -> PortableResearchDiscussion? {
        try requireActive()
        return try await services.portableResearchRecordStore.activeDiscussionIfPresent(id: id)
    }

    func createDiscussion(
        target: ResearchFunctionTarget,
        focalNotes: [ResearchFunctionMaterial],
        passage: CommentAnchor?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        try await createResearcherDiscussion(
            target: target,
            focalNotes: focalNotes,
            passage: passage,
            lineReference: nil,
            researcherMessage: researcherMessage
        )
    }

    func createComment(
        target: ResearchFunctionTarget,
        lineReference: ResearchLineReference,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        try await createResearcherDiscussion(
            target: target,
            focalNotes: [],
            passage: nil,
            lineReference: lineReference,
            researcherMessage: researcherMessage
        )
    }

    private func createResearcherDiscussion(
        target: ResearchFunctionTarget,
        focalNotes: [ResearchFunctionMaterial],
        passage: CommentAnchor?,
        lineReference: ResearchLineReference?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        let targetContext = try await researchContext(
            for: target.note,
            expectedRevision: target.fingerprint,
            permits: { ResearchFunctionTargetRole(vaultRole: $0) == target.role },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        guard targetContext.identity.id == target.noteID,
              passage == nil || lineReference == nil,
              passage?.fingerprint == target.fingerprint || passage == nil,
              lineReference?.fingerprint == target.fingerprint || lineReference == nil else {
            throw ResearchOperationError.noteUnavailable(target.note)
        }
        if let lineReference {
            let lineCount = targetContext.document.rawContent.reduce(into: 1) { count, character in
                if character.isNewline { count += 1 }
            }
            guard lineReference.endLine <= lineCount else {
                throw ResearchOperationError.staleCommentRevision
            }
        }
        var participants = [try portableDiscussionParticipant(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            title: target.title,
            fingerprint: target.fingerprint
        )]
        var seen: Set<UUID> = [target.noteID]
        for focal in focalNotes where seen.insert(focal.noteID).inserted {
            let context = try await researchContext(
                for: focal.note,
                expectedRevision: focal.fingerprint,
                permits: { ResearchFunctionTargetRole(vaultRole: $0) == focal.role },
                unavailable: { ResearchOperationError.commentUnavailable($0) }
            )
            guard context.identity.id == focal.noteID else {
                throw ResearchOperationError.noteUnavailable(focal.note)
            }
            participants.append(try portableDiscussionParticipant(
                noteID: focal.noteID,
                note: focal.note,
                role: focal.role,
                title: focal.title,
                fingerprint: focal.fingerprint
            ))
        }
        let createdAt = Date()
        let statement = try PortableResearchStatement(
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: researcherMessage,
            createdAt: createdAt,
            passage: passage,
            lineReference: lineReference
        )
        let requestedParticipantIDs = Set(participants.map(\.noteID))
        let active = try await activeDiscussions(noteID: target.noteID)
            .filter { $0.primaryNoteID == target.noteID }
        if let existing = active.first {
            guard active.count == 1,
                  requestedParticipantIDs.isSubset(
                    of: Set(existing.participatingNotes.map(\.noteID))
                  ) else {
                throw ResearchOperationError.discussionContextChanged
            }
            let stored = try await appendDiscussionStatement(
                statement,
                to: existing
            )
            try await refreshAfterResearchCommit("The Discussion")
            return stored
        }
        let discussion = try PortableResearchDiscussion(
            triptychID: services.manifest.id,
            primaryNoteID: target.noteID,
            participatingNotes: participants,
            statements: [statement],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let stored: PortableResearchDiscussion
        do {
            stored = try await services.portableResearchRecordStore
                .createActiveDiscussion(discussion)
        } catch ResearchRecordStoreV1Error.activeDiscussionAlreadyExists(
            primaryNoteID: _,
            discussionID: let discussionID
        ) {
            let existing = try await services.portableResearchRecordStore.activeDiscussion(
                id: discussionID
            )
            guard existing.primaryNoteID == target.noteID,
                  requestedParticipantIDs.isSubset(
                    of: Set(existing.participatingNotes.map(\.noteID))
                  ) else {
                throw ResearchOperationError.discussionContextChanged
            }
            stored = try await appendDiscussionStatement(statement, to: existing)
        }
        try await refreshAfterResearchCommit("The Discussion")
        return stored
    }

    func appendDiscussionStatement(
        discussionID: UUID,
        author: PortableResearchStatementAuthor,
        attribution: String,
        text: String,
        passage: CommentAnchor? = nil
    ) async throws -> PortableResearchDiscussion {
        try requireActive()
        let discussion = try await services.portableResearchRecordStore.activeDiscussion(
            id: discussionID
        )
        let kind: PortableResearchStatementKind = switch author {
        case .agent:
            .discussionTurn
        case .researcher:
            discussion.statements.contains(where: { $0.author == .agent })
                ? .researcherResponse
                : .discussionTurn
        }
        let createdAt = Date()
        let statement = try PortableResearchStatement(
            author: author,
            kind: kind,
            attribution: attribution,
            text: text,
            createdAt: createdAt,
            passage: passage
        )
        let stored = try await appendDiscussionStatement(statement, to: discussion)
        try await refreshAfterResearchCommit("The Discussion")
        return stored
    }

    private func appendDiscussionStatement(
        _ statement: PortableResearchStatement,
        to discussion: PortableResearchDiscussion
    ) async throws -> PortableResearchDiscussion {
        if let passage = statement.passage {
            guard let current = currentSnapshot.vaults.lazy
                .flatMap(\.documents)
                .first(where: { snapshot in
                    snapshot.lifecycle == .active
                        && snapshot.stableIdentity.resolvedID == discussion.primaryNoteID
                }) else {
                throw ResearchOperationError.noteUnavailable(discussion.primaryNote.note)
            }
            let document = try await repository(vaultID: current.id.vaultID).load(
                relativePath: current.id.relativePath
            )
            guard passage.fingerprint == document.fingerprint else {
                throw ResearchOperationError.staleCommentRevision
            }
        }
        return try await services.portableResearchRecordStore.appendDiscussionStatement(
            statement,
            to: discussion.id,
            at: statement.createdAt
        )
    }

    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord {
        try requireActive()
        if let local = try await services.localResearchExecutionStore.recordIfPresent(
            id: discussionID
        ) {
            guard local.snapshot.request.function == .discuss else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(discussionID)
            }
            _ = try await validatedDiscussionStatements(snapshot: local.snapshot)
        }
        let discussion: PortableResearchDiscussion
        do {
            discussion = try await services.portableResearchRecordStore.activeDiscussion(
                id: discussionID
            )
        } catch ResearchRecordStoreV1Error.discussionNotFound(_) {
            let existing = try await services.portableResearchRecordStore.record(
                id: discussionID
            )
            guard existing.kind == .discussion else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(discussionID)
            }
            return existing
        }
        let participants = try await currentDiscussionParticipants(discussion)
        let stored = try await services.portableResearchRecordStore.finishDiscussion(
            id: discussionID,
            participatingNotes: participants
        )
        try await refreshAfterResearchCommit("The Discussion finish")
        return stored
    }

    func validatedDiscussionStatements(
        snapshot: ResearchFunctionSnapshot
    ) async throws -> [PortableResearchStatement] {
        let expected = try ResearchDiscussionFactory.make(
            snapshot: snapshot,
            triptychID: services.manifest.id
        )
        if let active = try await services.portableResearchRecordStore
            .activeDiscussionIfPresent(id: snapshot.runID) {
            guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The portable Discussion no longer matches its frozen Action run."
                )
            }
            return active.statements
        }
        do {
            let finished = try await services.portableResearchRecordStore.record(
                id: snapshot.runID
            )
            guard ResearchDiscussionFactory.finishedMatches(finished, expected: expected) else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "The finished Discussion no longer matches its frozen Action run."
                )
            }
            return finished.statements
        } catch ResearchRecordStoreV1Error.recordNotFound(_) {
            throw ResearchFunctionContractError.invalidCompletion(
                "Record a durable attributed reply before completing Discuss."
            )
        }
    }

    func finishedResearchRecords(noteID: UUID?) async throws -> [PortableResearchRecord] {
        try requireActive()
        let listing = try await services.portableResearchRecordStore.listing()
        guard listing.issues.isEmpty else {
            throw ScholiumApplicationError.researchStoreUnavailable(
                listing.issues.map(\.reason).joined(separator: "\n")
            )
        }
        return listing.records.filter { record in
            noteID == nil || record.participatingNotes.contains(where: { $0.noteID == noteID })
        }
    }

    func saveResearcherResponse(
        recordID: UUID,
        draft: ResearcherResponseDraft,
        expectedEvaluationRevision: UUID?,
        expectedMethodFeedbackRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> PortableResearchRecord {
        try requireActive()
        let updated: PortableResearchRecord
        do {
            updated = try await services.portableResearchRecordStore
                .saveResearcherResponse(
                    draft,
                    recordID: recordID,
                    expectedEvaluationRevision: expectedEvaluationRevision,
                    expectedMethodFeedbackRevision: expectedMethodFeedbackRevision,
                    expectedResultFingerprint: expectedResultFingerprint
                )
        } catch {
            throw researcherResponseMutationError(
                error,
                operation: "the Researcher Response save"
            )
        }
        try await refreshAfterResearchCommit("The Researcher Response")
        return updated
    }

    func researchRecordChangeState(
        recordID: UUID
    ) async throws -> ResearchRecordChangeState {
        try requireActive()
        let record: PortableResearchRecord
        do {
            record = try await services.portableResearchRecordStore.record(id: recordID)
        } catch ResearchRecordStoreV1Error.recordNotFound(_),
                ResearchRecordStoreV1Error.recordPermanentlyDeleted(_) {
            throw ResearchRecordChangeRecoveryError.recordUnavailable
        }
        guard record.kind == .action else {
            throw ResearchRecordChangeRecoveryError.recordUnavailable
        }
        var documents: [ResearchRecordChangeCurrentState] = []
        for change in record.confirmedChanges {
            guard let current = try await currentResearchSource(noteID: change.noteID) else {
                documents.append(ResearchRecordChangeCurrentState(
                    noteID: change.noteID,
                    currentRelativePath: nil,
                    status: .unavailable,
                    observedRevision: nil
                ))
                continue
            }
            let status: ResearchRecordChangeCurrentStatus
            if current.document.fingerprint == change.endingRevision {
                status = .agentEndingRevision
            } else if let startingRevision = change.startingRevision,
                      current.document.fingerprint == startingRevision {
                status = .startingRevision
            } else {
                status = .superseded
            }
            documents.append(ResearchRecordChangeCurrentState(
                noteID: change.noteID,
                currentRelativePath: current.note.relativePath,
                status: status,
                observedRevision: current.document.fingerprint
            ))
        }
        return ResearchRecordChangeState(
            recordID: record.id,
            finalizedResultFingerprint: try record.finalizedResultFingerprint(),
            documents: documents
        )
    }

    func markCurrentNoteReviewed(
        noteID: UUID,
        expectedRevision: DocumentFingerprint,
        expectedRecordSourceManifestHash: String
    ) async throws -> PortableResearchNoteReview {
        try requireActive()
        guard let current = try await currentResearchSource(noteID: noteID) else {
            throw PortableResearchNoteReviewMutationError.sourceUnavailable
        }
        guard current.document.fingerprint == expectedRevision else {
            throw PortableResearchNoteReviewMutationError.sourceChanged
        }
        let review: PortableResearchNoteReview
        do {
            review = try await services.portableResearchRecordStore
                .markCurrentNoteReviewed(
                noteID: noteID,
                observedRevision: expectedRevision,
                expectedRecordSourceManifestHash: expectedRecordSourceManifestHash
            )
        } catch let storeError as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain(let reason) = storeError else {
                throw storeError
            }
            let records = try await services.portableResearchRecordStore.listing()
            let reviews = try await services.portableResearchRecordStore
                .noteReviewListing()
            let required = Set(records.records.compactMap { record ->
                PortableResearchNoteActivityReference? in
                guard record.confirmedChanges.contains(where: {
                    $0.noteID == noteID
                }) else { return nil }
                return PortableResearchNoteActivityReference(
                    recordID: record.id,
                    noteID: noteID
                )
            })
            if records.issues.isEmpty,
               reviews.issues.isEmpty,
               records.sourceManifestHash == expectedRecordSourceManifestHash,
               let reconciled = reviews.reviews.first(where: {
                   $0.noteID == noteID
                       && $0.observedRevision == expectedRevision
                       && required.isSubset(of: Set($0.coveredActivities))
               }) {
                review = reconciled
            } else {
                try? await refreshAfterResearchCommit("The uncertain Note Review")
                throw ScholiumApplicationError.operationCommitUncertain(
                    operation: "The Note Review",
                    reason: reason
                )
            }
        }
        guard let readback = try await currentResearchSource(noteID: noteID),
              readback.document.fingerprint == expectedRevision else {
            throw PortableResearchNoteReviewMutationError.sourceChanged
        }
        try await refreshAfterResearchCommit("The Note Review")
        return review
    }

    func undoResearchRecordChanges(
        recordID: UUID,
        selectedNoteIDs: Set<UUID>,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> ResearchRecordChangesUndoResult {
        try requireActive()
        let record = try await recoveryRecord(
            id: recordID,
            expectedResultFingerprint: expectedResultFingerprint
        )
        let changesByID = Dictionary(
            uniqueKeysWithValues: record.confirmedChanges.map { ($0.noteID, $0) }
        )
        guard !selectedNoteIDs.isEmpty,
              selectedNoteIDs.allSatisfy({ changesByID[$0] != nil }) else {
            throw ResearchRecordChangeRecoveryOperationError.invalidSelection
        }
        let execution: LocalResearchExecutionRecord
        do {
            execution = try await services.localResearchExecutionStore.record(id: recordID)
        } catch {
            throw ResearchRecordChangeRecoveryOperationError.executionUnavailable
        }
        guard execution.triptychID == record.triptychID,
              execution.id == record.id else {
            throw ResearchRecordChangeRecoveryOperationError.executionUnavailable
        }

        var plans: [ResearchRecordUndoPlan] = []
        for noteID in selectedNoteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let change = changesByID[noteID]!
            guard let startingRevision = change.startingRevision else {
                throw ResearchRecordChangeRecoveryOperationError
                    .createdNoteHasNoPreimage(noteID)
            }
            guard let entry = execution.boundedWriteSet.entries.first(where: {
                $0.noteID == noteID
            }), let firstCommitted = execution.documentWriteRecords
                .filter({
                    $0.target == entry.handle
                        && $0.actor == .agent
                        && $0.state == .committed
                })
                .min(by: { $0.startedAt < $1.startedAt }),
                firstCommitted.expectedRevision == startingRevision,
                firstCommitted.observedRevision == firstCommitted.intendedRevision else {
                throw ResearchRecordChangeRecoveryOperationError.checkpointMismatch(noteID)
            }
            guard let current = try await currentResearchSource(noteID: noteID) else {
                plans.append(.unavailable(noteID: noteID))
                continue
            }
            guard Self.vaultRole(entry.role)
                    == (try vault(id: current.note.vaultID)).role else {
                throw ResearchRecordChangeRecoveryOperationError.checkpointMismatch(noteID)
            }
            if current.document.fingerprint == startingRevision {
                plans.append(.alreadyRestored(
                    noteID: noteID,
                    revision: current.document.fingerprint
                ))
                continue
            }
            guard current.document.fingerprint == change.endingRevision else {
                plans.append(.conflict(
                    noteID: noteID,
                    revision: current.document.fingerprint
                ))
                continue
            }
            guard let checkpointID = firstCommitted.checkpointID else {
                throw ResearchRecordChangeRecoveryOperationError.checkpointMismatch(noteID)
            }
            let area = try checkpointArea(vaultID: current.note.vaultID)
            let checkpoint = try await services.checkpointStore.checkpoint(
                id: checkpointID
            )
            let sourceKey = TriptychCheckpointFileKey(
                area: area,
                relativePath: entry.note.relativePath
            )
            guard checkpoint.triptychID == record.triptychID,
                  checkpoint.kind == .researchContinuation,
                  let sourceRecord = checkpoint.files.first(where: {
                    $0.key == sourceKey
                  }),
                  sourceRecord.fingerprint == startingRevision else {
                throw ResearchRecordChangeRecoveryOperationError.checkpointMismatch(noteID)
            }
            let sourceBytes = try await services.checkpointStore.fileData(
                checkpointID: checkpoint.id,
                key: sourceKey
            )
            guard DocumentFingerprint(data: sourceBytes) == startingRevision else {
                throw ResearchRecordChangeRecoveryOperationError.checkpointMismatch(noteID)
            }
            plans.append(.restore(
                noteID: noteID,
                note: current.note,
                startingRevision: startingRevision,
                endingRevision: change.endingRevision,
                checkpointID: checkpoint.id,
                sourceKey: sourceKey,
                destinationKey: TriptychCheckpointFileKey(
                    area: area,
                    relativePath: current.note.relativePath
                )
            ))
        }

        var documents: [ResearchRecordChangeUndoDocumentResult] = []
        var sourceMutationAttempted = false
        for plan in plans {
            switch plan {
            case .unavailable(let noteID):
                documents.append(ResearchRecordChangeUndoDocumentResult(
                    noteID: noteID,
                    status: .unavailable,
                    observedRevision: nil
                ))
            case .alreadyRestored(let noteID, let revision):
                documents.append(ResearchRecordChangeUndoDocumentResult(
                    noteID: noteID,
                    status: .alreadyAtStartingRevision,
                    observedRevision: revision
                ))
            case .conflict(let noteID, let revision):
                documents.append(ResearchRecordChangeUndoDocumentResult(
                    noteID: noteID,
                    status: .conflict,
                    observedRevision: revision
                ))
            case .restore(
                let noteID,
                let note,
                let startingRevision,
                let endingRevision,
                let checkpointID,
                let sourceKey,
                let destinationKey
            ):
                sourceMutationAttempted = true
                do {
                    _ = try await services.checkpointStore.restoreResearchActionNoteFile(
                        checkpointID: checkpointID,
                        sourceKey: sourceKey,
                        destinationKey: destinationKey,
                        expectedDestinationRevision: endingRevision,
                        roots: services.roots,
                        repositories: repositoriesBySlot()
                    )
                    let readback = try await repository(vaultID: note.vaultID).load(
                        relativePath: note.relativePath
                    )
                    guard readback.fingerprint == startingRevision else {
                        throw VaultRepositoryError.readbackMismatch(
                            expected: startingRevision,
                            current: readback.fingerprint
                        )
                    }
                    documents.append(ResearchRecordChangeUndoDocumentResult(
                        noteID: noteID,
                        status: .restored,
                        observedRevision: startingRevision
                    ))
                } catch {
                    let observed = try? await repository(vaultID: note.vaultID)
                        .load(relativePath: note.relativePath).fingerprint
                    if observed == startingRevision {
                        documents.append(ResearchRecordChangeUndoDocumentResult(
                            noteID: noteID,
                            status: .restored,
                            observedRevision: startingRevision
                        ))
                    } else if let observed, observed != endingRevision {
                        documents.append(ResearchRecordChangeUndoDocumentResult(
                            noteID: noteID,
                            status: .conflict,
                            observedRevision: observed
                        ))
                    } else if let repositoryError = error as? VaultRepositoryError,
                              case .fileDoesNotExist = repositoryError {
                        documents.append(ResearchRecordChangeUndoDocumentResult(
                            noteID: noteID,
                            status: .unavailable,
                            observedRevision: nil
                        ))
                    } else if Self.isCommitUncertainRestoreError(error) {
                        documents.append(ResearchRecordChangeUndoDocumentResult(
                            noteID: noteID,
                            status: .commitUncertain,
                            observedRevision: observed
                        ))
                    } else {
                        documents.append(ResearchRecordChangeUndoDocumentResult(
                            noteID: noteID,
                            status: .unavailable,
                            observedRevision: observed
                        ))
                    }
                }
            }
        }

        let affectedVaultIDs = Set(plans.compactMap(\.affectedVaultID))
        if sourceMutationAttempted {
            try await refreshAfterCommittedOperation(
                "The Research Record source undo",
                publication: .researchRecords,
                affectedVaultIDs: affectedVaultIDs
            )
        }
        return ResearchRecordChangesUndoResult(record: record, documents: documents)
    }

    func setResearchRecordRecommendationDisposition(
        recordID: UUID,
        recommendationID: UUID,
        status: ResearchLiteratureRecommendationDispositionStatus
    ) async throws -> PortableResearchRecord {
        try requireActive()
        let updated = try await services.portableResearchRecordStore
            .setRecommendationDisposition(
                status,
                recommendationID: recommendationID,
                recordID: recordID
            )
        try await refreshAfterResearchCommit("The literature recommendation disposition")
        return updated
    }

    func setResearchRecordRecommendationNote(
        recordID: UUID,
        recommendationID: UUID,
        note: String?
    ) async throws -> PortableResearchRecord {
        try requireActive()
        let updated = try await services.portableResearchRecordStore
            .setRecommendationNote(
                note,
                recommendationID: recommendationID,
                recordID: recordID
            )
        try await refreshAfterResearchCommit("The literature recommendation note")
        return updated
    }

    func deleteResearchRecordPermanently(id: UUID) async throws {
        try requireActive()
        _ = try await services.portableResearchRecordStore.deletePermanently(id: id)
        try await refreshAfterResearchCommit("The permanent Research Record deletion")
    }

    func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ExactSourceComparison {
        try requireActive()
        let record = try await services.portableResearchRecordStore.record(id: recordID)
        guard let change = record.confirmedChanges.first(where: {
            $0.noteID == noteID
        }), let participant = record.participatingNotes.first(where: {
            $0.noteID == change.noteID
        }) else {
            throw ResearchRecordChangeRecoveryOperationError.confirmedChangeNotFound(noteID)
        }
        guard let startingRevision = change.startingRevision else {
            throw ResearchRecordChangeRecoveryOperationError
                .createdNoteHasNoPreimage(noteID)
        }
        let startingData = try await exactResearchRecordRevision(
            startingRevision,
            participant: participant
        )
        let endingData = try await exactResearchRecordRevision(
            change.endingRevision,
            participant: participant
        )
        let comparisonTask = Task.detached(priority: .userInitiated) {
            try ExactSourceComparisonBuilder.build(
                startingData: startingData,
                endingData: endingData,
                startingRevision: startingRevision,
                endingRevision: change.endingRevision
            )
        }
        return try await withTaskCancellationHandler {
            try await comparisonTask.value
        } onCancel: {
            comparisonTask.cancel()
        }
    }

    // MARK: Checkpoints and Recovery

    func createCheckpoint(
        name: String,
        kind: TriptychCheckpointKind
    ) async throws -> TriptychCheckpoint {
        try requireActive()
        let checkpoint = try await services.checkpointStore.create(
            name: name,
            kind: kind,
            roots: services.roots
        )
        try await refreshAfterResearchCommit("The checkpoint")
        return checkpoint
    }

    func prepareCheckpointsLocation() async throws -> URL {
        try requireActive()
        return try await services.checkpointStore.prepareStorageLocation()
    }

    func checkpoints() async throws -> TriptychCheckpointListing {
        try requireActive()
        return await services.checkpointStore.listing()
    }

    func noteCheckpoints(
        for noteID: VaultQualifiedNoteID
    ) async throws -> [TriptychCheckpoint] {
        try requireActive()
        let (stableID, area) = try checkpointNoteContext(noteID)
        var matches: [TriptychCheckpoint] = []
        for checkpoint in await services.checkpointStore.listing().checkpoints {
            if try await checkpointNoteKey(
                checkpoint: checkpoint,
                currentNote: noteID,
                stableID: stableID,
                area: area
            ) != nil {
                matches.append(checkpoint)
            }
        }
        return matches
    }

    func checkpointNoteContent(
        _ checkpointID: UUID,
        note noteID: VaultQualifiedNoteID
    ) async throws -> String {
        try requireActive()
        let (stableID, area) = try checkpointNoteContext(noteID)
        let checkpoint = try await services.checkpointStore.checkpoint(id: checkpointID)
        guard let key = try await checkpointNoteKey(
            checkpoint: checkpoint,
            currentNote: noteID,
            stableID: stableID,
            area: area
        ) else {
            throw TriptychCheckpointError.invalidRelativePath(noteID.relativePath)
        }
        let data = try await services.checkpointStore.fileData(
            checkpointID: checkpointID,
            key: key
        )
        guard let source = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return source
    }

    func checkpointComparison(
        _ checkpointID: UUID
    ) async throws -> [TriptychCheckpointChange] {
        try requireActive()
        return try await services.checkpointStore.comparison(
            checkpointID: checkpointID,
            roots: services.roots
        )
    }

    func restoreNote(
        _ noteID: VaultQualifiedNoteID,
        from checkpointID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychCheckpointRestoreResult {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        let area = try checkpointArea(vaultID: noteID.vaultID)
        let checkpoint = try await services.checkpointStore.checkpoint(id: checkpointID)
        guard let sourceKey = try await checkpointNoteKey(
            checkpoint: checkpoint,
            currentNote: noteID,
            stableID: context.identity.id,
            area: area
        ) else {
            throw TriptychCheckpointError.invalidRelativePath(noteID.relativePath)
        }
        let destinationKey = TriptychCheckpointFileKey(
            area: area,
            relativePath: noteID.relativePath
        )
        let result = try await services.checkpointStore.restoreNoteFile(
            checkpointID: checkpointID,
            sourceKey: sourceKey,
            destinationKey: destinationKey,
            expectedDestinationRevision: expectedRevision,
            roots: services.roots,
            repositories: repositoriesBySlot()
        )
        try await refreshAfterCommittedOperation(
            "The checkpoint restore",
            publication: .sourceCommitted(
                noteID,
                .checkpointRestore(checkpointID: checkpointID)
            ),
            affectedVaultIDs: [noteID.vaultID]
        )
        return result
    }

    func restoreCheckpoint(
        _ checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection
    ) async throws -> TriptychCheckpointRestoreResult {
        try requireActive()
        let result = try await services.checkpointStore.restore(
            checkpointID: checkpointID,
            selection: selection,
            roots: services.roots,
            repositories: repositoriesBySlot()
        )
        try await refreshAfterCommittedOperation(
            "The checkpoint restore",
            publication: .explicit,
            affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
        )
        return result
    }

    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try requireActive()
        return try await services.transactionRecoveryStore.pending()
    }

    func resolveRecoveryRecord(_ id: UUID) async throws {
        try requireActive()
        let records = try await services.transactionRecoveryStore.pending()
        guard let record = records.first(where: { $0.id == id }),
              record.triptychID == self.id else {
            throw TriptychTransactionError.invalidPlan(
                "The selected recovery record is unavailable for this Triptych."
            )
        }
        if let managedCreation = record.managedCreation {
            guard record.researchWrite == nil else {
                throw TriptychTransactionError.invalidPlan(
                    "The recovery record has competing creation owners."
                )
            }
            let lease = try await beginResearchControlledSourceObservation()
            var ownsLease = true
            defer {
                if ownsLease { endResearchControlledSourceObservation(lease) }
            }
            let note = try await reconcileManagedCreationRecovery(
                record,
                reference: managedCreation
            )
            endResearchControlledSourceObservation(lease)
            ownsLease = false
            try await refreshAfterResearchCommit(
                "The managed-note creation recovery"
            )
            _ = note
            return
        }
        guard let link = record.researchWrite else {
            try await services.transactionRecoveryStore.resolve(record)
            try await refreshAfterResearchCommit("The recovery-record resolution")
            return
        }
        let lease = try await beginResearchControlledSourceObservation()
        var ownsLease = true
        defer {
            if ownsLease { endResearchControlledSourceObservation(lease) }
        }
        let resolution = try await reconcileResearchWriteRecovery(record, link: link)
        endResearchControlledSourceObservation(lease)
        ownsLease = false
        if resolution.didReplaceSource {
            try await refreshAfterCommittedOperation(
                "The Agent write recovery",
                publication: .sourceCommitted(resolution.note, .save),
                affectedVaultIDs: [resolution.note.vaultID]
            )
        }
        try await refreshAfterResearchCommit("The recovery-record resolution")
    }

    private func reconcileResearchWriteRecovery(
        _ record: TriptychMutationRecoveryRecord,
        link: ResearchWriteRecoveryReference
    ) async throws -> (note: VaultQualifiedNoteID, didReplaceSource: Bool) {
        if record.operation == .noteCreation {
            return try await reconcileResearchCreationRecovery(record, link: link)
        }
        guard let sourceRecoveryID = link.sourceRecoveryID else {
            throw TriptychTransactionError.invalidPlan(
                "The Agent save recovery record has no interrupted-save identity."
            )
        }
        guard record.operation == .noteSave,
              record.files.count == 1,
              let file = record.files.first,
              file.role == .savedNote,
              file.vaultID == sourceRecoveryID.vaultID,
              let beforeRevision = file.beforeRevision,
              let intendedRevision = file.intendedRevision else {
            throw TriptychTransactionError.invalidPlan(
                "The Agent write recovery record does not describe one exact source transaction."
            )
        }
        let execution = try await services.localResearchExecutionStore.record(
            id: link.runID
        )
        guard execution.triptychID == self.id,
              let write = execution.documentWriteRecords.first(where: {
                  $0.id == link.operationID
                      && $0.runID == link.runID
                      && $0.target == link.target
                      && $0.recoveryRecordID == record.id
              }),
              let entry = execution.boundedWriteSet.entry(handle: link.target),
              entry.note.vaultID == file.vaultID,
              entry.note.relativePath == file.path,
              write.expectedRevision == beforeRevision,
              write.intendedRevision == intendedRevision,
              sourceRecoveryID.vaultID == entry.note.vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "The Agent write recovery record no longer matches its Run target."
            )
        }
        let repository = try repository(vaultID: entry.note.vaultID)
        let sourceRecovery = try await repository.interruptedSaveRecoveries()
            .first(where: { $0.id == sourceRecoveryID })
        if sourceRecovery == nil,
           ![.committed, .abandoned].contains(write.state) {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        if let sourceRecovery,
           sourceRecovery.relativePath != entry.note.relativePath
                || sourceRecovery.expectedRevision != write.expectedRevision
                || sourceRecovery.candidateRevision != write.intendedRevision {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let current = try await repository.load(relativePath: entry.note.relativePath)
        guard let identity = try await services.controlStore.identityRecord(
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        ), identity.id == entry.noteID,
           WorkspaceDocumentLifecycle(
            relativePath: entry.note.relativePath
           ) == .active,
           Self.vaultRole(entry.role)
            == (try vault(id: entry.note.vaultID).role) else {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        guard current.fingerprint == write.expectedRevision
                || current.fingerprint == write.intendedRevision else {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let terminal = [.committed, .abandoned].contains(write.state)
        if terminal {
            guard write.observedRevision == current.fingerprint else {
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
        } else {
            _ = try await services.localResearchExecutionStore
                .reconcileDocumentWriteRecovery(
                    runID: link.runID,
                    operationID: link.operationID,
                    recoveryRecordID: record.id,
                    observedRevision: current.fingerprint,
                    reconciledAt: Date()
                )
        }
        if sourceRecovery == nil {
            // The local Run was reconciled before an earlier process stopped;
            // the source transaction has already been cleaned up.
        } else if current.fingerprint == write.expectedRevision {
            try await repository.abandonInterruptedSaveRecovery(sourceRecovery!)
        } else {
            _ = try await repository.restoreInterruptedSaveRecovery(
                sourceRecovery!
            )
        }
        try await services.transactionRecoveryStore.resolve(record)
        return (
            note: entry.note,
            didReplaceSource: !terminal
                && current.fingerprint == write.intendedRevision
        )
    }

    private func reconcileResearchCreationRecovery(
        _ record: TriptychMutationRecoveryRecord,
        link: ResearchWriteRecoveryReference
    ) async throws -> (note: VaultQualifiedNoteID, didReplaceSource: Bool) {
        guard link.sourceRecoveryID == nil,
              record.files.count == 1,
              let file = record.files.first,
              file.role == .createdNote,
              file.beforeRevision == nil,
              let intendedRevision = file.intendedRevision else {
            throw TriptychTransactionError.invalidPlan(
                "The Agent creation recovery record does not describe one exact new Note."
            )
        }
        let execution = try await services.localResearchExecutionStore.record(
            id: link.runID
        )
        guard execution.triptychID == self.id,
              let write = execution.documentWriteRecords.first(where: {
                  $0.id == link.operationID
                      && $0.runID == link.runID
                      && $0.target == link.target
                      && $0.operation == .createNote
              }),
              let entry = execution.boundedWriteSet.entry(handle: link.target),
              entry.note.vaultID == file.vaultID,
              entry.note.relativePath == file.path,
              write.expectedRevision == nil,
              write.checkpointID == nil,
              write.intendedRevision == intendedRevision else {
            throw TriptychTransactionError.invalidPlan(
                "The Agent creation recovery no longer matches its Run target."
            )
        }
        if [.committed, .abandoned].contains(write.state) {
            guard write.recoveryRecordID == record.id else {
                throw TriptychTransactionError.invalidPlan(
                    "The completed Agent creation does not own this recovery record."
                )
            }
            try await services.transactionRecoveryStore.resolve(record)
            return (note: entry.note, didReplaceSource: false)
        }
        guard (write.state == .recoveryRequired
                && write.recoveryRecordID == record.id)
                || (write.state == .writing
                    && write.recoveryRecordID == nil) else {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let repository = try repository(vaultID: entry.note.vaultID)
        let source: NoteDocument?
        do {
            source = try await repository.load(
                relativePath: entry.note.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            source = nil
        } catch {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }

        if let barrier = researchCreationRecoveryObservationBarrierForTesting {
            await barrier()
        }

        guard source == nil || source?.fingerprint == intendedRevision else {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let identityReconciliation: ManagedCreationIdentityReconciliation
        do {
            identityReconciliation = try await services.controlStore
                .reconcileManagedCreationIdentity(
                vaultID: entry.note.vaultID,
                relativePath: entry.note.relativePath,
                intendedRevision: intendedRevision,
                reservedIdentityID: entry.noteID,
                sourceIsPresent: source != nil
            )
        } catch {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let didEstablishCreatedNote = source != nil
        let finalSource: NoteDocument?
        do {
            finalSource = try await repository.load(
                relativePath: entry.note.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            finalSource = nil
        } catch {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        let finalIdentity: NoteIdentityRecord?
        do {
            finalIdentity = try await services.controlStore.identityRecord(
                vaultID: entry.note.vaultID,
                relativePath: entry.note.relativePath
            )
        } catch {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        if let finalSource {
            guard finalSource.fingerprint == intendedRevision,
                  finalIdentity?.id == entry.noteID,
                  finalIdentity?.fingerprint == intendedRevision else {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: entry.note.vaultID,
                    relativePath: entry.note.relativePath
                )
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
        } else {
            guard finalIdentity == nil else {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: entry.note.vaultID,
                    relativePath: entry.note.relativePath
                )
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
        }
        _ = try await services.localResearchExecutionStore
            .reconcileDocumentWriteRecovery(
                runID: link.runID,
                operationID: link.operationID,
                recoveryRecordID: record.id,
                observedRevision: finalSource?.fingerprint,
                reconciledAt: Date()
            )
        try await services.transactionRecoveryStore.resolve(record)
        return (
            note: entry.note,
            didReplaceSource: finalSource != nil && didEstablishCreatedNote
        )
    }

    private func reconcileManagedCreationRecovery(
        _ record: TriptychMutationRecoveryRecord,
        reference: ManagedCreationRecoveryReference
    ) async throws -> VaultQualifiedNoteID {
        guard record.operation == .noteCreation,
              record.triptychID == id,
              record.files.count == 1,
              let file = record.files.first,
              file.role == .createdNote,
              file.beforeRevision == nil,
              file.vaultID == reference.target.vaultID,
              file.path == reference.target.relativePath,
              let intendedRevision = file.intendedRevision else {
            throw TriptychTransactionError.invalidPlan(
                "The managed creation recovery does not describe one exact new Note."
            )
        }
        let repository = try repository(vaultID: reference.target.vaultID)
        let source: NoteDocument?
        do {
            source = try await repository.load(
                relativePath: reference.target.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            source = nil
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        guard source == nil || source?.fingerprint == intendedRevision else {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        let identityReconciliation: ManagedCreationIdentityReconciliation
        do {
            identityReconciliation = try await services.controlStore
                .reconcileManagedCreationIdentity(
                vaultID: reference.target.vaultID,
                relativePath: reference.target.relativePath,
                intendedRevision: intendedRevision,
                reservedIdentityID: reference.reservedIdentityID,
                sourceIsPresent: source != nil
            )
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }

        let finalSource: NoteDocument?
        do {
            finalSource = try await repository.load(
                relativePath: reference.target.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            finalSource = nil
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        let finalPathIdentity: NoteIdentityRecord?
        let finalReservedIdentity: NoteIdentityRecord?
        do {
            finalPathIdentity = try await services.controlStore.identityRecord(
                vaultID: reference.target.vaultID,
                relativePath: reference.target.relativePath
            )
            finalReservedIdentity = try await services.controlStore.identityRecord(
                id: reference.reservedIdentityID
            )
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        if let finalSource {
            guard finalSource.fingerprint == intendedRevision,
                  finalPathIdentity?.id == reference.reservedIdentityID,
                  finalPathIdentity?.fingerprint == intendedRevision,
                  finalReservedIdentity == finalPathIdentity else {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
        } else {
            guard finalPathIdentity == nil,
                  finalReservedIdentity == nil else {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
        }
        try await services.transactionRecoveryStore.resolve(record)
        return reference.target
    }

    // MARK: Critique

    func critique(
        critiqueRelativePath: String
    ) async throws -> CritiqueAssociation? {
        try requireActive()
        if let issue = await services.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        return await services.critiqueRegistry.association(
            critiqueRelativePath: critiqueRelativePath
        )
    }

    func setCritiqueFindingDisposition(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String?,
        noTextChangeRationale: String?,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let context = try await researchContext(
            for: workNote,
            expectedRevision: expectedRevision,
            permits: { $0.allowsCritique },
            unavailable: { ResearchOperationError.critiqueUnavailable($0) }
        )
        guard !CritiquePlacement.isManagedCritiquePath(workNote.relativePath) else {
            throw ResearchOperationError.critiqueTargetMustBeOrdinaryWork(
                workNote.relativePath
            )
        }
        if let issue = await services.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        guard let current = await services.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await services.critiqueRegistry.setFindingDisposition(
            roundID: roundID,
            findingID: findingID,
            decision: decision,
            currentWorkRevision: context.document.fingerprint,
            rationale: rationale,
            noTextChangeRationale: noTextChangeRationale
        )
        try await refreshAfterResearchCommit("The Critique finding disposition")
        return association
    }

    func completeCritiqueRound(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let context = try await researchContext(
            for: workNote,
            expectedRevision: expectedRevision,
            permits: { $0.allowsCritique },
            unavailable: { ResearchOperationError.critiqueUnavailable($0) }
        )
        guard !CritiquePlacement.isManagedCritiquePath(workNote.relativePath) else {
            throw ResearchOperationError.critiqueTargetMustBeOrdinaryWork(
                workNote.relativePath
            )
        }
        guard let current = await services.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await services.critiqueRegistry.completeRound(
            roundID: roundID
        )
        guard association.rounds.contains(where: {
            $0.id == roundID && $0.completedAt != nil
        }) else {
            throw CritiqueRegistryError.incompleteDispositions(roundID)
        }
        try await refreshAfterResearchCommit("The completed Critique round")
        return association
    }


    // MARK: Helpers

    private func recoveryRecord(
        id: UUID,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> PortableResearchRecord {
        let record: PortableResearchRecord
        do {
            record = try await services.portableResearchRecordStore.record(id: id)
        } catch ResearchRecordStoreV1Error.recordNotFound(_),
                ResearchRecordStoreV1Error.recordPermanentlyDeleted(_) {
            throw ResearchRecordChangeRecoveryError.recordUnavailable
        }
        guard try record.finalizedResultFingerprint() == expectedResultFingerprint else {
            throw ResearchRecordChangeRecoveryError.finalizedResultChanged
        }
        guard record.kind == .action else {
            throw ResearchRecordChangeRecoveryOperationError.invalidSelection
        }
        return record
    }

    private func currentResearchSource(
        noteID: UUID
    ) async throws -> CurrentResearchSource? {
        guard let controlled = try await services.controlStore.identityRecord(id: noteID) else {
            return nil
        }
        let note = VaultQualifiedNoteID(
            vaultID: controlled.vaultID,
            relativePath: controlled.relativePath
        )
        guard !note.relativePath.hasPrefix("Set Aside/"),
              !note.relativePath.hasPrefix("Trash/") else {
            return nil
        }
        let document: NoteDocument
        do {
            document = try await repository(vaultID: note.vaultID).load(
                relativePath: note.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            return nil
        }
        let identity = try await resolvedIdentity(
            for: note,
            expectedRevision: document.fingerprint
        )
        guard identity.id == noteID else {
            throw NoteIdentityRecoveryError.targetIdentityChanged(
                note.relativePath
            )
        }
        return CurrentResearchSource(note: note, document: document)
    }

    private static func vaultRole(_ role: ResearchActionTargetRole) -> VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    private static func isCommitUncertainRestoreError(_ error: Error) -> Bool {
        guard let repositoryError = error as? VaultRepositoryError else { return false }
        switch repositoryError {
        case .commitUncertain, .readbackMismatch:
            return true
        default:
            return false
        }
    }

    private struct ResearchContext {
        let document: NoteDocument
        let identity: NoteIdentityRecord
        let vault: RegisteredVault
    }

    private func researchContext(
        for noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        permits: (VaultRole) -> Bool,
        unavailable: (VaultRole) -> Error
    ) async throws -> ResearchContext {
        try requireActive()
        let registeredVault = try vault(id: noteID.vaultID)
        guard permits(registeredVault.role) else {
            throw unavailable(registeredVault.role)
        }
        guard let snapshot = currentSnapshot.document(id: noteID),
              snapshot.lifecycle == .active else {
            throw ResearchOperationError.noteUnavailable(noteID)
        }
        let identity = try await resolvedIdentity(
            for: noteID,
            expectedRevision: expectedRevision
        )
        let document = try await repository(vaultID: noteID.vaultID).load(
            relativePath: noteID.relativePath
        )
        guard document.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: document.fingerprint
            )
        }
        return ResearchContext(
            document: document,
            identity: identity,
            vault: registeredVault
        )
    }

    private func portableDiscussionParticipant(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        title: String,
        fingerprint: DocumentFingerprint
    ) throws -> PortableResearchNoteRevision {
        try PortableResearchNoteRevision(
            noteID: noteID,
            note: note,
            role: actionRole(role),
            title: title,
            startingRevision: fingerprint,
            endingRevision: fingerprint
        )
    }

    private func currentDiscussionParticipants(
        _ discussion: PortableResearchDiscussion
    ) async throws -> [PortableResearchNoteRevision] {
        var result: [PortableResearchNoteRevision] = []
        for participant in discussion.participatingNotes {
            guard let current = currentSnapshot.vaults.lazy
                .flatMap(\.documents)
                .first(where: { snapshot in
                    snapshot.lifecycle == .active
                        && snapshot.stableIdentity.resolvedID == participant.noteID
                }) else {
                throw ResearchOperationError.noteUnavailable(participant.note)
            }
            let document = try await repository(vaultID: current.id.vaultID).load(
                relativePath: current.id.relativePath
            )
            result.append(try PortableResearchNoteRevision(
                noteID: participant.noteID,
                note: participant.note,
                role: participant.role,
                title: participant.title,
                startingRevision: participant.startingRevision,
                endingRevision: document.fingerprint
            ))
        }
        return result
    }

    private func actionRole(
        _ role: ResearchFunctionTargetRole
    ) -> ResearchActionTargetRole {
        switch role {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }

    private func refreshAfterResearchCommit(_ operation: String) async throws {
        try await refreshAfterCommittedOperation(
            operation,
            publication: .researchRecords
        )
    }

    private func researcherResponseMutationError(
        _ error: Error,
        operation: String
    ) -> Error {
        guard let storeError = error as? ResearchRecordStoreV1Error else {
            return error
        }
        switch storeError {
        case .replacementCommitUncertain(let reason):
            return ScholiumApplicationError.operationCommitUncertain(
                operation: operation,
                reason: reason
            )
        case .recordNotFound, .recordPermanentlyDeleted:
            return PortableResearcherResponseMutationError.recordUnavailable
        default:
            return error
        }
    }

    private func repositoriesBySlot() -> [WorkspaceVaultSlot: VaultRepository] {
        Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.compactMap { slot in
            guard let vault = assignment.vault(for: slot),
                  let repository = services.repositories[vault.id] else { return nil }
            return (slot, repository)
        })
    }

    private func checkpointNoteContext(
        _ noteID: VaultQualifiedNoteID
    ) throws -> (stableID: UUID, area: TriptychCheckpointArea) {
        guard let note = currentSnapshot.document(id: noteID),
              note.lifecycle == .active,
              case .resolved(let stableID) = note.stableIdentity else {
            throw ResearchOperationError.noteUnavailable(noteID)
        }
        return (stableID, try checkpointArea(vaultID: noteID.vaultID))
    }

    private func exactResearchRecordRevision(
        _ revision: DocumentFingerprint,
        participant: PortableResearchNoteRevision
    ) async throws -> Data {
        let current = currentSnapshot.vaults.lazy.flatMap(\.documents).first {
            $0.stableIdentity.resolvedID == participant.noteID
                && $0.fingerprint == revision
        }
        if let current { return current.document.sourceBytes }

        var repositories: [(VaultRepository, [String])] = []
        if let repository = services.repositories[participant.note.vaultID] {
            repositories.append((repository, [participant.note.relativePath]))
        }
        if let current = currentSnapshot.vaults.lazy.flatMap(\.documents).first(where: {
            $0.stableIdentity.resolvedID == participant.noteID
        }), let repository = services.repositories[current.id.vaultID] {
            if let index = repositories.firstIndex(where: { $0.0 === repository }) {
                repositories[index].1.append(current.id.relativePath)
            } else {
                repositories.append((repository, [current.id.relativePath]))
            }
        }
        for (repository, paths) in repositories {
            try Task.checkCancellation()
            for path in Set(paths) {
                for entry in await repository.recoveryEntries(relativePath: path)
                    where entry.fingerprint == revision {
                    try Task.checkCancellation()
                    let data = try await repository.recoveryData(entryID: entry.id)
                    if DocumentFingerprint(data: data) == revision { return data }
                }
            }
        }

        let area = try checkpointArea(vaultID: participant.note.vaultID)
        for checkpoint in await services.checkpointStore.listing().checkpoints {
            try Task.checkCancellation()
            var keys: [TriptychCheckpointFileKey] = []
            if let identityKey = try await services.checkpointStore.noteFileKey(
                checkpointID: checkpoint.id,
                noteID: participant.noteID,
                area: area
            ) {
                keys.append(identityKey)
            }
            keys.append(TriptychCheckpointFileKey(
                area: area,
                relativePath: participant.note.relativePath
            ))
            if let current = currentSnapshot.vaults.lazy.flatMap(\.documents).first(where: {
                $0.stableIdentity.resolvedID == participant.noteID
            }) {
                keys.append(TriptychCheckpointFileKey(
                    area: area,
                    relativePath: current.id.relativePath
                ))
            }
            for key in Set(keys) where checkpoint.files.contains(where: {
                $0.key == key && $0.fingerprint == revision
            }) {
                let data = try await services.checkpointStore.fileData(
                    checkpointID: checkpoint.id,
                    key: key
                )
                if DocumentFingerprint(data: data) == revision { return data }
            }
        }
        throw ExactSourceComparisonError.exactRevisionUnavailable(revision)
    }

    private func checkpointNoteKey(
        checkpoint: TriptychCheckpoint,
        currentNote: VaultQualifiedNoteID,
        stableID: UUID,
        area: TriptychCheckpointArea
    ) async throws -> TriptychCheckpointFileKey? {
        let direct = TriptychCheckpointFileKey(
            area: area,
            relativePath: currentNote.relativePath
        )
        let identities = TriptychCheckpointFileKey(
            area: .control,
            relativePath: "identities.json"
        )
        let hasIdentitySnapshot = checkpoint.files.contains { $0.key == identities }
        if !hasIdentitySnapshot {
            return checkpoint.files.contains { $0.key == direct } ? direct : nil
        }
        return try await services.checkpointStore.noteFileKey(
            checkpointID: checkpoint.id,
            noteID: stableID,
            area: area
        )
    }

    private func availableCritiquePath(
        base: String,
        repository: VaultRepository
    ) async throws -> String {
        let existing = Set(try await repository.markdownRelativePaths(
            includeLifecycle: true
        ))
        let first = "Critiques/\(base) Critique.md"
        if !existing.contains(first) { return first }
        var index = 2
        while existing.contains("Critiques/\(base) Critique \(index).md") {
            index += 1
        }
        return "Critiques/\(base) Critique \(index).md"
    }
}
