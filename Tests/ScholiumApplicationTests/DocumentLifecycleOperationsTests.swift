import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Application document lifecycle operations")
struct DocumentLifecycleOperationsTests {
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
        )

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

        let setAside = try await handle.documents.setAside(
            fixture.targetID,
            expectedRevision: source.fingerprint
        )
        let setAsideID = setAside.destination
        #expect(setAsideID.relativePath == "Set Aside/Target.md")
        let setAsideDocument = try await handle.documents.load(setAsideID)

        let trash = try await handle.documents.moveToTrash(
            setAsideID,
            expectedRevision: setAsideDocument.fingerprint
        )

        #expect(trash.destination.relativePath == "Trash/Target.md")
        #expect(
            try await handle.snapshot().document(id: trash.destination)?.lifecycle == .trash
        )
        #expect(
            try await handle.snapshot().document(id: VaultQualifiedNoteID(
                vaultID: fixture.targetID.vaultID,
                relativePath: "Trash/Set Aside/Target.md"
            )) == nil
        )
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
        )

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
        ))
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
        )
        #expect(declared.document.fingerprint != settlement.fingerprint)

        let created = try await handle.documents.create(DocumentCreationRequest(
            id: analysesID,
            title: "Analysis"
        ))
        #expect(created.rawContent == "# Analysis\n")

        let worksID = try #require(fixture.assignment.vault(for: .output)?.id)
        let untitledWork = try await handle.documents.create(DocumentCreationRequest(
            id: VaultQualifiedNoteID(vaultID: worksID, relativePath: "Untitled.md"),
            title: ""
        ))
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

        let created = try await handle.documents.createUntitledNote(
            inVault: vaultID,
            folderRelativePath: "Sources"
        )

        #expect(created.relativePath == "Sources/Untitled 3.md")
        #expect(created.rawContent.isEmpty)
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
        )
        let secondFolder = try await handle.documents.createUntitledFolder(
            inVault: vaultID,
            parentRelativePath: nil
        )
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
        )
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
        let commit = try await handle.documents.moveFolder(
            inVault: vaultID,
            from: "Untitled Folder",
            to: "Sources"
        )

        #expect(commit.noteMoves.count == 2)
        #expect(commit.rewrites.count == 2)
        let movedFirstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/First.md"
        )
        let movedSecondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Sources/Nested/Second.md"
        )
        let after = try await handle.snapshot()
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
        )
        #expect(trashCommit.destinationFolder.rawValue == "Trash/Sources")
        let trashedFirstID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/Sources/First.md"
        )
        let trashedSecondID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Trash/Sources/Nested/Second.md"
        )
        let trashed = try await handle.snapshot()
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
        let discussionPreparation = try await handle.research.prepareFunction(
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
        )
        let setAsideDocument = try await handle.documents.load(setAside.destination)
        let trash = try await handle.documents.moveToTrash(
            setAside.destination,
            expectedRevision: setAsideDocument.fingerprint
        )
        let trashDocument = try await handle.documents.load(trash.destination)

        let commit = try await handle.documents.deletePermanently(
            trash.destination,
            expectedRevision: trashDocument.fingerprint
        )

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
