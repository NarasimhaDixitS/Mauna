import AppKit
import Observation

/// Owns one music player: what it's doing, and what Mauna has done to it.
/// The rule coordinator calls `setRuleHold(_:)`; you (debug buttons, quiet shortcut) call `quiet(_:)` and `release()`.
/// The music gets the stronger of the two, so a rule ending never undoes a pause you made.
///
/// Rules it keeps (spec › Edge cases):
/// - Never resume what the user paused: Mauna only quiets music that is playing, and only resumes what it quieted.
/// - Fades start from the volume playing now and always end at the saved normal volume.
/// - The user pressed play during a pause: let it play, and tell the rules (`onUserOverride`).
/// - Player quit while quieted: don't relaunch it, just clear the hold.
@Observable
final class PlayerSession {
    enum QuietMode { case pause, duck }

    enum Issue: Equatable {
        /// Automation permission is off for this player.
        case needsPermission(PlayerID)
        case failed(String)
    }

    // MARK: State the UI reads

    private(set) var player: PlayerID
    private(set) var isRunning = false
    private(set) var playback: PlaybackState?
    /// Last volume read from or sent to the player, 0…1.
    private(set) var volume: Double?
    /// What Mauna is currently doing to the music.
    private(set) var hold: Hold = .none
    /// What the rules want.
    private(set) var ruleHold: Hold = .none
    /// What you asked for. Only you clear it.
    private(set) var manualHold: Hold = .none
    private(set) var isFading = false
    private(set) var issue: Issue?

    /// The volume music plays at the rest of the time. Fades return here.
    var normalVolume: Double = AudioTiming.normalVolume
    /// Ducked volume as a share of the normal volume.
    var duckLevel: Double = AudioTiming.duckLevel

    /// Called when the user presses play while Mauna has the music paused.
    var onUserOverride: (() -> Void)?

    // MARK: Private

    private var controller: any PlayerController
    private var work: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(player: PlayerID? = nil) {
        let chosen = player ?? PlayerID.installed.first(where: \.isRunning) ?? PlayerID.installed.first ?? .appleMusic
        self.player = chosen
        self.controller = ScriptablePlayer(player: chosen)
        observe()
        refresh()
    }

    func select(_ player: PlayerID) {
        guard player != self.player else { return }
        manualHold = .none
        apply(.none, animated: false)
        self.player = player
        controller = ScriptablePlayer(player: player)
        playback = nil
        volume = nil
        issue = nil
        refresh()
        resolve()   // rules still in charge apply to the new player
    }

    // MARK: Actions

    /// The rule engine's decision changed.
    func setRuleHold(_ target: Hold) {
        ruleHold = target
        resolve()
    }

    /// Manual quiet (debug buttons, quiet shortcut). Pause outranks duck: lowering paused music does nothing.
    func quiet(_ mode: QuietMode) {
        let target: Hold = mode == .pause ? .paused : .ducked
        guard target > hold else { return }
        manualHold = target
        resolve()
    }

    /// You want the music back: resume and fade in, or fade back up from the duck level.
    /// Rules in charge step aside until their trigger ends, as if you pressed play.
    func release(animated: Bool = true) {
        manualHold = .none
        if ruleHold != .none { onUserOverride?() }   // the coordinator answers with setRuleHold(.none)
        resolve(animated: animated)
    }

    /// Undo only your own quiet (the shortcut's second press). Rules still in charge keep the music
    /// where they want it: if TextEdit paused it, it stays paused.
    func releaseManual() {
        guard manualHold != .none else { return }
        manualHold = .none
        resolve()
    }

    private func resolve(animated: Bool = true) {
        apply(max(manualHold, ruleHold), animated: animated)
    }

    /// Move the music to `target` from whatever Mauna is doing now.
    /// - none → paused or ducked: only if music is playing. Never touch music the user stopped.
    /// - ducked → paused: fade the rest of the way and pause on top.
    /// - paused → ducked: resume and fade in to the duck level.
    /// - anything → none: resume, or fade back up, to the normal volume.
    private func apply(_ target: Hold, animated: Bool = true) {
        guard target != hold else { return }
        let previousHold = hold
        hold = target   // set now, so a change that arrives mid-fade starts from here
        enqueue { session, controller in
            let state = try await controller.state()
            if target != .none, previousHold == .none, state != .playing {
                session.playback = state
                session.hold = .none
                session.manualHold = .none   // nothing to quiet, so nothing for you to undo later
                return
            }
            switch target {
            case .paused:
                try await session.fadeOutAndPause(controller, state: state)
            case .ducked:
                try await session.duck(controller, state: state, from: previousHold)
            case .none:
                try await session.restore(controller, state: state, from: previousHold, animated: animated)
            }
        }
    }

    private func fadeOutAndPause(_ controller: any PlayerController, state: PlaybackState) async throws {
        guard state == .playing else { return }
        let start = try await controller.volume()
        try await fade(controller, from: start, to: 0, full: AudioTiming.fadeOut)
        try await controller.pause()
        // Leave the player at the normal volume, so pressing play by hand isn't silent.
        try await controller.setVolume(normalVolume)
        volume = normalVolume
        playback = .paused
    }

    private func duck(_ controller: any PlayerController, state: PlaybackState, from previousHold: Hold) async throws {
        let target = normalVolume * duckLevel
        switch (previousHold, state) {
        case (_, .playing):
            let start = try await controller.volume()
            try await fade(controller, from: start, to: target, full: AudioTiming.fadeOut)
        case (.paused, .paused):
            try await controller.setVolume(0)
            try await controller.play()
            playback = .playing
            try await fade(controller, from: 0, to: target, full: AudioTiming.fadeIn)
        default:
            break
        }
    }

    private func restore(_ controller: any PlayerController, state: PlaybackState, from previousHold: Hold, animated: Bool) async throws {
        switch (previousHold, state) {
        case (.paused, .paused):
            try await controller.setVolume(0)
            try await controller.play()
            playback = .playing
            if animated {
                try await fade(controller, from: 0, to: normalVolume, full: AudioTiming.fadeIn)
            } else {
                try await controller.setVolume(normalVolume)
            }
        case (_, .playing):
            // Mid fade-out, ducked, or the user already pressed play: fade up from where it is now.
            let start = try await controller.volume()
            try await fade(controller, from: start, to: normalVolume, full: AudioTiming.fadeIn)
        default:
            // Stopped, or the user paused it: leave playback alone, just restore the volume.
            try await controller.setVolume(normalVolume)
            volume = normalVolume
        }
    }

    /// Re-reads the player's state and volume.
    func refresh() {
        isRunning = player.isRunning
        guard isRunning else {
            playback = nil
            volume = nil
            return
        }
        // Runs beside any fade, never cancels it. Apple Events stay in order on the script queue.
        let controller = self.controller
        Task { [weak self] in
            do {
                let state = try await controller.state()
                let volume = try await controller.volume()
                guard let self, controller.player == self.player else { return }
                self.playback = state
                if !self.isFading { self.volume = volume }
            } catch ScriptError.notAuthorized {
                self?.issue = .needsPermission(controller.player)
            } catch {
                // Not running or slow to answer: the notifications will catch up.
            }
        }
    }

    /// Run one step after the previous one finishes. Quiet and release cancel what came before.
    private func enqueue(_ body: @escaping (PlayerSession, any PlayerController) async throws -> Void) {
        let previous = work
        previous?.cancel()
        let controller = self.controller
        work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await body(self, controller)
                if self.issue != nil { self.issue = nil }
            } catch is CancellationError {
                // A newer action took over. It starts from the volume playing now.
            } catch ScriptError.notAuthorized {
                self.issue = .needsPermission(controller.player)
                self.hold = .none
                self.manualHold = .none
            } catch ScriptError.notRunning {
                self.playerQuit()
            } catch {
                self.issue = .failed("\(controller.player.displayName) didn't respond")
            }
            self.isFading = false
        }
    }

    private func fade(_ controller: any PlayerController, from start: Double, to target: Double, full: TimeInterval) async throws {
        isFading = true
        defer { isFading = false }
        let duration = VolumeFader.scaledDuration(full, from: start, to: target, reference: normalVolume)
        try await VolumeFader.fade(controller, from: start, to: target, duration: duration) { [weak self] value in
            self?.volume = value
        }
    }

    // MARK: Observing the player

    private func playerQuit() {
        isRunning = false
        playback = nil
        volume = nil
        hold = .none
        manualHold = .none
    }

    private func observe() {
        let distributed = DistributedNotificationCenter.default()
        for id in PlayerID.allCases {
            observers.append(distributed.addObserver(forName: id.playbackNotification, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated {
                    guard let self, self.player == id, let raw, let state = PlaybackState(scriptValue: raw) else { return }
                    self.isRunning = true
                    // Mauna finished pausing, and now it plays: the user pressed play. Respect it.
                    if self.hold == .paused, self.playback == .paused, state == .playing, !self.isFading {
                        self.hold = .none
                        self.manualHold = .none
                        self.onUserOverride?()
                    }
                    self.playback = state
                }
            })
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    guard let self, bundleID == self.player.bundleID else { return }
                    if launched {
                        self.refresh()
                    } else {
                        self.work?.cancel()
                        self.playerQuit()
                    }
                }
            })
        }
    }
}
