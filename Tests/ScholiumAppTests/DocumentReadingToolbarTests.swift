import AppKit
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Pane-relative native reading toolbar", .serialized)
@MainActor
struct DocumentReadingToolbarTests {
    @Test("Native divider resize adapts commands from actual reader width in both window types", arguments: [false, true])
    func responsiveRegionWidth(detached: Bool) async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        model.isDetachedDocumentWindow = detached
        let operations = try await loadReader(in: model)
        let reading = makeReadingSplit()
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        let library = NSSplitViewItem(viewController: NSViewController())
        library.minimumThickness = 260
        library.maximumThickness = 300
        let inspector = NSSplitViewItem(viewController: NSViewController())
        inspector.isCollapsed = true
        split.addSplitViewItem(library)
        split.addSplitViewItem(NSSplitViewItem(viewController: reading))
        split.addSplitViewItem(inspector)
        let window = makeWindow(split)
        split.viewWillAppear()
        reading.viewWillAppear()
        window.setContentSize(NSSize(width: 1400, height: 600))
        split.splitView.adjustSubviews()
        window.layoutIfNeeded()
        let workspaceOwner: ScholiumWorkspaceToolbarController?
        let detachedOwner: DetachedDocumentToolbar?
        if detached {
            workspaceOwner = nil
            detachedOwner = DetachedDocumentToolbar(model: model)
            detachedOwner?.install(in: window)
        } else {
            detachedOwner = nil
            workspaceOwner = ScholiumWorkspaceToolbarController(
                appState: model, windowActions: inertActions, splitViewController: split)
            workspaceOwner?.install(in: window)
        }
        defer {
            workspaceOwner?.invalidate()
            detachedOwner?.invalidate()
            reading.invalidate()
            model.sidePaneCoordinator.shutdown()
            model.pdfReaderController.shutdown()
            window.toolbar = nil
            window.close()
            Task { await operations.cancelPending() }
        }
        let toolbar = try #require(window.toolbar)
        let controls = try #require(item(ID.readerControls, in: toolbar) as? PDFReaderToolbarItem)
        let divider = try #require(item(ID.readingDivider, in: toolbar) as? NSTrackingSeparatorToolbarItem)
        let document = reading.documentController.view
        model.pdfReaderController.recordPaneWidth(620)
        for (width, compact) in [(520.0, false), (320.0, !detached), (280.0, true), (520.0, false)] {
            reading.splitView.setPosition(reading.splitView.bounds.maxX - width - reading.splitView.dividerThickness, ofDividerAt: 0)
            window.layoutIfNeeded()
            reading.splitView.layoutSubtreeIfNeeded()
            await drainPresentation()
            #expect(abs(reading.readerController.view.bounds.width - width) < 1)
            #expect(model.pdfReaderController.paneWidth == 620)
            #expect(controls.usesCompactPresentation == compact)
            #expect(item(ID.readerControls, in: toolbar) === controls)
            #expect(divider.splitView === reading.splitView && reading.documentController.view === document)
            let view = try #require(controls.view)
            let compactButton = (view as? NSStackView)?.arrangedSubviews.first { $0.accessibilityIdentifier() == "scholium.pdf.compactControls" }
            #expect((compactButton?.isHidden ?? true) == !compact)
            if compact { #expect(view.fittingSize.width + CGFloat(detached ? 44 : 88) + 16 <= width) }
            // AppKit exposes toolbar view placement only after its native host
            // participates; the isolated app journey owns visible AX edges.
            if view.window === window {
                let boundary = document.convert(NSPoint(x: document.bounds.maxX, y: 0), to: nil).x
                #expect(view.convert(.zero, to: nil).x >= boundary - 1)
            }
        }
        workspaceOwner?.invalidate()
        detachedOwner?.invalidate()
        reading.splitView.setPosition(reading.splitView.bounds.maxX - 280 - reading.splitView.dividerThickness, ofDividerAt: 0)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        await drainPresentation()
        #expect(!controls.usesCompactPresentation && !controls.isEnabled)
    }

    @Test("The three side-pane states retain commands and bind the toolbar to the nested Markdown divider")
    func workspaceRegionOwnership() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let reading = ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: false, readerWidth: 360, widthDidChange: { _ in }, focusDocument: {})
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        let library = NSSplitViewItem(viewController: NSViewController())
        library.minimumThickness = 260
        library.maximumThickness = 300
        let inspector = NSSplitViewItem(viewController: NSViewController())
        inspector.minimumThickness = 270
        inspector.maximumThickness = 340
        inspector.isCollapsed = true
        split.addSplitViewItem(library)
        split.addSplitViewItem(NSSplitViewItem(viewController: reading))
        split.addSplitViewItem(inspector)
        let window = makeWindow(split)
        let actions = WorkspaceWindowActions(
            toggleFocusLayout: {}, canToggleFocusLayout: { true }, canUseSidebar: { true },
            setLibraryVisible: { _ in }, setResearchInspectorVisible: { model.recordResearchInspectorVisibility($0) },
            activateSidebar: { _ in }, showAttention: { _ in }, showPreferredAttention: {}, canShowAttention: { false })
        let toolbarOwner = ScholiumWorkspaceToolbarController(appState: model, windowActions: actions, splitViewController: split)
        defer {
            toolbarOwner.invalidate()
            reading.invalidate()
            model.pdfReaderController.shutdown()
            window.toolbar = nil
            window.close()
        }
        toolbarOwner.install(in: window)
        split.viewWillAppear()
        reading.viewWillAppear()
        window.setContentSize(NSSize(width: 1400, height: 600))
        split.splitView.adjustSubviews()
        window.layoutIfNeeded()
        let toolbar = try #require(window.toolbar)
        #expect(ScholiumDocumentReadingSplitController.find(in: split.view) === reading)
        let document = reading.documentController.view
        let mode = try #require(item(ID.documentMode, in: toolbar))
        let more = try #require(item(ID.noteActions, in: toolbar))
        let panes = try #require(item(ID.paneVisibility, in: toolbar) as? NSToolbarItemGroup)
        var retainedPDFControls: NSToolbarItem?
        var retainedDivider: NSTrackingSeparatorToolbarItem?
        for (readerVisible, inspectorVisible) in [(false, false), (true, false), (false, true), (true, false)] {
            model.pdfReaderController.setVisible(readerVisible)
            model.recordResearchInspectorVisibility(inspectorVisible)
            inspector.isCollapsed = !inspectorVisible
            reading.update(readerVisible: readerVisible, readerWidth: 360, widthDidChange: { _ in }, focusDocument: {})
            await drainPresentation()
            // Bounded native siblings leave a real resize interval; the full
            // SwiftUI empty shell otherwise consumes only the reading minima.
            split.splitView.setPosition(300, ofDividerAt: 0)
            if inspectorVisible {
                split.splitView.setPosition(split.splitView.bounds.width - 340, ofDividerAt: 1)
            }
            window.layoutIfNeeded()
            reading.splitView.layoutSubtreeIfNeeded()
            #expect(item(ID.documentMode, in: toolbar) === mode)
            #expect(item(ID.noteActions, in: toolbar) === more)
            #expect(item(ID.paneVisibility, in: toolbar) === panes)
            #expect(reading.documentController.view === document)
            #expect(panes.isSelected(at: 0) == readerVisible && panes.isSelected(at: 1) == inspectorVisible)
            let apparatusDivider = try #require(item(ID.apparatusDivider, in: toolbar) as? NSTrackingSeparatorToolbarItem)
            #expect(apparatusDivider.isHidden == !inspectorVisible)
            #expect(apparatusDivider.splitView === split.splitView && apparatusDivider.dividerIndex == 1)
            let moreIndex = try #require(toolbar.itemIdentifiers.firstIndex(of: ID.noteActions))
            if readerVisible {
                #expect(toolbar.itemIdentifiers[moreIndex + 1] == ID.readingDivider)
                #expect(toolbar.itemIdentifiers[moreIndex + 2] == ID.readerControls)
                let divider = try #require(item(ID.readingDivider, in: toolbar) as? NSTrackingSeparatorToolbarItem)
                let controls = try #require(item(ID.readerControls, in: toolbar) as? PDFReaderToolbarItem)
                #expect(divider.splitView === reading.splitView && divider.dividerIndex == 0)
                #expect(divider.splitView !== split.splitView)
                if let retainedPDFControls { #expect(controls === retainedPDFControls) }
                if let retainedDivider { #expect(divider === retainedDivider) }
                retainedPDFControls = controls
                retainedDivider = divider
                let boundary = document.convert(NSPoint(x: document.bounds.maxX, y: 0), to: nil).x
                let minimum = reading.documentItem.minimumThickness
                let maximum = reading.splitView.bounds.width - reading.readerItem.minimumThickness - reading.splitView.dividerThickness
                try #require(
                    maximum - minimum > 80,
                    "Resize fixture needs usable space: window \(window.contentLayoutRect), outer \(split.splitView.frame), reading \(reading.view.frame), document \(document.frame), reader \(reading.readerController.view.frame)"
                )
                let current = document.frame.maxX
                let target = abs(current - minimum) > abs(maximum - current) ? minimum + 20 : maximum - 20
                reading.splitView.setPosition(target, ofDividerAt: 0)
                window.layoutIfNeeded()
                reading.splitView.layoutSubtreeIfNeeded()
                #expect(
                    abs(document.convert(NSPoint(x: document.bounds.maxX, y: 0), to: nil).x - boundary) > 1,
                    "Nested resize: width \(reading.splitView.bounds.width), document \(document.frame), target \(target), previous boundary \(boundary)")
                #expect(divider.splitView === reading.splitView)
            } else {
                #expect(toolbar.itemIdentifiers[moreIndex + 1] == ID.apparatusDivider)
                #expect(item(ID.readerControls, in: toolbar) == nil)
                #expect(item(ID.readingDivider, in: toolbar) == nil)
            }
            #expect(toolbar.itemIdentifiers.last == ID.paneVisibility)
        }
    }

    @Test("Detached toolbar admits a late native split attachment without borrowing another window's geometry")
    func detachedAttachmentAndTeardown() async throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        model.isDetachedDocumentWindow = true
        let root = NSViewController()
        let window = makeWindow(root)
        let reading = makeReadingSplit()
        let foreign = makeReadingSplit()
        let foreignWindow = makeWindow(foreign)
        let owner = DetachedDocumentToolbar(model: model)
        defer {
            owner.invalidate()
            reading.invalidate()
            foreign.invalidate()
            model.pdfReaderController.shutdown()
            window.toolbar = nil
            window.close()
            foreignWindow.close()
        }
        owner.install(in: window)
        #expect(!owner.toolbar.itemIdentifiers.contains(ID.readingDivider))
        foreign.viewDidAppear()
        await drainPresentation()
        #expect(!owner.toolbar.itemIdentifiers.contains(ID.readingDivider))
        root.addChild(reading)
        reading.view.frame = root.view.bounds
        reading.view.autoresizingMask = [.width, .height]
        root.view.addSubview(reading.view)
        reading.viewDidAppear()
        await drainPresentation()
        let divider = try #require(item(ID.readingDivider, in: owner.toolbar) as? NSTrackingSeparatorToolbarItem)
        #expect(divider.splitView === reading.splitView && divider.splitView.window === window)
        #expect(divider.splitView !== foreign.splitView)
        #expect(owner.toolbar.itemIdentifiers == DetachedDocumentToolbar.itemIdentifiers(readerVisible: true))
        let controls = try #require(item(ID.readerControls, in: owner.toolbar) as? PDFReaderToolbarItem)
        reading.invalidate()
        await drainPresentation()
        #expect(!owner.toolbar.itemIdentifiers.contains(ID.readingDivider))
        owner.invalidate()
        foreign.viewDidAppear()
        await drainPresentation()
        #expect(owner.toolbar.delegate == nil && !controls.isEnabled)
        #expect(!owner.toolbar.itemIdentifiers.contains(ID.readingDivider))
    }

    private typealias ID = ScholiumWorkspaceToolbarController.Item

    private var inertActions: WorkspaceWindowActions {
        WorkspaceWindowActions(
            toggleFocusLayout: {}, canToggleFocusLayout: { true }, canUseSidebar: { true },
            setLibraryVisible: { _ in }, setResearchInspectorVisible: { _ in },
            activateSidebar: { _ in }, showAttention: { _ in }, showPreferredAttention: {}, canShowAttention: { false })
    }

    private func loadReader(in model: WindowModel) async throws -> ControlledPDFReaderOperations {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let canvas = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<2 {
            canvas.beginPDFPage(nil)
            canvas.endPDFPage()
        }
        canvas.closePDF()
        let pdf = data as Data
        let noteID = UUID()
        let vaultID = UUID()
        let operations = ControlledPDFReaderOperations(notes: [
            noteID: .init(
                record: .init(id: UUID(), vaultID: vaultID, location: .vaultRelative(try AttachmentRelativePath("synthetic.pdf"))),
                data: pdf, revision: .init(fingerprint: DocumentFingerprint(data: pdf), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
        ])
        model.pdfReaderController.setVisible(true)
        model.pdfReaderController.follow(
            .init(triptychID: UUID(), target: .init(noteID: noteID, vaultID: vaultID, relativePath: "Synthetic.md"), authoredPath: "synthetic.pdf"),
            operations: operations)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.pdfReaderController.document == nil || model.pdfReaderController.isLoading, ContinuousClock.now < deadline { await Task.yield() }
        try #require(model.pdfReaderController.document != nil && !model.pdfReaderController.isLoading)
        return operations
    }

    private func item(_ identifier: NSToolbarItem.Identifier, in toolbar: NSToolbar) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    private func makeReadingSplit() -> ScholiumDocumentReadingSplitController {
        ScholiumDocumentReadingSplitController(
            documentController: NSViewController(), readerController: NSViewController(),
            readerVisible: true, readerWidth: 360, widthDidChange: { _ in }, focusDocument: {})
    }

    private func makeWindow(_ controller: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 600),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.layoutIfNeeded()
        return window
    }

    private func drainPresentation() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
