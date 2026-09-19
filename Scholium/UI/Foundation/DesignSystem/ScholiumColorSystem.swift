import AppKit
import Foundation
import SwiftUI

/// The configurable document identity boundary.
enum ScholiumColorVariable: String, CaseIterable, Sendable {
    case paper
}

/// The only app-owned color input. The interface Accent is supplied by macOS
/// and is never persisted as a Scholium Variable.
struct ScholiumColorVariables: Equatable, Sendable {
    let paper: UInt32

    static let editorialPaper = Self(paper: 0xFEF8ED)

    subscript(variable: ScholiumColorVariable) -> UInt32 {
        switch variable {
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
    case separator
    case accent
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
        if self == .accent {
            return ScholiumNativeColorRole.controlAccent.nsColor
        }
        return NSColor(name: nil) { appearance in
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
        if self == .accent {
            return Self.systemAccentRGBValue(for: appearance)
        }
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return resolvedRGBValue(isDark: isDark, increasedContrast: increasedContrast)
    }

    func resolvedRGBValue(isDark: Bool, increasedContrast: Bool) -> UInt32 {
        if self == .accent {
            guard let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) else {
                return 0
            }
            return Self.systemAccentRGBValue(for: appearance)
        }
        let palette: ScholiumResolvedColorPalette =
            switch (isDark, increasedContrast) {
            case (false, false): Self.lightPalette
            case (false, true): Self.increasedContrastLightPalette
            case (true, false): Self.darkPalette
            case (true, true): Self.increasedContrastDarkPalette
            }
        return palette[self]
    }

    private static let resolver = ScholiumColorResolver(variables: .editorialPaper)
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

    static func systemAccentRGBValue(for appearance: NSAppearance) -> UInt32 {
        var value: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else {
                return
            }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            value =
                (UInt32((red * 255).rounded()) << 16)
                | (UInt32((green * 255).rounded()) << 8)
                | UInt32((blue * 255).rounded())
        }
        return value
    }
}

/// System-owned colors used for effects whose appearance is defined by
/// AppKit rather than by Scholium's configurable editorial palette. Keeping
/// these exceptions named prevents feature views from reaching into AppKit's
/// color catalog directly or treating them as additional product Variables.
enum ScholiumNativeColorRole: Sendable {
    case label, secondaryLabel, windowBackground, controlBackground, textBackground, controlAccent
    case searchMatchHighlight
    case inactiveTextSelection
    case structuralShadow
    case unreadAction, importantAction, archiveAction

    var nsColor: NSColor {
        switch self {
        case .label: .labelColor
        case .secondaryLabel: .secondaryLabelColor
        case .windowBackground: .windowBackgroundColor
        case .controlBackground: .controlBackgroundColor
        case .textBackground: .textBackgroundColor
        case .controlAccent: .controlAccentColor
        case .searchMatchHighlight: .findHighlightColor
        case .inactiveTextSelection: .unemphasizedSelectedTextBackgroundColor
        case .structuralShadow: .shadowColor
        case .unreadAction: .systemBlue
        case .importantAction: .systemOrange
        case .archiveAction: .systemPurple
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

/// A complete appearance result generated from the app-owned Paper input.
/// Accent is a resolved snapshot from the macOS system color; the source of
/// truth remains the system color rather than this adapted palette.
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
    let separator: UInt32
    let accent: UInt32
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
        case .separator: separator
        case .accent: accent
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

/// Resolves app-owned Paper-derived roles for native and WebKit presentation.
/// Fixed functional anchors supply semantic hue direction but aren't exposed
/// as researcher configuration. Accent is a system-owned role and is resolved
/// separately from the macOS control accent color.
struct ScholiumColorResolver: Sendable {
    let variables: ScholiumColorVariables

    func resolve(isDark: Bool, increasedContrast: Bool) -> ScholiumResolvedColorPalette {
        let paperSource = Self.oklch(from: variables.paper)
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
        let separator = Self.tone(
            paperSource,
            lightness: isDark
                ? (increasedContrast ? 0.70 : 0.57)
                : (increasedContrast ? 0.62 : 0.808),
            chromaLimit: 0.020
        )
        let comparisonBackgroundLightness =
            isDark
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

        let accent: UInt32 = {
            guard let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) else {
                return 0
            }
            return ScholiumColorRole.systemAccentRGBValue(for: appearance)
        }()

        return ScholiumResolvedColorPalette(
            documentBackground: documentBackground,
            surfaceBackground: surfaceBackground,
            navigationSurfaceBackground: navigationSurfaceBackground,
            apparatusSurfaceBackground: apparatusSurfaceBackground,
            raisedSurfaceBackground: raisedSurfaceBackground,
            primaryText: primaryText,
            secondaryText: secondaryText,
            separator: separator,
            accent: accent,
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

    /// Document role hues come from macOS; the shared contrast resolver adapts
    /// them to Paper. These labels do not imply warning, success or authorship.
    func calloutTitleColor(_ role: String, isDark: Bool, increasedContrast: Bool) -> UInt32 {
        let color: NSColor =
            switch role {
            case "orient": .systemBlue
            case "cite": .systemIndigo
            case "connect": .systemTeal
            case "state": .systemPurple
            case "illustrate": .systemBrown
            case "flag": .systemGray
            default: .secondaryLabelColor
            }
        var anchor: UInt32 = 0
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        appearance.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                anchor =
                    (UInt32((rgb.redComponent * 255).rounded()) << 16)
                    | (UInt32((rgb.greenComponent * 255).rounded()) << 8)
                    | UInt32((rgb.blueComponent * 255).rounded())
            }
        }
        let palette = resolve(isDark: isDark, increasedContrast: increasedContrast)
        return Self.contrastColor(
            Self.oklch(from: anchor), startingLightness: isDark ? 0.84 : 0.40,
            chromaLimit: 0.12,
            backgrounds: [palette.documentBackground, palette.surfaceBackground],
            target: 7, preferLight: isDark
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
