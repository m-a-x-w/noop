#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

// MARK: - TodaySleepCard — last night's sleep at a glance
//
// The selected night's asleep-duration numeral, a debt/surplus chip, and either a mini
// `V2Hypnogram` (detailed density, when the night has staged segments) or a proportional stage bar
// (compact, or when there are no segments). The whole card drills into the full Sleep detail.

struct TodaySleepCard: View {
    let ctx: TodayContext
    let session: CachedSleepSession?
    @Environment(\.v2Density) private var density

    private var isDetailed: Bool { density == .detailed }

    var body: some View {
        NavigationLink(value: V2DetailRoute.sleep(ctx.date)) {
            V2Card(domain: .rest) {
                VStack(alignment: .leading, spacing: V2.Space.md) {
                    HStack(alignment: .firstTextBaseline) {
                        V2BigNumber(value: TodayFormat.hmm(ctx.day?.totalSleepMin),
                                    label: "Time asleep", domain: .rest, size: 38)
                        Spacer(minLength: V2.Space.sm)
                        if let chip = debtChip { chip }
                    }
                    if isDetailed, let segs = segments, segs.count >= 2 {
                        V2Hypnogram(segments: segs)
                    } else {
                        stageBar
                    }
                    stageLegend
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Debt chip

    private var debtChip: V2Chip? {
        let ledger = SleepDebt.ledger(series: ctx.days.map { ($0.day, $0.totalSleepMin) })
        guard ledger.nightCount > 0 else { return nil }
        if ledger.isDebt {
            return V2Chip(TodayFormat.hmmMagnitude(ledger.balanceMin) + " " + String(localized: "debt"),
                          tone: .caution)
        }
        return V2Chip(TodayFormat.hmmMagnitude(ledger.balanceMin) + " " + String(localized: "ahead"),
                      tone: .positive)
    }

    // MARK: Stage bar (compact / no-segments fallback)

    /// Stage minutes for the selected night, from the day row.
    private var stageMinutes: [(SleepStage, Double)] {
        [(.deep, ctx.day?.deepMin ?? 0),
         (.rem, ctx.day?.remMin ?? 0),
         (.light, ctx.day?.lightMin ?? 0)].filter { $0.1 > 0 }
    }

    @ViewBuilder
    private var stageBar: some View {
        let stages = stageMinutes
        let total = stages.reduce(0) { $0 + $1.1 }
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(V2ChartScale.sleepStage(item.0))
                            .frame(width: max(2, geo.size.width * (item.1 / total) - 2))
                    }
                }
            }
            .frame(height: 8)
        } else {
            Text("No staged sleep")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
        }
    }

    private var stageLegend: some View {
        HStack(spacing: V2.Space.md) {
            legendItem(.deep, "Deep", ctx.day?.deepMin)
            legendItem(.rem, "REM", ctx.day?.remMin)
            legendItem(.light, "Light", ctx.day?.lightMin)
        }
    }

    private func legendItem(_ stage: SleepStage, _ label: String, _ minutes: Double?) -> some View {
        HStack(spacing: V2.Space.xs) {
            Circle().fill(V2ChartScale.sleepStage(stage)).frame(width: 6, height: 6)
            Text(label)
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
            Text(TodayFormat.hmm(minutes))
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textSecondary)
        }
    }

    // MARK: Hypnogram segments (decode the night's stagesJSON)

    private var segments: [V2SleepSegment]? {
        guard let json = session?.stagesJSON, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        var out: [V2SleepSegment] = []
        for seg in arr {
            guard let start = (seg["start"] as? NSNumber)?.intValue,
                  let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                  let name = seg["stage"] as? String else { continue }
            let stage: Int
            switch name {
            case "wake", "awake": stage = 0
            case "rem":           stage = 1
            case "light":         stage = 2
            case "deep":          stage = 3
            default:              continue
            }
            out.append(V2SleepSegment(start: Date(timeIntervalSince1970: TimeInterval(start)),
                                      end: Date(timeIntervalSince1970: TimeInterval(end)),
                                      stage: stage))
        }
        return out.isEmpty ? nil : out
    }
}
#endif
