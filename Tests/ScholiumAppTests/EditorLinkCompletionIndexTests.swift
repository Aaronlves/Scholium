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

    @Test("Queries are bounded and stale graph generations return nothing")
    func boundsAndGeneration() async throws {
        let vaultID = UUID()
        let index = EditorLinkCompletionIndex()
        await index.replace(notes: (0..<150).map {
            note(vaultID: vaultID, path: "Many/Item \($0).md", title: "Item \($0)")
        }, generation: 9)

        let current = try await index.query(
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

        #expect(current.count == 100)
        #expect(stale.isEmpty)
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
            zoteroItemKey: nil,
            zoteroSourceIdentity: nil,
            fingerprint: DocumentFingerprint(content: "# \(title)\n"),
            validationWarnings: []
        )
    }
}
