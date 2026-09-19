import AppKit
import Foundation
import SwiftUI

/// The shared shallow interaction surface for Scholium-owned controls inside
/// content regions. Hover uses one translucent semantic-ink veil so its
/// relative light/dark response follows the native toolbar on every underlying
/// plane, while keyboard focus retains a stronger raised blend. Native and
/// WebKit consumers share these exact semantic mixes while each component keeps
/// its own shape, geometry, focus, and lifecycle.
enum ScholiumContentInteractionSurface {
    private static let hoverOpacity: CGFloat = 0.05
    private static let increasedContrastHoverOpacity: CGFloat = 0.075
    private static let keyboardFocusOpacity: CGFloat = 0.42
    private static let increasedContrastKeyboardFocusOpacity: CGFloat = 0.56

    static let webCSSDeclarations = webCSSDeclarations(increasedContrast: false)
    static let increasedContrastWebCSSDeclarations = webCSSDeclarations(
        increasedContrast: true
    )

    static func opacity(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> CGFloat {
        if isFocused {
            return increasedContrast
                ? increasedContrastKeyboardFocusOpacity
                : keyboardFocusOpacity
        }
        if isHovering || isPressed {
            return increasedContrast
                ? increasedContrastHoverOpacity
                : hoverOpacity
        }
        return 0
    }

    static func color(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> Color {
        surfaceRole(isFocused: isFocused)
            .color(increasedContrast: increasedContrast)
            .opacity(
                opacity(
                    isHovering: isHovering,
                    isFocused: isFocused,
                    isPressed: isPressed,
                    increasedContrast: increasedContrast
                ))
    }

    /// Persistent local selection uses the same shallow editorial surface as
    /// transient hover and keyboard focus. It adds no Accent underline, glass,
    /// or filled segmented-control band.
    static func selectionColor(
        isSelected: Bool,
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> Color {
        if isSelected {
            return ScholiumColorRole.raisedSurfaceBackground
                .color(increasedContrast: increasedContrast)
        }
        return color(
            isHovering: isHovering,
            isFocused: isFocused,
            isPressed: isPressed,
            increasedContrast: increasedContrast
        )
    }

    static func nsColor(
        isHovering: Bool,
        isFocused: Bool,
        isPressed: Bool = false,
        increasedContrast: Bool
    ) -> NSColor {
        surfaceRole(isFocused: isFocused)
            .nsColor(increasedContrast: increasedContrast)
            .withAlphaComponent(
                opacity(
                    isHovering: isHovering,
                    isFocused: isFocused,
                    isPressed: isPressed,
                    increasedContrast: increasedContrast
                ))
    }

    private static func surfaceRole(isFocused: Bool) -> ScholiumColorRole {
        isFocused ? .raisedSurfaceBackground : .primaryText
    }

    private static func webCSSDeclarations(increasedContrast: Bool) -> String {
        let hoverPercentage = cssPercentage(
            opacity(
                isHovering: true,
                isFocused: false,
                increasedContrast: increasedContrast
            ))
        let focusPercentage = cssPercentage(
            opacity(
                isHovering: false,
                isFocused: true,
                increasedContrast: increasedContrast
            ))
        return """
            --scholium-content-hover-surface: color-mix(
              in srgb,
              var(--scholium-color-primary-text) \(hoverPercentage)%,
              transparent
            );
            --scholium-content-keyboard-focus-surface: color-mix(
              in srgb,
              var(--scholium-color-raised-surface-background) \(focusPercentage)%,
              transparent
            );
            --scholium-content-focus-ring: var(--scholium-color-accent);
            """
    }

    private static func cssPercentage(_ opacity: CGFloat) -> String {
        String(
            format: "%.4g",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(opacity * 100)
        )
    }
}

enum ScholiumSurfaceRole: CaseIterable, Hashable, Sendable {
    case document
    case navigation
    case apparatus
    case floatingControl
    case boundedPanel
    case denseEvidence

    var colorRole: ScholiumColorRole {
        switch self {
        case .document: .documentBackground
        case .navigation: .navigationSurfaceBackground
        case .apparatus: .apparatusSurfaceBackground
        case .floatingControl, .boundedPanel: .surfaceBackground
        case .denseEvidence: .documentBackground
        }
    }

    var defaultBoundaryRole: ScholiumBoundaryRole {
        switch self {
        case .floatingControl:
            .floatingBoundary
        case .document, .navigation, .apparatus, .boundedPanel, .denseEvidence:
            .subtleBoundary
        }
    }

    var defaultElevationRole: ScholiumElevationRole? {
        switch self {
        case .floatingControl:
            .floatingControl
        case .boundedPanel:
            nil
        case .document, .navigation, .apparatus, .denseEvidence:
            nil
        }
    }
}

struct ScholiumElevationStyle: Equatable, Sendable {
    let opacity: Double
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum ScholiumElevationRole: CaseIterable, Sendable {
    case floatingControl
    case boundedPanel

    var cssVariableName: String {
        switch self {
        case .floatingControl: "--scholium-elevation-floating-control"
        case .boundedPanel: "--scholium-elevation-bounded-panel"
        }
    }

    func style(
        increasedContrast: Bool,
        reduceTransparency: Bool,
        appearsActive: Bool
    ) -> ScholiumElevationStyle {
        let recipe: ScholiumElevationStyle =
            switch self {
            case .floatingControl:
                .init(opacity: 0.04, radius: 4, x: 0, y: 2)
            case .boundedPanel:
                .init(opacity: 0.08, radius: 8, x: 0, y: 4)
            }
        let contrastMultiplier = increasedContrast ? 0.0 : 1.0
        let transparencyMultiplier = reduceTransparency ? 0.5 : 1.0
        let activityMultiplier = appearsActive ? 1.0 : 0.6
        return .init(
            opacity: recipe.opacity
                * contrastMultiplier
                * transparencyMultiplier
                * activityMultiplier,
            radius: recipe.radius,
            x: recipe.x,
            y: recipe.y
        )
    }

    /// WebKit consumes the same semantic recipe in CSS pixels. This is a
    /// renderer-specific resolution, not a macOS-point-to-CSS-pixel conversion.
    func cssBoxShadow(
        increasedContrast: Bool,
        reduceTransparency: Bool
    ) -> String {
        let style = style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency,
            appearsActive: true
        )
        guard style.opacity > 0 else { return "none" }
        return String(
            format: "%gpx %gpx %gpx rgb(0 0 0 / %.4f)",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(style.x),
            Double(style.y),
            Double(style.radius),
            style.opacity
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
            .init(
                colorRole: .separator, opacity: emphasized ? 0.78 : 0.42,
                lineWidth: emphasized ? 1 : 0.5)
        case .subtleBoundary:
            .init(
                colorRole: .separator, opacity: emphasized ? 0.82 : 0.34,
                lineWidth: emphasized ? 1 : 0.75)
        case .floatingBoundary:
            .init(
                colorRole: .separator, opacity: emphasized ? 0.82 : 0.34,
                lineWidth: emphasized ? 1 : 0.75)
        }
    }
}
