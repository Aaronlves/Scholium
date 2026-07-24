import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Derived refresh status")
struct DerivedRefreshStatusTests {
    @Test("Live rebuild failure is typed and a successful retry clears it")
    func liveFailureThenCurrent() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let topicVaultID = try #require(
            fixture.assignment.vault(for: .topicKnowledge)?.id
        )

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)
        for _ in 0..<120 where await handle.events.publishedGeneration < 1 {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard await handle.events.publishedGeneration >= 1 else {
            Issue.record("The native watcher did not report the failed rebuild.")
            await runtime.shutdown()
            return
        }
        let failed = try #require(await iterator.next())
        guard case .derivedStateChanged(let event) = failed,
              case .failed(let issue) = event.status else {
            Issue.record("A live rebuild failure was published as current state.")
            await runtime.shutdown()
            return
        }
        #expect(issue.affectedVaultIDs == [topicVaultID])
        #expect(!issue.reason.isEmpty)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        let current = try #require(await iterator.next())
        guard case .current(let evidence) = current.derivedRefreshStatus else {
            Issue.record("The successful live retry did not clear failed state.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: current.snapshot))
        await runtime.shutdown()
    }

    @Test("A failed rebuild retains evidence and a later success clears it")
    func failedRebuildThenCurrent() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        do {
            _ = try await handle.discovery.refresh()
            Issue.record("An invalid source unexpectedly produced a current projection.")
        } catch {
            // Expected: source bytes remain authoritative and the prior
            // complete projection remains readable.
        }

        let failed = try #require(await iterator.next())
        #expect(failed.generation == initial.generation + 1)
        guard case .derivedStateChanged(let event) = failed,
              case .failed(let issue) = event.status else {
            Issue.record("A failed rebuild was not published as failed derived state.")
            await runtime.shutdown()
            return
        }
        #expect(!issue.reason.isEmpty)
        #expect(issue.lastKnownGood == WorkspaceDerivedRefreshEvidence(snapshot: initial.snapshot))
        #expect(event.snapshot.generatedAt == initial.snapshot.generatedAt)
        #expect(event.discovery.searchGeneration == initial.snapshot.discovery.searchGeneration)

        try FileManager.default.removeItem(at: invalidURL)
        let refreshed = try await handle.discovery.refresh()
        let current = try #require(await iterator.next())
        #expect(current.generation == failed.generation + 1)
        guard case .derivedStateChanged(let event) = current,
              case .current(let evidence) = event.status else {
            Issue.record("A successful retry did not clear the failed derived status.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: refreshed))
        #expect(event.snapshot.generatedAt == refreshed.generatedAt)
        await runtime.shutdown()
    }

    @Test("A committed source mutation publishes stale state and must not be retried")
    func committedMutationIsNotRetried() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        let applicationError: ScholiumApplicationError
        do {
            _ = try await handle.documents.save(
                fixture.analysisNoteID,
                changeSet: .body("Committed exactly once.\n"),
                expectedRevision: original.fingerprint
            )
            Issue.record("The committed save unexpectedly refreshed its projection.")
            await runtime.shutdown()
            return
        } catch let error as ScholiumApplicationError {
            applicationError = error
        }

        guard case .committedButRefreshFailed(let committedRevision, _) = applicationError else {
            Issue.record("The post-commit refresh failure lost its committed outcome.")
            await runtime.shutdown()
            return
        }
        #expect(applicationError.durableMutationWasCommitted)
        #expect(applicationError.mustNotRetryMutation)
        #expect(applicationError.committedDocumentRevision == committedRevision)
        #expect(applicationError.refreshFailureReason?.isEmpty == false)

        let stale = try #require(await iterator.next())
        #expect(stale.generation == initial.generation + 1)
        guard case .derivedStateChanged(let event) = stale,
              case .stale(let issue) = event.status else {
            Issue.record("A committed mutation with a failed refresh was not marked stale.")
            await runtime.shutdown()
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.analysisNoteID.vaultID])
        #expect(issue.lastKnownGood == WorkspaceDerivedRefreshEvidence(snapshot: initial.snapshot))
        #expect(event.snapshot.document(id: fixture.analysisNoteID)?.fingerprint == original.fingerprint)

        // Read the authority directly through DocumentOperations. The new
        // revision is durable even though the last complete projection is old;
        // a caller must refresh, never replay the save.
        let committed = try await handle.documents.load(fixture.analysisNoteID)
        #expect(committed.fingerprint == committedRevision)
        #expect(committed.rawContent.contains("Committed exactly once."))

        try FileManager.default.removeItem(at: invalidURL)
        let recovered = try await handle.discovery.refresh()
        let recoveryEvent = try #require(await iterator.next())
        #expect(recoveryEvent.generation == stale.generation + 1)
        guard case .current(let evidence) = recoveryEvent.derivedRefreshStatus else {
            Issue.record("A successful refresh did not clear stale derived state.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: recovered))
        #expect(recoveryEvent.snapshot.document(id: fixture.analysisNoteID)?.fingerprint == committedRevision)
        await runtime.shutdown()
    }

    @Test("A committed Research Function returns its packet and completion with a refresh warning")
    func committedResearchFunctionIsNotReportedAsRetryableFailure() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.snapshot()
        let note = try #require(snapshot.document(id: fixture.analysisNoteID))
        guard case .resolved(let noteID) = note.stableIdentity else {
            Issue.record("The fixture Analysis has no stable identity.")
            await runtime.shutdown()
            return
        }
        let target = ResearchFunctionTarget(
            noteID: noteID,
            note: fixture.analysisNoteID,
            role: .analysis,
            fingerprint: note.fingerprint,
            title: "Analysis"
        )
        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)

        let preparation = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        #expect(preparation.derivedRefreshWarning?.isEmpty == false)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        #expect(try await handle.snapshot().research.functionRuns.contains {
            $0.id == preparation.runID
        })
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        let completion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: preparation.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked the exact Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [FidelityCheckOutcome(
                    check: .content,
                    state: .passed,
                    summary: "No content-fidelity issue was found in the supplied evidence."
                )]
            )
        )
        #expect(completion.state == .complete)
        #expect(completion.derivedRefreshWarning?.isEmpty == false)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == preparation.runID
        }?.completion?.state == .complete)
        await runtime.shutdown()
    }

    @Test("Committed Fidelity remains reusable while derived refresh keeps failing")
    func committedFidelityRemainsReusableAcrossRefreshFailures() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await functionTarget(
            fixture.analysisNoteID,
            role: .analysis,
            handle: handle
        )
        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)

        let preparation = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        #expect(preparation.derivedRefreshWarning?.isEmpty == false)
        let completion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: preparation.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked the exact Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        #expect(completion.state == .complete)
        #expect(completion.derivedRefreshWarning?.isEmpty == false)

        // Both post-commit refreshes failed, so the disposable projection still
        // has no record of this run. Reuse must come from the durable store.
        #expect(try await handle.snapshot().research.functionRuns.contains {
            $0.id == preparation.runID
        } == false)
        let reused = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        #expect(reused.state == .complete)
        #expect(reused.reusedCompletion?.runID == completion.runID)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        let persistedMatches = try await handle.snapshot().research.functionRuns.filter {
            $0.snapshot.request.function == .fidelity
                && $0.snapshot.request.target.noteID == target.noteID
        }
        #expect(persistedMatches.count == 1)
        #expect(persistedMatches.first?.completion?.state == .complete)
        await runtime.shutdown()
    }

    @Test("Manuscript accepts a committed child while derived refresh remains stale")
    func manuscriptAcceptsCommittedChildAcrossRefreshFailures() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let worksVaultID = try #require(fixture.assignment.vault(for: .output)?.id)
        let workID = VaultQualifiedNoteID(
            vaultID: worksVaultID,
            relativePath: "Chapter.md"
        )
        let work = try await functionTarget(workID, role: .work, handle: handle)
        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        let manuscriptMethod = try await handle.research.duplicateBundledSkill(
            id: "scholium-manuscript",
            as: "refresh-manuscript-method"
        )
        let manuscriptStatus = try await handle.research
            .researchFunctionSkillBindingStatus(for: .manuscript)
        _ = try await handle.research.saveResearchFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .manuscript,
                primaryPackageID: manuscriptMethod.id
            ),
            expectedBindingRevision: manuscriptStatus.bindingRevision
        )

        let manuscript = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .manuscript, target: work, conditionalResources: [])
        )
        let revise = try await handle.research.prepareFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)

        let original = try await handle.documents.load(workID)
        let revisedSource = original.rawContent
            + "\nAn explicit premise now supports the inference.\n"
        try Data(revisedSource.utf8).write(
            to: fixture.worksURL.appendingPathComponent("Chapter.md"),
            options: .atomic
        )
        let revisedFingerprint = DocumentFingerprint(content: revisedSource)
        let fidelityOutcomes = try #require(revise.snapshot.fidelityHandoff).checks
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { check in
                FidelityCheckOutcome(
                    check: check,
                    state: .passed,
                    summary: "The final Work revision passed the selected check."
                )
            }
        let reviseActivityCompletion = try researchActivityCompletion(
            for: revise,
            candidateModifiedNotes: [workID],
            summary: "Revised the Work."
        )
        let awaitingRevision = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the Work; final Fidelity remains pending.",
                didModifyTarget: true,
                activityCompletion: reviseActivityCompletion
            )
        )
        #expect(awaitingRevision.state == .awaitingFidelity)
        let finalWork = ResearchFunctionTarget(
            noteID: work.noteID,
            note: work.note,
            role: work.role,
            lifecycle: work.lifecycle,
            fingerprint: revisedFingerprint,
            title: work.title
        )
        let fidelity = try await handle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalWork,
                checks: try #require(revise.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
                finalTargetFingerprint: revisedFingerprint,
                summary: "Checked the exact final Work revision.",
                didModifyTarget: false,
                fidelityOutcomes: fidelityOutcomes
            )
        )
        let reviseCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the Work and linked final Fidelity evidence.",
                didModifyTarget: true,
                activityCompletion: reviseActivityCompletion,
                childRunIDs: [fidelity.runID]
            )
        )
        #expect(reviseCompletion.state == .complete)
        #expect(reviseCompletion.derivedRefreshWarning?.isEmpty == false)

        // The last-known-good snapshot contains the prepared child but not its
        // committed completion. Child selection must consult the durable store.
        #expect(try await handle.snapshot().research.functionRuns.first {
            $0.id == revise.runID
        }?.completion == nil)
        let manuscriptCompletion = try await handle.research.completeFunction(
            ResearchFunctionCompletionSubmission(
                runID: manuscript.runID,
                confirmationToken: manuscript.snapshot.confirmationToken,
                finalTargetFingerprint: revisedFingerprint,
                summary: "Coordinated the selected manuscript activity.",
                didModifyTarget: true,
                childRunIDs: [revise.runID]
            )
        )
        #expect(manuscriptCompletion.state == .complete)
        #expect(manuscriptCompletion.childRunIDs == [revise.runID])
        #expect(manuscriptCompletion.reusedFidelityRunID == revise.runID)
        #expect(manuscriptCompletion.derivedRefreshWarning?.isEmpty == false)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        let functionRuns = try await handle.snapshot().research.functionRuns
        #expect(functionRuns.first { $0.id == revise.runID }?.completion?.state == .complete)
        #expect(functionRuns.first { $0.id == manuscript.runID }?.completion?.state == .complete)
        await runtime.shutdown()
    }
}

private func functionTarget(
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

private func researchActivityCompletion(
    for preparation: ResearchFunctionPreparation,
    candidateModifiedNotes: [VaultQualifiedNoteID],
    summary: String,
    submittedAt: Date = Date()
) throws -> ResearchActivityCompletionSubmission {
    let prefix = "Activity key: "
    let key = try #require(
        preparation.instructions
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
    )
    return ResearchActivityCompletionSubmission(
        activityID: try #require(preparation.snapshot.activityID),
        activityKey: String(key),
        candidateModifiedNotes: candidateModifiedNotes,
        summary: summary,
        submittedAt: submittedAt
    )
}

private extension FidelityCheckOutcome {
    static let passedContent = Self(
        check: .content,
        state: .passed,
        summary: "The exact final revision passed the Content Fidelity check."
    )
}
