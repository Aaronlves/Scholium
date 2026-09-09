import AppKit
import ScholiumContracts
import SwiftUI

/// Rich replies reuse the safe document reader so one native WebKit selection
/// spans prose, lists, code and horizontally scrolling tables.
struct AgentChatReadReply: View {
    let source: String
    let quote: ((AgentChatReplySelection) -> Void)?
    let openLink: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var projection: Projection?
    @State private var ready = false
    @State private var height: CGFloat = 120
    @State private var failure: String?
    @State private var preview = AgentChatRichPreviewController()
    @State private var quoteRequest: UUID?

    private struct Projection {
        let document: NoteDocument
        let html: String
        init(_ source: String) {
            document = NoteDocument(relativePath: "Reply.md", rawContent: source)
            html = SafeMarkdownRenderer.render(document).htmlBody
        }
    }

    var body: some View {
        Group {
            if let failure {
                VStack(alignment: .leading) {
                    Text(failure).foregroundStyle(.secondary)
                    Text(verbatim: source).textSelection(.enabled)
                    Button("Retry") { self.failure = nil; ready = false }
                }
            } else if let projection {
                SafeMarkdownReadWebView(documentID: "chat-reply", fingerprint: projection.document.fingerprint.sha256,
                    source: projection.document.rawContent, htmlBody: projection.html, presentationCSS: css, userCSS: "",
                    onLinkClick: { if let url = URL(string: $0) { openLink(url) } }, onOpenExternalURL: openLink,
                    selectionSurfaceIsActive: false, renderingReadinessIsAcknowledged: ready,
                    onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
                    onRenderingReady: { ready = true }, onReplyEvent: { receive($0, expectedSource: projection.document.rawContent) }, replyQuoteRequest: quoteRequest)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .contextMenu {
                        if quote != nil {
                            Button("Ask About Selection") { quoteRequest = UUID() }
                        }
                    }
            } else { ProgressView("Loading…") }
        }
        .onDisappear { preview.close() }
        .task(id: source) { preview.close(); failure = nil; ready = false; projection = Projection(source) }
    }

    private func receive(_ event: ReadReplyEvent, expectedSource: String) {
        guard expectedSource == source else { return }
        switch event {
        case .height(let value): height = value
        case .quote(let text): quote?(.reader(source: source, excerpt: text))
        case .object(let index, let copy, let size, let anchor, let view):
            let layout = AgentChatSelectableText.layoutReply(source)
            let objects = AgentChatRichSegment.collect(layout).filter(\.isObject)
            guard objects.indices.contains(index) else { return }
            let segment = objects[index]
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(segment.code ?? layout.text.attributedSubstring(from: segment.range).string, forType: .string)
            } else {
                preview.present(content:
                    AgentChatRichContent(source: source, openLink: openLink,
                        onlySegment: segment.id, expandedDiagramSize: size), naturalSize: size, anchor: anchor, of: view)
            }
        }
    }

    private var css: String {
        AgentChatDiagram.presentationCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased) + """
        html, body { overflow: hidden; }
        .scholium-document { padding: 0; margin: 0; font: \(NSFont.preferredFont(forTextStyle: .body).pointSize)px/1.55 system-ui; }
        .scholium-document > :first-child { margin-top: 0; }
        .scholium-document > :last-child { margin-bottom: 0; }
        .scholium-document p { margin: 0 0 12px; }
        .scholium-document :not(pre) > code { background: color-mix(in srgb, currentColor 8%, transparent); border-radius: 3px; padding: 1px 3px; }
        .scholium-reply-object { margin-block: 12px; }
        .scholium-reply-controls { display: flex; justify-content: end; gap: 8px; user-select: none; }
        .scholium-reply-controls button { border: 0; background: transparent; color: var(--scholium-color-secondary-text); width: 24px; height: 24px; font: inherit; cursor: pointer; }
        .scholium-reply-controls button span { display: block; width: 16px; height: 16px; background: currentColor; -webkit-mask: var(--reply-symbol) center / contain no-repeat; mask: var(--reply-symbol) center / contain no-repeat; }
        .scholium-table-scroll { margin-block: 0; }
        .scholium-reply-controls button:focus-visible { outline: auto; }
        .scholium-reply-object-scroll { overflow-x: auto; max-width: 100%; }
        .scholium-reply-object table { width: max-content; min-width: 100%; border-collapse: collapse; }
        .scholium-reply-object th, .scholium-reply-object td { min-width: 120px; padding: 6px 10px; text-align: start; }
        .scholium-reply-object-scroll pre { width: max-content; min-width: 100%; margin: 0; }
        """
    }
}
