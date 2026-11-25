#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - TrendsV2View — the v2 trends browser (over RangeReport)
//
// Honours the `V2DetailRoute.trends(String?)` contract. Two modes over one shared range control
// (30d / 90d / 6M / 1Y / All — the RangeReport export windows):
//
//   • metricKey == nil  → the multi-metric OVERVIEW. A calm scroll of the key physiological
//     metrics, each a card with a `V2Sparkline` of the windowed series and a first→second-half
//     trend `V2Delta`. Built once from `RangeReportEngine` via the shared `TrendsReportData`
//     glue over `Repository.days` (+ the stored daily-stress series). Each row taps through to
//     that metric's detail via `NavigationLink(value: .metric(key))`.
//
//   • metricKey != nil  → the FOCUS view for one catalog metric. Reads the metric's full
//     day→value history via `repo.exploreSeries`, windows it to the chosen range, and shows a
//     large `V2TrendChart` plus the RangeReport-style read: first-half vs second-half means,
//     the OLS slope-per-day, and the latest value. (Reached from `MetricDetailV2View`'s
//     "Trends — this metric across every range" link.)
//
// Every value is READ from the same data layer the v1 Trends screens read — nothing is scored or
// invented here. Dark-only, mono numerals, hairline rules, restrained per-domain accents.

struct TrendsV2View: View {
    let metricKey: String?

    init(metricKey: String?) { self.metricKey = metricKey }

    @EnvironmentObject private var repo: Repository

    /// The shared range window. Reuses the RangeReport export ranges (30/90/180/365/All).
    @State private var range: ReportRange = .days90

    // Overview: the stored daily stress series ("yyyy-MM-dd" → 0–3), for the Stress row (#457).
    // Same "my-whoop" series the Stress screen reads; empty until it arrives.
    @State private var stressByDay: [String: Double] = [:]

    // Focus: the full ascending day→value history for `metricKey`.
    @State private var focusSeries: [(day: String, value: Double)] = []
    @State private var focusLoaded = false

    // Unit preferences (display-only) — mirror MetricDetailV2View so the focus view honours
    // kg↔lb, °C↔°F and Effort 0–100↔0–21.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader(headerTitle, subtitle: headerSubtitle)

                rangeControl

                if metricKey == nil {
                    overviewContent
                } else {
                    focusContent
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) {
            if metricKey == nil { await loadStress() }
        }
        .task(id: focusTaskID) {
            if metricKey != nil { await loadFocus() }
        }
    }

    private var headerTitle: String {
        metricKey == nil ? "Trends" : (focusMetric?.title ?? metricKey ?? "Trends")
    }

    private var headerSubtitle: String {
        if metricKey == nil { return "Your metrics over time" }
        guard let m = focusMetric else { return metricKey ?? "" }
        let cat = MetricCatalog.categoryDisplayName(m.category)
        return m.source == "my-whoop" ? cat : "\(cat) · \(m.sourceLabel)"
    }

    // MARK: Range control

    private var rangeControl: some View {
        VStack(alignment: .leading, spacing: V2.Space.xs) {
            V2Segmented(selection: $range,
                        options: ReportRange.allCases.map { ($0, $0.label) })
            Text(range.longName)
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .padding(.horizontal, V2.Space.xs)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: - Overview (metricKey == nil)

    /// Today's local day key — the anchor for the range window (matches TrendsReportView).
    private var todayKey: String { repo.today?.day ?? Repository.localDayKey(Date()) }

    /// The full range report over the current window (pure; recomputed on body eval).
    private var overviewReport: RangeReport {
        TrendsReportData.report(for: range, days: repo.days, today: todayKey, stressByDay: stressByDay)
    }

    /// The key metrics surfaced in the overview, each mapped to its catalog key (for the
    /// `.metric` drill-in) and its v2 domain accent.
    private struct Featured {
        let metric: ReportMetric
        let key: String
        let domain: V2Domain
    }

    private let featured: [Featured] = [
        Featured(metric: .recovery,    key: "recovery",        domain: .charge),
        Featured(metric: .strain,      key: "strain",          domain: .effort),
        Featured(metric: .sleepHours,  key: "sleep_total_min", domain: .rest),
        Featured(metric: .hrv,         key: "hrv",             domain: .charge),
        Featured(metric: .restingHr,   key: "rhr",             domain: .stress),
        Featured(metric: .respRate,    key: "resp_rate",       domain: .health),
        Featured(metric: .skinTempDev, key: "skin_temp",       domain: .health),
        Featured(metric: .stress,      key: "stress",          domain: .stress),
    ]

    @ViewBuilder
    private var overviewContent: some View {
        let report = overviewReport
        let present = featured.filter { report.stat($0.metric) != nil }
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Metrics") {
                Text("\(report.totalDays) days")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
            if present.isEmpty {
                V2Card {
                    Text("Not enough data in this range yet. Import more history to see trends.")
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(present.indices, id: \.self) { i in
                    overviewRow(present[i], report: report)
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    @ViewBuilder
    private func overviewRow(_ f: Featured, report: RangeReport) -> some View {
        let stat = report.stat(f.metric)
        let series = TrendsReportData.series(f.metric, from: repo.days,
                                             start: report.start, end: report.end,
                                             stressByDay: stressByDay)
        NavigationLink(value: V2DetailRoute.metric(f.key)) {
            V2Card(domain: f.domain) {
                VStack(alignment: .leading, spacing: V2.Space.sm) {
                    V2StatRow(title: f.metric.label,
                              value: stat.map { num(f.metric, $0.latest.value) } ?? "—",
                              unit: (stat == nil || f.metric.unit.isEmpty) ? nil : f.metric.unit,
                              delta: stat.map { trendDelta($0, f.metric) })
                    if series.count >= 2 {
                        V2Sparkline(values: series, domain: f.domain, filled: true)
                    }
                    if let stat {
                        Text(overviewCaption(stat, f.metric))
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "avg 62 · 90d · 128 days" style caption under the sparkline.
    private func overviewCaption(_ stat: MetricRangeStat, _ metric: ReportMetric) -> String {
        let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
        return "avg \(num(metric, stat.mean))\(unit)  ·  \(stat.n) days"
    }

    /// First→second-half trend as a literal-direction `V2Delta` (up = rising). Valence is
    /// deliberately not coloured here — the arrow shows which way the metric moved.
    private func trendDelta(_ stat: MetricRangeStat, _ metric: ReportMetric) -> V2Delta {
        let dir: V2Delta.Direction
        switch stat.trend {
        case .rising:  dir = .up
        case .falling: dir = .down
        case .flat:    dir = .flat
        }
        return V2Delta(value: num(metric, abs(stat.halfDelta)), direction: dir)
    }

    private func num(_ metric: ReportMetric, _ v: Double) -> String {
        metric.usesOneDecimal ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }

    private func loadStress() async {
        let pts = await repo.series(key: "stress", source: "my-whoop")
        stressByDay = Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
    }

    // MARK: - Focus (metricKey != nil)

    private var focusTaskID: String { "\(metricKey ?? "")|\(repo.refreshSeq)" }

    /// The catalog descriptor for the focus key (first source wins — matches Explore's dedupe).
    private var focusMetric: MetricDescriptor? {
        metricKey.flatMap { key in MetricCatalog.all.first { $0.key == key } }
    }

    /// The v2 domain accent for the focus metric (mirrors MetricDetailV2View's mapping).
    private var focusDomain: V2Domain {
        switch focusMetric?.category {
        case "Charge":       return .charge
        case "Effort":       return .effort
        case "Rest", "Mind": return .rest
        case "Health":       return .health
        default:
            switch metricKey {
            case "rhr", "max_hr", "stress", "body_fat": return .stress
            default:                                    return .charge
            }
        }
    }

    private func loadFocus() async {
        guard let m = focusMetric else { focusLoaded = true; return }
        focusSeries = await repo.exploreSeries(key: m.key, source: m.source)
        focusLoaded = true
    }

    @ViewBuilder
    private var focusContent: some View {
        if focusMetric == nil {
            focusPlaceholder("This metric isn't in the catalog.")
        } else if !focusLoaded {
            focusPlaceholder("Reading your \(headerTitle.lowercased())…")
        } else if let stats = focusStats, stats.n >= 2 {
            focusChartCard
            focusStatsCard(stats)
        } else {
            focusPlaceholder("Not enough data in this range yet.")
        }
    }

    private func focusPlaceholder(_ text: String) -> some View {
        V2Card {
            Text(text)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Focus windowing / stats

    /// The focus series, sorted ascending and clipped to the chosen trailing window.
    private var windowedFocus: [(day: String, value: Double)] {
        let sorted = focusSeries.sorted { $0.day < $1.day }
        guard let days = range.days else { return sorted }
        guard let lastDay = sorted.last?.day, let last = Self.parseDay(lastDay) else { return sorted }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return sorted.filter { Self.parseDay($0.day).map { $0 >= cutoff } ?? false }
    }

    /// RangeReport-style summary of the windowed focus series: mean, the first/second-half split
    /// (mid = n/2, the back half keeps the odd point, exactly as RangeReportEngine), the OLS
    /// slope-per-day, latest, and the min/max.
    private struct FocusStats {
        let n: Int
        let mean: Double
        let firstMean: Double
        let secondMean: Double
        let slope: Double
        let latest: (day: String, value: Double)?
        let lo: Double
        let hi: Double
        var halfDelta: Double { secondMean - firstMean }
    }

    private var focusStats: FocusStats? {
        let pts = windowedFocus
        let vals = pts.map(\.value)
        guard !vals.isEmpty else { return nil }
        let n = vals.count
        let mean = vals.reduce(0, +) / Double(n)
        let mid = n / 2
        let firstMean = mid > 0 ? vals[0..<mid].reduce(0, +) / Double(mid) : mean
        let secondMean = (n - mid) > 0 ? vals[mid..<n].reduce(0, +) / Double(n - mid) : mean
        return FocusStats(n: n, mean: mean, firstMean: firstMean, secondMean: secondMean,
                          slope: ols(vals), latest: pts.last,
                          lo: vals.min() ?? mean, hi: vals.max() ?? mean)
    }

    /// Typical-range band (mean ± 1σ) behind the focus chart, when the window has spread.
    private var focusBand: ClosedRange<Double>? {
        guard let s = focusStats, s.n >= 2 else { return nil }
        let vals = windowedFocus.map(\.value)
        let variance = vals.reduce(0) { $0 + ($1 - s.mean) * ($1 - s.mean) } / Double(vals.count)
        let sd = variance.squareRoot()
        guard sd > 0 else { return nil }
        return (s.mean - sd)...(s.mean + sd)
    }

    private var focusChartPoints: [V2ChartPoint] {
        windowedFocus.compactMap { r in
            Self.parseDay(r.day).map { V2ChartPoint(date: $0, value: r.value) }
        }
    }

    // MARK: Focus cards

    private var focusChartCard: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader(headerTitle) {
                if let stats = focusStats {
                    Text("\(stats.n) days")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                }
            }
            V2Surface(domain: focusDomain) {
                VStack(alignment: .leading, spacing: 0) {
                    if focusChartPoints.count >= 2 {
                        V2TrendChart(points: focusChartPoints, domain: focusDomain,
                                     style: .area, band: focusBand)
                            .padding(V2.Space.lg)
                    } else {
                        Text("Not enough data in this range.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                            .padding(V2.Space.lg)
                    }
                }
            }
            Text("The band marks the typical range (average ± one standard deviation).")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .padding(.horizontal, V2.Space.xs)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    /// One row in the focus stats card.
    private struct StatLine {
        let title: String
        let number: String
        let unit: String?
        let delta: V2Delta?
    }

    /// The ordered stat rows for the focus card: latest, average, the first/second-half split
    /// (with its change chip), the slope-per-day, then the low/high.
    private func focusRows(_ s: FocusStats) -> [StatLine] {
        var rows: [StatLine] = []
        if let l = s.latest {
            let p = parts(l.value)
            rows.append(StatLine(title: "Latest", number: p.number, unit: p.unit, delta: nil))
        }
        let mp = parts(s.mean)
        rows.append(StatLine(title: "Average", number: mp.number, unit: mp.unit, delta: nil))
        let fp = parts(s.firstMean)
        rows.append(StatLine(title: "First half", number: fp.number, unit: fp.unit, delta: nil))
        let sp = parts(s.secondMean)
        rows.append(StatLine(title: "Second half", number: sp.number, unit: sp.unit,
                             delta: halfDeltaDelta(s)))
        rows.append(StatLine(title: "Slope", number: slopeText(s.slope), unit: "per day", delta: nil))
        let lp = parts(s.lo)
        rows.append(StatLine(title: "Low", number: lp.number, unit: lp.unit, delta: nil))
        let hp = parts(s.hi)
        rows.append(StatLine(title: "High", number: hp.number, unit: hp.unit, delta: nil))
        return rows
    }

    private func focusStatsCard(_ s: FocusStats) -> some View {
        let rows = focusRows(s)
        return VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Over this range") {
                trendChip(s)
            }
            V2Card(domain: focusDomain) {
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        if i > 0 { hairline }
                        V2StatRow(title: rows[i].title, value: rows[i].number,
                                  unit: rows[i].unit, delta: rows[i].delta)
                    }
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    /// The first→second-half change as a literal-direction `V2Delta` on the Second-half row.
    private func halfDeltaDelta(_ s: FocusStats) -> V2Delta {
        let floor = Swift.max(abs(s.mean) * 0.02, 1e-9)
        let dir: V2Delta.Direction = s.halfDelta > floor ? .up : (s.halfDelta < -floor ? .down : .flat)
        return V2Delta(value: deltaMag(s.halfDelta), direction: dir)
    }

    /// A valence-aware trend chip (up/down + good/bad from the metric's `higherIsBetter`).
    private func trendChip(_ s: FocusStats) -> V2Chip {
        let floor = Swift.max(abs(s.mean) * 0.02, 1e-9)
        if s.halfDelta > floor {
            return V2Chip("Trending up", tone: valence(rising: true))
        } else if s.halfDelta < -floor {
            return V2Chip("Trending down", tone: valence(rising: false))
        } else {
            return V2Chip("Holding steady", tone: .neutral)
        }
    }

    private func valence(rising: Bool) -> V2Tone {
        guard let hib = focusMetric?.higherIsBetter else { return .neutral }
        return (rising == hib) ? .positive : .caution
    }

    // MARK: Focus formatting (unit-pref aware, via the catalog descriptor)

    /// Full formatted value ("<number> <unit>") routed through the unit prefs.
    private func full(_ v: Double) -> String {
        focusMetric?.format(v, system: unitSystem, temperature: temperatureUnit, effortScale: effortScale)
            ?? String(format: "%.0f", v)
    }

    /// Split a formatted value into (number, unit?) so the row can render the unit smaller.
    private func parts(_ v: Double) -> (number: String, unit: String?) {
        let s = full(v)
        guard let sp = s.firstIndex(of: " ") else { return (s, nil) }
        let unit = String(s[s.index(after: sp)...])
        return (String(s[..<sp]), unit.isEmpty ? nil : unit)
    }

    /// Signed magnitude of a delta (kg/°C/effort scale correctly via `formatDelta`).
    private func deltaMag(_ v: Double) -> String {
        focusMetric?.formatDelta(abs(v), system: unitSystem, temperature: temperatureUnit,
                                 effortScale: effortScale) ?? String(format: "%.1f", abs(v))
    }

    /// Slope-per-day: signed converted magnitude. A negligible slope reads as "±0"; if the
    /// descriptor rounds a small-but-real slope to zero, fall back to a finer raw figure so the
    /// per-day movement is still visible.
    private func slopeText(_ slope: Double) -> String {
        guard abs(slope) >= 0.005 else { return "±0" }
        let sign = slope > 0 ? "+" : "−"
        let mag = deltaMag(slope)
        let numeric = Double(mag.filter { $0.isNumber || $0 == "." }) ?? 0
        if numeric == 0 { return String(format: "%@%.2f", sign, abs(slope)) }
        return "\(sign)\(mag)"
    }

    // MARK: Helpers

    private var hairline: some View {
        Rectangle()
            .fill(V2.Color.hairline)
            .frame(height: V2.Stroke.hairline)
    }

    private func ols(_ v: [Double]) -> Double {
        let n = v.count
        guard n >= 2 else { return 0 }
        let meanX = Double(n - 1) / 2.0
        let meanY = v.reduce(0, +) / Double(n)
        var num = 0.0, den = 0.0
        for (i, val) in v.enumerated() {
            let dx = Double(i) - meanX
            num += dx * (val - meanY)
            den += dx * dx
        }
        return den == 0 ? 0 : num / den
    }

    // Day parsing (UTC / POSIX, mirrors MetricDetailV2View).
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDay(_ day: String) -> Date? { dayParser.date(from: day) }
}
#endif
