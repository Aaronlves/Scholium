import Foundation
import ScholiumContracts
import Testing

@Suite("Local body writing vocabulary")
struct WritingCompletionVocabularyTests {
    @Test("Body words and phrases preserve spelling, whitespace and mixed Unicode without declared keywords")
    func bodyWordsAndPhrases() throws {
        let source =
            "\u{FEFF}---\r\ntitle: Metadata only\r\n---\r\n# Manual Heading Completion Target\r\n\r\nResponsibility concerns reasons.\r\n\r\n控制条件影响判断。\r\n\r\nA mixed  language phrase."
        let document = NoteDocument(relativePath: "Body.md", rawContent: source)
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: " Manual Heading Completion T").first == "Manual Heading Completion Target")
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Responsib").first == "Responsibility")
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "这里的控制").contains("控制条件"))
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "mixed  langu").contains("mixed  language"))
        #expect(!(try WritingCompletionVocabulary(document: document).terms(matching: "mixed langu")).contains { $0.hasPrefix("mixed language") })
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
    }

    @Test("Technical content and excluded spans never supply words or join disconnected prose")
    func proseBoundaries() throws {
        let source = """
            ---
            title: MetadataSecret
            private_value: YamlSecret
            ---
            Alpha `InlineSecret` Beta.

            ```swift
            BlockSecret
            ```

            Gamma $MathSecret$ Delta.

            Epsilon <!-- CommentSecret --> Zeta.

            [Visible label](https://HostSecret.invalid)

            First sentence. Second sentence.

            Different paragraph.
            """
        let document = NoteDocument(relativePath: "Boundaries.md", rawContent: source)
        for query in ["MetadataS", "YamlS", "InlineS", "BlockS", "MathS", "CommentS", "HostS", "Alpha B", "Gamma D", "Epsilon Z"] {
            #expect(try WritingCompletionVocabulary(document: document).terms(matching: query).isEmpty, "\(query)")
        }
        for query in ["sentence Second", "sentence Different"] {
            #expect(!(try WritingCompletionVocabulary(document: document).terms(matching: query)).contains { $0.hasPrefix(query) })
        }
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Visible l").contains("Visible label"))
        let unclosed = NoteDocument(relativePath: "Unclosed.md", rawContent: "\u{FEFF}---\r\nprivate_value: MetadataSecret")
        #expect(!unclosed.hasProvableBodyBoundary)
        #expect(try WritingCompletionVocabulary(document: unclosed).terms(matching: "MetadataS").isEmpty)
        let invalid = NoteDocument(relativePath: "Invalid.md", rawContent: "---\nvalue: [\n---\nResponsibility concerns reasons.")
        #expect(invalid.hasProvableBodyBoundary)
        #expect(try WritingCompletionVocabulary(document: invalid).terms(matching: "Responsib").contains("Responsibility"))
    }

    @Test("Callout roles and embed destinations stay outside authored vocabulary")
    func specialSyntaxBoundaries() throws {
        let source = """
            > [!state] Claim Vocabulary Target
            > Authored body phrase.

            > > [!state]- Nested Claim Vocabulary Target
            > > Nested body phrase.

            HiddenPublication exists.

            ![[HiddenDestination|Visible picture]]
            """
        let document = NoteDocument(relativePath: "Dialect.md", rawContent: source)
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "sta").isEmpty)
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Claim Vocabulary T").contains("Claim Vocabulary Target"))
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Nested Claim V").contains("Nested Claim Vocabulary"))
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Authored b").contains("Authored body"))
        let hidden = try WritingCompletionVocabulary(document: document).terms(matching: "Hidden")
        #expect(hidden.contains("HiddenPublication"))
        #expect(!hidden.contains { $0.contains("HiddenDestination") })
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Visible p").contains("Visible picture"))
    }

    @Test("Nested exclusions preserve visible labels and trailing body across exact source formats")
    func nestedExclusions() throws {
        for tail in ["", "\n\nTrailingVocabulary remains readable."] {
            for newline in ["\n", "\r\n"] {
                let raw =
                    "\u{FEFF}---\nqa_marker: preserve\n---\nDestinationPublication establishes visibility.\n\n![[Hidden$MathSecret$Destination|Visible picture]]"
                    + tail
                let source = raw.replacingOccurrences(of: "\n", with: newline)
                let document = NoteDocument(relativePath: "Nested.md", rawContent: source)
                for query in ["Hidden", "MathS"] {
                    #expect(try WritingCompletionVocabulary(document: document).terms(matching: query).isEmpty)
                }
                let destination = try WritingCompletionVocabulary(document: document).terms(matching: "Dest")
                #expect(destination.contains("DestinationPublication"))
                #expect(!destination.contains("Destination"))
                #expect(try WritingCompletionVocabulary(document: document).terms(matching: "Visible p").contains("Visible picture"))
                if !tail.isEmpty {
                    #expect(try WritingCompletionVocabulary(document: document).terms(matching: "TrailingV").contains("TrailingVocabulary"))
                }
                #expect(document.rawContent.utf8.elementsEqual(source.utf8))
            }
        }
        let labelMath = NoteDocument(relativePath: "Label.md", rawContent: "![[HiddenDestination|Visible $MathSecret$ picture]]")
        #expect(try WritingCompletionVocabulary(document: labelMath).terms(matching: "MathS").isEmpty)
    }

    @Test("Appendable corpus prefixes reject normalization-only matches and retain literal UTF-16")
    func exactPrefixes() throws {
        let source = "Éclair and caféine.\n\n𐐨界理论。"
        let document = NoteDocument(relativePath: "Unicode.md", rawContent: source)
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "e\u{301}c").isEmpty)
        #expect(try WritingCompletionVocabulary(document: document).terms(matching: "cafe").isEmpty)
        #expect(WritingCompletionPrefix.matchingCount("𐐨界理论", query: "Here 𐐨界") == "𐐨界".utf16.count)
        #expect(
            WritingCompletionPrefix.matchingCount("Manual Heading Completion Target", query: " Manual Heading Completion T")
                == "Manual Heading Completion T".utf16.count)
    }
    @Test("Synthetic repeated-query vocabulary cost retains identical source and expected results")
    func queryCostBenchmark() throws {
        let paragraph = "# Manual Heading Completion Target\n\nResponsibility concerns reasons.\n\n控制条件影响判断。\n\nA mixed  language phrase.\n\n"
        let source = String(repeating: paragraph, count: 300)
        let document = NoteDocument(relativePath: "Synthetic-speed.md", rawContent: source)
        let queries = ["Manual Heading Completion T", "Responsib", "这里的控制", "mixed  langu"]
        let clock = ContinuousClock()
        var seconds: [Double] = []
        for _ in 0..<3 {
            for query in queries {
                let start = clock.now
                let result = try WritingCompletionVocabulary(document: document).terms(matching: query)
                let duration = start.duration(to: clock.now).components
                seconds.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
                #expect(!result.isEmpty)
            }
        }
        let ordered = seconds.sorted()
        let preparationStart = clock.now
        let vocabulary = try WritingCompletionVocabulary(document: document)
        let preparation = preparationStart.duration(to: clock.now).components
        var reusedSeconds: [Double] = []
        for _ in 0..<3 {
            for query in queries {
                let start = clock.now
                let result = try vocabulary.terms(matching: query)
                let duration = start.duration(to: clock.now).components
                reusedSeconds.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
                #expect(try result == WritingCompletionVocabulary(document: document).terms(matching: query))
            }
        }
        let reusedOrdered = reusedSeconds.sorted()
        print(
            "Writing vocabulary benchmark source_bytes=\(document.sourceBytes.count) queries=\(seconds.count) direct_median_seconds=\(ordered[ordered.count / 2]) prepared_median_seconds=\(reusedOrdered[reusedOrdered.count / 2]) preparation_seconds=\(Double(preparation.seconds) + Double(preparation.attoseconds) / 1e18)"
        )
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
    }

}
