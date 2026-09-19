import AppKit
import SwiftUI

/// Chat's researcher-authored message fill derives from the shared adaptive Accent.
enum ScholiumChatAppearance {
    /// Both researcher-authored and Agent-authored messages use one native
    /// reading treatment. The bubble and alignment still communicate
    /// authorship, but never change the message's type or ink.
    static var messageFont: Font { .body }
    static var messageNSFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }
    static var messageForeground: Color { ScholiumColorRole.primaryText.color }
    static var messageNSForeground: NSColor { ScholiumColorRole.primaryText.nsColor }
    static let messageLineHeight: CGFloat = 1.55
    static var messageLoadingHeight: CGFloat { ceil(messageNSFont.pointSize * messageLineHeight) }
    static let messageSpacing: CGFloat = 20
    static let contentSpacing: CGFloat = 8
    static let userLeadingInset: CGFloat = 16
    static let bubbleHorizontalInset: CGFloat = 12
    static let bubbleVerticalInset: CGFloat = 10
    static let bubbleRadius: CGFloat = 16

    /// A complete chat rhythm overrides document-reading padding as well as
    /// margins. Em units keep structure proportional to the native body font.
    static var messageBodyCSS: String {
        """
        .scholium-document {
            padding: 0; margin: 0; max-width: none; display: flow-root;
            font: \(messageNSFont.pointSize)px/\(messageLineHeight) -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            color: var(--scholium-color-primary-text); text-align: start;
            text-wrap-style: auto;
            overflow-wrap: anywhere;
        }
        .scholium-document p { margin: 0 0 .75em; padding: 0; }
        .scholium-document :is(h1, h2, h3, h4, h5, h6) {
            font-family: inherit; font-style: normal; font-variant-caps: normal;
            font-weight: 600; line-height: 1.35; text-align: start;
            margin: 1.15em 0 .5em; padding: 0; text-wrap: wrap;
        }
        .scholium-document h1 { font-size: 1.3em; }
        .scholium-document h2 { font-size: 1.15em; }
        .scholium-document :is(h3, h4, h5, h6) { font-size: 1em; }
        .scholium-document :is(ul, ol) { margin: 0 0 .75em; padding-inline-start: 1.5em; }
        .scholium-document li { margin-block: .3em; }
        .scholium-document li > p { margin-block: .35em; padding: 0; }
        .scholium-document li > :is(ul, ol) { margin-block: .35em 0; }
        .scholium-document li > :first-child { margin-top: 0; }
        .scholium-document li > :last-child { margin-bottom: 0; }
        .scholium-document blockquote,
        .scholium-document blockquote blockquote:not(.scholium-callout-quotation) {
            margin: .85em 0; padding-block: 0;
            padding-inline: .85em 0;
            border-inline-start: 2px solid var(--scholium-color-separator);
            color: inherit;
        }
        .scholium-document blockquote > :last-child { margin-bottom: 0; }
        .scholium-document pre { font-family: 'SFMono-Regular', ui-monospace, monospace; font-size: 1em; line-height: 1.5; }
        .scholium-document pre code { font: inherit; color: inherit; }
        .scholium-document hr { margin-block: 1.1em; }
        .scholium-document > :first-child { margin-top: 0; padding-top: 0; }
        .scholium-document > :last-child { margin-bottom: 0; padding-bottom: 0; }
        """
    }
    static var inlineCodeBackground: NSColor { .quaternaryLabelColor }
    static func inlineCodeCSS(dark: Bool, increasedContrast: Bool) -> String {
        let name: NSAppearance.Name =
            increasedContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        var background = "transparent"
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            if let color = inlineCodeBackground.usingColorSpace(.sRGB) {
                background = String(
                    format: "rgba(%.0f, %.0f, %.0f, %.4f)",
                    color.redComponent * 255, color.greenComponent * 255,
                    color.blueComponent * 255, color.alphaComponent)
            }
        }
        return """
            .scholium-document :not(pre) > code {
                font-family: 'SFMono-Regular', ui-monospace, monospace;
                font-size: 1em; line-height: inherit; color: inherit;
                background: \(background); border: 0; border-radius: 0; padding: 0;
            }
            """
    }

    static var userMessageBackground: Color { ScholiumColorRole.accent.color.opacity(0.14) }
}
