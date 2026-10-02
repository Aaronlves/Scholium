import AppKit
import Testing

@testable import ScholiumApp

@Suite("Native PDF reader menus", .serialized)
@MainActor
struct PDFReaderMenuButtonTests {
    @Test("Native controls expose explicit names and retain a separate pull-down title")
    func controlNamesAndTitle() throws {
        let controller = reader()
        defer { controller.shutdown() }
        for kind in PDFReaderMenuButton.Kind.allCases {
            let button = PDFReaderNativeMenuButton(controller: controller, kind: kind)
            defer { button.invalidate() }
            let menu = try #require(button.menu)
            let reservedTitle = try #require(menu.items.first)
            let firstCommand = try #require(menu.items.dropFirst().first)
            #expect(button.accessibilityLabel() == ScholiumL10n.dynamicString(kind.title))
            #expect(button.accessibilityIdentifier() == kind.identifier)
            #expect(button.pullsDown)
            #expect(!button.autoenablesItems)
            #expect((button.cell as? NSPopUpButtonCell)?.usesItemFromMenu == true)
            #expect(reservedTitle.title == ScholiumL10n.dynamicString(kind.title))
            #expect(reservedTitle.representedObject == nil)
            #expect(firstCommand.action != nil)
            #expect(firstCommand.representedObject as? String != nil)
            #expect(button.frame.width >= 28 && button.frame.height >= 28)
            let owner = try #require(menu.delegate as? PDFReaderCommandMenu)
            owner.menuNeedsUpdate(menu)
            #expect(menu.items.first === reservedTitle)
            #expect(menu.items.dropFirst().first === firstCommand)
        }
    }

    @Test("Toolbar command menus begin with a real command and overflow retains that first action")
    func toolbarMenusHaveNoControlTitle() throws {
        let controller = reader()
        defer { controller.shutdown() }
        for kind in PDFReaderMenuButton.Kind.allCases {
            let owner = PDFReaderCommandMenu(controller: controller, kind: kind)
            defer { owner.invalidate() }
            let first = try #require(owner.menu.items.first)
            #expect(first.representedObject as? String == (kind == .actions ? "attach" : "zoomIn"))
            #expect(first.action != nil)
            let overflow = owner.makeOverflowMenu()
            #expect(overflow.items.first?.identifier == first.identifier)
            #expect(overflow.items.count == owner.menu.items.count)
            #expect(overflow.items.allSatisfy { $0.isSeparatorItem || $0.representedObject as? String != nil })
        }
    }

    @Test("Opening refreshes capability and toggle states while native target dispatch reaches the current owner")
    func commandDispatch() throws {
        let app = NSApplication.shared
        let first = reader()
        let second = reader()
        defer {
            first.shutdown()
            second.shutdown()
        }
        let owner = PDFReaderCommandMenu(controller: first, kind: .actions)
        defer { owner.invalidate() }
        let menu = owner.menu
        let highlight = try #require(menu.items.first { $0.representedObject as? String == "highlight" })
        let comment = try #require(menu.items.first { $0.representedObject as? String == "comment" })
        let toggle = try #require(menu.items.first { $0.representedObject as? String == "showAnnotations" })
        #expect(!highlight.isEnabled && !comment.isEnabled)
        #expect(toggle.isEnabled && toggle.state == .off)
        #expect(app.sendAction(try #require(toggle.action), to: toggle.target, from: toggle))
        #expect(first.showsAnnotations)
        #expect(toggle.state == .on)

        first.showsAnnotations = false
        owner.menuNeedsUpdate(menu)
        #expect(toggle.state == .off)
        owner.update(controller: second)
        #expect(app.sendAction(try #require(toggle.action), to: toggle.target, from: toggle))
        #expect(!first.showsAnnotations)
        #expect(second.showsAnnotations)
    }

    @Test("Unavailable source commands and dismantled targets cannot perform a stale command")
    func unavailableAndInvalidation() throws {
        let app = NSApplication.shared
        let controller = reader()
        defer { controller.shutdown() }
        let actions = PDFReaderCommandMenu(controller: controller, kind: .actions)
        let menu = actions.menu
        let attach = try #require(menu.items.first { $0.representedObject as? String == "attach" })
        let detach = try #require(menu.items.first { $0.representedObject as? String == "detach" })
        let export = try #require(menu.items.first { $0.representedObject as? String == "export" })
        let zotero = try #require(menu.items.first { $0.representedObject as? String == "openZotero" })
        #expect(!attach.isEnabled && !detach.isEnabled && !export.isEnabled)
        #expect(zotero.isHidden && !zotero.isEnabled)
        #expect(app.sendAction(try #require(attach.action), to: attach.target, from: attach))
        #expect(!controller.attachRequested)
        actions.invalidate()
        #expect(!actions.isEnabled)
        #expect(menu.items.isEmpty && menu.delegate == nil)
        #expect(attach.target == nil && attach.action == nil)

        let annotations = PDFReaderCommandMenu(controller: controller, kind: .actions)
        let toggle = try #require(annotations.menu.items.first { $0.representedObject as? String == "showAnnotations" })
        let staleAction = try #require(toggle.action)
        annotations.invalidate()
        annotations.update(controller: controller)
        #expect(app.sendAction(staleAction, to: annotations, from: toggle))
        #expect(!controller.showsAnnotations)
        #expect(!annotations.isEnabled)
    }

    @Test("Toolbar overflow uses the same live command owner and invalidation revokes retained entries")
    func overflowCommands() throws {
        let controller = reader()
        defer { controller.shutdown() }
        let owner = PDFReaderCommandMenu(controller: controller, kind: .actions, includesControlTitle: true)
        let overflow = owner.makeOverflowMenu()
        #expect(owner.makeOverflowMenu() === overflow)
        #expect(overflow.items.first?.representedObject as? String == "attach")
        let toggle = try #require(overflow.items.first { $0.representedObject as? String == "showAnnotations" })
        #expect(toggle.identifier?.rawValue == "scholium.pdf.actions.showAnnotations")
        let action = try #require(toggle.action)
        #expect(NSApplication.shared.sendAction(action, to: toggle.target, from: toggle))
        #expect(controller.showsAnnotations && toggle.state == .on)
        owner.invalidate()
        #expect(overflow.items.isEmpty && overflow.delegate == nil)
        #expect(toggle.target == nil && toggle.action == nil)
        #expect(NSApplication.shared.sendAction(action, to: owner, from: toggle))
        #expect(controller.showsAnnotations)
        let dismantledOverflow = owner.makeOverflowMenu()
        #expect(dismantledOverflow.items.isEmpty && dismantledOverflow.delegate == nil)
    }

    @Test("A retained menu rechecks presentation admission at dispatch and a dismantled pull-down stays inert")
    func presentationAdmission() throws {
        let controller = reader()
        defer { controller.shutdown() }
        var canPresent = true
        let owner = PDFReaderCommandMenu(controller: controller, kind: .actions, canPresent: { canPresent })
        defer { owner.invalidate() }
        let toggle = try #require(owner.menu.items.first { $0.representedObject as? String == "showAnnotations" })
        let action = try #require(toggle.action)
        #expect(toggle.isEnabled)
        canPresent = false
        #expect(NSApplication.shared.sendAction(action, to: toggle.target, from: toggle))
        #expect(!controller.showsAnnotations && !owner.isEnabled)
        owner.menuNeedsUpdate(owner.menu)
        #expect(!toggle.isEnabled)

        let button = PDFReaderNativeMenuButton(controller: controller, kind: .zoom)
        let menu = try #require(button.menu)
        let retained = try #require(menu.items.dropFirst().first)
        button.invalidate()
        button.update(controller: controller)
        #expect(!button.isEnabled && button.isAccessibilityHidden())
        #expect(menu.items.isEmpty && menu.delegate == nil)
        #expect(retained.target == nil && retained.action == nil)
    }

    private func reader() -> PDFReaderController {
        PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
    }
}
