import Foundation

// Audio tokens from design/tokens.json › audio. Used by the fade engine (Phase 1) and rule engine (Phase 2).
// The audio fade is the real animation: equal-power curves, always starting from the volume playing now.

nonisolated enum AudioTiming {
    static let fadeOut: TimeInterval = 1.2
    static let fadeIn: TimeInterval = 1.8
    static let fadeRange: ClosedRange<TimeInterval> = 0...5
    static let fadeStep: TimeInterval = 0.1

    static let debounce: TimeInterval = 1.5
    static let shortcutDoublePressIgnore: TimeInterval = 0.3
    static let shortSoundIgnore: TimeInterval = 3

    static let normalVolume: Double = 0.70
    static let duckLevel: Double = 0.20
    static let autoRestoreOptions: [TimeInterval] = [60, 300, 900]

    /// The player volume that sounds like `level` of `resting`. `curve` is how steeply the player's
    /// own slider maps to loudness: 1 for a slider that already follows the ear (Apple Music, YouTube
    /// Music's gain stage), about 3 for Spotify, whose low numbers are far quieter than they look.
    static func duckVolume(resting: Double, level: Double, curve: Double) -> Double {
        resting * pow(min(max(level, 0), 1), 1 / max(curve, 1))
    }

    /// Equal-power fade-out gain at progress t ∈ 0…1.
    static func fadeOutGain(_ t: Double) -> Double { cos(min(max(t, 0), 1) * .pi / 2) }

    /// Equal-power fade-in gain at progress t ∈ 0…1.
    static func fadeInGain(_ t: Double) -> Double { sin(min(max(t, 0), 1) * .pi / 2) }
}
