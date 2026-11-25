import SwiftUI
import Charts

// MARK: - V2 Day Chart
//
// An intraday line (heart rate, stress, …) with a native scrub read-out. On iOS 17 / macOS 14
// (and the watchOS 10 floor) it uses `chartXSelection` so a touch-drag pins a value callout;
// on older OSes the same view renders the plain line with no selection. The public init is
// identical across versions — the version split is entirely internal (`V2DayChartSelection`),
// so callers never branch.
//
// Replaces the v1 OverviewHRChart's read-out layer with the modern selection API instead of the
// pointer-only `.onContinuousHover` (which is dead on touch and absent on watchOS).

public struct V2DayChart: View {

    private let samples: [V2ChartPoint]
    private let domain: V2Domain

    private let height: CGFloat = 200

    /// The x the user is scrubbing (set only on iOS 17 / macOS 14+ via `chartXSelection`).
    @State private var selectedDate: Date?

    public init(samples: [V2ChartPoint], domain: V2Domain = .health) {
        self.samples = samples.sorted { $0.date < $1.date }
        self.domain = domain
    }

    /// The sample nearest the scrubbed x, or nil when nothing is selected.
    private var selectedSample: V2ChartPoint? {
        guard let selectedDate, !samples.isEmpty else { return nil }
        return samples.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    public var body: some View {
        Chart {
            ForEach(samples) { p in
                LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(domain.accent)
            }

            // Scrub read-out. `selectedSample` is only non-nil once `chartXSelection` has set
            // `selectedDate`, which only happens on iOS 17 / macOS 14+, so this whole layer is
            // inert (never built) on the older fallback path.
            if let sel = selectedSample {
                RuleMark(x: .value("Time", sel.date))
                    .foregroundStyle(V2.Color.hairlineHeavy)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", sel.date), y: .value("Value", sel.value))
                    .symbolSize(30)
                    .foregroundStyle(domain.accent)
                    .annotation(position: .top, alignment: .center) {
                        V2DayCallout(sample: sel, domain: domain)
                    }
            }
        }
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
        .modifier(V2DayChartSelection(selectedDate: $selectedDate))
        .frame(height: height)
        // No outer `.clipped()`: the plot-area clip above already contains any catmullRom overshoot,
        // and leaving the chart frame unclipped lets the scrub callout annotation extend into the
        // top margin instead of being hard-clipped when the selected point sits near the top edge.
    }
}

/// Applies `chartXSelection` on iOS 17 / macOS 14+ (and the watchOS 10 floor); a no-op passthrough
/// on older OSes so the plain line still renders. Keeps `V2DayChart`'s init version-agnostic.
private struct V2DayChartSelection: ViewModifier {
    @Binding var selectedDate: Date?
    func body(content: Content) -> some View {
        if #available(iOS 17, macOS 14, *) {
            content.chartXSelection(value: $selectedDate)
        } else {
            content
        }
    }
}

/// The scrub callout: value over time, in the v2 mono face on a floating card.
private struct V2DayCallout: View {
    let sample: V2ChartPoint
    let domain: V2Domain

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(Int(sample.value.rounded())))
                .font(V2Font.numeral(15))
                .foregroundStyle(domain.accent)
            Text(Self.timeFormatter.string(from: sample.date))
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: V2.Radius.sm, style: .continuous)
                .fill(V2.Color.surface3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V2.Radius.sm, style: .continuous)
                .strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline)
        )
        .fixedSize()
    }
}

#if DEBUG
#Preview("V2DayChart") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let pts: [V2ChartPoint] = (0..<180).map { i in
        let t = now.addingTimeInterval(Double(i) * 300 - 180 * 300)
        let base = 58.0 + 18 * abs(sin(Double(i) / 24.0))
        let spike = (i > 120 && i < 132) ? 60.0 : 0
        return V2ChartPoint(date: t, value: base + spike)
    }
    return VStack {
        V2DayChart(samples: pts, domain: .health)
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
