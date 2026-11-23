import AppKit
import Observation

/// Owns one music player: what it's doing, and what Mauna has done to it.
/// The rule engine (Phase 2) and the quiet shortcut (Phase 3) call `quiet(_:)` and `release()`.
///
/// Rules it keeps (spec › Edge cases):
/// - Never resume what the user paused: Mauna only quiets music that is playing, and only resumes what it quieted.
/// - Fades start from the volume playing now and always end at the saved normal volume.
/// - Player quit while quieted: don't relaunch it, just clear the hold.
@Observable
final class PlayerSession {
    enum Hold: Equatable { case none, paused, ducked }
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
    private(set) var isFading = false
    private(set) var issue: Issue?

    /// The volume music plays at the rest of the time. Fades return here.
    var normalVolume: Double = AudioTiming.normalVolume
    /// Ducked volume as a share of the normal volume.
    var duckLevel: Double = AudioTiming.duckLevel

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
        release(animated: false)
        self.player = player
        controller = ScriptablePlayer(player: player)
        playback = nil
        volume = nil
        issue = nil
        refresh()
    }

    // MARK: Actions

    /// Fade out and pause, or fade down to the duck level. Does nothing if nothing is playing.
    /// Pause outranks duck: pausing lowered music pauses on top; lowering paused music does nothing.
    func quiet(_ mode: QuietMode) {
        let target: Hold = mode == .pause ? .paused : .ducked
        guard hold != target, hold != .paused else { return }
        let previousHold = hold
        hold = target   // set now, so a release that arrives mid-fade undoes it
        enqueue { session, controller in
            if previousHold == .none {
                // Never pause music the user already stopped.
                let state = try await controller.state()
                guard state == .playing else {
                    session.playback = state
                    session.hold = .none
                    return
                }
            }
            let start = try await controller.volume()
            switch target {
            case .paused:
                try await session.fade(controller, from: start, to: 0, full: AudioTiming.fadeOut)
                try await controller.pause()
                // Leave the player at the normal volume, so pressing play by hand isn't silent.
                try await controller.setVolume(session.normalVolume)
                session.volume = session.normalVolume
                session.playback = .paused
            case .ducked:
                try await session.fade(controller, from: start, to: session.normalVolume * session.duckLevel, full: AudioTiming.fadeOut)
            case .none:
                break
            }
        }
    }

    /// Undo whatever Mauna did: resume and fade in, or fade back up from the duck level.
    func release(animated: Bool = true) {
        guard hold != .none else { return }
        let previousHold = hold
        hold = .none
        enqueue { session, controller in
            let state = try await controller.state()
            switch (previousHold, state) {
            case (.paused, .paused):
                try await controller.setVolume(0)
                try await controller.play()
                session.playback = .playing
                if animated {
                    try await session.fade(controller, from: 0, to: session.normalVolume, full: AudioTiming.fadeIn)
                } else {
                    try await controller.setVolume(session.normalVolume)
                }
            case (_, .playing):
                // Mid fade-out, ducked, or the user already pressed play: fade up from where it is now.
                let start = try await controller.volume()
                try await session.fade(controller, from: start, to: session.normalVolume, full: AudioTiming.fadeIn)
            default:
                // Stopped, or the user changed something: leave playback alone, just restore the volume.
                try await controller.setVolume(session.normalVolume)
                session.volume = session.normalVolume
            }
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
    }

    private func observe() {
        let distributed = DistributedNotificationCenter.default()
        for id in PlayerID.allCases {
            observers.append(distributed.addObserver(forName: id.playbackNotification, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated {
                    guard let self, self.player == id, let raw, let state = PlaybackState(scriptValue: raw) else { return }
                    self.isRunning = true
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
