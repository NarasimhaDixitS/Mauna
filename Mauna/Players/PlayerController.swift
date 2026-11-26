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

    /// Safari runs Apple Events JavaScript in the page's own world, where WebKit won't route streamed
    /// (MSE) audio through Web Audio, so the gain stage there does nothing. Instead Mauna wraps the video's
    /// `volume`: YouTube Music still reads and writes its own level (`__maunaWish`), and the element plays
    /// that level times Mauna's. Nothing changes under the page, so there is nothing to fight.
    /// Sets `v`, `w`, `L()` (Mauna's level, 1 when no lease) and `A()` (apply it now).
    private static let safariPrelude = """
    const v=document.querySelector('video');const w=window;\
    const d=Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype,'volume');\
    const L=()=>(w.__maunaHold!=null&&(w.__maunaHoldUntil||0)>Date.now())?w.__maunaHold:1;\
    const K=(x)=>{if(x&&!x.__maunaWrap){x.__maunaWrap=true;x.__maunaWish=d.get.call(x);\
    Object.defineProperty(x,'volume',{configurable:true,get(){return x.__maunaWish},\
    set(n){x.__maunaWish=n;d.set.call(x,Math.min(1,Math.max(0,n*L())))}})}};K(v);\
    const A=()=>{if(v)d.set.call(v,Math.min(1,Math.max(0,v.__maunaWish*L())))};\
    if(!w.__maunaSafariTimer){w.__maunaSafariTimer=setInterval(()=>{if(w.__maunaHold!=null&&(w.__maunaHoldUntil||0)<Date.now()){\
    w.__maunaHold=null;const x=document.querySelector('video');if(x&&x.__maunaWrap)d.set.call(x,x.__maunaWish)}},1000)}\
    if(w.__maunaHold!=null)w.__maunaHoldUntil=Date.now()+6000
    """

    private var isSafari: Bool { player == .youTubeMusicSafari }

    func state() async throws -> PlaybackState {
        let value = try await js("!v?'stopped':(v.paused?'paused':'playing')")
        return value.flatMap(PlaybackState.init(scriptValue:)) ?? .stopped
    }

    func volume() async throws -> Double {
        Double(try await js(isSafari ? "L()" : "g?g.gain.value:(v?v.volume:0)") ?? "0") ?? 0
    }

    func setVolume(_ volume: Double) async throws {
        let level = min(max(volume, 0), 1)
        let lease = "w.__maunaHold=\(level),w.__maunaHoldUntil=Date.now()+6000"
        // Chrome: setTargetAtTime smooths each 40 ms step, so fades have no zipper noise.
        _ = try await js(isSafari
            ? "(\(lease),A(),'ok')"
            : "(\(lease),g?g.gain.setTargetAtTime(\(level),c.currentTime,0.015):(v&&(v.volume=\(level))),'ok')")
    }

    // `__maunaPaused` marks the tab Mauna paused, so "bring it back" finds it among several.
    func play() async throws { _ = try await js("(w.__maunaPaused=false,v&&v.play(),'ok')") }
    func pause() async throws { _ = try await js("(w.__maunaPaused=true,v&&v.pause(),'ok')") }

    /// Rest is 1.0 (YouTube Music's own level) with the gain stage or Safari's wrap. Otherwise its slider.
    func homeVolume() async throws -> Double? {
        if isSafari { return 1 }
        let value = try await js("g?'1':(()=>{const s=document.querySelector('ytmusic-player-bar #volume-slider');const n=s&&s.getAttribute('aria-valuenow');return n==null?'':String(Number(n)/100)})()")
        return value.flatMap(Double.init)
    }

    func releaseVolume() async throws { _ = try await js(isSafari ? "(w.__maunaHold=null,A(),'ok')" : "(w.__maunaHold=null,'ok')") }

    /// Debug: whether the gain stage is wired.
    func usesGainStage() async throws -> Bool { isSafari ? false : try await js("g?'yes':'no'") == "yes" }

    /// Which tab to use when several YouTube Music tabs are open: the one playing (3), else the one Mauna
    /// paused (2), else any with a song loaded (1). An empty player (the home page) scores 0. Plain JavaScript, no prelude, so it never wires anything up.
    private static let tabScore = "(()=>{const v=document.querySelector('video');return String(!v||!v.currentSrc?0:(!v.paused?3:(window.__maunaPaused?2:1)))})()"

    /// Runs `expression` (after the prelude) in the YouTube Music tab you're listening to.
    /// One tab: that one. Several: the playing one, else the one Mauna paused, else the first.
    /// Returns nil if there's no such tab.
    /// Never sends anything to a browser that isn't running: `tell` would launch it.
    func js(_ expression: String) async throws -> String? {
        guard player.isRunning else { throw ScriptError.notRunning }
        let code = "(()=>{\(isSafari ? Self.safariPrelude : Self.prelude);return String(\(expression))})()"
        let result = try await AppleScriptRunner.shared.run("""
        tell application id "\(player.bundleID)"
            set found to {}
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "music.youtube.com" then set end of found to contents of t
                end repeat
            end repeat
            if (count of found) is 0 then return "no-tab"
            set best to item 1 of found
            if (count of found) > 1 then
                set bestScore to -1
                repeat with t in found
                    set s to (\(run(Self.tabScore, in: "t"))) as integer
                    if s > bestScore then
                        set bestScore to s
                        set best to contents of t
                    end if
                end repeat
            end if
            return (\(run(code, in: "best"))) as text
        end tell
        """)
        return result == "no-tab" ? nil : result
    }

    /// The browser's own "run this JavaScript in that tab" command.
    private func run(_ javaScript: String, in tab: String) -> String {
        let escaped = javaScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return isSafari ? "do JavaScript \"\(escaped)\" in \(tab)" : "execute \(tab) javascript \"\(escaped)\""
    }
}
