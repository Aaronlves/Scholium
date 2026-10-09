import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Search excerpts explain successful source matches")
struct SearchExcerptTests {
    @Test("A passage covering the query replaces a title-only excerpt without changing identity order")
    func queryCoverageAndIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source =
            "Emotion is mentioned incidentally.\n\n"
            + String(repeating: "emotion ", count: 1_500)
            + "\n\nEmotion theory concerns the intentional character of feeling."
        _ = try await index.synchronize([
            fixture.note("Emotion.md", source),
            fixture.note("Emotion theory.md", "A separate discussion."),
        ])
        let response = try await index.testSearch(fixture.request("emotion theory"))
        #expect(response.noteResults.map(\.relativePath) == ["Emotion theory.md", "Emotion.md"])
        #expect(response.noteResults.first?.rankReason == .exactTitle)
        let result = try #require(response.noteResults.last)
        #expect(result.matchedField == .body)
        #expect(result.snippet.contains("Emotion theory concerns"))
        #expect(Set(highlightedText(result).map { $0.lowercased() }) == ["emotion", "theory"])
        let range = try #require(result.sourceRange)
        #expect(sourceText(source, range) == "Emotion")
        #expect(range.utf16LowerBound == (source as NSString).range(of: "Emotion theory").location)
        let reversed = try await index.testSearch(fixture.request("theory emotion"))
        let reversedResult = try #require(reversed.noteResults.first { $0.relativePath == "Emotion.md" })
        #expect(reversedResult.snippet == result.snippet)
        #expect(reversedResult.sourceRange == result.sourceRange)
    }

    @Test("Highlights honor explicit fields in both clause orders")
    func fieldScopedHighlights() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.note("Reason emotion.md", "Emotion can provide a reason for action.")
        ])
        let titleResponse = try await index.testSearch(fixture.request("title:reason AND body:emotion"))
        let title = try #require(titleResponse.noteResults.first)
        #expect(title.matchedField == .title)
        #expect(highlightedText(title) == ["Reason"])
        #expect(title.snippet.contains("emotion"))
        let bodyResponse = try await index.testSearch(fixture.request("body:emotion AND title:reason"))
        let body = try #require(bodyResponse.noteResults.first)
        #expect(body.matchedField == .body)
        #expect(highlightedText(body) == ["Emotion"])
        #expect(body.snippet.contains("reason"))
    }

    @Test("An unsuccessful Boolean branch cannot select or highlight an excerpt")
    func successfulBranchesOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = "Emotion theory receives extended discussion.\n\nAgency concerns action."
        _ = try await index.synchronize([fixture.note("Discussion.md", source)])
        let response = try await index.testSearch(
            fixture.request(
                "body:agency OR (body:emotion AND body:theory AND body:missing)"))
        let result = try #require(response.noteResults.first)
        #expect(highlightedText(result) == ["Agency"])
        #expect(result.snippet.contains("Agency concerns action"))
        let range = try #require(result.sourceRange)
        #expect(sourceText(source, range) == "Agency")
    }

    @Test("Compactness measures visible whitespace, so the chosen excerpt includes its anchor and both terms")
    func collapsedWhitespaceDoesNotInventCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source =
            "freedom" + String(repeating: " ", count: 400) + "autonomy. "
            + String(repeating: "context ", count: 40) + "freedom autonomy together."
        _ = try await index.synchronize([fixture.note("Discussion.md", source)])
        let response = try await index.testSearch(fixture.request("body:freedom body:autonomy"))
        let result = try #require(response.noteResults.first)
        #expect(result.snippet.contains("freedom autonomy together"))
        #expect(Set(highlightedText(result)) == ["freedom", "autonomy"])
        #expect(result.snippet.count <= 240)
        let range = try #require(result.sourceRange)
        #expect(range.utf16LowerBound == (source as NSString).range(of: "freedom autonomy together").location)
        #expect(sourceText(source, range) == "freedom")
    }

    @Test("Late bilingual passages retain original graphemes and exact BOM/CRLF source locations")
    func unicodeSourceLocations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source =
            "\u{FEFF}# Ethics\r\n\r\nCafé is mentioned. " + String(repeating: "context ", count: 50)
            + "\r\n😀Cafe\u{301} concerns 行动理由 and judgment.\r\n"
        _ = try await index.synchronize([fixture.note("Ethics.md", source)])
        let response = try await index.testSearch(fixture.request("body:cafe body:行动理由"))
        let result = try #require(response.noteResults.first)
        #expect(result.snippet.contains("Cafe\u{301} concerns 行动理由"))
        #expect(Set(highlightedText(result)) == ["Cafe\u{301}", "行动理由"])
        #expect(result.snippet.count <= 240)
        let range = try #require(result.sourceRange)
        #expect(sourceText(source, range) == "Cafe\u{301}")
        #expect(range.line == 4)
        #expect(result.fingerprint == DocumentFingerprint(content: source))
        let reopened = try fixture.index()
        let restored = try await reopened.testSearch(fixture.request("body:cafe body:行动理由"))
        #expect(restored.noteResults.first?.sourceRange == result.sourceRange)
        #expect(restored.noteResults.first?.highlights == result.highlights)
    }

    @Test("Repeated normalized predicates do not outweigh a passage covering two different predicates")
    func distinctPredicateCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.note(
                "Discussion.md",
                "Café supplies an example. " + String(repeating: "context ", count: 50)
                    + "\n\nAgency and reason concern action.")
        ])
        let baseline = try await index.testSearch(fixture.request("body:cafe OR body:agency OR body:reason"))
        let repeated = try await index.testSearch(
            fixture.request(
                "body:cafe OR body:café OR body:CAFE OR body:agency OR body:reason"))
        let result = try #require(repeated.noteResults.first)
        #expect(result.snippet.contains("Agency and reason"))
        #expect(Set(highlightedText(result)) == ["Agency", "reason"])
        #expect(result.snippet == baseline.noteResults.first?.snippet)
        #expect(result.sourceRange == baseline.noteResults.first?.sourceRange)
    }

    @Test("This Note keeps each occurrence anchored to its own predicate")
    func currentNoteOccurrenceAnchors() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = "Agency and emotion explain emotion."
        let response = try await index.testSearch(
            .init(
                query: "body:agency OR body:emotion", presentationScope: .thisNote,
                executionScope: .currentNote(
                    .init(
                        noteID: .init(vaultID: fixture.vault.id, relativePath: "Current.md"),
                        editorSessionID: UUID(), source: source, editorRevision: 1)), limit: 20))
        #expect(response.noteResults.count == 3)
        for result in response.noteResults {
            let range = try #require(result.sourceRange)
            if sourceText(source, range) == "emotion" {
                #expect(highlightedText(result) == ["Agency", "emotion"])
                let occurrence = try #require(result.highlights.last)
                #expect(occurrence.utf16LowerBound == range.utf16LowerBound)
            }
        }
    }

    private func highlightedText(_ result: NoteSearchResult) -> [String] {
        result.highlights.map {
            (result.snippet as NSString).substring(
                with: NSRange(
                    location: $0.utf16LowerBound, length: $0.utf16UpperBound - $0.utf16LowerBound))
        }
    }

    private func sourceText(_ source: String, _ range: SearchSourceRange) -> String {
        (source as NSString).substring(
            with: NSRange(
                location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound))
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")

        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/search-excerpt-tests/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func index() throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptychID, vaults: [vault])
        }

        func note(_ path: String, _ source: String) -> SearchIndexDocument {
            .init(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: .init(relativePath: path, rawContent: source))
        }

        func request(_ query: String) -> SearchRequest {
            .init(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 20)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
