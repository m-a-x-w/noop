#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - SleepV2View — the v2 sleep detail
//
// Rebuilt fresh on the read layer (UI-V2-DATA §5). A drill-in for ONE night: the last-night session
// for `date` (its main-night GROUP, bridging briefly-interrupted fragments), rendered as a hero
// summary at the top (time asleep, efficiency, Rest score, sleep debt) with the full analysis below —
// a `V2Hypnogram`, per-stage totals, timings, the need/debt ledger, and a history range with a
// nightly-duration `V2TrendChart` + a Rest-score `V2HeatStrip`. Dark-only, mono, restrained violet
// (`.rest`) accent. `init(date:)` is frozen by the V2DetailRoute contract.

struct SleepV2View: View {
    @EnvironmentObject private var repo: Repository

    /// The night in focus (its calendar wake-day). Steppable via the header.
    @State private var selectedDate: Date

    /// Rest score (`sleep_performance`, 0–100) by day key — loaded off the metric resolver.
    @State private var restByDay: [String: Double] = [:]
    /// Learned habitual midsleep (local seconds) so the main-night pick matches the analytics rollup.
    @State private var habitual: Int?
    /// History window for the trend + heat strip, in nights.
    @State private var rangeDays: Int = 30

    init(date: Date) {
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: date))
    }

    // MARK: Day / session resolution

    private static let dayKeyFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var dayKey: String { Self.dayKeyFmt.string(from: selectedDate) }

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// The DailyMetric row for the selected wake-day (sleep-derived columns + latencies).
    private var dayMetric: DailyMetric? { repo.days.last { $0.day == dayKey } }

    /// Every cached block grouped by the calendar day it ENDS on (mirrors SleepView's nav grouping).
    private var sessionsForDay: [CachedSleepSession] {
        let cal = Calendar.current
        let target = cal.startOfDay(for: selectedDate)
        return repo.sleeps.filter {
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.endTs))) == target
        }
    }

    /// The night's MAIN-night group: the winning block plus adjacent fragments bridged into it, so a
    /// biphasic / briefly-interrupted night reads as one continuous sleep (SleepStageTotals #561).
    private var nightGroup: [CachedSleepSession] {
        let day = sessionsForDay
        guard !day.isEmpty else { return [] }
        let blocks = day.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) }
        guard let idx = SleepStageTotals.mainNightGroupIndices(
            blocks, offsetSec: TimeZone.current.secondsFromGMT(), habitualMidsleepSec: habitual)
        else { return day.sorted { $0.effectiveStartTs < $1.effectiveStartTs } }
        return idx.map { day[$0] }.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
    }

    /// Summed stage minutes across the main-night group (asleep / in-bed / per-stage).
    private var stageMinutes: SleepStageTotals.Minutes {
        var total = SleepStageTotals.Minutes()
        for s in nightGroup {
            if let m = SleepStageTotals.minutes(fromStagesJSON: s.stagesJSON) {
                total.awake += m.awake; total.light += m.light
                total.deep += m.deep; total.rem += m.rem
            }
        }
        return total
    }

    /// Total time asleep (min): the decoded stage total, falling back to the DailyMetric column.
    private var totalSleepMin: Double {
        let m = stageMinutes
        return m.asleep > 0 ? m.asleep : (dayMetric?.totalSleepMin ?? 0)
    }

    /// Efficiency as a 0–1 fraction: decoded asleep / in-bed when available, else the DailyMetric
    /// column (which is stored as a 0–100 percentage, so normalise it back to 0–1 here).
    private var efficiency: Double {
        let m = stageMinutes
        if m.inBed > 0 { return m.asleep / m.inBed }
        guard let e = dayMetric?.efficiency else { return 0 }
        return e > 1 ? e / 100 : e
    }

    private var restScore: Double? { restByDay[dayKey] }

    private var debtLedger: SleepDebtLedger {
        SleepDebt.ledger(series: repo.days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) })
    }

    private var hasNight: Bool { !nightGroup.isEmpty && totalSleepMin > 0 }

    private var canGoNext: Bool {
        selectedDate < Calendar.current.startOfDay(for: Date())
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Sleep",
                               date: $selectedDate,
                               canGoNext: canGoNext,
                               onPrev: { step(-1) },
                               onNext: { step(1) })

                if hasNight {
                    summarySection
                    hypnogramSection
                    stagesSection
                    timingsSection
                    debtSection
                    historySection
                } else {
                    emptyCard
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) { await load() }
    }

    private func step(_ n: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: n, to: selectedDate) else { return }
        if n > 0 && d > Calendar.current.startOfDay(for: Date()) { return }
        selectedDate = d
    }

    private func load() async {
        let series = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
        var map: [String: Double] = [:]
        for p in series { map[p.day] = p.value }
        restByDay = map
        habitual = await repo.habitualMidsleepSec()
    }

    // MARK: Summary (hero)

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Last night") {
                if let rest = restScore {
                    V2Chip("Rest \(Int(rest.rounded()))", tone: restTone(rest))
                }
            }
            V2Card(domain: .rest) {
                VStack(alignment: .leading, spacing: V2.Space.lg) {
                    HStack(alignment: .firstTextBaseline, spacing: V2.Space.xl) {
                        V2BigNumber(value: hhmm(totalSleepMin), label: "Asleep",
                                    domain: .rest, size: 52)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: V2.Space.xxs) {
                            Text("\(Int((efficiency * 100).rounded()))%")
                                .font(V2Font.numeral(22))
                                .foregroundStyle(V2.Color.textPrimary)
                            Text("Efficiency")
                                .font(V2Font.overline)
                                .tracking(V2Font.overlineTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(V2.Color.textTertiary)
                        }
                    }
                    Divider().overlay(V2.Color.hairline)
                    VStack(spacing: 0) {
                        V2StatRow(title: "Time in bed", value: hhmm(stageMinutes.inBed))
                        V2StatRow(title: "Sleep need",
                                  value: hhmm(debtLedger.needMin),
                                  delta: needDelta)
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    /// Actual-vs-need signed chip on the need row (how tonight compares to the personal need).
    private var needDelta: V2Delta {
        let diff = totalSleepMin - debtLedger.needMin
        if abs(diff) < 15 { return V2Delta(value: "on target", direction: .flat) }
        return V2Delta(value: hhmmShort(abs(diff)),
                       direction: diff >= 0 ? .up : .down)
    }

    // MARK: Hypnogram

    private var hypnogramSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Hypnogram")
            V2Card(domain: .rest) {
                VStack(alignment: .leading, spacing: V2.Space.md) {
                    let segs = hypnogramSegments
                    if segs.isEmpty {
                        Text("No stage timeline for this night.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    } else {
                        V2Hypnogram(segments: segs)
                        HStack {
                            Text(clock(nightGroup.first?.effectiveStartTs))
                            Spacer()
                            Text(clock(nightGroup.last?.endTs))
                        }
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                        stageLegend
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private var stageLegend: some View {
        HStack(spacing: V2.Space.lg) {
            legendDot("Deep", .deep)
            legendDot("REM", .rem)
            legendDot("Light", .light)
            legendDot("Awake", .awake)
        }
    }

    private func legendDot(_ label: String, _ stage: SleepStage) -> some View {
        HStack(spacing: V2.Space.xs) {
            Circle()
                .fill(V2ChartScale.sleepStage(stage))
                .frame(width: 7, height: 7)
            Text(label)
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textSecondary)
        }
    }

    // MARK: Stages (stacked bar + totals)

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Stages")
            V2Card {
                VStack(alignment: .leading, spacing: V2.Space.md) {
                    StageBar(minutes: stageMinutes)
                    VStack(spacing: 0) {
                        stageRow("Deep", .deep, stageMinutes.deep)
                        stageRow("REM", .rem, stageMinutes.rem)
                        stageRow("Light", .light, stageMinutes.light)
                        stageRow("Awake", .awake, stageMinutes.awake)
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private func stageRow(_ label: String, _ stage: SleepStage, _ minutes: Double) -> some View {
        let inBed = stageMinutes.inBed
        let pct = inBed > 0 ? Int((minutes / inBed * 100).rounded()) : 0
        return V2StatRow(title: label, value: hhmmShort(minutes), unit: "\(pct)%")
    }

    // MARK: Timings

    private var timingsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Timings")
            V2Card {
                VStack(spacing: 0) {
                    V2StatRow(icon: "moon.fill", title: "Bedtime",
                              value: clock(nightGroup.first?.effectiveStartTs))
                    V2StatRow(icon: "sunrise.fill", title: "Wake",
                              value: clock(nightGroup.last?.endTs))
                    if let sol = dayMetric?.solMin {
                        V2StatRow(icon: "hourglass", title: "Sleep latency",
                                  value: "\(Int(sol.rounded()))", unit: "min")
                    }
                    if let rem = dayMetric?.remLatencyMin {
                        V2StatRow(icon: "hourglass.bottomhalf.filled", title: "REM latency",
                                  value: "\(Int(rem.rounded()))", unit: "min")
                    }
                    if let waso = dayMetric?.wasoMin {
                        V2StatRow(icon: "eye", title: "Awake after onset",
                                  value: "\(Int(waso.rounded()))", unit: "min")
                    }
                    if let dist = dayMetric?.disturbances {
                        V2StatRow(icon: "waveform.path", title: "Disturbances",
                                  value: "\(dist)")
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    // MARK: Sleep debt

    private var debtSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Sleep debt") {
                V2Chip(debtHeadline, tone: debtTone)
            }
            V2Card(domain: .rest) {
                VStack(alignment: .leading, spacing: V2.Space.md) {
                    Text(debtCopy)
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        V2StatRow(title: "Balance", value: signedHHMM(debtLedger.balanceMin))
                        V2StatRow(title: "Nightly need", value: hhmm(debtLedger.needMin))
                        V2StatRow(title: "Nights counted", value: "\(debtLedger.nightCount)")
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private var debtHeadline: String {
        if debtLedger.magnitudeMin < SleepDebt.onTargetBandMin { return "On target" }
        return debtLedger.isDebt ? "Debt \(hhmmShort(debtLedger.magnitudeMin))"
                                 : "Surplus \(hhmmShort(debtLedger.magnitudeMin))"
    }

    private var debtTone: V2Tone {
        if debtLedger.magnitudeMin < SleepDebt.onTargetBandMin { return .neutral }
        return debtLedger.isDebt ? .negative : .positive
    }

    private var debtCopy: String {
        if debtLedger.magnitudeMin < SleepDebt.onTargetBandMin {
            return "You're on track — recent nights net out against your \(hhmmShort(debtLedger.needMin)) need."
        }
        return debtLedger.isDebt
            ? "You're carrying \(hhmmShort(debtLedger.magnitudeMin)) of sleep debt over the last \(debtLedger.nightCount) nights."
            : "You're \(hhmmShort(debtLedger.magnitudeMin)) ahead of your need over the last \(debtLedger.nightCount) nights."
    }

    // MARK: History (trend + heat strip)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("History") {
                V2Segmented(selection: $rangeDays,
                            options: [(14, "14N"), (30, "30N"), (90, "90N")])
                    .frame(width: 168)
            }
            V2Card {
                VStack(alignment: .leading, spacing: V2.Space.lg) {
                    VStack(alignment: .leading, spacing: V2.Space.xs) {
                        Text("Nightly sleep")
                            .font(V2Font.overline)
                            .tracking(V2Font.overlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(V2.Color.textTertiary)
                        if let avg = averageHours {
                            Text("Avg \(hhmm(avg * 60))")
                                .font(V2Font.caption)
                                .foregroundStyle(V2.Color.textSecondary)
                        }
                    }
                    if durationPoints.isEmpty {
                        Text("Not enough history yet.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        V2TrendChart(points: durationPoints, domain: .rest, style: .bars)
                    }
                    Divider().overlay(V2.Color.hairline)
                    VStack(alignment: .leading, spacing: V2.Space.sm) {
                        Text("Rest score by night")
                            .font(V2Font.overline)
                            .tracking(V2Font.overlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(V2.Color.textTertiary)
                        V2HeatStrip(days: heatCells)
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private var rangeCutoff: Date {
        Calendar.current.date(byAdding: .day, value: -rangeDays,
                              to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
    }

    private var durationPoints: [V2ChartPoint] {
        repo.days.compactMap { d in
            guard let mins = d.totalSleepMin, mins > 0,
                  let date = Self.dayKeyFmt.date(from: d.day), date >= rangeCutoff
            else { return nil }
            return V2ChartPoint(date: date, value: mins / 60.0)
        }
    }

    private var averageHours: Double? {
        let vals = durationPoints.map(\.value)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var heatCells: [V2HeatCell] {
        repo.days.compactMap { d in
            guard let date = Self.dayKeyFmt.date(from: d.day), date >= rangeCutoff else { return nil }
            return V2HeatCell(date: date, score: restByDay[d.day])
        }
    }

    // MARK: Empty state

    private var emptyCard: some View {
        V2Card(domain: .rest) {
            VStack(alignment: .leading, spacing: V2.Space.xs) {
                Text("No sleep recorded")
                    .font(V2Font.heading)
                    .foregroundStyle(V2.Color.textPrimary)
                Text("There's no main sleep session for this night. Step to another day, or wear your strap overnight to see stages here.")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Hypnogram decoding

    /// Absolute-epoch stage segments across the main-night group for `V2Hypnogram`
    /// (stage index: 0 awake · 1 rem · 2 light · 3 deep). Empty when only the imported minute-dict
    /// shape is available (no per-stage timeline to draw).
    private var hypnogramSegments: [V2SleepSegment] {
        var out: [V2SleepSegment] = []
        for s in nightGroup {
            guard let json = s.stagesJSON, let data = json.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            else { continue }
            for seg in arr {
                guard let start = (seg["start"] as? NSNumber)?.intValue,
                      let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                      let name = seg["stage"] as? String else { continue }
                let stageIdx: Int
                switch name {
                case "wake", "awake": stageIdx = 0
                case "rem": stageIdx = 1
                case "light": stageIdx = 2
                case "deep": stageIdx = 3
                default: continue
                }
                out.append(V2SleepSegment(
                    start: Date(timeIntervalSince1970: TimeInterval(start)),
                    end: Date(timeIntervalSince1970: TimeInterval(end)),
                    stage: stageIdx))
            }
        }
        return out
    }

    // MARK: Formatting

    /// Minutes → "6:48" (fixed mono numeral form for the hero).
    private func hhmm(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Minutes → "6h 48m" / "48m" (compact, for chips + stat values).
    private func hhmmShort(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Signed balance minutes → "+1h 20m" / "−0h 40m".
    private func signedHHMM(_ minutes: Double) -> String {
        let sign = minutes < 0 ? "−" : "+"
        return sign + hhmmShort(abs(minutes))
    }

    private func clock(_ ts: Int?) -> String {
        guard let ts else { return "—" }
        return Self.clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func restTone(_ score: Double) -> V2Tone {
        if score >= 67 { return .positive }
        if score >= 34 { return .caution }
        return .negative
    }
}

// MARK: - StageBar — a hairline stacked bar of the night's stage proportions

private struct StageBar: View {
    let minutes: SleepStageTotals.Minutes

    /// Left→right: deep · rem · light · awake, each weighted by its share of in-bed time.
    private var segments: [(stage: SleepStage, value: Double)] {
        [(.deep, minutes.deep), (.rem, minutes.rem),
         (.light, minutes.light), (.awake, minutes.awake)]
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(1, minutes.inBed)
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { i in
                    let seg = segments[i]
                    if seg.value > 0 {
                        Rectangle()
                            .fill(V2ChartScale.sleepStage(seg.stage))
                            .frame(width: max(2, geo.size.width * seg.value / total))
                    }
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }
}
#endif
