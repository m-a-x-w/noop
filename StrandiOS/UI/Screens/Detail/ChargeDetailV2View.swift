#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - ChargeDetailV2View
//
// The Charge (recovery) drill-in for one day. Progressive disclosure from the Today/Explore
// surfaces: the surface shows the number, this screen shows the full analysis — the score ring,
// the ordered DRIVER breakdown (RecoveryScorer.chargeDrivers, one honest row per term that fed
// the score, with its signed point contribution + plain-English verdict), the underlying vitals
// with their personal baselines, and a 14/30-day Charge trend.
//
// Every value is READ from the same data layer the v1 screens read (Repository.days DailyMetric,
// the sleep_performance series for the Rest-quality term, folded Baselines). Nothing is scored or
// invented here. Dark-only, mono numerals, hairline rules.

struct ChargeDetailV2View: View {
    let date: Date

    @EnvironmentObject var repo: Repository

    // Rest-quality term feeds the Charge model as sleep_performance ÷ 100 (§3/§5). Loaded async for
    // the selected day so the driver breakdown matches what AnalyticsEngine scored with.
    @State private var restScore: Double?
    // Trend window (nights). 30D default, 14D via the segmented control.
    @State private var trendDays: Int = 30

    // Imperial/Metric temperature preference for the skin-temp deviation read-out.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }

    init(date: Date) { self.date = date }

    // MARK: Day resolution

    private var dayKey: String { Repository.localDayKey(date) }

    /// The stored row for the selected day (newest matching key), or nil if that day isn't scored.
    private var row: DailyMetric? { repo.days.last { $0.day == dayKey } }

    private var score: Double? { row?.recovery }

    // MARK: Derived analysis (pure — reads only data already in repo.days + restScore)

    private var hrvBaseline: BaselineState {
        Baselines.foldHistory(repo.days.map(\.avgHrv), cfg: Baselines.hrvCfg)
    }
    private var rhrBaseline: BaselineState {
        Baselines.foldHistory(repo.days.map { $0.restingHr.map(Double.init) }, cfg: Baselines.restingHRCfg)
    }
    private var respBaseline: BaselineState {
        Baselines.foldHistory(repo.days.map(\.respRateBpm), cfg: Baselines.respCfg)
    }

    /// The ordered Charge driver breakdown for the selected day, built from the SAME inputs the
    /// score used. Empty for a calibrating night (no usable HRV baseline / no HRV or RHR).
    private var drivers: [ChargeDriver] {
        guard let row, let hrv = row.avgHrv, let rhr = row.restingHr else { return [] }
        let hrvBase = hrvBaseline
        guard hrvBase.usable else { return [] }
        let rhrBase = rhrBaseline
        let respBase = respBaseline
        let sleepPerf = restScore.map { $0 / 100.0 }
        return RecoveryScorer.chargeDrivers(
            hrv: hrv, rhr: Double(rhr), resp: row.respRateBpm,
            hrvBaseline: hrvBase,
            rhrBaseline: rhrBase.usable ? rhrBase : nil,
            respBaseline: respBase.usable ? respBase : nil,
            sleepPerf: sleepPerf, skinTempDev: row.skinTempDevC)
    }

    private var stateWord: String { score.map { StrandPalette.recoveryState($0) } ?? "NO DATA" }

    /// A restrained semantic dot for the WHOOP band (red/yellow/green → V2 negative/caution/positive).
    private var bandColor: Color {
        guard let s = score else { return V2.Color.textTertiary }
        switch RecoveryScorer.band(s) {
        case "green":  return V2.Color.positive
        case "yellow": return V2.Color.caution
        default:       return V2.Color.negative
        }
    }
    private var bandLabel: String {
        guard let s = score else { return "Not scored yet" }
        switch RecoveryScorer.band(s) {
        case "green":  return "In the green"
        case "yellow": return "In the yellow"
        default:       return "In the red"
        }
    }

    // MARK: Trend

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// Charge points for the trailing `trendDays` nights up to and including the selected day.
    private var trendPoints: [V2ChartPoint] {
        let rows = repo.days.filter { $0.day <= dayKey }.suffix(trendDays)
        return rows.compactMap { r in
            guard let rec = r.recovery, let d = Self.dayFmt.date(from: r.day) else { return nil }
            return V2ChartPoint(date: d, value: rec)
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Charge", subtitle: subtitleLabel)

                heroCard
                driverSection
                vitalsSection
                trendSection
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: dayKey) {
            let series = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            restScore = series.first(where: { $0.day == dayKey })?.value
        }
    }

    private var subtitleLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: Hero

    private var heroCard: some View {
        V2Card(domain: .charge) {
            HStack(spacing: V2.Space.xl) {
                V2Ring(progress: (score ?? 0) / 100.0,
                       domain: .charge,
                       size: 132,
                       label: "Charge",
                       value: score.map { "\(Int($0.rounded()))" } ?? "—")
                VStack(alignment: .leading, spacing: V2.Space.sm) {
                    Text(stateWord)
                        .font(V2Font.heading)
                        .foregroundStyle(V2.Color.textPrimary)
                    HStack(spacing: V2.Space.sm) {
                        Circle()
                            .fill(bandColor)
                            .frame(width: 7, height: 7)
                        Text(bandLabel)
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                    Text("Recovery for this day")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Drivers

    private var driverSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("What shaped it")
            V2Card {
                if drivers.isEmpty {
                    Text("Calibrating — not enough nights yet to break Charge down into its drivers.")
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(drivers.enumerated()), id: \.offset) { idx, driver in
                            if idx > 0 { hairline }
                            driverRow(driver)
                        }
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    @ViewBuilder
    private func driverRow(_ driver: ChargeDriver) -> some View {
        let pts = driver.deltaPoints
        let dir: V2Delta.Direction = pts > 0 ? .up : (pts < 0 ? .down : .flat)
        VStack(alignment: .leading, spacing: V2.Space.xxs) {
            V2StatRow(title: driver.label,
                      value: driver.valueText,
                      delta: V2Delta(value: "\(abs(pts)) pt" + (abs(pts) == 1 ? "" : "s"),
                                     direction: dir))
            let detail = [driver.baselineText, verdictLine(driver.verdict)]
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  ")
            if !detail.isEmpty {
                Text(detail)
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, V2.Space.sm)
            }
        }
    }

    // MARK: Vitals

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Vitals")
            V2Card {
                VStack(spacing: 0) {
                    vitalRow(title: "Heart rate variability",
                             value: row?.avgHrv,
                             unit: "ms",
                             decimals: 0,
                             baseline: hrvBaseline)
                    hairline
                    vitalRow(title: "Resting heart rate",
                             value: row?.restingHr.map(Double.init),
                             unit: "bpm",
                             decimals: 0,
                             baseline: rhrBaseline)
                    hairline
                    vitalRow(title: "Respiratory rate",
                             value: row?.respRateBpm,
                             unit: "br/min",
                             decimals: 1,
                             baseline: respBaseline)
                    hairline
                    skinTempRow
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    @ViewBuilder
    private func vitalRow(title: String, value: Double?, unit: String, decimals: Int,
                          baseline: BaselineState) -> some View {
        VStack(alignment: .leading, spacing: V2.Space.xxs) {
            V2StatRow(title: title,
                      value: value.map { fmt($0, decimals) } ?? "—",
                      unit: value == nil ? nil : unit)
            if let value, baseline.usable {
                let dev = Baselines.deviation(value, state: baseline)
                let sign = dev.delta >= 0 ? "+" : "−"
                Text("baseline \(fmt(baseline.baseline, decimals)) \(unit)  ·  \(sign)\(fmt(abs(dev.delta), decimals)) \(unit)")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
                    .padding(.bottom, V2.Space.sm)
            }
        }
    }

    @ViewBuilder
    private var skinTempRow: some View {
        VStack(alignment: .leading, spacing: V2.Space.xxs) {
            let dev = row?.skinTempDevC
            V2StatRow(title: "Skin temperature",
                      value: dev.map { UnitFormatter.temperatureDeltaFromCelsius($0, unit: temperatureUnit) } ?? "—")
            if let dev, let rel = RecoveryScorer.skinTempRelative(deviationC: dev) {
                Text(skinTierLabel(rel.tier) + "  ·  vs your baseline")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
                    .padding(.bottom, V2.Space.sm)
            }
        }
    }

    private func skinTierLabel(_ tier: SkinTempRelative.Tier) -> String {
        switch tier {
        case .warmer:  return "Warmer than typical"
        case .cooler:  return "Cooler than typical"
        case .typical: return "Within your typical range"
        }
    }

    // MARK: Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Charge trend") {
                V2Segmented(selection: $trendDays,
                            options: [(14, "14D"), (30, "30D")])
                    .frame(width: 132)
            }
            V2Surface {
                VStack(alignment: .leading, spacing: 0) {
                    if trendPoints.isEmpty {
                        Text("No Charge history yet for this window.")
                            .font(V2Font.body)
                            .foregroundStyle(V2.Color.textSecondary)
                            .padding(V2.Space.lg)
                    } else {
                        V2TrendChart(points: trendPoints,
                                     domain: .charge,
                                     style: .line,
                                     band: RecoveryScorer.bandRedMax...RecoveryScorer.bandYellowMax)
                            .padding(V2.Space.lg)
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
            Text("The band marks the moderate (yellow) zone; above it is green, below it red.")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .padding(.horizontal, V2.Space.gutter + V2.Space.xs)
        }
    }

    // MARK: Helpers

    private var hairline: some View {
        Rectangle()
            .fill(V2.Color.hairline)
            .frame(height: V2.Stroke.hairline)
    }

    private func fmt(_ v: Double, _ decimals: Int) -> String {
        String(format: "%.\(max(0, decimals))f", v)
    }

    /// Capitalise the first letter of an engine verdict ("above baseline, ..." → "Above baseline, ...").
    private func verdictLine(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
#endif
