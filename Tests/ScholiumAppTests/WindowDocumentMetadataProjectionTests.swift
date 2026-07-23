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

    @Test("Debate Importance follows the Core integer-range contract")
    func debateImportanceUsesCoreRange() throws {
        let contract = try #require(
            PropertyContractCatalog.contract(for: "debate_importance", profile: .analysis)
        )
        let bounds = try #require(contract.constraints.compactMap { constraint in
            guard case .integerRange(let minimum, let maximum) = constraint else {
                return nil as ClosedRange<Int>?
            }
            return minimum...maximum
        }.first)
        let midpoint = bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) / 2
        let cases: [(yaml: String, expected: Int?)] = [
            (String(bounds.lowerBound), bounds.lowerBound),
            (String(bounds.upperBound), bounds.upperBound),
            (String(bounds.lowerBound - 1), nil),
            (String(bounds.upperBound + 1), nil),
            ("\"\(midpoint)\"", nil),
            ("\(midpoint).0", nil),
        ]

        for item in cases {
            let source = """
            ---
            \(contract.canonicalKey): \(item.yaml)
            unknown:
              nested: untouched
            ---
            Body
            """
            let note = metadataLocation(source, role: .sourceCorpus)

            #expect(note.debateImportance == item.expected)
            #expect(note.rawContent == source)
        }
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

    @Test("Window model caches property filter options when the note inventory changes")
    func windowModelCachesPropertyFilterOptions() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/App/ScholiumApp.swift"
            ),
            encoding: .utf8
        )
        let notesStart = try #require(source.range(
            of: "@Published var notes: [WindowDocumentLocation]"
        ))
        let filtersEnd = try #require(source.range(
            of: "var activeMetadataFilterCount",
            range: notesStart.lowerBound..<source.endIndex
        ))
        let filterState = source[notesStart.lowerBound..<filtersEnd.lowerBound]

        #expect(filterState.contains(
            "didSet {\n            availablePropertyFilterOptions = WindowPropertyFilterOptions(notes: notes)"
        ))
        #expect(filterState.contains(
            "private(set) var availablePropertyFilterOptions = WindowPropertyFilterOptions(notes: [])"
        ))
        #expect(!filterState.contains(
            "var availablePropertyFilterOptions: WindowPropertyFilterOptions {"
        ))
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
