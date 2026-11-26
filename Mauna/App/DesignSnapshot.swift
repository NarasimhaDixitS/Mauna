#if DEBUG
import AppKit
import SwiftUI

/// Renders the popover to a PNG so its design can be checked against design-system.html without
/// screen recording. Native AppKit controls (the switch) don't draw in ImageRenderer.
enum DesignSnapshot {
    /// Debug only: lowers YouTube Music to 20%, then logs what the page does to it for 10 s.
    /// Chrome by default; `MAUNA_PROBE_PLAYER=safari` for Safari.
    static func probeYouTubeMusic() {
        let safari = ProcessInfo.processInfo.environment["MAUNA_PROBE_PLAYER"] == "safari"
        let player = BrowserPlayer(player: safari ? .youTubeMusicSafari : .youTubeMusicChrome)
        let read = safari
            ? "JSON.stringify({level:L(),wish:v?v.volume:null,el:v?Math.round(d.get.call(v)*1000)/1000:null,paused:v?v.paused:null})"
            : "JSON.stringify({ctx:c&&c.state,gain:g?Math.round(g.gain.value*1000)/1000:null,el:v?v.volume:null,paused:v?v.paused:null,hold:w.__maunaHold})"
        if let count = ProcessInfo.processInfo.environment["MAUNA_PROBE_RULES"].flatMap(Int.init) {
            // Time how long Settings › Rules takes to appear with `count` rules (nothing is saved).
            let model = AppModel()
            model.session.dryRun = true
            let names = ["Notes", "Xcode", "Figma", "Zoom", "Keynote", "Pages", "Numbers", "TV", "VLC", "Chess"]
            model.rules.showPreviewRules((0..<count).map { i in
                Rule(bundleID: "test.app\(i)", appName: "\(names[i % names.count]) \(i)", trigger: i % 3 == 0 ? .running : .inFront,
                     action: i % 2 == 0 ? .paused : .ducked)
            })
            model.store.preview(.pro)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            let start = Date()
            let host = NSHostingView(rootView: RulesSettings(model: model).frame(width: 620, height: 600))
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            host.display()
            print("rules page with \(count) rules appeared in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            fflush(stdout); exit(0)
        }
        if ProcessInfo.processInfo.environment["MAUNA_PROBE_MIC"] != nil {
            for line in MicWatcher.describeAll() { print(line) }
            let watcher = MicWatcher()
            print("apps in a call:", watcher.appsInCall.sorted())
            fflush(stdout); exit(0)
        }
        if ProcessInfo.processInfo.environment["MAUNA_PROBE_TIMES"] != nil {
            Task {
                var times: [Int] = []
                for _ in 0..<10 {
                    let t = Date()
                    _ = try? await player.state()
                    times.append(Int(Date().timeIntervalSince(t) * 1000))
                }
                print("state() ms:", times); fflush(stdout); exit(0)
            }
            return
        }
        if ProcessInfo.processInfo.environment["MAUNA_PROBE_PAUSE"] != nil {
            Task {
                let t0 = Date()
                func log(_ s: String) { print(String(format: "%6.2fs ", Date().timeIntervalSince(t0)), s); fflush(stdout) }
                do {
                    for _ in 0..<2 {
                        log("state \(try await player.state())")
                        log("volume \(try await player.volume())")
                        try await VolumeFader.fade(player, from: 1, to: 0, duration: 1.2) { _ in log("step") }
                        try await player.pause(); log("paused")
                        try await player.setVolume(1); try await player.releaseVolume(); log("reset")
                        try await Task.sleep(for: .seconds(1))
                        try await player.play(); log("playing again")
                        try await Task.sleep(for: .seconds(3))
                    }
                } catch { log("error \(error)") }
                exit(0)
            }
            return
        }
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
        // MAUNA_SNAPSHOT_PLAYER=youTubeMusicChrome renders with that player chosen.
        if let raw = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_PLAYER"], let player = PlayerID(rawValue: raw) {
            model.session.select(player)
        }
        // MAUNA_SNAPSHOT_DEMO=1: a full set of rules (not saved), one acting on the app in front.
        // Dry run: rules decide, nothing is sent to the player.
        if ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_DEMO"] != nil {
            model.session.dryRun = true
            let front = model.rules.frontmost.flatMap { id in
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first.map { (id, $0.localizedName ?? id) }
            }
            var demo: [Rule] = [
                Rule(bundleID: "com.apple.Notes", appName: "Notes", trigger: .inFront, action: .ducked),
                Rule(bundleID: "com.apple.TextEdit", appName: "TextEdit", trigger: .inFront, action: .paused),
                Rule(bundleID: "com.apple.FaceTime", appName: "FaceTime", trigger: .usingMicOrSound, action: .paused),
                Rule(bundleID: "com.apple.QuickTimePlayerX", appName: "QuickTime Player", trigger: .inFront, action: .paused),
                Rule(bundleID: "com.apple.TV", appName: "TV", trigger: .inFront, action: .paused),
                Rule(bundleID: "com.apple.Chess", appName: "Chess", trigger: .running, action: .paused),
                Rule(bundleID: "com.apple.finder", appName: "Finder", trigger: .inFront, action: .ducked),
                Rule(bundleID: "com.apple.Preview", appName: "Preview", trigger: .inFront, action: .ducked),
            ]
            // MAUNA_SNAPSHOT_FRONT_FREE=1 leaves the app in front without a rule (the quick rule card).
            if let front, ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_FRONT_FREE"] == nil { demo.append(Rule(bundleID: front.0, appName: front.1, trigger: .inFront, action: .paused)) }
            model.rules.showPreviewRules(demo)
        }
        // MAUNA_SNAPSHOT_PLAN=free|trial|pro renders on that plan.
        switch ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_PLAN"] {
        case "free": model.store.preview(.free)
        case "trial": model.store.preview(.trial(endsAt: .now.addingTimeInterval(9 * 86_400 - 60)))
        case "pro": model.store.preview(.pro)
        default: break
        }
        // MAUNA_SNAPSHOT_FOLDED=games,watching folds those Rules sections.
        if let folded = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_FOLDED"] {
            UserDefaults.standard.set(folded, forKey: "foldedRuleSections")
        }
        if let tab = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_TAB"] {
            UserDefaults.standard.set(tab, forKey: SettingsTab.storageKey)
        }
        let suggestions = SuggestionsState()
        Task { await suggestions.load(existing: model.rules) }
        let which = ProcessInfo.processInfo.environment["MAUNA_SNAPSHOT_VIEW"] ?? "popover"
        let content: AnyView = switch which {
        case "players": AnyView(PlayersSettings(model: model))
        case "rules":   AnyView(RulesSettings(model: model))
        case "sound":   AnyView(SoundSettings(model: model))
        case "general": AnyView(GeneralSettings(model: model))
        case "settings": AnyView(SettingsView(model: model))   // MAUNA_SNAPSHOT_TAB picks the tab
        case "states":  AnyView(StatesSheet())
        case "upgrade": AnyView(UpgradeView(model: model, feature: nil) {})
        case "upgrade-yt": AnyView(UpgradeView(model: model, feature: .youTubeMusic) {})
        case "upgrade-onboarding": AnyView(UpgradeView(model: model, feature: nil, afterOnboarding: true) {})
        case "glyphs":  AnyView(GlyphStudySheet())
        case "icons":   AnyView(IconStudySheet())
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
