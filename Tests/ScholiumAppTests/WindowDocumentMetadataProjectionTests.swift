import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Window document metadata projection")
struct WindowDocumentMetadataProjectionTests {
    @Test("Status follows Core canonical precedence and legacy aliases")
    func statusUsesCoreVocabulary() throws {
        let contract = try #require(
            PropertyContractCatalog.contract(for: "status", profile: .analysis)
        )
        #expect(!contract.legacyAliases.isEmpty)

        for alias in contract.legacyAliases {
            let source = """
            ---
            \(alias): complete
            unknown:
              nested: untouched
            ---
            Body
            """
            let note = metadataLocation(source, role: .sourceCorpus)

            #expect(note.status == "complete")
            #expect(note.rawContent == source)
        }

        let alias = try #require(contract.legacyAliases.first)
        let canonicalSource = """
        ---
        \(alias): complete
        \(contract.canonicalKey): reviewed
        unknown: untouched
        ---
        Body
        """
        let canonicalNote = metadataLocation(canonicalSource, role: .sourceCorpus)

        #expect(canonicalNote.status == "reviewed")
        #expect(canonicalNote.rawContent == canonicalSource)
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
            ("\"\(midpoint)\"", midpoint),
            ("\(midpoint).0", midpoint),
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

    @Test("App model contains no duplicated status aliases or rating bounds")
    func appModelContainsNoSemanticLiterals() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scholium/Models/Models.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("\"analysis_status\""))
        #expect(!source.contains("\"lifecycle_status\""))
        #expect(!source.contains("0...10"))
        #expect(!source.contains("TriptychProperty"))
        #expect(source.contains("PropertyContractCatalog.contract"))
    }

    @Test("Sidebar property options aggregate each note projection once")
    func propertyFilterOptionsPreserveValuesAndLimits() {
        let first = metadataLocation(
            """
            ---
            analysis_status: complete
            authors:
              - Beauvoir
              - Arendt
            custom: Alpha
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

        #expect(options.valuesByKey["status"] == ["complete", "reviewed"])
        #expect(options.valuesByKey["authors"] == ["Arendt", "Beauvoir", "Weil"])
        #expect(options.valuesByKey["custom"] == ["Alpha", "Beta"])
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
        review: nil,
        graphCounts: WorkspaceGraphCounts(
            incoming: 0,
            outgoing: 0,
            broken: 0,
            ambiguous: 0
        )
    ))
}
