import AppKit
import SwiftUI

/// Image labels survive native Menu hosting without a second overlay or
/// accessibility element. All composer glyphs use one square drawing boundary.
struct AgentChatComposerIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    enum Content {
        case add
        case context(Double?)
        case reasoning(Double)
        case action(String)
    }

    let content: Content

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: diameter, height: diameter)
            .foregroundStyle(ink)
            .accessibilityHidden(true)
    }

    private var diameter: CGFloat { ScholiumMetrics.AgentChat.composerControlVisualDiameter }

    private var image: Image {
        switch content {
        case .add:
            Image(nsImage: addImage)
        case .context, .reasoning:
            Image(nsImage: indicatorImage)
        case .action(let symbol):
            Image(systemName: symbol)
        }
    }

    private var ink: Color {
        if case .action = content {
            return Color(nsColor: isEnabled ? .controlAccentColor : .disabledControlTextColor)
        }
        return Color(nsColor: isEnabled && isEmphasized ? .labelColor : .secondaryLabelColor)
    }

    private var addImage: NSImage {
        let symbol = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: diameter, weight: .light))
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            if let symbol {
                // SF Symbols include typographic ascent/descent padding.
                // Normalize the square Add glyph to its optical cap height.
                let side = symbol.alignmentRect.height
                let source = CGRect(
                    x: (symbol.size.width - side) / 2,
                    y: symbol.alignmentRect.midY - side / 2, width: side, height: side)
                // The open cross needs less optical span than the circular controls.
                // Scaling its ink together also lightens the stroke without changing the hit target.
                let inset = (rect.width - ScholiumGrid.Dimension.iconTrackWidth) / 2
                symbol.draw(in: rect.insetBy(dx: inset, dy: inset), from: source, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private var indicatorImage: NSImage {
        let content = content
        let width = ScholiumMetrics.AgentChat.composerControlStrokeWidth
        let appearance = NSAppearance(
            named: colorScheme == .dark
                ? (contrast == .increased ? .accessibilityHighContrastDarkAqua : .darkAqua)
                : (contrast == .increased ? .accessibilityHighContrastAqua : .aqua))
        return NSImage(size: NSSize(width: diameter, height: diameter), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            appearance?.performAsCurrentDrawingAppearance {
                let radius = (rect.width - width) / 2
                var center = CGPoint(x: rect.midX, y: rect.midY)
                context.setLineWidth(width)
                context.setLineCap(.round)

                func arc(from start: Double, through sweep: Double, color: NSColor) {
                    context.setStrokeColor(color.cgColor)
                    context.beginPath()
                    context.addArc(
                        center: center, radius: radius,
                        startAngle: start, endAngle: start + sweep, clockwise: false)
                    context.strokePath()
                }

                switch content {
                case .add, .action: break
                case .context(let fraction):
                    arc(from: -.pi / 2, through: .pi * 2, color: .tertiaryLabelColor)
                    if let fraction {
                        if fraction > 0 {
                            arc(from: -.pi / 2, through: .pi * 2 * min(max(fraction, 0), 1), color: .secondaryLabelColor)
                        }
                    } else {
                        context.setLineDash(phase: 0, lengths: [width, width * 2])
                        arc(from: -.pi / 2, through: .pi * 2, color: .secondaryLabelColor)
                    }
                case .reasoning(let level):
                    // Center the visible open arc's bounding box, not its missing
                    // lower quadrant, on the other controls' center line.
                    center.y += radius * (1 - sin(.pi / 4)) / 2
                    let start = Double.pi * 3 / 4
                    let sweep = Double.pi * 3 / 2
                    let extent = sweep * min(max(level, 0), 1)
                    arc(from: start, through: sweep, color: .tertiaryLabelColor)
                    if extent > 0 { arc(from: start, through: extent, color: .controlAccentColor) }
                    let angle = start + extent
                    let needleLength = radius - width
                    context.setStrokeColor(NSColor.labelColor.cgColor)
                    context.beginPath()
                    context.move(to: center)
                    context.addLine(
                        to: CGPoint(
                            x: center.x + cos(angle) * needleLength,
                            y: center.y + sin(angle) * needleLength))
                    context.strokePath()
                    context.setFillColor(NSColor.labelColor.cgColor)
                    context.fillEllipse(
                        in: CGRect(
                            x: center.x - width / 2, y: center.y - width / 2,
                            width: width, height: width))
                }
            }
            return true
        }
    }
}

extension View {
    /// Put this inside a Menu label as well as on the control so its native
    /// button-style activation includes the whitespace around the glyph.
    func agentChatComposerControl() -> some View {
        frame(
            width: ScholiumGrid.Dimension.preferredCustomTarget,
            height: ScholiumGrid.Dimension.preferredCustomTarget
        )
        .contentShape(.rect)
    }
}
