import SwiftUI

// MARK: - V2Density — compact vs detailed layout mode
//
// A single environment-driven knob that lets a screen render its cards in a tighter `compact`
// form (fewer secondary stats, smaller hero) or the default `detailed` form. Components read
// `@Environment(\.v2Density)` and adapt; the default is `.detailed` so nothing has to opt in.

public enum V2Density: String, Sendable {
    case compact
    case detailed
}

private struct V2DensityKey: EnvironmentKey {
    static let defaultValue: V2Density = .detailed
}

public extension EnvironmentValues {
    /// The current v2 layout density. Defaults to `.detailed`.
    var v2Density: V2Density {
        get { self[V2DensityKey.self] }
        set { self[V2DensityKey.self] = newValue }
    }
}

public extension View {
    /// Set the v2 layout density for this subtree.
    func v2Density(_ density: V2Density) -> some View {
        environment(\.v2Density, density)
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(spacing: V2.Space.lg) {
            V2Card {
                Text("DETAILED (default)")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
            }
            V2Card {
                Text("COMPACT")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
            }
            .v2Density(.compact)
        }
        .padding(V2.Space.gutter)
    }
}
#endif
