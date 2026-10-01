import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@MainActor private final class SettingsTitleChangeCount { var value = 0 }

@Suite("Settings pane containment")
@MainActor
struct SettingsPaneContainerTests {
    @Test("Visited content remains attached while hidden content leaves accessibility and resizing")
    func retainedVisibilityAndGeometry() {
        let container = SettingsPaneContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let first = NSButton(title: "First", target: nil, action: nil)
        let second = NSButton(title: "Second", target: nil, action: nil)
        container.show(first)
        container.show(second)
        #expect(first.superview === container)
        #expect(first.isHidden)
        #expect(!second.isHidden)
        #expect(container.accessibilityChildren()?.count == 1)
        #expect(((container.accessibilityChildren()?.first as? NSObject)?.value(forKey: "accessibilityLabel") as? String) == "Second")

        container.setFrameSize(NSSize(width: 800, height: 500))
        container.layoutSubtreeIfNeeded()
        #expect(second.frame.size == container.bounds.size)
        #expect(first.frame.size == NSSize(width: 600, height: 400))
        container.show(first)
        #expect(!first.isHidden)
        #expect(first.frame.size == container.bounds.size)
        #expect(second.isHidden)
        container.removeContents()
        #expect(container.subviews.isEmpty)
        #expect(container.selectedView == nil)
    }

    @Test("Native preferences items project category selection without changing window size")
    func nativePreferencesNavigation() throws {
        _ = NSApplication.shared
        var selections: [ScholiumSettingsDestination] = []
        let controller = SettingsNavigationController(
            selection: .document, locale: Locale(identifier: "en"),
            page: AnyView(Text("Disposable settings page")),
            onSelect: { selections.append($0) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            controller.detachToolbar()
            window.contentViewController = nil
            window.close()
        }
        controller.attachToolbar()
        window.contentView?.layoutSubtreeIfNeeded()
        let toolbar = try #require(window.toolbar)
        let expectedIdentifiers = [
            "workspace", "document", "writing", "agents", "shortcuts", "zotero",
        ].map { NSToolbarItem.Identifier("scholium.settings.category.\($0)") }
        #expect(toolbar.delegate === controller)
        #expect(toolbar.isVisible)
        #expect(!toolbar.allowsUserCustomization && !toolbar.autosavesConfiguration)
        #expect(!toolbar.allowsDisplayModeCustomization)
        #expect(toolbar.displayMode == .iconAndLabel)
        #expect(window.toolbarStyle == .preference)
        #expect(window.titleVisibility == .visible)
        #expect(window.title == "Document Appearance")
        #expect(toolbar.items.map(\.itemIdentifier) == expectedIdentifiers)
        #expect(controller.toolbarSelectableItemIdentifiers(toolbar) == expectedIdentifiers)
        #expect(toolbar.selectedItemIdentifier == expectedIdentifiers[1])
        #expect(toolbar.items.map(\.label) == ["Workspace", "Document", "Writing", "Agents", "Shortcuts", "Zotero"])
        #expect(toolbar.items.allSatisfy { $0.view == nil && $0.image != nil })
        #expect(toolbar.items[1].toolTip == "Document Appearance")
        #expect(toolbar.items[1].menuFormRepresentation?.state == .on)
        #expect(controller.children.count == 1)
        #expect(controller.children.first === controller.pageController)

        // A scene projection with unchanged state must not repeatedly notify
        // the window and create a SwiftUI/AppKit presentation feedback loop.
        let titleChanges = SettingsTitleChangeCount()
        let titleObservation = window.observe(\.title, options: [.new]) { _, _ in
            MainActor.assumeIsolated { titleChanges.value += 1 }
        }
        for _ in 0..<3 { controller.update(selection: .document, locale: Locale(identifier: "en")) }
        #expect(titleChanges.value == 0)
        titleObservation.invalidate()

        let originalFrame = window.frame
        let writingItem = toolbar.items[2]
        let writingAction = try #require(writingItem.action)
        #expect(NSApplication.shared.sendAction(writingAction, to: writingItem.target, from: writingItem))
        #expect(selections == [.writing])
        // The action is an intent. Only the parent selection projection updates
        // the title and selected pane; sending it does not commit a page draft.
        #expect(window.title == "Document Appearance")
        controller.update(selection: .writing, locale: Locale(identifier: "en"))
        #expect(toolbar.selectedItemIdentifier == expectedIdentifiers[2])
        #expect(window.title == "Writing Assistance")
        #expect(window.toolbar === toolbar)
        #expect(window.frame == originalFrame)
        #expect(writingItem.menuFormRepresentation?.state == .on)
        #expect(toolbar.items[1].menuFormRepresentation?.state == .off)

        // Selecting the current pane still reaches the owner, which can leave
        // a temporary search route. The native overflow menu uses that route too.
        let writingMenu = try #require(writingItem.menuFormRepresentation)
        let menuAction = try #require(writingMenu.action)
        #expect(NSApplication.shared.sendAction(menuAction, to: writingMenu.target, from: writingMenu))
        #expect(selections == [.writing, .writing])
        let unknownItem = NSToolbarItem(itemIdentifier: .init("unknown-settings-category"))
        #expect(NSApplication.shared.sendAction(writingAction, to: controller, from: unknownItem))
        #expect(selections == [.writing, .writing])

        // A later scene-content transaction must not retire native resizing.
        window.styleMask.remove(.resizable)
        controller.update(selection: .workspace, locale: Locale(identifier: "en"))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.frame == originalFrame)
        for width in [CGFloat(920), CGFloat(780)] {
            window.setContentSize(NSSize(width: width, height: 600))
            window.contentView?.layoutSubtreeIfNeeded()
            controller.view.layoutSubtreeIfNeeded()
            let contentFrame = controller.pageController.view.convert(
                controller.pageController.view.bounds, to: controller.view)
            let safeFrame = controller.view.safeAreaLayoutGuide.frame
            #expect(abs(controller.view.bounds.width - width) < 0.5)
            #expect(abs(contentFrame.width - safeFrame.width) < 0.5)
            #expect(abs(contentFrame.minX - safeFrame.minX) < 0.5)
            #expect(abs(contentFrame.minY - safeFrame.minY) < 0.5)
            #expect(abs(contentFrame.maxY - safeFrame.maxY) < 0.5)
            #expect(window.toolbar === toolbar && toolbar.isVisible)
        }

        controller.update(selection: .document, locale: Locale(identifier: "zh-Hans"))
        #expect(toolbar.items.map(\.label) == ["工作区", "文稿", "写作", "Agent", "快捷键", "Zotero"])
        #expect(window.title == "文稿外观")
        #expect(toolbar.selectedItemIdentifier == expectedIdentifiers[1])
        #expect(toolbar.items[1].toolTip == "文稿外观")
        #expect(selections == [.writing, .writing], "Projection must not send a selection intent")

        controller.detachToolbar()
        #expect(window.toolbar == nil)
    }

    @Test("Detaching Settings preserves a toolbar installed by another owner")
    func detachPreservesReplacementToolbar() {
        _ = NSApplication.shared
        let controller = SettingsNavigationController(
            selection: .workspace, locale: Locale(identifier: "en"),
            page: AnyView(Text("Disposable settings page")), onSelect: { _ in })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            controller.detachToolbar()
            window.toolbar = nil
            window.contentViewController = nil
            window.close()
        }
        controller.attachToolbar()
        let replacement = NSToolbar(identifier: "disposable.replacement.toolbar")
        window.toolbar = replacement
        controller.detachToolbar()
        #expect(window.toolbar === replacement)
    }

    @Test("Hiding an editing pane releases its field editor but preserves outside focus")
    func outgoingFieldEditorAndSearchFocus() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        window.contentView = root
        let search = NSSearchField()
        search.stringValue = "Search"
        root.addSubview(search)
        let container = SettingsPaneContainerView(frame: NSRect(x: 200, y: 0, width: 600, height: 500))
        root.addSubview(container)
        let first = NSTextField(string: "Unsaved draft")
        let second = NSButton(title: "Second", target: nil, action: nil)
        container.show(first)
        #expect(window.makeFirstResponder(first))
        let oldEditor = window.firstResponder
        container.show(second)
        #expect(window.firstResponder !== oldEditor)
        #expect(first.stringValue == "Unsaved draft")

        #expect(window.makeFirstResponder(search))
        let searchEditor = window.firstResponder
        container.show(first)
        #expect(window.firstResponder === searchEditor)
        #expect(first.stringValue == "Unsaved draft")
    }
}
