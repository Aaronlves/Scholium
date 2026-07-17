import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("GUI and CLI application parity", .serialized)
struct DeliverySurfaceParityTests {
    @Test("Live GUI and snapshot CLI consumers see equivalent workspace results")
    func liveAndSnapshotParity() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }

        let appRuntime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL,
            refreshInterval: .seconds(30)
        )))
        let appHandle = try await appRuntime.openWorkspace(id: fixture.assignment.id)
        let original = try #require(
            try await appHandle.snapshot().document(id: fixture.analysisNoteID)
        )
        let declared = try await appHandle.documents.save(
            fixture.analysisNoteID,
            changeSet: .exactContent("""
                ---
                research_unit:
                  scope: "The bounded fixture source"
                ---
                \(original.document.rawContent)
                """),
            expectedRevision: original.fingerprint
        )
        _ = try await appHandle.research.completeHumanReview(
            for: fixture.analysisNoteID,
            expectedRevision: declared.document.fingerprint,
            qualification: .qualified,
            reviewNote: "Fixture review visible to every delivery surface."
        )
        let stableNoteID = try #require(original.stableIdentity.resolvedID)
        _ = try await appHandle.research.createDialogue(
            instruction: "Inspect the fixture argument.",
            selectedNotes: [DialogueNoteReference(
                noteID: stableNoteID,
                vaultID: fixture.analysisNoteID.vaultID,
                vaultName: "Analyses",
                title: "Agency",
                relativePath: fixture.analysisNoteID.relativePath,
                fingerprint: declared.document.fingerprint
            )],
            includedCommentIDs: [],
            requestedDestination: nil,
            responseProfile: nil
        )
        let appSnapshot = try await appHandle.snapshot()
        let appHits = try await appHandle.discovery.search(
            SearchQuery("freedom"),
            scope: .workspace
        )
        let appDocument = try #require(appSnapshot.document(id: fixture.analysisNoteID))
        let appMetadataIssues = PropertyContractCatalog.validate(
            appDocument.document,
            profile: .analysis
        )
        let appResearch = try await appHandle.research.snapshot()
        await appRuntime.shutdown()

        let cliRuntime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let cliHandle = try await cliRuntime.openWorkspace(id: fixture.assignment.id)
        let cliSnapshot = try await cliHandle.snapshot()
        let cliHits = try await cliHandle.discovery.search(
            SearchQuery("freedom"),
            scope: .workspace
        )
        let cliDocument = try #require(cliSnapshot.document(id: fixture.analysisNoteID))
        let cliMetadataIssues = PropertyContractCatalog.validate(
            cliDocument.document,
            profile: .analysis
        )
        let cliResearch = try await cliHandle.research.snapshot()

        #expect(cliSnapshot.discovery.catalog.notes == appSnapshot.discovery.catalog.notes)
        #expect(cliSnapshot.discovery.catalog.attention == appSnapshot.discovery.catalog.attention)
        #expect(cliHits == appHits)
        #expect(cliMetadataIssues == appMetadataIssues)
        #expect(cliResearch.humanReviews == appResearch.humanReviews)
        #expect(cliResearch.dialogues == appResearch.dialogues)
        #expect(cliResearch.critiques == appResearch.critiques)

        await cliRuntime.shutdown()
    }
}
