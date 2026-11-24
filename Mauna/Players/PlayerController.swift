import Foundation

/// Exact control over one music player. Volume is 0…1, the player's own volume, never the Mac's.
nonisolated protocol PlayerController: Sendable {
    var player: PlayerID { get }
    func state() async throws -> PlaybackState
    func volume() async throws -> Double
    func setVolume(_ volume: Double) async throws
    func play() async throws
    func pause() async throws
    /// The player's own resting volume, when it keeps one that Mauna doesn't own (YouTube Music's slider).
    func homeVolume() async throws -> Double?
    /// Stop holding the volume: the player may change it again.
    func releaseVolume() async throws
}

extension PlayerController {
    func homeVolume() async throws -> Double? { nil }
    func releaseVolume() async throws {}
}

/// Spotify and Apple Music share the same AppleScript vocabulary:
/// `player state`, `sound volume` (0–100), `play`, `pause`.
nonisolated struct ScriptablePlayer: PlayerController {
    let player: PlayerID

    func state() async throws -> PlaybackState {
        let value = try await tell("player state as string") ?? ""
        return PlaybackState(scriptValue: value) ?? .stopped
    }

    func volume() async throws -> Double {
        let value = try await tell("sound volume") ?? "0"
        return (Double(value) ?? 0) / 100
    }

    func setVolume(_ volume: Double) async throws {
        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        _ = try await tell("set sound volume to \(percent)")
    }

    func play() async throws { _ = try await tell("play") }
    func pause() async throws { _ = try await tell("pause") }

    /// Never sends anything to a player that isn't running: `tell` would launch it.
    private func tell(_ command: String) async throws -> String? {
        guard player.isRunning else { throw ScriptError.notRunning }
        return try await AppleScriptRunner.shared.run(
            "tell application id \"\(player.bundleID)\" to \(command)"
        )
    }
}

/// YouTube Music in a Chrome or Safari tab. AppleScript finds the first music.youtube.com tab and runs
/// JavaScript on the page's own `<video>` (spec: use the plain video element, not page buttons).
///
/// Volume: YouTube Music re-applies its own element volume on some events, so setting `video.volume`
/// turns into a tug of war you can hear. Instead Mauna routes the page's audio through a Web Audio gain
/// stage after the player: YouTube Music keeps its own volume (and slider), and Mauna's level multiplies it.
/// 1.0 means "as loud as YouTube Music is set". The stage is only wired once its AudioContext is running,
/// so audio can never go silent; until then the old element-volume path is the fallback.
///
/// A hold is a lease Mauna renews on every call (the 2 s check included). If Mauna quits mid-hold,
/// a page timer puts the level back to full within 6 s.
nonisolated struct BrowserPlayer: PlayerController {
    let player: PlayerID

    /// Runs before every call. Sets `v` (the video), `w` (window), `g` (gain node, if wired).
    private static let prelude = """
    const v=document.querySelector('video');const w=window;\
    if(!w.__maunaCtx){try{w.__maunaCtx=new AudioContext()}catch(e){}}\
    const c=w.__maunaCtx;if(c&&c.state==='suspended'){c.resume()}\
    if(v&&c&&c.state==='running'&&!v.__maunaGain){try{const s=c.createMediaElementSource(v);const n=c.createGain();\
    n.gain.value=w.__maunaHold!=null?w.__maunaHold:1;s.connect(n);n.connect(c.destination);v.__maunaGain=n}catch(e){}}\
    const g=v&&v.__maunaGain;\
    if(v&&!v.__maunaHook3){v.__maunaHook3=true;v.addEventListener('volumechange',()=>{const t=w.__maunaHold;\
    if(!v.__maunaGain&&t!=null&&(w.__maunaHoldUntil||0)>Date.now()&&Math.abs(v.volume-t)>0.005)v.volume=t})}\
    if(!w.__maunaTimer){w.__maunaTimer=setInterval(()=>{if(w.__maunaHold!=null&&(w.__maunaHoldUntil||0)<Date.now()){\
    w.__maunaHold=null;const x=document.querySelector('video');if(x&&x.__maunaGain)x.__maunaGain.gain.value=1}},1000)}\
    if(w.__maunaHold!=null)w.__maunaHoldUntil=Date.now()+6000
    """

    func state() async throws -> PlaybackState {
        let value = try await js("!v?'stopped':(v.paused?'paused':'playing')")
        return value.flatMap(PlaybackState.init(scriptValue:)) ?? .stopped
    }

    func volume() async throws -> Double {
        Double(try await js("g?g.gain.value:(v?v.volume:0)") ?? "0") ?? 0
    }

    func setVolume(_ volume: Double) async throws {
        let level = min(max(volume, 0), 1)
        // setTargetAtTime smooths each 40 ms step, so fades have no zipper noise.
        _ = try await js("(w.__maunaHold=\(level),w.__maunaHoldUntil=Date.now()+6000,g?g.gain.setTargetAtTime(\(level),c.currentTime,0.015):(v&&(v.volume=\(level))),'ok')")
    }

    func play() async throws { _ = try await js("(v&&v.play(),'ok')") }
    func pause() async throws { _ = try await js("(v&&v.pause(),'ok')") }

    /// With the gain stage, rest is 1.0 (YouTube Music's own level). Without it, YouTube Music's slider.
    func homeVolume() async throws -> Double? {
        let value = try await js("g?'1':(()=>{const s=document.querySelector('ytmusic-player-bar #volume-slider');const n=s&&s.getAttribute('aria-valuenow');return n==null?'':String(Number(n)/100)})()")
        return value.flatMap(Double.init)
    }

    func releaseVolume() async throws { _ = try await js("(w.__maunaHold=null,'ok')") }

    /// Debug: whether the gain stage is wired.
    func usesGainStage() async throws -> Bool { try await js("g?'yes':'no'") == "yes" }

    /// Runs `expression` (after the prelude) in the first YouTube Music tab. Returns nil if there's no such tab.
    /// Never sends anything to a browser that isn't running: `tell` would launch it.
    func js(_ expression: String) async throws -> String? {
        guard player.isRunning else { throw ScriptError.notRunning }
        let code = "(()=>{\(Self.prelude);return String(\(expression))})()"
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let run = player == .youTubeMusicSafari ? "do JavaScript \"\(escaped)\" in t" : "execute t javascript \"\(escaped)\""
        let result = try await AppleScriptRunner.shared.run("""
        tell application id "\(player.bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "music.youtube.com" then return (\(run)) as text
                end repeat
            end repeat
            return "no-tab"
        end tell
        """)
        return result == "no-tab" ? nil : result
    }
}
