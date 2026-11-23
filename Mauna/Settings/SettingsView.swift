import SwiftUI

/// Settings window. Placeholder until Phase 4 adds the Rules, Sound and General tabs.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: Spacing.s) {
            WaveGlyphView(state: .playing, size: 36)
                .foregroundStyle(.accentFill)
            Text("Settings come in a later build")
                .font(.headline)
            Text("Rules, sound and shortcut options will live here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xxxl)
        .frame(width: Size.settingsWindowWidth)
    }
}

#Preview {
    SettingsView()
}
