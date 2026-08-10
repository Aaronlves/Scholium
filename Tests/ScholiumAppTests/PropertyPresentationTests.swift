import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Property presentation and editor boundary")
struct PropertyPresentationTests {
    @Test("Current descriptors are unique, ordered, and resolve to Core")
    func descriptorsResolveToCoreContracts() {
        for profile in PropertyPresentationCatalog.currentProfiles {
            let presentations = PropertyPresentationCatalog.presentations(for: profile)
            #expect(presentations.count == Set(presentations.map(\.key)).count)
            #expect(
                Set(presentations.map(\.key))
                    == Set(PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey))
            )
            #expect(presentations == presentations.sorted {
                ($0.group.order, $0.order) < ($1.group.order, $1.order)
            })
            for presentation in presentations {
                #expect(PropertyPresentationCatalog.contract(
                    for: presentation,
                    in: profile
                ) != nil)
            }
        }
    }

    @Test("Controlled source type validation is returned by Core")
    func coreIssuesAreReturned() throws {
        let source = "---\ntype: book\ncustom: untouched\n---\nBody\n"
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "test.md", rawContent: source),
            role: .sourceCorpus
        )
        let model = PropertyEditorModel(note: note)
        let type = try #require(model.presentFields.first { $0.key == "type" })
        let invalid = model.updating(note.frontmatter, field: type, text: "web_page")

        #expect(model.validationIssues(
            proposedFrontmatter: invalid,
            changedKeys: ["type"]
        ).map(\.code) == [.valueNotAllowed])
    }

    @Test("Targeted semantic edit preserves unrelated exact bytes")
    func targetedEditPreservesCustomBytes() throws {
        let source = "\u{FEFF}---\r\n# keep\r\ntype: book\r\ncustom: 'exact'\r\n---\r\nBody\r\n"
        let document = NoteDocument(relativePath: "current.md", rawContent: source)
        let note = propertyWorkspaceLocation(document, role: .sourceCorpus)
        let model = PropertyEditorModel(note: note)
        let type = try #require(model.presentFields.first { $0.key == "type" })
        let proposed = model.updating(note.frontmatter, field: type, text: "journal_article")
        let edits = PropertyEditorModel.frontmatterEdits(from: note.frontmatter, to: proposed)
        let result = try document.applying(.frontmatter(edits), timestampKey: nil)

        #expect(result.hasPrefix("\u{FEFF}---\r\n"))
        #expect(result.contains("# keep\r\n"))
        #expect(result.contains("custom: 'exact'\r\n"))
        #expect(result.contains("type: journal_article\r\n"))
        #expect(NoteDocument(relativePath: "current.md", rawContent: result).body == document.body)
    }

    @Test("Malformed frontmatter fails closed through Core")
    func malformedFrontmatterFailsClosed() {
        let source = "---\ntags: [one, two\n---\nBody\n"
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "malformed.md", rawContent: source),
            role: .sourceCorpus
        )
        let issues = PropertyEditorModel(note: note).validationIssues(
            proposedFrontmatter: [:],
            changedKeys: ["title"]
        )
        #expect(issues.map(\.code) == [.malformedFrontmatter])
        #expect(note.rawContent == source)
    }
}

private func propertyWorkspaceLocation(
    _ document: NoteDocument,
    role: VaultRole
) -> WindowDocumentLocation {
    .workspace(WorkspaceNoteSnapshot(
        id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: document.relativePath),
        vaultRole: role,
        stableIdentity: .unresolved,
        document: document,
        fileMetadata: WorkspaceFileMetadata(
            byteCount: document.sourceBytes.count,
            creationDate: nil,
            modificationDate: nil
        ),
        lifecycle: .active,
        graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0),
        headings: []
    ))
}
