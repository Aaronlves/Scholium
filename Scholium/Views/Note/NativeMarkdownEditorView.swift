import ScholiumContracts
import AppKit
import SwiftUI

private final class CommentableMarkdownTextView: NSTextView {
    var onRequestComment: ((NSRange) -> Void)?
    private var contextReviewRange: NSRange?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard onRequestComment != nil,
              let reviewRange = reviewRange(for: event) else {
            return super.menu(for: event)
        }
        contextReviewRange = reviewRange

        let menu = NSMenu()
        menu.autoenablesItems = true

        if selectedRange().length > 0 {
            menu.addItem(menuItem(title: "Copy", action: #selector(NSText.copy(_:))))
        }

        menu.addItem(menuItem(title: "Add Comment…", action: #selector(requestComment(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Select All", action: #selector(NSText.selectAll(_:))))
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func requestComment(_ sender: Any?) {
        guard let contextReviewRange, let onRequestComment else { return }
        setSelectedRange(contextReviewRange)
        onRequestComment(contextReviewRange)
    }

    private func reviewRange(for event: NSEvent) -> NSRange? {
        let selected = selectedRange()
        if selected.length > 0 { return selected }

        let source = string as NSString
        guard source.length > 0,
              let layoutManager,
              let textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let safeGlyphIndex = min(glyphIndex, layoutManager.numberOfGlyphs - 1)
        let characterIndex = min(layoutManager.characterIndexForGlyph(at: safeGlyphIndex), source.length - 1)
        return source.lineRange(for: NSRange(location: characterIndex, length: 0))
    }
}

/// The fast, selectable Read-mode projection. It shares the same native
/// semantic styling as Live Preview without constructing a web process.
struct NativeMarkdownReadView: NSViewRepresentable {
    let source: String
    let textScale: Double
    let topContentInset: CGFloat
    let onLinkClick: (String) -> Void
    let onRequestComment: ((MarkdownReviewSelection) -> Void)?
    var onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil

    func makeCoordinator() -> NativeMarkdownCoordinator {
        NativeMarkdownCoordinator(
            text: .constant(source),
            isEditable: false,
            textScale: textScale,
            topContentInset: topContentInset,
            onLinkClick: onLinkClick,
            onRequestComment: onRequestComment,
            onSelectionChange: onSelectionChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(initialText: source)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateTextIfNeeded(source)
        context.coordinator.updateTextScale(textScale, in: scrollView)
        context.coordinator.updateTopContentInset(topContentInset)
    }
}

@MainActor
final class NativeMarkdownCoordinator: NSObject, NSTextViewDelegate {
    private struct ViewportAnchor {
        let characterIndex: Int
        let documentPositionBefore: CGFloat
        let viewportOriginBefore: CGFloat
    }

    @Binding private var text: String
    private let isEditable: Bool
    private var textScale: Double
    private var topContentInset: CGFloat
    private let onLinkClick: ((String) -> Void)?
    private let onRequestComment: ((MarkdownReviewSelection) -> Void)?
    private let onSelectionChange: ((MarkdownReviewSelection?) -> Void)?
    private var isApplyingStyles = false
    private var pendingStyleWork: DispatchWorkItem?
    private var pendingSelectionStyleWork: DispatchWorkItem?
    private var styledSelectionRanges: [NSRange] = []
    private var projectionGeneration: UInt = 0
    private var pendingViewportAnchor: ViewportAnchor?
    private var footnotePopover: NSPopover?
    weak var textView: NSTextView?

    init(
        text: Binding<String>,
        isEditable: Bool,
        textScale: Double = 1.0,
        topContentInset: CGFloat = 26,
        onLinkClick: ((String) -> Void)?,
        onRequestComment: ((MarkdownReviewSelection) -> Void)?,
        onSelectionChange: ((MarkdownReviewSelection?) -> Void)? = nil
    ) {
        _text = text
        self.isEditable = isEditable
        self.textScale = min(2.0, max(1.0, textScale))
        self.topContentInset = max(0, topContentInset)
        self.onLinkClick = onLinkClick
        self.onRequestComment = onRequestComment
        self.onSelectionChange = onSelectionChange
    }

    func makeScrollView(initialText: String) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // Document scaling must reflow ordinary prose. Magnifying the scroll
        // view doubles its layout width and can silently clip the trailing
        // half of a paragraph at 200%, even with no horizontal scroller.
        scrollView.allowsMagnification = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = CommentableMarkdownTextView()
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = isEditable
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = isEditable
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 32, height: topContentInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = initialText
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.setAccessibilityLabel(isEditable ? "Markdown live preview editor" : "Markdown reader")
        if onRequestComment != nil {
            textView.onRequestComment = { [weak self] range in
                self?.requestComment(for: range)
            }
        }

        scrollView.documentView = textView
        self.textView = textView
        applyStyles()
        return scrollView
    }

    func updateTextScale(_ requestedScale: Double, in scrollView: NSScrollView) {
        let scale = min(2.0, max(1.0, requestedScale))
        guard abs(textScale - scale) > 0.001 else { return }
        pendingViewportAnchor = textView.flatMap { captureViewportAnchor(in: $0) }
        textScale = scale
        applyStyles()
    }

    func updateTopContentInset(_ requestedInset: CGFloat) {
        let inset = max(0, requestedInset)
        guard abs(topContentInset - inset) > 0.5, let textView else { return }
        topContentInset = inset
        textView.textContainerInset = NSSize(width: textView.textContainerInset.width, height: inset)
    }

    func updateTextIfNeeded(_ newText: String) {
        guard let textView, textView.string != newText else { return }
        let selections = textView.selectedRanges
        textView.string = newText
        let utf16Count = newText.utf16.count
        textView.selectedRanges = selections.compactMap { value in
            let range = value.rangeValue
            let location = min(range.location, utf16Count)
            return NSValue(range: NSRange(
                location: location,
                length: min(range.length, max(0, utf16Count - location))
            ))
        }
        applyStyles()
    }

    func textDidChange(_ notification: Notification) {
        guard isEditable, !isApplyingStyles, let textView else { return }
        text = textView.string
        pendingStyleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyStyles() }
        pendingStyleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingStyles else { return }
        if !isEditable {
            guard let textView = notification.object as? NSTextView else { return }
            onSelectionChange?(reviewSelection(for: textView.selectedRange()))
            return
        }
        pendingSelectionStyleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyStyles() }
        pendingSelectionStyleWork = work
        DispatchQueue.main.async(execute: work)
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
        toCharacterRanges newSelectedCharRanges: [NSValue]
    ) -> [NSValue] {
        guard isEditable,
              !isApplyingStyles,
              let newSelection = newSelectedCharRanges.first?.rangeValue,
              newSelection.location != NSNotFound else { return newSelectedCharRanges }
        pendingViewportAnchor = captureViewportAnchor(
            in: textView,
            characterIndex: newSelection.location
        )
        return newSelectedCharRanges
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL else { return false }
        if url.scheme == "scholium-footnote" {
            let encoded = url.absoluteString.replacingOccurrences(of: "scholium-footnote:", with: "")
            showFootnotePopover(
                encoded.removingPercentEncoding ?? encoded,
                atCharacterIndex: charIndex,
                in: textView
            )
            return true
        }
        guard let onLinkClick, url.scheme == "scholium-note" else { return false }
        let encoded = url.absoluteString.replacingOccurrences(of: "scholium-note:", with: "")
        onLinkClick(encoded.removingPercentEncoding ?? encoded)
        return true
    }

    private func requestComment(for requestedRange: NSRange) {
        guard let onRequestComment,
              let selection = reviewSelection(for: requestedRange) else { return }
        onRequestComment(selection)
    }

    private func reviewSelection(for requestedRange: NSRange) -> MarkdownReviewSelection? {
        guard let textView else { return nil }
        let source = textView.string as NSString
        guard requestedRange.location != NSNotFound,
              requestedRange.location >= 0,
              requestedRange.length > 0,
              NSMaxRange(requestedRange) <= source.length else { return nil }

        let prefix = source.substring(to: requestedRange.location)
        let startLine = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let selectedText = source.substring(with: requestedRange)
        let endLine = startLine + selectedText.dropLast().reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String(trimmed.prefix(600))
        guard !excerpt.isEmpty else { return nil }
        return MarkdownReviewSelection(
            startLine: startLine,
            endLine: max(startLine, endLine),
            excerpt: excerpt,
            utf16LowerBound: requestedRange.location,
            utf16UpperBound: NSMaxRange(requestedRange),
            contextBefore: source.substring(with: NSRange(
                location: max(0, requestedRange.location - min(48, requestedRange.location)),
                length: min(48, requestedRange.location)
            )),
            contextAfter: source.substring(with: NSRange(
                location: NSMaxRange(requestedRange),
                length: min(48, source.length - NSMaxRange(requestedRange))
            ))
        )
    }

    func applyStyles() {
        guard let textView, let storage = textView.textStorage else { return }
        let viewportAnchor = pendingViewportAnchor ?? captureViewportAnchor(in: textView)
        pendingViewportAnchor = nil
        projectionGeneration &+= 1
        let generation = projectionGeneration
        isApplyingStyles = true
        defer {
            styledSelectionRanges = []
            isApplyingStyles = false
        }

        let selections = textView.selectedRanges
        styledSelectionRanges = selections.map(\.rangeValue)
        let source = storage.string as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let baseFont = ScholiumTypography.body(scale: CGFloat(textScale))
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = scaled(4)
        baseParagraph.paragraphSpacing = scaled(5)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.clear,
            .paragraphStyle: baseParagraph,
        ], range: fullRange)

        let bodyRange = collapseFrontmatter(in: source, storage: storage)
        styleInlineMarkup(in: source, range: bodyRange, storage: storage, baseFont: baseFont)
        styleHighlights(in: source, range: bodyRange, storage: storage)
        styleFootnotes(in: source, range: bodyRange, storage: storage)
        styleBlockquotes(in: source, range: bodyRange, storage: storage, baseFont: baseFont)
        styleCallouts(in: source, range: bodyRange, storage: storage)
        styleHeadings(in: source, range: bodyRange, storage: storage)

        storage.endEditing()
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraph,
        ]
        if textView.selectedRanges != selections {
            textView.selectedRanges = selections
        }
        restoreViewportAnchor(viewportAnchor, in: textView)
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self,
                  let textView,
                  self.projectionGeneration == generation else { return }
            self.restoreViewportAnchor(viewportAnchor, in: textView)
        }
    }

    private func captureViewportAnchor(
        in textView: NSTextView,
        characterIndex requestedCharacterIndex: Int? = nil
    ) -> ViewportAnchor? {
        guard let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let sourceLength = (textView.string as NSString).length
        guard sourceLength > 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let selectionLocation = requestedCharacterIndex ?? textView.selectedRange().location
        guard selectionLocation != NSNotFound else { return nil }
        let characterIndex = min(max(0, selectionLocation), sourceLength - 1)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return ViewportAnchor(
            characterIndex: characterIndex,
            documentPositionBefore: glyphRect.minY + textView.textContainerOrigin.y,
            viewportOriginBefore: scrollView.contentView.bounds.minY
        )
    }

    private func restoreViewportAnchor(_ anchor: ViewportAnchor?, in textView: NSTextView) {
        guard let anchor,
              let scrollView = textView.enclosingScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let sourceLength = (textView.string as NSString).length
        guard sourceLength > 0 else { return }

        layoutManager.ensureLayout(for: textContainer)
        let characterIndex = min(anchor.characterIndex, sourceLength - 1)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let documentPositionAfter = glyphRect.minY + textView.textContainerOrigin.y
        let clipView = scrollView.contentView
        let laidOutHeight = layoutManager.usedRect(for: textContainer).maxY
            + textView.textContainerOrigin.y
            + textView.textContainerInset.height
        let documentHeight = max(textView.bounds.height, laidOutHeight)
        let maximumOrigin = max(0, documentHeight - clipView.bounds.height)
        let restoredOrigin = MarkdownSyntaxProjection.viewportOriginPreservingAnchor(
            currentOrigin: anchor.viewportOriginBefore,
            anchorPositionBefore: anchor.documentPositionBefore,
            anchorPositionAfter: documentPositionAfter,
            maximumOrigin: maximumOrigin
        )

        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: restoredOrigin))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func styleHighlights(in source: NSString, range: NSRange, storage: NSTextStorage) {
        for highlight in MarkdownSemanticProjection.highlights(in: source as String)
            where NSIntersectionRange(highlight.range, range).length == highlight.range.length {
            storage.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.34),
            ], range: highlight.contentRange)
            hide(
                NSRange(location: highlight.range.location, length: highlight.contentRange.location - highlight.range.location),
                in: storage,
                revealWithin: highlight.range
            )
            hide(
                NSRange(location: NSMaxRange(highlight.contentRange), length: NSMaxRange(highlight.range) - NSMaxRange(highlight.contentRange)),
                in: storage,
                revealWithin: highlight.range
            )
        }
    }

    private func styleFootnotes(in source: NSString, range: NSRange, storage: NSTextStorage) {
        for footnote in MarkdownSemanticProjection.footnoteReferences(in: source as String)
            where NSIntersectionRange(footnote.range, range).length == footnote.range.length {
            let encoded = footnote.content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? footnote.content
            guard let footnoteURL = URL(string: "scholium-footnote:\(encoded)") else { continue }
            storage.addAttributes([
                .font: readingFont(size: 12, bold: true),
                .baselineOffset: scaled(7),
                .foregroundColor: NSColor.linkColor,
                .link: footnoteURL,
                .toolTip: footnote.content,
            ], range: footnote.labelRange)
            hide(
                NSRange(location: footnote.range.location, length: footnote.labelRange.location - footnote.range.location),
                in: storage,
                revealWithin: footnote.range
            )
            hide(
                NSRange(location: NSMaxRange(footnote.labelRange), length: NSMaxRange(footnote.range) - NSMaxRange(footnote.labelRange)),
                in: storage,
                revealWithin: footnote.range
            )
        }
    }

    private func styleCallouts(in source: NSString, range: NSRange, storage: NSTextStorage) {
        for callout in MarkdownSemanticProjection.callouts(in: source as String)
            where NSIntersectionRange(callout.blockRange, range).length == callout.blockRange.length {
            let accent = calloutAccent(for: callout.kind)
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = scaled(18)
            paragraph.firstLineHeadIndent = scaled(18)
            paragraph.tailIndent = -scaled(12)
            paragraph.lineSpacing = scaled(4)
            paragraph.paragraphSpacing = scaled(5)
            paragraph.paragraphSpacingBefore = scaled(7)
            storage.addAttributes([
                .backgroundColor: accent.withAlphaComponent(0.09),
                .paragraphStyle: paragraph,
            ], range: callout.blockRange)
            storage.addAttributes([
                .font: readingFont(size: 15, bold: true),
                .foregroundColor: accent,
            ], range: callout.kindRange)

            for marker in callout.markerRanges.dropFirst() {
                hide(marker, in: storage, revealWithin: callout.blockRange)
            }
            if let foldMarkerRange = callout.foldMarkerRange {
                hide(foldMarkerRange, in: storage, revealWithin: callout.headerRange)
            }
            let prefixLength = callout.kindRange.location - callout.headerRange.location
            hide(
                NSRange(location: callout.headerRange.location, length: prefixLength),
                in: storage,
                revealWithin: callout.headerRange
            )
            let closingLocation = NSMaxRange(callout.kindRange)
            if closingLocation < NSMaxRange(callout.headerRange),
               source.character(at: closingLocation) == 93 {
                hide(NSRange(location: closingLocation, length: 1), in: storage, revealWithin: callout.headerRange)
            }
        }
    }

    private func calloutAccent(for kind: String) -> NSColor {
        switch CalloutSemanticVocabulary.role(for: kind) {
        case .orient: .systemBlue
        case .cite, .quote: .systemTeal
        case .connect: .systemCyan
        case .state: .systemIndigo
        case .illustrate: .systemPurple
        case .flag: .systemOrange
        case .neutral: .secondaryLabelColor
        }
    }

    private func showFootnotePopover(_ content: String, atCharacterIndex index: Int, in textView: NSTextView) {
        guard !content.isEmpty, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        footnotePopover?.close()

        let label = NSTextField(wrappingLabelWithString: content)
        label.font = readingFont(size: 15)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 8
        label.preferredMaxLayoutWidth = 320
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
        footnotePopover = popover
    }

    private func collapseFrontmatter(in source: NSString, storage: NSTextStorage) -> NSRange {
        let bomLength = source.hasPrefix("\u{FEFF}") ? 1 : 0
        guard source.length >= bomLength + 3,
              source.substring(with: NSRange(location: bomLength, length: 3)) == "---" else {
            return NSRange(location: 0, length: source.length)
        }
        let searchStart = min(source.length, bomLength + 3)
        let closing = source.range(
            of: "\n---",
            options: [],
            range: NSRange(location: searchStart, length: source.length - searchStart)
        )
        guard closing.location != NSNotFound else {
            return NSRange(location: 0, length: source.length)
        }
        var bodyStart = NSMaxRange(closing)
        if bodyStart < source.length, source.character(at: bodyStart) == 10 { bodyStart += 1 }
        hide(NSRange(location: 0, length: bodyStart), in: storage, collapseLines: true)
        return NSRange(location: bodyStart, length: source.length - bodyStart)
    }

    private func styleInlineMarkup(
        in source: NSString,
        range: NSRange,
        storage: NSTextStorage,
        baseFont: NSFont
    ) {
        forEachMatch(#"\*\*([^*\n]+)\*\*"#, in: source, range: range) { match in
            let content = match.range(at: 1)
            storage.addAttribute(
                .font,
                value: ScholiumTypography.body(
                    scale: CGFloat(textScale),
                    bold: true
                ),
                range: content
            )
            hide(NSRange(location: match.range.location, length: content.location - match.range.location), in: storage, revealWithin: match.range)
            hide(NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)), in: storage, revealWithin: match.range)
        }

        let italicFont = ScholiumTypography.body(
            scale: CGFloat(textScale),
            italic: true
        )
        forEachMatch(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: source, range: range) { match in
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont, range: content)
            hide(NSRange(location: match.range.location, length: 1), in: storage, revealWithin: match.range)
            hide(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: storage, revealWithin: match.range)
        }

        forEachMatch(#"`([^`\n]+)`"#, in: source, range: range) { match in
            let content = match.range(at: 1)
            storage.addAttributes([
                .font: ScholiumTypography.exactSource(scale: CGFloat(textScale)),
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.16),
            ], range: content)
            hide(NSRange(location: match.range.location, length: 1), in: storage, revealWithin: match.range)
            hide(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: storage, revealWithin: match.range)
        }

        styleWikilinks(in: source, range: range, storage: storage)

        forEachMatch(#"(?<!!)\[([^\]]+)\]\(([^\)]+)\)"#, in: source, range: range) { match in
            let label = match.range(at: 1)
            let destination = source.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hide(NSRange(location: match.range.location, length: label.location - match.range.location), in: storage, revealWithin: match.range)
            hide(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), in: storage, revealWithin: match.range)
            let approvedExternalSchemes = Set(["http", "https", "mailto", "zotero"])
            if let url = URL(string: destination),
               let scheme = url.scheme?.lowercased(),
               approvedExternalSchemes.contains(scheme) {
                storage.addAttribute(.link, value: url, range: label)
            } else {
                addLink(target: destination, visibleRange: label, storage: storage)
            }
        }
    }

    private func styleBlockquotes(
        in source: NSString,
        range: NSRange,
        storage: NSTextStorage,
        baseFont: NSFont
    ) {
        let quoteFont = ScholiumTypography.body(
            scale: CGFloat(textScale),
            italic: true
        )
        forEachMatch(#"(?m)^(\s*>\s?)(.*)$"#, in: source, range: range) { match in
            let marker = match.range(at: 1)
            let content = match.range(at: 2)
            hide(marker, in: storage, revealWithin: match.range)
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = scaled(16)
            paragraph.firstLineHeadIndent = scaled(16)
            paragraph.lineSpacing = scaled(4)
            paragraph.paragraphSpacing = scaled(5)
            storage.addAttributes([
                .font: quoteFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ], range: content)
        }
    }

    private func styleHeadings(in source: NSString, range: NSRange, storage: NSTextStorage) {
        forEachMatch(#"(?m)^(\*\*)?(#{1,6}\s+)(.+?)(\*\*)?$"#, in: source, range: range) { match in
            let level = min(6, max(1, match.range(at: 2).length - 1))
            guard let headingLevel = ScholiumTypography.HeadingLevel(rawValue: level) else { return }
            let content = match.range(at: 3)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = scaled(2)
            paragraph.paragraphSpacingBefore = scaled(level <= 2 ? 18 : 12)
            paragraph.paragraphSpacing = scaled(level <= 2 ? 10 : 7)
            storage.addAttributes([
                .font: ScholiumTypography.heading(
                    level: headingLevel,
                    scale: CGFloat(textScale)
                ),
                .paragraphStyle: paragraph,
            ], range: content)
            hide(match.range(at: 1), in: storage, revealWithin: match.range)
            hide(match.range(at: 2), in: storage, revealWithin: match.range)
            hide(match.range(at: 4), in: storage, revealWithin: match.range)
        }
    }

    private func styleWikilinks(in source: NSString, range: NSRange, storage: NSTextStorage) {
        let document = NoteDocument(relativePath: "native-projection.md", rawContent: source as String)
        let semantic = MarkdownSemanticDocument(parsing: document)

        for link in semantic.links where link.syntax == .wikilink || link.syntax == .vectorWikilink {
            let fullRange = link.span.nsRange
            guard NSIntersectionRange(fullRange, range).length == fullRange.length,
                  NSMaxRange(fullRange) <= source.length else { continue }
            let opening = source.range(of: "[[", options: [], range: fullRange)
            guard opening.location != NSNotFound else { continue }
            let innerStart = NSMaxRange(opening)
            let innerSearch = NSRange(
                location: innerStart,
                length: max(0, NSMaxRange(fullRange) - innerStart)
            )
            let closing = source.range(of: "]]", options: .backwards, range: innerSearch)
            guard closing.location != NSNotFound, closing.location >= innerStart else { continue }
            let innerRange = NSRange(location: innerStart, length: closing.location - innerStart)
            let pipe = source.range(of: "|", options: [], range: innerRange)
            let targetRange = pipe.location == NSNotFound
                ? innerRange
                : NSRange(location: innerStart, length: pipe.location - innerStart)
            let aliasRange = pipe.location == NSNotFound
                ? nil
                : NSRange(location: NSMaxRange(pipe), length: closing.location - NSMaxRange(pipe))
            let visibleRange: NSRange
            if let aliasRange, !source.substring(with: aliasRange).hasPrefix(":") {
                visibleRange = aliasRange
            } else {
                visibleRange = targetRange
            }
            guard visibleRange.length > 0 else { continue }

            let target = link.target + (link.fragment.map { "#\($0)" } ?? "")
            let kind = link.vectorKind ?? .neutral
            let color = vectorColor(for: kind)
            let relationLabel = vectorLabel(for: kind)
            let help = "\(relationLabel) \(source.substring(with: visibleRange))"
            addLink(
                target: target,
                visibleRange: visibleRange,
                color: color,
                help: help,
                storage: storage
            )

            let shouldReveal = MarkdownSyntaxProjection.shouldReveal(
                enclosingRange: fullRange,
                selections: styledSelectionRanges,
                isEditable: isEditable
            )
            guard !shouldReveal else { continue }

            let iconRange = NSRange(location: fullRange.location, length: 1)
            if let attachment = vectorAttachment(for: kind) {
                storage.addAttribute(.attachment, value: attachment, range: iconRange)
                addLink(
                    target: target,
                    visibleRange: iconRange,
                    color: color,
                    help: help,
                    storage: storage
                )
            }
            let hiddenPrefix = NSRange(
                location: NSMaxRange(iconRange),
                length: max(0, visibleRange.location - NSMaxRange(iconRange))
            )
            hide(hiddenPrefix, in: storage)
            hide(
                NSRange(
                    location: NSMaxRange(visibleRange),
                    length: max(0, NSMaxRange(fullRange) - NSMaxRange(visibleRange))
                ),
                in: storage
            )
        }
    }

    private func vectorAttachment(for kind: VectorLinkKind) -> NSTextAttachment? {
        let symbol: String
        switch kind {
        case .neutral: symbol = "link"
        case .supportsTarget: symbol = "arrow.right.circle"
        case .supportedByTarget: symbol = "arrow.left.circle"
        case .incompatible: symbol = "xmark.circle"
        }
        guard let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: vectorLabel(for: kind)
        )?.withSymbolConfiguration(.init(pointSize: scaled(16), weight: .medium)) else { return nil }
        image.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: -scaled(2),
            width: scaled(16),
            height: scaled(16)
        )
        return attachment
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * CGFloat(textScale)
    }

    private func readingFont(
        size: CGFloat,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        ScholiumTypography.readingFont(
            size: scaled(size),
            bold: bold,
            italic: italic
        )
    }

    private func monospaceFont(
        size: CGFloat,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        ScholiumTypography.monospaceFont(
            size: scaled(size),
            bold: bold,
            italic: italic
        )
    }

    private func vectorColor(for kind: VectorLinkKind) -> NSColor {
        switch kind {
        case .neutral: .linkColor
        case .supportsTarget, .supportedByTarget: .systemTeal
        case .incompatible: .systemPurple
        }
    }

    private func vectorLabel(for kind: VectorLinkKind) -> String {
        switch kind {
        case .neutral: "Related note"
        case .supportsTarget: "Supports"
        case .supportedByTarget: "Supported by"
        case .incompatible: "Incompatible with"
        }
    }

    private func addLink(
        target: String,
        visibleRange: NSRange,
        color: NSColor = .linkColor,
        help: String? = nil,
        storage: NSTextStorage
    ) {
        let decodedTarget = target.removingPercentEncoding ?? target
        let encoded = decodedTarget.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? decodedTarget
        if let url = URL(string: "scholium-note:\(encoded)") {
            var attributes: [NSAttributedString.Key: Any] = [
                .link: url,
                .foregroundColor: color,
            ]
            if let help { attributes[.toolTip] = help }
            storage.addAttributes(attributes, range: visibleRange)
        }
    }

    private func hide(
        _ range: NSRange,
        in storage: NSTextStorage,
        collapseLines: Bool = false,
        revealWithin enclosingRange: NSRange? = nil
    ) {
        guard range.location != NSNotFound,
              range.length > 0,
              range.location >= 0,
              NSMaxRange(range) <= storage.length else { return }
        if let enclosingRange,
           MarkdownSyntaxProjection.shouldReveal(
            enclosingRange: enclosingRange,
            selections: styledSelectionRanges,
            isEditable: isEditable
           ) {
            return
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 0.1),
            .foregroundColor: NSColor.clear,
            .kern: -0.1,
        ]
        if collapseLines {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = 0.1
            paragraph.maximumLineHeight = 0.1
            paragraph.paragraphSpacing = 0
            paragraph.paragraphSpacingBefore = 0
            attributes[.paragraphStyle] = paragraph
        }
        storage.addAttributes(attributes, range: range)
    }

    private func forEachMatch(
        _ pattern: String,
        in source: NSString,
        range: NSRange,
        body: (NSTextCheckingResult) -> Void
    ) {
        guard range.length > 0,
              let expression = try? NSRegularExpression(pattern: pattern) else { return }
        for match in expression.matches(in: source as String, range: range) {
            body(match)
        }
    }
}
