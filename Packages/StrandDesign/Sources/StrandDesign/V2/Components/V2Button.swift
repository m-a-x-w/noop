import SwiftUI

// MARK: - V2Button — the one button-style family for v2
//
// Three capsule variants, applied to any `Button` via the `.v2Primary()` / `.v2Secondary()` /
// `.v2Ghost()` view modifiers:
//   • primary   — neutral `accent` fill, dark `surface0` label (the single strong CTA)
//   • secondary — no fill, hairline outline, `textPrimary` label
//   • ghost     — no fill, no outline, `textSecondary` label (quiet/tertiary actions)
// Pressed state is a slight opacity + scale dip; disabled dims the whole control.

public struct V2ButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case primary, secondary, ghost }

    private let variant: Variant

    public init(_ variant: Variant) {
        self.variant = variant
    }

    public func makeBody(configuration: Configuration) -> some View {
        Content(variant: variant, configuration: configuration)
    }

    private struct Content: View {
        let variant: Variant
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        private var foreground: Color {
            switch variant {
            case .primary:   return V2.Color.surface0
            case .secondary: return V2.Color.textPrimary
            case .ghost:     return V2.Color.textSecondary
            }
        }

        var body: some View {
            configuration.label
                .font(V2Font.body)
                .foregroundStyle(foreground)
                .padding(.horizontal, V2.Space.lg)
                .padding(.vertical, V2.Space.md)
                .background {
                    switch variant {
                    case .primary:
                        Capsule().fill(V2.Color.accent)
                    case .secondary:
                        Capsule().strokeBorder(V2.Color.hairlineHeavy, lineWidth: V2.Stroke.rule)
                    case .ghost:
                        Color.clear
                    }
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

public extension View {
    /// Neutral accent-fill CTA with a dark label.
    func v2Primary() -> some View { buttonStyle(V2ButtonStyle(.primary)) }
    /// Hairline-outline button with a primary-ink label.
    func v2Secondary() -> some View { buttonStyle(V2ButtonStyle(.secondary)) }
    /// Chrome-free quiet button with a secondary-ink label.
    func v2Ghost() -> some View { buttonStyle(V2ButtonStyle(.ghost)) }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(spacing: V2.Space.md) {
            Button("Log workout") {}.v2Primary()
            Button("Edit") {}.v2Secondary()
            Button("Skip") {}.v2Ghost()
            Button("Disabled") {}.v2Primary().disabled(true)
        }
        .padding(V2.Space.gutter)
    }
}
#endif
