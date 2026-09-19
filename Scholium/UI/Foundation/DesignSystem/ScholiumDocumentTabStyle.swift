import AppKit

/// Content-tab geometry and semantic system colors. No window chrome is copied.
@MainActor
enum ScholiumDocumentTabStyle {
    static let height: CGFloat = 28
    static let inset: CGFloat = ScholiumGrid.Spacing.inlineControlGap
    static let borderInset: CGFloat = 1
    static let borderWidth: CGFloat = 0.5
    static let closeInset: CGFloat = 6
    static let closeSize: CGFloat = 16
    static let labelInset: CGFloat = 24
    static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    static var track: NSColor { ScholiumColorRole.surfaceBackground.nsColor }
    static var foreground: NSColor { .labelColor }
    static var selectedFill: NSColor { ScholiumColorRole.documentBackground.nsColor }
    static var border: NSColor {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .labelColor : .separatorColor
    }
}
