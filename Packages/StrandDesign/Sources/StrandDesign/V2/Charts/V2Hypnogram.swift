import SwiftUI

// MARK: - V2 Hypnogram (custom Canvas)
//
// A minimal restyle of the v1 `Hypnogram`: stepped sleep-stage bands over the night, drawn as
// flat rounded pills at each stage's row (awake top → deep bottom) and joined by thin vertical
// risers so the trace reads as one staircase. Colours come from `V2ChartScale.sleepStage`.
//
// Custom `Canvas`/`Path` (no Swift Charts) — cheap for a whole night in one pass and available on
// the entire floor (macOS 12 / iOS 15 / watchOS 8), so no availability gate. No hover / a11y-walk
// layer (v2 keeps it purely visual); a caller supplies its own summary label if needed.

/// One stage interval. `stage`: 0 awake · 1 rem · 2 light · 3 deep (the vertical row order, top→bottom).
public struct V2SleepSegment: Identifiable {
    public var start: Date
    public var end: Date
    public var stage: Int
    /// Content-derived identity (stage + bounds); non-overlapping segments make it unique + stable.
    public var id: String { "\(stage)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)" }

    public init(start: Date, end: Date, stage: Int) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

public struct V2Hypnogram: View {

    private let segments: [V2SleepSegment]

    private let height: CGFloat = 120
    private let rowCount = 4

    public init(segments: [V2SleepSegment]) {
        self.segments = segments.sorted { $0.start < $1.start }
    }

    /// Map the packet's stage index onto the shared `SleepStage` used by `V2ChartScale`.
    private func sleepStage(_ i: Int) -> SleepStage {
        switch i {
        case 0:  return .awake
        case 1:  return .rem
        case 2:  return .light
        default: return .deep
        }
    }

    private var origin: TimeInterval { segments.first?.start.timeIntervalSince1970 ?? 0 }

    private var span: TimeInterval {
        guard let first = segments.first,
              let last = segments.max(by: { $0.end < $1.end }) else { return 1 }
        return max(1, last.end.timeIntervalSince1970 - first.start.timeIntervalSince1970)
    }

    /// Vertical centre of a stage row (clamped rank 0…3).
    private func rowY(_ rank: Int, in totalHeight: CGFloat) -> CGFloat {
        let step = totalHeight / CGFloat(rowCount)
        let clamped = min(max(rank, 0), rowCount - 1)
        return step * (CGFloat(clamped) + 0.5)
    }

    public var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty, size.width > 0 else { return }

            let rowStep = size.height / CGFloat(rowCount)
            let thickness = max(3, rowStep * 0.42)

            // Risers first, behind the bands.
            if segments.count > 1 {
                var risers = Path()
                for i in 0..<(segments.count - 1) {
                    let a = segments[i]
                    let b = segments[i + 1]
                    let x = CGFloat((b.start.timeIntervalSince1970 - origin) / span) * size.width
                    risers.move(to: CGPoint(x: x, y: rowY(a.stage, in: size.height)))
                    risers.addLine(to: CGPoint(x: x, y: rowY(b.stage, in: size.height)))
                }
                context.stroke(risers,
                               with: .color(V2.Color.textTertiary.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1.5))
            }

            // Stage bands — flat rounded pills.
            for seg in segments {
                let x0 = CGFloat((seg.start.timeIntervalSince1970 - origin) / span) * size.width
                let x1 = CGFloat((seg.end.timeIntervalSince1970 - origin) / span) * size.width
                let mid = (x0 + x1) / 2
                // Floor width at the thickness so a brief stage reads as a pill/dot, not a glitch tick.
                let width = max(thickness, x1 - x0)
                let y = rowY(seg.stage, in: size.height)
                let rect = CGRect(x: mid - width / 2, y: y - thickness / 2,
                                  width: width, height: thickness)
                let path = Path(roundedRect: rect, cornerRadius: thickness / 2)
                context.fill(path, with: .color(V2ChartScale.sleepStage(sleepStage(seg.stage))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
private func _v2SampleNight() -> [V2SleepSegment] {
    var t = Date(timeIntervalSince1970: 1_700_000_000)
    func add(_ stage: Int, _ minutes: Double) -> V2SleepSegment {
        let s = V2SleepSegment(start: t, end: t.addingTimeInterval(minutes * 60), stage: stage)
        t = t.addingTimeInterval(minutes * 60)
        return s
    }
    return [
        add(0, 6), add(2, 22), add(3, 38), add(2, 18), add(1, 24), add(2, 14),
        add(3, 30), add(1, 28), add(2, 20), add(0, 4), add(1, 32), add(2, 26), add(0, 8),
    ]
}

#Preview("V2Hypnogram") {
    VStack {
        V2Hypnogram(segments: _v2SampleNight())
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
