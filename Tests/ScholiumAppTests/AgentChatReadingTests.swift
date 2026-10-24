import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat reading continuity", .serialized) @MainActor
struct AgentChatReadingTests {
    @Test("Reply pointer selection reaches WebKit through message actions and keeps native Copy available")
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
                    AgentChatActionButton(label: "Copy Markdown", systemImage: "doc.on.doc") {}
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
            // A prepared DOM can have geometry before its measured native
            // surface is published. Exercise the real interaction boundary.
            if let webView = reader(in: host) as? AgentChatReadWebView, webView.isChatInteractive {
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

        // Keep command availability in this pointer/selection proof. Executing
        // system Copy would read or replace the researcher's clipboard.
        let responder = try #require(window.firstResponder)
        #expect(responder.responds(to: #selector(NSText.copy(_:))))
        #expect(webView.validateUserInterfaceItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")))
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
        #expect(window.range(in: ids) == 296..<300)
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
        #expect(window.range(in: ids) == 296..<300)
        #expect(window.range(in: []).isEmpty)
    }

    @Test("Initial hydration follows the mounted window when a new reply evicts its first reader", arguments: [false, true])
    func initialHydrationTracksMountedReaders(initiallyReady: Bool) throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        let initialIDs = ["a", "b", "c", "d"]
        session.mount(in: initialIDs, readerIDs: Set(initialIDs))
        let readers = initialIDs.map { id in
            let reader = AgentChatReadReply.Readiness()
            reader.mount(in: session, readerID: id, presentationID: presentationID)
            reader.ready = id != "a" || initiallyReady
            reader.hasMeasuredLayout = true
            return reader
        }
        #expect(session.initialTranscriptPhase == (initiallyReady ? .positioning : .hydrating))

        let updatedIDs = initialIDs + ["e"]
        session.contentDidChange(in: updatedIDs, readerIDs: Set(updatedIDs))
        #expect(session.history.range(in: updatedIDs) == 1..<5)
        #expect(session.initialTranscriptPhase == .hydrating)

        // The evicted reader never reports readiness again. The newly mounted
        // reader still has to finish before the transcript can become visible.
        readers[0].unmount()
        let latest = AgentChatReadReply.Readiness()
        latest.mount(in: session, readerID: "e", presentationID: presentationID)
        latest.ready = true
        #expect(session.initialTranscriptPhase == .hydrating)
        latest.hasMeasuredLayout = true
        #expect(session.initialTranscriptPhase == .positioning)
        session.acknowledge(try #require(session.viewportRequest))
        #expect(session.isInitialTranscriptReady)
        #expect(session.viewportRequest == nil)
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

    @Test("Returning to a conversation restores its loaded process extent and reading anchor")
    func retainedProcessWindow() {
        let store = AgentChatReadingStore()
        let a = UUID()
        let b = UUID()
        let processID = "activity-0"
        var messages = (0..<100).map {
            AgentChatMessage(id: "activity-\($0)", role: .operation, text: "Synthetic activity")
        }
        let session = store.session(for: a)
        session.processWindows[processID, default: .init()].reconcile(in: messages, preservesReading: false)
        session.pause()
        session.processWindows[processID, default: .init()].earlier(in: messages)
        session.processExpansions[processID] = true
        session.anchor = .init(id: processID, offset: -170)

        let other = store.session(for: b)
        other.processWindows[processID, default: .init()].reconcile(in: messages, preservesReading: false)
        #expect(other.processWindows[processID]?.first == "activity-68")
        #expect(other.anchor == nil)

        // A replaced detail view remounts against the conversation's existing
        // window, including activity received while another conversation was open.
        messages.append(.init(id: "activity-100", role: .operation, text: "New activity"))
        let returned = store.session(for: a)
        returned.processWindows[processID, default: .init()].reconcile(in: messages, preservesReading: returned.isRetainingPosition)
        returned.beginPresentation(UUID())
        returned.mount(in: [processID])
        #expect(returned === session)
        #expect(returned.processWindows[processID]?.indices(messages: messages, inspectedIDs: []) == Array(36..<101))
        #expect(returned.processExpansions[processID] == true)
        #expect(returned.anchor == .init(id: processID, offset: -170))
        #expect(returned.viewportRequest?.target == .anchor(.init(id: processID, offset: -170)))
        #expect(other.processWindows[processID]?.first == "activity-68")

        returned.reachedLatestFromViewport()
        returned.processWindows[processID, default: .init()].reconcile(in: messages, preservesReading: returned.isRetainingPosition)
        #expect(
            returned.processWindows[processID]?.indices(messages: messages, inspectedIDs: []) == Array(36..<101),
            "Ordinary scrolling cannot discard explicitly loaded activity or move its disclosure headers")
        #expect(returned.processExpansions[processID] == true)

        returned.latest(in: [processID])
        returned.processWindows[processID, default: .init()].reconcile(in: messages, preservesReading: returned.isRetainingPosition)
        #expect(returned.processWindows[processID]?.indices(messages: messages, inspectedIDs: []) == Array(69..<101))
    }

    @Test("Native reading anchor survives earlier row reflow and viewport reattachment")
    func nativeAnchor() async throws {
        let fixture = NativeReadingFixture()
        defer { fixture.close() }
        let session = fixture.session
        let scroll = fixture.scroll
        let document = fixture.document
        let viewport = fixture.viewport
        let marker = fixture.marker
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
        session.navigate(to: "answer", in: ["answer"])
        viewport.capture()
        #expect(session.anchor == .init(id: "answer", offset: 0))
        #expect(session.viewportRequest?.target == .anchor(.init(id: "answer", offset: 0)))
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.minY - 950) < 1)
        #expect(session.viewportRequest == nil)
        session.latest(in: ["answer"])
        viewport.capture()
        #expect(session.viewportRequest?.target == .latest)
        viewport.reconcile()
        #expect(abs(scroll.contentView.bounds.maxY - document.frame.height) < 1)
        #expect(session.viewportRequest == nil)
    }

    @Test("Idle reading survives internal row reflow without a document-size change")
    func nativeInternalReflow() async throws {
        let anchor = AgentChatReadingSession.Anchor(id: "answer", offset: -120)
        let fixture = NativeReadingFixture(anchor: anchor)
        defer { fixture.close() }
        try await waitForNativeReading(fixture, stage: "initial internal reflow anchor") {
            fixture.session.isInitialTranscriptReady && fixture.session.viewportRequest == nil
                && fixture.session.anchor == anchor && fixture.matches(anchor)
        }
        let documentSize = fixture.document.frame.size
        #expect(abs(fixture.scroll.contentView.bounds.minY - 820) < 1)

        // Earlier replies can exchange height while the transcript's total
        // height stays unchanged. Only the real marker layout notifies the owner.
        fixture.marker.setFrameOrigin(NSPoint(x: 0, y: 950))
        fixture.marker.needsLayout = true
        try await waitForNativeReading(fixture, stage: "internal row reflow") {
            fixture.session.viewportRequest == nil && fixture.session.anchor == anchor
                && fixture.matches(anchor)
                && abs(fixture.scroll.contentView.bounds.minY - 1070) < 1
        }
        #expect(fixture.document.frame.size == documentSize)
        #expect(!fixture.session.isScrolling && !fixture.window.isVisible)
    }

    @Test("Native geometry changes capture active scrolling and preserve idle reading", arguments: [false, true])
    func nativeGeometryChanges(activeGesture: Bool) async throws {
        for changesDock in [false, true] {
            let initialAnchor = AgentChatReadingSession.Anchor(id: "answer", offset: -120)
            let fixture = NativeReadingFixture(anchor: initialAnchor)
            defer { fixture.close() }
            let session = fixture.session
            let scroll = fixture.scroll
            let receipt = NativeBoundsReceipt()
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak receipt, weak clip = scroll.contentView] _ in
                MainActor.assumeIsolated {
                    guard let receipt, let clip else { return }
                    receipt.count += 1
                    receipt.lastY = clip.bounds.minY
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            try await waitForNativeReading(fixture, stage: "initial anchor") {
                session.isInitialTranscriptReady && session.viewportRequest == nil
                    && session.anchor == initialAnchor && fixture.matches(initialAnchor)
            }
            let initialY = scroll.contentView.bounds.minY
            let expectedTopInset = scroll.contentInsets.top + (changesDock ? 28 : 0)
            defer {
                #expect(scroll.contentInsets.top == expectedTopInset, "The fixture owns its inset throughout native layout")
            }
            let previousEvents = receipt.count
            if activeGesture { session.beginUserScroll() }

            if changesDock {
                var insets = scroll.contentInsets
                insets.top += 28
                scroll.contentInsets = insets
            } else {
                // A preceding reply grows without replacing this marker or the
                // viewport. This models asynchronous reader-height publication.
                fixture.marker.setFrameOrigin(NSPoint(x: 0, y: 820))
                fixture.document.setFrameSize(NSSize(width: 300, height: 1720))
            }

            if activeGesture {
                // Give geometry notifications their real dispatch turn before
                // continuing the gesture. Reconcile must not write this clip.
                await nativeMainQueueTurn()
                fixture.window.layoutIfNeeded()
                fixture.document.layoutSubtreeIfNeeded()
                await nativeMainQueueTurn()
                for tick in 0..<2 {
                    let oldY = scroll.contentView.bounds.minY
                    var bounds = scroll.contentView.bounds
                    bounds.origin.y += 18
                    let destination = scroll.contentView.constrainBoundsRect(bounds).origin
                    try #require(destination.y > oldY)
                    let beforeTick = receipt.count
                    scroll.contentView.scroll(to: destination)
                    scroll.reflectScrolledClipView(scroll.contentView)
                    // Neither capture nor settleUserPosition is called here:
                    // native bounds delivery must update the reading owner.
                    try await waitForNativeReading(fixture, stage: "active tick \(tick), dock=\(changesDock)") {
                        receipt.count > beforeTick && receipt.lastY.map { abs($0 - destination.y) < 1 } == true
                            && abs(scroll.contentView.bounds.minY - destination.y) < 1
                            && session.viewportRequest == nil && session.anchor.map(fixture.matches) == true
                    }
                    #expect(session.isScrolling && session.isRetainingPosition)
                    #expect(session.anchor?.id == initialAnchor.id)
                }
                // End the lifecycle only after both notification-owned captures
                // succeeded; ending must not conceal a missed active update.
                session.endUserScroll()
                try await waitForNativeReading(fixture, stage: "gesture ended") {
                    !session.isScrolling && session.viewportRequest == nil && session.anchor.map(fixture.matches) == true
                }
            } else {
                let expectedY = changesDock ? initialY - 28 : initialY + 120
                try await waitForNativeReading(fixture, stage: "idle geometry, dock=\(changesDock)") {
                    receipt.count > previousEvents && receipt.lastY.map { abs($0 - expectedY) < 1 } == true
                        && abs(scroll.contentView.bounds.minY - expectedY) < 1
                        && session.viewportRequest == nil && session.anchor == initialAnchor && fixture.matches(initialAnchor)
                }
                #expect(!session.isScrolling && session.isRetainingPosition)
                #expect(session.anchor == initialAnchor, "Idle layout must compensate the clip instead of replacing its semantic anchor")
            }
            #expect(session.ownsViewport(fixture.viewport))
            #expect(!fixture.window.isVisible)
        }
    }

    @Test("Phase-less native scrolling can cross a row and continue without being treated as reflow")
    func nativeScrollAcrossRows() async throws {
        let initial = AgentChatReadingSession.Anchor(id: "answer", offset: -120)
        let fixture = NativeReadingFixture(anchor: initial)
        defer { fixture.close() }
        fixture.document.setFrameSize(NSSize(width: 300, height: 2600))
        let next = AgentChatReadingMarker.View(id: "next-answer", session: fixture.session)
        next.frame = NSRect(x: 0, y: 1300, width: 300, height: 600)
        fixture.document.addSubview(next)
        try await waitForNativeReading(fixture, stage: "initial crossing anchor") {
            fixture.session.isInitialTranscriptReady && fixture.session.viewportRequest == nil
                && fixture.matches(initial)
        }
        await nativeMainQueueTurn()
        for y: CGFloat in [1305, 1323] {
            fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            fixture.scroll.reflectScrolledClipView(fixture.scroll.contentView)
            // Keyboard/accessibility input may have no trackpad gesture phase.
            // The native notifications alone must admit both movements.
            try await waitForNativeReading(fixture, stage: "phase-less crossing at \(y)") {
                fixture.session.anchor == .init(id: "next-answer", offset: 1300 - y)
                    && abs(fixture.scroll.contentView.bounds.minY - y) < 1
                    && fixture.session.viewportRequest == nil
            }
            #expect(!fixture.session.isScrolling)
        }
    }

    @MainActor private final class NativeReadingFixture {
        final class Document: NSView { override var isFlipped: Bool { true } }
        let session: AgentChatReadingSession
        let presentationID: UUID
        let scroll: NSScrollView
        let document: Document
        let viewport: AgentChatTranscriptViewport.View
        let marker: AgentChatReadingMarker.View
        let window: NSWindow

        init(anchor: AgentChatReadingSession.Anchor? = nil) {
            _ = NSApplication.shared
            let session = AgentChatReadingSession()
            let presentationID = UUID()
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            // This fixture drives dock insets; AppKit must not replace them
            // with the titled window's automatically calculated insets.
            scroll.automaticallyAdjustsContentInsets = false
            let document = Document(frame: NSRect(x: 0, y: 0, width: 300, height: 1600))
            let viewport = AgentChatTranscriptViewport.View(session: session, presentationID: presentationID)
            let marker = AgentChatReadingMarker.View(id: "answer", session: session)
            let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
            self.session = session
            self.presentationID = presentationID
            self.scroll = scroll
            self.document = document
            self.viewport = viewport
            self.marker = marker
            self.window = window
            session.anchor = anchor
            session.beginPresentation(presentationID)
            scroll.documentView = document
            document.addSubview(viewport)
            marker.frame = NSRect(x: 0, y: 700, width: 300, height: 600)
            document.addSubview(marker)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
        }

        func matches(_ anchor: AgentChatReadingSession.Anchor) -> Bool {
            let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
            let row = marker.convert(marker.bounds, to: document)
            return anchor.id == marker.id && abs(anchor.offset - (row.minY - top)) < 1
        }

        func close() {
            viewport.retire()
            session.endPresentation(presentationID)
            window.contentView = nil
            window.close()
        }
    }

    @MainActor private final class NativeBoundsReceipt {
        var count = 0
        var lastY: CGFloat?
    }

    private func nativeMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func waitForNativeReading(_ fixture: NativeReadingFixture, stage: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            await nativeMainQueueTurn()
            fixture.window.layoutIfNeeded()
            fixture.document.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(
            condition(),
            "Native reading did not settle at \(stage); clip=\(fixture.scroll.contentView.bounds), anchor=\(String(describing: fixture.session.anchor))")
    }

    @Test("A jump mounts older history and restores its actual native reading anchor")
    func jumpToUnloadedHistory() async throws {
        let session = AgentChatReadingSession()
        let presentationID = UUID()
        session.beginPresentation(presentationID)
        let ids = (0..<90).map(String.init)
        struct Fixture: View {
            let session: AgentChatReadingSession
            let ids: [String]
            let presentationID: UUID
            var body: some View {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(Array(ids[session.history.range(in: ids)]), id: \.self) { id in
                            Text("Retained question \(id)").frame(height: 100)
                                .background(AgentChatReadingMarker(id: id, session: session))
                        }
                    }.background(AgentChatTranscriptViewport(session: session, presentationID: presentationID))
                }
            }
        }
        let host = NSHostingView(rootView: Fixture(session: session, ids: ids, presentationID: presentationID))
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
        let latestMarker = try #require(session.markers["89"]?.view)
        let latestScroll = try #require(latestMarker.enclosingScrollView)
        let latestDocument = try #require(latestScroll.documentView)
        #expect(abs(latestScroll.contentView.bounds.maxY - latestDocument.frame.height) < 1)
        #expect(session.markers["5"]?.view == nil)
        session.navigate(to: "5", in: ids)
        try await settle("5")
        let marker = try #require(session.markers["5"]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        let document = try #require(scroll.documentView)
        #expect(abs(marker.convert(marker.bounds, to: document).minY - scroll.contentView.bounds.minY) < 1)
        #expect(session.isRetainingPosition)
        #expect(session.markers["89"]?.view == nil)
        session.latest(in: ids)
        try await settle("89")
        #expect(!session.isRetainingPosition)
        #expect(!session.isAwayFromLatest)
        #expect(abs(latestScroll.contentView.bounds.maxY - latestDocument.frame.height) < 1)
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
                    context: .init(reply: reply, history: [input, reply]), openAttachment: { _, _ in },
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
