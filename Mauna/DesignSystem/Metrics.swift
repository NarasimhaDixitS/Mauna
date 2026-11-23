import CoreGraphics

// Spacing, radius and size tokens from design/tokens.json.

nonisolated enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Badges use Capsule(). The popover and app icon use the system shape.
nonisolated enum Radius {
    static let row: CGFloat = 9
    static let control: CGFloat = 8
    static let glyphTile: CGFloat = 10
    static let card: CGFloat = 16
}

nonisolated enum Size {
    static let popoverWidth: CGFloat = 320
    static let settingsWindowWidth: CGFloat = 560
    static let onboardingWindow = CGSize(width: 520, height: 460)
    static let menuBarGlyph: CGFloat = 18
    static let statusGlyphTile: CGFloat = 34
    static let rowAppIcon: CGFloat = 20
    static let rowHeight: CGFloat = 34
}
