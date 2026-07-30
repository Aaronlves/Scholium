import Foundation
import ScholiumContracts

enum DocumentAppearanceStyles {
    static func css(for profile: DocumentAppearanceProfile?) -> String {
        guard let profile else { return "" }
        let body = profile.settings.body
        let headings = profile.settings.headings
        let title = headings.title
        let level1 = headings.level1
        let level2 = headings.level2
        let fontStyle = headings.style == .italic ? "italic" : "normal"
        let fontVariantCaps = headings.style == .smallCaps ? "small-caps" : "normal"
        let bodyFont = cssFontFamily(body.fontFamily)
        let headingFont = headings.fontFamily == .body
            ? bodyFont
            : cssFontFamily(headings.fontFamily)

        var rules = """
        :root {
          --scholium-document-line-width: \(number(profile.settings.lineWidthCharacterUnits))ch;
          --scholium-document-half-line-width: \(number(profile.settings.lineWidthCharacterUnits / 2))ch;
          --scholium-document-prose-font-size: \(number(body.fontSizePoints))pt;
          --scholium-rhythm-prose-line-height: \(number(body.lineHeight));
          --scholium-rhythm-paragraph-gap: \(number(body.paragraphSpacingEm))em;
          --scholium-document-h1-size: \(number(title.scale * 100))%;
          --scholium-document-h2-size: \(number(level1.scale * 100))%;
          --scholium-document-h3-size: \(number(level2.scale * 100))%;
          --scholium-rhythm-heading-line-height: \(number(headings.lineHeight));
          --scholium-appearance-title-before: \(number(title.spaceBeforeEm))em;
          --scholium-appearance-title-after: \(number(title.spaceAfterEm))em;
          --scholium-appearance-h2-before: \(number(level1.spaceBeforeEm))em;
          --scholium-appearance-h2-after: \(number(level1.spaceAfterEm))em;
          --scholium-appearance-h3-before: \(number(level2.spaceBeforeEm))em;
          --scholium-appearance-h3-after: \(number(level2.spaceAfterEm))em;
        }
        .scholium-document,
        .cm-editor.scholium-live-mode .cm-content {
          font-family: \(bodyFont);
          line-height: var(--scholium-rhythm-prose-line-height);
          letter-spacing: \(number(body.letterSpacingEm))em;
          word-spacing: \(number(body.wordSpacingEm))em;
          text-align: \(body.alignment.rawValue);
          hyphens: \(body.hyphenation == .automatic ? "auto" : "none");
          font-kerning: \(body.kerning ? "normal" : "none");
          font-variant-ligatures: \(body.ligatures ? "common-ligatures" : "none");
          font-size: calc(var(--scholium-document-prose-font-size) * var(--scholium-document-text-scale-factor));
        }
        .scholium-document p {
          margin-block: 0 var(--scholium-rhythm-paragraph-gap);
          text-indent: \(number(body.firstLineIndentEm))em;
        }
        .cm-editor.scholium-live-mode .cm-live-paragraph-start {
          text-indent: \(number(body.firstLineIndentEm))em;
        }
        .cm-editor.scholium-live-mode .cm-live-paragraph-end {
          padding-block-end: var(--scholium-rhythm-paragraph-gap);
        }
        .scholium-document h1,
        .scholium-document h2,
        .scholium-document h3,
        .scholium-document h4,
        .scholium-document h5,
        .scholium-document h6,
        .scholium-live-mode .cm-live-heading {
          font-family: \(headingFont);
          font-style: \(fontStyle);
          font-variant-caps: \(fontVariantCaps);
          font-weight: \(headings.weight);
          line-height: var(--scholium-rhythm-heading-line-height);
          letter-spacing: \(number(headings.letterSpacingEm))em;
        }
        .scholium-document > h1:first-child {
          margin-block: var(--scholium-appearance-title-before) var(--scholium-appearance-title-after);
          padding-block: 0;
          text-align: \(title.alignment.rawValue);
        }
        .scholium-live-mode .cm-live-document-title,
        .scholium-live-mode .cm-live-h1 {
          margin-block: 0;
          padding-block: var(--scholium-appearance-title-before) var(--scholium-appearance-title-after);
          text-align: \(title.alignment.rawValue);
        }
        .scholium-document h2 {
          margin-block: var(--scholium-appearance-h2-before) var(--scholium-appearance-h2-after);
          text-align: \(level1.alignment.rawValue);
        }
        .scholium-live-mode .cm-live-h2 {
          padding-block: var(--scholium-appearance-h2-before) var(--scholium-appearance-h2-after);
          text-align: \(level1.alignment.rawValue);
        }
        .scholium-document h3,
        .scholium-document h4,
        .scholium-document h5,
        .scholium-document h6 {
          margin-block: var(--scholium-appearance-h3-before) var(--scholium-appearance-h3-after);
          text-align: \(level2.alignment.rawValue);
        }
        .scholium-live-mode .cm-live-h3,
        .scholium-live-mode .cm-live-h4,
        .scholium-live-mode .cm-live-h5,
        .scholium-live-mode .cm-live-h6 {
          padding-block: var(--scholium-appearance-h3-before) var(--scholium-appearance-h3-after);
          text-align: \(level2.alignment.rawValue);
        }
        """

        for callout in profile.settings.callouts {
            rules += "\n" + calloutCSS(callout)
        }
        return rules
    }

    private static func calloutCSS(_ callout: DocumentCalloutAppearance) -> String {
        let selector = selector(for: callout.role)
        var css = """
        \(selector) {
          --scholium-callout-block-gap: \(number(callout.blockGapEm))em;
          margin-block: var(--scholium-callout-block-gap);
          font-size: \(number(callout.fontScale))em;
        }
        \(selector) .scholium-callout-body {
          line-height: \(callout.lineHeight.map(number) ?? "inherit");
        }
        \(selector) .scholium-callout-body p {
          margin-block: 0;
        }
        \(selector) .scholium-callout-body p + p {
          margin-block-start: \(number(callout.paragraphSpacingEm))em;
        }
        \(selector) .scholium-callout-title {
          font-family: inherit;
          font-weight: \(callout.titleWeight);
        }
        """

        switch callout.role {
        case .orientation:
            css += """

            \(selector) {
              margin-inline-start: \(number(callout.startInsetEm ?? callout.inlineInsetEm))em;
              margin-inline-end: \(number(callout.endInsetEm ?? callout.inlineInsetEm))em;
            }
            \(selector) .scholium-callout-body { margin-block-start: 0; }
            """
        case .connections:
            css += """

            \(selector) {
              --scholium-callout-connect-content-indent: \(number(callout.contentIndentEm ?? 1.1))em;
              margin-inline: \(number(callout.inlineInsetEm))em;
            }
            """
        case .statement:
            css += "\n\(selector) .scholium-callout-heading { margin-inline-end: \(number(callout.titleGapEm ?? 0))em; }"
        case .illustration:
            css += """

            \(selector) {
              grid-template-columns: \(number(callout.titleColumnEm ?? 6.5))em minmax(0, 1fr);
              column-gap: \(number(callout.columnGapEm ?? 1))em;
              margin-inline: \(number(callout.inlineInsetEm))em;
            }
            """
        case .caution, .source:
            css += """

            \(selector) {
              margin-inline: \(number(callout.inlineInsetEm))em;
              padding-block: \(number(callout.paddingBlockEm ?? 0.9))em;
              padding-inline: \(number(callout.paddingInlineEm ?? 1))em;
            }
            """
        case .folded:
            css += """

            \(selector) { margin-inline: \(number(callout.inlineInsetEm))em; }
            details.scholium-callout > .scholium-callout-body { margin-inline-start: \(number(callout.contentIndentEm ?? 0))em; }
            """
        case .quotation:
            css += """

            \(selector) { margin-inline: \(number(callout.inlineInsetEm))em; }
            \(selector) .scholium-callout-quotation { font-size: \(number(callout.quotationScale ?? 1))em; }
            \(selector) .scholium-callout-title { font-size: \(number(callout.attributionScale ?? 0.85))em; }
            """
        }
        return css
    }

    private static func selector(for role: DocumentCalloutAppearanceRole) -> String {
        switch role {
        case .orientation: ".scholium-callout-orient"
        case .connections: ".scholium-callout-connect"
        case .statement: ".scholium-callout-state"
        case .illustration: ".scholium-callout-illustrate"
        case .caution: ".scholium-callout-flag"
        case .folded: ".scholium-callout-neutral"
        case .quotation: ".scholium-callout-quote"
        case .source: ".scholium-callout-cite"
        }
    }

    private static func cssFontFamily(_ family: DocumentAppearanceFontFamily) -> String {
        switch family {
        case .alegreya: "Alegreya, \"Iowan Old Style\", Palatino, Georgia, serif"
        case .iowan: "\"Iowan Old Style\", Palatino, Georgia, serif"
        case .palatino: "Palatino, \"Palatino Linotype\", Georgia, serif"
        case .georgia: "Georgia, \"Times New Roman\", serif"
        case .times: "\"Times New Roman\", Times, serif"
        case .systemSerif: "ui-serif, \"New York\", Georgia, serif"
        }
    }

    private static func cssFontFamily(_ family: DocumentHeadingFontFamily) -> String {
        switch family {
        case .body: "inherit"
        case .alegreya: cssFontFamily(DocumentAppearanceFontFamily.alegreya)
        case .systemSerif: cssFontFamily(DocumentAppearanceFontFamily.systemSerif)
        case .systemSans: "ui-sans-serif, system-ui, -apple-system, sans-serif"
        }
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
