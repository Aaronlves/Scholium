import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Safe Markdown image delivery")
struct SafeMarkdownRendererImageDeliveryTests {
    @Test(
        "Catalog keys decode parser entities and percent spelling while preview targets retain it",
        arguments: ["a&amp;b%20one.png", "a&#38;b%20one.png", "a&#x26;b%20one.png", #"a\&b%20one.png"#])
    func decodedResourceKeys(destination: String) throws {
        let source = "\u{FEFF}---\r\nunknown: 'e\u{301} 🦉' # keep\r\n---\r\n\r\n![A & B](Attachments/\(destination) \"A title\")\r\n"
        let document = NoteDocument(relativePath: "Images.md", rawContent: source)
        let image = try png()
        let html = SafeMarkdownRenderer.render(
            document, embeddedImages: ["Attachments/a&b one.png": image], imageDelivery: .resourceCatalog
        ).htmlBody

        #expect(html.components(separatedBy: "<img ").count - 1 == 1)
        #expect(html.contains("data-scholium-image-resource=\"Attachments/a&amp;b one.png\""))
        #expect(html.contains("data-scholium-image-target=\"Attachments/a&amp;b%20one.png\""))
        #expect(html.contains("data-scholium-image-layout=\"block\""))
        #expect(html.contains("alt=\"A &amp; B\" title=\"A title\""))
        #expect(!html.contains("src=") && !html.contains("base64,"))
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Catalog delivery propagates through reference images, Callouts, annotations and footnotes")
    func recursiveResources() throws {
        let source =
            "\u{FEFF}---\r\nunknown: 'e\u{301} 🦉' # keep\r\n---\r\n\r\n"
            + "![Reference][figure]\r\n\r\n[figure]: reference.png\r\n\r\n"
            + "> [!note] ![Title](title.png)\r\n> ![Callout](callout.png)\r\n\r\n"
            + "[[Peer]]{{![Annotation](annotation.png)}}\r\n\r\n"
            + "Footnote[^image].\r\n\r\n[^image]: ![Footnote](footnote.png)\r\n\r\n"
            + "Inline ^[Synthetic footnote text].\r\n"
        let document = NoteDocument(relativePath: "Recursive.md", rawContent: source)
        let destinations = ["reference", "title", "callout", "annotation", "footnote"]
        let image = try png()
        let images = Dictionary(uniqueKeysWithValues: destinations.map { ("\($0).png", image) })
        let rendered = SafeMarkdownRenderer.render(document, embeddedImages: images, imageDelivery: .resourceCatalog)

        #expect(rendered.htmlBody.components(separatedBy: "<img ").count - 1 == destinations.count)
        for destination in destinations {
            #expect(rendered.htmlBody.contains("data-scholium-image-resource=\"\(destination).png\""))
        }
        #expect(!rendered.htmlBody.contains("src=") && !rendered.htmlBody.contains("base64,"))
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Standalone export retains inline bytes and resource catalogs never authorize absent images")
    func standaloneAndAdmission() throws {
        let image = try png()
        let source = "Before ![Inline](figure.png) after.\n\n![Missing](missing.png)\n\n![Remote](https://example.invalid/private.png)\n"
        let document = NoteDocument(relativePath: "Export.md", rawContent: source)
        let images = ["figure.png": image, "https://example.invalid/private.png": image]
        let standalone = SafeMarkdownRenderer.render(document, embeddedImages: images)
        let explicitInline = SafeMarkdownRenderer.render(document, embeddedImages: images, imageDelivery: .inlineData)
        let catalog = SafeMarkdownRenderer.render(document, embeddedImages: images, imageDelivery: .resourceCatalog)

        #expect(standalone == explicitInline)
        #expect(standalone.htmlBody.contains("src=\"data:image/png;base64,\(image.data.base64EncodedString())\""))
        #expect(!standalone.htmlBody.contains("data-scholium-image-resource="))
        #expect(catalog.htmlBody.contains("data-scholium-image-layout=\"inline\""))
        #expect(catalog.htmlBody.components(separatedBy: "<img ").count - 1 == 1)
        #expect(!catalog.htmlBody.contains("src=") && !catalog.htmlBody.contains("base64,"))
        #expect(!SafeMarkdownRenderer.render(document, imageDelivery: .resourceCatalog).htmlBody.contains("<img "))
        let stale = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: document.relativePath, rawContent: "old"))
        #expect(SafeMarkdownRenderer.render(document, semantic: stale, embeddedImages: images, imageDelivery: .resourceCatalog) == catalog)
        #expect(document.sourceBytes == Data(source.utf8))
    }

    private func png() throws -> RenderedMarkdownImage {
        try RenderedMarkdownImage(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), mimeType: "image/png")
    }
}
