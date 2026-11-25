#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - TodayV2Host — the Today tab root (the real card feed)
//
// The root of the Today tab, hosted inside the shell's per-tab `NavigationStack`. It resolves ONE
// `TodayContext` for the selected day (today-first day row + carry-forward vitals row + all days +
// unit prefs), loads the night's sleep session, then renders the enabled cards in the persisted
// `TodayLayout` order. A header date-stepper walks the day (never past today), a profile button
// hands off to Settings, and an edit affordance opens the card editor. Density is an `@AppStorage`
// knob injected into the feed via `.v2Density(_:)`.
//
// The `init(onOpenSettings:)` signature is frozen by the shell (`V2RootView`); the body is free.

struct TodayV2Host: View {
    /// Opens the Settings stack (the shell presents it). Wired to the header's profile button.
    var onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
    }

    @EnvironmentObject private var repo: Repository

    /// The day in focus. Defaults to today; the header stepper walks it within (…, today].
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Presents the card editor sheet (order / hidden / density).
    @State private var showEditor = false

    /// Layout density, shared live with the editor sheet. Injected onto the feed.
    @AppStorage(TodayDensityPrefs.storageKey) private var density: V2Density = .detailed
    /// The persisted card layout (ordered enabled cards as a JSON `[String]`).
    @AppStorage(TodayLayout.storageKey) private var layoutRaw = ""

    // Display-unit prefs (read the SAME keys as v1 / the v2 detail screens — no drift).
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // MARK: Day resolution (mirrors VitalsHealthV2View / the v1 today-first pattern)

    private var dayKey: String { Repository.localDayKey(selectedDate) }
    private var todayKey: String { repo.today?.day ?? Repository.logicalDayKey(Date()) }
    private var isToday: Bool { dayKey >= todayKey }
    private var canGoNext: Bool { dayKey < todayKey }

    /// The selected day's metric row — today's resolved row when showing today, else the stored row.
    private var dayRow: DailyMetric? {
        if isToday { return repo.today ?? repo.days.last { $0.day == dayKey } }
        return repo.days.last { $0.day == dayKey }
    }

    /// Carry-over row: the freshest day on-or-before the selected day carrying overnight vitals. Only
    /// used while showing an unscored TODAY (a past day shows its own reading only), so the today-first
    /// `TodayContext.hrv ?? vitalsDay` fallback matches VitalsHealthV2View's `resolve` intent.
    private var vitalsDay: DailyMetric? {
        guard isToday else { return nil }
        return repo.days.last {
            $0.day <= dayKey && ($0.avgHrv != nil || $0.restingHr != nil || $0.respRateBpm != nil)
        }
    }

    /// The night's main sleep block: the longest cached session ENDING on the selected wake-day
    /// (mirrors SleepV2View's end-day grouping, reduced to a single block for the card's hypnogram).
    private var sleepSession: CachedSleepSession? {
        let cal = Calendar.current
        let target = cal.startOfDay(for: selectedDate)
        return repo.sleeps
            .filter { cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.endTs))) == target }
            .max { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) }
    }

    /// The resolved read snapshot every card renders from.
    private var context: TodayContext {
        TodayContext(date: Calendar.current.startOfDay(for: selectedDate),
                     dayKey: dayKey,
                     isToday: isToday,
                     day: dayRow,
                     vitalsDay: vitalsDay,
                     days: repo.days,
                     effortScale: effortScale,
                     temperatureUnit: temperatureUnit,
                     unitSystem: unitSystem)
    }

    /// The enabled cards in persisted order (hero always first).
    private var enabledCards: [TodayCard] { TodayLayout.decode(layoutRaw) }

    // MARK: Body

    var body: some View {
        let ctx = context
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.lg) {
                V2ScreenHeader("Today",
                               date: $selectedDate,
                               canGoNext: canGoNext,
                               onPrev: { step(-1) },
                               onNext: { step(1) }) {
                    headerActions
                }

                LazyVStack(spacing: V2.Space.lg) {
                    ForEach(enabledCards) { card in
                        cardView(card, ctx: ctx)
                    }
                }
                .padding(.horizontal, V2.Space.gutter)
                .v2Density(density)
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: V2DetailRoute.self) { v2DetailDestination($0) }
        .sheet(isPresented: $showEditor) {
            TodayCardEditorSheet()
        }
    }

    // MARK: Day stepping

    private func step(_ delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        if delta > 0, Repository.localDayKey(next) > todayKey { return }
        selectedDate = cal.startOfDay(for: next)
    }

    // MARK: Header trailing actions (edit + profile)

    private var headerActions: some View {
        HStack(spacing: V2.Space.xs) {
            headerButton(icon: "slider.horizontal.3", label: "Edit Today feed") { showEditor = true }
            headerButton(icon: "person.crop.circle", label: "Profile and settings", action: onOpenSettings)
        }
    }

    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(V2Font.title)
                .foregroundStyle(V2.Color.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Card mapping

    @ViewBuilder
    private func cardView(_ card: TodayCard, ctx: TodayContext) -> some View {
        switch card {
        case .hero:     TodayHeroCard(ctx: ctx)
        case .vitals:   TodayVitalsCard(ctx: ctx)
        case .sleep:    TodaySleepCard(ctx: ctx, session: sleepSession)
        case .workouts: TodayWorkoutsCard(ctx: ctx)
        case .stress:   TodayStressCard(ctx: ctx)
        case .insight:  TodayInsightCard(ctx: ctx)
        case .metrics:  TodayMetricRowsCard(ctx: ctx)
        case .journal:  journalCard
        }
    }

    /// There is no dedicated journal card view; a small placeholder drills into the v1 Insights feed
    /// (which owns journaling) rather than inventing a broken reference.
    private var journalCard: some View {
        NavigationLink(value: V2DetailRoute.insights) {
            V2Card {
                HStack(spacing: V2.Space.md) {
                    Image(systemName: TodayCard.journal.icon)
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textSecondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: V2.Space.xxs) {
                        Text(TodayCard.journal.title)
                            .font(V2Font.heading)
                            .foregroundStyle(V2.Color.textPrimary)
                        Text("Log how today felt and what you did.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                    Spacer(minLength: V2.Space.sm)
                    Image(systemName: "chevron.right")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TodayV2Host(onOpenSettings: {})
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
