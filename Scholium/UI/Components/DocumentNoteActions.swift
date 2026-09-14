import AppKit
import ScholiumContracts

enum DocumentNoteAction: String, CaseIterable {
    case copyLink, addToChat, rename, move, duplicate, merge, find, agentChanges
    case revealInFinder, moveWindow, close, trash

    static let groups: [[Self]] = [
        [.copyLink, .addToChat], [.rename, .move, .duplicate, .merge],
        [.find, .agentChanges], [.revealInFinder, .moveWindow, .close], [.trash],
    ]

    func title(detached: Bool) -> String {
        switch self {
        case .copyLink: "Copy Note Link"
        case .addToChat: "Add to Chat"
        case .rename: "Rename Note…"
        case .move: "Move Note…"
        case .duplicate: "Duplicate Note…"
        case .merge: "Merge into Another Note…"
        case .find: "Find…"
        case .agentChanges: "Agent Changes…"
        case .revealInFinder: "Reveal in Finder"
        case .moveWindow: detached ? "Move to Main Window" : "Move to Separate Window"
        case .close: detached ? "Close Window" : "Close Tab"
        case .trash: "Move to Trash…"
        }
    }
}

/// Both window types use the same current-document menu. Native AppKit owns
/// presentation; the window model owns capabilities and action execution.
@MainActor
final class DocumentNoteActionsToolbarItem: NSMenuToolbarItem, NSMenuDelegate {
    private weak var model: WindowModel?
    private var menuDocument: WindowSelectedDocument?

    init(identifier: NSToolbarItem.Identifier, model: WindowModel) {
        self.model = model
        super.init(itemIdentifier: identifier)
        label = ScholiumL10n.string("More")
        paletteLabel = label
        toolTip = ScholiumL10n.string("Note Actions")
        image = ScholiumNativeToolbarPresentation.symbol(named: "ellipsis", accessibilityDescription: toolTip)
        showsIndicator = false
        isBordered = true
        style = .plain
        visibilityPriority = .high
        let actions = NSMenu(title: ScholiumL10n.string("Note Actions"))
        actions.delegate = self
        populate(actions)
        menu = actions
        refreshPresentation()
    }

    override func validate() { refreshPresentation() }

    func invalidate() {
        model = nil
        menuDocument = nil
        menu.cancelTracking()
        menu.removeAllItems()
        menu.delegate = nil
        menu.autoenablesItems = false
        target = nil
        action = nil
        isEnabled = false
        isHidden = true
        // AppKit synthesizes an enabled submenu-opening overflow item on each
        // read. Its submenu is this emptied menu; it has no Note action to run.
    }

    func refreshPresentation() {
        isEnabled = model.map { $0.currentNote != nil && !$0.transferInProgress } ?? false
        isHidden = model?.currentNote == nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let model else { return }
        menuDocument = model.documentController.selectedDocument
        // AppKit has already prepared its pull-down title item here. Replacing
        // the contents makes it hide our first command as that title item.
        for item in menu.items {
            guard let raw = item.representedObject as? String,
                let command = DocumentNoteAction(rawValue: raw)
            else { continue }
            item.title = ScholiumL10n.dynamicString(command.title(detached: model.isDetachedDocumentWindow))
        }
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }
        menuDocument = model.documentController.selectedDocument
        for (index, group) in DocumentNoteAction.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in group {
                let item = NSMenuItem(
                    title: ScholiumL10n.dynamicString(command.title(detached: model.isDetachedDocumentWindow)),
                    action: #selector(performNoteCommand(_:)), keyEquivalent: ""
                )
                item.identifier = NSUserInterfaceItemIdentifier("scholium.noteActions.\(command.rawValue)")
                item.representedObject = command.rawValue
                item.target = self
                menu.addItem(item)
            }
        }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let model, let menuDocument,
            menuDocument == model.documentController.selectedDocument,
            let raw = item.representedObject as? String,
            let command = DocumentNoteAction(rawValue: raw)
        else { return false }
        return model.canPerformNoteAction(command)
    }

    @objc private func performNoteCommand(_ item: NSMenuItem) {
        guard validateMenuItem(item), let raw = item.representedObject as? String,
            let command = DocumentNoteAction(rawValue: raw)
        else { return }
        model?.performNoteAction(command)
    }
}

/// A copied link has no destination-document context. Verify the complete path
/// from every current catalog origin so same-name notes cannot silently capture it.
enum DocumentNoteLink {
    static func target(for note: VaultQualifiedNoteID, catalog: [LinkCatalogNote]) -> String? {
        let target = (note.relativePath as NSString).deletingPathExtension
        guard !target.isEmpty, !target.contains(where: { "\\#|[]\r\n".contains($0) }),
            catalog.contains(where: { $0.id == note })
        else { return nil }
        let resolver = LinkResolutionCatalog(catalog: catalog)
        for origin in catalog {
            guard
                case .resolved(let destination) = resolver.resolveNavigation(
                    target: target, fragment: nil, from: origin.id, scope: .workspace
                ), destination.note == note
            else { return nil }
        }
        return target
    }
}

extension WindowModel {
    func currentNoteLinkTarget() async -> String? {
        guard let reference = currentDocumentDescriptor?.reference, let catalog = workspaceCatalog else { return nil }
        return DocumentNoteLink.target(
            for: .init(vaultID: reference.vaultID, relativePath: reference.relativePath),
            catalog: catalog.notes.map {
                LinkCatalogNote(
                    id: .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath),
                    title: $0.title, aliases: $0.aliases)
            }
        )
    }

    func canPerformNoteAction(_ action: DocumentNoteAction) -> Bool {
        guard currentNote != nil, !transferInProgress else { return false }
        switch action {
        case .copyLink: return currentDocumentDescriptor != nil && workspaceCatalog != nil
        case .addToChat: return currentDocumentDescriptor != nil && windowWorkspaceController.activeCapabilities != nil
        case .rename, .move: return currentDocumentCapabilities.allows(.move)
        case .duplicate: return currentDocumentCapabilities.allows(.duplicate)
        case .merge: return canMergeCurrentNote
        case .trash: return currentDocumentCapabilities.allows(.moveToSystemTrash)
        case .agentChanges: return currentDocumentDescriptor != nil && windowWorkspaceController.activeCapabilities != nil
        case .find: return documentController.selectedDocument != nil
        case .revealInFinder: return currentNoteFileURL != nil
        case .moveWindow, .close: return documentTabController.selectedTabID != nil
        }
    }

    private var currentNoteFileURL: URL? {
        guard let reference = currentDocumentDescriptor?.reference,
            let vault = registeredVaults.first(where: { $0.id == reference.vaultID })
        else { return nil }
        return URL(fileURLWithPath: vault.canonicalPath, isDirectory: true)
            .appendingPathComponent(reference.relativePath)
    }

    func performNoteAction(_ action: DocumentNoteAction) {
        guard canPerformNoteAction(action) else { return }
        switch action {
        case .copyLink:
            let document = documentController.selectedDocument
            Task { @MainActor [weak self] in
                guard let self, document == self.documentController.selectedDocument else { return }
                let target = await self.currentNoteLinkTarget()
                guard document == self.documentController.selectedDocument else { return }
                guard let target else {
                    self.reportOperationIssue(ScholiumL10n.string("This note has no unambiguous link across the Triptych."), kind: .information)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(target)]]", forType: .string)
            }
        case .addToChat:
            let document = documentController.selectedDocument
            Task { @MainActor [weak self] in
                guard let self, document == self.documentController.selectedDocument else { return }
                await self.addCurrentNoteToVisibleChat()
            }
        case .rename, .move, .duplicate:
            guard let note = currentNote, let target = NoteMutationTarget(note) else { return }
            switch action {
            case .rename: noteFileRequest = .rename(target)
            case .move: noteFileRequest = .move(target)
            case .duplicate: noteFileRequest = .duplicate(target)
            default: break
            }
        case .merge: requestMergeCurrentNote()
        case .find: presentCurrentDocumentFind()
        case .agentChanges: presentationRouter.present(.agentChanges(scope: .current))
        case .revealInFinder:
            if let url = currentNoteFileURL { workspaceStore.revealInFinder(url) }
        case .moveWindow:
            if isDetachedDocumentWindow { requestMoveDocumentBack() } else { requestMoveDocumentToWindow() }
        case .close:
            if isDetachedDocumentWindow {
                nativeWindowCoordinator?.requestNativeClose()
            } else if let id = documentTabController.selectedTabID {
                closeDocumentTab(withID: id)
            }
        case .trash: requestCurrentNoteSystemTrash()
        }
    }
}
