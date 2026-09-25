import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Export Markdown image references")
struct ExportMarkdownImageReferencesTests {
    @Test("Reference-style and referenced footnote images use one local target projection")
    func referenceStyleAndFootnote() {
        let document = NoteDocument(
            relativePath: "Folder/Note.md",
            rawContent: """
                ![Chart][figure]

                [figure]: ../Attachments/Chart%20One.png

                A note.[^detail]

                [^detail]: ![Inset](../Attachments/Inset.png)
                """
        )
        let files = ExportMarkdownImageReferences.references(in: document).compactMap {
            if case .local(let file) = $0 { file } else { nil }
        }
        #expect(
            files.map(\.relativePath?.rawValue) == [
                "Attachments/Chart One.png", "Attachments/Inset.png",
            ])
    }

    @Test("Prepared reference-style and footnote bytes reach the shared renderer")
    func referenceStyleRendering() throws {
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let embedded = try RenderedMarkdownImage(data: png, mimeType: "image/png")
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: """
                ![Chart][figure]

                [figure]: Chart%20one.png

                A note.[^detail]

                [^detail]: ![Inset](Inset.png)
                """
        )
        let html = SafeMarkdownRenderer.render(
            document,
            embeddedImages: ["Chart one.png": embedded, "Inset.png": embedded]
        ).htmlBody
        #expect(html.components(separatedBy: "class=\"scholium-embedded-image\"").count == 3)
        #expect(!html.contains("scholium-media-placeholder"))
    }

    @Test("Remote images stay remote and unsupported local targets remain visible")
    func classifications() {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: """
                ![Remote](https://example.org/chart.png)
                ![Query](chart.png?raw=1)
                ![Escape](../outside.png)
                """
        )
        let references = ExportMarkdownImageReferences.references(in: document)
        #expect(references.contains(.remote("https://example.org/chart.png")))
        #expect(references.contains(.unavailable("chart.png?raw=1")))
        #expect(references.contains(.unavailable("../outside.png")))
        #expect(
            ExportMarkdownImageReferences.references(
                in: NoteDocument(
                    relativePath: "Note.md",
                    rawContent: "![Unsupported](data:image/png;base64,AAAA)"
                )
            ).contains(.unavailable("data:image/png;base64,AAAA"))
        )
    }

    @Test("Malformed frontmatter remains literal source during export")
    func malformedFrontmatter() {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "---\n![Not rendered](missing.png)"
        )
        #expect(document.frontmatterState == .malformed)
        #expect(ExportMarkdownImageReferences.references(in: document).isEmpty)
    }

    @Test("An unreferenced footnote image is not part of rendered export")
    func unreferencedFootnote() {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "[^unused]: ![Unused](missing.png)"
        )
        #expect(ExportMarkdownImageReferences.references(in: document).isEmpty)
    }
}
