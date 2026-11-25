import SwiftUI

// MARK: - V2 design tokens
//
// The v2 UI rework (version 10) is a sleek, premium, dark-only redesign: near-black
// surfaces, big mono numerals, hairline dividers, restrained per-domain accents.
//
// These tokens are PURELY ADDITIVE. v1 `StrandPalette` / `Typography` / `Components`
// stay frozen because macOS, the watch app and the widget extension consume them.
// Everything here is a plain `public static let` so call sites read naturally:
// `V2.Color.surface1`, `V2.Space.md`, `V2.Radius.card`, `V2.Stroke.hairline`.
//
// Colours are dark-only and built with the in-module `Color(hex:)` initializer (defined
// in Palette.swift) so there is a single hex parser across the whole package.

public enum V2 {

    /// Dark-only palette: near-black surfaces, high-contrast off-white text, translucent
    /// white hairlines, and a small set of semantic signals plus a neutral accent.
    public enum Color {

        // MARK: Surfaces — app canvas up through nested wells and sheets.
        /// App canvas (the deepest surface).
        public static let surface0 = SwiftUI.Color(hex: "#0A0A0C")
        /// Card fill, floating just above the canvas.
        public static let surface1 = SwiftUI.Color(hex: "#121214")
        /// Nested content / input field fill.
        public static let surface2 = SwiftUI.Color(hex: "#1A1A1E")
        /// Sheet / pressed-state fill.
        public static let surface3 = SwiftUI.Color(hex: "#232328")
        /// Dimming scrim behind modals / sheets.
        public static let scrim = SwiftUI.Color.black.opacity(0.6)

        // MARK: Text — high-contrast off-white down to disabled ink.
        public static let textPrimary = SwiftUI.Color(hex: "#F2F2F0")
        public static let textSecondary = SwiftUI.Color(hex: "#9C9CA3")
        public static let textTertiary = SwiftUI.Color(hex: "#5C5C63")
        public static let textDisabled = SwiftUI.Color(hex: "#3A3A40")

        // MARK: Hairlines — translucent white rules over dark surfaces.
        public static let hairline = SwiftUI.Color.white.opacity(0.08)
        public static let hairlineHeavy = SwiftUI.Color.white.opacity(0.14)

        // MARK: Semantic signals + neutral accent.
        public static let positive = SwiftUI.Color(hex: "#4ADE80")
        public static let caution = SwiftUI.Color(hex: "#FBBF24")
        public static let negative = SwiftUI.Color(hex: "#F87171")
        /// Neutral near-white accent (buttons, focus, active chrome).
        public static let accent = SwiftUI.Color(hex: "#E8E8E4")
    }

    /// Spacing scale, in points.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        /// Standard screen-edge gutter.
        public static let gutter: CGFloat = 20
    }

    /// Corner radii, in points.
    public enum Radius {
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 14
        public static let card: CGFloat = 16
        public static let lg: CGFloat = 20
        /// Effectively a capsule / pill corner.
        public static let capsule: CGFloat = 999
    }

    /// Stroke widths, in points.
    public enum Stroke {
        /// Sub-pixel hairline rule.
        public static let hairline: CGFloat = 0.5
        /// Standard 1pt rule.
        public static let rule: CGFloat = 1
    }
}
