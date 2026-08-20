import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchFunctionOperationsTests {
    @Test("Researcher ending an unfinished Discussion preserves it and rejects later Agent access")
    func researcherEndsActiveDiscussion() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Which premise needs the most support?"),
                ]
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        #expect(preparation.instructions.contains("agent discuss-reply"))
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )

        try await handle.research.cancelAction(runID: preparation.runID)

        #expect(try await handle.research.activeDiscussions(noteID: nil).isEmpty)
        let finished = try await handle.research.finishedResearchRecords(noteID: nil)
        #expect(finished.contains {
            $0.id == preparation.runID
                && $0.statements.map(\.text) == ["Which premise needs the most support?"]
        })
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            _ = try await handle.research.authenticatedAgentContext(
                credential: credential,
                run: handoff.run
            )
        }
        await runtime.shutdown()
    }

    @Test("Discuss stays read-only, requires durable attributed response evidence, and prepared runs cancel durably")
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

        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Change this Analysis into a stronger argument."),
                ]
            )
        )
        let protectedRun = try await handle.research.protectedFunctionRun(id: preparation.runID)
        #expect(preparation.instructions.contains("Target and Materials are read-only"))
        #expect(preparation.instructions.contains(
            "begin a separately authorized Analyze Action"
        ))
        let storedInstructions = try #require(try await handle.services.localResearchExecutionStore.listing().records.first {
            $0.id == preparation.runID
        }?.preparedInstructions)
        #expect(preparation.instructions.hasPrefix(storedInstructions))
        #expect(try await handle.documents.load(fixture.analysisID).fingerprint == target.fingerprint)
        let discussion = try await handle.research.activeDiscussion(id: preparation.runID)
        #expect(discussion.action?.actionID == .discuss)
        #expect(discussion.statements.map(\.text) == [
            "Change this Analysis into a stronger argument.",
        ])
        let unchangedDiscussion = try await handle.research.activeDiscussion(
            id: preparation.runID
        )
        #expect(unchangedDiscussion == discussion)

        let incomplete = ResearchFunctionCompletionSubmission(
            runID: preparation.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            recordTitle: try ResearchRecordTitle("Test research result"),
            finalTargetFingerprint: target.fingerprint,
            summary: "A reply was allegedly produced.",
            didModifyTarget: false
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await completeTestProtectedFunction(handle: handle, submission: incomplete)
        }
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: preparation.runID,
            author: .agent,
            attribution: "Research Agent",
            text: "The requested change requires a separately authorized Analyze Action."
        )
        let completed = try await completeTestProtectedFunction(handle: handle, submission: incomplete)
        #expect(completed.state == .complete)
        #expect(!completed.didModifyTarget)
        let activeAfterCompletion = try await handle.research.activeDiscussions(noteID: nil)
        let recordsAfterCompletion = try await handle.research.finishedResearchRecords(noteID: nil)
        #expect(recordsAfterCompletion.allSatisfy { $0.id != preparation.runID })
        #expect(try await handle.snapshot().research.activeDiscussions.contains {
            $0.id == preparation.runID && !$0.awaitsAgentReply
        })
        #expect(activeAfterCompletion.contains {
            $0.id == preparation.runID && !$0.awaitsAgentReply
        })
        let record = try await handle.research.finishProtectedDiscussion(runID: preparation.runID)
        let repeated = try await handle.research.finishProtectedDiscussion(runID: preparation.runID)
        #expect(record == repeated)
        #expect(record.kind == .discussion)
        #expect(record.statements.count == 2)
        await #expect(throws: PortableResearcherResponseMutationError.recordUnavailable) {
            _ = try await handle.research.saveResearcherResponse(
                recordID: record.id,
                draft: ResearcherResponseDraft(
                    evaluation: ResearcherEvaluationDraft(noIssuesObserved: true),
                    methodFeedbackText: nil
                ),
                expectedEvaluationRevision: nil,
                expectedMethodFeedbackRevision: nil,
                expectedResultFingerprint: try record.finalizedResultFingerprint()
            )
        }
        #expect(try await handle.snapshot().research.activeDiscussions.allSatisfy {
            $0.id != preparation.runID
        })
        #expect(try await handle.snapshot().research.finishedResearchRecords.filter {
            $0.id == preparation.runID
        }.count == 1)

        let fidelity = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .checkFidelity,
                target: actionNote(target),
                platformInputs: try ResearchActionPlatformInputs(
                    fidelityChecks: [.content]
                )
            )
        )
        try await handle.research.cancelProtectedFunction(runID: fidelity.runID)
        let cancelled = try #require(try await handle.services.localResearchExecutionStore.listing().records
            .first { $0.id == fidelity.runID }?.completion)
        #expect(cancelled.state == .cancelled)
        await runtime.shutdown()
    }

    @Test("Authenticated Discuss replies are idempotent and remain bounded")
    func authenticatedAgentDiscussionReplyIsIdempotent() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Which premise needs a bounded reply?"),
                ]
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        #expect(preparation.instructions.contains("agent discuss-reply"))
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.authenticatedAgentContext(
            credential: credential,
            run: handoff.run
        )
        #expect(context.brief.capabilities.discussionReply)
        #expect(context.discussionResponseContract != nil)

        let request = try ResearchAgentDiscussionReplyRequest(
            statementID: UUID(uuidString: "00000000-0000-4000-8000-000000000903")!,
            attribution: "External Agent",
            text: "The premise needs a narrower source-faithful reconstruction."
        )
        let first = try await runtime.replyToResearchAgentDiscussion(
            credential: credential,
            run: handoff.run,
            request: request
        )
        #expect(first.state == .recorded)
        let repeated = try await runtime.replyToResearchAgentDiscussion(
            credential: credential,
            run: handoff.run,
            request: request
        )
        #expect(repeated.state == .alreadyRecorded)

        let active = try await handle.research.activeDiscussion(id: preparation.runID)
        #expect(active.statements.count == 2)
        #expect(active.statements.last?.author == .agent)
        #expect(active.statements.last?.text == request.text)

        let changed = try ResearchAgentDiscussionReplyRequest(
            statementID: request.statementID,
            attribution: request.attribution,
            text: "A different payload must not reuse the statement ID."
        )
        await #expect(throws: PortableResearchDiscussionError.self) {
            _ = try await runtime.replyToResearchAgentDiscussion(
                credential: credential,
                run: handoff.run,
                request: changed
            )
        }

        let end = try await runtime.endResearchAgentRun(
            credential: credential,
            run: handoff.run
        )
        #expect(!end.recoveryRetained)
        await runtime.shutdown()
    }

    @Test("Discussion supports whole-note focal context without writing Markdown")
    func portableDiscussionIsReadOnlyAcrossFocalNotes() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let focal = ResearchFunctionMaterial(
            noteID: topic.noteID,
            note: topic.note,
            role: topic.role,
            lifecycle: topic.lifecycle,
            fingerprint: topic.fingerprint,
            title: topic.title
        )
        let analysisBefore = try await handle.documents.load(fixture.analysisID)
        let topicBefore = try await handle.documents.load(fixture.topicID)

        let discussion = try await handle.research.createDiscussion(
            target: analysis,
            focalNotes: [focal],
            passage: nil,
            researcherMessage: "Compare the current Analysis with this Topic."
        )
        #expect(Set(discussion.participatingNotes.map(\.noteID)) == [
            analysis.noteID,
            topic.noteID,
        ])
        #expect(discussion.passage == nil)
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: discussion.id,
            author: .agent,
            attribution: "Research Agent",
            text: "The Topic qualifies rather than settles the Analysis."
        )
        let record = try await handle.research.finishDiscussion(
            discussionID: discussion.id
        )

        #expect(record.kind == .discussion)
        #expect(record.fidelityCompletion == .notApplicable)
        #expect(record.participatingNotes.count == 2)
        #expect(try await handle.documents.load(fixture.analysisID).rawContent
            == analysisBefore.rawContent)
        #expect(try await handle.documents.load(fixture.topicID).rawContent
            == topicBefore.rawContent)
        #expect(try await handle.snapshot().research.activeDiscussions.isEmpty)
        #expect(try await handle.snapshot().research.finishedResearchRecords.contains {
            $0.id == record.id
        })
        await runtime.shutdown()
    }

    @Test("Discussion source changes are not exposed as Agent-confirmed comparison")
    func researchRecordDeletionAndExactComparison() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let focal = ResearchFunctionMaterial(
            noteID: topic.noteID,
            note: topic.note,
            role: topic.role,
            lifecycle: topic.lifecycle,
            fingerprint: topic.fingerprint,
            title: topic.title
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let discussion = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [focal],
            passage: nil,
            researcherMessage: "Retain both exact revisions."
        )
        let changedSource = original.rawContent.replacingOccurrences(
            of: "narrow reconstruction",
            with: "strictly bounded reconstruction"
        )
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(changedSource),
            expectedRevision: original.fingerprint
        ).committedValue
        let record = try await handle.research.finishDiscussion(
            discussionID: discussion.id
        )
        let portableURL = fixture.rootURL
            .appendingPathComponent(".scholium/research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let recordBytes = try Data(contentsOf: portableURL)

        await #expect(throws: ResearchRecordChangeRecoveryOperationError.self) {
            _ = try await handle.research.researchRecordComparison(
                recordID: record.id,
                noteID: target.noteID
            )
        }
        #expect(try Data(contentsOf: portableURL) == recordBytes)

        try await handle.research.deleteResearchRecordPermanently(id: record.id)
        #expect(try await handle.research.finishedResearchRecords(noteID: target.noteID).isEmpty)
        #expect(try await handle.research.finishedResearchRecords(noteID: topic.noteID).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        #expect(try await handle.documents.load(fixture.analysisID).sourceBytes
            == saved.document.sourceBytes)
        await runtime.shutdown()
    }

    @Test("Research Record comparison refuses a participant without a confirmed change")
    func researchRecordComparisonRefusesUnconfirmedParticipant() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let discussion = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: nil,
            researcherMessage: "Do not approximate unavailable bytes."
        )
        let record = try await handle.research.finishDiscussion(discussionID: discussion.id)
        await #expect(throws: ResearchRecordChangeRecoveryOperationError.self) {
            _ = try await handle.research.researchRecordComparison(
                recordID: record.id,
                noteID: target.noteID
            )
        }
        await runtime.shutdown()
    }

    @Test("Passage Comments append to one active Discussion and one finished record")
    func passageCommentsShareOneDiscussion() async throws {
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

        let first = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: try commentAnchor(in: document),
            researcherMessage: "What is the role of this claim?"
        )
        let second = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: try commentAnchor(in: document, quotation: "narrow reconstruction"),
            researcherMessage: "How narrow should this reconstruction remain?"
        )

        #expect(second.id == first.id)
        #expect(second.statements.count == 2)
        #expect(second.statements.allSatisfy { $0.author == .researcher })
        #expect(second.statements.compactMap(\.passage).count == 2)
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: first.id,
            author: .agent,
            attribution: "Research Agent",
            text: "Keep the reconstruction bounded by the stated claim."
        )
        let record = try await handle.research.finishDiscussion(discussionID: first.id)
        #expect(record.primaryNoteID == target.noteID)
        #expect(record.statements.count == 3)
        #expect(try await handle.research.finishedResearchRecords(noteID: target.noteID)
            .filter { $0.id == first.id }.count == 1)
        await runtime.shutdown()
    }

    @Test("Line Comments append without retaining selected prose or exact offsets")
    func lineCommentsShareOneDiscussion() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let firstReference = try ResearchLineReference(
            fingerprint: target.fingerprint,
            line: 1,
            endLine: 1
        )
        let secondReference = try ResearchLineReference(
            fingerprint: target.fingerprint,
            line: 2,
            endLine: 2
        )

        let first = try await handle.research.createComment(
            target: target,
            lineReference: firstReference,
            researcherMessage: "Clarify this transition."
        )
        let second = try await handle.research.createComment(
            target: target,
            lineReference: secondReference,
            researcherMessage: "This premise may be doing two jobs."
        )

        #expect(second.id == first.id)
        #expect(second.statements.count == 2)
        #expect(second.statements.compactMap(\.lineReference) == [
            firstReference, secondReference,
        ])
        #expect(second.statements.allSatisfy { $0.passage == nil })

        let impossibleLine = try ResearchLineReference(
            fingerprint: target.fingerprint,
            line: 10_000,
            endLine: 10_000
        )
        await #expect(throws: ResearchOperationError.self) {
            _ = try await handle.research.createComment(
                target: target,
                lineReference: impossibleLine,
                researcherMessage: "This cannot be attached."
            )
        }
        await runtime.shutdown()
    }

    @Test("Synced duplicate primary Discussions are withheld from current projection")
    func duplicatePrimaryDiscussionsFailCurrentProjectionClosed() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let first = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: nil,
            researcherMessage: "Keep this primary identity singular."
        )
        let duplicate = try PortableResearchDiscussion(
            id: UUID(),
            triptychID: first.triptychID,
            primaryNoteID: first.primaryNoteID,
            action: first.action,
            method: first.method,
            participatingNotes: first.participatingNotes,
            statements: first.statements,
            createdAt: first.createdAt,
            updatedAt: first.updatedAt
        )
        let duplicateURL = fixture.rootURL
            .appendingPathComponent(".scholium/research-records/v1/active", isDirectory: true)
            .appendingPathComponent(duplicate.id.uuidString.lowercased() + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(duplicate).write(to: duplicateURL, options: .atomic)

        let refreshed = try await handle.refresh()
        #expect(refreshed.research.activeDiscussions.isEmpty)
        #expect(refreshed.research.healthIssues.contains {
            $0.contains("multiple active Discussions")
        })
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.activeDiscussion(id: first.id)
        }
        await runtime.shutdown()
    }

    @Test("A passage Discussion follows stable identity across rename")
    func passageDiscussionContinuesAfterRename() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let originalTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let discussion = try await handle.research.createDiscussion(
            target: originalTarget,
            focalNotes: [],
            passage: try commentAnchor(in: original),
            researcherMessage: "Keep this passage attached across rename."
        )

        let move = try await handle.documents.move(
            fixture.analysisID,
            to: "Renamed Analysis.md",
            expectedRevision: original.fingerprint
        ).committedValue
        // Note movement returns after the authoritative source and stable
        // identity commit. Research Actions intentionally reopen only after
        // the complete derived Workspace projection catches up.
        _ = try await handle.discovery.refresh()
        let movedTarget = try await researchFunctionTarget(
            move.destination,
            role: .analysis,
            handle: handle
        )
        let moved = try await handle.documents.load(move.destination)
        let appended = try await handle.research.createDiscussion(
            target: movedTarget,
            focalNotes: [],
            passage: try commentAnchor(in: moved, quotation: "narrow reconstruction"),
            researcherMessage: "Continue from the renamed Note."
        )

        #expect(appended.id == discussion.id)
        #expect(appended.statements.compactMap(\.passage).count == 2)
        let finished = try await handle.research.finishDiscussion(
            discussionID: discussion.id
        )
        #expect(finished.primaryNoteID == originalTarget.noteID)
        await runtime.shutdown()
    }

    @Test("A Comment-only Discussion activates through the resolved Discuss Method")
    func commentOnlyDiscussionActivatesThroughDiscussMethod() async throws {
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
        let discussion = try await handle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: try commentAnchor(in: document),
            researcherMessage: "Begin with a passage Comment."
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Continue at whole-note scope."),
                ]
            )
        )

        #expect(preparation.runID == discussion.id)
        let activated = try await handle.research.activeDiscussion(id: discussion.id)
        #expect(activated.action?.actionID == .discuss)
        #expect(activated.method != nil)
        #expect(activated.statements.first == discussion.statements.first)
        #expect(activated.statements.last?.id == preparation.runID)
        #expect(activated.statements.last?.text == "Continue at whole-note scope.")
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == discussion.id
        })
        await runtime.shutdown()
    }

    @Test("An interrupted Discuss preparation restores its exact portable pair")
    func localDiscussOrphanReconcilesOnReopen() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        var runtime = fixture.runtime()
        var handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Restore this interrupted preparation."),
                ]
            )
        )
        await runtime.shutdown()

        let activeURL = fixture.rootURL
            .appendingPathComponent(".scholium/research-records/v1/active", isDirectory: true)
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        try FileManager.default.removeItem(at: activeURL)

        runtime = fixture.runtime()
        handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let restored = try await handle.research.activeDiscussion(id: preparation.runID)
        #expect(restored.id == preparation.runID)
        #expect(restored.statements.first?.text == "Restore this interrupted preparation.")
        _ = try await handle.research.protectedFunctionRun(id: preparation.runID)
        await runtime.shutdown()
    }

    @Test("A cooperating runtime reply is visible through portable Discussion reload")
    func externalRuntimeReplyIsReloadable() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let firstRuntime = fixture.runtime()
        let secondRuntime = fixture.runtime()
        let firstHandle = try await firstRuntime.openWorkspace(id: fixture.assignment.id)
        let secondHandle = try await secondRuntime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: firstHandle
        )
        let document = try await firstHandle.documents.load(fixture.analysisID)
        let discussion = try await firstHandle.research.createDiscussion(
            target: target,
            focalNotes: [],
            passage: try commentAnchor(in: document),
            researcherMessage: "Reply from the cooperating runtime."
        )

        _ = try await secondHandle.research.appendDiscussionStatement(
            discussionID: discussion.id,
            author: .agent,
            attribution: "External Research Agent",
            text: "This reply was persisted by a separate runtime."
        )
        let reloaded = try await firstHandle.research.activeDiscussion(id: discussion.id)
        #expect(reloaded.statements.last?.attribution == "External Research Agent")
        #expect(reloaded.awaitsAgentReply == false)

        await secondRuntime.shutdown()
        await firstRuntime.shutdown()
    }

    @Test("Finishing a Discussion before run completion preserves completion evidence")
    func finishBeforeDiscussCompletionRemainsCompletable() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(target),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Clarify the argument without editing the Analysis."),
                ]
            )
        )
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: preparation.runID,
            author: .agent,
            attribution: "Research Agent",
            text: "The claim is narrower than the surrounding argument."
        )
        let finished = try await handle.research.finishDiscussion(
            discussionID: preparation.runID
        )
        #expect(finished.primaryNoteID == target.noteID)

        let run = try await handle.research.protectedFunctionRun(id: preparation.runID)
        let completion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: run.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: target.fingerprint,
                summary: "A bounded reply was recorded before Finish.",
                didModifyTarget: false
            )
        )
        #expect(completion.state == .complete)
        #expect(try await handle.research.activeDiscussions(noteID: nil).isEmpty)
        #expect(try await handle.research.finishedResearchRecords(noteID: target.noteID)
            .contains { $0.id == preparation.runID })
        await runtime.shutdown()
    }

    @Test("Markdown preparation is an executable immutable handoff")
    func completeMarkdownPreparationPacket() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let document = try await handle.documents.load(fixture.topicID)
        let selectionRange = (document.rawContent as NSString).range(
            of: "See [[Nested Topic]]"
        )
        let anchor = try #require(CommentAnchorBuilder.anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: selectionRange.location..<(selectionRange.location + selectionRange.length)
        ))
        let material = try #require(
            try await handle.research.protectedMaterialCandidates(
                for: target,
                function: .develop
            ).first { $0.material.note == fixture.analysisID }?.material
        )

        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material],
                instruction: "Synthesize only the selected connection.",
                scope: .passage(anchor)
            )
        )

        let packet = preparation.instructions
        #expect(packet.contains(fixture.assignment.id.uuidString.lowercased()))
        #expect(packet.contains(preparation.runID.uuidString.lowercased()))
        #expect(packet.contains(preparation.snapshot.confirmationToken.uuidString.lowercased()))
        #expect(packet.contains(target.noteID.uuidString.lowercased()))
        #expect(packet.contains(material.noteID.uuidString.lowercased()))
        #expect(packet.contains("\"quotation\" : \"See [[Nested Topic]]\""))
        #expect(packet.contains("\"line\""))
        #expect(packet.contains("\"utf8Range\""))
        #expect(packet.contains("\"action\" : \"synthesize\""))
        #expect(packet.contains("\"method\""))
        #expect(packet.contains("\"registrationKey\""))
        #expect(packet.contains("\"primaryMarkdownRevision\""))
        #expect(packet.contains("\"practices\""))
        #expect(!packet.contains("packageRevision"))
        #expect(!packet.contains("loadedResources"))
        #expect(packet.contains("\"profileRevision\""))
        #expect(!preparation.awaitsResourceSelection)
        #expect(!packet.contains("## Finalize conditional resources"))
        #expect(!packet.contains("scholium action select-resources"))
        #expect(packet.contains("frozen Result Contract"))
        #expect(packet.contains("authenticated Agent CLI"))
        let storedRun = try #require(try await handle.services.localResearchExecutionStore.listing().records.first {
            $0.id == preparation.runID
        })
        let persistedPacket = storedRun.preparedInstructions
        #expect(packet.hasPrefix(persistedPacket))
        #expect(!persistedPacket.contains("## Write authorization"))
        await runtime.shutdown()
    }

    @Test("Whole-note Critique does not infer Discussion records as Comment evidence")
    func wholeCritiqueDoesNotInferDiscussionEvidence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let document = try await handle.documents.load(fixture.workID)
        let first = try await createCommentExchange(
            for: target,
            anchor: commentAnchor(in: document, quotation: "claim requiring Critique"),
            researcherText: "Test the missing premise.",
            agentText: "The inference needs an explicit bridge premise.",
            finish: true,
            handle: handle
        )
        let second = try await createCommentExchange(
            for: target,
            anchor: commentAnchor(in: document, quotation: "See [[Analysis]]"),
            researcherText: "Check this evidential link.",
            agentText: "The linked Analysis supplies context but not support.",
            finish: true,
            handle: handle
        )
        let unfinished = try await createCommentExchange(
            for: target,
            anchor: commentAnchor(in: document, quotation: "Draft Argument"),
            researcherText: "This exchange is not finished.",
            agentText: "A reply alone must not count as reviewed evidence.",
            finish: false,
            handle: handle
        )

        let callerSuppliedID = UUID()
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.prepareProtectedFunction(
                ResearchFunctionRequest(
                    function: .critique,
                    target: target,
                    scope: .whole,
                    commentIDs: [callerSuppliedID],
                    conditionalResources: []
                )
            )
        }
        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .critique,
                target: target,
                scope: .whole,
                conditionalResources: []
            )
        )

        #expect(preparation.snapshot.request.commentIDs.isEmpty)
        #expect(!preparation.snapshot.request.commentIDs.contains(first))
        #expect(!preparation.snapshot.request.commentIDs.contains(second))
        #expect(!preparation.snapshot.request.commentIDs.contains(unfinished))
        #expect(!preparation.snapshot.request.commentIDs.contains(callerSuppliedID))
        #expect(!preparation.instructions.contains("Test the missing premise."))
        #expect(!preparation.instructions.contains("The linked Analysis supplies context but not support."))
        #expect(!preparation.instructions.contains("This exchange is not finished."))
        await runtime.shutdown()
    }

    @Test("Passage Critique does not infer overlapping Discussion records as evidence")
    func passageCritiqueDoesNotInferDiscussionEvidence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let document = try await handle.documents.load(fixture.workID)
        let passage = try commentAnchor(
            in: document,
            quotation: "A claim requiring Critique"
        )
        let overlapping = try await createCommentExchange(
            for: target,
            anchor: commentAnchor(in: document, quotation: "claim requiring"),
            researcherText: "Inspect this inference.",
            agentText: "The selected inference lacks a bridge premise.",
            finish: true,
            handle: handle
        )
        let outsidePassage = try await createCommentExchange(
            for: target,
            anchor: commentAnchor(in: document, quotation: "See [[Analysis]]"),
            researcherText: "Inspect the link separately.",
            agentText: "This link falls outside the selected passage.",
            finish: true,
            handle: handle
        )

        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .critique,
                target: target,
                scope: .passage(passage),
                conditionalResources: []
            )
        )

        #expect(preparation.snapshot.request.commentIDs.isEmpty)
        #expect(!preparation.snapshot.request.commentIDs.contains(overlapping))
        #expect(!preparation.snapshot.request.commentIDs.contains(outsidePassage))
        #expect(!preparation.instructions.contains("Inspect this inference."))
        #expect(!preparation.instructions.contains("Inspect the link separately."))
        await runtime.shutdown()
    }

}
