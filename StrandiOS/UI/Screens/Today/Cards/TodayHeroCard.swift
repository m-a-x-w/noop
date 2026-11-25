#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - TodayHeroCard — the three-column overview (Charge · Rest · Effort)
//
// The pinned top card: three `V2BigNumber` columns, each with a 1pt domain underline, a one-line
// status caption, and a tap that drills into that domain's detail. In `.detailed` density each
// column gains a 7-day `V2Sparkline`. Neutral card shell — the only colour is the per-column
// domain accent under each numeral.

struct TodayHeroCard: View {
    let ctx: TodayContext
    @Environment(\.v2Density) private var density

    private var isDetailed: Bool { density == .detailed }

    var body: some View {
        V2Card {
            HStack(alignment: .top, spacing: V2.Space.md) {
                column(
                    value: chargeValue, unit: ctx.day?.recovery == nil ? nil : "%",
                    label: "Charge", caption: TodayFormat.chargeWord(ctx.day?.recovery),
                    domain: .charge, spark: ctx.trailing(\.recovery),
                    route: .charge(ctx.date))

                divider

                column(
                    value: TodayFormat.hmm(ctx.day?.totalSleepMin), unit: nil,
                    label: "Rest", caption: restCaption,
                    domain: .rest, spark: ctx.trailing(\.totalSleepMin).map { $0 / 60 },
                    route: .sleep(ctx.date))

                divider

                column(
                    value: effortValue, unit: nil,
                    label: "Effort", caption: TodayFormat.effortWord(ctx.day?.strain),
                    domain: .effort, spark: ctx.trailing(\.strain),
                    route: .workouts)
            }
        }
    }

    // MARK: One column

    private func column(value: String, unit: String?, label: String, caption: String,
                        domain: V2Domain, spark: [Double], route: V2DetailRoute) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2BigNumber(value: value, unit: unit, label: label, domain: domain, size: 34)
                Text(caption)
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isDetailed && spark.count >= 2 {
                    V2Sparkline(values: spark, domain: domain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(V2.Color.hairline)
            .frame(width: V2.Stroke.hairline)
            .padding(.vertical, V2.Space.xxs)
    }

    // MARK: Derived values

    private var chargeValue: String {
        guard let r = ctx.day?.recovery else { return "—" }
        return "\(Int(r.rounded()))"
    }

    private var effortValue: String {
        guard let s = ctx.day?.strain else { return "—" }
        return UnitFormatter.effortDisplay(s, scale: ctx.effortScale)
    }

    private var restCaption: String {
        if let eff = ctx.day?.efficiency, eff > 0 {
            // `efficiency` is already a 0–100 percentage in the store (v1 formats it as "%.0f%% eff").
            return "\(Int(eff.rounded()))% " + String(localized: "efficient")
        }
        return TodayFormat.hmm(ctx.day?.totalSleepMin) == "—"
            ? String(localized: "No sleep logged")
            : String(localized: "Last night")
    }
}
#endif
