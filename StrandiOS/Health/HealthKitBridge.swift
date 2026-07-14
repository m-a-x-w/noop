#if os(iOS)
import Foundation
import HealthKit
import WhoopStore
import WhoopProtocol   // HRSample (raw strap HR rows written to Health)
import StrandImport

/// Two-way Apple Health bridge for the iOS app.
///
/// iOS has HealthKit (macOS does not), so the iOS target can do far more than parse a static export:
/// it reads the user's own Health data live and maps it onto the **same** `WhoopStore` rows the
/// macOS importer produces (under the `apple-health` source id), and it writes NOOP-computed metrics
/// back into Apple Health. Everything stays on-device and strictly opt-in.
@MainActor
final class HealthKitBridge: ObservableObject {

    enum AuthState: Equatable {
        case unknown, unavailable, denied, authorized
        /// The build can't talk to HealthKit at all: it was re-signed (free Apple ID / AltStore /
        /// Sideloadly) WITHOUT the `com.apple.developer.healthkit` entitlement, so the framework is
        /// present but the app can never read/write Health and can never appear under
        /// Settings › Health › Data Access & Devices. Distinct from `.denied` (entitled build, user
        /// said no) and `.unavailable` (no HealthKit hardware) so the UI can route to the honest
        /// file/Shortcuts import path instead of giving impossible Settings instructions (#348).
        case entitlementMissing
    }

    @Published private(set) var auth: AuthState = .unknown
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false
    /// The most recent failure surfaced by `sync` / `writeBack`. Cleared on a successful run. UI binds
    /// here so an Apple Health auth revoke, quota hit, or invalid sample is visible instead of silent.
    @Published private(set) var lastError: String?

    private let store = HKHealthStore()
    private let repo: Repository
    /// Source id imported HealthKit data lands under (matches `AppModel.appleDeviceId`).
    private let appleDeviceId: String
    /// NOOP's own strap-derived source id, read back when writing into Health.
    private let noopDeviceId: String
    /// NOOP's on-device COMPUTED daily scores (recovery/HRV/RHR/SpO₂/resp) live under the sibling
    /// `deviceId + "-noop"` id — mirrors `Repository.computedDeviceId` / `IntelligenceEngine.computedId`.
    /// `writeBack` must read this, not the raw import id: a Bluetooth-only WHOOP user has no imported
    /// `noopDeviceId` daily row, so those metrics exist ONLY here.
    private var computedDeviceId: String { noopDeviceId + "-noop" }

    init(repo: Repository, appleDeviceId: String, noopDeviceId: String) {
        self.repo = repo
        self.appleDeviceId = appleDeviceId
        self.noopDeviceId = noopDeviceId
        // Order matters: a free-signed build with no HealthKit entitlement is dead in the water even
        // where the hardware supports Health, so surface that first. `.unavailable` (no HealthKit at
        // all, e.g. iPad without the framework) still wins where it applies because we only reach the
        // entitlement check when `isHealthDataAvailable()` is true.
        if !HKHealthStore.isHealthDataAvailable() {
            auth = .unavailable
        } else if !HealthKitBridge.hasHealthKitEntitlement {
            auth = .entitlementMissing
        }
    }

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        for id in HealthKitBridge.quantityReadIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        s.insert(HKObjectType.workoutType())
        return s
    }

    private var writeTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        for id in HealthKitBridge.quantityWriteIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        s.insert(HKObjectType.workoutType())   // writeWorkouts: NOOP sessions land as real HKWorkouts
        return s
    }

    // Every id here ends up in the HealthKit permission dialog. Only request what `sync` actually
    // aggregates into `DayAgg`; adding read scopes the app never consumes makes the consent prompt
    // noisier and surfaces a privacy ask we don't honour.
    private static let quantityReadIds: [HKQuantityTypeIdentifier] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation,
        .respiratoryRate, .bodyTemperature, .stepCount, .activeEnergyBurned,
        .basalEnergyBurned, .vo2Max,
        // Body composition — READ-ONLY (#20). Imported under the apple-health source like the file
        // importer already ingests; deliberately NOT in quantityWriteIds (we never write these back).
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex
    ]
    // The daily-metric write-back scopes that have shipped since the feature existed. This is the set
    // the launch-resume gate checks (see `refreshAuthIfPreviouslyGranted`): a returning user granted
    // exactly these, so requiring the newer opt-in scopes below would fail the gate and silently strand
    // Apple Health for everyone who updates. Keep this list frozen — new write types go ONLY in the
    // extended list and must degrade per-type at their own call site.
    private static let coreQuantityWriteIds: [HKQuantityTypeIdentifier] = [
        .restingHeartRate, .heartRateVariabilitySDNN, .oxygenSaturation, .respiratoryRate,
    ]
    private static let quantityWriteIds: [HKQuantityTypeIdentifier] = coreQuantityWriteIds + [
        // Raw continuous strap HR (`writeRawHeartRate`) plus the energy/distance statistics attached
        // to written-back workouts — `HKWorkoutBuilder.addSamples` needs a share grant for EVERY
        // sample type it adds, so declining one of these on the sheet skips just that statistic. These
        // are NOT part of the launch-resume gate; each write guards its own `.sharingAuthorized`.
        .heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming
    ]

    // MARK: - Authorization

    /// Request read + write permission. HealthKit never reveals whether *read* was granted, so we
    /// treat a successful request as `.authorized` and let queries return empty if the user declined.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { auth = .unavailable; return }
        // A free-signed build (no `com.apple.developer.healthkit` entitlement) can NEVER reach Health:
        // `requestAuthorization` either throws "Missing application-identifier"/"missing entitlement"
        // or returns without ever presenting the sheet and leaves every type `.notDetermined`. Either
        // way the honest answer is "this build can't use Apple Health directly", NOT "you denied it" —
        // so never fall through to `.denied` (which tells the user to fix it in Settings, where the app
        // can never appear). Detect via the embedded provisioning profile up front (#348).
        guard HealthKitBridge.hasHealthKitEntitlement else { auth = .entitlementMissing; return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // The entitlement is present (the guard above proved it via the embedded profile, or there's
            // no profile = App Store build), so a successful request means the bridge is usable. We do
            // NOT reclassify to `.entitlementMissing` off the post-request `.notDetermined` heuristic
            // here: on a genuinely-entitled build the user could grant only reads (writes stay
            // `.notDetermined`) or dismiss the share sheet, and that must stay `.authorized` with the
            // normal Settings guidance — never the file-import reroute. The provisioning-profile check is
            // the authoritative signal; the `.notDetermined` fallback only matters when that check can't
            // run, which on iOS means an App Store build that by definition has the entitlement.
            auth = .authorized
        } catch {
            // A thrown error here is on a build that carries the entitlement (guarded above), so it's a
            // genuine denial / request failure — keep the normal `.denied` "enable in Settings" path,
            // never the entitlement-missing reroute.
            auth = .denied
        }
        // First successful grant in this process: arm the live HealthKit stream so a watch-only user
        // gets continuous ingestion (new SDNN/RHR/sleep/etc. land within the hour) instead of only on
        // app foreground. Guarded inside enableLiveDelivery on auth == .authorized, so the .denied path
        // above is a no-op.
        enableLiveDelivery()
    }

    /// The write types whose prior grant proves the user already enabled Apple Health: the frozen core
    /// daily-metric set (plus sleep). Deliberately NOT the full `writeTypes` — a returning user granted
    /// only the core scopes, so gating on the newer HR/workout/energy/distance scopes (which are
    /// `.notDetermined` until they re-consent) would make the gate fail and silently strand every
    /// existing user's Apple Health sync after an update. The new scopes degrade per-type at their
    /// own call sites instead.
    private var coreWriteTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        for id in HealthKitBridge.coreQuantityWriteIds { if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    /// Resume a prior grant on launch without re-prompting. `auth` is a fresh `.unknown` every
    /// process (the bridge isn't persisted), so a user who already enabled Apple Health would
    /// otherwise have to re-tap "Enable" each session before the scenePhase sync runs. HealthKit
    /// never reveals *read* status, but *write*/share status is observable — if the user already
    /// authorized our core write types, treat the bridge as `.authorized`. This only reads
    /// status, so no system permission sheet is shown.
    func refreshAuthIfPreviouslyGranted() {
        guard auth == .unknown, HKHealthStore.isHealthDataAvailable() else { return }
        let granted = coreWriteTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }
        if granted {
            auth = .authorized
            // A returning user who already granted access should get the live stream re-armed for this
            // process. enableLiveDelivery is idempotent (HealthKit dedups observers + background
            // delivery per type), so calling it here as well as after a fresh requestAuthorization is safe.
            enableLiveDelivery()
        }
    }

    // MARK: - Live delivery (continuous ingestion)

    /// The scored read types we want a live observer + hourly background delivery on. This is the
    /// subset of `quantityReadIds` (plus sleep) that actually feeds Charge/Rest/Effort/Fitness Age, so
    /// a watch-only user's numbers refresh on their own rather than only when the app is foregrounded.
    /// We deliberately do NOT observe the body-composition reads (weight/BMI/etc.) — those don't move a
    /// score and a manual weigh-in shouldn't wake the app every hour.
    private static let liveQuantityIds: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN, .restingHeartRate, .activeEnergyBurned, .heartRate, .vo2Max
    ]

    /// Long-lived observer queries, retained so HealthKit doesn't tear them down. Keyed by the sample
    /// type's identifier so a second `enableLiveDelivery()` call replaces rather than duplicates.
    private var observerQueries: [String: HKObserverQuery] = [:]

    /// Register one `HKObserverQuery` per scored read type and turn on hourly background delivery, so
    /// new Apple Watch data is ingested continuously. Each observer's update handler runs an anchored
    /// delta sync of just the affected window and then calls HealthKit's completion handler (required —
    /// HealthKit stops delivering to an observer that never acknowledges). Idempotent and guarded behind
    /// `auth == .authorized`; safe to call from several entry points.
    func enableLiveDelivery() {
        guard auth == .authorized, HKHealthStore.isHealthDataAvailable() else { return }

        var types: [HKSampleType] = []
        for id in HealthKitBridge.liveQuantityIds {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.append(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }

        for type in types {
            let key = type.identifier
            // Tear down a prior observer for this type before re-registering, so a re-arm (e.g. a
            // returning user hitting both requestAuthorization and refreshAuthIfPreviouslyGranted) can
            // never leave two live observers fighting over the same completion handler.
            if let existing = observerQueries[key] {
                store.stop(existing)
                observerQueries[key] = nil
            }
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                // HealthKit invokes this on a background queue. Hop to the main actor (the bridge is
                // @MainActor and `sync` mutates published state), run the incremental catch-up, then
                // ALWAYS call completion so HealthKit keeps delivering. We don't tie completion to sync
                // success: a transient store error shouldn't make HealthKit think we never handled the
                // update and back off — the next foreground catch-up will reconcile.
                guard let self else { completion(); return }
                Task { @MainActor in
                    await self.syncFromObserver(type: type)
                    completion()
                }
            }
            store.execute(observer)
            observerQueries[key] = observer

            // Hourly is the finest cadence HealthKit honours for most types and is plenty for daily
            // aggregate scores. Failure here is non-fatal: the foreground catch-up still backfills.
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// Foreground catch-up. Call on app-active so anything background delivery missed (the system can
    /// throttle or skip wakes) is backfilled. A short window is enough because live delivery keeps the
    /// recent days current; 7 covers a weekend of missed wakes. Exposed for the existing scenePhase
    /// hook in `StrandiOSApp` to call — no other file is edited.
    func foregroundCatchUp() async {
        await sync(days: 7)
    }

    /// Drive an incremental sync off an observer wake. We use an `HKAnchoredObjectQuery` per type to
    /// learn the span of days touched since we last looked (persisting the anchor so the same samples
    /// aren't walked twice and nothing between wakes is missed), then re-aggregate just that day window
    /// via the existing `sync(days:)` path. Re-aggregating the window (rather than the deltas alone)
    /// keeps every per-day average correct and idempotent — `sync` upserts are keyed by day.
    private func syncFromObserver(type: HKSampleType) async {
        guard auth == .authorized else { return }
        let touched = await fetchTouchedDayWindow(type: type)
        // No new samples since the last anchor (a spurious wake): nothing to do.
        guard let touched else { return }
        let cal = Calendar.current
        let daysBack = cal.dateComponents([.day], from: cal.startOfDay(for: touched),
                                          to: cal.startOfDay(for: Date())).day ?? 0
        // Clamp to a sane window: at least today, and never re-walk more than a month from one wake.
        let window = max(1, min(31, daysBack + 1))
        await sync(days: window)
    }

    /// Advance this type's stored anchor over any new samples and return the OLDEST sample date seen,
    /// or nil when there were no new samples. Anchors are persisted in UserDefaults per type so live
    /// deltas are neither re-ingested nor missed across launches. We don't consume the samples here —
    /// `sync(days:)` re-reads the aggregate for the affected window — the anchor's only job is to tell
    /// us how far back the change reached.
    private func fetchTouchedDayWindow(type: HKSampleType) async -> Date? {
        let key = HealthKitBridge.anchorDefaultsKey(for: type)
        let priorAnchor: HKQueryAnchor? = {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }()

        return await withCheckedContinuation { (cont: CheckedContinuation<Date?, Never>) in
            let q = HKAnchoredObjectQuery(
                type: type, predicate: Self.notNoopAuthored,
                anchor: priorAnchor, limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, _ in
                // Persist the advanced anchor so the next wake only sees genuinely-new samples. Skip the
                // write on a query error (newAnchor nil) so we don't blow away a good cursor.
                if let newAnchor,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                let oldest = (samples ?? []).map { $0.startDate }.min()
                cont.resume(returning: oldest)
            }
            store.execute(q)
        }
    }

    /// UserDefaults key for a type's persisted HealthKit anchor. Namespaced so it can't collide with
    /// other app defaults, and keyed by the stable HK identifier so it survives across launches.
    private static func anchorDefaultsKey(for type: HKSampleType) -> String {
        "hkAnchor.v1.\(type.identifier)"
    }

    // MARK: - Read → store

    /// Pull the last `days` of Apple Health into the on-device store under the `apple-health` source,
    /// then write NOOP's own computed metrics back into Health. Safe to call repeatedly (idempotent
    /// upserts keyed by day).
    func sync(days: Int = 30) async {
        guard auth == .authorized, !syncing else { return }
        syncing = true
        defer { syncing = false }
        guard let store = await repo.storeHandle() else { return }

        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) else { return }

        var byDay: [String: DayAgg] = [:]
        func agg(_ day: String) -> DayAgg { byDay[day] ?? DayAgg() }

        // Quantity aggregates per day.
        await collect(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.restingHr = v; byDay[day] = a
        }
        await collect(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.avgHr = v; byDay[day] = a
        }
        await collect(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteMax) { day, v in
            var a = agg(day); a.maxHr = v; byDay[day] = a
        }
        await collect(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.hrv = v; byDay[day] = a
        }
        await collect(.oxygenSaturation, unit: .percent(), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.spo2 = v * 100; byDay[day] = a   // 0…1 → percent
        }
        await collect(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.respRate = v; byDay[day] = a
        }
        await collect(.stepCount, unit: .count(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.steps = v; byDay[day] = a
        }
        await collect(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.activeKcal = v; byDay[day] = a
        }
        await collect(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end, op: .cumulativeSum) { day, v in
            var a = agg(day); a.basalKcal = v; byDay[day] = a
        }
        await collect(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.vo2max = v; byDay[day] = a
        }

        // Body composition — READ-ONLY import under the apple-health source (#20). Weight, lean mass
        // and BMI are point-in-time readings, so take the latest-of-day; body-fat reads fine as a
        // daily average. Body-fat HealthKit gives a 0…1 fraction, scaled to percent like spo2 above.
        await collect(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: end, op: .discreteMostRecent) { day, v in
            var a = agg(day); a.weightKg = v; byDay[day] = a
        }
        await collect(.bodyFatPercentage, unit: .percent(), start: start, end: end, op: .discreteAverage) { day, v in
            var a = agg(day); a.bodyFatPct = v * 100; byDay[day] = a   // 0…1 → percent
        }
        await collect(.leanBodyMass, unit: .gramUnit(with: .kilo), start: start, end: end, op: .discreteMostRecent) { day, v in
            var a = agg(day); a.leanMassKg = v; byDay[day] = a
        }
        await collect(.bodyMassIndex, unit: .count(), start: start, end: end, op: .discreteMostRecent) { day, v in
            var a = agg(day); a.bmi = v; byDay[day] = a
        }

        // Sleep minutes per day (asleep stages summed; attributed to wake day).
        await collectSleep(start: start, end: end) { day, asleepMin, deepMin, remMin, coreMin in
            var a = agg(day)
            a.asleepMin = asleepMin; a.deepMin = deepMin; a.remMin = remMin; a.coreMin = coreMin
            byDay[day] = a
        }

        // Build + upsert the store rows under the apple-health source.
        let appleRows = byDay.map { (day, a) in
            AppleDaily(day: day, steps: a.steps.map { Int($0) },
                       activeKcal: a.activeKcal, basalKcal: a.basalKcal, vo2max: a.vo2max,
                       avgHr: a.avgHr.map { Int($0.rounded()) }, maxHr: a.maxHr.map { Int($0.rounded()) },
                       walkingHr: nil, weightKg: a.weightKg)
        }
        let dmRows = byDay.map { (day, a) in
            DailyMetric(day: day, totalSleepMin: a.asleepMin, efficiency: nil,
                        deepMin: a.deepMin, remMin: a.remMin, lightMin: a.coreMin, disturbances: nil,
                        restingHr: a.restingHr.map { Int($0.rounded()) }, avgHrv: a.hrv,
                        recovery: nil, strain: nil, exerciseCount: nil,
                        spo2Pct: a.spo2, skinTempDevC: nil, respRateBpm: a.respRate)
        }
        // Flatten to the generic metricSeries the shared Apple Health screen, the Today apple-health
        // sparklines, and the Metric Explorer read from — repo.series(key:source:"apple-health")
        // queries ONLY metricSeries, so without this every tile/chart renders "—" after a successful
        // sync. Reuse the importer's canonical key mapping so the keys match the macOS path exactly.
        // Body composition (weight/body_fat/lean_mass/bmi) now reads live on iOS (#20) and flows
        // through the same metricPoints keys as the file importer. iOS still doesn't collect
        // awake/in-bed minutes, so those stay nil and emit no points — correct.
        let aggregates = byDay.map { (day, a) in
            AppleDailyAggregate(
                day: day,
                restingHr: a.restingHr,
                hrvSDNN: a.hrv,
                spo2Pct: a.spo2,
                respRate: a.respRate,
                avgHr: a.avgHr,
                maxHr: a.maxHr,
                steps: a.steps,
                activeKcal: a.activeKcal,
                basalKcal: a.basalKcal,
                vo2max: a.vo2max,
                weightKg: a.weightKg,
                bodyFatPct: a.bodyFatPct,
                leanMassKg: a.leanMassKg,
                bmi: a.bmi,
                asleepMin: a.asleepMin,
                deepMin: a.deepMin,
                remMin: a.remMin,
                coreMin: a.coreMin
            )
        }
        let points = AppleHealthAggregator.metricPoints(aggregates)
            .map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }

        // Workouts the user logged in Apple Health (Apple Watch rings, gym apps, etc.). macOS already
        // imports these from a static Health export and Android reads them from Health Connect; iOS now
        // reads them live on-device too, so the platforms reach parity. ON-DEVICE ONLY: this is a plain
        // HealthKit read of workouts NOOP did NOT author, never any cloud/3rd-party API. (#835)
        let workoutRows = await collectWorkouts(start: start, end: end)

        // Persist all the apple-health rows AND write back, advancing lastSync only when the WHOLE
        // round-trip succeeds. The three read-side upserts used to be swallowed by `try?`, so a failed
        // import (e.g. a disk-full GRDB write) dropped rows yet still cleared lastError and advanced
        // lastSync — a false "success", and the next delta sync skipped the window. (Reimplemented
        // from @vulnix0x4's PR #375.)
        do {
            try await store.upsertAppleDaily(appleRows, deviceId: appleDeviceId)
            try await store.upsertDailyMetrics(dmRows, deviceId: appleDeviceId)
            try await store.upsertMetricSeries(points, deviceId: appleDeviceId)
            if !workoutRows.isEmpty { try await store.upsertWorkouts(workoutRows, deviceId: appleDeviceId) }
            try await writeBack(whoopStore: store)
            // The raw HR stream and NOOP-authored workouts ride the same gate: a failure in any
            // write leaves lastSync unadvanced so the next sync retries the whole round-trip.
            try await writeRawHeartRate(whoopStore: store)
            try await writeWorkouts(whoopStore: store)
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = String(localized: "Apple Health sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Write back (NOOP → Health)

    /// Write NOOP's strap-derived daily metrics (resting HR, HRV, SpO₂, respiratory rate) into Apple
    /// Health so they appear across the user's Health ecosystem.
    ///
    /// Dedup model: each emitted sample carries a deterministic `HKMetadataKeyExternalUUID` derived
    /// from `noopDeviceId + metric + day`. Before saving, we delete any of *our* prior samples that
    /// carry the same key (scoped to `HKSource.default()` so we never touch another app's data) and
    /// then save the fresh batch. HealthKit assigns a new UUID per save, so the previous strategy
    /// (no metadata, no delete) flooded Health with duplicates on every `sync()`.
    ///
    /// Throws on save failure so the caller can decide whether to advance `lastSync`.
    private func writeBack(whoopStore: WhoopStore, days: Int = 14) async throws {
        guard auth == .authorized else { return }
        let cal = Calendar.current
        let to = HealthKitBridge.dayString(Date())
        guard let fromDate = cal.date(byAdding: .day, value: -days, to: Date()) else { return }
        let from = HealthKitBridge.dayString(fromDate)
        // Read NOOP's COMPUTED dailies (deviceId + "-noop"), which is the only place a strap-only
        // user's recovery/HRV/RHR/SpO₂/resp lives, then union with any imported `noopDeviceId` rows so
        // a user who ALSO imported a WHOOP export still gets the imported values. Imported overrides
        // computed per day, matching the dashboard's source precedence.
        let computed = (try? await whoopStore.dailyMetrics(deviceId: computedDeviceId, from: from, to: to)) ?? []
        let imported = (try? await whoopStore.dailyMetrics(deviceId: noopDeviceId, from: from, to: to)) ?? []
        var byDay: [String: DailyMetric] = [:]
        for r in computed { byDay[r.day] = r }   // computed first
        for r in imported { byDay[r.day] = r }   // imported overrides
        let rows = byDay.keys.sorted().map { byDay[$0]! }

        struct Candidate { let type: HKQuantityType; let key: String; let sample: HKQuantitySample }
        var candidates: [Candidate] = []
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, _ day: String, _ at: Date) {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
            let key = "noop:\(noopDeviceId):\(id.rawValue):\(day)"
            let sample = HKQuantitySample(
                type: type,
                quantity: .init(unit: unit, doubleValue: value),
                start: at, end: at,
                metadata: [HKMetadataKeyExternalUUID: key]
            )
            candidates.append(Candidate(type: type, key: key, sample: sample))
        }

        for row in rows {
            guard let date = HealthKitBridge.date(from: row.day) else { continue }
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            if let rhr = row.restingHr {
                add(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), Double(rhr), row.day, noon)
            }
            if let hrv = row.avgHrv {
                add(.heartRateVariabilitySDNN, .secondUnit(with: .milli), hrv, row.day, noon)
            }
            if let spo2 = row.spo2Pct {
                add(.oxygenSaturation, .percent(), spo2 / 100, row.day, noon)
            }
            if let rr = row.respRateBpm {
                add(.respiratoryRate, HKUnit.count().unitDivided(by: .minute()), rr, row.day, noon)
            }
        }
        guard !candidates.isEmpty else { return }

        // Delete any of OUR prior samples that carry the same metadata keys, then write the fresh
        // batch. Scoped to HKSource.default() so we never touch a sample written by another app
        // that happens to use the same external UUID. Delete failures are non-fatal (e.g., nothing
        // to delete on first run) — only the save throws.
        let bySource = HKQuery.predicateForObjects(from: HKSource.default())
        let grouped = Dictionary(grouping: candidates, by: { $0.type })
        for (type, items) in grouped {
            let keys = Array(Set(items.map { $0.key }))
            let byKey = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                    allowedValues: keys)
            let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [bySource, byKey])
            _ = try? await self.store.deleteObjects(of: type, predicate: pred)
        }
        try await self.store.save(candidates.map { $0.sample })
    }

    // MARK: - Raw heart-rate write (NOOP → Health)

    /// Persisted `"count:maxTs"` fingerprint of the HR rows last written to Health for one strap-day,
    /// so an unchanged day is a single cheap COUNT query and only a day whose SOURCE actually changed
    /// (live tail growth, or a backfilled offload landing OLD samples) is re-materialized. A per-day
    /// key rather than one forward watermark: a forward watermark skips a night backfilled AFTER it
    /// already advanced, leaving that day permanently absent from Health.
    private static func hrDayStateKey(device: String, day: String) -> String {
        "noop.health.hrDayFp.\(device).\(day)"
    }

    /// How many days back (including today) each sync reconsiders. Covers today (still filling) plus a
    /// couple of prior days so a historical offload that lands after a live sync already ran is still
    /// written. Each already-written prior day is a one-COUNT skip until its source changes.
    private static let hrLookbackDays = 3

    /// `.heartRate` samples per `HKHealthStore.save` call. A fully-worn day is ~86k 1 Hz rows;
    /// materializing + saving the whole window in one shot spikes memory and hands HealthKit one
    /// enormous transaction, so the write is chunked and each chunk's HK objects are built lazily.
    private static let hrSaveChunkSize = 10_000

    /// Write the strap's raw continuous heart-rate stream into Apple Health as loose `.heartRate`
    /// samples, so Health's Heart Rate chart (and every app reading it) sees the strap like a worn
    /// watch. Walks the last `hrLookbackDays` strap-days; each day is fingerprint-gated so an
    /// unchanged one costs one COUNT, a growing "today" appends only its new tail, and a day that
    /// gained backfilled samples is fully re-materialized (delete + save) — never appended past, so
    /// no night can end up permanently missing. Deliberately NOT attached to workouts — Health derives
    /// a workout's HR display from loose samples covering its span.
    private func writeRawHeartRate(whoopStore: WhoopStore) async throws {
        guard auth == .authorized,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
              // The user can decline JUST this scope on the share sheet — skip silently rather
              // than failing the whole sync.
              self.store.authorizationStatus(for: type) == .sharingAuthorized else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Oldest → newest so the live tail (today) is written last.
        for offset in stride(from: HealthKitBridge.hrLookbackDays - 1, through: 0, by: -1) {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            try await writeRawHRForDay(whoopStore: whoopStore, type: type,
                                       dayStart: dayStart, dayEnd: dayEnd)
        }
    }

    /// One strap-day of raw HR into Health, fingerprint-gated. Fast paths: unchanged day → skip; pure
    /// tail growth → append only samples past the last written max; otherwise (first write of the day,
    /// or a backfill that inserted OLD samples) → delete our prior HR for the day and re-save it whole.
    private func writeRawHRForDay(whoopStore: WhoopStore, type: HKQuantityType,
                                  dayStart: Date, dayEnd: Date) async throws {
        let from = Int(dayStart.timeIntervalSince1970)
        let to = Int(dayEnd.timeIntervalSince1970) - 1

        let fp = (try? await whoopStore.hrFingerprint(deviceId: noopDeviceId, from: from, to: to))
            ?? (count: 0, maxTs: 0)
        guard fp.count > 0 else { return }   // nothing recorded this day

        let stateKey = HealthKitBridge.hrDayStateKey(
            device: noopDeviceId, day: HealthKitBridge.dayString(dayStart))
        let token = "\(fp.count):\(fp.maxTs)"
        let prior = UserDefaults.standard.string(forKey: stateKey)
        if prior == token { return }   // source byte-identical to what we last wrote → skip

        var priorCount = 0, priorMaxTs = 0
        if let prior {
            let parts = prior.split(separator: ":")
            if parts.count == 2, let c = Int(parts[0]), let m = Int(parts[1]) { priorCount = c; priorMaxTs = m }
        }

        // Fast path — pure tail growth (today filling in). The max moved forward and the WHOLE day's
        // count grew by exactly the number of new samples after the old max (i.e. nothing was inserted
        // before it), so append just the tail with no delete. A backfill that also inserted older
        // samples fails this equality and falls through to a full rewrite.
        if priorCount > 0, fp.maxTs > priorMaxTs {
            let tailFp = (try? await whoopStore.hrFingerprint(
                deviceId: noopDeviceId, from: priorMaxTs + 1, to: to)) ?? (count: 0, maxTs: 0)
            if fp.count == priorCount + tailFp.count {
                let tail = try await whoopStore.hrSamples(
                    deviceId: noopDeviceId, from: priorMaxTs + 1, to: to, limit: 250_000)
                    .filter { (30...220).contains($0.bpm) }
                try await saveHRSamples(tail, type: type)
                UserDefaults.standard.set(token, forKey: stateKey)
                return
            }
        }

        // Full rewrite: first write of this day, or a backfill inserted OLD samples. Delete OUR prior
        // HR for the day (scoped to HKSource.default() so another app's HR is untouched), then re-save
        // the whole day — gap-free and idempotent.
        let windowPred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate),
        ])
        _ = try? await self.store.deleteObjects(of: type, predicate: windowPred)

        let rows = try await whoopStore.hrSamples(deviceId: noopDeviceId, from: from, to: to, limit: 250_000)
            .filter { (30...220).contains($0.bpm) }
        try await saveHRSamples(rows, type: type)
        // Record the fingerprint only after every chunk landed, so a mid-save throw re-writes next time.
        UserDefaults.standard.set(token, forKey: stateKey)
    }

    /// Save HR samples in bounded chunks, materializing each chunk's HK objects lazily to cap memory.
    private func saveHRSamples(_ rows: [HRSample], type: HKQuantityType) async throws {
        guard !rows.isEmpty else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        for chunkStart in stride(from: 0, to: rows.count, by: HealthKitBridge.hrSaveChunkSize) {
            let chunk = rows[chunkStart..<min(chunkStart + HealthKitBridge.hrSaveChunkSize, rows.count)]
            let samples = chunk.map { s -> HKQuantitySample in
                let at = Date(timeIntervalSince1970: TimeInterval(s.ts))
                return HKQuantitySample(
                    type: type,
                    quantity: .init(unit: unit, doubleValue: Double(s.bpm)),
                    start: at, end: at,
                    metadata: [HKMetadataKeyExternalUUID: "noop:hr:\(noopDeviceId):\(s.ts)"])
            }
            try await self.store.save(samples)
        }
    }

    // MARK: - Workout write (NOOP → Health)

    /// Write NOOP-authored workouts into Apple Health as real `HKWorkout`s (via `HKWorkoutBuilder` —
    /// the `HKWorkout` convenience initializers are deprecated on our floor), so a strap-tracked or
    /// manually-logged session closes rings and shows in Fitness like any watch workout.
    ///
    /// Only detected / manual / lifting / activity-file rows are written: an `.apple` row came FROM
    /// Health (writing it back would round-trip duplicate) and a `.whoop` row is official-app-era
    /// history the WHOOP app likely already wrote to Health itself.
    ///
    /// Low churn: a row whose deterministic external UUID already exists among OUR workouts in the
    /// window is skipped, never blindly re-created (Health treats each save as a fresh workout event,
    /// so re-saving unchanged rows would spam activity history). But OUR in-window workouts that no
    /// current row maps to ARE deleted — an edit changes the (startTs, sport) key, and a dismissed or
    /// deleted bout should leave Health — so the write is a reconcile, not an append-only skip.
    private func writeWorkouts(whoopStore: WhoopStore, days: Int = 14) async throws {
        guard auth == .authorized,
              // The user can decline just the workout scope; skip silently.
              self.store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        else { return }

        let now = Int(Date().timeIntervalSince1970)
        let from = now - days * 86_400

        // Detected bouts live under the computed id; live/manual/lifting/file sessions under the
        // strap id. Union both, imported over computed on a (startTs, sport) collision — the same
        // precedence writeBack applies to the daily metrics.
        // Detected bouts live under the computed id, live/manual sessions under the strap id — but
        // imported LIFTING (Hevy/Liftosaur) and ACTIVITY-FILE (GPX/TCX/FIT) sessions each live under
        // their OWN source id, so they must be queried explicitly or the `.lifting`/`.activityFile`
        // cases in the source filter below could never match and those workouts would silently never
        // reach Health.
        let computed = (try? await whoopStore.workouts(deviceId: computedDeviceId, from: from, to: now)) ?? []
        let imported = (try? await whoopStore.workouts(deviceId: noopDeviceId, from: from, to: now)) ?? []
        let lifting = (try? await whoopStore.workouts(deviceId: LiftingImporter.sourceId, from: from, to: now)) ?? []
        let activityFile = (try? await whoopStore.workouts(deviceId: ActivityFileImporter.sourceId, from: from, to: now)) ?? []
        // Apple-imported sessions (under appleDeviceId) are NEVER written back, but they ARE needed as
        // "real" rows so a detected bout that merely shadows an Apple-logged session is dropped rather
        // than written as its duplicate (Health already holds the Apple one).
        let appleReals = (try? await whoopStore.workouts(deviceId: appleDeviceId, from: from, to: now)) ?? []
        var byKey: [String: WorkoutRow] = [:]
        for r in computed { byKey["\(r.startTs):\(r.sport)"] = r }
        for r in imported { byKey["\(r.startTs):\(r.sport)"] = r }
        for r in lifting { byKey["\(r.startTs):\(r.sport)"] = r }
        for r in activityFile { byKey["\(r.startTs):\(r.sport)"] = r }
        for r in appleReals where byKey["\(r.startTs):\(r.sport)"] == nil { byKey["\(r.startTs):\(r.sport)"] = r }

        // Apply the SAME suppression the workout list applies before it ever shows a detected bout,
        // because Health has no removal path once we write: (1) drop a detected row the user explicitly
        // dismissed as "not a workout" (#107 — a durable UserDefaults span list, since the engine
        // re-derives detected rows every run and a table delete wouldn't stick); (2) drop a detected
        // shadow of a real logged session (#975). Skipping these here is what keeps a dismissed
        // false-positive or a transient live+detected twin out of Apple Health for good.
        let dismissedSpans = WorkoutSource.parseDismissedSpans(
            UserDefaults.standard.stringArray(forKey: WorkoutSource.dismissedDefaultsKey) ?? [])
        let visible = byKey.values.filter { !WorkoutSource.isDismissed($0, spans: dismissedSpans) }
        let deShadowed = WorkoutSource.dropDetectedShadows(Array(visible))

        // NOOP-authored sources only — never round-trip an Apple Health import, never re-write
        // official-app history (see the type doc above).
        let rows = deShadowed
            .filter { row in
                switch WorkoutSource.classify(row.source) {
                case .apple, .whoop: return false
                case .detected, .manual, .lifting, .activityFile: return true
                }
            }
            .sorted { $0.startTs < $1.startTs }
        guard !rows.isEmpty else { return }

        let existing = await existingNoopWorkouts(
            start: Date(timeIntervalSince1970: TimeInterval(from)),
            end: Date(timeIntervalSince1970: TimeInterval(now + 1)))

        // Reconcile: delete OUR in-window workouts that no CURRENT desired row maps to. Without this,
        // editing a workout's sport or start time (which changes the deterministic key) births a second
        // HKWorkout while the stale one lingers, and a since-dismissed/deleted bout stays in Health
        // forever — the skip-if-key-exists path alone never removes anything. Scoped to OUR source and
        // the window, so another app's data and older-than-window history are untouched.
        let desiredKeys = Set(rows.map { "noop:workout:\($0.startTs):\($0.sport)" })
        let orphans = existing.filter { !desiredKeys.contains($0.key) }.map { $0.value }
        if !orphans.isEmpty { try? await self.store.delete(orphans) }

        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        for row in rows {
            let key = "noop:workout:\(row.startTs):\(row.sport)"
            if existing[key] != nil { continue }
            // HealthKit rejects a zero/negative span — such a row can't make an honest workout.
            guard row.endTs > row.startTs else { continue }
            // Skip a row that hasn't finished yet (a manual entry whose start+duration lands in the
            // future): finishWorkout with a future end throws, and rethrowing would fail the WHOLE
            // Apple Health round-trip on every sync until the clock passes it. It exports next sync
            // once the end is in the past.
            guard row.endTs <= now else { continue }
            let start = Date(timeIntervalSince1970: TimeInterval(row.startTs))
            let end = Date(timeIntervalSince1970: TimeInterval(row.endTs))

            let config = HKWorkoutConfiguration()
            config.activityType = HealthKitBridge.activityType(row.sport)
            let builder = HKWorkoutBuilder(healthStore: self.store, configuration: config, device: .local())
            do {
                try await builder.beginCollection(at: start)

                // Attach total energy / distance as samples spanning the workout. Each sample type
                // needs its own share grant (they're listed individually on the sheet), so a
                // declined scope drops just that statistic. Deliberately NO child HR samples:
                // writeRawHeartRate already writes the same period's loose HR and children would
                // double-write — Health computes the workout's HR display from the loose samples.
                var samples: [HKSample] = []
                if let kcal = row.energyKcal, kcal > 0, let energyType,
                   self.store.authorizationStatus(for: energyType) == .sharingAuthorized {
                    samples.append(HKQuantitySample(
                        type: energyType,
                        quantity: .init(unit: .kilocalorie(), doubleValue: kcal),
                        start: start, end: end))
                }
                if let meters = row.distanceM, meters > 0,
                   let distId = HealthKitBridge.distanceTypeId(for: config.activityType),
                   let distType = HKQuantityType.quantityType(forIdentifier: distId),
                   self.store.authorizationStatus(for: distType) == .sharingAuthorized {
                    samples.append(HKQuantitySample(
                        type: distType,
                        quantity: .init(unit: .meter(), doubleValue: meters),
                        start: start, end: end))
                }
                if !samples.isEmpty { try await builder.addSamples(samples) }

                try await builder.endCollection(at: end)
                try await builder.addMetadata([
                    HKMetadataKeyExternalUUID: key,
                    HKMetadataKeyWorkoutBrandName: "NOOP",
                ])
                _ = try await builder.finishWorkout()
            } catch {
                // Abandon the half-built workout so HealthKit doesn't hold an open builder, then move
                // on to the next row. A single malformed/rejected workout must NOT strand the whole
                // Apple Health sync (which would leave lastSync unadvanced and retry everything each
                // pass); this row simply isn't keyed as written, so a later sync retries just it.
                builder.discardWorkout()
                continue
            }
        }
    }

    /// OUR workouts already in Health with a start in `[start, end)`, mapped by their deterministic
    /// external-UUID key. Scoped to HKSource.default() so another app's workouts — even ones carrying
    /// an external UUID — are never counted as ours. Returns the objects (not just keys) so the caller
    /// can both skip re-writing unchanged rows AND delete orphans (rows since edited, deleted, or
    /// dismissed — whose old key no longer maps to any desired row).
    private func existingNoopWorkouts(start: Date, end: Date) async -> [String: HKWorkout] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
        ])
        return await withCheckedContinuation { (cont: CheckedContinuation<[String: HKWorkout], Never>) in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var byKey: [String: HKWorkout] = [:]
                for case let w as HKWorkout in samples ?? [] {
                    if let id = w.metadata?[HKMetadataKeyExternalUUID] as? String { byKey[id] = w }
                }
                cont.resume(returning: byKey)
            }
            store.execute(q)
        }
    }

    private struct DayAgg {
        var restingHr: Double?; var avgHr: Double?; var maxHr: Double?; var hrv: Double?
        var spo2: Double?; var respRate: Double?; var steps: Double?
        var activeKcal: Double?; var basalKcal: Double?; var vo2max: Double?
        var weightKg: Double?; var bodyFatPct: Double?; var leanMassKg: Double?; var bmi: Double?
        var asleepMin: Double?; var deepMin: Double?; var remMin: Double?; var coreMin: Double?
    }

    /// Excludes NOOP's own write-back samples from reads, so the two-way sync never reads its own
    /// output back in as "apple-health" data — which would make the strap and "Apple Health" plot the
    /// same line for a strap-only user, and bias the apple-health average for someone who also has a
    /// watch. `HKSource.default()` is this app's own source. (Reimplemented from @vulnix0x4's PR #375.)
    private static var notNoopAuthored: NSPredicate {
        NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: [HKSource.default()]))
    }

    private func collect(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date,
                         op: HKStatisticsOptions, sink: @escaping (String, Double) -> Void) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: start)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            Self.notNoopAuthored,
        ])
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                options: op, anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let q: HKQuantity?
                    switch op {
                    case .cumulativeSum:     q = stats.sumQuantity()
                    case .discreteAverage:   q = stats.averageQuantity()
                    case .discreteMax:       q = stats.maximumQuantity()
                    case .discreteMostRecent: q = stats.mostRecentQuantity()
                    default:                 q = stats.averageQuantity()
                    }
                    if let q { sink(HealthKitBridge.dayString(stats.startDate), q.doubleValue(for: unit)) }
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    private func collectSleep(start: Date, end: Date,
                              sink: @escaping (String, Double?, Double?, Double?, Double?) -> Void) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: []),
            Self.notNoopAuthored,
        ])
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var asleep: [String: Double] = [:], deep: [String: Double] = [:]
                var rem: [String: Double] = [:], core: [String: Double] = [:]
                for case let s as HKCategorySample in samples ?? [] {
                    let mins = s.endDate.timeIntervalSince(s.startDate) / 60
                    let day = HealthKitBridge.dayString(s.endDate)
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep[day, default: 0] += mins; asleep[day, default: 0] += mins
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem[day, default: 0] += mins; asleep[day, default: 0] += mins
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core[day, default: 0] += mins; asleep[day, default: 0] += mins
                    default:
                        break
                    }
                }
                for day in Set(asleep.keys) {
                    sink(day, asleep[day], deep[day], rem[day], core[day])
                }
                cont.resume()
            }
            store.execute(q)
        }
    }

    // MARK: - Workouts (#835)

    /// Read the workouts the user logged in Apple Health over `[start, end)` and map each to a
    /// `WorkoutRow` under the apple-health source. ON-DEVICE ONLY: a straight HealthKit `HKWorkout` query,
    /// no cloud or third-party API. NOOP-authored workouts are excluded (the same `notNoopAuthored`
    /// predicate the metric reads use) so our own write-back never re-imports as "Apple Health". Mirrors
    /// the macOS export importer and the Android Health Connect importer, which already ingest workouts,
    /// closing the iOS gap. The upsert is idempotent on (deviceId, startTs), so re-running a sync window
    /// refreshes rather than duplicates.
    private func collectWorkouts(start: Date, end: Date) async -> [WorkoutRow] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            Self.notNoopAuthored,
        ])
        return await withCheckedContinuation { (cont: CheckedContinuation<[WorkoutRow], Never>) in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                var rows: [WorkoutRow] = []
                for case let workout as HKWorkout in samples ?? [] {
                    let startTs = Int(workout.startDate.timeIntervalSince1970)
                    let endTs = max(Int(workout.endDate.timeIntervalSince1970), startTs)
                    let duration = workout.duration > 0 ? workout.duration : Double(endTs - startTs)
                    rows.append(WorkoutRow(
                        startTs: startTs,
                        endTs: endTs,
                        sport: Self.sportName(workout.workoutActivityType),
                        source: HealthKitBridge.appleWorkoutSource,
                        durationS: duration,
                        energyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        avgHr: nil,
                        maxHr: nil,
                        strain: nil,
                        distanceM: workout.totalDistance?.doubleValue(for: .meter()),
                        zonesJSON: nil,
                        notes: nil))
                }
                cont.resume(returning: rows)
            }
            store.execute(q)
        }
    }

    /// Source tag stamped on workouts imported from Apple Health. Matches the macOS importer's
    /// `WorkoutSource.appleHealthSource` ("apple-health") and `appleDeviceId`, so the workout list and
    /// source filters treat an iOS-read workout exactly like a macOS-imported one.
    static let appleWorkoutSource = "apple-health"

    /// Map an `HKWorkoutActivityType` to NOOP's human sport label. Strength training routes to the
    /// shared lifting sport so a gym session lands in the Lifting lane; anything we don't name explicitly
    /// falls back to a generic "Workout" rather than an opaque numeric type.
    private static func sportName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                    return "Running"
        case .walking:                    return "Walking"
        case .hiking:                     return "Hiking"
        case .cycling:                    return "Cycling"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining: return LiftingImporter.sport
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining:               return "Core training"
        case .yoga:                       return "Yoga"
        case .pilates:                    return "Pilates"
        case .rowing:                     return "Rowing"
        case .elliptical:                 return "Elliptical"
        case .stairClimbing, .stairs:     return "Stairs"
        case .jumpRope:                   return "Jump rope"
        case .boxing, .kickboxing:        return "Boxing"
        case .basketball:                 return "Basketball"
        case .soccer:                     return "Soccer"
        case .americanFootball:           return "Football"
        case .baseball:                   return "Baseball"
        case .badminton:                  return "Badminton"
        case .tennis:                     return "Tennis"
        case .tableTennis:                return "Table tennis"
        case .volleyball:                 return "Volleyball"
        case .squash, .racquetball:       return "Squash"
        case .martialArts, .taiChi:       return "Martial arts"
        case .dance, .cardioDance, .socialDance: return "Dancing"
        case .golf:                       return "Golf"
        case .climbing:                   return "Climbing"
        case .downhillSkiing, .crossCountrySkiing: return "Skiing"
        case .snowboarding:               return "Snowboarding"
        case .swimming:                   return "Swimming"
        case .surfingSports:              return "Surfing"
        case .paddleSports:               return "Paddling"
        default:                          return "Workout"
        }
    }

    /// Invert `sportName` for the workout write-back: NOOP's sport label → the HK activity type a
    /// written workout is stamped with. Labels that fold several HK types to one name pick the
    /// most common member (e.g. "Boxing" → .boxing, "Skiing" → .downhillSkiing); anything unnamed —
    /// including the detector's "detected" token and free-typed manual sports — writes as `.other`.
    /// KEEP IN LOCKSTEP with `sportName` above.
    private static func activityType(_ sport: String) -> HKWorkoutActivityType {
        switch sport {
        case "Running":              return .running
        case "Walking":              return .walking
        case "Hiking":               return .hiking
        case "Cycling":              return .cycling
        case LiftingImporter.sport:  return .traditionalStrengthTraining
        case "HIIT":                 return .highIntensityIntervalTraining
        case "Core training":        return .coreTraining
        case "Yoga":                 return .yoga
        case "Pilates":              return .pilates
        case "Rowing":               return .rowing
        case "Elliptical":           return .elliptical
        case "Stairs":               return .stairClimbing
        case "Jump rope":            return .jumpRope
        case "Boxing":               return .boxing
        case "Basketball":           return .basketball
        case "Soccer":               return .soccer
        case "Football":             return .americanFootball
        case "Baseball":             return .baseball
        case "Badminton":            return .badminton
        case "Tennis":               return .tennis
        case "Table tennis":         return .tableTennis
        case "Volleyball":           return .volleyball
        case "Squash":               return .squash
        case "Martial arts":         return .martialArts
        // .dance is deprecated (iOS 14) in favor of the cardio/social split; write-back picks the
        // exercise-shaped member since a strap-detected "Dancing" bout is cardio by construction.
        case "Dancing":              return .cardioDance
        case "Golf":                 return .golf
        case "Climbing":             return .climbing
        case "Skiing":               return .downhillSkiing
        case "Snowboarding":         return .snowboarding
        case "Swimming":             return .swimming
        case "Surfing":              return .surfingSports
        case "Paddling":             return .paddleSports
        default:                     return .other
        }
    }

    /// The HK distance quantity a given activity's total distance belongs under; nil when the
    /// activity has no matching distance type (then the row's distance is simply not written —
    /// stamping, say, a rowing distance as walking/running would corrupt the user's move data).
    private static func distanceTypeId(for activity: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .running, .walking, .hiking: return .distanceWalkingRunning
        case .cycling:                    return .distanceCycling
        case .swimming:                   return .distanceSwimming
        default:                          return nil
        }
    }

    // MARK: - Entitlement detection (#348)

    /// True when this running build actually carries the `com.apple.developer.healthkit` entitlement —
    /// i.e. it can genuinely reach Apple Health. False for a free-Apple-ID / AltStore / Sideloadly
    /// re-sign, which strips the HealthKit capability: the framework links and `isHealthDataAvailable()`
    /// is still true, but `requestAuthorization` is a dead-end and the app can never appear under
    /// Settings › Health › Data Access & Devices.
    ///
    /// Resolution order (most authoritative first), mirroring `IOSDiagnostics`'s profile parse:
    ///  1. If an `embedded.mobileprovision` is present (every dev / sideloaded / TestFlight build ships
    ///     one), slice the wrapped XML plist and look for `com.apple.developer.healthkit` in its
    ///     `Entitlements` dict. A free re-sign re-writes this profile WITHOUT that key. This is the
    ///     definitive signal and is unaffected by whether the user later granted/denied permission.
    ///  2. No embedded profile → an App Store install (App Store strips it). Those are properly signed
    ///     with whatever capabilities the app declares, so treat the entitlement as PRESENT. This is the
    ///     conservative default: it never down-routes a legitimately-signed build, so a user who simply
    ///     denied permission keeps the normal Settings guidance rather than the file-import reroute.
    ///
    /// Computed once and cached: the bundle's profile can't change within a process lifetime.
    static let hasHealthKitEntitlement: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            // No embedded profile = App Store build = properly signed. Assume present.
            return true
        }
        guard let xmlStart = data.range(of: Data("<?xml".utf8)),
              let xmlEnd = data.range(of: Data("</plist>".utf8)) else {
            // Profile present but unparseable — don't claim a missing entitlement off a parse failure;
            // assume present so we never wrongly down-route a real build.
            return true
        }
        let plistData = data.subdata(in: xmlStart.lowerBound..<xmlEnd.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            return true
        }
        // The key is present (and truthy) on an entitled build; a free re-sign omits it entirely.
        return entitlements["com.apple.developer.healthkit"] != nil
    }()

    // MARK: - Date helpers

    // LOCAL civil day: the rest of the store keys days by the device-local civil day —
    // AppleHealthAggregator.localDay shifts each sample into its own offset, and
    // Repository.dayFormatter leaves timeZone at the default (local) zone. The
    // HKStatisticsCollectionQuery here already buckets in Calendar.current (anchor =
    // startOfDay, interval = 1 day), so labelling those local-midnight bucket starts with a
    // matching local formatter is strictly 1:1; using UTC instead mislabelled a full local day
    // under the previous UTC date for users east of UTC, so apple-health rows never merged with
    // the strap-computed/imported rows for the same civil day.
    // `nonisolated` so the HealthKit query completion handlers — which HealthKit invokes on a private
    // background queue (a nonisolated context) — can label day buckets without a main-actor-isolation
    // warning. They only read a thread-safe DateFormatter, so this is safe off the main actor.
    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone.current; return f
    }()
    nonisolated private static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    nonisolated private static func date(from day: String) -> Date? { dayFormatter.date(from: day) }
}
#endif
