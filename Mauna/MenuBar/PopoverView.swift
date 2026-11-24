import SwiftUI

/// The popover under the menu bar icon. Phase 1: live status header, a debug player panel, and the footer.
/// The real switch, Quiet now and rules list arrive in Phase 4.
struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.m)

            if case .needsPermission(let player) = model.session.issue {
                Divider().overlay(.hairline)
                PermissionNotice(player: player)
                    .padding(Spacing.m)
            }

            Divider().overlay(.hairline)
            RulesList(coordinator: model.rules)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.s)

            #if DEBUG
            Divider().overlay(.hairline)
            PlayerDebugPanel(session: model.session)
                .padding(Spacing.m)
            #endif

            Divider().overlay(.hairline)
            footer
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
        }
        .frame(width: Size.popoverWidth)
        .onAppear { model.session.refresh() }
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            // Accent fill only while Mauna is acting on the music.
            WaveGlyphView(state: model.glyphState, size: 20)
                .foregroundStyle(model.isActing ? .white : .primary)
                .frame(width: Size.statusGlyphTile, height: Size.statusGlyphTile)
                .background(
                    RoundedRectangle(cornerRadius: Radius.glyphTile, style: .continuous)
                        .fill(model.isActing ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.quaternary))
                )
                .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: model.isActing)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(model.statusLine)
                    .font(.headline)
                    .id(model.statusLine)
                    .transition(.blurCrossfade)
                Text(model.detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .id(model.detailLine)
                    .transition(.blurCrossfade)
            }
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: model.statusLine)
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: model.detailLine)

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            SettingsButton()
            Spacer()
            Button("Quit Mauna") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

/// Orange = needs setup. One plain sentence on why, then the next step.
private struct PermissionNotice: View {
    let player: PlayerID

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label("Mauna can't control \(player.displayName)", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.needsSetup)
            Text("Allow it in Privacy & Security › Automation, so Mauna can pause and fade your music.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Automation Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

#if DEBUG
/// Phase 1 test controls. Replaced by rules and the quiet shortcut in later phases.
private struct PlayerDebugPanel: View {
    @Bindable var session: PlayerSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Player test (debug)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if PlayerID.installed.count > 1 {
                    Picker("Player", selection: Binding(get: { session.player }, set: { session.select($0) })) {
                        ForEach(PlayerID.installed) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            HStack(spacing: Spacing.s) {
                Button("Pause") { session.quiet(.pause) }
                    .disabled(session.hold == .paused)
                Button("Lower") { session.quiet(.duck) }
                    .disabled(session.hold != .none)
                Button("Restore") { session.release() }
                    .disabled(session.hold == .none)
            }
            .disabled(!session.isRunning)

            // What you hear. While paused the player is silent, even though its own
            // volume is already back at the normal level for when it plays again.
            LabeledContent("You hear") {
                Text(heardVolume)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: heardVolume)
            }
            .font(.callout)

            LabeledContent("Normal volume") {
                HStack {
                    Slider(value: $session.normalVolume, in: 0.1...1, step: 0.05)
                        .frame(width: 120)
                    Text("\(Int((session.normalVolume * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .font(.callout)

            if case .failed(let message) = session.issue {
                Text(message).font(.callout).foregroundStyle(.failed)
            }
        }
    }

    private var heardVolume: String {
        guard session.isRunning, let volume = session.volume else { return "–" }
        let percent = "\(Int((volume * 100).rounded()))%"
        // Mid-fade the player is still playing, so show the live number until it actually pauses.
        if session.playback != .playing && !session.isFading { return "Silent · plays at \(percent)" }
        return percent
    }
}
#endif

/// Opens Settings and brings it to the front. Mauna has no Dock icon, so it must activate itself first.
private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApplication.shared.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

#Preview("Popover") {
    PopoverView(model: AppModel())
}
