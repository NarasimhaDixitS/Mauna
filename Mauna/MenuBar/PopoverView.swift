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

            PlayerCard(session: model.session, unlocksPro: model.unlocksPro,
                       upgrade: { model.showUpgrade(for: $0) })
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
        .background {
            // Full-screen Spaces: grow down from the menu bar, never off the top.
            // (Left out of design renders, which can't draw AppKit views.)
            if ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT"] == nil { PopoverTopPin() }
        }
        .onAppear { model.session.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            StatusTile(state: model.glyphState, isActing: model.isActing)

            VStack(alignment: .leading, spacing: 2) {
                // "YouTube Music is paused" is long: step down a size rather than cut it off.
                ViewThatFits(in: .horizontal) {
                    Text(model.statusLine).font(.system(size: 14, weight: .semibold))
                    Text(model.statusLine).font(.system(size: 12.5, weight: .semibold))
                }
                    .lineLimit(1)
                    .id(model.statusLine)
                    .transition(.blurCrossfade)
                ViewThatFits(in: .horizontal) {
                    Text(model.detailLine).font(.subheadline)
                    Text(model.detailLine).font(.caption)
                }
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
            if Store.sellsInApp {
                if model.store.plan == .pro {
                    // Owned: a quiet gold mark, not a pitch. Opens Settings › Mauna Pro.
                    SettingsButton(title: "Mauna Pro", symbol: "sparkle", tab: .pro)
                        .foregroundStyle(.accentText)
                        .help("You have Mauna Pro, for life")
                } else {
                    Button { model.showUpgrade(for: nil) } label: { ProLink(plan: model.store.plan) }
                }
                Spacer()
            }
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

/// The player, as a "now playing" tile lit by the player's own colour. Tap its name and the card unfolds
/// in place into your players (like Control Center's sound output list); pick one and it folds back.
/// Rules follow the choice at once. Dragging the slider sets the level music always returns to.
private struct PlayerCard: View {
    @Bindable var session: PlayerSession
    var unlocksPro = true
    var upgrade: (ProFeature) -> Void = { _ in }
    #if DEBUG
    /// MAUNA_SNAPSHOT_CHOOSING=1 renders the card open.
    @State private var choosing = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_CHOOSING"] != nil
    #else
    @State private var choosing = false
    #endif
    @Environment(\.colorScheme) private var scheme

    private var canChoose: Bool { PlayerID.installed.count > 1 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(10)

            if choosing {
                PlayerList(current: session.player, unlocksPro: unlocksPro) { player in
                    withAnimation(.maunaSpring) {
                        choosing = false
                        if player.isBrowser && !unlocksPro {
                            upgrade(.youTubeMusic)
                        } else {
                            session.select(player)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                // Unfolds inside the card: fades in while settling a few points down from under the header.
                .transition(.opacity.combined(with: .offset(y: -8)).animation(.maunaEaseOut(0.2)))
            } else {
                volumeRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.animation(.maunaEaseOut(0.15)))
            }
        }
        .clipShape(shape)   // nothing draws outside the card while it unfolds or folds
        .background {
            ZStack(alignment: .topLeading) {
                shape.fill(.popRow)
                // The player's colour, glowing from behind its icon. Changes with the player.
                RadialGradient(
                    colors: [session.player.tint.opacity(scheme == .dark ? 0.26 : 0.17), .clear],
                    center: UnitPoint(x: 0.1, y: 0), startRadius: 0, endRadius: 170
                )
                .animation(.maunaEaseOut(0.35), value: session.player)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 6, y: 3)
        }
        .overlay {
            shape.strokeBorder(.primary.opacity(scheme == .dark ? 0.06 : 0.05), lineWidth: 0.5)
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.16 : 0.7), .clear],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)),
                lineWidth: 0.5
            )
        }
    }

    /// Icon, name and state, then play/pause, then the round button that opens the list of players.
    /// Tapping the name opens the list too.
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: toggleChooser) {
                HStack(spacing: 11) {
                    PlayerIcon(player: session.player, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.player.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(stateText)
                            .font(.subheadline)
                            .foregroundStyle(session.hold != .none ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .id(stateText)
                            .transition(.blurCrossfade)
                    }
                    .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: stateText)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .help(canChoose ? "Choose the player Mauna controls" : "")
            .accessibilityLabel("\(session.player.fullName), \(stateText)")
            .accessibilityHint(canChoose ? "Choose another player" : "")

            PlayPauseButton(session: session)

            if canChoose {
                Button(action: toggleChooser) { ChooseButtonFace(isOpen: choosing) }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel(choosing ? "Close players" : "Choose player")
            }
        }
    }

    private func toggleChooser() {
        guard canChoose else { return }
        withAnimation(.maunaSpring) { choosing.toggle() }
    }

    @ViewBuilder private var volumeRow: some View {
        if session.isLocked {
            // YouTube Music on Free: say so once, with the way to unlock it.
            Button { upgrade(.youTubeMusic) } label: {
                HStack(spacing: 6) {
                    Text("Mauna rests on YouTube Music on Free")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    ProBadge()
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainTextButtonStyle())
        } else if session.player.isBrowser {
            // Mauna's own level on top of YouTube Music's volume. The page's slider stays its own.
            VStack(alignment: .leading, spacing: 4) {
                volumeSlider($session.browserLevel, label: "YouTube Music level")
                Text("Of YouTube Music's own volume")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
            }
        } else {
            volumeSlider($session.normalVolume, label: "Normal volume")
        }
    }

    private func volumeSlider(_ value: Binding<Double>, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
            MaunaSlider(value: value, range: 0.1...1, step: 0.01)
                .accessibilityLabel(label)
            Text(percentText)
                .font(.subheadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 32, alignment: .trailing)
        }
        .foregroundStyle(.tertiary)
    }

    /// The level music comes back to: the player's normal volume, or Mauna's YouTube Music level.
    private var percentText: String {
        let level = session.player.isBrowser ? session.browserLevel : session.normalVolume
        return "\(Int((level * 100).rounded()))%"
    }

    /// "Playing", "Lowered by Mauna". Browser players say where: "Playing in Chrome".
    private var stateText: String {
        let place = session.player.browserName.map { " in \($0)" } ?? ""
        guard session.isRunning else { return session.player.browserName.map { "\($0) isn't open" } ?? "Not open" }
        if session.player.isBrowser, session.playback == .stopped, session.hold == .none { return "No YouTube Music tab open" }
        switch session.hold {
        case .paused: return "Paused by Mauna"
        case .ducked: return "Lowered by Mauna"
        case .none:
            switch session.playback {
            case .playing: return "Playing\(place)"
            case .paused:  return "Paused\(place)"
            case .stopped, nil: return "Nothing playing"
            }
        }
    }
}

/// Play/pause for the player. A raised round face, like the player's own transport button.
/// While Mauna holds the music paused, play brings it back exactly as pressing play in the player would.
private struct PlayPauseButton: View {
    let session: PlayerSession

    private var showsPause: Bool { session.hold != .paused && session.playback == .playing }

    var body: some View {
        Button { session.togglePlayback() } label: {
            Image(systemName: showsPause ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .offset(x: showsPause ? 0 : 1)   // a play triangle looks centred a touch to the right
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(.control)
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                }
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 0.5
                    )
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!session.canTogglePlayback)
        .opacity(session.canTogglePlayback ? 1 : 0.4)
        .help(showsPause ? "Pause" : (session.hold == .paused ? "Bring music back" : "Play"))
        .accessibilityLabel(showsPause ? "Pause" : "Play")
    }
}

/// The small round control at the end of the player row: ⌃⌄ at rest, ✕-like "done" chevron when open.
private struct ChooseButtonFace: View {
    let isOpen: Bool

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .foregroundStyle(isOpen ? AnyShapeStyle(Color.onAccent) : AnyShapeStyle(.secondary))
            .frame(width: 24, height: 24)
            .background {
                ZStack {
                    Circle().fill(.well)
                    Circle().fill(LinearGradient.accentFill).opacity(isOpen ? 1 : 0)
                }
            }
            .overlay(Circle().strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
            .animation(.maunaEaseOut(0.2), value: isOpen)
    }
}

/// Your installed players, one row each: icon, name, where it plays or whether it's open, and a check
/// on the one Mauna controls. Rows light up under the pointer.
private struct PlayerList: View {
    let current: PlayerID
    var unlocksPro = true
    let choose: (PlayerID) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Rectangle().fill(.hairline).frame(height: 0.5).padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(PlayerID.installed) { player in
                let isOn = player == current
                Button { choose(player) } label: {
                    HStack(spacing: 10) {
                        PlayerIcon(player: player, size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(player.displayName)
                                .font(.body.weight(isOn ? .semibold : .regular))
                            Text(detail(for: player))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if player.isBrowser && !unlocksPro { ProBadge() }
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.accentText)
                            .opacity(isOn ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                    .rowHover(cornerRadius: 9, isActive: isOn)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(player.fullName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func detail(for player: PlayerID) -> String {
        if let browser = player.browserName {
            return player.isRunning ? "In \(browser)" : "In \(browser) · not open"
        }
        return player.isRunning ? "Open" : "Not open"
    }
}

/// A player's icon. YouTube Music is its browser's icon with the red play mark.
private struct PlayerIcon: View {
    let player: PlayerID
    let size: CGFloat

    var body: some View {
        AppIconView(bundleID: player.bundleID, size: size)
            .overlay(alignment: .bottomTrailing) {
                if player.isBrowser { MusicMark(size: size * 0.44).offset(x: size * 0.08, y: size * 0.08) }
            }
    }
}

/// A small red play mark on a browser's icon: this is YouTube Music in that browser.
struct MusicMark: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(red: 0.93, green: 0.13, blue: 0.13))
            .overlay(
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.03)
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1, size * 0.1)))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
    }
}

extension PlayerID {
    /// The player's own colour, for the glow behind its card.
    var tint: Color {
        switch self {
        case .spotify: Color(red: 0.11, green: 0.73, blue: 0.33)
        case .appleMusic: Color(red: 0.98, green: 0.18, blue: 0.28)
        case .youTubeMusicChrome, .youTubeMusicSafari: Color(red: 1.0, green: 0.1, blue: 0.15)
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
            WindowFront.activate()
            openSettings()
            WindowFront.raiseSettings()
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

/// Footer link to Mauna Pro: "Get Pro", or the trial's days left. Quiet, never a nag.
private struct ProLink: View {
    let plan: Plan

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .semibold))
            if let days = plan.trialDaysLeft(now: .now) {
                Text("Pro trial · \(days) \(days == 1 ? "day" : "days") left")
            } else {
                Text("Get Pro")
            }
        }
        .foregroundStyle(.accentText)
    }
}
