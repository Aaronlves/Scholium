import Foundation

public enum DocumentAppearanceFontFamily: String, Codable, CaseIterable, Sendable {
    case alegreya
    case iowan
    case palatino
    case georgia
    case times
    case systemSerif
}

public enum DocumentHeadingFontFamily: String, Codable, CaseIterable, Sendable {
    case body
    case alegreya
    case systemSerif
    case systemSans
}

public enum DocumentHeadingStyle: String, Codable, CaseIterable, Sendable {
    case upright
    case italic
    case smallCaps
}

public enum DocumentTextAlignment: String, Codable, CaseIterable, Sendable {
    case start
    case center
    case justify
}

public enum DocumentHyphenation: String, Codable, CaseIterable, Sendable {
    case none
    case automatic
}

public enum DocumentCalloutAppearanceRole: String, Codable, CaseIterable, Sendable {
    case orientation
    case connections
    case statement
    case illustration
    case caution
    case folded
    case quotation
    case source
}

public struct DocumentBodyAppearance: Codable, Hashable, Sendable {
    public var fontFamily: DocumentAppearanceFontFamily
    public var fontSizePoints: Double
    public var lineHeight: Double
    public var paragraphSpacingEm: Double
    public var firstLineIndentEm: Double
    public var letterSpacingEm: Double
    public var wordSpacingEm: Double
    public var alignment: DocumentTextAlignment
    public var hyphenation: DocumentHyphenation
    public var kerning: Bool
    public var ligatures: Bool

    public init(
        fontFamily: DocumentAppearanceFontFamily = .alegreya,
        fontSizePoints: Double = 12,
        lineHeight: Double = 2,
        paragraphSpacingEm: Double = 1,
        firstLineIndentEm: Double = 0,
        letterSpacingEm: Double = 0.02,
        wordSpacingEm: Double = 0,
        alignment: DocumentTextAlignment = .justify,
        hyphenation: DocumentHyphenation = .none,
        kerning: Bool = true,
        ligatures: Bool = true
    ) {
        self.fontFamily = fontFamily
        self.fontSizePoints = fontSizePoints
        self.lineHeight = lineHeight
        self.paragraphSpacingEm = paragraphSpacingEm
        self.firstLineIndentEm = firstLineIndentEm
        self.letterSpacingEm = letterSpacingEm
        self.wordSpacingEm = wordSpacingEm
        self.alignment = alignment
        self.hyphenation = hyphenation
        self.kerning = kerning
        self.ligatures = ligatures
    }
}

public struct DocumentHeadingLevelAppearance: Codable, Hashable, Sendable {
    public var scale: Double
    public var alignment: DocumentTextAlignment
    public var spaceBeforeEm: Double
    public var spaceAfterEm: Double

    public init(
        scale: Double,
        alignment: DocumentTextAlignment = .start,
        spaceBeforeEm: Double,
        spaceAfterEm: Double
    ) {
        self.scale = scale
        self.alignment = alignment
        self.spaceBeforeEm = spaceBeforeEm
        self.spaceAfterEm = spaceAfterEm
    }
}

public struct DocumentHeadingAppearance: Codable, Hashable, Sendable {
    public var fontFamily: DocumentHeadingFontFamily
    public var style: DocumentHeadingStyle
    public var weight: Int
    public var lineHeight: Double
    public var letterSpacingEm: Double
    public var title: DocumentHeadingLevelAppearance
    public var level1: DocumentHeadingLevelAppearance
    public var level2: DocumentHeadingLevelAppearance

    public init(
        fontFamily: DocumentHeadingFontFamily = .body,
        style: DocumentHeadingStyle = .upright,
        weight: Int = 500,
        lineHeight: Double = 1.8,
        letterSpacingEm: Double = 0,
        title: DocumentHeadingLevelAppearance = .init(
            scale: 2,
            alignment: .center,
            spaceBeforeEm: 0,
            spaceAfterEm: 2
        ),
        level1: DocumentHeadingLevelAppearance = .init(
            scale: 1.5,
            spaceBeforeEm: 0.6,
            spaceAfterEm: 0.6
        ),
        level2: DocumentHeadingLevelAppearance = .init(
            scale: 1.15,
            spaceBeforeEm: 0.5,
            spaceAfterEm: 0.5
        )
    ) {
        self.fontFamily = fontFamily
        self.style = style
        self.weight = weight
        self.lineHeight = lineHeight
        self.letterSpacingEm = letterSpacingEm
        self.title = title
        self.level1 = level1
        self.level2 = level2
    }
}

public struct DocumentCalloutAppearance: Codable, Hashable, Identifiable, Sendable {
    public var id: DocumentCalloutAppearanceRole { role }
    public var role: DocumentCalloutAppearanceRole
    public var inlineInsetEm: Double
    public var blockGapEm: Double
    public var fontScale: Double
    public var paragraphSpacingEm: Double
    public var titleWeight: Int
    public var lineHeight: Double?
    public var startInsetEm: Double?
    public var endInsetEm: Double?
    public var titleGapEm: Double?
    public var titleColumnEm: Double?
    public var columnGapEm: Double?
    public var paddingBlockEm: Double?
    public var paddingInlineEm: Double?
    public var contentIndentEm: Double?
    public var quotationScale: Double?
    public var attributionScale: Double?

    public init(
        role: DocumentCalloutAppearanceRole,
        inlineInsetEm: Double,
        blockGapEm: Double,
        fontScale: Double = 1,
        paragraphSpacingEm: Double = 0.75,
        titleWeight: Int,
        lineHeight: Double? = nil,
        startInsetEm: Double? = nil,
        endInsetEm: Double? = nil,
        titleGapEm: Double? = nil,
        titleColumnEm: Double? = nil,
        columnGapEm: Double? = nil,
        paddingBlockEm: Double? = nil,
        paddingInlineEm: Double? = nil,
        contentIndentEm: Double? = nil,
        quotationScale: Double? = nil,
        attributionScale: Double? = nil
    ) {
        self.role = role
        self.inlineInsetEm = inlineInsetEm
        self.blockGapEm = blockGapEm
        self.fontScale = fontScale
        self.paragraphSpacingEm = paragraphSpacingEm
        self.titleWeight = titleWeight
        self.lineHeight = lineHeight
        self.startInsetEm = startInsetEm
        self.endInsetEm = endInsetEm
        self.titleGapEm = titleGapEm
        self.titleColumnEm = titleColumnEm
        self.columnGapEm = columnGapEm
        self.paddingBlockEm = paddingBlockEm
        self.paddingInlineEm = paddingInlineEm
        self.contentIndentEm = contentIndentEm
        self.quotationScale = quotationScale
        self.attributionScale = attributionScale
    }
}

public struct DocumentAppearanceSettings: Codable, Hashable, Sendable {
    public var body: DocumentBodyAppearance
    public var headings: DocumentHeadingAppearance
    public var callouts: [DocumentCalloutAppearance]

    public init(
        body: DocumentBodyAppearance = .init(),
        headings: DocumentHeadingAppearance = .init(),
        callouts: [DocumentCalloutAppearance] = Self.defaultCallouts
    ) {
        self.body = body
        self.headings = headings
        self.callouts = callouts
    }

    public static let defaultCallouts: [DocumentCalloutAppearance] = [
        .init(
            role: .orientation,
            inlineInsetEm: 1,
            blockGapEm: 1.5,
            titleWeight: 400,
            lineHeight: 1.3,
            startInsetEm: 3,
            endInsetEm: 3
        ),
        .init(
            role: .connections,
            inlineInsetEm: 0,
            blockGapEm: 1.4,
            paragraphSpacingEm: 0.42,
            titleWeight: 700,
            contentIndentEm: 0.72
        ),
        .init(
            role: .statement,
            inlineInsetEm: 1,
            blockGapEm: 1.5,
            titleWeight: 500,
            titleGapEm: 0.32
        ),
        .init(
            role: .illustration,
            inlineInsetEm: 1,
            blockGapEm: 1,
            titleWeight: 500,
            titleColumnEm: 6.5,
            columnGapEm: 1
        ),
        .init(
            role: .caution,
            inlineInsetEm: 0,
            blockGapEm: 1.5,
            titleWeight: 500,
            paddingBlockEm: 0.9,
            paddingInlineEm: 1
        ),
        .init(
            role: .folded,
            inlineInsetEm: 1,
            blockGapEm: 1.7,
            titleWeight: 500,
            contentIndentEm: 1.05
        ),
        .init(
            role: .quotation,
            inlineInsetEm: 1,
            blockGapEm: 1.5,
            titleWeight: 400,
            quotationScale: 1.06,
            attributionScale: 0.85
        ),
        .init(
            role: .source,
            inlineInsetEm: 0,
            blockGapEm: 1.7,
            titleWeight: 500,
            paddingBlockEm: 0.9,
            paddingInlineEm: 1
        )
    ]

    public func callout(_ role: DocumentCalloutAppearanceRole) -> DocumentCalloutAppearance {
        callouts.first(where: { $0.role == role })
            ?? Self.defaultCallouts.first(where: { $0.role == role })!
    }
}

public struct DocumentAppearanceProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var settings: DocumentAppearanceSettings

    public init(
        id: UUID = UUID(),
        name: String,
        settings: DocumentAppearanceSettings = .init()
    ) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}
