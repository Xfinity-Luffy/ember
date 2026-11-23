import SwiftUI

/// Liquid Glass on iOS 26+, frosted material on older iOS versions.
extension View {
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

    /// Rounded-rectangle glass card.
    func glassCard(_ radius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive)
    }
}
