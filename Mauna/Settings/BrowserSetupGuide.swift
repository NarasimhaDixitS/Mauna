import AppKit
import SwiftUI

/// The one-time browser setting YouTube Music needs, shown as the real menu path.
/// Used in Settings › Players, onboarding, and (short form) the popover.
struct BrowserSetupGuide: View {
    let player: PlayerID
    let session: PlayerSession
    var needsSetup: Bool { session.issue == .needsBrowserSetup(player) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(LinearGradient.accentFill))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.text).font(.callout)
                        if !step.path.isEmpty { MenuPath(items: step.path) }
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Open YouTube Music") { openYouTubeMusic() }
                    .buttonStyle(.maunaSmall)
                Button("Check again") { session.refresh() }
                    .buttonStyle(.maunaSmall)
                Spacer()
                if session.player == player, !needsSetup, session.isRunning, session.playback != nil {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.accentText)
                }
            }
        }
    }

    private struct Step { let text: String; let path: [String] }

    private var steps: [Step] {
        switch player {
        case .youTubeMusicSafari:
            [Step(text: "In Safari's settings, turn on the developer features.", path: ["Safari", "Settings…", "Advanced", "Show features for web developers"]),
             Step(text: "Then allow Mauna to pause and play the page.", path: ["Develop", "Allow JavaScript from Apple Events"]),
             Step(text: "Keep a YouTube Music tab open while you listen.", path: [])]
        default:
            [Step(text: "In Chrome's menu bar, allow Mauna to pause and play the page.", path: ["View", "Developer", "Allow JavaScript from Apple Events"]),
             Step(text: "Keep a YouTube Music tab open while you listen.", path: [])]
        }
    }

    private func openYouTubeMusic() {
        guard let url = URL(string: "https://music.youtube.com"), let app = player.appURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A menu path drawn as small chips: View › Developer › Allow JavaScript from Apple Events.
struct MenuPath: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Text(item)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .elevated(.e1, cornerRadius: 5, fill: .control)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.joined(separator: ", then "))
    }
}
