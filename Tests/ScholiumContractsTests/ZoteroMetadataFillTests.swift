import Foundation
import ScholiumContracts
import Testing

@Suite("Zotero Metadata fill planning")
struct ZoteroMetadataFillTests {
    @Test("Only absent applicable managed fields are proposed and authored fields never enter the plan")
    func absentApplicableFieldsOnly() throws {
        let noteID = UUID()
        let metadata = NoteMetadataSnapshot(
            record: NoteMetadataRecord(noteID: noteID, fields: [
                "type": .string("book"),
                "title": .string("Researcher title"),
            ]),
            revision: DocumentFingerprint(content: "metadata-v1")
        )
        let source = ZoteroExactItemRead(
            library: ZoteroLibraryMetadata(identity: .user, name: "My Library"),
            item: ZoteroItemMetadata(
                key: "ITEM0001",
                itemType: "journalArticle",
                title: "Zotero title",
                creators: [
                    ZoteroCreatorMetadata(
                        role: "author",
                        name: "Philippa Foot",
                        givenName: "Philippa",
                        familyName: "Foot"
                    ),
                    ZoteroCreatorMetadata(
                        role: "editor",
                        name: "Literal Editor",
                        literalName: "Literal Editor"
                    ),
                ],
                date: "1967",
                language: "en",
                containerTitle: "Oxford Review",
                volume: "1",
                issue: "2",
                pages: "1–18",
                doi: "10.1000/example",
                abstract: "Must not become summary.",
                tags: ["must-not-become-keywords"],
                publisher: "Oxford University Press"
            ),
            serverID: "zotero-server-a"
        )
        let plan = try ZoteroMetadataFillPlanner.plan(
            noteID: noteID,
            sourceRevision: DocumentFingerprint(content: "source-v1"),
            bindingSnapshot: AnalysisZoteroBindingsSnapshot(
                bindings: [],
                revision: DocumentFingerprint(content: "bindings-v1")
            ),
            metadataSnapshot: metadata,
            source: source
        )

        #expect(plan.retainedConflicts.map(\.key) == ["type", "title"])
        #expect(plan.resultFields["type"] == .string("book"))
        #expect(plan.resultFields["title"] == .string("Researcher title"))
        #expect(plan.resultFields["authors"] == .array([
            .object(["given": .string("Philippa"), "family": .string("Foot")]),
        ]))
        #expect(plan.resultFields["editors"] == .array([
            .object(["literal": .string("Literal Editor")]),
        ]))
        #expect(plan.resultFields["issue"] == nil)
        #expect(plan.resultFields["container_title"] == nil)
        #expect(plan.resultFields["summary"] == nil)
        #expect(plan.resultFields["keywords"] == nil)
        #expect(NoteMetadataContractCatalog.validate(
            fields: plan.resultFields,
            profile: .analysis
        ).isEmpty)
    }
}
