import AppKit
import Foundation
import SwiftUI

/// Semantic colors share AppKit's appearance and accessibility adaptation.
/// WebKit receives resolved snapshots of these same roles through
/// ScholiumWebDesignTokens and DocumentWebEnvironment.
enum ScholiumColorRole: String, CaseIterable, Sendable {
    case documentBackground
    case surfaceBackground
    case navigationSurfaceBackground
    case apparatusSurfaceBackground
    case raisedSurfaceBackground
    case primaryText
    case secondaryText
    case separator
    case accent
    case information
    case attention
    case destructive
    case confirmed
    case agentAuthorship
    case comparisonRemoval
    case comparisonInsertion
    case comparisonRemovalBackground
    case comparisonInsertionBackground

    var cssVariableName: String { "--scholium-color-\(rawValue.kebabCased)" }
    var color: Color { Color(nsColor: nsColor) }
    func color(increasedContrast: Bool) -> Color {
        Color(nsColor: nsColor(increasedContrast: increasedContrast))
    }
    var nsColor: NSColor { makeNSColor(increasedContrast: nil) }
    func nsColor(increasedContrast: Bool) -> NSColor {
        makeNSColor(increasedContrast: increasedContrast)
    }

    /// The Sidebar's visual effect is owned by NSSplitViewItem. Its color role
    /// is only a semantic fallback for content outside that material.
    private var systemColor: NSColor {
        switch self {
        case .documentBackground: .textBackgroundColor
        case .surfaceBackground, .navigationSurfaceBackground,
             .apparatusSurfaceBackground: .windowBackgroundColor
        case .raisedSurfaceBackground: .underPageBackgroundColor
        case .primaryText: .labelColor
        // The native secondary label is below 4.5:1 on a light text surface.
        // Move it just toward the native label to keep small WebKit text readable.
        case .secondaryText:
            .secondaryLabelColor.blended(withFraction: 0.15, of: .labelColor) ?? .labelColor
        case .separator: .separatorColor
        case .accent: .controlAccentColor
        case .information: .systemBlue
        case .attention: .systemOrange
        case .destructive, .comparisonRemoval: .systemRed
        case .confirmed, .comparisonInsertion: .systemGreen
        case .agentAuthorship: .systemPurple
        case .comparisonRemovalBackground: .systemRed.withAlphaComponent(0.13)
        case .comparisonInsertionBackground: .systemGreen.withAlphaComponent(0.13)
        }
    }

    private func makeNSColor(increasedContrast: Bool?) -> NSColor {
        NSColor(name: nil) { appearance in
            let resolvedAppearance = Self.appearance(
                matching: appearance,
                increasedContrast: increasedContrast
                    ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            )
            var resolved = NSColor.clear
            resolvedAppearance.performAsCurrentDrawingAppearance {
                resolved = systemColor.usingColorSpace(.sRGB) ?? systemColor
            }
            return resolved
        }
    }

    func resolvedRGBValue(for appearance: NSAppearance, increasedContrast: Bool) -> UInt32 {
        let resolvedAppearance = Self.appearance(
            matching: appearance, increasedContrast: increasedContrast
        )
        var value: UInt32 = 0
        resolvedAppearance.performAsCurrentDrawingAppearance {
            let roleColor = systemColor.usingColorSpace(.sRGB) ?? .black
            let background = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white
            value = Self.rgbValue(of: roleColor, over: background)
        }
        return value
    }

    func resolvedRGBValue(isDark: Bool, increasedContrast: Bool) -> UInt32 {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        return resolvedRGBValue(for: appearance, increasedContrast: increasedContrast)
    }

    static func systemAccentRGBValue(for appearance: NSAppearance) -> UInt32 {
        ScholiumColorRole.accent.resolvedRGBValue(
            for: appearance, increasedContrast: false
        )
    }

    static func calloutTitleRGBValue(
        _ role: String, isDark: Bool, increasedContrast: Bool
    ) -> UInt32 {
        let color: NSColor = switch role {
        case "orient": .systemBlue
        case "cite": .systemIndigo
        case "connect": .systemTeal
        case "state": .systemPurple
        case "illustrate": .systemBrown
        case "flag": .systemGray
        default: .secondaryLabelColor
        }
        let appearance = Self.appearance(
            matching: NSAppearance(named: isDark ? .darkAqua : .aqua)!,
            increasedContrast: increasedContrast
        )
        var value: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            value = Self.rgbValue(
                of: color.usingColorSpace(.sRGB) ?? .black,
                over: NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? .white
            )
        }
        return value
    }

    private static func appearance(
        matching appearance: NSAppearance, increasedContrast: Bool
    ) -> NSAppearance {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name: NSAppearance.Name = increasedContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        return NSAppearance(named: name) ?? appearance
    }

    private static func rgbValue(of color: NSColor, over background: NSColor) -> UInt32 {
        let alpha = color.alphaComponent
        let red = color.redComponent * alpha + background.redComponent * (1 - alpha)
        let green = color.greenComponent * alpha + background.greenComponent * (1 - alpha)
        let blue = color.blueComponent * alpha + background.blueComponent * (1 - alpha)
        return (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
    }
}

/// System-owned colors for native effects and status surfaces.
enum ScholiumNativeColorRole: Sendable {
    case label, secondaryLabel, windowBackground, controlBackground, textBackground, controlAccent
    case searchMatchHighlight
    case inactiveTextSelection
    case structuralShadow
    case unreadAction, importantAction, archiveAction

    var nsColor: NSColor {
        switch self {
        case .label: .labelColor
        case .secondaryLabel: .secondaryLabelColor
        case .windowBackground: .windowBackgroundColor
        case .controlBackground: .controlBackgroundColor
        case .textBackground: .textBackgroundColor
        case .controlAccent: .controlAccentColor
        case .searchMatchHighlight: .findHighlightColor
        case .inactiveTextSelection: .unemphasizedSelectedTextBackgroundColor
        case .structuralShadow: .shadowColor
        case .unreadAction: .systemBlue
        case .importantAction: .systemOrange
        case .archiveAction: .systemPurple
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

extension String {
    fileprivate var kebabCased: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append("-")
            }
            result.append(String(scalar).lowercased())
        }
    }
}
