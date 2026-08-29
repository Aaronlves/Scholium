import CoreText
import Foundation
import SwiftUI

/// Registers Scholium's editorial typefaces for this process. Alegreya is
/// reserved for document and publication-like hierarchy; operational controls
/// continue to use the macOS system font.
enum ScholiumFontRegistry {
    private static let bundledFontNames = [
        "Alegreya-Regular",
        "Alegreya-Italic",
        "Alegreya-Bold",
        "Alegreya-BoldItalic",
        "VictorMono-Regular",
        "VictorMono-Italic",
        "VictorMono-Bold",
        "VictorMono-BoldItalic",
    ]

    static func registerBundledFonts() {
        for resourceName in bundledFontNames {
            let url = fontResourceURL(named: resourceName)
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// SwiftPM executables keep their processed-resource bundle beside the
    /// executable during development. The packaged macOS app correctly keeps
    /// that same bundle under `Contents/Resources`.
    private static func fontResourceURL(named resourceName: String) -> URL? {
        let resourceBundleName = "Scholium_ScholiumApp.bundle"
        var candidateURLs: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(resourceBundleName))
        }
        if let executableURL = Bundle.main.executableURL {
            candidateURLs.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(resourceBundleName)
            )
        }

        for bundleURL in candidateURLs {
            guard let resourceBundle = Bundle(url: bundleURL) else { continue }
            if let url = resourceBundle.url(forResource: resourceName, withExtension: "ttf") {
                return url
            }
        }
        return nil
    }
}

/// Low-level bundled-family resolution. Product views consume only the
/// semantic roles exposed by `ScholiumTypography` below.
private enum ScholiumTypeface {
    static func exact(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        bold: Bool = false,
        italic: Bool = false
    ) -> Font {
        let name: String
        switch (bold, italic) {
        case (false, false): name = "VictorMono-Regular"
        case (false, true): name = "VictorMono-Italic"
        case (true, false): name = "VictorMono-Bold"
        case (true, true): name = "VictorMono-BoldItalic"
        }
        return .custom(name, size: size, relativeTo: textStyle)
    }

    static func scholarly(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        bold: Bool = false,
        italic: Bool = false
    ) -> Font {
        let name: String
        switch (bold, italic) {
        case (false, false): name = "Alegreya-Regular"
        case (false, true): name = "Alegreya-Italic"
        case (true, false): name = "Alegreya-Bold"
        case (true, true): name = "Alegreya-BoldItalic"
        }
        return .custom(name, size: size, relativeTo: textStyle)
    }
}

/// The sole native typography resolver for Scholium-owned text. Family
/// communicates content kind; role communicates hierarchy. Feature views do
/// not publish aliases. Document typography remains owned by
/// `DocumentAppearanceSettings` and generated CSS.
enum ScholiumTypography {
    enum InterfaceRole {
        case primaryTitle
        case sectionTitle
        case rowTitle
        case body
        case compact
        case small
    }

    enum ScholarlyRole {
        case title
        case sectionTitle
        case body
        case emphasis
    }

    enum ExactRole {
        case body
        case strong
        case small
    }

    enum Emphasis {
        case medium
        case strong

        fileprivate var weight: Font.Weight {
            switch self {
            case .medium: .medium
            case .strong: .semibold
            }
        }
    }

    enum Brand {
        /// The sole editorial typeface exception inside interface identity.
        static let wordmark = ScholiumTypeface.scholarly(
            size: 22,
            relativeTo: .title2,
            bold: true
        )
    }

    enum Bootstrap {
        static let wordmark = ScholiumTypeface.scholarly(
            size: 34,
            relativeTo: .largeTitle,
            bold: true
        )
        static let title = Font.system(size: 26, weight: .semibold)
        static let statement = Font.system(size: 25, weight: .medium)
    }

    static func interface(
        _ role: InterfaceRole,
        emphasis: Emphasis? = nil,
        tabularDigits: Bool = false
    ) -> Font {
        let size: CGFloat
        let defaultWeight: Font.Weight
        switch role {
        case .primaryTitle:
            (size, defaultWeight) = (17, .semibold)
        case .sectionTitle:
            (size, defaultWeight) = (12, .semibold)
        case .rowTitle:
            (size, defaultWeight) = (12, .medium)
        case .body:
            (size, defaultWeight) = (12, .regular)
        case .compact:
            (size, defaultWeight) = (11, .regular)
        case .small:
            (size, defaultWeight) = (10, .regular)
        }
        let font = Font.system(size: size, weight: emphasis?.weight ?? defaultWeight)
        return tabularDigits ? font.monospacedDigit() : font
    }

    static func scholarly(
        _ role: ScholarlyRole,
        tabularDigits: Bool = false
    ) -> Font {
        let font: Font
        switch role {
        case .title:
            font = ScholiumTypeface.scholarly(
                size: 20,
                relativeTo: .title2,
                bold: true
            )
        case .sectionTitle:
            font = ScholiumTypeface.scholarly(
                size: 17,
                relativeTo: .headline,
                bold: true
            )
        case .body:
            font = ScholiumTypeface.scholarly(size: 13, relativeTo: .body)
        case .emphasis:
            font = ScholiumTypeface.scholarly(size: 13, relativeTo: .body)
                .weight(.medium)
        }
        return tabularDigits ? font.monospacedDigit() : font
    }

    static func scholarlyInline(
        bold: Bool = false,
        italic: Bool = false
    ) -> Font {
        ScholiumTypeface.scholarly(
            size: 13,
            relativeTo: .body,
            bold: bold,
            italic: italic
        )
    }

    static func exactInline(
        bold: Bool = false,
        italic: Bool = false
    ) -> Font {
        ScholiumTypeface.exact(
            size: 12,
            relativeTo: .body,
            bold: bold,
            italic: italic
        )
    }

    static func exact(_ role: ExactRole) -> Font {
        switch role {
        case .body:
            ScholiumTypeface.exact(size: 12, relativeTo: .body)
        case .strong:
            ScholiumTypeface.exact(size: 12, relativeTo: .body, bold: true)
        case .small:
            ScholiumTypeface.exact(size: 10, relativeTo: .caption)
        }
    }
}

/// Symbol scale is a component concern rather than a text-family role.
enum ScholiumSymbolStyle {
    case prominent
    case emphasizedProminent
    case large
    case relationship

    fileprivate var font: Font {
        switch self {
        case .prominent:
            .system(size: 15, weight: .regular)
        case .emphasizedProminent:
            .system(size: 15, weight: .semibold)
        case .large:
            .system(size: 17, weight: .regular)
        case .relationship:
            .system(
                size: ScholiumMetrics.Apparatus.relationGlyphSize,
                weight: .regular
            )
        }
    }
}

extension Image {
    func scholiumSymbolStyle(_ style: ScholiumSymbolStyle) -> some View {
        font(style.font)
    }
}
