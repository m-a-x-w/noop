# UI v2 — Data-Layer Read Cheat-Sheet

Map for UI agents building v2 screens. v2 screens are rebuilt fresh but read the **same** data
layer the current `TodayView` / `LiquidTodayView` / `SleepView` / `WorkoutsView` / `MetricExplorerView`
read today. All paths absolute. `file:line` anchors + real accessor snippets. v2 is **dark-only** —
ignore appearance prefs, but units still matter.

> Two naming corrections up front:
> - The per-day model is **`WhoopStore.DailyMetric`**, published as `Repository.days: [DailyMetric]`.
>   `AnalyticsEngine.DayResult` is an engine-only wrapper (`.daily` IS a `DailyMetric`) — views never read it.
> - The **"Rest" score** is NOT a `DailyMetric` field — it's the `sleep_performance` metric series
>   (loaded separately). Charge = `DailyMetric.recovery`, Effort = `DailyMetric.strain`.

---

## 1. App / environment objects

Injected at the app root, available to every screen — `StrandiOS/App/StrandiOSApp.swift:64-76`:

```swift
.environmentObject(model)            // AppModel
.environmentObject(model.live)       // LiveState
.environmentObject(model.repo)       // Repository   <- the day model + all reads
.environmentObject(model.profile)    // ProfileStore
.environmentObject(model.behavior)   // BehaviorStore
.environmentObject(model.intelligence) // IntelligenceEngine
.environmentObject(model.coach)      // AICoachEngine
.environmentObject(health)           // HealthKitBridge
.environmentObject(router)           // NavRouter
.environmentObject(UpdateStore.shared) // UpdateStore
.environment(\.stressNudgeCenter, model.stressNudgeCenter)
```

Declare in a view exactly like today, e.g. `Strand/Screens/TodayView.swift:152,153,167,192,193,195`:
```swift
@EnvironmentObject var app: AppModel
@EnvironmentObject var repo: Repository
@EnvironmentObject var profile: ProfileStore
@EnvironmentObject var router: NavRouter
@EnvironmentObject var updateStore: UpdateStore
```
(LiquidTodayView also uses `@EnvironmentObject var live: LiveState` — see the PERF note below.)

- **AppModel** — `Strand/App/AppModel.swift:22` (`@MainActor final class ... ObservableObject`). Members:
  `let live: LiveState` (:47), `let repo: Repository` (:51), `let profile = ProfileStore()` (:53),
  `let behavior = BehaviorStore()` (:54), `let intelligence: IntelligenceEngine` (:57),
  `let coach: AICoachEngine` (:60), `let ble: BLEManager` (:49),
  `@Published private(set) var deviceRegistry: DeviceRegistry?` (:67).
  Key `@Published`: **`bpm: Int?`** (:203 — smoothed, display-ready live HR; show THIS not `live.heartRate`),
  `activeWorkout: ActiveWorkout?` (:87), `lastWorkout: WorkoutRow?` (:89), `healthAlert: String?` (:132),
  `moments: [Date]` (:74), `sleepMarks: [Date]` (:80), `illnessSignal` (:140), `cyclePhase` (:147),
  `circadianPhase` (:151). Methods: `startWorkout(sport:)` (:543), `endWorkout()` (:645),
  `scan()` / `disconnect()` (:816/:822).
- **LiveState** — `Strand/BLE/LiveState.swift`, env obj `live`. Observed by leaves that show live HR:
  `.heartRate` (raw), `.rr`, `.bonded`, `.worn`, `.charging`, `.batteryPct`, `.lastSyncedAt`.
  PERF: TodayView deliberately does NOT observe `live` (it publishes ~1 Hz); only small leaf subviews
  hold their own `@EnvironmentObject var live` (`TodayView.swift:4358,4395,…`). Mirror that in v2.
- **Repository** — `Strand/Data/Repository.swift`, env obj `repo`. See §2. It owns every read accessor.
- **ProfileStore** — env obj `profile`. Fields used across views: `hrMax`, `sex` (String "male"/"female"),
  `weightKg`, `heightCm`, `age`.
- **IntelligenceEngine** — env obj `intelligence`. Scores raw streams into `repo.days`; `analyzeRecent()`.
- **AICoachEngine** — env obj `coach`. Opt-in AI (BYO key).
- **HealthKitBridge** — `StrandiOS/Health/HealthKitBridge.swift:15`, env obj `health`. `@Published`:
  `auth: AuthState` (:28), `lastSync: Date?` (:29), `syncing: Bool` (:30), `lastError: String?` (:33).
- **NavRouter** — `Strand/App/NavRouter.swift:17`, env obj `router`. `@Published requestedDestination:
  Destination?` (:44), `quickActionsRequested` (:48), `presentActiveWorkout` (:55). Methods:
  `requestQuickActions()`, `openTrends()`, `openDevices()`, `openInsightsHub()`, `openLabBook()`,
  `openActiveWorkout()` (:58-79). `Destination`: `devices, insightsHub, labBook, fusedRecord, rhythm,
  trends, activeWorkout, liveSession` (:22-30).
- **UpdateStore.shared** — env obj `updateStore`. Inbox / what's-new items.

---

## 2. The day model (`DailyMetric`)

- Type: **`WhoopStore.DailyMetric`** — `Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift:48`
  (`public struct DailyMetric: Equatable, Codable`).
- Published array: **`Repository.days: [DailyMetric]`** — `Strand/Data/Repository.swift:162`
  (`@Published var days`), **oldest → newest**. Companions: `@Published var sleeps: [CachedSleepSession]`
  (:164), `@Published var loaded` (:167), `@Published private(set) var freshness: RepositoryFreshness`
  (:170), `@Published private(set) var refreshSeq` (:177), `@Published private(set) var hydrationSeq` (:182).
- Fields (`MetricsCache.swift:49-73`):
  `day: String` "yyyy-MM-dd" (:49) · **`recovery: Double?`** 0–100 Charge (:58) ·
  **`strain: Double?`** 0–100 Effort (:59) · `restingHr: Int?` (:56) · `avgHrv: Double?` ms (:57) ·
  `respRateBpm: Double?` (:64) · `spo2Pct: Double?` (:62) · `skinTempDevC: Double?` (:63) ·
  `totalSleepMin/efficiency/deepMin/remMin/lightMin: Double?` (:50-54) · `disturbances: Int?` (:55) ·
  `exerciseCount: Int?` (:60) · `steps: Int?` (:67) · `activeKcalEst: Double?` (:68) ·
  `solMin/remLatencyMin/wasoMin: Double?` (:71-73). **No "rest score" column** (see §5).
- **Today**: `repo.today: DailyMetric?` — `Repository.swift:357`, via pure `resolveToday(days:logicalKey:
  localKey:)` (:366) with the 04:00 logical-day rollover (`logicalDayKey` :474).
- **Off-dashboard anchor** (widget / watch / Live Activity): `Repository.widgetAnchor(days:now:)` — `:402`
  (today's row when scored, else freshest strictly-prior scored day).
- **Day selection / stepping** (how Today does it — mirror in v2):
  `@State private var selectedDayOffset = 0` — `TodayView.swift:330` (0 = today, 1 = yesterday…).
  ```swift
  private var selectedDayKey: String {                                   // TodayView.swift:466
      if selectedDayOffset == 0, let todayKey = repo.today?.day { return todayKey }
      return Repository.localDayKey(selectedLogicalDay) }
  private var displayDay: DailyMetric? {                                 // TodayView.swift:474
      if selectedDayOffset == 0 { return repo.today ?? repo.days.last { $0.day == selectedDayKey } }
      return repo.days.last { $0.day == selectedDayKey } }
  ```
  `selectedLogicalDay = today − selectedDayOffset` (:460); clamp with `maxDayOffset(earliestDayKey:
  todayKey:)` (:567); the `DayNavBar` chevrons drive `selectedDayOffset`. LiquidTodayView mirrors this:
  `selectedDayOffset` (`LiquidTodayView.swift:50`), `displayDay` (:93), `vitalsDay` (:96).
- **Carry-over selectors** (today, before tonight is scored):
  `Repository.lastVitalsDay(days:todayKey:)` (:418/:425) — freshest prior day with any HRV/RHR/resp;
  `TodayView.lastScoredRecoveryDay(days:selectedDayKey:…)` (:529) — freshest prior fully-scored day.
  Views read **per-field, today-first**: `displayDay?.field ?? vitalsDay?.field`.

---

## 3. Charge / Recovery

- **Score (0–100)**: `DailyMetric.recovery: Double?`. Hero read:
  `LiquidTodayView.swift:384` → `HeroScoreCell(label: "Charge", score: displayDay?.recovery, tint: StrandPalette.chargeColor, …)`.
- **Color band**: `StrandPalette.recoveryColor(_ score: Double) -> Color` —
  `Packages/StrandDesign/Sources/StrandDesign/Palette.swift:306` (red→green ramp; used for Charge AND Rest,
  e.g. `TodayView.swift:3222`). State word: `StrandPalette.recoveryState(_:) -> DEPLETED/LOW/MODERATE/
  PRIMED/PEAK` (:324). Raw band string: `RecoveryScorer.band(_:) -> "red"/"yellow"/"green"` —
  `RecoveryScorer.swift:138` (thresholds `bandRedMax = 34`, `bandYellowMax = 67`, :59-60).
- **Driver breakdown** — `ChargeDriver` struct — `Packages/StrandAnalytics/Sources/StrandAnalytics/ChargeDrivers.swift:28`:
  `label: String`, `deltaPoints: Int` (signed points vs baseline), `valueText: String`,
  `baselineText: String`, `verdict: String`. Built by
  `RecoveryScorer.chargeDrivers(hrv:rhr:resp:hrvBaseline:rhrBaseline:respBaseline:sleepPerf:skinTempDev:)
  -> [ChargeDriver]` — `ChargeDrivers.swift:122` (ordered biggest-mover first; empty when cold-start).
- **How Today builds the driver list** — `TodayView.swift:645-662` (pure derivation from `displayDay`,
  no second store read):
  ```swift
  let hrvBase = Baselines.foldHistory(repo.days.map(\.avgHrv), cfg: Baselines.hrvCfg)          // :648
  let rhrBase = Baselines.foldHistory(repo.days.map { $0.restingHr.map(Double.init) }, cfg: Baselines.restingHRCfg)
  let respBase = Baselines.foldHistory(repo.days.map(\.respRateBpm), cfg: Baselines.respCfg)
  let sleepPerf = restScore.map { $0 / 100.0 }                                                // :655
  return RecoveryScorer.chargeDrivers(hrv: hrv, rhr: Double(rhr), resp: row.respRateBpm,
      hrvBaseline: hrvBase, rhrBaseline: rhrBase.usable ? rhrBase : nil,
      respBaseline: respBase.usable ? respBase : nil,
      sleepPerf: sleepPerf, skinTempDev: row.skinTempDevC)                                     // :656
  ```
- Extras: confidence `ScoreConfidence.charge(recovery:hrvBaseline:)` (`TodayView.swift:669`);
  skin-temp tier `RecoveryScorer.skinTempRelative(deviationC:) -> SkinTempRelative?` (:675) →
  `{ deviationC, tier: .cooler/.typical/.warmer }` (`ChargeDrivers.swift:56`).
- Score math (context): `RecoveryScorer.recovery(...)` weights wHRV 0.55 / wRHR 0.20 / wSleep 0.15 /
  wResp 0.05 / wSkinTemp 0.05 (`RecoveryScorer.swift:39-45,208`).

---

## 4. Vitals (HRV · RHR · Resp · Skin temp · SpO2)

Values on `DailyMetric` (all optional): `avgHrv` ms · `restingHr` bpm (Int) · `respRateBpm` br/min ·
`spo2Pct` % · `skinTempDevC` °C. Read per-field today-first — `TodayView.swift:2338-2340`:
```swift
let hrv = d?.avgHrv ?? vd?.avgHrv
let rhr = d?.restingHr ?? vd?.restingHr
let resp = d?.respRateBpm ?? vd?.respRateBpm
```
(LiquidTodayView `:612-614`; the RECOVERY VITALS card shows HRV/RHR/resp only, `"ms"`/`"bpm"`/`"rpm"`.)

- **Baselines** — `Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift`:
  `Baselines.foldHistory(_ values: [Double?], cfg: MetricCfg) -> BaselineState` (:264);
  cfgs `Baselines.hrvCfg` (:161), `restingHRCfg` (:162), `respCfg` (:163) — **no spo2 cfg** (population-only).
  `BaselineState.baseline` (mean), `.spread`, `.usable`/`.trusted` (:44). **Delta**:
  `Baselines.deviation(_ value:, state:) -> Deviation` (:345); `Deviation.delta` (= value − baseline),
  `.z` (:73). `ProfileBaselines` is engine-only (`AnalyticsEngine.swift:41`) — views use `foldHistory` directly.
- **In-range band** — `VitalBands.band(value:history:populationRange:cfg:) -> Result` — `VitalBands.swift:50`;
  `Result.band` (`inRange/outOfRange/noData`), `.basis` (`personal/population`).
- **Current vitals-tile screen** — `Strand/Screens/VitalSignsSummary.swift`, per-tile keypaths (:142-146):
  ```swift
  let respPoints = points(key: "resp", \.respRateBpm)   // pop 12...20, cfg respCfg
  let spo2Points = points(key: "spo2", \.spo2Pct)       // pop 95...100, cfg: nil (population only)
  let rhrPoints  = points(key: "rhr") { $0.restingHr.map(Double.init) }  // pop 40...60, cfg restingHRCfg
  let hrvPoints  = points(key: "hrv", \.avgHrv)         // pop 40...120, cfg hrvCfg
  let skinPoints = points(key: "skin", \.skinTempDevC)
  ```
  Each tile → `BodyVitalReading { value: Double?, unit: String, banding: VitalBands.Result }` (:10).
- **Skin temp °C/°F** (bimodal — deviation on-device, absolute when imported):
  gate `VitalBands.isAbsoluteSkinTemp(v)` = `v >= 20` (`VitalBands.swift:82`). Format:
  `UnitFormatter.temperatureFromCelsius(c, unit:, decimals:)` (absolute, `Units.swift:187`) vs
  `UnitFormatter.temperatureDeltaFromCelsius(dc, unit:, decimals:)` (deviation, no +32, :196).
  `temperatureUnit` computed var from `UnitPrefs.resolveTemperature(system:override:)` (`Units.swift:72`).

---

## 5. Sleep

- **Last-night session** — `repo.sleeps: [CachedSleepSession]` (`Repository.swift:164`); last night =
  `repo.sleeps.last` (`SleepView.swift:1517`). Fuller un-deduped list: `repo.allSleepSessions`
  (falls back to `repo.sleeps`, `SleepView.swift:1591`).
  **`CachedSleepSession`** — `MetricsCache.swift:14`: `startTs`/`endTs` (unix s), `efficiency: Double?`,
  `restingHr: Int?`, `avgHrv: Double?`, `stagesJSON: String?`, `userEdited`, `startTsAdjusted: Int?`,
  `effectiveStartTs: Int` (:30 — the onset to display/stage from), `lowConfidence`.
- **Rest score (0–100)**: NOT on `DailyMetric` — it is the **`sleep_performance`** metric series, computed by
  `AnalyticsEngine.Rest.composite(...)` (`AnalyticsEngine.swift:414`; surfaced as `DayResult.restScore` :84).
  Today loads it into `@State private var restScore: Double?` (`TodayView.swift:268`) via its `loadAll`
  snapshot (`c.restScore` :3809; `freshRestScore(...)` :600). Rest tile tint = `StrandPalette.recoveryColor(restScore)`
  (:3222). The Rest ring uses `provenanceKey: "sleep_performance"` (:2565). To fetch it generically for
  any day, use the metric resolver `repo.exploreSeries(key: "sleep_performance", source: "my-whoop")` (§7).
- **Totals / efficiency / stages**: on `DailyMetric` — `totalSleepMin`, `efficiency` (0–1),
  `deepMin`, `remMin`, `lightMin` (minutes). Or decode a session's `stagesJSON` (reusable, both formats):
  `SleepStageTotals.minutes(fromStagesJSON:) -> Minutes?` — `SleepStageTotals.swift:20`
  (`Minutes { awake, light, deep, rem; asleep; inBed }`). Night rollup:
  `SleepStageTotals.dailyAggregate([String?]) -> DailySleep?` (:58) →
  `{ totalSleepMin, efficiency, deepMin, remMin, lightMin }`.
- **Sleep need & debt** — `SleepDebt.ledger(series: [(day, totalSleepMin?)], needHours: Double = 8.0,
  window: Int = 14) -> SleepDebtLedger` — `SleepDebt.swift:90`.
  `SleepDebtLedger { balanceMin (negative = DEBT), nights: [SleepDebtNight], needMin, isDebt,
  magnitudeMin, nightCount }` (:42). `SleepDebtNight { day, sleptMin, deltaMin }` (:28).
  Default need = `AnalyticsEngine.Rest.defaultNeedHours` (8.0). Feed it `repo.days.map { ($0.day, $0.totalSleepMin) }`.
- **Hypnogram segments** — decode `stagesJSON`'s computed segment array `[{start,end,stage}]` (epoch secs,
  stage ∈ `wake|light|deep|rem`). Design-system types:
  `SleepInterval { stage: SleepStage, start: TimeInterval, end: TimeInterval }` (secs from night start) —
  `Packages/StrandDesign/Sources/StrandDesign/Hypnogram.swift:16`; `SleepStage` enum `awake/light/deep/rem`
  (`.label`, `.bandRank`) — `Palette.swift:450`. v2 chart component: `StrandDesign/V2/Charts/V2Hypnogram.swift`.
  Reference decoder (maps names + rebases to `start − sessionStart`) — `SleepView.decodeSegments(_:sessionStart:)
  -> (stages, [SleepInterval])` — `SleepView.swift:2231`. Imported minute-dict path:
  `SleepView.decodeStages(_:)` (:2213).

---

## 6. Effort / Strain + Workouts

- **Day strain / Effort (0–100)**: `DailyMetric.strain: Double?` (`StrainScorer.maxStrain = 100`).
  Hero: `LiquidTodayView.swift:386` → `HeroScoreCell(label: "Effort", score: displayDay?.strain, tint:
  StrandPalette.effortColor, …)`. Tile (`TodayView.swift:3202`):
  ```swift
  value: d?.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—",
  accent: d?.strain.map { StrandPalette.effortTint(fraction: $0 / StrainScorer.maxStrain) } ?? …
  ```
  Color: `StrandPalette.strainColor(_ v: Double)` / `effortColor` / `effortTint(fraction:)` (`Palette.swift:311/318`).
  Live/manual recompute: `StrainScorer.strain(_ hr: [HRSample], maxHR:, restingHR:, method: .edwards, sex:) -> Double?`
  — `Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift:209`.
- **Workout model** — `WhoopStore.WorkoutRow` — `Packages/WhoopStore/Sources/WhoopStore/JournalWorkoutAppleCache.swift:30`:
  `startTs: Int`, `endTs: Int`, `sport: String`, `source: String`, `durationS: Double?`,
  `energyKcal: Double?`, `avgHr: Int?`, `maxHr: Int?`, `strain: Double?`, `distanceM: Double?`,
  `zonesJSON: String?`, `notes: String?`. (SQLite `workout` table.)
- **Load** — `repo.workoutRows(days: Int = 4000) async -> [WorkoutRow]` — `Repository.swift:1920`.
  `WorkoutsView` — `Strand/Screens/WorkoutsView.swift`: `@State private var allRows: [WorkoutRow]` (:43),
  `let r = await repo.workoutRows(days: loadedWindowDays ?? 4000)` (:172) inside `.task(id: repo.refreshSeq)`
  (:169). Mutations on repo: `saveManualWorkout` (:198), `relabelDetected` (:325), `dismissDetected` (:332),
  `deleteWorkout` (:339), `bulkDeleteWorkouts` (:1003).
- **HR zones** (from imported `zonesJSON`) — `Strand/Data/WorkoutZones.swift`:
  `WorkoutZones.percents(_ zonesJSON: String?) -> [Double]?` (Z1…Z5 %, :14; tolerates `z1`/`zone1`);
  `WorkoutZones.summary(from rows: [WorkoutRow]) -> Summary?` (:35) →
  `Summary { minutes: [Double] /* Z1…Z5 */, sessionsWithZones, totalMinutes }`. Used at
  `WorkoutsView.swift:155` and per-sport `:769`.
- **HR zones from a raw HR stream** (live/detail) — `Packages/StrandAnalytics/Sources/StrandAnalytics/HRZones.swift`:
  `HRZones.zones(age:maxHROverride:) -> HRZoneSet` (:110); `HRZones.timeInZone(_ hr: [HRSample], zoneSet:) ->
  TimeInZone` (:150; `TimeInZone.seconds: [Double]`, `belowZone1`, `total`). Edges `[.50,.60,.70,.80,.90,1.0]`.
- **Sport** — `WorkoutRow.sport: String`; lookups via `WorkoutCatalog` (`Strand/Data/WorkoutCatalog.swift`):
  `WorkoutCatalog.sport(named:) -> Sport?` (e.g. `.isDistanceSport`), `WorkoutCatalog.defaultSportName` ("Other").

---

## 7. MetricCatalog (drives Explore + metric detail)

- Element: **`MetricDescriptor`** (`struct: Identifiable, Hashable`) — `Strand/Data/MetricCatalog.swift:6`.
  Array: `MetricCatalog.all: [MetricDescriptor]` (:112).
- Fields (:7-18): `key: String` · `title: String` · `category: String` · `unit: String` · `source: String`
  · `icon: String` (SF Symbol) · `decimals: Int` · `higherIsBetter: Bool?` · `description: String?` ·
  `id = source + ":" + key`. Helpers: `sourceLabel` (:21), `format(_:system:temperature:effortScale:)`
  (:36/44/55), `formatDelta` (:75), `displayUnit` (:90/101).
- **Category** is a plain `String` (not an enum). Canonical 7:
  `MetricCatalog.categories = ["Heart","Charge","Rest","Effort","Health","Nutrition","Mind"]` (:110);
  filter `MetricCatalog.inCategory(_:)` (:199); localize only at render via `categoryDisplayName(_:)` (:205).
- **Source** values (String): `"my-whoop"`, `"apple-health"`, `"xiaomi-band"`, `"nutrition-csv"`, `"noop-mood"`.
- **Value for (metric, day)**: `repo.exploreSeries(key: String, source: String, days: Int = 4000,
  fullHistory: Bool = false) async -> [(day: String, value: Double)]` — `Repository.swift:1728`
  (three-layer imported-wins merge; index the returned array by `day`). Generic reader beneath it:
  `repo.series(key:source:days:)` (:1296).
- Explore screen — `Strand/Screens/MetricExplorerView.swift`:
  ```swift
  for metric in MetricCatalog.all {                                          // :315
      let s = await repo.exploreSeries(key: metric.key, source: metric.source)  // :317
  ```
  Row type `MetricRow { let metric: MetricDescriptor }` (:328); detail `MetricDetailView(metric:)`.
  Same `MetricCatalog.all.first { $0.key == … }` accessor at `LiquidTodayView.swift:516`,
  `TrendsView.swift:580`, `LabBookView.swift:938`, `CompareView.swift:278`.

---

## 8. Trends (`RangeReport`)

- Engine — `Packages/StrandAnalytics/Sources/StrandAnalytics/RangeReport.swift`:
  `RangeReportEngine.build(metrics: [ReportMetric: [String: Double]], start: String, end: String)
  -> RangeReport` (:237). `end < start` ⇒ empty.
- `enum ReportMetric` (:34): `workouts, stress, recovery, sleepHours, hrv, restingHr, strain, respRate,
  skinTempDev`; props `label`, `unit`, `higherIsBetter`, `framesGoodBad`, `trendSlopeThreshold`.
- Output `RangeReport` (:188): `start`, `end`, `totalDays`, `metrics: [MetricRangeStat]`, `headlines: [String]`,
  `stat(_:)`, `isEmpty`. `MetricRangeStat` (:147): `metric`, `n`, `mean`, `min: DayValue`, `max: DayValue`,
  `firstHalfMean`, `secondHalfMean`, `trend: ReportTrend` (`rising/falling/flat`), `latest: DayValue`,
  `halfDelta`. **Slope is NOT surfaced** — only the `trend` enum (raw OLS is internal, `:391`).
  `DayValue { day: String, value: Double }` (:133).
- Range enum is app-side: `TrendsReportView.ReportRange` (`Strand/Screens/TrendsReportView.swift:31`):
  `days30 = 30, days90 = 90, days180 = 180, days365 = 365, all = 0`.
- Build (real call) — `TrendsReportView.swift:136`:
  ```swift
  static func report(for range: ReportRange, days: [DailyMetric], today: String,
                     stressByDay: [String: Double] = [:]) -> RangeReport {
      let (start, end) = window(for: range, days: days, today: today)
      return RangeReportEngine.build(metrics: metricMaps(from: days, stressByDay: stressByDay),
                                     start: start, end: end) }
  ```
  (`metricMaps(from:)` :73, `window(for:days:today:)` :113.) NOTE: two trends screens exist —
  `TrendsReportView.swift` (RangeReport) and `TrendsView.swift` (per-metric via MetricCatalog).

---

## 9. Correlations / Relationships (merged screen: outcome → ranked drivers)

- **EffectRanker** is the main "outcome → ranked drivers" entry —
  `Packages/StrandAnalytics/Sources/StrandAnalytics/EffectRanker.swift`:
  `EffectRanker.rank(behaviors: [String: Set<String>], outcomeByDay: [String: Double], outcome: String)
  -> [RankedEffect]` (:106). `RankedEffect` (:38): `behavior`, `outcome`, `lag: Int`, `effect: BehaviorEffect`,
  `confidence: ScoreConfidence`. `BehaviorEffect` (`BehaviorInsights.swift:29`): `meanWith`, `meanWithout`,
  `delta`, `pctChange`, `nWith`, `nWithout`, `cohensD`, `pApprox`, `significant`.
- **CorrelationEngine** (pairwise primitive) — `CorrelationEngine.swift`:
  `Correlation { r, n, pApprox, slope, intercept }` (:35); `pearson(_ xy: [(Double,Double)]) -> Correlation?`
  (:65); `alignByDay(_:_:)` (:104, inner-join two `[(day,value)]` series → pairs); `lagged(x:y:lagDays:)`
  (:123); `benjaminiHochberg(_:)` (:236). No built-in batch "rank drivers" — callers loop + rank by `abs(r)`.
- **DoseResponseEngine** (dose bucket → response curve) — `DoseResponseEngine.swift`:
  `estimate(behavior:doseByDay:outcomeByDay:)` / `estimate(behavior:outcome:doseByDay:outcomeByDay:)
  -> DoseResponse?` (:145/:155). `DoseResponse { perUnit, userSlope, priorSlope, weight, nUser,
  confidence, curve: [DoseCurvePoint], sentence() }` (:39). `DosedBehavior`: `alcohol`, `caffeine`.
- All three orchestrated together today in `Strand/Screens/InsightsHubView.swift`:
  `EffectRanker.rank(...)` → `@Published ranked: [RankedEffect]` (:624), `DoseResponseEngine.estimate(...)`
  → `doseCards` (:606). Outcome picker enum `recovery, hrv, sleep, rhr` (:494). Also `AICoach.swift:566`.
  CorrelationEngine-only call sites: `CompareView.swift:489`, `LabBookView.swift:880`, `MetricExplorerView.swift:902`.

---

## 10. Units / formatting

`Strand/Data/Units.swift` (everything stored SI; this is display-only). Read prefs via `@AppStorage`.

- Enums: `UnitSystem { metric, imperial }` (:15) · `TemperatureUnit { celsius, fahrenheit }` (:26) ·
  `EffortScale { hundred /* 0–100 native */, whoop /* 0–21 */ }` (:35).
- `UnitPrefs` (:45) keys: `systemKey = "units.system"`, `temperatureKey = "units.temperature"`,
  `effortScaleKey = "effort.scale"`. Resolvers: `resolveTemperature(system:override:)` (:72),
  `resolveEffortScale(_:)` (:78). Views compute an `effortScale` / `temperatureUnit` var from these
  (e.g. `TodayView.swift:202`).
- `UnitFormatter` (:91): `distanceFromMeters(_:system:)` (:109), `distanceFromKilometers(_:system:)` (:125),
  `massFromKilograms(_:system:)` (:143), `heightFromCentimeters(_:system:)` (:170),
  `temperatureFromCelsius(_:unit:decimals:)` (:187), `temperatureDeltaFromCelsius(_:unit:decimals:)` (:196),
  `effortValue(_:scale:)` (:217), `effortDisplay(_:scale:) -> String` (:224),
  `effortScaleMax(_:scale:) -> "100"/"21"` (:230). `effortScaleFactor = 21.0/100.0` (:214).
- Real example — `TodayView.swift:3202`: `UnitFormatter.effortDisplay(strain, scale: effortScale)`.

---

## 11. Logging surfaces (quick actions / journal card)

- **Hydration** — Repository extension (`Strand/Data/HydrationStore.swift`). Write:
  `repo.logHydration(amountMl: Int, day: String? = nil) async -> Double` (:109). Read total:
  `repo.hydrationTotal(day:) async -> Double` (:96); entries `repo.hydrationEntries(day:)` (:129),
  `deleteHydrationEntry`/`updateHydrationEntry`; 7-day `repo.hydrationHistory(days:)` (:190); goal
  `repo.hydrationGoalML(profileSex:)` (:212). Stored in `metricSeries` source/key `"hydration"`;
  writes call `noteHydrationChanged()` → bumps `repo.hydrationSeq` (observe for refresh).
- **Caffeine** — `CaffeineLogStore` `@MainActor ObservableObject` (`Strand/Data/CaffeineLog.swift:179`).
  **Standalone** — owned as `@StateObject` by the caffeine card, NOT a root env object (persists to
  UserDefaults `"caffeine.intakes"`). Write `log(at: Date, mg: Double? = nil)` (:203); `remove(_:)` (:214);
  `clearAll()` (:219); `estimate() -> CaffeineActiveEstimate` (:224); `intakes: [CaffeineIntake]` (:182).
- **Mood** — Repository extension (`Strand/Data/MoodStore.swift`). Write `repo.saveMood(day: String,
  value: Int) async` (:73); read `repo.mood(day:) async -> Int?` (:63), `repo.moodSeries()` (:58). Scale
  1–5; `metricSeries` source `"noop-mood"` key `"mood"`. Glyph/label `MoodStore.face(for:)` (:30),
  `MoodStore.label(for:)` (:41).
- **Journal** — Repository extension (`Strand/Data/Repository.swift`). Write
  `repo.saveJournalAnswer(day:question:answeredYes:notes:) async` (:1875),
  `repo.saveJournalNumeric(day:question:value:notes:) async` (:1885), `repo.clearJournalAnswer(day:question:)`
  (:1908). Read `repo.journalEntries()` (:1820), `repo.nativeJournalAnswers(day:) -> [String: Bool]` (:1846),
  `repo.nativeJournalNumeric(day:) -> [String: Double]` (:1856). Source `"noop-journal"`.
  Model `JournalEntry { day, question, answeredYes, notes, numericValue }` (`JournalWorkoutAppleCache.swift:10`).
  Question catalog: `JournalCatalogStore` / `JournalCatalogItem` / `JournalGroup` / `JournalKind`
  (`Strand/Data/JournalCatalog.swift`).

---

## Appendix — v2 design components (for reference)

Dark-only v2 kit under `Packages/StrandDesign/Sources/StrandDesign/V2/`: charts `V2Ring`, `V2Sparkline`,
`V2DayChart`, `V2HeatStrip`, `V2Hypnogram`, `V2BarChart`, `V2TrendChart`; components `V2Card`, `V2StatRow`,
`V2BigNumber`, `V2Segmented`, `V2Chip`, `V2ListRow`, `V2ScreenHeader`, `V2SheetHeader`, `V2SectionHeader`,
`V2Button`, `V2Density`, `V2Motion`; tokens `V2Tokens`, `V2ChartScales`, `NoopType`; pillar model
`V2Domain` (`Pillar { charge, effort, rest, stress, health }` with `accent`/tint helpers). v2 shell root:
`StrandiOS/UI/Shell/V2RootView.swift` (P0 scaffold; env objects come from `StrandiOSApp` as in §1).
