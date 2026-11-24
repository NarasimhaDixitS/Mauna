import SwiftUI

/// The popover under the menu bar icon. Built to design-system.html › popover, measure for measure:
/// 8pt outer padding; header (34pt glyph tile, status, switch); Quiet now; the volume well;
/// a hairline; Rules; a hairline; the footer.
struct PopoverView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 12)

            QuietNowButton(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            PlayerCard(session: model.session)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            if let issue = model.session.issue, issue.needsSetup {
                SetupNotice(issue: issue)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            Hairline()
            RulesList(model: model)
            Hairline()

            footer
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
        .padding(8)
        .frame(width: Size.popoverWidth)
        .onAppear { model.session.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            GlyphTile(state: model.glyphState, isActing: model.isActing)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusLine)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .id(model.statusLine)
                    .transition(.blurCrossfade)
                Text(model.detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .id(model.detailLine)
                    .transition(.blurCrossfade)
            }
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: model.statusLine)
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: model.detailLine)

            Spacer(minLength: 0)

            // Master switch in the header, like Wi-Fi in Control Center. Native control, accent tint.
            Toggle("Mauna", isOn: Binding(get: { model.rules.isEnabled }, set: { model.rules.isEnabled = $0 }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.accentFill)
                .accessibilityLabel("Mauna on")
        }
    }

    private var footer: some View {
        HStack {
            SettingsButton(title: "Settings…", symbol: "gearshape")
                .keyboardShortcut(",")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .buttonStyle(PlainTextButtonStyle())
    }
}

/// `.btn.primary`, full width: does exactly what the shortcut does. The key hint sits beside the label at 70%.
private struct QuietNowButton: View {
    let model: AppModel

    var body: some View {
        Button {
            model.quietPressed()
        } label: {
            HStack(spacing: 7) {
                Text(model.isQuietedByYou ? "Bring music back" : "Quiet now")
                if let shortcut = model.shortcutText {
                    Text(shortcut)
                        .font(.subheadline)
                        .opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.maunaPrimary)
        .disabled(!model.canQuiet)
    }
}

/// The status hero: 40pt tile. At rest a quiet well; while Mauna acts, an indigo gradient with a soft glow.
private struct GlyphTile: View {
    let state: GlyphState
    let isActing: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        WaveGlyphView(state: state, size: 22)
            .foregroundStyle(isActing ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 40, height: 40)
            .background {
                ZStack {
                    shape.fill(.well)
                    shape.fill(LinearGradient.accentFill)
                        .shadow(color: .accentShadow, radius: 6, y: 2)
                        .opacity(isActing ? 1 : 0)
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(isActing ? 0.35 : 0.0), .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 0.5
                )
            }
            .animation(.maunaEaseOut(0.25), value: isActing)
    }
}

/// The player: its real icon, what Mauna is doing to it, and the normal volume you can drag.
/// Dragging sets the level music always returns to, and moves the player now if it's playing untouched.
private struct PlayerCard: View {
    @Bindable var session: PlayerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppIconView(bundleID: session.player.bundleID, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.player.displayName)
                        .font(.body.weight(.medium))
                    Text(stateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .id(stateText)
                        .transition(.blurCrossfade)
                }
                .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: stateText)
                Spacer(minLength: 0)
                Text(percentText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            if session.player.isBrowser {
                // The page owns its volume: Mauna only lowers and pauses it, then hands it back.
                Label("Volume follows YouTube Music", systemImage: "slider.horizontal.below.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                    MaunaSlider(value: $session.normalVolume, range: 0.1...1, step: 0.01)
                        .accessibilityLabel("Normal volume")
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.popRow))
    }

    /// Native players: the normal volume you set. YouTube Music: the level you hear now.
    private var percentText: String {
        if session.player.isBrowser {
            guard let volume = session.volume, session.playback == .playing else { return "" }
            return "\(Int((volume * 100).rounded()))%"
        }
        return "\(Int((session.normalVolume * 100).rounded()))%"
    }

    private var stateText: String {
        guard session.isRunning else { return session.player.browserName.map { "\($0) isn't open" } ?? "Not open" }
        if session.player.isBrowser, session.playback == .stopped, session.hold == .none { return "No YouTube Music tab open" }
        switch session.hold {
        case .paused: return "Paused by Mauna"
        case .ducked: return "Lowered by Mauna"
        case .none:
            switch session.playback {
            case .playing: return "Playing"
            case .paused:  return "Paused"
            case .stopped, nil: return "Nothing playing"
            }
        }
    }
}

/// Orange = needs setup. One plain sentence on why, then the next step.
private struct SetupNotice: View {
    let issue: PlayerSession.Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.needsSetup)
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .needsBrowserSetup(let player) = issue {
                MenuPath(items: player == .youTubeMusicSafari
                         ? ["Develop", "Allow JavaScript from Apple Events"]
                         : ["View", "Developer", "Allow JavaScript from Apple Events"])
                SettingsButton(title: "Show me how", tab: .players)
                    .buttonStyle(.maunaSmall)
            } else {
                Button("Open Automation Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.maunaSmall)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
    }

    private var title: String {
        switch issue {
        case .needsPermission(let player): "Mauna can't control \(player.fullName)"
        case .needsBrowserSetup(let player): "Allow Mauna in \(player.browserName ?? "the browser")"
        case .failed(let message): message
        }
    }

    private var reason: String {
        switch issue {
        case .needsPermission: "Allow it in Privacy & Security › Automation, so Mauna can pause and fade your music."
        case .needsBrowserSetup: "Turn on one setting, so Mauna can pause and fade YouTube Music."
        case .failed: ""
        }
    }
}

/// Opens Settings, optionally at a tab, and brings it to the front.
/// Mauna has no Dock icon, so it must activate itself first.
struct SettingsButton: View {
    let title: String
    var symbol: String?
    var tab: SettingsTab?
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .rules

    var body: some View {
        Button {
            if let tab { selectedTab = tab }
            NSApplication.shared.activate()
            openSettings()
        } label: {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }
}

#Preview("Popover") {
    PopoverView(model: AppModel())
}
