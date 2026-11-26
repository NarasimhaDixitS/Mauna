#if DEBUG
import SwiftUI

// Design study only: three directions for the popover's status tile, in every state.
// Rendered with MAUNA_SNAPSHOT_VIEW=glyphs. Nothing in the app uses these yet.

/// The full sheet: one row per direction, then how each sits in the popover header.
struct GlyphStudySheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StudyRow(title: "A · Always lit", note: "Indigo tile, deep at rest, bright with a glow while Mauna acts. Paused becomes a pause mark.") { StudyTileA(state: $0, size: $1) }
            StudyRow(title: "B · Glass", note: "Frosted tile with an indigo wave. Tints and glows while Mauna acts.") { StudyTileB(state: $0, size: $1) }
            StudyRow(title: "C · Dial", note: "A ring that closes as music gets quieter, the wave at its centre.") { StudyTileC(state: $0, size: $1) }
        }
        .padding(28)
        .frame(width: 760)
    }
}

private enum StudyState: CaseIterable {
    case playing, lowered, paused, off

    var label: String {
        switch self {
        case .playing: "Playing"
        case .lowered: "Lowered by Mauna"
        case .paused: "Paused by Mauna"
        case .off: "Mauna off"
        }
    }

    var acting: Bool { self == .lowered || self == .paused }

    var status: (String, String) {
        switch self {
        case .playing: ("Playing on Apple Music", "Watching 9 apps")
        case .lowered: ("Lowered for Notes", "Back to normal when you leave Notes")
        case .paused: ("Paused for Zoom", "Resumes when zoom.us quits")
        case .off: ("Mauna is off", "Rules are off. Quiet now still works.")
        }
    }
}

private struct StudyRow<Tile: View>: View {
    let title: String
    let note: String
    @ViewBuilder let tile: (StudyState, CGFloat) -> Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(StudyState.allCases, id: \.self) { state in
                    VStack(spacing: 8) {
                        tile(state, 64)
                        Text(state.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // In context: the popover header at real size, for the two states you see most.
            HStack(spacing: 14) {
                ForEach([StudyState.paused, .playing], id: \.self) { state in
                    HStack(spacing: 12) {
                        tile(state, 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.status.0).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(state.status.1).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.popRow))
                }
            }
        }
    }
}

// MARK: Shared drawing

private enum Indigo {
    static let bright = Color(red: 0x6F / 255, green: 0x6A / 255, blue: 0xF0 / 255)
    static let mid = Color(red: 0x4C / 255, green: 0x47 / 255, blue: 0xC4 / 255)
    static let deep = Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x86 / 255)
    static let night = Color(red: 0x1F / 255, green: 0x1C / 255, blue: 0x5C / 255)
}

/// The wave for each state. Paused is a pause mark (two bars), not five dots.
private struct StudyGlyph: View {
    let state: StudyState
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 18
            let bars: [(x: CGFloat, w: CGFloat, h: CGFloat)]
            switch state {
            case .playing, .off: bars = [(1.5, 2, 6), (5, 2, 12), (8.5, 2, 16), (12, 2, 10), (15.5, 2, 5)]
            case .lowered: bars = [(1.5, 2, 3), (5, 2, 5), (8.5, 2, 7), (12, 2, 4), (15.5, 2, 3)]
            case .paused: bars = [(5.2, 2.8, 11), (10, 2.8, 11)]
            }
            for bar in bars {
                let rect = CGRect(x: bar.x * s, y: (9 - bar.h / 2) * s, width: bar.w * s, height: bar.h * s)
                context.fill(Path(roundedRect: rect, cornerRadius: bar.w * s / 2), with: .foreground)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: A · Always lit

private struct StudyTileA: View {
    let state: StudyState
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        StudyGlyph(state: state, size: size * 0.55)
            .foregroundStyle(.white.opacity(state == .off ? 0.75 : 1))
            .frame(width: size, height: size)
            .background {
                shape.fill(fill)
                    .shadow(color: state.acting ? Indigo.bright.opacity(0.55) : .black.opacity(0.18),
                            radius: state.acting ? size * 0.16 : size * 0.04, y: size * 0.04)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.6)
            }
    }

    private var fill: LinearGradient {
        switch state {
        case .lowered, .paused: LinearGradient(colors: [Indigo.bright, Indigo.mid], startPoint: .top, endPoint: .bottom)
        case .playing: LinearGradient(colors: [Indigo.mid, Indigo.deep], startPoint: .top, endPoint: .bottom)
        case .off: LinearGradient(colors: [Color(white: 0.55), Color(white: 0.40)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: B · Glass

private struct StudyTileB: View {
    let state: StudyState
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        let dark = scheme == .dark
        StudyGlyph(state: state, size: size * 0.55)
            .foregroundStyle(state == .off
                             ? AnyShapeStyle(.tertiary)
                             : AnyShapeStyle(LinearGradient(colors: [Indigo.bright, dark ? Color(red: 0.66, green: 0.64, blue: 1) : Indigo.mid],
                                                            startPoint: .top, endPoint: .bottom)))
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: dark ? [.white.opacity(0.16), .white.opacity(0.06)] : [.white.opacity(0.95), .white.opacity(0.7)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.fill(Indigo.bright.opacity(dark ? 0.28 : 0.16)).opacity(state.acting ? 1 : 0)
                }
                .shadow(color: state.acting ? Indigo.bright.opacity(0.45) : .black.opacity(dark ? 0.35 : 0.12),
                        radius: state.acting ? size * 0.14 : size * 0.06, y: size * 0.04)
            }
            .overlay {
                shape.strokeBorder(.black.opacity(dark ? 0.2 : 0.06), lineWidth: 0.5)
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.4 : 1), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
    }
}

// MARK: C · Dial

private struct StudyTileC: View {
    let state: StudyState
    let size: CGFloat

    /// How loud the music is: the ring's open arc.
    private var level: CGFloat {
        switch state {
        case .playing, .off: 1
        case .lowered: 0.3
        case .paused: 0
        }
    }

    var body: some View {
        let ring = size * 0.075
        ZStack {
            Circle().fill(RadialGradient(colors: state == .off ? [Color(white: 0.5), Color(white: 0.35)] : [Indigo.mid, Indigo.night],
                                         center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle()
                .inset(by: ring * 1.2)
                .stroke(.white.opacity(0.18), lineWidth: ring)
            Circle()
                .inset(by: ring * 1.2)
                .trim(from: 0, to: level)
                .stroke(.white.opacity(state == .off ? 0.6 : 1), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
            StudyGlyph(state: state, size: size * 0.4)
                .foregroundStyle(.white.opacity(state == .off ? 0.7 : 1))
        }
        .frame(width: size, height: size)
        .shadow(color: state.acting ? Indigo.bright.opacity(0.5) : .black.opacity(0.2), radius: state.acting ? size * 0.14 : size * 0.05, y: size * 0.04)
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.6))
    }
}
#endif
