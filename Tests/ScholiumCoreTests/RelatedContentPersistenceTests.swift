import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Persistent related-content projections")
struct RelatedContentPersistenceTests {
    @Test("Encoded projections retain nested Unicode paragraphs and exact CRLF source coordinates")
    func roundTrip() throws {
        let text = "\u{FEFF}---\r\nsummary: needle freedom\r\n---\r\n\r\n# Émotion 😀\r\n\r\n- nested needle freedom.\r\n\r\n> [[目标|行动]]{{needle freedom}}.\r\n"
        let document = NoteDocument(relativePath: "Émotion.md", rawContent: text)
        let prepared = try RelatedContentSourceProjection(document: document)
        let bytes = try prepared.encoded()
        let decoded = try RelatedContentSourceProjection.decode(
            bytes, checksum: RelatedContentSourceProjection.checksum(bytes), sourceUTF16Count: text.utf16.count)
        #expect(decoded.noteScoringDocument.fields == prepared.noteScoringDocument.fields)
        #expect(decoded.noteScoringDocument.fieldLengths == prepared.noteScoringDocument.fieldLengths)
        #expect(decoded.paragraphs.map(\.displayText) == ["nested needle freedom.", "行动 (needle freedom)."])
        #expect(decoded.paragraphs.map(\.range) == prepared.paragraphs.map(\.range))
        #expect(decoded.paragraphs.map { $0.range.line } == [7, 9])
        for (actual, original) in zip(decoded.paragraphs, prepared.paragraphs) {
            #expect(actual.normalizedDisplayText == original.normalizedDisplayText)
            #expect(actual.scoringDocument.fields == original.scoringDocument.fields)
            #expect(actual.scoringDocument.fieldLengths == original.scoringDocument.fieldLengths)
            let range = try #require(
                Range(NSRange(location: actual.range.utf16LowerBound, length: actual.range.utf16UpperBound - actual.range.utf16LowerBound), in: text))
            #expect(String(text[range]).contains("needle freedom"))
        }
        #expect(throws: SearchIndexError.self) {
            try RelatedContentSourceProjection.decode(bytes, checksum: "wrong", sourceUTF16Count: text.utf16.count)
        }
        #expect(throws: SearchIndexError.self) {
            try RelatedContentSourceProjection.decode(bytes, checksum: RelatedContentSourceProjection.checksum(bytes), sourceUTF16Count: 1)
        }
    }

    @Test("Reopened projections and incremental replacement match freshly rebuilt passage results")
    func reopenAndReplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originals = [
            fixture.item("Annotated.md", "# Émotion 😀\r\n\r\n[[Target|行动]]{{needle freedom}}.\r\n"),
            fixture.item("Body.md", "needle freedom ordinary.\r\n\r\nUnrelated prose.\r\n"),
            fixture.item("Metadata.md", "---\r\nsummary: needle freedom\r\n---\r\n\r\nUnrelated prose.\r\n"),
        ]
        try await fixture.seed(originals)
        let reopened = try fixture.index()
        let initial = try await fixture.passages(reopened, documents: originals)
        #expect(Set(initial.map { $0.candidate.note.relativePath }) == ["Annotated.md", "Body.md"])
        #expect(initial == (try TriptychSearchIndex.relatedPassages(fixture.request, sources: fixture.sources(originals))))
        let changed = [
            fixture.item("Annotated.md", "# Émotion 😀\r\n\r\n[[Target|行动]]{{justice reasons}}.\r\n"),
            originals[2],
            fixture.item("Added.md", "new needle freedom account.\r\n"),
        ]
        _ = try await reopened.synchronize(changed)
        let incremental = try await fixture.passages(reopened, documents: changed)
        #expect(incremental.map { $0.candidate.note.relativePath } == ["Added.md"])
        #expect(incremental.map(\.source) == ["new needle freedom account."])
        #expect(incremental == (try TriptychSearchIndex.relatedPassages(fixture.request, sources: fixture.sources(changed))))
        let rebuilt = try fixture.index(databaseURL: fixture.root.appendingPathComponent("rebuilt.sqlite"))
        _ = try await rebuilt.synchronize(changed)
        #expect(try await fixture.passages(rebuilt, documents: changed) == incremental)
        let secondReopen = try fixture.index()
        #expect(try await fixture.passages(secondReopen, documents: changed) == incremental)
    }

    @Test("Damaged projection payload or checksum rebuilds generated state without changing source bytes", arguments: [false, true])
    func corruptionRecovery(damagePayload: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data("\u{FEFF}# Émotion 😀\r\n\r\n[[Target|行动]]{{needle freedom}}.\r\n".utf8)
        let sourceURL = fixture.root.appendingPathComponent("Preserved.md")
        try bytes.write(to: sourceURL)
        let documents = [fixture.item("Preserved.md", String(decoding: bytes, as: UTF8.self))]
        try await fixture.seed(documents)
        try fixture.execute(
            damagePayload
                ? "UPDATE search_documents SET related_projection = X'00';"
                : "UPDATE search_documents SET related_projection_hash = 'incorrect';")
        let recovered = try TriptychSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID, vaults: fixture.vaults)
        #expect(recovered.recoveredCorruption)
        let update = try await recovered.index.synchronize(documents)
        #expect(update.disposition == .recoveredAndRebuilt)
        let actual = try await fixture.passages(recovered.index, documents: documents)
        #expect(actual == (try TriptychSearchIndex.relatedPassages(fixture.request, sources: fixture.sources(documents))))
        #expect(actual.map(\.source) == ["[[Target|行动]]{{needle freedom}}."])
        #expect(try Data(contentsOf: sourceURL) == bytes)
    }

    private struct Fixture {
        let root: URL
        let databaseURL: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")
        var vaults: [RegisteredVault] { [analyses, works] }
        var request: RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: works.id, relativePath: "Draft.md"), source: "needle freedom",
                    focuses: [.init(kind: .selectedPassage, text: "needle freedom")]))
        }

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/related-content-persistence/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search.sqlite")
        }

        func item(_ path: String, _ text: String) -> SearchIndexDocument {
            .init(
                vaultID: analyses.id, vaultName: analyses.name, vaultRole: analyses.role,
                document: NoteDocument(relativePath: path, rawContent: text))
        }

        func index(databaseURL: URL? = nil) throws -> TriptychSearchIndex {
            try .init(databaseURL: databaseURL ?? self.databaseURL, triptychID: triptychID, vaults: vaults)
        }

        func seed(_ documents: [SearchIndexDocument]) async throws {
            let index = try index()
            _ = try await index.synchronize(documents)
        }

        func sources(_ documents: [SearchIndexDocument]) -> [RelatedContentSource] {
            documents.map { item in
                .init(
                    candidate: .init(
                        note: .init(vaultID: item.vaultID, relativePath: item.relativePath),
                        vaultRole: item.vaultRole, title: item.relativePath, fingerprint: item.document.fingerprint,
                        reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))), document: item.document)
            }
        }

        func passages(_ index: TriptychSearchIndex, documents: [SearchIndexDocument]) async throws -> [RelatedContentPassage] {
            try await index.relatedPassages(request, sources: sources(documents))
        }

        func execute(_ sql: String) throws {
            var database: OpaquePointer?
            let opened = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil)
            defer { sqlite3_close(database) }
            try #require(opened == SQLITE_OK)
            try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
