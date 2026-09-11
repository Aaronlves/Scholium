import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Native Sidebar isolation", .serialized)
@MainActor
struct SidebarIsolationTests {
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
        let controller = ScholiumSidebarViewController(
            library: TextField("Library search", text: .constant("")),
            chat: Page(expanded: false), selection: .chat)
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
        for expanded in [true, false, true, false, true, false] {
            controller.update(
                library: TextField("Library search", text: .constant("")),
                chat: Page(expanded: expanded), selection: .chat)
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(window.frame == original)
            #expect(libraryView.isHidden && !chatView.isHidden)
            #expect(controller.libraryHost.view === libraryView)
            #expect(controller.chatHost.view === chatView)
            #expect(controller.view.safeAreaRect.contains(chatView.frame))
        }
        window.makeFirstResponder(chatView)
        controller.update(
            library: TextField("Library search", text: .constant("")),
            chat: Page(expanded: false), selection: .triptych)
        #expect(!libraryView.isHidden && chatView.isHidden)
        #expect(window.firstResponder !== chatView)
        window.setContentSize(.init(width: 1400, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(controller.view.safeAreaRect.contains(libraryView.frame))
        #expect(controller.libraryHost.sizingOptions.isEmpty && controller.chatHost.sizingOptions.isEmpty)
    }
}
