import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Window document metadata projection")
struct WindowDocumentMetadataProjectionTests {
    @Test("Unknown YAML remains source-only and never becomes a semantic property")
    func statusIsNotCoreVocabulary() {
        let source = """
        ---
        status: reviewed
        unknown: untouched
        ---
        Body
        """
        let note = metadataLocation(source, role: .sourceCorpus)

        #expect(PropertyContractCatalog.contract(for: "status", profile: .analysis) == nil)
        #expect(note.authoredYAMLValue(named: "status") == nil)
        #expect(note.semanticProperty(at: "status", catalog: .builtIn) == nil)
        #expect(note.filterableProperties(catalog: .builtIn)["status"] == nil)
        #expect(note.rawContent == source)
    }

    @Test("Managed publication date wins while same-named YAML remains source-only")
    func publicationDateUsesCoreShape() throws {
        let contract = try #require(
            NoteMetadataCatalog.builtIn.contract(for: "publication_date", profile: .analysis)
        )
        #expect(contract.valueKind == .date)
        #expect(PropertyContractCatalog.contract(for: "year", profile: .analysis) == nil)
        let source = """
        ---
        publication_date: 1990/1992
        year: 1991
        unknown:
          nested: untouched
        ---
        Body
        """
        let note = metadataLocation(
            source,
            role: .sourceCorpus,
            metadataFields: ["publication_date": .string("1990/1992")]
        )

        #expect(note.authoredYAMLValue(named: "publication_date") == nil)
        #expect(note.semanticProperty(
            at: "publication_date",
            catalog: .builtIn
        ) == .string("1990/1992"))
        #expect(note.semanticProperty(at: "year", catalog: .builtIn) == nil)
        #expect(note.rawContent == source)
    }

    @Test("Workspace locations reuse the fingerprint-bound title projection")
    func workspaceLocationUsesCachedTitleProjection() {
        let document = NoteDocument(
            relativePath: "Cached.md",
            rawContent: "# Cached Workspace Title\n\nBody"
        )
        let semantic = MarkdownSemanticDocument(parsing: document)
        let cachedTitle = WorkspaceNoteTitleProjection(
            document: document,
            vaultRole: .topicKnowledge
        )
        let snapshot = WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: document.relativePath
            ),
            vaultRole: .topicKnowledge,
            stableIdentity: .unresolved,
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: nil
            ),
            graphCounts: WorkspaceGraphCounts(
                incoming: 0,
                outgoing: 0,
                broken: 0,
                ambiguous: 0
            ),
            headings: semantic.headings,
            cachedTitleProjection: cachedTitle
        )

        #expect(WindowDocumentLocation.workspace(snapshot).displayName == cachedTitle.resolution.title)
        #expect(cachedTitle.resolution.title == "Cached")
        #expect(snapshot.cachedTitleProjection?.sourceFingerprint == document.fingerprint)
    }

    @Test("App model contains no duplicated status aliases or rating bounds")
    func appModelContainsNoSemanticLiterals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Models/Models.swift",
            "ScholiumContracts/SearchContracts.swift",
            "ScholiumCore/TriptychSearchIndex.swift",
        ]
        let sources = try relativePaths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }

        for source in sources {
            #expect(!source.contains("\"analysis_status\""))
            #expect(!source.contains("\"lifecycle_status\""))
        }
        let appModelSource = sources[0]
        #expect(!appModelSource.contains("0...10"))
        #expect(!appModelSource.contains("TriptychProperty"))
        #expect(appModelSource.contains("PropertyContractCatalog.contract"))
    }

    @Test("Sidebar property options aggregate canonical YAML and resolved managed Metadata only")
    func propertyFilterOptionsPreserveValuesAndLimits() {
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .paperAnalysis: [
                MetadataFieldDefinition(key: "research_status", valueKind: .text),
                MetadataFieldDefinition(key: "too_long", valueKind: .text),
            ],
        ])
        let first = metadataLocation(
            """
            ---
            status: complete
            summary: Alpha
            keywords: [ethics]
            nested:
              child: Gamma
            ---
            First
            """,
            role: .sourceCorpus,
            relativePath: "First.md",
            metadataFields: [
                "authors": .array([
                    .object(["literal": .string("Beauvoir")]),
                    .object(["literal": .string("Arendt")]),
                ]),
                "research_status": .string("complete"),
                "too_long": .string(String(repeating: "x", count: 81)),
            ]
        )
        let second = metadataLocation(
            """
            ---
            status: reviewed
            summary: Beta
            keywords: [ethics, value]
            ---
            Second
            """,
            role: .sourceCorpus,
            relativePath: "Second.md",
            metadataFields: [
                "authors": .array([
                    .object(["literal": .string("Arendt")]),
                    .object(["literal": .string("Weil")]),
                ]),
                "research_status": .string("reviewed"),
            ]
        )

        let options = WindowPropertyFilterOptions(
            notes: [first, second],
            catalog: catalog
        )

        #expect(options.valuesByKey["summary"] == ["Alpha", "Beta"])
        #expect(options.valuesByKey["keywords"] == ["ethics", "value"])
        #expect(options.valuesByKey["authors"] == ["Arendt", "Beauvoir", "Weil"])
        #expect(options.valuesByKey["research_status"] == ["complete", "reviewed"])
        #expect(options.valuesByKey["status"] == nil)
        #expect(options.valuesByKey["nested.child"] == nil)
        #expect(options.valuesByKey["too_long"] == nil)
        #expect(options.keys == options.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })
        #expect(Set(options.keys).count == options.keys.count)
    }

    @Test("Sidebar context consumes one aggregate property projection")
    func sidebarContextUsesAggregatePropertyOptions() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ContentView.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "private var sidebarContext"))
        let end = try #require(source.range(
            of: "private var currentWorkspaceSlot",
            range: start.upperBound..<source.endIndex
        ))
        let sidebarContext = source[start.lowerBound..<end.lowerBound]

        #expect(sidebarContext.contains(
            "let propertyFilterOptions = appState.availablePropertyFilterOptions"
        ))
        #expect(!sidebarContext.contains("availablePropertyValues(for:"))
    }

    @Test("Window projection owner commits property filters with the note inventory")
    func windowProjectionOwnsPropertyFilterOptions() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/Window/WindowWorkspaceProjectionController.swift"
            ),
            encoding: .utf8
        )

        #expect(controller.contains(
            "var propertyFilterOptions = WindowPropertyFilterOptions("
        ))
        #expect(controller.contains(
            "state.propertyFilterOptions = WindowPropertyFilterOptions("
        ))
        #expect(controller.contains("state.authors = Set(notes.flatMap(\\.authors)).sorted()"))
        #expect(!controller.contains("state.years"))
        #expect(app.contains(
            "var availablePropertyFilterOptions: WindowPropertyFilterOptions {"
        ))
        #expect(app.contains("workspaceProjectionController.propertyFilterOptions"))
        #expect(app.contains("workspaceProjectionController.authors"))
        #expect(!app.contains("workspaceProjectionController.years"))
        #expect(!app.contains("Set(notesInCurrentScope.flatMap(\\.authors)).sorted()"))
        #expect(!app.contains("Set(notesInCurrentScope.compactMap(\\.year)).sorted(by: >)"))
        #expect(!app.contains("@Published var notes: [WindowDocumentLocation]"))
    }
}

private func metadataLocation(
    _ source: String,
    role: VaultRole,
    relativePath: String = "metadata.md",
    metadataFields: [String: YAMLValue]? = nil
) -> WindowDocumentLocation {
    let document = NoteDocument(relativePath: relativePath, rawContent: source)
    let noteID = UUID()
    let metadata = metadataFields.map {
        NoteMetadataSnapshot(
            record: NoteMetadataRecord(noteID: noteID, fields: $0),
            revision: DocumentFingerprint(content: String(describing: $0))
        )
    }
    return .workspace(WorkspaceNoteSnapshot(
        id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: relativePath),
        vaultRole: role,
        stableIdentity: .resolved(noteID),
        document: document,
        fileMetadata: WorkspaceFileMetadata(
            byteCount: document.sourceBytes.count,
            creationDate: nil,
            modificationDate: nil
        ),
        graphCounts: WorkspaceGraphCounts(
            incoming: 0,
            outgoing: 0,
            broken: 0,
            ambiguous: 0
        ),
        metadata: metadata
    ))
}
