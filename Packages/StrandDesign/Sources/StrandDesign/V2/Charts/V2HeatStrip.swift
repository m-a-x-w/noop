import SwiftUI

// MARK: - V2 Heat Strip
//
// A horizontal year / streak strip of small rounded cells, each coloured by its day's score via
// the recovery ramp (`V2ChartScale.recovery`); a `nil` score (no data) reads as `surface2`.
// Replaces the v1 YearHeatStrip.
//
// Drawn with `Canvas` rather than Swift Charts: a full year is ~365 cells, and a single Canvas
// pass with rounded-rect `Path`s is cheaper and gives per-cell corner radii for free. Canvas is
// available on the whole floor (macOS 12 / iOS 15 / watchOS 8), so no availability gate is needed.

/// One day cell in a `V2HeatStrip`. `score` is a 0…100 recovery-scale value; `nil` = no data.
public struct V2HeatCell: Identifiable {
    public var date: Date
    public var score: Double?
    public var id: Date { date }

    public init(date: Date, score: Double?) {
        self.date = date
        self.score = score
    }
}

public struct V2HeatStrip: View {

    private let days: [V2HeatCell]

    /// Strip height; cells fill it vertically.
    private let height: CGFloat = 16

    public init(days: [V2HeatCell]) {
        self.days = days
    }

    public var body: some View {
        Canvas { context, size in
            let count = days.count
            guard count > 0, size.width > 0 else { return }

            let cellPitch = size.width / CGFloat(count)
            // Inter-cell gap scales with the pitch but is capped, so a dense year stays legible and
            // a short streak keeps clean gutters.
            let gap = min(2, cellPitch * 0.22)
            let cellW = max(1, cellPitch - gap)
            let corner = min(cellW, size.height) * 0.28

            for (i, cell) in days.enumerated() {
                let x = CGFloat(i) * cellPitch
                let rect = CGRect(x: x, y: 0, width: cellW, height: size.height)
                let color: Color
                if let score = cell.score {
                    color = V2ChartScale.recovery(Int(score.rounded()))
                } else {
                    color = V2.Color.surface2
                }
                let path = Path(roundedRect: rect, cornerRadius: corner)
                context.fill(path, with: .color(color))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("V2HeatStrip") {
    let cal = Calendar.current
    let today = Date()
    let year: [V2HeatCell] = (0..<180).map { i in
        let date = cal.date(byAdding: .day, value: -(179 - i), to: today)!
        // Sprinkle some gaps (nil) to show the empty-cell colour.
        let missing = (i % 23 == 0)
        let score = missing ? nil : min(100, max(0, 55 + 35 * sin(Double(i) / 9.0)))
        return V2HeatCell(date: date, score: score)
    }
    return VStack(alignment: .leading, spacing: 24) {
        V2HeatStrip(days: year)
        V2HeatStrip(days: Array(year.suffix(30)))
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
