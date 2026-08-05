import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Property presentation and editor boundary")
struct PropertyPresentationTests {
    @Test("Current profiles have unique descriptor keys and positions")
    func descriptorUniqueness() {
        for profile in PropertyPresentationCatalog.currentProfiles {
            let presentations = PropertyPresentationCatalog.presentations(for: profile)
            #expect(presentations.count == Set(presentations.map(\.key)).count)

            let positions = presentations.map { "\($0.group.rawValue):\($0.order)" }
            #expect(positions.count == Set(positions).count)
            #expect(presentations == presentations.sorted {
                ($0.group.order, $0.order) < ($1.group.order, $1.order)
            })
        }
    }

    @Test("Every current descriptor resolves to exactly one Core contract")
    func descriptorsResolveToCoreContracts() {
        for profile in PropertyPresentationCatalog.currentProfiles {
            let presentations = PropertyPresentationCatalog.presentations(for: profile)
            let contracts = PropertyContractCatalog.contracts(for: profile).filter {
                $0.ownership == .researcher
            }

            #expect(Set(presentations.map(\.key)) == Set(contracts.map(\.canonicalKey)))
            for presentation in presentations {
                let matches = contracts.filter { $0.canonicalKey == presentation.key }
                #expect(matches.count == 1)
                #expect(
                    PropertyPresentationCatalog.contract(
                        for: presentation,
                        in: profile
                    ) == matches.first
                )
            }
        }
    }

    @Test("Presentation descriptors contain interface metadata only")
    func presentationStoresOnlyInterfaceMetadata() throws {
        let presentation = try #require(
            PropertyPresentationCatalog.presentations(for: .analysis).first
        )
        let storedProperties = Set(
            Mirror(reflecting: presentation).children.compactMap(\.label)
        )
        #expect(storedProperties == Set([
            "key", "label", "help", "group", "order", "controlStyle",
        ]))
    }

    @Test("Editor returns Core validation issues")
    func coreIssuesAreReturned() throws {
        let source = """
        ---
        title: Test
        authors: [A]
        year: 2026
        research_unit:
          completion: "6/11"
        status: draft
        ---
        Body
        """
        let note = workspaceLocation(
            NoteDocument(relativePath: "test.md", rawContent: source),
            role: .sourceCorpus
        )
        let model = PropertyEditorModel(note: note)

        #expect(!model.allFields.contains { $0.key == "status" })

        let type = try #require(model.availableFields.first { $0.key == "type" })
        let invalidType = model.updating(note.frontmatter, field: type, text: "web_page")
        #expect(model.validationIssues(
            proposedFrontmatter: invalidType,
            researchUnitEdit: nil,
            changedKeys: ["type"]
        ).map(\.code).contains(.valueNotAllowed))

        let importance = try #require(model.availableFields.first { $0.key == "debate_importance" })
        let outOfRange = model.updating(note.frontmatter, field: importance, text: "11")
        let rangeIssues = model.validationIssues(
            proposedFrontmatter: outOfRange,
            researchUnitEdit: nil,
            changedKeys: ["debate_importance"]
        )
        #expect(rangeIssues.map(\.code).contains(.debateImportanceOutOfRange))
        #expect(rangeIssues.map(\.code).contains(.pairedPropertyMissing))
    }

    @Test("Semantic edit preserves custom YAML, comments, BOM, CRLF, and body bytes")
    func targetedEditPreservesCustomBytes() throws {
        let source = "\u{FEFF}---\r\n# keep this comment\r\nstatus: draft\r\ntype: book\r\nunknown:\r\n  nested: 'exact value'\r\n---\r\n# Body\r\n\r\nKeep me.\r\n"
        let document = NoteDocument(relativePath: "current.md", rawContent: source)
        let note = workspaceLocation(document, role: .sourceCorpus)
        let model = PropertyEditorModel(note: note)
        let type = try #require(model.presentFields.first { $0.key == "type" })

        let proposed = model.updating(note.frontmatter, field: type, text: "journal_article")
        let edits = PropertyEditorModel.frontmatterEdits(
            from: note.frontmatter,
            to: proposed
        )
        let result = try document.applying(.frontmatter(edits), timestampKey: nil)

        #expect(result.hasPrefix("\u{FEFF}---\r\n"))
        #expect(result.contains("# keep this comment\r\n"))
        #expect(result.contains("unknown:\r\n  nested: 'exact value'\r\n"))
        #expect(result.contains("status: draft\r\n"))
        #expect(result.contains("type: journal_article\r\n"))
        #expect(NoteDocument(relativePath: "current.md", rawContent: result).body == document.body)
    }

    @Test("Removing one Research Unit member preserves the other members")
    func researchUnitMembersAreIndependent() throws {
        let source = """
        ---
        research_unit:
          completion: "6/11"
          limitations:
            - Missing appendix
        unknown: untouched
        ---
        Body
        """
        let document = NoteDocument(relativePath: "analysis.md", rawContent: source)
        let edit = ResearchUnitEdit.set(
            completion: nil,
            scope: nil,
            limitations: ["Missing appendix"]
        )
        let result = try document.applying(
            .frontmatter(["research_unit": edit.coreValue]),
            timestampKey: nil
        )
        let reparsed = NoteDocument(relativePath: "analysis.md", rawContent: result)
        let declaration = ResearchUnitDeclaration(
            frontmatter: reparsed.parsedFrontmatter,
            profile: .analysis
        )

        #expect(declaration.completion == nil)
        #expect(declaration.limitations == ["Missing appendix"])
        #expect(declaration.state == .declared)
        #expect(result.contains("unknown: untouched"))
        #expect(result.contains("Body"))
    }

    @Test("Default About profiles keep role-aware semantic order")
    func defaultAboutProfiles() {
        #expect(AboutProfileCatalog.entries(for: .analysis, visibleFields: nil) == [
            .completion,
            .limitations,
            .property("summary"),
            .property("authors"),
            .property("year"),
            .property("type"),
            .sourceBasis,
        ])
        #expect(AboutProfileCatalog.entries(for: .topicMarkdown, visibleFields: nil) == [
            .scope(label: "Scope"),
            .limitations,
            .property("summary"),
            .property("aliases"),
        ])
        #expect(AboutProfileCatalog.entries(for: .draftProject, visibleFields: nil) == [
            .scope(label: "Research Scope"),
            .limitations,
            .property("summary"),
            .property("kind"),
            .property("authors"),
            .property("venue"),
        ])
        #expect(!AboutProfileCatalog.entries(
            for: .analysis,
            visibleFields: ["title", "zotero_item_key", "authors"]
        ).contains(.property("title")))
        #expect(!AboutProfileCatalog.entries(
            for: .analysis,
            visibleFields: ["title", "zotero_item_key", "authors"]
        ).contains(.property("zotero_item_key")))
    }

    @Test("Malformed frontmatter fails closed through Core")
    func malformedFrontmatterFailsClosed() {
        let source = "---\ntags: [one, two\n---\nBody\n"
        let note = workspaceLocation(
            NoteDocument(relativePath: "malformed.md", rawContent: source),
            role: .sourceCorpus
        )
        let issues = PropertyEditorModel(note: note).validationIssues(
            proposedFrontmatter: [:],
            researchUnitEdit: nil,
            changedKeys: ["title"]
        )
        #expect(issues.map(\.code) == [.malformedFrontmatter])
        #expect(note.rawContent == source)
        #expect(note.body == source)
    }
}

private func workspaceLocation(
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
        graphCounts: WorkspaceGraphCounts(
            incoming: 0,
            outgoing: 0,
            broken: 0,
            ambiguous: 0
        )
    ))
}
