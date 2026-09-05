import SwiftUI

/// Material belongs to the transient container; its contents retain semantic colors.
/// The system owns contrast, transparency adaptation, highlights, and elevation.
extension View {
    func scholiumFloatingSurface<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular, in: shape)
    }
}
