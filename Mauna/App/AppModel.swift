import AppKit
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
        self.rules = RuleCoordinator(session: session)
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

    /// True while your own quiet is in charge: Quiet now becomes "Bring music back".
    var isQuietedByYou: Bool { session.manualHold != .none }

    /// Nothing to quiet and nothing to bring back: Quiet now is disabled. It never starts music.
    var canQuiet: Bool { isQuietedByYou || (session.isRunning && session.playback == .playing) }

    /// "⌃⌥Space", or nil if the user cleared the shortcut.
    var shortcutText: String? { KeyboardShortcuts.Name.quietMusic.shortcut?.description }

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

    // MARK: Status

    /// What the user hears right now. The glyph says what you hear; the text says why.
    var glyphState: GlyphState {
        switch session.hold {
        case .paused: return .paused
        case .ducked: return .ducked
        case .none:
            if !rules.isEnabled { return .off }
            return session.playback == .playing ? .playing : .paused
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
            if !rules.isEnabled { return "Mauna is off" }
            guard session.isRunning else { return "\(name) isn't open" }
            switch session.playback {
            case .playing: return "Playing on \(name)"
            case .paused:  return "\(name) is paused"
            case .stopped, nil: return "Nothing playing"
            }
        }
    }

    /// Status sub-line: what happens next.
    var detailLine: String {
        if rules.isAway { return "Holding while you're away" }
        if session.hold != .none {
            if ruleCause == nil {
                return shortcutText.map { "Press \($0) to bring it back" } ?? "Press Quiet now to bring it back"
            }
            if let first = rules.decision.causes.first {
                let back = session.hold == .paused ? "Resumes" : "Back to normal"
                switch first.trigger {
                case .inFront: return "\(back) when you leave \(first.appName)"
                case .running: return "\(back) when \(first.appName) quits"
                case .usingMicOrSound: return "\(back) when the call ends"
                }
            }
        }
        if !rules.isEnabled { return "Rules are off. Quiet now still works." }
        let count = rules.allRules.filter(\.isEnabled).count
        switch count {
        case 0: return "No quiet apps yet"
        case 1: return "Watching 1 app"
        default: return "Watching \(count) apps"
        }
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

    // MARK: Quick rule

    struct FrontApp: Equatable {
        let bundleID: String
        let name: String
    }

    /// The app in front, when it has no rule yet: the popover offers "Pause until it quits".
    var quickRuleCandidate: FrontApp? {
        guard rules.isEnabled, let id = rules.frontmost, !rules.hasRule(for: id),
              !Self.neverQuiet.contains(id), !PlayerID.allCases.contains(where: { $0.bundleID == id })
        else { return nil }
        // Only real apps with a Dock icon, never background helpers.
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
              app.activationPolicy == .regular else { return nil }
        return FrontApp(bundleID: id, name: app.localizedName ?? id)
    }

    /// Apps that never quit, so "until it quits" would mean forever.
    private static let neverQuiet: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver"]
}
