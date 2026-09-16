import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Paragraph Search")
struct ParagraphSearchTests {
    @Test(
        "Malformed binary paragraph offset maps rebuild only the generated index",
        arguments: [false, true])
    func corruptParagraphOffsetMapRecovery(outOfBounds: Bool) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/paragraph-codec-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: root.path)
        let triptychID = UUID()
        let url = root.appendingPathComponent("search.sqlite")
        let source = "\u{FEFF}中文😀 alpha beta\r\n\r\nalpha gamma\r\n"
        let document = SearchIndexDocument(
            vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
            document: NoteDocument(relativePath: "Exact.md", rawContent: source))
        var index: TriptychSearchIndex? = try .init(
            databaseURL: url, triptychID: triptychID, vaults: [vault])
        _ = try await index?.synchronize([document])
        index = nil
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        var statement: OpaquePointer?
        #expect(
            sqlite3_prepare_v2(database, "SELECT paragraphs FROM search_documents;", -1, &statement, nil)
                == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        let stored = String(cString: try #require(sqlite3_column_text(statement, 0)))
        sqlite3_finalize(statement)
        var paragraphs = try #require(
            JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [[String: Any]])
        var first = try #require(paragraphs.first)
        var segments = try #require(first["segments"] as? [[String: Any]])
        _ = try #require(segments.first?["offsetMap"] as? String)
        // A truncated record, or a well-formed record whose normalized upper
        // bound is outside the owning segment. Format and semantic checks differ.
        var malformed = Data([0x53, 0x4f, 0x4d, 0x31, 1, 0, 0, 0])
        if outOfBounds {
            for value: UInt64 in [0, 100_000, 0, 1] {
                var littleEndian = value.littleEndian
                withUnsafeBytes(of: &littleEndian) { malformed.append(contentsOf: $0) }
            }
        }
        segments[0]["offsetMap"] = malformed.base64EncodedString()
        first["segments"] = segments
        paragraphs[0] = first
        let damaged = String(
            decoding: try JSONSerialization.data(withJSONObject: paragraphs), as: UTF8.self)
        let escaped = damaged.replacingOccurrences(of: "'", with: "''")
        #expect(
            sqlite3_exec(
                database, "UPDATE search_documents SET paragraphs = '\(escaped)';", nil, nil, nil)
                == SQLITE_OK)
        sqlite3_close(database)
        let reopened = try TriptychSearchIndex.openRecovering(
            databaseURL: url, triptychID: triptychID, vaults: [vault])
        #expect(reopened.recoveredCorruption)
        _ = try await reopened.index.synchronize([document])
        let response = try await reopened.index.testSearch(
            .init(
                query: "paragraph:(alpha NOT beta)",
                presentationScope: .triptych, executionScope: .triptych, limit: 20))
        let result = try #require(response.noteResults.first)
        #expect(result.relativePath == "Exact.md")
        #expect(result.fingerprint == document.document.fingerprint)
        #expect(result.paragraphRanges.first == document.projection.paragraphs.last?.range)
        #expect(Data(document.document.rawContent.utf8) == Data(source.utf8))
    }

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
