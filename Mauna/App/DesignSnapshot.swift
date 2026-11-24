#if DEBUG
import AppKit
import SwiftUI

/// Renders the popover to a PNG so its design can be checked against design-system.html without
/// screen recording. Native AppKit controls (the switch) don't draw in ImageRenderer.
enum DesignSnapshot {
    /// Debug only: lowers YouTube Music in Chrome to 20%, then logs what the page does to it for 10 s.
    static func probeYouTubeMusic() {
        let player = BrowserPlayer(player: .youTubeMusicChrome)
        let read = "JSON.stringify({ctx:c&&c.state,gain:g?Math.round(g.gain.value*1000)/1000:null,el:v?v.volume:null,paused:v?v.paused:null,hold:w.__maunaHold})"
        if let code = ProcessInfo.processInfo.environment["MAUNA_PROBE_JS"] {
            Task {
                do { print(try await player.js(code) ?? "no tab") } catch { print("error", error) }
                fflush(stdout); exit(0)
            }
            return
        }
        Task {
            do {
                let before = try await player.js(read) ?? "no tab"
                print("before", before)
                try await player.setVolume(0.2)
                let start = Date()
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(500))
                    print(String(format: "%5.1fs", Date().timeIntervalSince(start)), try await player.js(read) ?? "no tab")
                }
                let home = try await player.homeVolume() ?? 1
                try await player.setVolume(home)
                try await player.releaseVolume()
                print("restored to", home)
            } catch {
                print("error", error)
            }
            fflush(stdout)
            exit(0)
        }
    }

    static func render(to path: String) {
        let dark = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_DARK"] != nil
        let model = AppModel()
        let suggestions = SuggestionsState()
        Task { await suggestions.load(existing: model.rules) }
        let which = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_VIEW"] ?? "popover"
        let content: AnyView = switch which {
        case "players": AnyView(PlayersSettings(session: model.session))
        case "rules":   AnyView(RulesSettings(coordinator: model.rules))
        case "sound":   AnyView(SoundSettings(session: model.session))
        case "general": AnyView(GeneralSettings())
        case "states":  AnyView(StatesSheet())
        case "welcome1": AnyView(OnboardingView(model: model, startStep: 0))
        case "welcome2": AnyView(OnboardingView(model: model, startStep: 1, suggestions: suggestions))
        case "welcome3": AnyView(OnboardingView(model: model, startStep: 2))
        default:        AnyView(PopoverView(model: model))
        }
        let background = which == "popover"
            ? (dark ? Color(white: 0.16) : Color(white: 0.97))
            : (dark ? Color(white: 0.12) : Color(white: 0.93))
        let view = content
            .background(background)
            .environment(\.colorScheme, dark ? .dark : .light)
        // Let the first AppleScript reads land.
        let host = NSHostingView(rootView: view)   // lets .task (the app scan) run before rendering
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        _ = host
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}

/// The accent states a quiet popover never shows: acting tile, enabled Quiet now, active row and badge.
private struct StatesSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WaveGlyphView(state: .paused, size: 22)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient.accentFill)
                        .shadow(color: .accentShadow, radius: 6, y: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paused for TextEdit").font(.system(size: 14, weight: .semibold))
                    Text("Resumes when you leave TextEdit").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button {} label: {
                HStack(spacing: 7) { Text("Quiet now"); Text("⌃⌥Space").font(.subheadline).opacity(0.7) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.maunaPrimary)
            HStack(spacing: 10) {
                AppIconView(bundleID: "com.apple.TextEdit")
                Text("TextEdit")
                Text("now").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.accentText)
                Spacer()
                Badge(symbol: "macwindow", text: "Front", isAccent: true)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .rowHover(isActive: true)
            SettingsHeader(symbol: "app.badge.checkmark", title: "Rules", subtitle: "Apps that quiet your music, and when.")
        }
        .padding(16)
        .frame(width: 320)
    }
}
#endif
