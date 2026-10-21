import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat native paragraph", .serialized)
@MainActor
struct AgentChatNativeParagraphTests {
    @MainActor private final class NativeFixture {
        let view = AgentChatNativeParagraphView()
        let window: NSWindow

        init() {
            _ = NSApplication.shared
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
            window.contentView = container
            view.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
            container.addSubview(view)
        }

        func close() {
            view.detach()
            window.contentView = nil
            window.close()
        }
    }

    @Test(
        "Native source, selected Copy and text-area accessibility preserve exact Unicode in every appearance"
    )
    func exactSourceCopyAndAppearance() throws {
        let fixture = NativeFixture()
        defer { fixture.close() }
        let view = fixture.view
        let prefix = "Before "
        let selected = "中文 👩‍🔬 e\u{301}"
        let source = prefix + selected + " after."
        let range = NSRange(location: prefix.utf16.count, length: selected.utf16.count)
        let pasteboard = NSPasteboard(name: .init("scholium.native-paragraph-copy.\(UUID())"))
        defer { pasteboard.clearContents() }

        let appearances: [NSAppearance.Name] = [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]
        for name in appearances {
            let appearance = try #require(NSAppearance(named: name))
            view.appearance = appearance
            view.configure(
                source: source, revision: name.rawValue, fitsContent: true, isInteractive: true,
                onInteraction: {}, onLayout: { _, _ in })
            view.layout()
            let container = try #require(view.textContainer)
            let layout = try #require(view.layoutManager)
            layout.ensureLayout(for: container)
            try #require(fixture.window.makeFirstResponder(view))
            view.setSelectedRange(range)
            try #require(view.selectedRange() == range)
            #expect(Data(view.string.utf8) == Data(source.utf8))
            #expect(!view.isEditable && view.isSelectable && !view.isRichText)
            #expect(view.accessibilityRole() == .textArea)
            #expect((view.accessibilityValue() as? String).map { Data($0.utf8) } == Data(source.utf8))
            #expect(view.font == ScholiumChatAppearance.messageNSFont)
            let attributes = try #require(view.textStorage?.attributes(at: 0, effectiveRange: nil))
            #expect(attributes[.font] as? NSFont == ScholiumChatAppearance.messageNSFont)
            let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
            let lineHeight =
                ScholiumChatAppearance.messageNSFont.pointSize * ScholiumChatAppearance.messageLineHeight
            #expect(
                paragraph.minimumLineHeight == lineHeight && paragraph.maximumLineHeight == lineHeight)
            appearance.performAsCurrentDrawingAppearance {
                #expect(
                    view.textColor?.usingColorSpace(.deviceRGB)
                        == NSColor.labelColor.usingColorSpace(.deviceRGB))
                #expect(
                    (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.deviceRGB)
                        == NSColor.labelColor.usingColorSpace(.deviceRGB))
            }
            // Exercise NSTextView's selected Copy serialization without replacing
            // the researcher's general pasteboard. Use the formats advertised
            // by AppKit for this selection, as its native Copy mechanism does.
            let writableTypes = view.writablePasteboardTypes
            try #require(!writableTypes.isEmpty)
            pasteboard.clearContents()
            try #require(pasteboard.string(forType: .string) == nil)
            try #require(view.writeSelection(to: pasteboard, types: writableTypes))
            let copied = try #require(pasteboard.string(forType: .string))
            #expect(Data(copied.utf8) == Data(selected.utf8))
            #expect(view.selectedRange() == range)
        }

        // Swift String equality considers these equivalent; the source owner must
        // still install the exact newly supplied byte representation.
        let composed = source.precomposedStringWithCanonicalMapping
        try #require(Data(composed.utf8) != Data(source.utf8))
        view.configure(
            source: composed, revision: "composed", fitsContent: true, isInteractive: true,
            onInteraction: {}, onLayout: { _, _ in })
        #expect(Data(view.string.utf8) == Data(composed.utf8))
        view.configure(
            source: source, revision: "decomposed", fitsContent: true, isInteractive: true,
            onInteraction: {}, onLayout: { _, _ in })
        #expect(Data(view.string.utf8) == Data(source.utf8))
    }

    @Test(
        "Intrinsic width hugs short prose, narrow prose wraps, and measurement probes leave live selection and layout untouched"
    )
    func sizingProbesDoNotMutateLiveText() throws {
        let fixture = NativeFixture()
        defer { fixture.close() }
        let view = fixture.view
        var interactions = 0
        view.configure(
            source: "中文 e\u{301} 😀", revision: "short", fitsContent: true, isInteractive: true,
            onInteraction: { interactions += 1 }, onLayout: { _, _ in })
        let short = view.fittingSize(proposedWidth: 340)
        #expect(short.width > 0 && short.width < 340)
        let source = String(repeating: "Mixed 中文 👩‍🔬 e\u{301} prose wraps safely. ", count: 30)
        view.configure(
            source: source, revision: "long", fitsContent: true, isInteractive: true,
            onInteraction: { interactions += 1 }, onLayout: { _, _ in })
        let narrow = view.fittingSize(proposedWidth: 90)
        let wide = view.fittingSize(proposedWidth: 300)
        #expect(narrow.width <= 90 && wide.width <= 300)
        #expect(narrow.height > wide.height && wide.height > short.height)
        view.frame.size = CGSize(width: 240, height: view.fittingSize(proposedWidth: 240).height)
        view.layout()
        let container = try #require(view.textContainer)
        let layout = try #require(view.layoutManager)
        layout.ensureLayout(for: container)
        view.setSelectedRange(NSRange(location: 6, length: 2))
        let selection = view.selectedRanges
        let frame = view.frame
        let containerSize = container.containerSize
        let used = layout.usedRect(for: container)
        let interactionCount = interactions

        let proposals: [CGFloat?] = [nil, 0, -1, .nan, .infinity, 40, 90, 600]
        for width in proposals {
            let proposed = view.fittingSize(proposedWidth: width)
            #expect(
                proposed.width.isFinite && proposed.height.isFinite && proposed.width > 0
                    && proposed.height > 0)
            #expect(view.frame == frame && container.containerSize == containerSize)
            #expect(layout.usedRect(for: container) == used && view.selectedRanges == selection)
            #expect(Data(view.string.utf8) == Data(source.utf8) && interactions == interactionCount)
        }
        view.configure(
            source: "Short", revision: "fill", fitsContent: false, isInteractive: true, onInteraction: {},
            onLayout: { _, _ in })
        #expect(view.fittingSize(proposedWidth: 300).width == 300)
    }

    @Test(
        "Only the current visible attached layout reports readiness, including same-sized source revisions"
    )
    func layoutReceiptsFollowRevisionAndLifetime() async throws {
        let fixture = NativeFixture()
        defer { fixture.close() }
        let view = fixture.view
        var reports: [(String, CGSize)] = []
        func configure(_ source: String, _ revision: String) {
            view.configure(
                source: source, revision: revision, fitsContent: false, isInteractive: true,
                onInteraction: {}, onLayout: { reports.append(($0, $1)) })
            view.layout()
        }
        configure("原文 一", "first")
        configure("原文 二", "second")
        await mainTurn()
        #expect(reports.map(\.0) == ["second"])
        #expect(reports.first?.1 == view.bounds.size)
        let count = reports.count
        _ = view.fittingSize(proposedWidth: 40)
        _ = view.fittingSize(proposedWidth: 500)
        await mainTurn()
        #expect(reports.count == count)
        configure("Hidden revision", "hidden")
        view.isHidden = true
        await mainTurn()
        #expect(reports.count == count)
        view.isHidden = false
        configure("Detached revision", "detached")
        view.detach()
        await mainTurn()
        #expect(reports.count == count)
    }

    @Test(
        "Hidden or disabled paragraphs relinquish focus and input authority while retaining reading selection",
        arguments: [false, true])
    func inactiveParagraphIsInert(hidden: Bool) throws {
        let fixture = NativeFixture()
        defer { fixture.close() }
        let view = fixture.view
        let source = "Native 中文 e\u{301} selection."
        var interactions = 0
        func configure(_ interactive: Bool) {
            view.configure(
                source: source, revision: "same", fitsContent: false, isInteractive: interactive,
                onInteraction: { interactions += 1 }, onLayout: { _, _ in })
        }
        configure(true)
        view.setSelectedRange(NSRange(location: 7, length: 2))
        try #require(fixture.window.makeFirstResponder(view))
        let selection = view.selectedRanges
        if hidden { view.isHidden = true } else { configure(false) }
        let count = interactions
        #expect(fixture.window.firstResponder !== view)
        #expect(!view.isSelectable && !view.acceptsFirstResponder)
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
        view.setAccessibilitySelectedTextRange(NSRange(location: 0, length: 1))
        view.setAccessibilitySelectedTextRanges([NSValue(range: NSRange(location: 1, length: 1))])
        view.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: view))
        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: fixture.window.windowNumber, context: nil, characters: "x",
                charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
        view.keyDown(with: key)
        #expect(view.selectedRanges == selection && interactions == count)
        #expect(Data(view.string.utf8) == Data(source.utf8))
        view.isHidden = false
        configure(true)
        #expect(view.isSelectable && view.acceptsFirstResponder)
        view.setAccessibilitySelectedTextRange(NSRange(location: 0, length: 2))
        #expect(view.selectedRange() == NSRange(location: 0, length: 2) && interactions > count)
    }

    @Test("Native paragraphs obey active, preparing and retained surface visibility without hiding disabled text")
    func surfaceVisibilityControlsCompositingAndAccessibility() async throws {
        _ = NSApplication.shared
        let source = "Native 中文 e\u{301} selection."
        var interactions = 0
        var reports: [(String, CGSize)] = []
        func paragraph(
            _ visibility: DocumentSurfaceVisibility, revision: String, source: String,
            interactive: Bool = true
        ) -> some View {
            AgentChatNativeParagraph(
                source: source, revision: revision, fitsContent: false, isInteractive: interactive,
                onInteraction: { interactions += 1 }, onLayout: { reports.append(($0, $1)) }
            )
            .environment(\.scholiumDocumentSurfaceVisibility, visibility)
            .frame(width: 240)
        }
        let host = NSHostingView(rootView: paragraph(.active, revision: "active", source: source))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) {
            reports.last?.0 == "active"
                && self.descendants(AgentChatNativeParagraphView.self, in: host).first?.isSelectable == true
        }
        let view = try #require(descendants(AgentChatNativeParagraphView.self, in: host).first)
        #expect(!view.isHidden && !view.isAccessibilityHidden())
        #expect(reports.last?.1 == view.bounds.size)
        view.setSelectedRange(NSRange(location: 7, length: 2))
        try #require(window.makeFirstResponder(view))
        let selection = view.selectedRanges
        let count = interactions

        host.rootView = paragraph(.preparing, revision: "preparing", source: source)
        try await settle(host) { reports.last?.0 == "preparing" && view.isAccessibilityHidden() }
        #expect(!view.isHidden && view.bounds.width > 0 && view.bounds.height > 0)
        #expect(reports.last?.1 == view.bounds.size)
        #expect(!view.isSelectable && !view.acceptsFirstResponder && window.firstResponder !== view)
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
        view.setAccessibilitySelectedTextRange(NSRange(location: 0, length: 1))
        #expect(view.selectedRanges == selection && interactions == count)

        host.rootView = paragraph(.retained, revision: "retained", source: source)
        try await settle(host) { view.isHidden && view.isAccessibilityHidden() }
        view.layout()
        await mainTurn()
        #expect(!reports.contains { $0.0 == "retained" })
        #expect(!view.isSelectable && !view.acceptsFirstResponder && window.firstResponder !== view)
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
        view.setAccessibilitySelectedTextRanges([NSValue(range: NSRange(location: 0, length: 1))])
        #expect(view.selectedRanges == selection && interactions == count)
        #expect(Data(view.string.utf8) == Data(source.utf8))

        let wrapped = String(repeating: source + " ", count: 8)
        host.rootView = paragraph(.preparing, revision: "prepared-resize", source: wrapped)
        try await settle(host) { reports.last?.0 == "prepared-resize" && !view.isHidden }
        #expect(view.isAccessibilityHidden() && !view.isSelectable && !view.acceptsFirstResponder)
        #expect(reports.last?.1 == view.bounds.size)
        #expect(Data(view.string.utf8) == Data(wrapped.utf8))
        let container = try #require(view.textContainer)
        let layout = try #require(view.layoutManager)
        layout.ensureLayout(for: container)
        #expect(abs(container.containerSize.width - view.bounds.width) <= 1)
        #expect(abs(ceil(layout.usedRect(for: container).height) - view.bounds.height) <= 1)

        host.rootView = paragraph(.active, revision: "disabled", source: wrapped, interactive: false)
        try await settle(host) { reports.last?.0 == "disabled" && !view.isAccessibilityHidden() }
        #expect(!view.isHidden && !view.isSelectable && !view.acceptsFirstResponder)
        #expect(view.hitTest(NSPoint(x: 5, y: 5)) == nil)
        host.rootView = paragraph(.active, revision: "active-again", source: wrapped)
        try await settle(host) { reports.last?.0 == "active-again" && view.isSelectable }
        #expect(descendants(AgentChatNativeParagraphView.self, in: host).first === view)
        #expect(!view.isHidden && !view.isAccessibilityHidden() && view.acceptsFirstResponder)
        #expect(Data(view.string.utf8) == Data(wrapped.utf8))
        #expect(reports.allSatisfy { $0.1.width.isFinite && $0.1.height.isFinite && $0.1.width > 0 && $0.1.height > 0 })
    }

    @MainActor private final class Input: ObservableObject {
        @Published var source: ScholiumExactUTF8.SourceIdentity
        init(_ source: String) { self.source = .init(source) }
    }

    @MainActor private struct Reply: View {
        @ObservedObject var input: Input
        let session: AgentChatReadingSession
        let presentationID: UUID
        var allowsNativeParagraph = true
        var quoteEnabled = false
        var isStreaming = false

        var body: some View {
            AgentChatReadReply(
                source: input.source.source, readerID: "native-reply", isStreaming: isStreaming,
                quote: quoteEnabled ? { _ in } : nil, openLink: { _ in },
                allowsNativeParagraph: allowsNativeParagraph
            )
            .environment(\.chatReadingPresentation, .init(id: presentationID, session: session))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @MainActor private final class ReplyFixture {
        let session: AgentChatReadingSession
        let presentationID: UUID
        let host: NSHostingView<Reply>
        let window: NSWindow

        init(
            input: Input, allowsNativeParagraph: Bool = true, quoteEnabled: Bool = false,
            isStreaming: Bool = false
        ) {
            _ = NSApplication.shared
            let readingSession = AgentChatReadingSession()
            let presentation = UUID()
            session = readingSession
            presentationID = presentation
            readingSession.beginPresentation(presentation)
            let replyHost = NSHostingView(
                rootView: Reply(
                    input: input, session: readingSession, presentationID: presentation,
                    allowsNativeParagraph: allowsNativeParagraph,
                    quoteEnabled: quoteEnabled, isStreaming: isStreaming))
            replyHost.sizingOptions = []
            host = replyHost
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 320), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        func close() {
            session.endPresentation(presentationID)
            window.contentView = nil
            window.close()
        }
    }

    @Test(
        "The real host hydrates native same-sized revisions and both native/WebKit transitions with current source"
    )
    func hostHydrationAndRendererTransitions() async throws {
        let first = "原文 中文 e\u{301} 一"
        let input = Input(first)
        let fixture = ReplyFixture(input: input)
        defer { fixture.close() }
        try await settle(fixture.host) {
            self.nativeReady(in: fixture, source: first)
        }
        let native = try #require(
            descendants(AgentChatNativeParagraphView.self, in: fixture.host).first)
        let size = native.frame.size
        #expect(descendants(WKWebView.self, in: fixture.host).isEmpty)
        let second = "原文 中文 e\u{301} 二"
        input.source = .init(second)
        try await settle(fixture.host) { self.nativeReady(in: fixture, source: second) }
        #expect(descendants(AgentChatNativeParagraphView.self, in: fixture.host).first === native)
        #expect(
            abs(native.frame.height - size.height) <= 1 && abs(native.frame.width - size.width) <= 1)

        let rich = "**Rich 中文 e\u{301}** with [source](https://example.com)."
        input.source = .init(rich)
        try await settle(fixture.host) {
            fixture.session.areReadersHydrated(["native-reply"])
                && self.descendants(AgentChatNativeParagraphView.self, in: fixture.host).isEmpty
                && self.descendants(WKWebView.self, in: fixture.host).contains {
                    self.webSource($0, matches: rich)
                }
        }
        let web = try #require(descendants(WKWebView.self, in: fixture.host).first)
        #expect(
            try await web.evaluateJavaScript(
                "document.querySelector('#scholium-document strong')?.textContent") as? String
                == "Rich 中文 e\u{301}")
        let final = "最终 中文 👩‍🔬 e\u{301} 原文"
        input.source = .init(final)
        try await settle(fixture.host) {
            self.nativeReady(in: fixture, source: final)
                && self.descendants(WKWebView.self, in: fixture.host).isEmpty
        }
        #expect(Data(input.source.source.utf8) == Data(final.utf8))
    }

    @Test(
        "Plain text stays in WebKit without opt-in, with quoting, or while streaming",
        arguments: ["no-opt-in", "quote", "streaming"])
    func webKitRoutesRemainAvailable(route: String) async throws {
        let source = "Plain 中文 e\u{301} 👩‍🔬 source."
        let input = Input(source)
        let fixture = ReplyFixture(
            input: input, allowsNativeParagraph: route != "no-opt-in", quoteEnabled: route == "quote",
            isStreaming: route == "streaming")
        defer { fixture.close() }
        try await settle(fixture.host) {
            fixture.session.areReadersHydrated(["native-reply"])
                && self.descendants(WKWebView.self, in: fixture.host).contains {
                    self.webSource($0, matches: source)
                }
        }
        #expect(descendants(AgentChatNativeParagraphView.self, in: fixture.host).isEmpty)
    }

    private func nativeReady(in fixture: ReplyFixture, source: String) -> Bool {
        fixture.session.areReadersHydrated(["native-reply"])
            && descendants(AgentChatNativeParagraphView.self, in: fixture.host).contains {
                $0.isSelectable && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0
                    && $0.bounds.height > 0
                    && Data($0.string.utf8) == Data(source.utf8)
            }
    }

    private func webSource(_ web: WKWebView, matches source: String) -> Bool {
        guard let coordinator = web.navigationDelegate as? SafeMarkdownReadWebView.Coordinator,
            let current = Mirror(reflecting: coordinator).children.first(where: {
                $0.label == "selectionSource"
            })?.value as? String
        else { return false }
        return Data(current.utf8) == Data(source.utf8)
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func mainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func settle(_ host: NSView, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(
                ContinuousClock.now < deadline,
                "The current Chat renderer did not complete real source-bound hydration")
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
