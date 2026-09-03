import AppKit
import Foundation
import ScholiumContracts
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
    case comparisonRemoval
    case comparisonInsertion
    case comparisonRemovalBackground
    case comparisonInsertionBackground

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
            Self.rgb(
                resolvedRGBValue(
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
        let palette: ScholiumResolvedColorPalette =
            switch (isDark, increasedContrast) {
            case (false, false): Self.lightPalette
            case (false, true): Self.increasedContrastLightPalette
            case (true, false): Self.darkPalette
            case (true, true): Self.increasedContrastDarkPalette
            }
        return palette[self]
    }

    private static let resolver = ScholiumColorResolver(variables: .editorialCopper)
    private static let lightPalette = resolver.resolve(isDark: false, increasedContrast: false)
    private static let increasedContrastLightPalette = resolver.resolve(
        isDark: false, increasedContrast: true)
    private static let darkPalette = resolver.resolve(isDark: true, increasedContrast: false)
    private static let increasedContrastDarkPalette = resolver.resolve(
        isDark: true, increasedContrast: true)

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// System-owned colors used for effects whose appearance is defined by
/// AppKit rather than by Scholium's configurable editorial palette. Keeping
/// these exceptions named prevents feature views from reaching into AppKit's
/// color catalog directly or treating them as additional product Variables.
enum ScholiumNativeColorRole: Sendable {
    case searchMatchHighlight
    case structuralShadow

    var nsColor: NSColor {
        switch self {
        case .searchMatchHighlight: .findHighlightColor
        case .structuralShadow: .shadowColor
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
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
    let comparisonRemoval: UInt32
    let comparisonInsertion: UInt32
    let comparisonRemovalBackground: UInt32
    let comparisonInsertionBackground: UInt32

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
        case .comparisonRemoval: comparisonRemoval
        case .comparisonInsertion: comparisonInsertion
        case .comparisonRemovalBackground: comparisonRemovalBackground
        case .comparisonInsertionBackground: comparisonInsertionBackground
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
        let documentBackground =
            isDark
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
        let comparisonBackgroundLightness = isDark
            ? (increasedContrast ? 0.43 : 0.35)
            : (increasedContrast ? 0.86 : 0.91)
        let comparisonBackgroundChroma = increasedContrast ? 0.065 : 0.045
        let comparisonRemovalBackground = Self.tone(
            Self.oklch(from: FunctionalAnchor.destructive),
            lightness: comparisonBackgroundLightness,
            chromaLimit: comparisonBackgroundChroma
        )
        let comparisonInsertionBackground = Self.tone(
            Self.oklch(from: FunctionalAnchor.confirmed),
            lightness: comparisonBackgroundLightness,
            chromaLimit: comparisonBackgroundChroma
        )
        let semanticStart =
            isDark
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

        func comparisonForeground(
            _ anchor: UInt32,
            background: UInt32
        ) -> UInt32 {
            Self.contrastColor(
                Self.oklch(from: anchor),
                startingLightness: semanticStart,
                chromaLimit: increasedContrast ? 0.13 : 0.10,
                backgrounds: [background],
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
            comparisonRemoval: comparisonForeground(
                FunctionalAnchor.destructive,
                background: comparisonRemovalBackground
            ),
            comparisonInsertion: comparisonForeground(
                FunctionalAnchor.confirmed,
                background: comparisonInsertionBackground
            ),
            comparisonRemovalBackground: comparisonRemovalBackground,
            comparisonInsertionBackground: comparisonInsertionBackground
        )
    }

    private enum FunctionalAnchor {
        static let information: UInt32 = 0x466C82
        static let attention: UInt32 = 0xA16E2C
        static let destructive: UInt32 = 0xA34A43
        static let confirmed: UInt32 = 0x4D755A
        static let agentAuthorship: UInt32 = 0x665C82
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
        rgbValue(
            from: OKLCH(
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
            channels = sRGBChannels(
                from: OKLCH(
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

/// Contract names used by the CodeMirror and sanitized Read stylesheets.
/// Custom properties transport resolved semantic roles into WebKit; they are
/// not a second set of configurable color Variables.
enum ScholiumWebDesignTokens {
    /// Fixed document-markup colors are not Appearance inputs and do not
    /// participate in the Accent/Paper resolver. They are shared verbatim by
    /// Review and Edit so Markdown semantics cannot drift by mode or theme.
    static let fixedDocumentSyntaxCSSDeclarations = """
        --scholium-mark-highlight-background: #ff9a00;
        --scholium-mark-highlight-text: #28241d;
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
        return """
            --scholium-document-line-width: \(number(defaults.lineWidthCharacterUnits))ch;
            --scholium-document-half-line-width: \(number(defaults.lineWidthCharacterUnits / 2))ch;
            --scholium-document-prose-font-size: \(number(body.fontSizePoints))pt;
            --scholium-document-source-font-size: \(ScholiumDocumentRhythm.sourceFontSizePixels)px;
            --scholium-document-title-size: 180%;
            --scholium-document-title-line-height: 1.15;
            --scholium-document-title-after: 0.65em;
            --scholium-document-h1-size: \(number(headings.level1.scale * 100))%;
            --scholium-document-h2-size: \(number(headings.level2.scale * 100))%;
            --scholium-document-h3-size: \(number(headings.level2.scale * 100))%;
            --scholium-document-h4-size: \(number(headings.level2.scale * 100))%;
            --scholium-rhythm-prose-line-height: \(number(body.lineHeight));
            --scholium-rhythm-source-line-height: \(ScholiumDocumentRhythm.sourceLineHeight);
            --scholium-document-text-scale-factor: 1;
            --scholium-rhythm-paragraph-gap: \(number(
                body.paragraphSpacingEm * body.fontSizePoints * (96 / 72)
            ))px;
            --scholium-rhythm-heading-line-height: \(number(headings.lineHeight));
            \(DocumentAppearanceStyles.headingTransportDeclarations(for: defaults))
            --scholium-appearance-h1-before: \(number(headings.level1.spaceBeforeEm))em;
            --scholium-appearance-h1-after: \(number(headings.level1.spaceAfterEm))em;
            --scholium-appearance-lower-heading-before: \(number(headings.level2.spaceBeforeEm))em;
            --scholium-appearance-lower-heading-after: \(number(headings.level2.spaceAfterEm))em;
            --scholium-rhythm-code-inset: \(ScholiumDocumentRhythm.codeBlockInset)px;
            --scholium-rhythm-quote-inset: \(ScholiumDocumentRhythm.quoteInlineInset)px;
            --scholium-rhythm-semantic-block-gap: 1em;
            --scholium-rhythm-rule-block-gap: 0.5em;
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
        return ScholiumColorRole.allCases.map { role in
            let value = String(format: "#%06x", palette[role])
            return "\(role.cssVariableName): \(value);"
        }.joined(separator: "\n")
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
          \(fixedDocumentSyntaxCSSDeclarations)
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
          font-size: calc(
            var(--scholium-document-prose-font-size)
            * var(--scholium-document-text-scale-factor)
          );
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
          overflow-wrap: anywhere;
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
        .cm-editor.scholium-live-mode .cm-live-codeblock-active.cm-live-codeblock-end {
          /* The visible closing fence is already the active block's final source
             line. Do not synthesize a blank-looking inset below those exact bytes. */
          padding-block-end: 0;
        }
        .cm-editor.scholium-live-mode .cm-live-raw-html-end {
          padding-block-end: var(--scholium-rhythm-code-inset);
          border-end-start-radius: var(--scholium-corner-document-code-block);
          border-end-end-radius: var(--scholium-corner-document-code-block);
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
          color: var(--scholium-mark-highlight-text);
          background: var(--scholium-mark-highlight-background);
          border-radius: var(--scholium-corner-document-mark-highlight);
        }
        .scholium-document :not(pre) > code,
        .scholium-live-mode .cm-live-code {
          padding: 0.08em 0.25em;
          border-radius: var(--scholium-corner-document-inline-code);
          background: color-mix(in srgb, var(--scholium-color-primary-text) 8%, transparent);
          font-family: "Victor Mono", ui-monospace, "SFMono-Regular", Menlo, monospace;
          font-size: 0.82em;
        }
        .scholium-document a:not(.wiki-link),
        .scholium-live-mode .cm-live-link {
          color: var(--scholium-color-accent);
          text-decoration: underline;
          text-decoration-color: color-mix(in srgb, var(--scholium-color-accent) 42%, transparent);
          text-underline-offset: 0.15em;
        }
        .scholium-document .wiki-link,
        .scholium-live-mode .cm-live-wiki-link {
          color: var(--scholium-color-accent);
          line-height: 1.2;
          text-decoration: none;
        }
        .scholium-document h1,
        .scholium-document h2,
        .scholium-document h3,
        .scholium-document h4,
        .scholium-document h5,
        .scholium-document h6,
        .scholium-live-mode .cm-live-heading {
          font-family: var(--scholium-document-heading-font-family);
          font-style: var(--scholium-document-heading-font-style);
          font-variant-caps: var(--scholium-document-heading-font-variant-caps);
          font-weight: var(--scholium-document-heading-weight);
          line-height: var(--scholium-rhythm-heading-line-height);
          letter-spacing: var(--scholium-document-heading-letter-spacing);
          text-align: start;
          text-decoration-line: none;
          text-decoration: none;
          text-wrap: balance;
          box-sizing: border-box;
          margin: 0;
          padding-block: var(--scholium-appearance-lower-heading-before) var(--scholium-appearance-lower-heading-after);
        }
        .scholium-document h1,
        .scholium-live-mode .cm-live-h1 {
          font-size: var(--scholium-document-h1-size);
          font-weight: var(--scholium-document-heading-weight);
          padding-block: var(--scholium-appearance-h1-before) var(--scholium-appearance-h1-after);
        }
        .scholium-document h2,
        .scholium-live-mode .cm-live-h2 {
          font-size: var(--scholium-document-h2-size);
          padding-block: var(--scholium-appearance-lower-heading-before) var(--scholium-appearance-lower-heading-after);
        }
        .scholium-document h3,
        .scholium-live-mode .cm-live-h3 {
          font-size: var(--scholium-document-h3-size);
          padding-block: var(--scholium-appearance-lower-heading-before) var(--scholium-appearance-lower-heading-after);
        }
        .scholium-document h4,
        .scholium-document h5,
        .scholium-document h6,
        .scholium-live-mode .cm-live-h4,
        .scholium-live-mode .cm-live-h5,
        .scholium-live-mode .cm-live-h6 {
          font-size: var(--scholium-document-h4-size);
          padding-block: var(--scholium-appearance-lower-heading-before) var(--scholium-appearance-lower-heading-after);
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
          color: var(--scholium-color-accent);
          font-weight: 650;
          padding: 0.75rem 0.9rem;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-document-embedded-note);
          text-decoration: none;
        }
        .scholium-selection-actions {
          --scholium-selection-glyph-size: 16px;
          position: fixed;
          z-index: 110;
          box-sizing: border-box;
          padding: 4px;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-floating-selection-control);
          color: var(--scholium-color-primary-text);
          background: var(--scholium-color-surface-background);
          box-shadow: var(--scholium-elevation-floating-control);
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          line-height: 1;
        }
        .scholium-selection-actions[hidden] {
          display: none;
        }
        .scholium-selection-toolbar {
          display: flex;
          align-items: center;
          gap: 1px;
        }
        .scholium-selection-control {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 3px;
          box-sizing: border-box;
          min-width: 28px;
          min-height: 28px;
          padding: 3px 6px;
          border: 0;
          border-radius: var(--scholium-corner-document-control);
          color: inherit;
          background: transparent;
          font: inherit;
          cursor: default;
        }
        .scholium-selection-control:hover,
        .scholium-selection-menu-item:hover,
        .scholium-selection-control:active,
        .scholium-selection-menu-item:active {
          color: var(--scholium-color-primary-text);
          background: var(--scholium-content-hover-surface);
        }
        .scholium-selection-control:focus,
        .scholium-selection-menu-item:focus,
        .scholium-selection-control.scholium-selection-keyboard-focus,
        .scholium-selection-menu-item.scholium-selection-keyboard-focus {
          color: var(--scholium-color-primary-text);
          background: var(--scholium-content-keyboard-focus-surface);
        }
        .scholium-selection-control:focus-visible,
        .scholium-selection-menu-item:focus-visible {
          color: var(--scholium-color-primary-text);
          background: var(--scholium-content-keyboard-focus-surface);
          outline: 2px solid var(--scholium-content-focus-ring);
          outline-offset: 1px;
        }
        .scholium-selection-control.scholium-selection-keyboard-focus,
        .scholium-selection-menu-item.scholium-selection-keyboard-focus {
          outline: 2px solid var(--scholium-content-focus-ring);
          outline-offset: 1px;
        }
        .scholium-selection-symbol {
          inline-size: var(--scholium-selection-glyph-size);
          block-size: var(--scholium-selection-glyph-size);
        }
        .scholium-selection-icon-style {
          inline-size: 18px;
        }
        .scholium-selection-chevron {
          inline-size: 10px;
          block-size: 10px;
        }
        .scholium-selection-highlight-icon,
        .scholium-selection-link-icon,
        .scholium-selection-more-icon {
          inline-size: var(--scholium-selection-glyph-size);
          block-size: var(--scholium-selection-glyph-size);
        }
        .scholium-selection-menu-symbol {
          inline-size: 14px;
          block-size: 14px;
        }
        .scholium-selection-label,
        .scholium-selection-menu-label {
          font-size: 12px;
          line-height: 16px;
          letter-spacing: -0.01em;
          white-space: nowrap;
        }
        .scholium-selection-style-trigger {
          padding-inline: 6px 4px;
        }
        .scholium-selection-wiki-group {
          display: inline-flex;
          align-items: center;
          gap: 0;
        }
        .scholium-selection-wiki-primary {
          min-width: 0;
          padding-inline: 7px 3px;
          border-start-end-radius: var(--scholium-corner-selection-split-control);
          border-end-end-radius: var(--scholium-corner-selection-split-control);
        }
        .scholium-selection-wiki-menu-trigger {
          min-width: 22px;
          padding-inline: 2px 5px;
          border-start-start-radius: var(--scholium-corner-selection-split-control);
          border-end-start-radius: var(--scholium-corner-selection-split-control);
        }
        .scholium-selection-separator {
          inline-size: 1px;
          block-size: 18px;
          margin-inline: 2px;
          background: var(--scholium-color-separator);
        }
        .scholium-selection-menu {
          position: fixed;
          z-index: 112;
          box-sizing: border-box;
          inline-size: max-content;
          max-inline-size: calc(100vw - 16px);
          max-block-size: calc(100vh - 16px);
          padding: 4px;
          overflow: auto;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-bounded-panel);
          color: var(--scholium-color-primary-text);
          background: var(--scholium-color-surface-background);
          box-shadow: var(--scholium-elevation-bounded-panel);
        }
        .scholium-selection-menu[hidden] {
          display: none;
        }
        .scholium-selection-menu-item {
          display: flex;
          align-items: center;
          justify-content: flex-start;
          gap: 6px;
          box-sizing: border-box;
          inline-size: 100%;
          min-block-size: 28px;
          padding: 4px 8px;
          border: 0;
          border-radius: var(--scholium-corner-document-control);
          color: inherit;
          background: transparent;
          font: inherit;
          text-align: start;
          cursor: default;
        }
        .scholium-selection-menu-check {
          inline-size: 12px;
          block-size: 12px;
          color: transparent;
        }
        .scholium-selection-menu-check-active {
          color: currentColor;
        }
        .scholium-selection-submenu-trigger {
          justify-content: space-between;
        }
        .scholium-selection-menu-leading {
          display: inline-flex;
          align-items: center;
          gap: 6px;
        }
        .scholium-selection-submenu-chevron {
          inline-size: 12px;
          block-size: 12px;
          transform: rotate(-90deg);
        }
        .scholium-selection-compact-only {
          display: none;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions {
          z-index: 112;
          box-sizing: border-box;
          min-inline-size: 220px;
          inline-size: max-content;
          max-inline-size: min(360px, calc(100vw - 16px));
          padding: 4px;
          overflow: hidden;
          border: 1px solid var(--scholium-color-separator);
          border-radius: var(--scholium-corner-bounded-panel);
          color: var(--scholium-color-primary-text);
          background: var(--scholium-color-surface-background);
          box-shadow: var(--scholium-elevation-bounded-panel);
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          font-size: 12px;
          line-height: 16px;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions > ul {
          min-inline-size: 0;
          max-block-size: min(200px, calc(100vh - 24px));
          margin: 0;
          padding: 0;
          border: 0;
          font-family: inherit;
          font-size: inherit;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions > ul > li {
          display: flex;
          align-items: center;
          gap: 6px;
          box-sizing: border-box;
          min-block-size: 28px;
          max-inline-size: 352px;
          padding: 4px 8px;
          overflow: hidden;
          border-radius: var(--scholium-corner-document-control);
          color: inherit;
          background: transparent;
          white-space: nowrap;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions > ul > li:hover {
          color: var(--scholium-color-primary-text);
          background: var(--scholium-content-hover-surface);
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions > ul > li[aria-selected="true"] {
          color: var(--scholium-color-primary-text);
          background: var(--scholium-color-raised-surface-background);
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions .scholium-completion-symbol {
          flex: 0 0 14px;
          inline-size: 14px;
          block-size: 14px;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions .cm-completionLabel {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions .cm-completionMatchedText {
          color: inherit;
          font-weight: 600;
          text-decoration: none;
        }
        .cm-tooltip-autocomplete.scholium-editor-suggestions .cm-completionDetail {
          min-inline-size: 0;
          max-inline-size: 168px;
          margin-inline-start: auto;
          overflow: hidden;
          color: var(--scholium-color-secondary-text);
          font-size: 11px;
          font-style: normal;
          text-overflow: ellipsis;
          unicode-bidi: plaintext;
        }
        @media (max-width: 520px) {
          .scholium-selection-wide-only {
            display: none;
          }
          .scholium-selection-menu-item.scholium-selection-compact-only {
            display: flex;
          }
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
          .scholium-selection-actions,
          .scholium-selection-menu,
          .cm-tooltip-autocomplete.scholium-editor-suggestions { border-width: 2px; }
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
        static let accessibilityHierarchyRowHeight = foundationUnit * 11
        static let documentTabStripHeight = foundationUnit * 10
        static let regionHeaderHeight = foundationUnit * 12
        static let iconTrackWidth = foundationUnit * 4
    }

    enum Document {
        static let narrowWidthThresholdRootEms: CGFloat = 44
        static let compactShellInsetCSSPixels = Spacing.regionContentInset
        static let contentTopInsetCSSPixels = Spacing.documentShellInsetCSSPixels
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
        static let firstSectionGap = foundationUnit * 4
        static let sectionGap = foundationUnit * 4
        static let connectionDirectionControlMaximumWidth = foundationUnit * 60
        static let connectionGroupContentGap = foundationUnit * 2
        static let headingToContentGap = foundationUnit * 2.5
        static let contentRowGap = foundationUnit * 2
        static let contentLineSpacing = foundationUnit
        static let iconColumnWidth = foundationUnit * 4
        static let iconToTextGap = foundationUnit * 2
        static let connectionOccurrenceGap = foundationUnit * 3
        static let connectionOccurrenceVerticalInset = foundationUnit
        static let connectionOccurrenceMinimumHeight = Dimension.preferredCustomTarget
        static let actionRowVerticalInset = foundationUnit * 2
        static let actionRowMinimumHeight = foundationUnit * 11
        static let actionCopyGap = foundationUnit
        static let factGridMinimumWidth = foundationUnit * 51
        static let factLabelMinimumWidth = foundationUnit * 19.5
        static let factColumnGap = foundationUnit * 3.5
        static let factValueMinimumWidth =
            factGridMinimumWidth
            - factLabelMinimumWidth
            - factColumnGap
        static let longTextLabelGap = foundationUnit
        static let longTextIndent = foundationUnit * 3
        static let readingBlockGap = foundationUnit * 2
        static let bottomInset = contentInset
    }

    enum SegmentedControl {
        static let trackInset = Spacing.opticalAlignmentAdjustment
        static let segmentGap = Spacing.opticalAlignmentAdjustment
        static let regularSegmentMinimumHeight = Dimension.preferredCustomTarget
        static let compactSegmentMinimumHeight = Dimension.compactHierarchyRowHeight
        static let regularHorizontalInset = Spacing.nestedContentInset
        static let compactHorizontalInset = Spacing.inlineControlGap
    }

    /// The separate Records window owns a quiet collection-to-reading
    /// transition. A fixed index keeps navigation stable while the reading
    /// plane and step-local attachment strips own their scrolling axes.
    enum ResearchRecords {
        static let windowDragInset = foundationUnit * 8
        static let collectionWidth = foundationUnit * 72
        static let collectionRowVerticalInset = foundationUnit * 2
        static let collectionRowSpacing = foundationUnit
        static let readingMeasure = foundationUnit * 180
        static let readingHorizontalInset = foundationUnit * 8
        static let readingVerticalInset = foundationUnit * 8
        static let stepVerticalInset = foundationUnit * 6
        static let stepHeaderSpacing = foundationUnit
        static let referenceSectionSpacing = foundationUnit * 2
    }

    /// Page- and pane-level state copy shares one readable measure. Placement
    /// and density adapt to the owning region without changing the state's
    /// workflow meaning or lifecycle.
    enum ContentState {
        static let readableWidth = foundationUnit * 90
    }

    /// Research Guidance owns one settings-specific collection-row rhythm.
    /// Native Lists and controls retain their own geometry; these values apply
    /// only to the explanatory content/action rows inside the guidance pages.
    enum ResearchGuidance {
        static let titleDetailGap = foundationUnit * 1.5
        static let collectionRowColumnGap = foundationUnit * 3.5
        static let collectionRowVerticalInset = foundationUnit * 2.5
    }

    /// Research-facing sheets share one continuous editorial frame while
    /// their fields, operations, and lifecycle remain workflow-owned.
    enum ResearchSheet {
        static let headerDetailGap = Spacing.labelAccessoryGap
        static let bodySectionGap = Spacing.sectionSeparation
        static let footerControlGap = Spacing.inlineControlGap
        static let statusVerticalInset = foundationUnit * 2.5
    }
}

enum ScholiumMetrics {
    enum Accessibility {
        static let preferredCustomTarget = ScholiumGrid.Dimension.preferredCustomTarget
        static let minimumCustomTarget = ScholiumGrid.Dimension.minimumCustomTarget
    }

    enum SegmentedControl {
        static let trackInset = ScholiumGrid.SegmentedControl.trackInset
        static let segmentSpacing = ScholiumGrid.SegmentedControl.segmentGap
        static let regularSegmentMinimumHeight =
            ScholiumGrid.SegmentedControl.regularSegmentMinimumHeight
        static let compactSegmentMinimumHeight =
            ScholiumGrid.SegmentedControl.compactSegmentMinimumHeight
        static let regularHorizontalInset =
            ScholiumGrid.SegmentedControl.regularHorizontalInset
        static let compactHorizontalInset =
            ScholiumGrid.SegmentedControl.compactHorizontalInset
    }

    enum Onboarding {
        static let preferredWidth: CGFloat = 760
        static let preferredHeight: CGFloat = 740
        static let rootSectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let rootDisclosureSpacing = ScholiumGrid.foundationUnit * 1.5
        static let rootContentInset = ScholiumGrid.foundationUnit * 7
        static let statusHorizontalInset = ScholiumGrid.foundationUnit * 6
        static let statusBottomInset = ScholiumGrid.foundationUnit * 15.5
        static let footerHorizontalInset = ScholiumGrid.foundationUnit * 6
        static let footerVerticalInset = ScholiumGrid.foundationUnit * 3.5
        static let stepHorizontalInset = ScholiumGrid.foundationUnit * 8
        static let stepTopInset = ScholiumGrid.foundationUnit * 17
        static let stepBottomInset = ScholiumGrid.foundationUnit * 22
        static let headingDetailSpacing = ScholiumGrid.foundationUnit * 1.5
        static let statementLineSpacing = ScholiumGrid.foundationUnit * 0.75
        static let welcomeStatementTopSpacing = ScholiumGrid.foundationUnit * 4.5
        static let welcomeRuleVerticalInset = ScholiumGrid.foundationUnit * 6
        static let welcomeClosingTopSpacing = ScholiumGrid.foundationUnit * 5.5
        static let decisionRowSpacing = ScholiumGrid.foundationUnit * 3.5
        static let decisionDetailSpacing = ScholiumGrid.foundationUnit * 1.25
        static let decisionActionMinimumSpacing = ScholiumGrid.Spacing.inlineControlGap
        static let formSectionSpacing = ScholiumGrid.foundationUnit * 6
        static let formFieldSpacing = ScholiumGrid.foundationUnit * 3.5
        static let formTitleActionSpacing = ScholiumGrid.foundationUnit * 2.5
        static let reviewSectionSpacing = ScholiumGrid.foundationUnit * 5.5
        static let folderSummarySpacing = ScholiumGrid.foundationUnit * 2.5
        static let folderSummaryVerticalInset = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let statusTitleDetailSpacing = ScholiumGrid.foundationUnit * 0.75
        static let readySectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let readyStatusVerticalInset = ScholiumGrid.foundationUnit * 3.5
        static let agentStatusSpacing = ScholiumGrid.foundationUnit * 1.5
        static let agentDetailSpacing = ScholiumGrid.foundationUnit * 1.25
        static let agentTaskSpacing = ScholiumGrid.foundationUnit * 2.5
        static let agentTaskContentSpacing = ScholiumGrid.foundationUnit * 2.25
        static let agentContentTopInset = ScholiumGrid.foundationUnit * 14.5
        static let agentPromptHeaderHorizontalInset = ScholiumGrid.foundationUnit * 5.5
        static let agentPromptBodyInset = ScholiumGrid.foundationUnit * 6
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
        static let refreshStatusSpacing = ScholiumGrid.foundationUnit * 1.75
        static let refreshStatusHorizontalInset = ScholiumGrid.foundationUnit * 2.5
        static let refreshStatusVerticalInset = ScholiumGrid.foundationUnit * 1.5
        static let refreshStatusOuterInset = ScholiumGrid.foundationUnit * 2.5
        static let loadingOverlayInset = ScholiumGrid.foundationUnit * 7
        static let compactNoticeHorizontalInset = ScholiumGrid.foundationUnit * 4.5
        static let compactNoticeVerticalInset = ScholiumGrid.foundationUnit * 2.5
    }

    enum ResearchGuidance {
        static let titleDetailSpacing = ScholiumGrid.ResearchGuidance.titleDetailGap
        static let collectionRowColumnSpacing =
            ScholiumGrid.ResearchGuidance.collectionRowColumnGap
        static let collectionRowVerticalInset =
            ScholiumGrid.ResearchGuidance.collectionRowVerticalInset
        static let summarySpacing = ScholiumGrid.foundationUnit * 2.5
        static let editorSectionSpacing = ScholiumGrid.foundationUnit * 3.5
        static let editorMajorSectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let controlSpacing = ScholiumGrid.foundationUnit * 1.5
        static let trailingControlMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
        static let editorContentInset = ScholiumGrid.foundationUnit * 4.5
    }

    enum ResearchRecords {
        static let windowDragInset = ScholiumGrid.ResearchRecords.windowDragInset
        static let collectionWidth = ScholiumGrid.ResearchRecords.collectionWidth
        static let collectionRowVerticalInset =
            ScholiumGrid.ResearchRecords.collectionRowVerticalInset
        static let collectionRowSpacing = ScholiumGrid.ResearchRecords.collectionRowSpacing
        static let readingMeasure = ScholiumGrid.ResearchRecords.readingMeasure
        static let readingHorizontalInset = ScholiumGrid.ResearchRecords.readingHorizontalInset
        static let readingVerticalInset = ScholiumGrid.ResearchRecords.readingVerticalInset
        static let stepVerticalInset = ScholiumGrid.ResearchRecords.stepVerticalInset
        static let stepHeaderSpacing = ScholiumGrid.ResearchRecords.stepHeaderSpacing
        static let referenceSectionSpacing = ScholiumGrid.ResearchRecords.referenceSectionSpacing
    }

    enum ResearchSheet {
        static let contentInset = ScholiumGrid.Spacing.regionContentInset
        static let headerDetailSpacing = ScholiumGrid.ResearchSheet.headerDetailGap
        static let bodySectionSpacing = ScholiumGrid.ResearchSheet.bodySectionGap
        static let footerControlSpacing = ScholiumGrid.ResearchSheet.footerControlGap
        static let statusVerticalInset = ScholiumGrid.ResearchSheet.statusVerticalInset
        static let fieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let fieldGroupSpacing = ScholiumGrid.foundationUnit * 3.5
        static let fieldDetailSpacing = ScholiumGrid.foundationUnit * 0.75
        static let textEditorInset = ScholiumGrid.foundationUnit * 1.5

        enum Action {
            static let minimumWidth: CGFloat = 520
            static let idealWidth: CGFloat = 660
            static let compactMinimumHeight: CGFloat = 280
            static let compactIdealHeight: CGFloat = 320
            static let regularMinimumHeight: CGFloat = 340
            static let regularIdealHeight: CGFloat = 380
        }

        enum Comparison {
            static let minimumWidth: CGFloat = 760
            static let idealWidth: CGFloat = 900
            static let minimumHeight: CGFloat = 560
            static let idealHeight: CGFloat = 720
            static let detailPopoverWidth = ScholiumGrid.foundationUnit * 105
            static let disclosureIndicatorWidth = ScholiumGrid.foundationUnit * 3.5
            static let documentStateMinimumHeight = ScholiumGrid.foundationUnit * 40
        }

        enum SystemTrash {
            static let minimumWidth: CGFloat = 560
            static let idealWidth: CGFloat = 620
            static let minimumHeight: CGFloat = 440
            static let consequenceScrollMaximumHeight: CGFloat = 320
        }

        enum ReadingLeadNote {
            static let minimumWidth: CGFloat = 440
            static let idealWidth: CGFloat = 480
            static let maximumWidth: CGFloat = 620
            static let minimumHeight: CGFloat = 320
            static let idealHeight: CGFloat = 400
            static let maximumHeight: CGFloat = 640
        }
    }

    enum Properties {
        static let headerDetailSpacing = ScholiumGrid.foundationUnit * 0.75
        static let semanticGroupSeparation = ScholiumGrid.foundationUnit * 6
        static let fieldBlockSeparation = ScholiumGrid.Spacing.sectionSeparation
        static let creatorItemSeparation = ScholiumGrid.Spacing.sectionSeparation
        static let optionSpacing = ScholiumGrid.foundationUnit * 1.25
        static let fieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let labelSpacing = ScholiumGrid.foundationUnit * 1.25
        static let tagContentSpacing = ScholiumGrid.foundationUnit * 0.75
        static let tagVerticalInset = ScholiumGrid.foundationUnit * 0.75
        static let numberControlMaximumWidth = ScholiumGrid.foundationUnit * 50
        static let compactControlMaximumWidth = ScholiumGrid.foundationUnit * 60
    }

    enum Settings {
        static let sidebarWidth = ScholiumGrid.foundationUnit * 54
        static let sectionSpacing = ScholiumGrid.foundationUnit * 3.5
        static let columnSpacing = ScholiumGrid.foundationUnit * 6
        static let editorContentInset = ScholiumGrid.Spacing.regionContentInset
        static let headerMaximumWidth = ScholiumGrid.foundationUnit * 155
        static let formMaximumWidth = ScholiumGrid.foundationUnit * 165
        static let formExplanationMaximumWidth = ScholiumGrid.foundationUnit * 105
        static let appearancePickerWidth = ScholiumGrid.foundationUnit * 42
        static let listRowSpacing = ScholiumGrid.foundationUnit * 1.25
        static let rowControlSpacing = ScholiumGrid.foundationUnit * 1.5
        static let labelActionMinimumSpacing = ScholiumGrid.foundationUnit * 1.5
        static let explanationSpacing = ScholiumGrid.foundationUnit * 1.75
        static let fieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let rootSpacing = ScholiumGrid.foundationUnit * 2.5
        static let rowDetailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let rowStatusSpacing = ScholiumGrid.foundationUnit * 0.75
        static let rowActionMinimumSpacing = ScholiumGrid.Spacing.labelAccessoryGap
        static let rowVerticalInset = ScholiumGrid.foundationUnit * 0.75
        static let pathHorizontalInset = ScholiumGrid.foundationUnit * 6
        static let trailingControlMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
    }

    enum Critique {
        static let sectionSpacing = ScholiumGrid.foundationUnit * 2.25
        static let destinationMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
        static let headerSpacing = ScholiumGrid.foundationUnit * 1.75
        static let actionMinimumSpacing = ScholiumGrid.Spacing.inlineControlGap
        static let findingsSpacing = ScholiumGrid.foundationUnit * 1.75
        static let panelVerticalInset = ScholiumGrid.foundationUnit * 2.75
        static let detailSpacing = ScholiumGrid.foundationUnit * 0.5
    }

    enum DocumentWorkflow {
        static let sectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let sheetContentInset = ScholiumGrid.foundationUnit * 5.5
        static let identityContentInset = ScholiumGrid.foundationUnit * 6
        static let compactFieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let conflictHeaderDetailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let conflictHeaderInset = ScholiumGrid.foundationUnit * 4.5
        static let conflictRevisionSpacing = ScholiumGrid.foundationUnit * 6
        static let conflictRevisionHorizontalInset = ScholiumGrid.foundationUnit * 4.5
        static let conflictDiffRowVerticalInset = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let exactDiffColumnSpacing = ScholiumGrid.Spacing.inlineControlGap
        static let exactDiffLineNumberWidth: CGFloat = 38
        static let exactDiffMarkerWidth: CGFloat = 16
        static let conflictDetailSpacing = ScholiumGrid.foundationUnit * 0.75
        static let conflictDispositionSpacing = ScholiumGrid.foundationUnit * 1.75
        static let conflictDispositionDetailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let conflictActionMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
        static let conflictRowVerticalInset = ScholiumGrid.foundationUnit * 1.25
        static let recoverySectionSpacing = ScholiumGrid.foundationUnit * 1.75
        static let recoveryCompactSpacing = ScholiumGrid.foundationUnit * 1.5
        static let recoveryFileSpacing = ScholiumGrid.foundationUnit * 1.25
        static let recoveryRowVerticalInset = ScholiumGrid.foundationUnit * 1.25
    }

    enum Notice {
        static let contentSpacing = ScholiumGrid.foundationUnit * 2.5
        static let detailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let verticalInset = ScholiumGrid.foundationUnit * 2.5
        static let transientToastMaximumWidth = ScholiumGrid.foundationUnit * 105
        static let windowFeedbackMaximumWidth = ScholiumGrid.foundationUnit * 155
        static let settingsFeedbackMaximumWidth = ScholiumGrid.foundationUnit * 140
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
        /// Native outline rows remain uniform at accessibility text sizes so
        /// AppKit retains an exact scroll extent without clipping enlarged text.
        static let accessibilityHierarchyRowHeight =
            ScholiumGrid.Dimension.accessibilityHierarchyRowHeight
        static let rowHorizontalInset = ScholiumGrid.Spacing.nestedContentInset
        static let hierarchyIndent = ScholiumGrid.Dimension.iconTrackWidth
        static let selectionBoundaryWidth = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let workspaceNavigatorTopSpacing = ScholiumGrid.Spacing.nestedContentInset
        static let sectionSpacing = ScholiumGrid.Spacing.sectionSeparation
        /// Empty, loading, and error content begins one section step below the
        /// stable LibraryHeader while retaining the shared peripheral edge.
        static let sourceStateVerticalInset = ScholiumGrid.Spacing.sectionSeparation
    }

    enum Attention {
        /// Attention is intentionally a bounded, transient queue for a small
        /// number of urgent derived issues. Native popover chrome and arrow
        /// geometry remain system-owned.
        static let popoverWidth: CGFloat = 420
        static let popoverHeight: CGFloat = 480
    }

    enum ActivityNotificationStack {
        /// The exact count remains textual; these layers only make plurality
        /// visible before the researcher reads or focuses the control.
        static let visibleLayerLimit = 3
        static let collapsedLayerOffset = ScholiumGrid.foundationUnit
        static let horizontalScaleStep: CGFloat = 0.025
        static let maximumWidth: CGFloat = 520
        static let expandedMaximumHeight: CGFloat = 360
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
        /// AppKit's standard Inspector thickness is 270 points. Scholium keeps
        /// that readable lower bound while allowing the native split item to
        /// grow without an application-defined maximum.
        static let minimumReadableWidth: CGFloat = 270
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
        static let connectionDirectionControlMaximumWidth =
            ScholiumGrid.Apparatus.connectionDirectionControlMaximumWidth
        static let connectionGroupContentSpacing =
            ScholiumGrid.Apparatus.connectionGroupContentGap
        /// Internal section rhythm is deliberately separate from the spacing
        /// between complete sections.
        static let sectionContentSpacing = ScholiumGrid.Apparatus.headingToContentGap
        static let rowSpacing = ScholiumGrid.Apparatus.contentRowGap
        static let bodyLineSpacing = ScholiumGrid.Apparatus.contentLineSpacing
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
        static let connectionOccurrenceSpacing = ScholiumGrid.Apparatus.connectionOccurrenceGap
        static let connectionOccurrenceVerticalInset =
            ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset
        static let connectionOccurrenceMinimumHeight =
            ScholiumGrid.Apparatus.connectionOccurrenceMinimumHeight
        static let bottomInset = ScholiumGrid.Apparatus.bottomInset
    }

    enum ContentState {
        static let readableWidth = ScholiumGrid.ContentState.readableWidth
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
        static let explanationBottomInset = ScholiumGrid.foundationUnit * 1.5
        static let scopeBarVerticalInset = ScholiumGrid.foundationUnit * 1.5
        static let resultContentSpacing = ScholiumGrid.foundationUnit * 2.5
        static let diagnosticBottomInset = ScholiumGrid.foundationUnit * 1.75
        static let availabilityDetailSpacing = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let availabilityVerticalInset = ScholiumGrid.foundationUnit * 2.25
        static let savedSearchFieldSpacing = ScholiumGrid.foundationUnit * 1.5
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
            DocumentAppearanceSettings.defaultSettings.body.paragraphSpacingEm
                * DocumentAppearanceSettings.defaultSettings.body.fontSizePoints
                * (96 / 72)
                * textScale,
            Double(compactThresholdRootEms)
        )
    }
}

enum ScholiumCornerRole: CaseIterable, Hashable, Sendable {
    case inlineStatus
    case editorialControl
    case segmentedControl
    case workspaceNavigation
    case editorialPanel
    case loadingSurface
    case editorialTextEditor
    case searchOverlay
    case boundedPanel
    case documentCodeBlock
    case documentCalloutSurface
    case documentMarkHighlight
    case documentInlineCode
    case documentEmbeddedNote
    case floatingSelectionControl
    case documentControl
    case selectionSplitControl
    case calloutDisclosureFocus

    var radius: CGFloat {
        switch self {
        case .inlineStatus, .editorialControl, .workspaceNavigation,
             .boundedPanel,
             .documentCalloutSurface, .documentEmbeddedNote:
            8
        case .editorialPanel, .segmentedControl, .loadingSurface, .documentCodeBlock:
            10
        case .editorialTextEditor:
            6
        case .documentMarkHighlight, .calloutDisclosureFocus:
            2
        case .documentInlineCode, .selectionSplitControl:
            3
        case .documentControl:
            5
        case .floatingSelectionControl:
            9
        case .searchOverlay:
            12
        }
    }

    var cssVariableName: String? {
        switch self {
        case .inlineStatus:
            "--scholium-corner-inline-status"
        case .editorialTextEditor:
            "--scholium-corner-editorial-text-editor"
        case .boundedPanel:
            "--scholium-corner-bounded-panel"
        case .documentCodeBlock:
            "--scholium-corner-document-code-block"
        case .documentCalloutSurface:
            "--scholium-corner-document-callout-surface"
        case .documentMarkHighlight:
            "--scholium-corner-document-mark-highlight"
        case .documentInlineCode:
            "--scholium-corner-document-inline-code"
        case .documentEmbeddedNote:
            "--scholium-corner-document-embedded-note"
        case .floatingSelectionControl:
            "--scholium-corner-floating-selection-control"
        case .documentControl:
            "--scholium-corner-document-control"
        case .selectionSplitControl:
            "--scholium-corner-selection-split-control"
        case .calloutDisclosureFocus:
            "--scholium-corner-callout-disclosure-focus"
        case .editorialControl, .segmentedControl, .workspaceNavigation, .editorialPanel, .loadingSurface,
             .searchOverlay:
            nil
        }
    }
}

enum ScholiumShape {
    static let inlineStatusCornerRadius = ScholiumCornerRole.inlineStatus.radius
    static let editorialControlCornerRadius = ScholiumCornerRole.editorialControl.radius
    static let segmentedControlCornerRadius = ScholiumCornerRole.segmentedControl.radius
    static let workspaceNavigationCornerRadius = ScholiumCornerRole.workspaceNavigation.radius
    static let editorialPanelCornerRadius = ScholiumCornerRole.editorialPanel.radius
    static let loadingSurfaceCornerRadius = ScholiumCornerRole.loadingSurface.radius
    static let editorialTextEditorCornerRadius = ScholiumCornerRole.editorialTextEditor.radius
    static let searchOverlayCornerRadius = ScholiumCornerRole.searchOverlay.radius

    static let webCSSDeclarations = ScholiumCornerRole.allCases.compactMap { role in
        guard let name = role.cssVariableName else { return nil }
        let value = String(
            format: "%.4g",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(role.radius)
        )
        return "\(name): \(value)px;"
    }.joined(separator: "\n")
}

/// The shared shallow interaction surface for Scholium-owned controls inside
/// content regions. Hover uses one translucent semantic-ink veil so its
/// relative light/dark response follows the native toolbar on every underlying
/// plane, while keyboard focus retains a stronger raised blend. Native and
/// WebKit consumers share these exact semantic mixes while each component keeps
/// its own shape, geometry, focus, and lifecycle.
enum ScholiumContentInteractionSurface {
    private static let hoverOpacity: CGFloat = 0.05
    private static let increasedContrastHoverOpacity: CGFloat = 0.075
    private static let keyboardFocusOpacity: CGFloat = 0.42
    private static let increasedContrastKeyboardFocusOpacity: CGFloat = 0.56

    static let webCSSDeclarations = webCSSDeclarations(increasedContrast: false)
    static let increasedContrastWebCSSDeclarations = webCSSDeclarations(
        increasedContrast: true
    )

    static func opacity(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> CGFloat {
        if isFocused {
            return increasedContrast
                ? increasedContrastKeyboardFocusOpacity
                : keyboardFocusOpacity
        }
        if isHovering || isPressed {
            return increasedContrast
                ? increasedContrastHoverOpacity
                : hoverOpacity
        }
        return 0
    }

    static func color(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> Color {
        surfaceRole(isFocused: isFocused)
            .color(increasedContrast: increasedContrast)
            .opacity(
                opacity(
                    isHovering: isHovering,
                    isFocused: isFocused,
                    isPressed: isPressed,
                    increasedContrast: increasedContrast
                ))
    }

    /// Persistent local selection uses the same shallow editorial surface as
    /// transient hover and keyboard focus. It adds no Accent underline, glass,
    /// or filled segmented-control band.
    static func selectionColor(
        isSelected: Bool,
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> Color {
        if isSelected {
            return ScholiumColorRole.raisedSurfaceBackground
                .color(increasedContrast: increasedContrast)
        }
        return color(
            isHovering: isHovering,
            isFocused: isFocused,
            isPressed: isPressed,
            increasedContrast: increasedContrast
        )
    }

    static func nsColor(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> NSColor {
        surfaceRole(isFocused: isFocused)
            .nsColor(increasedContrast: increasedContrast)
            .withAlphaComponent(
                opacity(
                    isHovering: isHovering,
                    isFocused: isFocused,
                    isPressed: isPressed,
                    increasedContrast: increasedContrast
                ))
    }

    private static func surfaceRole(isFocused: Bool) -> ScholiumColorRole {
        isFocused ? .raisedSurfaceBackground : .primaryText
    }

    private static func webCSSDeclarations(increasedContrast: Bool) -> String {
        let hoverPercentage = cssPercentage(opacity(
            isHovering: true,
            isFocused: false,
            increasedContrast: increasedContrast
        ))
        let focusPercentage = cssPercentage(opacity(
            isHovering: false,
            isFocused: true,
            increasedContrast: increasedContrast
        ))
        return """
            --scholium-content-hover-surface: color-mix(
              in srgb,
              var(--scholium-color-primary-text) \(hoverPercentage)%,
              transparent
            );
            --scholium-content-keyboard-focus-surface: color-mix(
              in srgb,
              var(--scholium-color-raised-surface-background) \(focusPercentage)%,
              transparent
            );
            --scholium-content-focus-ring: var(--scholium-color-accent);
            """
    }

    private static func cssPercentage(_ opacity: CGFloat) -> String {
        String(
            format: "%.4g",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(opacity * 100)
        )
    }
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

/// Native-only depth recipes for structural relationships between Workspace
/// planes. These don't enter `ScholiumElevationRole.allCases`, because WebKit
/// document surfaces must not receive window-container presentation tokens.
enum ScholiumStructuralDepthRole: CaseIterable, Sendable {
    case documentNavigationBoundary

    /// The hidden one-point caster belongs to the dominant Document plane.
    /// Workspace navigation receives the shadow from its trailing edge.
    var castsFromTrailingEdge: Bool {
        true
    }

    func style(
        isDark: Bool,
        increasedContrast: Bool,
        reduceTransparency: Bool,
        appearsActive: Bool,
        layoutDirection: LayoutDirection
    ) -> ScholiumElevationStyle {
        let usesQuietOpacity = isDark || reduceTransparency || !appearsActive
        let logicalDirection: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return .init(
            opacity: increasedContrast ? 0 : (usesQuietOpacity ? 0.02 : 0.04),
            radius: 8,
            x: logicalDirection * (castsFromTrailingEdge ? -2 : 2),
            y: 0
        )
    }
}

enum ScholiumElevationRole: CaseIterable, Sendable {
    case floatingControl
    case boundedPanel
    case searchOverlay

    var cssVariableName: String {
        switch self {
        case .floatingControl: "--scholium-elevation-floating-control"
        case .boundedPanel: "--scholium-elevation-bounded-panel"
        case .searchOverlay: "--scholium-elevation-search-overlay"
        }
    }

    func style(
        increasedContrast: Bool,
        reduceTransparency: Bool,
        appearsActive: Bool
    ) -> ScholiumElevationStyle {
        let recipe: ScholiumElevationStyle =
            switch self {
            case .floatingControl:
                .init(opacity: 0.04, radius: 4, x: 0, y: 2)
            case .boundedPanel:
                .init(opacity: 0.08, radius: 8, x: 0, y: 4)
            case .searchOverlay:
                .init(opacity: 0.12, radius: 12, x: 0, y: 6)
            }
        let contrastMultiplier = increasedContrast ? 0.0 : 1.0
        let transparencyMultiplier = reduceTransparency ? 0.5 : 1.0
        let activityMultiplier = appearsActive ? 1.0 : 0.6
        return .init(
            opacity: recipe.opacity
                * contrastMultiplier
                * transparencyMultiplier
                * activityMultiplier,
            radius: recipe.radius,
            x: recipe.x,
            y: recipe.y
        )
    }

    /// WebKit consumes the same semantic recipe in CSS pixels. This is a
    /// renderer-specific resolution, not a macOS-point-to-CSS-pixel conversion.
    func cssBoxShadow(
        increasedContrast: Bool,
        reduceTransparency: Bool
    ) -> String {
        let style = style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency,
            appearsActive: true
        )
        guard style.opacity > 0 else { return "none" }
        return String(
            format: "%gpx %gpx %gpx rgb(0 0 0 / %.4f)",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(style.x),
            Double(style.y),
            Double(style.radius),
            style.opacity
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
            .init(
                colorRole: .separator, opacity: emphasized ? 0.78 : 0.42,
                lineWidth: emphasized ? 1 : 0.5)
        case .subtleBoundary:
            .init(
                colorRole: .separator, opacity: emphasized ? 0.82 : 0.34,
                lineWidth: emphasized ? 1 : 0.75)
        case .floatingBoundary:
            .init(
                colorRole: .separator, opacity: emphasized ? 0.82 : 0.34,
                lineWidth: emphasized ? 1 : 0.75)
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
    static let sourceFontSizePixels = 15
    static let narrowWidthThresholdRootEms = ScholiumGrid.Document.narrowWidthThresholdRootEms
    static let sourceLineHeight = 1.5
    static let codeBlockInset: CGFloat = 16
    static let quoteInlineInset = ScholiumGrid.Spacing.sectionSeparation

    static func contentInsets(
        for renderer: ScholiumDocumentRenderer,
        widthClass: ScholiumDocumentWidthClass
    ) -> ScholiumDocumentContentInsets {
        let inline: CGFloat =
            switch (renderer, widthClass) {
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
            Rectangle().fill(
                role.colorRole.color(
                    increasedContrast: increasedContrast
                ))
        }
    }
}

private struct ScholiumElevationModifier: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @Environment(\.scholiumAppearsActive) private var appearsActive
    let role: ScholiumElevationRole

    func body(content: Content) -> some View {
        let style = role.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency,
            appearsActive: appearsActive
        )
        content.shadow(
            color: ScholiumNativeColorRole.structuralShadow.color.opacity(style.opacity),
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

private struct ScholiumEditorialSurfaceModifier<S: RoundedRectangularShape>: ViewModifier {
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
        let surfacedContent =
            content
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
            .containerShape(shape)
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
        content.foregroundStyle(
            role.color(
                increasedContrast: increasedContrast
            ))
    }
}

private struct ScholiumContentInteractionSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast

    let isSelected: Bool
    let isHovering: Bool
    let isFocused: Bool
    let isPressed: Bool
    let shape: S

    func body(content: Content) -> some View {
        content.background(
            ScholiumContentInteractionSurface.selectionColor(
                isSelected: isSelected,
                isHovering: isEnabled && isHovering,
                isFocused: isEnabled && isFocused,
                isPressed: isEnabled && isPressed,
                increasedContrast: increasedContrast
            ),
            in: shape
        )
    }
}

private struct ScholiumContentControlIsEmphasizedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scholiumContentControlIsEmphasized: Bool {
        get { self[ScholiumContentControlIsEmphasizedKey.self] }
        set { self[ScholiumContentControlIsEmphasizedKey.self] = newValue }
    }
}

private struct ScholiumContentControlInkModifier: ViewModifier {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    let restingRole: ScholiumColorRole
    let emphasizedRole: ScholiumColorRole

    func body(content: Content) -> some View {
        content.foregroundStyle(
            (isEmphasized ? emphasizedRole : restingRole).color
        )
    }
}

/// The shared transient-state owner for custom SwiftUI Buttons. Native Menu
/// labels use the AppKit tracking adapter below because SwiftUI does not
/// reliably forward their pointer state. Ordinary Buttons use SwiftUI's
/// lightweight hover and ButtonStyle press path; native-container call sites
/// may leave hover to AppKit while retaining the shared press path.
private struct ScholiumHoverStateModifier: ViewModifier {
    let tracksHover: Bool
    let stateDidChange: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if tracksHover {
            content.onHover(perform: stateDidChange)
        } else {
            content
        }
    }
}

private struct ScholiumContentControlButtonFeedbackModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let isActive: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isPressed: Bool
    let tracksHover: Bool
    let pressedOpacity: Double
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let effectiveIsHovering = tracksHover && isHovering
        let hasTransientEmphasis =
            isEnabled && (effectiveIsHovering || isFocused || isPressed)
        let isEmphasized = isActive || isSelected || hasTransientEmphasis

        let feedback = content
            .environment(\.scholiumContentControlIsEmphasized, isEmphasized)
            .scholiumContentInteractionSurface(
                isSelected: isSelected,
                isHovering: effectiveIsHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                in: shape
            )
            .opacity(isEnabled && isPressed ? pressedOpacity : 1)

        feedback.modifier(
            ScholiumHoverStateModifier(
                tracksHover: tracksHover,
                stateDidChange: { isHovering = $0 }
            )
        )
    }
}

struct ScholiumContentControlButtonStyle<S: Shape>: ButtonStyle {
    let isActive: Bool
    let isSelected: Bool
    let isFocused: Bool
    let tracksHover: Bool
    let pressedOpacity: Double
    let shape: S

    init(
        isActive: Bool = false,
        isSelected: Bool = false,
        isFocused: Bool = false,
        tracksHover: Bool = true,
        pressedOpacity: Double = 0.78,
        in shape: S
    ) {
        self.isActive = isActive
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.tracksHover = tracksHover
        self.pressedOpacity = pressedOpacity
        self.shape = shape
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scholiumContentControlButtonFeedback(
                isActive: isActive,
                isSelected: isSelected,
                isFocused: isFocused,
                isPressed: configuration.isPressed,
                tracksHover: tracksHover,
                pressedOpacity: pressedOpacity,
                in: shape
            )
    }
}

/// A zero-hit-test AppKit observer for the complete control frame. SwiftUI's
/// native Menu host does not reliably forward pointer state to its label, so
/// the presentation adapter observes tracking and button events without
/// intercepting or replacing the native control's activation.
private struct ScholiumPointerInteractionReader: NSViewRepresentable {
    @Binding var isHovering: Bool
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> ScholiumPointerTrackingView {
        let view = ScholiumPointerTrackingView()
        view.stateDidChange = updateState
        return view
    }

    func updateNSView(_ view: ScholiumPointerTrackingView, context: Context) {
        view.stateDidChange = updateState
    }

    static func dismantleNSView(
        _ view: ScholiumPointerTrackingView,
        coordinator: Void
    ) {
        view.invalidate()
    }

    private func updateState(isHovering: Bool, isPressed: Bool) {
        self.isHovering = isHovering
        self.isPressed = isPressed
    }
}

private final class ScholiumPointerTrackingView: NSView {
    var stateDidChange: ((Bool, Bool) -> Void)?

    private var pointerIsInside = false
    private var pointerIsPressed = false
    private var localEventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            ))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeLocalEventMonitor()
        guard window != nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handlePointerButtonEvent(event)
            return event
        }
    }

    override func mouseEntered(with event: NSEvent) {
        setState(isHovering: true, isPressed: pointerIsPressed)
    }

    override func mouseExited(with event: NSEvent) {
        setState(isHovering: false, isPressed: false)
    }

    func invalidate() {
        removeLocalEventMonitor()
        stateDidChange = nil
    }

    private func handlePointerButtonEvent(_ event: NSEvent) {
        guard event.window === window else { return }
        let isInside = bounds.contains(convert(event.locationInWindow, from: nil))
        switch event.type {
        case .leftMouseDown:
            guard isInside else { return }
            setState(isHovering: true, isPressed: true)
        case .leftMouseDragged:
            guard pointerIsPressed else { return }
            setState(isHovering: isInside, isPressed: isInside)
        case .leftMouseUp:
            guard pointerIsPressed else { return }
            setState(isHovering: isInside, isPressed: false)
        default:
            break
        }
    }

    private func setState(isHovering: Bool, isPressed: Bool) {
        guard pointerIsInside != isHovering || pointerIsPressed != isPressed else {
            return
        }
        pointerIsInside = isHovering
        pointerIsPressed = isPressed
        stateDidChange?(isHovering, isPressed)
    }

    private func removeLocalEventMonitor() {
        guard let localEventMonitor else { return }
        NSEvent.removeMonitor(localEventMonitor)
        self.localEventMonitor = nil
        pointerIsInside = false
        pointerIsPressed = false
    }

    isolated deinit {
        removeLocalEventMonitor()
    }
}

/// One pointer-state owner for matching Scholium content controls. It keeps
/// hover and press capture, semantic ink promotion, shared surface paint, and
/// immediate press dimming identical whether a native Button or Menu owns the
/// actual activation.
private struct ScholiumContentControlPointerFeedbackModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var isPressed = false

    let isActive: Bool
    let isFocused: Bool
    let shape: S

    func body(content: Content) -> some View {
        let isEmphasized =
            isEnabled
            && (isActive || isHovering || isFocused || isPressed)

        content
            .environment(\.scholiumContentControlIsEmphasized, isEmphasized)
            .scholiumContentInteractionSurface(
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                in: shape
            )
            .opacity(isPressed ? 0.78 : 1)
            .overlay {
                ScholiumPointerInteractionReader(
                    isHovering: $isHovering,
                    isPressed: $isPressed
                )
                .accessibilityHidden(true)
            }
    }
}

/// Keeps controls in the complete keyboard focus chain. Custom content
/// surfaces clear pointer-manufactured keyboard focus before painting their
/// own focus treatment; native buttons keep AppKit's unmodified pointer,
/// keyboard, and focus behavior.
enum ScholiumActivationFocusPresentation: Sendable {
    case contentSurface
    case native
}

private struct ScholiumBooleanActivationFocusModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let presentation: ScholiumActivationFocusPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .contentSurface:
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus)
                .simultaneousGesture(pointerFocusReset)
        case .native:
            content
                .focusable()
                .focused(focus)
        }
    }

    private var pointerFocusReset: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in focus.wrappedValue = false }
            .onEnded { _ in focus.wrappedValue = false }
    }
}

private struct ScholiumValueActivationFocusModifier<Value: Hashable>: ViewModifier {
    let focus: FocusState<Value?>.Binding
    let value: Value
    let presentation: ScholiumActivationFocusPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .contentSurface:
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus, equals: value)
                .simultaneousGesture(pointerFocusReset)
        case .native:
            content
                .focusable()
                .focused(focus, equals: value)
        }
    }

    private var pointerFocusReset: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in clearPointerFocus() }
            .onEnded { _ in clearPointerFocus() }
    }

    private func clearPointerFocus() {
        guard focus.wrappedValue == value else { return }
        focus.wrappedValue = nil
    }
}

/// Keeps short floating surfaces at their natural width while still wrapping
/// long content inside the window's available width and a semantic upper cap.
private struct ScholiumContentFittingWidthLayout: Layout {
    let maximumWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let availableWidth = min(proposal.width ?? maximumWidth, maximumWidth)
        let ideal = subview.sizeThatFits(
            ProposedViewSize(width: availableWidth, height: nil)
        )
        let width = min(ideal.width, availableWidth)
        let fitted = subview.sizeThatFits(
            ProposedViewSize(width: width, height: nil)
        )
        return CGSize(width: width, height: fitted.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: bounds.height
            )
        )
    }
}

/// A borderless Scholium icon control for permanent commands, including custom
/// content hosted by the native macOS toolbar. It retains pointer, keyboard,
/// focus, help, and accessibility activation while leaving geometry to the
/// owning native container and expressing immediate states through ink.
struct ScholiumInkIconControl: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    let title: String
    let systemImage: String
    let identifier: String
    var isActive = false
    var symbolVerticalOffset: CGFloat = 0
    var role: ButtonRole? = nil
    var emphasizedColorRole: ScholiumColorRole = .primaryText
    var focus: FocusState<Bool>.Binding? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .offset(y: symbolVerticalOffset)
                .frame(
                    width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    height: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
                .scholiumContentControlInk(
                    resting: .secondaryText,
                    emphasized: emphasizedColorRole
                )
                .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isActive: isActive,
                isFocused: hasFocus,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .modifier(
            ScholiumInkIconFocusModifier(
                externalFocus: focus,
                localFocus: $isFocused
            )
        )
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var hasFocus: Bool {
        focus?.wrappedValue ?? isFocused
    }
}

private struct ScholiumInkIconFocusModifier: ViewModifier {
    let externalFocus: FocusState<Bool>.Binding?
    let localFocus: FocusState<Bool>.Binding

    @ViewBuilder
    func body(content: Content) -> some View {
        if let externalFocus {
            content
                .focusable()
                .focusEffectDisabled()
                .focused(externalFocus)
        } else {
            content
                .focusable()
                .focusEffectDisabled()
                .focused(localFocus)
        }
    }
}

enum ScholiumMotion {
    static let triptychWorkspaceSourceOffset = ScholiumGrid.foundationUnit * 1.5

    static func bootstrapStep(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    static func bootstrapStepTransition(
        movingForward: Bool,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let offset = movingForward ? 14.0 : -14.0
        return .asymmetric(
            insertion: .offset(x: offset).combined(with: .opacity),
            removal: .opacity
        )
    }

    static func documentReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.36)
    }

    static func documentRevealTransition(
        showingDocument: Bool,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return showingDocument
            ? .opacity.combined(with: .scale(scale: 0.995))
            : .opacity
    }

    static func searchPresentation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    static func searchPresentationTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    static func searchExpansion(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }

    static func disclosure(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func symbolReplacement(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    static func symbolReplacementTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity
    }

    static func symbolReplacementContentTransition(
        reduceMotion: Bool
    ) -> ContentTransition {
        reduceMotion ? .identity : .symbolEffect(.replace)
    }

    static func triptychWorkspaceSourceReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static func transientStatus(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    static func transientStatusTransition(
        reduceMotion: Bool,
        edge: Edge = .bottom
    ) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .move(edge: edge).combined(with: .opacity)
    }

    static func activityNotificationStackExpansion(
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0)
    }

    static func activityNotificationStackExpansionTransition(
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .offset(y: -ScholiumGrid.Spacing.inlineControlGap)
            .combined(with: .opacity)
    }
}

enum ScholiumFeedbackKind: Equatable, Sendable {
    case confirmation
    case information
    case warning
    case error

    var dismissesAutomatically: Bool {
        switch self {
        case .confirmation, .information: true
        case .warning, .error: false
        }
    }

    var symbol: String {
        switch self {
        case .confirmation: "checkmark.circle"
        case .information: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    var colorRole: ScholiumColorRole {
        switch self {
        case .confirmation: .confirmed
        case .information: .information
        case .warning: .attention
        case .error: .destructive
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .confirmation:
            String(localized: "Confirmation", table: "Localizable", bundle: .module)
        case .information:
            String(localized: "Information", table: "Localizable", bundle: .module)
        case .warning:
            String(localized: "Warning", table: "Localizable", bundle: .module)
        case .error:
            String(localized: "Error", table: "Localizable", bundle: .module)
        }
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .confirmation: "confirmation"
        case .information: "information"
        case .warning: "warning"
        case .error: "error"
        }
    }
}

enum ScholiumFeedbackPolicy {
    /// Transient feedback is redundant, noncritical, and explicitly dismissible.
    /// Warnings and errors never use this lifetime.
    static let transientLifetime: Duration = .seconds(6)
}

extension View {
    /// Fits compact overlays and banners to their content without allowing
    /// authored or diagnostic text to escape the containing window.
    func scholiumContentFittingWidth(maximumWidth: CGFloat) -> some View {
        ScholiumContentFittingWidthLayout(maximumWidth: maximumWidth) {
            self
        }
    }

    /// Reports SwiftUI pointer presence through the Design System's single
    /// hover adapter. Feature views may retain semantic reveal state, but do
    /// not own a second platform presentation path.
    func scholiumHoverState(
        tracksHover: Bool = true,
        _ stateDidChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            ScholiumHoverStateModifier(
                tracksHover: tracksHover,
                stateDidChange: stateDidChange
            )
        )
    }

    /// Applies the shared pointer-neutral, keyboard-complete focus policy to a
    /// custom button-like control with Boolean focus state.
    func scholiumActivationFocus(
        _ focus: FocusState<Bool>.Binding,
        presentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        modifier(ScholiumBooleanActivationFocusModifier(
            focus: focus,
            presentation: presentation
        ))
    }

    /// Applies the same policy to one value in a focusable control group.
    func scholiumActivationFocus<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding,
        equals value: Value,
        presentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        modifier(
            ScholiumValueActivationFocusModifier(
                focus: focus,
                value: value,
                presentation: presentation
            ))
    }

    /// Paints the shared shallow interaction surface inside content regions.
    /// The caller continues to own the purpose-specific shape and hit region.
    func scholiumContentInteractionSurface<S: Shape>(
        isSelected: Bool = false,
        isHovering: Bool,
        isFocused: Bool = false,
        isPressed: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentInteractionSurfaceModifier(
                isSelected: isSelected,
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                shape: shape
            ))
    }

    /// Applies the complete shared SwiftUI Button presentation while the
    /// Button retains activation, keyboard focus, and accessibility semantics.
    func scholiumContentControlButtonFeedback<S: Shape>(
        isActive: Bool = false,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isPressed: Bool,
        tracksHover: Bool = true,
        pressedOpacity: Double = 0.78,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentControlButtonFeedbackModifier(
                isActive: isActive,
                isSelected: isSelected,
                isFocused: isFocused,
                isPressed: isPressed,
                tracksHover: tracksHover,
                pressedOpacity: pressedOpacity,
                shape: shape
            )
        )
    }

    func scholiumContentControlInk(
        resting restingRole: ScholiumColorRole = .secondaryText,
        emphasized emphasizedRole: ScholiumColorRole = .primaryText
    ) -> some View {
        modifier(
            ScholiumContentControlInkModifier(
                restingRole: restingRole,
                emphasizedRole: emphasizedRole
            )
        )
    }

    /// Applies the complete shared pointer presentation to a matching custom
    /// content control while the enclosing native control retains activation,
    /// keyboard focus, menus, and accessibility.
    func scholiumContentControlPointerFeedback<S: Shape>(
        isActive: Bool = false,
        isFocused: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentControlPointerFeedbackModifier(
                isActive: isActive,
                isFocused: isFocused,
                shape: shape
            ))
    }

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

    func scholiumEditorialSurface<S: RoundedRectangularShape>(
        _ role: ScholiumSurfaceRole,
        in shape: S,
        boundary: ScholiumBoundaryRole? = nil,
        elevation: ScholiumElevationRole? = nil
    ) -> some View {
        modifier(
            ScholiumEditorialSurfaceModifier(
                role: role,
                boundary: boundary ?? role.defaultBoundaryRole,
                elevation: elevation ?? role.defaultElevationRole,
                shape: shape
            ))
    }
}

extension String {
    fileprivate var kebabCased: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append("-")
            }
            result.append(String(scalar).lowercased())
        }
    }
}
