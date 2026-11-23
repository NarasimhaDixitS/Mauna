import SwiftUI

@main
struct MaunaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            // The menu bar glyph swaps instantly between states. It never animates (DESIGN.md › Motion).
            Image(nsImage: WaveGlyph.menuBarImage(for: model.glyphState))
                .accessibilityLabel("Mauna, \(model.glyphState.spokenName)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
