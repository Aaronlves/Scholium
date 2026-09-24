import AppKit

enum InlineGhostKind {
    case local, ai, status
}

struct InlineGhostPresentation {
    let text: String
    let kind: InlineGhostKind
    let caret: Int
    let rect: NSRect
    let font: NSFont
    let elided: Bool
}

extension EditorTextView {
    public var hasInlineGhost: Bool { inlineGhostPresentation != nil }

    /// Draw a suggestion beside the caret without adding provisional text to
    /// NSTextStorage. The returned prefix is the *entire* text Tab may accept.
    /// Long suggestions are visibly elided and only their visible prefix may
    /// be accepted; the ellipsis is chrome, not source.
    @discardableResult
    public func showInlineGhost(_ text: String, at caret: Int, isAI: Bool = false, isStatus: Bool = false) -> String? {
        clearInlineGhost()
        guard viewMode == .edit, !isComposingSource, let window,
            !text.isEmpty, !text.contains(where: { $0.isNewline }),
            caret >= 0, caret <= (rawSource as NSString).length,
            selectedRange() == NSRange(location: caret, length: 0)
        else { return nil }

        let screen = firstRect(forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        let local = convert(window.convertFromScreen(screen), from: nil)
        guard local.width.isFinite, local.height.isFinite, local.minX.isFinite, local.minY.isFinite else { return nil }
        let fontIndex = max(0, min(caret == 0 ? 0 : caret - 1, (textStorage?.length ?? 1) - 1))
        let font =
            (textStorage?.length ?? 0) > 0
            ? (textStorage?.attribute(.font, at: fontIndex, effectiveRange: nil) as? NSFont ?? bodyFont)
            : bodyFont
        let hintFont = NSFont.systemFont(ofSize: max(10, font.pointSize * 0.72))
        let hint = isStatus ? "" : (isAI ? "  AI  ⇥" : "  ⇥")
        let hintWidth = (hint as NSString).size(withAttributes: [.font: hintFont]).width
        let contentRight = textContainerOrigin.x + (textContainer?.size.width ?? bounds.width)
        let right = min(contentRight, visibleRect.maxX) - 10
        let available = right - local.minX - hintWidth - 8
        guard available >= max(18, font.pointSize) else { return nil }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ value: String) -> CGFloat { (value as NSString).size(withAttributes: attributes).width }
        let elided = width(text) > available
        var visible = text
        if elided {
            visible = ""
            for character in text {
                let next = visible + String(character)
                if width(next + "…") > available { break }
                visible = next
            }
        }
        guard !visible.isEmpty else { return nil }
        let kind: InlineGhostKind = isStatus ? .status : (isAI ? .ai : .local)
        inlineGhostPresentation = .init(text: visible, kind: kind, caret: caret, rect: local, font: font, elided: elided)
        let repaint = NSRect(x: local.minX - 2, y: local.minY - 2, width: max(0, right - local.minX + 4), height: local.height + 6)
        setNeedsDisplay(repaint)
        return visible
    }

    public func clearInlineGhost() {
        guard let old = inlineGhostPresentation else { return }
        inlineGhostPresentation = nil
        let repaint = NSRect(
            x: old.rect.minX - 2, y: old.rect.minY - 2,
            width: max(0, visibleRect.maxX - old.rect.minX + 4), height: old.rect.height + 6)
        setNeedsDisplay(repaint)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ghost = inlineGhostPresentation, viewMode == .edit,
            !isComposingSource, selectedRange() == NSRange(location: ghost.caret, length: 0),
            NSRect(x: ghost.rect.minX, y: ghost.rect.minY, width: 2, height: ghost.rect.height).intersects(dirtyRect)
        else { return }
        let color = NSColor.secondaryLabelColor
        let hintFont = NSFont.systemFont(ofSize: max(10, ghost.font.pointSize * 0.72))
        let hint =
            switch ghost.kind {
            case .local: "  ⇥"
            case .ai: "  AI  ⇥"
            case .status: ""
            }
        let text = ghost.text as NSString
        let textWidth = text.size(withAttributes: [.font: ghost.font]).width
        let y = ghost.rect.midY - ghost.font.ascender / 2 - 1
        text.draw(at: NSPoint(x: ghost.rect.minX, y: y), withAttributes: [.font: ghost.font, .foregroundColor: color])
        let elision = ghost.elided ? "…" : ""
        let elisionWidth = (elision as NSString).size(withAttributes: [.font: ghost.font]).width
        if ghost.elided {
            (elision as NSString).draw(
                at: NSPoint(x: ghost.rect.minX + textWidth, y: y),
                withAttributes: [.font: ghost.font, .foregroundColor: color])
        }
        if ghost.kind != .status {
            let underline = NSBezierPath()
            underline.lineWidth = 1
            underline.setLineDash([1.5, 2.5], count: 2, phase: 0)
            let underlineY = y + ghost.font.ascender + 2
            underline.move(to: NSPoint(x: ghost.rect.minX, y: underlineY))
            underline.line(to: NSPoint(x: ghost.rect.minX + textWidth, y: underlineY))
            color.setStroke()
            underline.stroke()
            (hint as NSString).draw(
                at: NSPoint(x: ghost.rect.minX + textWidth + elisionWidth, y: y + 2),
                withAttributes: [.font: hintFont, .foregroundColor: color])
        }
    }
}
