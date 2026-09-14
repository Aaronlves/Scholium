import AppKit

/// A temporary, window-local presentation transaction. AppKit retains the
/// actual panes and document; this owner only saves and restores native chrome.
@MainActor
final class WorkspaceFocusLayout {
    private struct PaneLayout {
        let libraryVisible: Bool
        let inspectorVisible: Bool
        let libraryWidth: CGFloat
        let inspectorWidth: CGFloat
    }

    private struct Snapshot {
        let toolbarVisible: Bool
        let titlebarAppearsTransparent: Bool
        let panes: PaneLayout?
    }

    private var snapshot: Snapshot?
    private var focusBeforeFullScreen: Bool?
    var isActive: Bool { snapshot != nil }
    var isFullScreenEnforced: Bool { focusBeforeFullScreen != nil }
    var restoredLibraryVisibility: Bool? { snapshot?.panes?.libraryVisible }
    var restoredInspectorVisibility: Bool? { snapshot?.panes?.inspectorVisible }

    func beginFullScreen(in window: NSWindow, split: (any ScholiumWorkspaceSplitControlling)?) {
        if focusBeforeFullScreen == nil { focusBeforeFullScreen = isActive }
        enter(in: window, split: split)
        // AppKit may recreate chrome during the transition. Do not recapture
        // its temporary state or replace the pre-full-screen layout snapshot.
        keepChromeHidden(in: window)
    }

    func endFullScreen(in window: NSWindow, split: (any ScholiumWorkspaceSplitControlling)?) {
        guard let wasFocused = focusBeforeFullScreen else { return }
        focusBeforeFullScreen = nil
        if wasFocused {
            // A native temporary sidebar reveal must not become pinned when
            // returning to the independently focused ordinary window.
            split?.setLibraryVisible(false, animated: false)
            split?.setResearchInspectorVisible(false, animated: false)
            keepChromeHidden(in: window)
        } else {
            exit(in: window, split: split)
        }
    }

    private func keepChromeHidden(in window: NSWindow) {
        if window.toolbar?.isVisible == true { window.toolbar?.isVisible = false }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
    }

    func reset(in window: NSWindow, split: (any ScholiumWorkspaceSplitControlling)?) {
        focusBeforeFullScreen = nil
        exit(in: window, split: split)
    }

    func enter(in window: NSWindow, split: (any ScholiumWorkspaceSplitControlling)?) {
        guard snapshot == nil else { return }
        window.layoutIfNeeded()
        let panes = split.map {
            PaneLayout(
                libraryVisible: $0.libraryIsVisible,
                inspectorVisible: $0.researchInspectorIsVisible,
                libraryWidth: $0.nativeSplitViewController.splitViewItems.first?.viewController.view.frame.width ?? 0,
                inspectorWidth: $0.nativeSplitViewController.splitViewItems.last?.viewController.view.frame.width ?? 0
            )
        }
        snapshot = Snapshot(
            toolbarVisible: window.toolbar?.isVisible == true,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            panes: panes
        )
        let responder =
            (window.firstResponder as? NSTextView)?.delegate as? NSView
            ?? window.firstResponder as? NSView
        // One layout change, with no independent animation or document reload.
        split?.setLibraryVisible(false, animated: false)
        split?.setResearchInspectorVisible(false, animated: false)
        window.toolbar?.isVisible = false
        window.titlebarAppearsTransparent = true
        window.layoutIfNeeded()
        if responder?.isHiddenOrHasHiddenAncestor == true {
            window.makeFirstResponder(nil)
            window.selectNextKeyView(nil)
        }
    }

    func exit(in window: NSWindow, split: (any ScholiumWorkspaceSplitControlling)?) {
        guard !isFullScreenEnforced, let snapshot else { return }
        // Keep the normal-layout snapshot available while native visibility
        // callbacks publish the transition, including to session persistence.
        defer { self.snapshot = nil }
        window.toolbar?.isVisible = snapshot.toolbarVisible
        window.titlebarAppearsTransparent = snapshot.titlebarAppearsTransparent
        guard let panes = snapshot.panes, let split else {
            window.layoutIfNeeded()
            return
        }
        split.setLibraryVisible(panes.libraryVisible, animated: false)
        split.setResearchInspectorVisible(panes.inspectorVisible, animated: false)
        window.layoutIfNeeded()
        let nativeSplit = split.nativeSplitViewController.splitView
        if panes.libraryVisible, panes.libraryWidth > 0 {
            nativeSplit.setPosition(panes.libraryWidth, ofDividerAt: 0)
        }
        if panes.inspectorVisible, panes.inspectorWidth > 0 {
            nativeSplit.setPosition(
                nativeSplit.bounds.maxX - panes.inspectorWidth - nativeSplit.dividerThickness,
                ofDividerAt: nativeSplit.arrangedSubviews.count - 2
            )
        }
        // Native constraints clamp restored widths if the window was resized.
        window.layoutIfNeeded()
    }
}
