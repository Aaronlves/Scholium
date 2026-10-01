import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit
import ScholiumContracts
import WebKit

@MainActor
enum NoteExportFormat: Hashable, Sendable {
    case html
    case pdf
    case docx
}

@MainActor
enum NoteExportStyle: Hashable, Sendable {
    case document
    case apa7
    case mla9
}

@MainActor
enum NoteExportPaperSize: Hashable, Sendable {
    case a4
    case letter

    var cssName: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        }
    }

    var pointSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595, height: 842)
        case .letter: CGSize(width: 612, height: 792)
        }
    }
}

private enum NoteExportError: LocalizedError {
    case invalidTextSize
    case invalidSource
    case emptyOutput
    case invalidPDF
    case pageLoadTimedOut
    case missingLocalImage(String)

    var errorDescription: String? {
        switch self {
        case .invalidTextSize: ScholiumL10n.string("The export text size is invalid.")
        case .invalidSource: ScholiumL10n.string("The Note source could not be decoded for export.")
        case .emptyOutput: ScholiumL10n.string("The export produced no document data.")
        case .invalidPDF: ScholiumL10n.string("PDF export could not preserve the complete note.")
        case .pageLoadTimedOut: ScholiumL10n.string("The export page did not finish loading.")
        case .missingLocalImage(let destination):
            ScholiumL10n.string("The image at \(destination) could not be included in the export.")
        }
    }
}

/// Renders one supplied NoteDocument snapshot without reading or changing its source file.
@MainActor
struct NoteExportService {
    /// A Word preview follows the same HTML layout, but keeps the renderer's
    /// visible image placeholder for figures the native Word writer omits.
    static func renderDOCXPreviewHTML(
        document: NoteDocument,
        title: String,
        style: NoteExportStyle,
        textSize: CGFloat,
        paperSize: NoteExportPaperSize,
        appearance: DocumentAppearanceSettings = .defaultSettings,
        includeYAML: Bool = false,
        embeddedImages: [String: RenderedMarkdownImage] = [:]
    ) async throws -> Data {
        let html = try makeHTML(
            document: document, title: title, style: style, textSize: textSize,
            paperSize: paperSize, appearance: appearance, includeYAML: includeYAML,
            embeddedImages: embeddedImages, requireImages: false, pdfLayout: false
        )
        let data = Data(html.utf8)
        guard !data.isEmpty else { throw NoteExportError.emptyOutput }
        return data
    }

    static func render(
        document: NoteDocument,
        title: String,
        format: NoteExportFormat,
        style: NoteExportStyle,
        textSize: CGFloat,
        paperSize: NoteExportPaperSize,
        appearance: DocumentAppearanceSettings = .defaultSettings,
        includeYAML: Bool = false,
        embeddedImages: [String: RenderedMarkdownImage] = [:]
    ) async throws -> Data {
        let html = try makeHTML(
            document: document, title: title, style: style, textSize: textSize,
            paperSize: paperSize, appearance: appearance, includeYAML: includeYAML,
            embeddedImages: embeddedImages, requireImages: format != .docx,
            pdfLayout: format == .pdf
        )
        let htmlData = Data(html.utf8)
        guard !htmlData.isEmpty else { throw NoteExportError.emptyOutput }

        let output: Data
        switch format {
        case .html:
            output = htmlData
        case .pdf:
            output = try await renderPDF(html: html, paperSize: paperSize, style: style)
        case .docx:
            // The native writer retains text styling but flattens structures
            // such as tables and footnotes. Export never becomes source authority.
            let paragraphMarker = "\u{E000}\(UUID().uuidString)\u{E001}"
            let wordHTML =
                style == .document ? html : markBodyParagraphs(in: html, with: paragraphMarker)
            let imported = try NSAttributedString(
                data: Data(wordHTML.utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
            guard imported.length > 0 else { throw NoteExportError.emptyOutput }
            let attributed = styleWordDocument(
                imported, style: style, textSize: textSize, appearance: appearance,
                paragraphMarker: style == .document ? nil : paragraphMarker
            )
            output = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        }
        guard !output.isEmpty else { throw NoteExportError.emptyOutput }
        if format == .docx, !output.starts(with: [0x50, 0x4B]) {
            throw NoteExportError.emptyOutput
        }
        return output
    }

    private static func makeHTML(
        document: NoteDocument,
        title: String,
        style: NoteExportStyle,
        textSize: CGFloat,
        paperSize: NoteExportPaperSize,
        appearance: DocumentAppearanceSettings,
        includeYAML: Bool,
        embeddedImages: [String: RenderedMarkdownImage],
        requireImages: Bool,
        pdfLayout: Bool
    ) throws -> String {
        guard textSize.isFinite, textSize > 0 else {
            throw NoteExportError.invalidTextSize
        }
        try Task.checkCancellation()
        if requireImages, document.frontmatterState != .malformed {
            try requireLocalImages(in: document, embeddedImages: embeddedImages)
        }

        let frontmatter: String?
        let body: String
        if document.rawFrontmatter != nil {
            // Use the source byte boundary to include both YAML delimiters,
            // unknown keys, comments, whitespace, and the original newlines.
            let sourcePrefix = Data(document.sourceBytes.prefix(document.bodyByteRange.lowerBound))
            guard let exactFrontmatter = NoteDocument.decodeUTF8PreservingBOM(sourcePrefix) else {
                throw NoteExportError.invalidSource
            }
            frontmatter = exactFrontmatter
            let semantic = MarkdownSemanticDocument(parsing: document)
            body =
                SafeMarkdownRenderer.render(
                    document, semantic: semantic, embeddedImages: embeddedImages
                ).htmlBody
        } else if document.frontmatterState == .malformed {
            // An unclosed opening delimiter has no provable body boundary.
            // Show the entire source literally rather than reinterpret it.
            frontmatter = nil
            body =
                "<pre class=\"export-source-fallback\" dir=\"auto\">\(escapeHTML(document.rawContent))</pre>"
        } else {
            frontmatter = nil
            let semantic = MarkdownSemanticDocument(parsing: document)
            body =
                SafeMarkdownRenderer.render(
                    document, semantic: semantic, embeddedImages: embeddedImages
                ).htmlBody
        }
        let html = standaloneHTML(
            title: title,
            frontmatter: frontmatter,
            body: body,
            style: style,
            textSize: textSize,
            paperSize: paperSize,
            appearance: appearance,
            includeYAML: includeYAML,
            pdfLayout: pdfLayout
        )
        return html
    }

    private static func styleWordDocument(
        _ source: NSAttributedString,
        style: NoteExportStyle,
        textSize: CGFloat,
        appearance: DocumentAppearanceSettings,
        paragraphMarker: String?
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: result.length)
        let family: String
        switch style {
        case .document:
            switch appearance.body.fontFamily {
            case .alegreya: family = "Alegreya"
            case .iowan: family = "Iowan Old Style"
            case .palatino: family = "Palatino"
            case .georgia: family = "Georgia"
            case .times: family = "Times New Roman"
            case .systemSerif: family = "New York"
            default: family = appearance.body.fontFamily.rawValue
            }
        case .apa7, .mla9:
            family = "Times New Roman"
        }
        source.enumerateAttribute(.font, in: range) { value, run, _ in
            let original = value as? NSFont
            let size =
                style == .document
                ? max(8, (original?.pointSize ?? 16) * textSize / 16)
                : textSize
            var font =
                NSFont(name: family, size: size)
                ?? NSFont(name: "Iowan Old Style", size: size)
                ?? NSFont.systemFont(ofSize: size)
            if let original {
                let traits = original.fontDescriptor.symbolicTraits
                if traits.contains(.bold) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                if traits.contains(.italic) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
            }
            result.addAttribute(.font, value: font, range: run)
        }
        if style != .document {
            source.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                let paragraph =
                    (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 0
                paragraph.firstLineHeadIndent = 0
                result.addAttribute(.paragraphStyle, value: paragraph, range: run)
            }
            if let paragraphMarker {
                let text = result.string as NSString
                var markerRanges: [NSRange] = []
                var search = NSRange(location: 0, length: text.length)
                while search.length > 0 {
                    let markerRange = text.range(of: paragraphMarker, options: [], range: search)
                    guard markerRange.location != NSNotFound else { break }
                    markerRanges.append(markerRange)
                    let end = NSMaxRange(markerRange)
                    search = NSRange(location: end, length: text.length - end)
                }
                for markerRange in markerRanges {
                    let paragraphRange = text.paragraphRange(for: markerRange)
                    let paragraph =
                        (result.attribute(
                            .paragraphStyle, at: markerRange.location, effectiveRange: nil
                        ) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    // AppKit's HTML importer drops CSS text-indent. Only an
                    // actual <p> at the normal body margin receives this indent.
                    if paragraph.headIndent == 0 {
                        paragraph.firstLineHeadIndent = 36
                        result.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
                    }
                }
                for markerRange in markerRanges.reversed() {
                    result.deleteCharacters(in: markerRange)
                }
            }
        }
        return result
    }

    private static func markBodyParagraphs(in html: String, with marker: String) -> String {
        let tags = try! NSRegularExpression(pattern: "</?([A-Za-z][A-Za-z0-9-]*)\\b[^>]*>")
        let source = html as NSString
        let excludedContainers: Set<String> = ["li", "blockquote", "td", "th"]
        var insideMain = false
        var excludedDepth = 0
        var cursor = 0
        var marked = ""
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let end = NSMaxRange(match.range)
            marked += source.substring(with: NSRange(location: cursor, length: end - cursor))
            let tag = source.substring(with: match.range(at: 1)).lowercased()
            let closing = source.substring(with: match.range).hasPrefix("</")
            if tag == "main" { insideMain = !closing }
            if excludedContainers.contains(tag) {
                excludedDepth += closing ? -1 : 1
            }
            if tag == "p", !closing, insideMain, excludedDepth == 0 {
                marked += marker
            }
            cursor = end
        }
        marked += source.substring(from: cursor)
        return marked
    }

    private static func standaloneHTML(
        title: String,
        frontmatter: String?,
        body: String,
        style: NoteExportStyle,
        textSize: CGFloat,
        paperSize: NoteExportPaperSize,
        appearance: DocumentAppearanceSettings,
        includeYAML: Bool,
        pdfLayout: Bool
    ) -> String {
        let escapedTitle = escapeHTML(title)
        let styleCSS: String
        let margin: String
        switch style {
        case .document:
            margin = "54pt"
            styleCSS =
                DocumentAppearanceStyles.css(for: appearance) + """
                    .scholium-document { --scholium-document-text-scale-factor: 1; }
                    .scholium-document { font-size: \(Double(textSize))pt; }
                    .export-title { font-family: inherit; font-size: 1.55em; font-weight: 600; }
                    """
        case .apa7:
            margin = "72pt"
            styleCSS = """
                .scholium-document { font-family: "Times New Roman", Times, serif; font-size: \(Double(textSize))pt; line-height: 2; text-align: left; }
                .scholium-document p { margin: 0; text-indent: 36pt; }
                .scholium-document h1, .scholium-document h2 { font-size: 1em; font-weight: 700; line-height: 2; margin: 0; }
                .scholium-document h1 { text-align: center; }
                .scholium-document h2 { text-align: left; }
                .export-title { text-align: center; font-size: 1em; font-weight: 700; margin: 0; }
                .scholium-document blockquote { margin-inline-start: 36pt; border: 0; padding: 0; }
                """
        case .mla9:
            margin = "72pt"
            styleCSS = """
                .scholium-document { font-family: "Times New Roman", Times, serif; font-size: \(Double(textSize))pt; line-height: 2; text-align: left; hyphens: none; }
                .scholium-document p { margin: 0; text-indent: 36pt; }
                .scholium-document h1, .scholium-document h2 { font-size: 1em; line-height: 2; margin: 0; }
                .scholium-document > h1:first-child { text-align: center; font-weight: 400; }
                .export-title { text-align: center; font-size: 1em; font-weight: 400; margin: 0; }
                .scholium-document blockquote { margin-inline-start: 36pt; border: 0; padding: 0; }
                """
        }
        let pointSize = Double(textSize)
        let bodyPadding = pdfLayout ? "0 \(margin)" : margin
        let frontmatterHTML =
            (includeYAML ? frontmatter : nil).map {
                "<pre class=\"export-frontmatter\" aria-label=\"Authored YAML\" dir=\"auto\">\(escapeHTML($0))</pre>"
            } ?? ""
        let titleHTML =
            body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<h1 ")
            ? "" : "<h1 class=\"export-title\" dir=\"auto\">\(escapedTitle)</h1>"
        return """
            <!doctype html>
            <html><head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; form-action 'none'">
            <title>\(escapedTitle)</title>
            <style>
            @page { size: \(paperSize.cssName); margin: \(margin); }
            html { background: white; color: black; }
            body { box-sizing: border-box; margin: 0 auto; padding: \(bodyPadding); max-width: \(paperSize.pointSize.width)pt; font-size: \(pointSize)pt; overflow-wrap: anywhere; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; break-after: avoid; }
            .export-title { margin: 0 0 1.2em; font-size: 1.65em; }
            p, li, blockquote { orphans: 2; widows: 2; }
            a { color: inherit; text-decoration: underline; }
            pre, code { font-family: ui-monospace, Menlo, monospace; }
            pre { white-space: pre-wrap; overflow-wrap: anywhere; }
            .export-frontmatter, .export-source-fallback { margin-block: 0 1.4em; padding: 0.7em 0.9em; border-inline-start: 1pt solid #888; }
            table { border-collapse: collapse; max-width: 100%; }
            .scholium-embedded-image { display: inline-block; max-width: 100%; height: auto; object-fit: contain; }
            th, td { border: 0.5pt solid #888; padding: 0.25em 0.45em; vertical-align: top; }
            blockquote { margin-inline: 0; padding-inline-start: 1em; border-inline-start: 1pt solid #888; }
            .scholium-media-placeholder { font-style: italic; }
            \(styleCSS)
            @media print { body { max-width: none; padding: 0; } }
            </style>
            </head><body>
            <main class="scholium-document">\(titleHTML)\(frontmatterHTML)\(body)</main>
            </body></html>
            """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func requireLocalImages(
        in document: NoteDocument,
        embeddedImages: [String: RenderedMarkdownImage]
    ) throws {
        for reference in ExportMarkdownImageReferences.references(in: document) {
            switch reference {
            case .local(let file):
                let destination = file.destination.removingPercentEncoding ?? file.destination
                guard embeddedImages[destination] != nil else {
                    throw NoteExportError.missingLocalImage(destination)
                }
            case .remote:
                break
            case .unavailable(let destination):
                throw NoteExportError.missingLocalImage(destination)
            }
        }
    }

    private static func renderPDF(
        html: String, paperSize: NoteExportPaperSize, style: NoteExportStyle
    ) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: paperSize.pointSize),
            configuration: configuration
        )
        let loader = NoteExportPageLoader()
        webView.navigationDelegate = loader
        defer {
            loader.cancel()
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        try await loader.load(html: html, in: webView)
        try Task.checkCancellation()

        // A failed image decode must not silently become a missing figure in PDF.
        guard
            let imagesReady = try await webView.evaluateJavaScript(
                "Array.from(document.images).every(image => image.complete && image.naturalWidth > 0)"
            ) as? Bool, imagesReady
        else {
            throw NoteExportError.invalidPDF
        }

        // createPDF captures a rectangle rather than paginating. Capture each
        // chosen page band separately so searchable text occurs only once.
        guard
            let measured = try await webView.evaluateJavaScript(
                "document.querySelector('main').getBoundingClientRect().bottom + scrollY + 1"
            ) as? NSNumber
        else {
            throw NoteExportError.invalidPDF
        }
        let fullHeight = max(1, CGFloat(truncating: measured))
        guard fullHeight.isFinite, fullHeight > 0 else {
            throw NoteExportError.invalidPDF
        }
        // Range rectangles expose actual WebKit line boxes. Prefer a page
        // boundary after a rendered line or image instead of slicing glyphs.
        let boundaryScript = """
            (() => {
              const main = document.querySelector('main');
              const boxes = [];
              const imageStarts = [];
              const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
              for (let node; (node = walker.nextNode()); ) {
                if (!node.textContent.trim()) continue;
                if (node.parentElement?.closest('h1, h2, h3, h4, h5, h6')) continue;
                const range = document.createRange();
                range.selectNodeContents(node);
                for (const rect of range.getClientRects()) {
                  if (rect.height > 0) boxes.push([rect.top + scrollY, rect.bottom + scrollY]);
                }
              }
              for (const image of main.querySelectorAll('img')) {
                const rect = image.getBoundingClientRect();
                boxes.push([rect.top + scrollY, rect.bottom + scrollY]);
                imageStarts.push(rect.top + scrollY - 3);
              }
              for (const heading of main.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
                imageStarts.push(heading.getBoundingClientRect().top + scrollY - 3);
              }
              const lines = new Map();
              for (const [top, bottom] of boxes) {
                const key = Math.round(top / 2);
                lines.set(key, Math.max(lines.get(key) || 0, bottom));
              }
              return [...lines.values()].map(value => value + 3)
                .concat(imageStarts).sort((a, b) => a - b);
            })()
            """
        let lineBoundaries =
            (try await webView.evaluateJavaScript(boundaryScript) as? [NSNumber])?
            .map { CGFloat(truncating: $0) } ?? []
        let margin: CGFloat = style == .document ? 54 : 72
        let contentHeight = paperSize.pointSize.height - margin * 2
        var captures: [Data] = []
        var start: CGFloat = 0
        while start < fullHeight {
            try Task.checkCancellation()
            let target = min(start + contentHeight, fullHeight)
            let safe = lineBoundaries.last {
                $0 > start + contentHeight * 0.7 && $0 <= target - 4
            }
            let end = safe ?? target
            guard end > start, captures.count < 10_000 else {
                throw NoteExportError.invalidPDF
            }
            let capture = WKPDFConfiguration()
            capture.rect = CGRect(
                x: 0, y: start, width: paperSize.pointSize.width, height: end - start
            )
            captures.append(try await webView.pdf(configuration: capture))
            start = end
        }
        return try paginatePDF(
            captures, paperSize: paperSize.pointSize, style: style
        )
    }

    private static func paginatePDF(
        _ captures: [Data], paperSize: CGSize, style: NoteExportStyle
    ) throws -> Data {
        let margin: CGFloat = style == .document ? 54 : 72
        let pageCount = captures.count
        guard pageCount > 0 else { throw NoteExportError.invalidPDF }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw NoteExportError.invalidPDF
        }
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NoteExportError.invalidPDF
        }
        for (index, data) in captures.enumerated() {
            guard !data.isEmpty,
                let provider = CGDataProvider(data: data as CFData),
                let source = CGPDFDocument(provider),
                source.numberOfPages == 1,
                let page = source.page(at: 1)
            else { throw NoteExportError.invalidPDF }
            let bounds = page.getBoxRect(.mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite,
                bounds.width > 0, bounds.height > 0,
                bounds.height <= paperSize.height - margin * 2 + 1
            else { throw NoteExportError.invalidPDF }
            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: 0, y: mediaBox.height - margin - bounds.height,
                    width: mediaBox.width, height: bounds.height
                ))
            context.translateBy(
                x: -bounds.minX,
                y: mediaBox.height - margin - bounds.maxY
            )
            context.drawPDFPage(page)
            context.restoreGState()
            let number = NSAttributedString(
                string: String(index + 1),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.black,
                ]
            )
            let line = CTLineCreateWithAttributedString(number)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            context.textPosition = CGPoint(
                x: mediaBox.width - margin - width,
                y: style == .document ? 24 : mediaBox.height - 42
            )
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()

        let result = output as Data
        guard !result.isEmpty,
            let check = PDFDocument(data: result),
            check.pageCount == pageCount
        else {
            throw NoteExportError.invalidPDF
        }
        // Core Graphics draws page content but never carries PDF annotations.
        // Apply the same page translation to each captured link rectangle so
        // the final PDF retains working links at the visible text positions.
        for (index, data) in captures.enumerated() {
            guard let source = PDFDocument(data: data),
                let sourcePage = source.page(at: 0),
                let outputPage = check.page(at: index)
            else { throw NoteExportError.invalidPDF }
            let bounds = sourcePage.bounds(for: .mediaBox)
            let transform = CGAffineTransform(
                translationX: -bounds.minX,
                y: paperSize.height - margin - bounds.maxY
            )
            for annotation in sourcePage.annotations {
                guard
                    annotation.type == "Link"
                        || annotation.type == PDFAnnotationSubtype.link.rawValue
                else { continue }
                let action: PDFAction
                if let url = (annotation.action as? PDFActionURL)?.url {
                    action = PDFActionURL(url: url)
                } else if let goTo = annotation.action as? PDFActionGoTo,
                    goTo.destination.page === sourcePage
                {
                    let point = goTo.destination.point
                    let destination = PDFDestination(
                        page: outputPage, at: point.applying(transform)
                    )
                    destination.zoom = goTo.destination.zoom
                    action = PDFActionGoTo(destination: destination)
                } else {
                    continue
                }
                let translated = PDFAnnotation(
                    bounds: annotation.bounds.applying(transform),
                    forType: .link,
                    withProperties: nil
                )
                translated.action = action
                outputPage.addAnnotation(translated)
            }
        }
        guard let annotated = check.dataRepresentation(), !annotated.isEmpty else {
            throw NoteExportError.invalidPDF
        }
        return annotated
    }
}

@MainActor
private final class NoteExportPageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(html: String, in webView: WKWebView) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.timeoutTask = Task { @MainActor [weak self, weak webView] in
                    do {
                        try await Task.sleep(for: .seconds(10))
                        webView?.stopLoading()
                        self?.finish(.failure(NoteExportError.pageLoadTimedOut))
                    } catch {
                        // Completion and cancellation both stop the timer.
                    }
                }
                webView.loadHTMLString(html, baseURL: nil)
            }
        } onCancel: {
            Task { @MainActor [weak self, weak webView] in
                webView?.stopLoading()
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(NoteExportError.invalidPDF))
    }
}
