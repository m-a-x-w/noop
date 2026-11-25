import SwiftUI

// MARK: - V2Delta — a signed change chip (arrow + value)
//
// Rendered inside `V2StatRow` (or standalone) as a small arrow + value. Tone is automatic:
// up = positive, down = negative, flat = tertiary. (Direction is literal here — callers that
// need "down is good" semantics pass a chip with the tone they want via `V2Chip` instead.)
public struct V2Delta: Equatable, Sendable {
    public enum Direction: Sendable { case up, down, flat }

    public let value: String
    public let direction: Direction

    public init(value: String, direction: Direction) {
        self.value = value
        self.direction = direction
    }

    var tone: Color {
        switch direction {
        case .up:   return V2.Color.positive
        case .down: return V2.Color.negative
        case .flat: return V2.Color.textTertiary
        }
    }

    var symbol: String {
        switch direction {
        case .up:   return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "minus"
        }
    }

    /// The arrow + value pair used inside a row.
    @ViewBuilder var chip: some View {
        HStack(spacing: V2.Space.xxs) {
            Image(systemName: symbol)
                .font(V2Font.caption)
            Text(value)
                .font(V2Font.caption)
        }
        .foregroundStyle(tone)
    }
}

// MARK: - V2StatRow — one labelled metric in a card
//
// A single row: optional leading SF Symbol, a title on the left, and a value (+ optional unit,
// + optional `V2Delta`) on the right. When `action` is set the whole row becomes a plain
// Button with a subtle `surface2` pressed fill; otherwise it is inert content.

public struct V2StatRow: View {
    private let icon: String?
    private let title: String
    private let value: String
    private let unit: String?
    private let delta: V2Delta?
    private let action: (() -> Void)?

    public init(icon: String? = nil,
                title: String,
                value: String,
                unit: String? = nil,
                delta: V2Delta? = nil,
                action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.unit = unit
        self.delta = delta
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(V2PressableRowStyle())
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: V2.Space.md) {
            if let icon {
                Image(systemName: icon)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
                    .frame(width: 20, alignment: .center)
            }
            Text(title)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textPrimary)
            Spacer(minLength: V2.Space.sm)
            HStack(alignment: .firstTextBaseline, spacing: V2.Space.xs) {
                Text(value)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                }
                if let delta {
                    delta.chip
                        .padding(.leading, V2.Space.xxs)
                }
            }
        }
        .padding(.vertical, V2.Space.sm)
        .contentShape(Rectangle())
    }
}

/// Plain button style for a tappable stat/list row: fills `surface2` while pressed, nothing else.
struct V2PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? V2.Color.surface2 : Color.clear,
                in: RoundedRectangle(cornerRadius: V2.Radius.sm, style: .continuous)
            )
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        V2Card {
            VStack(spacing: 0) {
                V2StatRow(icon: "heart.fill", title: "Resting HR", value: "52", unit: "bpm",
                          delta: V2Delta(value: "3", direction: .down))
                V2StatRow(icon: "wind", title: "HRV", value: "128", unit: "ms",
                          delta: V2Delta(value: "12", direction: .up))
                V2StatRow(icon: "bed.double.fill", title: "Sleep debt", value: "0:42",
                          delta: V2Delta(value: "0", direction: .flat))
                V2StatRow(icon: "chevron.right.circle", title: "Open details", value: "",
                          action: {})
            }
        }
        .padding(V2.Space.gutter)
    }
}
#endif
