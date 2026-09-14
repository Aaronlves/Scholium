import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document note actions")
@MainActor
struct DocumentNoteActionsTests {
    @Test("A copied link uses its full path when another folder has the same filename")
    func duplicateBasenamesKeepExactDestination() {
        let vault = UUID()
        let target = VaultQualifiedNoteID(vaultID: vault, relativePath: "Arguments/Reasons.md")
        let other = VaultQualifiedNoteID(vaultID: vault, relativePath: "Objections/Reasons.md")
        #expect(
            DocumentNoteLink.target(
                for: target,
                catalog: [
                    LinkCatalogNote(id: target), LinkCatalogNote(id: other),
                ]) == "Arguments/Reasons")
    }

    @Test("A copied link cannot be captured by a different note in another vault")
    func crossVaultShadowingIsUnavailable() {
        let target = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Arguments/Reasons.md")
        let other = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Objections/Reasons.md")
        #expect(
            DocumentNoteLink.target(
                for: target,
                catalog: [
                    LinkCatalogNote(id: target), LinkCatalogNote(id: other),
                ]) == nil)
    }

    @Test("A unique full path resolves across the Triptych without a fabricated vault prefix")
    func crossVaultUniqueTarget() {
        let target = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Arguments/Reasons.md")
        let other = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Draft.md")
        #expect(
            DocumentNoteLink.target(
                for: target,
                catalog: [
                    LinkCatalogNote(id: target), LinkCatalogNote(id: other),
                ]) == "Arguments/Reasons")
    }

    @Test("Link delimiters in filenames cannot change the copied link meaning")
    func unsafeFilenameIsUnavailable() {
        let target = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Reasons#other.md")
        #expect(DocumentNoteLink.target(for: target, catalog: [LinkCatalogNote(id: target)]) == nil)
    }

    @Test("No-document and transferring windows cannot execute note actions")
    func unavailableDocumentMenu() throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let item = DocumentNoteActionsToolbarItem(identifier: .init("test.noteActions"), model: model)
        #expect(!item.isEnabled)
        #expect(item.isHidden)
        let menu = item.menu
        let originalCommands = menu.items
        item.menuNeedsUpdate(menu)
        #expect(zip(originalCommands, menu.items).allSatisfy { $0 === $1 })
        #expect(menu.items.first?.identifier?.rawValue == "scholium.noteActions.copyLink")
        #expect(menu.items.first?.isHidden == false)
        for command in menu.items where !command.isSeparatorItem {
            #expect(!item.validateMenuItem(command))
        }
        model.transferInProgress = true
        for action in DocumentNoteAction.allCases { #expect(!model.canPerformNoteAction(action)) }
        let retainedCommand = try #require(menu.items.first)
        item.invalidate()
        #expect(item.menu.items.isEmpty)
        #expect(item.menu.delegate == nil)
        let overflow = try #require(item.menuFormRepresentation)
        #expect(!item.isEnabled && item.action == nil && item.target == nil)
        #expect(overflow.submenu === item.menu)
        #expect(overflow.submenu?.items.isEmpty == true)
        #expect(!item.validateMenuItem(retainedCommand))
        item.menuNeedsUpdate(menu)
        item.validate()
        #expect(menu.items.isEmpty && !item.isEnabled)
        #expect(item.menuFormRepresentation?.submenu?.items.isEmpty == true)
    }

    @Test("The separate window retains exactly one More menu with its window actions")
    func detachedMenuUsesExistingSlot() throws {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        model.isDetachedDocumentWindow = true
        let controller = DetachedDocumentToolbar(model: model)
        let ids = controller.toolbarDefaultItemIdentifiers(controller.toolbar)
        #expect(ids.filter { $0.rawValue == "more" }.count == 1)
        let item = try #require(
            controller.toolbar(
                controller.toolbar,
                itemForItemIdentifier: .init("more"), willBeInsertedIntoToolbar: true) as? DocumentNoteActionsToolbarItem)
        let menu = item.menu
        let move = try #require(menu.items.first { $0.identifier?.rawValue == "scholium.noteActions.moveWindow" })
        #expect(move.title == ScholiumL10n.string("Move to Main Window"))
        let close = try #require(menu.items.first { $0.identifier?.rawValue == "scholium.noteActions.close" })
        #expect(close.title == ScholiumL10n.string("Close Window"))
        #expect(menu.items.last?.identifier?.rawValue == "scholium.noteActions.trash")
    }
}
