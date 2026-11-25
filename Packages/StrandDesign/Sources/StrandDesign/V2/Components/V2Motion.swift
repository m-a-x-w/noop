import SwiftUI

// MARK: - V2Motion — the one motion system for v2
//
// A tiny, opinionated set of animation curves used across every v2 component so motion
// reads as a single system: `snap` for direct-manipulation state flips (segmented control,
// toggles), `settle` for value/content changes (a stat re-scoring), and `calm` for the slow,
// premium reveal (hero count-up, sheet content). Nothing here depends on v1 `NoopMotion`.
//
// Reduce-Motion is honoured by call sites through `resolve(_:reduceMotion:)`, which returns
// `nil` (no animation) when the user has asked for reduced motion — pass the result straight
// into `.animation(_:value:)`, or `?? .default` into `withAnimation`.
public enum V2Motion {

    /// Direct-manipulation flips — a springy, low-latency response for taps that move UI now.
    public static let snap: Animation = .interactiveSpring(response: 0.28,
                                                           dampingFraction: 0.86,
                                                           blendDuration: 0.10)

    /// Value / content changes — a gentle spring that settles without overshoot ringing.
    public static let settle: Animation = .spring(response: 0.35,
                                                  dampingFraction: 0.90,
                                                  blendDuration: 0)

    /// Premium reveals — a slow ease-out (the classic 0.22,1,0.36,1 curve) for hero count-ups.
    public static let calm: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    /// Collapse any curve to "no animation" when Reduce Motion is on. Returns an optional so it
    /// drops straight into `.animation(_:value:)` (nil = off); for `withAnimation`, use `?? .default`.
    public static func resolve(_ a: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : a
    }
}
