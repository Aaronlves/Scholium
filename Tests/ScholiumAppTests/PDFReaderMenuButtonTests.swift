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
            button.menuNeedsUpdate(menu)
            #expect(menu.items.first === reservedTitle)
            #expect(menu.items.dropFirst().first === firstCommand)
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
        let button = PDFReaderNativeMenuButton(controller: first, kind: .annotations)
        defer { button.invalidate() }
        let menu = try #require(button.menu)
        let highlight = try #require(menu.items.first { $0.representedObject as? String == "highlight" })
        let comment = try #require(menu.items.first { $0.representedObject as? String == "comment" })
        let toggle = try #require(menu.items.first { $0.representedObject as? String == "showAnnotations" })
        #expect(!highlight.isEnabled && !comment.isEnabled)
        #expect(toggle.isEnabled && toggle.state == .off)
        #expect(app.sendAction(try #require(toggle.action), to: toggle.target, from: toggle))
        #expect(first.showsAnnotations)
        #expect(toggle.state == .on)

        first.showsAnnotations = false
        button.menuNeedsUpdate(menu)
        #expect(toggle.state == .off)
        button.update(controller: second)
        #expect(app.sendAction(try #require(toggle.action), to: toggle.target, from: toggle))
        #expect(!first.showsAnnotations)
        #expect(second.showsAnnotations)
    }

    @Test("Unavailable source commands and dismantled targets cannot perform a stale command")
    func unavailableAndInvalidation() throws {
        let app = NSApplication.shared
        let controller = reader()
        defer { controller.shutdown() }
        let actions = PDFReaderNativeMenuButton(controller: controller, kind: .actions)
        let menu = try #require(actions.menu)
        let attach = try #require(menu.items.first { $0.representedObject as? String == "attach" })
        let detach = try #require(menu.items.first { $0.representedObject as? String == "detach" })
        let export = try #require(menu.items.first { $0.representedObject as? String == "export" })
        let zotero = try #require(menu.items.first { $0.representedObject as? String == "openZotero" })
        #expect(!attach.isEnabled && !detach.isEnabled && !export.isEnabled)
        #expect(zotero.isHidden && !zotero.isEnabled)
        #expect(app.sendAction(try #require(attach.action), to: attach.target, from: attach))
        #expect(!controller.attachRequested)
        actions.invalidate()
        #expect(!actions.isEnabled && actions.isAccessibilityHidden())
        #expect(menu.items.isEmpty && menu.delegate == nil)
        #expect(attach.target == nil && attach.action == nil)

        let annotations = PDFReaderNativeMenuButton(controller: controller, kind: .annotations)
        let toggle = try #require(annotations.menu?.items.first { $0.representedObject as? String == "showAnnotations" })
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
        let button = PDFReaderNativeMenuButton(controller: controller, kind: .annotations)
        let overflow = button.makeOverflowMenu()
        #expect(button.makeOverflowMenu() === overflow)
        let toggle = try #require(overflow.items.first { $0.representedObject as? String == "showAnnotations" })
        #expect(toggle.identifier?.rawValue == "scholium.pdf.annotations.showAnnotations")
        let action = try #require(toggle.action)
        #expect(NSApplication.shared.sendAction(action, to: toggle.target, from: toggle))
        #expect(controller.showsAnnotations && toggle.state == .on)
        button.invalidate()
        #expect(overflow.items.isEmpty && overflow.delegate == nil)
        #expect(toggle.target == nil && toggle.action == nil)
        #expect(NSApplication.shared.sendAction(action, to: button, from: toggle))
        #expect(controller.showsAnnotations)
    }

    @Test("The native toolbar projects empty capabilities and releases controls and overflow on teardown")
    func toolbarLifetime() throws {
        let controller = reader()
        defer { controller.shutdown() }
        let item = PDFReaderToolbarItem(identifier: .init("fixture.pdf.controls"), controller: controller)
        let view = try #require(item.view as? NSStackView)
        #expect(view.accessibilityIdentifier() == "scholium.pdf.controls")
        #expect(view.arrangedSubviews.count == 9)
        #expect(view.arrangedSubviews.filter { !$0.isHidden }.count == 1)
        let overflow = try #require(item.menuFormRepresentation?.submenu)
        #expect(overflow.items.count == 7)
        #expect(overflow.items.prefix(3).allSatisfy { !$0.isEnabled })
        item.invalidate()
        item.refresh()
        #expect(!item.isEnabled && item.isHidden)
        #expect(overflow.items.isEmpty && overflow.delegate == nil)
        #expect(item.menuFormRepresentation?.isEnabled == false)
        #expect((view.arrangedSubviews[1] as? NSTextField)?.target == nil)
    }

    private func reader() -> PDFReaderController {
        PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
    }
}
