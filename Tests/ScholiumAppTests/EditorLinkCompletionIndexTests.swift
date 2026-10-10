import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Editor link completion index")
struct EditorLinkCompletionIndexTests {
    @Test("Completion ambiguity follows same-folder, vault, and workspace resolution")
    func ambiguityResolution() async throws {
        let firstVault = UUID()
        let secondVault = UUID()
        let notes = [
            note(vaultID: firstVault, vaultName: "Topics", path: "Folder/Foo.md", title: "Foo local"),
            note(vaultID: firstVault, vaultName: "Topics", path: "Other/Foo.md", title: "Foo other"),
            note(vaultID: secondVault, vaultName: "Works", path: "Other/Foo.md", title: "Foo cross"),
        ]
        let index = EditorLinkCompletionIndex()
        await index.replace(notes: notes, generation: 7)

        let results = try await index.query(
            kind: .wikilink,
            "Foo",
            sourcePath: "Folder/Source.md",
            currentVaultID: firstVault,
            generation: 7
        )

        #expect(results.first { $0.label == "Foo local" }?.insertion == "Foo")
        #expect(results.first { $0.label == "Foo other" }?.insertion == "Other/Foo")
        #expect(results.first { $0.label == "Foo cross" }?.insertion == "Foo cross")
        #expect(results.first { $0.label == "Foo cross" }?.availability == .available)
    }

    @Test("Wikilink and Analysis candidates only offer source targets that resolve to their displayed Note")
    func selectedIdentityRoundTrip() async throws {
        let topics = UUID()
        let analyses = UUID()
        let source = VaultQualifiedNoteID(vaultID: topics, relativePath: "Folder/Draft.md")
        let notes = [
            note(vaultID: topics, path: "Foo.md", title: "Foo"),
            note(vaultID: topics, path: "Folder/Foo.md", title: "Foo"),
            note(vaultID: topics, path: "Other/Foo.md", title: "Foo"),
            note(
                vaultID: analyses, vaultName: "Analyses", role: .sourceCorpus,
                path: "Research/Foo.md", title: "Foo", aliases: ["Unique Analysis"], authors: ["Author"], publicationDate: "2000"),
            note(
                vaultID: analyses, vaultName: "Analyses", role: .sourceCorpus,
                path: "A#draft.md", title: "A#draft", aliases: ["Safe Analysis"], authors: ["Other"], publicationDate: "2001"),
            note(
                vaultID: analyses, vaultName: "Analyses", role: .sourceCorpus,
                path: "Safe.md", title: "Safe", authors: ["[Invalid author"]),
        ]
        let catalog =
            [LinkCatalogNote(id: source)]
            + notes.map {
                LinkCatalogNote(id: .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), title: $0.title, aliases: $0.aliases)
            }
        let index = EditorLinkCompletionIndex()
        await index.replace(notes: notes, generation: 1)
        for kind in [EditorLinkCompletionKind.wikilink, .analysisReference] {
            let candidates = try await index.query(
                kind: kind, "", sourcePath: source.relativePath,
                currentVaultID: topics, generation: 1)
            #expect(candidates.count == (kind == .wikilink ? notes.count : 3))
            for candidate in candidates {
                #expect(candidate.availability == .available)
                let selected = try #require(notes.first { "\($0.reference.vaultName)/\($0.reference.relativePath)" == candidate.path })
                let alias = candidate.displayText.map { "|\($0)" } ?? ""
                let written = NoteDocument(relativePath: source.relativePath, rawContent: "[[\(candidate.insertion)\(alias)]]")
                let snapshot = LinkGraphBuilder.build(
                    generation: 1, catalog: catalog,
                    documents: [source: MarkdownSemanticDocument(parsing: written)], resolutionScope: .workspace)
                #expect(snapshot.outgoing[source]?.count == 1)
                #expect(
                    snapshot.outgoing[source]?.first?.destination?.note
                        == .init(
                            vaultID: selected.reference.vaultID, relativePath: selected.reference.relativePath))
                #expect(snapshot.diagnostics.isEmpty)
            }
        }
    }

    @Test("Unavailable candidates remain discoverable with their exact path and distinct reason")
    func unavailableCandidates() async throws {
        let topics = UUID()
        let analyses = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(
            notes: [
                note(vaultID: topics, path: "Foo.md", title: "Foo"),
                note(
                    vaultID: analyses, vaultName: "Analyses", role: .sourceCorpus,
                    path: "Research/Foo.md", title: "Foo"),
                note(
                    vaultID: analyses, vaultName: "Analyses", role: .sourceCorpus,
                    path: "A|B.md", title: "A|B"),
            ], generation: 1)
        let candidates = try await index.query(
            kind: .wikilink, "", sourcePath: "Draft.md",
            currentVaultID: topics, generation: 1)
        let ambiguous = try #require(candidates.first { $0.path == "Analyses/Research/Foo.md" })
        #expect(ambiguous.availability == .ambiguous)
        #expect(ambiguous.insertion.isEmpty)
        #expect(ambiguous.unavailableReason?.isEmpty == false)
        let unsupported = try #require(candidates.first { $0.path == "Analyses/A|B.md" })
        #expect(unsupported.availability == .unsupportedSyntax)
        #expect(unsupported.insertion.isEmpty)
        #expect(unsupported.unavailableReason?.isEmpty == false)
        let references = try await index.query(
            kind: .analysisReference, "A|B", sourcePath: "Draft.md",
            currentVaultID: topics, generation: 1)
        #expect(references.count == 1)
        #expect(references.first?.availability == .unsupportedSyntax)
        #expect(references.first?.unavailableReason?.isEmpty == false)
    }

    @Test("POSIX normalization handles canonical forms, Turkish I, and CJK")
    func localeStableUnicodeQueries() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(
            notes: [
                note(vaultID: vaultID, path: "NFD/e\u{301}.md", title: "Café"),
                note(vaultID: vaultID, path: "Cities/Istanbul.md", title: "İstanbul"),
                note(vaultID: vaultID, path: "中文/价值.md", title: "价值理论"),
            ], generation: 3)

        #expect(try await index.query(kind: .wikilink, "cafe", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
        #expect(try await index.query(kind: .wikilink, "istanbul", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
        #expect(try await index.query(kind: .wikilink, "价值", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
    }

    @Test("Top-K is globally ordered, input-order independent, bounded, and generation-safe")
    func boundsAndGeneration() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        let notes = (0..<150).map {
            note(vaultID: vaultID, path: "Many/Item \($0).md", title: "Item \($0)")
        }
        await index.replace(notes: Array(notes.reversed()), generation: 9)

        let reversed = try await index.query(
            kind: .wikilink,
            "Item",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 9,
            limit: 1_000
        )
        let stale = try await index.query(
            kind: .wikilink,
            "Item",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 8
        )
        await index.replace(
            notes: Array(notes.dropFirst(75)) + Array(notes.prefix(75)),
            generation: 10
        )
        let rotated = try await index.query(
            kind: .wikilink,
            "Item",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 10,
            limit: 1_000
        )

        let expectedLabels = (0..<100).map { "Item \($0)" }
        #expect(reversed.map(\.label) == expectedLabels)
        #expect(rotated.map(\.label) == expectedLabels)
        #expect(stale.isEmpty)
    }

    @Test("Equal labels use the complete display path before the unique identity tie-break")
    func equalLabelOrdering() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        let notes = [
            note(vaultID: vaultID, path: "Zed/Same.md", title: "Same"),
            note(vaultID: vaultID, path: "Able/Same.md", title: "Same"),
        ]
        await index.replace(notes: notes, generation: 1)

        let result = try await index.query(
            kind: .wikilink,
            "Same",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 1,
            limit: 1
        )

        #expect(result.map(\.path) == ["Topics/Able/Same.md"])
    }

    @Test("Alias matches preserve the canonical target and insert the selected display alias")
    func aliasInsertion() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(
            notes: [
                note(
                    vaultID: vaultID,
                    path: "Value.md",
                    title: "Axiology",
                    aliases: ["Value Theory"]
                )
            ], generation: 4)

        let aliasResults = try await index.query(
            kind: .wikilink,
            "value theory",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 4
        )
        let alias = try #require(aliasResults.first)
        #expect(alias.insertion == "Value")
        #expect(alias.displayText == "Value Theory")
        #expect(alias.label == "Value Theory")

        let canonicalResults = try await index.query(
            kind: .wikilink,
            "axiology",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 4
        )
        let canonical = try #require(canonicalResults.first)
        #expect(canonical.displayText == nil)
    }

    @Test("Analysis references search only Analysis academic fields")
    func analysisReferences() async throws {
        let analysisVaultID = UUID()
        let topicVaultID = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(
            notes: [
                note(
                    vaultID: analysisVaultID,
                    vaultName: "Analyses",
                    role: .sourceCorpus,
                    path: "What We Owe.md",
                    title: "What We Owe to Each Other",
                    authors: ["T. M. Scanlon"],
                    publicationDate: "1998-01-01"
                ),
                note(
                    vaultID: topicVaultID,
                    path: "Scanlon.md",
                    title: "Scanlon"
                ),
            ], generation: 5)

        let results = try await index.query(
            kind: .analysisReference,
            "Scanlon 1998",
            sourcePath: "Draft.md",
            currentVaultID: analysisVaultID,
            generation: 5
        )
        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.insertion == "What We Owe")
        #expect(result.displayText == "T. M. Scanlon 1998")
        #expect(result.detail.contains("What We Owe to Each Other"))
    }

    private func note(
        vaultID: UUID,
        vaultName: String = "Topics",
        role: VaultRole = .topicKnowledge,
        path: String,
        title: String,
        aliases: [String] = [],
        authors: [String] = [],
        publicationDate: String? = nil
    ) -> WorkspaceCatalogNote {
        WorkspaceCatalogNote(
            reference: VaultNoteReference(
                vaultID: vaultID,
                vaultName: vaultName,
                vaultRole: role,
                relativePath: path,
                stableNoteID: UUID().uuidString
            ),
            title: title,
            aliases: aliases,
            authors: authors,
            publicationDate: publicationDate,
            fingerprint: DocumentFingerprint(content: "# \(title)\n"),
            validationWarnings: []
        )
    }
}
