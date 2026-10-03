import AppKit
import CoreText
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF floating tools", .serialized)
@MainActor
struct PDFReaderFloatingToolsTests {
    @Test("Quiet controls leave pointer and accessibility reading clear while native keyboard focus reveals them")
    func idlePreservesKeyboardReachability() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let (tools, window) = makeQuietTools(fixture.reader)
        defer {
            tools.invalidate()
            window.close()
        }
        let document = fixture.reader.document
        let select = try button("select", in: tools)
        let highlight = try button("highlight", in: tools)
        try await waitForIdle(tools)
        #expect(!tools.isHidden && tools.alphaValue == 0 && tools.isAccessibilityHidden())
        try assertAccessibilityProjection(tools, hidden: true)
        #expect(select.canBecomeKeyView)
        let host = try #require(window.contentView)
        let point = select.convert(NSPoint(x: select.bounds.midX, y: select.bounds.midY), to: host)
        #expect(host.hitTest(point) !== select)
        window.recalculateKeyViewLoop()
        #expect(window.makeFirstResponder(select))
        #expect(!tools.isIdleHidden && tools.alphaValue == 1 && !tools.isAccessibilityHidden())
        try assertAccessibilityProjection(tools, hidden: false)
        window.selectNextKeyView(select)
        #expect(window.firstResponder === highlight)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!tools.isIdleHidden)
        window.selectPreviousKeyView(highlight)
        #expect(window.firstResponder === select)
        #expect(window.makeFirstResponder(nil))
        try await waitForIdle(tools)
        try assertAccessibilityProjection(tools, hidden: true)
        #expect(fixture.reader.document === document && fixture.reader.tool == .select)
        #expect(await fixture.operations.saveCount == 0)
    }

    @Test("Native presentation pins reveal synchronously and the final release resumes quiet reading")
    func presentationPinsRevealImmediately() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let (tools, window) = makeQuietTools(fixture.reader)
        defer {
            tools.invalidate()
            window.close()
        }
        try await waitForIdle(tools)
        let first = try #require(fixture.reader.presentationActivity.begin())
        #expect(!tools.isIdleHidden && tools.alphaValue == 1 && !tools.isAccessibilityHidden())
        try assertAccessibilityProjection(tools, hidden: false)
        let second = try #require(fixture.reader.presentationActivity.begin())
        fixture.reader.presentationActivity.end(first)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!tools.isIdleHidden)
        fixture.reader.presentationActivity.end(second)
        try await waitForIdle(tools)
        #expect(tools.isAccessibilityHidden())
        try assertAccessibilityProjection(tools, hidden: true)
    }

    @Test("A stationary click through quiet controls remains addressed to paper until pointer movement")
    func idleClickCannotActivateCoveredTool() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let window = makeWindow(view)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        let acceptsMovement = window.acceptsMouseMovedEvents
        defer {
            view.invalidate()
            window.close()
        }
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        let comment = try button("comment", in: tools)
        let host = try #require(window.contentView)
        let local = NSPoint(x: comment.bounds.midX, y: comment.bounds.midY)
        let point = comment.convert(local, to: nil)
        let hostPoint = comment.convert(local, to: host)
        let document = view.document
        #expect(
            view.trackingAreas.contains {
                ($0.owner as? PDFReaderNativePDFView) === view && $0.options.contains([.mouseMoved, .inVisibleRect, .activeInKeyWindow])
            })
        try await waitForIdle(tools)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            #expect(view.route(event) === event)
            #expect(tools.isIdleHidden && tools.isAccessibilityHidden())
            #expect(host.hitTest(hostPoint) !== comment)
        }
        let movement = try #require(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 0, pressure: 0))
        view.mouseMoved(with: movement)
        #expect(!tools.isIdleHidden && !tools.isAccessibilityHidden())
        #expect(window.acceptsMouseMovedEvents == acceptsMovement)
        #expect(host.hitTest(hostPoint) === comment)
        #expect(view.document === document && fixture.reader.tool == .select && fixture.reader.annotationDraft == nil)
        #expect(await fixture.operations.saveCount == 0)
    }

    @Test("Comment drafts and persistent failure retain controls until the existing state owner clears them")
    func draftsAndFailurePinControls() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let (tools, window) = makeQuietTools(fixture.reader)
        defer {
            tools.invalidate()
            window.close()
        }
        fixture.reader.annotationDraft = PDFReaderAnnotationDraft(
            sessionID: UUID(), annotation: nil, pageIndex: 0, point: .zero, text: "Synthetic draft")
        tools.update(fixture.reader)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!tools.isIdleHidden)
        fixture.reader.annotationDraft = nil
        tools.update(fixture.reader)
        try await waitForIdle(tools)
        fixture.reader.presentFailure(PDFReaderError.changed)
        tools.update(fixture.reader)
        #expect(!tools.isIdleHidden)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!tools.isIdleHidden && fixture.reader.error != nil)
    }

    @Test("Retargeting, Reduce Motion and teardown revoke old presentation and animation lifetimes")
    func visibilityInterruptionAndRetargeting() async throws {
        let first = try Fixture()
        let second = try Fixture()
        defer {
            first.reader.shutdown()
            second.reader.shutdown()
        }
        try await first.load()
        try await second.load()
        let (tools, window) = makeQuietTools(first.reader)
        defer {
            tools.invalidate()
            window.close()
        }
        tools.updatePresentation(reduceMotion: false)
        tools.update(second.reader)
        try await waitForIdle(tools)
        let oldPin = try #require(first.reader.presentationActivity.begin())
        #expect(tools.isIdleHidden)
        let currentPin = try #require(second.reader.presentationActivity.begin())
        #expect(!tools.isIdleHidden)
        tools.updatePresentation(reduceMotion: true)
        #expect(tools.layer?.animation(forKey: PDFReaderFloatingToolsView.visibilityAnimationKey) == nil)
        #expect(tools.alphaValue == 1)
        second.reader.presentationActivity.end(currentPin)
        try await waitForIdle(tools)
        #expect(tools.layer?.animation(forKey: PDFReaderFloatingToolsView.visibilityAnimationKey) == nil)
        tools.noteActivity()
        #expect(!tools.isIdleHidden && tools.alphaValue == 1)
        tools.invalidate()
        first.reader.presentationActivity.end(oldPin)
        let latePin = try #require(second.reader.presentationActivity.begin())
        tools.noteActivity()
        tools.update(second.reader)
        try await Task.sleep(for: .milliseconds(80))
        #expect(tools.isHidden && tools.isAccessibilityHidden())
        try assertAccessibilityProjection(tools, hidden: true)
        #expect(tools.layer?.animation(forKey: PDFReaderFloatingToolsView.visibilityAnimationKey) == nil)
        second.reader.presentationActivity.end(latePin)
    }

    @Test("The native capsule fits the pane and final-page text clears it without changing page spacing", arguments: [280.0, 500.0])
    func pageEndClearance(width: Double) async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let document = try #require(fixture.reader.document)
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.document = document
        view.layoutDocumentView()
        let scroll = try #require(view.documentView?.enclosingScrollView)
        let clip = scroll.contentView
        let originalInsets = scroll.contentInsets
        let originalAutomatic = scroll.automaticallyAdjustsContentInsets
        let margins = view.pageBreakMargins
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        #expect(!tools.isAccessibilityElement())
        #expect(tools.style == .regular)
        #expect(tools.frame.width > 100 && tools.frame.width < width)
        #expect(abs(tools.frame.midX - view.bounds.midX) < 1)
        #expect(tools.frame.minY >= ScholiumMetrics.PDFReader.toolsBottomInset - 1)
        #expect(scroll === view.documentView?.enclosingScrollView && scroll.contentView === clip)
        #expect(!scroll.automaticallyAdjustsContentInsets)
        #expect(scroll.contentInsets.top == originalInsets.top)
        #expect(scroll.contentInsets.bottom >= tools.frame.height + ScholiumMetrics.PDFReader.toolsBottomInset)
        #expect(view.pageBreakMargins.top == margins.top && view.pageBreakMargins.bottom == margins.bottom)
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        let lastLine = try #require(lastPage.selection(for: NSRect(x: 0, y: 0, width: 600, height: 35)))
        #expect(lastLine.string?.contains("final line") == true)
        view.setCurrentSelection(lastLine, animate: false)
        for factor in [view.scaleFactor, 1.1] {
            view.scaleFactor = factor
            view.layoutDocumentView()
            window.contentView?.layoutSubtreeIfNeeded()
            var end = clip.bounds
            end.origin.y = clip.isFlipped ? 100_000 : -100_000
            clip.scroll(to: clip.constrainBoundsRect(end).origin)
            scroll.reflectScrolledClipView(clip)
            let textFrame = view.convert(lastLine.bounds(for: lastPage), from: lastPage)
            #expect(textFrame.minY >= tools.frame.maxY - 1)
            try assertSelection(view.currentSelection, matches: lastLine)
        }
        view.invalidate()
        #expect(scroll.automaticallyAdjustsContentInsets == originalAutomatic)
        #expect(scroll.contentInsets.bottom == originalInsets.bottom)
        #expect(tools.isHidden && tools.isAccessibilityHidden())
    }

    @Test("Tool actions preserve the PDF selection, follow capability changes and revoke hidden or dismantled input")
    func toolAdmissionAndSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        let select = try button("select", in: tools)
        let highlight = try button("highlight", in: tools)
        let comment = try button("comment", in: tools)
        let sharedSymbols = try #require(select.symbolConfiguration)
        let nativeToggle = NSButton()
        nativeToggle.setButtonType(.pushOnPushOff)
        let nativeToggleCell = try #require(nativeToggle.cell as? NSButtonCell)
        for button in [select, highlight, comment] {
            #expect(button.image != nil && button.symbolConfiguration != nil)
            #expect(!button.isBordered && button.bezelColor == nil && button.alternateImage == nil)
            #expect(button.symbolConfiguration == sharedSymbols)
            let cell = try #require(button.cell as? NSButtonCell)
            #expect(cell.showsStateBy.isEmpty)
            #expect(cell.highlightsBy == nativeToggleCell.highlightsBy)
        }
        #expect(select.state == .on && highlight.state == .off && comment.state == .off)
        #expect(select.contentTintColor == .controlAccentColor && highlight.contentTintColor == .labelColor && comment.contentTintColor == .labelColor)
        try assertAccessibleToolSelection(select, selected: true)
        try assertAccessibleToolSelection(highlight, selected: false)
        try assertAccessibleToolSelection(comment, selected: false)
        let zoom = try #require(findButton("scholium.pdf.zoom", in: tools))
        #expect(!zoom.isBordered && zoom.bezelColor == nil)
        #expect(zoom.contentTintColor == highlight.contentTintColor && zoom.contentTintColor == comment.contentTintColor)
        for button in [select, highlight, comment, zoom] {
            let host = try #require(window.contentView)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.superview)
            #expect(host.hitTest(point) === button)
        }
        let document = try #require(view.document)
        let selection = try #require(document.page(at: 0)?.selection(for: NSRect(x: 0, y: 0, width: 600, height: 35)))
        view.setCurrentSelection(selection, animate: false)
        let position = view.currentDestination
        highlight.performClick(nil)
        #expect(fixture.reader.tool == .highlight && highlight.state == .on && select.state == .off)
        #expect(highlight.contentTintColor == .controlAccentColor && select.contentTintColor == .labelColor && comment.contentTintColor == .labelColor)
        #expect(highlight.symbolConfiguration == sharedSymbols && select.symbolConfiguration == sharedSymbols)
        try assertAccessibleToolSelection(highlight, selected: true)
        try assertAccessibleToolSelection(select, selected: false)
        try assertAccessibleToolSelection(comment, selected: false)
        highlight.performClick(nil)
        #expect(fixture.reader.tool == .highlight && highlight.state == .on)
        #expect(highlight.contentTintColor == .controlAccentColor)
        try assertAccessibleToolSelection(highlight, selected: true)
        #expect(view.document === document)
        try assertSelection(view.currentSelection, matches: selection)
        #expect(view.currentDestination?.page === position?.page)
        #expect(await fixture.operations.saveCount == 0)
        let departure = fixture.reader.beginDeparture()
        view.apply(fixture.reader)
        #expect(!highlight.isEnabled && !comment.isEnabled && !select.isEnabled)
        #expect(highlight.state == .on && highlight.contentTintColor == .controlAccentColor)
        try assertAccessibleToolSelection(highlight, selected: true)
        let staleAction = try #require(comment.action)
        #expect(NSApplication.shared.sendAction(staleAction, to: comment.target, from: comment))
        #expect(fixture.reader.tool == .highlight)
        try assertAccessibleToolSelection(comment, selected: false)
        fixture.reader.endDeparture(departure)
        view.isHidden = true
        #expect(NSApplication.shared.sendAction(staleAction, to: comment.target, from: comment))
        #expect(fixture.reader.tool == .highlight)
        view.isHidden = false
        view.apply(fixture.reader)
        comment.performClick(nil)
        #expect(fixture.reader.tool == .comment && fixture.reader.annotationDraft == nil)
        #expect(comment.state == .on && highlight.state == .off && select.state == .off)
        #expect(comment.contentTintColor == .controlAccentColor && highlight.contentTintColor == .labelColor && select.contentTintColor == .labelColor)
        #expect(comment.symbolConfiguration == sharedSymbols)
        try assertAccessibleToolSelection(comment, selected: true)
        try assertAccessibleToolSelection(highlight, selected: false)
        try assertAccessibleToolSelection(select, selected: false)
        view.invalidate()
        #expect(comment.target == nil && comment.action == nil)
        #expect(NSApplication.shared.sendAction(staleAction, to: tools, from: comment))
        #expect(fixture.reader.tool == .comment)
    }

    private func button(_ tool: String, in view: NSView) throws -> NSButton {
        try #require(findButton("scholium.pdf.tool.\(tool)", in: view), "Missing native tool \(tool)")
    }

    private func assertAccessibleToolSelection(_ button: NSButton, selected: Bool) throws {
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilitySubrole() == .toggle)
        let value = try #require(button.accessibilityValue() as? NSNumber)
        #expect(value.boolValue == selected)
    }

    private func assertAccessibilityProjection(_ tools: PDFReaderFloatingToolsView, hidden: Bool) throws {
        let group = try #require(tools.contentView as? NSStackView)
        #expect(group.accessibilityIdentifier() == "scholium.pdf.tools")
        #expect(group.isAccessibilityHidden() == hidden)
        let controls = group.views.compactMap { $0 as? NSButton }
        #expect(controls.count == 4)
        for control in controls {
            #expect(control.isAccessibilityHidden() == hidden)
            #expect(!control.isHidden)
        }
        let projection = tools.accessibilityChildren() ?? []
        if hidden {
            #expect(projection.isEmpty)
        } else {
            #expect(projection.count == 1 && projection.first as? NSStackView === group)
        }
    }

    private func makeQuietTools(_ reader: PDFReaderController) -> (PDFReaderFloatingToolsView, NSWindow) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let tools = PDFReaderFloatingToolsView(controller: reader, idleDelay: .milliseconds(40), canPresent: { true })
        let size = tools.intrinsicContentSize
        tools.frame = NSRect(x: 80, y: 12, width: size.width, height: size.height)
        host.addSubview(tools)
        let window = makeWindow(host)
        // An unshown native window keeps the physical pointer outside this
        // synthetic control, without moving the user's pointer or focus.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.layoutSubtreeIfNeeded()
        tools.update(reader)
        return (tools, window)
    }

    private func waitForIdle(_ tools: PDFReaderFloatingToolsView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !tools.isIdleHidden, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(tools.isIdleHidden)
    }

    @Test("Zero-sized insertion, native resizing, hiding and window removal refresh tool admission")
    func presentationLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: .zero)
        let host = PDFReaderNativeHostView(pdfView: view)
        view.apply(fixture.reader)
        let tools = try #require(view.floatingTools)
        try assertAccessibilityProjection(tools, hidden: true)
        let highlight = try button("highlight", in: tools)
        let action = try #require(highlight.action)
        #expect(!highlight.isEnabled)
        host.setFrameSize(NSSize(width: 400, height: 600))
        let window = makeWindow(host)
        defer {
            view.invalidate()
            window.close()
        }
        view.setFrameSize(host.bounds.size)
        #expect(highlight.isEnabled)
        try assertAccessibilityProjection(tools, hidden: false)
        view.isHidden = true
        #expect(!highlight.isEnabled)
        try assertAccessibilityProjection(tools, hidden: true)
        #expect(NSApplication.shared.sendAction(action, to: tools, from: highlight))
        #expect(fixture.reader.tool == .select)
        view.isHidden = false
        #expect(highlight.isEnabled)
        try assertAccessibilityProjection(tools, hidden: false)
        view.removeFromSuperview()
        #expect(!highlight.isEnabled)
        #expect(tools.isHidden)
        try assertAccessibilityProjection(tools, hidden: true)
        #expect(NSApplication.shared.sendAction(action, to: tools, from: highlight))
        #expect(fixture.reader.tool == .select)
        host.addSubview(view)
        #expect(highlight.isEnabled)
        try assertAccessibilityProjection(tools, hidden: false)
        highlight.performClick(nil)
        #expect(fixture.reader.tool == .highlight && highlight.state == .on)
    }

    @Test("The native key-view loop traverses floating tools in both directions")
    func nativeKeyTraversal() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        let select = try button("select", in: tools)
        let highlight = try button("highlight", in: tools)
        let comment = try button("comment", in: tools)
        window.recalculateKeyViewLoop()
        #expect(window.makeFirstResponder(select))
        window.selectNextKeyView(select)
        #expect(window.firstResponder === highlight)
        window.selectNextKeyView(highlight)
        #expect(window.firstResponder === comment)
        window.selectPreviousKeyView(comment)
        #expect(window.firstResponder === highlight)
        #expect(fixture.reader.annotationDraft == nil && fixture.reader.tool == .select)
    }

    private func assertSelection(_ actual: PDFSelection?, matches expected: PDFSelection) throws {
        let actual = try #require(actual)
        #expect(actual.string == expected.string)
        #expect(actual.pages.elementsEqual(expected.pages, by: { $0 === $1 }))
        for page in expected.pages { #expect(actual.bounds(for: page) == expected.bounds(for: page)) }
    }

    private func findButton(_ identifier: String, in view: NSView) -> NSButton? {
        for child in view.subviews {
            if let button = child as? NSButton, button.accessibilityIdentifier() == identifier { return button }
            if let button = findButton(identifier, in: child) { return button }
        }
        return nil
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = (view as? PDFReaderNativePDFView).map(PDFReaderNativeHostView.init(pdfView:)) ?? view
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    private struct Fixture {
        let reader: PDFReaderController
        let operations: ControlledPDFReaderOperations
        let context: PDFReaderNoteContext

        init() throws {
            let bytes = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: bytes as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let graphics = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for index in 1...2 {
                graphics.beginPDFPage(nil)
                let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
                let text = NSAttributedString(
                    string: "Synthetic final line \(index)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                graphics.textPosition = CGPoint(x: 30, y: 5)
                CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), graphics)
                graphics.endPDFPage()
            }
            graphics.closePDF()
            let data = bytes as Data
            let id = UUID()
            let record = PortableAttachmentRecord(
                id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString)/floating.pdf")))
            let snapshot = PDFReaderSnapshot(
                record: record, data: data,
                revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
            context = PDFReaderNoteContext(
                triptychID: UUID(), target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "synthetic-floating.md"),
                authoredPath: "../.scholium/attachments/files/floating.pdf")
            operations = ControlledPDFReaderOperations(notes: [context.target.noteID: snapshot])
            reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        }

        func load() async throws {
            reader.follow(context, operations: operations)
            #expect(reader.setVisible(true))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline { await Task.yield() }
            try #require(reader.document != nil && !reader.isLoading && reader.error == nil)
        }
    }
}
