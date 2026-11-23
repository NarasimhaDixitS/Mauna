import SwiftUI

// Elevation tokens from design/tokens.json › elevation.
// Ring + soft shadow, never a solid 1pt border. System surfaces (popover, Settings) keep their own material.
// SwiftUI shadows have no spread, so the CSS values are approximated: radius ≈ blur / 2, opacity lowered where spread was negative.

enum Elevation {
    /// Rows, chips, controls.
    case e1
    /// Cards, settings groups.
    case e2
    /// Mauna's own sheets and windows (onboarding, YouTube Music setup).
    case e3

    fileprivate var ring: Color {
        switch self {
        case .e1, .e2: Color(light: (0x000000, 0.07), dark: (0xFFFFFF, 0.08))
        case .e3:      Color(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.14))
        }
    }

    fileprivate var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch self {
        case .e1: (Color.black.opacity(0.04), 1, 1)
        case .e2: (Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x32 / 255).opacity(0.07), 6, 6)
        case .e3: (Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x3C / 255).opacity(0.22), 24, 24)
        }
    }
}

extension View {
    /// Fills a rounded shape behind the view, then adds the ring and shadow for `level`.
    func elevated<S: ShapeStyle>(_ level: Elevation, cornerRadius: CGFloat, fill: S) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadow = level.shadow
        return self
            .background {
                shape.fill(fill).shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            }
            .overlay {
                shape.strokeBorder(level.ring, lineWidth: 0.5)
            }
    }

    /// Bright 0.5pt top edge for Mauna's own translucent surfaces. Never stack translucent layers.
    func edgeHighlight(cornerRadius: CGFloat) -> some View {
        modifier(EdgeHighlight(cornerRadius: cornerRadius))
    }
}

private struct EdgeHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(scheme == .dark ? 0.12 : 0.9), .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.08)
                    ),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        }
    }
}
