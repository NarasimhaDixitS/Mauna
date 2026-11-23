import Foundation

/// Exact control over one music player. Volume is 0…1, the player's own volume, never the Mac's.
nonisolated protocol PlayerController: Sendable {
    var player: PlayerID { get }
    func state() async throws -> PlaybackState
    func volume() async throws -> Double
    func setVolume(_ volume: Double) async throws
    func play() async throws
    func pause() async throws
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
