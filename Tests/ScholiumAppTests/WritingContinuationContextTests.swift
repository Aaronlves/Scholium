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
            source: source, selections: [.init(anchor: position, head: position)], mode: .selectionOrParagraph)
    }

    @Test("A distant opener never admits a plain-looking hidden paragraph, while long ordinary prose remains readable", arguments: ["\n", "\r\n"])
    func distantHiddenParagraph(ending: String) throws {
        let padding = String(repeating: "Ordinary padding." + ending, count: 2_500)
        for opener in ["```swift", "~~~", "$$", "Earlier \\\\$hidden", "Earlier %%", "<!--", "<div>"] {
            let prefix = opener + ending + padding + ending
            let source = prefix + "Hidden res" + ending + ending + "Still hidden." + ending
            let caret = prefix.utf16.count + "Hidden res".utf16.count
            #expect(WritingContinuationContext(snapshot: try capture(source, caret: caret), caret: caret) == nil)
        }
        let source = padding + ending + "Readable res"
        let caret = source.utf16.count
        let context = try #require(WritingContinuationContext(snapshot: try capture(source, caret: caret), caret: caret))
        #expect(context.before == "Readable res")
        #expect(context.after.isEmpty)
        #expect(source.utf16.count > MarkdownReadableWritingRange.maximumFragmentUTF16Count)
        let escaped = "Earlier \\$price" + ending + padding + ending + "Readable res"
        let escapedContext = try #require(
            WritingContinuationContext(snapshot: try capture(escaped, caret: escaped.utf16.count), caret: escaped.utf16.count))
        #expect(escapedContext.before == "Readable res")
    }

    @Test("A distant comment's closing tail never joins the readable paragraph", arguments: ["\n", "\r\n"])
    func distantCommentClosingTail(ending: String) throws {
        let prefix = "<!--" + ending + String(repeating: "Hidden padding." + ending, count: 2_500) + ending
        let source = prefix + "Hidden last --> Readable res"
        let caret = source.utf16.count
        let context = try #require(WritingContinuationContext(snapshot: try capture(source, caret: caret), caret: caret))
        #expect(context.before == " Readable res")
        #expect(context.after.isEmpty)
        #expect(!context.focus.contains("Hidden"))
    }

    @Test("Inline math and comments cannot leak through a blank-line paragraph capture", arguments: ["\n", "\r\n"])
    func hiddenParagraphWithinBoundedProof(ending: String) throws {
        for (opening, closing) in [("Earlier $hidden", "$"), ("Earlier %%hidden", "%%")] {
            let prefix = opening + ending + ending
            let source = prefix + "Hidden res" + ending + ending + closing
            let caret = prefix.utf16.count + "Hidden res".utf16.count
            #expect(WritingContinuationContext(snapshot: try capture(source, caret: caret), caret: caret) == nil)
        }
    }

    @Test("Space and Tab after a word keep the exact paused continuation context", arguments: ["\n", "\r\n"])
    func pausedAfterWhitespace(ending: String) throws {
        for (body, expected) in [
            ("This synthetic note supplies a unique title for Title. And I don’t think that ", "And I don’t think that "),
            ("A claim about res\t", "A claim about res\t"),
            ("# Heading e\u{301}😀 res ", "Heading e\u{301}😀 res "),
            ("- List res ", "List res "),
            ("> Quote res  ", "Quote res  "),
            ("> [!state] Callout res ", "Callout res "),
            ("[^note]: Footnote res ", "Footnote res "),
        ] {
            let prefix = "\u{feff}---" + ending + "title: Preserve" + ending + "---" + ending + ending
            let source = prefix + body
            let caret = source.utf16.count
            let snapshot = try capture(source, caret: caret)
            let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret), "Rejected a paused word boundary: \(body)")
            #expect(Data(context.before.utf8) == Data(expected.utf8))
            #expect(context.after.isEmpty)
            #expect(snapshot.source == source)
        }
    }

    @Test("Trailing spaces with soft or terminal line endings remain exact current prose", arguments: ["\n", "\r\n"])
    func whitespaceBeforeLineEnding(ending: String) throws {
        let source = "Current res  " + ending
        for caret in [source.utf16.count - ending.utf16.count, source.utf16.count] {
            let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: caret), caret: caret))
            #expect(Data((context.before + context.after).utf8) == Data(source.utf8))
        }
    }

    @Test("Uses the exact current sentence, with before and after kept separate")
    func exactSentence() throws {
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

    @Test(
        "Current prose excludes adjacent YAML and structural Markdown without a blank separator",
        arguments: [
            "---\nid: 00000000-0000-4000-8000-000000000001\ntitle: Hidden\n---\n",
            "\u{feff}---\r\nid: 00000000-0000-4000-8000-000000000001\r\ntitle: Hidden\r\nunknown: 'keep'\r\n---\r\n",
            "# Heading\n",
            "\n---\n",
            "Heading\n=======\n",
            "```swift\nlet hidden = 1\n```\n",
        ])
    func adjacentStructuralBlocks(prefix: String) throws {
        let prose = "Unfinished😀 e\u{301} res"
        let source = prefix + prose + "\n# Following heading"
        let caret = prefix.utf16.count + prose.utf16.count
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(Data(context.before.utf8) == Data(prose.utf8))
        #expect(context.after == "\n")
        #expect(snapshot.source == source)
        #expect(!context.focus.contains("Hidden"))
        #expect(!context.focus.contains("Heading"))
        #expect(!context.focus.contains("Following"))
    }

    @Test("Soft line breaks and authored terminal CRLF remain exact current prose")
    func multilineProse() throws {
        let source = "# Heading\r\nA claim crosses a soft break\r\nand remains unfinished😀 res\r\n"
        let caret = source.utf16.count - 2
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(context.before == "A claim crosses a soft break\r\nand remains unfinished😀 res")
        #expect(context.after == "\r\n")
        #expect(snapshot.source == source)
    }

    @Test("An EOF caret retains only the authored terminal line ending", arguments: ["\n", "\r\n"])
    func terminalNewlineCaret(ending: String) throws {
        let source = "# Heading" + ending + "Current unfinished😀 e\u{301} res" + ending
        let caret = source.utf16.count
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(Data(context.before.utf8) == Data(("Current unfinished😀 e\u{301} res" + ending).utf8))
        #expect(context.after.isEmpty)
    }

    @Test(
        "A protected body boundary never admits a YAML caret or an unclosed envelope",
        arguments: [
            "---\ntitle: Hidden\n---\nBody",
            "---\ntitle: Hidden",
        ])
    func invalidBodyBoundary(source: String) throws {
        let caret = (source as NSString).range(of: "Hidden").location + "Hidden".utf16.count
        let snapshot = try capture(source, caret: caret)
        #expect(WritingContinuationContext(snapshot: snapshot, caret: caret) == nil)
    }

    @Test("Full-width sentence closers remain with the preceding Chinese sentence", arguments: ["）", "》"])
    func chineseSentenceClosers(closer: String) throws {
        let source = "前一句。" + closer + "当前句正在写"
        let caret = source.utf16.count
        let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: caret), caret: caret))
        #expect(context.before == "当前句正在写")
    }

    @Test("Keeps the current sentence, including a completed sentence at the caret")
    func sentenceBoundary() throws {
        let source = "Earlier sentence. Current claim about res. Later sentence."
        let punctuation = (source as NSString).range(of: ".", options: [], range: NSRange(location: 20, length: source.utf16.count - 20)).location
        let snapshot = try capture(source, caret: punctuation)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: punctuation))
        #expect(context.before == "Current claim about res")
        #expect(context.after == ".")
        #expect(!context.focus.contains("Earlier"))
        #expect(!context.focus.contains("Later"))

        let completedSource = "Earlier sentence. Current claim."
        let completedCaret = completedSource.utf16.count
        let completedSnapshot = try capture(completedSource, caret: completedCaret)
        let completed = try #require(WritingContinuationContext(snapshot: completedSnapshot, caret: completedCaret))
        #expect(completed.before == "Current claim.")
        #expect(completed.after.isEmpty)
        #expect(!completed.focus.contains("Earlier"))

        let chinese = "前一句。当前句正在写"
        let chineseCaret = chinese.utf16.count
        let chineseSnapshot = try capture(chinese, caret: chineseCaret)
        let chineseContext = try #require(WritingContinuationContext(snapshot: chineseSnapshot, caret: chineseCaret))
        #expect(chineseContext.before == "当前句正在写")
        #expect(!chineseContext.focus.contains("前一句"))
    }

    @Test(
        "Readable body structures permit a short insertion with exact source-owned context",
        arguments: [
            ("# Heading e\u{301}😀 res", "Heading e\u{301}😀 res"),
            ("- List res", "List res"),
            ("> Quote res", "Quote res"),
            ("> [!state] Callout res", "Callout res"),
            ("| Header | Other |\r\n| --- | --- |\r\n| Cell res | value |", "Cell res"),
            ("[^note]: Footnote res", "Footnote res"),
            ("See ^[Inline note res] here", "Inline note res"),
            ("Before [Visible label res](Hidden.md) after", "Visible label res"),
            ("Before [[Hidden.md|Visible alias res]] after", "Visible alias res"),
            ("![Authored alt res](Image.png)", "Authored alt res"),
            ("![[Hidden.md|Authored alias res]]", "Authored alias res"),
            ("# ==Highlighted res==", "Highlighted res"),
            ("[[Hidden.md]]{{Annotation res}}", "Annotation res"),
        ])
    func readableBody(source: String, text: String) throws {
        let caret = NSMaxRange((source as NSString).range(of: text))
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(Data(context.before.utf8) == Data(text.utf8))
        #expect(context.after.isEmpty)
        #expect(!context.before.contains("Hidden.md"))
        #expect(snapshot.source == source)
    }

    @Test(
        "Native readable admission rejects protected body points independently of the page",
        arguments: [
            ("Before `Hidden res` after", "Hidden res"),
            ("Before $Hidden res$ after", "Hidden res"),
            ("[Visible](Hidden.md)", "Hidden.md"),
            ("[[Hidden.md|Visible]]", "Hidden.md"),
            ("[^Hidden]: Visible", "Hidden"),
            ("<!-- Hidden res -->", "Hidden res"),
        ])
    func protectedBody(source: String, text: String) throws {
        let range = (source as NSString).range(of: text)
        let caret = range.location + max(1, range.length / 2)
        let snapshot = try capture(source, caret: caret)
        #expect(WritingContinuationContext(snapshot: snapshot, caret: caret) == nil)
    }

    @Test("Completed prose keeps exact trailing LF or CRLF and remains bounded", arguments: ["\n", "\r\n"])
    func completedSentenceEnding(ending: String) throws {
        let source = "Earlier sentence. 当前句。》" + ending
        let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: source.utf16.count), caret: source.utf16.count))
        #expect(Data(context.before.utf8) == Data(("当前句。》" + ending).utf8))
        #expect(context.after.isEmpty)
        #expect(!context.before.contains("Earlier"))
    }

    @Test("Footnote code cannot enter native context from an intermediate continuation line")
    func footnoteCode() throws {
        let source = "[^note]: Introduction\r\n  ```swift\r\n  Hidden code res\r\n  ```\r\n  Visible e\u{301}😀 res"
        let native = source as NSString
        for range in [native.range(of: "```swift"), native.range(of: "Hidden code res"), native.range(of: "```", options: .backwards)] {
            let caret = range.location + 1
            #expect(WritingContinuationContext(snapshot: try capture(source, caret: caret), caret: caret) == nil)
        }
        let caret = source.utf16.count
        let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: caret), caret: caret))
        #expect(Data(context.before.utf8) == Data("Visible e\u{301}😀 res".utf8))
        #expect(context.after.isEmpty)
        #expect(!context.before.contains("Hidden"))
    }

    @Test("Paragraph anchor identity never enters before, after or retrieval focus", arguments: ["", "\n", "\r\n"])
    func paragraphIdentity(ending: String) throws {
        let text = "Readable e\u{301}😀 res"
        let source = text + " ^hidden-id" + ending
        let caret = text.utf16.count
        let context = try #require(WritingContinuationContext(snapshot: capture(source, caret: caret), caret: caret))
        #expect(Data(context.before.utf8) == Data(text.utf8))
        #expect(context.after == " ")
        #expect(!context.focus.contains("hidden-id"))
        let markerCaret = (source as NSString).range(of: "^hidden-id").location + 2
        #expect(WritingContinuationContext(snapshot: try capture(source, caret: markerCaret), caret: markerCaret) == nil)
        let standalone = "Before.\n\n^hidden-id" + ending
        let standaloneCaret = (standalone as NSString).range(of: "^hidden-id").location + 2
        #expect(WritingContinuationContext(snapshot: try capture(standalone, caret: standaloneCaret), caret: standaloneCaret) == nil)
    }

    @Test("A paragraph split inside fenced code recovers readable body without admitting code", arguments: ["\n", "\r\n"])
    func truncatedFenceCapture(ending: String) throws {
        for prefix in ["", "[^note]: Introduction" + ending + "  "] {
            let indent = prefix.isEmpty ? "" : "  "
            let visible = "Readable e\u{301}😀 res"
            let source =
                prefix + "```swift" + ending + indent + "Hidden first" + ending + ending
                + indent + "Hidden last" + ending + indent + "```" + ending + indent + visible
            let caret = source.utf16.count
            let snapshot = try capture(source, caret: caret)
            #expect(snapshot.sourceRange.utf16LowerBound > 0)
            #expect(!snapshot.excerpt.contains("```swift"))
            let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
            #expect(Data(context.before.utf8) == Data(visible.utf8))
            #expect(context.after.isEmpty)
            #expect(!context.focus.contains("Hidden"))
            let codeCaret = (source as NSString).range(of: "Hidden last").location + 3
            let codeCapture = try capture(source, caret: codeCaret)
            #expect(!codeCapture.excerpt.contains("```swift"))
            #expect(WritingContinuationContext(snapshot: codeCapture, caret: codeCaret) == nil)
            #expect(Data(snapshot.source.utf8) == Data(source.utf8))
        }
    }

    @Test("Reference labels remain exact when the paragraph capture excludes their definition", arguments: [false, true])
    func referenceCapture(emphasized: Bool) throws {
        let text = "Readable e\u{301}😀 res"
        let label = emphasized ? "**" + text + "**" : text
        let source = "Before [" + label + "][private-id] after\n\n[private-id]: Hidden.md"
        let caret = NSMaxRange((source as NSString).range(of: text))
        let snapshot = try capture(source, caret: caret)
        #expect(!snapshot.excerpt.contains("Hidden.md"))
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(Data(context.before.utf8) == Data(text.utf8))
        #expect(context.after.isEmpty)
        #expect(!context.focus.contains("private-id"))
        let idCaret = (source as NSString).range(of: "private-id").location + 3
        #expect(WritingContinuationContext(snapshot: try capture(source, caret: idCaret), caret: idCaret) == nil)
        let unproved = "Before [Nested [label] res][private-id] after\n\n[private-id]: Hidden.md"
        let unprovedCaret = (unproved as NSString).range(of: " res").location + " res".utf16.count
        #expect(WritingContinuationContext(snapshot: try capture(unproved, caret: unprovedCaret), caret: unprovedCaret) == nil)
        #expect(Data(snapshot.source.utf8) == Data(source.utf8))
    }

    @Test("A callout header nested in a list never enters readable native context")
    func nestedCalloutCapture() throws {
        let text = "Readable e\u{301}😀 res"
        let source = "- > [!state] " + text
        let caret = source.utf16.count
        let snapshot = try capture(source, caret: caret)
        let context = try #require(WritingContinuationContext(snapshot: snapshot, caret: caret))
        #expect(Data(context.before.utf8) == Data(text.utf8))
        #expect(context.after.isEmpty)
        #expect(!context.focus.contains("state"))
        let markerCaret = (source as NSString).range(of: "state").location + 2
        #expect(WritingContinuationContext(snapshot: try capture(source, caret: markerCaret), caret: markerCaret) == nil)
    }

    @Test("Local syntax proof and provider context keep their independent bounds")
    func boundedSyntaxProof() throws {
        let visible = "Readable e\u{301}😀 res"
        let prose = String(repeating: "Earlier paragraph.\n\n", count: 2_000) + visible
        let context = try #require(WritingContinuationContext(snapshot: capture(prose, caret: prose.utf16.count), caret: prose.utf16.count))
        #expect(Data(context.before.utf8) == Data(visible.utf8))
        #expect(context.before.utf16.count <= WritingContinuationContext.maximumBeforeUTF16Count)
        #expect(context.after.utf16.count <= WritingContinuationContext.maximumAfterUTF16Count)
        let inlineHistory = String(repeating: "Earlier paragraph with a < b and %%comment%%.\n\n", count: 1_000) + visible
        let inlineContext = try #require(
            WritingContinuationContext(
                snapshot: capture(inlineHistory, caret: inlineHistory.utf16.count), caret: inlineHistory.utf16.count))
        #expect(Data(inlineContext.before.utf8) == Data(visible.utf8))
        let ambiguous = "```swift\n" + String(repeating: "Hidden line\n", count: 3_000) + "\nHidden last\n```\n" + visible
        let snapshot = try capture(ambiguous, caret: ambiguous.utf16.count)
        #expect(snapshot.excerpt.utf16.count < MarkdownReadableWritingRange.maximumFragmentUTF16Count)
        #expect(WritingContinuationContext(snapshot: snapshot, caret: ambiguous.utf16.count) == nil)
        let codeCaret = (ambiguous as NSString).range(of: "Hidden last").location + 3
        #expect(WritingContinuationContext(snapshot: try capture(ambiguous, caret: codeCaret), caret: codeCaret) == nil)
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
