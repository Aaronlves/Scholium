import AppKit

enum ScholiumPreviewStyles {
    /// Preview chrome and prose use system roles, independently of Document Appearance.
    @MainActor static var nativeCSS: String {
        func colors(_ name: NSAppearance.Name) -> String {
            var declarations = ""
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                for (variable, role) in [
                    ("primary-text", ScholiumNativeColorRole.label),
                    ("secondary-text", .secondaryLabel),
                    ("document-background", .windowBackground),
                    ("surface-background", .controlBackground),
                    ("raised-surface-background", .controlBackground),
                ] {
                    guard let color = role.nsColor.usingColorSpace(.sRGB) else { continue }
                    declarations +=
                        "--scholium-color-\(variable): rgba(\(color.redComponent * 255), \(color.greenComponent * 255), "
                        + "\(color.blueComponent * 255), \(color.alphaComponent)) !important;"
                }
            }
            return declarations
        }
        return """
            :root { color-scheme: light dark; font-size: \(NSFont.systemFontSize)px !important; \(colors(.aqua)) }
            @media (prefers-color-scheme: dark) { :root { \(colors(.darkAqua)) } }
            @media (prefers-contrast: more) { :root { \(colors(.accessibilityHighContrastAqua)) } }
            @media (prefers-color-scheme: dark) and (prefers-contrast: more) { :root { \(colors(.accessibilityHighContrastDarkAqua)) } }
            html, body { margin: 0 !important; min-height: 0 !important; height: auto !important; background: transparent !important; }
            body { padding: 14px 16px !important; box-sizing: border-box; color: var(--scholium-color-primary-text); overflow-wrap: anywhere; }
            body, .scholium-preview-body.scholium-document { font: 1rem/1.45 system-ui !important; text-align: start !important; }
            .scholium-preview-body.scholium-document { padding: 0 !important; margin: 0 !important; min-height: 0 !important; max-width: none !important; }
            .scholium-preview-body :is(p, li, blockquote, h1, h2, h3, h4, h5, h6, strong, em) { font-family: system-ui !important; }
            .scholium-preview-body p { text-indent: 0 !important; }
            """
    }

    static let css: String = {
        guard let url = Bundle.module.url(forResource: "previews", withExtension: "css"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()
}
