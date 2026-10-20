import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Commit-paced editing source fingerprints")
struct DocumentEditingSourceFingerprintTests {
    @Test("Every assigned snapshot preserves its exact Unicode, BOM and newline identity")
    func exactSnapshotAssignments() throws {
        let decomposed = "\u{FEFF}# Cafe\u{301}\r\nunknown: keep\n尾 😀\r\nEnd"
        let precomposed = "\u{FEFF}# Café\r\nunknown: keep\n尾 😀\r\nEnd"
        try #require(decomposed == precomposed)
        try #require(Data(decomposed.utf8) != Data(precomposed.utf8))
        let session = DocumentSessionModel(key: nil)
        session.editingRevision = DocumentFingerprint(content: "A different disk revision")
        #expect(session.editingSourceFingerprint == DocumentFingerprint(data: Data()))

        for exact in [decomposed, precomposed, "# Café\n尾 😀\n", "# Café\n尾 😀", "", ""] {
            session.editingSource = exact
            let expected = DocumentFingerprint(data: Data(exact.utf8))
            #expect(session.editingSourceFingerprint == expected)
            session.isSavingEdit.toggle()
            #expect(session.editingSourceFingerprint == expected)
            #expect(Data(session.editingSource.utf8) == Data(exact.utf8))
        }
    }

    @Test("A newer checked editor buffer does not change the retained snapshot's identity")
    func checkedBufferCanLeadSnapshot() throws {
        let exact = "\u{FEFF}# Synthetic\r\n尾 😀 e\u{301}\nEnd"
        let session = DocumentSessionModel(key: nil)
        session.editingSource = exact
        let retainedFingerprint = session.editingSourceFingerprint
        let editor = session.editorSession
        editor.loadDocument(exact, documentID: editor.bridgeDocumentID, mode: .source)
        let end = EditorSourceOffsetMap(source: exact).editorUTF16Length
        let generation = editor.generation
        let insertion = "\r\nTyped e\u{301} 😀"

        try #require(
            editor.acceptEditorChanges(
                [.init(from: end, to: end, insert: "\nTyped e\u{301} 😀", exactInsert: insertion)],
                baseGeneration: generation, resultingGeneration: generation + 1))

        let updated = exact + insertion
        #expect(editor.generation == generation + 1)
        #expect(Data(editor.checkedSource.utf8) == Data(updated.utf8))
        #expect(Data(session.editingSource.utf8) == Data(exact.utf8))
        #expect(session.editingSourceFingerprint == retainedFingerprint)
        session.editingSource = editor.checkedSource
        #expect(session.editingSourceFingerprint == DocumentFingerprint(data: Data(updated.utf8)))
        #expect(session.editingSourceFingerprint != retainedFingerprint)
    }

    @Test("An early publication read cannot retain the previous snapshot's fingerprint after assignment")
    func publicationReadCannotPoisonNextSnapshot() {
        let first = "\u{FEFF}# Cafe\u{301}\r\nFirst"
        let next = "\u{FEFF}# Café\r\nSecond"
        let session = DocumentSessionModel(key: nil)
        session.editingSource = first
        let firstFingerprint = session.editingSourceFingerprint
        var observed: [DocumentFingerprint] = []
        let observation = session.objectWillChange.sink {
            observed.append(session.editingSourceFingerprint)
        }
        defer { observation.cancel() }

        session.editingSource = next

        #expect(observed == [firstFingerprint])
        #expect(session.editingSourceFingerprint == DocumentFingerprint(data: Data(next.utf8)))
        #expect(session.editingSourceFingerprint != firstFingerprint)
        #expect(Data(session.editingSource.utf8) == Data(next.utf8))
    }
}
