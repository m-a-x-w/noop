import SwiftUI

// MARK: - V2Card / V2Surface — the one card system for v2
//
// Every boxed unit of the v2 UI is a `V2Card`: a `surface1` fill, a `Radius.card` corner, a
// single `hairline` stroke, and `Space.lg` internal padding. Passing a `domain` adds the ONLY
// per-card colour: a 2pt accent tick capsule on the leading edge (everything else stays
// neutral). `V2Surface` is the same shell with NO padding, for full-bleed content (charts,
// maps, media) that needs to reach the card edge itself.

/// A padded card: `surface1` fill, hairline stroke, `Radius.card` corner, `Space.lg` padding.
/// An optional `domain` paints a 2pt accent tick on the leading edge — the only per-card colour.
public struct V2Card<Content: View>: View {
    private let domain: V2Domain?
    private let content: Content

    public init(domain: V2Domain? = nil, @ViewBuilder content: () -> Content) {
        self.domain = domain
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: V2.Radius.card, style: .continuous)
    }

    public var body: some View {
        content
            .padding(V2.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    V2.Color.surface1
                    if let domain {
                        Capsule()
                            .fill(domain.accent)
                            .frame(width: 2)
                            .padding(.vertical, V2.Space.md)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
    }
}

/// A full-bleed surface: identical shell to `V2Card` (fill, corner, hairline) but with NO
/// padding, so content (charts, media) reaches the rounded edge. Optional leading `domain` tick.
public struct V2Surface<Content: View>: View {
    private let domain: V2Domain?
    private let content: Content

    public init(domain: V2Domain? = nil, @ViewBuilder content: () -> Content) {
        self.domain = domain
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: V2.Radius.card, style: .continuous)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    V2.Color.surface1
                    if let domain {
                        Capsule()
                            .fill(domain.accent)
                            .frame(width: 2)
                            .padding(.vertical, V2.Space.md)
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(spacing: V2.Space.lg) {
            V2Card {
                Text("Neutral card")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
            }
            V2Card(domain: .rest) {
                VStack(alignment: .leading, spacing: V2.Space.xs) {
                    Text("Domain card")
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textPrimary)
                    Text("2pt accent tick, leading edge")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            }
            V2Surface(domain: .effort) {
                Rectangle()
                    .fill(V2Domain.effort.trace)
                    .frame(height: 60)
                    .overlay(Text("Full-bleed V2Surface")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary))
            }
        }
        .padding(V2.Space.gutter)
    }
}
#endif
