import AppKit
import Combine
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Notifications native presentation", .serialized)
@MainActor
struct AttentionQueuePresentationTests {
    @Test("Native Notifications gives the list first responder and keeps the search field native")
    func nativeFocus() async throws {
        _ = NSApplication.shared
        let store = makeTestWorkspaceStore()
        let workspaceController = WindowWorkspaceController(
            workspaceStore: store,
            requestedTriptychID: nil
        )
        let discoveryController = DiscoveryController()
        let projectionController = WindowWorkspaceProjectionController {
            throw DiscoverySearchExecutionError.workspaceUnavailable
        }
        let documentChanges = PassthroughSubject<[DocumentChangeSummary]?, Never>()
        let documentChangeErrors = PassthroughSubject<String?, Never>()
        let vault = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixtures/Topics"
        )
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: "Reasons.md"
        )
        let issue = AttentionQueueItem(
            kind: .possibleOrphan,
            severity: .information,
            note: reference,
            message: "No incoming or outgoing links"
        )
        projectionController.replaceCatalog(
            WorkspaceCatalogBuilder.build(
                vaults: [vault],
                documents: [vault.id: [NoteDocument(relativePath: "Reasons.md", rawContent: "# Reasons\n")]],
                additionalAttention: [issue]
            )
        )
        let session = AttentionPopoverSession(
            presentation: AttentionPresentationState(),
            discoveryController: discoveryController,
            workspaceController: workspaceController,
            projectionController: projectionController,
            dependencies: .init(
                settlementRequirementChanges: Just([]).eraseToAnyPublisher(),
                documentChangeChanges: documentChanges.eraseToAnyPublisher(),
                documentChangeErrorChanges: documentChangeErrors.eraseToAnyPublisher(),
                refresh: {},
                showDocumentChange: { _ in }
            )
        )
        documentChanges.send([])
        documentChangeErrors.send(nil)
        session.presentQueue(anchor: .toolbar, workspaceSlot: nil, noteScope: nil)

        let controller = AttentionQueueViewController(
            presentation: session.presentation,
            session: session
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            window.contentView = nil
            window.close()
        }

        window.makeKeyAndOrderFront(nil)
        controller.focusInitialContentIfNeeded()

        try await wait {
            find(NSTableView.self, in: controller.view)?.numberOfRows == 0
                && window.firstResponder === find(NSTableView.self, in: controller.view)
        }
        let table = try #require(find(NSTableView.self, in: controller.view))
        let search = try #require(find(NSSearchField.self, in: controller.view))
        #expect(table.accessibilityIdentifier() == "scholium.attentionList")
        #expect(table.allowsMultipleSelection == false)
        #expect(search.accessibilityIdentifier() == "scholium.attentionSearch")
        #expect(search.searchMenuTemplate?.items.count == 3)
    }

    @Test("Long notification identity and errors fit the native popover")
    func longContentLayout() async throws {
        _ = NSApplication.shared
        let presentation = AttentionPresentationState()
        let workspaceController = WindowWorkspaceController(
            workspaceStore: makeTestWorkspaceStore(), requestedTriptychID: nil
        )
        let projectionController = WindowWorkspaceProjectionController {
            throw DiscoverySearchExecutionError.workspaceUnavailable
        }
        let vault = RegisteredVault(
            name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/Topics"
        )
        projectionController.replaceCatalog(
            WorkspaceCatalogBuilder.build(vaults: [vault], documents: [vault.id: []])
        )
        let changes = PassthroughSubject<[DocumentChangeSummary]?, Never>()
        let errors = PassthroughSubject<String?, Never>()
        let session = AttentionPopoverSession(
            presentation: presentation,
            discoveryController: DiscoveryController(),
            workspaceController: workspaceController,
            projectionController: projectionController,
            dependencies: .init(
                settlementRequirementChanges: Just([]).eraseToAnyPublisher(),
                documentChangeChanges: changes.eraseToAnyPublisher(),
                documentChangeErrorChanges: errors.eraseToAnyPublisher(),
                refresh: {}, showDocumentChange: { _ in }
            )
        )
        let controller = AttentionQueueViewController(presentation: presentation, session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        controller.preferredContentSize = NSSize(width: 420, height: 360)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 420, height: 360))
        defer {
            window.contentView = nil
            window.close()
        }

        let title = "情绪评价的规范性条件以及长期研究中的未解决问题的比较与批评 Some Long English Words in a Research Note.md"
        let shortTitle = "Short English Note.md"
        changes.send([
            DocumentChangeSummary(
                noteID: UUID(), vaultID: vault.id, role: .topicKnowledge,
                relativePath: title,
                startingRevision: DocumentFingerprint(content: "before"),
                endingRevision: DocumentFingerprint(content: "after"),
                savedAt: Date(), baselineState: .known
            ),
            DocumentChangeSummary(
                noteID: UUID(), vaultID: vault.id, role: .topicKnowledge,
                relativePath: shortTitle,
                startingRevision: DocumentFingerprint(content: "before short"),
                endingRevision: DocumentFingerprint(content: "after short"),
                savedAt: Date().addingTimeInterval(-60), baselineState: .known
            ),
        ])
        errors.send(nil)
        window.makeKeyAndOrderFront(nil)
        let table = try #require(find(NSTableView.self, in: controller.view))
        try await wait { table.numberOfRows == 3 }
        controller.view.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
        let category = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let item = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: true))
        let shortItem = try #require(table.view(atColumn: 0, row: 2, makeIfNecessary: true))
        item.layoutSubtreeIfNeeded()
        shortItem.layoutSubtreeIfNeeded()
        let itemTitle = try #require(findAll(NSTextField.self, in: item).first { $0.stringValue == title })
        let shortItemTitle = try #require(findAll(NSTextField.self, in: shortItem).first { $0.stringValue == shortTitle })
        let itemDetail = try #require(findAll(NSTextField.self, in: item).first {
            $0.stringValue.contains("Pending Changes")
        })
        let categoryLabel = try #require(find(NSTextField.self, in: category))
        let icon = try #require(find(NSImageView.self, in: item))
        let search = try #require(find(NSSearchField.self, in: controller.view))
        window.displayIfNeeded()
        let titleRect = itemTitle.convert(itemTitle.bounds, to: controller.view)
        let shortTitleRect = shortItemTitle.convert(shortItemTitle.bounds, to: controller.view)
        let itemDetailRect = itemDetail.convert(itemDetail.bounds, to: controller.view)
        let rowRect = table.convert(table.rect(ofRow: 1), to: controller.view)
        let categoryRect = categoryLabel.convert(categoryLabel.bounds, to: controller.view)
        let iconRect = icon.convert(icon.bounds, to: controller.view)
        let searchRect = search.convert(search.bounds, to: controller.view)
        #expect(controller.view.bounds.width >= 400)
        #expect(abs(iconRect.minX - searchRect.minX) < ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(abs(titleRect.minX - categoryRect.minX) < ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(abs(shortTitleRect.minX - categoryRect.minX) < ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(titleRect.width > 300)
        let singleLineHeight = ceil(itemTitle.font?.boundingRectForFont.height ?? 0)
        #expect(titleRect.height > singleLineHeight + ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        #expect(!titleRect.intersects(itemDetailRect))
        #expect(titleRect.minY >= rowRect.minY - 2)
        #expect(itemDetailRect.maxY <= rowRect.maxY + 2)
        #expect(!shortTitleRect.intersects(rowRect))
        #expect(titleRect.maxX <= controller.view.bounds.maxX)
        try renderIfRequested(controller.view, name: "populated-dark")
        if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_NOTIFICATIONS"] == "1" {
            window.appearance = NSAppearance(named: .aqua)
            window.displayIfNeeded()
            try renderIfRequested(controller.view, name: "populated-light")
        }

        changes.send([])
        errors.send(nil)
        try await wait { table.numberOfRows == 0 }
        controller.view.layoutSubtreeIfNeeded()
        try renderIfRequested(controller.view, name: "empty")

        let error = "The source could not be read. " + String(repeating: "Please verify this folder and try again. ", count: 4)
        errors.send(error)
        try await wait {
            findAll(NSTextField.self, in: controller.view).contains { $0.stringValue == error }
        }
        controller.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let detail = try #require(findAll(NSTextField.self, in: controller.view).first { $0.stringValue == error })
        let action = try #require(findAll(NSButton.self, in: controller.view).first {
            $0.accessibilityIdentifier() == "scholium.attentionStateAction"
        })
        let detailRect = detail.convert(detail.bounds, to: controller.view)
        let actionRect = action.convert(action.bounds, to: controller.view)
        #expect(detailRect.width <= ScholiumGrid.ContentState.readableWidth + ScholiumGrid.Spacing.labelAccessoryGap)
        #expect(detailRect.height > 2 * NSFont.smallSystemFontSize)
        #expect(detailRect.minY >= controller.view.bounds.minY)
        #expect(actionRect.minY >= controller.view.bounds.minY)
        #expect(actionRect.maxY <= controller.view.bounds.maxY)
        #expect(!action.isHidden && action.isEnabled)
        try renderIfRequested(controller.view, name: "error")
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private func findAll<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { findAll(type, in: $0) }
    }

    private func renderIfRequested(_ view: NSView, name: String) throws {
        guard ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_NOTIFICATIONS"] == "1" else { return }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent(".build/notification-layout-evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        view.wantsLayer = true
        var backgroundColor: CGColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        view.layer?.backgroundColor = backgroundColor
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(name).png"))
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(predicate())
    }
}
