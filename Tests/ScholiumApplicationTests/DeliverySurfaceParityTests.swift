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
            workspaceRegistryStorageURL: fixture.registryStorageURL
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
                  completion: incomplete
                ---
                \(original.document.rawContent)
                """),
            expectedRevision: original.fingerprint
        )
        _ = try await appHandle.research.settle(
            fixture.analysisNoteID,
            expectedRevision: declared.document.fingerprint,
            rationale: "Fixture settlement visible to every delivery surface."
        )
        _ = try await appHandle.research.prepareFunction(
            ResearchFunctionRequest(
                function: .discuss,
                target: ResearchFunctionTarget(
                    noteID: try #require(original.stableIdentity.resolvedID),
                    note: fixture.analysisNoteID,
                    role: .analysis,
                    fingerprint: declared.document.fingerprint,
                    title: "Agency"
                ),
                instruction: "Inspect the fixture argument."
            )
        )
        let appSnapshot = try await appHandle.snapshot()
        let appHits = try await appHandle.discovery.search(SearchRequest(
            query: "freedom",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
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
        let cliHits = try await cliHandle.discovery.search(SearchRequest(
            query: "freedom",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        let cliDocument = try #require(cliSnapshot.document(id: fixture.analysisNoteID))
        let cliMetadataIssues = PropertyContractCatalog.validate(
            cliDocument.document,
            profile: .analysis
        )
        let cliResearch = try await cliHandle.research.snapshot()

        #expect(cliSnapshot.discovery.catalog.notes == appSnapshot.discovery.catalog.notes)
        #expect(cliSnapshot.discovery.catalog.attention == appSnapshot.discovery.catalog.attention)
        // Each delivery request owns a distinct cancellation/staleness identity,
        // while the shared Application response content must remain identical.
        #expect(cliHits.contractVersion == appHits.contractVersion)
        #expect(cliHits.scope == appHits.scope)
        #expect(cliHits.freshnessToken == appHits.freshnessToken)
        #expect(cliHits.availability == appHits.availability)
        #expect(cliHits.results == appHits.results)
        #expect(cliHits.hasMore == appHits.hasMore)
        #expect(cliHits.diagnostics == appHits.diagnostics)
        #expect(cliMetadataIssues == appMetadataIssues)
        #expect(cliResearch.activityEvents == appResearch.activityEvents)
        #expect(cliResearch.settlements == appResearch.settlements)
        #expect(cliResearch.activeDiscussions == appResearch.activeDiscussions)
        #expect(cliResearch.finishedResearchRecords == appResearch.finishedResearchRecords)
        #expect(cliResearch.critiques == appResearch.critiques)

        await cliRuntime.shutdown()
    }
}
