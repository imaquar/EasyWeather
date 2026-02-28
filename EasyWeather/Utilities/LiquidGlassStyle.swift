import SwiftUI

struct LiquidGlassBackground: ViewModifier {
    var shape: RoundedRectangle = RoundedRectangle(cornerRadius: 18, style: .continuous)

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: shape)
            .glassEffectTransition(.materialize)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(LiquidGlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func liquidGlassPill() -> some View {
        self
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .glassEffectTransition(.materialize)
    }
}
