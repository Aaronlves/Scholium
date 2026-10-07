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

enum NoteExportError: LocalizedError {
    case invalidTextSize
    case invalidSource
    case emptyOutput
    case invalidPDF
    case pageLoadTimedOut
    case missingLocalImage(String)
    case docxPackaging
    case citationStateStale
    case citationSourceUnresolved

    var errorDescription: String? {
        switch self {
        case .invalidTextSize: ScholiumL10n.string("The export text size is invalid.")
        case .invalidSource: ScholiumL10n.string("The Note source could not be decoded for export.")
        case .emptyOutput: ScholiumL10n.string("The export produced no document data.")
        case .invalidPDF: ScholiumL10n.string("PDF export could not preserve the complete note.")
        case .pageLoadTimedOut: ScholiumL10n.string("The export page did not finish loading.")
        case .missingLocalImage(let destination):
            ScholiumL10n.string("The image at \(destination) could not be included in the export.")
        case .docxPackaging:
            ScholiumL10n.string("The Word document could not be prepared for export.")
        case .citationStateStale:
            ScholiumL10n.string("The citations changed. Refresh Citations or choose Export Saved Text.")
        case .citationSourceUnresolved:
            ScholiumL10n.string("The citation source is unresolved. Repair it or choose Export Saved Text.")
        }
    }
}

/// Renders one supplied NoteDocument snapshot without reading or changing its source file.
@MainActor
struct NoteExportService {
    /// Offline export knows only source integrity, never a live library's freshness.
    static func citationExportIssue(in document: NoteDocument) -> NoteExportError? {
        let fields = MarkdownSemanticDocument(parsing: document).zoteroFields
        if !fields.canMutate { return .citationSourceUnresolved }
        if fields.citationStateStale { return .citationStateStale }
        return nil
    }

    static func requireCitationExportAdmission(in document: NoteDocument, allowSavedCitationText: Bool = false) throws {
        try Task.checkCancellation()
        if !allowSavedCitationText, let issue = citationExportIssue(in: document) { throw issue }
    }

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
        embeddedImages: [String: RenderedMarkdownImage] = [:],
        allowSavedCitationText: Bool = false
    ) async throws -> Data {
        try requireCitationExportAdmission(in: document, allowSavedCitationText: allowSavedCitationText)
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
        embeddedImages: [String: RenderedMarkdownImage] = [:],
        allowSavedCitationText: Bool = false
    ) async throws -> Data {
        try requireCitationExportAdmission(in: document, allowSavedCitationText: allowSavedCitationText)
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
            let wordContent = prepareWordContent(html: html, document: document)
            let paragraphMarker = "\u{E000}\(UUID().uuidString)\u{E001}"
            let styledHTML = style == .document ? wordContent.html : markBodyParagraphs(in: wordContent.html, with: paragraphMarker)
            let wordHTML = styledHTML
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
            let wordLinks = markWordLinks(in: attributed)
            let nativeDOCX = try wordLinks.content.data(
                from: NSRange(location: 0, length: wordLinks.content.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
            output = try await addWordFootnotes(
                wordContent.footnotes, to: nativeDOCX, markers: wordContent.markers,
                links: wordLinks.links, headings: wordContent.headings,
                bibliographies: wordContent.bibliographies)
        }
        guard !output.isEmpty else { throw NoteExportError.emptyOutput }
        if format == .docx, !output.starts(with: [0x50, 0x4B]) {
            throw NoteExportError.emptyOutput
        }
        return output
    }

    static func prepareWordContent(
        html: String, document: NoteDocument
    ) -> (
        html: String, footnotes: [(Int, NSAttributedString)], markers: [String: Int], headings: [String: Int],
        bibliographies: [String: ZoteroMarkdownBibliographyStyle]
    ) {
        var headings: [String: Int] = [:]
        var prepared = replacingRegex(#"<h([1-6])\b[^>]*>"#, in: html) { match, source in
            let marker = "SCHOLIUMHEADING\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))END"
            headings[marker] = Int(source.substring(with: match.range(at: 1)))
            return source.substring(with: match.range) + marker
        }
        let semantic = MarkdownSemanticDocument(parsing: document)
        var bibliographies: [String: ZoteroMarkdownBibliographyStyle] = [:]
        if let layout = semantic.zoteroFields.documentState?.bibliographyStyle {
            prepared = replacingRegex(#"<section class="scholium-zotero-bibliography"[^>]*>[\s\S]*?</section>"#, in: prepared) { match, source in
                replacingRegex(#"<p\b[^>]*>"#, in: source.substring(with: match.range)) { entry, section in
                    let marker = "SCHOLIUMBIBLIOGRAPHY\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))END"
                    bibliographies[marker] = layout
                    return section.substring(with: entry.range) + marker
                }
            }
        }
        let referenced = Set(semantic.footnoteReferences.map(\.ordinal))
        let footnotes = semantic.footnoteDefinitions.compactMap { definition -> (Int, NSAttributedString)? in
            guard let ordinal = definition.ordinal, referenced.contains(ordinal) else { return nil }
            let note = NoteDocument(relativePath: "word-footnote.md", rawContent: definition.content)
            let rendered = SafeMarkdownRenderer.render(note).htmlBody
            let source = "<html><body>\(rendered)</body></html>"
            let content =
                (try? NSAttributedString(
                    data: Data(source.utf8),
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue,
                    ],
                    documentAttributes: nil
                )) ?? NSAttributedString(string: definition.content)
            return (ordinal, content)
        }
        guard !footnotes.isEmpty else { return (prepared, [], [:], headings, bibliographies) }
        let ids = Set(footnotes.map(\.0))
        var markers: [String: Int] = [:]
        for ordinal in ids.sorted() {
            let marker = "SCHOLIUMFOOTNOTE\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))END"
            let pattern = #"<button[^>]*class="footnote-reference"[^>]*data-footnote="\#(ordinal)"[^>]*>[^<]*</button>"#
            prepared = replacingRegex(pattern, in: prepared) { _, _ in
                markers[marker] = ordinal
                return marker
            }
        }
        prepared = replacingRegex(#"<section class="footnotes"[\s\S]*?</section>"#, in: prepared) { _, _ in "" }
        return (prepared, footnotes, markers, headings, bibliographies)
    }

    private static func addWordFootnotes(
        _ footnotes: [(Int, NSAttributedString)], to data: Data, markers: [String: Int], links: [WordLink], headings: [String: Int],
        bibliographies: [String: ZoteroMarkdownBibliographyStyle]
    ) async throws -> Data {
        do {
            var package = try await WorkspaceStore.unpackWordDocument(data)
            let documentXML = try wordPart("word/document.xml", in: package)
            var relationships = try wordPart("word/_rels/document.xml.rels", in: package)
            let preparedXML = try replacingWordMarkers(
                in: documentXML, footnotes: markers, links: links, headings: headings,
                bibliographies: bibliographies)
            package["word/document.xml"] = Data(preparedXML.utf8)
            for link in links {
                relationships = relationships.replacingOccurrences(
                    of: "</Relationships>", with: wordLinkRelationship(id: link.id, target: link.target) + "</Relationships>")
            }
            if !footnotes.isEmpty {
                relationships = relationships.replacingOccurrences(
                    of: "</Relationships>",
                    with:
                        "<Relationship Id=\"rIdScholiumFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/></Relationships>"
                )
            }
            try addWordStyles(to: &package, headingLevels: Set(headings.values), hasFootnotes: !footnotes.isEmpty, relationships: &relationships)
            package["word/_rels/document.xml.rels"] = Data(relationships.utf8)
            if !footnotes.isEmpty {
                var types = try wordPart("[Content_Types].xml", in: package)
                types = types.replacingOccurrences(
                    of: "</Types>",
                    with:
                        "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/></Types>"
                )
                package["[Content_Types].xml"] = Data(types.utf8)
            }
            var footnoteParts: [String] = []
            var footnoteRelationships =
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>"
            var footnoteLinkIndex = 0
            for (id, content) in footnotes.sorted(by: { $0.0 < $1.0 }) {
                let runs = wordRuns(for: content, relationships: &footnoteRelationships, linkIndex: &footnoteLinkIndex)
                footnoteParts.append(
                    "<w:footnote w:id=\"\(id)\"><w:p><w:pPr><w:pStyle w:val=\"FootnoteText\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteRef/></w:r>\(runs)</w:p></w:footnote>"
                )
            }
            let body = footnoteParts.joined()
            let footnoteXML =
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:footnotes xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>\(body)</w:footnotes>"
            if !footnotes.isEmpty {
                package["word/footnotes.xml"] = Data(footnoteXML.utf8)
                if footnoteLinkIndex > 0 {
                    package["word/_rels/footnotes.xml.rels"] = Data(footnoteRelationships.utf8)
                }
            }
            return try await WorkspaceStore.packWordDocument(package)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw NoteExportError.docxPackaging
        }
    }

    private static func wordPart(_ path: String, in package: [String: Data]) throws -> String {
        guard let data = package[path], let text = String(data: data, encoding: .utf8) else { throw NoteExportError.docxPackaging }
        return text
    }

    struct WordLink {
        let id: String
        let target: String
        let start: String
        let end: String
    }

    /// Mark source ranges, rather than searching exported prose for equal labels.
    /// This keeps repeated labels and links spanning several formatting runs distinct.
    private static func markWordLinks(in content: NSAttributedString) -> (content: NSAttributedString, links: [WordLink]) {
        var ranges: [(NSRange, WordLink)] = []
        content.enumerateAttribute(.link, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            guard let target = (value as? URL)?.absoluteString ?? (value as? String) else { return }
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            ranges.append(
                (
                    range,
                    WordLink(
                        id: "rIdScholiumHyperlink\(ranges.count + 1)", target: target,
                        start: "SCHOLIUMLINK\(token)START", end: "SCHOLIUMLINK\(token)END")
                ))
        }
        let marked = NSMutableAttributedString(attributedString: content)
        marked.removeAttribute(.link, range: NSRange(location: 0, length: marked.length))
        for (range, link) in ranges.reversed() {
            let attributes = marked.attributes(at: range.location, effectiveRange: nil)
            marked.insert(NSAttributedString(string: link.end, attributes: attributes), at: NSMaxRange(range))
            marked.insert(NSAttributedString(string: link.start, attributes: attributes), at: range.location)
        }
        return (marked, ranges.map(\.1))
    }

    static func replacingWordMarkers(
        in xml: String, footnotes: [String: Int], links: [WordLink], headings: [String: Int],
        bibliographies: [String: ZoteroMarkdownBibliographyStyle]
    ) throws -> String {
        let document = try XMLDocument(xmlString: xml, options: .nodePreserveWhitespace)
        try normalizeNativeWordProperties(in: document)
        let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        if document.rootElement()?.namespace(forPrefix: "r") == nil {
            document.rootElement()?.addNamespace(XMLNode.namespace(withName: "r", stringValue: relationshipNamespace) as! XMLNode)
        }
        let starts = Dictionary(uniqueKeysWithValues: links.map { ($0.start, $0.id) })
        let ends = Dictionary(uniqueKeysWithValues: links.map { ($0.end, $0.id) })
        let tokens = Array(footnotes.keys) + Array(starts.keys) + Array(ends.keys) + Array(headings.keys) + Array(bibliographies.keys)
        guard !tokens.isEmpty else { return document.xmlString }
        let pattern = tokens.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let regex = try NSRegularExpression(pattern: pattern)
        var startNodes: [String: XMLElement] = [:]
        var endNodes: [String: XMLElement] = [:]
        var bibliographyMarkers = Set<String>()
        var referencedFootnotes = Set<Int>()
        var footnoteDisplayNumbers: [Int: Int] = [:]
        let existingBookmarks = try document.nodes(forXPath: "//*[local-name()='bookmarkStart']").compactMap { $0 as? XMLElement }
        var bookmarkID = (existingBookmarks.compactMap { Int($0.attribute(forName: "w:id")?.stringValue ?? "") }.max() ?? 0) + 1
        var bookmarkNames = Set(existingBookmarks.compactMap { $0.attribute(forName: "w:name")?.stringValue })
        var footnoteBookmarks: [Int: String] = [:]
        for id in Set(footnotes.values).sorted() {
            var name = "ScholiumFootnote\(id)"
            while bookmarkNames.contains(name) { name += "_" }
            bookmarkNames.insert(name)
            footnoteBookmarks[id] = name
        }
        for node in try document.nodes(forXPath: "//*[local-name()='t']") {
            guard let text = node as? XMLElement, let value = text.stringValue else { continue }
            let nsValue = value as NSString
            let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
            guard !matches.isEmpty else { continue }
            guard let run = text.parent as? XMLElement, run.localName == "r",
                let parent = run.parent as? XMLElement,
                let runIndex = parent.children?.firstIndex(where: { $0 === run }),
                run.elements(forName: "w:t").count == 1
            else { throw NoteExportError.docxPackaging }
            var replacements: [XMLNode] = []
            func appendText(_ range: NSRange) {
                guard range.length > 0 else { return }
                let fragment = run.copy() as! XMLElement
                fragment.elements(forName: "w:t").first?.stringValue = nsValue.substring(with: range)
                fragment.elements(forName: "w:t").first?.addAttribute(XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as! XMLNode)
                replacements.append(fragment)
            }
            var offset = 0
            for match in matches {
                appendText(NSRange(location: offset, length: match.range.location - offset))
                let token = nsValue.substring(with: match.range)
                if let id = footnotes[token] {
                    let referenceRun = XMLElement(name: "w:r")
                    let properties = XMLElement(name: "w:rPr")
                    let style = XMLElement(name: "w:rStyle")
                    style.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "FootnoteReference") as! XMLNode)
                    properties.addChild(style)
                    referenceRun.addChild(properties)
                    let name = footnoteBookmarks[id]!
                    if referencedFootnotes.insert(id).inserted {
                        footnoteDisplayNumbers[id] = referencedFootnotes.count
                        let start = XMLElement(name: "w:bookmarkStart")
                        start.addAttribute(XMLNode.attribute(withName: "w:id", stringValue: String(bookmarkID)) as! XMLNode)
                        start.addAttribute(XMLNode.attribute(withName: "w:name", stringValue: name) as! XMLNode)
                        let reference = XMLElement(name: "w:footnoteReference")
                        reference.addAttribute(XMLNode.attribute(withName: "w:id", stringValue: String(id)) as! XMLNode)
                        referenceRun.addChild(reference)
                        let end = XMLElement(name: "w:bookmarkEnd")
                        end.addAttribute(XMLNode.attribute(withName: "w:id", stringValue: String(bookmarkID)) as! XMLNode)
                        bookmarkID += 1
                        replacements.append(contentsOf: [start, referenceRun, end])
                    } else {
                        // Word requires one owning reference per footnote. Later
                        // mentions use its editable, renumberable cross reference.
                        let field = XMLElement(name: "w:fldSimple")
                        field.addAttribute(XMLNode.attribute(withName: "w:instr", stringValue: " NOTEREF \(name) \\h ") as! XMLNode)
                        let number = XMLElement(name: "w:t", stringValue: String(footnoteDisplayNumbers[id]!))
                        referenceRun.addChild(number)
                        field.addChild(referenceRun)
                        replacements.append(field)
                    }
                } else if let id = starts[token] {
                    let marker = XMLElement(name: "scholiumLinkStart")
                    startNodes[id] = marker
                    replacements.append(marker)
                } else if let id = ends[token] {
                    let marker = XMLElement(name: "scholiumLinkEnd")
                    endNodes[id] = marker
                    replacements.append(marker)
                } else if let level = headings[token] {
                    var ancestor: XMLNode? = parent
                    while ancestor != nil, ancestor?.localName != "p" { ancestor = ancestor?.parent }
                    guard let paragraph = ancestor as? XMLElement else { throw NoteExportError.docxPackaging }
                    let properties = paragraph.elements(forName: "w:pPr").first ?? XMLElement(name: "w:pPr")
                    if properties.parent == nil { paragraph.insertChild(properties, at: 0) }
                    let style = XMLElement(name: "w:pStyle")
                    style.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: "Heading\(level)") as! XMLNode)
                    properties.insertChild(style, at: 0)
                    let outline = XMLElement(name: "w:outlineLvl")
                    outline.addAttribute(XMLNode.attribute(withName: "w:val", stringValue: String(level - 1)) as! XMLNode)
                    properties.addChild(outline)
                } else if let layout = bibliographies[token] {
                    guard bibliographyMarkers.insert(token).inserted else { throw NoteExportError.docxPackaging }
                    var ancestor: XMLNode? = parent
                    while ancestor != nil, ancestor?.localName != "p" { ancestor = ancestor?.parent }
                    guard let paragraph = ancestor as? XMLElement else { throw NoteExportError.docxPackaging }
                    applyWordBibliographyLayout(layout, to: paragraph)
                }
                offset = NSMaxRange(match.range)
            }
            appendText(NSRange(location: offset, length: nsValue.length - offset))
            run.detach()
            for (index, replacement) in replacements.enumerated() { parent.insertChild(replacement, at: runIndex + index) }
        }
        for link in links {
            guard let start = startNodes[link.id], let end = endNodes[link.id],
                let parent = start.parent as? XMLElement, end.parent === parent,
                let children = parent.children,
                let first = children.firstIndex(where: { $0 === start }),
                let last = children.firstIndex(where: { $0 === end }), first < last
            else { throw NoteExportError.docxPackaging }
            let hyperlink = XMLElement(name: "w:hyperlink")
            hyperlink.addAttribute(XMLNode.attribute(withName: "r:id", stringValue: link.id) as! XMLNode)
            for child in children[(first + 1)..<last] {
                child.detach()
                hyperlink.addChild(child)
            }
            start.detach()
            end.detach()
            parent.insertChild(hyperlink, at: first)
        }
        let remainingText = document.rootElement()?.stringValue ?? ""
        guard bibliographyMarkers == Set(bibliographies.keys),
            !tokens.contains(where: { remainingText.contains($0) })
        else { throw NoteExportError.docxPackaging }
        return document.xmlString
    }

    /// The source callback owns bibliography layout. Apply it after AppKit and
    /// page presets, which otherwise lose HTML indentation and line multiples.
    private static func applyWordBibliographyLayout(_ layout: ZoteroMarkdownBibliographyStyle, to paragraph: XMLElement) {
        let properties = paragraph.elements(forName: "w:pPr").first ?? XMLElement(name: "w:pPr")
        if properties.parent == nil { paragraph.insertChild(properties, at: 0) }
        for child in properties.children ?? [] where ["tabs", "spacing", "ind"].contains(child.localName ?? "") { child.detach() }
        func value(_ number: Double) -> String { String(Int(number.rounded())) }
        func attribute(_ name: String, _ content: String, on element: XMLElement) {
            element.addAttribute(XMLNode.attribute(withName: "w:\(name)", stringValue: content) as! XMLNode)
        }
        var additions: [XMLElement] = []
        if !layout.tabStops.isEmpty {
            let tabs = XMLElement(name: "w:tabs")
            for stop in layout.tabStops {
                let tab = XMLElement(name: "w:tab")
                attribute("val", "left", on: tab)
                attribute("pos", value(stop), on: tab)
                tabs.addChild(tab)
            }
            additions.append(tabs)
        }
        let spacing = XMLElement(name: "w:spacing")
        attribute("before", "0", on: spacing)
        attribute("after", value(layout.entrySpacing), on: spacing)
        attribute("line", value(layout.lineSpacing), on: spacing)
        attribute("lineRule", "auto", on: spacing)
        additions.append(spacing)
        let indentation = XMLElement(name: "w:ind")
        attribute("left", value(layout.indent), on: indentation)
        attribute(layout.firstLineIndent < 0 ? "hanging" : "firstLine", value(abs(layout.firstLineIndent)), on: indentation)
        additions.append(indentation)
        // Keep the paragraph-property schema order without reordering unrelated
        // paragraph settings produced by the native writer.
        let afterIndent: Set<String> = [
            "contextualSpacing", "mirrorIndents", "suppressOverlap", "jc", "textDirection", "textAlignment",
            "textboxTightWrap", "outlineLvl", "divId", "cnfStyle", "rPr", "sectPr", "pPrChange",
        ]
        let afterTabs = afterIndent.union([
            "suppressAutoHyphens", "kinsoku", "wordWrap", "overflowPunct", "topLinePunct", "autoSpaceDE",
            "autoSpaceDN", "bidi", "adjustRightInd", "snapToGrid", "spacing", "ind",
        ])
        for addition in additions {
            let following = addition.localName == "tabs" ? afterTabs : afterIndent.union(["ind"])
            let index = properties.children?.firstIndex { following.contains($0.localName ?? "") } ?? properties.childCount
            properties.insertChild(addition, at: index)
        }
    }

    /// AppKit writes obsolete complex-script size and first-line indent names,
    /// plus unordered run properties. Preserve values in the OOXML schema.
    private static func normalizeNativeWordProperties(in document: XMLDocument) throws {
        let namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        guard document.rootElement()?.namespace(forPrefix: "w")?.stringValue == namespace else { throw NoteExportError.docxPackaging }
        for node in try document.nodes(forXPath: "//*[local-name()='sz-cs']") where node.name == "w:sz-cs" {
            node.name = "w:szCs"
        }
        for node in try document.nodes(forXPath: "//*[local-name()='ind']") where node.name == "w:ind" {
            guard let indentation = node as? XMLElement, let native = indentation.attribute(forName: "w:first-line") else { continue }
            guard indentation.attribute(forName: "w:firstLine") == nil else { throw NoteExportError.docxPackaging }
            native.name = "w:firstLine"
        }
        let order = [
            "rStyle", "rFonts", "b", "bCs", "i", "iCs", "caps", "smallCaps", "strike", "dstrike", "outline", "shadow", "emboss", "imprint",
            "noProof", "snapToGrid", "vanish", "webHidden", "color", "spacing", "w", "kern", "position", "sz", "szCs", "highlight", "u", "effect",
            "bdr", "shd", "fitText", "vertAlign", "rtl", "cs", "em", "lang", "eastAsianLayout", "specVanish", "oMath", "rPrChange",
        ]
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        for node in try document.nodes(forXPath: "//*[local-name()='rPr']") where node.name == "w:rPr" {
            guard let properties = node as? XMLElement, let children = properties.children else { continue }
            let sorted = children.enumerated().sorted {
                let lhs = ranks[$0.element.localName ?? ""] ?? Int.max
                let rhs = ranks[$1.element.localName ?? ""] ?? Int.max
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }.map(\.element)
            for child in children { child.detach() }
            for child in sorted { properties.addChild(child) }
        }
    }

    private static func wordLinkRelationship(id: String, target: String) -> String {
        "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xmlEscape(target))\" TargetMode=\"External\"/>"
    }

    private static func addWordStyles(to package: inout [String: Data], headingLevels: Set<Int>, hasFootnotes: Bool, relationships: inout String) throws {
        guard !headingLevels.isEmpty || hasFootnotes else { return }
        let existing = package["word/styles.xml"]
        let styles =
            existing != nil
            ? try XMLDocument(data: existing!, options: .nodePreserveWhitespace)
            : try XMLDocument(xmlString: "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"/>")
        guard let root = styles.rootElement() else { throw NoteExportError.docxPackaging }
        var additions: [(String, String)] = headingLevels.sorted().map { level in
            (
                "Heading\(level)",
                "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>"
            )
        }
        if hasFootnotes {
            additions += [
                (
                    "FootnoteText",
                    "<w:style w:type=\"paragraph\" w:styleId=\"FootnoteText\"><w:name w:val=\"footnote text\"/><w:rPr><w:sz w:val=\"20\"/></w:rPr></w:style>"
                ),
                (
                    "FootnoteReference",
                    "<w:style w:type=\"character\" w:styleId=\"FootnoteReference\"><w:name w:val=\"footnote reference\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"
                ),
            ]
        }
        for (id, fragment) in additions where !root.elements(forName: "w:style").contains(where: { $0.attribute(forName: "w:styleId")?.stringValue == id }) {
            let wrapper = try XMLDocument(
                xmlString: "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(fragment)</w:styles>")
            if let style = wrapper.rootElement()?.children?.first { root.addChild(style.copy() as! XMLNode) }
        }
        package["word/styles.xml"] = styles.xmlData
        if existing == nil {
            relationships = relationships.replacingOccurrences(
                of: "</Relationships>",
                with:
                    "<Relationship Id=\"rIdScholiumStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
            )
            let types = try wordPart("[Content_Types].xml", in: package).replacingOccurrences(
                of: "</Types>",
                with:
                    "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"
            )
            package["[Content_Types].xml"] = Data(types.utf8)
        }
    }

    private static func wordRuns(for content: NSAttributedString, relationships: inout String, linkIndex: inout Int) -> String {
        var result = ""
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length)) { attributes, range, _ in
            let text = (content.string as NSString).substring(with: range)
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var properties = ""
            if traits.contains(.bold) { properties += "<w:b/>" }
            if traits.contains(.italic) { properties += "<w:i/>" }
            let runProperties = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
            let pieces = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var runs: [String] = []
            for (index, piece) in pieces.enumerated() {
                if !piece.isEmpty {
                    runs.append("<w:r>\(runProperties)<w:t xml:space=\"preserve\">\(xmlEscape(piece))</w:t></w:r>")
                }
                if index < pieces.count - 1 { runs.append("<w:r><w:br/></w:r>") }
            }
            var fragment = runs.joined()
            if let value = attributes[.link] {
                let target = (value as? URL)?.absoluteString ?? (value as? String)
                if let target {
                    linkIndex += 1
                    let relationID = "rIdScholiumFootnoteHyperlink\(linkIndex)"
                    relationships = relationships.replacingOccurrences(
                        of: "</Relationships>",
                        with: wordLinkRelationship(id: relationID, target: target) + "</Relationships>")
                    fragment = "<w:hyperlink r:id=\"\(relationID)\" w:history=\"1\">\(fragment)</w:hyperlink>"
                }
            }
            result += fragment
        }
        return result
    }

    private static func replacingRegex(
        _ pattern: String, in source: String, replacement: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        var result = source
        for match in matches.reversed() {
            let value = replacement(match, nsSource)
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: value) }
        }
        return result
    }

    private static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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

    static func markBodyParagraphs(in html: String, with marker: String) -> String {
        let tags = try! NSRegularExpression(pattern: "</?([A-Za-z][A-Za-z0-9-]*)\\b[^>]*>")
        let source = html as NSString
        let excludedContainers: Set<String> = ["li", "blockquote", "td", "th"]
        var insideMain = false
        var bibliographySections: [Bool] = []
        var excludedDepth = 0
        var cursor = 0
        var marked = ""
        for match in tags.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let end = NSMaxRange(match.range)
            marked += source.substring(with: NSRange(location: cursor, length: end - cursor))
            let tag = source.substring(with: match.range(at: 1)).lowercased()
            let closing = source.substring(with: match.range).hasPrefix("</")
            if tag == "main" { insideMain = !closing }
            if tag == "section" {
                if closing {
                    _ = bibliographySections.popLast()
                } else {
                    bibliographySections.append(
                        bibliographySections.last == true || source.substring(with: match.range).contains("class=\"scholium-zotero-bibliography\""))
                }
            }
            if excludedContainers.contains(tag) {
                excludedDepth += closing ? -1 : 1
            }
            if tag == "p", !closing, insideMain, excludedDepth == 0, bibliographySections.last != true {
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
            .scholium-document .scholium-zotero-bibliography p { text-indent: 0; }
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

    // WebKit lays out and captures CSS pixels (96/inch); PDF uses points (72/inch).
    private static let pdfPointsPerCSSPixel: CGFloat = 72.0 / 96.0

    private static func renderPDF(
        html: String, paperSize: NoteExportPaperSize, style: NoteExportStyle
    ) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let cssPaperSize = CGSize(
            width: paperSize.pointSize.width / pdfPointsPerCSSPixel,
            height: paperSize.pointSize.height / pdfPointsPerCSSPixel
        )
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: cssPaperSize),
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
        let contentHeight = (paperSize.pointSize.height - margin * 2) / pdfPointsPerCSSPixel
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
                x: 0, y: start, width: cssPaperSize.width, height: end - start
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
                bounds.height * pdfPointsPerCSSPixel <= paperSize.height - margin * 2 + 1
            else { throw NoteExportError.invalidPDF }
            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: 0, y: mediaBox.height - margin - bounds.height * pdfPointsPerCSSPixel,
                    width: mediaBox.width, height: bounds.height * pdfPointsPerCSSPixel
                ))
            context.translateBy(
                x: -bounds.minX * pdfPointsPerCSSPixel,
                y: mediaBox.height - margin - bounds.maxY * pdfPointsPerCSSPixel
            )
            context.scaleBy(x: pdfPointsPerCSSPixel, y: pdfPointsPerCSSPixel)
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
        // Apply the same scaling and translation to each captured link rectangle so
        // the final PDF retains working links at the visible text positions.
        for (index, data) in captures.enumerated() {
            guard let source = PDFDocument(data: data),
                let sourcePage = source.page(at: 0),
                let outputPage = check.page(at: index)
            else { throw NoteExportError.invalidPDF }
            let bounds = sourcePage.bounds(for: .mediaBox)
            let transform = CGAffineTransform(
                a: pdfPointsPerCSSPixel, b: 0, c: 0, d: pdfPointsPerCSSPixel,
                tx: -bounds.minX * pdfPointsPerCSSPixel,
                ty: paperSize.height - margin - bounds.maxY * pdfPointsPerCSSPixel
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
