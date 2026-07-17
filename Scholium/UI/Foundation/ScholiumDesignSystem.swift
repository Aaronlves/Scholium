import ScholiumContracts
import AppKit
import SwiftUI

/// Semantic interface colors shared by native call sites and the WebKit
/// document surfaces. Call sites choose a role; each platform resolves that
/// role through its own appearance-aware color system.
enum ScholiumColorRole: String, CaseIterable, Sendable {
    case documentBackground
    case navigationBackground
    case surfaceBackground
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
    case attentionForeground
    case destructive
    case destructiveForeground
    case confirmed
    case confirmedForeground
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
        let variants: DynamicColorVariants = switch self {
        case .documentBackground:
            Self.paletteVariants(
                light: .background,
                dark: .background
            )
        case .navigationBackground:
            Self.paletteVariants(
                light: .navigation,
                dark: .navigation
            )
        case .surfaceBackground:
            Self.paletteVariants(
                light: .surface,
                dark: .surface
            )
        case .raisedSurfaceBackground:
            Self.paletteVariants(
                light: .surfaceRaised,
                dark: .surfaceRaised,
                increasedContrastLight: ScholiumLightPalette.border.rawValue
            )
        case .primaryText:
            Self.paletteVariants(
                light: .textPrimary,
                dark: .textPrimary
            )
        case .secondaryText:
            Self.paletteVariants(
                light: .textSecondary,
                dark: .textSecondary,
                increasedContrastLight: ScholiumLightPalette.textPrimary.rawValue,
                increasedContrastDark: ScholiumDarkPalette.textPrimary.rawValue
            )
        case .mutedText:
            Self.paletteVariants(
                light: .neutral,
                dark: .neutral,
                increasedContrastLight: ScholiumLightPalette.textSecondary.rawValue,
                increasedContrastDark: ScholiumDarkPalette.textSecondary.rawValue
            )
        case .separator:
            Self.paletteVariants(
                light: .border,
                dark: .border,
                increasedContrastLight: ScholiumLightPalette.neutral.rawValue,
                increasedContrastDark: ScholiumDarkPalette.neutral.rawValue
            )
        case .accent:
            Self.paletteVariants(
                light: .primary,
                dark: .primary,
                increasedContrastLight: ScholiumLightPalette.primaryHover.rawValue,
                increasedContrastDark: ScholiumDarkPalette.primaryHover.rawValue
            )
        case .accentHover:
            Self.paletteVariants(
                light: .primaryHover,
                dark: .primaryHover
            )
        case .notificationHighlight:
            Self.paletteVariants(
                light: .notificationHighlight,
                dark: .notificationHighlight,
                increasedContrastLight: ScholiumLightPalette.attention.rawValue,
                increasedContrastDark: 0xF1C96D
            )
        case .information:
            Self.paletteVariants(
                light: .information,
                dark: .information,
                increasedContrastLight: 0x214D68,
                increasedContrastDark: 0xA7CCE6
            )
        case .attention:
            Self.attentionVariants
        case .attentionForeground:
            Self.attentionVariants
        case .destructive:
            Self.destructiveVariants
        case .destructiveForeground:
            Self.destructiveVariants
        case .confirmed:
            Self.confirmedVariants
        case .confirmedForeground:
            Self.confirmedVariants
        case .agentAuthorship:
            Self.paletteVariants(
                light: .agentAuthorship,
                dark: .agentAuthorship,
                increasedContrastLight: 0x493D72,
                increasedContrastDark: 0xD0C3EA
            )
        case .connectionNeutral:
            Self.paletteVariants(
                light: .primary,
                dark: .primary,
                increasedContrastLight: ScholiumLightPalette.primaryHover.rawValue,
                increasedContrastDark: ScholiumDarkPalette.primaryHover.rawValue
            )
        case .connectionSupport:
            Self.connectionSupportVariants
        case .connectionIncompatible:
            Self.connectionIncompatibleVariants
        }
        return Self.dynamicColor(from: variants, increasedContrast: increasedContrast)
    }

    func resolvedCustomRGBValue(
        for appearance: NSAppearance,
        increasedContrast: Bool
    ) -> UInt32? {
        switch self {
        case .connectionSupport:
            Self.connectionSupportVariants.value(
                for: appearance,
                increasedContrast: increasedContrast
            )
        case .connectionIncompatible:
            Self.connectionIncompatibleVariants.value(
                for: appearance,
                increasedContrast: increasedContrast
            )
        default:
            nil
        }
    }

    private static let connectionSupportVariants = DynamicColorVariants(
        light: ScholiumLightPalette.connectionSupport.rawValue,
        dark: ScholiumDarkPalette.connectionSupport.rawValue,
        increasedContrastLight: 0x195A54,
        increasedContrastDark: 0x9CD5CA
    )

    private static let connectionIncompatibleVariants = DynamicColorVariants(
        light: ScholiumLightPalette.connectionIncompatible.rawValue,
        dark: ScholiumDarkPalette.connectionIncompatible.rawValue,
        increasedContrastLight: 0x50365F,
        increasedContrastDark: 0xDDBCE5
    )

    private static let attentionVariants = paletteVariants(
        light: .attention,
        dark: .attention,
        increasedContrastLight: 0x70420B,
        increasedContrastDark: 0xF0C07A
    )

    private static let destructiveVariants = paletteVariants(
        light: .destructive,
        dark: .destructive,
        increasedContrastLight: 0x7F2528,
        increasedContrastDark: 0xF3A09C
    )

    private static let confirmedVariants = paletteVariants(
        light: .confirmed,
        dark: .confirmed,
        increasedContrastLight: 0x1F5838,
        increasedContrastDark: 0x9CD7AF
    )

    private static func paletteVariants(
        light: ScholiumLightPalette,
        dark: ScholiumDarkPalette,
        increasedContrastLight: UInt32? = nil,
        increasedContrastDark: UInt32? = nil
    ) -> DynamicColorVariants {
        DynamicColorVariants(
            light: light.rawValue,
            dark: dark.rawValue,
            increasedContrastLight: increasedContrastLight ?? light.rawValue,
            increasedContrastDark: increasedContrastDark ?? dark.rawValue
        )
    }

    private static func dynamicColor(
        from variants: DynamicColorVariants,
        increasedContrast: Bool?
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            rgb(variants.value(
                for: appearance,
                increasedContrast: increasedContrast
                    ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ))
        }
    }

    private struct DynamicColorVariants: Sendable {
        let light: UInt32
        let dark: UInt32
        let increasedContrastLight: UInt32
        let increasedContrastDark: UInt32

        func value(for appearance: NSAppearance, increasedContrast: Bool) -> UInt32 {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if increasedContrast {
                return isDark ? increasedContrastDark : increasedContrastLight
            }
            return isDark ? dark : light
        }
    }

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// One visual and accessible vocabulary for explicit Markdown Connections.
/// Standard command symbols remain direct SF Symbols at their call sites.
enum ScholiumConnectionPresentation: Int, CaseIterable, Identifiable, Sendable {
    case supports
    case supportedBy
    case incompatible
    case neutral

    var id: Self { self }

    init(vectorKind: VectorLinkKind?, currentIsSource: Bool) {
        self = switch vectorKind {
        case .supportsTarget:
            currentIsSource ? .supports : .supportedBy
        case .supportedByTarget:
            currentIsSource ? .supportedBy : .supports
        case .incompatible:
            .incompatible
        case .neutral, .none:
            .neutral
        }
    }

    var title: String {
        switch self {
        case .supports: "Supports"
        case .supportedBy: "Supported By"
        case .incompatible: "Incompatible With"
        case .neutral: "Related"
        }
    }

    var symbolName: String {
        switch self {
        case .supports: "arrow.right.circle"
        case .supportedBy: "arrow.left.circle"
        case .incompatible: "xmark.circle"
        case .neutral: "link.circle"
        }
    }

    var colorRole: ScholiumColorRole {
        switch self {
        case .supports, .supportedBy: .connectionSupport
        case .incompatible: .connectionIncompatible
        case .neutral: .connectionNeutral
        }
    }
}

/// Reviewed light-appearance swatches. Feature code consumes semantic
/// `ScholiumColorRole` values rather than these implementation colors.
enum ScholiumLightPalette: UInt32, CaseIterable, Sendable {
    case primary = 0xA94C22
    case primaryHover = 0x7A2917
    case notificationHighlight = 0xB47617
    case neutral = 0x706B65
    case background = 0xFFFCF5
    case navigation = 0xEFE9DF
    case surface = 0xF7F1E7
    case surfaceRaised = 0xDED3C5
    case textPrimary = 0x17191C
    case textSecondary = 0x514D48
    case border = 0xC8BCAE
    case confirmed = 0x2C7048
    case attention = 0x976015
    case destructive = 0xA13235
    case information = 0x315F88
    case agentAuthorship = 0x5D568F
    case connectionSupport = 0x276F68
    case connectionIncompatible = 0x6F4D83
}

/// Reviewed dark-appearance swatches. The Cordovan navigation surface and
/// walnut document surface form an evening-library counterpart to light mode.
enum ScholiumDarkPalette: UInt32, CaseIterable, Sendable {
    case primary = 0xEF8D5B
    case primaryHover = 0xF5AA7B
    case notificationHighlight = 0xE1B64F
    case neutral = 0xB6A38F
    case background = 0x302A26
    case navigation = 0x3A2B2B
    case surface = 0x3A322D
    case surfaceRaised = 0x423831
    case textPrimary = 0xF4E8D5
    case textSecondary = 0xD4C2AD
    case border = 0x807064
    case confirmed = 0x7FC39A
    case attention = 0xE0AB61
    case destructive = 0xEA817C
    case information = 0x84B0D4
    case agentAuthorship = 0xB5A6DC
    case connectionSupport = 0x79B9AB
    case connectionIncompatible = 0xC29CCF
}

/// Contract names used by the CodeMirror and sanitized Read stylesheets.
/// Values remain platform-specific while sharing the same reviewed light and
/// dark semantic vocabulary.
enum ScholiumWebDesignTokens {
    static let colorVariableNames = Set(ScholiumColorRole.allCases.map(\.cssVariableName))

    static let rhythmCSSDeclarations = """
    --scholium-rhythm-prose-line-height: \(ScholiumDocumentRhythm.proseLineHeight);
    --scholium-rhythm-source-line-height: \(ScholiumDocumentRhythm.sourceLineHeight);
    --scholium-rhythm-paragraph-gap: \(ScholiumDocumentRhythm.paragraphGapEm)em;
    --scholium-rhythm-heading-line-height: \(ScholiumDocumentRhythm.headingLineHeight);
    --scholium-rhythm-heading-before: \(ScholiumDocumentRhythm.headingGapBeforeEm)em;
    --scholium-rhythm-heading-after: \(ScholiumDocumentRhythm.headingGapAfterEm)em;
    --scholium-rhythm-code-inset: \(ScholiumDocumentRhythm.codeBlockInset)px;
    --scholium-rhythm-quote-inset: \(ScholiumDocumentRhythm.quoteInlineInset)px;
    --scholium-rhythm-live-code-inline-inset: \(ScholiumDocumentRhythm.livePreviewCodeInlineInsetEm)em;
    --scholium-rhythm-live-quote-inline-inset: \(ScholiumDocumentRhythm.livePreviewQuoteInlineInset)px;
    --scholium-rhythm-inline-regular: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).inline)px;
    --scholium-rhythm-inline-source: \(ScholiumDocumentRhythm.contentInsets(for: .source, widthClass: .regular).inline)px;
    --scholium-rhythm-inline-narrow: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).inline)px;
    --scholium-rhythm-read-block-start: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).blockStart)px;
    --scholium-rhythm-read-narrow-block-start: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .narrow).blockStart)px;
    --scholium-rhythm-trailing-scroll: \(ScholiumDocumentRhythm.contentInsets(for: .read, widthClass: .regular).trailingViewportFraction * 100)vh;
    """

    static let rootCSSDeclarations = """
    --scholium-color-document-background: #fffcf5;
    --scholium-color-navigation-background: #efe9df;
    --scholium-color-surface-background: #f7f1e7;
    --scholium-color-raised-surface-background: #ded3c5;
    --scholium-color-primary-text: #17191c;
    --scholium-color-secondary-text: #514d48;
    --scholium-color-muted-text: #706b65;
    --scholium-color-separator: #c8bcae;
    --scholium-color-accent: #a94c22;
    --scholium-color-accent-hover: #7a2917;
    --scholium-color-notification-highlight: #b47617;
    --scholium-color-information: #315f88;
    --scholium-color-attention: #976015;
    --scholium-color-attention-foreground: #976015;
    --scholium-color-destructive: #a13235;
    --scholium-color-destructive-foreground: #a13235;
    --scholium-color-confirmed: #2c7048;
    --scholium-color-confirmed-foreground: #2c7048;
    --scholium-color-agent-authorship: #5d568f;
    --scholium-color-connection-neutral: #a94c22;
    --scholium-color-connection-support: #276f68;
    --scholium-color-connection-incompatible: #6f4d83;
    """

    static let darkAppearanceCSSDeclarations = """
    --scholium-color-document-background: #302a26;
    --scholium-color-navigation-background: #3a2b2b;
    --scholium-color-surface-background: #3a322d;
    --scholium-color-raised-surface-background: #423831;
    --scholium-color-primary-text: #f4e8d5;
    --scholium-color-secondary-text: #d4c2ad;
    --scholium-color-muted-text: #b6a38f;
    --scholium-color-separator: #807064;
    --scholium-color-accent: #ef8d5b;
    --scholium-color-accent-hover: #f5aa7b;
    --scholium-color-notification-highlight: #e1b64f;
    --scholium-color-information: #84b0d4;
    --scholium-color-attention: #e0ab61;
    --scholium-color-attention-foreground: #e0ab61;
    --scholium-color-destructive: #ea817c;
    --scholium-color-destructive-foreground: #ea817c;
    --scholium-color-confirmed: #7fc39a;
    --scholium-color-confirmed-foreground: #7fc39a;
    --scholium-color-agent-authorship: #b5a6dc;
    --scholium-color-connection-neutral: #ef8d5b;
    --scholium-color-connection-support: #79b9ab;
    --scholium-color-connection-incompatible: #c29ccf;
    """

    static let increasedContrastCSSDeclarations = """
    --scholium-color-raised-surface-background: #c8bcae;
    --scholium-color-secondary-text: #17191c;
    --scholium-color-muted-text: #514d48;
    --scholium-color-separator: #706b65;
    --scholium-color-accent: #7a2917;
    --scholium-color-notification-highlight: #976015;
    --scholium-color-information: #214d68;
    --scholium-color-attention: #70420b;
    --scholium-color-attention-foreground: #70420b;
    --scholium-color-destructive: #7f2528;
    --scholium-color-destructive-foreground: #7f2528;
    --scholium-color-confirmed: #1f5838;
    --scholium-color-confirmed-foreground: #1f5838;
    --scholium-color-agent-authorship: #493d72;
    --scholium-color-connection-neutral: #7a2917;
    --scholium-color-connection-support: #195a54;
    --scholium-color-connection-incompatible: #50365f;
    """

    static let darkIncreasedContrastCSSDeclarations = """
    \(darkAppearanceCSSDeclarations)
    --scholium-color-secondary-text: #f4e8d5;
    --scholium-color-muted-text: #d4c2ad;
    --scholium-color-separator: #b6a38f;
    --scholium-color-accent: #f5aa7b;
    --scholium-color-notification-highlight: #f1c96d;
    --scholium-color-information: #a7cce6;
    --scholium-color-attention: #f0c07a;
    --scholium-color-attention-foreground: #f0c07a;
    --scholium-color-destructive: #f3a09c;
    --scholium-color-destructive-foreground: #f3a09c;
    --scholium-color-confirmed: #9cd7af;
    --scholium-color-confirmed-foreground: #9cd7af;
    --scholium-color-agent-authorship: #d0c3ea;
    --scholium-color-connection-neutral: #f5aa7b;
    --scholium-color-connection-support: #9cd5ca;
    --scholium-color-connection-incompatible: #ddbce5;
    """
}

enum ScholiumMetrics {
    enum Accessibility {
        static let preferredCustomTarget: CGFloat = 28
        static let minimumCustomTarget: CGFloat = 20
    }

    enum Onboarding {
        static let minimumWidth: CGFloat = 320
        static let minimumHeight: CGFloat = 560
        static let preferredWidth: CGFloat = 360
        static let preferredHeight: CGFloat = 720
    }

    enum Triptych {
        static let minimumWidth: CGFloat = 300
        static let preferredWidth: CGFloat = 360
    }

    enum Navigation {
        static let panelInset: CGFloat = 10
        static let panelCornerRadius: CGFloat = 18
    }

    enum Workspace {
        static let minimumWidth: CGFloat = 760
        static let minimumHeight: CGFloat = 520
        static let preferredWidth: CGFloat = 1_180
        static let preferredHeight: CGFloat = 760
    }

    enum Document {
        static let readableMeasure: CGFloat = 920
    }

    enum Search {
        static let preferredWidth: CGFloat = 640
        static let maximumWidth: CGFloat = 720
        static let collapsedHeight: CGFloat = 116
        static let resultRowHeight: CGFloat = 64
        static let expandedHeight: CGFloat = 520
        static let scopeWidth: CGFloat = 320
        static let responsiveMargin: CGFloat = 24
        static let cornerRadius: CGFloat = 24
    }

    enum ContextSurface {
        static let controlHeight: CGFloat = 40
        static let leadingControlsWidth: CGFloat = 78
        static let columnSpacing: CGFloat = 10
        static let metadataMeasure = Document.readableMeasure - leadingControlsWidth - columnSpacing
        static let clusterMeasure = Document.readableMeasure
        /// Scrolling document content begins below the floating context cluster.
        /// Because this is content padding rather than a safe-area inset, the
        /// clearance moves away and later prose can travel beneath the cluster.
        static let initialOverlayClearance: CGFloat = 92
    }
}

enum ScholiumShape {
    static let inlineStatusCornerRadius: CGFloat = 10
    static let floatingControlCornerRadius: CGFloat = 12
    static let loadingSurfaceCornerRadius: CGFloat = 16
}

enum ScholiumSurfaceRole: CaseIterable, Hashable, Sendable {
    case document
    case navigation
    case floatingControl
    case boundedPanel
    case searchOverlay
    case denseEvidence

    var colorRole: ScholiumColorRole {
        switch self {
        case .document: .documentBackground
        case .navigation: .navigationBackground
        case .floatingControl, .boundedPanel, .searchOverlay: .surfaceBackground
        case .denseEvidence: .documentBackground
        }
    }


    var usesLiquidGlass: Bool {
        self == .floatingControl || self == .searchOverlay
    }

    var usesMaterial: Bool {
        self == .navigation || self == .boundedPanel
    }

    var isOpaque: Bool {
        self == .document || self == .denseEvidence
    }
}

struct ScholiumElevationStyle: Equatable, Sendable {
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum ScholiumElevationRole: CaseIterable, Sendable {
    case triptychEdge
    case floatingControl
    case boundedPanel
    case searchOverlay

    func style(reduceTransparency: Bool, appearsActive: Bool) -> ScholiumElevationStyle {
        let recipe: ScholiumElevationStyle = switch self {
        case .triptychEdge:
            .init(opacity: 0.14, radius: 10, x: 5, y: 0)
        case .floatingControl:
            .init(opacity: 0.10, radius: 10, x: 0, y: 4)
        case .boundedPanel:
            .init(opacity: 0.08, radius: 12, x: 0, y: 4)
        case .searchOverlay:
            .init(opacity: 0.20, radius: 22, x: 0, y: 12)
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
            .init(colorRole: .separator, opacity: emphasized ? 0.78 : 0.24, lineWidth: emphasized ? 1 : 0.5)
        case .subtleBoundary:
            .init(colorRole: .separator, opacity: emphasized ? 0.82 : 0.34, lineWidth: emphasized ? 1 : 0.75)
        case .floatingBoundary:
            .init(colorRole: .separator, opacity: emphasized ? 0.82 : 0, lineWidth: emphasized ? 1 : 0)
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

struct ScholiumDocumentContentInsets: Equatable, Sendable {
    let inline: CGFloat
    let blockStart: CGFloat
    let trailingViewportFraction: CGFloat
}

/// Provisional values shared by Read and editor renderers. They remain
/// renderer-aware until the visual comparison freezes the rhythm contract.
enum ScholiumDocumentRhythm {
    static let proseLineHeight = 1.58
    static let sourceLineHeight = 1.5
    static let paragraphGapEm = 0.7
    static let headingLineHeight = 1.18
    static let headingGapBeforeEm = 1.45
    static let headingGapAfterEm = 0.55
    static let codeBlockInset: CGFloat = 16
    static let quoteInlineInset: CGFloat = 18
    static let livePreviewCodeInlineInsetEm = 0.8
    static let livePreviewQuoteInlineInset: CGFloat = 12

    static func lineHeight(for renderer: ScholiumDocumentRenderer) -> Double {
        renderer == .source ? sourceLineHeight : proseLineHeight
    }

    static func contentInsets(
        for renderer: ScholiumDocumentRenderer,
        widthClass: ScholiumDocumentWidthClass
    ) -> ScholiumDocumentContentInsets {
        let inline: CGFloat = switch (renderer, widthClass) {
        case (.source, .regular): 42
        case (.read, .regular), (.livePreview, .regular): 54
        case (_, .narrow): 24
        }
        let blockStart: CGFloat = switch renderer {
        case .read: widthClass == .narrow ? 28 : 44
        case .livePreview, .source: ScholiumMetrics.ContextSurface.initialOverlayClearance
        }
        return .init(inline: inline, blockStart: blockStart, trailingViewportFraction: 0.45)
    }
}

private struct ScholiumSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let role: ScholiumSurfaceRole

    func body(content: Content) -> some View {
        content.background {
            if role.usesMaterial, !reduceTransparency {
                Rectangle().fill(.regularMaterial)
            } else {
                Rectangle().fill(role.colorRole.color(
                    increasedContrast: colorSchemeContrast == .increased
                ))
            }
        }
    }
}

private struct ScholiumElevationModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appearsActive) private var appearsActive
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let role: ScholiumBoundaryRole
    let shape: S

    func body(content: Content) -> some View {
        let style = role.style(
            increasedContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency
        )
        content.overlay {
            shape.strokeBorder(
                style.colorRole.color(
                    increasedContrast: colorSchemeContrast == .increased
                ).opacity(style.opacity),
                lineWidth: style.lineWidth
            )
            .allowsHitTesting(false)
        }
    }
}

private struct ScholiumGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let role: ScholiumSurfaceRole
    let boundary: ScholiumBoundaryRole
    let elevation: ScholiumElevationRole
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        let boundaryStyle = boundary.style(
            increasedContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency
        )
        content
            .background(
                reduceTransparency ? role.colorRole.color(
                    increasedContrast: colorSchemeContrast == .increased
                ) : Color.clear,
                in: shape
            )
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            .overlay {
                shape.strokeBorder(
                    boundaryStyle.colorRole.color(
                        increasedContrast: colorSchemeContrast == .increased
                    ).opacity(boundaryStyle.opacity),
                    lineWidth: boundaryStyle.lineWidth
                )
                .allowsHitTesting(false)
            }
            .scholiumElevation(elevation)
    }
}

private struct ScholiumMaterialSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let role: ScholiumSurfaceRole
    let boundary: ScholiumBoundaryRole
    let elevation: ScholiumElevationRole
    let shape: S

    func body(content: Content) -> some View {
        let boundaryStyle = boundary.style(
            increasedContrast: colorSchemeContrast == .increased,
            reduceTransparency: reduceTransparency
        )
        content
            .background {
                if reduceTransparency {
                    shape.fill(role.colorRole.color(
                        increasedContrast: colorSchemeContrast == .increased
                    ))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    boundaryStyle.colorRole.color(
                        increasedContrast: colorSchemeContrast == .increased
                    ).opacity(boundaryStyle.opacity),
                    lineWidth: boundaryStyle.lineWidth
                )
                .allowsHitTesting(false)
            }
            .scholiumElevation(elevation)
    }
}

private struct ScholiumForegroundModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let role: ScholiumColorRole

    func body(content: Content) -> some View {
        content.foregroundStyle(role.color(
            increasedContrast: colorSchemeContrast == .increased
        ))
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
        reduceMotion ? nil : .easeInOut(duration: 0.18)
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

    func scholiumGlassSurface<S: InsettableShape>(
        _ role: ScholiumSurfaceRole,
        in shape: S,
        boundary: ScholiumBoundaryRole = .floatingBoundary,
        elevation: ScholiumElevationRole = .floatingControl,
        interactive: Bool = false
    ) -> some View {
        modifier(ScholiumGlassSurfaceModifier(
            role: role,
            boundary: boundary,
            elevation: elevation,
            shape: shape,
            interactive: interactive
        ))
    }


    func scholiumMaterialSurface<S: InsettableShape>(
        _ role: ScholiumSurfaceRole,
        in shape: S,
        boundary: ScholiumBoundaryRole = .subtleBoundary,
        elevation: ScholiumElevationRole = .boundedPanel
    ) -> some View {
        modifier(ScholiumMaterialSurfaceModifier(
            role: role,
            boundary: boundary,
            elevation: elevation,
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
