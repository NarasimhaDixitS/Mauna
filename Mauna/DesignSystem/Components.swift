import AppKit
import SwiftUI

// Mauna's own surfaces and controls. Measured from design/design-system.html, then given depth:
// light from the top, coloured shadows, quiet neutrals. Native behaviour (keyboard, VoiceOver) stays.

// MARK: Buttons

/// `.btn` family: 30pt tall, 9pt radius, ring + soft shadow + bright top edge, scale 0.97 on press.
struct MaunaButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, small, ghost }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        MaunaButton(configuration: configuration, kind: kind)
    }
}

private struct MaunaButton: View {
    let configuration: ButtonStyle.Configuration
    let kind: MaunaButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if kind == .ghost { ghost } else { filled }
    }

    /// `.btn.ghost`: no face, accent text. For secondary actions inside rows.
    private var ghost: some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.accentText)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.maunaEaseOut(MotionDuration.press), value: configuration.isPressed)
    }

    private var filled: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let accent = kind == .primary && isEnabled
        return configuration.label
            .font(kind == .small ? .callout.weight(.medium) : .body.weight(.medium))
            .foregroundStyle(accent ? AnyShapeStyle(.white) : (isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
            .padding(.horizontal, kind == .small ? 9 : 13)
            .frame(height: height)
            .background {
                shape
                    .fill(face(pressed: configuration.isPressed))
                    .shadow(color: accent ? .accentShadow : .black.opacity(0.05), radius: accent ? 4 : 1, y: accent ? 2 : 1)
            }
            .overlay {
                shape.strokeBorder(ring, lineWidth: 0.5)
                shape.strokeBorder(
                    LinearGradient(colors: [topEdge, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)),
                    lineWidth: 0.5
                )
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.maunaEaseOut(MotionDuration.press), value: configuration.isPressed)
            .animation(.maunaEaseOut(0.2), value: isEnabled)
    }

    private var height: CGFloat { kind == .small ? 24 : (kind == .primary ? 34 : 30) }
    private var radius: CGFloat { kind == .small ? 7 : (kind == .primary ? 10 : 9) }

    private func face(pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .primary:
            // Nothing to act on: a calm neutral, never washed-out lavender.
            guard isEnabled else { return AnyShapeStyle(.well) }
            return AnyShapeStyle(pressed ? LinearGradient.accentPressed : LinearGradient.accentFill)
        case .secondary, .small, .ghost:
            return AnyShapeStyle(pressed ? AnyShapeStyle(.popRow) : AnyShapeStyle(.control))
        }
    }

    private var ring: Color {
        if kind == .primary && isEnabled { return .black.opacity(0.14) }
        return scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var topEdge: Color {
        if kind == .primary && isEnabled { return .white.opacity(0.35) }
        return .white.opacity(scheme == .dark ? 0.10 : 0.9)
    }
}

extension ButtonStyle where Self == MaunaButtonStyle {
    static var maunaPrimary: MaunaButtonStyle { MaunaButtonStyle(kind: .primary) }
    static var maunaSecondary: MaunaButtonStyle { MaunaButtonStyle(kind: .secondary) }
    static var maunaSmall: MaunaButtonStyle { MaunaButtonStyle(kind: .small) }
    static var maunaGhost: MaunaButtonStyle { MaunaButtonStyle(kind: .ghost) }
}

/// Footer links: plain text that dims on press.
struct PlainTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: App icon

/// An app's real icon with a soft contact shadow, so it reads as an object, not a sticker.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 24
    /// Where the app is, when Launch Services doesn't know it by bundle ID.
    var path: String? = nil

    var body: some View {
        Group {
            if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
                    .shadow(color: .black.opacity(0.18), radius: size / 16, y: size / 24)
            } else if AppIcon.isInstalled(bundleID) {
                Image(nsImage: AppIcon.image(for: bundleID))
                    .resizable()
                    .interpolation(.high)
                    .shadow(color: .black.opacity(0.18), radius: size / 16, y: size / 24)
            } else {
                // Not on this Mac: a quiet placeholder, never a blank document.
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(.well)
                    .overlay(Image(systemName: "app.dashed").font(.system(size: size * 0.5)).foregroundStyle(.tertiary))
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Badge

/// Trigger badge. At rest it's quiet: secondary, no pill. With `showsText` off it's only its symbol
/// (plus `restSymbol`, like a small speaker for Lower), and the words slide in on hover.
/// While that rule is in charge it gains an accent pill. Triggers differ by glyph and word, never colour.
struct Badge: View {
    let symbol: String?
    let text: String
    var isAccent = false
    var restSymbol: String? = nil
    var showsText = true

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            if showsText {
                Text(text)
                    .font(.system(size: 10.5, weight: .semibold))
                    .fixedSize()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if let restSymbol {
                Image(systemName: restSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .transition(.opacity)
            }
        }
        .foregroundStyle(isAccent ? AnyShapeStyle(.accentText) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(isAccent ? AnyShapeStyle(.accentTint) : AnyShapeStyle(.clear)))
        .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: isAccent)
        .animation(.maunaEaseOut(0.16), value: showsText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

extension Trigger {
    /// Badge symbols: macwindow, phone.fill ("In a call"), play.circle.
    var symbol: String {
        switch self {
        case .inFront:         "macwindow"
        case .usingMicOrSound: "phone.fill"
        case .running:         "play.circle"
        }
    }
}

// MARK: Slider

/// A Control Center–style slider: a thin neutral track at rest that thickens and shows a knob
/// under the pointer. Click or drag anywhere on it. Arrow keys and VoiceOver adjust it too.
struct MaunaSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0.01
    /// What VoiceOver reads, like "1.2 seconds". Defaults to a percentage.
    var spokenValue: ((Double) -> String)?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let active = hovering || dragging
            let track: CGFloat = active ? 6 : 4

            ZStack(alignment: .leading) {
                Capsule().fill(.well).frame(height: track)
                Capsule()
                    .fill(.primary.opacity(active ? 0.7 : 0.55))
                    .frame(width: max(track, width * fraction), height: track)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                    .offset(x: min(max(0, width * fraction - 7), width - 14))
                    .opacity(active ? 1 : 0)
                    .scaleEffect(active ? 1 : 0.6)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        set(fraction: drag.location.x / width)
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
            .animation(.maunaEaseOut(0.16), value: active)
        }
        .frame(height: 16)
        .onHover { hovering = $0 }
        .accessibilityElement()
        .accessibilityValue(spokenValue?(value) ?? "\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step * 5)
            case .decrement: value = max(range.lowerBound, value - step * 5)
            @unknown default: break
            }
        }
    }

    private func set(fraction: CGFloat) {
        let raw = range.lowerBound + Double(min(max(fraction, 0), 1)) * (range.upperBound - range.lowerBound)
        value = (raw / step).rounded() * step
    }
}

// MARK: Separator

/// `.sep`: a 0.5pt hairline, inset 8pt, only between groups.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: Waiting ring

/// The debounce made visible: a ring that fills over 1.5 s next to "Waiting 1.5 s".
struct PendingRing: View {
    var duration: Double = AudioTiming.debounce
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(.well, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.accentText, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .onAppear {
            progress = 0
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
    }
}

// MARK: Row hover

extension View {
    /// Popover row: a soft fill under the pointer; a glow from the icon while the rule is in charge.
    func rowHover(cornerRadius: CGFloat = Radius.row, isActive: Bool = false) -> some View {
        modifier(RowHover(cornerRadius: cornerRadius, isActive: isActive))
    }
}

private struct RowHover: ViewModifier {
    let cornerRadius: CGFloat
    let isActive: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.popRow).opacity(hovering && !isActive ? 1 : 0)
                    shape.fill(LinearGradient.accentRowTint).opacity(isActive ? 1 : 0)
                }
            }
            .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: isActive)
            .animation(.maunaEaseOut(0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: Settings building blocks

/// Top of each Settings tab: a tinted symbol tile, the title, and one plain sentence.
struct SettingsHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient.accentFill)
                        .shadow(color: .accentShadow, radius: 3, y: 1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A Settings group: card face, 12pt radius, ring + soft shadow (e2). Rows inside are split by inset hairlines.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .elevated(.e2, cornerRadius: 12, fill: .card)
    }
}

/// One row inside a SettingsCard.
struct SettingsRow<Content: View>: View {
    var showsDivider = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            if showsDivider {
                Rectangle().fill(.hairline).frame(height: 0.5).padding(.leading, 14)
            }
        }
    }
}

/// Shared page layout for Settings tabs.
struct SettingsPage<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(symbol: symbol, title: title, subtitle: subtitle)
            content
        }
        .padding(24)
        .frame(width: Size.settingsWindowWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Status tile

/// Mauna's face: an indigo tile with the white wave. Deep and calm at rest; brighter with a soft glow
/// while Mauna acts; grey only when Mauna is off. The wave says what you hear: full, low, or ❙❙.
/// 40pt in the popover header; larger in the upgrade window.
struct StatusTile: View {
    let state: GlyphState
    let isActing: Bool
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.275, style: .continuous)
        WaveGlyphView(state: state == .off ? .playing : state, size: size * 0.55)
            .foregroundStyle(.white.opacity(state == .off ? 0.75 : 1))
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(LinearGradient.tileOff)
                    shape.fill(LinearGradient.tileRest).opacity(state == .off ? 0 : 1)
                    shape.fill(LinearGradient.tileActing).opacity(isActing ? 1 : 0)
                }
                .shadow(color: isActing ? .tileGlow : .black.opacity(0.18),
                        radius: isActing ? size * 0.16 : size * 0.04, y: isActing ? size * 0.04 : size * 0.025)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 0.6
                )
            }
            .animation(.maunaEaseOut(0.25), value: isActing)
            .animation(.maunaEaseOut(0.25), value: state == .off)
    }
}

// MARK: Pro badge

/// `.badge.pro`: a small "PRO" capsule, accent text on a tint that fades to the right.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.accentText)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(LinearGradient(colors: [Color.accentTint, Color.accentTint.opacity(0.3)], startPoint: .leading, endPoint: .trailing)))
            .overlay(Capsule().strokeBorder(Color.accentTint, lineWidth: 0.5))
            .accessibilityLabel("Pro")
    }
}
