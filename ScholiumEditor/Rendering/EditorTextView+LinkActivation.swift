// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

/// Observes native tracking without owning or consuming its selection events.
struct NativeLinkClick {
    let target: String
    let point: NSPoint
    let clickCount: Int
    let modifiers: NSEvent.ModifierFlags
    var dragged = false
    var releasePoint: NSPoint?

    mutating func observe(type: NSEvent.EventType, point: NSPoint) {
        if type == .leftMouseDragged { dragged = true }
        if type == .leftMouseUp { releasePoint = point }
    }

    func admitsActivation(selection: [NSRange], releaseTarget: String?) -> Bool {
        guard clickCount == 1, modifiers.intersection([.shift, .option, .control, .command]).isEmpty,
            !dragged, let releasePoint, releaseTarget == target,
            selection.allSatisfy({ $0.length == 0 })
        else { return false }
        return hypot(releasePoint.x - point.x, releasePoint.y - point.y) <= 3
    }
}

extension EditorTextView {
    func nativeLinkTarget(at offset: Int) -> String? {
        guard let storage = textStorage, offset >= 0, offset < storage.length else { return nil }
        return storage.attribute(.editorWikiTarget, at: offset, effectiveRange: nil) as? String
            ?? storage.attribute(.editorLinkURL, at: offset, effectiveRange: nil) as? String
    }

    func nativeLinkTarget(at event: NSEvent) -> String? {
        guard let offset = wrappedCellCharIndex(at: event) ?? clickCharIndex(at: event) else { return nil }
        return nativeLinkTarget(at: offset)
    }

    /// NSTextView's default implementation may launch a URL. Never call it:
    /// only a known source link can enter the application's navigation owner.
    public override func clicked(onLink link: Any, at charIndex: Int) {
        guard let target = nativeLinkTarget(at: charIndex) else { return }
        let supplied = (link as? String) ?? (link as? URL)?.absoluteString
        guard supplied == target else { return }
        onLinkActivation?(target)
    }

    @objc public func openNativeLink(_ sender: Any?) {
        if let item = sender as? NSMenuItem, let location = item.representedObject as? NativeLinkMenuTarget {
            guard nativeLinkTarget(at: location.offset) == location.target else { return }
            onLinkActivation?(location.target)
        } else if let target = nativeLinkTarget(at: selectedRange().location) {
            onLinkActivation?(target)
        }
    }

    func addNativeLinkMenu(to menu: NSMenu, event: NSEvent) {
        guard let offset = wrappedCellCharIndex(at: event) ?? clickCharIndex(at: event),
            let target = nativeLinkTarget(at: offset), onLinkActivation != nil
        else { return }
        let item = NSMenuItem(title: openLinkMenuTitle, action: #selector(openNativeLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NativeLinkMenuTarget(offset: offset, target: target)
        menu.insertItem(item, at: 0)
    }
}

private final class NativeLinkMenuTarget: NSObject {
    let offset: Int
    let target: String
    init(offset: Int, target: String) {
        self.offset = offset
        self.target = target
    }
}
