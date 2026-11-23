import Observation

/// App-wide state the UI reads. Grows into the rule engine's output in Phase 2.
@Observable
final class AppModel {
    /// What the user hears right now. Drives the menu bar glyph and the popover glyph.
    var glyphState: GlyphState = .playing
}
