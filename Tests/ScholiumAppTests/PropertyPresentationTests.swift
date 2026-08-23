import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Portable metadata presentation and editor boundary")
struct PropertyPresentationTests {
    @Test("Descriptors combine managed fields with the two authored YAML fields")
    func descriptorsResolveToOwningContracts() {
        for profile in PropertyPresentationCatalog.currentProfiles {
            let presentations = PropertyPresentationCatalog.presentations(
                for: profile,
                catalog: .builtIn
            )
            let expected = NoteMetadataCatalog.builtIn.contracts(for: profile)
                + PropertyContractCatalog.contracts(for: profile)
            #expect(presentations.count == Set(presentations.map(\.key)).count)
            #expect(Set(presentations.map(\.key)) == Set(expected.map(\.canonicalKey)))
            #expect(presentations == presentations.sorted {
                ($0.group.order, $0.order) < ($1.group.order, $1.order)
            })
        }
    }

    @Test("Metadata editor reads the portable record and ignores same-named YAML")
    func editorDoesNotPromoteYAML() {
        let source = "---\ntitle: YAML title\nauthors: [Legacy]\nsummary: Authored summary\n---\n# Heading\n"
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "paper.md", rawContent: source),
            role: .sourceCorpus,
            metadataFields: [
                "type": .string("book"),
                "title": .string("Managed title"),
            ]
        )
        let model = PropertyEditorModel(note: note, metadataCatalog: .builtIn)

        #expect(model.presentFields.map(\.key).contains("type"))
        #expect(model.presentFields.map(\.key).contains("title"))
        #expect(!model.presentFields.map(\.key).contains("authors"))
        #expect(!model.presentFields.map(\.key).contains("summary"))
        #expect(note.managedMetadataValue(named: "title") == .string("Managed title"))
        #expect(note.authoredYAMLValue(named: "title") == nil)
        #expect(note.rawContent == source)
    }

    @Test("Managed choice validation is returned by Contracts")
    func managedValidation() throws {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "paper.md", rawContent: "Body\n"),
            role: .sourceCorpus,
            metadataFields: ["type": .string("book")]
        )
        let model = PropertyEditorModel(note: note, metadataCatalog: .builtIn)
        let type = try #require(model.presentFields.first { $0.key == "type" })
        let invalid = model.updating(
            note.managedMetadataFields,
            field: type,
            text: "web_page"
        )
        #expect(model.validationIssues(
            proposedFields: invalid,
            changedKeys: ["type"]
        ).map(\.code) == [.valueNotAllowed])
    }

    @Test("Malformed YAML does not block an independent metadata edit")
    func malformedYAMLIsIndependent() throws {
        let source = "---\nkeywords: [one, two\n---\nBody\n"
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "paper.md", rawContent: source),
            role: .sourceCorpus,
            metadataFields: ["type": .string("book")]
        )
        let model = PropertyEditorModel(note: note, metadataCatalog: .builtIn)
        let title = try #require(model.availableFields.first { $0.key == "title" })
        let proposed = model.updating(
            note.managedMetadataFields,
            field: title,
            text: "Managed title"
        )
        #expect(model.validationIssues(
            proposedFields: proposed,
            changedKeys: ["title"]
        ).isEmpty)
        #expect(note.rawContent == source)
    }

    @Test("Analysis chooser follows the managed Source Type profile")
    func analysisChooserUsesSourceTypeProfile() {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "article.md", rawContent: "Body\n"),
            role: .sourceCorpus,
            metadataFields: ["type": .string("journal_article")]
        )
        let model = PropertyEditorModel(note: note, metadataCatalog: .builtIn)
        let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: .journalArticle)

        #expect(Set(model.availableFields.map(\.key))
            == Set(sourceProfile.applicableFields).subtracting(["type"]))
        #expect(!model.availableFields.map(\.key).contains("isbn"))
        for group in model.groupedAvailableFields {
            let flags = group.fields.map(\.isRecommended)
            if let firstOrdinary = flags.firstIndex(of: false) {
                #expect(!flags[firstOrdinary...].contains(true))
            }
        }
    }

    @Test("A chosen managed field remains addressable after Source Type changes")
    func selectedFieldSurvivesSourceTypeChange() throws {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "book.md", rawContent: "Body\n"),
            role: .sourceCorpus,
            metadataFields: ["type": .string("book")]
        )
        let bookModel = PropertyEditorModel(note: note, metadataCatalog: .builtIn)
        let isbn = try #require(bookModel.availableFields.first { $0.key == "isbn" })
        #expect(isbn.isTypicalForSourceType)

        let articleModel = PropertyEditorModel(
            note: note,
            metadataCatalog: .builtIn,
            analysisSourceTypeOverride: .journalArticle
        )
        #expect(articleModel.canonicalField(for: "isbn")?.isTypicalForSourceType == false)
        #expect(!articleModel.availableFields.contains { $0.key == "isbn" })
    }

    @Test("Analysis without Source Type offers only fields common to every type")
    func analysisChooserWithoutTypeUsesSharedFields() {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "analysis.md", rawContent: "Body\n"),
            role: .sourceCorpus
        )
        let fields = PropertyEditorModel(note: note, metadataCatalog: .builtIn).availableFields
        #expect(Set(fields.map(\.key)) == ["type", "title", "authors", "publication_date"])
        #expect(fields.first { $0.key == "type" }?.isRecommended == true)
    }

    @Test("Managed list edits preserve duplicate researcher values")
    func duplicateListEntriesRemainDistinct() throws {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "topic.md", rawContent: "---\nkeywords: [source]\n---\n"),
            role: .topicKnowledge,
            metadataFields: ["aliases": .array([.string("one")])]
        )
        let model = PropertyEditorModel(note: note, metadataCatalog: .builtIn)
        let aliases = try #require(model.presentFields.first { $0.key == "aliases" })
        let proposed = model.updating(
            note.managedMetadataFields,
            field: aliases,
            value: .array([.string("one"), .string("one")])
        )
        #expect(proposed["aliases"] == .array([.string("one"), .string("one")]))
        #expect(note.authoredYAMLValue(named: "keywords") == .array([.string("source")]))
    }

    @Test("Unauthoritative settings grant no About fields")
    func invalidSettingsDoNotFallBackToAboutDefaults() {
        let denied = WorkspaceAboutConfiguration.configuration(
            settings: TriptychSettings(),
            slot: .paperAnalysis,
            isAuthoritative: false
        )
        let allowed = WorkspaceAboutConfiguration.configuration(
            settings: TriptychSettings(),
            slot: .paperAnalysis,
            isAuthoritative: true
        )
        #expect(denied.visibleFields.isEmpty)
        #expect(allowed == TriptychSettings.defaultAbout[.paperAnalysis])
    }

    @Test("Choice values display human labels")
    func choiceValuesHaveHumanLabels() {
        #expect(PropertyPresentationCatalog.choiceDisplayName(
            for: "journal_article",
            fieldKey: "type"
        ) == "Journal Article")
        #expect(PropertyPresentationCatalog.choiceDisplayName(
            for: "in_press",
            fieldKey: "publication_status"
        ) == "In Press")
    }
}

private func propertyWorkspaceLocation(
    _ document: NoteDocument,
    role: VaultRole,
    metadataFields: [String: YAMLValue]? = nil
) -> WindowDocumentLocation {
    let noteID = UUID()
    let metadata = metadataFields.map {
        NoteMetadataSnapshot(
            record: NoteMetadataRecord(noteID: noteID, fields: $0),
            revision: DocumentFingerprint(content: String(describing: $0))
        )
    }
    return .workspace(WorkspaceNoteSnapshot(
        id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: document.relativePath),
        vaultRole: role,
        stableIdentity: .resolved(noteID),
        document: document,
        fileMetadata: WorkspaceFileMetadata(
            byteCount: document.sourceBytes.count,
            creationDate: nil,
            modificationDate: nil
        ),
        graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0),
        metadata: metadata,
        headings: []
    ))
}
