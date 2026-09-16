import AppKit
import ScholiumContracts
import SwiftUI

/// Ranges identify table and code content in the object-copy projection.
struct AgentChatRichSegment: Identifiable {
    let id: Int
    var range: NSRange
    var columns: Int = 0
    var code: String?
    var language: String?
    var isObject: Bool { columns > 0 || code != nil }

    static func collect(_ layout: AgentChatObjectProjection.Layout) -> [Self] {
        var segments: [Self] = []
        for item in layout.blocks {
            var segment = Self(id: item.block.id, range: item.range)
            switch item.block.kind {
            case .tableRow: segment.columns = item.block.cells.count
            case .code:
                segment.code = String(item.block.text.characters)
                segment.language = item.block.language
            default: break
            }
            if let last = segments.last,
                !last.isObject && !segment.isObject || last.columns > 0 && segment.columns > 0
            {
                segments[segments.count - 1].range = NSUnionRange(last.range, segment.range)
                segments[segments.count - 1].columns = max(last.columns, segment.columns)
            } else {
                segments.append(segment)
            }
        }
        return segments
    }
}

/// Expanded content fills the shared preview's viewport; source remains immutable.
struct AgentChatRichContent: View {
    let text: NSAttributedString
    let diagramSource: String?
    let naturalSize: CGSize
    let openLink: (URL) -> Void

    var body: some View {
        if let diagramSource {
            AgentChatDiagram(source: "```mermaid\n" + diagramSource + "\n```")
        } else {
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    AgentChatObjectText(text: text, openLink: openLink)
                        .frame(width: max(viewport.size.width, naturalSize.width), alignment: .topLeading)
                }.defaultScrollAnchor(.topLeading)
            }
        }
    }
}

struct AgentChatObjectText: NSViewRepresentable {
    let text: NSAttributedString
    let openLink: (URL) -> Void
    func makeNSView(context: Context) -> AgentChatObjectTextView { AgentChatObjectTextView() }
    func updateNSView(_ view: AgentChatObjectTextView, context: Context) {
        view.openLink = openLink
        if !view.attributedString().isEqual(to: text) { view.textStorage?.setAttributedString(text) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatObjectTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measuredHeight(width: width))
    }
    static func dismantleNSView(_ view: AgentChatObjectTextView, coordinator: ()) {
        view.openLink = nil
    }
}

/// Reuses the document reader's inert HTML, local Mermaid runtime and navigation guard.
struct AgentChatDiagram: View {
    let source: String
    var onSize: ((CGSize) -> Void)? = nil
    @State private var failure: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var projection: Projection?
    @State private var ready = false
    private struct Projection {
        let document: NoteDocument
        let html: String
        init(_ source: String) {
            document = NoteDocument(relativePath: "Chat.md", rawContent: source)
            html = SafeMarkdownRenderer.render(document).htmlBody
        }
    }
    var body: some View {
        Group {
            if let failure {
                VStack(alignment: .leading) {
                    Text(verbatim: failure).foregroundStyle(.secondary)
                    Text(verbatim: source).textSelection(.enabled)
                    Button("Retry") { self.failure = nil }
                }
            } else if let projection {
                SafeMarkdownReadWebView(
                    documentID: "chat-diagram", fingerprint: projection.document.fingerprint.sha256,
                    source: source, htmlBody: projection.html,
                    presentationCSS: Self.previewCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased),
                    userCSS: "", onLinkClick: { _ in }, onOpenExternalURL: { _ in }, selectionSurfaceIsActive: false,
                    renderingReadinessIsAcknowledged: ready,
                    onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
                    onRenderingReady: { ready = true }, onRenderedDiagramSize: onSize)
            } else {
                ProgressView("Loading…")
            }
        }
        .task(id: source) {
            failure = nil
            ready = false
            projection = Projection(source)
        }
    }
    static func previewCSS(dark: Bool, increasedContrast: Bool) -> String {
        presentationCSS(dark: dark, increasedContrast: increasedContrast)
            + ScholiumPreviewStyles.diagramColorCSS(dark: dark, increasedContrast: increasedContrast) + """
            :root {
                --scholium-document-body-font-family: system-ui;
                font-size: \(NSFont.systemFontSize)px;
                --scholium-diagram-inline-size: 100%;
                --scholium-diagram-block-size: 100%;
                --scholium-diagram-max-block-size: 100%;
            }
            html, body { height: 100%; overflow: hidden; }
            .scholium-document { height: 100%; box-sizing: border-box; padding: 0; font: 1rem/1.45 system-ui; }
            .scholium-mermaid-rendered { height: 100%; display: flex; align-items: center; justify-content: center; }
            .scholium-mermaid-output { width: 100%; height: 100%; }
            .scholium-mermaid:not(.scholium-mermaid-rendered) { max-height: 100%; overflow: auto; }
            .scholium-document .scholium-mermaid-source {
                font: 1rem/1.45 ui-monospace, monospace;
                color: var(--scholium-color-primary-text);
                background: var(--scholium-color-document-background);
            }
            .scholium-document .scholium-mermaid-source code { font: inherit; color: inherit; background: transparent; }
            .scholium-mermaid-diagnostic { font: inherit; }
            """
    }
    static func presentationCSS(dark: Bool, increasedContrast: Bool) -> String {
        let colors: [(String, ScholiumColorRole)] = [
            ("document-background", .documentBackground), ("surface-background", .surfaceBackground),
            ("raised-surface-background", .raisedSurfaceBackground),
            ("primary-text", .primaryText), ("secondary-text", .secondaryText),
            ("separator", .separator), ("accent", .accent), ("attention", .attention),
        ]
        let declarations = colors.map { key, role in
            return String(
                format: "--scholium-color-%@: #%06x;", key,
                role.resolvedRGBValue(isDark: dark, increasedContrast: increasedContrast))
        }.joined(separator: "\n")
        let interactionDeclarations =
            increasedContrast
            ? ScholiumContentInteractionSurface.increasedContrastWebCSSDeclarations
            : ScholiumContentInteractionSurface.webCSSDeclarations
        return """
            :root {
                color-scheme: \(dark ? "dark" : "light");
                \(declarations)
                \(ScholiumShape.webCSSDeclarations)
                \(interactionDeclarations)
                \(ScholiumWebDesignTokens.documentMarkupCSSDeclarations)
            }
            html, body { background: transparent; color: var(--scholium-color-primary-text); }
            .scholium-document { padding: 8px; margin: 0; max-width: none; font-family: system-ui; }
            .scholium-document > .scholium-mermaid { margin-block: 0; }
            .scholium-mermaid-source, .scholium-mermaid-diagnostic { font-family: system-ui; }
            .scholium-mermaid-rendered .scholium-mermaid-diagnostic { display: none; }
            """
    }

}
