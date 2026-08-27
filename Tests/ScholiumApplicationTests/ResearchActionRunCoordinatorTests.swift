import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Research Action Run coordinator ownership")
struct ResearchActionCoordinatorTests {
    private func preflightStart(
        runtime: WorkspaceRuntime,
        triptychID: UUID,
        requestID: UUID,
        relativePath: String,
        metadata: AnalysisCreationMetadata,
        source: ResearchAgentNewAnalysisSource? = nil,
        academicPurpose: String? = nil
    ) async throws -> (
        request: ResearchAgentStartRequest,
        preflight: ResearchAgentAnalysisCreationPreflight,
        target: VaultQualifiedNoteID
    ) {
        let destination = try ResearchAgentAnalysisDestination(
            managedDefaultFilename: relativePath
        )
        let input = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: destination,
            metadata: metadata,
            source: source,
            sourceRoute: source == nil ? .researcherProvided : nil
        )
        let preflight = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: triptychID,
            request: input
        )
        #expect(preflight.status == .ready)
        let creation = try #require(preflight.startNewAnalysis)
        return (
            try ResearchAgentStartRequest(
                actionID: .analyze,
                newAnalysis: creation,
                academicInputs: academicPurpose.map {
                    ["research-request": .freeText($0)]
                } ?? [:]
            ),
            preflight,
            preflight.targetState.target
        )
    }

    @Test("Direct Agent start validates every current custom academic input")
    func directStartSupportsCustomRequiredAcademicInputs() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let profiles = try await handle.research.academicActionProfiles()
        let originalAnalyze = try #require(
            profiles.document.profile(for: .analyze)
        )
        let focusID = try #require(
            ResearchAcademicFieldID(rawValue: "required-focus")
        )
        let focus = try ResearchAcademicFieldDefinition.freeText(
            id: focusID,
            label: "Required Focus",
            requirement: .required
        )
        let customized = try ResearchAcademicActionProfile(
            actionID: originalAnalyze.actionID,
            displayName: originalAnalyze.displayName,
            order: originalAnalyze.order,
            isEnabled: originalAnalyze.isEnabled,
            applicableRoles: originalAnalyze.applicableRoles,
            academicInputFields: originalAnalyze.academicInputFields + [focus],
            academicResultFields: originalAnalyze.academicResultFields
        )
        let document = try ResearchAcademicProfileDocument(
            profiles: profiles.document.profiles.map {
                $0.actionID == .analyze ? customized : $0
            }
        )
        _ = try await handle.research.saveAcademicActionProfiles(
            document,
            expectedRevision: profiles.revision
        )

        let incomplete = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: fixture.analysisNoteID,
            academicInputs: [
                "research-request": .freeText("Analyze the bounded source."),
            ],
            sourceRoute: .researcherProvided
        )
        await #expect(throws: ResearchAcademicProfileError.self) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: incomplete,
                sessionValidity: 300
            )
        }

        let complete = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: fixture.analysisNoteID,
            academicInputs: [
                "research-request": .freeText("Analyze the bounded source."),
                "required-focus": .freeText("Test the central inference."),
            ],
            sourceRoute: .researcherProvided
        )
        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: complete,
            sessionValidity: 300
        )
        let context = try await runtime.researchAgentContext(
            credential: started.credential,
            run: started.receipt.run
        )
        #expect(context.brief.academicPurpose == "Analyze the bounded source.")
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Analysis creation preflight exposes optional preferences without Settings authority")
    func analysisCreationPreflightSettingsBoundary() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.services.controlStore.settings()
        var settings = original.settings
        settings.metadataFields[.paperAnalysis] = [
            MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
        ]
        settings.analysisAgentCreation = AnalysisAgentCreationConfiguration(
            preferredFieldsBySourceType: [
                .journalArticle: ["authors", "argument_stage"],
            ]
        )
        let preferredSnapshot = try await handle.services.controlStore.saveSettings(
            settings,
            expectedRevision: original.revision
        )
        let requestID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000461"
        )!
        let input = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Optional Fields.md"
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            sourceRoute: .researcherProvided
        )
        let ready = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: input
        )
        #expect(ready.status == .ready)
        #expect(Set(ready.preferredFields) == ["authors", "argument_stage"])
        #expect(Set(ready.fixedYAMLFields) == ["summary", "keywords"])
        #expect(ready.applicableFields.contains { $0.canonicalKey == "authors" })
        #expect(ready.applicableFields.contains {
            $0.canonicalKey == "argument_stage" && $0.valueKind == .text
        })
        let start = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: #require(ready.startNewAnalysis)
        )

        settings.attentionDismissalDays += 1
        _ = try await handle.services.controlStore.saveSettings(
            settings,
            expectedRevision: preferredSnapshot.revision
        )
        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: start,
            sessionValidity: 300
        )
        #expect(started.receipt.target.note == ready.targetState.target)
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("A pre-commit reservation freezes authored and managed values, not Settings preferences")
    func analysisCreationReservationRecoveryBoundary() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let requestID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000462"
        )!
        let initialInput = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Reserved Before Source.md"
            ),
            metadata: AnalysisCreationMetadata(
                sourceType: .journalArticle,
                fields: [try CanonicalPropertyInput(
                    key: "title",
                    value: .string("Frozen initial title")
                )]
            ),
            authoredYAML: try AuthoredNoteYAML(
                summary: "Frozen authored summary",
                keywords: ["reservation"]
            ),
            sourceRoute: .researcherProvided
        )
        let initialPreflight = try await runtime
            .preflightResearchAgentAnalysisCreation(
                triptychID: fixture.assignment.id,
                request: initialInput
            )
        let initialStart = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: #require(initialPreflight.startNewAnalysis),
            academicInputs: [
                "research-request": .freeText("Frozen initial purpose"),
            ]
        )

        let gate = AgentCreationReservationGate()
        await handle.setManagedCreationPreLeaseBarrierForTesting {
            await gate.wait()
        }
        let starting = Task {
            try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: initialStart,
                sessionValidity: 300
            )
        }
        #expect(await gate.waitUntilArrived())
        let original = try await handle.services.controlStore.settings()
        var changed = original.settings
        changed.analysisAgentCreation = AnalysisAgentCreationConfiguration(
            preferredFieldsBySourceType: [.journalArticle: ["authors"]]
        )
        _ = try await handle.services.controlStore.saveSettings(
            changed,
            expectedRevision: original.revision
        )
        await gate.release()
        let started = try await starting.value
        await handle.setManagedCreationPreLeaseBarrierForTesting(nil)
        #expect(started.receipt.target.note == initialPreflight.targetState.target)

        let changedSourceType = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: initialInput.destination,
            metadata: AnalysisCreationMetadata(
                sourceType: .book,
                fields: [try CanonicalPropertyInput(
                    key: "title",
                    value: .string("Frozen initial title")
                )]
            ),
            authoredYAML: initialInput.authoredYAML,
            sourceRoute: .researcherProvided
        )
        #expect(try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: changedSourceType
        ).status == .replayConflict)

        let changedExistingValue = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: initialInput.destination,
            metadata: AnalysisCreationMetadata(
                sourceType: .journalArticle,
                fields: [
                    try CanonicalPropertyInput(
                        key: "title",
                        value: .string("Rewritten title")
                    ),
                ]
            ),
            authoredYAML: initialInput.authoredYAML,
            sourceRoute: .researcherProvided
        )
        #expect(try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: changedExistingValue
        ).status == .replayConflict)

        let changedAuthored = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: requestID,
            destination: initialInput.destination,
            metadata: initialInput.metadata,
            authoredYAML: try AuthoredNoteYAML(
                summary: "Changed authored summary",
                keywords: ["reservation"]
            ),
            sourceRoute: .researcherProvided
        )
        #expect(try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: changedAuthored
        ).status == .replayConflict)
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Concurrent exact starts coalesce while changed payload conflicts")
    func concurrentAnalysisCreationStarts() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let prepared = try await preflightStart(
            runtime: runtime,
            triptychID: fixture.assignment.id,
            requestID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000464"
            )!,
            relativePath: "Concurrent Creation.md",
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            academicPurpose: "One frozen purpose."
        )
        let gate = AgentCreationReservationGate()
        await handle.setManagedCreationPreLeaseBarrierForTesting {
            await gate.wait()
        }
        let first = Task {
            try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: prepared.request,
                sessionValidity: 300
            )
        }
        #expect(await gate.waitUntilArrived())
        let same = Task {
            try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: prepared.request,
                sessionValidity: 300
            )
        }
        let changed = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: #require(prepared.request.newAnalysis),
            academicInputs: [
                "research-request": .freeText("A concurrent changed purpose."),
            ]
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: changed,
                sessionValidity: 300
            )
        }
        await gate.release()
        let firstStarted = try await first.value
        let sameStarted = try await same.value
        #expect(firstStarted.receipt.run != sameStarted.receipt.run)
        #expect(firstStarted.receipt.target.noteID
            == sameStarted.receipt.target.noteID)
        let executions = try await handle.services.localResearchExecutionStore
            .listing().records.filter {
                $0.snapshot.actionSnapshot.target.note == prepared.target
            }
        #expect(executions.count == 1)
        let source = try await handle.documents.load(prepared.target)
        #expect(source.fingerprint == firstStarted.receipt.target.fingerprint)
        let services = await handle.services
        let sessions = try #require(services.researchAgentSessions)
        let firstAuthentication = try? await sessions.authenticate(
            firstStarted.credential,
            run: firstStarted.receipt.run,
            requiresWrite: true,
        )
        let sameAuthentication = try? await sessions.authenticate(
            sameStarted.credential,
            run: sameStarted.receipt.run,
            requiresWrite: true,
        )
        #expect((firstAuthentication == nil) != (sameAuthentication == nil))
        await handle.setManagedCreationPreLeaseBarrierForTesting(nil)
        await runtime.shutdown()
    }

    @Test("Analysis creation preflight distinguishes occupied paths and missing portable sources")
    func analysisCreationPreflightRecoveryStates() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        _ = try await runtime.openWorkspace(id: fixture.assignment.id)

        let occupiedURL = fixture.analysesURL.appendingPathComponent("Occupied.md")
        try Data("# Occupied\n".utf8).write(to: occupiedURL)
        let occupiedRequest = try ResearchAgentAnalysisCreationPreflightRequest(
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Occupied.md"
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            sourceRoute: .researcherProvided
        )
        let occupied = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: occupiedRequest
        )
        #expect(occupied.status == .pathOccupied)
        #expect(occupied.targetState.sourceState == .present)
        #expect(occupied.targetState.stableIdentity == nil)
        #expect(occupied.recovery.nextStep
            == .requestResearcherDistinctFilenameAndPreflight)
        #expect(!occupied.recovery.mustReuseRequestIdentity)

        let existingRequest = try ResearchAgentAnalysisCreationPreflightRequest(
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Agency.md"
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            sourceRoute: .researcherProvided
        )
        let existing = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: existingRequest
        )
        #expect(existing.status == .identityOccupied)
        #expect(existing.targetState.stableIdentity != nil)
        #expect(existing.recovery.nextStep == .startExistingAnalysis)

        try FileManager.default.removeItem(
            at: fixture.analysesURL.appendingPathComponent("Agency.md")
        )
        let missing = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: existingRequest
        )
        #expect(missing.status == .identitySourceMissingOrTrashed)
        #expect(missing.targetState.sourceState == .missingOrInSystemTrash)
        #expect(missing.targetState.stableIdentity == existing.targetState.stableIdentity)
        #expect(missing.recovery.nextStep == .requestResearcherRecoveryChoice)
        #expect(!missing.recovery.mustReuseRequestIdentity)
        #expect(missing.recovery.creationBranches.map(\.kind) == [
            .restoreOriginalSource,
            .explicitlyCreateAtDistinctDestination,
        ])
        #expect(!missing.recovery.creationBranches[0].mustReuseRequestIdentity)
        #expect(missing.recovery.creationBranches[0].nextStep
            == .startExistingAnalysis)
        #expect(!missing.recovery.creationBranches[1].mustReuseRequestIdentity)
        #expect(missing.startNewAnalysis == nil)
        await runtime.shutdown()
    }

    @Test("Exact start refuses a replacement Session after the created source is missing")
    func analysisCreationRunSourceLossRecovery() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let prepared = try await preflightStart(
            runtime: runtime,
            triptychID: fixture.assignment.id,
            requestID: UUID(
                uuidString: "00000000-0000-0000-0000-000000000463"
            )!,
            relativePath: "Created Then Missing.md",
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle)
        )
        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: prepared.request,
            sessionValidity: 300
        )
        try FileManager.default.removeItem(
            at: fixture.analysesURL.appendingPathComponent(
                prepared.target.relativePath
            )
        )

        let recovery = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: #require(prepared.request.newAnalysis).preflight
        )
        #expect(recovery.status == .identitySourceMissingOrTrashed)
        #expect(recovery.targetState.stableIdentity == started.receipt.target.noteID)
        #expect(recovery.recovery.creationBranches[0].kind == .restoreOriginalSource)
        #expect(recovery.recovery.creationBranches[0].mustReuseRequestIdentity)
        #expect(recovery.recovery.creationBranches[0].nextStep == .retryExactRequest)
        #expect(!recovery.recovery.creationBranches[1].mustReuseRequestIdentity)
        await #expect(
            throws: ResearchAgentConnectionError
                .analysisIdentitySourceMissingOrTrashed
        ) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: prepared.request,
                sessionValidity: 300
            )
        }
        try Data("# Restored with a different revision\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent(
                prepared.target.relativePath
            ),
            options: .atomic
        )
        let stale = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: #require(prepared.request.newAnalysis).preflight
        )
        #expect(stale.status == .runStale)
        #expect(stale.recovery.nextStep == .startNewActionFromCurrentRevision)
        await #expect(throws: ResearchAgentConnectionError.runStale(.targetChanged)) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: prepared.request,
                sessionValidity: 300
            )
        }
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Exact Analysis replay preserves a newer researcher Zotero binding")
    func agentStartBindingReplayConflict() async throws {
        enum InjectedFailure: Error { case afterBinding }
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        await handle.setAgentStartPostBindingBarrierForTesting {
            throw InjectedFailure.afterBinding
        }
        let prepared = try await preflightStart(
            runtime: runtime,
            triptychID: fixture.assignment.id,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000458")!,
            relativePath: "Binding Replay.md",
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            source: ResearchAgentNewAnalysisSource(
                library: .user,
                itemKey: "ORIGINAL1"
            )
        )
        let target = prepared.target
        let request = prepared.request

        await #expect(throws: InjectedFailure.afterBinding) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: request,
                sessionValidity: 300
            )
        }
        let identity = try #require(
            try await handle.services.controlStore.identityRecord(
                vaultID: target.vaultID,
                relativePath: target.relativePath
            )
        )
        let original = try #require(
            try await handle.services.controlStore.zoteroBindings()
                .binding(for: identity.id)
        )
        #expect(original.itemKey == "ORIGINAL1")

        let beforeRebind = try await handle.services.controlStore.zoteroBindings()
        let researcherBinding = try AnalysisZoteroBinding(
            noteID: identity.id,
            library: .group(42),
            itemKey: "RESEARCH2"
        )
        _ = try await handle.services.controlStore.setZoteroBinding(
            researcherBinding,
            expectedRevision: beforeRebind.revision
        )
        await handle.setAgentStartPostBindingBarrierForTesting(nil)

        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: request,
                sessionValidity: 300
            )
        }
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: identity.id) == researcherBinding)

        let beforeClear = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.clearZoteroBinding(
            for: identity.id,
            expectedRevision: beforeClear.revision
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: request,
                sessionValidity: 300
            )
        }
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: identity.id) == nil)
        await runtime.shutdown()
    }

    @Test("Agent Analysis creation survives a stale projection and exact retry does not duplicate source")
    func agentStartCreationProjectionRecovery() async throws {
        enum InjectedFailure: Error { case staleProjection }
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        await handle.setResearchStateRepairBarrierForTesting {
            throw InjectedFailure.staleProjection
        }
        let prepared = try await preflightStart(
            runtime: runtime,
            triptychID: fixture.assignment.id,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000457")!,
            relativePath: "Projection Recovery.md",
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle)
        )
        let target = prepared.target
        let request = prepared.request

        do {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: request,
                sessionValidity: 300
            )
            Issue.record("A failed derived projection must remain visible to the caller.")
        } catch let error as ScholiumApplicationError {
            guard case .operationCommittedButRefreshFailed = error else {
                Issue.record("Unexpected committed creation result: \(error)")
                return
            }
        }
        let committed = try await handle.documents.load(target)
        let identity = try #require(
            try await handle.services.controlStore.identityRecord(
                vaultID: target.vaultID,
                relativePath: target.relativePath
            )
        )
        #expect(identity.fingerprint == committed.fingerprint)

        let targetURL = fixture.analysesURL.appendingPathComponent(
            target.relativePath
        )
        try Data("# Changed during projection recovery\n".utf8).write(
            to: targetURL,
            options: .atomic
        )
        let changed = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: #require(request.newAnalysis).preflight
        )
        #expect(changed.status == .replayConflict)
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: request,
                sessionValidity: 300
            )
        }
        try committed.sourceBytes.write(to: targetURL, options: .atomic)
        let resumable = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: #require(request.newAnalysis).preflight
        )
        #expect(resumable.status == .sourceCommittedProjectionPending)

        await handle.setResearchStateRepairBarrierForTesting(nil)
        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: request,
            sessionValidity: 300
        )
        #expect(started.receipt.target.noteID == identity.id)
        #expect(try await handle.documents.load(target).fingerprint == committed.fingerprint)
        _ = try await runtime.endResearchAgentRun(
            credential: started.credential,
            run: started.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Agent start creates an absent Analysis through the managed creator")
    func agentStartCreatesNewAnalysis() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let requestID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000456"
        )!
        let metadata = try AnalysisCreationMetadata(
            sourceType: .journalArticle,
            fields: [
                try CanonicalPropertyInput(
                    key: "title",
                    value: .string("Agent-created Analysis")
                ),
            ]
        )
        let prepared = try await preflightStart(
            runtime: runtime,
            triptychID: fixture.assignment.id,
            requestID: requestID,
            relativePath: "Created Analysis.md",
            metadata: metadata,
            academicPurpose: "Reconstruct the source argument with bounded evidence."
        )
        let createdID = prepared.target
        let creation = try #require(prepared.request.newAnalysis)
        let request = prepared.request
        #expect(prepared.preflight.analysisVaultID == createdID.vaultID)
        #expect(createdID.relativePath == "Created Analysis.md")
        #expect(prepared.preflight.recovery.nextStep == .startWithReturnedTemplate)

        let started = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: request,
            sessionValidity: 300
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(createdID)
        #expect(document.rawContent
            == "---\nsummary: null\nkeywords: []\n---\n")
        let createdMetadata = try #require(
            try await handle.services.controlStore.noteMetadata(
                noteID: started.receipt.target.noteID
            )
        )
        #expect(createdMetadata.record.fields["type"]?.scalarString
            == AnalysisSourceType.journalArticle.rawValue)
        #expect(createdMetadata.record.fields["title"]?.scalarString
            == "Agent-created Analysis")

        let note = try #require(try await handle.snapshot().document(id: createdID))
        #expect(note.stableIdentity.resolvedID == started.receipt.target.noteID)
        let binding = try await handle.services.controlStore.zoteroBindings()
            .binding(for: started.receipt.target.noteID)
        #expect(binding == nil)
        let services = await handle.services
        let sessions = try #require(services.researchAgentSessions)
        let firstAuthenticated = try await sessions.authenticate(
            started.credential,
            run: started.receipt.run,
            requiresWrite: false,
        )

        let changedPreflightInput = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: creation.requestID,
            destination: creation.destination,
            metadata: try AnalysisCreationMetadata(
                sourceType: .journalArticle,
                fields: [
                    try CanonicalPropertyInput(
                        key: "title",
                        value: .string("A different payload must not reuse the committed Note")
                    ),
                ]
            ),
            sourceRoute: .researcherProvided
        )
        let changedPreflight = try await runtime.preflightResearchAgentAnalysisCreation(
            triptychID: fixture.assignment.id,
            request: changedPreflightInput
        )
        #expect(changedPreflight.status == .replayConflict)
        let changedCreation = ResearchAgentNewAnalysisRequest(
            preflight: changedPreflightInput
        )
        let changedRequest = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: changedCreation,
            academicInputs: request.academicInputs
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: changedRequest,
                sessionValidity: 300
            )
        }
        let changedPurpose = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: creation,
            academicInputs: [
                "research-request": .freeText(
                    "A changed purpose must not receive the existing Run."
                ),
            ]
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: changedPurpose,
                sessionValidity: 300
            )
        }
        let retried = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: request,
            sessionValidity: 300
        )
        #expect(retried.receipt.run != started.receipt.run)
        #expect(retried.receipt.target.noteID == started.receipt.target.noteID)
        let retriedDocument = try await handle.documents.load(createdID)
        #expect(retriedDocument.fingerprint == document.fingerprint)
        #expect(retriedDocument.sourceBytes == document.sourceBytes)

        let context = try await runtime.researchAgentContext(
            credential: retried.credential,
            run: retried.receipt.run
        )
        #expect(context.brief.actionID == .analyze)
        #expect(context.brief.initialObjectRole == .analysis)
        #expect(context.boundedWriteSet.contains(where: {
            $0.relativePath == createdID.relativePath
                && $0.operations.contains(.modifyMarkdown)
        }))

        let authenticated = try await sessions.authenticate(
            retried.credential,
            run: retried.receipt.run,
            requiresWrite: false,
        )
        #expect(authenticated.runID == firstAuthenticated.runID)
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            _ = try await sessions.authenticate(
                started.credential,
                run: started.receipt.run,
                requiresWrite: false,
            )
        }
        let execution = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        #expect(execution.snapshot.sourceReference == nil)
        #expect(execution.snapshot.analysisSourceRoute == .researcherProvided)
        #expect(execution.preparedInstructions.contains("Researcher-provided source"))
        #expect(!execution.preparedInstructions.contains("machineLocalPath"))

        let receipt = try await runtime.submitResearchAgentResult(
            credential: retried.credential,
            run: retried.receipt.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: ResearchRecordTitle("Researcher-provided source analysis"),
                academicResults: ResearchAcademicFieldValues(
                    rawValues: [
                        "source-reconstruction": .freeText(
                            "The researcher-provided source supports one bounded reconstruction."
                        ),
                        "coverage": .singleChoice("specified-part-only"),
                        "reliability": .multipleChoice(["no-material-limitations"]),
                    ],
                    definitions: context.resultContract.academicFields
                ),
                literatureRecommendations: []
            )
        )
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)
        let record = try await services.portableResearchRecordStore.record(
            id: authenticated.runID
        )
        #expect(record.analysisSourceRoute == .researcherProvided)
        #expect(record.sourceReference == nil)
        #expect(record.zoteroBibliographicContext == nil)

        _ = try await runtime.endResearchAgentRun(
            credential: retried.credential,
            run: retried.receipt.run
        )
        await runtime.shutdown()
    }

    @Test("Completed and cancelled Analysis creation replays issue no Session")
    func terminalAgentStartCreationReplay() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        func request(_ suffix: String, id: String) async throws
            -> ResearchAgentStartRequest {
            try await preflightStart(
                runtime: runtime,
                triptychID: fixture.assignment.id,
                requestID: UUID(uuidString: id)!,
                relativePath: "Terminal \(suffix).md",
                metadata: AnalysisCreationMetadata(sourceType: .journalArticle)
            ).request
        }

        let completedRequest = try await request(
            "Complete",
            id: "00000000-0000-0000-0000-000000000459"
        )
        let completed = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: completedRequest,
            sessionValidity: 300
        )
        let completedContext = try await runtime.researchAgentContext(
            credential: completed.credential,
            run: completed.receipt.run
        )
        _ = try await runtime.submitResearchAgentResult(
            credential: completed.credential,
            run: completed.receipt.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: ResearchRecordTitle("Completed creation replay"),
                academicResults: ResearchAcademicFieldValues(
                    rawValues: [
                        "source-reconstruction": .freeText("One bounded result."),
                        "coverage": .singleChoice("specified-part-only"),
                        "reliability": .multipleChoice(["no-material-limitations"]),
                    ],
                    definitions: completedContext.resultContract.academicFields
                ),
                literatureRecommendations: []
            )
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: completedRequest,
                sessionValidity: 300
            )
        }

        let cancelledRequest = try await request(
            "Cancelled",
            id: "00000000-0000-0000-0000-000000000460"
        )
        let cancelled = try await runtime.startResearchAgentRun(
            triptychID: fixture.assignment.id,
            request: cancelledRequest,
            sessionValidity: 300
        )
        _ = try await runtime.endResearchAgentRun(
            credential: cancelled.credential,
            run: cancelled.receipt.run
        )
        await #expect(throws: ResearchAgentConnectionError.newAnalysisReplayConflict) {
            _ = try await runtime.startResearchAgentRun(
                triptychID: fixture.assignment.id,
                request: cancelledRequest,
                sessionValidity: 300
            )
        }
        await runtime.shutdown()
    }

    @Test("Coordinator owns protected preparation and completion on the Workspace actor")
    func protectedPreparationAndCompletionOwnership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let coordinator = await handle.researchActionRunCoordinator

        let snapshot = try await handle.snapshot()
        let note = try #require(snapshot.document(id: fixture.analysisNoteID))
        let noteID = try #require(note.stableIdentity.resolvedID)
        let target = ResearchActionNoteSnapshot(
            noteID: noteID,
            note: fixture.analysisNoteID,
            role: .analysis,
            fingerprint: note.fingerprint,
            title: "Analysis"
        )
        let availability = try await coordinator.researchActionRunAvailability(
            for: target,
            checkingSourceAccess: false,
            host: handle
        )
        #expect(availability.first { $0.actionID == .checkFidelity }?.isEnabled == true)
        let preparation = try await coordinator.prepareResearchActionRun(
            ResearchActionRunRequest(
                actionID: .checkFidelity,
                target: target,
                checks: [.content]
            ),
            host: handle
        )
        let recovered = try await coordinator.researchActionRun(
            id: preparation.runID,
            host: handle
        )
        #expect(recovered.snapshot == preparation.snapshot)
        #expect(try coordinator.attachingAgentActions(
            to: recovered
        ).nextActions == nil)
        let submission = ResearchActionRunCompletionSubmission(
            runID: preparation.runID,
            confirmationToken: preparation.snapshot.confirmationToken,
            recordTitle: try ResearchRecordTitle("Test research result"),
            finalTargetFingerprint: note.fingerprint,
            summary: "Checked the frozen Analysis revision.",
            didModifyTarget: false,
            fidelityOutcomes: [FidelityCheckOutcome(
                check: .content,
                state: .passed,
                summary: "The fixture found no unresolved content-fidelity issue."
            )]
        )
        let action = preparation.snapshot.actionSnapshot
        _ = try await handle.services.localResearchExecutionStore.stageResultPayload(
            ResearchRunResultPayload(
                runID: preparation.runID,
                submissionFingerprint: DocumentFingerprint(
                    content: "coordinator-result"
                ),
                recordTitle: submission.recordTitle,
                disposition: .completed,
                academicResults: testAcademicResults(for: action),
                contextUseReport: nil,
                fidelityOutcomes: submission.fidelityOutcomes,
                literatureRecommendations: nil,
                submittedAt: submission.submittedAt
            )
        )

        let completed = try await coordinator.completeActionRun(
            submission,
            host: handle
        )
        #expect(completed.state == .complete)
        #expect(completed.runID == preparation.runID)
        #expect(try await coordinator.record(
            runID: preparation.runID
        ).completion == completed)
        #expect(try await coordinator.completeActionRun(
            submission,
            host: handle
        ) == completed)
        await runtime.shutdown()
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await coordinator.researchActionRun(
                id: preparation.runID,
                host: handle
            )
        }
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await coordinator.completeActionRun(
                submission,
                host: handle
            )
        }
    }

    @Test("One Workspace coordinator owns terminal run persistence and lifetime")
    func terminalRunOwnership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let coordinator = await handle.researchActionRunCoordinator
        let repeatedLookup = await handle.researchActionRunCoordinator
        #expect(coordinator === repeatedLookup)
        #expect(coordinator.workspaceID == handle.id)

        let snapshot = try await handle.snapshot()
        let note = try #require(snapshot.document(id: fixture.analysisNoteID))
        guard case .resolved(let noteID) = note.stableIdentity else {
            Issue.record("The fixture Analysis has no stable identity.")
            await runtime.shutdown()
            return
        }
        let target = ResearchActionNoteSnapshot(
            noteID: noteID,
            note: fixture.analysisNoteID,
            role: .analysis,
            fingerprint: note.fingerprint,
            title: "Analysis"
        )
        let preparation = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .checkFidelity,
                target: target,
                checks: [.content]
            )
        )

        try await handle.research.cancelActionRun(runID: preparation.runID)
        try await handle.research.cancelActionRun(runID: preparation.runID)
        #expect(try await coordinator.record(
            runID: preparation.runID
        ).completion?.state == .cancelled)

        await runtime.shutdown()
        await #expect(throws: ScholiumApplicationError.self) {
            try await coordinator.cancelActionRun(
                runID: preparation.runID,
                host: handle
            )
        }
    }
}

private actor AgentCreationReservationGate {
    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async -> Bool {
        if arrived { return true }
        await withCheckedContinuation { arrivalContinuation = $0 }
        return true
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
