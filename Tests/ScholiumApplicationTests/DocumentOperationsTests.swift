import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

@Suite("Application document operations")
struct DocumentOperationsTests {
    @Test("Pre-rename Settle failure leaves the portable marker unchanged")
    func preRenameSettleFailureLeavesMarkerUnchanged() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        _ = try #require(projected.stableIdentity.resolvedID)
        await handle.setResearchSettlementReplacementFaultForTesting(.beforeRename)

        do {
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: "Must not cross rename."
            )
            Issue.record("Expected typed Settle pre-commit failure.")
        } catch {}
        let portableProjection = try await handle.portableSettlementProjectionForTesting()
        #expect(portableProjection.issueCount == 0)
        #expect(portableProjection.settlements.isEmpty)
        await handle.setResearchSettlementReplacementFaultForTesting(nil)
        await runtime.shutdown()
    }

    @Test("Post-rename Settle uncertainty retains the portable marker")
    func postRenameSettleUncertaintyRetainsMarker() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        _ = try #require(projected.stableIdentity.resolvedID)
        await handle.setResearchSettlementReplacementFaultForTesting(.afterRename)

        do {
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: "Crossed rename before the injected failure."
            )
            Issue.record("Expected typed Settle commit uncertainty.")
        } catch {}
        let portableProjection = try await handle.portableSettlementProjectionForTesting()
        #expect(portableProjection.issueCount == 0)
        #expect(portableProjection.settlements.map(\.fingerprint)
            == [document.fingerprint])
        await handle.setResearchSettlementReplacementFaultForTesting(nil)
        await runtime.shutdown()
    }

    @Test("An ordinary move rewrites resolved incoming links")
    func ordinaryMoveRewritesIncomingLinks() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)

        let destinationPath = "Moved/Target.md"
        let commit = try await handle.documents.move(
            fixture.targetID,
            to: destinationPath,
            expectedRevision: source.fingerprint
        ).committedValue

        #expect(commit.destination == VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: destinationPath
        ))
        #expect(commit.rewrites.count == 1)
        #expect(commit.rewrites[0].rewrittenOccurrences == 1)
        let referringDocument = try await handle.documents.load(fixture.referenceID)
        #expect(referringDocument.rawContent.contains("[[Moved/Target]]"))
        #expect(!referringDocument.rawContent.contains("[[Target]]"))
        await runtime.shutdown()
    }

    @Test("A captured Trash target rejects a reused path with another stable identity")
    func mutationTargetRejectsIdentityDrift() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projection = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projection.stableIdentity.resolvedID)
        let staleTarget = NoteMutationTarget(
            documentID: fixture.targetID,
            stableNoteID: UUID(),
            revision: source.fingerprint
        )

        do {
            _ = try await handle.documents.prepareSystemTrash(staleTarget)
            Issue.record("Expected the stale stable identity to reject preparation.")
        } catch NoteIdentityRecoveryError.targetIdentityChanged(let path) {
            #expect(path == fixture.targetID.relativePath)
        }
        let unchanged = try await handle.documents.load(fixture.targetID)
        #expect(unchanged.relativePath == source.relativePath)
        #expect(unchanged.rawContent == source.rawContent)
        #expect(unchanged.fingerprint == source.fingerprint)

        let target = NoteMutationTarget(
            documentID: fixture.targetID,
            stableNoteID: stableID,
            revision: source.fingerprint
        )
        #expect(staleTarget.id != target.id)
        let preview = try await handle.documents.prepareSystemTrash(target)
        #expect(preview.sources.map(\.relativePath) == ["Target.md"])
        await runtime.shutdown()
    }

    @Test("Creating a note records a portable stable identity")
    func createRecordsPortableIdentity() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let createdID = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "New/Created.md"
        )

        let created = try await handle.documents.create(
            createdID,
            content: "# Created\n\nApplication-owned creation.\n"
        ).committedValue

        let projected = try #require(try await handle.snapshot().document(id: createdID))
        let stableID = try #require(projected.stableIdentity.resolvedID)
        #expect(projected.fingerprint == created.fingerprint)
        await runtime.shutdown()

        // A fresh snapshot runtime resolves the same portable identity without
        // borrowing the Core identity store across the Application boundary.
        let reopenedRuntime = fixture.runtime()
        let reopenedHandle = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        let reopened = try #require(try await reopenedHandle.snapshot().document(id: createdID))
        #expect(reopened.stableIdentity.resolvedID == stableID)
        #expect(reopened.fingerprint == created.fingerprint)
        await reopenedRuntime.shutdown()
    }

    @Test("Typed creation validates Core contracts and preserves canonical source bytes")
    func typedCreationUsesCorePropertyContract() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysesID = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "New/Analysis.md"
        )

        let optionalID = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "New/Optional.md"
        )
        let optional = try await handle.documents.createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: optionalID.vaultID,
                destination: .exact(relativePath: optionalID.relativePath),
                body: "# Optional\n"
            )
        ).committedValue.document
        #expect(optional.rawContent == "# Optional\n")
        #expect(!optional.rawContent.contains("research_unit"))
        _ = try await handle.refresh()

        let settlement = try await handle.research.settle(
            optionalID,
            expectedRevision: optional.fingerprint,
            rationale: "Settlement is bound only to the current revision."
        )
        #expect(settlement.fingerprint == optional.fingerprint)

        let declared = try await handle.documents.save(
            optionalID,
            changeSet: .exactContent("""
                ---
                research_unit:
                  completion: "6/11"
                  limitations:
                    - "Only one translation was consulted."
                ---
                # Optional

            """),
            expectedRevision: optional.fingerprint
        ).committedValue
        #expect(declared.document.fingerprint != settlement.fingerprint)

        let created = try await handle.documents.createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: analysesID.vaultID,
                destination: .exact(relativePath: analysesID.relativePath),
                body: "# Analysis\n"
            )
        ).committedValue.document
        #expect(created.rawContent == "# Analysis\n")

        let worksID = try #require(fixture.assignment.vault(for: .output)?.id)
        let untitledWork = try await handle.documents.createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: worksID,
                destination: .exact(relativePath: "Untitled.md")
            )
        ).committedValue.document
        #expect(untitledWork.rawContent.isEmpty)
        await runtime.shutdown()
    }

    @Test("Untitled creation claims the first unoccupied name in the requested folder")
    func untitledCreationAdvancesWithoutReplacingSource() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID

        for relativePath in ["Sources/Untitled.md", "Sources/Untitled 2.md"] {
            _ = try await handle.documents.create(
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath),
                content: "Existing source at \(relativePath)\n"
            )
        }
        let events = await handle.events.events()
        var iterator = events.makeAsyncIterator()
        _ = try #require(await iterator.next())

        let created = try await handle.documents.createUntitledNote(
            inVault: vaultID,
            folderRelativePath: "Sources"
        ).committedValue

        #expect(created.document.relativePath == "Sources/Untitled 3.md")
        #expect(created.document.rawContent.isEmpty)
        #expect(created.sourceAheadSnapshot.derivedProjectionState == .sourceAhead)
        let publication = try #require(await iterator.next())
        guard case .sourceCommitted(let event) = publication else {
            Issue.record("Untitled creation did not own the first post-commit refresh publication.")
            await runtime.shutdown()
            return
        }
        #expect(event.note.id == created.id)
        #expect(event.kind == .creation)
        let first = try await handle.documents.load(VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/Untitled.md"
        ))
        let second = try await handle.documents.load(VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/Untitled 2.md"
        ))
        #expect(first.rawContent == "Existing source at Sources/Untitled.md\n")
        #expect(second.rawContent == "Existing source at Sources/Untitled 2.md\n")
        await runtime.shutdown()
    }

    @Test("Managed creation treats a source-absent portable identity as an occupied path")
    func managedCreationDoesNotReusePortableIdentity() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID
        let occupiedPath = "Sources/Untitled.md"
        let oldRevision = DocumentFingerprint(content: "# Previously deleted\n")
        let oldIdentity = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: vaultID,
                relativePath: occupiedPath,
                fingerprint: oldRevision
            )
        )
        let bindings = try await handle.services.controlStore.zoteroBindings()
        let oldBinding = try AnalysisZoteroBinding(
            noteID: oldIdentity.id,
            library: .group(42),
            itemKey: "ABCD1234"
        )
        _ = try await handle.services.controlStore.setZoteroBinding(
            oldBinding,
            expectedRevision: bindings.revision
        )

        let created = try await handle.documents.createUntitledNote(
            inVault: vaultID,
            folderRelativePath: "Sources"
        ).committedValue
        #expect(created.id.relativePath == "Sources/Untitled 2.md")
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: try #require(
                fixture.assignment.vaults.values.first { $0.id == vaultID }
            ).canonicalPath).appendingPathComponent(occupiedPath).path
        ))
        await #expect(
            throws: DocumentCreationError.portableIdentityAlreadyExists
        ) {
            _ = try await handle.documents.createManagedNote(
                ManagedNoteCreationRequest(
                    vaultID: vaultID,
                    destination: .exact(relativePath: occupiedPath)
                )
            )
        }
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: vaultID,
            relativePath: occupiedPath
        ) == oldIdentity)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: oldIdentity.id) == oldBinding)
        await runtime.shutdown()
    }

    @Test("Managed creation copies exactly one role seed and leaves the body empty")
    func managedCreationUsesExactRoleSeed() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let saved = try await handle.research.settings()
        var settings = saved.settings
        settings.properties[.paperAnalysis]?.newNoteYAML =
            "tags: [draft]\ncustom: |+\n  exact\n  ---\n  after\n\n"
        settings.properties[.topicKnowledge]?.newNoteYAML = "summary: Map\n"
        settings.properties[.output]?.newNoteYAML = "work_type: chapter\n"
        _ = try await handle.research.saveSettings(
            settings,
            expectedRevision: saved.revision
        )

        let cases: [(WorkspaceVaultSlot, String)] = [
            (
                .paperAnalysis,
                "---\ntags: [draft]\ncustom: |+\n  exact\n  ---\n  after\n\n---\n"
            ),
            (.topicKnowledge, "---\nsummary: Map\n---\n"),
            (.output, "---\nwork_type: chapter\n---\n"),
        ]
        for (slot, expectedSource) in cases {
            let registeredVault = try #require(fixture.assignment.vault(for: slot))
            let vaultID = registeredVault.id
            let created = try await handle.documents.createUntitledNote(
                inVault: vaultID,
                folderRelativePath: nil
            ).committedValue
            #expect(created.document.rawContent == expectedSource)
            #expect(created.document.hasExactEmptyBody)
            #expect(
                created.document.bodyUTF16Offset
                    == expectedSource.utf16.count
            )
            #expect(
                try Data(
                    contentsOf: URL(fileURLWithPath: registeredVault.canonicalPath)
                        .appendingPathComponent(created.id.relativePath)
                ) == Data(expectedSource.utf8)
            )
        }
        await runtime.shutdown()
    }

    @Test("Typed managed creation shares the seed while Agent policy freezes requirements and identity")
    func typedManagedCreationUsesOneCreator() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analyses = try #require(fixture.assignment.vault(for: .paperAnalysis))

        let saved = try await handle.research.settings()
        var settings = saved.settings
        settings.properties[.paperAnalysis]?.newNoteYAML =
            "# researcher seed\ntags: [configured]\n"
        settings.analysisAgentCreation.requiredFieldsBySourceType[.journalArticle] = [
            "authors",
        ]
        let configured = try await handle.research.saveSettings(
            settings,
            expectedRevision: saved.revision
        )

        let title = try CanonicalPropertyInput(
            key: "title",
            value: .string("Reasons and Persons")
        )
        let authors = try CanonicalPropertyInput(
            key: "authors",
            value: .array([.object([
                "family": .string("Scanlon"),
                "given": .string("T. M."),
            ])])
        )
        let metadata = try AnalysisCreationMetadata(
            sourceType: .journalArticle,
            properties: [authors, title]
        )
        let reservedIdentity = UUID()
        let created = try await handle.documents.createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: analyses.id,
                destination: .exact(relativePath: "Agent/Created.md"),
                body: "# Working body\n",
                analysisMetadata: metadata,
                authority: .authenticatedAgent(
                    settingsRevision: configured.revision,
                    reservedIdentity: reservedIdentity
                )
            )
        ).committedValue

        #expect(created.stableIdentity.resolvedID == reservedIdentity)
        #expect(created.document.parsedFrontmatter["type"] == .string("journal_article"))
        #expect(created.document.parsedFrontmatter["title"] == .string("Reasons and Persons"))
        #expect(created.document.parsedFrontmatter["authors"] == authors.value)
        #expect(created.document.parsedFrontmatter["tags"] == .array([.string("configured")]))
        #expect(created.document.body == "# Working body\n")
        let source = created.document.rawContent
        let typeRange = try #require(source.range(of: "type: journal_article"))
        let titleRange = try #require(source.range(of: "title: Reasons and Persons"))
        let seedRange = try #require(source.range(of: "# researcher seed"))
        #expect(typeRange.lowerBound < titleRange.lowerBound)
        #expect(titleRange.lowerBound < seedRange.lowerBound)

        await #expect(throws: DocumentCreationError.missingRequiredAgentFields(["authors"])) {
            _ = try await handle.documents.createManagedNote(
                try ManagedNoteCreationRequest(
                    vaultID: analyses.id,
                    destination: .exact(relativePath: "Agent/Missing.md"),
                    analysisMetadata: try AnalysisCreationMetadata(
                        sourceType: .journalArticle,
                        properties: [title]
                    ),
                    authority: .authenticatedAgent(
                        settingsRevision: configured.revision,
                        reservedIdentity: UUID()
                    )
                )
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: analyses.canonicalPath)
                .appendingPathComponent("Agent/Missing.md").path
        ))

        // The same typed request through researcher CLI policy is not subject
        // to Agent-only requiredness.
        let researcher = try await handle.documents.createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: analyses.id,
                destination: .exact(relativePath: "Researcher/Created.md"),
                analysisMetadata: try AnalysisCreationMetadata(
                    sourceType: .journalArticle,
                    properties: [title]
                )
            )
        ).committedValue
        #expect(researcher.document.parsedFrontmatter["authors"] == nil)

        await runtime.shutdown()
    }

    @Test("First YAML insertion is explicit and bound to the current source revision")
    func firstYAMLInsertionUsesExpectedRevision() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID
        let id = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "YAML-free.md"
        )
        let plain = try await handle.documents.create(
            id,
            content: "# Existing body\n\nExact prose.\n"
        ).committedValue

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.documents.save(
                id,
                changeSet: .insertFrontmatter([
                    "tags": .array(["explicit"])
                ]),
                expectedRevision: DocumentFingerprint(content: "stale")
            )
        }
        #expect(try await handle.documents.load(id).rawContent == plain.rawContent)

        let inserted = try await handle.documents.save(
            id,
            changeSet: .insertFrontmatter([
                "tags": .array(["explicit"])
            ]),
            expectedRevision: plain.fingerprint
        ).committedValue.document
        #expect(
            inserted.rawContent
                == "---\ntags:\n  - explicit\n---\n# Existing body\n\nExact prose.\n"
        )
        #expect(inserted.body == plain.rawContent)
        await runtime.shutdown()
    }

    @Test("First YAML insertion refuses malformed opening boundaries without changing bytes")
    func firstYAMLInsertionPreservesMalformedSource() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID

        for (index, source) in [
            "---\nkey: value\n",
            "\u{FEFF}---\r\nkey: value\r\n",
        ].enumerated() {
            let id = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Malformed-\(index).md"
            )
            let created = try await handle.documents.create(
                id,
                content: source
            ).committedValue
            await #expect(throws: VaultRepositoryError.self) {
                _ = try await handle.documents.save(
                    id,
                    changeSet: .insertFrontmatter([
                        "summary": .string("Do not insert")
                    ]),
                    expectedRevision: created.fingerprint
                )
            }
            let loaded = try await handle.documents.load(id)
            #expect(loaded.rawContent == source)
            #expect(loaded.sourceBytes == Data(source.utf8))
        }
        await runtime.shutdown()
    }

    @Test("Managed creation refuses settings that need review before claiming source")
    func managedCreationFailsBeforeWriteForInvalidSettings() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let works = try #require(fixture.assignment.vault(for: .output))
        let settingsURL = URL(fileURLWithPath: works.canonicalPath)
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium/settings.json")
        var invalidSettings = try await handle.research.settings().settings
        invalidSettings.properties[.paperAnalysis]?.newNoteYAML =
            "title: forbidden\n"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(invalidSettings).write(
            to: settingsURL,
            options: .atomic
        )

        let analysesVault = try #require(
            fixture.assignment.vault(for: .paperAnalysis)
        )
        await #expect(throws: (any Error).self) {
            _ = try await handle.documents.createUntitledNote(
                inVault: analysesVault.id,
                folderRelativePath: nil
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: analysesVault.canonicalPath)
                    .appendingPathComponent("Untitled.md").path
            )
        )
        await runtime.shutdown()
    }

    @Test("Managed body text cannot introduce a top-level YAML envelope")
    func managedBodyCannotCarryFrontmatter() throws {
        let vaultID = UUID()
        for body in [
            "---\nsecret: value\n---\n# Body\n",
            "---\nsecret: value\n",
        ] {
            #expect(throws: DocumentCreationError.invalidBody) {
                _ = try ManagedNoteCreationRequest(
                    vaultID: vaultID,
                    destination: .exact(relativePath: "Created.md"),
                    body: body
                )
            }
            #expect(throws: DocumentCreationError.invalidBody) {
                _ = try ManagedNoteCreationRequest(
                    vaultID: vaultID,
                    destination: .exact(relativePath: "Analysis.md"),
                    body: body,
                    analysisMetadata: try AnalysisCreationMetadata(
                        sourceType: .journalArticle
                    )
                )
            }
        }
        #expect(try ManagedNoteCreationRequest(
            vaultID: vaultID,
            destination: .exact(relativePath: "Safe.md"),
            body: "# Body\n\n---\nNested thematic break.\n"
        ).body.hasPrefix("# Body"))
    }

    @Test("Agent managed creation revalidates Settings after a concurrent save")
    func managedCreationRejectsChangedSettingsBeforeClaim() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let saved = try await handle.research.settings()
        let reservedID = UUID()
        let request = try ManagedNoteCreationRequest(
            vaultID: topic.id,
            destination: .exact(relativePath: "Stale Settings.md"),
            body: "# Must not commit\n",
            authority: .authenticatedAgent(
                settingsRevision: saved.revision,
                reservedIdentity: reservedID
            )
        )
        let gate = ManagedCreationTestGate()
        await handle.setManagedCreationPreLeaseBarrierForTesting {
            await gate.wait()
        }
        let creation = Task {
            try await handle.documents.createManagedNote(request)
        }
        #expect(await gate.waitUntilArrived())

        var changed = saved.settings
        changed.properties[.topicKnowledge]?.newNoteYAML = "summary: newer\n"
        _ = try await handle.research.saveSettings(
            changed,
            expectedRevision: saved.revision
        )
        await gate.release()
        await #expect(throws: DocumentCreationError.settingsRevisionChanged) {
            _ = try await creation.value
        }
        await handle.setManagedCreationPreLeaseBarrierForTesting(nil)
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: topic.canonicalPath)
                .appendingPathComponent("Stale Settings.md").path
        ))
        #expect(try await handle.services.controlStore.identityRecord(
            id: reservedID
        ) == nil)
        await runtime.shutdown()
    }

    @Test("Researcher managed creation retains visible recovery after final source loss")
    func researcherCreationFinalFailureIsDurable() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let path = "Researcher Final Recovery.md"
        let gate = ManagedCreationTestGate()
        await handle.setManagedCreationPostSourceBarrierForTesting {
            await gate.wait()
        }
        let creation = Task {
            try await handle.documents.createManagedNote(
                ManagedNoteCreationRequest(
                    vaultID: topic.id,
                    destination: .exact(relativePath: path),
                    body: "# Intended\n"
                )
            )
        }
        #expect(await gate.waitUntilArrived())
        let repositories = await handle.services.repositories
        let repository = try #require(repositories[topic.id])
        let current = try await repository.load(relativePath: path)
        try await repository.removeCreatedFileForRollback(
            relativePath: path,
            createdRevision: current.fingerprint
        )
        await gate.release()
        var recoveryID: UUID?
        do {
            _ = try await creation.value
            Issue.record("Expected final managed-creation recovery.")
        } catch let error as TriptychTransactionError {
            guard case .recoveryRequired(let record) = error else {
                Issue.record("Unexpected managed-creation error: \(error)")
                await runtime.shutdown()
                return
            }
            #expect(record.operation == .noteCreation)
            #expect(record.researchWrite == nil)
            #expect(record.managedCreation?.reservedIdentityID != nil)
            #expect(record.files.first?.state == .missing)
            recoveryID = record.id
        }
        await handle.setManagedCreationPostSourceBarrierForTesting(nil)
        #expect(try await handle.research.recoveryRecords().count == 1)
        try await handle.research.resolveRecoveryRecord(try #require(recoveryID))
        #expect(try await handle.research.recoveryRecords().isEmpty)
        #expect(try await handle.services.controlStore.identityRecord(
            vaultID: topic.id,
            relativePath: path
        ) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: topic.canonicalPath)
                .appendingPathComponent(path).path
        ))
        await runtime.shutdown()
    }

    @Test("Researcher managed creation durably records retained and unreadable identity failures")
    func researcherCreationIdentityFailureIsDurable() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let cases: [(path: String, unreadable: Bool)] = [
            ("Recovery/Externally Changed.md", false),
            ("Recovery/Unreadable.md", true),
        ]
        var recoveryIDs: Set<UUID> = []
        var foreignIdentities: [String: NoteIdentityRecord] = [:]

        for item in cases {
            let gate = ManagedCreationTestGate()
            await handle.setManagedCreationPostSourceBarrierForTesting {
                await gate.wait()
            }
            let creation = Task {
                try await handle.documents.createManagedNote(
                    ManagedNoteCreationRequest(
                        vaultID: topic.id,
                        destination: .exact(relativePath: item.path),
                        body: "# Intended\n"
                    )
                )
            }
            #expect(await gate.waitUntilArrived())
            let repositories = await handle.services.repositories
            let repository = try #require(repositories[topic.id])
            let created = try await repository.load(relativePath: item.path)
            let foreign = try #require(try await handle.services.controlStore.identity(
                forVaultID: topic.id,
                relativePath: item.path,
                fingerprint: created.fingerprint
            ))
            foreignIdentities[item.path] = foreign
            let sourceURL = URL(fileURLWithPath: topic.canonicalPath)
                .appendingPathComponent(item.path)
            if item.unreadable {
                try FileManager.default.removeItem(at: sourceURL)
                try FileManager.default.createDirectory(
                    at: sourceURL,
                    withIntermediateDirectories: false
                )
            } else {
                try Data("# Externally changed\n".utf8).write(
                    to: sourceURL,
                    options: .atomic
                )
            }
            await gate.release()

            do {
                _ = try await creation.value
                Issue.record("Expected managed-creation recovery for \(item.path).")
            } catch let error as TriptychTransactionError {
                guard case .recoveryRequired(let record) = error else {
                    Issue.record("Unexpected managed-creation error for \(item.path): \(error)")
                    continue
                }
                #expect(record.researchWrite == nil)
                #expect(record.managedCreation?.target.relativePath == item.path)
                #expect(record.managedCreation?.reservedIdentityID != foreign.id)
                #expect(record.files.first?.state
                    == (item.unreadable ? .unreadable : .externallyChanged))
                recoveryIDs.insert(record.id)
            }
            await handle.setManagedCreationPostSourceBarrierForTesting(nil)
        }

        #expect(Set(try await handle.research.recoveryRecords().map(\.id))
            == recoveryIDs)
        await runtime.shutdown()

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(
            id: fixture.assignment.id
        )
        #expect(Set(try await reopened.research.recoveryRecords().map(\.id))
            == recoveryIDs)
        for item in cases {
            #expect(try await reopened.services.controlStore.identityRecord(
                vaultID: topic.id,
                relativePath: item.path
            )?.id == foreignIdentities[item.path]?.id)
        }
        await reopenedRuntime.shutdown()
    }

    @Test("Managed creation recovery cannot remove a Zotero-bound reserved identity")
    func researcherCreationRecoveryPreservesBinding() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let path = "Bound Final Recovery.md"
        let gate = ManagedCreationTestGate()
        await handle.setManagedCreationPostSourceBarrierForTesting {
            await gate.wait()
        }
        let creation = Task {
            try await handle.documents.createManagedNote(
                ManagedNoteCreationRequest(
                    vaultID: topic.id,
                    destination: .exact(relativePath: path),
                    body: "# Intended\n"
                )
            )
        }
        #expect(await gate.waitUntilArrived())
        let repositories = await handle.services.repositories
        let repository = try #require(repositories[topic.id])
        let current = try await repository.load(relativePath: path)
        try await repository.removeCreatedFileForRollback(
            relativePath: path,
            createdRevision: current.fingerprint
        )
        await gate.release()
        let recovery: TriptychMutationRecoveryRecord
        do {
            _ = try await creation.value
            Issue.record("Expected final managed-creation recovery.")
            await runtime.shutdown()
            return
        } catch let error as TriptychTransactionError {
            guard case .recoveryRequired(let record) = error else {
                Issue.record("Unexpected managed-creation error: \(error)")
                await runtime.shutdown()
                return
            }
            recovery = record
        }
        await handle.setManagedCreationPostSourceBarrierForTesting(nil)
        let reservedID = try #require(
            recovery.managedCreation?.reservedIdentityID
        )
        let binding = try AnalysisZoteroBinding(
            noteID: reservedID,
            library: .group(42),
            itemKey: "ABCD"
        )
        _ = try await handle.services.controlStore.setZoteroBinding(
            binding,
            expectedRevision: try await handle.services.controlStore
                .zoteroBindings().revision
        )

        await #expect(throws: (any Error).self) {
            try await handle.research.resolveRecoveryRecord(recovery.id)
        }
        #expect(try await handle.research.recoveryRecords().map(\.id) == [recovery.id])
        #expect(try await handle.services.controlStore.identityRecord(
            id: reservedID
        ) != nil)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: reservedID) == binding)
        await runtime.shutdown()
    }

    @Test("A source-ahead Note follows two immediate Folder classifications")
    func sourceAheadNoteAuthorizesConsecutiveFolderMoves() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID

        let folder = try await handle.documents.createUntitledFolder(
            inVault: vaultID,
            parentRelativePath: nil
        ).committedValue
        let created = try await handle.documents.createUntitledNote(
            inVault: vaultID,
            folderRelativePath: folder.rawValue
        ).committedValue
        let stableNoteID = try #require(created.stableIdentity.resolvedID)

        let first = try await handle.documents.moveFolder(
            inVault: vaultID,
            from: folder.rawValue,
            to: "First Classification"
        ).committedValue
        #expect(first.noteMoves.map(\.stableNoteID) == [stableNoteID])
        #expect(first.noteMoves.map(\.destination.relativePath)
            == ["First Classification/Untitled.md"])

        let second = try await handle.documents.moveFolder(
            inVault: vaultID,
            from: "First Classification",
            to: "Second Classification"
        ).committedValue
        #expect(second.noteMoves.map(\.stableNoteID) == [stableNoteID])
        #expect(second.noteMoves.map(\.destination.relativePath)
            == ["Second Classification/Untitled.md"])
        let moved = try await handle.documents.load(VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Second Classification/Untitled.md"
        ))
        #expect(moved.rawContent.isEmpty)
        await runtime.shutdown()
    }

    @Test("Folder planning overlays durable source-ahead identities by Note ID")
    func sourceAheadFolderPlanReplacesStaleSnapshotLocations() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.snapshot()
        let vault = try #require(snapshot.vault(id: fixture.targetID.vaultID))
        let target = try #require(vault.documents.first {
            $0.id == fixture.targetID
        })
        let targetID = try #require(target.stableIdentity.resolvedID)
        let movedLocation = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "First Classification/Target.md"
        )
        let createdLocation = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "First Classification/Untitled.md"
        )
        let movedRecord = NoteIdentityRecord(
            id: targetID,
            vaultID: movedLocation.vaultID,
            relativePath: movedLocation.relativePath,
            fingerprint: target.fingerprint
        )
        let createdRecord = NoteIdentityRecord(
            vaultID: createdLocation.vaultID,
            relativePath: createdLocation.relativePath,
            fingerprint: DocumentFingerprint(content: "")
        )

        let moves = try sourceAuthorizedFolderNoteMoves(
            vaultID: fixture.targetID.vaultID,
            sourceFolder: VaultRelativeFolderPath("First Classification"),
            destinationFolder: VaultRelativeFolderPath("Second Classification"),
            snapshotDocuments: vault.documents,
            sourceAheadIdentityRecords: [
                movedLocation: movedRecord,
                createdLocation: createdRecord,
            ]
        )

        let plannedIDs = moves.map(\.stableNoteID).sorted {
            $0.uuidString < $1.uuidString
        }
        let expectedIDs = [targetID, createdRecord.id].sorted {
            $0.uuidString < $1.uuidString
        }
        #expect(plannedIDs == expectedIDs)
        #expect(moves.map(\.source.relativePath) == [
            "First Classification/Target.md",
            "First Classification/Untitled.md",
        ])
        #expect(moves.map(\.destination.relativePath) == [
            "Second Classification/Target.md",
            "Second Classification/Untitled.md",
        ])
        await runtime.shutdown()
    }

    @Test("Folder creation is direct and ordinary moves preserve note identities and resolved links")
    func folderOperationsTrackNotesRatherThanFolders() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vaultID = fixture.targetID.vaultID
        let searchGenerationBeforeFolders = try await handle.snapshot()
            .discovery.searchGeneration

        let firstFolder = try await handle.documents.createUntitledFolder(
            inVault: vaultID,
            parentRelativePath: nil
        ).committedValue
        let secondFolder = try await handle.documents.createUntitledFolder(
            inVault: vaultID,
            parentRelativePath: nil
        ).committedValue
        #expect(firstFolder.rawValue == "Untitled Folder")
        #expect(secondFolder.rawValue == "Untitled Folder 2")
        #expect(try await handle.snapshot().discovery.searchGeneration
            == searchGenerationBeforeFolders)

        let firstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Untitled Folder/First.md"
        )
        let secondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Untitled Folder/Nested/Second.md"
        )
        let referenceID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Folder Reference.md"
        )
        let first = try await handle.documents.create(
            firstID,
            content: "# First\n\nSee [[Untitled Folder/Nested/Second]].\n"
        ).committedValue
        _ = try await handle.documents.create(secondID, content: "# Second\n")
        _ = try await handle.documents.create(
            referenceID,
            content: "# Reference\n\nSee [[Untitled Folder/First]].\n"
        )
        _ = try await handle.documents.save(
            firstID,
            changeSet: .exactContent(
                first.rawContent + "\nA revised observation.\n"
            ),
            expectedRevision: first.fingerprint
        )
        let attachmentBytes = Data([9, 8, 7, 0, 255])
        try attachmentBytes.write(
            to: fixture.analysesURL.appendingPathComponent(
                "Untitled Folder/Nested/source.bin"
            )
        )

        let before = try await handle.snapshot()
        let firstStableID = try #require(before.document(id: firstID)?.stableIdentity.resolvedID)
        let secondStableID = try #require(before.document(id: secondID)?.stableIdentity.resolvedID)
        let events = await handle.events.events()
        var iterator = events.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let commit = try await handle.documents.moveFolder(
            inVault: vaultID,
            from: "Untitled Folder",
            to: "Sources"
        ).committedValue

        #expect(commit.noteMoves.count == 2)
        #expect(commit.rewrites.count == 2)
        #expect(commit.noteMoves.first(where: {
            $0.destination.relativePath == "Sources/First.md"
        })?.committedRawContent.contains("[[Sources/Nested/Second]]") == true)
        let movedFirstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/First.md"
        )
        let movedSecondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/Nested/Second.md"
        )
        var publishedMove: WorkspaceSnapshot?
        for _ in 0..<3 where publishedMove == nil {
            let event = try #require(await iterator.next())
            if event.snapshot.document(id: movedFirstID) != nil,
               event.snapshot.document(id: movedSecondID) != nil {
                publishedMove = event.snapshot
            }
        }
        let after = try #require(publishedMove)
        #expect(after.document(id: movedFirstID)?.stableIdentity.resolvedID == firstStableID)
        #expect(after.document(id: movedSecondID)?.stableIdentity.resolvedID == secondStableID)
        #expect(after.document(id: firstID) == nil)
        #expect(after.vault(id: vaultID)?.folders.contains(
            try VaultRelativeFolderPath("Untitled Folder 2")
        ) == true)
        #expect(after.vault(id: vaultID)?.folders.contains(
            try VaultRelativeFolderPath("Sources/Nested")
        ) == true)
        let reference = try await handle.documents.load(referenceID)
        #expect(reference.rawContent.contains("[[Sources/First]]"))
        let movedFirst = try await handle.documents.load(movedFirstID)
        #expect(movedFirst.rawContent.contains("[[Sources/Nested/Second]]"))
        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(
            "Sources/Nested/source.bin"
        )) == attachmentBytes)

        await runtime.shutdown()
    }

    @Test("System Trash discards an affected active Discussion and preserves stable identity")
    func systemTrashCoordinatesOwnedState() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        let discussion = try await handle.research.createDiscussion(
            target: ResearchFunctionTarget(
                noteID: stableID,
                note: fixture.targetID,
                role: .analysis,
                fingerprint: source.fingerprint,
                title: "Target",
            ),
            focalNotes: [],
            passage: nil,
            researcherMessage: "Inspect this private note."
        )
        let preview = try await handle.documents.prepareSystemTrash(
            NoteMutationTarget(
                documentID: fixture.targetID,
                stableNoteID: stableID,
                revision: source.fingerprint
            )
        )
        let commit = try await handle.documents.moveToSystemTrash(preview)
            .committedValue
        defer {
            for path in commit.resultingTrashPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        #expect(commit.noteIDs == [stableID])
        #expect(commit.removedDiscussionIDs == [discussion.id])
        #expect(try await handle.research.activeDiscussions(noteID: stableID).isEmpty)
        #expect(try await handle.snapshot().document(id: fixture.targetID) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Target.md").path))
        await runtime.shutdown()
    }

    @Test("System Trash preparation rejects a participating active Research Action")
    func systemTrashRejectsActiveExecution() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .discuss,
                target: ResearchFunctionTarget(
                    noteID: stableID,
                    note: fixture.targetID,
                    role: .analysis,
                    fingerprint: source.fingerprint,
                    title: "Target"
                ),
                instruction: "Keep this Run active during deletion preflight."
            )
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await handle.documents.prepareSystemTrash(NoteMutationTarget(
                documentID: fixture.targetID,
                stableNoteID: stableID,
                revision: source.fingerprint
            ))
        }

        #expect(FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Target.md").path))
        #expect(try await handle.research.activeDiscussion(id: preparation.runID).id
            == preparation.runID)
        try await handle.research.cancelProtectedFunction(runID: preparation.runID)
        await runtime.shutdown()
    }

    @Test("System Trash archives exact legacy execution bytes and retries preparation")
    func systemTrashArchivesLegacyExecutionBeforeRetry() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        let fileName = UUID().uuidString.lowercased() + ".json"
        let executionDirectory = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v10", isDirectory: true)
        let legacyURL = executionDirectory.appendingPathComponent(fileName)
        let legacyBytes = Data("{\"schema_version\":16}".utf8)
        try legacyBytes.write(to: legacyURL)
        let target = NoteMutationTarget(
            documentID: fixture.targetID,
            stableNoteID: stableID,
            revision: source.fingerprint
        )

        let recovery: LocalResearchExecutionRecoveryPreview
        do {
            _ = try await handle.documents.prepareSystemTrash(target)
            Issue.record("Expected local execution recovery.")
            return
        } catch SystemTrashPreparationError.localExecutionRecoveryRequired(let preview) {
            recovery = preview
        }
        let commit = try await handle.documents
            .archiveUnsupportedLocalResearchExecutions(recovery)
        let trashPreview = try await handle.documents.prepareSystemTrash(target)

        #expect(commit.archivedFileNames == [fileName])
        #expect(trashPreview.affectedNoteIDs == [stableID])
        let archivedURL = executionDirectory
            .appendingPathComponent("unsupported-executions", isDirectory: true)
            .appendingPathComponent(fileName)
        #expect(try Data(contentsOf: archivedURL) == legacyBytes)
        await runtime.shutdown()
    }

    @Test("Settle stores one portable marker for the latest settled revision")
    func settleStoresLatestPortableMarker() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(try await handle.snapshot().document(id: fixture.targetID))
        let stableID = try #require(projected.stableIdentity.resolvedID)

        _ = try await handle.research.settle(
            fixture.targetID,
            expectedRevision: document.fingerprint,
            rationale: "First marker"
        )
        document = try await handle.documents.save(
            fixture.targetID,
            changeSet: .exactContent("# Target\n\nUpdated.\n"),
            expectedRevision: document.fingerprint
        ).committedValue.document
        let latest = try await handle.research.settle(
            fixture.targetID,
            expectedRevision: document.fingerprint,
            rationale: "Current marker"
        )

        let projection = try await handle.portableSettlementProjectionForTesting()
        #expect(projection.issueCount == 0)
        #expect(projection.settlements.count == 1)
        #expect(projection.settlements.first?.noteID == stableID)
        #expect(projection.settlements.first?.fingerprint == latest.fingerprint)
        #expect(projection.settlements.first?.rationale == "Current marker")
        await runtime.shutdown()
    }

    @Test("Interrupted save recovery stays vault-qualified and publishes its committed source")
    func interruptedSaveRecoveryIsVaultQualified() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let expected = try Data(
            contentsOf: fixture.analysesURL.appendingPathComponent("Target.md")
        )
        let candidate = Data(
            [0xEF, 0xBB, 0xBF] + Array("# Target\r\n\r\nRecovered after interruption.\r\n".utf8)
        )
        let transactionID = UUID()
        let createdAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let transactionDirectory = fixture.applicationSupportURL
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(fixture.targetID.vaultID.uuidString, isDirectory: true)
            .appendingPathComponent(
                "save-transactions-v1",
                isDirectory: true
            )
            .appendingPathComponent(
                transactionID.uuidString.lowercased(),
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: true
        )
        try expected.write(to: transactionDirectory.appendingPathComponent("expected.md"))
        try candidate.write(to: transactionDirectory.appendingPathComponent("candidate.md"))
        let manifest = InterruptedSaveManifestFixture(
            schemaVersion: 1,
            id: transactionID,
            relativePath: fixture.targetID.relativePath,
            expected: DocumentFingerprint(data: expected),
            candidate: DocumentFingerprint(data: candidate),
            createdAt: createdAt,
            retainedReason: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: transactionDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let recovery = try #require(
            try await handle.documents.interruptedSaveRecoveries().first
        )
        #expect(recovery.id == InterruptedSaveRecoveryID(
            vaultID: fixture.targetID.vaultID,
            transactionID: transactionID
        ))
        #expect(recovery.relativePath == fixture.targetID.relativePath)
        #expect(recovery.sourceState == .expectedRevision)
        let content = try await handle.documents.interruptedSaveRecoveryContent(recovery)
        #expect(Data(content.exactSource.utf8) == candidate)

        let otherVaultID = try #require(
            fixture.assignment.vault(for: .topicKnowledge)?.id
        )
        let wrongVault = InterruptedSaveRecovery(
            id: InterruptedSaveRecoveryID(
                vaultID: otherVaultID,
                transactionID: recovery.id.transactionID
            ),
            relativePath: recovery.relativePath,
            expectedRevision: recovery.expectedRevision,
            candidateRevision: recovery.candidateRevision,
            createdAt: recovery.createdAt,
            retainedReason: recovery.retainedReason,
            sourceState: recovery.sourceState
        )
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.documents.interruptedSaveRecoveryContent(wrongVault)
        }

        let outcome = try await handle.documents.restoreInterruptedSaveRecovery(recovery)
        #expect(outcome.committedValue.didReplaceSource)
        #expect(outcome.derivedRefreshWarning == nil)
        #expect(outcome.committedValue.document.sourceBytes == candidate)
        #expect(try Data(
            contentsOf: fixture.analysesURL.appendingPathComponent("Target.md")
        ) == candidate)
        #expect(try await handle.documents.interruptedSaveRecoveries().isEmpty)
        #expect(try await handle.snapshot().document(id: fixture.targetID)?.document.sourceBytes
            == candidate)
        await runtime.shutdown()
    }
}

private struct InterruptedSaveManifestFixture: Codable {
    let schemaVersion: Int
    let id: UUID
    let relativePath: String
    let expected: DocumentFingerprint
    let candidate: DocumentFingerprint
    let createdAt: Date
    let retainedReason: String?
}

private actor ManagedCreationTestGate {
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

private struct LifecycleFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let registryStorageURL: URL
    let analysesURL: URL
    let assignment: TriptychAssignment
    let targetID: VaultQualifiedNoteID
    let referenceID: VaultQualifiedNoteID

    static func make() async throws -> Self {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ScholiumApplicationLifecycleTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let applicationSupportURL = rootURL
            .appendingPathComponent("Application Support", isDirectory: true)
        let registryStorageURL = rootURL
            .appendingPathComponent("Registry", isDirectory: true)
        let analysesURL = rootURL.appendingPathComponent("Analyses", isDirectory: true)
        let topicsURL = rootURL.appendingPathComponent("Topics", isDirectory: true)
        let worksURL = rootURL.appendingPathComponent("Works", isDirectory: true)
        for directory in [applicationSupportURL, analysesURL, topicsURL, worksURL] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try Data("# Target\n\nA source note.\n".utf8).write(
            to: analysesURL.appendingPathComponent("Target.md"),
            options: .atomic
        )
        try Data("# Reference\n\nSee [[Target]].\n".utf8).write(
            to: analysesURL.appendingPathComponent("Reference.md"),
            options: .atomic
        )
        try Data("# Topic\n".utf8).write(
            to: topicsURL.appendingPathComponent("Topic.md"),
            options: .atomic
        )
        try Data("# Work\n".utf8).write(
            to: worksURL.appendingPathComponent("Work.md"),
            options: .atomic
        )

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analysesURL,
            topicKnowledgeURL: topicsURL,
            outputURL: worksURL,
            portableContainerURL: rootURL,
            triptychName: "Lifecycle Fixture"
        )
        let assignment = handle.assignment
        let analysesID = try #require(assignment.vault(for: .paperAnalysis)?.id)
        await runtime.shutdown()
        return Self(
            rootURL: rootURL,
            applicationSupportURL: applicationSupportURL,
            registryStorageURL: registryStorageURL,
            analysesURL: analysesURL,
            assignment: assignment,
            targetID: VaultQualifiedNoteID(
                vaultID: analysesID,
                relativePath: "Target.md"
            ),
            referenceID: VaultQualifiedNoteID(
                vaultID: analysesID,
                relativePath: "Reference.md"
            )
        )
    }

    func runtime() -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            assignments: [assignment]
        )))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
