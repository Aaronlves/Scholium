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

        let notYetID = VaultQualifiedNoteID(
            vaultID: fixture.targetID.vaultID,
            relativePath: "New/Not Yet.md"
        )
        let notYet = try await handle.documents.create(DocumentCreationRequest(
            id: notYetID,
            title: "Not Yet",
            analysisResearchStatus: .notYet
        ))
        #expect(notYet.rawContent == "# Not Yet\n")
        #expect(!notYet.rawContent.contains("research_unit"))

        let settlement = try await handle.research.settle(
            notYetID,
            expectedRevision: notYet.fingerprint,
            rationale: "Settlement is independent of legacy Review status."
        )
        #expect(settlement.fingerprint == notYet.fingerprint)

        let declared = try await handle.documents.save(
            notYetID,
            changeSet: .exactContent("""
                ---
                research_unit:
                  scope: "One bounded source"
                ---
                # Not Yet

                """),
            expectedRevision: notYet.fingerprint
        )
        #expect(declared.document.fingerprint != settlement.fingerprint)

        let created = try await handle.documents.create(DocumentCreationRequest(
            id: analysesID,
            title: "Analysis",
            analysisResearchStatus: .declareNow(
                scope: "A source with \"quoted\" language",
                limitations: ["First limitation", "Second limitation"]
            )
        ))
        #expect(created.rawContent == """
            ---
            research_unit:
              scope: "A source with \\"quoted\\" language"
              limitations:
                - "First limitation"
                - "Second limitation"
            ---
            # Analysis

            """)

        let worksID = try #require(fixture.assignment.vault(for: .output)?.id)
        let untitledWork = try await handle.documents.create(DocumentCreationRequest(
            id: VaultQualifiedNoteID(vaultID: worksID, relativePath: "Untitled.md"),
            title: ""
        ))
        #expect(untitledWork.rawContent.isEmpty)
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
        let dialogue = try await handle.research.prepareFunction(
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
        #expect(!commit.removedHumanReview)
        #expect(commit.removedDialogueIDs == [dialogue.runID])
        #expect(commit.invalidatedCheckpointIDs.contains(checkpoint.id))
        #expect(dialogue.snapshot.checkpointID == nil)
        #expect(try await handle.research.discussionHistory(noteID: stableID).isEmpty)
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
