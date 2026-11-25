#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - VitalsHealthV2View
//
// The full-day vitals + health record for one day. Reads the SAME data layer the v1
// VitalSignsSummary / TodayView RECOVERY-VITALS card reads (see docs/UI-V2-DATA.md §2,4,6):
//   • HRV / RHR / Resp / SpO2 / Skin temp from the day's `DailyMetric`, each compared to the
//     user's own personal baseline (`Baselines.foldHistory`/`deviation`), shown as `V2StatRow`s.
//   • An intraday `V2DayChart` of heart rate (SQL-bucketed) with a `V2Segmented` to swap in the
//     hourly HRV lens (RMSSD per waking hour, reusing the shipped `DaytimeStress` engine).
//   • A small health-record card (steps / active energy / workouts) so no capability is lost.
//
// Dark-only, mono, progressive: the surface shows the numbers, this screen shows the full day.
// The `init(date:)` signature is frozen by the `V2DetailRoute` contract.

struct VitalsHealthV2View: View {
    @EnvironmentObject var repo: Repository

    let date: Date

    init(date: Date) {
        self.date = date
        _selectedDate = State(initialValue: date)
    }

    /// The day currently shown; the header stepper walks it within [earliest … today].
    @State private var selectedDate: Date

    /// Intraday series (loaded async per selected day).
    @State private var hrPoints: [V2ChartPoint] = []
    @State private var hrvPoints: [V2ChartPoint] = []
    @State private var intradayLoaded = false

    /// Which intraday lens the day chart shows.
    @State private var chartMetric: IntradayMetric = .hr

    // Display-unit prefs (temperature is the only one that matters here). Dark-only ignores appearance.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }

    enum IntradayMetric: Hashable { case hr, hrv }

    // MARK: Day resolution

    private var dayKey: String { Repository.localDayKey(selectedDate) }
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }
    private var isToday: Bool { dayKey >= todayKey }
    private var canGoNext: Bool { dayKey < todayKey }

    /// The selected day's row (today-first when showing today).
    private var dayRow: DailyMetric? {
        if isToday { return repo.today ?? repo.days.last { $0.day == dayKey } }
        return repo.days.last { $0.day == dayKey }
    }

    /// Carry-over row for TODAY before tonight is scored: freshest day ≤ selected with any vital.
    private var carryRow: DailyMetric? {
        repo.days.last { $0.day <= dayKey && ($0.avgHrv != nil || $0.restingHr != nil || $0.respRateBpm != nil) }
    }

    /// A vital value for the day, carrying a prior reading forward only while showing an unscored today.
    private func resolve(_ kp: KeyPath<DailyMetric, Double?>) -> Double? {
        if let v = dayRow?[keyPath: kp] { return v }
        return isToday ? carryRow?[keyPath: kp] : nil
    }
    private func resolveRHR() -> Double? {
        if let v = dayRow?.restingHr { return Double(v) }
        return isToday ? carryRow?.restingHr.map(Double.init) : nil
    }

    // MARK: Baselines (history up to and including the selected day)

    private var histDays: [DailyMetric] { repo.days.filter { $0.day <= dayKey } }
    private var hrvState: BaselineState { Baselines.foldHistory(histDays.map(\.avgHrv), cfg: Baselines.hrvCfg) }
    private var rhrState: BaselineState {
        Baselines.foldHistory(histDays.map { $0.restingHr.map(Double.init) }, cfg: Baselines.restingHRCfg)
    }
    private var respState: BaselineState { Baselines.foldHistory(histDays.map(\.respRateBpm), cfg: Baselines.respCfg) }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Vitals",
                               date: $selectedDate,
                               canGoNext: canGoNext,
                               onPrev: { step(-1) },
                               onNext: { step(1) })

                intradaySection
                vitalsSection
                healthRecordSection
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(dayKey)|\(repo.refreshSeq)") { await loadHR() }
        // The hourly HRV lens needs the day's raw R-R, a heavier read, so load it lazily the first
        // time the user selects the HRV segment (and re-load when the day/refresh changes).
        .task(id: "\(dayKey)|\(chartMetric == .hrv)|\(repo.refreshSeq)") { await loadHRVIfNeeded() }
    }

    private func step(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        if delta > 0, Repository.localDayKey(next) > todayKey { return }
        selectedDate = next
    }

    // MARK: Intraday chart

    @ViewBuilder
    private var intradaySection: some View {
        let points = chartMetric == .hr ? hrPoints : hrvPoints
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Intraday")
            V2Surface(domain: .health) {
                VStack(alignment: .leading, spacing: V2.Space.md) {
                    V2Segmented(selection: $chartMetric,
                                options: [(.hr, "Heart rate"), (.hrv, "HRV")])
                    if points.count >= 2 {
                        V2DayChart(samples: points, domain: chartMetric == .hr ? .health : .charge)
                    } else {
                        intradayPlaceholder
                    }
                }
                .padding(V2.Space.lg)
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private var intradayPlaceholder: some View {
        Text(chartMetric == .hrv
             ? "Hourly HRV needs enough R-R beats through the day."
             : (intradayLoaded ? "No heart-rate data recorded this day." : "Reading the day…"))
            .font(V2Font.label)
            .foregroundStyle(V2.Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // MARK: Vitals rows

    @ViewBuilder
    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Vitals") {
                Text("vs baseline")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
            V2Card(domain: .health) {
                VStack(spacing: 0) {
                    vitalRow(icon: "waveform.path.ecg", title: "HRV",
                             value: resolve(\.avgHrv), unit: "ms", decimals: 0,
                             delta: devDelta(resolve(\.avgHrv), state: hrvState, higherIsBetter: true, decimals: 0))
                    hairline
                    vitalRow(icon: "heart.fill", title: "Resting HR",
                             value: resolveRHR(), unit: "bpm", decimals: 0,
                             delta: devDelta(resolveRHR(), state: rhrState, higherIsBetter: false, decimals: 0))
                    hairline
                    vitalRow(icon: "lungs.fill", title: "Respiratory rate",
                             value: resolve(\.respRateBpm), unit: "rpm", decimals: 1,
                             delta: devDelta(resolve(\.respRateBpm), state: respState, higherIsBetter: false, decimals: 1))
                    hairline
                    vitalRow(icon: "drop.fill", title: "Blood oxygen",
                             value: resolve(\.spo2Pct), unit: "%", decimals: 0, delta: nil)
                    hairline
                    skinTempRow
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    /// A single vital as a `V2StatRow`; "—" when the day has no reading.
    @ViewBuilder
    private func vitalRow(icon: String, title: String, value: Double?, unit: String,
                          decimals: Int, delta: V2Delta?) -> some View {
        if let value {
            V2StatRow(icon: icon, title: title,
                      value: fmt(value, decimals), unit: unit, delta: delta)
        } else {
            V2StatRow(icon: icon, title: title, value: "—")
        }
    }

    /// Skin temp is bimodal: an on-device ±deviation, or an absolute reading when imported.
    @ViewBuilder
    private var skinTempRow: some View {
        if let dc = resolve(\.skinTempDevC) {
            let absolute = VitalBands.isAbsoluteSkinTemp(dc)
            let text = absolute
                ? UnitFormatter.temperatureFromCelsius(dc, unit: temperatureUnit, decimals: 1)
                : UnitFormatter.temperatureDeltaFromCelsius(dc, unit: temperatureUnit, decimals: 1)
            V2StatRow(icon: "thermometer.medium", title: "Skin temp", value: text)
        } else {
            V2StatRow(icon: "thermometer.medium", title: "Skin temp", value: "—")
        }
    }

    // MARK: Health record

    @ViewBuilder
    private var healthRecordSection: some View {
        let steps = dayRow?.steps
        let kcal = dayRow?.activeKcalEst
        let workouts = dayRow?.exerciseCount
        if steps != nil || kcal != nil || (workouts ?? 0) > 0 {
            VStack(alignment: .leading, spacing: V2.Space.md) {
                V2SectionHeader("Health record")
                V2Card {
                    VStack(spacing: 0) {
                        if let steps {
                            V2StatRow(icon: "figure.walk", title: "Steps",
                                      value: fmt(Double(steps), 0))
                        }
                        if let kcal {
                            if steps != nil { hairline }
                            V2StatRow(icon: "flame.fill", title: "Active energy",
                                      value: fmt(kcal, 0), unit: "kcal")
                        }
                        if let workouts, workouts > 0 {
                            if steps != nil || kcal != nil { hairline }
                            V2StatRow(icon: "figure.run", title: "Workouts",
                                      value: "\(workouts)")
                        }
                    }
                }
                .padding(.horizontal, V2.Space.gutter)
            }
        }
    }

    // MARK: Shared bits

    private var hairline: some View {
        Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
    }

    private func fmt(_ v: Double, _ decimals: Int) -> String {
        decimals > 0 ? String(format: "%.\(decimals)f", v) : String(Int(v.rounded()))
    }

    /// A goodness-toned baseline delta: green when the reading is better than baseline for this
    /// metric, red when worse, flat (grey) when inside the personal normal range. `nil` when the
    /// baseline is not yet usable, so a cold-start day shows the value with no misleading arrow.
    private func devDelta(_ value: Double?, state: BaselineState,
                          higherIsBetter: Bool, decimals: Int) -> V2Delta? {
        guard let value, state.usable else { return nil }
        let dev = Baselines.deviation(value, state: state)
        let mag = fmt(abs(dev.delta), decimals)
        if dev.inNormalRange { return V2Delta(value: mag, direction: .flat) }
        let improved = (dev.delta > 0) == higherIsBetter
        return V2Delta(value: mag, direction: improved ? .up : .down)
    }

    // MARK: Intraday load

    /// Local-day window [midnight, min(now, next midnight)] for the selected day, or nil when empty.
    private var dayWindow: (from: Int, to: Int, start: Date)? {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let from = Int(start.timeIntervalSince1970)
        let to = Int(min(Date(), start.addingTimeInterval(86_400)).timeIntervalSince1970)
        return to > from ? (from, to, start) : nil
    }

    /// Heart-rate line — SQL-bucketed 5-min means (never the raw ~1 Hz rows). Cheap; loads eagerly.
    private func loadHR() async {
        intradayLoaded = false
        hrPoints = []
        hrvPoints = []
        guard let w = dayWindow else { intradayLoaded = true; return }
        let buckets = await repo.hrBuckets(from: w.from, to: w.to, bucketSeconds: 300)
        hrPoints = buckets.map {
            V2ChartPoint(date: Date(timeIntervalSince1970: Double($0.ts)), value: $0.bpm)
        }
        intradayLoaded = true
    }

    /// Hourly HRV lens — reuses the shipped DaytimeStress engine's per-hour RMSSD. Reads the day's
    /// raw HR + R-R (heavier), so it runs only once the HRV segment is actually selected.
    private func loadHRVIfNeeded() async {
        guard chartMetric == .hrv, hrvPoints.isEmpty, let w = dayWindow else { return }
        let hr = await repo.hrSamples(from: w.from, to: w.to, limit: 200_000)
        guard !hr.isEmpty else { return }
        let rr = (try? await repo.storeHandle()?.rrIntervals(
            deviceId: repo.deviceId, from: w.from, to: w.to, limit: 200_000)) ?? []
        let tz = TimeZone.current.secondsFromGMT(for: w.start)
        let day = DaytimeStress.analyze(hr: hr, rr: rr, tzOffsetSeconds: tz)
        hrvPoints = day.hours.compactMap { h in
            h.rmssd.map { V2ChartPoint(date: Date(timeIntervalSince1970: Double(h.startTs)), value: $0) }
        }
    }
}
#endif
