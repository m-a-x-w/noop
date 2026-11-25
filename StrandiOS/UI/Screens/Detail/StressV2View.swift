#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - StressV2View
//
// The day's stress detail. Reads the SAME autonomic-load layer the v1 Stress monitor reads
// (docs/UI-V2-DATA.md §4, §11): the shipped `StressModel` resolves a 0–3 score for the day
// (stored "stress" series first, else a personal-baseline z-score derivation), and the shipped
// `DaytimeStress` engine gives the intraday hour-by-hour signal. This screen re-presents that in
// the v2 language: a horizontal gauge of the day score, a `V2DayChart` of the intraday signal, a
// Calm/Moderate/High split, and a Breathe check-in affordance.
//
// Dark-only, mono, progressive. The `init(date:)` signature is frozen by the `V2DetailRoute` contract.

struct StressV2View: View {
    @EnvironmentObject var repo: Repository

    let date: Date

    init(date: Date) {
        self.date = date
        _selectedDate = State(initialValue: date)
    }

    @State private var selectedDate: Date
    @State private var storedSeries: [(day: String, value: Double)] = []
    @State private var model: StressModel?
    @State private var daytime: DaytimeStress.Result?
    @State private var loaded = false
    @State private var showBreathe = false

    // MARK: Day resolution

    private var dayKey: String { Repository.localDayKey(selectedDate) }
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }
    private var canGoNext: Bool { dayKey < todayKey }

    /// Days up to and including the selected day, so `StressModel` scores THAT day as "today"
    /// against its own prior baseline (the model always treats `days.last` as the day of interest).
    private var slicedDays: [DailyMetric] { repo.days.filter { $0.day <= dayKey } }

    private var stressPoints: [V2ChartPoint] {
        (daytime?.hours ?? []).compactMap { h in
            h.level.map { V2ChartPoint(date: Date(timeIntervalSince1970: Double(h.startTs)), value: $0) }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Stress",
                               date: $selectedDate,
                               canGoNext: canGoNext,
                               onPrev: { step(-1) },
                               onNext: { step(1) })

                if let model {
                    heroCard(model)
                    markersCard(model)
                    intradaySection
                    checkInCard
                } else if loaded {
                    emptyCard
                } else {
                    loadingCard
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(dayKey)|\(repo.refreshSeq)") { await load() }
        .sheet(isPresented: $showBreathe) {
            NavigationStack {
                BreathingView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showBreathe = false }
                    } }
            }
        }
    }

    private func step(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        if delta > 0, Repository.localDayKey(next) > todayKey { return }
        selectedDate = next
    }

    // MARK: Hero — horizontal 0–3 gauge

    private func heroCard(_ model: StressModel) -> some View {
        let band = StressBand(score: model.score)
        return V2Card(domain: .stress) {
            VStack(alignment: .leading, spacing: V2.Space.lg) {
                HStack {
                    Text("Stress monitor")
                        .font(V2Font.overline)
                        .tracking(V2Font.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(V2.Color.textTertiary)
                    Spacer()
                    V2Chip(band.title, tone: tone(band))
                }
                V2BigNumber(value: String(format: "%.1f", model.score),
                            unit: "of 3", domain: .stress, size: 48)
                StressGauge(score: model.score)
                Text(model.explanation)
                    .font(V2Font.proseSmall)
                    .foregroundStyle(V2.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Markers — RHR / HRV vs baseline

    private func markersCard(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Markers") {
                Text("vs baseline")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
            V2Card {
                VStack(spacing: 0) {
                    V2StatRow(icon: "heart.fill", title: "Resting HR",
                              value: model.rhrToday.map { "\($0)" } ?? "—",
                              unit: model.rhrToday != nil ? "bpm" : nil,
                              delta: markerDelta(model.rhrDelta, higherIsBetter: false))
                    Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
                    V2StatRow(icon: "waveform.path.ecg", title: "HRV",
                              value: model.hrvToday.map { String(Int($0.rounded())) } ?? "—",
                              unit: model.hrvToday != nil ? "ms" : nil,
                              delta: markerDelta(model.hrvDelta, higherIsBetter: true))
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    /// A goodness-toned delta from a signed physical baseline delta (today − baseline). Green when
    /// the move is toward recovery, red toward stress, flat when it's essentially at baseline.
    private func markerDelta(_ delta: Double?, higherIsBetter: Bool) -> V2Delta? {
        guard let delta else { return nil }
        let mag = String(Int(abs(delta).rounded()))
        if abs(delta) < 0.5 { return V2Delta(value: mag, direction: .flat) }
        let improved = (delta > 0) == higherIsBetter
        return V2Delta(value: mag, direction: improved ? .up : .down)
    }

    // MARK: Intraday signal + Calm/Moderate/High split

    @ViewBuilder
    private var intradaySection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Intraday") {
                if let peak = daytime?.peak, let lvl = peak.level {
                    Text("peak \(String(format: "%.1f", lvl))")
                        .font(V2Font.caption)
                        .foregroundStyle(V2ChartScale.stress(lvl / 3.0))
                }
            }
            V2Surface(domain: .stress) {
                VStack(alignment: .leading, spacing: V2.Space.lg) {
                    if stressPoints.count >= 2 {
                        V2DayChart(samples: stressPoints, domain: .stress)
                        Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
                        totalsSplit
                    } else {
                        Text(loaded ? "Not enough intraday heart-rate data to trace stress for this day."
                                    : "Reading the day…")
                            .font(V2Font.label)
                            .foregroundStyle(V2.Color.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(V2.Space.lg)
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    @ViewBuilder
    private var totalsSplit: some View {
        let totals = StressTotals(hours: daytime?.hours ?? [])
        if totals.total > 0 {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        segment(totals.fraction(.low), V2ChartScale.stress(0.12), width: geo.size.width)
                        segment(totals.fraction(.medium), V2ChartScale.stress(0.5), width: geo.size.width)
                        segment(totals.fraction(.high), V2ChartScale.stress(0.9), width: geo.size.width)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                HStack(spacing: V2.Space.lg) {
                    legend("Calm", totals.calmHours, V2ChartScale.stress(0.12))
                    legend("Moderate", totals.moderateHours, V2ChartScale.stress(0.5))
                    legend("High", totals.highHours, V2ChartScale.stress(0.9))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func segment(_ frac: Double, _ color: Color, width: CGFloat) -> some View {
        if frac > 0 {
            Rectangle().fill(color).frame(width: max(2, width * frac))
        }
    }

    private func legend(_ label: String, _ hours: Int, _ color: Color) -> some View {
        HStack(spacing: V2.Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(V2Font.caption).foregroundStyle(V2.Color.textSecondary)
            Text(hours > 0 ? "\(hours)h" : "—")
                .font(V2Font.caption).foregroundStyle(V2.Color.textTertiary)
        }
    }

    // MARK: Check-in affordance

    @ViewBuilder
    private var checkInCard: some View {
        let sustained = daytime?.sustainedHigh ?? false
        V2Card(domain: .stress) {
            VStack(alignment: .leading, spacing: V2.Space.md) {
                HStack {
                    Text("Check in")
                        .font(V2Font.overline)
                        .tracking(V2Font.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(V2.Color.textTertiary)
                    Spacer()
                    if sustained, let run = daytime?.sustainedRun, run > 0 {
                        V2Chip("\(run)h elevated", tone: .caution)
                    }
                }
                Text(sustained
                     ? "Your last few hours have stayed in the high band. A minute of paced breathing can help downshift your nervous system."
                     : "Take a minute to downshift. A short paced-breathing session nudges your nervous system toward calm.")
                    .font(V2Font.proseSmall)
                    .foregroundStyle(V2.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Breathe") { showBreathe = true }
                    .v2Primary()
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Empty / loading

    private var emptyCard: some View {
        V2Card(domain: .stress) {
            Text("No stress signal for this day yet. Wear your strap or import a history to see autonomic load.")
                .font(V2Font.proseSmall)
                .foregroundStyle(V2.Color.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    private var loadingCard: some View {
        V2Card(domain: .stress) {
            Text("Reading your heart-rate variability and resting heart rate…")
                .font(V2Font.proseSmall)
                .foregroundStyle(V2.Color.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Tone mapping

    private func tone(_ band: StressBand) -> V2Tone {
        switch band {
        case .low:    return .positive
        case .medium: return .caution
        case .high:   return .negative
        }
    }

    // MARK: Load

    private func load() async {
        storedSeries = await repo.series(key: "stress", source: "my-whoop")
        model = StressModel(days: slicedDays, stored: storedSeries)
        loaded = true
        await loadDaytime()
    }

    private func loadDaytime() async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let from = Int(start.timeIntervalSince1970)
        let endDate = min(Date(), start.addingTimeInterval(86_400))
        let to = Int(endDate.timeIntervalSince1970)
        guard to > from else { daytime = .empty; return }

        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { daytime = .empty; return }
        let rr = (try? await repo.storeHandle()?.rrIntervals(
            deviceId: repo.deviceId, from: from, to: to, limit: 200_000)) ?? []
        let tz = TimeZone.current.secondsFromGMT(for: start)
        daytime = DaytimeStress.analyze(hr: hr, rr: rr, tzOffsetSeconds: tz)
    }
}

// MARK: - Horizontal stress gauge (0–3)
//
// A hairline capsule track with an accent fill to `score`/3, painted with the stress ramp
// (calm → balanced → high). Tick labels anchor the 0 / 1.5 / 3 scale. Purely presentational.
private struct StressGauge: View {
    let score: Double

    private var frac: Double { min(max(score / 3.0, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: V2.Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(V2.Color.surface2)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [V2ChartScale.stress(0.05),
                                     V2ChartScale.stress(0.5),
                                     V2ChartScale.stress(0.95)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * frac))
                }
            }
            .frame(height: 10)
            HStack {
                Text("0").font(V2Font.caption).foregroundStyle(V2.Color.textTertiary)
                Spacer()
                Text("1.5").font(V2Font.caption).foregroundStyle(V2.Color.textTertiary)
                Spacer()
                Text("3").font(V2Font.caption).foregroundStyle(V2.Color.textTertiary)
            }
        }
    }
}
#endif
