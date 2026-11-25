import SwiftUI

// MARK: - V2BigNumber — the hero numeral with a self-contained count-up
//
// The big mono number at the top of a screen or card: `value` in a fixed-size numeral, an
// optional small trailing `unit`, an optional `label` overline beneath. Passing a `domain`
// draws a 1pt underline under the number in the domain accent — the only colour on the tile.
//
// Count-up is self-contained (no dependency on v1 `NoopMotion`): the number rolls with
// `.contentTransition(.numericText())`. On first appear it rolls up from a zeroed shape of the
// same width; on any later change it rolls from the previous value to the new one. Reduce
// Motion skips both rolls. `minimumScaleFactor` + `lineLimit(1)` keep large accessibility
// sizes from clipping the container.

public struct V2BigNumber: View {
    private let value: String
    private let unit: String?
    private let label: String?
    private let domain: V2Domain?
    private let size: CGFloat

    public init(value: String,
                unit: String? = nil,
                label: String? = nil,
                domain: V2Domain? = nil,
                size: CGFloat = 56) {
        self.value = value
        self.unit = unit
        self.label = label
        self.domain = domain
        self.size = size
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The currently-displayed string. Empty until the first appear resolves it to `value`.
    @State private var shown: String = ""
    @State private var didAppear = false

    /// What to render right now: the animated `shown`, or `value` before the first appear.
    private var displayed: String { shown.isEmpty ? value : shown }

    /// True when `value` contains at least one digit — only then does a count-up make sense.
    private var isNumeric: Bool { value.contains(where: \.isNumber) }

    /// A same-width "zero frame" of `value` (digits → 0, other glyphs kept) to roll up from.
    private func zeroed(_ s: String) -> String {
        String(s.map { $0.isNumber ? "0" : $0 })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: V2.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: V2.Space.xs) {
                Text(displayed)
                    .font(V2Font.numeral(size))
                    .foregroundStyle(V2.Color.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .overlay(alignment: .bottom) {
                        if let domain {
                            Rectangle()
                                .fill(domain.accent)
                                .frame(height: 1)
                                .offset(y: 3)
                        }
                    }
                if let unit {
                    Text(unit)
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            }
            if let label {
                Text(label)
                    .font(V2Font.overline)
                    .tracking(V2Font.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(V2.Color.textTertiary)
            }
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            if reduceMotion || !isNumeric {
                shown = value
            } else {
                // Render a zeroed frame first, then roll up to the real value next runloop.
                shown = zeroed(value)
                DispatchQueue.main.async {
                    withAnimation(V2Motion.calm) { shown = value }
                }
            }
        }
        .onChange(of: value) { newValue in
            if reduceMotion {
                shown = newValue
            } else {
                withAnimation(V2Motion.settle) { shown = newValue }
            }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        VStack(alignment: .leading, spacing: V2.Space.xl) {
            V2BigNumber(value: "72", unit: "%", label: "Charge", domain: .charge)
            V2BigNumber(value: "6:48", label: "Time asleep", domain: .rest, size: 44)
            V2BigNumber(value: "128", unit: "ms", label: "HRV")
        }
        .padding(V2.Space.gutter)
    }
}
#endif
