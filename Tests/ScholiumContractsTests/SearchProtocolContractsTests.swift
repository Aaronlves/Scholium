import Foundation
import ScholiumContracts
import Testing

@Suite("Current Search contracts")
struct SearchProtocolContractsTests {
    @Test("Note provider remains the default and preserves finite lexical syntax")
    func noteProviderFiniteSyntax() throws {
        let result = SearchQueryParser.parse(#"title:"reflective \"equilibrium\"" summary:autonomy autonom* -tag:survey"#)
        let ast = try #require(result.ast)
        #expect(result.diagnostics.isEmpty)
        #expect(ast.provider == .note)
        #expect(!ast.providerWasExplicit)
        #expect(ast.clauses.count == 4)
        guard case .lexical(let title) = ast.clauses[0],
              case .phrase(let phrase) = title.value else {
            Issue.record("Expected a title phrase")
            return
        }
        #expect(title.field == .title)
        #expect(phrase == #"reflective "equilibrium""#)
        guard case .lexical(let summary) = ast.clauses[1] else {
            Issue.record("Expected a summary field")
            return
        }
        #expect(summary.field == .summary)
        #expect(summary.value == .term("autonomy"))
        guard case .lexical(let prefix) = ast.clauses[2],
              case .prefix(let value) = prefix.value else {
            Issue.record("Expected a prefix")
            return
        }
        #expect(value == "autonom")
        guard case .lexical(let excluded) = ast.clauses[3] else {
            Issue.record("Expected an excluded lexical field")
            return
        }
        #expect(excluded.excluded)
        #expect(excluded.field == .tag)
    }

    @Test("Provider selection is closed, order independent, and appears at most once")
    func closedProviderSelection() throws {
        let record = SearchQueryParser.parse(#"action:"Analyze Note" kind:record agency"#)
        let ast = try #require(record.ast)
        #expect(ast.provider == .record)
        #expect(ast.providerWasExplicit)
        #expect(ast.clauses.count == 2)

        let noteOnly = try #require(SearchQueryParser.parse("kind:note").ast)
        #expect(noteOnly.provider == .note)
        #expect(noteOnly.clauses.isEmpty)
        #expect(noteOnly.isFilterOnly)

        let recordOnly = try #require(SearchQueryParser.parse("kind:record").ast)
        #expect(recordOnly.provider == .record)
        #expect(recordOnly.clauses.isEmpty)
        #expect(recordOnly.isFilterOnly)

        #expect(SearchQueryParser.parse("kind:any").diagnostics.first?.code == .unknownStructuredValue)
        #expect(
            SearchQueryParser.parse("kind:note kind:record").diagnostics.first?.code
                == .duplicateClause
        )
    }

    @Test("Structured-only positive and negative queries remain valid")
    func structuredOnly() throws {
        let positive = SearchQueryParser.parse("callout:state")
        #expect(try #require(positive.ast).isFilterOnly)
        let negative = SearchQueryParser.parse("-has:broken-link")
        #expect(try #require(negative.ast).isFilterOnly)
        #expect(SearchQueryParser.parse("-autonomy").diagnostics.first?.code == .onlyExcludedFreeText)
    }

    @Test("Unknown fields and query-level scope selectors fail closed without legacy semantics")
    func currentFieldDiagnostics() {
        #expect(SearchQueryParser.parse("vault:Analyses autonomy").diagnostics.first?.code == .unsupportedScopeSelector)
        #expect(SearchQueryParser.parse("scope:triptych").diagnostics.first?.code == .unsupportedScopeSelector)
        #expect(SearchQueryParser.parse("role:Analyses").diagnostics.first?.code == .unsupportedScopeSelector)
        #expect(SearchQueryParser.parse("status:draft").diagnostics.first?.code == .unsupportedField)
        #expect(SearchQueryParser.parse("review:reviewed").diagnostics.first?.code == .unsupportedField)
        #expect(SearchQueryParser.parse("unknown:value").diagnostics.first?.code == .unknownField)
    }

    @Test("Note properties preserve exact keys and typed equality values")
    func noteProperties() throws {
        let result = SearchQueryParser.parse(#"property:Language property:author="Hannah Arendt""#)
        let ast = try #require(result.ast)
        #expect(ast.provider == .note)
        #expect(ast.clauses.count == 2)
        guard case .property(let presence) = ast.clauses[0],
              case .property(let equality) = ast.clauses[1] else {
            Issue.record("Expected property clauses")
            return
        }
        #expect(presence.key == "Language")
        #expect(presence.value == nil)
        #expect(equality.key == "author")
        #expect(equality.value == "hannah arendt")
        #expect(equality.valueWasQuoted)

        let formulaAST = try #require(
            SearchQueryParser.parse(#"property:formula="p=q""#).ast
        )
        guard case .property(let formula) = formulaAST.clauses.first else {
            Issue.record("Expected formula Property equality")
            return
        }
        #expect(formula.key == "formula")
        #expect(formula.value == "p=q")

        #expect(SearchQueryParser.parse("-property:author").diagnostics.first?.code == .unsupportedSyntax)
        #expect(SearchQueryParser.parse("property:a:b").diagnostics.first?.code == .unsupportedSyntax)
        #expect(SearchQueryParser.parse("property:key=").diagnostics.first?.code == .missingFieldValue)
    }

    @Test("Relation queries require one direction anchor and one canonical relation")
    func noteRelations() throws {
        let result = SearchQueryParser.parse(#"from-note:"Groundwork" relation:supports duty"#)
        let ast = try #require(result.ast)
        #expect(ast.provider == .note)
        #expect(ast.relationQuery?.direction == .fromNote)
        #expect(ast.relationQuery?.noteIdentity == "groundwork")
        #expect(ast.relationQuery?.relation == .supports)

        #expect(SearchQueryParser.parse("from-note:A").diagnostics.first?.code == .missingCompanion)
        #expect(SearchQueryParser.parse("relation:opposes").diagnostics.first?.code == .missingCompanion)
        #expect(
            SearchQueryParser.parse("from-note:A to-note:B relation:neutral")
                .diagnostics.first?.code == .duplicateClause
        )
        #expect(
            SearchQueryParser.parse("from-note:A relation:supports relation:opposes")
                .diagnostics.first?.code == .duplicateClause
        )
        #expect(SearchQueryParser.parse("-from-note:A relation:supports").diagnostics.first?.code == .unsupportedSyntax)
    }

    @Test("Record provider has its own closed fields and rejects Note-only clauses")
    func recordProvider() throws {
        let result = SearchQueryParser.parse(
            #"kind:record note:"Groundwork" action:"Analyze Note" skill:close-reading participant:researcher date:7d agency -obsolete"#
        )
        let ast = try #require(result.ast)
        #expect(ast.provider == .record)
        #expect(ast.clauses.count == 7)
        #expect(ast.recordClauses.count == 7)

        #expect(SearchQueryParser.parse("kind:record title:duty").diagnostics.first?.code == .providerMismatch)
        #expect(SearchQueryParser.parse("kind:record property:author").diagnostics.first?.code == .providerMismatch)
        #expect(SearchQueryParser.parse("kind:record from-note:A relation:supports").diagnostics.first?.code == .providerMismatch)
        #expect(SearchQueryParser.parse("kind:note action:analyze").diagnostics.first?.code == .providerMismatch)
        #expect(SearchQueryParser.parse("kind:record action:analy*").diagnostics.first?.code == .unsupportedSyntax)
        #expect(SearchQueryParser.parse("kind:record -skill:test").diagnostics.first?.code == .unsupportedSyntax)
        #expect(SearchQueryParser.parse("kind:record participant:model").diagnostics.first?.code == .unknownStructuredValue)
        #expect(SearchQueryParser.parse(#"kind:record date:"7d""#).diagnostics.first?.code == .unsupportedSyntax)
    }

    @Test("Explanation and capabilities are deterministic products of the current contract")
    func explanationAndCapabilities() throws {
        let ast = try #require(SearchQueryParser.parse(
            #"kind:note property:author="Arendt" to-note:"Agency" relation:incompatible title:freedom"#
        ).ast)
        let explanation = ast.explanation(scope: .currentVault)
        #expect(explanation.provider == .note)
        #expect(explanation.scope == .currentVault)
        #expect(explanation.operator == .and)
        #expect(explanation.clauses.count == ast.clauses.count)
        #expect(explanation.normalization == [
            .canonicalUnicodeCaseWhitespace,
            .lexicalUnicodeCaseDiacriticWhitespace,
            .cjkCharacterAndOverlappingBigramProjection,
            .caseSensitiveTopLevelPropertyKey,
        ])
        #expect(explanation.ordering == .noteExactIdentityThenBM25ThenTitleRolePath)
        #expect(explanation.limitations.contains(.noteRelationsDirectOnly))
        let recordExplanation = try #require(
            SearchQueryParser.parse("kind:record participant:researcher")
                .ast
        ).explanation(scope: .triptych)
        #expect(recordExplanation.scope == .triptych)
        #expect(recordExplanation.normalization == [
            .canonicalUnicodeCaseWhitespace,
            .lexicalUnicodeCaseDiacriticWhitespace,
        ])
        #expect(recordExplanation.ordering == .recordPinnedThenFinishedAtThenUUID)
        #expect(recordExplanation.limitations.contains(.recordNoCrossObjectRelevance))
        #expect(explanation.clauses.contains {
            if case .property(let key, let value) = $0.kind {
                return key == "author" && value == "arendt"
            }
            return false
        })
        #expect(explanation.clauses.contains {
            if case .relation(let direction, let identity, let relation, let symmetric) = $0.kind {
                return direction == .toNote && identity == "agency"
                    && relation == .incompatible && symmetric
            }
            return false
        })

        #expect(SearchCapabilities.current.contractVersion == SearchContract.currentVersion)
        #expect(SearchCapabilities.current.providers.map(\.provider) == [.note, .record])
        #expect(SearchCapabilities.current.capability(for: .note)?.fields.contains {
            $0.name == "property"
        } == true)
        #expect(SearchCapabilities.current.capability(for: .record)?.fields.contains {
            $0.name == "participant" && $0.allowedValues == ["researcher", "agent"]
        } == true)

        let scoped = SearchCompletionContext(
            propertyKeys: ["language", "limitations"],
            noteIdentities: ["Groundwork", "Critique of Practical Reason"]
        )
        #expect(
            SearchCapabilities.current.completions(
                for: "property:lan",
                context: scoped
            ).first?.replacementText == "property:language"
        )
        #expect(
            SearchCapabilities.current.completions(
                for: "from-note:Crit",
                context: scoped
            ).first?.replacementText
                == #"from-note:"Critique of Practical Reason""#
        )
        #expect(
            SearchCapabilities.current.completions(
                for: "kind:record prop",
                context: scoped
            ).isEmpty
        )
    }

    @Test("Parser bounds query and clause work before execution")
    func boundedQueryWork() {
        let oversized = String(
            repeating: "x",
            count: SearchContract.maximumQueryUTF16Count + 1
        )
        #expect(SearchQueryParser.parse(oversized).diagnostics.first?.code == .unsupportedSyntax)

        let tooManyClauses = Array(
            repeating: "term",
            count: SearchContract.maximumQueryTokenCount + 1
        ).joined(separator: " ")
        #expect(
            SearchQueryParser.parse(tooManyClauses).diagnostics.first?.code
                == .unsupportedSyntax
        )
    }

    @Test("Saved Searches persist definitions and apply declared contract compatibility")
    func savedSearchCurrentDefinitionOnly() throws {
        #expect(SearchContract.isSavedSearchContractCompatible(SearchContract.currentVersion))
        #expect(!SearchContract.isSavedSearchContractCompatible(SearchContract.currentVersion - 1))
        #expect(!SearchContract.isSavedSearchContractCompatible(SearchContract.currentVersion + 1))

        let saved = SavedSearch(
            name: "Records by researcher",
            definition: SearchDefinition(
                query: "kind:record participant:researcher",
                presentationScope: .triptych
            ),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let encoded = try JSONEncoder().encode(saved)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["definition"] != nil)
        #expect(json["state"] == nil)
        #expect(try JSONDecoder().decode(SavedSearch.self, from: encoded) == saved)

        let summarySearch = SavedSearch(
            name: "Current canonical summaries",
            definition: SearchDefinition(
                query: "summary:inheritance",
                presentationScope: .triptych
            )
        )
        #expect(summarySearch.needsEditingDiagnostic == nil)
        #expect(SearchQueryParser.parse(summarySearch.definition.query).ast != nil)

        let old = SavedSearch(
            name: "Old",
            definition: SearchDefinition(
                contractVersion: SearchContract.currentVersion - 1,
                query: "autonomy",
                presentationScope: .triptych
            )
        )
        #expect(old.needsEditingDiagnostic?.code == .needsEditing)
        #expect(old.needsEditingDiagnostic?.needsEditing == true)

        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","state":{"query":"autonomy","scope":"triptych"},"createdAt":0}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SavedSearch.self, from: legacy)
        }
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
        summary: "A concise autonomy map"
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
        #expect(projection.summary == "A concise autonomy map")
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
            (.summary, "autonomy"),
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

    @Test("Summary projection fails closed when exact scalar provenance is unavailable")
    func summaryProjectionRequiresExactScalarProvenance() {
        let block = NoteDocument(
            relativePath: "Block.md",
            rawContent: "---\nsummary: |\n  folded discovery text\n---\nBody\n"
        )
        let blockProperties = SearchPropertyProjection(document: block)
        #expect(blockProperties.entry(forExactKey: "summary")?.valueKind == .string)
        #expect(blockProperties.entry(forExactKey: "summary")?.stringMembers.isEmpty == true)
        #expect(SearchDocumentProjection(document: block).summary == nil)
        #expect(!SearchDocumentProjection(document: block).segments.contains { $0.field == .summary })

        let duplicate = NoteDocument(
            relativePath: "Duplicate.md",
            rawContent: "---\nsummary: first\nsummary: second\n---\nBody\n"
        )
        #expect(SearchDocumentProjection(document: duplicate).summary == nil)
        #expect(!SearchDocumentProjection(document: duplicate).segments.contains { $0.field == .summary })

        let missing = NoteDocument(relativePath: "Missing.md", rawContent: "# No summary\n")
        #expect(SearchDocumentProjection(document: missing).summary == nil)
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
