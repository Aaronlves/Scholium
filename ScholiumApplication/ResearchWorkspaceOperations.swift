import ScholiumContracts
import Foundation
import ScholiumCore

extension WorkspaceHandle {
    // MARK: Researcher Comments and Human Review

    func comments(noteID: UUID) async throws -> [ResearcherComment] {
        try requireActive()
        try await requireHealthyHumanReviewStore()
        return await services.humanReviewStore.record(noteID: noteID)?.comments ?? []
    }

    func addComment(
        to noteID: VaultQualifiedNoteID,
        text: String,
        anchor: ResearcherCommentAnchor,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        if anchor.fingerprint != expectedRevision {
            throw ResearchOperationError.staleCommentRevision
        }
        let record = try await services.humanReviewStore.addComment(
            noteID: context.identity.id,
            vaultID: noteID.vaultID,
            relativePath: noteID.relativePath,
            comment: ResearcherComment(text: text, anchor: anchor)
        )
        try await refreshAfterResearchCommit("The Comment")
        return record
    }

    func updateComment(
        noteID: UUID,
        commentID: UUID,
        text: String
    ) async throws -> HumanReviewRecord {
        try requireActive()
        try await requireHealthyHumanReviewStore()
        try await services.humanReviewStore.updateCommentText(
            noteID: noteID,
            commentID: commentID,
            text: text
        )
        let record = try await requireHumanReviewRecord(noteID: noteID)
        try await refreshAfterResearchCommit("The Comment")
        return record
    }

    func setCommentResolved(
        noteID: UUID,
        commentID: UUID,
        resolved: Bool
    ) async throws -> HumanReviewRecord {
        try requireActive()
        try await requireHealthyHumanReviewStore()
        try await services.humanReviewStore.setCommentResolvedByResearcher(
            noteID: noteID,
            commentID: commentID,
            resolved: resolved
        )
        let record = try await requireHumanReviewRecord(noteID: noteID)
        try await refreshAfterResearchCommit("The Comment")
        return record
    }

    func deleteComment(
        noteID: UUID,
        commentID: UUID
    ) async throws -> HumanReviewRecord {
        try requireActive()
        try await requireHealthyHumanReviewStore()
        try await services.humanReviewStore.removeComment(
            noteID: noteID,
            commentID: commentID
        )
        let record = try await requireHumanReviewRecord(noteID: noteID)
        try await refreshAfterResearchCommit("The Comment")
        return record
    }

    func reattachComment(
        to noteID: VaultQualifiedNoteID,
        commentID: UUID,
        anchor: ResearcherCommentAnchor,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        guard anchor.fingerprint == expectedRevision else {
            throw ResearchOperationError.staleCommentRevision
        }
        try await services.humanReviewStore.reattachComment(
            noteID: context.identity.id,
            commentID: commentID,
            to: anchor
        )
        let record = try await requireHumanReviewRecord(noteID: context.identity.id)
        try await refreshAfterResearchCommit("The Comment attachment")
        return record
    }

    func reattachComments(
        to noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.commentUnavailable($0) }
        )
        try await services.humanReviewStore.reattachComments(
            noteID: context.identity.id,
            to: context.document
        )
        let record = try await requireHumanReviewRecord(noteID: context.identity.id)
        try await refreshAfterResearchCommit("The Comment attachments")
        return record
    }

    func saveHumanReviewDraft(
        for noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0.allowsHumanReview },
            unavailable: { ResearchOperationError.humanReviewUnavailable($0) }
        )
        let record = try await services.humanReviewStore.saveDraft(
            noteID: context.identity.id,
            vaultID: noteID.vaultID,
            relativePath: noteID.relativePath,
            draft: HumanReviewDraft(
                fingerprint: expectedRevision,
                qualification: qualification,
                reviewNote: reviewNote
            )
        )
        try await refreshAfterResearchCommit("The Human Review draft")
        return record
    }

    func completeHumanReview(
        for noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        let context = try await researchContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0.allowsHumanReview },
            unavailable: { ResearchOperationError.humanReviewUnavailable($0) }
        )
        if context.vault.role == .sourceCorpus,
           ResearchUnitDeclaration(
                frontmatter: context.document.parsedFrontmatter
           ).state != .declared {
            throw ResearchOperationError.researchStatusRequiredForReview
        }
        let record = try await services.humanReviewStore.completeReview(
            noteID: context.identity.id,
            vaultID: noteID.vaultID,
            relativePath: noteID.relativePath,
            fingerprint: expectedRevision,
            qualification: qualification,
            reviewNote: reviewNote
        )
        try await refreshAfterResearchCommit("The Human Review")
        return record
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

    // MARK: Dialogue

    func createDialogue(
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        includedCommentIDs: Set<UUID>,
        requestedDestination: String?,
        responseProfile: DialogueResponseProfile?,
        dialogueID requestedDialogueID: UUID? = nil,
        functionSnapshot: ResearchFunctionSnapshot? = nil,
        skillInstructionsOverride: String? = nil
    ) async throws -> DialoguePreparation {
        try requireActive()
        if let issue = await services.dialogueStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        let settings = try await services.controlStore.settings()
        let template = settings.activePromptTemplate(for: .dialogue)
        guard template.validationIssues.isEmpty else {
            throw ResearchGuidanceError.invalidActiveTemplate(
                .dialogue,
                template.validationIssues
            )
        }
        let storedProfile = try await services.controlStore.dialogueResponseProfile()
        let effectiveProfile = responseProfile ?? storedProfile
        guard effectiveProfile.validationIssues.isEmpty else {
            throw ResearchOperationError.invalidDialogueResponseContract(
                effectiveProfile.validationIssues
            )
        }
        let responseContract = DialogueResponseContract(profile: effectiveProfile)
        let dialogueID = requestedDialogueID ?? UUID()
        if let functionSnapshot {
            guard functionSnapshot.runID == dialogueID,
                  functionSnapshot.recordID == dialogueID,
                  functionSnapshot.request.function == .dialogue else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "Dialogue function evidence does not match its record identity."
                )
            }
        }
        let skillInstructions = if let skillInstructionsOverride {
            skillInstructionsOverride
        } else {
            try await services.researchSkillStore.instructionAssembly()
        }
        try await verifyDialogueSelectionIsCurrent(selectedNotes)

        var includedComments: [DialogueIncludedComment] = []
        for note in selectedNotes {
            let comments = await services.humanReviewStore.record(noteID: note.noteID)?.comments ?? []
            includedComments.append(contentsOf: comments
                .filter { includedCommentIDs.contains($0.id) }
                .map { DialogueIncludedComment(note: note, comment: $0) })
        }

        let linkedSummary = dialogueLinkedNoteSummary(for: selectedNotes)
        var instructions = DialoguePromptBuilder.build(
            DialoguePromptContext(
                instruction: instruction,
                selectedNotes: selectedNotes,
                comments: includedComments,
                triptychSummary: dialogueTriptychSummary(),
                linkedNoteSummary: linkedSummary,
                requestedDestination: requestedDestination
            ),
            template: template.source
        )
        let responseLocator = DialogueResponseTransport.locator(
            dialogueID: dialogueID,
            triptychID: services.manifest.id,
            contract: responseContract
        )
        instructions += "\n\n" + responseLocator
        if !skillInstructions.isEmpty {
            instructions += "\n\n" + skillInstructions
        }

        let entry = DialogueEntry(
            id: dialogueID,
            triptychID: services.manifest.id,
            instruction: instruction,
            selectedNotes: selectedNotes,
            includedComments: includedComments,
            // Ordinary Dialogue keeps its historical record shape. A
            // Research Function Dialogue persists the canonical immutable
            // packet so a prepared run remains recoverable after dismissal.
            preparedInstructions: functionSnapshot == nil
                ? ""
                : skillInstructions + "\n\n" + responseLocator,
            checkpointID: nil,
            functionSnapshot: functionSnapshot,
            responseContract: responseContract,
            requestedDestination: requestedDestination,
            linkedNoteSummary: linkedSummary
        )
        let saved = try await services.dialogueStore.save(entry)
        try await refreshAfterResearchCommit("The Dialogue request")
        return DialoguePreparation(
            entry: saved,
            instructions: instructions,
            checkpoint: nil
        )
    }

    func appendDialogueFollowUpComment(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try requireActive()
        if let issue = await services.dialogueStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
        let entry = try await services.dialogueStore.appendFollowUpComment(
            comment,
            to: entryID
        )
        try await refreshAfterResearchCommit("The Dialogue follow-up Comment")
        return entry
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
        skillInstructionsOverride: String? = nil
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
        let workTitle = workContext.document.parsedFrontmatter["title"]?.scalarString
            ?? currentSnapshot.discovery.catalog.notes.first(where: {
                $0.reference.vaultID == workID.vaultID
                    && $0.reference.relativePath == workID.relativePath
            })?.title
            ?? (workID.relativePath as NSString).lastPathComponent
                .replacingOccurrences(of: ".md", with: "")
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

        let skillInstructions: String
        do {
            if let skillInstructionsOverride {
                skillInstructions = skillInstructionsOverride
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

        let outputSnapshot = ResearchFunctionOutputSnapshot(
            note: VaultQualifiedNoteID(
                vaultID: workID.vaultID,
                relativePath: critiquePath
            ),
            fingerprint: preparedRevision
        )
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

        let association: CritiqueAssociation
        do {
            association = try await services.critiqueRegistry.recordRequest(
                workNoteID: workContext.identity.id,
                workRelativePath: workID.relativePath,
                targetFingerprint: expectedRevision,
                critiqueRelativePath: critiquePath,
                checkpointID: checkpoint.id,
                scope: scope,
                roundID: roundID,
                functionSnapshot: functionSnapshot,
                functionInstructions: functionSnapshot == nil
                    ? nil
                    : skillInstructions + "\n\n"
                        + researchFunctionCritiqueOutputBinding(outputSnapshot),
                requestedAt: requestedAt
            )
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

    private func requireHealthyHumanReviewStore() async throws {
        if let issue = await services.humanReviewStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(issue)
        }
    }

    private func requireHumanReviewRecord(
        noteID: UUID
    ) async throws -> HumanReviewRecord {
        guard let record = await services.humanReviewStore.record(noteID: noteID) else {
            throw HumanReviewError.recordNotFound(noteID)
        }
        return record
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

    private func verifyDialogueSelectionIsCurrent(
        _ selectedNotes: [DialogueNoteReference]
    ) async throws {
        for reference in selectedNotes {
            let id = VaultQualifiedNoteID(
                vaultID: reference.vaultID,
                relativePath: reference.relativePath
            )
            guard let snapshot = currentSnapshot.document(id: id),
                  snapshot.lifecycle == .active,
                  case .resolved(let stableID) = snapshot.stableIdentity,
                  stableID == reference.noteID else {
                throw ResearchOperationError.dialogueContextChanged(reference.title)
            }
            do {
                let document = try await repository(vaultID: reference.vaultID).load(
                    relativePath: reference.relativePath
                )
                guard document.fingerprint == reference.fingerprint else {
                    throw ResearchOperationError.dialogueContextChanged(reference.title)
                }
            } catch is ResearchOperationError {
                throw ResearchOperationError.dialogueContextChanged(reference.title)
            } catch {
                throw ResearchOperationError.dialogueContextChanged(reference.title)
            }
        }
    }

    private func dialogueTriptychSummary() -> String {
        var lines = ["Triptych: \(assignment.triptych.name)"]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot) else { continue }
            lines.append("- \(slot.displayName) root: \(vault.canonicalPath)")
        }
        return lines.joined(separator: "\n")
    }

    private func dialogueLinkedNoteSummary(
        for selectedNotes: [DialogueNoteReference]
    ) -> String? {
        let catalog = currentSnapshot.discovery.catalog
        guard let graph = catalog.graph else { return nil }
        let notesByID = Dictionary(uniqueKeysWithValues: catalog.notes.map { note in
            (
                VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                note
            )
        })
        var lines: [String] = []
        for note in selectedNotes {
            let source = VaultQualifiedNoteID(
                vaultID: note.vaultID,
                relativePath: note.relativePath
            )
            for edge in graph.outgoing[source, default: []] {
                let targetName: String
                if let destination = edge.destination?.note {
                    targetName = notesByID[destination]?.title ?? destination.relativePath
                } else {
                    targetName = edge.occurrence.target
                }
                let relation = switch edge.occurrence.vectorKind {
                case .supportsTarget: "supports"
                case .supportedByTarget: "is supported by"
                case .incompatible: "is incompatible with"
                case .neutral, .none: "connects neutrally to"
                }
                lines.append(
                    "- \(note.title) \(relation) \(targetName) "
                        + "(declared on line \(edge.occurrence.span.start.line))"
                )
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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
