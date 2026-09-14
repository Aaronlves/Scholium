import AppKit
import Testing

@testable import ScholiumApp

@Suite("Workspace Focus Layout", .serialized)
@MainActor
struct WorkspaceFocusLayoutTests {
    @Test(
        "Focus restores every initial pane combination and toolbar visibility",
        arguments: [true, false], [true, false])
    func restoresNativeLayout(libraryVisible: Bool, inspectorVisible: Bool) {
        // Both toolbar states matter independently of the four pane combinations.
        for toolbarVisible in [true, false] {
            let fixture = FocusLayoutFixture()
            defer { fixture.close() }
            fixture.split.setLibraryVisible(libraryVisible, animated: false)
            fixture.split.setResearchInspectorVisible(inspectorVisible, animated: false)
            fixture.toolbar.isVisible = toolbarVisible
            fixture.window.layoutIfNeeded()
            fixture.setPaneWidths(library: 237, inspector: 319)
            let libraryWidth = fixture.split.splitViewItems[0].viewController.view.frame.width
            let inspectorWidth = fixture.split.splitViewItems[2].viewController.view.frame.width
            if libraryVisible { #expect(abs(libraryWidth - 237) <= 1) }
            if inspectorVisible { #expect(abs(inspectorWidth - 319) <= 1) }
            let document = fixture.split.document
            let source = document.string
            let selection = NSRange(location: 7, length: 9)
            document.setSelectedRange(selection)
            #expect(fixture.window.makeFirstResponder(document))
            let normalDocumentWidth = document.frame.width
            let owner = WorkspaceFocusLayout()

            owner.enter(in: fixture.window, split: fixture.split)

            #expect(owner.isActive)
            #expect(!fixture.split.libraryIsVisible)
            #expect(!fixture.split.researchInspectorIsVisible)
            #expect(fixture.split.splitView.isSubviewCollapsed(fixture.split.splitView.arrangedSubviews[0]))
            #expect(fixture.split.splitView.isSubviewCollapsed(fixture.split.splitView.arrangedSubviews[2]))
            #expect(fixture.window.toolbar === fixture.toolbar)
            #expect(!fixture.toolbar.isVisible)
            #expect(document.frame.width >= normalDocumentWidth)
            #expect(fixture.split.splitViewItems[1].viewController.view === document)
            #expect(fixture.window.firstResponder === document)
            #expect(document.selectedRange() == selection)
            #expect(document.string == source)
            #expect(owner.restoredLibraryVisibility == libraryVisible)
            #expect(owner.restoredInspectorVisibility == inspectorVisible)

            owner.exit(in: fixture.window, split: fixture.split)

            #expect(!owner.isActive)
            #expect(fixture.split.libraryIsVisible == libraryVisible)
            #expect(fixture.split.researchInspectorIsVisible == inspectorVisible)
            #expect(fixture.window.toolbar === fixture.toolbar)
            #expect(fixture.toolbar.isVisible == toolbarVisible)
            if libraryVisible {
                #expect(abs(fixture.split.splitViewItems[0].viewController.view.frame.width - libraryWidth) <= 1)
            }
            if inspectorVisible {
                #expect(abs(fixture.split.splitViewItems[2].viewController.view.frame.width - inspectorWidth) <= 1)
            }
            #expect(fixture.split.splitViewItems[1].viewController.view === document)
            #expect(fixture.window.firstResponder === document)
            #expect(document.selectedRange() == selection)
            #expect(document.string == source)
            #expect(owner.restoredLibraryVisibility == nil)
            #expect(owner.restoredInspectorVisibility == nil)
        }
    }

    @Test("Full screen locks focus and restores the preceding windowed state", arguments: [false, true])
    func fullScreenRestoration(manuallyFocused: Bool) {
        let fixture = FocusLayoutFixture()
        defer { fixture.close() }
        let owner = WorkspaceFocusLayout()
        fixture.split.setResearchInspectorVisible(false, animated: false)
        fixture.setPaneWidths(library: 237, inspector: 319)
        if manuallyFocused { owner.enter(in: fixture.window, split: fixture.split) }

        owner.beginFullScreen(in: fixture.window, split: fixture.split)
        #expect(owner.isFullScreenEnforced && owner.isActive)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(owner.isActive)
        #expect(!fixture.split.libraryIsVisible)
        // A completed native transition may reinstall toolbar visibility.
        fixture.toolbar.isVisible = true
        owner.beginFullScreen(in: fixture.window, split: fixture.split)
        #expect(!fixture.toolbar.isVisible)
        fixture.toolbar.isVisible = true
        fixture.split.setLibraryVisible(true, animated: false)
        owner.endFullScreen(in: fixture.window, split: fixture.split)
        #expect(!owner.isFullScreenEnforced)
        #expect(owner.isActive == manuallyFocused)
        #expect(fixture.toolbar.isVisible == !manuallyFocused)
        #expect(fixture.split.libraryIsVisible == !manuallyFocused)
        #expect(!fixture.split.researchInspectorIsVisible)
        owner.endFullScreen(in: fixture.window, split: fixture.split)
        if manuallyFocused { owner.exit(in: fixture.window, split: fixture.split) }
        #expect(fixture.toolbar.isVisible && fixture.split.libraryIsVisible)
        #expect(abs(fixture.split.splitViewItems[0].viewController.view.frame.width - 237) <= 1)
    }

    @Test("Repeated enter retains the original snapshot and repeated exit is inert")
    func repeatedTransitions() {
        let fixture = FocusLayoutFixture()
        defer { fixture.close() }
        fixture.split.setResearchInspectorVisible(false, animated: false)
        fixture.setPaneWidths(library: 253, inspector: 319)
        let originalWidth = fixture.split.splitViewItems[0].viewController.view.frame.width
        let owner = WorkspaceFocusLayout()

        owner.enter(in: fixture.window, split: fixture.split)
        owner.enter(in: fixture.window, split: fixture.split)
        #expect(owner.restoredLibraryVisibility == true)
        #expect(owner.restoredInspectorVisibility == false)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(fixture.toolbar.isVisible)
        #expect(fixture.split.libraryIsVisible)
        #expect(!fixture.split.researchInspectorIsVisible)
        #expect(abs(fixture.split.splitViewItems[0].viewController.view.frame.width - originalWidth) <= 1)

        fixture.toolbar.isVisible = false
        fixture.split.setLibraryVisible(false, animated: false)
        fixture.split.setResearchInspectorVisible(true, animated: false)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(!fixture.toolbar.isVisible)
        #expect(!fixture.split.libraryIsVisible)
        #expect(fixture.split.researchInspectorIsVisible)

        // A later transaction must capture the new normal layout.
        owner.enter(in: fixture.window, split: fixture.split)
        #expect(owner.restoredLibraryVisibility == false)
        #expect(owner.restoredInspectorVisibility == true)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(!fixture.toolbar.isVisible)
        #expect(!fixture.split.libraryIsVisible)
        #expect(fixture.split.researchInspectorIsVisible)
    }

    @Test("Focus removes titlebar background and restores the original appearance", arguments: [true, false])
    func restoresTitlebarAppearance(wasTransparent: Bool) {
        let fixture = FocusLayoutFixture()
        defer { fixture.close() }
        fixture.window.titlebarAppearsTransparent = wasTransparent
        let owner = WorkspaceFocusLayout()

        owner.enter(in: fixture.window, split: fixture.split)
        #expect(fixture.window.titlebarAppearsTransparent)
        #expect(!fixture.toolbar.isVisible)
        owner.enter(in: fixture.window, split: fixture.split)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(fixture.window.titlebarAppearsTransparent == wasTransparent)
        #expect(fixture.toolbar.isVisible)
    }

    @Test("Two window owners retain independent snapshots and native chrome")
    func independentWindows() {
        let first = FocusLayoutFixture()
        let second = FocusLayoutFixture()
        defer {
            first.close()
            second.close()
        }
        second.toolbar.isVisible = false
        second.split.setLibraryVisible(false, animated: false)
        let firstOwner = WorkspaceFocusLayout()
        let secondOwner = WorkspaceFocusLayout()

        firstOwner.enter(in: first.window, split: first.split)
        #expect(!secondOwner.isActive)
        #expect(!second.split.libraryIsVisible)
        #expect(second.split.researchInspectorIsVisible)
        secondOwner.enter(in: second.window, split: second.split)
        firstOwner.exit(in: first.window, split: first.split)
        #expect(first.toolbar.isVisible)
        #expect(first.split.libraryIsVisible && first.split.researchInspectorIsVisible)
        #expect(secondOwner.isActive)
        #expect(!second.toolbar.isVisible)
        #expect(!second.split.libraryIsVisible && !second.split.researchInspectorIsVisible)
        #expect(secondOwner.restoredLibraryVisibility == false)
        #expect(secondOwner.restoredInspectorVisibility == true)

        secondOwner.exit(in: second.window, split: second.split)
        #expect(!second.toolbar.isVisible)
        #expect(!second.split.libraryIsVisible && second.split.researchInspectorIsVisible)
        #expect(first.window.toolbar === first.toolbar)
        #expect(second.window.toolbar === second.toolbar)
        #expect(first.split.libraryIsVisible && first.split.researchInspectorIsVisible)
    }

    @Test(
        "A detached document without a split changes only its existing toolbar",
        arguments: [true, false])
    func toolbarOnly(initiallyVisible: Bool) {
        let window = makeFocusLayoutWindow()
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier(UUID().uuidString))
        window.toolbar = toolbar
        toolbar.isVisible = initiallyVisible
        let document = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        document.string = "Detached document selection"
        window.contentView = document
        defer {
            window.toolbar = nil
            window.close()
        }
        let selection = NSRange(location: 9, length: 8)
        document.setSelectedRange(selection)
        #expect(window.makeFirstResponder(document))
        let owner = WorkspaceFocusLayout()

        owner.enter(in: window, split: nil)
        #expect(owner.isActive)
        #expect(window.toolbar === toolbar)
        #expect(!toolbar.isVisible)
        #expect(owner.restoredLibraryVisibility == nil)
        #expect(owner.restoredInspectorVisibility == nil)
        #expect(window.contentView === document)
        #expect(window.firstResponder === document)
        #expect(document.selectedRange() == selection)
        owner.exit(in: window, split: nil)
        #expect(!owner.isActive)
        #expect(window.toolbar === toolbar)
        #expect(toolbar.isVisible == initiallyVisible)
        #expect(window.contentView === document)
        #expect(window.firstResponder === document)
        #expect(document.selectedRange() == selection)
        #expect(document.string == "Detached document selection")
    }

    @Test("A window without toolbar or split does not acquire replacement chrome")
    func absentChrome() {
        let window = makeFocusLayoutWindow()
        defer { window.close() }
        let content = window.contentView
        let owner = WorkspaceFocusLayout()
        owner.enter(in: window, split: nil)
        #expect(owner.isActive)
        #expect(window.toolbar == nil)
        owner.exit(in: window, split: nil)
        #expect(!owner.isActive)
        #expect(window.toolbar == nil)
        #expect(window.contentView === content)
    }

    @Test("Persistence can read normal visibility throughout native transition callbacks")
    func persistenceSnapshotSurvivesCallbacks() {
        let fixture = FocusLayoutFixture()
        defer { fixture.close() }
        fixture.split.setResearchInspectorVisible(false, animated: false)
        let owner = WorkspaceFocusLayout()
        var callbackCount = 0
        fixture.split.visibilityDidChange = { libraryVisible, inspectorVisible in
            callbackCount += 1
            #expect(owner.isActive)
            #expect(owner.restoredLibraryVisibility == true)
            #expect(owner.restoredInspectorVisibility == false)
            // This is the coordinator's session-persistence fallback expression.
            #expect((owner.restoredLibraryVisibility ?? libraryVisible) == true)
            #expect((owner.restoredInspectorVisibility ?? inspectorVisible) == false)
        }

        owner.enter(in: fixture.window, split: fixture.split)
        #expect(callbackCount == 2)
        #expect(!fixture.split.libraryIsVisible && !fixture.split.researchInspectorIsVisible)
        owner.exit(in: fixture.window, split: fixture.split)
        #expect(callbackCount == 4)
        #expect(owner.restoredLibraryVisibility == nil)
        #expect(owner.restoredInspectorVisibility == nil)
        #expect(fixture.split.libraryIsVisible && !fixture.split.researchInspectorIsVisible)
        fixture.split.visibilityDidChange = nil
    }
}

@MainActor
private func makeFocusLayoutWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 760),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    return window
}

@MainActor
private final class FocusLayoutFixture {
    let window = makeFocusLayoutWindow()
    let split = FocusLayoutSplitController(nibName: nil, bundle: nil)
    let toolbar = NSToolbar(identifier: NSToolbar.Identifier(UUID().uuidString))

    init() {
        window.contentViewController = split
        window.toolbar = toolbar
        toolbar.isVisible = true
        window.setContentSize(NSSize(width: 1_280, height: 760))
        split.view.frame = window.contentView?.bounds ?? .zero
        window.layoutIfNeeded()
    }

    func setPaneWidths(library: CGFloat, inspector: CGFloat) {
        window.layoutIfNeeded()
        if split.libraryIsVisible {
            split.splitView.setPosition(library, ofDividerAt: 0)
        }
        if split.researchInspectorIsVisible {
            split.splitView.setPosition(
                split.splitView.bounds.width - inspector - split.splitView.dividerThickness,
                ofDividerAt: 1
            )
        }
        window.layoutIfNeeded()
    }

    func close() {
        split.visibilityDidChange = nil
        window.toolbar = nil
        window.close()
    }
}

/// Only the protocol boundary is synthetic: AppKit owns collapse, geometry,
/// window chrome and the retained text view. No research model or vault is used.
@MainActor
private final class FocusLayoutSplitController: NSSplitViewController, ScholiumWorkspaceSplitControlling {
    let document = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
    var visibilityDidChange: ((Bool, Bool) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        document.string = "Source paragraph with a retained selection.\nSecond paragraph."
        let library = NSViewController()
        library.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 700))
        let documentController = NSViewController()
        documentController.view = document
        let inspector = NSViewController()
        inspector.view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 700))
        let libraryItem = NSSplitViewItem(sidebarWithViewController: library)
        let documentItem = NSSplitViewItem(viewController: documentController)
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        for item in [libraryItem, inspectorItem] {
            item.minimumThickness = 100
            item.maximumThickness = 500
            item.canCollapseFromWindowResize = false
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            item.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        }
        libraryItem.canCollapse = true
        inspectorItem.canCollapse = false
        documentItem.minimumThickness = 200
        documentItem.canCollapse = false
        documentItem.canCollapseFromWindowResize = false
        addSplitViewItem(libraryItem)
        addSplitViewItem(documentItem)
        addSplitViewItem(inspectorItem)
    }

    var nativeSplitViewController: NSSplitViewController { self }
    var libraryIsVisible: Bool { !splitViewItems[0].isCollapsed }
    var researchInspectorIsVisible: Bool { !splitViewItems[2].isCollapsed }

    func setLibraryVisible(_ visible: Bool, animated: Bool) {
        #expect(!animated)
        splitViewItems[0].isCollapsed = !visible
        visibilityDidChange?(libraryIsVisible, researchInspectorIsVisible)
    }

    func setResearchInspectorVisible(_ visible: Bool, animated: Bool) {
        #expect(!animated)
        splitViewItems[2].isCollapsed = !visible
        visibilityDidChange?(libraryIsVisible, researchInspectorIsVisible)
    }
}
