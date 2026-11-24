import Foundation
import KeyboardShortcuts
import Observation

/// App-wide state the UI reads.
@Observable
final class AppModel {
    let session: PlayerSession
    let rules: RuleCoordinator

    /// A short message that replaces the status line for a few seconds, like "Still paused for Zoom".
    private(set) var notice: String?

    @ObservationIgnored private var presses = QuietShortcut.PressFilter()
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?

    init() {
        let session = PlayerSession()
        self.session = session
        self.rules = RuleCoordinator(session: session, rules: Rule.phase2Samples)
        KeyboardShortcuts.onKeyDown(for: .quietMusic) { [weak self] in self?.quietPressed() }
    }

    // MARK: Quiet shortcut

    /// ⌃⌥Space, or Quiet now in the popover. Toggle: quiet, then restore.
    func quietPressed() {
        guard presses.accept(at: ProcessInfo.processInfo.systemUptime) else { return }
        let mode = QuietShortcut.Mode.saved
        switch QuietShortcut.action(mode: mode, manual: session.manualHold, rule: session.ruleHold) {
        case .quiet(let hold):
            session.quiet(hold == .paused ? .pause : .duck)
        case .restore:
            session.releaseManual()
            // A rule still holds the music: say so, so the press never feels ignored.
            if session.ruleHold != .none { showStillHeld() }
        case .stillHeld:
            showStillHeld()
        }
    }

    private func showStillHeld() {
        guard let cause = ruleCauseName else { return }
        let verb = session.ruleHold == .paused ? "paused" : "lowered"
        show(notice: "Still \(verb) for \(cause)")
    }

    private func show(notice text: String) {
        notice = text
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
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
        if let notice { return notice }
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
        guard session.ruleHold == session.hold, session.manualHold < session.hold else { return nil }
        return ruleCauseName
    }

    /// The rules in charge, whatever you did on top.
    private var ruleCauseName: String? {
        let causes = rules.decision.causes
        guard let first = causes.first else { return nil }
        return causes.count > 1 ? "\(first.appName) + \(causes.count - 1)" : first.appName
    }
}
