import SwiftUI

/// Normal volume, fade time and lowered volume. Changes apply at once and are saved.
struct SoundSettings: View {
    @Bindable var session: PlayerSession

    var body: some View {
        SettingsPage(symbol: "speaker.wave.2.fill", title: "Sound", subtitle: "How loud your music plays, and how gently it steps aside.") {
            SettingsCard {
                SettingsRow {
                    SoundSlider(title: "Normal volume", detail: "Music always comes back to this level.",
                                value: $session.normalVolume, range: 0.1...1, step: 0.01,
                                text: { "\(Int(($0 * 100).rounded()))%" }, lowIcon: "speaker.fill", highIcon: "speaker.wave.3.fill")
                }
                SettingsRow {
                    VStack(alignment: .leading, spacing: 12) {
                        SoundSlider(title: "Fade time", detail: "Fading back in takes a little longer, so music returns gently.",
                                    value: $session.fadeTime, range: 0...5, step: 0.1,
                                    text: { "\($0.formatted(.number.precision(.fractionLength(1)))) s" },
                                    lowIcon: "hare", highIcon: "tortoise",
                                    spoken: { "\($0.formatted(.number.precision(.fractionLength(1)))) seconds" })
                        FadeCurve(fadeOut: session.fadeTime)
                    }
                }
                SettingsRow(showsDivider: false) {
                    SoundSlider(title: "Lowered volume", detail: "When a rule lowers music, it plays at this share of normal.",
                                value: $session.duckLevel, range: 0.05...0.6, step: 0.05,
                                text: { "\(Int(($0 * 100).rounded()))%" }, lowIcon: "speaker.fill", highIcon: "speaker.wave.1.fill")
                }
            }
        }
    }
}

private struct SoundSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: (Double) -> String
    let lowIcon: String
    let highIcon: String
    var spoken: ((Double) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(text(value))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.accentText)
            }
            HStack(spacing: 10) {
                Image(systemName: lowIcon).frame(width: 18)
                MaunaSlider(value: $value, range: range, step: step, spokenValue: spoken)
                    .accessibilityLabel(title)
                Image(systemName: highIcon).frame(width: 18)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }
}

/// What a fade sounds like: equal-power out over the fade time, then in over 1.5× as long.
private struct FadeCurve: View {
    let fadeOut: Double
    private var fadeIn: Double { fadeOut * AudioTiming.fadeIn / AudioTiming.fadeOut }

    var body: some View {
        HStack(spacing: 12) {
            Canvas { context, size in
                let total = max(fadeOut + fadeIn, 0.01)
                let outWidth = size.width * fadeOut / total
                var path = Path()
                let steps = 40
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let point = CGPoint(x: outWidth * t, y: size.height * (1 - AudioTiming.fadeOutGain(t)))
                    i == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    path.addLine(to: CGPoint(x: outWidth + (size.width - outWidth) * t, y: size.height * (1 - AudioTiming.fadeInGain(t))))
                }
                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [Color(light: 0x5B56D8, dark: 0x8C88FF), Color(light: 0x4540B8, dark: 0xA9A5FF)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 34)
            .padding(.vertical, 4)
            .animation(.maunaSpring, value: fadeOut)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Out \(fadeOut.formatted(.number.precision(.fractionLength(1)))) s")
                Text("In \(fadeIn.formatted(.number.precision(.fractionLength(1)))) s")
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.popRow))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fades out over \(fadeOut.formatted()) seconds, back in over \(fadeIn.formatted()) seconds")
    }
}
