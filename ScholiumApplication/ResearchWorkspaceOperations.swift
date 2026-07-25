import ScholiumContracts
import Foundation
import ScholiumCore

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
            && discussion.createdAt == expected.createdAt
            && discussion.statements.first == expected.statements.first
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
            && record.startedAt == expected.createdAt
            && record.statements.first == expected.statements.first
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
        let settlement = try await services.portableResearchRecordStore.settle(
            noteID: context.identity.id,
            fingerprint: expectedRevision,
            rationale: rationale
        )
        try await refreshAfterResearchCommit("The settlement")
        return settlement
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
        let targetContext = try await researchContext(
            for: target.note,
            expectedRevision: target.fingerprint,
            permits: { ResearchFunctionTargetRole(vaultRole: $0) == target.role },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        guard targetContext.identity.id == target.noteID,
              passage?.fingerprint == target.fingerprint || passage == nil else {
            throw ResearchOperationError.noteUnavailable(target.note)
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
            passage: passage
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
        let listing = try await services.portableResearchRecordStore.listing(location: .records)
        guard listing.issues.isEmpty else {
            throw ScholiumApplicationError.researchStoreUnavailable(
                listing.issues.map(\.reason).joined(separator: "\n")
            )
        }
        return listing.records.filter { record in
            noteID == nil || record.participatingNotes.contains(where: { $0.noteID == noteID })
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
        try await services.transactionRecoveryStore.resolve(id)
        try await refreshAfterResearchCommit("The recovery-record resolution")
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
        guard let round = association.rounds.first(where: { $0.id == roundID }),
              let completedAt = round.completedAt else {
            throw CritiqueRegistryError.incompleteDispositions(roundID)
        }
        let title = ResearchNoteTitleResolver.resolve(
            document: context.document,
            vaultRole: context.vault.role
        ).title
        let reference = ResearchActivityNoteReference(
            noteID: context.identity.id,
            note: workNote,
            role: .work,
            title: title
        )
        _ = try await services.researchActivityStore.appendEvent(
            ResearchActivityEvent(
                id: ResearchActivityEvent.stableID(
                    activityID: roundID,
                    noteID: context.identity.id,
                    kind: .critiqueAddressed
                ),
                activityID: roundID,
                note: reference,
                kind: .critiqueAddressed,
                occurredAt: completedAt,
                origin: reference,
                researchRecordID: roundID
            )
        )
        try await refreshAfterResearchCommit("The completed Critique round")
        return association
    }

    func requestCritique(
        for workID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        scope: CritiqueRequestScope,
        lens: String,
        selectedRanges: String,
        additionalInstructions: String,
        preparedCheckpoint: TriptychCheckpoint? = nil,
        roundID: UUID = UUID(),
        functionSnapshotBuilder: ((ResearchFunctionOutputSnapshot) -> ResearchFunctionSnapshot)? = nil,
        skillInstructionsOverride: ((ResearchFunctionOutputSnapshot) throws -> String)? = nil
    ) async throws -> CritiquePreparation {
        let workContext = try await researchContext(
            for: workID,
            expectedRevision: expectedRevision,
            permits: { $0.allowsCritique },
            unavailable: { ResearchOperationError.critiqueUnavailable($0) }
        )
        guard !CritiquePlacement.isManagedCritiquePath(workID.relativePath) else {
            throw ResearchOperationError.critiqueTargetMustBeOrdinaryWork(
                workID.relativePath
            )
        }
        let settings = try await services.controlStore.settings()
        let template = settings.activePromptTemplate(for: .critique)
        guard template.validationIssues.isEmpty else {
            throw ResearchGuidanceError.invalidActiveTemplate(
                .critique,
                template.validationIssues
            )
        }
        if let issue = await services.critiqueRegistry.healthError() {
            throw ResearchOperationError.critiqueRegistryUnavailable(issue)
        }

        let repository = try repository(vaultID: workID.vaultID)
        let workTitle = ResearchNoteTitleResolver.resolve(
            document: workContext.document,
            vaultRole: workContext.vault.role
        ).title
        let requestedAt = Date()
        let checkpoint = if let preparedCheckpoint {
            preparedCheckpoint
        } else {
            try await createCheckpoint(name: "Before Agent Work", kind: .automatic)
        }
        let recheckedTarget = try await repository.load(
            relativePath: workID.relativePath
        )
        guard recheckedTarget.fingerprint == expectedRevision else {
            throw ResearchOperationError.critiqueTargetChanged
        }

        let critiquePath: String
        var previousCritiqueDocument: NoteDocument?
        var preparedRevision: DocumentFingerprint
        var createdIdentity: NoteIdentityRecord?

        if let existing = await services.critiqueRegistry.association(
            workNoteID: workContext.identity.id
        ) {
            guard CritiquePlacement.isActiveCritiquePath(existing.critiqueRelativePath) else {
                throw CritiquePlacementError.invalidCritiquePath(
                    existing.critiqueRelativePath
                )
            }
            critiquePath = existing.critiqueRelativePath
            let critiqueDocument = try await repository.load(relativePath: critiquePath)
            guard try await services.controlStore.identityRecord(
                vaultID: workID.vaultID,
                relativePath: critiquePath
            ) != nil else {
                throw NoteIdentityRecoveryError.identityUnresolved(critiquePath)
            }
            previousCritiqueDocument = critiqueDocument
            let saved: SaveResult
            if critiqueDocument.rawFrontmatter == nil {
                let source = try CritiqueDocumentContract.sourceByAddingRequestMetadata(
                    to: critiqueDocument,
                    targetRelativePath: workID.relativePath,
                    targetFingerprint: expectedRevision,
                    scope: scope,
                    requestedAt: requestedAt
                )
                saved = try await repository.save(
                    relativePath: critiquePath,
                    changeSet: .exactContent(source),
                    expectedRevision: critiqueDocument.fingerprint
                )
            } else {
                saved = try await repository.save(
                    relativePath: critiquePath,
                    changeSet: .frontmatter(CritiqueDocumentContract.requestEdits(
                        targetRelativePath: workID.relativePath,
                        targetFingerprint: expectedRevision,
                        scope: scope,
                        requestedAt: requestedAt
                    )),
                    expectedRevision: critiqueDocument.fingerprint
                )
            }
            preparedRevision = saved.document.fingerprint
        } else {
            let base = (workID.relativePath as NSString).lastPathComponent
                .replacingOccurrences(of: ".md", with: "")
            critiquePath = try await availableCritiquePath(
                base: base,
                repository: repository
            )
            let scaffold = CritiqueDocumentContract.scaffold(
                title: workTitle,
                targetRelativePath: workID.relativePath,
                targetFingerprint: expectedRevision,
                scope: scope,
                requestedAt: requestedAt
            )
            let created = try await repository.create(
                relativePath: critiquePath,
                content: scaffold
            )
            preparedRevision = created.fingerprint
            do {
                createdIdentity = try await services.controlStore.identity(
                    forVaultID: workID.vaultID,
                    relativePath: critiquePath,
                    fingerprint: preparedRevision
                )
            } catch {
                do {
                    try await repository.removeCreatedFileForRollback(
                        relativePath: critiquePath,
                        createdRevision: preparedRevision
                    )
                } catch let rollbackError {
                    throw ResearchOperationError.critiqueRollbackFailed(
                        requestError: error.localizedDescription,
                        rollbackError: rollbackError.localizedDescription
                    )
                }
                throw error
            }
        }

        func rollbackPreparedCritique() async throws {
            if let previousCritiqueDocument {
                _ = try await repository.save(
                    relativePath: critiquePath,
                    changeSet: .exactContent(previousCritiqueDocument.rawContent),
                    expectedRevision: preparedRevision
                )
            } else {
                try await repository.removeCreatedFileForRollback(
                    relativePath: critiquePath,
                    createdRevision: preparedRevision
                )
                if let createdIdentity {
                    _ = try await services.controlStore.purgeIdentity(
                        id: createdIdentity.id,
                        vaultID: workID.vaultID,
                        relativePath: critiquePath
                    )
                }
            }
        }

        let outputSnapshot = ResearchFunctionOutputSnapshot(
            note: VaultQualifiedNoteID(
                vaultID: workID.vaultID,
                relativePath: critiquePath
            ),
            fingerprint: preparedRevision
        )

        let skillInstructions: String
        do {
            if let skillInstructionsOverride {
                skillInstructions = try skillInstructionsOverride(outputSnapshot)
            } else {
            let contract = try ResearchWorkflowRouteContracts.critique(
                work: ResearchWorkflowObjectReference(
                    kind: .note,
                    identifier: workID.relativePath,
                    fingerprint: expectedRevision
                ),
                critique: ResearchWorkflowObjectReference(
                    kind: .note,
                    identifier: critiquePath,
                    fingerprint: preparedRevision
                ),
                purpose: "Conduct \(scope.rawValue.lowercased()) of the exact Work revision and write attributed findings to its current Critique document."
            )
            let envelope = try await ResearchWorkflowAssembler.resolve(
                contract,
                store: services.researchSkillStore
            )
            guard envelope.isExecutable else {
                throw ResearchWorkflowContractError.invalid(
                    envelope.blockingConflicts.joined(separator: " ")
                )
            }
            skillInstructions = envelope.renderedInstructions
            }
        } catch {
            let requestError = error
            do {
                try await rollbackPreparedCritique()
            } catch let rollbackError {
                throw ResearchOperationError.critiqueRollbackFailed(
                    requestError: requestError.localizedDescription,
                    rollbackError: rollbackError.localizedDescription
                )
            }
            throw requestError
        }

        let functionSnapshot = functionSnapshotBuilder?(outputSnapshot)
        if let functionSnapshot {
            guard functionSnapshot.runID == roundID,
                  functionSnapshot.recordID == roundID,
                  functionSnapshot.checkpointID == checkpoint.id,
                  functionSnapshot.request.function == .critique,
                  functionSnapshot.preparedOutput == outputSnapshot else {
                try await rollbackPreparedCritique()
                throw ResearchFunctionContractError.invalidCompletion(
                    "Critique function evidence does not match its prepared output."
                )
            }
        }

        let preparedFunctionInstructions = functionSnapshot.map { _ in
            skillInstructions + "\n\n"
                + researchFunctionCritiqueOutputBinding(outputSnapshot)
        }
        let association: CritiqueAssociation
        do {
            if let functionSnapshot,
               functionSnapshot.actionSnapshot != nil,
               let preparedFunctionInstructions {
                try await services.localResearchExecutionStore.stageCritiqueHandoff(
                    snapshot: functionSnapshot,
                    preparedInstructions: preparedFunctionInstructions
                )
            }
            association = try await services.critiqueRegistry.recordRequest(
                workNoteID: workContext.identity.id,
                workRelativePath: workID.relativePath,
                targetFingerprint: expectedRevision,
                critiqueRelativePath: critiquePath,
                checkpointID: checkpoint.id,
                scope: scope,
                roundID: roundID,
                functionSnapshot: functionSnapshot,
                functionInstructions: preparedFunctionInstructions,
                requestedAt: requestedAt
            )
        } catch {
            let requestError = error
            if let functionSnapshot,
               functionSnapshot.actionSnapshot != nil,
               let preparedFunctionInstructions {
                try? await services.localResearchExecutionStore
                    .discardCritiqueHandoff(
                        snapshot: functionSnapshot,
                        preparedInstructions: preparedFunctionInstructions
                    )
            }
            do {
                try await rollbackPreparedCritique()
            } catch let rollbackError {
                throw ResearchOperationError.critiqueRollbackFailed(
                    requestError: requestError.localizedDescription,
                    rollbackError: rollbackError.localizedDescription
                )
            }
            throw requestError
        }

        var instructions = CritiquePromptBuilder.build(CritiquePromptContext(
            template: template.source,
            scope: scope,
            lens: lens,
            selectedRanges: selectedRanges,
            additionalInstructions: additionalInstructions,
            workTitle: workTitle,
            workRelativePath: workID.relativePath,
            workFingerprint: expectedRevision,
            critiqueRelativePath: association.critiqueRelativePath
        ))
        if !skillInstructions.isEmpty {
            instructions += "\n\n" + skillInstructions
        }
        try await refreshAfterCommittedOperation(
            "The Critique request",
            publication: .explicit,
            affectedVaultIDs: [workID.vaultID]
        )
        return CritiquePreparation(
            association: association,
            instructions: instructions,
            checkpoint: checkpoint
        )
    }

    // MARK: Helpers

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
