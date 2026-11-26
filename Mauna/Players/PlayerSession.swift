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
        /// The browser blocks JavaScript from Apple Events (YouTube Music only). A one-time setting.
        case needsBrowserSetup(PlayerID)
        case failed(String)

        var needsSetup: Bool {
            switch self {
            case .needsPermission, .needsBrowserSetup: true
            case .failed: false
            }
        }
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
    var normalVolume: Double = PlayerSession.saved(Keys.normalVolume, AudioTiming.normalVolume) {
        didSet {
            UserDefaults.standard.set(normalVolume, forKey: Keys.normalVolume)
            applyNormalVolumeSoon()
        }
    }
    /// YouTube Music: Mauna's own level on top of the page's volume (its slider stays YouTube Music's).
    /// 1 = exactly as loud as YouTube Music is set. Music always comes back to this level.
    var browserLevel: Double = PlayerSession.saved(Keys.browserLevel, 1) {
        didSet {
            UserDefaults.standard.set(browserLevel, forKey: Keys.browserLevel)
            applyBrowserLevelSoon()
        }
    }
    /// Ducked volume as a share of the normal volume.
    var duckLevel: Double = PlayerSession.saved(Keys.duckLevel, AudioTiming.duckLevel) {
        didSet { UserDefaults.standard.set(duckLevel, forKey: Keys.duckLevel) }
    }
    /// Fade-out time. Fading back in takes 1.5× as long: a slower return feels kinder.
    var fadeTime: TimeInterval = PlayerSession.saved(Keys.fadeTime, AudioTiming.fadeOut) {
        didSet { UserDefaults.standard.set(fadeTime, forKey: Keys.fadeTime) }
    }
    /// Pro is unlocked (bought or on trial). Free: the standard fade, and YouTube Music rests.
    var unlocksPro = true {
        didSet {
            guard unlocksPro != oldValue, isLocked else { return }
            // The trial ended while Mauna held YouTube Music: hand it back.
            manualHold = .none
            apply(.none, animated: false)
        }
    }

    /// YouTube Music on Free: shown, but Mauna doesn't act on it.
    var isLocked: Bool { !unlocksPro && player.isBrowser }

    /// Custom fade time is Pro. Free fades at the standard 1.2 s.
    private var fadeOutTime: TimeInterval { unlocksPro ? fadeTime : AudioTiming.fadeOut }
    private var fadeInTime: TimeInterval { fadeOutTime * AudioTiming.fadeIn / AudioTiming.fadeOut }

    /// Called when the user presses play while Mauna has the music paused.
    var onUserOverride: (() -> Void)?

    // MARK: Private

    private var controller: any PlayerController
    private var work: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var volumeTask: Task<Void, Never>?
    private var poller: Task<Void, Never>?

    private enum Keys {
        static let normalVolume = "normalVolume"
        static let browserLevel = "browserLevel"
        static let duckLevel = "duckLevel"
        static let fadeTime = "fadeTime"
        static let player = "player"
    }

    private static func saved(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    init(player: PlayerID? = nil) {
        let savedPlayer = UserDefaults.standard.string(forKey: Keys.player).flatMap(PlayerID.init(rawValue:))
        let native = PlayerID.installed.filter { !$0.isBrowser }
        let chosen = player ?? savedPlayer ?? native.first(where: \.isRunning) ?? native.first ?? .appleMusic
        self.player = chosen
        self.controller = chosen.makeController()
        observe()
        refresh()
        startPolling()
    }

    /// Switch the player Mauna controls. The old one is let go, never restarted: if a rule paused it,
    /// it stays paused at its normal volume; if one lowered it, it goes back to normal. Then whatever is in
    /// charge (a rule, your quiet) applies to the new player at once.
    #if DEBUG
    /// Design renders: rules decide, but nothing is sent to the player.
    var dryRun = false

    /// Design renders: the player looks open and playing at this volume, whatever it really is.
    private var isStaged = false
    func stage(playback: PlaybackState, volume: Double) {
        dryRun = true
        isStaged = true
        isRunning = true
        self.playback = playback
        self.volume = volume
    }
    #endif

    func select(_ player: PlayerID) {
        guard player != self.player else { return }
        letGo()
        self.player = player
        UserDefaults.standard.set(player.rawValue, forKey: Keys.player)
        controller = player.makeController()
        playback = nil
        volume = nil
        issue = nil
        refresh()
        startPolling()
        resolve()   // rules still in charge apply to the new player
    }

    /// Hand the current player back untouched: its normal volume, no hold, playback left as it is.
    private func letGo() {
        let previousHold = hold
        hold = .none
        guard previousHold != .none else { return }
        // Its own task, not the work queue: the new player's first action would cancel it there.
        let previous = work
        previous?.cancel()
        let controller = self.controller
        Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let resting = await restingVolume(controller)
            try? await controller.setVolume(resting)
            try? await controller.releaseVolume()
        }
    }

    // MARK: Actions

    /// The play/pause button on the player card.
    /// - Mauna paused it: same as pressing play in the player. Music fades back in, and rules in charge
    ///   step aside until their trigger ends.
    /// - Playing (or lowered): pause. You paused it, so Mauna never starts it again when a rule ends.
    /// - Paused by you: play.
    func togglePlayback() {
        guard isRunning else { return }
        if hold == .paused {
            release()
            return
        }
        let pausing = playback == .playing
        playback = pausing ? .paused : .playing   // answer the click now; the player confirms shortly
        enqueue { _, controller in
            if pausing { try await controller.pause() } else { try await controller.play() }
        }
    }

    /// True when the play/pause button has something to act on.
    var canTogglePlayback: Bool {
        guard isRunning else { return false }
        if player.isBrowser, playback == .stopped, hold == .none { return false }   // no tab
        return true
    }

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
        if isLocked && target != .none { return }   // YouTube Music on Free
        #if DEBUG
        if dryRun { hold = target; return }
        #endif
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

    /// The level music rests at: the saved normal volume, or the player's own (YouTube Music's slider).
    private func restingVolume(_ controller: any PlayerController) async -> Double {
        let home = (try? await controller.homeVolume()) ?? normalVolume
        return controller.player.isBrowser ? home * browserLevel : home
    }

    private func fadeOutAndPause(_ controller: any PlayerController, state: PlaybackState) async throws {
        guard state == .playing else { return }
        let start = try await controller.volume()
        try await fade(controller, from: start, to: 0, full: fadeOutTime)
        try await controller.pause()
        // Leave the player at its resting volume, so pressing play by hand isn't silent.
        let resting = await restingVolume(controller)
        try await controller.setVolume(resting)
        try await settle(controller)
        volume = resting
        playback = .paused
    }

    private func duck(_ controller: any PlayerController, state: PlaybackState, from previousHold: Hold) async throws {
        let target = AudioTiming.duckVolume(resting: await restingVolume(controller), level: duckLevel, curve: player.volumeCurve)
        switch (previousHold, state) {
        case (_, .playing):
            let start = try await controller.volume()
            try await fade(controller, from: start, to: target, full: fadeOutTime)
        case (.paused, .paused):
            try await controller.setVolume(0)
            try await controller.play()
            playback = .playing
            try await fade(controller, from: 0, to: target, full: fadeInTime)
        default:
            break
        }
    }

    private func restore(_ controller: any PlayerController, state: PlaybackState, from previousHold: Hold, animated: Bool) async throws {
        let resting = await restingVolume(controller)
        switch (previousHold, state) {
        case (.paused, .paused):
            try await controller.setVolume(0)
            try await controller.play()
            playback = .playing
            if animated {
                try await fade(controller, from: 0, to: resting, full: fadeInTime)
            } else {
                try await controller.setVolume(resting)
            }
        case (_, .playing):
            // Mid fade-out, ducked, or the user already pressed play: fade up from where it is now.
            let start = try await controller.volume()
            try await fade(controller, from: start, to: resting, full: fadeInTime)
        default:
            // Stopped, or the user paused it: leave playback alone, just restore the volume.
            try await controller.setVolume(resting)
            volume = resting
        }
        // Back to normal: the player owns its volume again.
        try await settle(controller)
    }

    /// Done acting: hand the volume back. YouTube Music below 100% keeps Mauna's level in force (renewed
    /// by the 2 s check); at 100% the page simply owns its volume again.
    private func settle(_ controller: any PlayerController) async throws {
        if controller.player.isBrowser && browserLevel < 0.995 { return }
        try await controller.releaseVolume()
    }

    /// YouTube Music's level changed: apply it now unless Mauna is lowering or pausing.
    private func applyBrowserLevelSoon() {
        guard player.isBrowser else { return }
        volumeTask?.cancel()
        let controller = self.controller
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))   // let the slider settle
            guard let self, !Task.isCancelled else { return }
            await keepBrowserLevel(controller)
        }
    }

    /// Puts YouTube Music at Mauna's level while nothing is held. Safe to repeat: the 2 s check calls it,
    /// so the level survives the tab reloading.
    private func keepBrowserLevel(_ controller: any PlayerController) async {
        guard controller.player.isBrowser, controller.player == player, hold == .none, !isFading, !isLocked else { return }
        if browserLevel < 0.995 {
            try? await controller.setVolume(browserLevel)
        } else {
            try? await controller.setVolume(1)
            try? await controller.releaseVolume()
        }
        volume = browserLevel
    }

    /// The normal volume changed (Settings › Sound). If the music is playing untouched, move to it now.
    private func applyNormalVolumeSoon() {
        volumeTask?.cancel()
        let controller = self.controller
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))   // let the slider settle
            // YouTube Music keeps its own volume (its slider), so Mauna's normal volume doesn't apply there.
            guard let self, !Task.isCancelled, !player.isBrowser, hold == .none, !isFading, playback == .playing else { return }
            let target = normalVolume
            try? await controller.setVolume(target)
            volume = target
        }
    }

    /// Re-reads the player's state and volume.
    func refresh() {
        #if DEBUG
        if isStaged { return }
        #endif
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
                #if DEBUG
                if self.isStaged { return }
                #endif
                self.playback = state
                if !self.isFading { self.volume = volume }
                if self.issue?.needsSetup == true { self.issue = nil }
            } catch ScriptError.notAuthorized {
                self?.issue = .needsPermission(controller.player)
            } catch ScriptError.javaScriptOff {
                self?.issue = .needsBrowserSetup(controller.player)
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
            } catch ScriptError.javaScriptOff {
                self.issue = .needsBrowserSetup(controller.player)
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
        #if DEBUG
        if isStaged { return }
        #endif
        isRunning = false
        playback = nil
        volume = nil
        hold = .none
        manualHold = .none
    }

    /// A new playback state from the player (notification or browser check).
    private func received(_ state: PlaybackState) {
        #if DEBUG
        if isStaged { return }
        #endif
        // Mauna finished pausing, and now it plays: the user pressed play. Respect it.
        if hold == .paused, playback == .paused, state == .playing, !isFading {
            hold = .none
            manualHold = .none
            onUserOverride?()
        }
        playback = state
    }

    /// Browsers post no playback notifications, so YouTube Music is checked every 2 s while the browser runs.
    private func startPolling() {
        poller?.cancel()
        guard player.isBrowser else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                guard self.player.isRunning else { continue }
                let controller = self.controller
                // Below 100%, keep Mauna's level in force (also after the tab reloads).
                if self.browserLevel < 0.995 { await self.keepBrowserLevel(controller) }
                do {
                    let state = try await controller.state()
                    guard controller.player == self.player else { continue }
                    self.isRunning = true
                    self.received(state)
                    if self.issue?.needsSetup == true { self.issue = nil }
                } catch ScriptError.javaScriptOff {
                    self.issue = .needsBrowserSetup(controller.player)
                } catch ScriptError.notAuthorized {
                    self.issue = .needsPermission(controller.player)
                } catch {
                    // Slow or busy: try again next time.
                }
            }
        }
    }

    private func observe() {
        let distributed = DistributedNotificationCenter.default()
        for id in PlayerID.allCases {
            guard let name = id.playbackNotification else { continue }
            observers.append(distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated {
                    guard let self, self.player == id, let raw, let state = PlaybackState(scriptValue: raw) else { return }
                    self.isRunning = true
                    self.received(state)
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
