import AppKit
import Observation
import ScholiumContracts
import SwiftUI

/// Rich bodies retain one safe WebKit selection across their Markdown objects.
/// Proven plain user paragraphs use the same exact source in native text.
struct AgentChatReadReply: View {
    private let sourceIdentity: ScholiumExactUTF8.SourceIdentity
    private var source: String { sourceIdentity.source }
    var readerID: String? = nil
    var isStreaming = false
    let quote: ((AgentChatReplySelection) -> Void)?
    let openLink: (URL) -> Void
    var fitsContent = false
    var allowsNativeParagraph = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    @Environment(\.chatReadingInteraction) private var readingInteraction
    @Environment(\.chatReadingPresentation) private var readingPresentation
    @Environment(\.openChatNoteInNewTab) private var openNewTab
    @Environment(\.openChatNoteInSeparateWindow) private var openSeparate
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject private var renderer = AgentChatReplyProjection()
    @State private var readerProjection: AgentChatReplyProjection.Snapshot?
    @State private var hasHydratedReader = false
    @State private var hasPresentedReader = false
    @State private var preparationIsAdmitted = false
    @State private var preparationAttempt = UUID()
    @State private var readiness = Readiness()
    @State private var height = ScholiumChatAppearance.messageLoadingHeight
    @State private var intrinsicWidth: CGFloat?
    @State private var objects: [ReadReplyObject] = []
    @State private var objectsSource: ScholiumExactUTF8.SourceIdentity?
    @State private var preview = ScholiumContentPreview()

    init(
        source: String, readerID: String? = nil, isStreaming: Bool = false,
        quote: ((AgentChatReplySelection) -> Void)?, openLink: @escaping (URL) -> Void,
        fitsContent: Bool = false, allowsNativeParagraph: Bool = false
    ) {
        sourceIdentity = .init(source)
        self.readerID = readerID
        self.isStreaming = isStreaming
        self.quote = quote
        self.openLink = openLink
        self.fitsContent = fitsContent
        self.allowsNativeParagraph = allowsNativeParagraph
    }

    var body: some View {
        Group {
            if let failure = readiness.failure {
                VStack(alignment: .leading) {
                    Text(failure).foregroundStyle(.secondary)
                    Text(verbatim: source).textSelection(.enabled)
                    Button("Retry") {
                        readiness.reset()
                        hasHydratedReader = false
                        preparationIsAdmitted = false
                        hasPresentedReader = false
                        preparationAttempt = UUID()
                    }
                }
            } else if let projection = readerProjection, preparationIsAdmitted {
                if let paragraph = nativeParagraph(in: projection) {
                    AgentChatNativeParagraph(
                        source: paragraph, revision: projection.presentationRevision, fitsContent: fitsContent,
                        isInteractive: readerIsVisible && readiness.acceptsInteraction
                            && ScholiumExactUTF8.equal(source, paragraph),
                        onInteraction: readingInteraction,
                        onLayout: { revision, size in
                            guard readerProjection?.presentationRevision == revision,
                                ScholiumExactUTF8.equal(source, paragraph), size.width.isFinite, size.height.isFinite,
                                size.width > 0, size.height > 0
                            else { return }
                            readiness.measureLayout(height: size.height, viewportWidth: size.width, maximumWidth: fitsContent ? size.width : nil)
                            readiness.applyLayout(size)
                            readiness.ready = true
                            acceptHydratedProjection()
                        }
                    )
                } else {
                    // Keep the readable native projection as the row's geometry until
                    // the dedicated reader has reported both a loaded page and its
                    // actual height. Mounting WebKit at the one-line loading height
                    // makes the whole transcript collapse and then expand on first
                    // entry, which is visible as a spurious scroll.
                    fallbackBody
                        .frame(height: readerIsVisible ? height : nil, alignment: .topLeading)
                        .opacity(readerIsVisible ? 0 : 1)
                        .allowsHitTesting(!readerIsVisible)
                        .accessibilityHidden(readerIsVisible)
                        .overlay(alignment: .topLeading) {
                            AgentChatReadWebViewSurface(
                                documentID: "chat-reply", document: projection.document,
                                htmlBody: projection.html, presentationCSS: css, userCSS: "",
                                projectionRevision: projection.presentationRevision,
                                onLinkClick: { if let url = URL(string: $0) { openLink(url) } }, onOpenExternalURL: openLink,
                                renderingReadinessIsAcknowledged: readiness.ready,
                                onRenderingFailure: {
                                    guard readerProjection?.presentationRevision == projection.presentationRevision else { return }
                                    preparationIsAdmitted = false
                                    hasPresentedReader = false
                                    readiness.failure = $0
                                    hasHydratedReader = false
                                    renderer.cancel()
                                },
                                onRenderingLoading: {
                                    guard readerProjection?.presentationRevision == projection.presentationRevision else { return }
                                    readiness.reset()
                                    hasHydratedReader = false
                                },
                                onRenderingReady: {
                                    guard readerProjection?.presentationRevision == projection.presentationRevision else { return }
                                    readiness.ready = true
                                    acceptHydratedProjection()
                                },
                                onEvent: { receive($0, expectedSource: projection.document.rawContent) }
                            )
                            .frame(maxWidth: fitsContent ? intrinsicWidth ?? .infinity : .infinity)
                            .frame(height: height)
                            .onGeometryChange(for: CGSize.self) {
                                $0.size
                            } action: {
                                guard readerProjection?.presentationRevision == projection.presentationRevision else { return }
                                readiness.applyLayout($0)
                            }
                            .opacity(readerIsVisible ? 1 : 0)
                            .allowsHitTesting(readerIsVisible)
                            .overlay(alignment: .topLeading) {
                                ZStack(alignment: .topLeading) {
                                    ForEach(objects) { object in
                                        AgentChatRichObjectActions(
                                            object: object,
                                            copy: {
                                                guard let objectsSource, let payload = objectContent(object.id, expectedSource: objectsSource.source) else {
                                                    return false
                                                }
                                                readingInteraction()
                                                NSPasteboard.general.clearContents()
                                                return NSPasteboard.general.setString(payload.copyText, forType: .string)
                                            },
                                            expand: { origin in
                                                guard let objectsSource, let payload = objectContent(object.id, expectedSource: objectsSource.source) else {
                                                    return
                                                }
                                                readingInteraction()
                                                let content = AgentChatRichContent(
                                                    object: payload, naturalSize: object.naturalSize, openLink: openLink)
                                                preview.present(
                                                    title: ScholiumL10n.string(payload.kind == .diagram ? "Diagram" : payload.kind == .code ? "Code" : "Table"),
                                                    copyText: payload.copyText, from: origin
                                                ) {
                                                    content
                                                }
                                            }
                                        )
                                        .disabled(
                                            objectsSource != ScholiumExactUTF8.SourceIdentity(source)
                                                || objectsSource != ScholiumExactUTF8.SourceIdentity(projection.document.rawContent)
                                        )
                                        .frame(width: object.frame.width, height: object.frame.height, alignment: .topTrailing)
                                        .offset(x: object.frame.minX, y: object.frame.minY)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .disabled(!readerIsVisible)
                        }
                        .frame(maxWidth: fitsContent && readerIsVisible ? intrinsicWidth ?? .infinity : .infinity, alignment: .leading)
                        .frame(height: readerIsVisible ? height : nil, alignment: .topLeading)
                }
            } else {
                fallbackBody
            }
        }
        // The native preview is an acceptable first paint when no reader exists;
        // a retained reader must stay mounted while its source streams forward.
        .preference(
            key: AgentChatReplyReadyPreference.self,
            value: readiness.ready || readiness.failure != nil || readerProjection == nil
        )
        .onAppear {
            readiness.mount(in: readingPresentation?.session, readerID: readerID, presentationID: readingPresentation?.id, itemID: readingPresentation?.itemID)
        }
        .onChange(of: readerIsVisible) { _, visible in
            if visible { hasPresentedReader = true }
        }
        .onChange(of: readerID) { _, _ in
            readiness.updateOwner(
                readingPresentation?.session, readerID: readerID, presentationID: readingPresentation?.id, itemID: readingPresentation?.itemID)
        }
        .onChange(of: readingPresentation) { _, _ in
            readiness.updateOwner(
                readingPresentation?.session, readerID: readerID, presentationID: readingPresentation?.id, itemID: readingPresentation?.itemID)
        }
        .onDisappear {
            readiness.unmount()
            preview.close()
            renderer.cancel()
            hasHydratedReader = false
            hasPresentedReader = false
        }
        .onChange(of: renderer.snapshot?.presentationRevision, initial: true) { _, _ in
            // Keep the first safe projection stable through navigation, bundled
            // runtime setup and layout measurement. Streamed snapshots continue
            // parsing/coalescing off the UI actor, but cannot restart this page
            // or invalidate its fingerprint-bound initialization messages.
            if readerProjection == nil || hasHydratedReader || readerProjection.flatMap(nativeParagraph) != nil {
                installProjection(renderer.snapshot)
            }
        }
        .onChange(of: renderer.failure) { _, failure in
            if let failure {
                readiness.failure = failure
                hasHydratedReader = false
            }
        }
        .onChange(of: isEnabled && surfaceVisibility.isActive, initial: true) { _, interactive in
            readiness.interactionIsEnabled = interactive
            if !interactive { preview.close() }
        }
        .task(
            id: PreparationIdentity(
                source: .init(source),
                isStreaming: isStreaming,
                isActive: preparationIsActive,
                presentationID: readingPresentation?.id, attempt: preparationAttempt)
        ) {
            guard preparationIsActive else { return }
            readiness.mount(in: readingPresentation?.session, readerID: readerID, presentationID: readingPresentation?.id, itemID: readingPresentation?.itemID)
            if !preparationIsAdmitted {
                guard let admission = await readiness.prepare() else { return }
                guard !Task.isCancelled, preparationIsActive else {
                    admission.cancelUnstarted()
                    return
                }
                preparationIsAdmitted = true
                // This grant owns a new native page, including a failed page's
                // retry. Publish one fresh receipt and never initialize it with
                // an obsolete source projection.
                readiness.reset()
                readiness.clearAppliedLayout()
                readerProjection = renderer.snapshot.flatMap {
                    $0.request == .init(source, isStreaming: isStreaming) ? $0 : nil
                }
            }
            preview.close()
            readiness.failure = nil
            // Source revisions reconcile inside the retained page. Its measured
            // prefix stays readable while the next projection is prepared;
            // navigation or a replacement (not an append) invalidates readiness.
            // A queued replacement must not discard the first page's layout
            // proof while its rendering-ready acknowledgement is still pending.
            if hasHydratedReader, let displayed = readerProjection?.document.rawContent, !ScholiumExactUTF8.hasPrefix(source, displayed) {
                readiness.reset()
            }
            renderer.submit(source, isStreaming: isStreaming)
        }
    }

    private struct PreparationIdentity: Equatable {
        let source: ScholiumExactUTF8.SourceIdentity
        let isStreaming: Bool
        let isActive: Bool
        let presentationID: UUID?
        let attempt: UUID
    }

    private var preparationIsActive: Bool {
        guard isEnabled && surfaceVisibility != .retained else { return false }
        guard readerID != nil, let presentation = readingPresentation else { return true }
        return presentation.session.ownsPresentation(presentation.id)
    }

    private func nativeParagraph(in projection: AgentChatReplyProjection.Snapshot) -> String? {
        guard allowsNativeParagraph, quote == nil else { return nil }
        return projection.nativeParagraph
    }

    private func installProjection(_ projection: AgentChatReplyProjection.Snapshot?) {
        let replacesNativeWithWeb = readerProjection.flatMap(nativeParagraph) != nil && projection.flatMap(nativeParagraph) == nil
        if readerProjection?.presentationRevision != projection?.presentationRevision,
            readerProjection.flatMap(nativeParagraph) != nil || projection.flatMap(nativeParagraph) != nil
        {
            // A new native revision (including a same-size replacement) needs
            // its own applied-layout receipt, as does either renderer transition.
            readiness.reset()
            readiness.clearAppliedLayout()
            hasHydratedReader = false
        }
        readerProjection = projection
        if replacesNativeWithWeb {
            preparationIsAdmitted = false
            preparationAttempt = UUID()
        }
    }

    private var readerIsVisible: Bool {
        // Every reader waits for measured geometry before replacing its finite
        // preview. Transcript readers additionally respect active scrolling.
        readiness.ready && readiness.hasMeasuredLayout
            && (surfaceVisibility == .preparing || hasPresentedReader || readingPresentation?.session.isScrolling != true)
    }

    @ViewBuilder
    private var fallbackBody: some View {
        // Keep retained history readable while the exact WebKit projection is
        // prepared. This is presentation-only; source and selection authority
        // remain in the reader below.
        // First paint and the first native page share one finite submitted
        // revision. A live preview must never run ahead of the DOM it hands off
        // to. Pending chunks coalesce behind that page without starving it.
        let readable = readerProjection?.previewText ?? (isStreaming ? "" : readiness.preview(for: source))
        if readable.isEmpty {
            ProgressView("Loading…")
        } else {
            Text(verbatim: readable)
                .font(ScholiumChatAppearance.messageFont)
                .foregroundStyle(ScholiumChatAppearance.messageForeground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func receive(_ event: ReadReplyEvent, expectedSource: String) {
        guard let displayed = readerProjection?.document.rawContent, ScholiumExactUTF8.equal(expectedSource, displayed) else { return }
        switch event {
        case .interaction: readingInteraction()
        case .layout(let value, let viewportWidth, let width, let objects):
            height = value
            intrinsicWidth = width
            readiness.measureLayout(height: value, viewportWidth: viewportWidth, maximumWidth: fitsContent ? width : nil)
            self.objects = objects.filter { readerProjection?.objects[$0.id] != nil }
            objectsSource = .init(expectedSource)
            acceptHydratedProjection()
        case .quote(let text):
            guard ScholiumExactUTF8.equal(expectedSource, source) else { return }
            quote?(.reader(source: source, excerpt: text))
        case .selectionContext(let text, let point, let view):
            guard ScholiumExactUTF8.equal(expectedSource, source) else { return }
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
                guard let view, view.window != nil, readiness.acceptsInteraction,
                    let current = renderer.snapshot?.document.rawContent,
                    ScholiumExactUTF8.equal(expectedSource, current)
                else { return }
                menu.popUp(positioning: nil, at: point, in: view)
            }
        case .noteContext(let url, let point, let view):
            guard ScholiumExactUTF8.equal(expectedSource, source) else { return }
            guard AgentChatReplySource.collect(source).contains(where: { $0.url == url && $0.isNote }) else { return }
            let menu = NSMenu()
            menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open Note")) { openLink(url) })
            if let openNewTab {
                menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in New Tab")) { openNewTab(url) })
            }
            if let openSeparate {
                menu.addItem(AgentChatNoteMenuItem(ScholiumL10n.string("Open in Separate Window")) { openSeparate(url) })
            }
            menu.popUp(positioning: nil, at: point, in: view)

        }
    }

    private func acceptHydratedProjection() {
        guard readiness.ready && readiness.hasMeasuredLayout else { return }
        // Native readiness and layout callbacks complete this page's lifetime
        // synchronously. A later SwiftUI change observer could miss completion
        // when a source revision arrives before its next rendering pass.
        hasHydratedReader = true
        installProjection(renderer.snapshot)
    }

    private func objectContent(_ id: String, expectedSource: String) -> RenderedMarkdownObject? {
        guard ScholiumExactUTF8.equal(expectedSource, source), let snapshot = readerProjection,
            ScholiumExactUTF8.equal(expectedSource, snapshot.document.rawContent)
        else { return nil }
        return snapshot.objects[id]
    }

    private var css: String {
        AgentChatDiagram.presentationCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
            + ScholiumChatAppearance.messageBodyCSS
            + ScholiumChatAppearance.inlineCodeCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased)
            + AgentChatWebsiteIcon.presentationCSS
                + """
                html, body { overflow: hidden; }
                .scholium-document a { color: var(--scholium-document-accent); text-decoration-color: currentColor; }
                .scholium-document a.scholium-chat-link::before {
                    content: "";
                    display: inline-block;
                    inline-size: \(ScholiumChatAppearance.linkIconScale)em;
                    block-size: \(ScholiumChatAppearance.linkIconScale)em;
                    margin-inline-start: \(ScholiumChatAppearance.linkIconLeadingGapEm)em;
                    margin-inline-end: \(ScholiumChatAppearance.linkIconTrailingGapEm)em;
                    vertical-align: -.06em;
                    background: var(--scholium-color-secondary-text);
                    -webkit-mask: var(--scholium-chat-link-symbol) center / contain no-repeat;
                    mask: var(--scholium-chat-link-symbol) center / contain no-repeat;
                }
                .scholium-chat-link[data-scholium-pending-link]::before { visibility: hidden; }
                .scholium-chat-link[data-scholium-chat-link-symbol="globe"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-globe); }
                .scholium-chat-link[data-scholium-chat-link-symbol="doc-text"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-doc-text); }
                .scholium-chat-link[data-scholium-chat-link-symbol="doc-richtext"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-doc-richtext); }
                .scholium-chat-link[data-scholium-chat-link-symbol="books-vertical"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-books-vertical); }
                .scholium-chat-link[data-scholium-chat-link-symbol="tablecells"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-tablecells); }
                .scholium-chat-link[data-scholium-chat-link-symbol="rectangle-on-rectangle"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-rectangle-on-rectangle); }
                .scholium-chat-link[data-scholium-chat-link-symbol="photo"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-photo); }
                .scholium-chat-link[data-scholium-chat-link-symbol="doc-zipper"] { --scholium-chat-link-symbol: var(--scholium-system-symbol-doc-zipper); }
                .scholium-document a[href]:hover {
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
                AgentChatCopyButton(accessibilityID: "scholium.chat.copyObject", copy: copy)
                AgentChatActionButton(label: "Expand", systemImage: ScholiumSidebarAction.expand.symbol,
                    accessibilityID: "scholium.chat.expandObject") {
                    if let origin { expand(origin) }
                }
            }
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

extension AgentChatReadReply {
    /// The reader's actual presentation state also supplies its hydration
    /// receipt. Native callbacks publish directly, independently of SwiftUI's
    /// aggregate preferences and the separate arrival-animation preference.
    @MainActor @Observable
    final class Readiness {
        var ready = false { didSet { publish() } }
        var hasMeasuredLayout = false { didSet { publish() } }
        var failure: String? { didSet { publish() } }

        @ObservationIgnored private weak var session: AgentChatReadingSession?
        @ObservationIgnored private var readerID: String?
        @ObservationIgnored private var presentationID: UUID?
        @ObservationIgnored private var itemID: String?
        @ObservationIgnored private var instance: UUID?
        @ObservationIgnored private var isMounted = false
        @ObservationIgnored private var isStandalone = false
        @ObservationIgnored private var isResetting = false
        @ObservationIgnored private var measuredSize: CGSize?
        @ObservationIgnored private var appliedSize: CGSize?
        @ObservationIgnored private var maximumLayoutWidth: CGFloat?
        @ObservationIgnored var interactionIsEnabled = false

        @ObservationIgnored private var previewSource: ScholiumExactUTF8.SourceIdentity?
        @ObservationIgnored private var previewText = ""

        func preview(for source: String) -> String {
            let identity = ScholiumExactUTF8.SourceIdentity(source)
            if previewSource != identity {
                previewText = MarkdownVisibleText.render(source)
                previewSource = identity
            }
            return previewText
        }

        @MainActor struct Admission {
            let queue: AgentChatReaderPreparation?
            let permit: AgentChatReaderPreparation.Permit?
            func cancelUnstarted() {
                if let permit { queue?.releaseUnstarted(permit) }
            }
        }

        func prepare() async -> Admission? {
            guard let session, let readerID, let presentationID, let instance else {
                return isStandalone ? Admission(queue: nil, permit: nil) : nil
            }
            let reader = AgentChatReaderPreparation.Reader(presentationID: presentationID, id: readerID, instance: instance)
            guard let permit = await session.readerPreparation.acquire(reader) else { return nil }
            guard session.ownsReplyReader(readerID, presentationID: presentationID, instance: instance) else {
                session.readerPreparation.releaseUnstarted(permit)
                return nil
            }
            return Admission(queue: session.readerPreparation, permit: permit)
        }

        var isHydrated: Bool { (ready && hasMeasuredLayout) || failure != nil }
        var layoutIsApplied: Bool {
            if failure != nil { return true }
            guard isHydrated, let measuredSize, let appliedSize else { return false }
            // A short user paragraph first measures at the available width.
            // That receipt cannot present the row before its intrinsic-width
            // intent has reached both SwiftUI and the browser viewport.
            if let maximumLayoutWidth, measuredSize.width > maximumLayoutWidth + 1 { return false }
            return abs(measuredSize.width - appliedSize.width) <= 1 && abs(measuredSize.height - appliedSize.height) <= 1
        }

        func measureLayout(height: CGFloat, viewportWidth: CGFloat, maximumWidth: CGFloat? = nil) {
            measuredSize = CGSize(width: viewportWidth, height: height)
            maximumLayoutWidth = maximumWidth
            hasMeasuredLayout = true
        }

        func applyLayout(_ size: CGSize) {
            guard appliedSize != size else { return }
            appliedSize = size
            publish()
        }

        func clearAppliedLayout() {
            appliedSize = nil
            publish()
        }
        var acceptsInteraction: Bool {
            guard isMounted, interactionIsEnabled else { return false }
            if isStandalone { return true }
            guard let session, let readerID, let presentationID, let instance else { return false }
            return session.ownsReplyReader(readerID, presentationID: presentationID, instance: instance)
        }

        func reset() {
            isResetting = true
            ready = false
            hasMeasuredLayout = false
            measuredSize = nil
            maximumLayoutWidth = nil
            failure = nil
            isResetting = false
            publish()
        }

        func mount(in session: AgentChatReadingSession?, readerID: String?, presentationID: UUID?, itemID: String? = nil) {
            isMounted = true
            updateOwner(session, readerID: readerID, presentationID: presentationID, itemID: itemID)
        }

        func updateOwner(_ session: AgentChatReadingSession?, readerID: String?, presentationID: UUID?, itemID: String? = nil) {
            guard isMounted else { return }
            isStandalone = readerID == nil
            if self.session === session, self.readerID == readerID, self.presentationID == presentationID, self.itemID == itemID, instance != nil {
                publish()
                return
            }
            detach()
            guard let session, let readerID, let presentationID else { return }
            let instance = UUID()
            self.session = session
            self.readerID = readerID
            self.presentationID = presentationID
            self.itemID = itemID
            self.instance = instance
            session.mountReplyReader(readerID, presentationID: presentationID, instance: instance, hydrated: isHydrated, itemID: itemID)
            publish()
        }

        func unmount() {
            isMounted = false
            detach()
        }

        private func detach() {
            if let session, let readerID, let presentationID, let instance {
                session.unmountReplyReader(readerID, presentationID: presentationID, instance: instance)
            }
            session = nil
            readerID = nil
            presentationID = nil
            itemID = nil
            instance = nil
        }

        private func publish() {
            guard !isResetting, let session, let readerID, let presentationID, let instance else { return }
            session.updateReplyHydration(readerID, presentationID: presentationID, instance: instance, hydrated: isHydrated, layoutApplied: layoutIsApplied)
        }
    }
}
