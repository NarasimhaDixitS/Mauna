import SwiftUI

/// The popover under the menu bar icon. Phase 0: header, a debug glyph switcher, and the footer.
/// The real status line, switch, Quiet now and rules list arrive in Phase 4.
struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.m)

            #if DEBUG
            Divider().overlay(.hairline)
            debugGlyphSwitcher
                .padding(Spacing.m)
            #endif

            Divider().overlay(.hairline)
            footer
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
        }
        .frame(width: Size.popoverWidth)
    }

    private var isActing: Bool { model.glyphState == .ducked || model.glyphState == .paused }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            // Accent fill only while Mauna is acting on the music.
            WaveGlyphView(state: model.glyphState, size: 20)
                .foregroundStyle(isActing ? .white : .primary)
                .frame(width: Size.statusGlyphTile, height: Size.statusGlyphTile)
                .background(
                    RoundedRectangle(cornerRadius: Radius.glyphTile, style: .continuous)
                        .fill(isActing ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.quaternary))
                )
                .animation(.maunaEaseOut(MotionDuration.rowHighlight), value: isActing)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(statusLine)
                    .font(.headline)
                    .id(statusLine)
                    .transition(.blurCrossfade)
                Text("Not watching any apps yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .animation(.maunaEaseOut(MotionDuration.textCrossfade), value: statusLine)

            Spacer(minLength: 0)
        }
    }

    private var statusLine: String {
        switch model.glyphState {
        case .playing: "Mauna is ready"
        case .ducked:  "Lowered"
        case .paused:  "Paused"
        case .off:     "Mauna is off"
        }
    }

    #if DEBUG
    private var debugGlyphSwitcher: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Glyph state (debug)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Glyph state", selection: $model.glyphState) {
                ForEach(GlyphState.allCases, id: \.self) { state in
                    Text(state.spokenName.capitalized).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
    #endif

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
