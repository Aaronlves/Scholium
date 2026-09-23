import Foundation
import ScholiumContracts

enum DocumentAppearanceStyles {
    static func css(for profile: DocumentAppearanceProfile?) -> String {
        guard let profile else { return "" }
        return css(for: profile.settings)
    }

    static func css(for settings: DocumentAppearanceSettings) -> String {
        let body = settings.body
        let headings = settings.headings
        let fontStyle = headings.style == .italic ? "italic" : "normal"
        let fontVariantCaps = headings.style == .smallCaps ? "small-caps" : "normal"
        let hyphenation = settings.hyphenation.cssValue
        let bodyFont = cssFontFamily(body.fontFamily)
        let headingFont =
            headings.fontFamily == .body
            ? bodyFont
            : cssFontFamily(headings.fontFamily)
        let headingLevelDeclarations = headings.levels.enumerated().map { index, level in
            let levelNumber = index + 1
            return """
                  --scholium-document-h\(levelNumber)-size: \(number(level.scale * 100))%;
                  --scholium-appearance-h\(levelNumber)-before: \(number(level.spaceBeforeEm))em;
                  --scholium-appearance-h\(levelNumber)-after: \(number(level.spaceAfterEm))em;
                  --scholium-appearance-h\(levelNumber)-align: \(level.alignment.rawValue);
                """
        }.joined(separator: "\n")
        let headingLevelRules = headings.levels.enumerated().map { index, _ in
            let levelNumber = index + 1
            return """
                .scholium-document h\(levelNumber) {
                  font-size: var(--scholium-document-h\(levelNumber)-size);
                  padding-block: var(--scholium-appearance-h\(levelNumber)-before) var(--scholium-appearance-h\(levelNumber)-after);
                  text-align: var(--scholium-appearance-h\(levelNumber)-align);
                }
                """
        }.joined(separator: "\n")

        var rules = """
            :root {
              --scholium-document-body-font-family: \(bodyFont);
              --scholium-document-line-width: \(number(settings.lineWidthCharacterUnits))ch;
              --scholium-document-half-line-width: \(number(settings.lineWidthCharacterUnits / 2))ch;
              --scholium-document-prose-font-size: \(number(body.fontSizePoints))pt;
              --scholium-document-source-font-family: \(quotedCSSString(settings.source.fontFamily)), ui-monospace, monospace;
              --scholium-document-source-font-size: \(number(settings.source.fontSizePoints))pt;
              --scholium-rhythm-prose-line-height: \(number(body.lineHeight));
              --scholium-rhythm-paragraph-gap: \(number(body.paragraphSpacingEm))em;
              \(headingLevelDeclarations)
              --scholium-rhythm-heading-line-height: \(number(headings.lineHeight));
            }
            .scholium-document {
              font-family: \(bodyFont);
              line-height: var(--scholium-rhythm-prose-line-height);
              text-align: \(body.alignment.rawValue);
              font-size: calc(var(--scholium-document-prose-font-size) * var(--scholium-document-text-scale-factor));
              hyphens: \(hyphenation);
            }
            .scholium-document p {
              margin: 0;
              padding-block: 0 var(--scholium-rhythm-paragraph-gap);
              text-indent: \(number(body.firstLineIndentEm))em;
            }
            .scholium-document h1,
            .scholium-document h2,
            .scholium-document h3,
            .scholium-document h4,
            .scholium-document h5,
            .scholium-document h6 {
              font-family: \(headingFont);
              font-style: \(fontStyle);
              font-variant-caps: \(fontVariantCaps);
              font-weight: \(headings.weight);
              line-height: var(--scholium-rhythm-heading-line-height);
            }
            .scholium-document h1,
            .scholium-document h2,
            .scholium-document h3,
            .scholium-document h4,
            .scholium-document h5,
            .scholium-document h6 {
              text-wrap-style: auto;
            }
            \(headingLevelRules)
            """

        for callout in settings.callouts {
            rules += "\n" + calloutCSS(callout)
        }
        rules += "\n" + semanticTypographyCSS(for: settings)
        return rules
    }

    /// Shared WebKit typography remains derived from the same Appearance
    /// owner used by a selected profile, including no-profile and failed-
    /// profile paths for shared Chat and read-only HTML previews.
    static func documentTypographyTransportDeclarations(
        for settings: DocumentAppearanceSettings
    ) -> String {
        let bodyFont = cssFontFamily(settings.body.fontFamily)
        let headings = settings.headings
        let headingFont =
            headings.fontFamily == .body
            ? bodyFont
            : cssFontFamily(headings.fontFamily)
        let fontStyle = headings.style == .italic ? "italic" : "normal"
        let fontVariantCaps = headings.style == .smallCaps ? "small-caps" : "normal"

        return """
            --scholium-document-body-font-family: \(bodyFont);
            --scholium-document-heading-font-family: \(headingFont);
            --scholium-document-heading-font-style: \(fontStyle);
            --scholium-document-heading-font-variant-caps: \(fontVariantCaps);
            --scholium-document-heading-weight: \(headings.weight);
            """
    }

    /// Keeps semantic font choices script-aware while exposing only general
    /// role controls in Settings. Latin glyphs stay with the role's selected
    /// family so its real bold/italic face remains available; the built-in
    /// mixed-script defaults are used until a researcher chooses another
    /// family. An empty configured value explicitly disables that fallback.
    static func semanticTypographyCSS(for settings: DocumentAppearanceSettings) -> String {
        let bodyFont = cssFontFamily(settings.body.fontFamily)
        let headingFont =
            settings.headings.fontFamily == .body
            ? bodyFont
            : cssFontFamily(settings.headings.fontFamily)
        let bodyEmphasis = cjkFontFamily(
            configured: settings.body.cjkEmphasisFontFamily,
            fallback: bodyFont,
            useDefault: true
        )
        let bodyStrong = cjkFontFamily(
            configured: settings.body.cjkStrongFontFamily,
            fallback: bodyFont,
            useDefault: false
        )
        let headingEmphasis = cjkFontFamily(
            configured: settings.headings.cjkEmphasisFontFamily,
            fallback: headingFont,
            useDefault: true
        )
        let headingStrong = cjkFontFamily(
            configured: settings.headings.cjkStrongFontFamily,
            fallback: headingFont,
            useDefault: false
        )

        let bodyContainers = [
            ".scholium-document p",
            ".scholium-document li",
            ".scholium-document blockquote",
            ".scholium-document td",
            ".scholium-document th",
        ]
        let headingContainers = (1...6).map { ".scholium-document h\($0)" }

        func staticSelector(_ containers: [String], _ semantic: String) -> [String] {
            containers.map { "\($0) \(semantic) :lang(zh-Hans)" }
        }

        func addRule(_ selectors: [String], _ declarations: String, to css: inout String) {
            guard !selectors.isEmpty else { return }
            css += "\n\(selectors.joined(separator: ",\n")) {\n\(declarations)\n}"
        }

        var css = ""
        if let bodyEmphasis {
            addRule(
                staticSelector(bodyContainers, "em"),
                "  font-family: \(bodyEmphasis);\n  font-style: normal;",
                to: &css
            )
        } else if settings.body.cjkEmphasisFontFamily?.isEmpty == true {
            addRule(
                staticSelector(bodyContainers, "em"),
                "  font-family: inherit;\n  font-style: italic;",
                to: &css
            )
        }
        if let bodyStrong {
            addRule(
                staticSelector(bodyContainers, "strong"),
                "  font-family: \(bodyStrong);",
                to: &css
            )
        }
        if let headingEmphasis {
            addRule(
                staticSelector(headingContainers, "em"),
                "  font-family: \(headingEmphasis);\n  font-style: normal;",
                to: &css
            )
            if settings.headings.style == .italic {
                addRule(
                    headingContainers.flatMap { ["\($0) :lang(zh-Hans)"] },
                    "  font-family: \(headingEmphasis);\n  font-style: normal;",
                    to: &css
                )
            }
        } else if settings.headings.cjkEmphasisFontFamily?.isEmpty == true {
            let inlineSelectors =
                staticSelector(headingContainers, "em")
            addRule(
                inlineSelectors,
                "  font-family: inherit;\n  font-style: italic;",
                to: &css
            )
        }
        if let headingStrong {
            addRule(
                staticSelector(headingContainers, "strong"),
                "  font-family: \(headingStrong);",
                to: &css
            )
        }
        return css
    }

    private static let defaultCJKBodyCSSFamily = "\"\(DocumentAppearanceSettings.defaultCJKBodyFontFamily)\", \"FangSong\", \"STFangSong\", serif"
    private static let defaultCJKEmphasisCSSFamily = "\"\(DocumentAppearanceSettings.defaultCJKEmphasisFontFamily)\", \"STKaiti\", serif"

    private static func cjkFontFamily(
        configured: String?,
        fallback: String,
        useDefault: Bool
    ) -> String? {
        if configured?.isEmpty == true { return nil }
        if let configured {
            let safe = quotedCSSString(configured)
            let fallbackFamily = fallback == "inherit" ? defaultCJKEmphasisCSSFamily : fallback
            return "\(safe), \(fallbackFamily)"
        }
        return useDefault ? defaultCJKEmphasisCSSFamily : nil
    }

    private static func calloutCSS(_ callout: DocumentCalloutAppearance) -> String {
        let defaults = DocumentAppearanceSettings.defaultSettings.callout(callout.role)
        let canonical: String =
            switch callout.role {
            case .orientation: "orient"
            case .connections: "connect"
            case .statement: "state"
            case .illustration: "illustrate"
            case .caution: "flag"
            case .folded: "neutral"
            case .quotation: "quote"
            case .source: "cite"
            }
        let selector = ".scholium-callout-\(canonical)"
        var css = """
            \(selector) {
              --scholium-callout-block-gap: \(number(callout.blockGapEm))em;
              margin-block: var(--scholium-callout-block-gap);
              margin-inline: \(number(callout.inlineInsetEm))em;
              font-size: \(number(callout.fontScale))em;
            }
            \(selector) .scholium-callout-body { line-height: \(callout.lineHeight.map(number) ?? "inherit"); }
            \(selector) .scholium-callout-body p { margin-block: 0; padding-block: 0; }
            \(selector) .scholium-callout-body p + p { margin-block-start: \(number(callout.paragraphSpacingEm))em; }
            \(selector) .scholium-callout-title { font-family: inherit; font-weight: \(callout.titleWeight); }
            """
        switch callout.role {
        case .orientation:
            css += """

                \(selector) {
                  margin-inline-start: \(number(callout.startInsetEm ?? defaults.startInsetEm ?? callout.inlineInsetEm))em;
                  margin-inline-end: \(number(callout.endInsetEm ?? defaults.endInsetEm ?? callout.inlineInsetEm))em;
                }
                """
        case .connections:
            css += """

                \(selector) { --scholium-callout-connect-content-indent: \(number(callout.contentIndentEm ?? defaults.contentIndentEm ?? 0))em; }
                """
        case .statement:
            css += """

                \(selector) .scholium-callout-heading { margin-inline-end: \(number(callout.titleGapEm ?? defaults.titleGapEm ?? 0))em; }
                """
        case .illustration:
            break
        case .caution, .source:
            css += """

                \(selector) {
                  padding-block: \(number(callout.paddingBlockEm ?? defaults.paddingBlockEm ?? 0.72))em;
                  padding-inline: \(number(callout.paddingInlineEm ?? defaults.paddingInlineEm ?? 0.88))em;
                }
                """
        case .folded:
            css += """

                \(selector) > .scholium-callout-body { margin-inline-start: \(number(callout.contentIndentEm ?? defaults.contentIndentEm ?? 0.5))em; }
                """
        case .quotation:
            css += """

                \(selector) .scholium-callout-quotation { font-size: \(number(callout.quotationScale ?? defaults.quotationScale ?? 1.03))em; }
                \(selector) .scholium-callout-title { font-size: \(number(callout.attributionScale ?? defaults.attributionScale ?? 0.82))em; }
                """
        }
        return css
    }

    private static func cssFontFamily(_ family: DocumentAppearanceFontFamily) -> String {
        switch family {
        // Keep the chosen Latin face first, then give mixed-script prose an
        // explicit macOS CJK partner before the generic fallback. Font
        // fallback is per glyph, so this does not force an entire mixed line
        // into one face or alter the authored source.
        case .alegreya: "Alegreya, \"Iowan Old Style\", Palatino, Georgia, \(defaultCJKBodyCSSFamily)"
        case .iowan: "\"Iowan Old Style\", Palatino, Georgia, \(defaultCJKBodyCSSFamily)"
        case .palatino: "Palatino, \"Palatino Linotype\", Georgia, \(defaultCJKBodyCSSFamily)"
        case .georgia: "Georgia, \"Times New Roman\", \(defaultCJKBodyCSSFamily)"
        case .times: "\"Times New Roman\", Times, \(defaultCJKBodyCSSFamily)"
        case .systemSerif: "ui-serif, \"New York\", Georgia, \(defaultCJKBodyCSSFamily)"
        default: "\(quotedCSSString(family.rawValue)), \(defaultCJKBodyCSSFamily)"
        }
    }

    private static func cssFontFamily(_ family: DocumentHeadingFontFamily) -> String {
        switch family {
        case .body: "inherit"
        case .alegreya: cssFontFamily(DocumentAppearanceFontFamily.alegreya)
        case .systemSerif: cssFontFamily(DocumentAppearanceFontFamily.systemSerif)
        case .systemSans: "ui-sans-serif, system-ui, -apple-system, \"PingFang SC\", sans-serif"
        default: "\(quotedCSSString(family.rawValue)), \(defaultCJKBodyCSSFamily)"
        }
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Font names are CSS string data, including quotes, markup-sensitive
    /// characters, and controls. Keep ordinary family names readable while
    /// hex-escaping everything that could terminate or escape the string.
    private static func quotedCSSString(_ value: String) -> String {
        "\""
            + value.unicodeScalars.map { scalar -> String in
                switch scalar.value {
                case 0x30...0x39, 0x41...0x5a, 0x61...0x7a, 0x20, 0x2d, 0x2e, 0x5f:
                    String(scalar)
                default:
                    "\\" + String(scalar.value, radix: 16) + " "
                }
            }.joined() + "\""
    }
}
