import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research Record prose presentation")
@MainActor
struct ResearchRecordProsePresentationTests {
    @Test("Only uniquely resolved links with stable identities become interactive")
    func stableNavigationOnly() throws {
        let vaultID = UUID()
        let source = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Source.md")
        let target = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Target.md")
        let targetStableID = UUID()
        let navigation = ResearchRecordProseNavigation(
            catalog: [
                LinkCatalogNote(id: source, headings: [], blockAnchors: [:]),
                LinkCatalogNote(id: target, headings: [], blockAnchors: [:]),
            ],
            stableNoteIDs: [source: UUID(), target: targetStableID]
        )

        let destination = try #require(navigation.destination(
            target: "Target",
            fragment: nil,
            from: source
        ))
        #expect(destination.stableNoteID == targetStableID)
        #expect(destination.note == target)
        #expect(destination.sourceLine == nil)
        let url = try #require(navigation.url(for: destination))
        #expect(navigation.destination(for: url) == destination)

        let fingerprint = DocumentFingerprint(content: "recorded")
        let participant = try PortableResearchNoteRevision(
            noteID: targetStableID,
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Old/Target.md"
            ),
            role: .analysis,
            title: "Target",
            startingRevision: fingerprint,
            endingRevision: fingerprint
        )
        #expect(navigation.currentLocation(for: participant) == target)

        #expect(navigation.destination(
            target: "Missing",
            fragment: nil,
            from: source
        ) == nil)

        let duplicate = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Duplicate.md"
        )
        let ambiguousIdentityNavigation = ResearchRecordProseNavigation(
            catalog: [
                LinkCatalogNote(id: source, headings: [], blockAnchors: [:]),
                LinkCatalogNote(id: target, headings: [], blockAnchors: [:]),
                LinkCatalogNote(id: duplicate, headings: [], blockAnchors: [:]),
            ],
            stableNoteIDs: [
                source: UUID(),
                target: targetStableID,
                duplicate: targetStableID,
            ]
        )
        #expect(ambiguousIdentityNavigation.destination(
            target: "Target",
            fragment: nil,
            from: source
        ) == nil)
    }

    @Test("Resolved Wikilinks show their label while unresolved links show exact fallback source")
    func failClosedPresentation() throws {
        let vaultID = UUID()
        let source = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Source.md")
        let target = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Paper.md")
        let navigation = ResearchRecordProseNavigation(
            catalog: [
                LinkCatalogNote(id: source, headings: [], blockAnchors: [:]),
                LinkCatalogNote(id: target, headings: [], blockAnchors: [:]),
            ],
            stableNoteIDs: [source: UUID(), target: UUID()]
        )
        let presentation = ResearchRecordProsePresentation(
            source: "See [[Paper|the paper]] and [[Missing#Claim|its reply]].",
            sourceNote: source,
            navigation: navigation
        )
        let block = try #require(presentation.blocks.first)

        #expect(String(block.text.characters) == "See the paper and [[Missing#Claim|its reply]].")
        let links = block.text.runs.compactMap(\.link)
        #expect(links.count == 1)
        #expect(navigation.destination(for: try #require(links.first))?.note == target)
    }

    @Test("Absent source context leaves internal links literal but preserves safe web links")
    func absentSourceContext() throws {
        let presentation = ResearchRecordProsePresentation(
            source: "[[Paper]] and [web](https://example.org)",
            sourceNote: nil,
            navigation: .empty
        )
        let block = try #require(presentation.blocks.first)

        #expect(String(block.text.characters) == "[[Paper]] and web")
        let links = block.text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.org")!])
    }
}
