import ScholiumContracts
import Foundation
import ScholiumCore

struct WorkspaceResearchOperationsDependencies: Sendable {
    let portableResearchRecordStore: PortableResearchRecordStore
    let controlStore: TriptychControlStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let localResearchExecutionStore: LocalResearchExecutionStore
    let critiqueRegistry: CritiqueRegistry
    let agentChangeEvidenceStore: AgentChangeEvidenceStore
}

extension WorkspaceServices {
    var researchWorkspaceDependencies:
        WorkspaceResearchOperationsDependencies {
        WorkspaceResearchOperationsDependencies(
            portableResearchRecordStore: portableResearchRecordStore,
            controlStore: controlStore,
            transactionRecoveryStore: transactionRecoveryStore,
            localResearchExecutionStore: localResearchExecutionStore,
            critiqueRegistry: critiqueRegistry,
            agentChangeEvidenceStore: agentChangeEvidenceStore
        )
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
        startingData: Data
    )

    var affectedVaultID: UUID? {
        guard case .restore(_, let note, _, _, _) = self else { return nil }
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
        snapshot: ResearchActionRunSnapshot,
        triptychID: UUID
    ) throws -> PortableResearchDiscussion {
        let action = snapshot.actionSnapshot
        guard action.actionID == .discuss else {
            throw ResearchActionRunContractError.invalidCompletion(
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
                throw ResearchActionRunContractError.invalidCompletion(
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
            action: try ResearchActionRecordIdentity(snapshot: action),
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
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPostCommitFaultForTesting(nil)
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPreCommitFaultForTesting { _ in
                    throw InjectedResearchSettlementReplacementFault.beforeRename
                }
        case .afterRename:
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPreCommitFaultForTesting(nil)
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPostCommitFaultForTesting { _ in
                    throw InjectedResearchSettlementReplacementFault.afterRename
                }
        case nil:
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPreCommitFaultForTesting(nil)
            await researchWorkspaceDependencies.portableResearchRecordStore
                .setPostCommitFaultForTesting(nil)
        }
    }

    @discardableResult
    func writePortableSettlementForTesting(
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        try await researchWorkspaceDependencies.portableResearchRecordStore.settle(
            noteID: noteID,
            fingerprint: fingerprint,
            rationale: rationale
        )
    }

    func portableSettlementProjectionForTesting() async throws
        -> PortableSettlementProjectionForTesting {
        let listing = try await researchWorkspaceDependencies.portableResearchRecordStore
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
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        let settlement = try await researchWorkspaceDependencies.portableResearchRecordStore.settle(
            noteID: context.identity.id,
            fingerprint: expectedRevision,
            rationale: rationale
        )
        try await refreshAfterResearchCommit("The settlement")
        return settlement
    }

    func activeDiscussions(noteID: UUID?) async throws -> [PortableResearchDiscussion] {
        try requireActive()
        let listing = try await researchWorkspaceDependencies.portableResearchRecordStore.activeDiscussions(
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
        return try await researchWorkspaceDependencies.portableResearchRecordStore.activeDiscussion(id: id)
    }

    func activeDiscussionIfPresent(id: UUID) async throws -> PortableResearchDiscussion? {
        try requireActive()
        return try await researchWorkspaceDependencies.portableResearchRecordStore.activeDiscussionIfPresent(id: id)
    }

    func createDiscussion(
        target: ResearchActionNoteSnapshot,
        focalNotes: [ResearchActionNoteSnapshot],
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
        target: ResearchActionNoteSnapshot,
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
        target: ResearchActionNoteSnapshot,
        focalNotes: [ResearchActionNoteSnapshot],
        passage: CommentAnchor?,
        lineReference: ResearchLineReference?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        let targetContext = try await researchContext(
            for: target.note,
            expectedRevision: target.fingerprint,
            permits: { ResearchActionTargetRole(vaultRole: $0) == target.role },
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
                permits: { ResearchActionTargetRole(vaultRole: $0) == focal.role },
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
            triptychID: self.id,
            primaryNoteID: target.noteID,
            participatingNotes: participants,
            statements: [statement],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let stored: PortableResearchDiscussion
        do {
            stored = try await researchWorkspaceDependencies.portableResearchRecordStore
                .createActiveDiscussion(discussion)
        } catch ResearchRecordStoreV1Error.activeDiscussionAlreadyExists(
            primaryNoteID: _,
            discussionID: let discussionID
        ) {
            let existing = try await researchWorkspaceDependencies.portableResearchRecordStore.activeDiscussion(
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

    func replyToDiscussionAndFinish(
        discussionID: UUID,
        statementID: UUID,
        attribution: String,
        text: String
    ) async throws -> PortableResearchRecord {
        try requireActive()
        let active = try await researchWorkspaceDependencies
            .portableResearchRecordStore.activeDiscussion(id: discussionID)
        let statement = try PortableResearchStatement(
            id: statementID,
            author: .agent,
            kind: .discussionTurn,
            attribution: attribution,
            text: text,
            createdAt: max(Date(), active.updatedAt)
        )
        if let local = try await researchWorkspaceDependencies
            .localResearchExecutionStore.recordIfPresent(id: discussionID) {
            guard local.snapshot.request.actionID == .discuss else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(
                    discussionID
                )
            }
            let commit = try await researchActionRunCoordinator
                .finishProtectedDiscussion(
                    runID: discussionID,
                    appendingAgentStatement: statement,
                    host: self
                )
            return commit.record
        }
        let record = try await finishDiscussion(
            discussionID: discussionID,
            appendingAgentStatement: statement
        ).record
        try await refreshAfterResearchCommit("The Agent Discussion reply")
        return record
    }

    private func appendDiscussionStatement(
        _ statement: PortableResearchStatement,
        to discussion: PortableResearchDiscussion
    ) async throws -> PortableResearchDiscussion {
        if let passage = statement.passage {
            guard let current = currentSnapshot.vaults.lazy
                .flatMap(\.documents)
                .first(where: { snapshot in
                    snapshot.stableIdentity.resolvedID == discussion.primaryNoteID
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
        return try await researchWorkspaceDependencies.portableResearchRecordStore.appendDiscussionStatement(
            statement,
            to: discussion.id,
            at: statement.createdAt
        )
    }

    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord {
        try requireActive()
        if let local = try await researchWorkspaceDependencies.localResearchExecutionStore.recordIfPresent(
            id: discussionID
        ) {
            guard local.snapshot.request.actionID == .discuss else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(discussionID)
            }
            _ = try await validatedDiscussionStatements(snapshot: local.snapshot)
        }
        let discussion: PortableResearchDiscussion
        do {
            discussion = try await researchWorkspaceDependencies.portableResearchRecordStore.activeDiscussion(
                id: discussionID
            )
        } catch ResearchRecordStoreV1Error.discussionNotFound(_) {
            let existing = try await researchWorkspaceDependencies.portableResearchRecordStore.record(
                id: discussionID
            )
            guard existing.kind == .discussion else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(discussionID)
            }
            return existing
        }
        let participants = try await currentDiscussionParticipants(discussion)
        let stored = try await researchWorkspaceDependencies.portableResearchRecordStore.finishDiscussion(
            id: discussionID,
            participatingNotes: participants
        )
        try await refreshAfterResearchCommit("The Discussion finish")
        return stored
    }

    func finishDiscussion(
        discussionID: UUID,
        appendingAgentStatement statement: PortableResearchStatement
    ) async throws -> (
        record: PortableResearchRecord,
        replyWasAlreadyRecorded: Bool
    ) {
        try requireActive()
        let participants: [PortableResearchNoteRevision]
        if let discussion = try await researchWorkspaceDependencies
            .portableResearchRecordStore.activeDiscussionIfPresent(id: discussionID) {
            participants = try await currentDiscussionParticipants(discussion)
        } else {
            // Exact completion retries are validated against the already
            // finished Record by the portable store; no current source read is
            // allowed to rewrite its frozen participant revisions.
            participants = []
        }
        let commit = try await researchWorkspaceDependencies.portableResearchRecordStore
            .finishDiscussion(
                id: discussionID,
                appendingAgentStatement: statement,
                participatingNotes: participants,
                finishedAt: max(Date(), statement.createdAt)
            )
        return commit
    }

    func validatedDiscussionStatements(
        snapshot: ResearchActionRunSnapshot
    ) async throws -> [PortableResearchStatement] {
        let expected = try ResearchDiscussionFactory.make(
            snapshot: snapshot,
            triptychID: self.id
        )
        if let active = try await researchWorkspaceDependencies.portableResearchRecordStore
            .activeDiscussionIfPresent(id: snapshot.runID) {
            guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "The portable Discussion no longer matches its frozen Action run."
                )
            }
            return active.statements
        }
        do {
            let finished = try await researchWorkspaceDependencies.portableResearchRecordStore.record(
                id: snapshot.runID
            )
            guard ResearchDiscussionFactory.finishedMatches(finished, expected: expected) else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "The finished Discussion no longer matches its frozen Action run."
                )
            }
            return finished.statements
        } catch ResearchRecordStoreV1Error.recordNotFound(_) {
            throw ResearchActionRunContractError.invalidCompletion(
                "Record a durable attributed reply before completing Discuss."
            )
        }
    }

    func finishedResearchRecords(noteID: UUID?) async throws -> [PortableResearchRecord] {
        try requireActive()
        let listing = try await researchWorkspaceDependencies.portableResearchRecordStore.listing()
        guard listing.issues.isEmpty else {
            throw ScholiumApplicationError.researchStoreUnavailable(
                listing.issues.map(\.reason).joined(separator: "\n")
            )
        }
        return listing.records.filter { record in
            noteID == nil || record.participatingNotes.contains(where: { $0.noteID == noteID })
        }
    }

    func saveMethodFeedback(
        recordID: UUID,
        draft: ResearchMethodFeedbackDraft?,
        expectedMethodFeedbackRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> PortableResearchRecord {
        try requireActive()
        let updated: PortableResearchRecord
        do {
            updated = try await researchWorkspaceDependencies.portableResearchRecordStore
                .saveMethodFeedback(
                    draft,
                    recordID: recordID,
                    expectedMethodFeedbackRevision: expectedMethodFeedbackRevision,
                    expectedResultFingerprint: expectedResultFingerprint
                )
        } catch {
            throw methodFeedbackMutationError(
                error,
                operation: "the Method Feedback save"
            )
        }
        try await refreshAfterResearchCommit("The Method Feedback")
        return updated
    }

    func researchRecordChangeState(
        recordID: UUID
    ) async throws -> ResearchRecordChangeState {
        try requireActive()
        let record: PortableResearchRecord
        do {
            record = try await researchWorkspaceDependencies.portableResearchRecordStore.record(id: recordID)
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
            review = try await researchWorkspaceDependencies.portableResearchRecordStore
                .markCurrentNoteReviewed(
                noteID: noteID,
                observedRevision: expectedRevision,
                expectedRecordSourceManifestHash: expectedRecordSourceManifestHash
            )
        } catch let storeError as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain(let reason) = storeError else {
                throw storeError
            }
            let records = try await researchWorkspaceDependencies.portableResearchRecordStore.listing()
            let reviews = try await researchWorkspaceDependencies.portableResearchRecordStore
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
        var plans: [ResearchRecordUndoPlan] = []
        for noteID in selectedNoteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let change = changesByID[noteID]!
            guard let startingRevision = change.startingRevision else {
                throw ResearchRecordChangeRecoveryOperationError
                    .createdNoteHasNoPreimage(noteID)
            }
            guard let current = try await currentResearchSource(noteID: noteID) else {
                plans.append(.unavailable(noteID: noteID))
                continue
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
            let evidence = try await researchWorkspaceDependencies.agentChangeEvidenceStore.evidence(
                runID: record.id,
                noteID: noteID
            )
            guard evidence.triptychID == record.triptychID,
                  evidence.runID == record.id,
                  evidence.noteID == noteID,
                  evidence.startingRevision == startingRevision,
                  evidence.endingRevision == change.endingRevision else {
                throw ResearchRecordChangeRecoveryOperationError
                    .changeEvidenceMismatch(noteID)
            }
            let sourceBytes = try await researchWorkspaceDependencies.agentChangeEvidenceStore.startingData(
                runID: record.id,
                noteID: noteID,
                expectedRevision: startingRevision
            )
            guard DocumentFingerprint(data: sourceBytes) == startingRevision else {
                throw ResearchRecordChangeRecoveryOperationError
                    .changeEvidenceMismatch(noteID)
            }
            plans.append(.restore(
                noteID: noteID,
                note: current.note,
                startingRevision: startingRevision,
                endingRevision: change.endingRevision,
                startingData: sourceBytes
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
                let startingData
            ):
                sourceMutationAttempted = true
                do {
                    guard let startingContent = NoteDocument
                        .decodeUTF8PreservingBOM(startingData) else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    _ = try await repository(vaultID: note.vaultID).save(
                        relativePath: note.relativePath,
                        changeSet: .exactContent(startingContent),
                        expectedRevision: endingRevision
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
        let updated = try await researchWorkspaceDependencies.portableResearchRecordStore
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
        let updated = try await researchWorkspaceDependencies.portableResearchRecordStore
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
        do {
            _ = try await researchWorkspaceDependencies.portableResearchRecordStore.deletePermanently(id: id)
        } catch ResearchRecordStoreV1Error.recordNotFound {
            guard await researchWorkspaceDependencies.portableResearchRecordStore
                .isRecordPermanentlyDeleted(id: id) else {
                throw ResearchRecordStoreV1Error.recordNotFound(id)
            }
            // Resume cleanup after a prior deletion committed.
        }
        _ = try await researchWorkspaceDependencies.agentChangeEvidenceStore.removeEvidence(runID: id)
        if try await researchWorkspaceDependencies.localResearchExecutionStore.recordIfPresent(id: id) != nil {
            try await researchWorkspaceDependencies.localResearchExecutionStore.removeCompleted(runID: id)
        }
        try await refreshAfterResearchCommit("The permanent Research Record deletion")
    }

    func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ExactSourceComparison {
        try requireActive()
        let record = try await researchWorkspaceDependencies.portableResearchRecordStore.record(id: recordID)
        guard let change = record.confirmedChanges.first(where: {
            $0.noteID == noteID
        }) else {
            throw ResearchRecordChangeRecoveryOperationError.confirmedChangeNotFound(noteID)
        }
        guard let startingRevision = change.startingRevision else {
            throw ResearchRecordChangeRecoveryOperationError
                .createdNoteHasNoPreimage(noteID)
        }
        let evidence = try await researchWorkspaceDependencies.agentChangeEvidenceStore.evidence(
            runID: record.id,
            noteID: noteID
        )
        guard evidence.triptychID == record.triptychID,
              evidence.startingRevision == startingRevision,
              evidence.endingRevision == change.endingRevision else {
            throw ResearchRecordChangeRecoveryOperationError
                .changeEvidenceMismatch(noteID)
        }
        let startingData = try await researchWorkspaceDependencies.agentChangeEvidenceStore.startingData(
            runID: record.id,
            noteID: noteID,
            expectedRevision: startingRevision
        )
        let endingData = try await researchWorkspaceDependencies.agentChangeEvidenceStore.endingData(
            runID: record.id,
            noteID: noteID,
            expectedRevision: change.endingRevision
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

    // MARK: Interrupted Mutation Recovery

    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try requireActive()
        return try await researchWorkspaceDependencies.transactionRecoveryStore.pending()
    }

    func resolveRecoveryRecord(_ id: UUID) async throws {
        try requireActive()
        let records = try await researchWorkspaceDependencies.transactionRecoveryStore.pending()
        guard let record = records.first(where: { $0.id == id }),
              record.triptychID == self.id else {
            throw TriptychTransactionError.invalidPlan(
                "The selected recovery record is unavailable for this Triptych."
            )
        }
        if let systemTrashPlan = record.systemTrashDeletionPlan {
            if systemTrashPlan.sourceReceipts.contains(where: {
                $0.progress == .outcomeUnknown
            }) {
                guard systemTrashPlan.deletedRecordIDs.isEmpty,
                      systemTrashPlan.removedDiscussionIDs.isEmpty,
                      let vaultID = systemTrashPlan.preview.sources.first?.vaultID,
                      systemTrashPlan.preview.sources.allSatisfy({
                          $0.vaultID == vaultID
                      }) else {
                    throw TriptychTransactionError.invalidPlan(
                        "This unknown native-Trash outcome can no longer be resolved by retaining Records."
                    )
                }
                try await retainRecordsForUnknownSystemTrashOutcome(
                    recoveryRecordID: record.id,
                    vaultID: vaultID
                )
                try await refreshAfterResearchCommit(
                    "The unknown system-Trash outcome resolution"
                )
                return
            }
            let issues = await recoverInterruptedDocumentTransactions()
            if let remaining = try await researchWorkspaceDependencies.transactionRecoveryStore
                .pending().first(where: { $0.id == record.id }) {
                throw TriptychTransactionError.recoveryRequired(remaining)
            }
            guard issues.isEmpty else {
                throw TriptychTransactionError.invalidPlan(
                    issues.joined(separator: "\n")
                )
            }
            try await refreshAfterResearchCommit(
                "The system-Trash Record cleanup"
            )
            return
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
            try await researchWorkspaceDependencies.transactionRecoveryStore.resolve(record)
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
        let execution = try await researchWorkspaceDependencies.localResearchExecutionStore.record(
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
        guard let identity = try await researchWorkspaceDependencies.controlStore.identityRecord(
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        ), identity.id == entry.noteID,
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
            _ = try await researchWorkspaceDependencies.localResearchExecutionStore
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
        try await researchWorkspaceDependencies.transactionRecoveryStore.resolve(record)
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
        let execution = try await researchWorkspaceDependencies.localResearchExecutionStore.record(
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
            try await researchWorkspaceDependencies.transactionRecoveryStore.resolve(record)
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
            identityReconciliation = try await researchWorkspaceDependencies.controlStore
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
        var createdMetadata: NoteMetadataSnapshot?
        if let fields = link.metadataFields, source != nil {
            do {
                if let current = try await researchWorkspaceDependencies.controlStore
                    .noteMetadata(noteID: entry.noteID) {
                    guard current.record.fields == fields else {
                        throw NoteMetadataError.revisionConflict(entry.noteID)
                    }
                } else {
                    createdMetadata = try await researchWorkspaceDependencies.controlStore
                        .saveNoteMetadata(
                            noteID: entry.noteID,
                            fields: fields,
                            expectedRevision: nil
                        )
                }
            } catch {
                try? await researchWorkspaceDependencies.controlStore
                    .rollbackManagedCreationIdentity(
                        identityReconciliation,
                        vaultID: entry.note.vaultID,
                        relativePath: entry.note.relativePath
                    )
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
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
            finalIdentity = try await researchWorkspaceDependencies.controlStore.identityRecord(
                vaultID: entry.note.vaultID,
                relativePath: entry.note.relativePath
            )
        } catch {
            throw ResearchBoundedWriteSetError.recoveryRequired
        }
        if let finalSource {
            let finalMetadata = try? await researchWorkspaceDependencies.controlStore
                .noteMetadata(noteID: entry.noteID)
            guard finalSource.fingerprint == intendedRevision,
                  finalIdentity?.id == entry.noteID,
                  finalIdentity?.fingerprint == intendedRevision,
                  finalMetadata?.record.fields == link.metadataFields else {
                if let createdMetadata {
                    try? await researchWorkspaceDependencies.controlStore
                        .removeNoteMetadata(createdMetadata)
                }
                try? await researchWorkspaceDependencies.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: entry.note.vaultID,
                    relativePath: entry.note.relativePath
                )
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
        } else {
            guard finalIdentity == nil else {
                try? await researchWorkspaceDependencies.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: entry.note.vaultID,
                    relativePath: entry.note.relativePath
                )
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
            let currentMetadata: NoteMetadataSnapshot?
            do {
                currentMetadata = try await researchWorkspaceDependencies.controlStore
                    .noteMetadata(noteID: entry.noteID)
            } catch {
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
            if let currentMetadata {
                guard currentMetadata.record.fields == link.metadataFields else {
                    throw ResearchBoundedWriteSetError.recoveryRequired
                }
                do {
                    try await researchWorkspaceDependencies.controlStore
                        .removeNoteMetadata(currentMetadata)
                } catch {
                    throw ResearchBoundedWriteSetError.recoveryRequired
                }
            }
        }
        _ = try await researchWorkspaceDependencies.localResearchExecutionStore
            .reconcileDocumentWriteRecovery(
                runID: link.runID,
                operationID: link.operationID,
                recoveryRecordID: record.id,
                observedRevision: finalSource?.fingerprint,
                reconciledAt: Date()
            )
        try await researchWorkspaceDependencies.transactionRecoveryStore.resolve(record)
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
            identityReconciliation = try await researchWorkspaceDependencies.controlStore
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

        var createdMetadata: NoteMetadataSnapshot?
        if let fields = reference.metadataFields, source != nil {
            do {
                if let current = try await researchWorkspaceDependencies.controlStore
                    .noteMetadata(noteID: reference.reservedIdentityID) {
                    guard current.record.fields == fields else {
                        throw NoteMetadataError.revisionConflict(
                            reference.reservedIdentityID
                        )
                    }
                } else {
                    createdMetadata = try await researchWorkspaceDependencies.controlStore
                        .saveNoteMetadata(
                            noteID: reference.reservedIdentityID,
                            fields: fields,
                            expectedRevision: nil
                        )
                }
            } catch {
                try? await researchWorkspaceDependencies.controlStore
                    .rollbackManagedCreationIdentity(
                        identityReconciliation,
                        vaultID: reference.target.vaultID,
                        relativePath: reference.target.relativePath
                    )
                throw TriptychTransactionError.recoveryRequired(record)
            }
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
            finalPathIdentity = try await researchWorkspaceDependencies.controlStore.identityRecord(
                vaultID: reference.target.vaultID,
                relativePath: reference.target.relativePath
            )
            finalReservedIdentity = try await researchWorkspaceDependencies.controlStore.identityRecord(
                id: reference.reservedIdentityID
            )
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        if let finalSource {
            let finalMetadata = try? await researchWorkspaceDependencies.controlStore
                .noteMetadata(noteID: reference.reservedIdentityID)
            guard finalSource.fingerprint == intendedRevision,
                  finalPathIdentity?.id == reference.reservedIdentityID,
                  finalPathIdentity?.fingerprint == intendedRevision,
                  finalReservedIdentity == finalPathIdentity,
                  finalMetadata?.record.fields == reference.metadataFields else {
                if let createdMetadata {
                    try? await researchWorkspaceDependencies.controlStore
                        .removeNoteMetadata(createdMetadata)
                }
                try? await researchWorkspaceDependencies.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
        } else {
            guard finalPathIdentity == nil,
                  finalReservedIdentity == nil else {
                try? await researchWorkspaceDependencies.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
            let currentMetadata: NoteMetadataSnapshot?
            do {
                currentMetadata = try await researchWorkspaceDependencies.controlStore
                    .noteMetadata(noteID: reference.reservedIdentityID)
            } catch {
                throw TriptychTransactionError.recoveryRequired(record)
            }
            if let current = currentMetadata {
                guard current.record.fields == reference.metadataFields else {
                    throw TriptychTransactionError.recoveryRequired(record)
                }
                do {
                    try await researchWorkspaceDependencies.controlStore
                        .removeNoteMetadata(current)
                } catch {
                    throw TriptychTransactionError.recoveryRequired(record)
                }
            }
        }
        try await researchWorkspaceDependencies.transactionRecoveryStore.resolve(record)
        return reference.target
    }

    // MARK: Critique

    func critique(
        critiqueRelativePath: String
    ) async throws -> CritiqueAssociation? {
        try requireActive()
        if let issue = await researchWorkspaceDependencies.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        return await researchWorkspaceDependencies.critiqueRegistry.association(
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
        if let issue = await researchWorkspaceDependencies.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        guard let current = await researchWorkspaceDependencies.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await researchWorkspaceDependencies.critiqueRegistry.setFindingDisposition(
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
        guard let current = await researchWorkspaceDependencies.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await researchWorkspaceDependencies.critiqueRegistry.completeRound(
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
            record = try await researchWorkspaceDependencies.portableResearchRecordStore.record(id: id)
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
        guard let controlled = try await researchWorkspaceDependencies.controlStore.identityRecord(id: noteID) else {
            return nil
        }
        let note = VaultQualifiedNoteID(
            vaultID: controlled.vaultID,
            relativePath: controlled.relativePath
        )
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
        guard currentSnapshot.document(id: noteID) != nil else {
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
        role: ResearchActionTargetRole,
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
                    snapshot.stableIdentity.resolvedID == participant.noteID
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
        _ role: ResearchActionTargetRole
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

    private func methodFeedbackMutationError(
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
            return PortableResearchMethodFeedbackMutationError.recordUnavailable
        default:
            return error
        }
    }

    private func availableCritiquePath(
        base: String,
        repository: VaultRepository
    ) async throws -> String {
        let existing = Set(try await repository.markdownRelativePaths())
        let first = "Critiques/\(base) Critique.md"
        if !existing.contains(first) { return first }
        var index = 2
        while existing.contains("Critiques/\(base) Critique \(index).md") {
            index += 1
        }
        return "Critiques/\(base) Critique \(index).md"
    }
}
