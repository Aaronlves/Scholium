import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Paragraph Search")
struct ParagraphSearchTests {
    @Test("Existential paragraph predicates keep containers, negation, and exact ranges distinct")
    func paragraphSemantics() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
            ".build/paragraph-search-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: root.path)
        let triptych = UUID()
        let documents = [
            ("Same.md", "alpha beta\n\nalpha gamma"), ("Split.md", "alpha\n\nbeta"),
            ("List.md", "- alpha beta\n"), ("Quote.md", "> alpha beta\n"),
            ("Code.md", "```\nalpha beta\n```"), ("Heading.md", "# alpha beta\n"),
            ("Footnote.md", "text[^1]\n\n[^1]: alpha beta\n"),
            ("Math.md", "$$\nalpha beta\n$$"), ("HTML.md", "<div>alpha beta</div>"),
            ("Annotation.md", "alpha [[Target]]{{beta}}"),
            ("Huge.md", "alpha " + String(repeating: "filler ", count: 10000) + "beta"),
            ("Unclosed.md", "---\nstatus: draft\nalpha beta"),
        ].map { path, source in
            SearchIndexDocument(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: NoteDocument(relativePath: path, rawContent: source))
        }
        func index(_ name: String) throws -> TriptychSearchIndex {
            try .init(databaseURL: root.appendingPathComponent(name), triptychID: triptych, vaults: [vault])
        }
        func request(_ query: String) -> SearchRequest { .init(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 100) }
        let active = try index("index.sqlite")
        _ = try await active.synchronize(documents)
        let same = try await active.testSearch(request("paragraph:(alpha AND beta)"))
        #expect(Set(same.noteResults.map(\.relativePath)) == ["Same.md", "Annotation.md", "Huge.md"])
        #expect(same.noteResults.allSatisfy { $0.paragraphRanges.count == 1 && !$0.highlights.isEmpty && $0.matchedField == .body })
        let annotation = try await active.testSearch(request("path:Annotation.md AND paragraph:(beta)"))
        let annotationHit = try #require(annotation.noteResults.first)
        #expect(annotationHit.matchedFields.contains(.linkAnnotation))
        let annotationOnly = try await active.testSearch(request("paragraph:(beta)"))
        #expect(annotationOnly.noteResults.first { $0.relativePath == "Annotation.md" }?.matchedField == .linkAnnotation)
        #expect(try await active.testSearch(request("paragraph:(missingterm)")).indeterminateDocumentCount == 1)
        let localNot = try await active.testSearch(request("paragraph:(alpha NOT beta)"))
        #expect(Set(localNot.noteResults.map(\.relativePath)) == ["Same.md", "Split.md"])
        let outerNot = try await active.testSearch(request("NOT paragraph:(alpha AND beta)"))
        #expect(!outerNot.noteResults.contains { ["Same.md", "Huge.md", "Unclosed.md"].contains($0.relativePath) })
        #expect(outerNot.indeterminateDocumentCount == 1)
        #expect(try await active.testSearch(request("paragraph:(missingterm)")).indeterminateDocumentCount == 1)
        #expect(outerNot.noteResults.allSatisfy { $0.paragraphRanges.isEmpty && $0.highlights.isEmpty && $0.sourceRange == nil })
        let both = try await active.testSearch(request("paragraph:(alpha)"))
        let sameNote = try #require(both.noteResults.first { $0.relativePath == "Same.md" })
        #expect(sameNote.paragraphRanges.count == 2)
        let source = "\u{FEFF}中文😀 alpha beta\r\n\r\nalpha gamma\r\n"
        let snapshot = SearchSourceSnapshot(
            noteID: .init(vaultID: vault.id, relativePath: "Unsaved.md"), editorSessionID: UUID(), source: source, editorRevision: 1)
        let occurrence = try await active.testSearch(
            .init(query: "paragraph:(alpha NOT beta)", presentationScope: .thisNote, executionScope: .currentNote(snapshot), limit: 100))
        #expect(occurrence.results.count == 1)
        let span = try #require(occurrence.noteResults.first?.sourceRange)
        #expect(span.utf16LowerBound == (source as NSString).range(of: "alpha", options: .backwards).location)
        let reopened = try index("index.sqlite")
        #expect(try await reopened.testSearch(request("paragraph:(alpha)")).noteResults.map(\.paragraphRanges) == both.noteResults.map(\.paragraphRanges))
        var updated = documents
        updated[0] = .init(
            vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: NoteDocument(relativePath: "Same.md", rawContent: "alpha\n\nbeta"))
        _ = try await active.synchronize(updated)
        let rebuilt = try index("rebuilt.sqlite")
        _ = try await rebuilt.synchronize(updated)
        let incremental = try await active.testSearch(request("paragraph:(alpha AND beta)"))
        let clean = try await rebuilt.testSearch(request("paragraph:(alpha AND beta)"))
        #expect(incremental.noteResults.map(\.relativePath) == clean.noteResults.map(\.relativePath))
        #expect(incremental.noteResults.map(\.paragraphRanges) == clean.noteResults.map(\.paragraphRanges))
        var corruptIndex: TriptychSearchIndex? = try index("corrupt.sqlite")
        _ = try await corruptIndex?.synchronize(updated)
        corruptIndex = nil
        var database: OpaquePointer?
        #expect(sqlite3_open(root.appendingPathComponent("corrupt.sqlite").path, &database) == SQLITE_OK)
        #expect(sqlite3_exec(database, "UPDATE search_documents SET paragraphs = '[{}]';", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let recovered = try TriptychSearchIndex.openRecovering(
            databaseURL: root.appendingPathComponent("corrupt.sqlite"), triptychID: triptych, vaults: [vault])
        #expect(recovered.recoveredCorruption)
        _ = try await recovered.index.synchronize(updated)
        #expect(
            try await recovered.index.testSearch(request("paragraph:(alpha AND beta)")).noteResults.map(\.relativePath) == clean.noteResults.map(\.relativePath)
        )
    }
}
