import Foundation

/// Equal-power volume fades. The audio fade is Mauna's real animation (DESIGN.md › Audio).
/// - Fades always start from the volume playing now, so an interrupted fade continues without a jump.
/// - Duration scales with the distance left, so a half-finished fade-out reverses in half the time.
enum VolumeFader {
    static let tick: Duration = .milliseconds(40)

    /// Volume at progress `t` (0…1) between `start` and `target`.
    /// Fading down follows cos(t·π/2); fading up follows sin(t·π/2).
    nonisolated static func value(at t: Double, from start: Double, to target: Double) -> Double {
        let t = min(max(t, 0), 1)
        if target < start {
            return target + (start - target) * AudioTiming.fadeOutGain(t)
        } else {
            return start + (target - start) * AudioTiming.fadeInGain(t)
        }
    }

    /// Duration for a fade from `start` to `target`, given the full-range duration to `reference`.
    nonisolated static func scaledDuration(_ full: TimeInterval, from start: Double, to target: Double, reference: Double) -> TimeInterval {
        guard reference > 0 else { return full }
        let fraction = min(abs(target - start) / reference, 1)
        return max(full * fraction, 0.15)
    }

    /// Fades `controller` from `start` to `target` over `duration`. Throws `CancellationError` if cancelled.
    /// `onStep` reports each volume sent, for the UI.
    static func fade(
        _ controller: some PlayerController,
        from start: Double,
        to target: Double,
        duration: TimeInterval,
        onStep: (Double) -> Void = { _ in }
    ) async throws {
        guard abs(target - start) > 0.005, duration > 0 else {
            try await controller.setVolume(target)
            onStep(target)
            return
        }

        let clock = ContinuousClock()
        let began = clock.now
        var lastPercent = Int((start * 100).rounded())

        while true {
            try Task.checkCancellation()
            let elapsed = began.duration(to: clock.now)
            let t = min(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, duration) / duration
            let volume = value(at: t, from: start, to: target)

            // Players take whole percents; skip steps that wouldn't change anything.
            let percent = Int((volume * 100).rounded())
            if percent != lastPercent || t >= 1 {
                do {
                    try await controller.setVolume(volume)
                    lastPercent = percent
                    onStep(volume)
                } catch ScriptError.timedOut where t < 1 {
                    // The player stalled on one step. Keep going: the next step jumps to where the fade is now.
                }
            }
            if t >= 1 { return }
            try await Task.sleep(for: tick)
        }
    }
}
