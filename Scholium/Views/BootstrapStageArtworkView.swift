import AppKit
import SwiftUI

enum BootstrapArtworkStage: CaseIterable {
    case welcome
    case triptych
    case agent
    case ready
}

/// The four released Bootstrap compositions. These values are product assets,
/// not runtime tuning controls.
struct BootstrapStageArtworkConfiguration: Equatable {
    let stage: BootstrapArtworkStage
    let handStyle: String
    let handAssetName: String
    let narrativeShapes: String
    let constellationPattern: String
    let colorField: String
    let offsetX: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat
    let rotation: CGFloat
    let showsHand: Bool
    let showsContactTarget: Bool
    let showsSafeRegion: Bool

    static func approved(for stage: BootstrapArtworkStage) -> Self {
        switch stage {
        case .welcome:
            Self(
                stage: stage,
                handStyle: "Point",
                handAssetName: "manicule-canonical",
                narrativeShapes: "Constellation",
                constellationPattern: "Flow",
                colorField: "Golden Ochre",
                offsetX: 0,
                offsetY: 0,
                scale: 1,
                rotation: 0,
                showsHand: true,
                showsContactTarget: false,
                showsSafeRegion: false
            )
        case .triptych:
            Self(
                stage: stage,
                handStyle: "Offer",
                handAssetName: "manicule-offer-v2",
                narrativeShapes: "Constellation",
                constellationPattern: "Flow",
                colorField: "Mineral Blue",
                offsetX: -115,
                offsetY: -180,
                scale: 1.18,
                rotation: 78,
                showsHand: true,
                showsContactTarget: false,
                showsSafeRegion: false
            )
        case .agent:
            Self(
                stage: stage,
                handStyle: "Unlock Straight",
                handAssetName: "manicule-unlock-straight-v1",
                narrativeShapes: "Constellation",
                constellationPattern: "Converge",
                colorField: "Verdigris",
                offsetX: 60,
                offsetY: 0,
                scale: 1,
                rotation: 0,
                showsHand: true,
                showsContactTarget: false,
                showsSafeRegion: false
            )
        case .ready:
            Self(
                stage: stage,
                handStyle: "Lift",
                handAssetName: "manicule-lift-v1",
                narrativeShapes: "Constellation",
                constellationPattern: "Converge",
                colorField: "Oxblood",
                offsetX: 24,
                offsetY: 57,
                scale: 0.96,
                rotation: 0,
                showsHand: true,
                showsContactTarget: false,
                showsSafeRegion: false
            )
        }
    }
}

struct BootstrapStageArtwork: View {
    let stage: BootstrapArtworkStage

    private var configuration: BootstrapStageArtworkConfiguration {
        .approved(for: stage)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(fieldColor)
                    )
                    drawConstellation(in: &context, size: size)
                }

                if configuration.showsHand, let handImage {
                    let placement = maniculePlacement(in: geometry.size)
                    Image(nsImage: handImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: placement.width, height: placement.height)
                        .rotationEffect(.degrees(actualRotation))
                        .position(placement.center)
                }
            }
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var fieldColor: Color {
        switch stage {
        case .welcome: BootstrapArtworkPalette.goldenOchre
        case .triptych: BootstrapArtworkPalette.mineralBlue
        case .agent: BootstrapArtworkPalette.verdigris
        case .ready: BootstrapArtworkPalette.oxblood
        }
    }

    private var handImage: NSImage? {
        guard let url = Bundle.module.url(
            forResource: configuration.handAssetName,
            withExtension: "png"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    private var actualRotation: Double {
        switch stage {
        case .welcome: -12 + configuration.rotation
        case .triptych: -90 + configuration.rotation
        case .agent: configuration.rotation
        case .ready: -8 + configuration.rotation
        }
    }

    private func maniculePlacement(
        in size: CGSize
    ) -> (width: CGFloat, height: CGFloat, center: CGPoint) {
        let plan: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, assetScale: CGFloat, alignX: CGFloat, alignY: CGFloat)

        switch stage {
        case .welcome:
            plan = (-23, size.height * 0.68, 240, 160, 1, 0, 0)
        case .triptych:
            plan = (127, size.height * 0.685, 190, 127, 1, 0, 0)
        case .agent:
            plan = (-55, size.height * 0.385, 260, 173, 1, -74, 3)
        case .ready:
            plan = (-70, size.height * 0.46, 270, 180, 1.28, 0, 0)
        }

        let base = CGRect(
            x: plan.x,
            y: plan.y,
            width: plan.width,
            height: plan.height
        )
        return (
            width: plan.width * configuration.scale * plan.assetScale,
            height: plan.height * configuration.scale * plan.assetScale,
            center: CGPoint(
                x: base.midX + configuration.offsetX + plan.alignX,
                y: base.midY + configuration.offsetY + plan.alignY
            )
        )
    }

    private func drawConstellation(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let plan = constellationPlan
        let points = plan.points.map { point($0.x, $0.y, in: size) }

        if stage == .agent {
            var boundary = Path()
            boundary.move(to: point(0.56, 0.08, in: size))
            boundary.addLine(to: point(0.56, 0.445, in: size))
            boundary.move(to: point(0.56, 0.555, in: size))
            boundary.addLine(to: point(0.56, 0.92, in: size))
            context.stroke(
                boundary,
                with: .color(BootstrapArtworkPalette.accent),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }

        var linePath = Path()
        for (start, end) in plan.links {
            linePath.move(to: points[start])
            linePath.addLine(to: points[end])
        }
        context.stroke(
            linePath,
            with: .color(BootstrapArtworkPalette.ink),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )

        for (index, node) in points.enumerated() {
            if stage == .agent, index == plan.accentIndex {
                drawKeyhole(at: node, in: &context)
            } else {
                drawNode(
                    at: node,
                    accent: index == plan.accentIndex,
                    in: &context
                )
            }
        }
    }

    private var constellationPlan: BootstrapConstellationPlan {
        switch stage {
        case .welcome:
            BootstrapConstellationPlan(
                points: [
                    .init(x: 0.18, y: 0.16), .init(x: 0.46, y: 0.22),
                    .init(x: 0.69, y: 0.38), .init(x: 0.38, y: 0.48),
                    .init(x: 0.55, y: 0.70), .init(x: 0.42, y: 0.89),
                ],
                links: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)],
                accentIndex: 4
            )
        case .triptych:
            BootstrapConstellationPlan(
                points: [
                    .init(x: 0.16, y: 0.31), .init(x: 0.31, y: 0.21),
                    .init(x: 0.50, y: 0.39), .init(x: 0.69, y: 0.21),
                    .init(x: 0.84, y: 0.31), .init(x: 0.78, y: 0.68),
                ],
                links: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)],
                accentIndex: 2
            )
        case .agent:
            BootstrapConstellationPlan(
                points: [
                    .init(x: 0.07, y: 0.15), .init(x: 0.25, y: 0.23),
                    .init(x: 0.43, y: 0.15), .init(x: 0.07, y: 0.85),
                    .init(x: 0.25, y: 0.77), .init(x: 0.43, y: 0.85),
                    .init(x: 0.60, y: 0.50), .init(x: 0.87, y: 0.23),
                    .init(x: 0.90, y: 0.50), .init(x: 0.87, y: 0.77),
                ],
                links: [(0, 1), (1, 2), (3, 4), (4, 5), (7, 6), (8, 6), (9, 6)],
                accentIndex: 6
            )
        case .ready:
            BootstrapConstellationPlan(
                points: [
                    .init(x: 0.18, y: 0.28), .init(x: 0.50, y: 0.17),
                    .init(x: 0.82, y: 0.28), .init(x: 0.26, y: 0.48),
                    .init(x: 0.74, y: 0.48), .init(x: 0.50, y: 0.58),
                ],
                links: [(0, 5), (1, 5), (2, 5), (3, 5), (4, 5)],
                accentIndex: 5
            )
        }
    }

    private func drawNode(
        at center: CGPoint,
        accent: Bool,
        in context: inout GraphicsContext
    ) {
        let frame = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        context.fill(
            Path(ellipseIn: frame),
            with: .color(accent ? BootstrapArtworkPalette.accent : BootstrapArtworkPalette.paper)
        )
        context.stroke(
            Path(ellipseIn: frame),
            with: .color(BootstrapArtworkPalette.ink),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawKeyhole(
        at center: CGPoint,
        in context: inout GraphicsContext
    ) {
        var keyhole = Path()
        keyhole.move(to: CGPoint(x: center.x, y: center.y - 11))
        keyhole.addCurve(
            to: CGPoint(x: center.x + 4.5, y: center.y + 4),
            control1: CGPoint(x: center.x + 11, y: center.y - 10),
            control2: CGPoint(x: center.x + 11, y: center.y + 1)
        )
        keyhole.addLine(to: CGPoint(x: center.x + 5.5, y: center.y + 12))
        keyhole.addLine(to: CGPoint(x: center.x - 5.5, y: center.y + 12))
        keyhole.addLine(to: CGPoint(x: center.x - 4.5, y: center.y + 4))
        keyhole.addCurve(
            to: CGPoint(x: center.x, y: center.y - 11),
            control1: CGPoint(x: center.x - 11, y: center.y + 1),
            control2: CGPoint(x: center.x - 11, y: center.y - 10)
        )
        keyhole.closeSubpath()
        context.fill(keyhole, with: .color(BootstrapArtworkPalette.accent))
        context.stroke(
            keyhole,
            with: .color(BootstrapArtworkPalette.ink),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

private struct BootstrapConstellationPlan {
    let points: [CGPoint]
    let links: [(Int, Int)]
    let accentIndex: Int
}

private enum BootstrapArtworkPalette {
    static let goldenOchre = Color(red: 153.0 / 255, green: 129.0 / 255, blue: 90.0 / 255)
    static let mineralBlue = Color(red: 92.0 / 255, green: 113.0 / 255, blue: 128.0 / 255)
    static let verdigris = Color(red: 114.0 / 255, green: 139.0 / 255, blue: 128.0 / 255)
    static let oxblood = Color(red: 128.0 / 255, green: 91.0 / 255, blue: 87.0 / 255)
    static let paper = Color(red: 232.0 / 255, green: 210.0 / 255, blue: 172.0 / 255)
    static let ink = Color(red: 25.0 / 255, green: 48.0 / 255, blue: 61.0 / 255)
    static let accent = Color(red: 155.0 / 255, green: 74.0 / 255, blue: 43.0 / 255)
}
