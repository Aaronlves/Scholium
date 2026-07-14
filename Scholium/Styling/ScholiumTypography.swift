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
    static let readingBodySize: CGFloat = 17
    static let sourceBodySize: CGFloat = 14

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
}
