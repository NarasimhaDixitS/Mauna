import SwiftUI

/// Free vs Pro, side by side: exactly what each gives, nothing hidden. Used in Settings › Mauna Pro
/// and the Pro window. The row for what you reached for glows.
struct PlanComparison: View {
    var highlight: ProFeature? = nil

    private struct Line: Identifiable {
        let title: String
        let free: Value
        let pro: Value
        var feature: ProFeature? = nil
        var id: String { title }
    }

    private enum Value { case yes, no, text(String) }

    private let lines: [Line] = [
        Line(title: "Rules", free: .text("2"), pro: .text("Unlimited"), feature: .moreRules),
        Line(title: "\u{201C}In front\u{201D} trigger", free: .yes, pro: .yes),
        Line(title: "\u{201C}In a call\u{201D} and \u{201C}Running\u{201D}", free: .no, pro: .yes, feature: .everyTrigger),
        Line(title: "Pause music", free: .yes, pro: .yes),
        Line(title: "Lower music instead", free: .no, pro: .yes, feature: .lower),
        Line(title: "Spotify and Apple Music", free: .yes, pro: .yes),
        Line(title: "YouTube Music in Chrome and Safari", free: .no, pro: .yes, feature: .youTubeMusic),
        Line(title: "Quiet shortcut", free: .yes, pro: .yes),
        Line(title: "Your own fade time", free: .no, pro: .yes, feature: .customFade),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("Free")
                    .frame(width: 84)
                    .foregroundStyle(.secondary)
                Text("Pro")
                    .frame(width: 84)
                    .foregroundStyle(.accentText)
            }
            .font(.callout.weight(.semibold))
            .padding(.bottom, 8)

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack(spacing: 0) {
                    Text(line.title)
                        .font(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.leading, 12)
                    Spacer(minLength: 8)
                    cell(line.free, pro: false).frame(width: 84)
                    cell(line.pro, pro: true).frame(width: 84)
                }
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(line.feature != nil && line.feature == highlight
                              ? AnyShapeStyle(LinearGradient.accentRowTint)
                              : AnyShapeStyle(index.isMultiple(of: 2) ? Color.popRow.opacity(0.6) : .clear))
                }
            }
        }
        // The Pro column glows faintly, top to bottom.
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentTint.opacity(0.6))
                .frame(width: 84)
                .padding(.vertical, -4)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func cell(_ value: Value, pro: Bool) -> some View {
        switch value {
        case .yes:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(pro ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
                .accessibilityLabel("Included")
        case .no:
            Text("—")
                .foregroundStyle(.quaternary)
                .accessibilityLabel("Not included")
        case .text(let text):
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(pro ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
        }
    }
}

/// Settings › Mauna Pro: your plan at the top (Free, the trial, or Pro · Lifetime), then Free vs Pro.
struct ProSettings: View {
    let model: AppModel
    @State private var restoring = false
    @State private var note: String?

    private var store: Store { model.store }
    private var plan: Plan { store.plan }

    var body: some View {
        SettingsPage(symbol: "sparkle", title: "Mauna Pro", subtitle: "One purchase. Yours for life.") {
            SettingsCard {
                HStack(spacing: 16) {
                    StatusTile(state: plan.unlocksPro ? .playing : .paused, isActing: plan.unlocksPro, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(title).font(.title3.weight(.semibold))
                            if plan == .pro { ProBadge() }
                        }
                        Text(note ?? detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if plan != .pro {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button { model.showUpgrade(for: nil) } label: {
                                Text(store.pro.map { "Unlock for Life · \($0.displayPrice)" } ?? "Unlock Pro")
                            }
                            .buttonStyle(.maunaPrimary)
                            .fixedSize()
                            Button(restoring ? "Restoring…" : "Restore Purchase", action: restore)
                                .buttonStyle(PlainTextButtonStyle())
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .disabled(restoring)
                        }
                    }
                }
                .padding(16)
            }

            SettingsCard {
                PlanComparison()
                    .padding(16)
            }

            Text(plan == .pro
                 ? "Thank you for supporting Mauna. Every future update is included."
                 : "Pay once, keep it forever: no subscription, every update included.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var title: String {
        switch plan {
        case .pro: "Mauna Pro · Lifetime"
        case .trial: "Mauna Pro trial"
        case .free: "Mauna Free"
        }
    }

    private var detail: String {
        switch plan {
        case .pro: return "Everything is unlocked, for good."
        case .trial:
            let days = plan.trialDaysLeft(now: .now) ?? 1
            return "\(days) \(days == 1 ? "day" : "days") left. Afterwards your first two simple rules keep working; nothing is deleted."
        case .free: return "Two rules, \u{201C}In front\u{201D}, Pause, Spotify and Apple Music."
        }
    }

    private func restore() {
        restoring = true
        Task {
            let outcome = await store.restore()
            restoring = false
            switch outcome {
            case .unlocked: note = "Restored. Everything is unlocked."
            case .failed(let text): note = text
            case .cancelled, .pending: break
            }
        }
    }
}
