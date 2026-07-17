import ScholiumContracts
import AppKit
import CoreText
import SwiftUI

/// Registers Scholium's document typefaces for this process. The interface
/// itself continues to use the macOS system font.
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

/// The document typography contract shared by SwiftUI and the AppKit-backed
/// Markdown reader/editor.
enum ScholiumTypography {
    enum HeadingLevel: Int, CaseIterable, Sendable {
        case h1 = 1
        case h2
        case h3
        case h4
        case h5
        case h6

        fileprivate var scale: CGFloat {
            switch self {
            case .h1: 1.50
            case .h2: 1.30
            case .h3: 1.15
            case .h4, .h5, .h6: 1.00
            }
        }
    }

    private static let bodyPointSize: CGFloat = 12
    static let exactSourcePointSize: CGFloat = 14
    static let codePointSize: CGFloat = 13
    static let diffPointSize: CGFloat = 13
    static let revisionIdentityPointSize: CGFloat = 11

    static func body(
        scale: CGFloat = 1,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        readingFont(
            size: bodyPointSize * scale,
            bold: bold,
            italic: italic
        )
    }

    static func heading(
        level: HeadingLevel,
        scale: CGFloat = 1
    ) -> NSFont {
        readingFont(
            size: bodyPointSize * level.scale * scale,
            bold: true
        )
    }

    static func exactSource(
        scale: CGFloat = 1,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        monospaceFont(
            size: exactSourcePointSize * scale,
            bold: bold,
            italic: italic
        )
    }

    static func code(scale: CGFloat = 1) -> NSFont {
        monospaceFont(size: codePointSize * scale)
    }

    static func diff(
        scale: CGFloat = 1,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        monospaceFont(
            size: diffPointSize * scale,
            bold: bold,
            italic: italic
        )
    }

    static func revisionIdentity(scale: CGFloat = 1) -> NSFont {
        monospaceFont(size: revisionIdentityPointSize * scale)
    }

    static func readingFont(
        size: CGFloat,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        let name: String
        switch (bold, italic) {
        case (false, false): name = "Alegreya-Regular"
        case (false, true): name = "Alegreya-Italic"
        case (true, false): name = "Alegreya-Bold"
        case (true, true): name = "Alegreya-BoldItalic"
        }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(
            ofSize: size,
            weight: bold ? .bold : .regular
        )
    }

    static func monospaceFont(
        size: CGFloat,
        bold: Bool = false,
        italic: Bool = false
    ) -> NSFont {
        let name: String
        switch (bold, italic) {
        case (false, false): name = "VictorMono-Regular"
        case (false, true): name = "VictorMono-Italic"
        case (true, false): name = "VictorMono-Bold"
        case (true, true): name = "VictorMono-BoldItalic"
        }
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(
            ofSize: size,
            weight: bold ? .bold : .regular
        )
    }

    static func swiftUIMonospaceFont(
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

    static func swiftUICode(scale: CGFloat = 1) -> Font {
        swiftUIMonospaceFont(
            size: codePointSize * scale,
            relativeTo: .body
        )
    }

    static func swiftUIDiff(
        scale: CGFloat = 1,
        bold: Bool = false,
        italic: Bool = false
    ) -> Font {
        swiftUIMonospaceFont(
            size: diffPointSize * scale,
            relativeTo: .body,
            bold: bold,
            italic: italic
        )
    }

    static func swiftUIRevisionIdentity(scale: CGFloat = 1) -> Font {
        swiftUIMonospaceFont(
            size: revisionIdentityPointSize * scale,
            relativeTo: .caption
        )
    }
}

/// A restrained system-font hierarchy for persistent app chrome. Document
/// prose and exact-source text continue to use the typefaces above.
enum ScholiumInterfaceTypography {
    static let identity = Font.title3.weight(.medium)
    static let sectionTitle = Font.headline.weight(.medium)
    static let rowTitle = Font.callout.weight(.medium)
    static let metadata = Font.caption.weight(.medium)
}
