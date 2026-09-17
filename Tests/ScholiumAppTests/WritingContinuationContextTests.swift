import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Writing continuation context")
struct WritingContinuationContextTests {
    private func capture(_ source: String, caret: Int) throws -> MarkdownSourceSelectionSnapshot {
        let map = EditorSourceOffsetMap(source: source)
        let position = try #require(map.editorUTF16Offset(forSourceUTF16Offset: caret))
        return try MarkdownWritingContextProjection.capture(
            source: source, selections: [.init(anchor: position, head: position)], paragraph: true)
    }

    @Test("Uses exact current paragraph, with before and after kept separate")
    func exactParagraph() throws {
        let source = "\u{feff}---\r\nkeywords: [控制]\r\n---\r\n\r\nEarlier paragraph.\r\n\r\n控制😀 moral res ends here.\r\n\r\nLater paragraph."
        let caret = (source as NSString).range(of: " ends here.").location
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(context.before == "控制😀 moral res")
        #expect(context.after == " ends here.\r\n")
        #expect(!context.focus.contains("Earlier"))
        #expect(!context.focus.contains("Later"))
        #expect(!context.focus.contains("keywords"))
        #expect(!context.focus.contains("res "))
    }

    @Test("Retrieval focus ignores the growing final Latin word and retains Chinese wording")
    func stableFocus() throws {
        let short = "moral res"
        let longer = "moral respon"
        let a = try #require(WritingContinuationContext(snapshot: capture(short, caret: short.utf16.count), caret: short.utf16.count))
        let b = try #require(WritingContinuationContext(snapshot: capture(longer, caret: longer.utf16.count), caret: longer.utf16.count))
        #expect(a.focus == b.focus)
        let chinese = "这里讨论控制条件"
        let context = try #require(WritingContinuationContext(snapshot: capture(chinese, caret: chinese.utf16.count), caret: chinese.utf16.count))
        #expect(context.focus == chinese)
    }

    @Test("Bounds context without splitting emoji, combining marks or exact newlines")
    func bounds() throws {
        #expect(WritingContinuationContext.bounded("ab😀", limit: 3) == "ab")
        #expect(WritingContinuationContext.bounded("😀ab", limit: 3, suffix: true) == "ab")
        #expect(WritingContinuationContext.bounded("e\u{301}x", limit: 1).isEmpty)
        #expect(WritingContinuationContext.bounded("\r\nx", limit: 2) == "\r\n")
        let source = String(repeating: "中文😀", count: 1_000)
        let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: source.utf16.count), caret: source.utf16.count))
        #expect(context.before.utf16.count <= WritingContinuationContext.maximumBeforeUTF16Count)
    }

    @Test("Rejects a stale caret outside the captured paragraph")
    func invalidCaret() throws {
        let source = "First.\n\nSecond."
        let snapshot = try capture(source, caret: source.utf16.count)
        #expect(WritingContinuationContext(snapshot: snapshot, caret: 0) == nil)
    }

    @Test("Background retains role and source attribution, excludes changed sources, and stays bounded")
    func background() {
        let vault = UUID()
        func material(_ name: String, role: VaultRole, text: String) -> (RelatedContentPassage, WorkspaceCatalogNote) {
            let reference = VaultNoteReference(vaultID: vault, vaultName: "Fixture", vaultRole: role, relativePath: name + ".md")
            let candidate = RelatedContentCandidate(
                note: .init(vaultID: vault, relativePath: reference.relativePath), vaultRole: role,
                title: name, fingerprint: .init(content: text),
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["control"])])))
            let passage = RelatedContentPassage(
                candidate: candidate,
                range: .init(
                    utf16LowerBound: 0, utf16UpperBound: text.utf16.count,
                    line: 1, column: 1, endLine: 1, endColumn: text.utf16.count + 1),
                source: text, displayText: text, excerpt: text, excerptMatches: [], matches: [])
            return (passage, .init(reference: reference, title: name, fingerprint: candidate.fingerprint, validationWarnings: []))
        }
        let work = material("Researcher writing", role: .draftProject, text: String(repeating: "control conditions 😀 ", count: 100))
        let topic = material("Topic", role: .topicKnowledge, text: "An authored concept distinction.")
        let source = material("Changed source", role: .sourceCorpus, text: "Old analysis text.")
        let response = RelatedContentResponse(
            requestID: UUID(), seedFingerprint: .init(content: "seed"), freshnessToken: .init("fixture"),
            availability: .unavailable, state: .current, identityCandidates: [], lexicalCandidates: [],
            identityHasMore: false, lexicalHasMore: false, passages: [work.0, work.0, source.0, topic.0])
        let stale = WorkspaceCatalogNote(
            reference: source.1.reference, title: source.1.title,
            fingerprint: .init(content: "new source"), validationWarnings: [])
        let result = WritingContinuationContext.background(response, catalog: [work.1, stale, topic.1])
        #expect(result.count == 2)
        #expect(result[0].contains("Role: draft_project"))
        #expect(result[0].contains("Revision: " + work.0.candidate.fingerprint.sha256))
        #expect(!result.joined().contains("Old analysis"))
        #expect(result.joined().utf16.count <= WritingContinuationContext.maximumBackgroundUTF16Count)
    }

    @Test("Retrieval unavailable or empty does not manufacture background")
    func noBackground() {
        let response = RelatedContentResponse(
            requestID: UUID(), seedFingerprint: .init(content: "seed"), freshnessToken: .init("fixture"),
            availability: .unavailable, state: .stale, identityCandidates: [], lexicalCandidates: [],
            identityHasMore: false, lexicalHasMore: false)
        #expect(WritingContinuationContext.background(response, catalog: []).isEmpty)
    }

    @Test("Cached background binds the full seed revision even when focus is unchanged")
    @MainActor func cacheRevision() {
        let triptych = UUID()
        let runtime = TriptychRuntimeIdentity(triptychID: triptych, activationID: UUID())
        let note = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Fixture.md")
        let generation = SearchGenerationID(triptychID: triptych, sequence: 1, sourceManifestHash: "fixture")
        func key(_ source: String) -> WritingContinuationContextCache.Key {
            .init(
                runtime: runtime, note: note, generation: generation,
                seedFingerprint: .init(content: source), focus: "moral")
        }
        let cache = WritingContinuationContextCache()
        let response = RelatedContentResponse(
            requestID: UUID(), seedFingerprint: .init(content: "moral res"), freshnessToken: .init("fixture"),
            availability: .unavailable, state: .empty, identityCandidates: [], lexicalCandidates: [],
            identityHasMore: false, lexicalHasMore: false)
        cache.replace(key: key("moral res"), response: response)
        #expect(cache.value(for: key("moral res"))?.requestID == response.requestID)
        #expect(cache.value(for: key("moral respon")) == nil)
    }
}
