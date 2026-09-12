import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Writing suggestions") @MainActor
struct EditorWritingSuggestionsTests {
    private let vault = UUID()
    private func note(_ title: String, aliases: [String] = []) -> WorkspaceCatalogNote {
        .init(
            reference: .init(
                vaultID: vault, vaultName: "Topics", vaultRole: .topicKnowledge,
                relativePath: title + ".md", stableNoteID: nil), title: title, aliases: aliases,
            fingerprint: .init(content: "fixture"), validationWarnings: [])
    }
    @Test("Completes whole terms and Chinese suffixes without matching arbitrary Latin word endings")
    func terms() {
        let owner = EditorWritingSuggestions()
        let notes = [note("控制条件（QA材料）", aliases: ["控制条件"]), note("responsibility", aliases: ["moral responsibility"])]
        #expect(owner.terms("这里的控制", notes: notes).first?.insertion == "控制条件")
        #expect(owner.terms("这里的控制", notes: notes).first?.replacementUTF16Count == 2)
        #expect(owner.terms("moral res", notes: notes).first?.insertion == "moral responsibility")
        #expect(owner.terms("express", notes: notes).isEmpty)
        #expect(owner.terms("responsibility", notes: notes).isEmpty)
        #expect(owner.terms("  ", notes: notes).isEmpty)
    }
    @Test("Note titles are not prose terms unless explicitly declared as an alias or keyword")
    func titlesAreNotTerms() {
        let owner = EditorWritingSuggestions()
        #expect(owner.terms("自由", notes: [note("自由（QA材料）")]).isEmpty)
        #expect(owner.terms("控制", notes: [note("控制条件")]).isEmpty)
        #expect(owner.terms("控制", notes: [note("控制条件（QA材料）", aliases: ["控制条件"])]).first?.label == "控制条件")
    }

    @Test("Vocabulary follows current YAML and removes deleted Notes")
    func vocabulary() {
        let owner = EditorWritingSuggestions()
        let base = note("A")
        let document = NoteDocument(relativePath: "A.md", rawContent: "---\nkeywords: [控制条件]\n---\nBody")
        let catalog = WorkspaceCatalogNote(
            reference: base.reference, title: base.title,
            fingerprint: document.fingerprint, validationWarnings: [])
        owner.replace([
            .init(
                id: .init(vaultID: vault, relativePath: "A.md"),
                stableIdentity: .unresolved, document: document,
                fileMetadata: .init(byteCount: document.rawContent.utf8.count, creationDate: nil, modificationDate: nil),
                graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
        ])
        #expect(owner.terms("控制", notes: [catalog]).first?.insertion == "控制条件")
        owner.replace([])
        #expect(owner.terms("控制", notes: [catalog]).isEmpty)
    }
}
