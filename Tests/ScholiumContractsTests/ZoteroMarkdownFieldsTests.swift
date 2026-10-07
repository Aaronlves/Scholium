import Foundation
import ScholiumContracts
import Testing

@Suite("Source-owned Zotero Markdown fields")
struct ZoteroMarkdownFieldsTests {
    private let citationCode = #"ITEM CSL_CITATION {"citationItems":[{"id":"http://zotero.org/users/1/items/ABCDEFGH"}],"properties":{"plainCitation":"Fang"}}"#

    private func encoded(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]).base64EncodedString()
    }
    private func citation(id: String = "cite_a", fallback: String = "*Fang*", code: String? = nil, text: String = "<i>Fang</i>") throws -> String {
        "[\(fallback)](scholium-zotero:1:\(try encoded(["id": id, "kind": "citation", "code": code ?? citationCode, "text": text])))"
    }
    private func documentState(_ accepted: [[String: String]]? = nil, style: Bool = false) throws -> String {
        var payload: [String: Any] = ["data": "<data>\r\nopaque \"vendor\" data</data>"]
        if let accepted { payload["acceptedFields"] = accepted }
        if style { payload["bibliographyStyle"] = ["firstLineIndent": -720, "indent": 720, "lineSpacing": 240, "entrySpacing": 0, "tabStops": [720]] }
        return "<!--scholium-zotero-document:1:\(try encoded(payload))-->"
    }
    private func bibliography(id: String = "bib_a") throws -> String {
        let payload: [String: Any] = [
            "id": id, "kind": "bibliography", "code": "BIBL {} CSL_BIBLIOGRAPHY",
            "text": "<div class=\"csl-bib-body\"><div class=\"csl-entry\">Fang. <i>Book.</i></div><div class=\"csl-entry\">Other.</div></div>",
        ]
        return "<!--scholium-zotero-field:1:\(try encoded(payload))-->\n\nFang. *Book.*\n\nOther.\n\n<!--/scholium-zotero-field-->"
    }

    @Test("Opaque strings, source spans and deletion-only projection preserve Unicode and CRLF")
    func exactCarrierAndMapping() throws {
        let link = try citation()
        let marker = try documentState([["id": "cite_a", "code": citationCode]])
        let source = "\u{FEFF}---\r\nunknown: 'keep' # comment\r\n---\r\n😀 e\u{301} \(link) 依据。\r\n\r\n\(marker)\r\n"
        let document = NoteDocument(relativePath: "Manuscript.md", rawContent: source)
        let catalog = ZoteroMarkdownFields(parsing: document)
        let field = try #require(catalog.fields.first)
        #expect(catalog.canMutate)
        #expect(!catalog.citationStateStale)
        #expect(field.code == citationCode)
        #expect(field.text == "<i>Fang</i>")
        #expect(field.plainText == "Fang")
        #expect(field.isCompleted)
        #expect((source as NSString).substring(with: field.span.nsRange) == link)
        #expect((source as NSString).substring(with: field.fallbackSpan.nsRange) == "*Fang*")
        #expect(Data(source.utf8).subdata(in: field.span.utf8Range) == Data(link.utf8))
        let projected = try #require(catalog.readingProjection(source: source))
        #expect(projected.source == source.replacingOccurrences(of: link, with: "*Fang*").replacingOccurrences(of: marker, with: ""))
        for segment in projected.segments {
            #expect(
                (projected.source as NSString).substring(with: NSRange(location: segment.projectedRange.lowerBound, length: segment.projectedRange.count))
                    == (source as NSString).substring(with: NSRange(location: segment.sourceRange.lowerBound, length: segment.sourceRange.count)))
        }
        let tail = (projected.source as NSString).range(of: "依据")
        let mapped = try #require(projected.sourceRange(for: tail.location..<NSMaxRange(tail)))
        #expect((source as NSString).substring(with: NSRange(location: mapped.lowerBound, length: mapped.count)) == "依据")
        #expect(catalog.readingProjection(source: source + "changed") == nil)
        #expect(document.rawContent == source)
    }

    @Test("Freshness follows source order and exact code; readable fallback stays current")
    func freshness() throws {
        let a = try citation()
        let b = try citation(id: "cite_b", fallback: "Other")
        let marker = try documentState([["id": "cite_a", "code": citationCode], ["id": "cite_b", "code": citationCode]])
        #expect(!ZoteroMarkdownFields(parsing: .init(relativePath: "a.md", rawContent: "\(a) \(b)\n\n\(marker)")).citationStateStale)
        #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "a.md", rawContent: "\(b) \(a)\n\n\(marker)")).citationStateStale)
        #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "a.md", rawContent: a)).citationStateStale)
        #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "deleted.md", rawContent: marker)).citationStateStale)
        let manual = try citation(fallback: "Manually **changed**", text: "Original")
        let freshMarker = try documentState([["id": "cite_a", "code": citationCode]])
        let document = NoteDocument(relativePath: "manual.md", rawContent: "\(manual)\n\n\(freshMarker)")
        #expect(ZoteroMarkdownFields(parsing: document).fields.first?.plainText == "Manually changed")
        #expect(!ZoteroMarkdownFields(parsing: document).citationStateStale)
        #expect(SafeMarkdownRenderer.render(document).htmlBody.contains("Manually <strong>changed</strong>"))
        #expect(!SafeMarkdownRenderer.render(document).htmlBody.contains("Original"))
    }

    @Test("Copy duplicates and malformed envelopes confer no field or navigation authority")
    func duplicatesAndMalformed() throws {
        let link = try citation()
        let source = "\(link) \(link)"
        let document = NoteDocument(relativePath: "copy.md", rawContent: source)
        let catalog = ZoteroMarkdownFields(parsing: document)
        #expect(!catalog.canMutate)
        #expect(catalog.fields.isEmpty)
        #expect(catalog.diagnostics.filter { $0.kind == .duplicateID }.count == 2)
        #expect(catalog.readingProjection(source: source)?.source == source)
        #expect(!SafeMarkdownRenderer.render(document).htmlBody.contains("href=\"scholium-zotero:"))
        for invalid in ["[Visible](scholium-zotero:2:AAAA)", "[Visible](scholium-zotero:1:AAAA)", "<!--/scholium-zotero-field-->"] {
            let invalidDocument = NoteDocument(relativePath: "invalid.md", rawContent: invalid)
            #expect(!ZoteroMarkdownFields(parsing: invalidDocument).canMutate)
        }
        let marker = try documentState()
        let repeatedDocument = NoteDocument(relativePath: "duplicate-state.md", rawContent: "\(marker)\n\n\(marker)")
        let repeated = ZoteroMarkdownFields(parsing: repeatedDocument)
        #expect(!repeated.canMutate)
        #expect(repeated.documentState == nil)
        #expect(repeated.readingProjection(source: repeatedDocument.rawContent)?.source == repeatedDocument.rawContent)
        let ordinary = NoteDocument(relativePath: "ordinary.md", rawContent: "[About scholium-zotero:](https://example.com)")
        #expect(ZoteroMarkdownFields(parsing: ordinary).canMutate)
        #expect(ZoteroMarkdownFields(parsing: ordinary).fields.isEmpty)
        let globallyInvalidSource = "\(link)\n\n\(marker)\n\n[Invalid](scholium-zotero:2:AAAA)"
        let globallyInvalid = NoteDocument(relativePath: "global.md", rawContent: globallyInvalidSource)
        let globalCatalog = ZoteroMarkdownFields(parsing: globallyInvalid)
        #expect(!globalCatalog.canMutate)
        #expect(globalCatalog.readingProjection(source: globallyInvalidSource)?.source == globallyInvalidSource)
        #expect(!SafeMarkdownRenderer.render(globallyInvalid).htmlBody.contains("class=\"scholium-zotero-citation\""))
        #expect(SafeMarkdownRenderer.render(globallyInvalid).htmlBody.contains("scholium-zotero-document:"))
    }

    @Test("Bibliography and document comments are metadata only after complete source validation")
    func bibliographyRenderingAndRetrieval() throws {
        let link = try citation()
        let bibliography = try bibliography()
        let marker = try documentState([["id": "cite_a", "code": citationCode], ["id": "bib_a", "code": "BIBL {} CSL_BIBLIOGRAPHY"]], style: true)
        let source = "Before \(link).\n\n\(bibliography)\n\nAfter 依据。\n\n\(marker)"
        let document = NoteDocument(relativePath: "bibliography.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let fields = semantic.zoteroFields
        #expect(fields.canMutate)
        #expect(fields.fields.map(\.id) == ["cite_a", "bib_a"])
        #expect(fields.fields.allSatisfy { $0.isCompleted })
        #expect(!fields.citationStateStale)
        #expect(fields.documentState?.bibliographyStyle?.indent == 720)
        #expect(fields.documentState?.bibliographyStyle?.bodyIndentPoints == 36)
        #expect(fields.documentState?.bibliographyStyle?.firstLineOffsetPoints == -36)
        #expect(fields.documentState?.bibliographyStyle?.firstLineIndentPoints == 0)
        #expect(fields.documentState?.bibliographyStyle?.lineHeightMultiple == 1)
        #expect(fields.documentState?.bibliographyStyle?.tabStopPoints == [36])
        #expect(fields.documentState?.data == "<data>\r\nopaque \"vendor\" data</data>")
        let html = SafeMarkdownRenderer.render(document, semantic: semantic).htmlBody
        #expect(html.contains("scholium-zotero-citation"))
        #expect(html.contains("scholium-zotero-bibliography"))
        #expect(html.contains("class=\"scholium-zotero-bibliography-entry\""))
        #expect(html.contains("margin-left:36.0pt;text-indent:-36.0pt;line-height:1.0;"))
        #expect(html.contains("Fang. <em>Book.</em>"))
        #expect(html.contains("After 依据。"))
        #expect(!html.contains("scholium-zotero-document:"))
        #expect(!html.contains("scholium-zotero-field:"))
        #expect(!html.contains("href=\"scholium-zotero:"))
        #expect(!semantic.links.contains { $0.target.hasPrefix("scholium-zotero:") })
        let readable = ResearchExcerptPresentation.readableText(source)
        #expect(readable.contains("Before Fang."))
        #expect(readable.contains("Fang. Book."))
        #expect(!readable.contains("scholium-zotero"))
        let search = SearchDocumentProjection(document: document, semantic: semantic)
        #expect(search.body.contains("Before Fang."))
        #expect(search.body.contains("Fang. Book."))
        #expect(!search.body.contains("CSL_CITATION"))
        #expect(search.paragraphs.count == 4)
        #expect(semantic.blocks.first(where: { (source as NSString).substring(with: $0.span.nsRange) == "After 依据。" })?.span.start.line == 11)
    }

    @Test("Literal examples and unsupported containers cannot become managed fields")
    func protectedContexts() throws {
        let link = try citation()
        let marker = try documentState()
        for source in [
            "`\(link)`", "```md\n\(link)\n\(marker)\n```", "---\nexample: '\(link)'\n---\nBody", "<div>\n\(link)\n\(marker)\n</div>",
            "Before <span>\(link)</span> after.",
        ] {
            #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "literal.md", rawContent: source)).fields.isEmpty)
        }
        for source in ["# \(link)", "- \(link)", "> \(link)", "[^a]: \(link)", "^[\(link)]"] {
            let catalog = ZoteroMarkdownFields(parsing: .init(relativePath: "container.md", rawContent: source))
            #expect(catalog.fields.isEmpty)
            #expect(!catalog.canMutate, "Context prefix: \(source.prefix(6))")
        }
        let unowned = ZoteroMarkdownFields(parsing: .init(relativePath: "unowned.md", rawContent: "Bare scholium-zotero:1:AAAA"))
        #expect(!unowned.canMutate)
        #expect(unowned.fields.isEmpty)
        let escaped = ZoteroMarkdownFields(parsing: .init(relativePath: "escaped.md", rawContent: #"\<!--scholium-zotero-document:1:AAAA-->"#))
        #expect(escaped.canMutate)
        #expect(escaped.fields.isEmpty)
    }

    @Test("Completed-code admission rejects placeholders and malformed vendor payloads")
    func completedCodes() throws {
        for code in [
            "", "TEMP", "ITEM CSL_CITATION {}", "ITEM CSL_CITATION {\"citationItems\":[]}", "ITEM CSL_CITATION {\"citationItems\":[{\"id\":true}]}",
            "ITEM CSL_CITATION {\"citationItems\":[{\"id\":0}]}", "ITEM CSL_CITATION {\"citationItems\":[{\"id\":1.5}]}",
            "ITEM CSL_CITATION {\"citationItems\":[{\"id\":9007199254740992}]}",
        ] {
            let source = try citation(code: code)
            #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "code.md", rawContent: source)).fields.first?.isCompleted == false)
        }
        let numeric = try citation(code: "ITEM CSL_CITATION {\"citationItems\":[{\"id\":1}]}")
        #expect(ZoteroMarkdownFields(parsing: .init(relativePath: "code.md", rawContent: numeric)).fields.first?.isCompleted == true)
    }

    @Test("Invalid paragraph spacing stays source visible instead of creating unusable layout")
    func invalidStyle() throws {
        for (line, entry) in [(0, 0), (-240, 0), (240, -1)] {
            let payload: [String: Any] = [
                "data": "opaque", "bibliographyStyle": ["firstLineIndent": -720, "indent": 720, "lineSpacing": line, "entrySpacing": entry, "tabStops": []],
            ]
            let source = "<!--scholium-zotero-document:1:\(try encoded(payload))-->"
            let document = NoteDocument(relativePath: "style.md", rawContent: source)
            let catalog = ZoteroMarkdownFields(parsing: document)
            #expect(!catalog.canMutate)
            #expect(catalog.documentState == nil)
            #expect(catalog.readingProjection(source: source)?.source == source)
        }
    }

    @Test("Bibliography separators remove exactly two newlines and retain authored blank lines")
    func bibliographySeparatorRanges() throws {
        let source = try bibliography().replacingOccurrences(of: "-->\n\n", with: "-->\n\n\n")
            .replacingOccurrences(of: "\n\n<!--/", with: "\n\n\n<!--/")
        for newline in ["\n", "\r\n"] {
            let exactSource = source.replacingOccurrences(of: "\n", with: newline)
            let catalog = ZoteroMarkdownFields(parsing: .init(relativePath: "Blank.md", rawContent: exactSource))
            let field = try #require(catalog.fields.first)
            #expect(catalog.canMutate)
            #expect(field.fallbackMarkdown == "\(newline)Fang. *Book.*\(newline)\(newline)Other.\(newline)")
            #expect((exactSource as NSString).substring(with: field.fallbackSpan.nsRange) == field.fallbackMarkdown)
        }
        for invalid in [
            try bibliography().replacingOccurrences(of: "-->\n\n", with: "-->\n \n"), try bibliography().replacingOccurrences(of: "\n", with: "\r"),
        ] {
            let catalog = ZoteroMarkdownFields(parsing: .init(relativePath: "InvalidSeparator.md", rawContent: invalid))
            #expect(!catalog.canMutate)
            #expect(catalog.fields.isEmpty)
            #expect(catalog.readingProjection(source: invalid)?.source == invalid)
        }
    }

    @Test("Editor and native catalog share exact source, ranges, fallback and freshness")
    func sharedSourceFixtures() throws {
        let url = try #require(Bundle.module.url(forResource: "zotero-field-source-fixtures", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(SourceFixtures.self, from: Data(contentsOf: url))
        #expect(fixture.version == 1)
        for row in fixture.cases {
            let document = NoteDocument(relativePath: "Fixture.md", rawContent: row.source)
            let catalog = ZoteroMarkdownFields(parsing: document)
            #expect(catalog.fields.map(\.id) == row.ids, "Fixture: \(row.name)")
            #expect(catalog.fields.map(\.plainText) == row.plainTexts, "Fixture: \(row.name)")
            #expect(catalog.citationStateStale == row.stateStale, "Fixture: \(row.name)")
            if let expected = row.diagnosticKinds {
                let kinds = Set(catalog.diagnostics.map { diagnosticName($0.kind) }).sorted()
                #expect(kinds == expected, "Fixture: \(row.name)")
            }
            if let blocked = row.mutationBlocked { #expect(!catalog.canMutate == blocked, "Fixture: \(row.name)") }
            if let expected = row.documentRange {
                let actual = catalog.documentState.map { FixtureRange(from: $0.span.utf16LowerBound, to: $0.span.utf16UpperBound) }
                #expect(actual == expected, "Fixture: \(row.name)")
            }
            #expect(catalog.fields.map { FixtureRange(from: $0.span.utf16LowerBound, to: $0.span.utf16UpperBound) } == row.fieldRanges, "Fixture: \(row.name)")
            #expect(
                catalog.fields.map { FixtureRange(from: $0.fallbackSpan.utf16LowerBound, to: $0.fallbackSpan.utf16UpperBound) } == row.fallbackRanges,
                "Fixture: \(row.name)")
            #expect(document.rawContent == row.source)
        }
        for row in fixture.completedCodes {
            let source =
                row.kind == .citation
                ? try citation(code: row.code)
                : "<!--scholium-zotero-field:1:\(try encoded(["id": "bib_code", "kind": "bibliography", "code": row.code, "text": "Readable"]))-->\n\nReadable\n\n<!--/scholium-zotero-field-->"
            let catalog = ZoteroMarkdownFields(parsing: .init(relativePath: "Code.md", rawContent: source))
            let field = try #require(catalog.fields.first)
            #expect(field.isCompleted == row.completed, "Code: \(row.code)")
        }
    }

    private func diagnosticName(_ kind: ZoteroMarkdownDiagnostic.Kind) -> String {
        switch kind {
        case .malformedEnvelope: "malformed-envelope"
        case .unsupportedEnvelope: "unsupported-envelope"
        case .duplicateID: "duplicate-id"
        case .duplicateDocument: "duplicate-document"
        case .unsupportedText: "unsupported-text"
        case .unsupportedContext: "unsupported-context"
        }
    }

    private struct FixtureRange: Decodable, Equatable {
        let from: Int
        let to: Int
    }
    private struct SourceFixtures: Decodable {
        let version: Int
        let cases: [SourceCase]
        let completedCodes: [CompletedCode]
    }
    private struct SourceCase: Decodable {
        let name: String
        let source: String
        let ids: [String]
        let plainTexts: [String]
        let stateStale: Bool
        let diagnosticKinds: [String]?
        let mutationBlocked: Bool?
        let documentRange: FixtureRange?
        let fieldRanges: [FixtureRange]
        let fallbackRanges: [FixtureRange]
    }
    private struct CompletedCode: Decodable {
        let kind: ZoteroMarkdownField.Kind
        let code: String
        let completed: Bool
    }
}
