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
    @State private var height = ScholiumChatAppearance.messageLoadingHeight
    @State private var intrinsicWidth: CGFloat?
    @State private var objects: [ReadReplyObject] = []
    @State private var objectsSource: String?
    @State private var failure: String?
    @State private var preview = ScholiumContentPreview()

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
                    onRenderingReady: { ready = true }, onReplyEvent: { receive($0, expectedSource: projection.document.rawContent) }
                )
                .frame(maxWidth: fitsContent ? intrinsicWidth ?? .infinity : .infinity)
                .frame(height: height)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(objects) { object in
                            AgentChatRichObjectActions(
                                object: object,
                                copy: {
                                    guard let objectsSource, let payload = objectContent(object.id, expectedSource: objectsSource) else { return false }
                                    readingInteraction()
                                    NSPasteboard.general.clearContents()
                                    return NSPasteboard.general.setString(payload.copyText, forType: .string)
                                },
                                expand: { origin in
                                    guard let objectsSource, let payload = objectContent(object.id, expectedSource: objectsSource) else { return }
                                    readingInteraction()
                                    preview.present(
                                        title: ScholiumL10n.string(payload.kind == .diagram ? "Diagram" : payload.kind == .code ? "Code" : "Table"),
                                        copyText: payload.copyText, from: origin
                                    ) {
                                        AgentChatRichContent(object: payload, naturalSize: object.naturalSize, openLink: openLink)
                                    }
                                }
                            )
                            .disabled(objectsSource != source || objectsSource != projection.document.rawContent)
                            .frame(width: object.frame.width, height: object.frame.height, alignment: .topTrailing)
                            .offset(x: object.frame.minX, y: object.frame.minY)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .layout(let value, let width, let objects):
            height = value
            intrinsicWidth = width
            self.objects = objects.filter { renderer.snapshot?.objects[$0.id] != nil }
            objectsSource = expectedSource
        case .quote(let text):
            guard expectedSource == source else { return }
            quote?(.reader(source: source, excerpt: text))
        case .selectionContext(let text, let point, let view):
            guard expectedSource == source else { return }
            let menu = NSMenu()
            menu.addItem(
                AgentChatNoteMenuItem(ScholiumL10n.string("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                })
            if let quote {
                menu.addItem(
                    AgentChatNoteMenuItem(ScholiumL10n.string("Ask About Selection")) {
                        quote(.reader(source: source, excerpt: text))
                    })
            }
            // Leave WebKit's script-message callback before AppKit starts the
            // native menu event loop. Copy owns this exact selected snapshot.
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil else { return }
                menu.popUp(positioning: nil, at: point, in: view)
            }
        case .noteContext(let url, let point, let view):
            guard expectedSource == source else { return }
            guard AgentChatReplySource.collect(source).contains(where: { $0.url == url && $0.isNote }) else { return }
            let menu = NSMenu()
            menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open Note")) { openLink(url) })
            if let openSeparate {
                menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in Separate Window")) { openSeparate(url) })
            }
            menu.popUp(positioning: nil, at: point, in: view)

        }
    }

    private func objectContent(_ id: String, expectedSource: String) -> RenderedMarkdownObject? {
        guard expectedSource == source, let snapshot = renderer.snapshot,
            expectedSource == snapshot.document.rawContent
        else { return nil }
        return snapshot.objects[id]
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
                .scholium-reply-controls { height: \(ScholiumGrid.Dimension.preferredCustomTarget)px; margin-bottom: \(ScholiumGrid.Spacing.labelAccessoryGap)px; }
                .scholium-table-scroll { margin-block: 0; }
                .scholium-reply-object-scroll { overflow-x: auto; max-width: 100%; }
                .scholium-reply-object table { width: max-content; min-width: 100%; border-collapse: collapse; }
                .scholium-reply-object th, .scholium-reply-object td { min-width: 120px; padding: 6px 10px; text-align: start; }
                .scholium-reply-object-scroll pre { width: max-content; min-width: 100%; margin: 0; }
                """
    }
}

/// Native actions sit above the reader as siblings, preserving WebKit selection
/// and using the same pointer/focus disclosure and copy feedback as message actions.
private struct AgentChatRichObjectActions: View {
    let object: ReadReplyObject
    let copy: () -> Bool
    let expand: (NSView) -> Void
    @State private var origin: NSView?

    var body: some View {
        AgentChatMessageActionVisibility(alignment: .trailing, actionsAbove: true) {
            Color.clear
                .frame(height: max(0, object.frame.height - ScholiumGrid.Dimension.preferredCustomTarget - ScholiumGrid.Spacing.labelAccessoryGap))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } actions: {
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ScholiumCopyButton(copy: copy)
                    .accessibilityIdentifier("scholium.chat.copyObject")
                Button {
                    if let origin { expand(origin) }
                } label: {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.expand.symbol, placement: .action)
                }
                .help("Expand").accessibilityLabel("Expand")
                .accessibilityIdentifier("scholium.chat.expandObject")
            }
            .buttonStyle(ScholiumContentActionButtonStyle())
        }
        // The origin exists even while the action row's drawing is concealed.
        // Accessibility activation must not depend on a prior pointer reveal.
        .background(alignment: .topTrailing) {
            ScholiumPreviewAttachment { origin = $0 }
                .frame(
                    width: ScholiumGrid.Dimension.preferredCustomTarget,
                    height: ScholiumGrid.Dimension.preferredCustomTarget
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onDisappear { origin = nil }
    }
}
