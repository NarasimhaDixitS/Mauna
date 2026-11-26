import SwiftUI

@main
struct MaunaApp: App {
    @State private var model = AppModel()

    #if DEBUG
    init() {
        // Debug only: MAUNA_SNAPSHOT=/path.png renders the popover to an image and quits, for design review.
        if let path = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT"] {
            DesignSnapshot.render(to: path)
        }
        if let directory = ProcessInfo.processInfo.environment["MAUNA_ICON_EXPORT"] {
            IconExport.run(to: directory)
            exit(0)
        }
        if ProcessInfo.processInfo.environment["MAUNA_PROBE"] != nil {
            DesignSnapshot.probeYouTubeMusic()
        }
    }
    #endif

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
            SettingsView(model: model)
        }
    }
}
