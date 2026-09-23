import AppKit

/// Host-derived typography. It has no persistence or document-content authority.
@MainActor
public struct NativeDocumentAppearance {
    public let identifier: Int
    public let theme: EditorTheme
    public let readingWidth: CGFloat
    public let blockStyle: (Block, NSAttributedString) -> NSAttributedString
    public let calloutStyles: [String: CalloutStyle]
    public let calloutTitleFonts: [String: NSFont]
    public let calloutVerticalPadding: [String: CGFloat]
    public let calloutHeaderGaps: [String: CGFloat]
    public let codeBlockCornerRadius: CGFloat
    public let calloutCornerRadius: CGFloat

    public init(
        identifier: Int, theme: EditorTheme, readingWidth: CGFloat,
        calloutStyles: [String: CalloutStyle],
        calloutTitleFonts: [String: NSFont], calloutVerticalPadding: [String: CGFloat],
        calloutHeaderGaps: [String: CGFloat],
        codeBlockCornerRadius: CGFloat, calloutCornerRadius: CGFloat,
        blockStyle: @escaping (Block, NSAttributedString) -> NSAttributedString
    ) {
        self.identifier = identifier
        self.theme = theme
        self.readingWidth = readingWidth
        self.calloutStyles = calloutStyles
        self.calloutTitleFonts = calloutTitleFonts
        self.calloutVerticalPadding = calloutVerticalPadding
        self.calloutHeaderGaps = calloutHeaderGaps
        self.codeBlockCornerRadius = codeBlockCornerRadius
        self.calloutCornerRadius = calloutCornerRadius
        self.blockStyle = blockStyle
    }
}

extension EditorTextView {
    public func applyNativeAppearance(_ appearance: NativeDocumentAppearance) {
        guard appearance.identifier != appliedNativeAppearance?.identifier else {
            pendingNativeAppearance = nil
            return
        }
        pendingNativeAppearance = appearance
        applyPendingNativeAppearance()
    }

    public func applyPendingNativeAppearance() {
        guard !hasMarkedText(), !isTrackingPointerSelection, !isUpdating,
            let appearance = pendingNativeAppearance
        else { return }
        pendingNativeAppearance = nil
        appliedNativeAppearance = appearance
        blockAppearance = appearance.blockStyle
        calloutStyleOverrides = appearance.calloutStyles
        maxContentWidthPoints = appearance.readingWidth
        // The host already supplies its per-window scale. Avoid a second zoom.
        if zoomFactor != 1 { setZoom(1) }
        applyTheme(appearance.theme)
        updateContentInset()
        updateScrollOverscroll()
    }

    func applyingHostAppearance(to styled: NSAttributedString, block: Block) -> NSAttributedString {
        guard let blockAppearance else { return styled }
        let candidate = blockAppearance(block, styled)
        // Appearance cannot modify, normalize or regenerate source text.
        guard (candidate.string as NSString).isEqual(to: styled.string) else { return styled }
        return candidate
    }
}
