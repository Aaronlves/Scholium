import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Derived refresh status")
struct DerivedRefreshStatusTests {
    @Test("Creation identity rollback failures are never discarded")
    func creationIdentityRollbackFailureIsExplicit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumApplication/WorkspaceHandle.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains(
            "try? await repository.removeCreatedFileForRollback"
        ))
        // Four source-producing operations (import, explicit creation,
        // untitled creation, and duplication) plus the helper declaration
        // must retain the same revision-checked rollback boundary.
        #expect(source.components(
            separatedBy: "retainedCreatedDocumentAfterIdentityFailure("
        ).count == 6)
        #expect(source.contains(
            "CreatedDocumentIdentityRollbackError.sourcePresenceUncertain("
        ))
    }

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

    @Test("A committed source mutation returns before a failing derived refresh")
    func committedMutationReturnsBeforeDerivedFailure() async throws {
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
        let saved = try await handle.documents.commit(
            fixture.analysisNoteID,
            changeSet: .body("Committed exactly once.\n"),
            expectedRevision: original.fingerprint
        )
        let committedRevision = saved.document.fingerprint

        // Save acknowledges authoritative bytes. The owned background refresh
        // independently reports stale derived state and never converts that
        // committed result into an Autosave Failed retry.
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

    @Test("A committed Folder claim returns before a failing derived refresh")
    func committedFolderReturnsBeforeDerivedFailure() async throws {
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
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)

        let outcome = try await handle.documents.createUntitledFolder(
            inVault: fixture.analysisNoteID.vaultID,
            parentRelativePath: nil
        )

        #expect(outcome.committedValue.rawValue == "Untitled Folder")
        #expect(outcome.derivedRefreshWarning == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Untitled Folder").path))
        let stale = try #require(await iterator.next())
        guard case .stale(let issue) = stale.derivedRefreshStatus else {
            Issue.record("A failed background Folder refresh was not marked stale.")
            await runtime.shutdown()
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.analysisNoteID.vaultID])
        #expect(issue.lastKnownGood == WorkspaceDerivedRefreshEvidence(
            snapshot: initial.snapshot
        ))

        try FileManager.default.removeItem(at: invalidURL)
        let refreshed = try await handle.discovery.refresh()
        #expect(refreshed.vault(id: fixture.analysisNoteID.vaultID)?.folders.contains {
            $0.rawValue == "Untitled Folder"
        } == true)
        _ = try #require(await iterator.next())
        await runtime.shutdown()
    }

    @Test("A known-stale projection cannot authorize the optimized move plan")
    func staleProjectionCannotAuthorizeMoveFastPath() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        _ = try await handle.documents.createUntitledFolder(
            inVault: fixture.analysisNoteID.vaultID,
            parentRelativePath: nil
        )
        let stale = try #require(await iterator.next())
        guard case .stale = stale.derivedRefreshStatus else {
            Issue.record("The fixture did not establish a known-stale projection.")
            await runtime.shutdown()
            return
        }

        let source = try await handle.documents.load(fixture.analysisNoteID)
        do {
            _ = try await handle.documents.move(
                fixture.analysisNoteID,
                to: "Moved/Agency.md",
                expectedRevision: source.fingerprint
            )
            Issue.record("A stale snapshot unexpectedly authorized an optimized move.")
        } catch {
            // The complete planner observes the invalid authoritative source
            // and fails before the Note rename can commit.
        }
        #expect(FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Agency.md").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Moved/Agency.md").path))
        await runtime.shutdown()
    }

    @Test("Document mutations return committed values instead of retryable refresh failures")
    func documentMutationOutcomesPreserveCommittedAuthority() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        func makeDerivedRefreshFail() throws {
            try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)
        }

        func recoverDerivedProjection() async throws {
            try FileManager.default.removeItem(at: invalidURL)
            _ = try await handle.discovery.refresh()
        }

        try makeDerivedRefreshFail()
        let createdID = VaultQualifiedNoteID(
            vaultID: fixture.analysisNoteID.vaultID,
            relativePath: "Postcommit Created.md"
        )
        let created = try await handle.documents.create(
            createdID,
            content: ""
        )
        #expect(created.committedValue.rawContent.isEmpty)
        #expect(created.derivedRefreshWarning?.isEmpty == false)
        #expect(created.identityRecoveryWarning == nil)
        #expect(try await handle.documents.load(createdID).sourceBytes.isEmpty)

        try await recoverDerivedProjection()
        try makeDerivedRefreshFail()
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let saved = try await handle.documents.save(
            fixture.analysisNoteID,
            changeSet: .body("Committed once despite a failed derived refresh.\n"),
            expectedRevision: original.fingerprint
        )
        #expect(saved.derivedRefreshWarning?.isEmpty == false)
        #expect(saved.identityRecoveryWarning == nil)
        #expect(try await handle.documents.load(fixture.analysisNoteID).fingerprint
            == saved.committedValue.document.fingerprint)

        try await recoverDerivedProjection()
        let current = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let stableID = try #require(current.stableIdentity.resolvedID)
        let preview = try await handle.documents.prepareSystemTrash(
            NoteMutationTarget(
                documentID: fixture.analysisNoteID,
                stableNoteID: stableID,
                revision: current.fingerprint
            )
        )
        try makeDerivedRefreshFail()
        let trashed = try await handle.documents.moveToSystemTrash(preview)
        defer {
            for path in trashed.committedValue.resultingTrashPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        #expect(trashed.derivedRefreshWarning?.isEmpty == false)
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.documents.load(fixture.analysisNoteID)
        }

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

        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        #expect(preparation.derivedRefreshWarning?.isEmpty == false)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == preparation.runID
        })
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        let completion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: preparation.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
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
        #expect(try await handle.services.localResearchExecutionStore.listing().records.first {
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

        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        #expect(preparation.derivedRefreshWarning?.isEmpty == false)
        let completion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: preparation.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked the exact Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.derivedRefreshPassedContent]
            )
        )
        #expect(completion.state == .complete)
        #expect(completion.derivedRefreshWarning?.isEmpty == false)

        // Action execution is intentionally absent from the disposable
        // workspace projection. Reuse must come from the durable store.
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: preparation.runID
        ).completion?.state == .complete)
        let reused = try await handle.research.prepareProtectedFunction(
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
        let persistedMatches = try await handle.services.localResearchExecutionStore
            .listing().records.filter {
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

        let registrations = try await handle.research.researchSkillRegistrations()
        let manuscriptRegistration = try #require(
            registrations.document.registration(for: .manuscript)
        )
        _ = try await handle.research.saveResearchSkillRegistrations(
            try registrations.document.replacing(ResearchSkillRegistration(
                key: manuscriptRegistration.key,
                actionID: manuscriptRegistration.actionID,
                displayName: manuscriptRegistration.displayName,
                primaryMarkdown: manuscriptRegistration.primaryMarkdown,
                skillFolder: manuscriptRegistration.skillFolder,
                isEnabled: true
            )),
            expectedRevision: registrations.revision
        )
        let profiles = try await handle.research.academicActionProfiles()
        let manuscriptProfile = try #require(
            profiles.document.profile(for: .manuscript)
        )
        let enabledProfile = try ResearchAcademicActionProfile(
            actionID: manuscriptProfile.actionID,
            displayName: manuscriptProfile.displayName,
            order: manuscriptProfile.order,
            isEnabled: true,
            applicableRoles: manuscriptProfile.applicableRoles,
            academicInputFields: manuscriptProfile.academicInputFields,
            academicResultFields: manuscriptProfile.academicResultFields
        )
        _ = try await handle.research.saveAcademicActionProfiles(
            try ResearchAcademicProfileDocument(
                profiles: profiles.document.profiles.filter {
                    $0.actionID != .manuscript
                } + [enabledProfile]
            ),
            expectedRevision: profiles.revision
        )

        let manuscript = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .manuscript, target: work)
        )
        let revise = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .revise, target: work)
        )
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)

        let original = try await handle.documents.load(workID)
        let revisedBody = original.body
            + "\nAn explicit premise now supports the inference.\n"
        let revisedSource = try original.applying(
            .body(revisedBody),
            timestampKey: nil
        )
        let write = try await writePreparedResearchDocument(
            for: revise,
            body: revisedBody,
            handle: handle
        )
        #expect(write.state == .committed)
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
        let awaitingRevision = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                summary: "Revised the Work; final Fidelity remains pending.",
                didModifyTarget: true
            )
        )
        #expect(awaitingRevision.state == .awaitingFidelity)
        let finalWork = ResearchFunctionTarget(
            noteID: work.noteID,
            note: work.note,
            role: work.role,
            fingerprint: revisedFingerprint,
            title: work.title
        )
        let fidelity = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalWork,
                checks: try #require(revise.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: revisedFingerprint,
                summary: "Checked the exact final Work revision.",
                didModifyTarget: false,
                fidelityOutcomes: fidelityOutcomes
            )
        )
        let reviseCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                summary: "Revised the Work and linked final Fidelity evidence.",
                didModifyTarget: false,
                childRunIDs: [fidelity.runID]
            )
        )
        #expect(reviseCompletion.state == .complete)
        #expect(reviseCompletion.derivedRefreshWarning?.isEmpty == false)

        // Child selection consults durable execution evidence, not the
        // disposable workspace projection.
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: revise.runID
        ).completion?.state == .complete)
        let manuscriptCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: manuscript.runID,
                confirmationToken: manuscript.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: revisedFingerprint,
                summary: "Coordinated the selected manuscript activity.",
                didModifyTarget: false,
                childRunIDs: [revise.runID]
            )
        )
        #expect(manuscriptCompletion.state == .complete)
        #expect(manuscriptCompletion.childRunIDs == [revise.runID])
        #expect(manuscriptCompletion.reusedFidelityRunID == revise.runID)
        #expect(manuscriptCompletion.derivedRefreshWarning?.isEmpty == false)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        let functionRuns = try await handle.services.localResearchExecutionStore
            .listing().records
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
        fingerprint: note.fingerprint,
        title: note.document.parsedFrontmatter["title"]?.scalarString ?? id.relativePath
    )
}

private extension FidelityCheckOutcome {
    static let derivedRefreshPassedContent = Self(
        check: .content,
        state: .passed,
        summary: "The exact final revision passed the Content Fidelity check."
    )
}
