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
            "Foo",
            sourcePath: "Folder/Source.md",
            currentVaultID: firstVault,
            generation: 7
        )

        #expect(results.first { $0.label == "Foo local" }?.insertion == "Foo")
        #expect(results.first { $0.label == "Foo other" }?.insertion == "Other/Foo")
        #expect(results.first { $0.label == "Foo cross" }?.isAmbiguous == true)
    }

    @Test("POSIX normalization handles canonical forms, Turkish I, and CJK")
    func localeStableUnicodeQueries() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(notes: [
            note(vaultID: vaultID, path: "NFD/e\u{301}.md", title: "Café"),
            note(vaultID: vaultID, path: "Cities/Istanbul.md", title: "İstanbul"),
            note(vaultID: vaultID, path: "中文/价值.md", title: "价值理论"),
        ], generation: 3)

        #expect(try await index.query("cafe", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
        #expect(try await index.query("istanbul", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
        #expect(try await index.query("价值", sourcePath: "Source.md", currentVaultID: vaultID, generation: 3).count == 1)
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
            "Item",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 9,
            limit: 1_000
        )
        let stale = try await index.query(
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
            "Same",
            sourcePath: "Source.md",
            currentVaultID: vaultID,
            generation: 1,
            limit: 1
        )

        #expect(result.map(\.path) == ["Topics/Able/Same.md"])
    }

    private func note(
        vaultID: UUID,
        vaultName: String = "Topics",
        path: String,
        title: String
    ) -> WorkspaceCatalogNote {
        WorkspaceCatalogNote(
            reference: VaultNoteReference(
                vaultID: vaultID,
                vaultName: vaultName,
                vaultRole: .topicKnowledge,
                relativePath: path,
                stableNoteID: UUID().uuidString
            ),
            title: title,
            fingerprint: DocumentFingerprint(content: "# \(title)\n"),
            validationWarnings: []
        )
    }
}
