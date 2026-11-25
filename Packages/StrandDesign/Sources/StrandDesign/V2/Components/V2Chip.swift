import SwiftUI

// MARK: - V2Chip — the one status/trend pill for v2
//
// Replaces v1's separate `TrendChip` + `StatePill`. A capsule of tinted text: the tone colour
// as foreground over a very faint (14%) wash of the same colour. `.neutral` uses the secondary
// text ink so an untone-d chip stays quiet.

public enum V2Tone: Sendable {
    case neutral
    case positive
    case caution
    case negative

    var color: Color {
        switch self {
        case .neutral:  return V2.Color.textSecondary
        case .positive: return V2.Color.positive
        case .caution:  return V2.Color.caution
        case .negative: return V2.Color.negative
        }
    }
}

public struct V2Chip: View {
    private let text: String
    private let tone: V2Tone

    public init(_ text: String, tone: V2Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(V2Font.caption)
            .foregroundStyle(tone.color)
            .padding(.horizontal, V2.Space.sm)
            .padding(.vertical, V2.Space.xxs)
            .background(tone.color.opacity(0.14), in: Capsule())
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(spacing: V2.Space.md) {
            V2Chip("Balanced")
            V2Chip("Optimal", tone: .positive)
            V2Chip("Elevated", tone: .caution)
            V2Chip("Strained", tone: .negative)
        }
        .padding(V2.Space.gutter)
    }
}
#endif
