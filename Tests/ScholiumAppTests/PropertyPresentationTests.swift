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

    @Test("Archived custom fields retain present values but leave new-value and About discovery")
    func archivedCustomFieldPresentation() throws {
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .topicKnowledge: [
                MetadataFieldDefinition(
                    key: "research_stage",
                    valueKind: .choice,
                    label: "Research Stage",
                    description: "Current stage of the topic",
                    allowedValues: ["draft", "review"],
                    lifecycle: .archived
                ),
            ],
        ])
        let presentNote = propertyWorkspaceLocation(
            NoteDocument(relativePath: "topic.md", rawContent: "# Topic\n"),
            role: .topicKnowledge,
            metadataFields: ["research_stage": .string("draft")]
        )
        let present = PropertyEditorModel(
            note: presentNote,
            metadataCatalog: catalog
        )
        let field = try #require(present.presentFields.first {
            $0.key == "research_stage"
        })
        #expect(field.label == "Research Stage")
        #expect(field.help == "Current stage of the topic")
        #expect(field.allowedValues == ["draft", "review"])

        let absent = PropertyEditorModel(
            note: propertyWorkspaceLocation(
                NoteDocument(relativePath: "empty.md", rawContent: "# Empty\n"),
                role: .topicKnowledge
            ),
            metadataCatalog: catalog
        )
        #expect(!absent.availableFields.contains { $0.key == "research_stage" })
        #expect(!AboutProfileCatalog.allowsOptionalField(
            "research_stage",
            profile: .topicMarkdown,
            catalog: catalog
        ))
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

    @Test("About keeps core empty fields and appends every other present value")
    func aboutCombinesAlwaysShownAndPresentFields() throws {
        let groups = AboutProfileCatalog.groupedEntries(
            for: .analysis,
            visibleFields: ["type", "authors", "publication_date"],
            presentManagedFields: ["doi", "publisher"],
            catalog: .builtIn
        )
        let keys = groups.flatMap(\.keys)

        #expect(keys.contains("type"))
        #expect(keys.contains("authors"))
        #expect(keys.contains("publication_date"))
        #expect(keys.contains("publisher"))
        #expect(keys.contains("doi"))
        #expect(keys.suffix(2) == ["summary", "keywords"])
        #expect(!keys.contains("title"))
    }

    @Test("About preserves configured order within semantic groups")
    func aboutPreservesConfiguredGroupOrder() {
        let groups = AboutProfileCatalog.groupedEntries(
            for: .analysis,
            visibleFields: ["authors", "type", "publication_date"],
            presentManagedFields: ["publisher", "doi"],
            catalog: .builtIn
        )

        #expect(groups.map(\.group) == [
            .source,
            .publication,
            .accessAndIdentifiers,
            .authoredYAML,
        ])
        #expect(groups.map(\.keys) == [
            ["authors", "type"],
            ["publication_date", "publisher"],
            ["doi"],
            ["summary", "keywords"],
        ])
    }

    @Test("About inline save state distinguishes conflicts and permits retry or cancel")
    func aboutInlineSaveState() {
        var state = AboutFieldOperationState.idle
        state.beginSaving()
        #expect(state.isSaving)
        #expect(state.failure == nil)

        state.finishSaving(with: NoteMetadataError.revisionConflict(UUID()))
        #expect(!state.isSaving)
        #expect(state.failure?.isConflict == true)
        #expect(state.failure?.message.contains("changed after it was loaded") == true)

        state.beginSaving()
        state.finishSaving(with: VaultRepositoryError.conflict(
            expected: DocumentFingerprint(content: "expected"),
            current: DocumentFingerprint(content: "current")
        ))
        #expect(state.failure?.isConflict == true)

        state.beginSaving()
        #expect(state == .saving)
        state.finishSaving(with: VaultRepositoryError.invalidFrontmatter("Fixture"))
        #expect(state.failure?.isConflict == false)
        #expect(state.failure?.message.contains("Fixture") == true)

        state.reset()
        #expect(state == .idle)
    }

    @Test("About keeps a present archived custom value without making it selectable when empty")
    func aboutKeepsPresentArchivedValue() throws {
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .topicKnowledge: [
                MetadataFieldDefinition(
                    key: "research_stage",
                    valueKind: .text,
                    lifecycle: .archived
                ),
            ],
        ])
        let groups = AboutProfileCatalog.groupedEntries(
            for: .topicMarkdown,
            visibleFields: ["aliases"],
            presentManagedFields: ["research_stage"],
            catalog: catalog
        )

        #expect(groups.flatMap(\.keys).contains("research_stage"))
        #expect(!AboutProfileCatalog.allowsOptionalField(
            "research_stage",
            profile: .topicMarkdown,
            catalog: catalog
        ))
    }

    @Test("Settlement presentation distinguishes current, changed, and never-settled revisions")
    func settlementPresentationUsesExactRevision() throws {
        let noteID = UUID()
        let settledRevision = DocumentFingerprint(content: "settled")
        let currentRevision = DocumentFingerprint(content: "current")
        let settledAt = Date(timeIntervalSince1970: 1_700_000_000)
        let settlement = SettlementRecord(
            noteID: noteID,
            fingerprint: settledRevision,
            settledAt: settledAt,
            researcher: "Researcher",
            rationale: "Stable enough"
        )

        let current = AboutSettlementPresentation.resolve(
            noteID: noteID,
            currentRevision: settledRevision,
            requirement: nil,
            settlements: [settlement]
        )
        let changed = AboutSettlementPresentation.resolve(
            noteID: noteID,
            currentRevision: currentRevision,
            requirement: WorkspaceSettlementRequirement(
                noteID: noteID,
                note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "note.md"),
                title: "Note",
                currentRevision: currentRevision,
                reason: .changedSinceSettlement,
                previousSettlement: settlement
            ),
            settlements: [settlement]
        )
        let never = AboutSettlementPresentation.resolve(
            noteID: noteID,
            currentRevision: currentRevision,
            requirement: nil,
            settlements: []
        )

        #expect(current.state == .settled)
        #expect(current.settledAt == settledAt)
        #expect(changed.state == .changedSinceSettlement)
        #expect(changed.settledAt == settledAt)
        #expect(never.state == .notYetSettled)
        #expect(never.settledAt == nil)
    }

    @Test("Changed-since-settlement exposes Settle Again in the Document Rail")
    func changedSettlementRailAction() {
        #expect(DocumentSettlementRailAction.resolve(
            .changedSinceSettlement
        ) == .settleAgain)
        #expect(DocumentSettlementRailAction.resolve(.settled) == .settleAgain)
        #expect(DocumentSettlementRailAction.resolve(.notYetSettled) == .settle)
        #expect(DocumentSettlementRailAction.resolve(.unavailable) == .unavailable)
    }

    @Test("About presents file creation and modification facts from the snapshot")
    func aboutFileHistoryFacts() {
        let created = Date(timeIntervalSince1970: 10)
        let modified = Date(timeIntervalSince1970: 20)
        let facts = AboutFactPresentation.fileHistory(
            metadata: WorkspaceFileMetadata(
                byteCount: 42,
                creationDate: created,
                modificationDate: modified
            ),
            formatDate: fixtureDate
        )

        #expect(facts == [
            ScholiumApparatusFact(
                id: "file-created",
                label: "File Created",
                value: "10",
                monospacedDigits: true
            ),
            ScholiumApparatusFact(
                id: "source-modified",
                label: "Source Modified",
                value: "20",
                monospacedDigits: true
            ),
        ])
        #expect(AboutFactPresentation.fileHistory(
            metadata: nil,
            formatDate: fixtureDate
        ).map(\.value) == ["Unavailable", "Unavailable"])
    }

    @Test("About distinguishes unavailable Settlement facts from never settled")
    func aboutSettlementFacts() {
        let changed = AboutFactPresentation.settlement(
            AboutSettlementPresentation(
                state: .changedSinceSettlement,
                settledAt: Date(timeIntervalSince1970: 30),
                researcher: "Researcher",
                rationale: "Stable enough"
            ),
            formatDate: fixtureDate
        )
        let never = AboutFactPresentation.settlement(
            AboutSettlementPresentation(
                state: .notYetSettled,
                settledAt: nil,
                researcher: nil,
                rationale: nil
            ),
            formatDate: fixtureDate
        )
        let unavailable = AboutFactPresentation.settlement(
            .unavailable,
            formatDate: fixtureDate
        )

        #expect(changed.map(\.id) == [
            "settlement-status", "settled-at", "settled-by",
        ])
        #expect(changed.map(\.label) == ["Status", "Last Settled", "Researcher"])
        #expect(changed.map(\.value) == [
            "Changed since settlement", "30", "Researcher",
        ])
        #expect(never.map(\.value) == ["Not yet settled", "Never"])
        #expect(unavailable.map(\.value) == ["Unavailable", "Unavailable"])
    }

    @Test("About authored edits preserve every unrelated source byte")
    func aboutAuthoredEditUsesTargetedSourcePatch() throws {
        let source = "\u{FEFF}---\r\n# exact comment\r\nsummary: Old value\r\nkeywords: [one, two]\r\nunknown: 'keep'\r\n---\r\n# Body 😀"
        let document = NoteDocument(relativePath: "analysis.md", rawContent: source)
        let proposedChange = try AboutAuthoredFieldMutation.changeSet(
            document: document,
            key: "summary",
            value: .string("New: value")
        )
        let changeSet = try #require(proposedChange)
        let result = try document.applying(changeSet, timestampKey: nil)

        #expect(result == "\u{FEFF}---\r\n# exact comment\r\nsummary: \"New: value\"\r\nkeywords: [one, two]\r\nunknown: 'keep'\r\n---\r\n# Body 😀")
    }

    @Test("About inserts the first authored field only after explicit input")
    func aboutAuthoredEditCanInsertFirstEnvelope() throws {
        let source = "\u{FEFF}# Existing body\r\n\r\nExact tail"
        let document = NoteDocument(relativePath: "topic.md", rawContent: source)
        let proposedChange = try AboutAuthoredFieldMutation.changeSet(
            document: document,
            key: "keywords",
            value: .array([.string("agency"), .string("reasons")])
        )
        let changeSet = try #require(proposedChange)
        let result = try document.applying(changeSet, timestampKey: nil)

        #expect(result == "\u{FEFF}---\r\nkeywords:\r\n  - agency\r\n  - reasons\r\n---\r\n# Existing body\r\n\r\nExact tail")
    }
}

private func fixtureDate(_ date: Date?) -> String {
    date.map { String(Int($0.timeIntervalSince1970)) } ?? "Unavailable"
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
