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
