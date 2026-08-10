import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Authenticated bounded Research write sets", .serialized)
struct ResearchBoundedWriteOperationsTests {
    @Test("Only Agent writes can enter the bounded Research write ledger")
    func boundedWriteActorIsAgentOnly() {
        let starting = DocumentFingerprint(content: "starting")
        let ending = DocumentFingerprint(content: "ending")
        #expect(throws: ResearchBoundedWriteSetError.invalidWriteRecord) {
            _ = try ResearchDocumentWriteRecord(
                id: UUID(),
                runID: UUID(),
                target: ResearchWriteTargetHandle(rawValue: "target-handle-00000001")!,
                actor: .researcher,
                operation: .modifyMarkdown,
                requestFingerprint: DocumentFingerprint(content: "request"),
                expectedRevision: starting,
                intendedRevision: ending,
                observedRevision: ending,
                state: .committed,
                checkpointID: UUID(),
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 11)
            )
        }
    }

    @Test("Agent write warnings preserve every committed post-save condition")
    func combinedCommittedWarningsRemainBounded() throws {
        let warning = try #require(boundedResearchDocumentWriteWarning([
            "Displaced source cleanup pending.",
            "Derived refresh failed.",
            "Identity recovery incomplete.",
        ]))
        #expect(warning.contains("Displaced source cleanup pending."))
        #expect(warning.contains("Derived refresh failed."))
        #expect(warning.contains("Identity recovery incomplete."))

        let oversized = try #require(boundedResearchDocumentWriteWarning([
            String(repeating: "清", count: 3_000),
            String(repeating: "d", count: 5_000),
            String(repeating: "i", count: 5_000),
        ]))
        #expect(oversized.utf8.count <= 4_096)
        #expect(oversized.contains("清"))
        #expect(oversized.contains("d"))
        #expect(oversized.contains("i"))
    }

    @Test("Full Access extends one Run to two documents and writes them sequentially with idempotent retry")
    func fullAccessMultiDocumentWrite() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let initialContext = try await handle.research.authenticatedAgentContext(
            credential: connection.credential,
            run: connection.handoff.run
        )
        #expect(initialContext.boundedWriteSet.map(\.relativePath) == ["Analysis.md"])
        let contextJSON = String(
            decoding: try JSONEncoder().encode(initialContext),
            as: UTF8.self
        )
        for forbidden in [
            "expected_revision", "checkpoint_id", "note_id", "capability",
            "authorization_revision",
        ] {
            #expect(!contextJSON.contains(forbidden))
        }

        let policy = try await handle.research.collaborationPolicy()
        _ = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .fullAccess
            ),
            expectedRevision: policy.revision
        )
        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: true)
        )
        #expect(extensionResult.state == .allowedSubset)
        #expect(extensionResult.entries.map(\.relativePath).sorted() == [
            "Agency.md", "Analysis.md", "Draft Argument.md",
        ])
        let reloadedContext = try await handle.research.authenticatedAgentContext(
            credential: connection.credential,
            run: connection.handoff.run
        )
        #expect(reloadedContext.boundedWriteSet.map(\.relativePath).sorted() == [
            "Agency.md", "Analysis.md", "Draft Argument.md",
        ])

        let topic = try await handle.documents.load(fixture.topicID)
        let topicIntent = try ResearchDocumentWriteIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
            role: .topic,
            relativePath: "Agency.md",
            content: topic.rawContent + "\nAgent-bounded topic addition.\n"
        )
        let topicWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: topicIntent
        )
        #expect(topicWrite.state == .committed)
        let retry = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: topicIntent
        )
        #expect(retry == topicWrite)

        let work = try await handle.documents.load(fixture.workID)
        let workWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!,
                role: .work,
                relativePath: "Draft Argument.md",
                content: work.rawContent + "\nAgent-bounded work addition.\n"
            )
        )
        #expect(workWrite.state == .committed)
        #expect(try await handle.documents.load(fixture.topicID).rawContent
            .hasSuffix("Agent-bounded topic addition.\n"))
        #expect(try await handle.documents.load(fixture.workID).rawContent
            .hasSuffix("Agent-bounded work addition.\n"))

        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        #expect(stored.documentWriteRecords.count == 2)
        #expect(Set(stored.boundedWriteSet.entries.map(\.checkpointID)).count == 3)
        #expect(try await handle.snapshot().research.activities.contains {
            $0.runID == connection.preparation.runID && $0.state == .running
        })
        await runtime.shutdown()
    }

    @Test("Ask Every Time grants only the selected subset and one conflict does not poison another member")
    func explicitSubsetAndPerDocumentConflict() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let pending = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: true)
        )
        #expect(pending.state == .pending)
        let pendingRecord = try await handle.services.localResearchExecutionStore
            .writeSetExtension(
                runID: connection.preparation.runID,
                requestID: pending.requestID
            )
        let topicHandle = try #require(pendingRecord.candidates.first {
            $0.note.relativePath == "Agency.md"
        }?.handle)
        let decided = try await handle.research.resolveAgentWriteSetExtension(
            requestID: pending.requestID,
            state: .allowedSubset,
            allowedHandles: [topicHandle]
        )
        #expect(decided.state == .allowedSubset)
        #expect(decided.allowedHandles == [topicHandle])

        try Data("---\ntitle: Agency\n---\n# Agency\n\nExternal revision.\n".utf8)
            .write(
                to: fixture.rootURL
                    .appendingPathComponent("Topics", isDirectory: true)
                    .appendingPathComponent("Agency.md"),
                options: .atomic
            )
        let conflicted = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .topic,
                relativePath: "Agency.md",
                content: "# Agency\n\nAgent stale write.\n"
            )
        )
        #expect(conflicted.state == .conflict)

        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let initialEntry = try #require(stored.boundedWriteSet.entries.first {
            $0.note == fixture.analysisID
        })
        let analysis = try await handle.documents.load(fixture.analysisID)
        let unaffected = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .analysis,
                relativePath: "Analysis.md",
                content: analysis.rawContent + "\r\nAgent-bounded analysis addition.\r\n"
            )
        )
        #expect(unaffected.state == .committed)
        let final = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        #expect(final.boundedWriteSet.entry(handle: topicHandle)?.state == .conflict)
        #expect(try await handle.snapshot().research.activities.contains {
            $0.runID == connection.preparation.runID
                && $0.state == .needsAttention
                && $0.repairReason == .sourceConflict
        })
        #expect(final.boundedWriteSet.entry(handle: initialEntry.handle)?.state == .ready)
        #expect(!final.boundedWriteSet.entries.contains {
            $0.note.relativePath == "Draft Argument.md"
        })
        await runtime.shutdown()
    }

    @Test("Write capabilities are one-use and bound to session, full set, target, revision, and operation")
    func writeCapabilityBinding() async throws {
        let authority = try ResearchAgentSessionAuthority(
            random: BoundedWriteRandomSource()
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let handoff = try await authority.issuePairing(
            runID: UUID(),
            triptychID: UUID(),
            canWrite: true,
            now: now
        )
        let credential = try await authority.exchange(
            run: handoff.run,
            pairingCode: handoff.pairingCode,
            now: now
        )
        let setRevision = DocumentFingerprint(content: "write set one")
        let otherSetRevision = DocumentFingerprint(content: "write set two")
        let expected = DocumentFingerprint(content: "source")
        let firstTarget = ResearchWriteTargetHandle(runID: UUID(), noteID: UUID())
        let secondTarget = ResearchWriteTargetHandle(runID: UUID(), noteID: UUID())
        let operationID = UUID()
        let capability = try await authority.issueWriteCapability(
            credential: credential,
            run: handoff.run,
            writeSetRevision: setRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        #expect(String(describing: capability) == "<redacted write capability>")
        #expect(!String(reflecting: capability).contains(capability.secret))
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeWriteCapability(
                capability,
                credential: credential,
                run: handoff.run,
                writeSetRevision: setRevision,
                target: secondTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeWriteCapability(
                capability,
                credential: credential,
                run: handoff.run,
                writeSetRevision: setRevision,
                target: firstTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }

        let second = try await authority.issueWriteCapability(
            credential: credential,
            run: handoff.run,
            writeSetRevision: setRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeWriteCapability(
                second,
                credential: credential,
                run: handoff.run,
                writeSetRevision: otherSetRevision,
                target: firstTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }

        let third = try await authority.issueWriteCapability(
            credential: credential,
            run: handoff.run,
            writeSetRevision: setRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        try await authority.consumeWriteCapability(
            third,
            credential: credential,
            run: handoff.run,
            writeSetRevision: setRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeWriteCapability(
                third,
                credential: credential,
                run: handoff.run,
                writeSetRevision: setRevision,
                target: firstTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }
    }

    @Test("Direct undo restores the first committed Agent baseline after conflict and rename")
    func researchRecordUndoPreservesPreAgentExternalRevision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let run = try await handle.research.protectedFunctionRun(
            id: connection.preparation.runID
        )
        let initial = try await handle.documents.load(fixture.analysisID)
        let externalSource = initial.rawContent + "\nExternal pre-Agent addition.\n"
        let externalURL = fixture.analysesURL.appendingPathComponent("Analysis.md")
        try Data(externalSource.utf8).write(to: externalURL, options: .atomic)
        let agentSource = externalSource + "\nAgent addition.\n"
        let intent = try ResearchDocumentWriteIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000501")!,
            role: .analysis,
            relativePath: "Analysis.md",
            content: agentSource
        )
        let conflict = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(conflict.state == .conflict)
        _ = try await handle.research.resolveAgentWriteConflict(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteConflictResolutionIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000502")!,
                role: .analysis,
                relativePath: "Analysis.md",
                action: .refreshAuthority
            )
        )
        let write = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(write.state == .committed)

        let resultSubmission = try makeTestAgentResultSubmission(
            for: run,
            literatureRecommendations: []
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: resultSubmission
        )
        if !receipt.recordFormed {
            try await completeAutomaticFidelity(
                parentRunID: connection.preparation.runID,
                handle: handle
            )
            _ = try await handle.research.submitAgentResult(
                credential: connection.credential,
                run: connection.handoff.run,
                submission: resultSubmission
            )
        }
        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first(where: { $0.id == connection.preparation.runID })
        )
        let change = try #require(record.confirmedChanges.first)
        let participant = try #require(record.participatingNotes.first(where: {
            $0.noteID == change.noteID
        }))
        let externalRevision = DocumentFingerprint(content: externalSource)
        #expect(participant.startingRevision == initial.fingerprint)
        #expect(change.startingRevision == externalRevision)
        #expect(change.endingRevision == DocumentFingerprint(content: agentSource))
        let readyActivity = try #require(
            try await handle.snapshot().research.activities.first(where: {
                $0.runID == record.id
            })
        )
        #expect(readyActivity.state == .resultReady)
        #expect(readyActivity.repairReason == nil)

        let comparison = try await handle.research.researchRecordComparison(
            recordID: record.id,
            noteID: change.noteID
        )
        #expect(comparison.startingRevision == externalRevision)
        #expect(comparison.endingRevision == change.endingRevision)

        let moved: TriptychMoveCommit
        do {
            moved = try await handle.documents.move(
                fixture.analysisID,
                to: "Renamed Analysis.md",
                expectedRevision: change.endingRevision
            ).committedValue
        } catch {
            Issue.record("Rename before direct undo failed: \(error)")
            throw error
        }
        let kept = try await handle.research.keepResearchRecordChanges(
            recordID: record.id,
            expectedReviewRevision: nil,
            expectedResultFingerprint: try record.finalizedResultFingerprint()
        )
        #expect(kept.researcherReviewDisposition?.reviewedChanges.first?.outcome
            == .keptAgentRevision)
        #expect(try await handle.snapshot().research.activities.allSatisfy {
            $0.runID != record.id
        })
        enum InjectedDispositionReadbackFault: Error { case afterRename }
        await handle.services.portableResearchRecordStore.setPostCommitFaultForTesting { _ in
            throw InjectedDispositionReadbackFault.afterRename
        }
        let undo: ResearchRecordChangesUndoResult
        do {
            undo = try await handle.research.undoResearchRecordChanges(
                recordID: record.id,
                selectedNoteIDs: [change.noteID],
                expectedReviewRevision: kept.researcherReviewDisposition?.revision,
                expectedResultFingerprint: try record.finalizedResultFingerprint()
            )
        } catch {
            await handle.services.portableResearchRecordStore
                .setPostCommitFaultForTesting(nil)
            Issue.record("Direct undo failed after rename: \(error)")
            throw error
        }
        await handle.services.portableResearchRecordStore.setPostCommitFaultForTesting(nil)
        #expect(undo.documents.map(\.status) == [.restored])
        #expect(undo.record.researcherReviewIsComplete)
        #expect(undo.record.researcherReviewDisposition?.reviewedChanges.first?.outcome
            == .restoredStartingRevision)
        #expect(try await handle.documents.load(moved.destination).sourceBytes
            == Data(externalSource.utf8))
        let reconciled = try await handle.research.undoResearchRecordChanges(
            recordID: record.id,
            selectedNoteIDs: [change.noteID],
            expectedReviewRevision: undo.record.researcherReviewDisposition?.revision,
            expectedResultFingerprint: try record.finalizedResultFingerprint()
        )
        #expect(reconciled.documents.map(\.status) == [.alreadyAtStartingRevision])
        await #expect(throws: PortableResearcherReviewMutationError.staleReviewRevision) {
            _ = try await handle.research.undoResearchRecordChanges(
                recordID: record.id,
                selectedNoteIDs: [change.noteID],
                expectedReviewRevision: nil,
                expectedResultFingerprint: try record.finalizedResultFingerprint()
            )
        }
        await runtime.shutdown()
    }

    @Test("A conflict refreshes one exact member, retries idempotently, and can later be abandoned")
    func refreshRetryAndAbandonConflict() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let pending = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: false)
        )
        let pendingRecord = try await handle.services.localResearchExecutionStore
            .writeSetExtension(
                runID: connection.preparation.runID,
                requestID: pending.requestID
            )
        let topicHandle = try #require(pendingRecord.candidates.first?.handle)
        _ = try await handle.research.resolveAgentWriteSetExtension(
            requestID: pending.requestID,
            state: .allowedSubset,
            allowedHandles: [topicHandle]
        )
        let beforeConflict = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        let originalCheckpoint = try #require(
            beforeConflict.boundedWriteSet.entry(handle: topicHandle)?.checkpointID
        )

        let topicURL = fixture.rootURL
            .appendingPathComponent("Topics", isDirectory: true)
            .appendingPathComponent("Agency.md")
        try Data("---\ntitle: Agency\n---\n# Agency\n\nExternal revision.\n".utf8)
            .write(to: topicURL, options: .atomic)
        let writeRequestID = UUID(uuidString: "00000000-0000-4000-8000-000000000301")!
        let intendedContent = "---\ntitle: Agency\n---\n# Agency\n\nReconciled Agent revision.\n"
        let writeIntent = try ResearchDocumentWriteIntent(
            requestID: writeRequestID,
            role: .topic,
            relativePath: "Agency.md",
            content: intendedContent
        )
        let conflict = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: writeIntent
        )
        #expect(conflict.state == .conflict)

        let refreshIntent = try ResearchWriteConflictResolutionIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000302")!,
            role: .topic,
            relativePath: "Agency.md",
            action: .refreshAuthority
        )
        let refreshed = try await handle.research.resolveAgentWriteConflict(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: refreshIntent
        )
        #expect(refreshed.state == .readyToRetry)
        let refreshReplay = try await handle.research.resolveAgentWriteConflict(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: refreshIntent
        )
        #expect(refreshReplay == refreshed)

        let committed = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: writeIntent
        )
        #expect(committed.state == .committed)
        #expect(committed.operationID != conflict.operationID)
        #expect(try Data(contentsOf: topicURL) == Data(intendedContent.utf8))

        try Data("---\ntitle: Agency\n---\n# Agency\n\nSecond external revision.\n".utf8)
            .write(to: topicURL, options: .atomic)
        let secondConflict = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000303")!,
                role: .topic,
                relativePath: "Agency.md",
                content: intendedContent + "Another Agent attempt.\n"
            )
        )
        #expect(secondConflict.state == .conflict)
        let abandoned = try await handle.research.resolveAgentWriteConflict(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteConflictResolutionIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000304")!,
                role: .topic,
                relativePath: "Agency.md",
                action: .abandonWrite
            )
        )
        #expect(abandoned.state == .abandoned)

        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let currentEntry = try #require(
            stored.boundedWriteSet.entry(handle: topicHandle)
        )
        #expect(currentEntry.state == .abandoned)
        #expect(currentEntry.checkpointID != originalCheckpoint)
        #expect(stored.writeConflictResolutionRecords.count == 2)
        #expect(stored.documentWriteRecords.map(\.state) == [
            .conflict, .committed, .conflict,
        ])
        let checkpointIDs = await handle.services.checkpointStore.checkpoints().map(\.id)
        #expect(checkpointIDs.contains(originalCheckpoint))
        #expect(checkpointIDs.contains(currentEntry.checkpointID))
        await runtime.shutdown()
    }

    @Test("An already-bound request creates no extension decision record")
    func alreadyBoundRequestHasNoFakeDecision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let result = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: "Analysis.md",
                    operations: [.modifyMarkdown]
                )],
                academicReason: "Continue using the initial Action target."
            )
        )
        #expect(result.state == .continueWithoutChanges)
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        #expect(stored.writeSetExtensionRecords.isEmpty)
        await runtime.shutdown()
    }

    @Test("Tightening collaboration policy stales an unused policy-derived member")
    func policyTighteningNarrowsUnusedMember() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let original = try await handle.research.collaborationPolicy()
        let fullAccess = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .fullAccess
            ),
            expectedRevision: original.revision
        )
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: false)
        )
        _ = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .askEveryTime
            ),
            expectedRevision: fullAccess.revision
        )
        let topic = try await handle.documents.load(fixture.topicID)
        await #expect(throws: ResearchBoundedWriteSetError.staleAuthorization) {
            try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    role: .topic,
                    relativePath: "Agency.md",
                    content: topic.rawContent + "\nThis write must not proceed.\n"
                )
            )
        }
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        #expect(stored.boundedWriteSet.entries.first {
            $0.note.relativePath == "Agency.md"
        }?.state == .stale)
        await runtime.shutdown()
    }

    @Test("A symlink escape cannot enter a bounded write set")
    func symlinkEscapeRejected() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let outsideURL = fixture.rootURL.appendingPathComponent("Outside.md")
        try Data("# Outside\n".utf8).write(to: outsideURL, options: .atomic)
        let linkURL = fixture.rootURL
            .appendingPathComponent("Topics", isDirectory: true)
            .appendingPathComponent("Escape.md")
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: outsideURL
        )
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        await #expect(throws: ResearchBoundedWriteSetError.targetUnavailable) {
            try await handle.research.extendAgentWriteSet(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchWriteSetExtensionIntent(
                    targets: [try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: "Escape.md",
                        operations: [.modifyMarkdown]
                    )],
                    academicReason: "This fixture must remain outside the vault boundary."
                )
            )
        }
        #expect(try Data(contentsOf: outsideURL) == Data("# Outside\n".utf8))
        await runtime.shutdown()
    }

    private func prepareWritableRun(
        handle: WorkspaceHandle,
        fixture: ResearchFixture
    ) async throws -> (
        preparation: ResearchActionPreparation,
        handoff: ResearchAgentHandoff,
        credential: ResearchConnectionCredential
    ) {
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let helpers = ResearchFunctionOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .analyze,
                target: helpers.actionNote(target)
            )
        )
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: preparation.runID
        )
        #expect(stored.boundedWriteSet.entries.map(\.noteID) == [target.noteID])
        #expect(stored.boundedWriteSet.entries.first?.authorizationBasis == .initialAction)
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        return (preparation, handoff, credential)
    }

    private func completeAutomaticFidelity(
        parentRunID: UUID,
        handle: WorkspaceHandle
    ) async throws {
        let automatic = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: parentRunID
        )
        let preparation = automatic.preparation
        let checks = preparation.snapshot.request.checks.sorted {
            $0.rawValue < $1.rawValue
        }
        let outcomes = checks.map(FidelityCheckOutcome.passed)
        let targets = preparation.snapshot.request.resolvedFidelityTargets
        _ = try await completeTestProtectedFunction(
            handle: handle,
            submission: ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: preparation.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: targets.count == 1
                    ? targets[0].fingerprint
                    : nil,
                summary: "Checked every exact final Agent revision.",
                didModifyTarget: false,
                fidelityOutcomes: targets.count == 1 ? outcomes : [],
                fidelityTargetSubmissions: targets.count > 1
                    ? targets.map { target in
                        ResearchFunctionFidelityTargetSubmission(
                            noteID: target.noteID,
                            note: target.note,
                            fingerprint: target.fingerprint,
                            outcomes: outcomes
                        )
                    }
                    : []
            )
        )
        _ = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: parentRunID
        )
    }

    private func extensionIntent(
        includeWork: Bool
    ) throws -> ResearchWriteSetExtensionIntent {
        var targets = [try ResearchWriteSetTargetSelector(
            role: .topic,
            relativePath: "Agency.md",
            operations: [.modifyMarkdown]
        )]
        if includeWork {
            targets.append(try ResearchWriteSetTargetSelector(
                role: .work,
                relativePath: "Draft Argument.md",
                operations: [.modifyMarkdown]
            ))
        }
        return try ResearchWriteSetExtensionIntent(
            targets: targets,
            academicReason: "Update the directly relevant topic and draft while preserving source attribution."
        )
    }
}

private final class BoundedWriteRandomSource: ResearchSecureRandomSource,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var next: UInt8 = 113

    func bytes(count: Int) throws -> Data {
        lock.withLock {
            let start = next
            next &+= 29
            return Data((0..<count).map {
                start &+ UInt8(truncatingIfNeeded: $0)
            })
        }
    }
}
