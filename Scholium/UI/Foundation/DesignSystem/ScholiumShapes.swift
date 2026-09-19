import Foundation

enum ScholiumCornerRole: CaseIterable, Hashable, Sendable {
    case inlineStatus
    case editorialControl
    case segmentedControl
    case workspaceNavigation
    case editorialPanel
    case loadingSurface
    case editorialTextEditor
    case boundedPanel
    case documentCodeBlock
    case documentCalloutSurface
    case documentMarkHighlight
    case documentInlineCode
    case documentEmbeddedNote
    case documentControl
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
        case .documentInlineCode:
            3
        case .documentControl:
            5
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
        case .documentControl:
            "--scholium-corner-document-control"
        case .calloutDisclosureFocus:
            "--scholium-corner-callout-disclosure-focus"
        case .editorialControl, .segmentedControl, .workspaceNavigation, .editorialPanel,
            .loadingSurface:
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
