import ScholiumContracts
import AppKit
import Foundation
import SwiftUI

/// The complete configurable color boundary.
enum ScholiumColorVariable: String, CaseIterable, Sendable {
    case accent
    case paper
}

/// The only configurable color inputs. Every interface color is a resolved
/// semantic role rather than another independently configurable swatch.
struct ScholiumColorVariables: Equatable, Sendable {
    let accent: UInt32
    let paper: UInt32

    static let editorialCopper = Self(
        accent: 0xA94C22,
        paper: 0xFEF8ED
    )

    subscript(variable: ScholiumColorVariable) -> UInt32 {
        switch variable {
        case .accent: accent
        case .paper: paper
        }
    }
}

/// Semantic interface colors shared by native call sites and WebKit document
/// surfaces. These are resolver outputs, not user-configurable Variables.
enum ScholiumColorRole: String, CaseIterable, Sendable {
    case documentBackground
    case surfaceBackground
    case navigationSurfaceBackground
    case apparatusSurfaceBackground
    case raisedSurfaceBackground
    case primaryText
    case secondaryText
    case mutedText
    case separator
    case accent
    case accentHover
    case notificationHighlight
    case information
    case attention
    case destructive
    case confirmed
    case agentAuthorship
    case connectionNeutral
    case connectionSupport
    case connectionIncompatible

    var cssVariableName: String {
        "--scholium-color-\(rawValue.kebabCased)"
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    func color(increasedContrast: Bool) -> Color {
        Color(nsColor: nsColor(increasedContrast: increasedContrast))
    }

    var nsColor: NSColor {
        makeNSColor(increasedContrast: nil)
    }

    func nsColor(increasedContrast: Bool) -> NSColor {
        makeNSColor(increasedContrast: increasedContrast)
    }

    private func makeNSColor(increasedContrast: Bool?) -> NSColor {
        NSColor(name: nil) { appearance in
            Self.rgb(resolvedRGBValue(
                for: appearance,
                increasedContrast: increasedContrast
                    ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ))
        }
    }

    func resolvedRGBValue(
        for appearance: NSAppearance,
        increasedContrast: Bool
    ) -> UInt32 {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return resolvedRGBValue(isDark: isDark, increasedContrast: increasedContrast)
    }

    func resolvedRGBValue(isDark: Bool, increasedContrast: Bool) -> UInt32 {
        let palette: ScholiumResolvedColorPalette = switch (isDark, increasedContrast) {
        case (false, false): Self.lightPalette
        case (false, true): Self.increasedContrastLightPalette
        case (true, false): Self.darkPalette
        case (true, true): Self.increasedContrastDarkPalette
        }
        return palette[self]
    }

    private static let resolver = ScholiumColorResolver(variables: .editorialCopper)
    private static let lightPalette = resolver.resolve(isDark: false, increasedContrast: false)
    private static let increasedContrastLightPalette = resolver.resolve(isDark: false, increasedContrast: true)
    private static let darkPalette = resolver.resolve(isDark: true, increasedContrast: false)
    private static let increasedContrastDarkPalette = resolver.resolve(isDark: true, increasedContrast: true)

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A complete appearance result generated from the two configurable inputs.
/// Call sites consume `ScholiumColorRole`; this value never becomes a second
/// configuration or persistence authority.
struct ScholiumResolvedColorPalette: Equatable, Sendable {
    let documentBackground: UInt32
    let surfaceBackground: UInt32
    let navigationSurfaceBackground: UInt32
    let apparatusSurfaceBackground: UInt32
    let raisedSurfaceBackground: UInt32
    let primaryText: UInt32
    let secondaryText: UInt32
    let mutedText: UInt32
    let separator: UInt32
    let accent: UInt32
    let accentHover: UInt32
    let notificationHighlight: UInt32
    let information: UInt32
    let attention: UInt32
    let destructive: UInt32
    let confirmed: UInt32
    let agentAuthorship: UInt32
    let connectionNeutral: UInt32
    let connectionSupport: UInt32
    let connectionIncompatible: UInt32

    subscript(role: ScholiumColorRole) -> UInt32 {
        switch role {
        case .documentBackground: documentBackground
        case .surfaceBackground: surfaceBackground
        case .navigationSurfaceBackground: navigationSurfaceBackground
        case .apparatusSurfaceBackground: apparatusSurfaceBackground
        case .raisedSurfaceBackground: raisedSurfaceBackground
        case .primaryText: primaryText
        case .secondaryText: secondaryText
        case .mutedText: mutedText
        case .separator: separator
        case .accent: accent
        case .accentHover: accentHover
        case .notificationHighlight: notificationHighlight
        case .information: information
        case .attention: attention
        case .destructive: destructive
        case .confirmed: confirmed
        case .agentAuthorship: agentAuthorship
        case .connectionNeutral: connectionNeutral
        case .connectionSupport: connectionSupport
        case .connectionIncompatible: connectionIncompatible
        }
    }
}

/// Resolves both native and WebKit roles from the same two sRGB variables.
/// Fixed functional anchors supply semantic hue direction but aren't exposed
/// as researcher configuration. Contrast is checked against every opaque
/// surface before a foreground result is accepted.
struct ScholiumColorResolver: Sendable {
    let variables: ScholiumColorVariables

    func resolve(isDark: Bool, increasedContrast: Bool) -> ScholiumResolvedColorPalette {
        let paperSource = Self.oklch(from: variables.paper)
        let accentSource = Self.oklch(from: variables.accent)
        let contrastTarget = increasedContrast ? 7.0 : 4.5
        let paperChroma = isDark ? 0.018 : 0.028

        // In Light appearance the approved Paper Variable is the illuminated
        // document plane itself. Dark appearance remains a resolver output
        // rather than a hard-coded inversion.
        let documentBackground = isDark
            ? Self.tone(paperSource, lightness: 0.285, chromaLimit: paperChroma)
            : variables.paper
        let surfaceBackground = Self.tone(
            paperSource,
            lightness: isDark ? 0.35 : 0.952,
            chromaLimit: paperChroma
        )
        // Both peripheral roles remain Paper-derived. Navigation owns the
        // complete Sidebar, while Apparatus is a document-adjacent margin
        // whose tone stays deliberately closer to Document than Navigation.
        let navigationSurfaceBackground = Self.tone(
            paperSource,
            lightness: isDark ? 0.33 : 0.932,
            chromaLimit: isDark ? 0.010 : 0.0103
        )
        let apparatusSurfaceBackground = Self.tone(
            paperSource,
            lightness: isDark ? 0.305 : 0.967,
            chromaLimit: isDark ? 0.017 : 0.024
        )
        let raisedSurfaceBackground = Self.tone(
            paperSource,
            lightness: isDark ? 0.405 : 0.8845,
            chromaLimit: isDark ? paperChroma : 0.0139
        )
        let backgrounds = [
            documentBackground,
            surfaceBackground,
            navigationSurfaceBackground,
            apparatusSurfaceBackground,
            raisedSurfaceBackground,
        ]

        let primaryText = Self.contrastColor(
            paperSource,
            startingLightness: isDark ? 0.94 : 0.262,
            chromaLimit: 0.014,
            backgrounds: backgrounds,
            target: contrastTarget,
            preferLight: isDark
        )
        let secondaryText = Self.contrastColor(
            paperSource,
            startingLightness: isDark ? 0.84 : 0.40,
            chromaLimit: 0.020,
            backgrounds: backgrounds,
            target: contrastTarget,
            preferLight: isDark
        )
        let mutedText = Self.contrastColor(
            paperSource,
            startingLightness: isDark ? 0.76 : 0.478,
            chromaLimit: 0.020,
            backgrounds: backgrounds,
            target: contrastTarget,
            preferLight: isDark
        )
        let separator = Self.tone(
            paperSource,
            lightness: isDark
                ? (increasedContrast ? 0.70 : 0.57)
                : (increasedContrast ? 0.62 : 0.808),
            chromaLimit: 0.020
        )
        let accent = Self.contrastColor(
            accentSource,
            startingLightness: isDark
                ? (increasedContrast ? 0.84 : 0.74)
                : (increasedContrast ? 0.38 : 0.50),
            chromaLimit: isDark ? 0.17 : 0.18,
            backgrounds: backgrounds,
            target: contrastTarget,
            preferLight: isDark
        )
        let accentHover = Self.contrastColor(
            accentSource,
            startingLightness: isDark
                ? (increasedContrast ? 0.90 : 0.82)
                : (increasedContrast ? 0.30 : 0.42),
            chromaLimit: isDark ? 0.16 : 0.17,
            backgrounds: backgrounds,
            target: contrastTarget,
            preferLight: isDark
        )
        let notificationHighlight = Self.tone(
            Self.oklch(from: FunctionalAnchor.attention),
            lightness: isDark
                ? (increasedContrast ? 0.84 : 0.76)
                : (increasedContrast ? 0.54 : 0.62),
            chromaLimit: increasedContrast ? 0.13 : 0.10
        )
        let semanticStart = isDark
            ? (increasedContrast ? 0.88 : 0.78)
            : (increasedContrast ? 0.34 : 0.48)

        func semanticColor(_ anchor: UInt32) -> UInt32 {
            Self.contrastColor(
                Self.oklch(from: anchor),
                startingLightness: semanticStart,
                chromaLimit: increasedContrast ? 0.13 : 0.10,
                backgrounds: backgrounds,
                target: contrastTarget,
                preferLight: isDark
            )
        }

        return ScholiumResolvedColorPalette(
            documentBackground: documentBackground,
            surfaceBackground: surfaceBackground,
            navigationSurfaceBackground: navigationSurfaceBackground,
            apparatusSurfaceBackground: apparatusSurfaceBackground,
            raisedSurfaceBackground: raisedSurfaceBackground,
            primaryText: primaryText,
            secondaryText: secondaryText,
            mutedText: mutedText,
            separator: separator,
            accent: accent,
            accentHover: accentHover,
            notificationHighlight: notificationHighlight,
            information: semanticColor(FunctionalAnchor.information),
            attention: semanticColor(FunctionalAnchor.attention),
            destructive: semanticColor(FunctionalAnchor.destructive),
            confirmed: semanticColor(FunctionalAnchor.confirmed),
            agentAuthorship: semanticColor(FunctionalAnchor.agentAuthorship),
            connectionNeutral: semanticColor(FunctionalAnchor.connectionNeutral),
            connectionSupport: semanticColor(FunctionalAnchor.connectionSupport),
            connectionIncompatible: semanticColor(FunctionalAnchor.connectionIncompatible)
        )
    }

    private enum FunctionalAnchor {
        static let information: UInt32 = 0x466C82
        static let attention: UInt32 = 0xA16E2C
        static let destructive: UInt32 = 0xA34A43
        static let confirmed: UInt32 = 0x4D755A
        static let agentAuthorship: UInt32 = 0x665C82
        static let connectionNeutral: UInt32 = 0x80694E
        static let connectionSupport: UInt32 = 0x3D746B
        static let connectionIncompatible: UInt32 = 0x77566F
    }

    private struct OKLCH: Sendable {
        let lightness: Double
        let chroma: Double
        let hue: Double
    }

    private static func oklch(from value: UInt32) -> OKLCH {
        let red = sRGBToLinear(Double((value >> 16) & 0xFF) / 255)
        let green = sRGBToLinear(Double((value >> 8) & 0xFF) / 255)
        let blue = sRGBToLinear(Double(value & 0xFF) / 255)
        let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        let lightness = 0.2104542553 * lRoot + 0.793617785 * mRoot - 0.0040720468 * sRoot
        let a = 1.9779984951 * lRoot - 2.428592205 * mRoot + 0.4505937099 * sRoot
        let b = 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.808675766 * sRoot
        let chroma = hypot(a, b)
        return OKLCH(
            lightness: lightness,
            chroma: chroma,
            hue: chroma < 0.00001 ? 0 : atan2(b, a)
        )
    }

    private static func tone(
        _ source: OKLCH,
        lightness: Double,
        chromaLimit: Double
    ) -> UInt32 {
        rgbValue(from: OKLCH(
            lightness: lightness,
            chroma: min(source.chroma, chromaLimit),
            hue: source.hue
        ))
    }

    private static func contrastColor(
        _ source: OKLCH,
        startingLightness: Double,
        chromaLimit: Double,
        backgrounds: [UInt32],
        target: Double,
        preferLight: Bool
    ) -> UInt32 {
        var lightness = startingLightness
        for _ in 0..<100 {
            let candidate = tone(source, lightness: lightness, chromaLimit: chromaLimit)
            if backgrounds.allSatisfy({ contrastRatio(candidate, $0) >= target }) {
                return candidate
            }
            lightness = clamp(
                lightness + (preferLight ? 0.008 : -0.008),
                minimum: 0.04,
                maximum: 0.97
            )
        }
        return tone(source, lightness: lightness, chromaLimit: chromaLimit)
    }

    private static func rgbValue(from color: OKLCH) -> UInt32 {
        var chroma = max(0, color.chroma)
        var channels = [Double](repeating: 0, count: 3)
        for _ in 0..<40 {
            channels = sRGBChannels(from: OKLCH(
                lightness: clamp(color.lightness, minimum: 0, maximum: 1),
                chroma: chroma,
                hue: color.hue
            ))
            if channels.allSatisfy({ $0 >= 0 && $0 <= 1 }) {
                break
            }
            chroma *= 0.92
        }
        let encoded = channels.map {
            UInt32((clamp($0, minimum: 0, maximum: 1) * 255).rounded())
        }
        return (encoded[0] << 16) | (encoded[1] << 8) | encoded[2]
    }

    private static func sRGBChannels(from color: OKLCH) -> [Double] {
        let a = color.chroma * cos(color.hue)
        let b = color.chroma * sin(color.hue)
        let lRoot = color.lightness + 0.3963377774 * a + 0.2158037573 * b
        let mRoot = color.lightness - 0.1055613458 * a - 0.0638541728 * b
        let sRoot = color.lightness - 0.0894841775 * a - 1.291485548 * b
        let l = pow(lRoot, 3)
        let m = pow(mRoot, 3)
        let s = pow(sRoot, 3)
        return [
            linearToSRGB(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            linearToSRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            linearToSRGB(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
        ]
    }

    private static func relativeLuminance(_ value: UInt32) -> Double {
        let red = sRGBToLinear(Double((value >> 16) & 0xFF) / 255)
        let green = sRGBToLinear(Double((value >> 8) & 0xFF) / 255)
        let blue = sRGBToLinear(Double(value & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func sRGBToLinear(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ channel: Double) -> Double {
        channel <= 0.0031308
            ? 12.92 * channel
            : 1.055 * pow(channel, 1 / 2.4) - 0.055
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

/// One visual and accessible vocabulary for explicit Markdown Connections.
/// Standard command symbols remain direct SF Symbols at their call sites.
enum ScholiumConnectionPresentation: Int, CaseIterable, Hashable, Identifiable, Sendable {
    case supports
    case supportsThisNote
    case opposes
    case opposesThisNote
    case incompatible
    case neutral

    var id: Self { self }

    init(vectorKind: VectorLinkKind?, currentIsSource: Bool) {
        self = switch vectorKind {
        case .supports:
            currentIsSource ? .supports : .supportsThisNote
        case .opposes:
            currentIsSource ? .opposes : .opposesThisNote
        case .incompatible:
            .incompatible
        case .neutral, .none:
            .neutral
        }
    }

    var title: String {
        switch self {
        case .supports: ScholiumL10n.dynamicString("Supports")
        case .supportsThisNote: ScholiumL10n.dynamicString("Supports This Note")
        case .opposes: ScholiumL10n.dynamicString("Opposes")
        case .opposesThisNote: ScholiumL10n.dynamicString("Opposes This Note")
        case .incompatible: ScholiumL10n.dynamicString("Incompatible")
        case .neutral: ScholiumL10n.dynamicString("Related")
        }
    }

    var glyphKind: ScholiumConnectionGlyphKind {
        switch self {
        case .supports: .supports
        case .supportsThisNote: .supportedBy
        case .opposes: .opposes
        case .opposesThisNote: .opposedBy
        case .incompatible: .incompatible
        case .neutral: .neutral
        }
    }
}

/// Contract names used by the CodeMirror and sanitized Read stylesheets.
/// Custom properties transport resolved semantic roles into WebKit; they are
/// not a second set of configurable color Variables.
enum ScholiumWebDesignTokens {
    static let resolvedColorRoleCSSVariableNames = Set(
        ScholiumColorRole.allCases.map(\.cssVariableName)
    )

    static let rhythmCSSDeclarations = """
    --scholium-document-line-width: \(Int(DocumentAppearanceSettings.defaultLineWidthCharacterUnits))ch;
    --scholium-document-half-line-width: \(Int(DocumentAppearanceSettings.defaultLineWidthCharacterUnits / 2))ch;
    --scholium-document-prose-font-size: \(ScholiumDocumentRhythm.proseFontSizePoints)pt;
    --scholium-document-source-font-size: \(ScholiumDocumentRhythm.sourceFontSizePixels)px;
    --scholium-document-h1-size: \(ScholiumDocumentRhythm.heading1ScalePercent)%;
    --scholium-document-h2-size: \(ScholiumDocumentRhythm.heading2ScalePercent)%;
    --scholium-document-h3-size: \(ScholiumDocumentRhythm.heading3ScalePercent)%;
    --scholium-document-h4-size: \(ScholiumDocumentRhythm.heading4ScalePercent)%;
    --scholium-rhythm-prose-line-height: \(ScholiumDocumentRhythm.proseLineHeight);
    --scholium-rhythm-source-line-height: \(ScholiumDocumentRhythm.sourceLineHeight);
    --scholium-document-text-scale-factor: 1;
    --scholium-rhythm-paragraph-gap: \(ScholiumDocumentRhythm.paragraphGapCSSPixels)px;
    --scholium-rhythm-heading-line-height: \(ScholiumDocumentRhythm.headingLineHeight);
    --scholium-rhythm-heading-before: \(ScholiumDocumentRhythm.headingGapBeforeCSSPixels)px;
    --scholium-rhythm-heading-after: \(ScholiumDocumentRhythm.headingGapAfterCSSPixels)px;
    --scholium-rhythm-title-before: \(ScholiumDocumentRhythm.headingGapBeforeCSSPixels)px;
    --scholium-rhythm-title-after: \(ScholiumDocumentRhythm.headingGapAfterCSSPixels)px;
    --scholium-rhythm-title-rule-gap: 0.5em;
    --scholium-rhythm-code-inset: \(ScholiumDocumentRhythm.codeBlockInset)px;
    --scholium-rhythm-quote-inset: \(ScholiumDocumentRhythm.quoteInlineInset)px;
    --scholium-rhythm-semantic-block-gap: 1em;
    --scholium-rhythm-rule-block-gap: 0.5em;
    --scholium-rhythm-inline-regular: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).inline)px;
    --scholium-rhythm-inline-source: \(ScholiumDocumentRhythm.contentInsets(for: .source, widthClass: .regular).inline)px;
    --scholium-rhythm-inline-narrow: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).inline)px;
    --scholium-rhythm-trailing-scroll: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).trailingViewportFraction * 100)vh;
    --scholium-document-content-top-inset: \(ScholiumMetrics.Document.contentTopInsetCSSPixels)px;
    --scholium-document-text-scale: 1em;
    """

    private static let colorResolver = ScholiumColorResolver(variables: .editorialCopper)

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

    private static func colorDeclarations(
        isDark: Bool,
        increasedContrast: Bool
    ) -> String {
        let palette = colorResolver.resolve(
            isDark: isDark,
            increasedContrast: increasedContrast
        )
        return ScholiumColorRole.allCases.map { role in
            let value = String(format: "#%06x", palette[role])
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
      font-family: Alegreya, Georgia, serif;
      font-size: var(--scholium-document-text-scale);
      line-height: var(--scholium-rhythm-prose-line-height);
      overflow-wrap: anywhere;
    }
    .cm-editor.scholium-source-mode .cm-content {
      padding-inline: max(
        var(--scholium-rhythm-inline-source),
        calc(50% - var(--scholium-document-half-line-width))
      );
    }
    .scholium-document p,
    .cm-editor.scholium-live-mode .cm-live-paragraph {
      box-sizing: border-box;
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
      border-inline-start: 3px solid var(--scholium-color-accent);
      color: color-mix(in srgb, var(--scholium-color-primary-text) 78%, transparent);
    }
    .scholium-document pre,
    .cm-editor.scholium-live-mode .cm-live-codeblock {
      box-sizing: border-box;
      font-family: "Victor Mono", ui-monospace, monospace;
      background: color-mix(in srgb, var(--scholium-color-primary-text) 7%, transparent);
    }
    .scholium-document pre.raw-html,
    .cm-editor.scholium-live-mode .cm-live-raw-html {
      box-sizing: border-box;
      color: var(--scholium-color-muted-text);
      background: color-mix(in srgb, var(--scholium-color-primary-text) 7%, transparent);
      font-family: "Victor Mono", ui-monospace, monospace;
    }
    .cm-editor.scholium-live-mode .cm-live-raw-html {
      padding-inline: var(--scholium-rhythm-code-inset);
    }
    .scholium-document pre {
      max-inline-size: 100%;
      padding: var(--scholium-rhythm-code-inset);
      overflow: auto;
      border-radius: 10px;
    }
    .cm-editor.scholium-live-mode .cm-live-codeblock {
      padding-inline: var(--scholium-rhythm-code-inset);
    }
    .cm-editor.scholium-live-mode .cm-live-codeblock-start {
      padding-block-start: var(--scholium-rhythm-code-inset);
      border-start-start-radius: 10px;
      border-start-end-radius: 10px;
    }
    .cm-editor.scholium-live-mode .cm-live-raw-html-start {
      padding-block-start: var(--scholium-rhythm-code-inset);
      border-start-start-radius: 10px;
      border-start-end-radius: 10px;
    }
    .cm-editor.scholium-live-mode .cm-live-codeblock-end {
      padding-block-end: var(--scholium-rhythm-code-inset);
      border-end-start-radius: 10px;
      border-end-end-radius: 10px;
    }
    .cm-editor.scholium-live-mode .cm-live-raw-html-end {
      padding-block-end: var(--scholium-rhythm-code-inset);
      border-end-start-radius: 10px;
      border-end-end-radius: 10px;
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
    .scholium-document del,
    .scholium-live-mode .cm-live-strike {
      color: var(--scholium-color-primary-text);
      text-decoration: line-through;
    }
    .scholium-document .scholium-highlight,
    .scholium-live-mode .cm-live-highlight {
      padding-inline: 0.06em;
      color: var(--scholium-color-primary-text);
      background: color-mix(in srgb, var(--scholium-color-notification-highlight) 32%, transparent);
      border-radius: 3px;
    }
    .scholium-document :not(pre) > code,
    .scholium-live-mode .cm-live-code {
      padding: 0.08em 0.25em;
      border-radius: 4px;
      background: color-mix(in srgb, var(--scholium-color-primary-text) 8%, transparent);
      font-family: "Victor Mono", ui-monospace, "SFMono-Regular", Menlo, monospace;
      font-size: 0.82em;
    }
    .scholium-document a:not(.scholium-vector-link),
    .scholium-live-mode .cm-live-link {
      color: var(--scholium-color-accent);
      text-decoration: underline;
      text-decoration-color: color-mix(in srgb, var(--scholium-color-accent) 42%, transparent);
      text-underline-offset: 0.15em;
    }
    .scholium-document .scholium-vector-link,
    .scholium-live-mode .cm-live-vector-link {
      line-height: 1.2;
    }
    .scholium-document h1,
    .scholium-document h2,
    .scholium-document h3,
    .scholium-document h4,
    .scholium-document h5,
    .scholium-document h6,
    .scholium-live-mode .cm-live-heading {
      font-family: Alegreya, Georgia, serif;
      font-weight: 700;
      line-height: var(--scholium-rhythm-heading-line-height);
      text-align: start;
      text-decoration-line: none;
      text-decoration: none;
      text-wrap: balance;
      box-sizing: border-box;
      margin: 0;
      padding-block: var(--scholium-rhythm-heading-before) var(--scholium-rhythm-heading-after);
    }
    .scholium-document h1,
    .scholium-live-mode .cm-live-h1 {
      font-size: var(--scholium-document-h1-size);
      font-weight: 400;
    }
    .scholium-document h2,
    .scholium-live-mode .cm-live-h2 {
      font-size: var(--scholium-document-h2-size);
    }
    .scholium-document h3,
    .scholium-live-mode .cm-live-h3 {
      font-size: var(--scholium-document-h3-size);
    }
    .scholium-document h4,
    .scholium-document h5,
    .scholium-document h6,
    .scholium-live-mode .cm-live-h4,
    .scholium-live-mode .cm-live-h5,
    .scholium-live-mode .cm-live-h6 {
      font-size: var(--scholium-document-h4-size);
    }
    .scholium-document h1 a,
    .scholium-document h2 a,
    .scholium-document h3 a,
    .scholium-document h4 a,
    .scholium-document h5 a,
    .scholium-document h6 a,
    .scholium-live-mode .cm-live-heading .cm-live-link,
    .scholium-live-mode .cm-live-heading .cm-live-wikilink,
    .scholium-live-mode .cm-live-heading .cm-live-vector-link {
      text-decoration: underline;
    }
    .scholium-document > h1:first-child,
    .scholium-live-mode .cm-live-document-title,
    .scholium-live-mode .cm-live-h1 {
      position: relative;
      margin: 0;
      padding-block: var(--scholium-rhythm-title-before) var(--scholium-rhythm-title-after);
      text-align: center;
      border-block-end: 0;
    }
    .scholium-document > h1:first-child::after,
    .scholium-live-mode .cm-live-document-title::after,
    .scholium-live-mode .cm-live-h1::after {
      content: "";
      position: absolute;
      inset-inline: 0;
      inset-block-end: max(
        0px,
        calc(var(--scholium-rhythm-title-after) - var(--scholium-rhythm-title-rule-gap))
      );
      border-block-start: 1px solid var(--scholium-color-separator);
      pointer-events: none;
    }
    .scholium-document .scholium-embed {
      color: var(--scholium-color-accent);
      font-weight: 650;
      padding: 0.08em 0.3em;
      border: 1px solid color-mix(in srgb, var(--scholium-color-accent) 28%, transparent);
      border-radius: 5px;
      text-decoration: none;
    }
    .scholium-selection-actions {
      position: fixed;
      z-index: 110;
      box-sizing: border-box;
      padding: 4px;
      border: 1px solid var(--scholium-color-accent);
      border-radius: 8px;
      color: var(--scholium-color-primary-text);
      background: var(--scholium-color-surface-background);
      font: 13px/1.3 -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .scholium-selection-actions[hidden] {
      display: none;
    }
    .scholium-selection-toolbar {
      display: flex;
      gap: 4px;
    }
    .scholium-selection-toolbar button {
      min-width: 28px;
      min-height: 28px;
      padding: 4px 7px;
      border: 0;
      border-radius: 5px;
      color: inherit;
      background: transparent;
      font: inherit;
    }
    .scholium-selection-toolbar button:hover {
      color: var(--scholium-color-accent-hover);
      background: var(--scholium-color-document-background);
    }
    .scholium-selection-toolbar button:focus-visible {
      color: var(--scholium-color-accent-hover);
      background: var(--scholium-color-document-background);
      outline: 2px solid var(--scholium-color-accent);
      outline-offset: 1px;
    }
    @media (prefers-color-scheme: dark) {
      :root { \(darkAppearanceCSSDeclarations) }
    }
    @media (prefers-contrast: more) {
      :root { \(increasedContrastCSSDeclarations) }
      .scholium-selection-actions { border-width: 2px; }
    }
    @media (prefers-color-scheme: dark) and (prefers-contrast: more) {
      :root { \(darkIncreasedContrastCSSDeclarations) }
    }
    """
}

/// The approved adaptive editorial grid. Values are named by responsibility,
/// not by scale position: AppKit still owns window and split geometry, while
/// these roles govern Scholium-owned spacing and component dimensions.
enum ScholiumGrid {
    static let foundationUnit: CGFloat = 4

    enum Spacing {
        /// Reserved for baseline and symbol alignment, never ordinary spacing.
        static let opticalAlignmentAdjustment = foundationUnit / 2
        static let labelAccessoryGap = foundationUnit
        static let inlineControlGap = foundationUnit * 2
        static let nestedContentInset = foundationUnit * 3
        static let sectionSeparation = foundationUnit * 4
        static let regionContentInset = foundationUnit * 5
        static let documentShellInsetCSSPixels = foundationUnit * 8
        static let sourceShellInsetCSSPixels = foundationUnit * 10
    }

    enum Dimension {
        static let minimumCustomTarget = foundationUnit * 5
        static let compactHierarchyRowHeight = foundationUnit * 6
        static let preferredCustomTarget = foundationUnit * 7
        static let libraryHierarchyRowHeight = foundationUnit * 7
        static let documentTabStripHeight = foundationUnit * 10
        static let researchFunctionTargetHeight = foundationUnit * 11
        static let regionHeaderHeight = foundationUnit * 12
        static let iconTrackWidth = foundationUnit * 4
    }

    enum Document {
        static let narrowWidthThresholdRootEms: CGFloat = 44
        static let compactShellInsetCSSPixels = Spacing.regionContentInset
        static let contentTopInsetCSSPixels = Spacing.documentShellInsetCSSPixels
        static let paragraphGapCSSPixels = foundationUnit * 3
        static let headingGapBeforeCSSPixels = foundationUnit * 6
        static let headingGapAfterCSSPixels = foundationUnit * 2
        static let trailingScrollViewportFraction: CGFloat = 0.45
    }

    /// The two scholarly peripheral planes share one calm page edge. Their
    /// internal row, hierarchy, and section rhythms remain independently owned.
    enum Peripheral {
        static let contentInset = foundationUnit * 7
    }

    /// Inspector-owned layout variables. The mode strip, section hierarchy,
    /// dense content groups, and Action rows each have a distinct cadence.
    enum Apparatus {
        static let contentInset = Peripheral.contentInset
        static let modeStripHeight = foundationUnit * 10
        static let modeColumnGap: CGFloat = 0
        static let selectedModeIndicatorWidth = foundationUnit * 4.5
        static let selectedModeIndicatorHeight = foundationUnit / 4
        static let firstSectionGap = foundationUnit * 4
        static let sectionGap = foundationUnit * 4
        static let headingToContentGap = foundationUnit * 2.5
        static let contentRowGap = foundationUnit * 2
        static let contentLineSpacing = foundationUnit
        static let iconColumnWidth = foundationUnit * 4
        static let iconToTextGap = foundationUnit * 2
        static let relationGlyphColumnWidth = foundationUnit * 6
        static let relationGlyphSize = foundationUnit * 5
        static let relationGlyphToTextGap = foundationUnit
        static let relationClusterGap = foundationUnit * 3
        static let relationPinnedGlyphTop = foundationUnit * 9
        static let relationRowVerticalInset = foundationUnit
        static let relationRowMinimumHeight = foundationUnit * 9
        static let actionRowVerticalInset = foundationUnit * 2
        static let actionRowMinimumHeight = foundationUnit * 11
        static let actionCopyGap = foundationUnit
        static let factGridMinimumWidth = foundationUnit * 51
        static let factLabelMinimumWidth = foundationUnit * 19.5
        static let factColumnGap = foundationUnit * 3.5
        static let factValueMinimumWidth = factGridMinimumWidth
            - factLabelMinimumWidth
            - factColumnGap
        static let longTextLabelGap = foundationUnit
        static let longTextIndent = foundationUnit * 3
        static let readingBlockGap = foundationUnit * 2
        static let bottomInset = contentInset
    }
}

enum ScholiumMetrics {
    enum Accessibility {
        static let preferredCustomTarget = ScholiumGrid.Dimension.preferredCustomTarget
        static let minimumCustomTarget = ScholiumGrid.Dimension.minimumCustomTarget
    }

    enum Onboarding {
        static let preferredWidth: CGFloat = 720
        static let preferredHeight: CGFloat = 720
    }

    enum Workspace {
        static let preferredWidth: CGFloat = 1_180
        static let preferredHeight: CGFloat = 760
        /// Spacing between Scholium-owned controls hosted by the native
        /// toolbar. Toolbar height and window-control geometry remain owned by
        /// macOS and therefore are not Scholium metrics.
        static let headerControlSpacing = ScholiumGrid.Spacing.nestedContentInset
        /// A region-owned row beneath the native titlebar. Unlike toolbar
        /// height, this is a Scholium component metric used by the Library
        /// identity and Apparatus mode row. Document identity and commands
        /// belong to the native toolbar and do not create a second row.
        static let regionHeaderHeight = ScholiumGrid.Dimension.regionHeaderHeight
    }

    enum Library {
        /// Smallest width at which the complete Library remains readable while
        /// expanded. The longest fixed English header, its count and action,
        /// plus the 20-point region insets fit inside this boundary. AppKit
        /// still owns resizing and collapse; this is not a preferred width or
        /// a window minimum.
        static let minimumReadableWidth: CGFloat = 300
        /// Library and Inspector share the peripheral page edge. This does not
        /// merge their row, hierarchy, or section rhythm, and it deliberately
        /// does not derive geometry from the traffic-light group.
        static let contentInset = ScholiumGrid.Peripheral.contentInset
        /// One semantic leading slot shared by disclosure, Folder, and Note
        /// rows. No row may render a second icon beside this track.
        static let leadingSlotWidth = ScholiumGrid.Dimension.iconTrackWidth
        /// Folder and Note rows use the preferred macOS custom-control target.
        /// The value is a minimum so enlarged interface text can grow.
        static let hierarchyRowHeight = ScholiumGrid.Dimension.libraryHierarchyRowHeight
        static let rowHorizontalInset = ScholiumGrid.Spacing.nestedContentInset
        static let hierarchyIndent = ScholiumGrid.Dimension.iconTrackWidth
        static let selectionBoundaryWidth = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let scopeIndicatorWidth: CGFloat = 18
        static let scopeIndicatorHeight: CGFloat = 1
        static let scopeTopSpacing = ScholiumGrid.Spacing.sectionSeparation
        static let sectionSpacing = ScholiumGrid.Spacing.sectionSeparation
        /// The fixed bibliography band sits slightly above the visual centre
        /// of its region so its last line keeps a calm window-edge margin.
        static let bibliographyTopInset = ScholiumGrid.Spacing.nestedContentInset
        static let bibliographyBottomInset = ScholiumGrid.Spacing.sectionSeparation
        /// Empty, loading, and error content begins one section step below the
        /// stable LocationHeader while retaining the shared peripheral edge.
        static let sourceStateVerticalInset = ScholiumGrid.Spacing.sectionSeparation
    }

    enum Attention {
        /// Attention is intentionally a bounded, transient queue for a small
        /// number of urgent derived issues. Native popover chrome and arrow
        /// geometry remain system-owned.
        static let popoverWidth: CGFloat = 420
        static let popoverHeight: CGFloat = 480
    }

    enum Document {
        /// Document-local breathing room below the system-owned toolbar. The
        /// toolbar safe area is not added again by document layout.
        static let contentTopInsetCSSPixels = ScholiumGrid.Document.contentTopInsetCSSPixels
        static let defaultTextScale = 1.0
        static let minimumTextScale = 1.0
        static let maximumTextScale = 2.0
        static let textScaleStep = 0.1
    }

    enum Apparatus {
        /// One initial suggestion, mirroring the system inspector's ideal-width
        /// semantics. AppKit continues to own subsequent resizing.
        static let firstRevealWidth: CGFloat = 320
        /// Component-owned height for the Overview/Connections/Functions row and
        /// the trailing Research Inspector header. It does not size the window
        /// toolbar or the standard window controls.
        static let headerHeight = ScholiumGrid.Apparatus.modeStripHeight
        /// All three Inspector modes share one outer content edge. Individual
        /// sections must not invent their own horizontal padding.
        static let contentInset = ScholiumGrid.Apparatus.contentInset
        static let firstSectionSpacing = ScholiumGrid.Apparatus.firstSectionGap
        static let sectionSpacing = ScholiumGrid.Apparatus.sectionGap
        /// Internal section rhythm is deliberately separate from the spacing
        /// between complete sections.
        static let sectionContentSpacing = ScholiumGrid.Apparatus.headingToContentGap
        static let rowSpacing = ScholiumGrid.Apparatus.contentRowGap
        static let bodyLineSpacing = ScholiumGrid.Apparatus.contentLineSpacing
        static let modeColumnSpacing = ScholiumGrid.Apparatus.modeColumnGap
        static let selectedModeIndicatorWidth =
            ScholiumGrid.Apparatus.selectedModeIndicatorWidth
        static let selectedModeIndicatorHeight =
            ScholiumGrid.Apparatus.selectedModeIndicatorHeight
        static let actionRowVerticalInset = ScholiumGrid.Apparatus.actionRowVerticalInset
        static let actionRowMinimumHeight = ScholiumGrid.Apparatus.actionRowMinimumHeight
        static let actionCopySpacing = ScholiumGrid.Apparatus.actionCopyGap
        static let factGridMinimumWidth = ScholiumGrid.Apparatus.factGridMinimumWidth
        static let factLabelMinimumWidth = ScholiumGrid.Apparatus.factLabelMinimumWidth
        static let factColumnSpacing = ScholiumGrid.Apparatus.factColumnGap
        static let factValueMinimumWidth = ScholiumGrid.Apparatus.factValueMinimumWidth
        static let longTextLabelSpacing = ScholiumGrid.Apparatus.longTextLabelGap
        static let longTextIndent = ScholiumGrid.Apparatus.longTextIndent
        static let readingBlockSpacing = ScholiumGrid.Apparatus.readingBlockGap
        /// A fixed symbol track keeps every row's text on the same scan line,
        /// regardless of the optical width of its SF Symbol.
        static let iconColumnWidth = ScholiumGrid.Apparatus.iconColumnWidth
        static let iconToTextSpacing = ScholiumGrid.Apparatus.iconToTextGap
        static let relationGlyphColumnWidth =
            ScholiumGrid.Apparatus.relationGlyphColumnWidth
        static let relationGlyphSize = ScholiumGrid.Apparatus.relationGlyphSize
        static let relationGlyphToTextSpacing =
            ScholiumGrid.Apparatus.relationGlyphToTextGap
        static let relationClusterSpacing = ScholiumGrid.Apparatus.relationClusterGap
        static let relationPinnedGlyphTop = ScholiumGrid.Apparatus.relationPinnedGlyphTop
        static let relationRowVerticalInset =
            ScholiumGrid.Apparatus.relationRowVerticalInset
        static let relationRowMinimumHeight =
            ScholiumGrid.Apparatus.relationRowMinimumHeight
        static let bottomInset = ScholiumGrid.Apparatus.bottomInset
    }

    enum Search {
        static let preferredWidth: CGFloat = 640
        static let maximumWidth: CGFloat = 720
        static let collapsedHeight: CGFloat = 104
        static let resultRowHeight: CGFloat = 64
        static let resultHorizontalInset = ScholiumGrid.Spacing.regionContentInset
        static let resultVerticalInset = ScholiumGrid.Spacing.labelAccessoryGap
        static let selectionIndicatorWidth = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let expandedHeight: CGFloat = 520
        static let scopeWidth: CGFloat = 320
        static let responsiveMargin = ScholiumGrid.Spacing.regionContentInset
        static let cornerRadius: CGFloat = 12
    }

}

/// The one mutable presentation contract shared by Read, Live Preview, and
/// Source. It configures layout and scale only; no renderer may derive or
/// rewrite authoritative Markdown from these values.
struct ScholiumDocumentPresentationConfiguration: Equatable, Sendable {
    let textScale: Double
    let contentTopInsetCSSPixels: CGFloat
    let regularInlineInsetCSSPixels: CGFloat
    let sourceInlineInsetCSSPixels: CGFloat
    let compactInlineInsetCSSPixels: CGFloat
    let compactThresholdRootEms: CGFloat

    init(
        textScale: Double,
        contentTopInsetCSSPixels: CGFloat = ScholiumMetrics.Document.contentTopInsetCSSPixels,
        regularInlineInsetCSSPixels: CGFloat = ScholiumGrid.Spacing.documentShellInsetCSSPixels,
        sourceInlineInsetCSSPixels: CGFloat = ScholiumGrid.Spacing.sourceShellInsetCSSPixels,
        compactInlineInsetCSSPixels: CGFloat = ScholiumGrid.Document.compactShellInsetCSSPixels,
        compactThresholdRootEms: CGFloat = ScholiumGrid.Document.narrowWidthThresholdRootEms
    ) {
        self.textScale = min(
            ScholiumMetrics.Document.maximumTextScale,
            max(ScholiumMetrics.Document.minimumTextScale, textScale)
        )
        self.contentTopInsetCSSPixels = max(0, contentTopInsetCSSPixels)
        self.regularInlineInsetCSSPixels = max(0, regularInlineInsetCSSPixels)
        self.sourceInlineInsetCSSPixels = max(0, sourceInlineInsetCSSPixels)
        self.compactInlineInsetCSSPixels = max(0, compactInlineInsetCSSPixels)
        self.compactThresholdRootEms = max(0, compactThresholdRootEms)
    }

    var css: String {
        let locale = Locale(identifier: "en_US_POSIX")
        return String(
            format: """
            :root {
              --scholium-document-text-scale: %.6fem;
              --scholium-document-text-scale-factor: %.6f;
              --scholium-document-content-top-inset: %.6fpx;
              --scholium-rhythm-inline-regular: %.6fpx;
              --scholium-rhythm-inline-source: %.6fpx;
              --scholium-rhythm-inline-narrow: %.6fpx;
              --scholium-rhythm-paragraph-gap: %.6fpx;
              --scholium-rhythm-heading-before: %.6fpx;
              --scholium-rhythm-heading-after: %.6fpx;
            }
            @media (max-width: %.6frem) {
              .scholium-document,
              .cm-editor.scholium-live-mode .cm-content,
              .cm-editor.scholium-source-mode .cm-content {
                padding-inline: max(
                  var(--scholium-rhythm-inline-narrow),
                  calc(50%% - var(--scholium-document-half-line-width))
                );
              }
            }
            """,
            locale: locale,
            textScale,
            textScale,
            Double(contentTopInsetCSSPixels),
            Double(regularInlineInsetCSSPixels),
            Double(sourceInlineInsetCSSPixels),
            Double(compactInlineInsetCSSPixels),
            Double(ScholiumDocumentRhythm.paragraphGapCSSPixels) * textScale,
            Double(ScholiumDocumentRhythm.headingGapBeforeCSSPixels) * textScale,
            Double(ScholiumDocumentRhythm.headingGapAfterCSSPixels) * textScale,
            Double(compactThresholdRootEms)
        )
    }
}

enum ScholiumShape {
    static let inlineStatusCornerRadius: CGFloat = 8
    static let editorialControlCornerRadius: CGFloat = 8
    static let editorialPanelCornerRadius: CGFloat = 10
    static let loadingSurfaceCornerRadius: CGFloat = 10
}

enum ScholiumSurfaceRole: CaseIterable, Hashable, Sendable {
    case document
    case navigation
    case apparatus
    case floatingControl
    case boundedPanel
    case searchOverlay
    case denseEvidence

    var colorRole: ScholiumColorRole {
        switch self {
        case .document: .documentBackground
        case .navigation: .navigationSurfaceBackground
        case .apparatus: .apparatusSurfaceBackground
        case .floatingControl, .boundedPanel, .searchOverlay: .surfaceBackground
        case .denseEvidence: .documentBackground
        }
    }

    var defaultBoundaryRole: ScholiumBoundaryRole {
        switch self {
        case .floatingControl, .searchOverlay:
            .floatingBoundary
        case .document, .navigation, .apparatus, .boundedPanel, .denseEvidence:
            .subtleBoundary
        }
    }

    var defaultElevationRole: ScholiumElevationRole? {
        switch self {
        case .floatingControl:
            .floatingControl
        case .boundedPanel:
            .boundedPanel
        case .searchOverlay:
            .searchOverlay
        case .document, .navigation, .apparatus, .denseEvidence:
            nil
        }
    }
}

struct ScholiumElevationStyle: Equatable, Sendable {
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum ScholiumElevationRole: CaseIterable, Sendable {
    case floatingControl
    case boundedPanel
    case searchOverlay

    func style(reduceTransparency: Bool, appearsActive: Bool) -> ScholiumElevationStyle {
        let recipe: ScholiumElevationStyle = switch self {
        case .floatingControl:
            .init(opacity: 0.04, radius: 4, x: 0, y: 2)
        case .boundedPanel:
            .init(opacity: 0.03, radius: 4, x: 0, y: 2)
        case .searchOverlay:
            .init(opacity: 0.12, radius: 12, x: 0, y: 6)
        }
        let transparencyMultiplier = reduceTransparency ? 0.5 : 1.0
        let activityMultiplier = appearsActive ? 1.0 : 0.6
        return .init(
            opacity: recipe.opacity * transparencyMultiplier * activityMultiplier,
            radius: recipe.radius,
            x: recipe.x,
            y: recipe.y
        )
    }
}

struct ScholiumBoundaryStyle: Equatable, Sendable {
    let colorRole: ScholiumColorRole
    let opacity: Double
    let lineWidth: CGFloat
}

enum ScholiumBoundaryRole: CaseIterable, Sendable {
    case structuralDivider
    case subtleBoundary
    case floatingBoundary

    func style(
        increasedContrast: Bool,
        reduceTransparency: Bool
    ) -> ScholiumBoundaryStyle {
        let emphasized = increasedContrast || reduceTransparency
        return switch self {
        case .structuralDivider:
            .init(colorRole: .separator, opacity: emphasized ? 0.78 : 0.42, lineWidth: emphasized ? 1 : 0.5)
        case .subtleBoundary:
            .init(colorRole: .separator, opacity: emphasized ? 0.82 : 0.34, lineWidth: emphasized ? 1 : 0.75)
        case .floatingBoundary:
            .init(colorRole: .separator, opacity: emphasized ? 0.82 : 0.34, lineWidth: emphasized ? 1 : 0.75)
        }
    }
}

enum ScholiumDocumentRenderer: CaseIterable, Sendable {
    case read
    case livePreview
    case source
}

enum ScholiumDocumentWidthClass: CaseIterable, Sendable {
    case regular
    case narrow
}

/// Preview and test overrides for environment-owned visual adaptations. A nil
/// field preserves the actual macOS environment used by production windows.
struct ScholiumVisualEnvironmentOverride: Equatable, Sendable {
    var increasedContrast: Bool?
    var reduceTransparency: Bool?
    var reduceMotion: Bool?
    var appearsActive: Bool?

    init(
        increasedContrast: Bool? = nil,
        reduceTransparency: Bool? = nil,
        reduceMotion: Bool? = nil,
        appearsActive: Bool? = nil
    ) {
        self.increasedContrast = increasedContrast
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        self.appearsActive = appearsActive
    }
}

private struct ScholiumVisualEnvironmentOverrideKey: EnvironmentKey {
    static let defaultValue = ScholiumVisualEnvironmentOverride()
}

extension EnvironmentValues {
    var scholiumVisualEnvironmentOverride: ScholiumVisualEnvironmentOverride {
        get { self[ScholiumVisualEnvironmentOverrideKey.self] }
        set { self[ScholiumVisualEnvironmentOverrideKey.self] = newValue }
    }

    var scholiumIncreasedContrast: Bool {
        scholiumVisualEnvironmentOverride.increasedContrast
            ?? (colorSchemeContrast == .increased)
    }

    var scholiumReduceTransparency: Bool {
        scholiumVisualEnvironmentOverride.reduceTransparency
            ?? accessibilityReduceTransparency
    }

    var scholiumReduceMotion: Bool {
        scholiumVisualEnvironmentOverride.reduceMotion
            ?? accessibilityReduceMotion
    }

    var scholiumAppearsActive: Bool {
        scholiumVisualEnvironmentOverride.appearsActive ?? appearsActive
    }
}

struct ScholiumDocumentContentInsets: Equatable, Sendable {
    let inline: CGFloat
    let trailingViewportFraction: CGFloat
}

/// Provisional values shared by Read and editor renderers. They remain
/// renderer-aware until the visual comparison freezes the rhythm contract.
enum ScholiumDocumentRhythm {
    static let proseFontSizePoints = 12
    static let sourceFontSizePixels = 15
    static let heading1ScalePercent = 187.5
    static let heading2ScalePercent = 130
    static let heading3ScalePercent = 115
    static let heading4ScalePercent = 100
    static let narrowWidthThresholdRootEms = ScholiumGrid.Document.narrowWidthThresholdRootEms
    static let proseLineHeight = 1.5
    static let sourceLineHeight = 1.5
    static let paragraphGapCSSPixels = ScholiumGrid.Document.paragraphGapCSSPixels
    static let headingLineHeight = 1.18
    static let headingGapBeforeCSSPixels = ScholiumGrid.Document.headingGapBeforeCSSPixels
    static let headingGapAfterCSSPixels = ScholiumGrid.Document.headingGapAfterCSSPixels
    static let codeBlockInset: CGFloat = 16
    static let quoteInlineInset = ScholiumGrid.Spacing.sectionSeparation

    static func contentInsets(
        for renderer: ScholiumDocumentRenderer,
        widthClass: ScholiumDocumentWidthClass
    ) -> ScholiumDocumentContentInsets {
        let inline: CGFloat = switch (renderer, widthClass) {
        case (.source, .regular): ScholiumGrid.Spacing.sourceShellInsetCSSPixels
        case (.read, .regular), (.livePreview, .regular):
            ScholiumGrid.Spacing.documentShellInsetCSSPixels
        case (_, .narrow): ScholiumGrid.Document.compactShellInsetCSSPixels
        }
        return .init(
            inline: inline,
            trailingViewportFraction: ScholiumGrid.Document.trailingScrollViewportFraction
        )
    }
}

private struct ScholiumSurfaceModifier: ViewModifier {
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumSurfaceRole

    func body(content: Content) -> some View {
        content.background {
            Rectangle().fill(role.colorRole.color(
                increasedContrast: increasedContrast
            ))
        }
    }
}

private struct ScholiumElevationModifier: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumAppearsActive) private var appearsActive
    let role: ScholiumElevationRole

    func body(content: Content) -> some View {
        let style = role.style(
            reduceTransparency: reduceTransparency,
            appearsActive: appearsActive
        )
        content.shadow(
            color: Color(nsColor: .shadowColor).opacity(style.opacity),
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}

private struct ScholiumBoundaryModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumBoundaryRole
    let shape: S

    func body(content: Content) -> some View {
        let style = role.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency
        )
        content.overlay {
            shape.strokeBorder(
                style.colorRole.color(
                    increasedContrast: increasedContrast
                ).opacity(style.opacity),
                lineWidth: style.lineWidth
            )
            .allowsHitTesting(false)
        }
    }
}

private struct ScholiumEditorialSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumSurfaceRole
    let boundary: ScholiumBoundaryRole
    let elevation: ScholiumElevationRole?
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let boundaryStyle = boundary.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency
        )
        let surfacedContent = content
            .background(
                role.colorRole.color(
                    increasedContrast: increasedContrast
                ),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    boundaryStyle.colorRole.color(
                        increasedContrast: increasedContrast
                    ).opacity(boundaryStyle.opacity),
                    lineWidth: boundaryStyle.lineWidth
                )
                .allowsHitTesting(false)
            }
        if let elevation {
            surfacedContent.scholiumElevation(elevation)
        } else {
            surfacedContent
        }
    }
}

private struct ScholiumForegroundModifier: ViewModifier {
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumColorRole

    func body(content: Content) -> some View {
        content.foregroundStyle(role.color(
            increasedContrast: increasedContrast
        ))
    }
}

/// A borderless Scholium icon control for permanent workspace commands,
/// including custom content hosted by the native macOS toolbar. It retains
/// pointer, keyboard, focus, help, and accessibility activation while
/// expressing hover/focus with ink alone.
struct ScholiumInkIconControl: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    let title: String
    let systemImage: String
    let identifier: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(
                    width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    height: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
                .foregroundStyle(
                    isActive || isHovering || isFocused
                        ? ScholiumColorRole.primaryText.color
                        : ScholiumColorRole.secondaryText.color
                )
                .opacity(isEnabled ? 1 : 0.42)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ScholiumColorRole.accent.color)
                        .frame(height: 1)
                        .opacity(isEnabled && (isHovering || isFocused) ? 0.72 : 0)
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

enum ScholiumMotion {
    static func documentReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.36)
    }

    static func searchPresentation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    static func searchExpansion(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }

    static func disclosure(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func sidebarAttentionPresentation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static func transientStatus(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }
}

extension View {
    func scholiumForeground(_ role: ScholiumColorRole) -> some View {
        modifier(ScholiumForegroundModifier(role: role))
    }

    func scholiumSurface(_ role: ScholiumSurfaceRole) -> some View {
        modifier(ScholiumSurfaceModifier(role: role))
    }

    func scholiumElevation(_ role: ScholiumElevationRole) -> some View {
        modifier(ScholiumElevationModifier(role: role))
    }

    func scholiumBoundary<S: InsettableShape>(
        _ role: ScholiumBoundaryRole,
        in shape: S
    ) -> some View {
        modifier(ScholiumBoundaryModifier(role: role, shape: shape))
    }

    func scholiumEditorialSurface<S: InsettableShape>(
        _ role: ScholiumSurfaceRole,
        in shape: S,
        boundary: ScholiumBoundaryRole? = nil,
        elevation: ScholiumElevationRole? = nil
    ) -> some View {
        modifier(ScholiumEditorialSurfaceModifier(
            role: role,
            boundary: boundary ?? role.defaultBoundaryRole,
            elevation: elevation ?? role.defaultElevationRole,
            shape: shape
        ))
    }
}

private extension String {
    var kebabCased: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append("-")
            }
            result.append(String(scalar).lowercased())
        }
    }
}
