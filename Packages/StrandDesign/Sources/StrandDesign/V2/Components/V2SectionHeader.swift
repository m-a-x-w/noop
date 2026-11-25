import SwiftUI

// MARK: - V2SectionHeader — the overline eyebrow above a group of cards
//
// Sits OUTSIDE cards, above a run of them, as a small uppercased overline in `textTertiary`.
// Optional trailing content (a "See all" ghost button, a segmented control) is right-aligned
// on the same baseline. Generic over the trailing view so no `AnyView` box is required.

public struct V2SectionHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    /// Section header with trailing accessory content (right-aligned).
    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V2.Space.sm) {
            Text(title)
                .font(V2Font.overline)
                .tracking(V2Font.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(V2.Color.textTertiary)
            Spacer(minLength: V2.Space.sm)
            trailing
        }
        .padding(.horizontal, V2.Space.xs)
    }
}

public extension V2SectionHeader where Trailing == EmptyView {
    /// Section header with no trailing content.
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(alignment: .leading, spacing: V2.Space.xl) {
            V2SectionHeader("Today")
            V2SectionHeader("Trends") {
                Text("See all")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textSecondary)
            }
        }
        .padding(V2.Space.gutter)
    }
}
#endif
