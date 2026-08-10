import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

@Suite("Application document lifecycle operations")
struct DocumentLifecycleOperationsTests {
    @Test("Pre-rename Settle failure removes only its newly created machine-local pin")
    func preRenameSettleFailureRollsBackPin() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        await handle.setResearchSettlementReplacementFaultForTesting(.beforeRename)

        do {
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: "Must not cross rename."
            )
            Issue.record("Expected typed Settle pre-commit failure.")
        } catch {
            #expect(ResearchSettlementRecovery.shouldRollbackNewPin(after: error))
        }
        #expect(try await handle.research.settledSnapshots(noteID: stableID).isEmpty)
        let portableProjection = try await handle.portableSettlementProjectionForTesting()
        #expect(portableProjection.issueCount == 0)
        #expect(portableProjection.settlements.isEmpty)
        await handle.setResearchSettlementReplacementFaultForTesting(nil)
        await runtime.shutdown()
    }

    @Test("Post-rename Settle uncertainty retains the exact machine-local pin")
    func postRenameSettleUncertaintyRetainsPin() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        await handle.setResearchSettlementReplacementFaultForTesting(.afterRename)

        do {
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: "Crossed rename before the injected failure."
            )
            Issue.record("Expected typed Settle commit uncertainty.")
        } catch {
            #expect(!ResearchSettlementRecovery.shouldRollbackNewPin(after: error))
        }
        #expect(try await handle.research.settledSnapshots(noteID: stableID).count == 1)
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

    @Test("Moving a Set Aside note to Trash removes the lifecycle prefix")
    func setAsideToTrashUsesCanonicalPath() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let events = await handle.events.events()
        var iterator = events.makeAsyncIterator()
        _ = try #require(await iterator.next())

        let setAside = try await handle.documents.setAside(
            fixture.targetID,
            expectedRevision: source.fingerprint
        ).committedValue
        let setAsideID = setAside.destination
        #expect(setAsideID.relativePath == "Set Aside/Target.md")
        let setAsideDocument = try await handle.documents.load(setAsideID)

        let trash = try await handle.documents.moveToTrash(
            setAsideID,
            expectedRevision: setAsideDocument.fingerprint
        ).committedValue

        #expect(trash.destination.relativePath == "Trash/Target.md")
        var publishedTrash: WorkspaceNoteSnapshot?
        for _ in 0..<3 where publishedTrash == nil {
            let event = try #require(await iterator.next())
            publishedTrash = event.snapshot.document(id: trash.destination)
        }
        #expect(publishedTrash?.lifecycle == .trash)
        #expect(
            try await handle.snapshot().document(id: VaultQualifiedNoteID(
                vaultID: fixture.targetID.vaultID,
                relativePath: "Trash/Set Aside/Target.md"
            )) == nil
        )
        await runtime.shutdown()
    }

    @Test("A captured lifecycle target rejects a reused path with another stable identity")
    func lifecycleTargetRejectsIdentityDrift() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projection = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projection.stableIdentity.resolvedID)
        let staleTarget = NoteLifecycleTarget(
            documentID: fixture.targetID,
            stableNoteID: UUID(),
            revision: source.fingerprint
        )

        do {
            _ = try await handle.documents.setAside(staleTarget)
            Issue.record("Expected the stale stable identity to reject the move.")
        } catch NoteIdentityRecoveryError.targetIdentityChanged(let path) {
            #expect(path == fixture.targetID.relativePath)
        }
        let unchanged = try await handle.documents.load(fixture.targetID)
        #expect(unchanged.relativePath == source.relativePath)
        #expect(unchanged.rawContent == source.rawContent)
        #expect(unchanged.fingerprint == source.fingerprint)

        let target = NoteLifecycleTarget(
            documentID: fixture.targetID,
            stableNoteID: stableID,
            revision: source.fingerprint
        )
        #expect(staleTarget.id != target.id)
        let commit = try await handle.documents.setAside(target).committedValue
        #expect(commit.destination.relativePath == "Set Aside/Target.md")
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
        let optional = try await handle.documents.create(DocumentCreationRequest(
            id: optionalID,
            title: "Optional"
        )).committedValue
        #expect(optional.rawContent == "# Optional\n")
        #expect(!optional.rawContent.contains("research_unit"))

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

        let created = try await handle.documents.create(DocumentCreationRequest(
            id: analysesID,
            title: "Analysis"
        )).committedValue
        #expect(created.rawContent == "# Analysis\n")

        let worksID = try #require(fixture.assignment.vault(for: .output)?.id)
        let untitledWork = try await handle.documents.create(DocumentCreationRequest(
            id: VaultQualifiedNoteID(vaultID: worksID, relativePath: "Untitled.md"),
            title: ""
        )).committedValue
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

    @Test("Folder creation is direct and folder moves preserve note identities and resolved links")
    func folderLifecycleTracksNotesRatherThanFolders() async throws {
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

        let trashCommit = try await handle.documents.moveFolderToTrash(
            inVault: vaultID,
            relativePath: "Sources"
        ).committedValue
        #expect(trashCommit.destinationFolder.rawValue == "Trash/Sources")
        let trashedFirstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/Sources/First.md"
        )
        let trashedSecondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/Sources/Nested/Second.md"
        )
        var publishedTrash: WorkspaceSnapshot?
        for _ in 0..<3 where publishedTrash == nil {
            let event = try #require(await iterator.next())
            if event.snapshot.document(id: trashedFirstID) != nil,
               event.snapshot.document(id: trashedSecondID) != nil {
                publishedTrash = event.snapshot
            }
        }
        let trashed = try #require(publishedTrash)
        #expect(trashed.document(id: trashedFirstID)?.stableIdentity.resolvedID == firstStableID)
        #expect(trashed.document(id: trashedSecondID)?.stableIdentity.resolvedID == secondStableID)
        #expect(trashed.document(id: trashedFirstID)?.lifecycle == .trash)
        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(
            "Trash/Sources/Nested/source.bin"
        )) == attachmentBytes)
        await runtime.shutdown()
    }

    @Test("Permanent deletion purges coordinated research and recovery state")
    func permanentDeletionCoordinatesOwnedState() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = try await handle.documents.load(fixture.targetID)
        let projected = try #require(
            try await handle.snapshot().document(id: fixture.targetID)
        )
        let stableID = try #require(projected.stableIdentity.resolvedID)
        let discussionPreparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .discuss,
                target: ResearchFunctionTarget(
                noteID: stableID,
                    note: fixture.targetID,
                    role: .analysis,
                    fingerprint: source.fingerprint,
                title: "Target",
                ),
                instruction: "Inspect this private note."
            )
        )
        let checkpoint = try await handle.research.createCheckpoint(
            name: "Contains Deleted Target",
            kind: .manual
        )

        let setAside = try await handle.documents.setAside(
            fixture.targetID,
            expectedRevision: source.fingerprint
        ).committedValue
        let setAsideDocument = try await handle.documents.load(setAside.destination)
        let trash = try await handle.documents.moveToTrash(
            setAside.destination,
            expectedRevision: setAsideDocument.fingerprint
        ).committedValue
        let trashDocument = try await handle.documents.load(trash.destination)

        let commit = try await handle.documents.deletePermanently(
            trash.destination,
            expectedRevision: trashDocument.fingerprint
        ).committedValue

        #expect(commit.noteID == stableID)
        #expect(commit.relativePath == "Trash/Target.md")
        #expect(commit.removedDialogueIDs.isEmpty)
        #expect(commit.invalidatedCheckpointIDs.contains(checkpoint.id))
        #expect(discussionPreparation.snapshot.checkpointID == nil)
        #expect(try await handle.research.activeDiscussions(noteID: stableID).isEmpty)
        #expect(try await handle.research.checkpoints().checkpoints.isEmpty)
        #expect(try await handle.snapshot().document(id: trash.destination) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.analysesURL
            .appendingPathComponent("Trash/Target.md").path))
        await runtime.shutdown()
    }

    @Test("Settle pins distinct exact Note revisions and applies per-Note retention")
    func settlePinsExactRevisions() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var document = try await handle.documents.load(fixture.targetID)
        let projected = try #require(try await handle.snapshot().document(id: fixture.targetID))
        let stableID = try #require(projected.stableIdentity.resolvedID)

        // Simulate a D-107-preexisting portable Settle that has no
        // machine-local pin, then backfill it by settling the same revision.
        _ = try await handle.writePortableSettlementWithoutPinForTesting(
            noteID: stableID,
            fingerprint: document.fingerprint,
            rationale: nil
        )
        #expect(try await handle.research.settledSnapshots(noteID: stableID).isEmpty)
        let updatedSettlement = try await handle.research.settle(
            fixture.targetID,
            expectedRevision: document.fingerprint,
            rationale: "The same revision remains useful."
        )
        #expect(updatedSettlement.rationale == "The same revision remains useful.")
        #expect(try await handle.research.settledSnapshots(noteID: stableID).count == 1)

        for index in 1...11 {
            document = try await handle.documents.save(
                fixture.targetID,
                changeSet: .exactContent("# Target\n\nRevision \(index).\n"),
                expectedRevision: document.fingerprint
            ).committedValue.document
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: nil
            )
        }
        #expect(try await handle.research.settledSnapshots(noteID: stableID).count == 12)

        let currentPolicy = try await handle.research.recoveryPolicy()
        #expect(currentPolicy.retention == .keep30)
        let preview = try await handle.research.prepareRecoveryPolicyChange(
            .keep10,
            expectedRevision: currentPolicy.revision
        )
        #expect(preview.snapshotIDsToRemove.count == 2)
        #expect(preview.affectedNoteCount == 1)
        let outcome = try await handle.research.applyRecoveryPolicyChange(preview)
        #expect(outcome.removedSnapshotCount == 2)
        #expect(outcome.snapshot.retention == .keep10)
        #expect(try await handle.research.settledSnapshots(noteID: stableID).count == 10)
        #expect(try await handle.research.checkpoints().checkpoints.isEmpty)
        await runtime.shutdown()

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        #expect(try await reopened.research.recoveryPolicy().retention == .keep10)
        #expect(try await reopened.research.settledSnapshots(noteID: stableID).count == 10)
        await reopenedRuntime.shutdown()
    }

    @Test("A Recovery policy preview cannot cross Triptychs")
    func recoveryPolicyPreviewIsTriptychBound() async throws {
        let firstFixture = try await LifecycleFixture.make()
        let secondFixture = try await LifecycleFixture.make()
        defer {
            firstFixture.remove()
            secondFixture.remove()
        }
        let firstRuntime = firstFixture.runtime()
        let secondRuntime = secondFixture.runtime()
        let first = try await firstRuntime.openWorkspace(id: firstFixture.assignment.id)
        let second = try await secondRuntime.openWorkspace(id: secondFixture.assignment.id)
        let firstPolicy = try await first.research.recoveryPolicy()
        let preview = try await first.research.prepareRecoveryPolicyChange(
            .keep50,
            expectedRevision: firstPolicy.revision
        )

        await #expect(throws: ResearchRecoveryPolicyError.stalePreview) {
            _ = try await second.research.applyRecoveryPolicyChange(preview)
        }
        #expect(try await second.research.recoveryPolicy().retention == .keep30)
        await firstRuntime.shutdown()
        await secondRuntime.shutdown()
    }

    @Test("An interrupted retention change resumes only its approved snapshot removals")
    func interruptedRecoveryPolicyChangeResumes() async throws {
        let fixture = try await LifecycleFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var document = try await handle.documents.load(fixture.targetID)
        for index in 0..<12 {
            if index > 0 {
                document = try await handle.documents.save(
                    fixture.targetID,
                    changeSet: .exactContent("# Target\n\nInterrupted revision \(index).\n"),
                    expectedRevision: document.fingerprint
                ).committedValue.document
            }
            _ = try await handle.research.settle(
                fixture.targetID,
                expectedRevision: document.fingerprint,
                rationale: nil
            )
        }
        let before = try await handle.research.settledSnapshots(noteID: nil)
        let policy = try await handle.research.recoveryPolicy()
        let preview = try await handle.research.prepareRecoveryPolicyChange(
            .keep10,
            expectedRevision: policy.revision
        )
        #expect(preview.snapshotIDsToRemove.count == 2)
        await runtime.shutdown()

        let policyDirectory = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-recovery-policy-v1", isDirectory: true)
        let policyURL = policyDirectory.appendingPathComponent("policy.json")
        let payload: [String: Any] = [
            "schema_version": 1,
            "triptych_id": fixture.assignment.id.uuidString,
            "retention": SettledSnapshotRetention.keep10.rawValue,
            "pending_snapshot_ids_to_remove": preview.snapshotIDsToRemove
                .map(\.uuidString).sorted(),
        ]
        try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: policyURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: policyURL.path
        )

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        let recoveredPolicy = try await reopened.research.recoveryPolicy()
        #expect(recoveredPolicy.retention == .keep10)
        let after = try await reopened.research.settledSnapshots(noteID: nil)
        #expect(Set(after.map(\.id)) == Set(before.map(\.id))
            .subtracting(preview.snapshotIDsToRemove))
        let readback = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: policyURL))
                as? [String: Any]
        )
        #expect((readback["pending_snapshot_ids_to_remove"] as? [String])?.isEmpty == true)
        await reopenedRuntime.shutdown()
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
                "recovery-v2/transactions/mutations",
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
        #expect(outcome.committedValue.recoveryCleanupWarning == nil)
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
    let id: UUID
    let relativePath: String
    let expected: DocumentFingerprint
    let candidate: DocumentFingerprint
    let createdAt: Date
    let retainedReason: String?
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
