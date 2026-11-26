import AppKit

/// The music players Mauna can control in v1: two native apps, and YouTube Music in a browser tab.
nonisolated enum PlayerID: String, CaseIterable, Identifiable, Sendable, Codable {
    case spotify
    case appleMusic
    case youTubeMusicChrome
    case youTubeMusicSafari

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify:    "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        case .youTubeMusicChrome: "com.google.Chrome"
        case .youTubeMusicSafari: "com.apple.Safari"
        }
    }

    /// YouTube Music lives in a browser tab: no notifications, JavaScript instead of a scripting dictionary.
    var isBrowser: Bool { self == .youTubeMusicChrome || self == .youTubeMusicSafari }

    /// "Chrome", "Safari" for browser players.
    var browserName: String? {
        switch self {
        case .youTubeMusicChrome: "Chrome"
        case .youTubeMusicSafari: "Safari"
        case .spotify, .appleMusic: nil
        }
    }

    /// The app the player lives in, for rules: a native player itself never becomes a quiet app.
    static var nativeBundleIDs: Set<String> { [PlayerID.spotify.bundleID, PlayerID.appleMusic.bundleID] }

    var displayName: String {
        switch self {
        case .spotify:    "Spotify"
        case .appleMusic: "Apple Music"
        case .youTubeMusicChrome, .youTubeMusicSafari: "YouTube Music"
        }
    }

    /// "YouTube Music in Chrome", or just the name for native players.
    var fullName: String { browserName.map { "\(displayName) in \($0)" } ?? displayName }

    /// Posted by the player whenever playback changes. Free to observe: never launches the player.
    /// Browsers post nothing, so browser players are checked on a timer instead.
    var playbackNotification: Notification.Name? {
        switch self {
        case .spotify:    Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        case .youTubeMusicChrome, .youTubeMusicSafari: nil
        }
    }

    /// How steeply the player's volume slider maps to loudness (see `AudioTiming.duckVolume`).
    /// Spotify's slider is roughly cubic: 14 of 100 is close to silent.
    var volumeCurve: Double { self == .spotify ? 3 : 1 }

    /// The player's own controller.
    func makeController() -> any PlayerController {
        isBrowser ? BrowserPlayer(player: self) : ScriptablePlayer(player: self)
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    static var installed: [PlayerID] { allCases.filter(\.isInstalled) }
}

nonisolated enum PlaybackState: String, Sendable {
    case playing, paused, stopped

    /// Parses AppleScript's `player state as string` and the notifications' "Player State" value.
    init?(scriptValue: String) {
        switch scriptValue.lowercased() {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: return nil
        }
    }
}
