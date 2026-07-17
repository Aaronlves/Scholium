import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Application research operations")
struct ResearchOperationsMutationTests {
    @Test("Comments and Human Review are revision-bound and publish research state")
    func commentsAndHumanReview() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(try await handle.snapshot().document(id: fixture.analysisID))
        let stableID = try #require(note.stableIdentity.resolvedID)
        let quotation = "Exact philosophical claim"
        let source = note.document.rawContent
        let range = try #require(source.range(of: quotation))
        let lowerUTF16 = range.lowerBound.utf16Offset(in: source)
        let upperUTF16 = range.upperBound.utf16Offset(in: source)
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: source,
            fingerprint: note.fingerprint,
            utf16Range: lowerUTF16..<upperUTF16
        ))

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let added = try await handle.research.addComment(
            to: fixture.analysisID,
            text: "Check the textual support.",
            anchor: anchor,
            expectedRevision: note.fingerprint
        )
        let commentID = try #require(added.comments.first?.id)
        let event = try #require(await iterator.next())
        if case .researchRecordsChanged(let changed) = event {
            #expect(changed.research.humanReviews.contains { $0.id == stableID })
        } else {
            Issue.record("A Comment mutation did not publish researchRecordsChanged.")
        }

        let updated = try await handle.research.updateComment(
            noteID: stableID,
            commentID: commentID,
            text: "Check the primary-text support."
        )
        #expect(updated.comments.first?.text == "Check the primary-text support.")
        let resolved = try await handle.research.setCommentResolved(
            noteID: stableID,
            commentID: commentID,
            resolved: true
        )
        #expect(resolved.comments.first?.resolvedAt != nil)
        let reattached = try await handle.research.reattachComment(
            to: fixture.analysisID,
            commentID: commentID,
            anchor: anchor,
            expectedRevision: note.fingerprint
        )
        #expect(reattached.comments.first?.anchor.state == .attached)
        _ = try await handle.research.reattachComments(
            to: fixture.analysisID,
            expectedRevision: note.fingerprint
        )

        let draft = try await handle.research.saveHumanReviewDraft(
            for: fixture.analysisID,
            expectedRevision: note.fingerprint,
            qualification: .qualified,
            reviewNote: "The reconstruction remains source-faithful."
        )
        #expect(draft.draft?.fingerprint == note.fingerprint)
        let completed = try await handle.research.completeHumanReview(
            for: fixture.analysisID,
            expectedRevision: note.fingerprint,
            qualification: .qualified,
            reviewNote: "The reconstruction remains source-faithful."
        )
        #expect(completed.review(for: note.fingerprint)?.qualification == .qualified)
        #expect(completed.comments.count == 1)

        let afterDelete = try await handle.research.deleteComment(
            noteID: stableID,
            commentID: commentID
        )
        #expect(afterDelete.comments.isEmpty)

        try Data("# Analysis\n\nAn external revision.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.research.addComment(
                to: fixture.analysisID,
                text: "This stale Comment must not land.",
                anchor: anchor,
                expectedRevision: note.fingerprint
            )
        }
        #expect(try await handle.research.comments(noteID: stableID).isEmpty)
        await runtime.shutdown()
    }

    @Test("Checkpoint history follows identity across rename and restores exact bytes")
    func checkpointHistoryAndRestore() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisID)
        let originalBytes = original.sourceBytes
        let checkpoint = try await handle.research.createCheckpoint(
            name: "Exact source",
            kind: .manual
        )

        let destinationPath = "Renamed Analysis.md"
        let move = try await handle.documents.move(
            fixture.analysisID,
            to: destinationPath,
            expectedRevision: original.fingerprint
        )
        let moved = try await handle.documents.load(move.destination)
        let changed = try await handle.documents.save(
            move.destination,
            changeSet: .exactContent("# Changed\n\nA later revision.\n"),
            expectedRevision: moved.fingerprint
        )

        let history = try await handle.research.noteCheckpoints(for: move.destination)
        #expect(history.contains { $0.id == checkpoint.id })
        let historical = try await handle.research.checkpointNoteContent(
            checkpoint.id,
            note: move.destination
        )
        #expect(Data(historical.utf8) == originalBytes)
        let comparison = try await handle.research.checkpointComparison(checkpoint.id)
        #expect(comparison.contains {
            $0.checkpointPath == fixture.analysisID.relativePath
                || $0.currentPath == destinationPath
        })

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let restored = try await handle.research.restoreNote(
            move.destination,
            from: checkpoint.id,
            expectedRevision: changed.document.fingerprint
        )
        #expect(restored.restoredFiles == [TriptychCheckpointFileKey(
            area: .analyses,
            relativePath: destinationPath
        )])
        let sourceEvent = try #require(await iterator.next())
        if case .sourceCommitted(let commit) = sourceEvent {
            if case .checkpointRestore(let restoredID) = commit.kind {
                #expect(restoredID == checkpoint.id)
            } else {
                Issue.record("Selective checkpoint restore used the wrong commit kind.")
            }
        } else {
            Issue.record("Selective checkpoint restore did not publish sourceCommitted.")
        }
        #expect(sourceEvent.snapshot.research.checkpointListing.checkpoints.contains {
            $0.id == restored.recoveryCheckpoint.id
        })

        let restoredData = try Data(contentsOf: fixture.analysesURL
            .appendingPathComponent(destinationPath))
        #expect(restoredData == originalBytes)
        #expect(restoredData.starts(with: [0xEF, 0xBB, 0xBF]))
        await runtime.shutdown()
    }

    @Test("Dialogue preparation is read-only and persists its immutable request contract")
    func dialoguePreparation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(try await handle.snapshot().document(id: fixture.analysisID))
        let stableID = try #require(note.stableIdentity.resolvedID)
        let anchor = try commentAnchor(in: note.document)
        let commentRecord = try await handle.research.addComment(
            to: fixture.analysisID,
            text: "Preserve this distinction.",
            anchor: anchor,
            expectedRevision: note.fingerprint
        )
        let commentID = try #require(commentRecord.comments.first?.id)
        let reference = DialogueNoteReference(
            noteID: stableID,
            vaultID: fixture.analysisID.vaultID,
            vaultName: "Analyses",
            title: "Analysis",
            relativePath: fixture.analysisID.relativePath,
            fingerprint: note.fingerprint,
            kind: nil
        )

        let preparation = try await handle.research.createDialogue(
            instruction: "Reconstruct the argument and mark uncertainty.",
            selectedNotes: [reference],
            includedCommentIDs: [commentID],
            requestedDestination: "Topics/Agency.md"
        )
        #expect(!preparation.entry.generatedPrompt.isEmpty)
        #expect(preparation.entry.generatedPrompt.contains("Target and Materials are read-only"))
        #expect(preparation.checkpoint == nil)
        #expect(preparation.entry.checkpointID == nil)
        #expect(preparation.entry.includedComments.map(\.comment.id) == [commentID])
        #expect(preparation.instructions.contains("Scholium Dialogue locator"))
        #expect(preparation.instructions.contains(preparation.entry.id.uuidString))
        #expect(preparation.instructions.contains("scholium dialogue show"))
        #expect(try await handle.research.dialogue(id: preparation.entry.id) == preparation.entry)
        #expect(try await handle.research.checkpoints().checkpoints.isEmpty)

        let followUp = DialogueFollowUpComment(
            text: "Also distinguish premise from background context.",
            noteID: stableID,
            commentID: commentID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let updated = try await handle.research.appendDialogueFollowUpComment(
            followUp,
            to: preparation.entry.id
        )
        #expect(updated.followUpComments == [followUp])
        await runtime.shutdown()
    }

    @Test("Critique and recovery operations stay inside the Application boundary")
    func critiqueAndRecovery() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try #require(try await handle.snapshot().document(id: fixture.workID))

        let preparation = try await handle.research.requestCritique(
            for: fixture.workID,
            expectedRevision: work.fingerprint,
            scope: .both,
            lens: "Source fidelity",
            selectedRanges: "Lines 5-8",
            additionalInstructions: "Separate textual and argumentative concerns."
        )
        #expect(preparation.association.workRelativePath == fixture.workID.relativePath)
        #expect(preparation.association.rounds.count == 1)
        #expect(preparation.association.rounds.first?.checkpointID == preparation.checkpoint.id)
        #expect(preparation.instructions.contains("Write Critique to:"))
        #expect(preparation.instructions.contains("Source fidelity"))
        let critiqueID = VaultQualifiedNoteID(
            vaultID: fixture.workID.vaultID,
            relativePath: preparation.association.critiqueRelativePath
        )
        let critique = try await handle.documents.load(critiqueID)
        #expect(critique.parsedFrontmatter[CritiqueDocumentContract.authorshipKey]?.scalarString == "agent")
        #expect(critique.parsedFrontmatter[CritiqueDocumentContract.targetPathKey]?.scalarString
            == fixture.workID.relativePath)
        let projected = try #require(try await handle.snapshot().document(id: critiqueID))
        #expect(projected.stableIdentity.resolvedID != nil)
        #expect(try await handle.research.critique(
            critiqueRelativePath: preparation.association.critiqueRelativePath
        )?.id == preparation.association.id)

        // Seeding writes disposable fixture bytes before exercising only the
        // public delivery-neutral list/resolve surface and event publication.
        let recovery = TriptychMutationRecoveryRecord(
            triptychID: fixture.assignment.id,
            operation: .noteMove,
            failure: "Synthetic disposable-fixture rollback evidence",
            files: [TriptychMutationRecoveryFile(
                vaultID: fixture.analysisID.vaultID,
                path: fixture.analysisID.relativePath,
                role: .movedNote,
                beforeRevision: nil,
                intendedRevision: nil,
                observedRevision: nil,
                state: .externallyChanged,
                detail: "Fixture-only evidence"
            )]
        )
        try fixture.writeRecoveryFixture(recovery)
        _ = try await handle.discovery.refresh()
        #expect(try await handle.research.recoveryRecords().map(\.id) == [recovery.id])

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        try await handle.research.resolveRecoveryRecord(recovery.id)
        let event = try #require(await iterator.next())
        if case .researchRecordsChanged(let changed) = event {
            #expect(changed.research.recoveryRecords.isEmpty)
        } else {
            Issue.record("Resolving recovery evidence did not publish researchRecordsChanged.")
        }
        #expect(try await handle.research.recoveryRecords().isEmpty)
        await runtime.shutdown()
    }
}

@Suite("Application Research Function orchestration")
struct ResearchFunctionOperationsTests {
    @Test("Dialogue stays read-only, requires durable attributed reply evidence, and prepared runs cancel durably")
    func dialogueAndCancellation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        let originalProfile = try await handle.research.dialogueResponseProfile()

        let preparation = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .dialogue,
                target: target,
                instruction: "Change this Analysis into a stronger argument.",
                dialogueResponseModules: [
                    .criticalReflection,
                    .philosophicalSignificance,
                ]
            )
        )
        #expect(preparation.snapshot.checkpointID == nil)
        #expect(preparation.instructions.contains("Target and Materials are read-only"))
        #expect(preparation.instructions.contains("new Develop run"))
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == preparation.runID
        }?.preparedInstructions == preparation.instructions)
        #expect(try await handle.documents.load(fixture.analysisID).fingerprint == target.fingerprint)
        #expect(try await handle.research.checkpoints().checkpoints.isEmpty)
        let dialogue = try await handle.research.dialogue(id: preparation.runID)
        #expect(dialogue.responseContract?.knownModules == [
            .criticalReflection,
            .philosophicalSignificance,
        ])
        #expect(preparation.snapshot.request.dialogueResponseModules == [
            .criticalReflection,
            .philosophicalSignificance,
        ])
        #expect(preparation.instructions.contains("critical-reflection"))
        #expect(preparation.instructions.contains("philosophical-significance"))

        try await handle.research.saveDialogueResponseProfile(DialogueResponseProfile(
            modules: [.researchDirections]
        ))
        let unchangedDialogue = try await handle.research.dialogue(id: preparation.runID)
        #expect(unchangedDialogue.responseContract == dialogue.responseContract)
        #expect(unchangedDialogue.generatedPrompt == dialogue.generatedPrompt)
        #expect(unchangedDialogue.functionSnapshot?.request == preparation.snapshot.request)
        #expect(unchangedDialogue.responseContract?.profileRevision
            != originalProfile.profileRevision)

        let incomplete = ResearchFunctionCompletionSubmission(
            runID: preparation.runID,
            confirmationToken: preparation.snapshot.confirmationToken,
            finalTargetFingerprint: target.fingerprint,
            summary: "A reply was allegedly produced.",
            didModifyTarget: false
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(incomplete)
        }
        _ = try await handle.research.appendDialogueReply(
            DialogueReply(
                agentName: "Research Agent",
                text: "The requested change requires promotion to Develop.",
                createdAt: preparation.snapshot.preparedAt.addingTimeInterval(1)
            ),
            to: preparation.runID
        )
        let completed = try await handle.research.completeFunction(incomplete)
        #expect(completed.state == .complete)
        #expect(!completed.didModifyTarget)

        let fidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        try await handle.research.cancelFunction(runID: fidelity.runID)
        let cancelled = try #require(try await handle.snapshot().research.functionRuns
            .first { $0.id == fidelity.runID }?.completion)
        #expect(cancelled.state == .cancelled)
        await runtime.shutdown()
    }

    @Test("Markdown preparation is an executable immutable handoff")
    func completeMarkdownPreparationPacket() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let document = try await handle.documents.load(fixture.analysisID)
        let selectionRange = (document.rawContent as NSString).range(
            of: "Exact philosophical claim"
        )
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: selectionRange.location..<(selectionRange.location + selectionRange.length)
        ))
        let review = try await handle.research.addComment(
            to: fixture.analysisID,
            text: "Preserve the distinction between textual support and reconstruction.",
            anchor: anchor,
            expectedRevision: document.fingerprint
        )
        let commentID = try #require(review.comments.first?.id)
        let material = try #require(
            try await handle.research.materialCandidates(
                for: target,
                function: .develop
            ).first { $0.material.note == fixture.topicID }?.material
        )

        let preparation = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material],
                instruction: "Develop only the selected claim.",
                scope: .passage(anchor),
                commentIDs: [commentID]
            )
        )

        let packet = preparation.instructions
        #expect(packet.contains(fixture.assignment.id.uuidString.lowercased()))
        #expect(packet.contains(preparation.runID.uuidString.lowercased()))
        #expect(packet.contains(preparation.snapshot.confirmationToken.uuidString.lowercased()))
        #expect(packet.contains(target.noteID.uuidString.lowercased()))
        #expect(packet.contains(material.noteID.uuidString.lowercased()))
        #expect(packet.contains("\"quotation\" : \"Exact philosophical claim\""))
        #expect(packet.contains("\"line\""))
        #expect(packet.contains("\"utf8Range\""))
        #expect(packet.contains(commentID.uuidString))
        #expect(packet.contains("Preserve the distinction between textual support and reconstruction."))
        #expect(preparation.awaitsResourceSelection)
        #expect(packet.contains("## Finalize conditional resources"))
        #expect(packet.contains("scholium function select-resources"))
        #expect(!packet.contains("scholium function complete --from"))
        #expect(packet.contains("scholium function cancel"))
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == preparation.runID
        }?.preparedInstructions == packet)
        await runtime.shutdown()
    }

    @Test("External resource selection finalizes the same run with only exact conditional resources")
    func resourceSelectionFinalizesSameRun() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let material = try #require(
            try await handle.research.materialCandidates(
                for: target,
                function: .develop
            ).first { $0.material.note == fixture.topicID }?.material
        )
        let preflight = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material]
            )
        )
        let checkpointCount = try await handle.research.checkpoints().checkpoints.count
        let baseResources = Set(preflight.snapshot.phases
            .flatMap(\.skills)
            .flatMap(\.loadedResources)
            .map(\.relativePath))
        #expect(baseResources.contains("references/method.md"))
        #expect(!baseResources.contains("references/synthesis.md"))

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(
                ResearchFunctionCompletionSubmission(
                    runID: preflight.runID,
                    confirmationToken: preflight.snapshot.confirmationToken,
                    finalTargetFingerprint: target.fingerprint,
                    finalMaterialFingerprints: [material.noteID: material.fingerprint],
                    summary: "This must not bypass resource selection.",
                    didModifyTarget: false
                )
            )
        }

        let submission = ResearchFunctionResourceSelectionSubmission(
            runID: preflight.runID,
            confirmationToken: preflight.snapshot.confirmationToken,
            resources: [.developmentSynthesis]
        )
        let finalized = try await handle.research.selectFunctionResources(submission)
        #expect(!finalized.awaitsResourceSelection)
        #expect(finalized.snapshot.request.conditionalResources == [.developmentSynthesis])
        #expect(finalized.runID == preflight.runID)
        #expect(finalized.snapshot.recordID == preflight.snapshot.recordID)
        #expect(finalized.snapshot.checkpointID == preflight.snapshot.checkpointID)
        #expect(finalized.snapshot.preparedAt == preflight.snapshot.preparedAt)
        #expect(finalized.snapshot.confirmationToken == preflight.snapshot.confirmationToken)
        #expect(finalized.instructions.contains("scholium function complete --from"))
        let finalizedResources = Set(finalized.snapshot.phases
            .flatMap(\.skills)
            .flatMap(\.loadedResources)
            .map(\.relativePath))
        #expect(finalizedResources.contains("references/method.md"))
        #expect(finalizedResources.contains("references/synthesis.md"))
        #expect(!finalizedResources.contains("references/exploration.md"))
        #expect(!finalizedResources.contains("references/expression.md"))
        #expect(try await handle.research.checkpoints().checkpoints.count == checkpointCount)

        let repeated = try await handle.research.selectFunctionResources(submission)
        #expect(repeated.snapshot == finalized.snapshot)
        #expect(repeated.instructions == finalized.instructions)
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.selectFunctionResources(
                ResearchFunctionResourceSelectionSubmission(
                    runID: preflight.runID,
                    confirmationToken: preflight.snapshot.confirmationToken,
                    resources: [.developmentExploration]
                )
            )
        }

        let baseOnlyPreflight = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material]
            )
        )
        let baseOnly = try await handle.research.selectFunctionResources(
            ResearchFunctionResourceSelectionSubmission(
                runID: baseOnlyPreflight.runID,
                confirmationToken: baseOnlyPreflight.snapshot.confirmationToken,
                resources: []
            )
        )
        #expect(baseOnly.snapshot.request.conditionalResources == [])
        #expect(!baseOnly.snapshot.phases.flatMap(\.skills)
            .flatMap(\.loadedResources).contains {
                $0.relativePath == "references/synthesis.md"
            })

        let stalePreflight = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material]
            )
        )
        let topic = try await handle.documents.load(fixture.topicID)
        _ = try await handle.documents.save(
            fixture.topicID,
            changeSet: .exactContent(topic.rawContent + "\nChanged after preflight.\n"),
            expectedRevision: topic.fingerprint
        )
        let checkpointCountBeforeStaleSelection = try await handle.research
            .checkpoints().checkpoints.count
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.selectFunctionResources(
                ResearchFunctionResourceSelectionSubmission(
                    runID: stalePreflight.runID,
                    confirmationToken: stalePreflight.snapshot.confirmationToken,
                    resources: [.developmentSynthesis]
                )
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.count
            == checkpointCountBeforeStaleSelection)
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == stalePreflight.runID
        }?.snapshot.request.conditionalResources == nil)
        await runtime.shutdown()
    }

    @Test("Preparation rejects stale Target and Material fingerprints without checkpoint or record residue")
    func fingerprintValidationAndRollback() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.materialCandidates(
            for: target,
            function: .develop
        )
        #expect(!candidates.contains { $0.material.noteID == target.noteID })
        let topic = try #require(candidates.first {
            $0.material.note == fixture.topicID
        }?.material)
        let originalRuns = try await handle.snapshot().research.functionRuns.count
        let originalCheckpoints = try await handle.research.checkpoints().checkpoints.count

        let topicDocument = try await handle.documents.load(fixture.topicID)
        _ = try await handle.documents.save(
            fixture.topicID,
            changeSet: .exactContent(topicDocument.rawContent + "\nA changed Material.\n"),
            expectedRevision: topicDocument.fingerprint
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.prepareFunction(
                ResearchFunctionRequest(
                    function: .develop,
                    target: target,
                    materials: [topic]
                )
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.count == originalCheckpoints)
        #expect(try await handle.snapshot().research.functionRuns.count == originalRuns)

        let targetDocument = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(targetDocument.rawContent + "\nA changed Target.\n"),
            expectedRevision: targetDocument.fingerprint
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.prepareFunction(
                ResearchFunctionRequest(function: .develop, target: target)
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.count == originalCheckpoints)
        #expect(try await handle.snapshot().research.functionRuns.count == originalRuns)
        await runtime.shutdown()
    }

    @Test("Material suggestions use only resolved one-hop links and preserve catalog aliases")
    func materialCandidateSuggestions() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.materialCandidates(
            for: target,
            function: .develop
        )

        let agency = try #require(candidates.first {
            $0.material.note == fixture.topicID
        })
        #expect(agency.aliases.contains("Freedom"))
        #expect(agency.suggestionReasons.map(\.kind) == [.linkedFromTarget])
        #expect(agency.suggestionReasons.first?.sourceNote == target.note)

        let work = try #require(candidates.first {
            $0.material.note == fixture.workID
        })
        #expect(work.suggestionReasons.map(\.kind) == [.linksDirectlyToTarget])
        #expect(work.suggestionReasons.first?.sourceNote == fixture.workID)

        let transitive = try #require(candidates.first {
            $0.material.note.relativePath == "Debates/Nested Topic.md"
        })
        #expect(transitive.suggestionReasons.isEmpty)
        #expect(!candidates.contains { $0.material.note == target.note })
        await runtime.shutdown()
    }

    @Test("Human Review rejects the agent Materials candidate boundary")
    func humanReviewRejectsMaterialCandidates() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.materialCandidates(
                for: target,
                function: .review
            )
        }
        #expect(try await handle.snapshot().research.functionRuns.isEmpty)
        await runtime.shutdown()
    }

    @Test("Automatic Fidelity prepares an independent final-revision child and reuses its evidence")
    func automaticFidelityOrchestration() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA developed claim.\n"),
            expectedRevision: original.fingerprint
        )
        let awaiting = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Developed one bounded claim.",
                didModifyTarget: true
            )
        )
        #expect(awaiting.state == .awaitingFidelity)

        let afterCompletion = try await handle.snapshot().research.functionRuns
        let automaticallyPrepared = try #require(afterCompletion.first { record in
            record.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        })
        #expect(automaticallyPrepared.completion == nil)
        #expect(automaticallyPrepared.preparedInstructions?.isEmpty == false)

        let automatic = try await handle.research.prepareAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(automatic.state == .prepared)
        #expect(automatic.effectiveFidelityRunID == automaticallyPrepared.id)
        #expect(automatic.preparation.snapshot.resolvedFidelityInvocation == .automatic(
            parentRunID: develop.runID
        ))
        #expect(automatic.preparation.snapshot.request.target.fingerprint
            == saved.document.fingerprint)
        #expect(automatic.preparation.snapshot.request.checks
            == develop.snapshot.fidelityHandoff?.checks)
        #expect(automatic.preparation.snapshot.request.materials
            == develop.snapshot.request.materials)
        #expect(automatic.preparation.snapshot.request.scope
            == develop.snapshot.request.scope)
        #expect(automatic.preparation.snapshot.request.commentIDs
            == develop.snapshot.request.commentIDs)

        let repeated = try await handle.research.prepareAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(repeated.state == .prepared)
        #expect(repeated.effectiveFidelityRunID == automatic.effectiveFidelityRunID)
        #expect(try await handle.snapshot().research.functionRuns.filter {
            $0.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        }.count == 1)

        let fidelityCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: automatic.preparation.runID,
                confirmationToken: automatic.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Checked the exact final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let completedProjection = try await handle.research.prepareAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(completedProjection.state == .complete)
        #expect(completedProjection.effectiveFidelityRunID == fidelityCompletion.runID)

        let verified = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                childRunIDs: [automatic.preparation.runID]
            )
        )
        #expect(verified.state == .complete)
        #expect(verified.reusedFidelityRunID == fidelityCompletion.runID)

        let currentTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let manualReuse = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: currentTarget,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        #expect(manualReuse.state == .complete)
        #expect(manualReuse.reusedCompletion?.runID == fidelityCompletion.runID)
        #expect(manualReuse.snapshot.resolvedFidelityInvocation == .manual)
        await runtime.shutdown()
    }

    @Test("Unchanged Develop and Revise runs complete without Automatic Fidelity")
    func unchangedWritesSkipAutomaticFidelity() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .develop, target: analysis, conditionalResources: [])
        )

        // Even matching completed manual evidence cannot be attached to an
        // unchanged substantive run: there is no post-edit revision to audit.
        let manual = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: analysis,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: manual.runID,
                confirmationToken: manual.snapshot.confirmationToken,
                finalTargetFingerprint: analysis.fingerprint,
                summary: "Checked the unchanged Analysis revision manually.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    finalTargetFingerprint: analysis.fingerprint,
                    summary: "No Analysis change was needed.",
                    didModifyTarget: false,
                    childRunIDs: [manual.runID]
                )
            )
        }

        let unchangedDevelop = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                finalTargetFingerprint: analysis.fingerprint,
                summary: "No Analysis change was needed.",
                didModifyTarget: false
            )
        )
        #expect(unchangedDevelop.state == .complete)
        #expect(!unchangedDevelop.didModifyTarget)
        #expect(unchangedDevelop.childRunIDs == nil)
        #expect(unchangedDevelop.reusedFidelityRunID == nil)

        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let revise = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let unchangedRevise = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "No Work change was needed.",
                didModifyTarget: false
            )
        )
        #expect(unchangedRevise.state == .complete)
        #expect(!unchangedRevise.didModifyTarget)
        #expect(unchangedRevise.childRunIDs == nil)
        #expect(unchangedRevise.reusedFidelityRunID == nil)

        for parentRunID in [develop.runID, revise.runID] {
            await #expect(throws: ResearchFunctionContractError.self) {
                _ = try await handle.research.prepareAutomaticFidelity(
                    parentRunID: parentRunID
                )
            }
        }
        let records = try await handle.snapshot().research.functionRuns
        let automaticChildren = records.filter { record in
            guard case .automatic(let parentRunID)? =
                    record.snapshot.resolvedFidelityInvocation else {
                return false
            }
            return parentRunID == develop.runID || parentRunID == revise.runID
        }
        #expect(automaticChildren.isEmpty)
        await runtime.shutdown()
    }

    @Test("Automatic Fidelity immediately links exact completed manual evidence")
    func automaticFidelityReusesCompletedManualEvidence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA developed claim.\n"),
            expectedRevision: original.fingerprint
        )
        let finalTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let manual = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        let manualCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: manual.runID,
                confirmationToken: manual.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )

        let completed = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Developed one bounded claim.",
                didModifyTarget: true
            )
        )
        #expect(completed.state == .complete)
        #expect(completed.reusedFidelityRunID == manualCompletion.runID)
        #expect(completed.childRunIDs == [manualCompletion.runID])
        #expect(try await handle.snapshot().research.functionRuns.filter {
            $0.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        }.isEmpty)
        await runtime.shutdown()
    }

    @Test("Develop records its exact Fidelity handoff, advances completion, deduplicates exact audits, and marks later evidence stale")
    func fidelityHandoffDeduplicationAndStaleness() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        #expect(develop.snapshot.checkpointID != nil)
        #expect(develop.snapshot.phases.map(\.function) == [.develop])
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(develop.snapshot.fidelityHandoff?.checks == [.content])
        #expect(develop.snapshot.fidelityHandoff?.preparedTargetFingerprint == target.fingerprint)
        #expect(!develop.instructions.contains("## Isolated phase 2: fidelity"))
        #expect(develop.instructions.contains("separate Fidelity function"))
        let developmentResources = Set(develop.snapshot.phases
            .first { $0.function == .develop }?.skills
            .flatMap(\.loadedResources).map(\.relativePath) ?? [])
        #expect(developmentResources.contains("references/method.md"))
        #expect(!developmentResources.contains("references/exploration.md"))
        #expect(!developmentResources.contains("references/synthesis.md"))
        #expect(!developmentResources.contains("references/expression.md"))
        #expect(!developmentResources.contains("references/definition-impact.md"))
        #expect(try await handle.snapshot().research.functionRuns.contains {
            $0.id == develop.runID
        })

        let preEditFidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        _ = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: preEditFidelity.runID,
                confirmationToken: preEditFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked only the pre-edit Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )

        let original = try await handle.documents.load(fixture.analysisID)
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA bounded developed claim.\n"),
            expectedRevision: original.fingerprint
        )
        #expect(try await handle.snapshot().research.functionRuns.contains {
            $0.id == develop.runID
        })
        let awaitingSubmission = ResearchFunctionCompletionSubmission(
            runID: develop.runID,
            confirmationToken: develop.snapshot.confirmationToken,
            finalTargetFingerprint: saved.document.fingerprint,
            summary: "Developed one bounded claim.",
            didModifyTarget: true
        )
        let awaiting = try await handle.research.completeFunction(awaitingSubmission)
        #expect(awaiting.state == .awaitingFidelity)
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    finalTargetFingerprint: saved.document.fingerprint,
                    summary: "Tried to reuse an audit of the pre-edit revision.",
                    didModifyTarget: true,
                    childRunIDs: [preEditFidelity.runID]
                )
            )
        }
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    finalTargetFingerprint: saved.document.fingerprint,
                    summary: "Tried to attach an unprepared audit claim.",
                    didModifyTarget: true,
                    fidelityOutcomes: [.passedContent]
                )
            )
        }

        let finalTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let finalFidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: [.content]
            )
        )
        let finalFidelityCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: finalFidelity.runID,
                confirmationToken: finalFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact post-edit Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let verified = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                childRunIDs: [finalFidelity.runID]
            )
        )
        #expect(verified.state == .complete)
        #expect(verified.fidelityEvidenceKey == finalFidelityCompletion.fidelityEvidenceKey)
        #expect(verified.reusedFidelityRunID == finalFidelity.runID)

        let directReuse = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: [.content]
            )
        )
        #expect(directReuse.state == .complete)
        #expect(directReuse.reusedCompletion?.runID == finalFidelity.runID)

        let finalDocument = try await handle.documents.load(fixture.analysisID)
        let commentRecord = try await handle.research.addComment(
            to: fixture.analysisID,
            text: "Check this additional evidence-bound concern.",
            anchor: try commentAnchor(in: finalDocument),
            expectedRevision: finalTarget.fingerprint
        )
        let commentID = try #require(commentRecord.comments.first?.id)
        let auditRequest = ResearchFunctionRequest(
            function: .fidelity,
            target: finalTarget,
            checks: [.content],
            commentIDs: [commentID]
        )
        let audit = try await handle.research.prepareFunction(auditRequest)
        let auditCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: audit.runID,
                confirmationToken: audit.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the final Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let reused = try await handle.research.prepareFunction(auditRequest)
        #expect(reused.state == .complete)
        #expect(reused.reusedCompletion?.runID == auditCompletion.runID)

        let current = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(current.rawContent + "\nEvidence changed after audit.\n"),
            expectedRevision: current.fingerprint
        )
        let stale = try #require(try await handle.snapshot().research.functionRuns
            .first { $0.id == audit.runID }?.completion)
        #expect(stale.state == .stale)
        await runtime.shutdown()
    }

    @Test("Explicit citation style reaches Fidelity resources, instructions, snapshots, and evidence")
    func citationStyleExecutionBinding() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let status = try await handle.research.adoptBundledCitationStarter(
            expectedBindingRevision: nil
        )
        #expect(status.activeCitationStyle == "apa-7")
        #expect(status.activePackageID != nil)

        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let fidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content, .citations]
            )
        )
        let phase = try #require(fidelity.snapshot.phases.first {
            $0.function == .fidelity
        })
        #expect(phase.citationStyle == "apa-7")
        #expect(phase.skills.flatMap(\.loadedResources).contains {
            $0.relativePath == "references/apa-7-starter.md"
        })
        #expect(fidelity.instructions.contains("Citation style: apa-7"))

        let completion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked content and citations under the selected style.",
                didModifyTarget: false,
                fidelityOutcomes: [
                    .passed(.content),
                    .passed(.citations),
                ]
            )
        )
        #expect(completion.fidelityEvidenceKey != nil)

        let develop = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        #expect(develop.snapshot.fidelityHandoff?.checks == [.content, .citations])
        #expect(develop.snapshot.phases.map(\.function) == [.develop])
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(!develop.instructions.contains("Citation style: apa-7"))
        try await handle.research.cancelFunction(runID: develop.runID)
        await runtime.shutdown()
    }

    @Test("Draft inspection preserves protected package collisions")
    func draftInspectionPreservesProtectedCollision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let source = """
        ---
        name: Conflicting Development
        description: A researcher-owned draft with a protected identifier.
        ---
        Keep the method explicit.
        """ + "\n"
        let packageURL = fixture.rootURL.appendingPathComponent(
            ".scholium/skills/scholium-development",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try Data(source.utf8).write(
            to: packageURL.appendingPathComponent("SKILL.md"),
            options: .atomic
        )

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let inspected = await handle.research.inspectSkillDraft(
            id: "scholium-development",
            source: source,
            origin: .triptych
        )
        #expect(!inspected.isValid)
        #expect(inspected.validationIssues.contains {
            $0.contains("protected Scholium package")
        })
        await runtime.shutdown()
    }

    @Test("Settings activation selects Researcher Skills for later function runs")
    func researcherSkillFunctionActivation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let prose = try await handle.research.duplicateBundledSkill(
            id: "scholium-prose-control",
            as: "my-prose-control"
        )
        let practices = try await handle.research.duplicateBundledSkill(
            id: "scholium-philosophical-practices",
            as: "my-practices"
        )

        let initial = try await handle.research
            .researchFunctionSkillBindingStatus(for: .revise)
        #expect(initial.selection.isEmpty)
        #expect(initial.candidates.first { $0.packageID == prose.id }?.name == "Prose Control")
        #expect(initial.candidates.first { $0.packageID == prose.id }?.availableRoles
            == [.supplemental])
        #expect(initial.candidates.first { $0.packageID == practices.id }?.practiceIDs
            .contains("philosophical-expositor") == true)

        let practice = ResearchPracticeSelection(
            packageID: practices.id,
            practiceID: "philosophical-expositor"
        )
        let active = try await handle.research.saveResearchFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .revise,
                supplementalPackageIDs: [prose.id],
                selectedPractices: [practice]
            ),
            expectedBindingRevision: initial.bindingRevision
        )
        #expect(active.selection.supplementalPackageIDs == [prose.id])
        #expect(active.selection.selectedPractices == [practice])
        #expect(active.bindingRevision != nil)

        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let preparation = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let phase = try #require(preparation.snapshot.phases.first {
            $0.function == .revise
        })
        #expect(phase.skills.contains { $0.packageID == prose.id })
        let selectedPractice = try #require(phase.skills.first {
            $0.packageID == practices.id
        })
        #expect(selectedPractice.loadedResources.map(\.relativePath).contains(
            "references/Philosophical-Expositor.md"
        ))

        let cleared = try await handle.research.clearResearchFunctionSkillSelection(
            for: .revise,
            expectedBindingRevision: active.bindingRevision
        )
        #expect(cleared.selection.isEmpty)
        await runtime.shutdown()
    }

    @Test("Legacy incompatible and replacement Practices expose typed repair")
    func legacyPracticeBindingRepair() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let practices = try await handle.research.duplicateBundledSkill(
            id: "scholium-philosophical-practices",
            as: "my-legacy-practices"
        )
        let bindingURL = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("research-skill-bindings.json")

        let incompatible = """
        {
          "schema_version": 1,
          "function_bindings": {},
          "function_skill_bindings": {},
          "function_practice_bindings": {
            "revise": [
              {
                "package_id": "\(practices.id)",
                "practice_id": "reviewer",
                "application": "supplement"
              }
            ]
          }
        }
        """
        try Data(incompatible.utf8).write(to: bindingURL, options: .atomic)
        let invalidStatus = try await handle.research
            .researchFunctionSkillBindingStatus(for: .revise)
        #expect(invalidStatus.issue?.code == .invalidPractice)
        #expect(invalidStatus.issue?.selectedPracticeID == "reviewer")

        let replacement = """
        {
          "schema_version": 1,
          "function_bindings": {},
          "function_skill_bindings": {},
          "function_practice_bindings": {
            "critique": [
              {
                "package_id": "\(practices.id)",
                "practice_id": "reviewer",
                "application": "replace",
                "official_skill_id": "scholium-critique",
                "editable_point": "review calibration",
                "scope": "one Critique",
                "reason": "legacy fixture"
              }
            ]
          }
        }
        """
        try Data(replacement.utf8).write(to: bindingURL, options: .atomic)
        let replacementStatus = try await handle.research
            .researchFunctionSkillBindingStatus(for: .critique)
        #expect(replacementStatus.issue?.code == .legacyReplacementPractice)
        #expect(replacementStatus.issue?.selectedPracticeID == "reviewer")
        await runtime.shutdown()
    }

    @Test("Critique completion binds a changed separate record, while Manuscript selects independent revision-specific child runs")
    func critiqueAndManuscriptChildren() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )

        let critique = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .critique,
                target: work,
                scope: .whole,
                conditionalResources: []
            )
        )
        let critiqueOutput = try #require(critique.snapshot.preparedOutput)
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == critique.runID
        }?.preparedInstructions == critique.instructions)
        let missingOutput = ResearchFunctionCompletionSubmission(
            runID: critique.runID,
            confirmationToken: critique.snapshot.confirmationToken,
            finalTargetFingerprint: work.fingerprint,
            summary: "Critique completed.",
            didModifyTarget: false
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeFunction(missingOutput)
        }
        let critiqueDocument = try await handle.documents.load(critiqueOutput.note)
        let savedCritique = try await handle.documents.save(
            critiqueOutput.note,
            changeSet: .exactContent(
                critiqueDocument.rawContent
                    + "\n## Finding\n\nThe inference needs an explicit premise.\n"
            ),
            expectedRevision: critiqueDocument.fingerprint
        )
        #expect(try await handle.snapshot().research.functionRuns.contains {
            $0.id == critique.runID
        })
        let critiqueCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: critique.runID,
                confirmationToken: critique.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Recorded one bounded Critique finding.",
                didModifyTarget: false,
                outputFingerprint: savedCritique.document.fingerprint
            )
        )
        #expect(critiqueCompletion.outputFingerprint == savedCritique.document.fingerprint)
        #expect(try await handle.documents.load(fixture.workID).fingerprint == work.fingerprint)

        let manuscript = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .manuscript, target: work, conditionalResources: [])
        )
        #expect(manuscript.snapshot.requiredChildFunctions.isEmpty)
        #expect(!manuscript.instructions.contains("Critique, then Revise, then Fidelity"))
        let revise = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let workDocument = try await handle.documents.load(fixture.workID)
        let revised = try await handle.documents.save(
            fixture.workID,
            changeSet: .exactContent(
                workDocument.rawContent
                    + "\nAn explicit premise now supports the inference.\n"
            ),
            expectedRevision: workDocument.fingerprint
        )
        let awaitingRevision = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                finalTargetFingerprint: revised.document.fingerprint,
                summary: "Revised the inference; final Fidelity remains pending.",
                didModifyTarget: true
            )
        )
        #expect(awaitingRevision.state == .awaitingFidelity)

        work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let revisionFidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: work,
                checks: try #require(revise.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revisionFidelity.runID,
                confirmationToken: revisionFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Checked the exact final Work revision.",
                didModifyTarget: false,
                fidelityOutcomes: try #require(revise.snapshot.fidelityHandoff).checks
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map(FidelityCheckOutcome.passed)
            )
        )
        let reviseCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Revised the inference and linked final Fidelity evidence.",
                didModifyTarget: true,
                childRunIDs: [revisionFidelity.runID]
            )
        )
        #expect(reviseCompletion.state == .complete)
        let fidelityReuse = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: work,
                checks: [.content]
            )
        )
        #expect(fidelityReuse.state == .complete)
        #expect(fidelityReuse.reusedCompletion?.runID == revisionFidelity.runID)
        let completedManuscript = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: manuscript.runID,
                confirmationToken: manuscript.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Coordinated the selected manuscript activities.",
                didModifyTarget: true,
                childRunIDs: [revise.runID]
            )
        )
        #expect(completedManuscript.state == .complete)
        #expect(completedManuscript.childRunIDs == [revise.runID])
        #expect(completedManuscript.reusedFidelityRunID == revise.runID)
        await runtime.shutdown()
    }

    @Test("Recommended Bibliography is Analysis-only, immutable, and accepts zero results")
    func recommendedBibliographyLifecycle() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try #require(
            try await handle.snapshot().document(id: fixture.analysisID)
        )
        let stableID = try #require(analysis.stableIdentity.resolvedID)
        let target = RecommendedBibliographyTarget(
            noteID: stableID,
            note: fixture.analysisID,
            fingerprint: analysis.fingerprint,
            title: "Analysis"
        )
        let preparation = try await handle.research.prepareRecommendation(
            RecommendedBibliographyRequest(
                target: target,
                goals: [.objections, .replies],
                purpose: "Identify only source-grounded reading leads."
            )
        )
        #expect(preparation.method.packageID == "scholium-source-analyzer")
        #expect(preparation.method.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/bibliography-recommendations.md",
            "references/method.md",
            "templates/recommended-bibliography-completion.json",
        ])
        #expect(preparation.method.renderedResources.map(\.relativePath)
            == preparation.method.loadedResources.map(\.relativePath))
        #expect(preparation.method.renderedResources.allSatisfy { resource in
            DocumentFingerprint(content: resource.source) == resource.revision
                && preparation.instructions.contains(resource.source)
        })
        #expect(preparation.instructions.contains("Reading leads, not evidence"))
        #expect(preparation.instructions.contains("\"identity\""))
        #expect(preparation.instructions.contains("\"discussionStatus\""))
        #expect(preparation.instructions.contains("\"requiredNextCheck\""))
        #expect(try await handle.documents.load(fixture.analysisID).fingerprint == analysis.fingerprint)

        let projection = try await handle.research.completeRecommendation(
            RecommendedBibliographyCompletionSubmission(
                requestID: preparation.id,
                confirmationToken: preparation.confirmationToken,
                targetFingerprint: analysis.fingerprint,
                sourceScope: "Complete Analysis and its documented source scope",
                candidates: []
            )
        )
        #expect(projection.state == .complete)
        #expect(projection.candidates.isEmpty)
        #expect(try await handle.research.recommendations(for: target) == projection)
        #expect(try await handle.research.recommendationOverview(for: target).result == projection)
        #expect(try await handle.documents.load(fixture.analysisID).fingerprint == analysis.fingerprint)

        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        await #expect(throws: RecommendedBibliographyError.self) {
            _ = try await handle.research.prepareRecommendation(
                RecommendedBibliographyRequest(
                    target: RecommendedBibliographyTarget(
                        noteID: work.noteID,
                        note: work.note,
                        fingerprint: work.fingerprint,
                        title: work.title
                    )
                )
            )
        }
        await runtime.shutdown()
    }
}

private struct ResearchFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let analysesURL: URL
    let assignment: TriptychAssignment
    let analysisID: VaultQualifiedNoteID
    let topicID: VaultQualifiedNoteID
    let workID: VaultQualifiedNoteID

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumApplicationResearchTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let registryURL = root.appendingPathComponent("Registry", isDirectory: true)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for directory in [appSupport, analyses, topics, works] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let analysisSource = "\u{FEFF}---\r\ntitle: Analysis\r\nresearch_unit:\r\n  scope: 'One bounded source'\r\nunknown_key: 'preserve me'\r\n---\r\n# Analysis\r\n\r\nExact philosophical claim with a narrow reconstruction. See [[Agency]].\r\n"
        try Data(analysisSource.utf8).write(
            to: analyses.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        try Data("---\ntitle: Agency\naliases:\n  - Freedom\n---\n# Agency\n\nSee [[Nested Topic]].\n".utf8).write(
            to: topics.appendingPathComponent("Agency.md"),
            options: .atomic
        )
        let debates = topics.appendingPathComponent("Debates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: debates,
            withIntermediateDirectories: true
        )
        try Data("---\ntitle: Nested Topic\n---\n# Nested Topic\n".utf8).write(
            to: debates.appendingPathComponent("Nested Topic.md"),
            options: .atomic
        )
        try Data("---\ntitle: Draft Argument\nkind: chapter\n---\n# Draft Argument\n\nA claim requiring Critique. See [[Analysis]].\n".utf8).write(
            to: works.appendingPathComponent("Draft Argument.md"),
            options: .atomic
        )

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: appSupport,
            workspaceRegistryStorageURL: registryURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychName: "Research Operations Fixture"
        )
        let assignment = handle.assignment
        let analysisVaultID = try #require(assignment.vault(for: .paperAnalysis)?.id)
        let topicVaultID = try #require(assignment.vault(for: .topicKnowledge)?.id)
        let workVaultID = try #require(assignment.vault(for: .output)?.id)
        await runtime.shutdown()
        return Self(
            rootURL: root,
            applicationSupportURL: appSupport,
            analysesURL: analyses,
            assignment: assignment,
            analysisID: VaultQualifiedNoteID(
                vaultID: analysisVaultID,
                relativePath: "Analysis.md"
            ),
            topicID: VaultQualifiedNoteID(
                vaultID: topicVaultID,
                relativePath: "Agency.md"
            ),
            workID: VaultQualifiedNoteID(
                vaultID: workVaultID,
                relativePath: "Draft Argument.md"
            )
        )
    }

    func runtime() -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            assignments: [assignment]
        )))
    }

    func writeRecoveryFixture(_ record: TriptychMutationRecoveryRecord) throws {
        let storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(RecoveryFixturePayload(records: [record]))
        try data.write(
            to: storageURL.appendingPathComponent("transaction-recovery.json"),
            options: .atomic
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func researchFunctionTarget(
    _ id: VaultQualifiedNoteID,
    role: ResearchFunctionTargetRole,
    handle: WorkspaceHandle
) async throws -> ResearchFunctionTarget {
    let note = try #require(try await handle.snapshot().document(id: id))
    return ResearchFunctionTarget(
        noteID: try #require(note.stableIdentity.resolvedID),
        note: id,
        role: role,
        lifecycle: note.lifecycle,
        fingerprint: note.fingerprint,
        title: note.document.parsedFrontmatter["title"]?.scalarString ?? id.relativePath
    )
}

private func commentAnchor(
    in document: NoteDocument,
    quotation: String = "Exact philosophical claim"
) throws -> ResearcherCommentAnchor {
    let range = try #require(document.rawContent.range(of: quotation))
    let lowerUTF16 = range.lowerBound.utf16Offset(in: document.rawContent)
    let upperUTF16 = range.upperBound.utf16Offset(in: document.rawContent)
    return try #require(ResearcherCommentAnchorBuilder.anchor(
        in: document.rawContent,
        fingerprint: document.fingerprint,
        utf16Range: lowerUTF16..<upperUTF16
    ))
}

private extension FidelityCheckOutcome {
    static let passedContent = passed(.content)

    static func passed(_ check: FidelityCheck) -> Self {
        Self(
            check: check,
            state: .passed,
            summary: "The named check found no unresolved issue in this fixture revision."
        )
    }
}

private struct RecoveryFixturePayload: Codable {
    let records: [TriptychMutationRecoveryRecord]
}
