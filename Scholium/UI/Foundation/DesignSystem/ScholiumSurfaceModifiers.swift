import SwiftUI

private struct ScholiumSurfaceModifier: ViewModifier {
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumSurfaceRole

    func body(content: Content) -> some View {
        content.background {
            Rectangle().fill(
                role.colorRole.color(
                    increasedContrast: increasedContrast
                ))
        }
    }
}

private struct ScholiumElevationModifier: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @Environment(\.scholiumAppearsActive) private var appearsActive
    let role: ScholiumElevationRole

    func body(content: Content) -> some View {
        let style = role.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency,
            appearsActive: appearsActive
        )
        content.shadow(
            color: ScholiumNativeColorRole.structuralShadow.color.opacity(style.opacity),
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}

private struct ScholiumBoundaryModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumBoundaryRole
    let shape: S

    func body(content: Content) -> some View {
        let style = role.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency
        )
        content.overlay {
            shape.strokeBorder(
                style.colorRole.color(
                    increasedContrast: increasedContrast
                ).opacity(style.opacity),
                lineWidth: style.lineWidth
            )
            .allowsHitTesting(false)
        }
    }
}

private struct ScholiumEditorialSurfaceModifier<S: RoundedRectangularShape>: ViewModifier {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumSurfaceRole
    let boundary: ScholiumBoundaryRole
    let elevation: ScholiumElevationRole?
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let boundaryStyle = boundary.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency
        )
        let surfacedContent =
            content
            .background(
                role.colorRole.color(
                    increasedContrast: increasedContrast
                ),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    boundaryStyle.colorRole.color(
                        increasedContrast: increasedContrast
                    ).opacity(boundaryStyle.opacity),
                    lineWidth: boundaryStyle.lineWidth
                )
                .allowsHitTesting(false)
            }
            .containerShape(shape)
        if let elevation {
            surfacedContent.scholiumElevation(elevation)
        } else {
            surfacedContent
        }
    }
}

private struct ScholiumForegroundModifier: ViewModifier {
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let role: ScholiumColorRole

    func body(content: Content) -> some View {
        content.foregroundStyle(
            role.color(
                increasedContrast: increasedContrast
            ))
    }
}

private struct ScholiumContentInteractionSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast

    let isSelected: Bool
    let isHovering: Bool
    let isFocused: Bool
    let isPressed: Bool
    let shape: S

    func body(content: Content) -> some View {
        content.background(
            ScholiumContentInteractionSurface.selectionColor(
                isSelected: isSelected,
                isHovering: isEnabled && isHovering,
                isFocused: isEnabled && isFocused,
                isPressed: isEnabled && isPressed,
                increasedContrast: increasedContrast
            ),
            in: shape
        )
    }
}

extension View {
    /// Paints the shared shallow interaction surface inside content regions.
    /// The caller continues to own the purpose-specific shape and hit region.
    func scholiumContentInteractionSurface<S: Shape>(
        isSelected: Bool = false,
        isHovering: Bool,
        isFocused: Bool = false,
        isPressed: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentInteractionSurfaceModifier(
                isSelected: isSelected,
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                shape: shape
            ))
    }

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

    func scholiumEditorialSurface<S: RoundedRectangularShape>(
        _ role: ScholiumSurfaceRole,
        in shape: S,
        boundary: ScholiumBoundaryRole? = nil,
        elevation: ScholiumElevationRole? = nil
    ) -> some View {
        modifier(
            ScholiumEditorialSurfaceModifier(
                role: role,
                boundary: boundary ?? role.defaultBoundaryRole,
                elevation: elevation ?? role.defaultElevationRole,
                shape: shape
            ))
    }
}
