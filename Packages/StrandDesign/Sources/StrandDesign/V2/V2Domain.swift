import SwiftUI

// MARK: - V2 domains
//
// The five score domains of the v2 UI. Each owns a single dark-only accent used for its
// gauge stroke, sparkline/trace and card tint. `dim` and `trace` are pre-faded variants
// (28% / 12%) for secondary strokes and fills sitting behind data on near-black surfaces.

public enum V2Domain: String, CaseIterable, Sendable {
    case charge
    case effort
    case rest
    case stress
    case health

    /// Full-strength domain accent (dark-only).
    public var accent: Color {
        switch self {
        case .charge: return Color(hex: "#34D399") // green
        case .effort: return Color(hex: "#60A5FA") // blue
        case .rest:   return Color(hex: "#A78BFA") // violet
        case .stress: return Color(hex: "#FBBF24") // amber
        case .health: return Color(hex: "#F472B6") // pink
        }
    }

    /// 28%-opacity accent for secondary strokes / dim states.
    public var dim: Color { accent.opacity(0.28) }

    /// 12%-opacity accent for fills / traces behind data.
    public var trace: Color { accent.opacity(0.12) }
}
