import Foundation
import ScholiumContracts
import SwiftUI

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
