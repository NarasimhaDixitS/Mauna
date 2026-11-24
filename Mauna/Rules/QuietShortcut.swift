import Foundation

/// What one press of the quiet shortcut (⌃⌥Space) does. Pure, so tests can check every case.
///
/// Spec › Shortcut rules:
/// - Toggle: press once to quiet (pause or lower, the user's choice), press again to restore.
/// - Manual action wins: no rule may undo it. Only the shortcut brings it back.
/// - Rule already holds the music at least as strongly: do nothing, say "Still paused for Zoom".
/// - Rule only lowered it and the shortcut pauses: pause on top. Restoring returns to the rule's level.
/// - Nothing playing: do nothing, never start music (PlayerSession checks the player).
/// - Presses closer than 300 ms are ignored.
nonisolated enum QuietShortcut {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case pause, lower
        var id: Self { self }
        var hold: Hold { self == .pause ? .paused : .ducked }
        var title: String { self == .pause ? "Pause" : "Lower" }
    }

    enum Action: Equatable, Sendable {
        /// Quiet the music yourself.
        case quiet(Hold)
        /// Undo your own quiet. Rules still in charge keep their hold.
        case restore
        /// A rule already holds the music this much or more. Nothing to do.
        case stillHeld
    }

    static func action(mode: Mode, manual: Hold, rule: Hold) -> Action {
        if manual != .none { return .restore }
        if rule >= mode.hold { return .stillHeld }
        return .quiet(mode.hold)
    }

    /// Drops presses that come too soon after the last one (key bounce, nervous double taps).
    struct PressFilter: Sendable {
        var minimumGap: TimeInterval = AudioTiming.shortcutDoublePressIgnore
        private var lastAccepted: TimeInterval?

        init(minimumGap: TimeInterval = AudioTiming.shortcutDoublePressIgnore) {
            self.minimumGap = minimumGap
        }

        mutating func accept(at now: TimeInterval) -> Bool {
            if let lastAccepted, now - lastAccepted < minimumGap { return false }
            lastAccepted = now
            return true
        }
    }
}
