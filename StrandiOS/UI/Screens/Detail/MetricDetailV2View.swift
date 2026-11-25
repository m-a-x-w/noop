#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - MetricDetailV2View — one catalog metric's depth surface
//
// The v2 replacement for MetricExplorer's per-metric detail. Keyed by `MetricDescriptor.key`
// (the `V2DetailRoute.metric` contract), it reads the metric's full day→value history via
// `repo.exploreSeries`, then shows — for a chosen range (7D / 30D / 90D / 1Y):
//   • the latest value as a V2BigNumber (+ small unit) with a baseline-delta chip,
//   • a V2TrendChart of the windowed series with a faint typical-range band (mean ± 1σ),
//   • a stats strip (mean / min / max / trend direction) as V2StatRow rows,
//   • a pin toggle writing the shared @AppStorage("v2.explore.pinned") CSV,
//   • a link into Relationships (what moves this metric).
// Values format through `MetricDescriptor.format(_:system:temperature:effortScale:)` so unit
// prefs (kg↔lb, °C↔°F, Effort 0–100↔0–21) are honoured. Dark-only, mono, calm.

struct MetricDetailV2View: View {
    let metricKey: String

    init(metricKey: String) { self.metricKey = metricKey }

    @EnvironmentObject private var repo: Repository

    // Unit preferences (display-only) — mirror the v1 MetricDetailView routing.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    // Pinned metrics, shared with ExploreV2Host's quick-access strip.
    @AppStorage("v2.explore.pinned") private var pinnedCSV = ""

    @State private var range: MetricRange = .d30
    /// Full ascending day→value history for this metric.
    @State private var series: [(day: String, value: Double)] = []
    @State private var loaded = false

    // MARK: Descriptor

    /// The catalog descriptor for this key (first source wins — matches Explore's dedupe-by-key).
    private var metric: MetricDescriptor? {
        MetricCatalog.all.first { $0.key == metricKey }
    }

    private var title: String { metric?.title ?? metricKey }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The domain accent world for this metric (mirrors the v1 category → world mapping, mapped
    /// onto the five v2 domains). Colour communicates category only.
    private var domain: V2Domain {
        switch metric?.category {
        case "Charge":       return .charge
        case "Effort":       return .effort
        case "Rest", "Mind": return .rest
        case "Health":       return .health
        default: // Heart / Nutrition — risk-style metrics read as stress, the rest as charge.
            switch metricKey {
            case "rhr", "max_hr", "stress", "body_fat": return .stress
            default:                                    return .charge
            }
        }
    }

    // MARK: Formatting

    /// Full formatted value string (number + unit), routed through unit prefs.
    private func full(_ v: Double) -> String {
        metric?.format(v, system: unitSystem, temperature: temperatureUnit, effortScale: effortScale)
            ?? String(format: "%.0f", v)
    }

    /// Split a formatted value into (number, unit?) so the hero can render the unit smaller. Every
    /// converted unit string is "<number> <unit>" (single space); unit-less metrics have no space.
    private func parts(_ v: Double) -> (number: String, unit: String?) {
        let s = full(v)
        guard let sp = s.firstIndex(of: " ") else { return (s, nil) }
        let unit = String(s[s.index(after: sp)...])
        return (String(s[..<sp]), unit.isEmpty ? nil : unit)
    }

    /// Magnitude of a delta (no sign — the caller renders the sign / arrow).
    private func deltaText(_ v: Double) -> String {
        metric?.formatDelta(abs(v), system: unitSystem, temperature: temperatureUnit,
                            effortScale: effortScale) ?? String(format: "%.0f", abs(v))
    }

    // MARK: Windowing / stats

    private var windowed: [(day: String, value: Double)] {
        guard let days = range.days else { return series }
        guard let lastDay = series.last?.day, let last = Self.parseDay(lastDay) else { return series }
        let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
        return series.filter { Self.parseDay($0.day).map { $0 >= cutoff } ?? false }
    }

    private var windowValues: [Double] { windowed.map(\.value) }

    private var latest: (day: String, value: Double)? { series.last }

    private var mean: Double? {
        let v = windowValues
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    /// Baseline delta: latest − windowed mean. Signed.
    private var baselineDelta: Double? {
        guard let m = mean, let l = latest?.value else { return nil }
        return l - m
    }

    /// Trend direction over the window, from the first-half vs second-half mean split with a
    /// noise floor (2% of |mean|, or a tiny epsilon) so a near-level series reads as flat.
    private var trend: MetricTrend {
        let v = windowValues
        guard v.count >= 4, let m = mean else { return .flat }
        let mid = v.count / 2
        let firstMean = v[0..<mid].reduce(0, +) / Double(mid)
        let secondMean = v[mid...].reduce(0, +) / Double(v.count - mid)
        let delta = secondMean - firstMean
        let floor = Swift.max(abs(m) * 0.02, 1e-6)
        if delta > floor { return .rising }
        if delta < -floor { return .falling }
        return .flat
    }

    /// Typical-range band (mean ± 1σ) for the trend chart, when the window has spread.
    private var band: ClosedRange<Double>? {
        let v = windowValues
        guard v.count >= 2, let m = mean else { return nil }
        let variance = v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)
        let sd = variance.squareRoot()
        guard sd > 0 else { return nil }
        return (m - sd)...(m + sd)
    }

    private var chartPoints: [V2ChartPoint] {
        windowed.compactMap { row in
            Self.parseDay(row.day).map { V2ChartPoint(date: $0, value: row.value) }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader(title, subtitle: subtitle) { pinButton }

                V2Segmented(selection: $range, options: MetricRange.allCases.map { ($0, $0.label) })
                    .padding(.horizontal, V2.Space.gutter)

                if !loaded {
                    placeholder("Reading your \(title.lowercased())…")
                } else if series.isEmpty {
                    placeholder("No history yet. Import your data to explore this metric.")
                } else {
                    heroCard
                    chartCard
                    statsCard
                    relationshipsLink
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: taskID) { await load() }
    }

    private var taskID: String { "\(metricKey)|\(repo.refreshSeq)" }

    private func load() async {
        guard let m = metric else { loaded = true; return }
        series = await repo.exploreSeries(key: m.key, source: m.source)
        loaded = true
    }

    // MARK: Header pieces

    private var subtitle: String {
        guard let m = metric else { return metricKey }
        let cat = MetricCatalog.categoryDisplayName(m.category)
        return m.source == "my-whoop" ? cat : "\(cat) · \(m.sourceLabel)"
    }

    private var pinButton: some View {
        Button(action: togglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(V2Font.title)
                .foregroundStyle(isPinned ? domain.accent : V2.Color.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Unpin metric" : "Pin metric")
    }

    private var isPinned: Bool { pinnedKeys.contains(metricKey) }

    private var pinnedKeys: [String] {
        pinnedCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func togglePin() {
        var keys = pinnedKeys
        if let i = keys.firstIndex(of: metricKey) { keys.remove(at: i) } else { keys.append(metricKey) }
        pinnedCSV = keys.joined(separator: ",")
    }

    // MARK: Hero

    private var heroCard: some View {
        V2Card(domain: domain) {
            VStack(alignment: .leading, spacing: V2.Space.md) {
                if let l = latest {
                    let p = parts(l.value)
                    V2BigNumber(value: p.number, unit: p.unit, domain: domain)
                    if let d = baselineDelta {
                        baselineChip(d)
                    }
                    if let day = Self.parseDay(l.day) {
                        Text("as of \(Self.longDate(day))")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                } else {
                    V2BigNumber(value: "—", domain: domain)
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    /// The signed baseline-delta chip, toned by whether the move is good (uses higherIsBetter).
    private func baselineChip(_ delta: Double) -> some View {
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "±")
        let tone: V2Tone = {
            guard let hib = metric?.higherIsBetter, abs(delta) > 1e-6 else { return .neutral }
            let good = (delta > 0) == hib
            return good ? .positive : .caution
        }()
        return V2Chip("\(sign)\(deltaText(delta)) vs \(range.label) avg", tone: tone)
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Trend")
            V2Surface {
                VStack(alignment: .leading, spacing: 0) {
                    if chartPoints.count >= 2 {
                        V2TrendChart(points: chartPoints, domain: domain, style: .line, band: band)
                            .padding(V2.Space.lg)
                    } else {
                        Text("Not enough data in this range.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                            .padding(V2.Space.lg)
                    }
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Statistics") {
                Text("\(windowValues.count) days")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
            V2Card {
                VStack(spacing: 0) {
                    if let m = mean {
                        let p = parts(m)
                        V2StatRow(title: "Mean", value: p.number, unit: p.unit)
                    }
                    if let lo = windowValues.min() {
                        let p = parts(lo)
                        V2StatRow(title: "Minimum", value: p.number, unit: p.unit)
                    }
                    if let hi = windowValues.max() {
                        let p = parts(hi)
                        V2StatRow(title: "Maximum", value: p.number, unit: p.unit)
                    }
                    V2StatRow(title: "Trend", value: trend.word, delta: trend.delta)
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Relationships

    private var relationshipsLink: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Compare")
            V2List {
                NavigationLink(value: V2DetailRoute.relationships) {
                    V2ListRow(title: "Relationships",
                              subtitle: "What moves this metric",
                              chevron: true)
                }
                .buttonStyle(.plain)
                NavigationLink(value: V2DetailRoute.trends(metricKey)) {
                    V2ListRow(title: "Trends",
                              subtitle: "This metric across every range",
                              chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Placeholder

    private func placeholder(_ text: String) -> some View {
        V2Card {
            Text(text)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Day parsing (UTC / POSIX, mirrors the v1 strandDayParser)

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDay(_ day: String) -> Date? { dayParser.date(from: day) }

    private static let longFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static func longDate(_ d: Date) -> String { longFmt.string(from: d) }
}

// MARK: - Range control

private enum MetricRange: Int, CaseIterable, Hashable {
    case d7 = 7, d30 = 30, d90 = 90, y1 = 365

    var label: String {
        switch self {
        case .d7:  return "7D"
        case .d30: return "30D"
        case .d90: return "90D"
        case .y1:  return "1Y"
        }
    }

    /// Trailing days the window spans (nil would mean "all", but every range here is finite).
    var days: Int? { rawValue }
}

// MARK: - Trend direction

private enum MetricTrend {
    case rising, falling, flat

    var word: String {
        switch self {
        case .rising:  return "Rising"
        case .falling: return "Falling"
        case .flat:    return "Flat"
        }
    }

    /// A literal-direction arrow chip (up/down/flat). Good/bad valence lives on the hero chip.
    var delta: V2Delta {
        switch self {
        case .rising:  return V2Delta(value: "", direction: .up)
        case .falling: return V2Delta(value: "", direction: .down)
        case .flat:    return V2Delta(value: "", direction: .flat)
        }
    }
}
#endif
