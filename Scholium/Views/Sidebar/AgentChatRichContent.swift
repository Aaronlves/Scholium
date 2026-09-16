import AppKit
import ScholiumContracts
import SwiftUI

/// Expanded objects use their renderer-owned payload; no Markdown is reparsed.
struct AgentChatRichContent: View {
    let object: RenderedMarkdownObject
    let naturalSize: CGSize
    let openLink: (URL) -> Void

    var body: some View {
        if object.kind == .code {
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    AgentChatObjectText(text: Self.codeText(object.copyText))
                        .frame(width: max(viewport.size.width, naturalSize.width), alignment: .topLeading)
                }.defaultScrollAnchor(.topLeading)
            }
        } else {
            AgentChatObjectHTML(object: object, openLink: openLink)
        }
    }

    static func codeText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: ScholiumChatAppearance.messageNSFont.pointSize, weight: .regular),
                .foregroundColor: ScholiumChatAppearance.messageNSForeground,
            ])
    }
}

struct AgentChatObjectText: NSViewRepresentable {
    let text: NSAttributedString
    func makeNSView(context: Context) -> AgentChatObjectTextView { AgentChatObjectTextView() }
    func updateNSView(_ view: AgentChatObjectTextView, context: Context) {
        if !view.attributedString().isEqual(to: text) { view.textStorage?.setAttributedString(text) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatObjectTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.measuredHeight(width: width))
    }
}

/// Safe HTML comes from the same source snapshot as Copy and the inline object.
private struct AgentChatObjectHTML: View {
    let object: RenderedMarkdownObject
    let openLink: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var failure: String?
    @State private var ready = false

    var body: some View {
        Group {
            if let failure {
                VStack(alignment: .leading) {
                    Text(verbatim: failure).foregroundStyle(.secondary)
                    Text(verbatim: object.copyText).textSelection(.enabled)
                    Button("Retry") { self.failure = nil }
                }
            } else {
                SafeMarkdownReadWebView(
                    documentID: "chat-object", fingerprint: DocumentFingerprint(content: object.copyText).sha256,
                    source: object.copyText, htmlBody: object.html,
                    presentationCSS: object.kind == .diagram
                        ? AgentChatDiagram.previewCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
                        : Self.tableCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased),
                    userCSS: "", onLinkClick: { if let url = URL(string: $0) { openLink(url) } }, onOpenExternalURL: openLink,
                    selectionSurfaceIsActive: false, renderingReadinessIsAcknowledged: ready,
                    onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
                    onRenderingReady: { ready = true })
            }
        }
    }

    private static func tableCSS(dark: Bool, increasedContrast: Bool) -> String {
        AgentChatDiagram.presentationCSS(dark: dark, increasedContrast: increasedContrast)
            + ScholiumPreviewStyles.diagramColorCSS(dark: dark, increasedContrast: increasedContrast) + """
                :root { font-size: \(NSFont.systemFontSize)px; --scholium-document-body-font-family: system-ui; }
                html, body { height: 100%; overflow: auto; }
                .scholium-document { padding: 0; font: 1rem/1.45 system-ui; }
                .scholium-table-scroll { overflow: visible; }
                .scholium-table { width: max-content; min-width: 100%; border-collapse: collapse; }
                .scholium-table th, .scholium-table td { min-width: 120px; padding: 6px 10px; text-align: start; }
                """
    }
}

@MainActor enum AgentChatDiagram {
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
