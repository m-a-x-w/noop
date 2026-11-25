import SwiftUI

// MARK: - V2 data-viz scales
//
// The v2 chart/gauge colour scales. These PORT the DARK values of the v1 Titanium data
// ramps (`StrandPalette.recoveryStops` / `strainStops` / `hrZones` / `sleepStageColor` /
// `stressGradient`, in their default `.titanium` chart style) and re-expose them slightly
// desaturated so highly-saturated ramps read cleanly on the v2 near-black surfaces
// (#0A0A0C … #232328) rather than vibrating against them.
//
// "Desaturated ~10%" here means each colour is mixed 10% of the way toward a grey of its
// own Rec.709 luminance — i.e. chroma is reduced ~10% while perceived brightness is
// preserved. The maths is pure sRGB (via the in-module `Color.sRGBComponents(hex:)`
// parser), so it is fully deterministic and compiles identically on iOS / macOS / watchOS
// with no UIKit / AppKit colour bridging.
//
// Sampling reuses the in-module `StrandPalette.sample(stops:at:)` so interpolation matches
// v1 exactly. `SleepStage` is the SAME type v1 `sleepStageColor(_:)` uses — it lives in
// this module (Palette.swift), so it is referenced directly with no import.

public enum V2ChartScale {

    // MARK: Desaturation helper

    /// Mix `hex` `amount` of the way toward a grey of its own luminance (chroma −`amount`,
    /// luminance preserved). Pure sRGB math — no platform colour bridging.
    private static func desaturated(_ hex: String, by amount: Double = 0.10) -> Color {
        let c = Color.sRGBComponents(hex: hex)
        let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        func mix(_ v: Double) -> Double { v + (lum - v) * amount }
        return Color(.sRGB, red: mix(c.r), green: mix(c.g), blue: mix(c.b), opacity: c.a)
    }

    // MARK: Recovery / Charge — red → green band (WHOOP-like)

    /// Dark Titanium recovery ramp (red → red-orange → yellow → yellow-green → green),
    /// desaturated ~10%.
    static let recoveryStops: [Gradient.Stop] = [
        .init(color: desaturated("#E0463C"), location: 0.00),
        .init(color: desaturated("#E8743C"), location: 0.30),
        .init(color: desaturated("#F9DF4A"), location: 0.55),
        .init(color: desaturated("#8FD86A"), location: 0.78),
        .init(color: desaturated("#03E095"), location: 1.00),
    ]

    /// Recovery colour for a 0…100 score (out-of-range clamped).
    public static func recovery(_ score: Int) -> Color {
        StrandPalette.sample(stops: recoveryStops, at: Double(score) / 100.0)
    }

    // MARK: Strain / Effort — ember → amber ramp

    /// Dark Titanium Effort ramp (deep ember → warm/bright amber → soft amber peak),
    /// desaturated ~10%.
    static let strainStops: [Gradient.Stop] = [
        .init(color: desaturated("#9C5A14"), location: 0.00),
        .init(color: desaturated("#C2762A"), location: 0.33),
        .init(color: desaturated("#D98A3D"), location: 0.66),
        .init(color: desaturated("#F0A85A"), location: 1.00),
    ]

    /// Strain colour for `v` on NOOP's 0…100 Effort scale (matches v1
    /// `StrandPalette.strainColor(_:)`; out-of-range clamped).
    public static func strain(_ v: Double) -> Color {
        StrandPalette.sample(stops: strainStops, at: v / 100.0)
    }

    // MARK: HR zones — 5 zones, low → high

    /// Dark Titanium HR zones (blue → cyan → gold → amber → orange-red), low → high,
    /// desaturated ~10%. Indexed 0…4 (zone 1 … zone 5).
    public static let hrZones: [Color] = [
        desaturated("#4A90E2"),
        desaturated("#3FA9C9"),
        desaturated("#E8B84B"),
        desaturated("#D98A3D"),
        desaturated("#E0662F"),
    ]

    // MARK: Sleep stages

    /// Dark Titanium sleep-stage colour, desaturated ~10%. Uses the same `SleepStage`
    /// type as v1 `StrandPalette.sleepStageColor(_:)` (defined in this module).
    public static func sleepStage(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return desaturated("#C2CCDA")
        case .light: return desaturated("#4A90E2")
        case .deep:  return desaturated("#2F6FCB")
        case .rem:   return desaturated("#6FA8E8")
        }
    }

    // MARK: Stress — calm → balanced → high (mirrors v1 `stressGradient`)

    /// Dark Titanium stress ramp (calm green → balanced yellow → high red), desaturated ~10%.
    public static let stressStops: [Gradient.Stop] = [
        .init(color: desaturated("#46B45A"), location: 0.0),
        .init(color: desaturated("#F2C53D"), location: 0.5),
        .init(color: desaturated("#E5483B"), location: 1.0),
    ]

    /// Stress colour for a 0…1 fraction (out-of-range clamped).
    public static func stress(_ fraction: Double) -> Color {
        StrandPalette.sample(stops: stressStops, at: fraction)
    }
}
