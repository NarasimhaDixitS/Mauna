import AppKit

/// The music players Mauna can control in v1. YouTube Music joins in Phase 5.
nonisolated enum PlayerID: String, CaseIterable, Identifiable, Sendable, Codable {
    case spotify
    case appleMusic

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify:    "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify:    "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    /// Posted by the player whenever playback changes. Free to observe: never launches the player.
    var playbackNotification: Notification.Name {
        switch self {
        case .spotify:    Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
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
