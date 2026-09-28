import AppKit

enum ScholiumPreviewStyles {
    /// Mermaid's theme parser requires concrete opaque colors. Resolve native
    /// roles against the preview canvas rather than inheriting workspace Paper.
    @MainActor static func diagramColorCSS(dark: Bool, increasedContrast: Bool) -> String {
        let appearance: NSAppearance.Name =
            increasedContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        var declarations = ""
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            guard let background = NSColor.textBackgroundColor.usingColorSpace(.sRGB) else { return }
            for (variable, native) in [
                ("document-background", NSColor.textBackgroundColor),
                ("surface-background", .textBackgroundColor),
                ("raised-surface-background", .textBackgroundColor),
                ("primary-text", .labelColor), ("secondary-text", .secondaryLabelColor),
                // Diagram connectors carry relationships, so they need stronger
                // ink than a decorative native window separator.
                ("separator", increasedContrast ? .labelColor : .secondaryLabelColor),
                ("accent", .controlAccentColor),
            ] {
                guard let color = native.usingColorSpace(.sRGB) else { continue }
                let alpha = color.alphaComponent
                let rgb = zip(
                    [color.redComponent, color.greenComponent, color.blueComponent],
                    [background.redComponent, background.greenComponent, background.blueComponent]
                )
                .map { Int((($0 * alpha + $1 * (1 - alpha)) * 255).rounded()) }
                declarations += String(format: "--scholium-color-%@: #%02x%02x%02x;", variable, rgb[0], rgb[1], rgb[2])
            }
        }
        return ":root { \(declarations) }"
    }

    /// Preview chrome and prose use system roles, independently of Document Appearance.
    @MainActor static var nativeCSS: String {
        func colors(_ name: NSAppearance.Name) -> String {
            var declarations = ""
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                for (variable, color) in [
                    ("--scholium-color-primary-text", NSColor.labelColor),
                    ("--scholium-color-secondary-text", .secondaryLabelColor),
                    ("--scholium-color-document-background", .windowBackgroundColor),
                    ("--scholium-color-surface-background", .controlBackgroundColor),
                    ("--scholium-color-raised-surface-background", .controlBackgroundColor),
                    ("--scholium-color-separator", .separatorColor),
                    ("--scholium-color-accent", .controlAccentColor),
                    ("--scholium-document-accent", .controlAccentColor),
                    ("--scholium-content-focus-ring", .keyboardFocusIndicatorColor),
                ] {
                    guard let color = color.usingColorSpace(.sRGB) else { continue }
                    declarations +=
                        "\(variable): rgba(\(color.redComponent * 255), \(color.greenComponent * 255), "
                        + "\(color.blueComponent * 255), \(color.alphaComponent)) !important;"
                }
            }
            return declarations
        }
        return """
            :root { color-scheme: light dark; font-size: \(NSFont.systemFontSize)px !important; \(colors(.aqua))
              --scholium-document-source-font-family: ui-monospace, monospace !important;
              --scholium-document-source-font-size: .9rem !important; }
            @media (prefers-color-scheme: dark) { :root { \(colors(.darkAqua)) } }
            @media (prefers-contrast: more) { :root { \(colors(.accessibilityHighContrastAqua)) } }
            @media (prefers-color-scheme: dark) and (prefers-contrast: more) { :root { \(colors(.accessibilityHighContrastDarkAqua)) } }
            html, body { margin: 0 !important; min-height: 0 !important; height: auto !important; background: transparent !important; }
            body { padding: 14px 16px !important; box-sizing: border-box; color: var(--scholium-color-primary-text); overflow-wrap: anywhere; }
            body, .scholium-preview-body.scholium-document { font: 1rem/1.45 system-ui !important; text-align: start !important; }
            .scholium-preview-body.scholium-document { padding: 0 !important; margin: 0 !important; min-height: 0 !important; max-width: none !important; }
            .scholium-preview-body :is(p, li, blockquote, h1, h2, h3, h4, h5, h6, strong, em) { font-family: system-ui !important; }
            .scholium-preview-body.scholium-document :lang(zh-Hans) { font-family: system-ui !important; }
            .scholium-preview-body.scholium-document :is(code, pre, code *, pre *) {
              font-family: ui-monospace, monospace !important;
              font-size: .9rem !important;
            }
            .scholium-preview-body p { text-indent: 0 !important; }
            .scholium-preview-body.scholium-document :is(h1, h2, h3, h4, h5, h6) {
              font: 600 1rem/1.3 system-ui !important;
              text-align: start !important;
              padding-block: .35em .25em !important;
            }
            .scholium-preview-body.scholium-document h1 { font-size: 1.25rem !important; }
            .scholium-preview-body.scholium-document h2 { font-size: 1.15rem !important; }
            .scholium-preview-body.scholium-document h3 { font-size: 1.08rem !important; }
            .scholium-preview-body.scholium-document h4 { font-size: 1.03rem !important; }
            .scholium-preview-body.scholium-document h6 { font-size: .95rem !important; }
            """
    }

    static let css: String = {
        guard let url = Bundle.module.url(forResource: "previews", withExtension: "css"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()
}
