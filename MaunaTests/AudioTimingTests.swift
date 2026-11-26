import Testing
import Foundation

struct AudioTimingTests {
    @Test func linearPlayerDucksToTheLevel() {
        #expect(abs(AudioTiming.duckVolume(resting: 0.7, level: 0.2, curve: 1) - 0.14) < 0.0001)
    }

    @Test func spotifyDucksHigherOnItsSlider() {
        // On a cubic slider, 20% loudness is about 58% of the resting slider position.
        let v = AudioTiming.duckVolume(resting: 0.7, level: 0.2, curve: 3)
        #expect(abs(v - 0.7 * 0.5848) < 0.001)
        // And it really is 20% of the loudness: (v / resting)^3.
        #expect(abs(pow(v / 0.7, 3) - 0.2) < 0.0001)
    }

    @Test func levelIsClamped() {
        #expect(AudioTiming.duckVolume(resting: 0.7, level: 1.5, curve: 3) == 0.7)
        #expect(AudioTiming.duckVolume(resting: 0.7, level: -1, curve: 3) == 0)
    }
}
