import AppKit
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
struct NoteExportServiceTests {
    @Test("Export presets use selected document typography or academic page spacing")
    func stylePresets() async throws {
        let note = NoteDocument(relativePath: "Styles.md", rawContent: "A paragraph.")
        let appearance = DocumentAppearanceSettings(
            body: DocumentBodyAppearance(fontFamily: .georgia, lineHeight: 1.9)
        )
        let document = try #require(
            String(
                data: try await NoteExportService.render(
                    document: note, title: "Styles", format: .html,
                    style: .document, textSize: 15, paperSize: .a4, appearance: appearance
                ), encoding: .utf8))
        #expect(document.contains("Georgia"))
        #expect(document.contains("font-size: 15.0pt"))

        for style in [NoteExportStyle.apa7, .mla9] {
            let html = try #require(
                String(
                    data: try await NoteExportService.render(
                        document: note, title: "Styles", format: .html,
                        style: style, textSize: 12, paperSize: .letter
                    ), encoding: .utf8))
            #expect(html.contains("@page { size: Letter; margin: 72pt; }"))
            #expect(html.contains("line-height: 2"))
            #expect(html.contains("text-indent: 36pt"))
        }

        let withMetadata = NoteDocument(
            relativePath: "Paper.md",
            rawContent: "---\nprivate: draft\n---\n# Authored title\n\nThe body."
        )
        let academic = try #require(
            String(
                data: try await NoteExportService.render(
                    document: withMetadata, title: "Paper", format: .html,
                    style: .apa7, textSize: 12, paperSize: .letter
                ), encoding: .utf8))
        #expect(!academic.contains("private: draft"))
        #expect(!academic.contains("class=\"export-title\""))
        #expect(academic.contains("Authored title"))

        let wordData = try await NoteExportService.render(
            document: note, title: "Styles", format: .docx,
            style: .apa7, textSize: 12, paperSize: .letter
        )
        let word = try NSAttributedString(
            data: wordData,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        )
        let bodyIndex = (word.string as NSString).range(of: "A paragraph.").location
        #expect(bodyIndex != NSNotFound)
        let wordFont = try #require(
            word.attribute(.font, at: bodyIndex, effectiveRange: nil) as? NSFont)
        #expect(abs(wordFont.pointSize - 12) < 0.5)
        let wordParagraph = try #require(
            word.attribute(.paragraphStyle, at: bodyIndex, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(wordParagraph.firstLineHeadIndent >= 35.5)
    }

    @Test("Standalone HTML escapes its title and keeps rendered source text")
    func htmlIsSelfContained() async throws {
        let document = NoteDocument(relativePath: "Safe.md", rawContent: "中文 **research**")
        let data = try await NoteExportService.render(
            document: document, title: "A <B> & C", format: .html,
            style: .document, textSize: 13, paperSize: .a4
        )
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(html.contains("<title>A &lt;B&gt; &amp; C</title>"))
        #expect(html.contains("中文"))
        #expect(html.contains("default-src 'none'"))
    }

    @Test("Native Word output retains Unicode prose")
    func docxRetainsText() async throws {
        let document = NoteDocument(relativePath: "Word.md", rawContent: "# 标题\n\n中文 **重点**")
        let data = try await NoteExportService.render(
            document: document, title: "Word", format: .docx,
            style: .document, textSize: 13, paperSize: .a4
        )
        #expect(data.starts(with: [0x50, 0x4B]))
        let imported = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        )
        #expect(imported.string.contains("标题"))
        #expect(imported.string.contains("中文 重点"))
    }

    @Test("Editable DOCX preserves repeated bilingual footnote references and link targets")
    func docxFootnotesAndLinks() async throws {
        let source = """
            # Heading

            A **bold** [linked word](https://example.test/source) 中文[^basis][^basis], repeated[^basis] and another[^other].

            Plain repeat. [repeat](https://example.test/one?a=1&b=2) and [repeat](https://example.test/two) and [**bold** *mixed* 中文](https://example.test/rich). Plain repeat.

            [^basis]: 中文 **註釋** and [footnote link](https://example.test/note).
            [^other]: Another *注释* with [footnote link](https://example.test/other).
            """
        let data = try await NoteExportService.render(
            document: NoteDocument(relativePath: "Footnotes.md", rawContent: source),
            title: "Footnotes", format: .docx, style: .document, textSize: 13, paperSize: .a4
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Scholium-DOCX-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("note.docx")
        try data.write(to: archive)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", archive.path, "-d", root.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
        let documentXML = try String(contentsOf: root.appendingPathComponent("word/document.xml"), encoding: .utf8)
        let footnotesXML = try String(contentsOf: root.appendingPathComponent("word/footnotes.xml"), encoding: .utf8)
        let document = try XMLDocument(xmlString: documentXML, options: .nodePreserveWhitespace)
        let footnotes = try XMLDocument(xmlString: footnotesXML, options: .nodePreserveWhitespace)
        let relationships = try XMLDocument(contentsOf: root.appendingPathComponent("word/_rels/document.xml.rels"))
        let footnoteRelationships = try XMLDocument(contentsOf: root.appendingPathComponent("word/_rels/footnotes.xml.rels"))
        let types = try XMLDocument(contentsOf: root.appendingPathComponent("[Content_Types].xml"))
        #expect(try document.nodes(forXPath: "//*[local-name()='footnoteReference' and @*[local-name()='id']='1']").count == 1)
        #expect(try document.nodes(forXPath: "//*[local-name()='footnoteReference' and @*[local-name()='id']='2']").count == 1)
        #expect(try document.nodes(forXPath: "//*[local-name()='fldSimple' and contains(@*[local-name()='instr'], 'NOTEREF ScholiumFootnote1')]").count == 2)
        let bookmark = try #require(
            document.nodes(forXPath: "//*[local-name()='bookmarkStart' and @*[local-name()='name']='ScholiumFootnote1']").first as? XMLElement)
        let bookmarkID = try #require(bookmark.attribute(forName: "w:id")?.stringValue)
        #expect(try document.nodes(forXPath: "//*[local-name()='bookmarkEnd' and @*[local-name()='id']='\(bookmarkID)']").count == 1)
        #expect(try bookmark.nodes(forXPath: "following-sibling::*[1]/*[local-name()='footnoteReference' and @*[local-name()='id']='1']").count == 1)
        try expectCompatibleWordFontProperties(in: document)
        #expect(try footnotes.nodes(forXPath: "//*[local-name()='footnote' and @*[local-name()='id']='1']").count == 1)
        #expect(try types.nodes(forXPath: "//*[local-name()='Override' and @PartName='/word/footnotes.xml']").count == 1)
        #expect(documentXML.contains("Heading"))
        #expect(try !document.nodes(forXPath: "//*[local-name()='b']").isEmpty)
        #expect(footnotesXML.contains("中文"))
        #expect(footnotesXML.contains("<w:b/>"))
        #expect(footnotesXML.contains("footnote link"))
        #expect(!documentXML.contains("SCHOLIUMFOOTNOTE"))
        #expect(!documentXML.contains("SCHOLIUMLINK"))
        #expect(!documentXML.contains("SCHOLIUMHEADING"))
        #expect(try document.nodes(forXPath: "//*[local-name()='hyperlink']//*[local-name()='hyperlink']").isEmpty)
        func targets(_ part: XMLDocument, _ rels: XMLDocument) throws -> [(String, String)] {
            let items = try rels.nodes(forXPath: "//*[local-name()='Relationship']").compactMap { $0 as? XMLElement }
            let ids = items.compactMap { $0.attribute(forName: "Id")?.stringValue }
            #expect(Set(ids).count == ids.count)
            return try part.nodes(forXPath: "//*[local-name()='hyperlink']").map { node in
                let element = try #require(node as? XMLElement)
                let id = try #require(element.attribute(forName: "r:id")?.stringValue)
                let relationship = try #require(items.first(where: { $0.attribute(forName: "Id")?.stringValue == id }))
                #expect(relationship.attribute(forName: "TargetMode")?.stringValue == "External")
                return (element.stringValue ?? "", try #require(relationship.attribute(forName: "Target")?.stringValue))
            }
        }
        let bodyLinks = try targets(document, relationships)
        // XMLNode.stringValue omits whitespace-only w:t nodes. The native
        // consumer check below verifies the complete visible text separately.
        #expect(bodyLinks.map(\.0) == ["linked word", "repeat", "repeat", "boldmixed 中文"])
        #expect(
            bodyLinks.map(\.1) == ["https://example.test/source", "https://example.test/one?a=1&b=2", "https://example.test/two", "https://example.test/rich"])
        #expect(try targets(footnotes, footnoteRelationships).map(\.1) == ["https://example.test/note", "https://example.test/other"])
        let heading = try #require(document.nodes(forXPath: "//*[local-name()='p' and .//*[local-name()='t' and text()='Heading']]").first as? XMLElement)
        #expect(try !heading.nodes(forXPath: ".//*[local-name()='outlineLvl' and @*[local-name()='val']='0']").isEmpty)
        #expect(try !heading.nodes(forXPath: ".//*[local-name()='pStyle' and @*[local-name()='val']='Heading1']").isEmpty)
        let styles = try XMLDocument(contentsOf: root.appendingPathComponent("word/styles.xml"))
        #expect(try !styles.nodes(forXPath: "//*[local-name()='style' and @*[local-name()='styleId']='Heading1']").isEmpty)
        let imported = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        #expect(imported.string.contains("bold mixed 中文"))
        #expect(imported.string.contains("Plain repeat."))
    }

    @Test("Plain DOCX normalizes native font XML while preserving editable emphasis and bilingual text")
    func plainDocxFontCompatibility() async throws {
        let data = try await NoteExportService.render(
            document: NoteDocument(relativePath: "Plain.md", rawContent: "A **bold** *italic* 中文."),
            title: "Plain", format: .docx, style: .apa7, textSize: 12, paperSize: .letter
        )
        let package = try await WorkspaceStore.unpackWordDocument(data)
        let xml = try #require(package["word/document.xml"])
        let document = try XMLDocument(data: xml, options: .nodePreserveWhitespace)
        try expectCompatibleWordFontProperties(in: document)
        #expect(try !document.nodes(forXPath: "//*[local-name()='szCs']").isEmpty)
        #expect(
            try !document.nodes(forXPath: "//*[local-name()='r' and ./*[local-name()='t' and text()='bold']]/*[local-name()='rPr']/*[local-name()='b']").isEmpty
        )
        #expect(
            try !document.nodes(forXPath: "//*[local-name()='r' and ./*[local-name()='t' and text()='italic']]/*[local-name()='rPr']/*[local-name()='i']")
                .isEmpty)
        let imported = try NSAttributedString(
            data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        #expect(imported.string.contains("A bold italic 中文."))
    }

    private func expectCompatibleWordFontProperties(in document: XMLDocument) throws {
        #expect(try document.nodes(forXPath: "//*[local-name()='sz-cs']").isEmpty)
        // OOXML orders emphasis and character spacing before font sizes, and
        // underline after them. Check the actual exported runs, including links.
        let fontOrder = ["rFonts", "b", "i", "spacing", "sz", "szCs", "u"]
        for node in try document.nodes(forXPath: "//*[local-name()='rPr']") {
            let names = (node.children ?? []).compactMap(\.localName).filter(fontOrder.contains)
            #expect(names == fontOrder.filter(names.contains))
        }
    }

    @Test("Repeated Word reference displays the owning note number when an earlier Markdown reference is unresolved")
    func docxRepeatNumberAfterUnresolvedReference() async throws {
        let data = try await NoteExportService.render(
            document: NoteDocument(relativePath: "Gap.md", rawContent: "Missing[^missing], source[^actual], again[^actual].\n\n[^actual]: 註釋."),
            title: "Gap", format: .docx, style: .apa7, textSize: 12, paperSize: .letter
        )
        let package = try await WorkspaceStore.unpackWordDocument(data)
        let document = try XMLDocument(data: #require(package["word/document.xml"]), options: .nodePreserveWhitespace)
        let field = try #require(document.nodes(forXPath: "//*[local-name()='fldSimple']").first as? XMLElement)
        #expect(field.attribute(forName: "w:instr")?.stringValue?.contains("NOTEREF ScholiumFootnote2") == true)
        #expect(field.stringValue == "1")
        #expect(try document.nodes(forXPath: "//*[local-name()='footnoteReference']").count == 1)
    }

    @Test("Academic Word indentation applies to body paragraphs, not headings or list items")
    func academicWordParagraphRoles() async throws {
        let document = NoteDocument(
            relativePath: "Academic.md",
            rawContent:
                "# Main heading\n\nFirst body paragraph.\n\n## Later heading\n\nSecond body paragraph.\n\n- Listed item\n\n> Quoted paragraph."
        )
        for style in [NoteExportStyle.apa7, .mla9] {
            let data = try await NoteExportService.render(
                document: document, title: "Academic", format: .docx,
                style: style, textSize: 12, paperSize: .letter
            )
            let word = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
            for (text, indented) in [
                ("Main heading", false), ("First body paragraph.", true),
                ("Later heading", false), ("Second body paragraph.", true),
                ("Quoted paragraph.", false),
            ] {
                let location = (word.string as NSString).range(of: text).location
                let index = try #require(location == NSNotFound ? nil : location)
                let paragraph = try #require(
                    word.attribute(.paragraphStyle, at: index, effectiveRange: nil)
                        as? NSParagraphStyle
                )
                #expect(
                    (paragraph.firstLineHeadIndent >= 35.5) == indented,
                    "\(text): head=\(paragraph.headIndent), first=\(paragraph.firstLineHeadIndent), lists=\(paragraph.textLists.count)"
                )
            }
            let listLocation = (word.string as NSString).range(of: "Listed item").location
            let listIndex = try #require(listLocation == NSNotFound ? nil : listLocation)
            let listParagraph = try #require(
                word.attribute(.paragraphStyle, at: listIndex, effectiveRange: nil)
                    as? NSParagraphStyle
            )
            // The native DOCX writer positions list text after its bullet;
            // this is the list margin, not an added academic first-line indent.
            #expect(listParagraph.headIndent > 0)
            #expect(listParagraph.firstLineHeadIndent <= listParagraph.headIndent + 0.5)
            #expect(!word.string.contains("SCHOLIUM-PARAGRAPH"))
            #expect(!word.string.contains("\u{E000}"))
        }
    }

    @Test("PDF includes the end of a long Note on later paper pages")
    func pdfRetainsLongDocumentTail() async throws {
        let source = (1...140).map { index in
            "Paragraph \(index): 中文 research text and explanatory words."
        }.joined(separator: "\n\n")
        let document = NoteDocument(relativePath: "Long.md", rawContent: source)
        let data = try await NoteExportService.render(
            document: document, title: "Long Note", format: .pdf,
            style: .document, textSize: 13, paperSize: .a4
        )
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Paragraph 1:") == true)
        #expect(pdf.string?.contains("Paragraph 140:") == true)
        let extracted = try #require(pdf.string)
        for index in 1...140 {
            #expect(extracted.components(separatedBy: "Paragraph \(index):").count == 2)
        }
    }

    @Test("PDF links remain clickable on both sides of a page break")
    func pdfRetainsLinkAnnotations() async throws {
        let middle = (1...110).map { "Paragraph \($0): Words on a long exported page." }
            .joined(separator: "\n\n")
        let document = NoteDocument(
            relativePath: "Links.md",
            rawContent:
                "[First](https://example.org/first)\n\n\(middle)\n\n[Last](https://example.org/last)"
        )
        let data = try await NoteExportService.render(
            document: document, title: "Links", format: .pdf,
            style: .document, textSize: 13, paperSize: .a4
        )
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 1)
        let firstPage = try #require(pdf.page(at: 0))
        let lastPage = try #require(pdf.page(at: pdf.pageCount - 1))
        let firstLink = try #require(
            firstPage.annotations.first {
                ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.org/first"
            })
        let lastLink = try #require(
            lastPage.annotations.first {
                ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.org/last"
            })
        let firstText = try #require(pdf.findString("First", withOptions: []).first)
        let lastText = try #require(pdf.findString("Last", withOptions: []).last)
        #expect(firstLink.bounds.intersects(firstText.bounds(for: firstPage)))
        #expect(lastLink.bounds.intersects(lastText.bounds(for: lastPage)))
    }

    @Test("Requested source metadata stays visible before the body")
    func authoredYAMLIsVisible() async throws {
        let source = "\u{FEFF}---\r\n# source comment\r\ncustom: \"A & B\"\r\n---\r\n中文 body"
        let document = NoteDocument(relativePath: "YAML.md", rawContent: source)
        let htmlData = try await NoteExportService.render(
            document: document, title: "YAML", format: .html,
            style: .document, textSize: 13, paperSize: .a4, includeYAML: true
        )
        let html = try #require(String(data: htmlData, encoding: .utf8))
        #expect(html.contains("---\r\n# source comment\r\ncustom: &quot;A &amp; B&quot;\r\n---\r\n"))
        let yamlRange = try #require(html.range(of: "# source comment"))
        let bodyRange = try #require(html.range(of: "中文 body"))
        #expect(yamlRange.lowerBound < bodyRange.lowerBound)

        let docxData = try await NoteExportService.render(
            document: document, title: "YAML", format: .docx,
            style: .document, textSize: 13, paperSize: .a4, includeYAML: true
        )
        let docxText = try NSAttributedString(
            data: docxData,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        ).string
        #expect(docxText.contains("# source comment"))
        #expect(docxText.contains("custom: \"A & B\""))
        #expect(docxText.contains("中文 body"))

        let pdfData = try await NoteExportService.render(
            document: document, title: "YAML", format: .pdf,
            style: .document, textSize: 13, paperSize: .a4, includeYAML: true
        )
        let pdfText = try #require(PDFDocument(data: pdfData)?.string)
        #expect(pdfText.contains("# source comment"))
        #expect(pdfText.contains("custom: \"A & B\""))
        // WebKit's PDF text extraction may use compatibility ideographs for
        // the same visible glyph; normalize only the extraction assertion.
        #expect(pdfText.precomposedStringWithCompatibilityMapping.contains("中文 body"))
    }

    @Test("An unclosed YAML opening remains visible as escaped source")
    func malformedOpeningIsLiteral() async throws {
        let document = NoteDocument(
            relativePath: "Unclosed.md",
            rawContent: "---\ncustom: <script>\n中文 body"
        )
        let data = try await NoteExportService.render(
            document: document, title: "Unclosed", format: .html,
            style: .document, textSize: 13, paperSize: .a4
        )
        let html = try #require(String(data: data, encoding: .utf8))
        #expect(html.contains("<pre class=\"export-source-fallback\""))
        #expect(html.contains("custom: &lt;script&gt;"))
        #expect(html.contains("中文 body"))
        #expect(!html.contains("custom: <script>"))
    }

    @Test("An authorized local image is self-contained in HTML and decodes for PDF")
    func localImageIsEmbedded() async throws {
        let png = try #require(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4nGM8oSHyn4GBgYEJRIAwAB8cAgc7DdFwAAAAAElFTkSuQmCC"
            ))
        let image = try RenderedMarkdownImage(data: png, mimeType: "image/png")
        let document = NoteDocument(
            relativePath: "Image.md",
            rawContent: "![Red dot](media/red%20dot.png)"
        )
        let map = ["media/red dot.png": image]
        let htmlData = try await NoteExportService.render(
            document: document, title: "Image", format: .html,
            style: .document, textSize: 13, paperSize: .a4,
            embeddedImages: map
        )
        let html = try #require(String(data: htmlData, encoding: .utf8))
        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(html.contains("img-src data:"))
        #expect(!html.contains("src=\"media/red"))

        let pdfData = try await NoteExportService.render(
            document: document, title: "Image", format: .pdf,
            style: .document, textSize: 13, paperSize: .a4,
            embeddedImages: map
        )
        #expect(PDFDocument(data: pdfData)?.pageCount == 1)
    }

    @Test("An unresolved local Markdown image stops export")
    func missingLocalImageFails() async throws {
        for source in [
            "![Missing](../outside.png)",
            "> ![Missing](../outside.png)",
            "Text[^1].\n\n[^1]: ![Missing](../outside.png)",
        ] {
            let document = NoteDocument(relativePath: "Missing.md", rawContent: source)
            do {
                _ = try await NoteExportService.render(
                    document: document, title: "Missing", format: .html,
                    style: .document, textSize: 13, paperSize: .a4
                )
                Issue.record("The unresolved local image was silently omitted: \(source)")
            } catch {
                #expect(error.localizedDescription.contains("../outside.png"))
            }
        }
    }

    @Test("Word export does not require an image that its format omits")
    func missingImageDoesNotBlockWord() async throws {
        let document = NoteDocument(
            relativePath: "Missing.md",
            rawContent: "Before ![Missing](media/absent.png) after."
        )
        let previewData = try await NoteExportService.renderDOCXPreviewHTML(
            document: document, title: "Missing", style: .document,
            textSize: 13, paperSize: .a4
        )
        let preview = try #require(String(data: previewData, encoding: .utf8))
        #expect(preview.contains("Before"))
        #expect(preview.contains("scholium-media-placeholder"))
        #expect(preview.contains("after."))

        let data = try await NoteExportService.render(
            document: document, title: "Missing", format: .docx,
            style: .document, textSize: 13, paperSize: .a4
        )
        let word = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil
        )
        #expect(word.string.contains("Before"))
        #expect(word.string.contains("after."))

        do {
            _ = try await NoteExportService.render(
                document: document, title: "Missing", format: .html,
                style: .document, textSize: 13, paperSize: .a4
            )
            Issue.record("Normal HTML export accepted an unresolved local image")
        } catch {
            #expect(error.localizedDescription.contains("media/absent.png"))
        }
    }
}
