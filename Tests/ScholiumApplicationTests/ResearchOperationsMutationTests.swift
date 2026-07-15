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
        #expect(reattached.comments.first?.anchor?.state == .attached)
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

    @Test("Dialogue preparation persists its checkpoint and immutable request contract")
    func dialoguePreparation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(try await handle.snapshot().document(id: fixture.analysisID))
        let stableID = try #require(note.stableIdentity.resolvedID)
        let commentRecord = try await handle.research.addComment(
            to: fixture.analysisID,
            text: "Preserve this distinction.",
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
        #expect(preparation.entry.generatedPrompt.isEmpty)
        #expect(preparation.entry.checkpointID == preparation.checkpoint.id)
        #expect(preparation.entry.includedComments.map(\.comment.id) == [commentID])
        #expect(preparation.instructions.contains("Scholium Dialogue locator"))
        #expect(preparation.instructions.contains(preparation.entry.id.uuidString))
        #expect(preparation.instructions.contains("scholium dialogue show"))
        #expect(try await handle.research.dialogue(id: preparation.entry.id) == preparation.entry)
        #expect(try await handle.research.checkpoints().checkpoints.contains {
            $0.id == preparation.checkpoint.id
        })

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

private struct ResearchFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let analysesURL: URL
    let assignment: TriptychAssignment
    let analysisID: VaultQualifiedNoteID
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

        let analysisSource = "\u{FEFF}---\r\ntitle: Analysis\r\nunknown_key: 'preserve me'\r\n---\r\n# Analysis\r\n\r\nExact philosophical claim with a narrow reconstruction.\r\n"
        try Data(analysisSource.utf8).write(
            to: analyses.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        try Data("---\ntitle: Agency\n---\n# Agency\n".utf8).write(
            to: topics.appendingPathComponent("Agency.md"),
            options: .atomic
        )
        try Data("---\ntitle: Draft Argument\nkind: chapter\n---\n# Draft Argument\n\nA claim requiring Critique.\n".utf8).write(
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

private struct RecoveryFixturePayload: Codable {
    let records: [TriptychMutationRecoveryRecord]
}
