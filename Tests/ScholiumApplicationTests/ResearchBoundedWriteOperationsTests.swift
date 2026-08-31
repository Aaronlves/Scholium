import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Authenticated bounded Research write sets", .serialized)
struct ResearchBoundedWriteOperationsTests {
    @Test("Synthesize and Write reload and exact reread advance to their own committed revision")
    func selfWriteAdvancesAuthenticatedReadBoundary() async throws {
        for actionID in [ResearchActionID.synthesize, .write] {
            let fixture = try await ResearchFixture.make()
            defer { fixture.remove() }
            let runtime = fixture.runtime()
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let role: ResearchActionTargetRole = actionID == .synthesize
                ? .topic
                : .work
            let note = actionID == .synthesize ? fixture.topicID : fixture.workID
            let target = try await researchActionTarget(
                note,
                role: role,
                handle: handle
            )
            let helpers = ResearchActionRunOperationsTests()
            let preparation = try await handle.research.prepareAction(
                try await helpers.actionRequest(
                    handle: handle,
                    actionID: actionID,
                    target: target
                )
            )
            let handoff = try await handle.research.issueAgentHandoff(
                runID: preparation.runID
            )
            let credential = try await handle.research.pairAgent(
                run: handoff.run,
                pairingCode: handoff.pairingCode
            )
            _ = try await handle.research.authenticatedAgentContext(
                credential: credential,
                run: handoff.run
            )

            let marker = "Self-write reload marker for \(actionID.rawValue)."
            let heading = actionID == .synthesize ? "# Agency" : "# Draft Argument"
            let write = try await handle.research.writeAgentDocument(
                credential: credential,
                run: handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    role: role,
                    relativePath: note.relativePath,
                    content: "\(heading)\n\n\(marker)\n"
                )
            )
            #expect(write.state == .committed)

            let reloaded = try await handle.research.authenticatedAgentContext(
                credential: credential,
                run: handoff.run
            )
            let rereadAction = try #require(reloaded.nextActions.first {
                $0.kind == .query
                    && $0.label == "Read the exact current Target revision"
            })
            let template = try #require(rereadAction.inputTemplate)
            let request = try JSONDecoder().decode(
                ResearchContextRequest.self,
                from: Data(template.utf8)
            )
            let response = try await handle.research.queryAgentResearchContext(
                credential: credential,
                run: handoff.run,
                request: request
            )
            #expect(response.availability == .current)
            #expect(response.items.first?.exactSource?.content.contains(marker)
                == true)

            let sourceURL = fixture.rootURL
                .appendingPathComponent(
                    actionID == .synthesize ? "Topics" : "Works",
                    isDirectory: true
                )
                .appendingPathComponent(note.relativePath)
            try Data("\(heading)\n\nGenuine external edit.\n".utf8).write(
                to: sourceURL,
                options: .atomic
            )
            do {
                _ = try await handle.research.authenticatedAgentContext(
                    credential: credential,
                    run: handoff.run
                )
                Issue.record("A genuine external edit must stale the Run.")
            } catch let error as ResearchAgentConnectionError {
                #expect(error == .runStale(.targetChanged))
            }
            await runtime.shutdown()
        }
    }

    @Test("Tracked activity survives Session rotation without a wall-clock lease")
    func trackedActivitySurvivesSessionRotation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let tracked = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .topic,
                    relativePath: "Agency.md",
                    operations: [.modifyMarkdown]
                )],
                academicReason: "Continue one relevant topic across a rotated Session."
            )
        )
        #expect(tracked.state == .recorded)

        let replacement = try await handle.research.issueAgentHandoff(
            runID: connection.preparation.runID
        )
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            _ = try await handle.research.authenticatedAgentContext(
                credential: connection.credential,
                run: connection.handoff.run
            )
        }
        let replacementCredential = try await handle.research.pairAgent(
            run: replacement.run,
            pairingCode: replacement.pairingCode
        )
        let reloaded = try await handle.research.authenticatedAgentContext(
            credential: replacementCredential,
            run: replacement.run
        )
        #expect(reloaded.boundedWriteSet.contains {
            $0.role == .topic && $0.relativePath == "Agency.md"
        })
        let write = try await handle.research.writeAgentDocument(
            credential: replacementCredential,
            run: replacement.run,
            intent: try ResearchDocumentWriteIntent(
                role: .topic,
                relativePath: "Agency.md",
                content: "# Agency\n\nContinued after Session rotation.\n"
            )
        )
        #expect(write.state == .committed)
        #expect(try await handle.documents.load(fixture.topicID).rawContent
            .contains("Continued after Session rotation."))
        await runtime.shutdown()
    }

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

    @Test("Zotero binding authority is independent, revision checked, and idempotent")
    func zoteroBindingWritesUseIndependentAuthority() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let sourceBefore = try await handle.documents.load(fixture.analysisID)

        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: "Analysis.md",
                    operations: [.setZoteroBinding, .clearZoteroBinding]
                )],
                academicReason: "Bind the exact Zotero source used by this Analysis."
            )
        )
        #expect(extensionResult.state == .recorded)
        let target = try #require(extensionResult.entries.first)
        #expect(target.operations.contains(.modifyMarkdown))
        #expect(target.operations.contains(.setZoteroBinding))
        #expect(target.operations.contains(.clearZoteroBinding))

        let setIntent = try ResearchZoteroBindingWriteIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000701")!,
            role: .analysis,
            relativePath: "Analysis.md",
            operation: .setZoteroBinding,
            library: .group(42),
            itemKey: "item_42"
        )
        let set = try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: setIntent
        )
        #expect(set.state == .committed)
        #expect(try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: setIntent
        ) == set)

        let execution = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let entry = try #require(execution.boundedWriteSet.entries.first)
        let bound = try #require(
            try await handle.services.controlStore.zoteroBindings()
                .binding(for: entry.noteID)
        )
        #expect(bound.library == .group(42))
        #expect(bound.itemKey == "ITEM_42")
        #expect(
            try await handle.documents.load(fixture.analysisID).sourceBytes
                == sourceBefore.sourceBytes
        )
        #expect(execution.zoteroBindingWriteRecords.count == 1)
        #expect(execution.documentWriteRecords.isEmpty)

        let externalSnapshot = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.setZoteroBinding(
            AnalysisZoteroBinding(
                noteID: entry.noteID,
                library: .user,
                itemKey: "EXTERNAL1"
            ),
            expectedRevision: externalSnapshot.revision
        )
        let conflicted = try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchZoteroBindingWriteIntent(
                requestID: UUID(),
                role: .analysis,
                relativePath: "Analysis.md",
                operation: .clearZoteroBinding
            )
        )
        #expect(conflicted.state == .conflict)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: entry.noteID)?.itemKey == "EXTERNAL1")

        let cleared = try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchZoteroBindingWriteIntent(
                requestID: UUID(),
                role: .analysis,
                relativePath: "Analysis.md",
                operation: .clearZoteroBinding
            )
        )
        #expect(cleared.state == .committed)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: entry.noteID) == nil)
        #expect(
            try await handle.documents.load(fixture.analysisID).sourceBytes
                == sourceBefore.sourceBytes
        )
        do {
            _ = try await runtime.endResearchAgentRun(
                credential: connection.credential,
                run: connection.handoff.run
            )
            Issue.record("A committed portable binding write must require Result finalization.")
        } catch let error as ResearchActionRunContractError {
            guard case .committedWritesRequireCompletion(let runID) = error else {
                Issue.record("Unexpected end error: \(error)")
                await runtime.shutdown()
                return
            }
            #expect(runID == connection.preparation.runID)
        }
        await runtime.shutdown()
    }

    @Test("Exact Zotero binding retry reconciles an unknown outcome without another write")
    func zoteroBindingRecoveryRetryConverges() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: "Analysis.md",
                    operations: [.setZoteroBinding]
                )],
                academicReason: "Retain one exact portable source relationship."
            )
        )
        let execution = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let entry = try #require(execution.boundedWriteSet.entries.first)
        let expectedRevision = try #require(entry.zoteroBindingsRevision)
        let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000702")!
        let intent = try ResearchZoteroBindingWriteIntent(
            requestID: requestID,
            role: .analysis,
            relativePath: "Analysis.md",
            operation: .setZoteroBinding,
            library: .group(42),
            itemKey: "intended42"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestFingerprint = DocumentFingerprint(data: try encoder.encode(intent))
        let operationDigest = DocumentFingerprint(content: [
            connection.preparation.runID.uuidString.lowercased(),
            "zotero-binding-write",
            requestID.uuidString.lowercased(),
        ].joined(separator: ":")).sha256
        let operationID = try #require(UUID(uuidString: [
            String(operationDigest.prefix(8)),
            String(operationDigest.dropFirst(8).prefix(4)),
            String(operationDigest.dropFirst(12).prefix(4)),
            String(operationDigest.dropFirst(16).prefix(4)),
            String(operationDigest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")))
        let intended = try AnalysisZoteroBinding(
            noteID: entry.noteID,
            library: .group(42),
            itemKey: "intended42"
        )
        _ = try await handle.services.localResearchExecutionStore
            .beginZoteroBindingWrite(try ResearchZoteroBindingWriteRecord(
                id: operationID,
                runID: connection.preparation.runID,
                target: entry.handle,
                operation: .setZoteroBinding,
                requestFingerprint: requestFingerprint,
                expectedRevision: expectedRevision,
                intendedBinding: intended,
                state: .writing,
                startedAt: Date()
            ))

        _ = try await handle.services.controlStore.setZoteroBinding(
            AnalysisZoteroBinding(
                noteID: entry.noteID,
                library: .user,
                itemKey: "external1"
            ),
            expectedRevision: expectedRevision
        )
        let unresolved = try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(unresolved.operationID == operationID)
        #expect(unresolved.state == .recoveryRequired)

        let current = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.setZoteroBinding(
            intended,
            expectedRevision: current.revision
        )
        let recovered = try await handle.research.writeAgentZoteroBinding(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(recovered.operationID == operationID)
        #expect(recovered.state == .committed)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: entry.noteID) == intended)

        let run = try await handle.research.actionRunDetails(
            id: connection.preparation.runID
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: try makeTestAgentResultSubmission(
                for: run,
                literatureRecommendations: []
            )
        )
        #expect(receipt.recordFormed)
        let record = try await handle.services.portableResearchRecordStore.record(
            id: connection.preparation.runID
        )
        #expect(record.activityOutcomes.first { $0.id == operationID }?.state
            == .committed)
        await runtime.shutdown()
    }

    @Test("Exact Metadata retry reconciles an unknown outcome without another write")
    func metadataRecoveryRetryConverges() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: "Analysis.md",
                    operations: [.modifyMetadata],
                    metadataKeys: ["language"]
                )],
                academicReason: "Record one exact language declaration."
            )
        )
        let execution = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let entry = try #require(execution.boundedWriteSet.entries.first)
        let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000703")!
        let intent = try ResearchDocumentWriteIntent(
            requestID: requestID,
            role: .analysis,
            relativePath: "Analysis.md",
            operation: .modifyMetadata,
            metadata: [try CanonicalPropertyInput(
                key: "language",
                value: .string("en")
            )]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestFingerprint = DocumentFingerprint(data: try encoder.encode(intent))
        let operationDigest = DocumentFingerprint(content: [
            connection.preparation.runID.uuidString.lowercased(),
            "write",
            requestID.uuidString.lowercased(),
        ].joined(separator: ":")).sha256
        let operationID = try #require(UUID(uuidString: [
            String(operationDigest.prefix(8)),
            String(operationDigest.dropFirst(8).prefix(4)),
            String(operationDigest.dropFirst(12).prefix(4)),
            String(operationDigest.dropFirst(16).prefix(4)),
            String(operationDigest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")))
        let initialMetadata = try await handle.services.controlStore.noteMetadata(
            noteID: entry.noteID
        )
        var intendedFields = initialMetadata?.record.fields ?? [:]
        intendedFields["language"] = .string("en")
        let intendedRevision = DocumentFingerprint(
            data: try NoteMetadataRecord(
                noteID: entry.noteID,
                fields: intendedFields
            ).encodedPortableData()
        )
        _ = try await handle.services.localResearchExecutionStore.beginDocumentWrite(
            try ResearchDocumentWriteRecord(
                id: operationID,
                runID: connection.preparation.runID,
                target: entry.handle,
                actor: .agent,
                operation: .modifyMetadata,
                requestFingerprint: requestFingerprint,
                expectedRevision: entry.metadataRevision,
                intendedRevision: intendedRevision,
                state: .writing,
                startedAt: Date()
            )
        )

        var externalFields = initialMetadata?.record.fields ?? [:]
        externalFields["language"] = .string("fr")
        _ = try await handle.services.controlStore.saveNoteMetadata(
            noteID: entry.noteID,
            fields: externalFields,
            expectedRevision: entry.metadataRevision
        )
        let unresolved = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(unresolved.operationID == operationID)
        #expect(unresolved.state == .recoveryRequired)

        let current = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: entry.noteID)
        )
        _ = try await handle.services.controlStore.saveNoteMetadata(
            noteID: entry.noteID,
            fields: intendedFields,
            expectedRevision: current.revision
        )
        let recovered = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(recovered.operationID == operationID)
        #expect(recovered.state == .committed)
        #expect(try await handle.services.controlStore.noteMetadata(
            noteID: entry.noteID
        )?.record.fields == intendedFields)

        let run = try await handle.research.actionRunDetails(
            id: connection.preparation.runID
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: try makeTestAgentResultSubmission(
                for: run,
                literatureRecommendations: []
            )
        )
        #expect(receipt.recordFormed)
        let record = try await handle.services.portableResearchRecordStore.record(
            id: connection.preparation.runID
        )
        #expect(record.activityOutcomes.first { $0.id == operationID }?.state
            == .committed)
        await runtime.shutdown()
    }

    @Test("Authenticated Analysis creation freezes a safe field plan and records one created mutation")
    func authenticatedAnalysisCreationIsIdempotentAndPortable() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let savedSettings = try await handle.research.settings()
        var settings = savedSettings.settings
        settings.analysisAgentCreation.preferredFieldsBySourceType[.journalArticle] = [
            "authors",
        ]
        _ = try await handle.research.saveSettings(
            settings,
            expectedRevision: savedSettings.revision
        )

        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: "Created/Journal Analysis.md",
                    operations: [.createNote]
                )],
                academicReason: "Create the Analysis required by this source-focused Action."
            )
        )
        #expect(extensionResult.state == .recorded)
        let creationView = try #require(extensionResult.entries.first(where: {
            $0.relativePath == "Created/Journal Analysis.md"
        }))
        #expect(creationView.expectsAbsence)
        let journalPlan = try #require(creationView.analysisCreationPlans.first {
            $0.sourceType == .journalArticle
        })
        #expect(journalPlan.fields.first { $0.key == "authors" }?.isPreferred == true)
        #expect(journalPlan.fields.allSatisfy { $0.key != "keywords" })
        let exposed = String(
            decoding: try JSONEncoder().encode(creationView),
            as: UTF8.self
        )
        for forbidden in [
            "settings_revision", "reserved", "note_id",
        ] {
            #expect(!exposed.contains(forbidden))
        }

        let metadata = try AnalysisCreationMetadata(
            sourceType: .journalArticle,
            fields: [
                try CanonicalPropertyInput(
                    key: "title",
                    value: .string("Created Analysis")
                ),
                try CanonicalPropertyInput(
                    key: "authors",
                    value: .array([.object([
                        "family": .string("Scanlon"),
                        "given": .string("T. M."),
                    ])])
                ),
            ]
        )
        let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
        let intent = try ResearchDocumentWriteIntent(
            requestID: requestID,
            role: .analysis,
            relativePath: "Created/Journal Analysis.md",
            operation: .createNote,
            content: "# Analysis body\n",
            authoredYAML: try AuthoredNoteYAML(
                summary: "A portable analysis note",
                keywords: ["reasons"]
            ),
            analysisMetadata: metadata
        )
        // Keep the catalog projection stale throughout create -> same-Note
        // augmentation -> write. Authoritative control/source state must own
        // every consequential decision in this sequence.
        let invalidDerivedSource = fixture.rootURL
            .appendingPathComponent("Topics", isDirectory: true)
            .appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(
            to: invalidDerivedSource,
            options: .atomic
        )
        let created = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(created.state == .committed)
        #expect(try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        ) == created)

        let execution = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        let createdEntry = try #require(execution.boundedWriteSet.entries.first {
            $0.note.relativePath == "Created/Journal Analysis.md"
        })
        #expect(createdEntry.state == .consumed)
        #expect(createdEntry.wasCreated)
        let document = try await handle.documents.load(createdEntry.note)
        #expect(document.body == "# Analysis body\n")
        #expect(document.parsedFrontmatter["type"] == nil)
        #expect(document.parsedFrontmatter["summary"]
            == .string("A portable analysis note"))
        #expect(document.parsedFrontmatter["keywords"]
            == .array([.string("reasons")]))
        let createdMetadata = try #require(
            try await handle.services.controlStore.noteMetadata(
                noteID: createdEntry.noteID
            )
        )
        #expect(createdMetadata.record.fields["type"] == .string("journal_article"))
        #expect(createdMetadata.record.fields["title"] == .string("Created Analysis"))
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: createdEntry.note.vaultID,
            relativePath: createdEntry.note.relativePath
        )?.id == createdEntry.noteID)
        let firstCreatedRevision = document.fingerprint

        await #expect(throws: ResearchBoundedWriteSetError.staleAuthorization) {
            try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    requestID: UUID(),
                    role: .analysis,
                    relativePath: createdEntry.note.relativePath,
                    operation: .createNote,
                    content: "# Duplicate\n",
                    analysisMetadata: metadata
                )
            )
        }

        let metadataExtension = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [try ResearchWriteSetTargetSelector(
                    role: .analysis,
                    relativePath: createdEntry.note.relativePath,
                    operations: [.modifyMetadata],
                    metadataKeys: ["title"]
                )],
                academicReason: "Add one exact field under fresh existing-Note authority."
            )
        )
        #expect(metadataExtension.state == .recorded)
        let augmented = try #require(metadataExtension.entries.first {
            $0.relativePath == createdEntry.note.relativePath
        })
        #expect(!augmented.expectsAbsence)
        #expect(augmented.operations == [.modifyMetadata])
        #expect(augmented.metadataKeys == ["title"])
        let metadataWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .analysis,
                relativePath: createdEntry.note.relativePath,
                operation: .modifyMetadata,
                metadata: [try CanonicalPropertyInput(
                    key: "title",
                    value: .string("Revised Created Analysis")
                )]
            )
        )
        #expect(metadataWrite.state == .committed)
        let finalDocument = try await handle.documents.load(createdEntry.note)
        #expect(finalDocument.fingerprint == firstCreatedRevision)
        #expect(finalDocument.parsedFrontmatter["title"] == nil)
        let finalMetadata = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: createdEntry.noteID)
        )
        #expect(finalMetadata.record.fields["title"]
            == .string("Revised Created Analysis"))
        let cancelError = await #expect(
            throws: ResearchActionRunContractError.self
        ) {
            try await handle.research.cancelAction(
                runID: connection.preparation.runID
            )
        }
        if case .committedWritesRequireCompletion(let runID) = cancelError {
            #expect(runID == connection.preparation.runID)
        } else {
            Issue.record("Committed creation returned the wrong End refusal.")
        }
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        ).completion == nil)

        let run = try await handle.research.actionRunDetails(
            id: connection.preparation.runID
        )
        let submission = try makeTestAgentResultSubmission(
            for: run,
            literatureRecommendations: []
        )
        let firstReceipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: submission
        )
        let sourceConfirmed = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        #expect(sourceConfirmed.writeReport?.observedFingerprints[
            createdEntry.noteID
        ] == finalDocument.fingerprint)
        try FileManager.default.removeItem(at: invalidDerivedSource)
        _ = try await handle.refresh()
        #expect(firstReceipt.recordFormed)
        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: createdEntry.noteID)
                .first(where: { $0.id == connection.preparation.runID })
        )
        let change = try #require(record.confirmedChanges.first {
            $0.noteID == createdEntry.noteID
        })
        #expect(change.kind == .created)
        #expect(change.startingRevision == nil)
        #expect(change.endingRevision == finalDocument.fingerprint)
        let participant = try #require(record.participatingNotes.first {
            $0.noteID == createdEntry.noteID
        })
        #expect(participant.startingRevision == firstCreatedRevision)
        #expect(participant.endingRevision == finalDocument.fingerprint)
        await #expect(
            throws: ResearchRecordChangeRecoveryOperationError
                .createdNoteHasNoPreimage(createdEntry.noteID)
        ) {
            _ = try await handle.research.researchRecordComparison(
                recordID: record.id,
                noteID: createdEntry.noteID
            )
        }
        #expect(try await handle.research.recoveryRecords().isEmpty)
        await runtime.shutdown()
    }

    @Test("Metadata authority changes only approved managed keys and preserves exact source")
    func metadataWritePreservesSourceAndRejectsExtraKeys() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let before = try await handle.documents.load(fixture.topicID)
        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [
                    try ResearchWriteSetTargetSelector(
                        role: .analysis,
                        relativePath: "Analysis.md",
                        operations: [.modifyMetadata],
                        metadataKeys: ["language"]
                    ),
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: "Agency.md",
                        operations: [.modifyMetadata],
                        metadataKeys: ["aliases"]
                    ),
                ],
                academicReason: "Update two researcher-approved Metadata fields."
            )
        )
        #expect(extensionResult.state == .recorded)
        let initialTarget = try #require(extensionResult.entries.first {
            $0.relativePath == "Analysis.md"
        })
        #expect(initialTarget.operations == [
            .modifyMarkdown, .modifyMetadata, .modifySource,
        ])
        #expect(initialTarget.metadataKeys == ["language"])
        #expect(extensionResult.entries.first {
            $0.relativePath == "Agency.md"
        }?.metadataKeys == ["aliases"])
        let metadataPlans = try #require(extensionResult.entries.first {
            $0.relativePath == "Agency.md"
        }?.metadataWritePlans)
        #expect(metadataPlans.first { $0.key == "aliases" }?.valueKind == .textList)

        let initialBefore = try await handle.documents.load(fixture.analysisID)
        let initialMetadataWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .analysis,
                relativePath: "Analysis.md",
                operation: .modifyMetadata,
                metadata: [try CanonicalPropertyInput(
                    key: "language",
                    value: .string("en")
                )]
            )
        )
        #expect(initialMetadataWrite.state == .committed)
        let initialAfter = try await handle.documents.load(fixture.analysisID)
        #expect(initialAfter.rawContent == initialBefore.rawContent)

        let topicIdentity = try #require(try await handle.services.controlStore.identityRecord(
            vaultID: fixture.topicID.vaultID,
            relativePath: fixture.topicID.relativePath
        ))
        let topicMetadataBeforeExternalChange = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: topicIdentity.id)
        )
        let externalMetadata = try await handle.services.controlStore.saveNoteMetadata(
            noteID: topicIdentity.id,
            fields: ["aliases": .array([.string("External change")])],
            expectedRevision: topicMetadataBeforeExternalChange.revision
        )
        let writeIntent = try ResearchDocumentWriteIntent(
            requestID: UUID(),
            role: .topic,
            relativePath: "Agency.md",
            operation: .modifyMetadata,
            metadata: [
                try CanonicalPropertyInput(
                    key: "aliases",
                    value: .array([
                        .string("Freedom"),
                        .string("Practical agency"),
                    ])
                ),
            ]
        )
        let conflict = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: writeIntent
        )
        #expect(conflict.state == .conflict)
        #expect(try await handle.services.controlStore.noteMetadata(
            noteID: topicIdentity.id
        )?.revision == externalMetadata.revision)
        let refreshed = try await handle.research.resolveAgentWriteConflict(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteConflictResolutionIntent(
                requestID: UUID(),
                role: .topic,
                relativePath: "Agency.md",
                action: .refreshAuthority
            )
        )
        #expect(refreshed.state == .readyToRetry)
        let write = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: writeIntent
        )
        #expect(write.state == .committed)
        let after = try await handle.documents.load(fixture.topicID)
        #expect(after.rawContent == before.rawContent)
        let topicMetadata = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: topicIdentity.id)
        )
        #expect(topicMetadata.record.fields["aliases"] == .array([
            .string("Freedom"), .string("Practical agency"),
        ]))

        await #expect(throws: ResearchBoundedWriteSetError.operationNotAuthorized) {
            try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    requestID: UUID(),
                    role: .topic,
                    relativePath: "Agency.md",
                    operation: .modifyMetadata,
                    metadata: [try CanonicalPropertyInput(
                        key: "summary",
                        value: .array([.string("unauthorized")])
                    )]
                )
            )
        }
        await runtime.shutdown()
    }

    @Test("Agent creation recovery reconciles owned state and preserves a foreign restart identity")
    func creationRecoverySurvivesRestart() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let cases: [(path: String, source: Bool, identity: Bool, linked: Bool)] = [
            ("Recovery/Source Only.md", true, false, false),
            ("Recovery/Identity Only.md", false, true, true),
            ("Recovery/Both Intended.md", true, true, true),
            ("Recovery/Both Absent.md", false, false, true),
        ]
        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: try cases.map { item in
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: item.path,
                        operations: [.createNote]
                    )
                },
                academicReason: "Exercise every durable managed-creation recovery state."
            )
        )
        #expect(extensionResult.state == .recorded)

        var recoveryIDs: [String: UUID] = [:]
        for item in cases {
            let execution = try await handle.services.localResearchExecutionStore
                .record(id: connection.preparation.runID)
            let entry = try #require(execution.boundedWriteSet.entries.first {
                $0.note.relativePath == item.path
            })
            let source = "# \(URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent)\n"
            let revision = DocumentFingerprint(content: source)
            let operationID = UUID()
            let write = try ResearchDocumentWriteRecord(
                id: operationID,
                runID: connection.preparation.runID,
                target: entry.handle,
                actor: .agent,
                operation: .createNote,
                requestFingerprint: DocumentFingerprint(content: item.path),
                expectedRevision: nil,
                intendedRevision: revision,
                state: .writing,
                startedAt: Date()
            )
            _ = try await handle.services.localResearchExecutionStore
                .beginDocumentWrite(write)
            if item.source {
                let repositories = await handle.services.repositories
                let repository = try #require(
                    repositories[entry.note.vaultID]
                )
                _ = try await repository.create(
                    relativePath: item.path,
                    content: source
                )
            }
            if item.identity {
                _ = try await handle.services.controlStore.identity(
                    forVaultID: entry.note.vaultID,
                    relativePath: item.path,
                    fingerprint: revision,
                    preferredID: entry.noteID
                )
            }
            let recoveryID = UUID()
            let recovery = TriptychMutationRecoveryRecord(
                id: recoveryID,
                triptychID: fixture.assignment.id,
                operation: .noteCreation,
                failure: "Injected mixed creation state",
                files: [TriptychMutationRecoveryFile(
                    vaultID: entry.note.vaultID,
                    path: item.path,
                    role: .createdNote,
                    beforeRevision: nil,
                    intendedRevision: revision,
                    observedRevision: item.source ? revision : nil,
                    state: item.source ? .intendedBytesRemain : .missing,
                    detail: "Deterministic restart fixture"
                )],
                researchWrite: ResearchWriteRecoveryReference(
                    runID: connection.preparation.runID,
                    operationID: operationID,
                    target: entry.handle
                )
            )
            try await handle.services.transactionRecoveryStore.record(recovery)
            if item.linked {
                _ = try await handle.services.localResearchExecutionStore
                    .finishDocumentWrite(
                        runID: connection.preparation.runID,
                        operationID: operationID,
                        state: .recoveryRequired,
                        observedRevision: item.source ? revision : nil,
                        warning: recovery.failure,
                        recoveryRecordID: recoveryID,
                        finishedAt: Date()
                    )
            }
            recoveryIDs[item.path] = recoveryID
        }
        await runtime.shutdown()

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(
            id: fixture.assignment.id
        )
        let reopenedExecution = try await reopened.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)

        // External source changes after the durable observation cannot be
        // settled from stale evidence. Both directions retain the recovery
        // record, then converge on a fresh retry.
        for (path, makePresent) in [
            ("Recovery/Identity Only.md", true),
            ("Recovery/Source Only.md", false),
        ] {
            let entry = try #require(reopenedExecution.boundedWriteSet.entries.first {
                $0.note.relativePath == path
            })
            let write = try #require(reopenedExecution.documentWriteRecords.first {
                $0.target == entry.handle
            })
            let gate = ResearchCreationTestGate()
            await reopened.setResearchCreationRecoveryObservationBarrierForTesting {
                await gate.wait()
            }
            let recoveryID = try #require(recoveryIDs[path])
            let resolution = Task {
                try await reopened.research.resolveRecoveryRecord(recoveryID)
            }
            #expect(await gate.waitUntilArrived())
            let repositories = await reopened.services.repositories
            let repository = try #require(repositories[entry.note.vaultID])
            if makePresent {
                _ = try await repository.create(
                    relativePath: path,
                    content: "# Identity Only\n"
                )
            } else {
                try await repository.removeCreatedFileForRollback(
                    relativePath: path,
                    createdRevision: write.intendedRevision
                )
            }
            await gate.release()
            await #expect(throws: ResearchBoundedWriteSetError.recoveryRequired) {
                try await resolution.value
            }
            await reopened.setResearchCreationRecoveryObservationBarrierForTesting(nil)
            #expect(try await reopened.research.recoveryRecords().contains {
                $0.id == recoveryIDs[path]
            })
            let identity = try await reopened.services.controlStore.identityRecord(
                vaultID: entry.note.vaultID,
                relativePath: path
            )
            if makePresent {
                #expect(identity?.id == entry.noteID)
                #expect(identity?.fingerprint == write.intendedRevision)
            }
        }

        // A crash after Local Execution settles but before the recovery record
        // is removed must make the next click cleanup-only. A later external
        // identity and binding are not reinterpreted or replaced.
        let terminalPath = "Recovery/Both Intended.md"
        let terminalEntry = try #require(
            reopenedExecution.boundedWriteSet.entries.first {
                $0.note.relativePath == terminalPath
            }
        )
        let terminalWrite = try #require(
            reopenedExecution.documentWriteRecords.first {
                $0.target == terminalEntry.handle
            }
        )
        _ = try await reopened.services.localResearchExecutionStore
            .reconcileDocumentWriteRecovery(
                runID: connection.preparation.runID,
                operationID: terminalWrite.id,
                recoveryRecordID: try #require(recoveryIDs[terminalPath]),
                observedRevision: terminalWrite.intendedRevision,
                reconciledAt: Date()
            )
        _ = try await reopened.services.controlStore.purgeIdentity(
            id: terminalEntry.noteID,
            vaultID: terminalEntry.note.vaultID,
            relativePath: terminalPath
        )
        let externalTerminalIdentity = try #require(
            try await reopened.services.controlStore.identity(
                forVaultID: terminalEntry.note.vaultID,
                relativePath: terminalPath,
                fingerprint: terminalWrite.intendedRevision
            )
        )
        let terminalBindings = try await reopened.services.controlStore.zoteroBindings()
        let externalTerminalBinding = try AnalysisZoteroBinding(
            noteID: externalTerminalIdentity.id,
            library: .group(77),
            itemKey: "TERMINAL"
        )
        _ = try await reopened.services.controlStore.setZoteroBinding(
            externalTerminalBinding,
            expectedRevision: terminalBindings.revision
        )

        let sourceOnlyPath = "Recovery/Source Only.md"
        let sourceOnlyEntry = try #require(
            reopenedExecution.boundedWriteSet.entries.first {
                $0.note.relativePath == sourceOnlyPath
            }
        )
        let foreignSourceOnlyIdentity = try #require(
            try await reopened.services.controlStore.identityRecord(
                vaultID: sourceOnlyEntry.note.vaultID,
                relativePath: sourceOnlyPath
            )
        )
        #expect(foreignSourceOnlyIdentity.id != sourceOnlyEntry.noteID)
        await #expect(throws: ResearchBoundedWriteSetError.recoveryRequired) {
            try await reopened.research.resolveRecoveryRecord(
                try #require(recoveryIDs[sourceOnlyPath])
            )
        }

        for item in cases where item.path != sourceOnlyPath {
            try await reopened.research.resolveRecoveryRecord(
                try #require(recoveryIDs[item.path])
            )
        }
        let reconciled = try await reopened.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        for item in cases {
            let entry = try #require(reconciled.boundedWriteSet.entries.first {
                $0.note.relativePath == item.path
            })
            let write = try #require(reconciled.documentWriteRecords.first {
                $0.target == entry.handle
            })
            let expectedState: ResearchDocumentWriteState = switch item.path {
            case "Recovery/Identity Only.md", "Recovery/Both Intended.md":
                .committed
            case "Recovery/Both Absent.md":
                .abandoned
            case let path where path == sourceOnlyPath:
                .writing
            default:
                fatalError("Unexpected recovery fixture")
            }
            #expect(write.state == expectedState)
            let identity = try await reopened.services.controlStore.identityRecord(
                vaultID: entry.note.vaultID,
                relativePath: item.path
            )
            if item.path == terminalPath {
                #expect(identity == externalTerminalIdentity)
                #expect(try await reopened.services.controlStore.zoteroBindings()
                    .binding(for: externalTerminalIdentity.id)
                    == externalTerminalBinding)
            } else if item.path == sourceOnlyPath {
                #expect(identity == foreignSourceOnlyIdentity)
            } else {
                #expect((identity?.id == entry.noteID)
                    == (expectedState == .committed))
            }
        }
        #expect(try await reopened.research.recoveryRecords().map(\.id)
            == [try #require(recoveryIDs[sourceOnlyPath])])
        await reopenedRuntime.shutdown()
    }

    @Test("Agent create authorization requires both source and portable identity absence")
    func creationRefusesOrphanedPortableIdentity() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let path = "Created/Occupied Identity.md"
        let oldIdentity = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: fixture.topicID.vaultID,
                relativePath: path,
                fingerprint: DocumentFingerprint(content: "# Old\n")
            )
        )
        let bindings = try await handle.services.controlStore.zoteroBindings()
        let oldBinding = try AnalysisZoteroBinding(
            noteID: oldIdentity.id,
            library: .user,
            itemKey: "OLDKEY01"
        )
        _ = try await handle.services.controlStore.setZoteroBinding(
            oldBinding,
            expectedRevision: bindings.revision
        )

        await #expect(throws: ResearchBoundedWriteSetError.targetUnavailable) {
            _ = try await handle.research.extendAgentWriteSet(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: ResearchWriteSetExtensionIntent(
                    targets: [ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: path,
                        operations: [.createNote]
                    )],
                    academicReason: "Attempt an exact new Note identity."
                )
            )
        }
        let topicVault = try #require(
            fixture.assignment.vaults.values.first { $0.id == fixture.topicID.vaultID }
        )
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: topicVault.canonicalPath)
                .appendingPathComponent(path).path
        ))
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: fixture.topicID.vaultID,
            relativePath: path
        ) == oldIdentity)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: oldIdentity.id) == oldBinding)
        await runtime.shutdown()
    }

    @Test("Exact retry settles a created source and identity after Local Execution stopped at writing")
    func creationRetrySettlesPostCommitWritingSeam() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let path = "Created/Post Commit Retry.md"
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: ResearchWriteSetExtensionIntent(
                targets: [ResearchWriteSetTargetSelector(
                    role: .topic,
                    relativePath: path,
                    operations: [.createNote]
                )],
                academicReason: "Create one retry-stable Note."
            )
        )
        let execution = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        let entry = try #require(execution.boundedWriteSet.entries.first {
            $0.note.relativePath == path
        })
        let intent = try ResearchDocumentWriteIntent(
            requestID: UUID(),
            role: .topic,
            relativePath: path,
            operation: .createNote,
            content: "# Durable creation\n"
        )
        let source = try await handle.managedCreationSource(
            request: ManagedNoteCreationRequest(
                vaultID: entry.note.vaultID,
                destination: .exact(relativePath: path),
                body: intent.content,
                authority: .authenticatedAgent(reservedIdentity: entry.noteID)
            ),
            slot: .topicKnowledge
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestFingerprint = DocumentFingerprint(
            data: try encoder.encode(intent)
        )
        let operationDigest = DocumentFingerprint(content: [
            connection.preparation.runID.uuidString.lowercased(),
            "write",
            intent.requestID.uuidString.lowercased(),
        ].joined(separator: ":")).sha256
        let operationID = try #require(UUID(uuidString: [
            String(operationDigest.prefix(8)),
            String(operationDigest.dropFirst(8).prefix(4)),
            String(operationDigest.dropFirst(12).prefix(4)),
            String(operationDigest.dropFirst(16).prefix(4)),
            String(operationDigest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")))
        _ = try await handle.services.localResearchExecutionStore.beginDocumentWrite(
            ResearchDocumentWriteRecord(
                id: operationID,
                runID: connection.preparation.runID,
                target: entry.handle,
                actor: .agent,
                operation: .createNote,
                requestFingerprint: requestFingerprint,
                expectedRevision: nil,
                intendedRevision: DocumentFingerprint(content: source),
                state: .writing,
                startedAt: Date()
            )
        )
        _ = try await handle.documents.createManagedNote(
            ManagedNoteCreationRequest(
                vaultID: entry.note.vaultID,
                destination: .exact(relativePath: path),
                body: intent.content,
                authority: .authenticatedAgent(reservedIdentity: entry.noteID)
            )
        )

        let retried = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(retried.state == .committed)
        let settled = try #require(
            try await handle.services.localResearchExecutionStore.record(
                id: connection.preparation.runID
            ).documentWriteRecords.first { $0.id == operationID }
        )
        #expect(settled.state == .committed)
        #expect(settled.observedRevision == DocumentFingerprint(content: source))
        await runtime.shutdown()
    }

    @Test("Identity claim race rolls source back without disturbing the other identity")
    func creationIdentityRaceIsProvenAbandoned() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let path = "Created/Identity Race.md"
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: ResearchWriteSetExtensionIntent(
                targets: [ResearchWriteSetTargetSelector(
                    role: .topic,
                    relativePath: path,
                    operations: [.createNote]
                )],
                academicReason: "Exercise the final identity claim race."
            )
        )
        let gate = ResearchCreationTestGate()
        await handle.setManagedCreationPostSourceBarrierForTesting {
            await gate.wait()
        }
        let intent = try ResearchDocumentWriteIntent(
            role: .topic,
            relativePath: path,
            operation: .createNote,
            content: "# Raced source\n"
        )
        let creation = Task {
            try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: intent
            )
        }
        #expect(await gate.waitUntilArrived())
        let entry = try #require(
            try await handle.services.localResearchExecutionStore.record(
                id: connection.preparation.runID
            ).boundedWriteSet.entries.first { $0.note.relativePath == path }
        )
        let currentSource = try Data(
            contentsOf: URL(fileURLWithPath: try #require(
                fixture.assignment.vaults.values.first {
                    $0.id == entry.note.vaultID
                }
            ).canonicalPath).appendingPathComponent(path)
        )
        let otherIdentity = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: entry.note.vaultID,
                relativePath: path,
                fingerprint: DocumentFingerprint(data: currentSource)
            )
        )
        #expect(otherIdentity.id != entry.noteID)
        let bindings = try await handle.services.controlStore.zoteroBindings()
        let otherBinding = try AnalysisZoteroBinding(
            noteID: otherIdentity.id,
            library: .user,
            itemKey: "RACEKEY1"
        )
        _ = try await handle.services.controlStore.setZoteroBinding(
            otherBinding,
            expectedRevision: bindings.revision
        )
        await gate.release()
        let result = try await creation.value
        await handle.setManagedCreationPostSourceBarrierForTesting(nil)
        #expect(result.state == .abandoned)
        #expect(result.recoveryRecordID == nil)
        let vault = try #require(
            fixture.assignment.vaults.values.first { $0.id == entry.note.vaultID }
        )
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: vault.canonicalPath)
                .appendingPathComponent(path).path
        ))
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: entry.note.vaultID,
            relativePath: path
        ) == otherIdentity)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: otherIdentity.id) == otherBinding)
        #expect(try await handle.research.recoveryRecords().isEmpty)
        await runtime.shutdown()
    }

    @Test("Managed creator requires final joint source and reserved identity readback")
    func creationFinalReadbackRetainsRecoveryForMissingOrChangedSource() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let cases = [
            (path: "Created/Missing Final Source.md", replacement: nil as String?),
            (path: "Created/Changed Final Source.md", replacement: "# External replacement\n"),
        ]
        _ = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: ResearchWriteSetExtensionIntent(
                targets: try cases.map {
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: $0.path,
                        operations: [.createNote]
                    )
                },
                academicReason: "Prove final source and identity jointly."
            )
        )
        for item in cases {
            let gate = ResearchCreationTestGate()
            await handle.setManagedCreationPostSourceBarrierForTesting {
                await gate.wait()
            }
            let creation = Task {
                try await handle.research.writeAgentDocument(
                    credential: connection.credential,
                    run: connection.handoff.run,
                    intent: ResearchDocumentWriteIntent(
                        role: .topic,
                        relativePath: item.path,
                        operation: .createNote,
                        content: "# Intended\n"
                    )
                )
            }
            #expect(await gate.waitUntilArrived())
            let execution = try await handle.services.localResearchExecutionStore
                .record(id: connection.preparation.runID)
            let entry = try #require(execution.boundedWriteSet.entries.first {
                $0.note.relativePath == item.path
            })
            let repositories = await handle.services.repositories
            let repository = try #require(repositories[entry.note.vaultID])
            let current = try await repository.load(relativePath: item.path)
            try await repository.removeCreatedFileForRollback(
                relativePath: item.path,
                createdRevision: current.fingerprint
            )
            if let replacement = item.replacement {
                _ = try await repository.create(
                    relativePath: item.path,
                    content: replacement
                )
            }
            await gate.release()
            let result = try await creation.value
            await handle.setManagedCreationPostSourceBarrierForTesting(nil)
            #expect(result.state == .recoveryRequired)
            #expect(result.recoveryRecordID != nil)
        }
        #expect(try await handle.research.recoveryRecords().count == cases.count)
        await runtime.shutdown()
    }

    @Test("Final Agent save preflight rejects a same-byte path reused by another identity")
    func existingWriteRevalidatesIdentityInsideSourceLease() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let execution = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        let entry = try #require(execution.boundedWriteSet.entries.first)
        let original = try await handle.documents.load(entry.note)
        let gate = ResearchCreationTestGate()
        await handle.setResearchDocumentSavePreflightBarrierForTesting {
            await gate.wait()
        }
        let writing = Task {
            try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: ResearchDocumentWriteIntent(
                    role: entry.role,
                    relativePath: entry.note.relativePath,
                    operation: .modifyMarkdown,
                    content: "# Unauthorized replacement write\n"
                )
            )
        }
        #expect(await gate.waitUntilArrived())
        _ = try await handle.services.controlStore.purgeIdentity(
            id: entry.noteID,
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        )
        let replacementIdentity = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: entry.note.vaultID,
                relativePath: entry.note.relativePath,
                fingerprint: original.fingerprint
            )
        )
        #expect(replacementIdentity.id != entry.noteID)
        await gate.release()
        let result = try await writing.value
        await handle.setResearchDocumentSavePreflightBarrierForTesting(nil)
        #expect(result.state == .abandoned)
        #expect(result.target.state == .stale)
        #expect(try await handle.documents.load(entry.note).rawContent
            == original.rawContent)
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        )?.id == replacementIdentity.id)
        await runtime.shutdown()
    }

    @Test("Metadata authority is independent of absent or malformed YAML")
    func metadataAuthorityIsIndependentOfFrontmatter() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let plainID = VaultQualifiedNoteID(
            vaultID: fixture.topicID.vaultID,
            relativePath: "Metadata Plain.md"
        )
        let malformedID = VaultQualifiedNoteID(
            vaultID: fixture.topicID.vaultID,
            relativePath: "Metadata Malformed.md"
        )
        let plain = try await handle.documents.importMarkdownSource(
            "# Plain\n",
            at: plainID
        ).committedValue
        _ = try await handle.documents.importMarkdownSource(
            "---\nsummary: incomplete\n",
            at: malformedID
        )
        _ = try await handle.refresh()
        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [plainID.relativePath, malformedID.relativePath].map { path in
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: path,
                        operations: [.modifyMetadata],
                        metadataKeys: ["aliases"]
                    )
                },
                academicReason: "Add managed aliases without changing authored source."
            )
        )
        #expect(extensionResult.state == .recorded)
        #expect(try await handle.documents.load(plainID).sourceBytes
            == plain.sourceBytes)
        #expect(try await handle.documents.load(malformedID).rawContent
            == "---\nsummary: incomplete\n")
        for (path, alias) in [
            (plainID.relativePath, "Plain alias"),
            (malformedID.relativePath, "Malformed source alias"),
        ] {
            #expect(try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    role: .topic,
                    relativePath: path,
                    operation: .modifyMetadata,
                    metadata: [try CanonicalPropertyInput(
                        key: "aliases",
                        value: .array([.string(alias)])
                    )]
                )
            ).state == .committed)
        }
        #expect(try await handle.documents.load(plainID).sourceBytes == plain.sourceBytes)
        #expect(try await handle.documents.load(malformedID).rawContent
            == "---\nsummary: incomplete\n")
        await runtime.shutdown()
    }

    @Test("Activity tracking adds two documents without another permission and writes them idempotently")
    func trackedMultiDocumentWrite() async throws {
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
            "expected_revision", "change_evidence_id", "note_id",
            "authorization_revision",
        ] {
            #expect(!contextJSON.contains(forbidden))
        }
        #expect(initialContext.brief.capabilities.trackActivity)

        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: true)
        )
        #expect(extensionResult.state == .recorded)
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
            content: topic.body + "\nAgent-bounded topic addition.\n"
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
                content: work.body + "\nAgent-bounded work addition.\n"
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
        for entry in stored.boundedWriteSet.entries where !entry.expectsAbsence {
            #expect(try await handle.services.agentChangeEvidenceStore.evidence(
                runID: connection.preparation.runID,
                noteID: entry.noteID
            ).noteID == entry.noteID)
        }
        #expect(try await handle.snapshot().research.activities.contains {
            $0.runID == connection.preparation.runID && $0.state == .running
        })

        await runtime.shutdown()
    }

    @Test("A stale activity registration settles and the same Run can retry and finalize")
    func staleActivityRegistrationConverges() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let gate = ResearchCreationTestGate()
        await handle.setResearchActivityPostInstallBarrierForTesting {
            await gate.wait()
        }

        let intent = try extensionIntent(includeWork: false)
        let tracking = Task {
            try await handle.research.extendAgentWriteSet(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: intent
            )
        }
        #expect(await gate.waitUntilArrived())
        let topicURL = fixture.rootURL
            .appendingPathComponent("Topics", isDirectory: true)
            .appendingPathComponent("Agency.md")
        try Data("---\ntitle: Agency\n---\n# Agency\n\nChanged during tracking.\n".utf8)
            .write(to: topicURL, options: .atomic)
        await gate.release()
        await #expect(throws: ResearchBoundedWriteSetError.staleAuthorization) {
            try await tracking.value
        }
        await handle.setResearchActivityPostInstallBarrierForTesting(nil)

        var execution = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        #expect(execution.writeSetExtensionRecords.map(\.state) == [.stale])
        #expect(execution.writeSetExtensionRecords.allSatisfy { !$0.isUnresolved })

        _ = try await handle.refresh()
        let retried = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: intent
        )
        #expect(retried.state == .recorded)
        execution = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        #expect(execution.writeSetExtensionRecords.allSatisfy { !$0.isUnresolved })

        let run = try await handle.research.actionRunDetails(
            id: connection.preparation.runID
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: try makeTestAgentResultSubmission(
                for: run,
                literatureRecommendations: []
            )
        )
        #expect(receipt.recordFormed)
        let completed = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        #expect(completed.isCompacted)
        #expect(completed.writeSetExtensionRecords.isEmpty)
        await runtime.shutdown()
    }

    @Test("Body authority preserves every provable frontmatter boundary")
    func bodyAuthorityPreservesFrontmatterState() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let plainID = VaultQualifiedNoteID(
            vaultID: fixture.topicID.vaultID,
            relativePath: "Plain.md"
        )
        let closedInvalidID = VaultQualifiedNoteID(
            vaultID: fixture.topicID.vaultID,
            relativePath: "Closed Invalid.md"
        )
        let unclosedID = VaultQualifiedNoteID(
            vaultID: fixture.topicID.vaultID,
            relativePath: "Unclosed.md"
        )
        _ = try await handle.documents.importMarkdownSource(
            "# Plain\n\nBody only.\n",
            at: plainID
        )
        let topicsURL = fixture.rootURL.appendingPathComponent(
            "Topics",
            isDirectory: true
        )
        try Data("---\ntags: [\n---\n# Original body\n".utf8).write(
            to: topicsURL.appendingPathComponent(closedInvalidID.relativePath),
            options: .atomic
        )
        try Data("---\nkey: value\n".utf8).write(
            to: topicsURL.appendingPathComponent(unclosedID.relativePath),
            options: .atomic
        )
        _ = try await handle.refresh()

        let extensionResult = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchWriteSetExtensionIntent(
                targets: [
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: "Plain.md",
                        operations: [.modifyMarkdown]
                    ),
                    try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: "Closed Invalid.md",
                        operations: [.modifyMarkdown]
                    ),
                ],
                academicReason: "Exercise exact body-only authority."
            )
        )
        #expect(extensionResult.state == .recorded)

        let frontmatterLikeBody = "---\nsecret: value\n---\n# Body\n"
        let validWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .analysis,
                relativePath: "Analysis.md",
                content: frontmatterLikeBody
            )
        )
        #expect(validWrite.state == .committed)
        let valid = try await handle.documents.load(fixture.analysisID)
        #expect(valid.frontmatterState == .valid)
        #expect(valid.parsedFrontmatter["secret"] == nil)
        #expect(valid.body == frontmatterLikeBody)

        let plainBefore = try await handle.documents.load(plainID)
        await #expect(throws: ResearchBoundedWriteSetError.operationNotAuthorized) {
            _ = try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    role: .topic,
                    relativePath: "Plain.md",
                    content: frontmatterLikeBody
                )
            )
        }
        #expect(try await handle.documents.load(plainID).sourceBytes
            == plainBefore.sourceBytes)

        let closedInvalidBody = "# Replaced body\n\nYAML bytes stay exact.\n"
        let closedInvalidWrite = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                role: .topic,
                relativePath: closedInvalidID.relativePath,
                operation: .modifyMarkdown,
                content: closedInvalidBody
            )
        )
        #expect(closedInvalidWrite.state == .committed)
        #expect(try await handle.documents.load(closedInvalidID).rawContent
            == "---\ntags: [\n---\n" + closedInvalidBody)

        await #expect(throws: ResearchBoundedWriteSetError.operationNotAuthorized) {
            _ = try await handle.research.extendAgentWriteSet(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchWriteSetExtensionIntent(
                    targets: [try ResearchWriteSetTargetSelector(
                        role: .topic,
                        relativePath: "Unclosed.md",
                        operations: [.modifyMarkdown]
                    )],
                    academicReason: "This unclosed source has no provable body boundary."
                )
            )
        }
        #expect(try await handle.documents.load(unclosedID).rawContent
            == "---\nkey: value\n")
        await runtime.shutdown()
    }

    @Test("Complete-source authority preserves exact bytes and remains revision checked")
    func completeSourceAuthorityPreservesExactBytes() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)
        let original = try await handle.documents.load(fixture.analysisID)
        #expect(original.newlineStyle == .crlf)
        #expect(original.sourceBytes.starts(with: [0xEF, 0xBB, 0xBF]))

        let completeSource = "\u{FEFF}---\r\n# Preserve this comment\r\ntitle: Rewritten Analysis\r\nunknown_key: 'kept exactly'\r\n---\r\n# Rewritten Analysis\r\n\r\nMixed 中文 and \u{1F4DA}.\r\n"
        let committed = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000901")!,
                role: .analysis,
                relativePath: "Analysis.md",
                operation: .modifySource,
                source: completeSource
            )
        )
        #expect(committed.state == .committed)
        let rewritten = try await handle.documents.load(fixture.analysisID)
        #expect(rewritten.sourceBytes == Data(completeSource.utf8))
        #expect(rewritten.frontmatterState == .valid)
        #expect(rewritten.newlineStyle == .crlf)
        #expect(rewritten.parsedFrontmatter["unknown_key"]
            == .string("kept exactly"))
        #expect(rewritten.body.contains("Mixed 中文 and 📚."))

        await #expect(throws: (any Error).self) {
            _ = try await handle.research.writeAgentDocument(
                credential: connection.credential,
                run: connection.handoff.run,
                intent: try ResearchDocumentWriteIntent(
                    requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000902")!,
                    role: .analysis,
                    relativePath: "Analysis.md",
                    operation: .modifySource,
                    source: "\u{FEFF}---\r\ntitle: Broken\r\n"
                )
            )
        }
        #expect(try await handle.documents.load(fixture.analysisID).sourceBytes
            == Data(completeSource.utf8))

        let external = "\u{FEFF}---\r\ntitle: External\r\n---\r\n# External\r\n"
        try Data(external.utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        let conflict = try await handle.research.writeAgentDocument(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try ResearchDocumentWriteIntent(
                requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000903")!,
                role: .analysis,
                relativePath: "Analysis.md",
                operation: .modifySource,
                source: completeSource + "\u{FEFF}"
            )
        )
        #expect(conflict.state == .conflict)
        #expect(try Data(contentsOf: fixture.analysesURL
            .appendingPathComponent("Analysis.md")) == Data(external.utf8))

        let execution = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        let sourceWrites = execution.documentWriteRecords.filter {
            $0.operation == .modifySource
        }
        #expect(sourceWrites.count == 2)
        #expect(sourceWrites.contains { $0.state == .committed })
        #expect(sourceWrites.contains { $0.state == .conflict })
        await runtime.shutdown()
    }

    @Test("Activity tracking records every valid target and one conflict does not poison another member")
    func automaticTrackingAndPerDocumentConflict() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let tracked = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: true)
        )
        #expect(tracked.state == .recorded)
        let activityRecord = try await handle.services.localResearchExecutionStore
            .writeSetExtension(
                runID: connection.preparation.runID,
                requestID: tracked.requestID
            )
        let topicHandle = try #require(activityRecord.candidates.first {
            $0.note.relativePath == "Agency.md"
        }?.handle)
        #expect(Set(activityRecord.allowedHandles)
            == Set(activityRecord.candidates.map(\.handle)))

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
                content: analysis.body + "\r\nAgent-bounded analysis addition.\r\n"
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
        #expect(final.boundedWriteSet.entries.contains {
            $0.note.relativePath == "Draft Argument.md"
        })
        await runtime.shutdown()
    }

    @Test("Mutation leases are one-use and bound to session, ledger, target, revision, and operation")
    func mutationLeaseBinding() async throws {
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
        let ledgerRevision = DocumentFingerprint(content: "write set one")
        let otherLedgerRevision = DocumentFingerprint(content: "write set two")
        let expected = DocumentFingerprint(content: "source")
        let firstTarget = ResearchWriteTargetHandle(runID: UUID(), noteID: UUID())
        let secondTarget = ResearchWriteTargetHandle(runID: UUID(), noteID: UUID())
        let operationID = UUID()
        let lease = try await authority.issueMutationLease(
            credential: credential,
            run: handoff.run,
            activityLedgerRevision: ledgerRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        #expect(String(describing: lease) == "<redacted mutation lease>")
        #expect(!String(reflecting: lease).contains(lease.secret))
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeMutationLease(
                lease,
                credential: credential,
                run: handoff.run,
                activityLedgerRevision: ledgerRevision,
                target: secondTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeMutationLease(
                lease,
                credential: credential,
                run: handoff.run,
                activityLedgerRevision: ledgerRevision,
                target: firstTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }

        let second = try await authority.issueMutationLease(
            credential: credential,
            run: handoff.run,
            activityLedgerRevision: ledgerRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeMutationLease(
                second,
                credential: credential,
                run: handoff.run,
                activityLedgerRevision: otherLedgerRevision,
                target: firstTarget,
                expectedRevision: expected,
                operationID: operationID,
                now: now
            )
        }

        let third = try await authority.issueMutationLease(
            credential: credential,
            run: handoff.run,
            activityLedgerRevision: ledgerRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        try await authority.consumeMutationLease(
            third,
            credential: credential,
            run: handoff.run,
            activityLedgerRevision: ledgerRevision,
            target: firstTarget,
            expectedRevision: expected,
            operationID: operationID,
            now: now
        )
        await #expect(throws: ResearchAgentSessionError.sessionRejected) {
            try await authority.consumeMutationLease(
                third,
                credential: credential,
                run: handoff.run,
                activityLedgerRevision: ledgerRevision,
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
        let run = try await handle.research.actionRunDetails(
            id: connection.preparation.runID
        )
        let initial = try await handle.documents.load(fixture.analysisID)
        let externalSource = initial.rawContent + "\nExternal pre-Agent addition.\n"
        let externalURL = fixture.analysesURL.appendingPathComponent("Analysis.md")
        try Data(externalSource.utf8).write(to: externalURL, options: .atomic)
        let agentSource = externalSource + "\nAgent addition.\n"
        let agentBody = NoteDocument(
            relativePath: "Analysis.md",
            rawContent: agentSource
        ).body
        let intent = try ResearchDocumentWriteIntent(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000501")!,
            role: .analysis,
            relativePath: "Analysis.md",
            content: agentBody
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
        let cancelError = await #expect(
            throws: ResearchActionRunContractError.self
        ) {
            try await handle.research.cancelAction(
                runID: connection.preparation.runID
            )
        }
        if case .committedWritesRequireCompletion(let runID) = cancelError {
            #expect(runID == connection.preparation.runID)
        } else {
            Issue.record("Committed modification returned the wrong End refusal.")
        }

        let beforeCompletion = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        #expect(beforeCompletion.boundedWriteSet.entries.allSatisfy {
            [.ready, .consumed, .stale, .abandoned].contains($0.state)
        })
        #expect(beforeCompletion.documentWriteRecords.map(\.state) == [
            .conflict, .committed,
        ])
        #expect(beforeCompletion.writeConflictResolutionRecords.map(
            \.conflictOperationID
        ) == [beforeCompletion.documentWriteRecords[0].id])
        #expect(try await handle.research.recoveryRecords().isEmpty)

        let resultSubmission = try makeTestAgentResultSubmission(
            for: run,
            literatureRecommendations: []
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: connection.credential,
            run: connection.handoff.run,
            submission: resultSubmission
        )
        #expect(receipt.recordFormed)
        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first(where: { $0.id == connection.preparation.runID })
        )
        let change = try #require(record.confirmedChanges.first)
        let changeStartingRevision = try #require(change.startingRevision)
        let participant = try #require(record.participatingNotes.first(where: {
            $0.noteID == change.noteID
        }))
        let externalRevision = DocumentFingerprint(content: externalSource)
        #expect(participant.startingRevision == initial.fingerprint)
        #expect(changeStartingRevision == externalRevision)
        #expect(change.endingRevision == DocumentFingerprint(content: agentSource))
        let completedSnapshot = try await handle.snapshot()
        #expect(completedSnapshot.research.activities.allSatisfy {
            $0.runID != record.id
        })
        #expect(completedSnapshot.research.resultArrivals.contains {
            $0.recordID == record.id
        })

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
        let currentState = try await handle.research
            .researchRecordChangeState(recordID: record.id)
        #expect(currentState.recordID == record.id)
        #expect(currentState.finalizedResultFingerprint
            == (try record.finalizedResultFingerprint()))
        #expect(currentState.documents.map(\.status) == [.agentEndingRevision])
        #expect(currentState.documents.first?.currentRelativePath
            == "Renamed Analysis.md")
        #expect(currentState.documents.first?.observedRevision == change.endingRevision)
        let undo: ResearchRecordChangesUndoResult
        do {
            undo = try await handle.research.undoResearchRecordChanges(
                recordID: record.id,
                selectedNoteIDs: [change.noteID],
                expectedResultFingerprint: try record.finalizedResultFingerprint()
            )
        } catch {
            Issue.record("Direct undo failed after rename: \(error)")
            throw error
        }
        #expect(undo.documents.map(\.status) == [.restored])
        #expect(try await handle.documents.load(moved.destination).sourceBytes
            == Data(externalSource.utf8))
        let restoredState = try await handle.research
            .researchRecordChangeState(recordID: record.id)
        #expect(restoredState.documents.map(\.status) == [.startingRevision])
        #expect(restoredState.documents.first?.observedRevision == changeStartingRevision)
        let reconciled = try await handle.research.undoResearchRecordChanges(
            recordID: record.id,
            selectedNoteIDs: [change.noteID],
            expectedResultFingerprint: try record.finalizedResultFingerprint()
        )
        #expect(reconciled.documents.map(\.status) == [.alreadyAtStartingRevision])

        var settlementSnapshot = try await handle.snapshot()
        let pendingSettlement = try #require(
            settlementSnapshot.research.settlementRequirements.first {
                $0.noteID == change.noteID
            }
        )
        #expect(pendingSettlement.reason == .agentChanges)
        #expect(pendingSettlement.currentRevision == changeStartingRevision)
        #expect(pendingSettlement.pendingActivities == [
            SettlementActivityReference(
                recordID: record.id,
                noteID: change.noteID
            ),
        ])

        _ = try await handle.research.settle(
            moved.destination,
            expectedRevision: changeStartingRevision,
            rationale: nil
        )
        settlementSnapshot = try await handle.snapshot()
        #expect(settlementSnapshot.research.settlementRequirements.allSatisfy {
            $0.noteID != change.noteID
        })

        let researcherSource = externalSource + "\nResearcher later edit.\n"
        let researcherRevision = DocumentFingerprint(content: researcherSource)
        try Data(researcherSource.utf8).write(
            to: fixture.analysesURL.appendingPathComponent(
                moved.destination.relativePath
            ),
            options: .atomic
        )
        settlementSnapshot = try await handle.refresh()
        let afterResearcherEdit = try #require(
            settlementSnapshot.research.settlementRequirements.first {
                $0.noteID == change.noteID
            }
        )
        #expect(afterResearcherEdit.reason == .changedSinceSettlement)
        #expect(afterResearcherEdit.currentRevision == researcherRevision)
        #expect(afterResearcherEdit.previousSettlement?.fingerprint
            == changeStartingRevision)

        _ = try await handle.research.settle(
            moved.destination,
            expectedRevision: researcherRevision,
            rationale: "Re-settled after the researcher edit."
        )
        settlementSnapshot = try await handle.snapshot()
        #expect(settlementSnapshot.research.settlementRequirements.allSatisfy {
            $0.noteID != change.noteID
        })
        try FileManager.default.removeItem(
            at: fixture.analysesURL.appendingPathComponent(
                moved.destination.relativePath
            )
        )
        _ = try await handle.refresh()
        let unavailableState = try await handle.research
            .researchRecordChangeState(recordID: record.id)
        #expect(unavailableState.documents.map(\.status) == [.unavailable])
        #expect(unavailableState.documents.first?.observedRevision == nil)
        await runtime.shutdown()
    }

    @Test("A conflict refreshes one exact member, retries idempotently, and can later be abandoned")
    func refreshRetryAndAbandonConflict() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let connection = try await prepareWritableRun(handle: handle, fixture: fixture)

        let tracked = try await handle.research.extendAgentWriteSet(
            credential: connection.credential,
            run: connection.handoff.run,
            intent: try extensionIntent(includeWork: false)
        )
        #expect(tracked.state == .recorded)
        let beforeConflict = try await handle.services.localResearchExecutionStore
            .record(id: connection.preparation.runID)
        let topicEntry = try #require(
            beforeConflict.boundedWriteSet.entries.first {
                $0.note.relativePath == "Agency.md"
            }
        )
        let topicHandle = topicEntry.handle
        let originalStartingRevision = try await handle.services
            .agentChangeEvidenceStore.evidence(
                runID: connection.preparation.runID,
                noteID: topicEntry.noteID
            ).startingRevision

        let topicURL = fixture.rootURL
            .appendingPathComponent("Topics", isDirectory: true)
            .appendingPathComponent("Agency.md")
        try Data("---\ntitle: Agency\n---\n# Agency\n\nExternal revision.\n".utf8)
            .write(to: topicURL, options: .atomic)
        let writeRequestID = UUID(uuidString: "00000000-0000-4000-8000-000000000301")!
        let intendedContent = "---\ntitle: Agency\n---\n# Agency\n\nReconciled Agent revision.\n"
        let intendedBody = "# Agency\n\nReconciled Agent revision.\n"
        let writeIntent = try ResearchDocumentWriteIntent(
            requestID: writeRequestID,
            role: .topic,
            relativePath: "Agency.md",
            content: intendedBody
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
                content: intendedBody + "Another Agent attempt.\n"
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
        #expect(stored.writeConflictResolutionRecords.count == 2)
        #expect(stored.documentWriteRecords.map(\.state) == [
            .conflict, .committed, .conflict,
        ])
        let evidence = try await handle.services.agentChangeEvidenceStore.evidence(
            runID: connection.preparation.runID,
            noteID: currentEntry.noteID
        )
        #expect(evidence.noteID == currentEntry.noteID)
        #expect(evidence.startingRevision != originalStartingRevision)
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
        #expect(result.state == .unchanged)
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: connection.preparation.runID
        )
        #expect(stored.writeSetExtensionRecords.isEmpty)
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
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let helpers = ResearchActionRunOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .analyze,
                target: target
            )
        )
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: preparation.runID
        )
        #expect(stored.boundedWriteSet.entries.map(\.noteID) == [target.noteID])
        #expect(stored.boundedWriteSet.entries.first?.activityOrigin == .initialAction)
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        return (preparation, handoff, credential)
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

private actor ResearchCreationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var arrived = false

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
