import AppKit
import Foundation
import ScholiumContracts

/// Contract names used by the CodeMirror and sanitized Read stylesheets.
/// Custom properties transport resolved semantic roles into WebKit; they are
/// not a second set of configurable color Variables.
enum ScholiumWebDesignTokens {
    /// Document-markup appearance aliases are shared by Review and Edit. The
    /// document accent preserves the system Accent hue while mixing it toward
    /// document ink; controls, focus, selection, and transient arrival states
    /// continue to use the raw system Accent.
    static let documentMarkupCSSDeclarations = """
        --scholium-document-accent: color-mix(in srgb, var(--scholium-color-accent) 66%, var(--scholium-color-primary-text));
        --scholium-syntax-active-ink: var(--scholium-document-accent);
        --scholium-mark-highlight-background: color-mix(in srgb, var(--scholium-color-attention) 20%, transparent);
        --scholium-mark-highlight-edge: color-mix(in srgb, var(--scholium-color-attention) 52%, transparent);
        """
    static let resolvedColorRoleCSSVariableNames = Set(
        ScholiumColorRole.allCases.map(\.cssVariableName)
    )
    static let resolvedElevationRoleCSSVariableNames = Set(
        ScholiumElevationRole.allCases.map(\.cssVariableName)
    )
    static let resolvedCornerRoleCSSVariableNames = Set(
        ScholiumCornerRole.allCases.compactMap(\.cssVariableName)
    )

    static let rhythmCSSDeclarations: String = {
        let defaults = DocumentAppearanceSettings.defaultSettings
        let body = defaults.body
        let headings = defaults.headings
        let number: (Double) -> String = {
            String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), $0)
        }
        let headingLevelDeclarations = headings.levels.enumerated().map { index, level in
            let levelNumber = index + 1
            return """
                --scholium-document-h\(levelNumber)-size: \(number(level.scale * 100))%;
                --scholium-appearance-h\(levelNumber)-before: \(number(level.spaceBeforeEm))em;
                --scholium-appearance-h\(levelNumber)-after: \(number(level.spaceAfterEm))em;
                --scholium-appearance-h\(levelNumber)-align: \(level.alignment.rawValue);
                """
        }.joined(separator: "\n            ")
        return """
            --scholium-document-line-width: \(number(defaults.lineWidthCharacterUnits))ch;
            --scholium-document-half-line-width: \(number(defaults.lineWidthCharacterUnits / 2))ch;
            --scholium-document-prose-font-size: \(number(body.fontSizePoints))pt;
            --scholium-document-source-font-size: \(number(defaults.source.fontSizePoints))pt;
            --scholium-document-source-font-family: "Courier", ui-monospace, "SFMono-Regular", Menlo, monospace;
            --scholium-document-title-size: 180%;
            --scholium-document-title-line-height: 1.15;
            --scholium-document-title-after: 0.65em;
            \(headingLevelDeclarations)
            --scholium-rhythm-prose-line-height: \(number(body.lineHeight));
            --scholium-rhythm-source-line-height: \(ScholiumDocumentRhythm.sourceLineHeight);
            --scholium-document-text-scale-factor: 1;
            --scholium-rhythm-paragraph-gap: \(number(
                body.paragraphSpacingEm * body.fontSizePoints * (96 / 72)
            ))px;
            --scholium-rhythm-heading-line-height: \(number(headings.lineHeight));
            \(DocumentAppearanceStyles.documentTypographyTransportDeclarations(for: defaults))
            --scholium-rhythm-code-inset: \(ScholiumDocumentRhythm.codeBlockInset)px;
            --scholium-document-technical-surface: color-mix(
              in srgb,
              var(--scholium-color-primary-text) 7%,
              transparent
            );
            --scholium-rhythm-quote-inset: \(ScholiumDocumentRhythm.quoteInlineInset)px;
            --scholium-rhythm-semantic-block-gap: 1em;
            --scholium-rhythm-rule-block-gap: 0.5em;
            --scholium-rhythm-frontmatter-inline-inset: 1.5em;
            --scholium-rhythm-frontmatter-after: 0.75em;
            --scholium-list-marker-track: 1.25em;
            --scholium-list-marker-gap: 0.35em;
            --scholium-list-indent: calc(
              var(--scholium-list-marker-track) + var(--scholium-list-marker-gap)
            );
            --scholium-task-checkbox-size: max(1em, 20px);
            --scholium-rhythm-inline-regular: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).inline)px;
            --scholium-rhythm-inline-source: \(ScholiumDocumentRhythm.contentInsets(for: .source, widthClass: .regular).inline)px;
            --scholium-rhythm-inline-narrow: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).inline)px;
            --scholium-rhythm-trailing-scroll: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).trailingViewportFraction * 100)vh;
            --scholium-document-content-top-inset: \(ScholiumMetrics.Document.contentTopInsetCSSPixels)px;
            --scholium-document-text-scale: 1em;
            """
    }()

    private static let colorResolver = ScholiumColorResolver(variables: .editorialPaper)

    static let rootCSSDeclarations = colorDeclarations(
        isDark: false,
        increasedContrast: false
    )
    static let darkAppearanceCSSDeclarations = colorDeclarations(
        isDark: true,
        increasedContrast: false
    )
    static let increasedContrastCSSDeclarations = colorDeclarations(
        isDark: false,
        increasedContrast: true
    )
    static let darkIncreasedContrastCSSDeclarations = colorDeclarations(
        isDark: true,
        increasedContrast: true
    )
    static let elevationCSSDeclarations = elevationDeclarations(
        increasedContrast: false,
        reduceTransparency: false
    )
    static let reducedTransparencyElevationCSSDeclarations = elevationDeclarations(
        increasedContrast: false,
        reduceTransparency: true
    )
    static let increasedContrastElevationCSSDeclarations = elevationDeclarations(
        increasedContrast: true,
        reduceTransparency: false
    )

    private static func colorDeclarations(
        isDark: Bool,
        increasedContrast: Bool
    ) -> String {
        let palette = colorResolver.resolve(
            isDark: isDark,
            increasedContrast: increasedContrast
        )
        let colors = ScholiumColorRole.allCases.map { role in
            // The initial page gets AppKit's resolved Accent too. The native
            // container refreshes its projection when the system changes.
            let value = String(format: "#%06x", palette[role])
            return "\(role.cssVariableName): \(value);"
        }.joined(separator: "\n")
        let callouts = ["orient", "cite", "connect", "state", "illustrate", "quote", "flag", "neutral"].map { role in
            let value = colorResolver.calloutTitleColor(role, isDark: isDark, increasedContrast: increasedContrast)
            return "--scholium-callout-\(role)-title: \(String(format: "#%06x", value));"
        }.joined(separator: "\n")
        // Transport native text colors into WebKit without adding palette inputs.
        var nativeTextColors: [String] = []
        let appearance = NSAppearance(
            named: increasedContrast
                ? (isDark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                : (isDark ? .darkAqua : .aqua))!
        appearance.performAsCurrentDrawingAppearance {
            for (role, name) in [
                (ScholiumNativeColorRole.secondaryLabel, "--scholium-native-secondary-label"),
                (.inactiveTextSelection, "--scholium-native-inactive-text-selection"),
            ] {
                if let rgb = role.nsColor.usingColorSpace(.sRGB) {
                    nativeTextColors.append(
                        "\(name): rgba(\(rgb.redComponent * 255), \(rgb.greenComponent * 255), \(rgb.blueComponent * 255), \(rgb.alphaComponent));")
                }
            }
        }
        return colors + "\n" + callouts + "\n" + nativeTextColors.joined(separator: "\n")
    }

    private static func elevationDeclarations(
        increasedContrast: Bool,
        reduceTransparency: Bool
    ) -> String {
        ScholiumElevationRole.allCases.map { role in
            let value = role.cssBoxShadow(
                increasedContrast: increasedContrast,
                reduceTransparency: reduceTransparency
            )
            return "\(role.cssVariableName): \(value);"
        }.joined(separator: "\n")
    }

    /// One runtime presentation contract for every WebKit-backed document
    /// surface. Read and CodeMirror both append this Swift-owned block; the
    /// resource stylesheet consumes these variables rather than duplicating
    /// provisional layout and typography values.
    static let documentPresentationCSS = """
        :root {
          color-scheme: light dark;
          \(rootCSSDeclarations)
          \(elevationCSSDeclarations)
          \(ScholiumShape.webCSSDeclarations)
          \(ScholiumContentInteractionSurface.webCSSDeclarations)
          \(documentMarkupCSSDeclarations)
          \(rhythmCSSDeclarations)
        }
        .scholium-document,
        .cm-editor.scholium-live-mode .cm-content {
          box-sizing: border-box;
          min-width: 0;
          inline-size: 100%;
          margin: 0;
          padding-block: var(--scholium-document-content-top-inset) var(--scholium-rhythm-trailing-scroll);
          padding-inline: max(
            var(--scholium-rhythm-inline-regular),
            calc(50% - var(--scholium-document-half-line-width))
          );
          font-family: var(--scholium-document-body-font-family);
          font-size: calc(
            var(--scholium-document-prose-font-size)
            * var(--scholium-document-text-scale-factor)
          );
          color: color-mix(
            in srgb,
            var(--scholium-color-primary-text) 90%,
            var(--scholium-color-document-background)
          );
          line-height: var(--scholium-rhythm-prose-line-height);
          line-break: strict;
          word-break: normal;
          overflow-wrap: break-word;
          hyphens: none;
          text-autospace: normal;
          text-spacing-trim: trim-both;
        }
        /* Read may use the engine's best available paragraph treatment;
           editable Live Preview stays stable while the source is changing. */
        .scholium-document {
          text-wrap-style: pretty;
        }
        .cm-editor.scholium-live-mode .cm-content {
          text-wrap-style: stable;
        }
        /* CSS text spacing is a rendering projection. Technical and exact
           source regions retain their authored character grid and never
           receive synthetic inter-script or punctuation spacing. */
        :is(
          .scholium-document code,
          .scholium-document pre,
          .scholium-document .scholium-frontmatter-source,
          .scholium-document .scholium-math,
          .scholium-document .raw-html,
          .cm-editor.scholium-live-mode .cm-live-table,
          .cm-editor.scholium-live-mode .cm-live-math,
          .cm-editor.scholium-live-mode .cm-live-math-source,
          .cm-editor.scholium-live-mode .cm-live-raw-html,
          .cm-editor.scholium-live-mode .scholium-frontmatter-line,
          .cm-editor.scholium-source-mode .cm-content
        ) {
          hyphens: none;
          text-autospace: no-autospace;
          text-spacing-trim: space-all;
          text-wrap-style: stable;
        }
        .scholium-document :lang(en) {
          line-break: auto;
        }
        .cm-editor .cm-line[lang="en"] {
          line-break: auto;
        }
        .scholium-document :lang(zh-Hans),
        .cm-editor .cm-line[lang="zh-Hans"] {
          line-break: strict;
        }
        .cm-editor.scholium-source-mode .cm-content {
          padding-inline: max(
            var(--scholium-rhythm-inline-source),
            calc(50% - var(--scholium-document-half-line-width))
          );
        }
        :is(.scholium-document, .cm-editor) button:not(:disabled),
        :is(.scholium-document, .cm-editor) select:not(:disabled),
        :is(.scholium-document, .cm-editor) a[href],
        :is(.scholium-document, .cm-editor) [role="button"]:not([aria-disabled="true"]),
        :is(.scholium-document, .cm-editor) [role="menuitem"]:not([aria-disabled="true"]),
        :is(.scholium-document, .cm-editor) [role="option"]:not([aria-disabled="true"]) {
          cursor: pointer;
        }
        .scholium-reader-arrival,
        .cm-editor .cm-content .cm-line.scholium-arrival-target {
          background-color: color-mix(in srgb, var(--scholium-color-accent) 16%, transparent);
          animation: scholium-arrival-fade 1.4s ease-in-out both;
        }
        @keyframes scholium-arrival-fade {
          0%, 100% { background-color: transparent; }
          10%, 50% {
            background-color: color-mix(in srgb, var(--scholium-color-accent) 16%, transparent);
          }
        }
        @media (prefers-reduced-motion: reduce) {
          .scholium-reader-arrival,
          .cm-editor .cm-content .cm-line.scholium-arrival-target {
            animation: none;
          }
        }

        .scholium-document p,
        .cm-editor.scholium-live-mode .cm-live-paragraph {
          box-sizing: border-box;
        }
        :is(
          .scholium-document .scholium-frontmatter-source,
          .cm-editor.scholium-live-mode .cm-content > .cm-line.scholium-frontmatter-line
        ) {
          font-family: var(--scholium-document-source-font-family);
          font-size: calc(
            var(--scholium-document-source-font-size)
            * var(--scholium-document-text-scale-factor)
          );
          line-height: 1.7;
          text-indent: 0;
          background: transparent;
          border: 0;
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }
        .scholium-document .scholium-frontmatter-source {
          display: block;
          margin: 0;
          padding-inline: var(--scholium-rhythm-frontmatter-inline-inset, 1.5em);
        }
        .scholium-document .scholium-frontmatter-source {
          margin-block-end: var(--scholium-rhythm-frontmatter-after, 0.75em);
        }
        .scholium-document .scholium-frontmatter-source.scholium-frontmatter-followed-by-blank-line {
          margin-block-end: calc(
            var(--scholium-document-prose-font-size)
            * var(--scholium-rhythm-prose-line-height)
            * var(--scholium-document-text-scale-factor)
          );
        }
        .scholium-document .scholium-frontmatter-line {
          display: block;
          min-block-size: 1lh;
        }
        .scholium-document .scholium-frontmatter-delimiter-line {
          display: block;
          min-block-size: 1lh;
          opacity: 0;
        }
        .cm-editor .scholium-frontmatter-line * { color: inherit; }
        .cm-editor.scholium-live-mode .cm-content > .cm-line.scholium-frontmatter-delimiter-line {
          /* The authored YAML envelope already owns these source rows. Keep
             their space stable in Live mode; the fence is presentation-only
             and disappears through opacity rather than layout collapse. */
          block-size: auto;
          min-block-size: 1.7em;
          line-height: 1.7;
          font-size: calc(
            var(--scholium-document-source-font-size)
            * var(--scholium-document-text-scale-factor)
          );
          overflow: visible;
          opacity: 0;
        }
        .cm-editor.scholium-live-mode .cm-content > .cm-line.scholium-frontmatter-delimiter-line-active {
          opacity: 1;
        }
        :is(
          .scholium-document .scholium-frontmatter-source,
          #editor .cm-editor.scholium-live-mode .cm-content
        ) .cm-live-yaml-delimiter,
        :is(
          .scholium-document .scholium-frontmatter-source,
          #editor .cm-editor.scholium-live-mode .cm-content
        ) .cm-live-yaml-comment {
          color: var(--scholium-color-secondary-text);
        }
        :is(
          .scholium-document .scholium-frontmatter-source,
          #editor .cm-editor.scholium-live-mode .cm-content
        ) .cm-live-yaml-key {
          color: var(--scholium-color-primary-text);
        }
        :is(
          .scholium-document .scholium-frontmatter-source,
          #editor .cm-editor.scholium-live-mode .cm-content
        ) :is(.cm-live-yaml-value, .cm-live-yaml-scalar, .cm-live-yaml-collection) {
          color: var(--scholium-color-secondary-text);
        }
        :is(
          .scholium-document .scholium-frontmatter-source,
          #editor .cm-editor.scholium-live-mode .cm-content
        ) .cm-live-yaml-string {
          color: var(--scholium-document-accent);
        }
        .scholium-note-title {
          box-sizing: border-box;
          margin: 0;
          padding-block: 0 var(--scholium-document-title-after);
          color: var(--scholium-color-primary-text);
          font-family: var(--scholium-document-heading-font-family);
          font-size: var(--scholium-document-title-size);
          font-style: normal;
          font-variant-caps: normal;
          font-weight: 600;
          line-height: var(--scholium-document-title-line-height);
          letter-spacing: 0;
          text-align: start;
          text-indent: 0;
          line-break: strict;
          word-break: normal;
          overflow-wrap: break-word;
          cursor: text;
        }
        .scholium-note-title-input {
          box-sizing: border-box;
          display: block;
          inline-size: 100%;
          min-block-size: 1lh;
          margin: 0;
          padding: 0;
          overflow: hidden;
          resize: none;
          border: 0;
          border-radius: 0;
          outline: 0;
          color: inherit;
          background: transparent;
          font: inherit;
          letter-spacing: inherit;
          text-align: inherit;
          overflow-wrap: inherit;
          cursor: text;
          appearance: none;
        }
        .scholium-note-title-input:disabled {
          color: inherit;
          opacity: 1;
          cursor: progress;
          -webkit-text-fill-color: currentColor;
        }
        .scholium-note-title-input::selection {
          color: inherit;
          background: color-mix(
            in srgb,
            var(--scholium-color-accent) 28%,
            transparent
          ) !important;
        }
        .scholium-note-title-error {
          margin-block-start: 0.35em;
          color: var(--scholium-color-destructive);
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          font-size: 0.48em;
          font-weight: 400;
          line-height: 1.35;
        }

        .scholium-document-empty-state {
          margin: 0;
          padding-block: 0;
          color: var(--scholium-color-secondary-text);
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          font-size: 13px;
          font-style: normal;
          font-weight: 400;
          line-height: 1.4;
        }
        .scholium-document-empty-state p {
          margin: 0;
          padding: 0;
        }
        .scholium-document p {
          margin: 0;
          padding-block: 0 var(--scholium-rhythm-paragraph-gap);
        }
        .scholium-document > ul,
        .scholium-document > ol,
        .scholium-document > blockquote,
        .scholium-document > pre {
          margin-block: var(--scholium-rhythm-semantic-block-gap);
        }
        .scholium-document li > ul,
        .scholium-document li > ol {
          margin-block: 0;
        }
        .scholium-document ul,
        .scholium-document ol {
          box-sizing: border-box;
          margin-inline: 0;
          padding-inline-start: var(--scholium-list-indent);
          list-style-position: outside;
        }
        .scholium-document li {
          padding-inline: 0;
        }
        .scholium-document li::marker {
          color: var(--scholium-color-primary-text);
          font-family: inherit;
          font-weight: 400;
        }
        .scholium-document li.scholium-task-list-item {
          position: relative;
          list-style: none;
        }
        .scholium-document .scholium-task-checkbox {
          position: absolute;
          inset-block-start: calc((1lh - var(--scholium-task-checkbox-size)) / 2);
          inset-inline-end: calc(100% + var(--scholium-list-marker-gap));
          box-sizing: border-box;
          inline-size: var(--scholium-task-checkbox-size);
          block-size: var(--scholium-task-checkbox-size);
          margin: 0;
          opacity: 1;
          accent-color: var(--scholium-color-accent);
          font: inherit;
          pointer-events: none;
        }
        .scholium-document > hr {
          margin-block: var(--scholium-rhythm-rule-block-gap);
        }
        .scholium-document > hr,
        .cm-editor.scholium-live-mode .cm-live-rule {
          box-sizing: border-box;
          block-size: 1px;
          min-block-size: 1px;
          border: 0;
          border-block-start: 1px solid var(--scholium-color-separator);
        }
        .scholium-document li > p,
        .cm-editor.scholium-live-mode .cm-live-list {
          box-sizing: border-box;
          padding-inline-start: 0;
          text-align: start;
        }
        .scholium-document li > p {
          padding-block-end: 0;
        }
        .scholium-document blockquote,
        .cm-editor.scholium-live-mode .cm-live-quote {
          box-sizing: border-box;
          margin-inline: 0;
          padding-inline-start: var(--scholium-rhythm-quote-inset);
          border-inline-start: 3px solid var(--scholium-document-accent);
          color: color-mix(in srgb, var(--scholium-color-primary-text) 78%, transparent);
        }
        /* Nested quotations are real children of their parent quotation in
           Review. Edit carries the same nested role on every line while its
           separate rail track paints the ancestor borders. */
        .scholium-document blockquote blockquote:not(.scholium-callout-quotation) {
          border-inline-start: 1px solid var(--scholium-color-separator);
          color: color-mix(in srgb, var(--scholium-color-primary-text) 66%, transparent);
          padding-inline-start: var(--scholium-rhythm-quote-inset);
        }
        .cm-editor.scholium-live-mode .cm-live-quote.cm-live-quote-nested {
          color: color-mix(in srgb, var(--scholium-color-primary-text) 66%, transparent);
        }
        .scholium-document pre,
        .cm-editor.scholium-live-mode .cm-live-codeblock {
          box-sizing: border-box;
          font-family: var(--scholium-document-source-font-family);
          font-size: var(--scholium-document-source-font-size);
          line-height: var(--scholium-rhythm-source-line-height);
          font-style: normal;
          font-variant-caps: normal;
          background: var(--scholium-document-technical-surface);
        }
        /* The block owns the source surface. Its inline code child only carries
           the same Source Text metrics and must not paint a second rectangle
           over the block background. */
        .scholium-document pre code {
          box-sizing: border-box;
          font-family: var(--scholium-document-source-font-family);
          font-size: var(--scholium-document-source-font-size);
          line-height: var(--scholium-rhythm-source-line-height);
          font-style: normal;
          font-variant-caps: normal;
          background: transparent;
        }
        .scholium-document pre.raw-html,
        .cm-editor.scholium-live-mode .cm-live-raw-html {
          box-sizing: border-box;
          color: var(--scholium-color-secondary-text);
          background: color-mix(in srgb, var(--scholium-color-primary-text) 7%, transparent);
          font-family: var(--scholium-document-source-font-family);
          font-size: var(--scholium-document-source-font-size);
          line-height: var(--scholium-rhythm-source-line-height);
          font-style: normal;
          font-variant-caps: normal;
        }
        .cm-editor.scholium-live-mode .cm-live-raw-html {
          padding-inline: var(--scholium-rhythm-code-inset);
        }
        .scholium-document pre {
          max-inline-size: 100%;
          padding: var(--scholium-rhythm-code-inset);
          overflow: auto;
          border-radius: var(--scholium-corner-document-code-block);
        }
        .cm-editor.scholium-live-mode .cm-live-codeblock {
          padding-inline: var(--scholium-rhythm-code-inset);
        }
        .cm-editor.scholium-live-mode .cm-live-codeblock-start {
          padding-block-start: var(--scholium-rhythm-code-inset);
          border-start-start-radius: var(--scholium-corner-document-code-block);
          border-start-end-radius: var(--scholium-corner-document-code-block);
        }
        .cm-editor.scholium-live-mode .cm-live-raw-html-start {
          padding-block-start: var(--scholium-rhythm-code-inset);
          border-start-start-radius: var(--scholium-corner-document-code-block);
          border-start-end-radius: var(--scholium-corner-document-code-block);
        }
        .cm-editor.scholium-live-mode .cm-live-codeblock-end {
          padding-block-end: var(--scholium-rhythm-code-inset);
          border-end-start-radius: var(--scholium-corner-document-code-block);
          border-end-end-radius: var(--scholium-corner-document-code-block);
        }
        .cm-editor.scholium-live-mode .cm-live-raw-html-end {
          padding-block-end: var(--scholium-rhythm-code-inset);
          border-end-start-radius: var(--scholium-corner-document-code-block);
          border-end-end-radius: var(--scholium-corner-document-code-block);
        }
        @media (prefers-reduced-transparency: reduce) {
          .scholium-document pre,
          .scholium-document pre.raw-html,
          .cm-editor.scholium-live-mode :is(
            .cm-live-codeblock,
            .cm-live-math-source,
            .cm-live-raw-html
          ) {
            background: var(--scholium-color-document-background);
          }
        }
        .scholium-callout p,
        .footnote-content p {
          padding-block: 0;
        }
        .scholium-document strong,
        .scholium-live-mode .cm-live-strong {
          font-weight: 700;
        }
        .scholium-document em,
        .scholium-live-mode .cm-live-emphasis {
          font-style: italic;
        }
        \(DocumentAppearanceStyles.semanticTypographyCSS(for: DocumentAppearanceSettings.defaultSettings))
        .scholium-document del,
        .scholium-live-mode .cm-live-strike {
          color: var(--scholium-color-primary-text);
          text-decoration: line-through;
        }
        .scholium-document .scholium-highlight,
        .scholium-live-mode .cm-live-highlight {
          box-decoration-break: clone;
          -webkit-box-decoration-break: clone;
          padding-inline: 0.08em;
          color: inherit;
          background-color: var(--scholium-mark-highlight-background);
          box-shadow: inset 0 -0.16em 0 var(--scholium-mark-highlight-edge);
          border-radius: var(--scholium-corner-document-mark-highlight);
        }
        @media (prefers-contrast: more) {
          .scholium-document .scholium-highlight,
          .scholium-live-mode .cm-live-highlight {
            background-color: color-mix(in srgb, var(--scholium-color-attention) 30%, transparent);
            box-shadow: inset 0 -0.18em 0 var(--scholium-color-attention);
          }
        }
        .scholium-document :not(pre) > code,
        .scholium-table :not(pre) > code,
        .scholium-live-mode .cm-live-code {
          padding: 0.08em 0.25em;
          border-radius: var(--scholium-corner-document-inline-code);
          background: color-mix(in srgb, var(--scholium-color-primary-text) 8%, transparent);
          font-family: var(--scholium-document-source-font-family);
          font-size: var(--scholium-document-source-font-size);
          line-height: inherit;
          font-style: normal;
          font-variant-caps: normal;
          vertical-align: baseline;
        }
        .scholium-document a:not(.wiki-link),
        .scholium-live-mode .cm-live-link {
          color: var(--scholium-document-accent);
          text-decoration: underline;
          text-decoration-color: color-mix(in srgb, var(--scholium-document-accent) 42%, transparent);
          text-underline-offset: 0.15em;
        }
        .scholium-document a:not(.wiki-link):hover,
        .scholium-live-mode .cm-live-link:hover {
          color: var(--scholium-color-accent);
          background: var(--scholium-content-hover-surface);
          border-radius: var(--scholium-corner-document-control);
          text-decoration-color: currentColor;
        }
        .scholium-document a:not(.wiki-link):focus-visible {
          color: var(--scholium-color-accent);
          background: var(--scholium-content-keyboard-focus-surface);
          border-radius: var(--scholium-corner-document-control);
          outline: 2px solid var(--scholium-content-focus-ring);
          outline-offset: 2px;
          text-decoration-color: currentColor;
        }
        .scholium-document a:not(.wiki-link):active,
        .scholium-live-mode .cm-live-link:active {
          background: var(--scholium-content-keyboard-focus-surface);
        }
        .scholium-document .wiki-link,
        .scholium-live-mode .cm-live-wiki-link {
          display: inline-block;
          max-inline-size: 100%;
          vertical-align: baseline;
          color: var(--scholium-document-accent);
          line-height: 1.2;
          text-decoration-line: underline;
          text-decoration-color: color-mix(in srgb, var(--scholium-document-accent) 42%, transparent);
          text-underline-offset: 0.15em;
          border-radius: var(--scholium-corner-document-control);
        }
        .scholium-document .wiki-link:hover,
        .scholium-document .wiki-link:focus-visible,
        .scholium-live-mode .cm-live-wiki-link.scholium-link-preview-armed {
          color: var(--scholium-document-accent);
          background: var(--scholium-content-hover-surface);
          text-decoration-color: currentColor;
        }
        .scholium-document .wiki-link:focus-visible {
          outline: 2px solid var(--scholium-content-focus-ring);
          outline-offset: 2px;
        }
        .scholium-document .wiki-link:active,
        .scholium-live-mode .cm-live-wiki-link.scholium-link-preview-armed:active {
          background: var(--scholium-content-keyboard-focus-surface);
        }
        .scholium-live-mode .cm-live-wiki-link.scholium-link-preview-armed {
          cursor: pointer;
        }
        .scholium-document h1,
        .scholium-document h2,
        .scholium-document h3,
        .scholium-document h4,
        .scholium-document h5,
        .scholium-document h6,
        .scholium-live-mode .cm-live-heading {
          color: var(--scholium-color-primary-text);
          font-family: var(--scholium-document-heading-font-family);
          font-style: var(--scholium-document-heading-font-style);
          font-variant-caps: var(--scholium-document-heading-font-variant-caps);
          font-weight: var(--scholium-document-heading-weight);
          line-height: var(--scholium-rhythm-heading-line-height);
          letter-spacing: normal;
          text-align: start;
          text-decoration-line: none;
          text-decoration: none;
          /* Review headings use the predictable first-fit algorithm while
             body prose may use the document's readable `pretty` wrapping.
             Edit inherits CodeMirror's stable wrapping. Do not balance
             headings: balancing can move a heading to a new line while the
             current line still has available measure. */
          text-wrap-style: auto;
          box-sizing: border-box;
          margin: 0;
          padding-block: 0;
        }
        .scholium-document h1,
        .scholium-live-mode .cm-live-h1 {
          font-size: var(--scholium-document-h1-size);
          font-weight: var(--scholium-document-heading-weight);
          padding-block: var(--scholium-appearance-h1-before) var(--scholium-appearance-h1-after);
          text-align: var(--scholium-appearance-h1-align);
        }
        .scholium-document h2,
        .scholium-live-mode .cm-live-h2 {
          font-size: var(--scholium-document-h2-size);
          padding-block: var(--scholium-appearance-h2-before) var(--scholium-appearance-h2-after);
          text-align: var(--scholium-appearance-h2-align);
        }
        .scholium-document h3,
        .scholium-live-mode .cm-live-h3 {
          font-size: var(--scholium-document-h3-size);
          padding-block: var(--scholium-appearance-h3-before) var(--scholium-appearance-h3-after);
          text-align: var(--scholium-appearance-h3-align);
        }
        .scholium-document h4,
        .scholium-live-mode .cm-live-h4 {
          font-size: var(--scholium-document-h4-size);
          padding-block: var(--scholium-appearance-h4-before) var(--scholium-appearance-h4-after);
          text-align: var(--scholium-appearance-h4-align);
        }
        .scholium-document h5,
        .scholium-live-mode .cm-live-h5 {
          font-size: var(--scholium-document-h5-size);
          padding-block: var(--scholium-appearance-h5-before) var(--scholium-appearance-h5-after);
          text-align: var(--scholium-appearance-h5-align);
        }
        .scholium-document h6,
        .scholium-live-mode .cm-live-h6 {
          font-size: var(--scholium-document-h6-size);
          padding-block: var(--scholium-appearance-h6-before) var(--scholium-appearance-h6-after);
          text-align: var(--scholium-appearance-h6-align);
        }
        .scholium-document h1 a:not(.wiki-link),
        .scholium-document h2 a:not(.wiki-link),
        .scholium-document h3 a:not(.wiki-link),
        .scholium-document h4 a:not(.wiki-link),
        .scholium-document h5 a:not(.wiki-link),
        .scholium-document h6 a:not(.wiki-link),
        .scholium-live-mode .cm-live-heading .cm-live-link {
          text-decoration: underline;
        }
        .scholium-document .scholium-embed {
          display: block;
          box-sizing: border-box;
          margin-block: var(--scholium-rhythm-semantic-block-gap);
          color: var(--scholium-document-accent);
          font-weight: 650;
          padding: 0.75rem 0.9rem;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-document-embedded-note);
          text-decoration: none;
        }
        @media (prefers-color-scheme: dark) {
          :root { \(darkAppearanceCSSDeclarations) }
        }
        @media (prefers-reduced-transparency: reduce) {
          :root { \(reducedTransparencyElevationCSSDeclarations) }
        }
        @media (prefers-contrast: more) {
          :root {
            \(increasedContrastCSSDeclarations)
            \(increasedContrastElevationCSSDeclarations)
            \(ScholiumContentInteractionSurface.increasedContrastWebCSSDeclarations)
          }
        }
        @media (prefers-color-scheme: dark) and (prefers-contrast: more) {
          :root { \(darkIncreasedContrastCSSDeclarations) }
        }
        """
}
