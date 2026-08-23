import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Application Zotero Link and Fill")
struct ZoteroLinkAndFillOperationsTests {
    @Test("An exact reviewed item links and fills empty Metadata without touching Markdown")
    func linkAndFill() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let exactSource = "---\nsummary: Researcher summary\nkeywords: [ethics, action]\ncustom: keep\n---\n# Agency\n\nFreedom enables action.\n"
        try Data(exactSource.utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Agency.md")
        )
        let item = Self.itemData
        let script = LinkAndFillRequestScript(steps: [
            .init(status: 200, data: item, serverID: "server-a"),
            .init(status: 200, data: item, serverID: "server-a"),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: {
            try await script.load($0)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let sourceBefore = try await handle.documents.load(fixture.analysisNoteID)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        _ = try await handle.documents.saveMetadata(
            fixture.analysisNoteID,
            fields: ["title": .string("Researcher title")],
            expectedRevision: nil
        )

        let plan = try await handle.zoteroBindings.prepareZoteroLinkAndFill(
            noteID: noteID,
            library: ZoteroLibraryMetadata(identity: .user, name: "My Library"),
            itemKey: "item0001"
        )
        #expect(plan.source.item.key == "ITEM0001")
        #expect(plan.retainedConflicts.map(\.key) == ["title"])
        #expect(plan.fieldsToFill.map(\.key).contains("authors"))
        #expect(plan.resultFields["summary"] == nil)
        #expect(plan.resultFields["keywords"] == nil)

        let result = try await handle.zoteroBindings.commitZoteroMetadataPlan(plan)
        #expect(result.retainedConflictKeys == ["title"])
        let metadata = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: noteID)
        )
        #expect(metadata.record.fields["type"] == .string("journal_article"))
        #expect(metadata.record.fields["title"] == .string("Researcher title"))
        #expect(metadata.record.fields["doi"] == .string("10.1000/example"))
        #expect(metadata.record.fields["authors"] == .array([
            .object(["given": .string("Philippa"), "family": .string("Foot")]),
        ]))
        #expect(sourceBefore.rawContent == exactSource)
        #expect(try await handle.documents.load(fixture.analysisNoteID).rawContent
            == exactSource)
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: noteID)?.itemKey == "ITEM0001")
        #expect(await script.paths() == [
            "/api/users/0/items/ITEM0001",
            "/api/users/0/items/ITEM0001",
        ])
        await runtime.shutdown()
    }

    @Test("A bound-item refresh reads only that exact item and updates its reviewed mapped fields")
    func refreshBoundItemOnly() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let sourceBefore = try Data(
            contentsOf: fixture.analysesURL.appendingPathComponent("Agency.md")
        )
        let script = LinkAndFillRequestScript(steps: [
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: {
            try await script.load($0)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        _ = try await handle.documents.saveMetadata(
            fixture.analysisNoteID,
            fields: [
                "type": .string("journal_article"),
                "title": .string("Earlier title"),
                "doi": .string("10.1000/earlier"),
                "language": .string("fr"),
            ],
            expectedRevision: nil
        )
        let bindings = try await handle.services.controlStore.zoteroBindings()
        _ = try await handle.services.controlStore.setZoteroBinding(
            AnalysisZoteroBinding(
                noteID: noteID,
                library: .user,
                itemKey: "ITEM0001"
            ),
            expectedRevision: bindings.revision
        )

        let plan = try await handle.zoteroBindings.prepareZoteroMetadataRefresh(
            noteID: noteID
        )
        #expect(plan.fieldsToUpdate.map(\.key) == ["title", "doi"])
        #expect(plan.fieldsToFill.map(\.key).contains("authors"))

        let result = try await handle.zoteroBindings.commitZoteroMetadataPlan(plan)
        #expect(result.updatedKeys == ["title", "doi"])
        let metadata = try #require(
            try await handle.services.controlStore.noteMetadata(noteID: noteID)
        )
        #expect(metadata.record.fields["title"] == .string("Zotero title"))
        #expect(metadata.record.fields["doi"] == .string("10.1000/example"))
        #expect(metadata.record.fields["language"] == .string("fr"))
        #expect(try Data(
            contentsOf: fixture.analysesURL.appendingPathComponent("Agency.md")
        ) == sourceBefore)
        #expect(await script.paths() == [
            "/api/users/0/items/ITEM0001",
            "/api/users/0/items/ITEM0001",
        ])
        await runtime.shutdown()
    }

    @Test("A different Zotero server at commit changes neither binding nor Metadata")
    func serverIdentitySubstitutionFailsClosed() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let script = LinkAndFillRequestScript(steps: [
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
            .init(status: 200, data: Self.itemData, serverID: "server-b"),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: {
            try await script.load($0)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        let plan = try await handle.zoteroBindings.prepareZoteroLinkAndFill(
            noteID: noteID,
            library: ZoteroLibraryMetadata(identity: .user, name: "My Library"),
            itemKey: "ITEM0001"
        )

        await #expect(throws: ZoteroMetadataOperationError.self) {
            _ = try await handle.zoteroBindings.commitZoteroMetadataPlan(plan)
        }
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: noteID) == nil)
        #expect(try await handle.services.controlStore.noteMetadata(noteID: noteID) == nil)
        await runtime.shutdown()
    }

    @Test("A changed Metadata revision is rejected before the Zotero binding is written")
    func metadataRevisionConflictPrecedesBinding() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let script = LinkAndFillRequestScript(steps: [
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: {
            try await script.load($0)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        let initial = try await handle.documents.saveMetadata(
            fixture.analysisNoteID,
            fields: ["title": .string("Initial title")],
            expectedRevision: nil
        ).committedValue
        let plan = try await handle.zoteroBindings.prepareZoteroLinkAndFill(
            noteID: noteID,
            library: ZoteroLibraryMetadata(identity: .user, name: "My Library"),
            itemKey: "ITEM0001"
        )
        let concurrent = try await handle.documents.saveMetadata(
            fixture.analysisNoteID,
            fields: ["title": .string("Concurrent researcher title")],
            expectedRevision: initial.revision
        ).committedValue

        await #expect(throws: NoteMetadataError.self) {
            _ = try await handle.zoteroBindings.commitZoteroMetadataPlan(plan)
        }
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: noteID) == nil)
        #expect(try await handle.services.controlStore.noteMetadata(noteID: noteID)
            == concurrent)
        await runtime.shutdown()
    }

    @Test("A changed Analysis source is rejected before the Zotero binding is written")
    func analysisSourceRevisionConflictPrecedesBinding() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let script = LinkAndFillRequestScript(steps: [
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
            .init(status: 200, data: Self.itemData, serverID: "server-a"),
        ])
        let runtime = fixture.runtime(zotero: ZoteroOperations(requestLoader: {
            try await script.load($0)
        }))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        let plan = try await handle.zoteroBindings.prepareZoteroLinkAndFill(
            noteID: noteID,
            library: ZoteroLibraryMetadata(identity: .user, name: "My Library"),
            itemKey: "ITEM0001"
        )
        try Data("# Changed outside Scholium\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Agency.md")
        )

        await #expect(throws: ZoteroMetadataOperationError.self) {
            _ = try await handle.zoteroBindings.commitZoteroMetadataPlan(plan)
        }
        #expect(try await handle.services.controlStore.zoteroBindings()
            .binding(for: noteID) == nil)
        #expect(try await handle.services.controlStore.noteMetadata(noteID: noteID) == nil)
        await runtime.shutdown()
    }

    private static let itemData = Data(#"""
    {
      "key": "ITEM0001",
      "data": {
        "key": "ITEM0001",
        "itemType": "journalArticle",
        "title": "Zotero title",
        "creators": [
          {"creatorType":"author","firstName":"Philippa","lastName":"Foot"}
        ],
        "date": "1967",
        "publicationTitle": "Oxford Review",
        "volume": "1",
        "issue": "2",
        "pages": "1-18",
        "DOI": "10.1000/example",
        "abstractNote": "Must not become summary.",
        "tags": [{"tag":"must-not-become-keywords"}]
      }
    }
    """#.utf8)
}

private actor LinkAndFillRequestScript {
    struct Step: Sendable {
        let status: Int
        let data: Data
        let serverID: String?

        init(status: Int, data: Data, serverID: String? = nil) {
            self.status = status
            self.data = data
            self.serverID = serverID
        }
    }

    private var steps: [Step]
    private var requestedPaths: [String] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, !steps.isEmpty else {
            throw URLError(.badServerResponse)
        }
        requestedPaths.append(url.path)
        let step = steps.removeFirst()
        let headers = step.serverID.map { ["Zotero-Server-ID": $0] }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: step.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (step.data, response)
    }

    func paths() -> [String] { requestedPaths }
}

private extension ApplicationFixture {
    func runtime(zotero: ZoteroOperations) -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL,
            assignments: [assignment]
        )), zotero: zotero)
    }
}
