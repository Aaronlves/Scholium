import AppKit
import ScholiumContracts
import SwiftUI

/// All message bodies reuse the safe document reader so one WebKit selection
/// spans prose, lists, code and horizontally scrolling tables.
struct AgentChatReadReply: View {
    let source: String
    let quote: ((AgentChatReplySelection) -> Void)?
    let openLink: (URL) -> Void
    var fitsContent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.chatReadingInteraction) private var readingInteraction
    @Environment(\.openChatNoteInSeparateWindow) private var openSeparate
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject private var renderer = AgentChatReplyProjection()
    @State private var ready = false
    @State private var height: CGFloat = 120
    @State private var intrinsicWidth: CGFloat?
    @State private var failure: String?
    @State private var preview = ScholiumContentPreview()
    @State private var quoteRequest: UUID?

    var body: some View {
        Group {
            if let failure {
                VStack(alignment: .leading) {
                    Text(failure).foregroundStyle(.secondary)
                    Text(verbatim: source).textSelection(.enabled)
                    Button("Retry") {
                        self.failure = nil
                        ready = false
                    }
                }
            } else if let projection = renderer.snapshot {
                SafeMarkdownReadWebView(
                    documentID: "chat-reply", fingerprint: projection.document.fingerprint.sha256,
                    source: projection.document.rawContent, htmlBody: projection.html, presentationCSS: css, userCSS: "",
                    onLinkClick: { if let url = URL(string: $0) { openLink(url) } }, onOpenExternalURL: openLink,
                    selectionSurfaceIsActive: false, renderingReadinessIsAcknowledged: ready,
                    onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
                    onRenderingReady: { ready = true }, onReplyEvent: { receive($0, expectedSource: projection.document.rawContent) },
                    replyQuoteRequest: quoteRequest
                )
                .frame(maxWidth: fitsContent ? intrinsicWidth ?? .infinity : .infinity)
                .frame(height: height)
                .contextMenu {
                    if quote != nil {
                        Button("Ask About Selection") { quoteRequest = UUID() }
                    }
                }
            } else {
                ProgressView("Loading…")
            }
        }
        .preference(key: AgentChatReplyReadyPreference.self, value: ready || failure != nil)
        .onDisappear {
            preview.close()
            renderer.cancel()
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { preview.close() } }
        .task(id: source) {
            preview.close()
            failure = nil
            renderer.submit(source)
        }
    }

    private func receive(_ event: ReadReplyEvent, expectedSource: String) {
        guard expectedSource == renderer.snapshot?.document.rawContent else { return }
        switch event {
        case .interaction: readingInteraction()
        case .layout(let value, let width):
            height = value
            intrinsicWidth = width
        case .quote(let text):
            guard expectedSource == source else { return }
            quote?(.reader(source: source, excerpt: text))
        case .noteContext(let url, let point, let view):
            guard expectedSource == source else { return }
            guard AgentChatReplySource.collect(source).contains(where: { $0.url == url && $0.isNote }) else { return }
            let menu = NSMenu()
            menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open Note")) { openLink(url) })
            if let openSeparate {
                menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in Separate Window")) { openSeparate(url) })
            }
            menu.popUp(positioning: nil, at: point, in: view)

        case .object(let index, let copy, let size, let anchor, let view):
            guard expectedSource == source else { return }
            let layout = AgentChatObjectProjection.layoutReply(source)
            let objects = AgentChatRichSegment.collect(layout).filter(\.isObject)
            guard objects.indices.contains(index) else { return }
            let segment = objects[index]
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(segment.code ?? layout.text.attributedSubstring(from: segment.range).string, forType: .string)
            } else {
                guard !anchor.intersection(view.visibleRect).isEmpty else { return }
                let isDiagram = segment.language?.lowercased() == "mermaid"
                preview.present(
                    title: ScholiumL10n.string(isDiagram ? "Diagram" : segment.code != nil ? "Code" : "Table"),
                    copyText: segment.code ?? layout.text.attributedSubstring(from: segment.range).string,
                    from: view, anchor: anchor
                ) {
                    AgentChatRichContent(
                        text: layout.text.attributedSubstring(from: segment.range),
                        diagramSource: isDiagram ? segment.code : nil, naturalSize: size, openLink: openLink)
                }
            }
        }
    }

    private var css: String {
        AgentChatDiagram.presentationCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
            + ScholiumChatAppearance.messageBodyCSS
            + ScholiumChatAppearance.inlineCodeCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased) + """
                html, body { overflow: hidden; }
                .scholium-document a { color: var(--scholium-document-accent); text-decoration-color: currentColor; }
                .scholium-document a:hover {
                    color: var(--scholium-color-accent);
                    background: var(--scholium-content-hover-surface);
                    border-radius: var(--scholium-corner-document-control);
                    text-decoration-color: currentColor;
                }
                .scholium-document a:focus-visible {
                    color: var(--scholium-color-accent);
                    background: var(--scholium-content-keyboard-focus-surface);
                    border-radius: var(--scholium-corner-document-control);
                    outline: 2px solid var(--scholium-content-focus-ring);
                    outline-offset: 2px;
                    text-decoration-color: currentColor;
                }
                .scholium-document a:active {
                    background: var(--scholium-content-keyboard-focus-surface);
                }
                .scholium-reply-object { margin-block: .85em; }
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
