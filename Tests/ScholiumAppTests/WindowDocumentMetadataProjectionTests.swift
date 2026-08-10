import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Window document metadata projection")
struct WindowDocumentMetadataProjectionTests {
    @Test("Status has no semantic projection and remains unknown source YAML")
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
        #expect(note.property(at: "status") == .string("reviewed"))
        #expect(note.filterableProperties["status"] == nil)
        #expect(note.rawContent == source)
    }

    @Test("Publication date is source-safe text and legacy year stays custom")
    func publicationDateUsesCoreShape() throws {
        let contract = try #require(
            PropertyContractCatalog.contract(for: "publication_date", profile: .analysis)
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
        let note = metadataLocation(source, role: .sourceCorpus)

        #expect(note.property(at: "publication_date") == .string("1990/1992"))
        #expect(note.property(at: "year") == .integer(1991))
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
            vaultRole: .topicKnowledge,
            semantic: semantic
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
            lifecycle: .active,
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

    @Test("Sidebar property options aggregate each note projection once")
    func propertyFilterOptionsPreserveValuesAndLimits() {
        let first = metadataLocation(
            """
            ---
            status: complete
            authors:
              - Beauvoir
              - Arendt
            custom: Alpha
            relevance: 9
            nested:
              child: Gamma
            too_long: \(String(repeating: "x", count: 81))
            ---
            First
            """,
            role: .sourceCorpus,
            relativePath: "First.md"
        )
        let second = metadataLocation(
            """
            ---
            status: reviewed
            authors:
              - Arendt
              - Weil
            custom: Beta
            ---
            Second
            """,
            role: .sourceCorpus,
            relativePath: "Second.md"
        )

        let options = WindowPropertyFilterOptions(notes: [first, second])

        #expect(options.valuesByKey["status"] == nil)
        #expect(options.valuesByKey["authors"] == ["Arendt", "Beauvoir", "Weil"])
        #expect(options.valuesByKey["custom"] == ["Alpha", "Beta"])
        #expect(options.valuesByKey["relevance"] == nil)
        #expect(options.valuesByKey["nested.child"] == ["Gamma"])
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
            "var propertyFilterOptions = WindowPropertyFilterOptions(notes: [])"
        ))
        #expect(controller.contains(
            "state.propertyFilterOptions = WindowPropertyFilterOptions(notes: notes)"
        ))
        #expect(controller.contains("state.authors = Set(notes.flatMap(\\.authors)).sorted()"))
        #expect(controller.contains("state.years = Set(notes.compactMap(\\.year)).sorted(by: >)"))
        #expect(app.contains(
            "var availablePropertyFilterOptions: WindowPropertyFilterOptions {"
        ))
        #expect(app.contains("workspaceProjectionController.propertyFilterOptions"))
        #expect(app.contains("workspaceProjectionController.authors"))
        #expect(app.contains("workspaceProjectionController.years"))
        #expect(!app.contains("Set(notesInCurrentScope.flatMap(\\.authors)).sorted()"))
        #expect(!app.contains("Set(notesInCurrentScope.compactMap(\\.year)).sorted(by: >)"))
        #expect(!app.contains("@Published var notes: [WindowDocumentLocation]"))
    }
}

private func metadataLocation(
    _ source: String,
    role: VaultRole,
    relativePath: String = "metadata.md"
) -> WindowDocumentLocation {
    let document = NoteDocument(relativePath: relativePath, rawContent: source)
    return .workspace(WorkspaceNoteSnapshot(
        id: VaultQualifiedNoteID(vaultID: UUID(), relativePath: relativePath),
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
