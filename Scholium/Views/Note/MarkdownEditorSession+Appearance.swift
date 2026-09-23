import AppKit
import CoreText
import ScholiumContracts
import ScholiumEditor

extension MarkdownEditorSession {
    func applyAppearance(_ appearance: DocumentAppearanceSettings, textScale: Double) {
        let style = NativeDocumentStyle(settings: appearance, scale: textScale)
        var token = Hasher()
        token.combine(appearance)
        token.combine(textScale)
        token.combine(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        nativeEditor.applyNativeAppearance(style.configuration(identifier: token.finalize()))
    }
}

/// Translates the existing appearance profile into AppKit attributes. The native
/// editor continues to own hidden syntax, overlays, source and text history.
@MainActor
struct NativeDocumentStyle {
    let settings: DocumentAppearanceSettings
    let scale: CGFloat
    let body: NSFont
    let heading: NSFont

    init(settings: DocumentAppearanceSettings, scale: Double) {
        self.settings = settings
        self.scale = CGFloat(scale.isFinite && scale > 0 ? scale : 1)
        let size = CGFloat(settings.body.fontSizePoints) * self.scale
        body = Self.font(settings.body.fontFamily.rawValue, size: size)
        heading =
            settings.headings.fontFamily == .body
            ? body : Self.font(settings.headings.fontFamily.rawValue, size: size)
    }

    func configuration(identifier: Int) -> NativeDocumentAppearance {
        var theme = EditorTheme.default
        theme.fontName = body.fontName
        theme.fontSize = body.pointSize
        theme.monospaceFontName = settings.source.fontFamily
        theme.monospaceFontSize = CGFloat(settings.source.fontSizePoints) * scale
        theme.lineSpacing = max(0, body.pointSize * CGFloat(settings.body.lineHeight - 1))
        theme.paragraphSpacingBefore = 0
        // Role-specific Han choices are applied per visible run below, so the
        // upstream global script override must not overwrite them afterward.
        theme.fontCascade = [:]
        let width =
            ("0" as NSString).size(withAttributes: [.font: body]).width
            * CGFloat(settings.lineWidthCharacterUnits)
        var styles: [String: CalloutStyle] = [:]
        var titleFonts: [String: NSFont] = [:]
        var padding: [String: CGFloat] = [:]
        var headerGaps: [String: CGFloat] = [:]
        for role in CalloutSemanticRole.allCases {
            let appearance = settings.callout(Self.appearanceRole(role))
            let aliases =
                (CalloutSemanticVocabulary.aliasesByCanonicalIdentifier[role.rawValue] ?? [])
                + Callout.defaultStyles.keys.filter { CalloutSemanticVocabulary.role(for: $0) == role }
            let color = Self.calloutColor(role.rawValue, dark: false)
            let darkColor = Self.calloutColor(role.rawValue, dark: true)
            let surfaceStrength =
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.09 : 0.045
            let hasSurface: Bool =
                switch role {
                case .orient, .connect, .illustrate, .quote: false
                case .cite, .state, .flag, .neutral: true
                }
            let titleScale = role == .quote ? appearance.attributionScale ?? 1 : 1
            let title = Self.weighted(
                body, size: body.pointSize * CGFloat(appearance.fontScale * titleScale),
                weight: appearance.titleWeight,
                italic: role == .orient || role == .illustrate)
            for name in [role.rawValue] + aliases {
                styles[name] = CalloutStyle(
                    iconName: "", colorHex: color, darkColorHex: darkColor,
                    backgroundColorHex: hasSurface
                        ? Self.neutralCalloutSurfaceHex(dark: false, strength: surfaceStrength) : nil,
                    darkBackgroundColorHex: hasSurface
                        ? Self.neutralCalloutSurfaceHex(dark: true, strength: surfaceStrength) : nil,
                    backgroundAlpha: 0,
                    borderEdges: [], borderWidth: 0)
                titleFonts[name] = title
                padding[name] = body.pointSize * CGFloat(appearance.fontScale * appearance.resolvedPaddingBlockEm)
                headerGaps[name] = body.pointSize * CGFloat(appearance.fontScale * appearance.resolvedHeaderBodyGapEm)
            }
        }
        return NativeDocumentAppearance(
            identifier: identifier, theme: theme, readingWidth: width,
            calloutStyles: styles, calloutTitleFonts: titleFonts,
            calloutVerticalPadding: padding, calloutHeaderGaps: headerGaps,
            codeBlockCornerRadius: ScholiumCornerRole.documentCodeBlock.radius,
            calloutCornerRadius: ScholiumCornerRole.documentCalloutSurface.radius
        ) { block, attributed in
            style(block, attributed: attributed)
        }
    }

    func style(_ block: Block, attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        switch block.kind {
        case .fence, .indentedCode, .mathDisplay, .table, .frontMatter, .htmlBlock:
            return attributed
        default: break
        }
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        let level: Int? = if case .heading(let value) = block.kind { value } else { nil }
        let headingAppearance = level.flatMap {
            settings.headings.levels.indices.contains($0 - 1)
                ? settings.headings.levels[$0 - 1] : nil
        }
        let callout = calloutRole(block)
        let calloutAppearance = callout.map { settings.callout(Self.appearanceRole($0)) }
        let firstLineEnd = (block.content as NSString).range(of: "\n").location
        let headerEnd = firstLineEnd == NSNotFound ? result.length : firstLineEnd
        let spans = SyntaxHighlighter.parse(block.content)
        let technical = spans.compactMap { span -> NSRange? in
            switch span.kind {
            case .code, .codeBlock, .math, .image, .embed, .table: span.fullRange
            default: nil
            }
        }
        let baseSize = body.pointSize * CGFloat(headingAppearance?.scale ?? calloutAppearance?.fontScale ?? 1)
        let face = Self.weighted(
            level == nil ? body : heading, size: baseSize,
            weight: level == nil ? (callout == .state ? 500 : 400) : settings.headings.weight,
            italic: level != nil && settings.headings.style == .italic)
        // Do not revive hidden delimiters or change metrics reserved by images,
        // formulas or other overlays. Technical fonts remain the code face.
        let boundaries = Set([0, result.length, headerEnd] + technical.flatMap { [$0.location, $0.upperBound] })
            .filter { 0 <= $0 && $0 <= result.length }.sorted()
        let stylingRanges = zip(boundaries, boundaries.dropFirst()).map { NSRange(location: $0, length: $1 - $0) }
        for stylingRange in stylingRanges {
            result.enumerateAttributes(in: stylingRange) { attributes, range, _ in
                guard let existing = attributes[.font] as? NSFont, existing.pointSize >= 1,
                    attributes[.attachment] == nil, attributes[.fragmentOverlay] == nil,
                    attributes[.editorTechnicalFont] == nil,
                    (attributes[.foregroundColor] as? NSColor)?.alphaComponent != 0,
                    !technical.contains(where: { NSIntersectionRange($0, range).length > 0 })
                else { return }
                var font = face
                let isHeader = callout != nil && range.location < headerEnd
                if let calloutAppearance {
                    if isHeader {
                        font = Self.weighted(
                            body,
                            size: baseSize * CGFloat(callout == .quote ? calloutAppearance.attributionScale ?? 1 : 1),
                            weight: calloutAppearance.titleWeight,
                            italic: callout == .orient || callout == .illustrate)
                    } else if callout == .quote {
                        font = Self.weighted(
                            body, size: baseSize * CGFloat(calloutAppearance.quotationScale ?? 1),
                            weight: 400, italic: true)
                    }
                }
                if let runLevel = (attributes[.editorHeadingLevel] as? Int) ?? level, (1...6).contains(runLevel) {
                    font = headingFace(size: body.pointSize * CGFloat(settings.headings.levels[runLevel - 1].scale))
                }
                var traits: NSFontTraitMask = []
                if attributes[.editorStrong] as? Bool == true { traits.insert(.boldFontMask) }
                if attributes[.editorEmphasis] as? Bool == true { traits.insert(.italicFontMask) }
                if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
                result.addAttribute(.font, value: font, range: range)
                if attributes[.editorSyntaxInk] != nil {
                    result.addAttribute(
                        .foregroundColor, value: ScholiumColorRole.secondaryText.nsColor,
                        range: range)
                } else if attributes[.link] == nil, attributes[.editorLinkURL] == nil,
                    attributes[.editorWikiTarget] == nil
                {
                    if !isHeader {
                        let secondary = callout.map { [.orient, .cite, .connect].contains($0) } ?? false
                        result.addAttribute(
                            .foregroundColor,
                            value: (secondary ? ScholiumColorRole.secondaryText : .primaryText).nsColor,
                            range: range)
                    }
                }
            }
        }
        var headingSpans: [(range: NSRange, level: Int)] = []
        result.enumerateAttribute(.editorHeadingLevel, in: full) { value, range, _ in
            guard let value = value as? Int, (1...6).contains(value) else { return }
            headingSpans.append((range, value))
        }
        if headingSpans.isEmpty, let level { headingSpans.append((full, level)) }
        // Semantic spans preserve authored strong/emphasis after heading font
        // replacement, including distinct configured CJK role faces.
        for span in spans {
            let traits: NSFontTraitMask
            switch span.kind {
            case .bold: traits = .boldFontMask
            case .italic: traits = .italicFontMask
            case .boldItalic: traits = [.boldFontMask, .italicFontMask]
            default: continue
            }
            let range = NSIntersectionRange(full, span.contentRange)
            guard range.length > 0 else { continue }
            result.enumerateAttribute(.font, in: range) { value, subrange, _ in
                guard let font = value as? NSFont, font.pointSize >= 1 else { return }
                result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: subrange)
            }
        }
        applyHanFonts(result, headingRanges: headingSpans.map(\.range), technical: technical)
        (result.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { _, _, range, _ in
            let value = result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
            let paragraph =
                (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            let isHeader = callout != nil && range.location < headerEnd
            let nestedHeading = headingSpans.first { NSIntersectionRange($0.range, range).length > 0 }
                .map { settings.headings.levels[$0.level - 1] }
            let headingAppearance = nestedHeading ?? headingAppearance
            let baseSize = headingAppearance.map { body.pointSize * CGFloat($0.scale) } ?? baseSize
            let lineHeight =
                headingAppearance == nil
                ? (calloutAppearance?.lineHeight ?? settings.body.lineHeight) : settings.headings.lineHeight
            paragraph.lineSpacing = 0
            var hasOverlay = false
            result.enumerateAttribute(.fragmentOverlay, in: range) { value, _, stop in
                if value != nil {
                    hasOverlay = true
                    stop.pointee = true
                }
            }
            let lineSize =
                baseSize
                * CGFloat(
                    !isHeader && callout == .quote
                        ? calloutAppearance?.quotationScale ?? 1 : 1)
            paragraph.minimumLineHeight =
                hasOverlay
                ? max(paragraph.minimumLineHeight, lineSize * CGFloat(lineHeight))
                : lineSize * CGFloat(lineHeight)
            paragraph.lineHeightMultiple = 0
            paragraph.alignment = Self.alignment(headingAppearance?.alignment ?? settings.body.alignment)
            paragraph.usesDefaultHyphenation = settings.hyphenation == .automatic
            paragraph.hyphenationFactor = settings.hyphenation == .automatic ? 1 : 0
            if let headingAppearance {
                paragraph.paragraphSpacingBefore = baseSize * CGFloat(headingAppearance.spaceBeforeEm)
                paragraph.paragraphSpacing = baseSize * CGFloat(headingAppearance.spaceAfterEm)
            } else if let calloutAppearance {
                // The native renderer owns the source-marker gutter and the
                // box's clickable vertical padding. Shift that intact layout
                // to the same content inset used by Read; replacing its
                // paragraph spacing used to put the *outer* block gap inside
                // the painted Callout and made the box much too tall.
                let quoteWidth = ("> " as NSString).size(withAttributes: [.font: body]).width
                let nativeInset = 2 + quoteWidth
                let start =
                    baseSize
                    * CGFloat(
                        (calloutAppearance.startInsetEm ?? calloutAppearance.inlineInsetEm)
                            + calloutAppearance.resolvedPaddingInlineEm)
                let end =
                    baseSize
                    * CGFloat(
                        (calloutAppearance.endInsetEm ?? calloutAppearance.inlineInsetEm)
                            + calloutAppearance.resolvedPaddingInlineEm)
                let bodyIndent = isHeader ? 0 : baseSize * CGFloat(calloutAppearance.contentIndentEm ?? 0)
                let shift = start - nativeInset + bodyIndent
                paragraph.firstLineHeadIndent += shift
                paragraph.headIndent += shift
                paragraph.tailIndent = -end
            } else if block.kind == .paragraph {
                paragraph.firstLineHeadIndent = baseSize * CGFloat(settings.body.firstLineIndentEm)
                paragraph.paragraphSpacing = baseSize * CGFloat(settings.body.paragraphSpacingEm)
            }
            result.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        return result
    }

    private func applyHanFonts(_ result: NSMutableAttributedString, headingRanges: [NSRange], technical: [NSRange]) {
        let text = result.string as NSString
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byComposedCharacterSequences) { cluster, range, _, _ in
            guard let cluster, FontCascadeScript.classify(cluster) == .han,
                result.attribute(.editorTechnicalFont, at: range.location, effectiveRange: nil) == nil,
                result.attribute(.attachment, at: range.location, effectiveRange: nil) == nil,
                result.attribute(.fragmentOverlay, at: range.location, effectiveRange: nil) == nil,
                (result.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.alphaComponent != 0,
                !technical.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
                font.pointSize >= 1
            else { return }
            let isHeading = headingRanges.contains { NSLocationInRange(range.location, $0) }
            let traits = font.fontDescriptor.symbolicTraits
            let strong = isHeading ? settings.headings.cjkStrongFontFamily : settings.body.cjkStrongFontFamily
            let emphasis = isHeading ? settings.headings.cjkEmphasisFontFamily : settings.body.cjkEmphasisFontFamily
            let family: String?
            if traits.contains(.italic) {
                family = emphasis ?? DocumentAppearanceSettings.defaultCJKEmphasisFontFamily
            } else if traits.contains(.bold) {
                family = strong
            } else {
                family = nil
            }
            let scalars = Array(cluster.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: scalars.count)
            let covers = CTFontGetGlyphsForCharacters(font as CTFont, scalars, &glyphs, scalars.count)
            var han =
                family.flatMap { $0.isEmpty ? nil : NSFont(name: $0, size: font.pointSize) }
                ?? (covers ? font : NSFont(name: DocumentAppearanceSettings.defaultCJKBodyFontFamily, size: font.pointSize) ?? font)
            if traits.contains(.bold) { han = NSFontManager.shared.convert(han, toHaveTrait: .boldFontMask) }
            if family == "", traits.contains(.italic) { han = NSFontManager.shared.convert(han, toHaveTrait: .italicFontMask) }
            result.addAttribute(.font, value: han, range: range)
            if traits.contains(.bold), !han.fontDescriptor.symbolicTraits.contains(.bold) {
                // Match the native core's existing bold-less CJK fallback.
                result.addAttribute(.strokeWidth, value: NSNumber(value: -3.0), range: range)
            }
        }
    }

    private func headingFace(size: CGFloat) -> NSFont {
        let face = Self.weighted(
            heading, size: size, weight: settings.headings.weight,
            italic: settings.headings.style == .italic)
        guard settings.headings.style == .smallCaps else { return face }
        let features: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLowerCaseType, .selectorIdentifier: kLowerCaseSmallCapsSelector],
            [.typeIdentifier: kUpperCaseType, .selectorIdentifier: kUpperCaseSmallCapsSelector],
        ]
        return NSFont(
            descriptor: face.fontDescriptor.addingAttributes([.featureSettings: features]),
            size: face.pointSize) ?? face
    }

    private func calloutRole(_ block: Block) -> CalloutSemanticRole? {
        guard case .quoteRun(let isCallout) = block.kind, isCallout else { return nil }
        let first = block.content.components(separatedBy: "\n")[0]
        let content = first.drop(while: { $0 == " " || $0 == "\t" || $0 == ">" })
        guard let marker = Callout.parseMarker(String(content)) else { return nil }
        return CalloutSemanticVocabulary.role(for: marker.type)
    }

    private static func appearanceRole(_ role: CalloutSemanticRole) -> DocumentCalloutAppearanceRole {
        switch role {
        case .orient: .orientation
        case .cite: .source
        case .connect: .connections
        case .state: .statement
        case .illustrate: .illustration
        case .quote: .quotation
        case .flag: .caution
        case .neutral: .folded
        }
    }

    private static func alignment(_ value: DocumentTextAlignment) -> NSTextAlignment {
        switch value {
        case .start: .natural
        case .center: .center
        case .justify: .justified
        }
    }

    private static func font(_ family: String, size: CGFloat) -> NSFont {
        if family == "systemSans" { return .systemFont(ofSize: size) }
        if family == "systemSerif", let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif),
            let font = NSFont(descriptor: descriptor, size: size)
        {
            return font
        }
        let names: [String] =
            switch family {
            case "alegreya": ["Alegreya", "Iowan Old Style", "Palatino", "Georgia"]
            case "iowan": ["Iowan Old Style", "Palatino", "Georgia"]
            case "palatino": ["Palatino", "Palatino Linotype", "Georgia"]
            case "georgia": ["Georgia", "Times New Roman"]
            case "times": ["Times New Roman", "Times"]
            default: [family]
            }
        return names.lazy.compactMap { NSFont(name: $0, size: size) }.first ?? .systemFont(ofSize: size)
    }

    private static func weighted(_ font: NSFont, size: CGFloat, weight: Int, italic: Bool) -> NSFont {
        let nativeWeight: NSFont.Weight =
            switch weight {
            case ...199: .ultraLight
            case 200...299: .thin
            case 300...399: .light
            case 400...499: .regular
            case 500...599: .medium
            case 600...699: .semibold
            case 700...799: .bold
            case 800...899: .heavy
            default: .black
            }
        let descriptor = font.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: nativeWeight.rawValue]])
        let resolved = NSFont(descriptor: descriptor, size: size) ?? font
        return italic ? NSFontManager.shared.convert(resolved, toHaveTrait: .italicFontMask) : resolved
    }

    private static func calloutColor(_ role: String, dark: Bool) -> String {
        String(
            format: "#%06X",
            ScholiumColorRole.calloutTitleRGBValue(
                role, isDark: dark,
                increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast))
    }

    private static func neutralCalloutSurfaceHex(dark: Bool, strength: Double) -> String {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let ink = ScholiumColorRole.primaryText.resolvedRGBValue(
            isDark: dark, increasedContrast: contrast)
        let paper = ScholiumColorRole.documentBackground.resolvedRGBValue(
            isDark: dark, increasedContrast: contrast)
        func channel(_ shift: UInt32) -> UInt32 {
            let foreground = Double((ink >> shift) & 0xFF)
            let background = Double((paper >> shift) & 0xFF)
            return UInt32((foreground * strength + background * (1 - strength)).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(16), channel(8), channel(0))
    }
}
