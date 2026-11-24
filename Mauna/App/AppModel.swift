import Observation

/// App-wide state the UI reads.
@Observable
final class AppModel {
    let session: PlayerSession
    let rules: RuleCoordinator

    init() {
        let session = PlayerSession()
        self.session = session
        self.rules = RuleCoordinator(session: session, rules: Rule.phase2Samples)
    }

    /// What the user hears right now. The glyph says what you hear; the text says why.
    var glyphState: GlyphState {
        switch session.hold {
        case .paused: return .paused
        case .ducked: return .ducked
        case .none:   return session.playback == .playing ? .playing : .paused
        }
    }

    /// Popover status line: the cause, never a bare state.
    var statusLine: String {
        let name = session.player.displayName
        switch session.hold {
        case .paused: return ruleCause.map { "Paused for \($0)" } ?? "Quieted by you"
        case .ducked: return ruleCause.map { "Lowered for \($0)" } ?? "Quieted by you"
        case .none:
            guard session.isRunning else { return "\(name) isn't open" }
            switch session.playback {
            case .playing: return "Playing on \(name)"
            case .paused:  return "\(name) is paused"
            case .stopped, nil: return "Nothing playing"
            }
        }
    }

    /// Status sub-line.
    var detailLine: String {
        if rules.isAway { return "Holding while you're away" }
        if rules.isWaiting { return "Waiting \(AudioTiming.debounce.formatted()) s" }
        let count = rules.rules.filter(\.isEnabled).count
        return count == 1 ? "Watching 1 app" : "Watching \(count) apps"
    }

    /// True while Mauna is acting on the music.
    var isActing: Bool { session.hold != .none }

    /// "Zoom", "Zoom + 1". Nil when you quieted it yourself (debug buttons, quiet shortcut).
    private var ruleCause: String? {
        let causes = rules.decision.causes
        guard let first = causes.first, session.ruleHold == session.hold, session.manualHold < session.hold else { return nil }
        return causes.count > 1 ? "\(first.appName) + \(causes.count - 1)" : first.appName
    }
}
