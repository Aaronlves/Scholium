import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Current Note catalog for Chat") @MainActor
struct AgentChatNoteCatalogTests {
    @Test("The complete material and picker lists preserve ordering and exact first activity identity")
    func completeListsAndActivityIdentity() {
        let duplicateID = UUID().uuidString
        let first = note(title: "Note 10", path: "first.md", stableID: duplicateID)
        let second = note(title: "Alpha", path: "second.md", stableID: duplicateID)
        let tieOne = note(title: "Note 2", path: "one.md")
        let tieTwo = note(title: "Note 2", path: "two.md")
        let notes = [first, tieOne, second, tieTwo, note(stableID: nil), note(stableID: "invalid")]
        let catalog = AgentChatNoteCatalog(notes: notes)
        #expect(catalog.orderedNotes.map(\.id) == [second, tieOne, tieTwo, first].map(\.id))
        #expect(catalog.note(UUID(uuidString: duplicateID)!)?.id == first.id)
        #expect(catalog.materialCandidates.count == 7)
        #expect(catalog.materialCandidates.prefix(4).map(\.title) == ["Alpha", "Note 2", "Note 2", "Note 10"])
        #expect(catalog.materialCandidates.suffix(3).map(\.id) == ["material:file", "material:note-picker", "material:selection"])
        #expect(catalog.matchingNotes(query: "  ").map(\.id) == catalog.orderedNotes.map(\.id))
        #expect(catalog.matchingNotes(query: "NOTE 2").map(\.id) == [tieOne.id, tieTwo.id])
        #expect(catalog.matchingNotes(query: "first.md").map(\.id) == [first.id])
        #expect(catalog.matchingNotes(query: "missing").isEmpty)
        for candidate in catalog.materialCandidates.prefix(4) {
            guard case .note(let note) = candidate.action else {
                Issue.record("Expected the exact current Note")
                continue
            }
            #expect(catalog.orderedNotes.contains { $0.reference == note.reference && $0.fingerprint == note.fingerprint })
        }
    }

    @Test("Reuse follows complete ordered source metadata, exact Unicode bytes and locale")
    func exactCohortInvalidation() {
        let cache = AgentChatNoteCatalogCache()
        let base = note()
        let initial = cache.catalog(notes: [base], localeIdentifier: "en")
        #expect(cache.catalog(notes: [base], localeIdentifier: "en") === initial)
        // Swift String equality considers these spellings equivalent. The
        // projected source path and title must retain the new exact spelling.
        #expect(base.title == "é" && base.reference.relativePath == "é.md")
        let changes = [
            note(title: "é"), note(path: "é.md"), note(source: "changed source"),
            note(vaultID: UUID()), note(vaultName: "Other vault"), note(role: .sourceCorpus),
            note(stableID: nil), note(stableID: UUID().uuidString),
            note(aliases: ["é"]), note(authors: ["é"]), note(publicationDate: "é"),
            note(warnings: ["é"]),
        ]
        for changed in changes {
            let original = cache.catalog(notes: [base], localeIdentifier: "en")
            let replacement = cache.catalog(notes: [changed], localeIdentifier: "en")
            #expect(replacement !== original)
            #expect(cache.catalog(notes: [changed], localeIdentifier: "en") === replacement)
            if changed.reference.stableNoteID == nil {
                #expect(replacement.orderedNotes.isEmpty)
            } else {
                #expect(replacement.orderedNotes.first?.title.utf8.elementsEqual(changed.title.utf8) == true)
                #expect(replacement.orderedNotes.first?.reference.relativePath.utf8.elementsEqual(changed.reference.relativePath.utf8) == true)
                #expect(replacement.orderedNotes.first?.fingerprint == changed.fingerprint)
            }
        }
        let beforeLocale = cache.catalog(notes: [base], localeIdentifier: "en")
        #expect(cache.catalog(notes: [base], localeIdentifier: "zh") !== beforeLocale)
        let second = note(title: "Another", path: "other.md", stableID: base.reference.stableNoteID)
        let beforeOrder = cache.catalog(notes: [base, second])
        let afterOrder = cache.catalog(notes: [second, base])
        #expect(afterOrder !== beforeOrder)
        #expect(afterOrder.note(UUID(uuidString: base.reference.stableNoteID!)!)?.id == second.id)
        let emptied = cache.catalog(notes: [])
        #expect(emptied.orderedNotes.isEmpty && emptied.materialCandidates.count == 3)
    }

    @Test("Unidentified and runtime activities do not construct a Note catalog")
    func activityLookupIsLazyAndScoped() {
        let note = note(title: "", path: "Exact.md")
        let noteID = UUID(uuidString: note.reference.stableNoteID!)!
        var constructions = 0
        func catalog() -> AgentChatNoteCatalog {
            constructions += 1
            return AgentChatNoteCatalog(notes: [note])
        }
        let file = AgentChatActivity.File(path: note.reference.relativePath, noteID: noteID, effect: .read)
        let runtime = AgentChatActivity(kind: .read, source: .runtime, files: [file])
        #expect(AgentChatActivityProjection.noteTarget(runtime, catalog: catalog()) == nil)
        let unidentified = AgentChatActivity(kind: .read, source: .scholium, files: [.init(path: "Exact.md", effect: .read)])
        #expect(AgentChatActivityProjection.noteTarget(unidentified, catalog: catalog()) == nil)
        let multiple = AgentChatActivity(kind: .read, source: .scholium, files: [file, file])
        #expect(AgentChatActivityProjection.noteTarget(multiple, catalog: catalog()) == nil)
        #expect(constructions == 0)
        let known = AgentChatActivity(kind: .read, source: .scholium, files: [file])
        let target = AgentChatActivityProjection.noteTarget(known, catalog: catalog())
        #expect(constructions == 1 && target?.title == "Exact.md")
        #expect(target?.noteID == noteID && target?.vaultID == note.reference.vaultID)
    }

    private func note(
        title: String = "e\u{301}", path: String = "e\u{301}.md",
        stableID: String? = "22222222-2222-2222-2222-222222222222",
        vaultID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        vaultName: String = "Topics", role: VaultRole = .topicKnowledge, source: String = "source",
        aliases: [String] = ["e\u{301}"], authors: [String] = ["e\u{301}"],
        publicationDate: String? = "e\u{301}", warnings: [String] = ["e\u{301}"]
    ) -> WorkspaceCatalogNote {
        .init(
            reference: .init(vaultID: vaultID, vaultName: vaultName, vaultRole: role, relativePath: path, stableNoteID: stableID),
            title: title, aliases: aliases, authors: authors, publicationDate: publicationDate,
            fingerprint: .init(content: source), validationWarnings: warnings)
    }
}
