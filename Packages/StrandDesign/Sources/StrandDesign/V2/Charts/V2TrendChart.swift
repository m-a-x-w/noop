import SwiftUI
import Charts

// MARK: - V2 Trend Chart
//
// The v2 general-purpose trend chart: a single accent-coloured series over time in one of
// three styles (line / area / bars), with an optional faint baseline band (a "typical range"
// rectangle behind the data) and an optional dashed comparison series. It replaces the v1
// TrendChart / large Sparkline / TypicalRangeBar with ONE minimal component.
//
// Cross-platform (macOS 13 / iOS 16 / watchOS 10): uses only floor-level Swift Charts marks
// (LineMark / AreaMark / BarMark / RectangleMark) and axis modifiers — no hover / selection API,
// so nothing here needs an availability gate.

/// One point on a v2 chart series. Identity is content-derived (the date), so Swift Charts
/// diffs by data instead of re-identifying every mark on each render (a random `UUID()` would
/// replay the draw-on animation every body eval).
public struct V2ChartPoint: Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// How a `V2TrendChart` renders its primary series.
public enum V2ChartStyle {
    case line
    case area
    case bars
}

public struct V2TrendChart: View {

    private let points: [V2ChartPoint]
    private let domain: V2Domain
    private let style: V2ChartStyle
    private let band: ClosedRange<Double>?
    private let comparison: [V2ChartPoint]?

    /// Fixed plot height for the v2 card trend.
    private let height: CGFloat = 200

    public init(
        points: [V2ChartPoint],
        domain: V2Domain,
        style: V2ChartStyle = .line,
        band: ClosedRange<Double>? = nil,
        comparison: [V2ChartPoint]? = nil
    ) {
        self.points = points.sorted { $0.date < $1.date }
        self.domain = domain
        self.style = style
        self.band = band
        self.comparison = comparison.map { $0.sorted { $0.date < $1.date } }
    }

    public var body: some View {
        Chart {
            // Baseline band — a faint horizontal rectangle behind the data (drawn first so the
            // series sits on top), spanning the data's date extent. Explicit x-bounds keep the
            // `RectangleMark` X type unambiguous across the floor.
            if let band, let first = points.first?.date, let last = points.last?.date {
                RectangleMark(
                    xStart: .value("Start", first),
                    xEnd: .value("End", last),
                    yStart: .value("Low", band.lowerBound),
                    yEnd: .value("High", band.upperBound)
                )
                .foregroundStyle(domain.trace)
            }

            // Primary series in the domain accent.
            switch style {
            case .line:
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(domain.accent)
                }
            case .area:
                ForEach(points) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [domain.accent.opacity(0.28), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(domain.accent)
                }
            case .bars:
                ForEach(points) { p in
                    BarMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(domain.accent)
                        .cornerRadius(2)
                }
            }

            // Optional dashed comparison series (e.g. last period / baseline curve).
            if let comparison {
                ForEach(comparison) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value),
                        series: .value("Series", "comparison")
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(V2.Color.textTertiary)
                }
            }
        }
        // catmullRom overshoots past the data on sharp turns and the area gradient draws
        // unclipped — clip the plot so a spiky curve can't bleed past the chart.
        .chartPlotStyle { plotArea in plotArea.clipped() }
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
        .frame(height: height)
        .clipped()
    }
}

#if DEBUG
private func _v2SampleTrend(days: Int, base: Double, swing: Double) -> [V2ChartPoint] {
    let cal = Calendar.current
    let today = Date()
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = base + swing * sin(Double(i) / 3.0) + Double((i * 17) % 9) - 4
        return V2ChartPoint(date: date, value: max(0, v))
    }
}

#Preview("V2TrendChart") {
    VStack(spacing: 24) {
        V2TrendChart(points: _v2SampleTrend(days: 30, base: 62, swing: 20),
                     domain: .charge, style: .line, band: 50...75)
        V2TrendChart(points: _v2SampleTrend(days: 30, base: 58, swing: 14),
                     domain: .rest, style: .area,
                     comparison: _v2SampleTrend(days: 30, base: 52, swing: 8))
        V2TrendChart(points: _v2SampleTrend(days: 14, base: 40, swing: 24),
                     domain: .effort, style: .bars)
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
