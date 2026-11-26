#if DEBUG
import AppKit
import SwiftUI

// Design study only: Mauna's app icon, round 2. Rendered with MAUNA_SNAPSHOT_VIEW=icons.
// Every direction uses the brand mark: the wave settling into silence (WaveGlyph.brandMark).

struct IconStudySheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack(alignment: .top, spacing: 34) {
                ForEach(IconDirection.allCases, id: \.self) { direction in
                    VStack(spacing: 14) {
                        StudyIcon(direction: direction, size: 240)
                        VStack(spacing: 3) {
                            Text(direction.title).font(.system(size: 15, weight: .semibold))
                            Text(direction.note).font(.callout).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 240)
                        }
                    }
                }
            }
            // In the Dock, between Apple's own icons, on a light and a dark wallpaper.
            VStack(spacing: 18) {
                ForEach(IconDirection.allCases, id: \.self) { direction in
                    HStack(spacing: 18) {
                        DockMock(direction: direction, dark: false)
                        DockMock(direction: direction, dark: true)
                    }
                }
            }
        }
        .padding(40)
    }
}

private enum IconDirection: CaseIterable {
    case sapphire, gold, bezel, sapphireGold

    var title: String {
        switch self {
        case .sapphire: "1 · Sapphire"
        case .gold: "2 · Black and gold"
        case .bezel: "2b · Gold bezel"
        case .sapphireGold: "3 · Sapphire and gold"
        }
    }

    var note: String {
        switch self {
        case .sapphire: "Light inside the stone, a pearl wave with polished edges."
        case .gold: "Velvet black with fine grain, solid brushed gold catching the light."
        case .bezel: "The same, framed by a thin gold ring like a watch face."
        case .sapphireGold: "Mauna's indigo as the stone, gold as the setting."
        }
    }

    var stone: Bool { self == .sapphire || self == .sapphireGold }
    var gold: Bool { self != .sapphire }
}

// MARK: The icon

private struct StudyIcon: View {
    let direction: IconDirection
    let size: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.225, style: .continuous) }

    var body: some View {
        ZStack {
            background
            if direction == .bezel { bezel }
            wave
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(direction.stone ? 0.45 : 0.28), .white.opacity(0.02)],
                                              startPoint: .top, endPoint: .center),
                               lineWidth: max(0.5, size * 0.005))
        }
        .shadow(color: .black.opacity(0.3), radius: size * 0.05, y: size * 0.03)
    }

    // MARK: Materials

    @ViewBuilder private var background: some View {
        if direction.stone {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4A44D4), Color(hex: 0x241F7C), Color(hex: 0x0E0B3A)],
                               startPoint: .top, endPoint: .bottom)
                // Light deep inside the stone, behind the wave.
                RadialGradient(colors: [Color(hex: 0x8F8BFF).opacity(direction == .sapphireGold ? 0.35 : 0.6), .clear],
                               center: .init(x: 0.5, y: 0.45), startRadius: 0, endRadius: size * 0.5)
                // A facet: one diagonal plane catches more light.
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)
                // Sheen across the top.
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 1.3, height: size * 0.6)
                    .offset(y: -size * 0.42)
            }
        } else {
            ZStack {
                RadialGradient(colors: [Color(white: 0.16), Color(white: 0.045)],
                               center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: size * 0.85)
                Grain(size: size, opacity: 0.05)
                LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.4))
            }
        }
    }

    /// A thin gold ring inset from the edge, like a watch bezel.
    private var bezel: some View {
        RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
            .strokeBorder(Gold.metal(size: size), lineWidth: max(0.6, size * 0.012))
            .padding(size * 0.085)
    }

    // MARK: The wave

    @ViewBuilder private var wave: some View {
        let mark = WaveShape(heights: WaveGlyph.brandMark)
        let side = size * (direction == .bezel ? 0.56 : 0.62)
        if direction.gold {
            ZStack {
                mark.fill(Gold.metal(size: side))
                // Brushed: fine horizontal lines in the metal.
                Brushed(size: side).mask(mark)
                // Polished edges: light on the top edge of every bar.
                mark.stroke(LinearGradient(colors: [Color(hex: 0xFFF4D6), .clear], startPoint: .top, endPoint: .center),
                            lineWidth: max(0.5, side * 0.012))
                    .mask(mark)
            }
            .frame(width: side, height: side)
            .shadow(color: Color(hex: 0xE9C77B).opacity(0.35), radius: size * 0.03)
            .shadow(color: .black.opacity(0.55), radius: size * 0.008, y: size * 0.008)
        } else {
            ZStack {
                // Pearl: white with a faint lavender-to-cyan sheen.
                mark.fill(LinearGradient(colors: [.white, Color(hex: 0xE4E0FF), Color(hex: 0xD6F0FF), .white],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                mark.stroke(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: max(0.5, side * 0.014))
                    .mask(mark)
            }
            .frame(width: side, height: side)
            .shadow(color: Color(hex: 0xB3AFFF).opacity(0.85), radius: size * 0.045)
            .shadow(color: .black.opacity(0.3), radius: size * 0.008, y: size * 0.008)
        }
    }
}

private enum Gold {
    /// Champagne gold with a bright band where the light hits, darker below.
    static func metal(size: CGFloat) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(hex: 0xB8914A), location: 0),
            .init(color: Color(hex: 0xFFF1C9), location: 0.28),
            .init(color: Color(hex: 0xE2C07A), location: 0.45),
            .init(color: Color(hex: 0xA97F38), location: 0.75),
            .init(color: Color(hex: 0x7A5A24), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// Fine horizontal brushing, drawn from a fixed seed so every render matches.
private struct Brushed: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let step = max(0.6, canvas.height / 180)
            var y: CGFloat = 0
            while y < canvas.height {
                let light = next() > 0.5
                let alpha = 0.05 + next() * 0.12
                context.fill(Path(CGRect(x: 0, y: y, width: canvas.width, height: step * 0.5)),
                             with: .color(light ? .white.opacity(alpha) : .black.opacity(alpha)))
                y += step
            }
        }
        .frame(width: size, height: size)
    }
}

/// Velvet: a fine, even grain.
private struct Grain: View {
    let size: CGFloat
    let opacity: Double

    var body: some View {
        Canvas { context, canvas in
            var seed: UInt64 = 0xD1B54A32D192ED03
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let dot = max(0.5, canvas.width / 400)
            for _ in 0..<Int(canvas.width * canvas.height / (dot * dot * 6)) {
                let rect = CGRect(x: next() * canvas.width, y: next() * canvas.height, width: dot, height: dot)
                context.fill(Path(rect), with: .color(.white.opacity(next() * opacity * 2)))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Dock

/// A Dock on a wallpaper: Apple's icons either side of Mauna, at real Dock size.
private struct DockMock: View {
    let direction: IconDirection
    let dark: Bool

    private static let neighbours = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music",
                                     "com.apple.Notes", "com.apple.iCal", "com.apple.systempreferences"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.neighbours.prefix(3), id: \.self) { neighbour($0) }
            StudyIcon(direction: direction, size: 56)
                .padding(.horizontal, 2)
            ForEach(Self.neighbours.suffix(4), id: \.self) { neighbour($0) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(dark ? Color.white.opacity(0.12) : Color.white.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(dark ? 0.15 : 0.6), lineWidth: 0.6))
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 26)
        .background {
            LinearGradient(colors: dark ? [Color(hex: 0x1C2340), Color(hex: 0x3A2B55), Color(hex: 0x10121C)]
                                        : [Color(hex: 0x9CC3E8), Color(hex: 0xE6C9D9), Color(hex: 0xF3E4C8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func neighbour(_ id: String) -> some View {
        Image(nsImage: AppIcon.image(for: id))
            .resizable()
            .interpolation(.high)
            .frame(width: 60, height: 60)
    }
}
// MARK: Export

/// The app icon on Apple's grid: the squircle is 824 of 1024, centred, with the standard shadow.
private struct AppIconArt: View {
    let pixels: CGFloat

    var body: some View {
        StudyIcon(direction: .gold, size: pixels * 824 / 1024)
            .frame(width: pixels, height: pixels)
    }
}

/// Writes AppIcon.appiconset: every size macOS uses. MAUNA_ICON_EXPORT=/path/AppIcon.appiconset
enum IconExport {
    static func run(to directory: String) {
        let folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // (points, scale) pairs Apple asks for on the Mac.
        let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
        var images: [[String: String]] = []
        for (points, scale) in slots {
            let pixels = points * scale
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            let renderer = ImageRenderer(content: AppIconArt(pixels: CGFloat(pixels)).environment(\.colorScheme, .dark))
            renderer.scale = 1
            renderer.isOpaque = false
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            }
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        if let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("Contents.json"))
        }
        print("wrote", images.count, "icons to", directory)
    }
}
#endif
