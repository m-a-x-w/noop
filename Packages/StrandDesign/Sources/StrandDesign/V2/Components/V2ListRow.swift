import SwiftUI

// MARK: - V2ListRow / V2List — settings & nav lists without the UITableView look
//
// `V2List` stacks its rows on a single `surface1` panel with hairline separators BETWEEN rows
// only (never a trailing rule, never a grouped-table inset background). `V2ListRow` is the
// standard row: a title, an optional subtitle, optional trailing text and/or SF Symbol, and a
// chevron by default. A row with an `action` becomes a plain Button with a `surface2` pressed
// fill (reusing `V2PressableRowStyle`).

public struct V2ListRow: View {
    private let title: String
    private let subtitle: String?
    private let trailingText: String?
    private let trailingSymbol: String?
    private let chevron: Bool
    private let action: (() -> Void)?

    public init(title: String,
                subtitle: String? = nil,
                trailingText: String? = nil,
                trailingSymbol: String? = nil,
                chevron: Bool = true,
                action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.trailingSymbol = trailingSymbol
        self.chevron = chevron
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
            VStack(alignment: .leading, spacing: V2.Space.xxs) {
                Text(title)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            }
            Spacer(minLength: V2.Space.sm)
            if let trailingText {
                Text(trailingText)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
        }
        .padding(.horizontal, V2.Space.lg)
        .padding(.vertical, V2.Space.md)
        .contentShape(Rectangle())
    }
}

/// A panel that stacks rows on `surface1` with hairline separators between them (inset to align
/// with row text), a `Radius.card` corner and a single hairline border. No grouped-table look.
public struct V2List<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: V2.Radius.card, style: .continuous)
    }

    public var body: some View {
        _VariadicView.Tree(V2DividedListRoot()) { content }
            .background(V2.Color.surface1)
            .clipShape(shape)
            .overlay(shape.strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
    }
}

/// Lays the list's child rows into a `VStack` and inserts a hairline separator after every row
/// except the last. Uses SwiftUI's variadic-view tree so an arbitrary run of rows composes
/// correctly with between-only rules (there is no fully-public way to do between-only separators
/// over `@ViewBuilder` content). Compiles on iOS 16 / macOS 13 / watchOS 10.
private struct V2DividedListRoot: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != lastID {
                    Rectangle()
                        .fill(V2.Color.hairline)
                        .frame(height: V2.Stroke.hairline)
                        .padding(.leading, V2.Space.lg)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        V2List {
            V2ListRow(title: "Units", trailingText: "Metric", action: {})
            V2ListRow(title: "Connected devices", subtitle: "WHOOP 4.0", action: {})
            V2ListRow(title: "Notifications", trailingSymbol: "bell.fill", action: {})
            V2ListRow(title: "About", chevron: false, action: {})
        }
        .padding(V2.Space.gutter)
    }
}
#endif
