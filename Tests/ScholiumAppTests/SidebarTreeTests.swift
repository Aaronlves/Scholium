import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Library folder tree")
struct SidebarTreeTests {
    @Test("App-owned Attachments storage stays outside the Library hierarchy")
    func attachmentStorageIsNotProjected() {
        let projection = LibraryTreeProjection(
            preorderedNotes: [
                .syntheticPreview(
                    relativePath: "Research/Visible.md",
                    rawContent: "# Visible\n"
                ),
                .syntheticPreview(
                    relativePath: "Attachments/id/Attached.md",
                    rawContent: "# Attached file\n"
                ),
            ],
            folderRelativePaths: [
                "Research",
                "Attachments",
                "Attachments/id",
            ]
        )

        #expect(projection.roots.map(\.id) == ["Research"])
        #expect(
            projection.roots.flatMap(\.children).map(\.id)
                == ["Research/Visible.md"]
        )
        #expect(!WorkspaceLibraryVisibility.includes("Attachments"))
        #expect(!WorkspaceLibraryVisibility.includes("Attachments/id/file.pdf"))
        #expect(WorkspaceLibraryVisibility.includes("Research/Attachments.md"))
    }

    @Test("Window tree cache ignores unrelated presentation publications")
    @MainActor
    func windowTreeProjectionCache() {
        let notes = [
            WindowDocumentLocation.syntheticPreview(
                relativePath: "Cluster/Note.md",
                rawContent: "# Note\n"
            )
        ]
        let cache = LibraryTreeProjectionCache()
        let first = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty"]
        )
        let repeated = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty"]
        )

        #expect(repeated.revision == first.revision)
        #expect(repeated.value.roots.map(\.id) == ["Cluster", "Empty"])

        let changed = cache.projection(
            preorderedNotes: notes,
            folderRelativePaths: ["Empty", "Second"]
        )
        #expect(changed.revision == first.revision + 1)

        let revisedNotes = [
            WindowDocumentLocation.syntheticPreview(
                relativePath: "Cluster/Note.md",
                rawContent: "# Revised\n"
            )
        ]
        let revised = cache.projection(
            preorderedNotes: revisedNotes,
            folderRelativePaths: ["Empty", "Second"]
        )
        #expect(revised.revision == changed.revision + 1)
        #expect(
            revised.value.roots
                .first(where: { $0.id == "Cluster" })?
                .children.first?
                .note?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: "# Revised\n")
        )
    }

    @Test("Ten thousand sibling folders build one bounded adjacency projection")
    func largeSiblingFolderProjection() {
        let folders = (0..<10_000).map { index in
            "Cluster-\(String(format: "%05d", index))"
        }
        let clock = ContinuousClock()
        let start = clock.now
        let projection = LibraryTreeProjection(
            preorderedNotes: [],
            folderRelativePaths: folders
        )
        let elapsed = start.duration(to: clock.now)
        print("LibraryTreeProjection diagnostic: 10,000 sibling folders in \(elapsed)")

        #expect(projection.roots.count == folders.count)
        #expect(projection.expandableFolderIDs.isEmpty)
        #expect(elapsed < .seconds(2))
    }

    @Test("Ten thousand preordered Notes build one bounded hierarchy projection")
    func largePreorderedNoteProjection() throws {
        let notes = (0..<10_000).map { index in
            WindowDocumentLocation.syntheticPreview(
                relativePath: "Cluster/Note-\(String(format: "%05d", index)).md",
                rawContent: ""
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let projection = LibraryTreeProjection(
            preorderedNotes: notes
        )
        let elapsed = start.duration(to: clock.now)
        print("LibraryTreeProjection diagnostic: 10,000 preordered Notes in \(elapsed)")

        let folder = try #require(projection.roots.first)
        #expect(folder.id == "Cluster")
        #expect(folder.children.count == notes.count)
        #expect(folder.children.first?.id == "Cluster/Note-00000.md")
        #expect(folder.children.last?.id == "Cluster/Note-09999.md")
        #expect(elapsed < .seconds(2))
    }

    @Test("Context menus and accessibility actions share one file-command projection")
    func noteCommandProjection() {
        let workspaceMenu = sidebarNoteCommandGroups().flatMap(\.commands)
        #expect(
            workspaceMenu == [
                .openInNewTab,
                .openInSeparateWindow,
                .addToChat,
                .duplicate,
                .move,
                .revealInFinder,
                .copyRelativePath,
                .moveToSystemTrash,
            ])

    }

    @MainActor
    @Test("Native Chat action follows the selected Note and rejects stale selection or teardown")
    func nativeChatAccessibilityAction() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        let projection = LibraryTreeProjection(preorderedNotes: notes)
        var available = true
        var added: [String] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            canAddNoteToChat: { _ in available }, addNoteToChat: { added.append($0.relativePath) })
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        coordinator.apply(configuration: configuration)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        let outline = fixture.outlineView
        #expect(outline.chatAccessibilityAction?() == nil)
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let first = try #require(outline.accessibilityCustomActions()?.first { $0.name == "Add to Chat" })
        #expect(first.handler?() == true)
        #expect(added == ["First.md"])
        outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(first.handler?() == false)
        let second = try #require(outline.chatAccessibilityAction?())
        available = false
        #expect(second.handler?() == false)
        #expect(outline.chatAccessibilityAction?() == nil)
        available = true
        coordinator.detach(from: fixture.scrollView)
        #expect(second.handler?() == false)
        #expect(outline.chatAccessibilityAction == nil)
        #expect(added == ["First.md"])
    }

    @MainActor
    @Test("Native multiple selection survives document changes and blocks mixed-item mutations")
    func nativeMultipleSelection() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        let projection = LibraryTreeProjection(preorderedNotes: notes, folderRelativePaths: ["Folder"])
        var selectionEvents: [Set<String>] = []
        var opened: [String] = []
        var moved: [[NoteMutationTarget]] = []
        var trashed: [[NoteMutationTarget]] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            selectedDocumentPath: "First.md", revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            selectedRowIDs: ["First.md", "Second.md"], canMutate: true,
            onSelectionChange: { selectionEvents.append($0) }, onSelect: { opened.append($0.relativePath) },
            onBatchMove: { moved.append($0) }, onBatchTrash: { trashed.append($0) })
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        let outline = fixture.outlineView
        coordinator.apply(configuration: configuration)
        #expect(outline.selectedRowIndexes.count == 2)
        #expect(selectionEvents.isEmpty)
        #expect(opened.isEmpty)
        #expect(outline.openSelection?() == false)
        #expect(outline.chatAccessibilityAction?() == nil)
        let moveAction = try #require(outline.selectionAccessibilityActions?().first)
        #expect(moveAction.handler?() == true)
        #expect(moved.first?.count == 2)
        #expect(outline.trashSelection?() == true)
        #expect(trashed.first?.count == 2)
        coordinator.apply(configuration: configuration)
        #expect(outline.selectedRowIndexes.count == 2)
        #expect(opened.isEmpty)
        let folderRow = try #require(
            (0..<outline.numberOfRows).first {
                (outline.item(atRow: $0) as? SidebarOutlineItem)?.node.isFolder == true
            })
        outline.selectRowIndexes(IndexSet(integer: folderRow), byExtendingSelection: true)
        #expect(selectionEvents.last?.count == 3)
        #expect(opened.isEmpty)
        #expect(outline.trashSelection?() == false)
        #expect(outline.selectionAccessibilityActions?().isEmpty == true)
        #expect(moveAction.handler?() == false)
        #expect(outline.canDragRows(with: outline.selectedRowIndexes, at: .zero) == false)
        let menu = try #require(outline.selectionMenuProvider?(folderRow))
        #expect(menu.items.allSatisfy { !$0.isEnabled })
    }

    @MainActor
    @Test("Secondary selection names its Note without opening it and retains a selected group")
    func contextualSelectionAndFocus() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        let projection = LibraryTreeProjection(preorderedNotes: notes)
        var selected: [Set<String>] = []
        var opened: [String] = []
        var copied: [String] = []
        var configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            selectedDocumentPath: "First.md", revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            canMutate: true, onSelectionChange: { selected.append($0) },
            onSelect: { opened.append($0.relativePath) }, copyRelativePath: { copied.append($0) }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        let outline = fixture.outlineView
        let secondRow = try #require(
            (0..<outline.numberOfRows).first {
                (outline.item(atRow: $0) as? SidebarOutlineItem)?.id == "Second.md"
            })
        let menu = try #require(outline.contextMenu(forRow: secondRow))
        #expect(outline.selectedRowIndexes == IndexSet(integer: secondRow))
        #expect(selected.last == ["Second.md"])
        #expect(opened.isEmpty)
        #expect(fixture.window.firstResponder === outline)
        #expect(menu.accessibilityIdentifier() == "scholium.noteRow.Second.md")
        let copyIndex = try #require(menu.items.firstIndex { $0.title == "Copy Relative Path" })
        menu.performActionForItem(at: copyIndex)
        #expect(copied == ["Second.md"])
        let cell = try #require(
            outline.view(atColumn: 0, row: secondRow, makeIfNecessary: true) as? SidebarOutlineCell
        )
        #expect(cell.textField === cell.titleLabel)
        #expect(cell.titleLabel.accessibilityLabel() == notes[1].title)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.noteRow.Second.md")
        #expect(cell.titleLabel.accessibilityCustomActions()?.contains { $0.name == "Copy Relative Path" } == true)

        configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            selectedRowIDs: ["First.md", "Second.md"], canMutate: true,
            onSelect: { opened.append($0.relativePath) }
        )
        coordinator.apply(configuration: configuration)
        let groupMenu = try #require(outline.contextMenu(forRow: secondRow))
        #expect(outline.selectedRowIndexes.count == 2)
        #expect(groupMenu.items.map(\.title) == ["Move Notes…", "Move to Trash…"])
        #expect(opened.isEmpty)
    }

    @MainActor
    @Test("Native primary activation opens unchanged contextual selection and rejects modified or invalid clicks")
    func primaryClickOpensUnchangedSelection() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        var opened: [String] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: LibraryTreeProjection(preorderedNotes: notes, folderRelativePaths: ["Folder"]).roots,
            notes: notes, scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            selectedDocumentPath: "First.md", revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            onSelect: { opened.append($0.relativePath) }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        let outline = fixture.outlineView
        let secondRow = try #require(
            (0..<outline.numberOfRows).first {
                (outline.item(atRow: $0) as? SidebarOutlineItem)?.id == "Second.md"
            })
        #expect(outline.contextMenu(forRow: secondRow) != nil)
        #expect(opened.isEmpty)
        let primaryClick = try #require(outline.primaryClickHandler)
        #expect(outline.target === outline)
        #expect(outline.action != nil)
        let modifiers: [NSEvent.ModifierFlags] = [.command, .shift, .control]
        for modifier in modifiers {
            #expect(primaryClick(secondRow, modifier) == false)
        }
        #expect(primaryClick(-1, []) == false)
        #expect(opened.isEmpty)
        // Simulate one click already recognized by NSTableView; the selected
        // row is unchanged, so no selection-change notification can open it.
        #expect(primaryClick(secondRow, []) == true)
        #expect(opened == ["Second.md"])
        #expect(outline.openSelection?() == true)
        #expect(opened == ["Second.md", "Second.md"])
        outline.isHidden = true
        #expect(primaryClick(secondRow, []) == false)
        outline.isHidden = false
        coordinator.detach(from: fixture.scrollView)
        #expect(primaryClick(secondRow, []) == false)
        #expect(outline.action == nil)
        #expect(opened == ["Second.md", "Second.md"])
    }

    @MainActor
    @Test("Option-click retains ordinary Note opening while selection and contextual modifiers still take precedence")
    func optionClickRetainsOrdinaryOpening() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        var opened: [String] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: LibraryTreeProjection(preorderedNotes: notes).roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
            selectedDocumentPath: "First.md", revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            onSelect: { opened.append($0.relativePath) }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        let outline = fixture.outlineView
        let secondRow = try #require(
            (0..<outline.numberOfRows).first {
                (outline.item(atRow: $0) as? SidebarOutlineItem)?.id == "Second.md"
            })
        #expect(outline.contextMenu(forRow: secondRow) != nil)
        let primaryClick = try #require(outline.primaryClickHandler)
        #expect(primaryClick(secondRow, [.option, .command]) == false)
        #expect(primaryClick(secondRow, [.option, .shift]) == false)
        #expect(primaryClick(secondRow, [.option, .control]) == false)
        #expect(opened.isEmpty)
        #expect(primaryClick(secondRow, .option) == true)
        #expect(opened == ["Second.md"])
    }

    @MainActor
    @Test("Native cells retain semantic colors, selection adaptation and item identity across system appearances")
    func nativeCellSemanticAdaptation() throws {
        _ = NSApplication.shared
        let note = WindowDocumentLocation.syntheticPreview(relativePath: "示例 Note.md", rawContent: "# Example\n")
        let node = try #require(LibraryTreeProjection(preorderedNotes: [note]).roots.first)
        let cell = SidebarOutlineCell(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        cell.configure(
            item: SidebarOutlineItem(node: node), isExpanded: false,
            nativeStrings: .init(locale: Locale(identifier: "zh-Hans")),
            presentation: .init(effectiveRowSizeStyle: .default)
        )
        let generation = cell.representationGeneration
        let identifier = cell.titleLabel.accessibilityIdentifier()
        func channels(_ color: NSColor, appearance: NSAppearance) throws -> [CGFloat] {
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
            let rgb = try #require(resolved)
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        }
        var normalColors: [NSAppearance.Name: [CGFloat]] = [:]
        let appearances: [NSAppearance.Name] = [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]
        for name in appearances {
            let appearance = try #require(NSAppearance(named: name))
            cell.appearance = appearance
            let styles: [NSView.BackgroundStyle] = [.normal, .emphasized, .normal]
            for style in styles {
                cell.backgroundStyle = style
                let title = try #require(cell.titleLabel.textColor)
                let icon = try #require(cell.imageView?.contentTintColor)
                let expectedTitle: NSColor =
                    style == .emphasized
                    ? .alternateSelectedControlTextColor : ScholiumColorRole.primaryText.nsColor
                let expectedIcon: NSColor =
                    style == .emphasized
                    ? .alternateSelectedControlTextColor : ScholiumColorRole.secondaryText.nsColor
                #expect(try channels(title, appearance: appearance) == channels(expectedTitle, appearance: appearance))
                #expect(try channels(icon, appearance: appearance) == channels(expectedIcon, appearance: appearance))
                if style == .normal { normalColors[name] = try channels(title, appearance: appearance) }
                #expect(cell.titleLabel.accessibilityIdentifier() == identifier)
                #expect(cell.titleLabel.accessibilityLabel() == note.title)
                #expect(cell.titleLabel.toolTip == note.title)
                #expect(cell.representationGeneration == generation)
                #expect(cell.titleLabel.font?.pointSize == NSFont.systemFontSize(for: .regular))
            }
        }
        #expect(normalColors[.aqua] != normalColors[.darkAqua])
        func containsMaterial(_ view: NSView) -> Bool {
            view is NSVisualEffectView || view.subviews.contains(where: containsMaterial)
        }
        // The native sidebar/row own material and transition adaptation. The
        // cell adds no blur, opacity treatment, background or app animation.
        #expect(!containsMaterial(cell))
        #expect(cell.alphaValue == 1)
        #expect(!cell.titleLabel.drawsBackground)
        #expect(cell.layer?.backgroundColor == nil)
        #expect((cell.layer?.animationKeys() ?? []).isEmpty)
    }

    @MainActor
    @Test("Native cells reuse unchanged content while refreshing titles, disclosure, locale and row size")
    func nativeCellContentRefresh() throws {
        _ = NSApplication.shared
        let strings = SidebarNativeStrings(locale: Locale(identifier: "en_US"))
        let presentation = SidebarSourceListRowPresentation(effectiveRowSizeStyle: .default)
        let note = WindowDocumentLocation.syntheticPreview(relativePath: "Original.md", rawContent: "")
        let item = SidebarOutlineItem(node: try #require(LibraryTreeProjection(preorderedNotes: [note]).roots.first))
        let cell = SidebarOutlineCell(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        cell.configure(item: item, isExpanded: false, nativeStrings: strings, presentation: presentation)
        let image = try #require(cell.imageView?.image)
        let generation = cell.representationGeneration
        cell.configure(item: item, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(cell.imageView?.image === image)
        #expect(cell.representationGeneration == generation)

        let renamed = WindowDocumentLocation.syntheticPreview(relativePath: "Renamed.md", rawContent: "")
        item.node = try #require(LibraryTreeProjection(preorderedNotes: [renamed]).roots.first)
        cell.configure(item: item, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.stringValue == "Renamed")
        #expect(cell.titleLabel.accessibilityLabel() == "Renamed")
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.noteRow.Renamed.md")
        #expect(cell.titleLabel.toolTip == "Renamed")
        #expect(cell.imageView?.image === image)

        let nested = WindowDocumentLocation.syntheticPreview(relativePath: "Folder/Nested.md", rawContent: "")
        let folder = SidebarOutlineItem(node: try #require(LibraryTreeProjection(preorderedNotes: [nested]).roots.first))
        folder.children = folder.node.children.map(SidebarOutlineItem.init)
        cell.configure(item: folder, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.folderRow.Folder")
        #expect(cell.titleLabel.accessibilityValue() as? String == "Collapsed")
        let folderImage = try #require(cell.imageView?.image)
        cell.configure(item: folder, isExpanded: true, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.accessibilityValue() as? String == "Expanded")
        #expect(cell.imageView?.image === folderImage)

        let chinese = SidebarNativeStrings(locale: Locale(identifier: "zh-Hans"))
        cell.configure(item: folder, isExpanded: true, nativeStrings: chinese, presentation: presentation)
        #expect(cell.titleLabel.accessibilityValue() as? String == "已展开")
        let large = SidebarSourceListRowPresentation(effectiveRowSizeStyle: .large)
        cell.configure(item: folder, isExpanded: true, nativeStrings: chinese, presentation: large)
        #expect(cell.titleLabel.font?.pointSize == NSFont.systemFontSize(for: .large))
        let expectedLargeImage = try #require(
            NSImage(systemSymbolName: ScholiumSidebarItem.folder.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: large.textPointSize, weight: .regular)))
        #expect(cell.imageView?.image?.size == expectedLargeImage.size)
        folder.children = []
        cell.configure(item: folder, isExpanded: true, nativeStrings: chinese, presentation: large)
        #expect(cell.titleLabel.accessibilityValue() as? String == "空文件夹")
        folder.children = folder.node.children.map(SidebarOutlineItem.init)

        cell.prepareForReuse()
        cell.configure(item: folder, isExpanded: true, nativeStrings: chinese, presentation: large)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.folderRow.Folder")
        #expect(cell.titleLabel.accessibilityLabel() == "Folder")
        #expect(cell.titleLabel.accessibilityValue() as? String == "已展开")
    }

    @MainActor
    @Test("A canonically equivalent rename refreshes exact row identity and label bytes")
    func nativeCellExactPathRefresh() throws {
        let cell = SidebarOutlineCell(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        let strings = SidebarNativeStrings(locale: Locale(identifier: "en_US"))
        let presentation = SidebarSourceListRowPresentation(effectiveRowSizeStyle: .default)
        let first = WindowDocumentLocation.syntheticPreview(relativePath: "Caf\u{e9}.md", rawContent: "")
        let renamed = WindowDocumentLocation.syntheticPreview(relativePath: "Cafe\u{301}.md", rawContent: "")
        let item = SidebarOutlineItem(node: try #require(LibraryTreeProjection(preorderedNotes: [first]).roots.first))
        cell.configure(item: item, isExpanded: false, nativeStrings: strings, presentation: presentation)
        item.node = try #require(LibraryTreeProjection(preorderedNotes: [renamed]).roots.first)
        cell.configure(item: item, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.stringValue.utf8.elementsEqual("Cafe\u{301}".utf8))
        #expect(cell.titleLabel.accessibilityIdentifier().utf8.elementsEqual("scholium.noteRow.Cafe\u{301}.md".utf8))
        #expect(cell.titleLabel.accessibilityLabel()?.utf8.elementsEqual("Cafe\u{301}".utf8) == true)
        #expect(cell.titleLabel.toolTip?.utf8.elementsEqual("Cafe\u{301}".utf8) == true)
    }

    @MainActor
    @Test("Captured row menus and accessibility actions reject hidden, removed and detached targets")
    func contextualActionsRejectStaleLifecycle() throws {
        let vaultID = UUID()
        let note = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Note.md", source: "# Note\n")
        let projection = LibraryTreeProjection(preorderedNotes: [note])
        var copied: [String] = []
        func configuration(roots: [TreeNode], revision: UInt64 = 1) -> SidebarOutlineSourceList {
            makeSidebarCoordinatorConfiguration(
                roots: roots, notes: [note],
                scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
                revealRequest: nil, requestedFocusPath: nil,
                onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
                copyRelativePath: { copied.append($0) }, projectionRevision: revision
            )
        }
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration(roots: projection.roots))
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration(roots: projection.roots))
        let outline = fixture.outlineView
        let menu = try #require(outline.contextMenu(forRow: 0))
        let index = try #require(menu.items.firstIndex { $0.title == "Copy Relative Path" })
        let cell = try #require(outline.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SidebarOutlineCell)
        let action = try #require(cell.titleLabel.accessibilityCustomActions()?.first { $0.name == "Copy Relative Path" })
        outline.isHidden = true
        #expect(outline.contextMenu(forRow: 0) == nil)
        menu.performActionForItem(at: index)
        #expect(action.handler?() == false)
        outline.isHidden = false
        menu.performActionForItem(at: index)
        #expect(copied.isEmpty)
        let currentMenu = try #require(outline.contextMenu(forRow: 0))
        let currentIndex = try #require(currentMenu.items.firstIndex { $0.title == "Copy Relative Path" })
        currentMenu.performActionForItem(at: currentIndex)
        #expect(copied == ["Note.md"])
        coordinator.apply(configuration: configuration(roots: [], revision: 2))
        currentMenu.performActionForItem(at: currentIndex)
        #expect(action.handler?() == false)
        #expect(copied == ["Note.md"])
        coordinator.detach(from: fixture.scrollView)
        currentMenu.performActionForItem(at: currentIndex)
        #expect(outline.delegate == nil)
        #expect(outline.dataSource == nil)
        #expect(copied == ["Note.md"])
    }

    @MainActor
    @Test("Native label exposes Note identity and rejects actions retained across cell reuse")
    func nativeCellLabelAndActionReuse() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md", "Folder/Nested.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        var copied: [String] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: LibraryTreeProjection(preorderedNotes: notes).roots, notes: notes,
            scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: ["Folder"],
            revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
            copyRelativePath: { copied.append($0) }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        let outline = fixture.outlineView
        func item(_ id: String) throws -> SidebarOutlineItem {
            try #require(
                (0..<outline.numberOfRows).compactMap {
                    outline.item(atRow: $0) as? SidebarOutlineItem
                }.first { $0.id == id })
        }
        let first = try item("First.md")
        let second = try item("Second.md")
        let folder = try item("Folder")
        let cell = try #require(
            outline.view(atColumn: 0, row: outline.row(forItem: first), makeIfNecessary: true) as? SidebarOutlineCell
        )
        #expect(cell.textField === cell.titleLabel)
        #expect(cell.titleLabel.accessibilityRole() == .staticText)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.noteRow.First.md")
        #expect(cell.titleLabel.toolTip == notes[0].title)
        #expect(cell.imageView?.isAccessibilityElement() == false)
        let action = try #require(
            cell.titleLabel.accessibilityCustomActions()?.first {
                $0.name == "Copy Relative Path"
            })
        #expect(action.handler?() == true)
        #expect(copied == ["First.md"])
        cell.prepareForReuse()
        #expect(action.handler?() == false)
        #expect(cell.titleLabel.actionProvider == nil)
        #expect((cell.titleLabel.accessibilityIdentifier() ?? "").isEmpty)
        let strings = SidebarNativeStrings(locale: Locale(identifier: "en_US"))
        let presentation = SidebarSourceListRowPresentation(effectiveRowSizeStyle: .default)
        cell.configure(item: second, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.noteRow.Second.md")
        #expect(action.handler?() == false)
        cell.configure(item: first, isExpanded: false, nativeStrings: strings, presentation: presentation)
        #expect(action.handler?() == false)
        cell.configure(item: folder, isExpanded: true, nativeStrings: strings, presentation: presentation)
        #expect(cell.titleLabel.accessibilityIdentifier() == "scholium.folderRow.Folder")
        #expect(cell.titleLabel.accessibilityLabel() == "Folder")
        #expect(cell.titleLabel.accessibilityValue() as? String == "Expanded")
        #expect(copied == ["First.md"])
    }

    @MainActor
    @Test("An open menu ends when its exact Note snapshot changes, while unrelated updates retain it")
    func contextualMenuSnapshotInvalidation() throws {
        let vaultID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let first = workspaceNote(vaultID: vaultID, stableID: firstID, path: "First.md", source: "# First\n")
        let second = workspaceNote(vaultID: vaultID, stableID: secondID, path: "Second.md", source: "# Second\n")
        var copied: [String] = []
        func configuration(notes: [WindowDocumentLocation], revision: UInt64) -> SidebarOutlineSourceList {
            makeSidebarCoordinatorConfiguration(
                roots: LibraryTreeProjection(preorderedNotes: notes).roots, notes: notes,
                scope: .init(vaultID: vaultID, sourceScope: .library), expandedFolderIDs: [],
                revealRequest: nil, requestedFocusPath: nil,
                onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {},
                selectedRowIDs: ["First.md"], copyRelativePath: { copied.append($0) },
                projectionRevision: revision
            )
        }
        let initial = configuration(notes: [first, second], revision: 1)
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: initial)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: initial)
        let menu = try #require(fixture.outlineView.contextMenu(forRow: 0))
        let copyIndex = try #require(menu.items.firstIndex { $0.title == "Copy Relative Path" })
        let updatedSecond = workspaceNote(
            vaultID: vaultID, stableID: secondID, path: "Second.md", source: "# Second revised\n"
        )
        coordinator.apply(configuration: configuration(notes: [first, updatedSecond], revision: 2))
        #expect(menu.delegate === coordinator)
        menu.performActionForItem(at: copyIndex)
        #expect(copied == ["First.md"])
        let updatedFirst = workspaceNote(
            vaultID: vaultID, stableID: firstID, path: "First.md", source: "# First revised\n"
        )
        coordinator.apply(configuration: configuration(notes: [updatedFirst, updatedSecond], revision: 3))
        #expect(menu.delegate == nil)
        menu.performActionForItem(at: copyIndex)
        #expect(copied == ["First.md"])
    }

    @MainActor
    @Test("Hidden Library defers reveal and focus until it can own the responder again")
    func hiddenLibraryDefersFocusAndReveal() async throws {
        let vaultID = UUID()
        let note = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Folder/Note.md", source: "# Note\n")
        let projection = LibraryTreeProjection(preorderedNotes: [note])
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        var reveals = 0
        var focuses = 0
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: [note], scope: scope, expandedFolderIDs: ["Folder"],
            selectedDocumentPath: note.relativePath,
            revealRequest: .init(generation: 1, scope: scope, relativePath: note.relativePath, alignment: .nearest),
            requestedFocusPath: note.relativePath,
            onConsumeRevealRequest: { _ in reveals += 1 }, onFocusRequestHandled: { focuses += 1 }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        fixture.outlineView.isHidden = true
        try await Task.sleep(for: .milliseconds(25))
        #expect(reveals == 0)
        #expect(focuses == 0)
        fixture.outlineView.isHidden = false
        try await Task.sleep(for: .milliseconds(25))
        #expect(reveals == 1)
        #expect(focuses == 1)
        #expect(fixture.window.firstResponder === fixture.outlineView)
    }

    @MainActor
    @Test("Repeated focus intent for the same row is handled and removed targets cannot finish queued work")
    func repeatedFocusAndRemovedTarget() async throws {
        let vaultID = UUID()
        let note = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Note.md", source: "# Note\n")
        let projection = LibraryTreeProjection(preorderedNotes: [note])
        var focuses = 0
        func configuration(roots: [TreeNode], revision: UInt64, generation: UInt64) -> SidebarOutlineSourceList {
            makeSidebarCoordinatorConfiguration(
                roots: roots, notes: [note], scope: .init(vaultID: vaultID, sourceScope: .library),
                expandedFolderIDs: [], revealRequest: nil, requestedFocusPath: note.relativePath,
                onConsumeRevealRequest: { _ in }, onFocusRequestHandled: { focuses += 1 },
                projectionRevision: revision, focusRequestGeneration: generation
            )
        }
        let initial = configuration(roots: projection.roots, revision: 1, generation: 1)
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: initial)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: initial)
        try await Task.sleep(for: .milliseconds(25))
        #expect(focuses == 1)
        coordinator.apply(configuration: configuration(roots: projection.roots, revision: 1, generation: 2))
        try await Task.sleep(for: .milliseconds(25))
        #expect(focuses == 2)
        coordinator.apply(configuration: configuration(roots: projection.roots, revision: 1, generation: 3))
        coordinator.apply(configuration: configuration(roots: [], revision: 2, generation: 3))
        try await Task.sleep(for: .milliseconds(25))
        #expect(focuses == 2)
    }

    @MainActor
    @Test("Native multi-item pasteboard retains every Note and rejects mixed or duplicate payloads")
    func nativeMultipleNoteDragPayload() throws {
        let vaultID = UUID()
        let notes = ["First.md", "Second.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        let payloads = try notes.map { SidebarNoteDragItem(try #require(NoteMutationTarget($0))) }
        func item(_ payload: SidebarNoteDragItem) throws -> NSPasteboardItem {
            let item = NSPasteboardItem()
            item.setData(try JSONEncoder().encode(payload), forType: sidebarNativeDraggingTypes[0])
            return item
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(try payloads.map(item))
        guard case .notes(let decoded) = sidebarNativeDragPayload(from: pasteboard) else {
            Issue.record("Expected the complete note group")
            return
        }
        #expect(decoded.map(\.mutationTarget) == payloads.map(\.mutationTarget))
        var committed: [SidebarNoteDragItem] = []
        commitSidebarNativeDrop(
            .notes(decoded), folderRelativePath: "Target",
            onMoveNote: { _, _ in
                Issue.record("Must not split the batch into single-note operations")
            }, onMoveFolder: { _, _ in }, onMoveNotes: { items, _ in committed = items })
        #expect(committed.count == 2)
        pasteboard.clearContents()
        pasteboard.writeObjects([try item(payloads[0]), try item(payloads[0])])
        #expect(sidebarNativeDragPayload(from: pasteboard) == nil)
        let folderItem = NSPasteboardItem()
        folderItem.setData(
            try JSONEncoder().encode(SidebarFolderDragItem(.init(vaultID: vaultID, relativePath: "Folder"))),
            forType: sidebarNativeDraggingTypes[1])
        pasteboard.clearContents()
        pasteboard.writeObjects([try item(payloads[0]), folderItem])
        #expect(sidebarNativeDragPayload(from: pasteboard) == nil)
    }

    @MainActor
    @Test("The native tree accepts root gaps and Folder destinations for Notes and Folders")
    func nativeOutlineMoveDestinations() throws {
        let vaultID = UUID()
        let source = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Source/Note.md", source: "# Note\n")
        let other = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Source/Other.md", source: "# Other\n")
        let folders: Set<String> = ["Source", "Source/Group", "Source/Group/Child", "Target", "Target/Nested"]
        let notes = [source, other]
        let projection = LibraryTreeProjection(preorderedNotes: notes, folderRelativePaths: Array(folders))
        let inventory = SidebarTreeDropInventory(
            currentVaultID: vaultID, sourceScope: .library, currentVaultRole: .other, canMutate: true,
            notes: notes, folderRelativePaths: folders,
            pathComparisonPolicy: .init(caseSensitive: true, normalizationSensitive: true),
            pendingNoteMoves: [], pendingFolderMoves: [])
        var noteDestinations: [String?] = []
        var folderDestinations: [String?] = []
        var groups: [[SidebarNoteDragItem]] = []
        let configuration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots, notes: notes, scope: .init(vaultID: vaultID, sourceScope: .library),
            expandedFolderIDs: projection.expandableFolderIDs, revealRequest: nil, requestedFocusPath: nil,
            onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {}, canMutate: true,
            dropInventory: inventory, onMoveNoteDrop: { _, folder in noteDestinations.append(folder) },
            onMoveFolderDrop: { _, folder in folderDestinations.append(folder) },
            onMoveNotesDrop: { items, folder in
                #expect(folder == nil)
                groups.append(items)
            })
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        let outline = fixture.outlineView
        defer {
            coordinator.detach(from: fixture.scrollView)
            fixture.window.close()
        }
        coordinator.apply(configuration: configuration)
        func item(_ path: String) throws -> SidebarOutlineItem {
            try #require((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarOutlineItem }.first { $0.id == path })
        }
        let drag = SidebarTreeDraggingInfo(source: outline, window: fixture.window)
        defer { drag.draggingPasteboard.releaseGlobally() }
        try drag.setPayload(SidebarNoteDragItem(try #require(NoteMutationTarget(source))), type: sidebarNativeDraggingTypes[0])

        for index in [0, projection.roots.count, NSOutlineViewDropOnItemIndex] {
            #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: index) == .move)
            #expect(coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: index))
        }
        #expect(noteDestinations.count == 3)
        #expect(noteDestinations.allSatisfy { $0 == nil })
        for path in ["Target", "Target/Nested"] {
            let target = try item(path)
            #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: target, proposedChildIndex: 0) == .move)
            #expect(coordinator.outlineView(outline, acceptDrop: drag, item: target, childIndex: NSOutlineViewDropOnItemIndex))
        }
        #expect(noteDestinations.suffix(2) == ["Target", "Target/Nested"])
        let nestedTarget = try item("Target/Nested")
        let parentTarget = try item("Target")
        outline.collapseItem(parentTarget)
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: nestedTarget, childIndex: NSOutlineViewDropOnItemIndex))
        #expect(noteDestinations.count == 5)
        outline.expandItem(parentTarget)
        #expect(
            coordinator.outlineView(outline, validateDrop: drag, proposedItem: try item(source.relativePath), proposedChildIndex: NSOutlineViewDropOnItemIndex)
                .isEmpty)
        #expect(
            coordinator.outlineView(outline, validateDrop: drag, proposedItem: try item("Source"), proposedChildIndex: NSOutlineViewDropOnItemIndex).isEmpty)
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: projection.roots.count + 1).isEmpty)

        try drag.setPayload(SidebarFolderDragItem(.init(vaultID: vaultID, relativePath: "Source/Group")), type: sidebarNativeDraggingTypes[1])
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0) == .move)
        #expect(coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        #expect(
            coordinator.outlineView(outline, validateDrop: drag, proposedItem: try item("Target"), proposedChildIndex: NSOutlineViewDropOnItemIndex) == .move)
        #expect(coordinator.outlineView(outline, acceptDrop: drag, item: try item("Target"), childIndex: NSOutlineViewDropOnItemIndex))
        #expect(folderDestinations.count == 2)
        #expect(folderDestinations[0] == nil)
        #expect(folderDestinations[1] == "Target")
        for path in ["Source", "Source/Group", "Source/Group/Child"] {
            #expect(
                coordinator.outlineView(outline, validateDrop: drag, proposedItem: try item(path), proposedChildIndex: NSOutlineViewDropOnItemIndex).isEmpty)
        }
        try drag.setPayload(SidebarFolderDragItem(.init(vaultID: vaultID, relativePath: "Source")), type: sidebarNativeDraggingTypes[1])
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0).isEmpty)
        let foreign = workspaceNote(vaultID: UUID(), stableID: UUID(), path: source.relativePath, source: "# Note\n")
        try drag.setPayload(SidebarNoteDragItem(try #require(NoteMutationTarget(foreign))), type: sidebarNativeDraggingTypes[0])
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0).isEmpty)

        let payloads = try notes.map { SidebarNoteDragItem(try #require(NoteMutationTarget($0))) }
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.writeObjects(
            try payloads.map { payload in
                let item = NSPasteboardItem()
                item.setData(try JSONEncoder().encode(payload), forType: sidebarNativeDraggingTypes[0])
                return item
            })
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0) == .move)
        #expect(coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        #expect(groups.first?.map(\.mutationTarget) == payloads.map(\.mutationTarget))
        let parentRow = outline.row(forItem: try item("Source"))
        let childRow = outline.row(forItem: try item(source.relativePath))
        #expect(!outline.canDragRows(with: IndexSet([parentRow, childRow]), at: .zero))
    }

    @MainActor
    @Test("Drop commit rechecks revisions, target lifetime, visible ownership and process-private payloads")
    func nativeOutlineDropRevalidation() throws {
        let vaultID = UUID()
        let stableID = UUID()
        let source = workspaceNote(vaultID: vaultID, stableID: stableID, path: "Source/Note.md", source: "# Note\n")
        var commits = 0
        func configuration(notes: [WindowDocumentLocation], folders: Set<String>, revision: UInt64) -> SidebarOutlineSourceList {
            let projection = LibraryTreeProjection(preorderedNotes: notes, folderRelativePaths: Array(folders))
            return makeSidebarCoordinatorConfiguration(
                roots: projection.roots, notes: notes, scope: .init(vaultID: vaultID, sourceScope: .library),
                expandedFolderIDs: projection.expandableFolderIDs, revealRequest: nil, requestedFocusPath: nil,
                onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {}, canMutate: true,
                projectionRevision: revision,
                dropInventory: .init(
                    currentVaultID: vaultID, sourceScope: .library, currentVaultRole: .other, canMutate: true,
                    notes: notes, folderRelativePaths: folders,
                    pathComparisonPolicy: .init(caseSensitive: true, normalizationSensitive: true),
                    pendingNoteMoves: [], pendingFolderMoves: []),
                onMoveNoteDrop: { _, _ in commits += 1 })
        }
        let initial = configuration(notes: [source], folders: ["Source", "Target"], revision: 1)
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: initial)
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        let outline = fixture.outlineView
        defer { fixture.window.close() }
        coordinator.apply(configuration: initial)
        let target = try #require((0..<outline.numberOfRows).compactMap { outline.item(atRow: $0) as? SidebarOutlineItem }.first { $0.id == "Target" })
        let drag = SidebarTreeDraggingInfo(source: outline, window: fixture.window)
        defer { drag.draggingPasteboard.releaseGlobally() }
        let payload = SidebarNoteDragItem(try #require(NoteMutationTarget(source)))
        try drag.setPayload(payload, type: sidebarNativeDraggingTypes[0])
        #expect(coordinator.outlineView(outline, validateDrop: drag, proposedItem: target, proposedChildIndex: NSOutlineViewDropOnItemIndex) == .move)

        let changed = workspaceNote(vaultID: vaultID, stableID: stableID, path: source.relativePath, source: "# External change\n")
        coordinator.apply(configuration: configuration(notes: [changed], folders: ["Source", "Target"], revision: 2))
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: target, childIndex: NSOutlineViewDropOnItemIndex))
        coordinator.apply(configuration: configuration(notes: [source], folders: ["Source"], revision: 3))
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: target, childIndex: NSOutlineViewDropOnItemIndex))
        coordinator.apply(configuration: initial)
        outline.isHidden = true
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        outline.isHidden = false
        drag.draggingSource = nil
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        drag.draggingSource = outline
        drag.draggingPasteboard.clearContents()
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        try drag.setPayload(payload, type: sidebarNativeDraggingTypes[0])
        coordinator.detach(from: fixture.scrollView)
        #expect(!coordinator.outlineView(outline, acceptDrop: drag, item: nil, childIndex: 0))
        #expect(commits == 0)
    }

    @Test("Group drop validation rejects filename collisions across source folders")
    func nativeMultipleNoteDropCollision() throws {
        let vaultID = UUID()
        let notes = ["One/Note.md", "Two/note.md", "Two/Other.md"].map {
            workspaceNote(vaultID: vaultID, stableID: UUID(), path: $0, source: "# Material\n")
        }
        let payloads = try notes.map { SidebarNoteDragItem(try #require(NoteMutationTarget($0))) }
        let inventory = SidebarTreeDropInventory(
            currentVaultID: vaultID, sourceScope: .library, currentVaultRole: .sourceCorpus,
            canMutate: true, notes: notes, folderRelativePaths: ["One", "Two", "Target"],
            pathComparisonPolicy: .init(caseSensitive: false, normalizationSensitive: true),
            pendingNoteMoves: [], pendingFolderMoves: [])
        #expect(sidebarValidatedNotesDropDestinations(items: [payloads[0], payloads[1]], folderRelativePath: "Target", inventory: inventory) == nil)
        #expect(
            sidebarValidatedNotesDropDestinations(items: [payloads[0], payloads[2]], folderRelativePath: "Target", inventory: inventory) == [
                "Target/Note.md", "Target/Other.md",
            ])
        #expect(sidebarValidatedNotesDropDestinations(items: [payloads[0], payloads[0]], folderRelativePath: "Target", inventory: inventory) == nil)
    }

    @Test("Library filter presentation counts only complete property filters")
    func libraryFilterPresentationProjection() {
        var filters = DiscoveryFilterState()
        #expect(sidebarActiveLibraryFilterCount(filters) == 0)

        filters.needsAttention = true
        filters.tag = "Agency"
        filters.propertyKey = "publication_status"
        #expect(sidebarActiveLibraryFilterCount(filters) == 2)

        filters.propertyValue = "forthcoming"
        #expect(sidebarActiveLibraryFilterCount(filters) == 3)

        filters.propertyValue = "  \n"
        #expect(sidebarActiveLibraryFilterCount(filters) == 3)
    }

    @Test("Modified ordering uses file time before the title tie-break")
    @MainActor
    func modifiedOrderingPreservesTitleTieBreak() {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let vaultID = UUID()
        let older = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Zeta.md",
            source: "# Zeta\n",
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        let newer = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Alpha.md",
            source: "# Alpha\n",
            modificationDate: Date(timeIntervalSince1970: 2)
        )

        window.discoveryController.selectSortOrder(.modifiedNewest)
        #expect(window.notesAreOrdered(newer, older))
        #expect(!window.notesAreOrdered(older, newer))

        window.discoveryController.selectSortOrder(.modifiedOldest)
        #expect(window.notesAreOrdered(older, newer))
        #expect(!window.notesAreOrdered(newer, older))

        let alphaTie = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Alpha Tie.md",
            source: "# Alpha\n",
            modificationDate: Date(timeIntervalSince1970: 1)
        )
        window.discoveryController.selectSortOrder(.modifiedNewest)
        #expect(window.notesAreOrdered(alphaTie, older))
    }

    @Test("A created Note reveals only its folder ancestors")
    func createdNoteFolderAncestors() {
        #expect(libraryFolderAncestors(forDocumentPath: "Untitled.md").isEmpty)
        #expect(
            libraryFolderAncestors(
                forDocumentPath: "papers/Arguments/Agency/Untitled.md"
            ) == ["papers", "papers/Arguments", "papers/Arguments/Agency"]
        )
    }

    @Test("Former role names remain ordinary researcher Folder roots")
    func formerRoleNamesRemainOrdinaryFolders() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "papers/Ethics/Agency/Argument.md",
                    rawContent: "# Argument\n"
                ),
                .syntheticPreview(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                ),
                .syntheticPreview(
                    relativePath: "topics/Debate/Position.md",
                    rawContent: "# Position\n"
                ),
                .syntheticPreview(
                    relativePath: "output/Chapter/Draft.md",
                    rawContent: "# Draft\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        #expect(Set(tree.filter(\.isFolder).map(\.id)) == ["papers", "topics", "output"])
        let papers = try #require(tree.first { $0.id == "papers" })
        #expect(papers.folderRelativePath == "papers")
        let ethics = try #require(papers.children.first { $0.id == "papers/Ethics" })
        #expect(ethics.folderRelativePath == "papers/Ethics")
        let agency = try #require(ethics.children.first { $0.id == "papers/Ethics/Agency" })
        #expect(agency.folderRelativePath == "papers/Ethics/Agency")
        #expect(agency.folderIDs == ["papers/Ethics/Agency"])
    }

    @Test("Same-named subfolders under distinct roots retain distinct action paths")
    func sameNamedSubfoldersRemainDistinct() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "papers/Shared/Analysis.md",
                    rawContent: "# Analysis\n"
                ),
                .syntheticPreview(
                    relativePath: "topics/Shared/Topic.md",
                    rawContent: "# Topic\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let papers = try #require(tree.first { $0.id == "papers" })
        let topics = try #require(tree.first { $0.id == "topics" })
        let paperShared = try #require(papers.children.first { $0.id == "papers/Shared" })
        let topicShared = try #require(topics.children.first { $0.id == "topics/Shared" })
        #expect(paperShared.folderRelativePath == "papers/Shared")
        #expect(topicShared.folderRelativePath == "topics/Shared")
    }

    @Test("Empty folders participate in the same hierarchy as folders containing notes")
    func emptyFoldersAreVisible() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "papers/Ethics/Overview.md",
                    rawContent: "# Overview\n"
                )
            ],
            folderRelativePaths: [
                "papers",
                "papers/Ethics",
                "papers/Ethics/Empty Archive",
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let papers = try #require(tree.first { $0.id == "papers" })
        let ethics = try #require(papers.children.first { $0.id == "papers/Ethics" })
        let empty = try #require(
            ethics.children.first {
                $0.id == "papers/Ethics/Empty Archive"
            })
        #expect(empty.isFolder)
        #expect(empty.children.isEmpty)
        #expect(empty.folderRelativePath == "papers/Ethics/Empty Archive")
        let projection = LibraryTreeProjection(
            preorderedNotes: [],
            folderRelativePaths: [
                "papers",
                "papers/Ethics",
                "papers/Ethics/Empty Archive",
            ]
        )
        #expect(projection.expandableFolderIDs == ["papers", "papers/Ethics"])
        #expect(tree.contains { $0.id == "papers" })
    }

    @Test("Native outline visibility stays deterministic")
    func expandedHierarchyUsesNativeOutlineProjection() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                ),
                .syntheticPreview(
                    relativePath: "Arguments/Overview.md",
                    rawContent: "# Overview\n"
                ),
                .syntheticPreview(
                    relativePath: "Loose.md",
                    rawContent: "# Loose\n"
                ),
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let collapsed = sidebarVisibleTreeNodes(from: tree, expandedFolders: [])
        #expect(collapsed.map(\.id) == ["Arguments", "Loose.md"])

        let expanded = sidebarVisibleTreeNodes(
            from: tree,
            expandedFolders: ["Arguments", "Arguments/Agency"]
        )
        #expect(
            expanded.map(\.id) == [
                "Arguments",
                "Arguments/Agency",
                "Arguments/Agency/Reply.md",
                "Arguments/Overview.md",
                "Loose.md",
            ])
        #expect(sidebarControlSize(for: .small) == .small)
        #expect(sidebarControlSize(for: .medium) == .regular)
        #expect(sidebarControlSize(for: .large) == .large)
        #expect(
            SidebarSourceListRowPresentation(
                effectiveRowSizeStyle: .large
            ).textPointSize == NSFont.systemFontSize(for: .large)
        )
    }

    @Test("Native expansion synchronization runs only for changed disclosure or structure")
    func nativeExpansionSynchronizationInvalidation() {
        let disclosure: Set<String> = ["Cluster"]
        #expect(
            sidebarExpansionSynchronizationIsRequired(
                previouslyApplied: nil,
                desired: disclosure,
                structureChanged: false
            ))
        #expect(
            !sidebarExpansionSynchronizationIsRequired(
                previouslyApplied: disclosure,
                desired: disclosure,
                structureChanged: false
            ))
        #expect(
            sidebarExpansionSynchronizationIsRequired(
                previouslyApplied: disclosure,
                desired: ["Other"],
                structureChanged: false
            ))
        #expect(
            sidebarExpansionSynchronizationIsRequired(
                previouslyApplied: disclosure,
                desired: disclosure,
                structureChanged: true
            ))
    }

    @MainActor
    @Test("Triptych workspace navigation delegates selection and traversal to AppKit")
    func nativeTriptychWorkspaceSelection() throws {
        var requestedSlot: WorkspaceVaultSlot?
        let coordinator = ScholiumTriptychWorkspaceNavigator.Coordinator(select: { requestedSlot = $0 })
        let control = WorkspaceSegmentedControl(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        control.segmentCount = 3
        control.segmentDistribution = .fillEqually
        control.titles = ["Analyses", "Topics", "Works"]
        control.setSegmentToolTips(control.titles)
        control.selectedSegment = 0
        control.setEnabled(false, forSegment: 1)
        control.updateLabels()
        #expect(!control.usesSymbols)
        #expect(control.segmentToolTipMessages == ["Analyses", "Topics", "Works"])
        #expect(control.toolTipRegistrations.count == 3)
        #expect(control.label(forSegment: 0) == "Analyses")
        control.selectedSegment = 1
        coordinator.selectWorkspace(control)
        #expect(requestedSlot == nil)
        control.selectedSegment = 2
        coordinator.selectWorkspace(control)
        #expect(requestedSlot == .output)
        requestedSlot = nil
        control.frame.size.width = 140
        control.updateLabels()
        #expect(control.usesSymbols)
        #expect(control.image(forSegment: 0) != nil)
        #expect(control.toolTipRegistrations.map(\.message) == ["Analyses", "Topics", "Works"])
        #expect(
            control.toolTipRegistrations[0].rect.width
                == control.bounds.width / CGFloat(control.segmentCount)
        )
        #expect(control.selectedSegment == 2)
        #expect(requestedSlot == nil)
        control.frame.size.width = 360
        control.updateLabels()
        #expect(!control.usesSymbols)
        #expect(control.label(forSegment: 2) == "Works")
        #expect(control.image(forSegment: 2) == nil)
        #expect(control.selectedSegment == 2)
    }

    @Test("An empty root Folder remains visible when disclosure state contains it")
    func emptyRootRemainsVisible() throws {
        let tree = buildTree(
            from: [],
            folderRelativePaths: ["Empty Archive"],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )

        let projected = sidebarVisibleTreeNodes(
            from: tree,
            expandedFolders: ["Empty Archive"]
        )
        let empty = try #require(projected.first)
        #expect(projected.map(\.id) == ["Empty Archive"])
        #expect(empty.isFolder)
        #expect(empty.children.isEmpty)
    }

    @Test("Only visibly expanded Folders request the Collapse All presentation")
    func visibleExpandedFolderState() throws {
        let tree = buildTree(
            from: [
                .syntheticPreview(
                    relativePath: "Arguments/Agency/Reply.md",
                    rawContent: "# Reply\n"
                )
            ],
            notesAreOrdered: { $0.relativePath < $1.relativePath }
        )
        let arguments = try #require(tree.first { $0.id == "Arguments" })

        #expect(
            arguments.visibleExpandedFolderIDs(in: ["Arguments/Agency"])
                .isEmpty
        )
        #expect(
            arguments.visibleExpandedFolderIDs(
                in: ["Arguments", "Arguments/Agency"]
            ) == ["Arguments", "Arguments/Agency"]
        )
    }

    @Test("A dropped Note keeps its file name and changes only its containing folder")
    func droppedNoteDestination() {
        #expect(
            sidebarNoteDropDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                folderRelativePath: "papers/Cluster-10"
            ) == "papers/Cluster-10/Argument.md"
        )
        #expect(
            sidebarNoteDropDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                folderRelativePath: nil
            ) == "Argument.md"
        )
    }

    @Test("A dropped Folder can move into another Folder or back to the vault root")
    func droppedFolderDestination() {
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "papers/Cluster-01/Arguments",
                folderRelativePath: "papers/Cluster-10"
            ) == "papers/Cluster-10/Arguments"
        )
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "papers/Cluster-01/Arguments",
                folderRelativePath: nil
            ) == "Arguments"
        )
    }

    @Test("A Folder drop rejects no-op, self, and descendant destinations")
    func droppedFolderRejectsInvalidDestinations() {
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "Cluster-01/Arguments",
                folderRelativePath: "Cluster-01"
            ) == nil)
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "Cluster-01/Arguments",
                folderRelativePath: "Cluster-01/Arguments"
            ) == nil)
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "Cluster-01/Arguments",
                folderRelativePath: "Cluster-01/Arguments/Replies"
            ) == nil)
        #expect(
            sidebarFolderDropDestination(
                sourceRelativePath: "Arguments",
                folderRelativePath: nil
            ) == nil)
    }

    @Test("Native Note drop validation rejects stale, pending, and occupied moves")
    func nativeNoteDropValidation() throws {
        let vaultID = UUID()
        let stableID = UUID()
        let pathComparisonPolicy = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )
        let source = workspaceNote(
            vaultID: vaultID,
            stableID: stableID,
            path: "papers/Cluster-01/Argument.md",
            source: "# Argument\n"
        )
        let target = try #require(NoteMutationTarget(source))
        let item = SidebarNoteDragItem(target)
        let base = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: [
                "papers/Cluster-01",
                "papers/Cluster-10",
            ],
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )

        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: base
            ) == "papers/Cluster-10/Argument.md")
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: nil,
                inventory: base
            ) == "Argument.md")

        let unavailablePolicy = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: nil,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: unavailablePolicy
            ) == nil)

        let stale = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [
                workspaceNote(
                    vaultID: vaultID,
                    stableID: stableID,
                    path: target.relativePath,
                    source: "# Changed while dragging\n"
                )
            ],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: stale
            ) == nil)

        let pending = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [item.id],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: pending
            ) == nil)

        let collision = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [
                source,
                workspaceNote(
                    vaultID: vaultID,
                    stableID: UUID(),
                    path: "papers/Cluster-10/Argument.md",
                    source: "# Existing\n"
                ),
            ],
            folderRelativePaths: base.folderRelativePaths,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: collision
            ) == nil)
    }

    @Test("Native Folder drop validation rejects pending and occupied moves")
    func nativeFolderDropValidation() {
        let vaultID = UUID()
        let pathComparisonPolicy = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )
        let item = SidebarFolderDragItem(
            FolderMutationTarget(
                vaultID: vaultID,
                relativePath: "papers/Cluster-01/Arguments"
            ))
        let folders: Set<String> = [
            "papers/Cluster-01",
            "papers/Cluster-01/Arguments",
            "papers/Cluster-10",
        ]
        let base = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: base
            ) == "papers/Cluster-10/Arguments")
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: nil,
                inventory: base
            ) == "Arguments")

        let unavailablePolicy = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: nil,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: unavailablePolicy
            ) == nil)

        let pending = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: [item.id]
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: pending
            ) == nil)

        let occupied = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders.union(["papers/Cluster-10/Arguments"]),
            pathComparisonPolicy: pathComparisonPolicy,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "papers/Cluster-10",
                inventory: occupied
            ) == nil)
    }

    @Test("Native Note drop validation uses the mounted volume comparison policy")
    func nativeNoteDropUsesVolumeComparisonPolicy() throws {
        let vaultID = UUID()
        let source = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Source/Draft.md",
            source: "# Draft\n"
        )
        let caseVariant = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Target/draft.md",
            source: "# Existing\n"
        )
        let item = SidebarNoteDragItem(try #require(NoteMutationTarget(source)))
        let folders: Set<String> = ["Source", "Target"]

        let caseInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source, caseVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "Target",
                inventory: caseInsensitive
            ) == nil)

        let caseSensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [source, caseVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: item,
                folderRelativePath: "Target",
                inventory: caseSensitive
            ) == "Target/Draft.md")

        let unicodeSource = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Source/Café.md",
            source: "# Café\n"
        )
        let unicodeVariant = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Target/Cafe\u{301}.md",
            source: "# Existing\n"
        )
        let unicodeItem = SidebarNoteDragItem(
            try #require(NoteMutationTarget(unicodeSource))
        )
        let normalizationInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [unicodeSource, unicodeVariant],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: false
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedNoteDropDestination(
                item: unicodeItem,
                folderRelativePath: "Target",
                inventory: normalizationInsensitive
            ) == nil)
    }

    @Test("Native Folder drop validation uses the mounted volume comparison policy")
    func nativeFolderDropUsesVolumeComparisonPolicy() {
        let vaultID = UUID()
        let item = SidebarFolderDragItem(
            FolderMutationTarget(
                vaultID: vaultID,
                relativePath: "Source/Arguments"
            ))
        let folders: Set<String> = [
            "Source",
            "Source/Arguments",
            "Target",
            "Target/arguments",
        ]
        let caseInsensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "Target",
                inventory: caseInsensitive
            ) == nil)

        let caseSensitive = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: folders,
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: true,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "Target",
                inventory: caseSensitive
            ) == "Target/Arguments")

        let currentParentWithDifferentCase = SidebarTreeDropInventory(
            currentVaultID: vaultID,
            sourceScope: .library,
            currentVaultRole: .sourceCorpus,
            canMutate: true,
            notes: [],
            folderRelativePaths: ["Source/Arguments", "source"],
            pathComparisonPolicy: VaultPathComparisonPolicy(
                caseSensitive: false,
                normalizationSensitive: true
            ),
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
        #expect(
            sidebarValidatedFolderDropDestination(
                item: item,
                folderRelativePath: "source",
                inventory: currentParentWithDifferentCase
            ) == nil)
    }

    @Test("Inline title changes only the file name inside the current folder")
    func renamedNoteDestination() {
        #expect(
            noteRenameDestination(
                sourceRelativePath: "papers/Cluster-01/Argument.md",
                requestedName: "Revised Argument"
            ) == "papers/Cluster-01/Revised Argument.md"
        )
        #expect(
            noteRenameDestination(
                sourceRelativePath: "Argument.md",
                requestedName: "Revised.md"
            ) == "Revised.md"
        )
        #expect(
            noteRenameDestination(
                sourceRelativePath: "Argument.md",
                requestedName: "Another/Folder"
            ) == nil)
    }

    @MainActor
    @Test("A retained-document reveal restores selection after navigation fails")
    func retainedDocumentRevealRestoresSelection() async throws {
        _ = NSApplication.shared
        let vaultID = UUID()
        let first = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "First.md", source: "# First\n")
        let second = workspaceNote(vaultID: vaultID, stableID: UUID(), path: "Second.md", source: "# Second\n")
        let projection = LibraryTreeProjection(preorderedNotes: [first, second])
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        func configuration(reveal: DiscoveryLibraryRevealRequest?) -> SidebarOutlineSourceList {
            makeSidebarCoordinatorConfiguration(
                roots: projection.roots, notes: [first, second], scope: scope,
                expandedFolderIDs: [], selectedDocumentPath: first.relativePath,
                revealRequest: reveal, requestedFocusPath: nil,
                onConsumeRevealRequest: { _ in }, onFocusRequestHandled: {}
            )
        }
        let coordinator = SidebarOutlineSourceList.Coordinator(configuration: configuration(reveal: nil))
        let fixture = makeSidebarCoordinatorOutline(coordinator)
        coordinator.apply(configuration: configuration(reveal: nil))
        let retainedRow = fixture.outlineView.selectedRow
        #expect(retainedRow >= 0)
        fixture.outlineView.selectRowIndexes(IndexSet(integer: retainedRow == 0 ? 1 : 0), byExtendingSelection: false)
        coordinator.apply(
            configuration: configuration(
                reveal: DiscoveryLibraryRevealRequest(
                    generation: 1, scope: scope, relativePath: first.relativePath, alignment: .nearest
                )))
        try await Task.sleep(for: .milliseconds(25))
        #expect(fixture.outlineView.selectedRow == retainedRow)
        coordinator.detach(from: fixture.scrollView)
        fixture.window.close()
    }

    @MainActor
    @Test("Sidebar drops queued reveal and focus callbacks across detach and reattach")
    func coordinatorDropsStaleTeardownCallbacks() async throws {
        _ = NSApplication.shared
        let vaultID = UUID()
        let firstNote = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Folder/First.md",
            source: "# First\n"
        )
        let secondNote = workspaceNote(
            vaultID: vaultID,
            stableID: UUID(),
            path: "Folder/Second.md",
            source: "# Second\n"
        )
        let projection = LibraryTreeProjection(
            preorderedNotes: [firstNote, secondNote]
        )
        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            sourceScope: .library
        )
        let expandedFolderIDs: Set<String> = ["Folder"]
        var revealCount = 0
        var focusCount = 0

        let initialConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 1,
                scope: scope,
                relativePath: firstNote.relativePath,
                alignment: .nearest
            ),
            requestedFocusPath: firstNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        let coordinator = SidebarOutlineSourceList.Coordinator(
            configuration: initialConfiguration
        )
        let firstFixture = makeSidebarCoordinatorOutline(coordinator)
        defer { firstFixture.window.close() }
        coordinator.apply(configuration: initialConfiguration)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 1)
        #expect(focusCount == 1)

        let staleConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 2,
                scope: scope,
                relativePath: secondNote.relativePath,
                alignment: .center
            ),
            requestedFocusPath: secondNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        coordinator.apply(configuration: staleConfiguration)
        coordinator.detach(from: firstFixture.scrollView)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 1)
        #expect(focusCount == 1)

        let replacementConfiguration = makeSidebarCoordinatorConfiguration(
            roots: projection.roots,
            notes: [firstNote, secondNote],
            scope: scope,
            expandedFolderIDs: expandedFolderIDs,
            revealRequest: DiscoveryLibraryRevealRequest(
                generation: 3,
                scope: scope,
                relativePath: firstNote.relativePath,
                alignment: .nearest
            ),
            requestedFocusPath: firstNote.relativePath,
            onConsumeRevealRequest: { _ in revealCount += 1 },
            onFocusRequestHandled: { focusCount += 1 }
        )
        let replacementFixture = makeSidebarCoordinatorOutline(coordinator)
        defer { replacementFixture.window.close() }
        coordinator.apply(configuration: replacementConfiguration)
        try await Task.sleep(for: .milliseconds(25))

        #expect(revealCount == 2)
        #expect(focusCount == 2)
        coordinator.detach(from: replacementFixture.scrollView)
    }

    private func workspaceNote(
        vaultID: UUID,
        stableID: UUID,
        path: String,
        source: String,
        modificationDate: Date? = nil
    ) -> WindowDocumentLocation {
        let document = NoteDocument(relativePath: path, rawContent: source)
        return .workspace(
            WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                vaultRole: .sourceCorpus,
                stableIdentity: .resolved(stableID),
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: modificationDate
                ),
                graphCounts: WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                )
            ).summary)
    }
}

@MainActor
private func makeSidebarCoordinatorConfiguration(
    roots: [TreeNode],
    notes: [WindowDocumentLocation],
    scope: LibraryDisclosureScope,
    expandedFolderIDs: Set<String>,
    selectedDocumentPath: String? = nil,
    revealRequest: DiscoveryLibraryRevealRequest?,
    requestedFocusPath: String?,
    onConsumeRevealRequest: @escaping (DiscoveryLibraryRevealRequest) -> Void,
    onFocusRequestHandled: @escaping () -> Void,
    canAddNoteToChat: @escaping (WindowDocumentLocation) -> Bool = { _ in false },
    addNoteToChat: @escaping (WindowDocumentLocation) -> Void = { _ in },
    selectedRowIDs: Set<String>? = nil,
    canMutate: Bool = false,
    onSelectionChange: @escaping (Set<String>) -> Void = { _ in },
    onSelect: @escaping (WindowDocumentLocation) -> Void = { _ in },
    onBatchMove: @escaping ([NoteMutationTarget]) -> Void = { _ in },
    onBatchTrash: @escaping ([NoteMutationTarget]) -> Void = { _ in },
    copyRelativePath: @escaping (String) -> Void = { _ in },
    projectionRevision: UInt64 = 1,
    focusRequestGeneration: UInt64 = 0,
    dropInventory suppliedDropInventory: SidebarTreeDropInventory? = nil,
    onMoveNoteDrop: @escaping (SidebarNoteDragItem, String?) -> Void = { _, _ in },
    onMoveFolderDrop: @escaping (SidebarFolderDragItem, String?) -> Void = { _, _ in },
    onMoveNotesDrop: @escaping ([SidebarNoteDragItem], String?) -> Void = { _, _ in }
) -> SidebarOutlineSourceList {
    let context = SidebarTreeContext(
        currentVaultID: scope.vaultID,
        currentVaultRole: .other,
        openNote: { _, _ in },
        canAddNoteToChat: canAddNoteToChat,
        addNoteToChat: addNoteToChat,
        requestFileOperation: { _ in },
        canMutateLibrary: canMutate,
        createUntitledNote: { _ in },
        createUntitledFolder: { _ in },
        requestFolderFileOperation: { _ in },
        requestFolderSystemTrash: { _ in },
        copyRelativePath: copyRelativePath,
        revealNote: { _ in },
        requestSystemTrash: { _ in },
        showError: { _ in }
    )
    let dropInventory =
        suppliedDropInventory
        ?? SidebarTreeDropInventory(
            currentVaultID: scope.vaultID,
            sourceScope: .library,
            currentVaultRole: .other,
            canMutate: canMutate,
            notes: notes,
            folderRelativePaths: [],
            pathComparisonPolicy: nil,
            pendingNoteMoves: [],
            pendingFolderMoves: []
        )
    return SidebarOutlineSourceList(
        roots: roots,
        projectionRevision: projectionRevision,
        locale: Locale(identifier: "en_US"),
        expandedFolders: .constant(expandedFolderIDs),
        expandedFolderIDs: expandedFolderIDs,
        usesAccessibilitySize: false,
        selectedDocumentPath: selectedDocumentPath,
        context: context,
        dropInventory: dropInventory,
        revealRequest: revealRequest,
        disclosureScope: scope,
        focusRequestGeneration: focusRequestGeneration,
        requestedFocusPath: requestedFocusPath,
        onConsumeRevealRequest: onConsumeRevealRequest,
        onFocusRequestHandled: onFocusRequestHandled,
        onSelect: onSelect,
        onMoveNoteDrop: onMoveNoteDrop,
        onMoveFolderDrop: onMoveFolderDrop,
        selectedRowIDs: selectedRowIDs ?? Set(selectedDocumentPath.map { [$0] } ?? []),
        onSelectionChange: onSelectionChange,
        onBatchMove: onBatchMove,
        onBatchTrash: onBatchTrash,
        onMoveNotesDrop: onMoveNotesDrop
    )
}

@MainActor
private final class SidebarTreeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingDestinationWindow: NSWindow?
    var draggingLocation: NSPoint { .zero }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(source: NSView, window: NSWindow) {
        draggingSource = source
        draggingDestinationWindow = window
    }

    func setPayload(_ payload: some Encodable, type: NSPasteboard.PasteboardType) throws {
        draggingPasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(try JSONEncoder().encode(payload), forType: type)
        draggingPasteboard.writeObjects([item])
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}

@MainActor
private func makeSidebarCoordinatorOutline(
    _ coordinator: SidebarOutlineSourceList.Coordinator
) -> (window: NSWindow, scrollView: NSScrollView, outlineView: SidebarOutlineView) {
    _ = NSApplication.shared
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    let scrollView = NSScrollView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 320)
    )
    let outlineView = SidebarOutlineView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 320)
    )
    outlineView.dataSource = coordinator
    outlineView.delegate = coordinator
    outlineView.style = .sourceList
    outlineView.floatsGroupRows = false
    outlineView.allowsMultipleSelection = true
    outlineView.usesAutomaticRowHeights = false
    outlineView.rowSizeStyle = .default
    outlineView.intercellSpacing = .zero
    let column = NSTableColumn(
        identifier: SidebarOutlineSourceList.Coordinator.columnIdentifier
    )
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    scrollView.documentView = outlineView
    window.contentView = scrollView
    coordinator.attach(outlineView: outlineView, scrollView: scrollView)
    return (window, scrollView, outlineView)
}
