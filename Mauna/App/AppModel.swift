import Observation

/// App-wide state the UI reads. Grows into the rule engine's output in Phase 2.
@Observable
final class AppModel {
    let session = PlayerSession()

    /// What the user hears right now. The glyph says what you hear; the text says why.
    var glyphState: GlyphState {
        switch session.hold {
        case .paused: return .paused
        case .ducked: return .ducked
        case .none:   return session.playback == .playing ? .playing : .paused
        }
    }

    /// Popover status line.
    var statusLine: String {
        let name = session.player.displayName
        switch session.hold {
        case .paused: return "Paused by Mauna"
        case .ducked: return "Lowered by Mauna"
        case .none:
            guard session.isRunning else { return "\(name) isn't open" }
            switch session.playback {
            case .playing: return "Playing on \(name)"
            case .paused:  return "\(name) is paused"
            case .stopped, nil: return "Nothing playing"
            }
        }
    }

    /// True while Mauna is acting on the music.
    var isActing: Bool { session.hold != .none }
}
