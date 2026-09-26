import SwiftUI

extension View {
    /// Liquid Glass on iOS 26+, a tinted blur on earlier versions.
    @ViewBuilder
    func glassBackground(in shape: some Shape, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint))
            }
        }
    }
}
