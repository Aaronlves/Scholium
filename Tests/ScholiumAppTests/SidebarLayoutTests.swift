import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Library sidebar layout", .serialized)
@MainActor
struct SidebarLayoutTests {
    @Test("Batch commands stay inside the menu at narrow widths and system appearances")
    func menuDoesNotExpandSidebar() async throws {
        _ = NSApplication.shared
        let controller = DiscoveryController()
        let notes = [WindowDocumentLocation.syntheticPreview(relativePath: "Example.md", rawContent: "Example\n")]
        let context = SidebarContext(
            workspaceNoteCounts: .init(values: [:]),
            treeProjection: .init(revision: 1, value: LibraryTreeProjection(preorderedNotes: notes)),
            allNotes: notes, folders: [], pathComparisonPolicy: nil,
            disclosureScope: .init(vaultID: UUID(), sourceScope: .library),
            selectedDocumentPath: nil, libraryFocusRequestGeneration: 0,
            currentVaultRole: .topicKnowledge, currentWorkspaceSlot: .topicKnowledge,
            requestedWorkspaceSlot: nil, canMutateLibrary: true,
            filterOptions: .init(catalogIsAvailable: true, graphIsAvailable: true, tags: [], authors: [], propertyKeys: [], propertyValues: [:]),
            openNote: { _, _ in }, canAddNoteToChat: { _ in false }, addNoteToChat: { _ in },
            selectTriptychWorkspace: { _ in }, createUntitledNote: { _ in }, createUntitledFolder: { _ in },
            pendingNoteMoves: [], pendingFolderMoves: [],
            requestNoteDrop: { _, _ in }, requestFolderDrop: { _, _ in }, requestNoteBatchMove: { _ in },
            requestNoteBatchTrash: { _ in }, moveNotesDrop: { _, _ in }, hasBatchOutcome: true, showBatchOutcome: {},
            requestFolderFileOperation: { _ in }, requestFolderSystemTrash: { _ in },
            copyRelativePath: { _ in }, revealNote: { _ in }, requestSystemTrash: { _ in },
            selectSortOrder: { _ in }, showError: { _ in })
        let host = NSHostingView(rootView: SidebarView(controller: controller, context: context))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        for width in [300.0, 220.0] {
            window.setContentSize(NSSize(width: width, height: 600))
            for appearance in [NSAppearance.Name.aqua, .accessibilityHighContrastDarkAqua] {
                host.appearance = NSAppearance(named: appearance)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
                let outline = try #require(descendants(host).compactMap { $0 as? NSOutlineView }.first)
                let scroll = try #require(outline.enclosingScrollView)
                let frame = scroll.convert(scroll.bounds, to: host)
                #expect(frame.minX >= -1 && frame.maxX <= width + 1)
                #expect(frame.height >= 400)
                let visibleButtons = descendants(host).compactMap { $0 as? NSButton }
                #expect(!visibleButtons.contains { $0.title.contains("Move Selected Notes") || $0.title.contains("Last Batch Result") })
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
