import KeyboardShortcuts
import SwiftUI

/// Settings window. Phase 3: the quiet shortcut. Rules, Sound and the full General tab arrive in Phase 4.
struct SettingsView: View {
    @AppStorage(QuietShortcut.Mode.storageKey) private var mode: QuietShortcut.Mode = .pause

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Quiet shortcut", name: .quietMusic)
                Picker("When pressed", selection: $mode) {
                    ForEach(QuietShortcut.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } footer: {
                Text("Press once to quiet your music from any app, press again to bring it back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Size.settingsWindowWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
