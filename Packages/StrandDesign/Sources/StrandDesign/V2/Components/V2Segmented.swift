import SwiftUI

// MARK: - V2Segmented — the hairline range/segment control
//
// A capsule of equal-width segments inside a hairline outline. The selected segment gets a
// `surface2` fill (sliding between segments via a matched-geometry pill) and `textPrimary`
// ink; the rest are `textTertiary`. Used for range switches (7D / 30D / 90D / 1Y) and small
// mode toggles. Generic over any `Hashable` value.

public struct V2Segmented<T: Hashable>: View {
    @Binding private var selection: T
    private let options: [(T, String)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    public init(selection: Binding<T>, options: [(T, String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                segment(option.0, option.1)
            }
        }
        .padding(V2.Space.xxs)
        .background(Capsule().strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
        .animation(V2Motion.resolve(V2Motion.snap, reduceMotion: reduceMotion), value: selection)
    }

    @ViewBuilder
    private func segment(_ tag: T, _ label: String) -> some View {
        let isSelected = tag == selection
        Button {
            selection = tag
        } label: {
            Text(label)
                .font(V2Font.label)
                .foregroundStyle(isSelected ? V2.Color.textPrimary : V2.Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, V2.Space.sm)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(V2.Color.surface2)
                            .matchedGeometryEffect(id: "v2segpill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
private struct V2SegmentedPreview: View {
    @State private var range = "7D"
    var body: some View {
        ZStack {
            V2.Color.surface0.ignoresSafeArea()
            V2Segmented(selection: $range,
                        options: [("7D", "7D"), ("30D", "30D"), ("90D", "90D"), ("1Y", "1Y")])
                .padding(V2.Space.gutter)
        }
    }
}

#Preview {
    V2SegmentedPreview()
}
#endif
