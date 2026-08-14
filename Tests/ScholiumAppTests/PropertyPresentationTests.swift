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

    @Test("Choice values keep exact YAML while displaying human labels")
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

    @Test("Analysis chooser is source-type aware and keeps recommendations first")
    func analysisChooserUsesSourceTypeProfile() throws {
        let source = "---\ntype: journal_article\n---\n"
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "article.md", rawContent: source),
            role: .sourceCorpus
        )
        let model = PropertyEditorModel(note: note)
        let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: .journalArticle)

        #expect(
            Set(model.availableFields.map(\.key))
                == Set(sourceProfile.applicableFields).subtracting(["type"])
        )
        #expect(!model.availableFields.map(\.key).contains("isbn"))
        #expect(!model.availableFields.map(\.key).contains("report_number"))

        for group in model.groupedAvailableFields {
            let flags = group.fields.map(\.isRecommended)
            if let firstOrdinary = flags.firstIndex(of: false) {
                #expect(!flags[firstOrdinary...].contains(true))
            }
        }
    }

    @Test("A selected canonical field remains addressable after Source Type changes")
    func selectedFieldSurvivesSourceTypeChange() throws {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "book.md", rawContent: "---\ntype: book\n---\n"),
            role: .sourceCorpus
        )
        let bookModel = PropertyEditorModel(note: note)
        let selectedISBN = try #require(bookModel.availableFields.first {
            $0.key == "isbn"
        })
        #expect(selectedISBN.isTypicalForSourceType)

        let articleModel = PropertyEditorModel(
            note: note,
            analysisSourceTypeOverride: .journalArticle
        )
        let retainedISBN = try #require(articleModel.canonicalField(for: "isbn"))

        #expect(!retainedISBN.isTypicalForSourceType)
        #expect(!articleModel.availableFields.contains { $0.key == "isbn" })
    }

    @Test("Text-list updates preserve authored duplicate sequence entries")
    func duplicateListEntriesRemainDistinct() throws {
        let document = NoteDocument(
            relativePath: "tags.md",
            rawContent: "---\ntags: [draft]\n---\n"
        )
        let note = propertyWorkspaceLocation(document, role: .sourceCorpus)
        let model = PropertyEditorModel(note: note)
        let tags = try #require(model.presentFields.first { $0.key == "tags" })
        let proposed = model.updating(
            note.frontmatter,
            field: tags,
            value: .array([.string("draft"), .string("draft")])
        )
        let result = try document.applying(
            .frontmatter(PropertyEditorModel.frontmatterEdits(
                from: note.frontmatter,
                to: proposed
            )),
            timestampKey: nil
        )

        #expect(NoteDocument(relativePath: "tags.md", rawContent: result)
            .parsedFrontmatter["tags"] == .array([.string("draft"), .string("draft")]))
    }

    @Test("Dotted Unicode custom keys remain exact top-level Properties")
    func dottedCustomKeysDoNotBecomeKeyPaths() throws {
        let document = NoteDocument(
            relativePath: "custom.md",
            rawContent: "---\n研究.阶段: 草稿\n---\n"
        )
        let note = propertyWorkspaceLocation(document, role: .topicKnowledge)
        let model = PropertyEditorModel(note: note)
        let field = try #require(model.presentFields.first {
            $0.key == "研究.阶段"
        })

        #expect(note.topLevelProperty(named: "研究.阶段") == .string("草稿"))
        #expect(note.property(at: "研究.阶段") == nil)
        #expect(!field.isReadOnly)
        #expect(AboutProfileCatalog.groupedEntries(
            for: .topicMarkdown,
            visibleFields: ["研究.阶段"]
        ).flatMap(\.keys) == ["研究.阶段"])
    }

    @Test("Unauthoritative portable settings grant no About fields")
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
        #expect(allowed == TriptychSettings.defaultProperties[.paperAnalysis])
    }

    @Test("Current-note editing is independent of portable About settings")
    func currentNoteEditabilityComesFromExactSource() throws {
        let document = NoteDocument(
            relativePath: "topic.md",
            rawContent: "---\naliases: [one, two]\ncustom_note: exact\n---\n"
        )
        let note = propertyWorkspaceLocation(document, role: .topicKnowledge)
        let model = PropertyEditorModel(note: note)

        #expect(model.presentFields.first { $0.key == "aliases" }?.isReadOnly == false)
        #expect(model.presentFields.first { $0.key == "custom_note" }?.isReadOnly == false)
    }

    @Test("Analysis without Source Type offers only shared fields and Source Type")
    func analysisChooserWithoutTypeUsesSharedFields() {
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "analysis.md", rawContent: "Body\n"),
            role: .sourceCorpus
        )
        let fields = PropertyEditorModel(note: note).availableFields
        let keys = Set(fields.map(\.key))

        #expect(keys.contains("type"))
        #expect(keys.contains("title"))
        #expect(keys.contains("authors"))
        #expect(keys.contains("source_basis"))
        #expect(!keys.contains("report_number"))
        #expect(fields.first { $0.key == "type" }?.isRecommended == true)
    }

    @Test("Existing non-typical fields remain present while unsupported shapes stay read only")
    func existingFieldsAreNeverHiddenOrGuessed() throws {
        let source = """
        ---
        type: journal_article
        isbn: 978-1-4028-9462-6
        authors:
          - Legacy String Author
        custom_mapping:
          nested: exact
        ---
        Body
        """
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "legacy.md", rawContent: source),
            role: .sourceCorpus
        )
        let model = PropertyEditorModel(note: note)
        let isbn = try #require(model.presentFields.first { $0.key == "isbn" })
        let authors = try #require(model.presentFields.first { $0.key == "authors" })
        let custom = try #require(model.presentFields.first { $0.key == "custom_mapping" })

        #expect(!isbn.isTypicalForSourceType)
        #expect(!isbn.isReadOnly)
        #expect(authors.isReadOnly)
        #expect(custom.isReadOnly)
    }

    @Test("Lexically unbounded values remain Source-only even with a supported semantic shape")
    func unsupportedLexicalShapesAreReadOnly() throws {
        let source = """
        ---
        summary: |
          Keep this block style exact.
        "custom-key": plain scalar
        tags:
          - editable
        ---
        Body
        """
        let note = propertyWorkspaceLocation(
            NoteDocument(relativePath: "lexical.md", rawContent: source),
            role: .sourceCorpus
        )
        let model = PropertyEditorModel(note: note)
        let summary = try #require(model.presentFields.first { $0.key == "summary" })
        let custom = try #require(model.presentFields.first { $0.key == "custom-key" })
        let tags = try #require(model.presentFields.first { $0.key == "tags" })

        #expect(summary.isReadOnly)
        #expect(custom.isReadOnly)
        #expect(tags.isReadOnly)
    }

    @Test("Property deletion uses the same exact targeted patch path")
    func deletionPreservesNeighboringSource() throws {
        let source = "---\n# keep\ntitle: Remove me\ncustom: 'exact'\n---\nBody\n"
        let document = NoteDocument(relativePath: "delete.md", rawContent: source)
        var proposed = document.parsedFrontmatter
        proposed.removeValue(forKey: "title")
        let edits = PropertyEditorModel.frontmatterEdits(
            from: document.parsedFrontmatter,
            to: proposed
        )
        let result = try document.applying(.frontmatter(edits), timestampKey: nil)

        #expect(result == "---\n# keep\ncustom: 'exact'\n---\nBody\n")
    }

    @Test("Authored date text is preserved rather than parsed or trimmed")
    func dateEditingPreservesAuthoredText() throws {
        let source = "---\npublication_date: \"2026\"\n---\n"
        let document = NoteDocument(relativePath: "date.md", rawContent: source)
        let note = propertyWorkspaceLocation(document, role: .sourceCorpus)
        let model = PropertyEditorModel(note: note)
        let field = try #require(model.presentFields.first {
            $0.key == "publication_date"
        })
        let proposed = model.updating(
            note.frontmatter,
            field: field,
            text: " circa 1920–1922 "
        )
        let result = try document.applying(
            .frontmatter(PropertyEditorModel.frontmatterEdits(
                from: note.frontmatter,
                to: proposed
            )),
            timestampKey: nil
        )

        #expect(result.contains("publication_date: \" circa 1920–1922 \"\n"))
    }

    @Test("YAML timestamps remain exact authored text and Source-only for every text field")
    func timestampScalarsAreSourceOnly() throws {
        let unquoted = propertyWorkspaceLocation(
            NoteDocument(
                relativePath: "unquoted-date.md",
                rawContent: "---\npublication_date: 2025-01-01\n---\n"
            ),
            role: .sourceCorpus
        )
        let unquotedField = try #require(
            PropertyEditorModel(note: unquoted).presentFields.first {
                $0.key == "publication_date"
            }
        )
        let authoredToken = try #require(
            unquoted.authoredTopLevelScalarToken(named: "publication_date")
        )

        #expect(authoredToken == "2025-01-01")
        #expect(FrontmatterPatchPlanner.isTimestampScalarToken(authoredToken))
        #expect(unquotedField.isReadOnly)

        let title = propertyWorkspaceLocation(
            NoteDocument(
                relativePath: "timestamp-title.md",
                rawContent: "---\ntitle: 2025-01-01\n---\n"
            ),
            role: .sourceCorpus
        )
        let titleField = try #require(
            PropertyEditorModel(note: title).presentFields.first { $0.key == "title" }
        )
        #expect(title.authoredTopLevelScalarToken(named: "title") == "2025-01-01")
        #expect(titleField.isReadOnly)

        let explicit = propertyWorkspaceLocation(
            NoteDocument(
                relativePath: "explicit-date.md",
                rawContent: "---\npublication_date: !!timestamp 2025-01-01\n---\n"
            ),
            role: .sourceCorpus
        )
        let explicitField = try #require(
            PropertyEditorModel(note: explicit).presentFields.first {
                $0.key == "publication_date"
            }
        )
        let explicitToken = try #require(
            explicit.authoredTopLevelScalarToken(named: "publication_date")
        )
        #expect(explicitToken == "!!timestamp 2025-01-01")
        #expect(FrontmatterPatchPlanner.isTimestampScalarToken(explicitToken))
        #expect(explicitField.isReadOnly)

        let quoted = propertyWorkspaceLocation(
            NoteDocument(
                relativePath: "quoted-date.md",
                rawContent: "---\npublication_date: \"2025-01-01\"\n---\n"
            ),
            role: .sourceCorpus
        )
        let quotedField = try #require(
            PropertyEditorModel(note: quoted).presentFields.first {
                $0.key == "publication_date"
            }
        )
        let quotedToken = try #require(
            quoted.authoredTopLevelScalarToken(named: "publication_date")
        )

        #expect(quotedToken == "\"2025-01-01\"")
        #expect(!FrontmatterPatchPlanner.isTimestampScalarToken(quotedToken))
        #expect(!quotedField.isReadOnly)
        #expect(quoted.topLevelProperty(named: "publication_date") == .string("2025-01-01"))
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
