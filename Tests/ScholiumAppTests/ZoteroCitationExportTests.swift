import AppKit
import Foundation
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
struct ZoteroCitationExportTests {
    private let citationCode = #"ITEM CSL_CITATION {"citationItems":[{"id":"synthetic-item","locator":"12","label":"page"}],"properties":{}}"#
    private let bibliographyCode = "BIBL {} CSL_BIBLIOGRAPHY"

    private func encoded(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
    }

    private func fixture(layout: Bool = true, longEntry: Bool = false) throws -> NoteDocument {
        let citation = try encoded([
            "id": "cite_a", "kind": "citation", "code": citationCode,
            "text": "CACHED CITATION MUST NOT DISPLAY",
        ])
        let bibliography = try encoded([
            "id": "bib_a", "kind": "bibliography", "code": bibliographyCode,
            "text": "<script>CACHED BIBLIOGRAPHY MUST NOT DISPLAY</script>",
        ])
        var state: [String: Any] = [
            "data": "opaque-vendor-document-data",
            "acceptedFields": [["id": "cite_a", "code": citationCode], ["id": "bib_a", "code": bibliographyCode]],
        ]
        if layout {
            state["bibliographyStyle"] = [
                "firstLineIndent": -720, "indent": 720, "lineSpacing": 360,
                "entrySpacing": 120, "tabStops": [720, 1440],
            ]
        }
        let entry =
            longEntry
            ? "Alpha. " + Array(repeating: "Synthetic bibliography wrapping text.", count: 10).joined(separator: " ")
            : "Alpha. *Current Title.* 中文。"
        let source =
            "\u{FEFF}---\r\nunknown: 'keep' # exact source\n---\r\n"
            + "Ordinary prose [(Current, p. 12)](scholium-zotero:1:\(citation)).\n\n"
            + "<!--scholium-zotero-field:1:\(bibliography)-->\r\n\r\n\(entry)\r\n\r\nBeta. **Second Title.**\r\n\r\n<!--/scholium-zotero-field-->\n\n"
            + "<!--scholium-zotero-document:1:\(try encoded(state))-->\r\n\nUnchanged tail."
        return NoteDocument(relativePath: "Synthetic-Citations.md", rawContent: source)
    }

    private func companionFixture() throws -> NoteDocument {
        let source =
            "\u{FEFF}---\r\nunknown: 'keep' # exact source\n---\r\n"
            + "Ordinary prose [(Current, p. 12)](cite:cite_a).\n\n"
            + "<!--cite-bibliography:bib_a-->\r\n\r\nAlpha. "
            + Array(repeating: "Synthetic bibliography wrapping text.", count: 10).joined(separator: " ")
            + " *Current Title.* 中文。\r\n\r\nBeta. **Second Title.**\r\n\r\n<!--/cite-bibliography-->\r\n\nUnchanged tail."
        let data = ZoteroCitationData(
            fields: [
                .init(id: "cite_a", kind: .citation, code: citationCode, text: "CACHED CITATION MUST NOT DISPLAY"),
                .init(id: "bib_a", kind: .bibliography, code: bibliographyCode, text: "<script>CACHED BIBLIOGRAPHY MUST NOT DISPLAY</script>"),
            ],
            documentData: "opaque-vendor-document-data",
            bibliographyStyle: .init(firstLineIndent: -720, indent: 720, lineSpacing: 360, entrySpacing: 120, tabStops: [720, 1440]),
            acceptedFields: [.init(id: "cite_a", code: citationCode), .init(id: "bib_a", code: bibliographyCode)])
        let companion = ZoteroCitationCompanion(
            noteID: UUID(), vaultID: UUID(), sourceFingerprint: DocumentFingerprint(content: source), data: data)
        let bytes = try JSONEncoder().encode(companion)
        let decoded = try ZoteroCitationCompanion.decode(bytes)
        try ZoteroMarkdownFields.validateCompanion(source: source, data: decoded.data)
        return NoteDocument(
            relativePath: "Managed-Citations.md", rawContent: source,
            citationSnapshot: .init(
                noteID: decoded.noteID, vaultID: decoded.vaultID, revision: DocumentFingerprint(data: bytes),
                sourceFingerprint: decoded.sourceFingerprint, data: decoded.data, status: .available))
    }

    private func expectNoCitationAuthority(in output: String) {
        for forbidden in [
            "cite:", "cite-bibliography:", "scholium-zotero:", "<!--scholium-zotero", "ITEM CSL_CITATION", "CSL_BIBLIOGRAPHY", "synthetic-item",
            "opaque-vendor", "CACHED",
        ] {
            #expect(!output.contains(forbidden), "Static output retained citation authority: \(forbidden)")
        }
    }

    private func expectCitationAndBibliographyOrder(in output: String) throws {
        let text = output as NSString
        let positions = try ["(Current, p. 12)", "Alpha.", "Beta.", "Unchanged tail."].map { value in
            let range = text.range(of: value)
            #expect(range.location != NSNotFound, "Static output omitted \(value)")
            return try #require(range.location != NSNotFound ? range.location : nil)
        }
        #expect(positions == positions.sorted())
    }

    @Test("A managed companion exports readable adjacent citation and bibliography through HTML, Word and PDF")
    func compactCompanionExports() async throws {
        let note = try companionFixture()
        let snapshot = try #require(note.citationSnapshot)
        let catalog = MarkdownSemanticDocument(parsing: note).zoteroFields
        #expect(snapshot.sourceFingerprint == note.fingerprint)
        #expect(snapshot.revision != nil)
        #expect(catalog.canMutate && !catalog.citationStateStale)
        #expect(catalog.fields.map(\.id) == ["cite_a", "bib_a"])
        #expect(catalog.fields.map(\.code) == [citationCode, bibliographyCode])
        #expect(catalog.fields.first?.plainText == "(Current, p. 12)")
        #expect(!note.rawContent.contains("opaque-vendor") && !note.rawContent.contains("CACHED"))
        try await checkHTMLFallback(note, style: .apa7)
        try await checkDOCXLayout(note, style: .apa7)
        try await checkPDFLayout(note, paperSize: .letter)
        #expect(note.citationSnapshot == snapshot)
    }

    @Test("Static citation HTML and Word preview use current fallback and source bibliography layout", arguments: [NoteExportStyle.document, .apa7, .mla9])
    func htmlUsesCurrentFallback(style: NoteExportStyle) async throws {
        try await checkHTMLFallback(fixture(), style: style)
    }

    private func checkHTMLFallback(_ note: NoteDocument, style: NoteExportStyle) async throws {
        let source = note.sourceBytes
        #expect(MarkdownSemanticDocument(parsing: note).zoteroFields.fields.count == 2)
        for data in [
            try await NoteExportService.render(
                document: note, title: "Synthetic", format: .html,
                style: style, textSize: 12, paperSize: .letter),
            try await NoteExportService.renderDOCXPreviewHTML(
                document: note, title: "Synthetic",
                style: style, textSize: 12, paperSize: .letter),
        ] {
            let html = try #require(String(data: data, encoding: .utf8))
            #expect(html.contains("(Current, p. 12)"))
            #expect(html.contains("<em>Current Title.</em>"))
            #expect(html.contains("<strong>Second Title.</strong>"))
            #expect(html.contains("class=\"scholium-zotero-bibliography-entry\""))
            #expect(html.contains("margin-left:36.0pt;text-indent:-36.0pt;line-height:1.5;margin-bottom:6.0pt;"))
            #expect(!html.contains("CACHED CITATION"))
            #expect(!html.contains("CACHED BIBLIOGRAPHY"))
            #expect(!html.contains("opaque-vendor-document-data"))
            #expect(!html.contains("scholium-zotero:1:"))
            #expect(!html.contains("<!--scholium-zotero"))
            expectNoCitationAuthority(in: html)
            try expectCitationAndBibliographyOrder(in: html)
        }
        #expect(note.sourceBytes == source)
        #expect(NoteDocument.decodeUTF8PreservingBOM(source) == note.rawContent)
        #expect(MarkdownSemanticDocument(parsing: note).zoteroFields.documentState?.data == "opaque-vendor-document-data")
    }

    @Test("Static DOCX keeps bibliography layout after every page preset without live Zotero fields", arguments: [NoteExportStyle.document, .apa7, .mla9])
    func docxLayoutOverridesProse(style: NoteExportStyle) async throws {
        try await checkDOCXLayout(fixture(), style: style)
    }

    private func checkDOCXLayout(_ note: NoteDocument, style: NoteExportStyle) async throws {
        let source = note.sourceBytes
        let data = try await NoteExportService.render(
            document: note, title: "Synthetic", format: .docx,
            style: style, textSize: 12, paperSize: .letter)
        let package = try await WorkspaceStore.unpackWordDocument(data)
        let xml = try #require(package["word/document.xml"].flatMap { String(data: $0, encoding: .utf8) })
        let document = try XMLDocument(xmlString: xml, options: .nodePreserveWhitespace)
        for title in ["Alpha.", "Beta."] {
            let paragraph = try #require(try document.nodes(forXPath: "//*[local-name()='p' and contains(., '\(title)')]").first as? XMLElement)
            let indent = try #require(paragraph.elements(forName: "w:pPr").first?.elements(forName: "w:ind").first)
            #expect(indent.attribute(forName: "w:left")?.stringValue == "720")
            #expect(indent.attribute(forName: "w:hanging")?.stringValue == "720")
            #expect(indent.attribute(forName: "w:firstLine") == nil)
            let spacing = try #require(paragraph.elements(forName: "w:pPr").first?.elements(forName: "w:spacing").first)
            #expect(spacing.attribute(forName: "w:line")?.stringValue == "360")
            #expect(spacing.attribute(forName: "w:lineRule")?.stringValue == "auto")
            #expect(spacing.attribute(forName: "w:before")?.stringValue == "0")
            #expect(spacing.attribute(forName: "w:after")?.stringValue == "120")
            let tabs = try paragraph.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='tabs']/*[local-name()='tab']").compactMap { $0 as? XMLElement }
            #expect(tabs.map { $0.attribute(forName: "w:pos")?.stringValue } == ["720", "1440"])
        }
        if style != .document {
            let prose = try #require(try document.nodes(forXPath: "//*[local-name()='p' and contains(., 'Ordinary prose')]").first as? XMLElement)
            #expect(
                prose.elements(forName: "w:pPr").first?.elements(forName: "w:ind").first?.attribute(forName: "w:firstLine")?.stringValue == "720",
                "Prose XML: \(prose.xmlString)")
        }
        #expect(xml.contains("Current Title."))
        #expect(xml.contains("中文"))
        #expect(try !document.nodes(forXPath: "//*[local-name()='i']").isEmpty)
        #expect(try !document.nodes(forXPath: "//*[local-name()='b']").isEmpty)
        #expect(try document.nodes(forXPath: "//*[local-name()='fldSimple' or local-name()='fldChar' or local-name()='instrText']").isEmpty)
        #expect(try document.nodes(forXPath: "//@*[local-name()='first-line']").isEmpty)
        #expect(!xml.contains("SCHOLIUMBIBLIOGRAPHY"))
        #expect(!xml.contains("scholium-zotero:"))
        #expect(!xml.contains("opaque-vendor"))
        #expect(!xml.contains("CACHED"))
        try expectCitationAndBibliographyOrder(in: try #require(document.rootElement()?.stringValue))
        for (path, bytes) in package where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
            expectNoCitationAuthority(in: try #require(String(data: bytes, encoding: .utf8)))
        }
        #expect(note.sourceBytes == source)
    }

    @Test("Compact export requires a supported companion bound to the exact source revision")
    func compactCompanionAdmission() async throws {
        let original = try companionFixture()
        let authority = try #require(original.citationSnapshot)
        let missing = original.withCitationSnapshot(nil)
        let unavailable = original.withCitationSnapshot(
            .init(noteID: authority.noteID, vaultID: authority.vaultID, status: .unresolved))
        let unsupported = original.withCitationSnapshot(
            .init(noteID: authority.noteID, vaultID: authority.vaultID, revision: authority.revision, status: .unsupported))
        let mismatched = NoteDocument(
            relativePath: original.relativePath, rawContent: original.rawContent + "\n", citationSnapshot: authority)
        #expect(NoteExportService.citationExportIssue(in: original) == nil)
        for note in [missing, unavailable, unsupported, mismatched] {
            let source = note.sourceBytes
            guard case .citationSourceUnresolved? = NoteExportService.citationExportIssue(in: note) else {
                Issue.record("Unavailable companion authority admitted a compact citation export.")
                continue
            }
            do {
                try NoteExportService.requireCitationExportAdmission(in: note)
                Issue.record("Unavailable companion authority passed export admission.")
            } catch NoteExportError.citationSourceUnresolved {}
            #expect(note.sourceBytes == source)
        }
        // One representative missing-companion case exercises each public
        // format entry point; admission must fail before any renderer starts.
        for format in [NoteExportFormat.html, .docx, .pdf] {
            do {
                _ = try await NoteExportService.render(
                    document: missing, title: "Synthetic", format: format,
                    style: .document, textSize: 12, paperSize: .letter)
                Issue.record("Missing companion reached a format renderer without saved-text authorization.")
            } catch NoteExportError.citationSourceUnresolved {}
        }
        let saved = try await NoteExportService.render(
            document: missing, title: "Synthetic", format: .html,
            style: .document, textSize: 12, paperSize: .letter, allowSavedCitationText: true)
        let html = try #require(String(data: saved, encoding: .utf8))
        try expectCitationAndBibliographyOrder(in: html)
        // Explicit literal saved-text export may show escaped unresolved
        // markers; those must never become executable citation destinations.
        #expect(html.range(of: #"href\s*=\s*["'](?:cite|scholium-zotero):"#, options: [.regularExpression, .caseInsensitive]) == nil)
        #expect(!html.contains("opaque-vendor") && !html.contains("CACHED"))
        #expect(!html.contains("class=\"scholium-zotero-citation\""))
        #expect(!html.contains("margin-left:36.0pt;text-indent:-36.0pt;line-height:1.5;margin-bottom:6.0pt;"))
        #expect(missing.sourceBytes == original.sourceBytes)
        #expect(mismatched.citationSnapshot == authority)
    }

    @Test("Malformed YAML with unresolved companion authority requires explicit saved-text export")
    func malformedFrontmatterCompanionAdmission() async throws {
        let source = "\u{FEFF}---\r\nbroken: [\r\nReadable 😀 e\u{301} prose."
        for status in [ZoteroCitationSnapshot.Status.unresolved, .unsupported] {
            let note = NoteDocument(
                relativePath: "Malformed.md", rawContent: source,
                citationSnapshot: .init(noteID: UUID(), vaultID: UUID(), status: status))
            #expect(note.frontmatterState == .malformed)
            guard case .citationSourceUnresolved? = NoteExportService.citationExportIssue(in: note) else {
                Issue.record("Malformed YAML hid known unavailable citation authority.")
                continue
            }
            for format in [NoteExportFormat.html, .docx, .pdf] {
                do {
                    _ = try await NoteExportService.render(
                        document: note, title: "Synthetic", format: format,
                        style: .document, textSize: 12, paperSize: .letter)
                    Issue.record("Malformed YAML bypassed citation export admission.")
                } catch NoteExportError.citationSourceUnresolved {}
            }
            let saved = try await NoteExportService.render(
                document: note, title: "Synthetic", format: .html,
                style: .document, textSize: 12, paperSize: .letter, allowSavedCitationText: true)
            let html = try #require(String(data: saved, encoding: .utf8))
            #expect(html.contains("class=\"export-source-fallback\""))
            #expect(html.contains(source))
            #expect(note.sourceBytes == Data(source.utf8))
        }
    }

    @Test("Bibliography without declared layout receives no academic prose first-line indent")
    func undeclaredLayoutIsNotProse() async throws {
        let note = try fixture(layout: false)
        let data = try await NoteExportService.render(
            document: note, title: "Synthetic", format: .docx,
            style: .apa7, textSize: 12, paperSize: .letter)
        let package = try await WorkspaceStore.unpackWordDocument(data)
        let xml = try #require(package["word/document.xml"].flatMap { String(data: $0, encoding: .utf8) })
        let document = try XMLDocument(xmlString: xml, options: .nodePreserveWhitespace)
        let entry = try #require(try document.nodes(forXPath: "//*[local-name()='p' and contains(., 'Alpha.')]").first as? XMLElement)
        let indent = entry.elements(forName: "w:pPr").first?.elements(forName: "w:ind").first
        #expect(indent?.attribute(forName: "w:firstLine")?.stringValue != "720")
    }

    @Test("Known stale citation exports require an explicit saved-text choice before any format renderer")
    func knownStaleExportAdmission() async throws {
        let original = try fixture()
        let bibliography = try #require(MarkdownSemanticDocument(parsing: original).zoteroFields.fields.first { $0.kind == .bibliography })
        let staleSource = (original.rawContent as NSString).replacingCharacters(in: bibliography.span.nsRange, with: "")
        let stale = NoteDocument(relativePath: original.relativePath, rawContent: staleSource)
        #expect(NoteExportService.citationExportIssue(in: original) == nil)
        guard case .citationStateStale? = NoteExportService.citationExportIssue(in: stale) else {
            Issue.record("Removing a managed occurrence must require refresh or explicit saved-text export.")
            return
        }
        for format in [NoteExportFormat.html, .pdf, .docx] {
            do {
                _ = try await NoteExportService.render(
                    document: stale, title: "Synthetic", format: format,
                    style: .apa7, textSize: 12, paperSize: .letter)
                Issue.record("Known stale source reached a format renderer without saved-text authorization.")
            } catch NoteExportError.citationStateStale {}
        }
        let saved = try await NoteExportService.render(
            document: stale, title: "Synthetic", format: .html,
            style: .apa7, textSize: 12, paperSize: .letter, allowSavedCitationText: true)
        let preview = try await NoteExportService.renderDOCXPreviewHTML(
            document: stale, title: "Synthetic",
            style: .apa7, textSize: 12, paperSize: .letter, allowSavedCitationText: true)
        for data in [saved, preview] {
            let html = try #require(String(data: data, encoding: .utf8))
            #expect(html.contains("(Current, p. 12)"))
            #expect(!html.contains("CACHED CITATION"))
            #expect(!html.contains("scholium-zotero:1:"))
        }
        #expect(stale.rawContent == staleSource)
        #expect(NoteDocument.decodeUTF8PreservingBOM(stale.sourceBytes) == staleSource)
    }

    @Test("Unresolved citation source has a distinct admission error and preserves explicit literal saved text")
    func unresolvedExportAdmission() async throws {
        let original = try fixture()
        let occurrence = try #require(MarkdownSemanticDocument(parsing: original).zoteroFields.fields.first { $0.kind == .citation })
        let copied = (original.rawContent as NSString).substring(with: occurrence.span.nsRange)
        let source = original.rawContent + "\n\n" + copied
        let unresolved = NoteDocument(relativePath: original.relativePath, rawContent: source)
        guard case .citationSourceUnresolved? = NoteExportService.citationExportIssue(in: unresolved) else {
            Issue.record("Duplicate managed identities must remain unresolved.")
            return
        }
        do {
            _ = try await NoteExportService.render(
                document: unresolved, title: "Synthetic", format: .html,
                style: .document, textSize: 12, paperSize: .letter)
            Issue.record("Unresolved source exported without an explicit saved-text choice.")
        } catch NoteExportError.citationSourceUnresolved {}
        let data = try await NoteExportService.render(
            document: unresolved, title: "Synthetic", format: .html,
            style: .document, textSize: 12, paperSize: .letter, allowSavedCitationText: true)
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(html.contains("Current"))
        #expect(!html.contains("<script>"))
        #expect(!html.contains("class=\"scholium-zotero-citation\""))
        #expect(NoteDocument.decodeUTF8PreservingBOM(unresolved.sourceBytes) == source)
    }

    @Test("Word preparation marks source bibliography entries separately from preset prose", arguments: [NoteExportStyle.document, .apa7, .mla9])
    func wordPreparationKeepsBibliographyOwnership(style: NoteExportStyle) async throws {
        let note = try fixture()
        let html = try #require(
            String(
                data: try await NoteExportService.renderDOCXPreviewHTML(
                    document: note, title: "Synthetic", style: style, textSize: 12, paperSize: .letter), encoding: .utf8))
        // This production preparation path imports only authored footnotes;
        // the citation-only fixture needs no operating-system HTML service.
        let prepared = NoteExportService.prepareWordContent(html: html, document: note)
        #expect(prepared.footnotes.isEmpty)
        #expect(prepared.bibliographies.count == 2)
        let layout = try #require(MarkdownSemanticDocument(parsing: note).zoteroFields.documentState?.bibliographyStyle)
        #expect(prepared.bibliographies.values.allSatisfy { $0 == layout })
        for marker in prepared.bibliographies.keys { #expect(prepared.html.components(separatedBy: marker).count == 2) }
        let marked = NoteExportService.markBodyParagraphs(in: prepared.html, with: "PRESETPROSEMARKER")
        let section = try #require(marked.range(of: #"<section class="scholium-zotero-bibliography"[\s\S]*?</section>"#, options: .regularExpression))
        #expect(!marked[section].contains("PRESETPROSEMARKER"))
        #expect(marked.components(separatedBy: "PRESETPROSEMARKER").count == 3)
    }

    private func syntheticWordXML(markers: [String]) -> String {
        let entries = markers.enumerated().map { index, marker in
            """
            <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="100"/></w:tabs><w:spacing w:before="40" w:after="240" w:line="480" w:lineRule="auto"/><w:ind w:firstLine="720"/><w:jc w:val="left"/></w:pPr><w:r><w:t>\(marker)</w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>Entry \(index). 中文。</w:t></w:r></w:p>
            """
        }.joined()
        return """
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:spacing w:line="480"/><w:ind w:firstLine="720"/></w:pPr><w:r><w:t>Ordinary prose.</w:t></w:r></w:p>\(entries)<w:p><w:r><w:t>Unrelated tail.</w:t></w:r></w:p></w:body></w:document>
            """
    }

    @Test("Production DOCX XML finalizer overrides preset bibliography layout and preserves unrelated content")
    func deterministicWordXMLLayout() throws {
        let layout = try #require(MarkdownSemanticDocument(parsing: fixture()).zoteroFields.documentState?.bibliographyStyle)
        let before = syntheticWordXML(markers: ["ENTRY_A", "ENTRY_B"])
        let after = try NoteExportService.replacingWordMarkers(
            in: before, footnotes: [:], links: [], headings: [:],
            bibliographies: ["ENTRY_A": layout, "ENTRY_B": layout])
        let input = try XMLDocument(xmlString: before)
        let output = try XMLDocument(xmlString: after)
        let paragraphs = try output.nodes(forXPath: "//*[local-name()='p']").compactMap { $0 as? XMLElement }
        #expect(paragraphs.map(\.stringValue) == ["Ordinary prose.", "Entry 0. 中文。", "Entry 1. 中文。", "Unrelated tail."])
        let originals = try input.nodes(forXPath: "//*[local-name()='p']").compactMap { $0 as? XMLElement }
        #expect(paragraphs.first?.xmlString == originals.first?.xmlString)
        #expect(paragraphs.last?.xmlString == originals.last?.xmlString)
        for entry in paragraphs.dropFirst().dropLast() {
            let properties = try #require(entry.elements(forName: "w:pPr").first)
            #expect(properties.children?.compactMap(\.localName) == ["tabs", "spacing", "ind", "jc"])
            let indent = try #require(properties.elements(forName: "w:ind").first)
            #expect(indent.attribute(forName: "w:left")?.stringValue == "720")
            #expect(indent.attribute(forName: "w:hanging")?.stringValue == "720")
            #expect(indent.attribute(forName: "w:firstLine") == nil)
            let spacing = try #require(properties.elements(forName: "w:spacing").first)
            #expect(spacing.attribute(forName: "w:before")?.stringValue == "0")
            #expect(spacing.attribute(forName: "w:after")?.stringValue == "120")
            #expect(spacing.attribute(forName: "w:line")?.stringValue == "360")
            #expect(spacing.attribute(forName: "w:lineRule")?.stringValue == "auto")
            let tabs = try entry.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='tabs']/*[local-name()='tab']").compactMap { $0 as? XMLElement }
            #expect(tabs.map { $0.attribute(forName: "w:pos")?.stringValue } == ["720", "1440"])
        }
        #expect(try output.nodes(forXPath: "//*[local-name()='i']").count == 2)
        #expect(try output.nodes(forXPath: "//*[local-name()='fldSimple' or local-name()='fldChar' or local-name()='instrText']").isEmpty)
        #expect(!after.contains("ENTRY_"))
    }

    @Test("Missing or duplicated bibliography entry markers refuse DOCX finalization")
    func missingOrDuplicateWordMarkers() throws {
        let layout = try #require(MarkdownSemanticDocument(parsing: fixture()).zoteroFields.documentState?.bibliographyStyle)
        for markers in [[], ["ENTRY_A", "ENTRY_A"]] {
            #expect(throws: (any Error).self) {
                try NoteExportService.replacingWordMarkers(
                    in: syntheticWordXML(markers: markers), footnotes: [:], links: [], headings: [:],
                    bibliographies: ["ENTRY_A": layout])
            }
        }
    }

    @Test("DOCX finalization preserves native prose indentation in standard OOXML")
    func nativeProseIndentNormalization() throws {
        let before = """
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:ind w:left="120" w:first-line="720"/></w:pPr><w:r><w:t>Native prose. 中文。</w:t></w:r></w:p><w:p><w:pPr><w:ind w:firstLine="360"/></w:pPr><w:r><w:t>Unrelated prose.</w:t></w:r></w:p></w:body></w:document>
            """
        let after = try NoteExportService.replacingWordMarkers(in: before, footnotes: [:], links: [], headings: [:], bibliographies: [:])
        let document = try XMLDocument(xmlString: after)
        let indents = try document.nodes(forXPath: "//*[local-name()='ind']").compactMap { $0 as? XMLElement }
        #expect(indents.map { $0.attribute(forName: "w:firstLine")?.stringValue } == ["720", "360"])
        #expect(indents.first?.attribute(forName: "w:left")?.stringValue == "120")
        #expect(try document.nodes(forXPath: "//@*[local-name()='first-line']").isEmpty)
        #expect(document.rootElement()?.stringValue == "Native prose. 中文。Unrelated prose.")
        let ambiguous = before.replacingOccurrences(of: "w:first-line=\"720\"", with: "w:first-line=\"720\" w:firstLine=\"360\"")
        #expect(throws: (any Error).self) {
            try NoteExportService.replacingWordMarkers(in: ambiguous, footnotes: [:], links: [], headings: [:], bibliographies: [:])
        }
    }

    @Test("Static PDF preserves physical paper, margin, bibliography indent and line spacing", arguments: [NoteExportPaperSize.letter, .a4])
    func pdfHangingIndent(paperSize: NoteExportPaperSize) async throws {
        try await checkPDFLayout(fixture(longEntry: true), paperSize: paperSize)
    }

    private func checkPDFLayout(_ note: NoteDocument, paperSize: NoteExportPaperSize) async throws {
        let source = note.sourceBytes
        let data = try await NoteExportService.render(
            document: note, title: "Synthetic", format: .pdf,
            style: .apa7, textSize: 12, paperSize: paperSize)
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string) as NSString
        let first = text.range(of: "Alpha.")
        #expect(first.location != NSNotFound)
        let lineEnd = text.range(of: "\n", range: NSRange(location: first.location, length: text.length - first.location))
        #expect(lineEnd.location != NSNotFound)
        let firstLine = try #require(page.selection(for: first))
        let nextLine = try #require(page.selection(for: NSRange(location: NSMaxRange(lineEnd), length: 3)))
        let firstBounds = firstLine.bounds(for: page)
        let nextBounds = nextLine.bounds(for: page)
        #expect(page.bounds(for: .mediaBox).size == paperSize.pointSize)
        #expect(abs(firstBounds.minX - 72) < 2, "PDF physical body margin: \(firstBounds)")
        #expect(
            abs(nextBounds.minX - firstBounds.minX - 36) < 2,
            "PDF first line: \(firstBounds); next line: \(nextBounds)")
        #expect(
            abs(firstBounds.minY - nextBounds.minY - 18) < 2,
            "PDF bibliography line spacing: \(firstBounds.minY - nextBounds.minY)")
        let exportedText = try #require(document.string)
        expectNoCitationAuthority(in: exportedText)
        try expectCitationAndBibliographyOrder(in: exportedText)
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            #expect(page.annotations.allSatisfy { ($0.action as? PDFActionURL)?.url == nil })
        }
        #expect(note.sourceBytes == source)
    }
}
