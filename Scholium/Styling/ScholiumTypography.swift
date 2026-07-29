import ScholiumContracts
import AppKit
import CoreText
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

    static func swiftUIReadingFont(
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

/// Scholarly Editorialism pairs an Alegreya publication hierarchy with system
/// typography for operational chrome, metadata, and native controls.
enum ScholiumInterfaceTypography {
    /// Scholium's wordmark is the sole editorial exception inside window
    /// chrome. Commands and all other operational labels remain system sans.
    static let identity = ScholiumTypography.swiftUIReadingFont(
        size: 22,
        relativeTo: .title2,
        bold: true
    )
    static let documentTitle = ScholiumTypography.swiftUIReadingFont(
        size: 22.5,
        relativeTo: .title,
        bold: false
    )
    /// One scan rhythm for both folders and notes. Hierarchy is expressed by
    /// weight, color, indentation, and symbols rather than a size change.
    static let libraryHierarchy = Font.callout
    /// Library Folders and unselected Notes share a regular scan weight.
    /// Selection alone adds semibold emphasis without changing point size.
    static let libraryFolderTitle = libraryHierarchy
    static let libraryNoteTitle = libraryHierarchy
    static let librarySelectedNoteTitle = libraryNoteTitle.weight(.semibold)
    /// The compact native-toolbar identity is positional metadata. The
    /// scrolling document title remains the primary editorial identity.
    static let workspaceToolbarIdentity = Font.body
    static let noteTitle = Font.body
    static let literatureCitation = ScholiumTypography.swiftUIReadingFont(
        size: 12,
        relativeTo: .body
    )
    static let bibliographyPreview = literatureCitation
    static let apparatusTitle = ScholiumTypography.swiftUIReadingFont(
        size: 17,
        relativeTo: .headline,
        bold: true
    )
    static let sectionTitle = Font.headline.weight(.medium)
    static let rowTitle = libraryHierarchy.weight(.medium)
    static let metadata = Font.caption.weight(.medium)
    static let bibliographyEmptyState = metadata
    static let editorialLabel = Font.caption2.weight(.semibold)
    /// The LocationPicker is the primary title of its stable Library header.
    /// It uses the macOS default interface size without acquiring a bezel.
    static let libraryLocation = Font.system(size: 13, weight: .semibold)

    /// Inspector chrome follows the compact type scale frozen in the HTML
    /// study. Selection changes weight, not size, so switching modes does not
    /// disturb the three-column grid.
    static let apparatusMode = Font.system(size: 11, weight: .medium)
    static let apparatusModeSelected = Font.system(size: 11, weight: .semibold)

    /// Section headings stay quiet but gain enough weight and tracking to
    /// remain distinct from their more tightly grouped content.
    static let apparatusLabel = Font.system(size: 10, weight: .semibold)

    /// Operational labels remain system sans-serif. Explanations, values, and
    /// researcher-authored text use the editorial serif role below.
    static let apparatusBody = Font.system(size: 11, weight: .regular)
    static let apparatusMetadata = Font.system(size: 10, weight: .regular)
    static let apparatusActionTitle = Font.system(size: 12, weight: .semibold)
    static let apparatusResearchContent = ScholiumTypography.swiftUIReadingFont(
        size: 12,
        relativeTo: .body
    )
}
