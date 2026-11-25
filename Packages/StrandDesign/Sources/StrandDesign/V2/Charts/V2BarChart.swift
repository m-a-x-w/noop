import SwiftUI
import Charts

// MARK: - V2 Bar Chart
//
// Daily bars in the domain accent. Two modes:
//  • full (default) — a card-height daily bar chart with minimal axes.
//  • micro (`micro: true`) — a tiny axis-free strip (~24pt) that replaces the v1 PipBar for
//    inline "last N days" glances inside stat rows.
//
// Cross-platform (macOS 13 / iOS 16 / watchOS 10): floor-level `BarMark` + axis modifiers only.

public struct V2BarChart: View {

    private let bars: [V2ChartPoint]
    private let domain: V2Domain
    private let micro: Bool

    public init(bars: [V2ChartPoint], domain: V2Domain, micro: Bool = false) {
        self.bars = bars.sorted { $0.date < $1.date }
        self.domain = domain
        self.micro = micro
    }

    public var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: .day),
                y: .value("Value", bar.value),
                width: micro ? .ratio(0.55) : .ratio(0.65)
            )
            .foregroundStyle(domain.accent)
            .cornerRadius(micro ? 1.5 : 2.5)
        }
        .chartPlotStyle { plotArea in plotArea.clipped() }
        .modifier(V2BarAxes(micro: micro))
        .frame(height: micro ? 24 : 140)
        .accessibilityHidden(micro)
    }
}

/// Micro mode hides all chrome; full mode shows the minimal v2 hairline axes.
private struct V2BarAxes: ViewModifier {
    let micro: Bool
    func body(content: Content) -> some View {
        if micro {
            content
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        } else {
            content
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(V2.Color.hairline)
                        AxisValueLabel()
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(V2.Color.hairline)
                        AxisValueLabel()
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                }
        }
    }
}

#if DEBUG
private func _v2SampleBars(days: Int) -> [V2ChartPoint] {
    let cal = Calendar.current
    let today = Date()
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 30 + 45 * abs(sin(Double(i) / 2.5)) + Double((i * 11) % 8)
        return V2ChartPoint(date: date, value: v)
    }
}

#Preview("V2BarChart") {
    VStack(alignment: .leading, spacing: 24) {
        V2BarChart(bars: _v2SampleBars(days: 14), domain: .effort)
        V2BarChart(bars: _v2SampleBars(days: 14), domain: .charge, micro: true)
            .frame(width: 120)
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
