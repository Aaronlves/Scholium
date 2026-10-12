import Foundation
import ScholiumContracts
import Testing

@Suite("Readable Markdown writing ranges")
struct MarkdownReadableWritingRangeTests {
    private struct Fixture: Sendable {
        let source: String
        let text: String
    }

    @Test(
        "Readable structures retain exact text without their Markdown markers or destinations",
        arguments: [
            Fixture(source: "# Heading e\u{301}😀 res", text: "Heading e\u{301}😀 res"),
            Fixture(source: "Heading res\n===========", text: "Heading res"),
            Fixture(source: "- List res", text: "List res"),
            Fixture(source: "1. Ordered res", text: "Ordered res"),
            Fixture(source: "> Quote res", text: "Quote res"),
            Fixture(source: "> [!state] Callout res\n> Body", text: "Callout res"),
            Fixture(source: "- > [!state] Nested callout res", text: "Nested callout res"),
            Fixture(source: "> [!state]\n> Callout body res", text: "Callout body res"),
            Fixture(source: "| Header | Other |\n| --- | --- |\n| Cell e\u{301}😀 res | value |", text: "Cell e\u{301}😀 res"),
            Fixture(source: "| Header | Other |\n| --- | --- |\n| Escaped \\| pipe res | value |", text: "Escaped \\| pipe res"),
            Fixture(source: "[^note]: Footnote res", text: "Footnote res"),
            Fixture(source: "[^note]: First line\n  Continued res", text: "Continued res"),
            Fixture(source: "See ^[Inline footnote res] here", text: "Inline footnote res"),
            Fixture(source: "Before [Visible label res](Hidden.md#Target) after", text: "Visible label res"),
            Fixture(source: "Before [Reference label res][hidden]\n\n[hidden]: https://example.invalid", text: "Reference label res"),
            Fixture(source: "Before [Reference label res][hidden] after", text: "Reference label res"),
            Fixture(source: "Before [**Reference label res**][hidden] after", text: "Reference label res"),
            Fixture(source: "Before [[Hidden.md#Target|Visible alias res]] after", text: "Visible alias res"),
            Fixture(source: "# **Emphasized res**", text: "Emphasized res"),
            Fixture(source: "[**Emphasized label res**](Hidden.md)", text: "Emphasized label res"),
            Fixture(source: "![Authored alt res](Image.png)", text: "Authored alt res"),
            Fixture(source: "![[Hidden.md|Authored alias res]]", text: "Authored alias res"),
            Fixture(source: "# ==Highlighted res==", text: "Highlighted res"),
            Fixture(source: "[[Hidden.md]]{{Annotation res}}", text: "Annotation res"),
        ])
    private func readableContainers(fixture: Fixture) throws {
        let needle = (fixture.source as NSString).range(of: fixture.text)
        let caret = NSMaxRange(needle)
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: fixture.source, caretUTF16: caret))
        let range = try #require(Range(NSRange(location: capture.sourceUTF16Range.lowerBound, length: capture.sourceUTF16Range.count), in: fixture.source))
        #expect(Data(fixture.source[range].utf8) == Data(fixture.text.utf8))
        #expect(!capture.isProse)
        #expect(capture.sourceUTF16Range.contains(caret - 1))
        #expect(capture.sourceUTF16Range.upperBound == caret)
    }

    @Test(
        "Typed horizontal whitespace remains readable at the current caret",
        arguments: [
            Fixture(source: "A claim about res ", text: "A claim about res "),
            Fixture(source: "A claim about res\t", text: "A claim about res\t"),
            Fixture(source: "# Heading e\u{301}😀 res ", text: "Heading e\u{301}😀 res "),
            Fixture(source: "- List res ", text: "List res "),
            Fixture(source: "> Quote res  ", text: "Quote res  "),
            Fixture(source: "> [!state] Callout res ", text: "Callout res "),
            Fixture(source: "| Header | Other |\n| --- | --- |\n| Cell res | value |", text: "Cell res "),
            Fixture(source: "[^note]: Footnote res ", text: "Footnote res "),
            Fixture(source: "Before [Visible label res ](Hidden.md) after", text: "Visible label res "),
            Fixture(source: "Before [[Hidden.md|Visible alias res ]] after", text: "Visible alias res "),
        ])
    private func typedHorizontalWhitespace(fixture: Fixture) throws {
        let caret = NSMaxRange((fixture.source as NSString).range(of: fixture.text))
        let readable = try #require(MarkdownReadableWritingRange(bodyFragment: fixture.source, caretUTF16: caret))
        let range = try #require(Range(NSRange(location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count), in: fixture.source))
        #expect(Data(fixture.source[range].utf8) == Data(fixture.text.utf8))
        #expect(readable.sourceUTF16Range.upperBound == caret)
    }

    @Test("Horizontal-tail admission does not consume a following blank or structural line", arguments: ["\n", "\r\n"])
    func whitespaceTailBoundary(ending: String) throws {
        let first = "Current res  " + ending
        let source = first + ending + "# Following heading"
        let readable = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: "Current res  ".utf16.count))
        #expect(readable.sourceUTF16Range == 0..<first.utf16.count)
        let blankCaret = first.utf16.count + ending.utf16.count
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: blankCaret) == nil)
    }

    @Test(
        "Whitespace does not bridge literal or structural writing boundaries",
        arguments: [
            "`Hidden res `", "```md\nHidden res ", "    Hidden res ", "$Hidden res $",
            "<!-- Hidden res -->", "[Visible](Hiddenres )", "[[Hidden res ]]",
            "[^Hidden res ]: Definition", "Before res ^hidden-id ",
            "[^note]: `Hidden res `", "[^note]: First line\n  ```md\n  Hidden res ",
            "[^note]: $Hidden res ",
        ])
    func protectedWhitespace(source: String) {
        let needle = (source as NSString).range(of: "res ")
        #expect(needle.location != NSNotFound)
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: NSMaxRange(needle)) == nil)
    }

    @Test("Ordinary prose keeps soft breaks and authored terminal line endings", arguments: ["\n", "\r\n"])
    func prose(ending: String) throws {
        let source = "Earlier claim" + ending + "and current e\u{301}😀 res" + ending
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count))
        #expect(capture.isProse)
        #expect(capture.sourceUTF16Range == 0..<source.utf16.count)
    }

    @Test("Escaped table pipes keep exact cell coordinates and never shift protected inlines", arguments: ["\n", "\r\n"])
    func escapedTableSource(ending: String) throws {
        let header = "| Header | Other |" + ending + "| --- | --- |" + ending
        for text in ["Escaped \\| pipe res", "β \\| e\u{301} \\| 😀 res", "# Authored \\| label res"] {
            let source = header + "| " + text + " | value |"
            let caret = NSMaxRange((source as NSString).range(of: text))
            let readable = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret))
            let range = try #require(
                Range(
                    NSRange(
                        location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count), in: source))
            #expect(Data(source[range].utf8) == Data(text.utf8))
            #expect(readable.sourceUTF16Range.upperBound == caret)
            #expect(!readable.isProse)
        }
        let source = header + "| Escaped \\| `private code` [Visible](Hidden.md) Current res | value |"
        for hidden in ["private code", "Hidden.md"] {
            let caret = (source as NSString).range(of: hidden).location + 2
            #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret) == nil)
        }
        let caret = NSMaxRange((source as NSString).range(of: "Current res"))
        let readable = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret))
        let range = try #require(
            Range(
                NSRange(
                    location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count), in: source))
        #expect(Data(source[range].utf8) == Data(" Current res".utf8))
    }

    @Test("A missing inline-math closer protects the remaining bounded capture across blank lines", arguments: ["\n", "\r\n"])
    func incompleteMultilineMath(ending: String) throws {
        for opening in ["Before $Hidden first", "Before \\\\$Hidden first"] {
            let source = opening + ending + ending + "Hidden body res"
            #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count) == nil)
        }
        let closed = "Before $Hidden first" + ending + ending + "Hidden body$ Visible res"
        let readable = try #require(MarkdownReadableWritingRange(bodyFragment: closed, caretUTF16: closed.utf16.count))
        let range = try #require(
            Range(
                NSRange(
                    location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count), in: closed))
        #expect(Data(closed[range].utf8) == Data(" Visible res".utf8))
        for source in ["Readable \\$price res", "[Visible](Hidden$target.md) Current res"] {
            #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count) != nil)
        }
    }

    @Test("Footnote projections cannot bypass completed or dangling outer mathematics", arguments: ["\n", "\r\n"])
    func footnoteOuterMath(ending: String) throws {
        for source in [
            "Earlier $hidden" + ending + ending + "[^id]: Hidden footnote res" + ending + ending + "closing$",
            "Before $Hidden ^[Footnote res]$ after",
            "Earlier $Hidden" + ending + ending + "[^id]: Footnote res",
        ] {
            let footnote = (source as NSString).range(of: "footnote res", options: .caseInsensitive)
            let caret = footnote.location + 5
            #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret) == nil)
        }
        let text = "Readable e\u{301}😀 res"
        for source in ["[^id]: " + text, "Before ^[" + text + "] after"] {
            let caret = NSMaxRange((source as NSString).range(of: text))
            let readable = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret))
            let range = try #require(
                Range(
                    NSRange(
                        location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count), in: source))
            #expect(Data(source[range].utf8) == Data(text.utf8))
            #expect(!readable.isProse)
        }
    }

    @Test(
        "Technical source, hidden destinations and structural identifiers never admit writing",
        arguments: [
            Fixture(source: "```swift\nHidden res\n```", text: "Hidden res"),
            Fixture(source: "    Hidden res", text: "Hidden res"),
            Fixture(source: "Before `Hidden res` after", text: "Hidden res"),
            Fixture(source: "<div>Hidden res</div>", text: "Hidden res"),
            Fixture(source: "Before <!-- Hidden res --> after", text: "Hidden res"),
            Fixture(source: "Before %% Hidden res %% after", text: "Hidden res"),
            Fixture(source: "Before $Hidden res$ after", text: "Hidden res"),
            Fixture(source: "$$\nHidden res\n$$", text: "Hidden res"),
            Fixture(source: "$$\nHidden res", text: "Hidden res"),
            Fixture(source: "[Visible](Hidden.md#Target)", text: "Hidden.md"),
            Fixture(source: "[Visible][Hidden]\n\n[Hidden]: Target.md", text: "Hidden"),
            Fixture(source: "[Visible][Hidden]", text: "Hidden"),
            Fixture(source: "[Nested [label] res][Hidden]", text: "res"),
            Fixture(source: "[[Hidden.md#Target]]", text: "Hidden.md"),
            Fixture(source: "[[Hidden.md|Visible]]", text: "Hidden.md"),
            Fixture(source: "<https://example.invalid/Hidden>", text: "Hidden"),
            Fixture(source: "![Visible alt](Hidden.png)", text: "Hidden.png"),
            Fixture(source: "![[Hidden.md]]", text: "Hidden.md"),
            Fixture(source: "[^Hidden]: Visible body", text: "Hidden"),
            Fixture(source: "[^Hidden]: Visible `code` body", text: "Hidden"),
            Fixture(source: "Visible [^Hidden] body\n\n[^Hidden]: Definition", text: "Hidden"),
            Fixture(source: "> [!Hidden] Visible title", text: "Hidden"),
            Fixture(source: "- > [!Hidden] Visible title", text: "Hidden"),
            Fixture(source: "> [!Hidden] Visible `code` title", text: "Hidden"),
            Fixture(source: "[[Hidden.md|Unclosed alias", text: "Unclosed alias"),
            Fixture(source: "[Visible](Unclosed target", text: "Unclosed target"),
            Fixture(source: "Before `Unclosed code", text: "Unclosed code"),
            Fixture(source: "Before $Unclosed math", text: "Unclosed math"),
            Fixture(source: "Before <span Unclosed HTML", text: "Unclosed HTML"),
        ])
    private func protectedPositions(fixture: Fixture) {
        let needle = (fixture.source as NSString).range(of: fixture.text)
        let caret = needle.location + max(1, needle.length / 2)
        #expect(MarkdownReadableWritingRange(bodyFragment: fixture.source, caretUTF16: caret) == nil)
    }

    @Test("Protected inline regions divide source context rather than being remotely concatenated")
    func separatedContext() throws {
        let source = "Earlier `hidden` $private$ [visible](Hidden.md) Current res"
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count))
        let range = try #require(Range(NSRange(location: capture.sourceUTF16Range.lowerBound, length: capture.sourceUTF16Range.count), in: source))
        #expect(String(source[range]) == " Current res")
        #expect(!String(source[range]).contains("hidden"))
        #expect(!String(source[range]).contains("private"))
        #expect(!String(source[range]).contains("Hidden.md"))
    }

    @Test("Bounded captures reject invalid UTF16 coordinates without normalizing source")
    func boundsAndCoordinates() throws {
        let source = "Readable 😀 e\u{301} res"
        let emoji = (source as NSString).range(of: "😀")
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: emoji.location + 1) == nil)
        let decomposed = (source as NSString).range(of: "e\u{301}")
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: decomposed.location + 1) == nil)
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: -1) == nil)
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count + 1) == nil)
        let excessive = String(repeating: "a", count: MarkdownReadableWritingRange.maximumFragmentUTF16Count + 1)
        #expect(MarkdownReadableWritingRange(bodyFragment: excessive, caretUTF16: excessive.utf16.count) == nil)
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: source.utf16.count))
        let range = try #require(Range(NSRange(location: capture.sourceUTF16Range.lowerBound, length: capture.sourceUTF16Range.count), in: source))
        #expect(Data(source[range].utf8) == Data(source.utf8))
    }

    @Test("Footnote fenced code remains protected across source slices", arguments: ["\n", "\r\n"])
    func footnoteMultilineCode(ending: String) throws {
        let source = ["[^note]: Introduction", "  ```swift", "  Hidden code res", "  ```", "  Visible e\u{301}😀 res"].joined(separator: ending)
        let native = source as NSString
        let opening = native.range(of: "```swift")
        let inside = native.range(of: "Hidden code res")
        let closing = native.range(of: "```", options: .backwards)
        for range in [opening, inside, closing] {
            #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: range.location + 1) == nil)
        }
        let visible = "Visible e\u{301}😀 res"
        let caret = NSMaxRange(native.range(of: visible))
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: caret))
        let range = try #require(Range(NSRange(location: capture.sourceUTF16Range.lowerBound, length: capture.sourceUTF16Range.count), in: source))
        #expect(Data(source[range].utf8) == Data(visible.utf8))
        #expect(!capture.isProse)
    }

    @Test("Paragraph identifiers are excluded before the caret and never become readable context", arguments: ["", "\n", "\r\n"])
    func paragraphIdentity(ending: String) throws {
        let text = "Readable e\u{301}😀 res"
        let source = text + " ^hidden-id" + ending
        let capture = try #require(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: text.utf16.count))
        let range = try #require(Range(NSRange(location: capture.sourceUTF16Range.lowerBound, length: capture.sourceUTF16Range.count), in: source))
        #expect(Data(source[range].utf8) == Data((text + " ").utf8))
        let marker = (source as NSString).range(of: "^hidden-id")
        #expect(MarkdownReadableWritingRange(bodyFragment: source, caretUTF16: marker.location + 2) == nil)
        let standalone = "^hidden-id" + ending
        #expect(MarkdownReadableWritingRange(bodyFragment: standalone, caretUTF16: 3) == nil)
    }
}
