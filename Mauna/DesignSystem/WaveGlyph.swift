import AppKit
import SwiftUI

// The Mauna wave (Concept B) from design/tokens.json › glyph.
// The glyph says what you hear. The text says why.
// Same glyph = same sound: "Quieted by you" and "Lowered for Xcode" both use `.ducked`.

nonisolated enum GlyphState: CaseIterable, Hashable, Sendable {
    case playing, ducked, paused, off

    var bars: BarHeights {
        switch self {
        case .playing, .off: BarHeights(6, 12, 16, 10, 5)
        case .ducked:        BarHeights(3, 5, 7, 4, 3)
        case .paused:        BarHeights(2, 2, 2, 2, 2)
        }
    }

    /// Off keeps the playing shape at 35% opacity.
    var opacity: Double { self == .off ? 0.35 : 1 }

    var spokenName: String {
        switch self {
        case .playing: "playing"
        case .ducked:  "lowered"
        case .paused:  "paused"
        case .off:     "off"
        }
    }
}

nonisolated enum WaveGlyph {
    static let canvas: CGFloat = 18
    static let barX: [CGFloat] = [1.5, 5, 8.5, 12, 15.5]
    static let barWidth: CGFloat = 2
    static let minBarHeight: CGFloat = 2
    static let brandMark = BarHeights(6, 12, 8, 3, 2)

    /// Bar rects in the 18pt canvas, centred on y = 9. Origin top-left.
    static func rects(_ heights: BarHeights, in size: CGFloat = canvas) -> [CGRect] {
        let scale = size / canvas
        return zip(barX, heights.values).map { x, h in
            let h = max(minBarHeight, h)
            return CGRect(x: x * scale, y: (canvas / 2 - h / 2) * scale, width: barWidth * scale, height: h * scale)
        }
    }
}

extension WaveGlyph {
    /// Template image for the menu bar. macOS tints it for light, dark and highlighted menu bars.
    @MainActor
    static func menuBarImage(for state: GlyphState) -> NSImage {
        if let cached = menuBarCache[state] { return cached }
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
            NSColor.black.withAlphaComponent(state.opacity).setFill()
            for rect in rects(state.bars) {
                NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mauna"
        menuBarCache[state] = image
        return image
    }

    @MainActor private static var menuBarCache: [GlyphState: NSImage] = [:]
}

// MARK: - SwiftUI

/// Five bar heights, animatable so the glyph can morph on a spring.
nonisolated struct BarHeights: VectorArithmetic, Sendable {
    var values: [CGFloat]

    init(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ e: CGFloat) {
        values = [a, b, c, d, e]
    }

    private init(values: [CGFloat]) { self.values = values }

    static var zero: BarHeights { BarHeights(values: Array(repeating: 0, count: 5)) }

    static func + (l: BarHeights, r: BarHeights) -> BarHeights {
        BarHeights(values: zip(l.values, r.values).map(+))
    }

    static func - (l: BarHeights, r: BarHeights) -> BarHeights {
        BarHeights(values: zip(l.values, r.values).map(-))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * CGFloat(rhs) }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + Double($1 * $1) }
    }
}

nonisolated struct WaveShape: Shape {
    var heights: BarHeights

    var animatableData: BarHeights {
        get { heights }
        set { heights = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let radius = WaveGlyph.barWidth / 2 * side / WaveGlyph.canvas
        var path = Path()
        for bar in WaveGlyph.rects(heights, in: side) {
            path.addRoundedRect(in: bar.offsetBy(dx: origin.x, dy: origin.y),
                                cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}

/// The glyph inside Mauna's own UI. Morphs on the default spring; Reduce Motion crossfades instead.
struct WaveGlyphView: View {
    var state: GlyphState
    var size: CGFloat = Size.menuBarGlyph

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    WaveShape(heights: state.bars)
                        .opacity(state.opacity)
                        .id(state)
                        .transition(.opacity.animation(.maunaEaseOut(MotionDuration.textCrossfade)))
                }
            } else {
                WaveShape(heights: state.bars)
                    .opacity(state.opacity)
                    .animation(.maunaSpring, value: state)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Glyph states") {
    HStack(spacing: Spacing.l) {
        ForEach(GlyphState.allCases, id: \.self) { state in
            VStack(spacing: Spacing.s) {
                WaveGlyphView(state: state, size: 36)
                Text(state.spokenName).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    .padding(Spacing.xxl)
}
