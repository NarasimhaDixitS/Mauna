import SwiftUI

// Motion tokens from design/tokens.json › motion. Rules: design/DESIGN.md › Motion.
// Decide in order: should it animate → why → easing → duration. Never ease-in. Never scale from 0.

nonisolated enum MotionDuration {
    static let press: Double = 0.16
    static let textCrossfade: Double = 0.2
    static let rowHighlight: Double = 0.2
    static let popoverIn: Double = 0.16
    static let popoverOut: Double = 0.11
    static let onboardingStep: Double = 0.3
    static let staggerStep: ClosedRange<Double> = 0.04...0.08
}

extension Animation {
    /// Enter and press. cubic-bezier(0.23, 1, 0.32, 1)
    static func maunaEaseOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// On-screen movement. cubic-bezier(0.77, 0, 0.175, 1)
    static func maunaEaseInOut(_ duration: Double) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    /// Glyph morph and highlights. Critically damped, interruptible, starts from the current value.
    static let maunaSpring: Animation = .spring(response: 0.3, dampingFraction: 1)

    /// Only after a gesture that carried momentum. Mauna has almost none.
    static let maunaFlick: Animation = .spring(response: 0.35, dampingFraction: 0.8)
}

/// Press feedback for Mauna's own tappable surfaces (glyph tile, rows).
/// Native buttons keep their system look; don't put this on them.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.maunaEaseOut(MotionDuration.press), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
}

/// Status text crossfade: opacity plus a 2pt blur, 0.2 s. Reduce Motion drops the blur.
struct BlurCrossfade: ViewModifier {
    let isIdentity: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isIdentity ? 1 : 0)
            .blur(radius: isIdentity ? 0 : 2)
    }
}

extension AnyTransition {
    static var blurCrossfade: AnyTransition {
        .modifier(active: BlurCrossfade(isIdentity: false), identity: BlurCrossfade(isIdentity: true))
            .animation(.maunaEaseOut(MotionDuration.textCrossfade))
    }
}
