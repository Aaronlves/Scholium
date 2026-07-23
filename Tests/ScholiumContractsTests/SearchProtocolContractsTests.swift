import Foundation
import ScholiumContracts
import Testing

@Suite("Search v4 contracts")
struct SearchProtocolContractsTests {
    @Test("Finite syntax parses AND, escaped phrases, prefix, and exclusion")
    func finiteSyntax() throws {
        let result = SearchQueryParser.parse(#"title:"reflective \"equilibrium\"" autonom* -tag:survey"#)
        let ast = try #require(result.ast)
        #expect(result.diagnostics.isEmpty)
        #expect(ast.clauses.count == 3)
        guard case .lexical(let title) = ast.clauses[0],
              case .phrase(let phrase) = title.value else {
            Issue.record("Expected a title phrase")
            return
        }
        #expect(title.field == .title)
        #expect(phrase == #"reflective "equilibrium""#)
        guard case .lexical(let prefix) = ast.clauses[1],
              case .prefix(let value) = prefix.value else {
            Issue.record("Expected a prefix")
            return
        }
        #expect(value == "autonom")
        guard case .lexical(let excluded) = ast.clauses[2] else {
            Issue.record("Expected an excluded lexical field")
            return
        }
        #expect(excluded.excluded)
        #expect(excluded.field == .tag)
    }

    @Test("Structured-only positive and negative queries remain valid")
    func structuredOnly() throws {
        let positive = SearchQueryParser.parse("callout:state")
        #expect(try #require(positive.ast).isFilterOnly)
        let negative = SearchQueryParser.parse("-has:broken-link")
        #expect(try #require(negative.ast).isFilterOnly)
        #expect(SearchQueryParser.parse("-autonomy").diagnostics.first?.code == .onlyExcludedFreeText)
    }

    @Test("Removed fields and unknown canonical values fail closed")
    func removedFields() {
        let removed = SearchQueryParser.parse("vault:Analyses autonomy")
        #expect(removed.ast == nil)
        #expect(removed.diagnostics.first?.code == .removedField)
        #expect(removed.diagnostics.first?.needsEditing == true)
        let status = SearchQueryParser.parse("status:draft")
        #expect(status.ast == nil)
        #expect(status.diagnostics.first?.code == .removedField)
        #expect(status.diagnostics.first?.message.contains("not a Scholium property") == true)
        #expect(SearchQueryParser.parse("review:reviewed").diagnostics.first?.code == .unknownField)
        #expect(SearchQueryParser.parse("unknown:value").diagnostics.first?.code == .unknownField)
    }

    @Test("Unsupported and malformed syntax returns stable diagnostics")
    func diagnosticCoverage() {
        let cases: [(String, SearchQueryDiagnosticCode)] = [
            ("-", .emptyClause),
            (#""unterminated"#, .unclosedPhrase),
            (#""bad\q""#, .invalidEscape),
            (#""phrase"*"#, .invalidPrefix),
            ("a*", .invalidPrefix),
            ("autonomy OR agency", .unsupportedSyntax),
            ("(autonomy)", .unsupportedSyntax),
            ("autonomy NEAR agency", .unsupportedSyntax),
            ("/autonomy/", .unsupportedSyntax),
            ("autonomy~", .unsupportedSyntax),
            ("year:1990..2000", .unsupportedSyntax),
            ("title:", .missingFieldValue),
            ("callout:not-canonical", .unknownStructuredValue),
            ("-autonomy", .onlyExcludedFreeText),
        ]
        for (query, expected) in cases {
            #expect(
                SearchQueryParser.parse(query).diagnostics.first?.code == expected,
                "Unexpected diagnostic for \(query)"
            )
        }
        let empty = SearchQueryParser.parse("   ")
        #expect(empty.diagnostics.isEmpty)
        #expect(empty.ast?.clauses.isEmpty == true)
    }

    @Test("CJK uses symmetric character and bigram rules without prefix syntax")
    func cjkTokenization() {
        #expect(SearchTokenization.queryTokens(for: "哲学") == ["哲学"])
        #expect(SearchTokenization.queryTokens(for: "认识论") == ["认识", "识论"])
        #expect(SearchTokenization.queryTokens(for: "A认识论B") == ["a", "认识", "识论", "b"])
        #expect(SearchTokenization.queryTokens(for: "ㅎㅏㄴ") == ["ㅎㅏ", "ㅏㄴ"])
        #expect(SearchTokenization.queryTokens(for: "ｶﾅ") == ["ｶﾅ"])
        #expect(SearchQueryParser.parse("认识*").diagnostics.first?.code == .cjkPrefixUnsupported)
    }

    @Test("Visible semantic projection separates weighted roles and excludes destinations")
    func semanticProjection() throws {
        let source = """
        ---
        title: Test Note
        aliases: [Alias]
        authors: [Author]
        year: 2026
        tags: [search]
        status: draft
        ---
        # Heading Text

        Body with [visible link](https://hidden.example/destination),
        ![visible diagram](https://hidden.example/image.png "hidden image title"),
        and `inline code`.

        ```swift
        fenced code
        ```

        <!-- hidden comment -->

        > [!state] Claim
        > Callout **body**

        [^one]: Footnote *content*
        """
        let document = NoteDocument(relativePath: "Folder/Test Note.md", rawContent: source)
        let projection = SearchDocumentProjection(
            document: document,
            profile: .analysis,
            hasBrokenLink: true
        )

        #expect(projection.title == "Test Note")
        #expect(projection.headings == ["Heading Text"])
        #expect(projection.body.contains("visible link"))
        #expect(projection.body.contains("visible diagram"))
        #expect(!projection.body.contains("hidden.example"))
        #expect(!projection.body.contains("hidden image title"))
        #expect(projection.body.contains("inline code"))
        #expect(projection.body.contains("fenced code"))
        #expect(!projection.body.contains("hidden comment"))
        #expect(!projection.body.contains("Heading Text"))
        #expect(!projection.body.contains("Callout body"))
        #expect(!projection.body.contains("Footnote content"))
        #expect(projection.callouts.contains("Callout body"))
        #expect(projection.footnotes.contains("Footnote content"))
        #expect(projection.calloutRoles.contains("state"))
        #expect(projection.hasBrokenLink)

        for (field, needle) in [
            (SearchMatchedField.heading, "Heading Text"),
            (.callout, "body"),
            (.footnote, "content"),
            (.body, "visible diagram"),
        ] {
            let segment = try #require(projection.segments.first {
                $0.field == field && $0.normalizedText.contains(needle.lowercased())
            })
            let normalizedRange = try #require(segment.normalizedText.range(of: needle.lowercased()))
            let utf16Range = normalizedRange.lowerBound.utf16Offset(in: segment.normalizedText)
                ..< normalizedRange.upperBound.utf16Offset(in: segment.normalizedText)
            let sourceRange = try #require(
                segment.sourceUTF16Range(forNormalizedUTF16Range: utf16Range)
            )
            #expect((source as NSString).substring(with: NSRange(
                location: sourceRange.lowerBound,
                length: sourceRange.count
            )) == needle)
        }
    }

    @Test("Lexical projection maps a folded NFC hit back to the decomposed UTF-16 source")
    func normalizedSourceRange() throws {
        let decomposed = "Cafe\u{301}"
        let source = "Prefix \(decomposed) suffix"
        let projection = SearchDocumentProjection(
            document: NoteDocument(relativePath: "Unicode.md", rawContent: source)
        )
        let body = try #require(projection.segments.first { $0.field == .body })
        let needle = SearchTextNormalization.lexicalNormalize(decomposed)
        let range = try #require(body.normalizedText.range(of: needle))
        let utf16 = range.lowerBound.utf16Offset(in: body.normalizedText)
            ..< range.upperBound.utf16Offset(in: body.normalizedText)
        let sourceRange = try #require(body.sourceUTF16Range(forNormalizedUTF16Range: utf16))
        #expect((source as NSString).substring(with: NSRange(
            location: sourceRange.lowerBound,
            length: sourceRange.count
        )) == decomposed)
    }

    @Test("A cached source projection changes only dynamic broken-link state")
    func cachedSourceProjection() {
        let document = NoteDocument(
            relativePath: "Cached.md",
            rawContent: "# Cached\n\nExact visible body.\n"
        )
        let semantic = MarkdownSemanticDocument(parsing: document)
        let cached = SearchDocumentProjection(
            document: document,
            profile: .analysis,
            semantic: semantic
        )
        let reused = SearchIndexDocument(
            vaultID: UUID(),
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            document: document,
            semantic: semantic,
            cachedSourceProjection: cached,
            hasBrokenLink: true
        )
        let rebuilt = SearchIndexDocument(
            vaultID: reused.vaultID,
            vaultName: reused.vaultName,
            vaultRole: reused.vaultRole,
            document: document,
            semantic: semantic,
            hasBrokenLink: true
        )

        #expect(reused.projection == rebuilt.projection)
        #expect(reused.projection.segments == cached.segments)
        #expect(reused.projection.hasBrokenLink)
        #expect(reused.projection.projectionHash != cached.projectionHash)
    }

    @Test("BOM, CRLF, emoji, and RTL text retain exact UTF-16 source ranges")
    func byteHostileSourceRanges() throws {
        let source = "\u{FEFF}---\r\ntitle: Mixed Script\r\n---\r\n# 😀 Heading\r\n\r\nעברית العربية Cafe\u{301}\r\n"
        let projection = SearchDocumentProjection(
            document: NoteDocument(relativePath: "Mixed.md", rawContent: source)
        )

        func verify(_ needle: String, field: SearchMatchedField) throws {
            let normalizedNeedle = SearchTextNormalization.lexicalNormalize(needle)
            let segment = try #require(projection.segments.first {
                $0.field == field && $0.normalizedText.contains(normalizedNeedle)
            })
            let match = try #require(segment.normalizedText.range(of: normalizedNeedle))
            let normalizedRange = match.lowerBound.utf16Offset(in: segment.normalizedText)
                ..< match.upperBound.utf16Offset(in: segment.normalizedText)
            let sourceRange = try #require(
                segment.sourceUTF16Range(forNormalizedUTF16Range: normalizedRange)
            )
            #expect((source as NSString).substring(with: NSRange(
                location: sourceRange.lowerBound,
                length: sourceRange.count
            )) == needle)
        }

        try verify("😀 Heading", field: .heading)
        try verify("עברית", field: .body)
        try verify("العربية", field: .body)
        try verify("Cafe\u{301}", field: .body)
        #expect(projection.sourceLineStartsUTF16.count == 7)
    }
}
