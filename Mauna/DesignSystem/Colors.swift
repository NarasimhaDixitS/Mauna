import AppKit
import SwiftUI

// Colour tokens from design/tokens.json › color.
// Neutrals are macOS semantic colours (Color.primary, .secondary, .tertiary, .quaternary). Never hard-code greys.
// Orange = needs setup, red = something failed. No other colour carries meaning.

extension ShapeStyle where Self == Color {
    /// Active glyph tile, primary button, switch on. White content on top.
    static var accentFill: Color { Color("AccentColor") }

    /// "now" label, active badge, links on backgrounds. Bronze in light mode (champagne won't read on white).
    static var accentText: Color { Color(light: 0x8A6420, dark: 0xE6C98A) }

    /// Text and symbols on a gold surface: a warm near-black, never white.
    static var onAccent: Color { Color(hex: 0x241A09) }

    /// Active rule row background.
    static var accentTint: Color { Color(light: (0xB8913F, 0.14), dark: (0xE2C07A, 0.15)) }

    /// Pressed state of accent fills.
    static var accentPressed: Color { Color(light: 0xA98136, dark: 0xC9A35B) }

    /// 0.5pt separators inside groups only.
    static var hairline: Color { Color(light: (0x000000, 0.06), dark: (0xFFFFFF, 0.07)) }

    /// Glyph tile at rest, badge fill, track background.
    static var well: Color { Color(light: (0x000000, 0.06), dark: (0xFFFFFF, 0.08)) }

    /// Row hover and the volume well inside the popover.
    static var popRow: Color { Color(light: (0x000000, 0.045), dark: (0xFFFFFF, 0.07)) }

    /// Secondary button face.
    static var control: Color { Color(light: (0xFFFFFF, 1), dark: (0x2E2E33, 1)) }

    /// Settings card face. Sits on the window background with ring + soft shadow.
    static var card: Color { Color(light: (0xFFFFFF, 1), dark: (0xFFFFFF, 0.05)) }

    /// Permission missing, YouTube Music setup incomplete.
    static var needsSetup: Color { Color(nsColor: .systemOrange) }

    /// Player unreachable, script failed.
    static var failed: Color { Color(nsColor: .systemRed) }
}

extension Color {
    /// A colour that follows light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(light: (light, 1), dark: (dark, 1))
    }

    init(light: (hex: UInt32, alpha: CGFloat), dark: (hex: UInt32, alpha: CGFloat)) {
        let l = NSColor(hex: light.hex, alpha: light.alpha)
        let d = NSColor(hex: dark.hex, alpha: dark.alpha)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

@MainActor
extension LinearGradient {
    /// Accent surfaces get light from the top: a subtle gradient instead of one flat colour.
    static var accentFill: LinearGradient {
        // Champagne gold, brighter at the top where the light hits.
        LinearGradient(
            colors: [Color(light: 0xEBD39A, dark: 0xF2DCA6), Color(light: 0xC39A4F, dark: 0xC9A35B)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var accentPressed: LinearGradient {
        LinearGradient(
            colors: [Color(light: 0xD6B676, dark: 0xDCC07F), Color(light: 0xA98136, dark: 0xAE8740)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Status tile at rest: Mauna's face, the app icon in miniature. Black velvet. Never grey unless off.
    static var tileRest: LinearGradient {
        LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
    }

    /// Status tile while Mauna acts: a little lighter, with a gold glow (`Color.tileGlow`) around it.
    static var tileActing: LinearGradient {
        LinearGradient(colors: [Color(white: 0.26), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
    }

    /// The gold of the wave on the status tile and the icon.
    static var tileWave: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(hex: 0xC9A35B), location: 0),
            .init(color: Color(hex: 0xFFF1C9), location: 0.32),
            .init(color: Color(hex: 0xD9B66A), location: 0.6),
            .init(color: Color(hex: 0xA97F38), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Status tile when Mauna is off: the only grey state.
    static var tileOff: LinearGradient {
        LinearGradient(colors: [Color(white: 0.55), Color(white: 0.40)], startPoint: .top, endPoint: .bottom)
    }

    /// Active rule row: the tint fades out to the right, so the row glows from the icon.
    static var accentRowTint: LinearGradient {
        LinearGradient(
            colors: [Color(light: (0xB8913F, 0.16), dark: (0xE2C07A, 0.17)), Color(light: (0xB8913F, 0.04), dark: (0xE2C07A, 0.05))],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

extension Color {
    /// Coloured shadow under accent surfaces.
    static var accentShadow: Color { Color(light: (0x7A5A24, 0.35), dark: (0x000000, 0.5)) }

    /// The soft glow around the status tile while Mauna acts.
    static var tileGlow: Color { Color(hex: 0xE9C77B).opacity(0.5) }

    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
