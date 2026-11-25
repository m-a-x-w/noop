import SwiftUI
import Charts

// MARK: - V2 Sparkline
//
// A tiny, axis-free inline trend for stat rows and pinned mini-cards: no axes, no labels,
// no gridlines — just the accent line (optionally with a faint fill). Height ~28.
//
// Cross-platform (macOS 13 / iOS 16 / watchOS 10): floor-level marks + `.chartXAxis(.hidden)` /
// `.chartYAxis(.hidden)` only, so no availability gate is needed.

public struct V2Sparkline: View {

    private let values: [Double]
    private let domain: V2Domain
    private let filled: Bool

    private let height: CGFloat = 28

    public init(values: [Double], domain: V2Domain = .charge, filled: Bool = false) {
        self.values = values
        self.domain = domain
        self.filled = filled
    }

    public var body: some View {
        Chart {
            if filled {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                    AreaMark(x: .value("i", idx), y: .value("v", v))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [domain.accent.opacity(0.24), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                LineMark(x: .value("i", idx), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(domain.accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in plotArea.clipped() }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("V2Sparkline") {
    let vals: [Double] = (0..<24).map { i in
        let wave: Double = 22 * sin(Double(i) / 3.2)
        let jitter: Double = Double((i * 13) % 7)
        return 50 + wave + jitter
    }
    return VStack(alignment: .leading, spacing: 20) {
        V2Sparkline(values: vals, domain: .charge)
        V2Sparkline(values: vals, domain: .stress, filled: true)
        V2Sparkline(values: vals, domain: .effort, filled: true)
    }
    .frame(width: 180)
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
