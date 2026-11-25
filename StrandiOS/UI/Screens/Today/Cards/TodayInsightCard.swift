#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

// MARK: - TodayInsightCard — one honest, derived insight
//
// Surfaces a SINGLE insight for the selected day: the biggest Charge driver (via the pure
// `RecoveryScorer.chargeDrivers`, ordered biggest-mover first), phrased in plain prose (SF Pro). If
// there's no scored signal yet it degrades to a calm band read. "See all" opens the full Insights feed.

struct TodayInsightCard: View {
    let ctx: TodayContext

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("Insight") {
                    NavigationLink(value: V2DetailRoute.insights) {
                        Text("See all")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                if let driver = topDriver {
                    HStack(alignment: .top, spacing: V2.Space.sm) {
                        Image(systemName: driver.deltaPoints >= 0 ? "arrow.up.circle" : "arrow.down.circle")
                            .font(V2Font.body)
                            .foregroundStyle(driver.deltaPoints >= 0 ? V2.Color.positive : V2.Color.caution)
                        VStack(alignment: .leading, spacing: V2.Space.xxs) {
                            Text(driver.label)
                                .font(V2Font.heading)
                                .foregroundStyle(V2.Color.textPrimary)
                            Text(driver.verdict.prefix(1).capitalized + driver.verdict.dropFirst() + ".")
                                .font(V2Font.prose)
                                .foregroundStyle(V2.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(fallbackText)
                        .font(V2Font.prose)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Derivation

    private var topDriver: ChargeDriver? {
        guard let hrv = ctx.hrv, let rhr = ctx.rhr else { return nil }
        let hrvBase = Baselines.foldHistory(ctx.days.map(\.avgHrv), cfg: Baselines.hrvCfg)
        let rhrBase = Baselines.foldHistory(ctx.days.map { $0.restingHr.map(Double.init) },
                                            cfg: Baselines.restingHRCfg)
        let respBase = Baselines.foldHistory(ctx.days.map(\.respRateBpm), cfg: Baselines.respCfg)
        let drivers = RecoveryScorer.chargeDrivers(
            hrv: hrv, rhr: Double(rhr), resp: ctx.resp,
            hrvBaseline: hrvBase,
            rhrBaseline: rhrBase.usable ? rhrBase : nil,
            respBaseline: respBase.usable ? respBase : nil,
            sleepPerf: nil, skinTempDev: ctx.skinTempDevC)
        return drivers.first
    }

    private var fallbackText: String {
        switch ctx.day?.recovery {
        case .some(let r) where r >= 67:
            return String(localized: "Your Charge is high — a good day to push if you feel up to it.")
        case .some(let r) where r < 34:
            return String(localized: "Your Charge is low — keep today easy and prioritise sleep tonight.")
        case .some:
            return String(localized: "Your Charge is moderate — train to feel, and listen to your body.")
        case .none:
            return String(localized: "Wear your strap overnight to unlock a personalised read on your day.")
        }
    }
}
#endif
