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
    /// Optional installed family used for Chinese glyphs inside strong text.
    /// `nil` follows the selected body family; an empty string explicitly
    /// restores that family when a configuration wants to override a default.
    public var cjkStrongFontFamily: String?
    /// Optional installed family used for Chinese glyphs inside emphasized
    /// text. `nil` uses Scholium's readable Kai-style default; an empty string
    /// explicitly restores the selected body family's native italic treatment.
    public var cjkEmphasisFontFamily: String?
    public var fontSizePoints: Double
    public var lineHeight: Double
    public var paragraphSpacingEm: Double
    public var firstLineIndentEm: Double
    public var alignment: DocumentTextAlignment

    public init(
        fontFamily: DocumentAppearanceFontFamily = .alegreya,
        cjkStrongFontFamily: String? = nil,
        cjkEmphasisFontFamily: String? = nil,
        fontSizePoints: Double = 12,
        lineHeight: Double = 1.7,
        paragraphSpacingEm: Double = 0.7,
        firstLineIndentEm: Double = 0,
        alignment: DocumentTextAlignment = .start
    ) {
        self.fontFamily = fontFamily
        self.cjkStrongFontFamily = cjkStrongFontFamily
        self.cjkEmphasisFontFamily = cjkEmphasisFontFamily
        self.fontSizePoints = fontSizePoints
        self.lineHeight = lineHeight
        self.paragraphSpacingEm = paragraphSpacingEm
        self.firstLineIndentEm = firstLineIndentEm
        self.alignment = alignment
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
    /// Optional installed family used for Chinese glyphs inside strong heading
    /// text. `nil` follows the selected heading family.
    public var cjkStrongFontFamily: String?
    /// Optional installed family used for Chinese glyphs in italic headings or
    /// inline emphasis. `nil` uses Scholium's readable Kai-style default.
    public var cjkEmphasisFontFamily: String?
    public var style: DocumentHeadingStyle
    public var weight: Int
    public var lineHeight: Double
    public var level1: DocumentHeadingLevelAppearance
    public var level2: DocumentHeadingLevelAppearance
    public var level3: DocumentHeadingLevelAppearance
    public var level4: DocumentHeadingLevelAppearance
    public var level5: DocumentHeadingLevelAppearance
    public var level6: DocumentHeadingLevelAppearance

    public init(
        fontFamily: DocumentHeadingFontFamily = .body,
        cjkStrongFontFamily: String? = nil,
        cjkEmphasisFontFamily: String? = nil,
        style: DocumentHeadingStyle = .upright,
        weight: Int = 500,
        lineHeight: Double = 1.35,
        level1: DocumentHeadingLevelAppearance = .init(
            scale: 1.4,
            spaceBeforeEm: 0.9,
            spaceAfterEm: 0.35
        ),
        level2: DocumentHeadingLevelAppearance = .init(
            scale: 1.22,
            spaceBeforeEm: 0.8,
            spaceAfterEm: 0.3
        ),
        level3: DocumentHeadingLevelAppearance = .init(
            scale: 1.14,
            spaceBeforeEm: 0.7,
            spaceAfterEm: 0.28
        ),
        level4: DocumentHeadingLevelAppearance = .init(
            scale: 1.08,
            spaceBeforeEm: 0.6,
            spaceAfterEm: 0.24
        ),
        level5: DocumentHeadingLevelAppearance = .init(
            scale: 1.02,
            spaceBeforeEm: 0.5,
            spaceAfterEm: 0.2
        ),
        level6: DocumentHeadingLevelAppearance = .init(
            scale: 0.98,
            spaceBeforeEm: 0.4,
            spaceAfterEm: 0.18
        )
    ) {
        self.fontFamily = fontFamily
        self.cjkStrongFontFamily = cjkStrongFontFamily
        self.cjkEmphasisFontFamily = cjkEmphasisFontFamily
        self.style = style
        self.weight = weight
        self.lineHeight = lineHeight
        self.level1 = level1
        self.level2 = level2
        self.level3 = level3
        self.level4 = level4
        self.level5 = level5
        self.level6 = level6
    }

    public var levels: [DocumentHeadingLevelAppearance] {
        [level1, level2, level3, level4, level5, level6]
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
        self.paddingBlockEm = paddingBlockEm
        self.paddingInlineEm = paddingInlineEm
        self.contentIndentEm = contentIndentEm
        self.quotationScale = quotationScale
        self.attributionScale = attributionScale
    }
}

public struct DocumentSourceAppearance: Codable, Hashable, Sendable {
    public var fontFamily: String
    public var fontSizePoints: Double

    public init(fontFamily: String = "Courier", fontSizePoints: Double = 9.6) {
        self.fontFamily = fontFamily
        self.fontSizePoints = fontSizePoints
    }
}

public struct DocumentAppearanceSettings: Codable, Hashable, Sendable {
    public static let defaultLineWidthCharacterUnits: Double = 66
    public static let lineWidthCharacterUnitsRange: ClosedRange<Double> = 48...96
    public static let defaultCJKBodyFontFamily = "STFangsong"
    public static let defaultCJKEmphasisFontFamily = "Kaiti SC"

    public var lineWidthCharacterUnits: Double
    public var body: DocumentBodyAppearance
    public var source: DocumentSourceAppearance
    public var headings: DocumentHeadingAppearance
    public var callouts: [DocumentCalloutAppearance]

    public init(
        lineWidthCharacterUnits: Double = Self.defaultLineWidthCharacterUnits,
        body: DocumentBodyAppearance = .init(),
        source: DocumentSourceAppearance = .init(),
        headings: DocumentHeadingAppearance = .init(),
        callouts: [DocumentCalloutAppearance] = Self.defaultCallouts
    ) {
        self.lineWidthCharacterUnits = lineWidthCharacterUnits
        self.body = body
        self.source = source
        self.headings = headings
        self.callouts = callouts
    }

    /// The sole source for Scholium's built-in document Appearance. WebKit
    /// transports and native document adapters derive their initial values
    /// from this normalized settings object rather than keeping a second
    /// typography table.
    public static let defaultSettings = Self()

    public static let defaultCallouts: [DocumentCalloutAppearance] = [
        .init(
            role: .orientation,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 600,
            startInsetEm: 0,
            endInsetEm: 0
        ),
        .init(
            role: .connections,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            paragraphSpacingEm: 0.34,
            titleWeight: 550,
            contentIndentEm: 0.72
        ),
        .init(
            role: .statement,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 700,
            titleGapEm: 0
        ),
        .init(
            role: .illustration,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 600
        ),
        .init(
            role: .caution,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 650,
            paddingBlockEm: 0.72,
            paddingInlineEm: 0.88
        ),
        .init(
            role: .folded,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 550,
            contentIndentEm: 0.5
        ),
        .init(
            role: .quotation,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            titleWeight: 600,
            quotationScale: 1.03,
            attributionScale: 0.82
        ),
        .init(
            role: .source,
            inlineInsetEm: 0,
            blockGapEm: 1.18,
            fontScale: 0.95,
            titleWeight: 650,
            paddingBlockEm: 0.72,
            paddingInlineEm: 0.88
        ),
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
