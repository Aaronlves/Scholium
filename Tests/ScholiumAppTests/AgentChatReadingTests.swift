import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat reading continuity", .serialized) @MainActor
struct AgentChatReadingTests {
    @Test("Reply pointer selection reaches WebKit through message actions and supports native Copy")
    func nativeReplyPointerSelectionAndCopy() async throws {
        _ = NSApplication.shared
        let host = NSHostingView(
            rootView:
                AgentChatMessageActionVisibility {
                    AgentChatMessageSurface(isUser: false) {
                        AgentChatReadReply(
                            source: "Alpha **selection** remains intact.\n\nSecond paragraph.",
                            quote: { _ in }, openLink: { _ in })
                    }
                } actions: {
                    Button("Copy Markdown") {}
                        .contextMenu { Button("Quote in Reply") {} }
                }
                .padding(20)
                .frame(width: 480, height: 240, alignment: .topLeading))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        func reader(in view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader(in: $0) }.first
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var points: [String: Double]?
        var mountedReader: WKWebView?
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if let webView = reader(in: host) {
                mountedReader = webView
                // Read geometry only: selection must be created by native pointer events.
                points =
                    try await webView.callAsyncJavaScript(
                        """
                        const paragraph = document.querySelector('#scholium-document p');
                        const emphasis = paragraph?.querySelector('strong');
                        if (!paragraph || !emphasis) return null;
                        const start = document.createRange();
                        start.setStart(paragraph.firstChild, 0);
                        start.setEnd(paragraph.firstChild, 1);
                        const first = start.getBoundingClientRect();
                        const last = emphasis.getBoundingClientRect();
                        if (!first.width || !last.width) return null;
                        return {startX: first.left + 0.5, startY: first.top + first.height / 2,
                            endX: last.right - 0.5, endY: last.top + last.height / 2};
                        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Double]
                if points != nil { break }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try #require(mountedReader)
        let geometry = try #require(points)
        func point(_ prefix: String) throws -> NSPoint {
            let x = try #require(geometry[prefix + "X"])
            let y = try #require(geometry[prefix + "Y"])
            return webView.convert(NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y), to: nil)
        }
        let start = try point("start")
        let end = try point("end")
        let hit = try #require(host.hitTest(start))
        try #require(hit === webView || hit.isDescendant(of: webView))
        let timestamp = ProcessInfo.processInfo.systemUptime
        for step in 0...9 {
            let fraction = min(Double(step) / 8, 1)
            let location = NSPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            let type: NSEvent.EventType = step == 0 ? .leftMouseDown : step == 9 ? .leftMouseUp : .leftMouseDragged
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: location, modifierFlags: [], timestamp: timestamp + Double(step) * 0.025,
                    windowNumber: window.windowNumber, context: nil, eventNumber: step, clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1))
            // SwiftPM's host has no key application window. Resolve the real
            // native recipient through the complete SwiftUI hierarchy first.
            switch type {
            case .leftMouseDown: hit.mouseDown(with: event)
            case .leftMouseDragged: hit.mouseDragged(with: event)
            default: hit.mouseUp(with: event)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let selectionDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        var selected = ""
        repeat {
            selected = try await webView.evaluateJavaScript("window.getSelection().toString()") as? String ?? ""
            if selected == "Alpha selection" { break }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < selectionDeadline
        try #require(selected == "Alpha selection")

        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let items = savedItems.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        pasteboard.clearContents()
        #expect(NSApp.sendAction(#selector(NSText.copy(_:)), to: window.firstResponder, from: nil))
        let copyDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while pasteboard.string(forType: .string) != selected && ContinuousClock.now < copyDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(pasteboard.string(forType: .string) == selected)
        let transfer = try #require(
            try await webView.callAsyncJavaScript(
                """
                const range = window.getSelection().getRangeAt(0);
                const rect = range.getClientRects()[0];
                const data = new DataTransfer();
                const root = document.getElementById('scholium-document');
                const x = rect.left + 1, y = rect.top + rect.height / 2;
                const target = document.elementFromPoint(x, y);
                target.dispatchEvent(new MouseEvent('mousedown', {bubbles: true, cancelable: true,
                    button: 0, buttons: 1, detail: 1, clientX: x, clientY: y}));
                const rootIsNative = !root.hasAttribute('draggable');
                let dragImageCalls = 0;
                Object.defineProperty(data, 'setDragImage', {value: () => { dragImageCalls++; }});
                const previewObserver = new MutationObserver(() => {});
                previewObserver.observe(document.body, {childList: true});
                // Verify the DOM payload contract without asserting the system's
                // physical gesture recognition or native drag-image timing.
                root.dispatchEvent(new DragEvent('dragstart', {bubbles: true, cancelable: true,
                    dataTransfer: data, clientX: x, clientY: y}));
                const previewNodes = previewObserver.takeRecords()
                    .reduce((count, record) => count + record.addedNodes.length, 0);
                previewObserver.disconnect();
                const nativeDuringDrag = !root.hasAttribute('draggable');
                root.dispatchEvent(new DragEvent('dragend', {bubbles: true}));
                return {text: data.getData('text/plain'),
                    selected: window.getSelection().toString(), types: Array.from(data.types).join(','),
                    rootIsNative: String(rootIsNative), nativeDuringDrag: String(nativeDuringDrag),
                    dragImageCalls: String(dragImageCalls), previewNodes: String(previewNodes),
                    rootStillNative: String(!root.hasAttribute('draggable'))};
                """, arguments: [:], in: nil, contentWorld: .page) as? [String: String])
        #expect(transfer["text"] == selected)
        #expect(transfer["selected"] == selected)
        #expect(transfer["types"] == "text/plain")
        #expect(transfer["rootIsNative"] == "true")
        #expect(transfer["nativeDuringDrag"] == "true")
        #expect(transfer["rootStillNative"] == "true")
        #expect(transfer["dragImageCalls"] == "0")
        #expect(transfer["previewNodes"] == "0")
    }

    @Test("History navigation loads the target without discarding source or reversing page order")
    func historyWindow() {
        let ids = (0..<300).map(String.init)
        var window = AgentChatHistoryWindow()
        #expect(window.range(in: ids) == 276..<300)
        window.reveal("80", in: ids)
        #expect(window.range(in: ids).contains(80))
        #expect(window.range(in: ids).count == AgentChatHistoryWindow.pageSize)
        let end = window.range(in: ids).upperBound
        window.earlier(in: ids)
        #expect(window.range(in: ids).upperBound == end)
        #expect(window.range(in: ids).count == 48)
        window.later(in: ids)
        #expect(window.range(in: ids).count == 72)
        window.latest(in: ids)
        #expect(window.range(in: ids) == 276..<300)
        #expect(window.range(in: []).isEmpty)
    }

    @Test("Independent conversations retain reading and disclosure choices")
    func independentSessions() {
        let store = AgentChatReadingStore()
        let a = UUID()
        let b = UUID()
        let session = store.session(for: a)
        session.anchor = .init(id: "old-answer", offset: -170)
        session.pause()
        session.expandedActivities.insert("tool")
        session.processExpansions["turn"] = false
        #expect(store.session(for: b).anchor == nil)
        #expect(store.session(for: a) === session)
        #expect(store.session(for: a).anchor == .init(id: "old-answer", offset: -170))
        #expect(store.session(for: a).expandedActivities.contains("tool"))
        #expect(store.session(for: a).processExpansions["turn"] == false)
    }

    @Test("Native reading anchor survives earlier row reflow and viewport reattachment")
    func nativeAnchor() async throws {
        let session = AgentChatReadingSession()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        final class Document: NSView { override var isFlipped: Bool { true } }
        let document = Document(frame: NSRect(x: 0, y: 0, width: 300, height: 1600))
        scroll.documentView = document
        let viewport = AgentChatTranscriptViewport.View(session: session)
        document.addSubview(viewport)
        let marker = AgentChatReadingMarker.View(id: "answer", session: session)
        marker.frame = NSRect(x: 0, y: 700, width: 300, height: 600)
        document.addSubview(marker)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer {
            window.contentView = nil
            window.close()
        }
        session.pause()
        session.anchor = .init(id: "answer", offset: -120)
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.minY - 820) < 1)
        marker.setFrameOrigin(NSPoint(x: 0, y: 950))
        document.setFrameSize(NSSize(width: 300, height: 1850))
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.minY - 1070) < 1)
        viewport.detach()
        viewport.viewDidMoveToWindow()
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.minY - 1070) < 1)
        session.latest(in: ["answer"])
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.maxY - document.frame.height) < 1)
    }

    @Test("A jump mounts older history and restores its actual native reading anchor")
    func jumpToUnloadedHistory() async throws {
        let session = AgentChatReadingSession()
        let ids = (0..<90).map(String.init)
        struct Fixture: View {
            let session: AgentChatReadingSession
            let ids: [String]
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(Array(ids[session.history.range(in: ids)]), id: \.self) { id in
                            Text("Retained question \(id)").frame(height: 100)
                                .background(AgentChatReadingMarker(id: id, session: session))
                        }
                    }.background(AgentChatTranscriptViewport(session: session))
                }
            }
        }
        let host = NSHostingView(rootView: Fixture(session: session, ids: ids))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func settle(_ id: String) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while session.markers[id]?.view == nil && ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            }
            try #require(session.markers[id]?.view != nil)
            host.layoutSubtreeIfNeeded()
            session.viewport?.reconcile()
        }
        try await settle("89")
        #expect(session.markers["5"]?.view == nil)
        session.navigate(to: "5", in: ids)
        try await settle("5")
        let marker = try #require(session.markers["5"]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        let document = try #require(scroll.documentView)
        #expect(abs(marker.convert(marker.bounds, to: document).minY - scroll.contentView.bounds.minY) < 1)
        #expect(session.isPaused)
        #expect(session.markers["89"]?.view == nil)
        session.latest(in: ids)
        try await settle("89")
        #expect(!session.isPaused)
        #expect(!session.isAwayFromLatest)
    }

    @Test("All named reply actions fit the narrow reading grid without clipping controls")
    func compactReplyActions() {
        let material = AgentChatLocalMaterial(
            id: UUID(), source: .file(URL(fileURLWithPath: "/synthetic/paper.pdf")),
            storedFileName: "snapshot.pdf", fingerprint: DocumentFingerprint(content: "fixture"), kind: .pdf)
        var input = AgentChatMessage(role: .user, text: "Discuss", localMaterials: [material])
        input.turnID = "turn"
        var reply = AgentChatMessage(role: .assistant, text: "[Source](https://example.org/paper)")
        reply.turnID = "turn"
        let host = NSHostingView(
            rootView: HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                AgentChatReplyActions(
                    text: reply.text, openNote: { _ in },
                    context: .init(reply: reply, history: [input, reply]), openAttachment: { _ in },
                    previewMaterial: { _ in URL(fileURLWithPath: "/synthetic/paper.pdf") })
                Group {
                    Button("Branch from This Turn", systemImage: "arrow.triangle.branch") {}
                    Button("Retry in New Branch", systemImage: "arrow.clockwise") {}
                    Button("Quote in Reply", systemImage: "text.quote") {}
                }.labelStyle(ScholiumSidebarActionLabelStyle())
            }.buttonStyle(.borderless).environment(\.locale, Locale(identifier: "zh-Hans")).fixedSize())
        #expect(host.fittingSize.width <= 260 - 2 * ScholiumSidebarLayout.textInset)
        #expect(host.fittingSize.height >= ScholiumGrid.Dimension.preferredCustomTarget)
    }

    @Test("Synthetic history mount cost", .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
    func historyMeasurement() async throws {
        let ids = (0..<72).map(String.init)
        for paged in [false, true] {
            let range = paged ? AgentChatHistoryWindow().range(in: ids) : ids.indices
            let start = ContinuousClock.now
            let host = NSHostingView(
                rootView: ScrollView {
                    VStack {
                        ForEach(Array(ids[range]), id: \.self) { id in
                            AgentChatMarkdown(text: "Question \(id)\n\nA synthetic paragraph with **emphasis** and 中文.")
                        }
                    }
                })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            func readers(_ view: NSView) -> [WKWebView] {
                (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(readers)
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while readers(host).count != range.count && ContinuousClock.now < deadline {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(readers(host).count == range.count)
            print("CHAT_HISTORY_MOUNT paged=\(paged) readers=\(readers(host).count) elapsed=\(start.duration(to: .now))")
            window.contentView = nil
            window.close()
        }
    }

    @Test("Synthetic projection baseline", .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
    func projectionBaseline() {
        let body = String(repeating: "A source-faithful paragraph with **emphasis**, 中文 and `code`.\n\n", count: 70)
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<80 {
            let result = SafeMarkdownRenderer.render(NoteDocument(relativePath: "Reply.md", rawContent: body + String(repeating: "尾", count: i)))
            #expect(!result.htmlBody.isEmpty)
        }
        print("CHAT_PROJECTION_BASELINE snapshots=80 elapsed=\(start.duration(to: clock.now))")
    }
}
