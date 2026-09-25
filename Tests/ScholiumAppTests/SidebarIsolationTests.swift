import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Native Sidebar isolation", .serialized)
@MainActor
struct SidebarIsolationTests {
    private struct SearchFieldPage: NSViewRepresentable {
        let field: NSSearchField

        func makeNSView(context: Context) -> NSSearchField { field }
        func updateNSView(_ nsView: NSSearchField, context: Context) {}
    }

    private struct Page: View {
        var expanded: Bool
        var body: some View {
            VStack {
                Text("Chat")
                DisclosureGroup("Operation Details", isExpanded: .constant(expanded)) {
                    Text(String(repeating: "Conversation history could not be refreshed. ", count: 50))
                }
                ScrollView { Text("Retained conversation") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @Test("Details never resize the window and hidden pages lose native interaction")
    func disclosureAndVisibility() throws {
        let searchField = NSSearchField()
        searchField.stringValue = "Retained Library query"
        searchField.setAccessibilityLabel("Library Search")
        searchField.toolTip = "Library search tooltip"
        let library = ScholiumSidebarPageSurface(
            label: "Library", identifier: "scholium.librarySurface"
        ) {
            SearchFieldPage(field: searchField)
        }
        func chatPage(expanded: Bool) -> ScholiumSidebarPageSurface<Page> {
            ScholiumSidebarPageSurface(label: "Chat", identifier: "scholium.chatSurface") {
                Page(expanded: expanded)
            }
        }
        let controller = ScholiumSidebarViewController(
            library: library, chat: chatPage(expanded: false), selection: .chat)
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        let sidebar = NSSplitViewItem(sidebarWithViewController: controller)
        sidebar.minimumThickness = 260
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        let original = window.frame
        let libraryView = controller.libraryHost.view
        let chatView = controller.chatHost.view
        #expect(libraryView.isAccessibilityHidden())
        #expect(!chatView.isAccessibilityHidden())
        for expanded in [true, false, true, false, true, false] {
            controller.update(
                library: library,
                chat: chatPage(expanded: expanded), selection: .chat)
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(window.frame == original)
            #expect(libraryView.isHidden && !chatView.isHidden)
            #expect(controller.libraryHost.view === libraryView)
            #expect(controller.chatHost.view === chatView)
            #expect(controller.view.safeAreaRect.contains(chatView.frame))
        }
        window.makeFirstResponder(chatView)
        controller.update(
            library: library,
            chat: chatPage(expanded: false), selection: .library)
        #expect(!libraryView.isHidden && chatView.isHidden)
        #expect(!libraryView.isAccessibilityHidden())
        #expect(chatView.isAccessibilityHidden())
        #expect(window.firstResponder !== chatView)

        #expect(window.makeFirstResponder(searchField))
        let fieldEditor = try #require(searchField.currentEditor() as? NSTextView)
        #expect(window.firstResponder === fieldEditor)
        controller.update(
            library: library,
            chat: chatPage(expanded: false), selection: .chat)
        #expect(window.firstResponder !== fieldEditor)
        #expect(searchField.stringValue == "Retained Library query")
        #expect(libraryView.isHidden && !chatView.isHidden)
        #expect(libraryView.isAccessibilityHidden())
        #expect(!chatView.isAccessibilityHidden())
        let fieldCenter = searchField.convert(
            NSPoint(x: searchField.bounds.midX, y: searchField.bounds.midY), to: nil
        )
        let contentPoint = try #require(window.contentView).convert(fieldCenter, from: nil)
        let hitView = try #require(window.contentView?.hitTest(contentPoint))
        #expect(searchField.toolTip == "Library search tooltip")
        #expect(hitView !== searchField)
        #expect(!hitView.isDescendant(of: libraryView))

        controller.update(
            library: library,
            chat: chatPage(expanded: true), selection: .chat)
        #expect(libraryView.isHidden && !chatView.isHidden)
        #expect(controller.libraryHost.view === libraryView)
        #expect(controller.chatHost.view === chatView)
        #expect(window.frame == original)
        window.setContentSize(.init(width: 1400, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(controller.view.safeAreaRect.contains(chatView.frame))
        #expect(controller.libraryHost.sizingOptions.isEmpty && controller.chatHost.sizingOptions.isEmpty)
    }
}
