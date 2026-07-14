#if os(iOS)
import Foundation
import AppIntents

// The ACTION intents (MarkMomentIntent, BuzzStrapIntent) and their PendingIntents queue moved to
// StrandiOSShared/AppIntents.swift so the widget extension's interactive buttons can fire them too.
// This file keeps what is app-target-ONLY: the read-side intents (they reach the live AppModel /
// Repository, which the widget extension doesn't compile) and the single AppShortcutsProvider.

/// Read-side failure. Mirrors the macOS twin's `NOOPIntentError` style: a clear "open NOOP" message
/// instead of a silent no-op, since the snapshot only exists after the app has run once.
enum NOOPReadError: Error, CustomLocalizedStringResourceConvertible {
    case noData
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noData: return "No NOOP data yet. Open NOOP once so it can sync your latest scores."
        }
    }
}

// The read intents are snapshot-FIRST: `WidgetSnapshot.load()` needs no live process, so Siri can
// answer with the app closed (no openAppWhenRun). The live model is only the fallback for the window
// where the app is running but hasn't published that snapshot field yet — it reads the SAME
// `Repository.widgetAnchor` day the snapshot publish does, so the two paths never disagree about
// which day they describe.

/// Read today's recovery (Charge) score, 0–100.
struct GetRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Recovery"
    static var description = IntentDescription("Read today's NOOP recovery (Charge) score, 0 to 100.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        var value = WidgetSnapshot.load()?.recovery
        if value == nil, let model = AppModel.shared {
            value = Repository.widgetAnchor(days: model.repo.days)?.recovery.map { Int($0.rounded()) }
        }
        guard let value else { throw NOOPReadError.noData }
        return .result(value: value, dialog: "Your recovery is \(value) percent.")
    }
}

/// Read today's strain (Effort). Stays on NOOP's 0–100 axis (`StrainScorer.maxStrain == 100`), the
/// same value the widget publishes — never converted to WHOOP's 0–21 display toggle.
struct GetStrainIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Strain"
    static var description = IntentDescription("Read today's NOOP strain (Effort) on the 0 to 100 scale.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        var value = WidgetSnapshot.load()?.effort
        if value == nil, let model = AppModel.shared {
            value = Repository.widgetAnchor(days: model.repo.days)?.strain.map { Int($0.rounded()) }
        }
        guard let value else { throw NOOPReadError.noData }
        return .result(value: value, dialog: "Your strain is \(value) out of 100.")
    }
}

/// Read the anchor day's overnight HRV, in milliseconds.
struct GetHRVIntent: AppIntent {
    static var title: LocalizedStringResource = "Get HRV"
    static var description = IntentDescription("Read your latest overnight HRV, in milliseconds.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        var value = WidgetSnapshot.load()?.hrv
        if value == nil, let model = AppModel.shared {
            value = Repository.widgetAnchor(days: model.repo.days)?.avgHrv.map { Int($0.rounded()) }
        }
        guard let value else { throw NOOPReadError.noData }
        return .result(value: value, dialog: "Your HRV is \(value) milliseconds.")
    }
}

/// Read the anchor day's Rest (sleep performance) score, 0–100.
struct GetSleepScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Sleep Score"
    static var description = IntentDescription("Read your latest NOOP sleep (Rest) score, 0 to 100.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        var value = WidgetSnapshot.load()?.rest
        if value == nil, let model = AppModel.shared {
            // Rest lives in a computed metric series, not a DailyMetric column, so the fallback is the
            // same anchor-day exploreSeries lookup WidgetSnapshot.publish does — including its guard
            // that the tail borrow is only honest when the anchor day IS the local today (borrowing it
            // for a prior anchor would surface a DIFFERENT day's Rest as that day's).
            let now = Date()
            if let day = Repository.widgetAnchor(days: model.repo.days, now: now) {
                let restSeries = await model.repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
                let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
                let anchorIsToday = day.day == Repository.localDayKey(now)
                value = (restByDay[day.day] ?? (anchorIsToday ? restSeries.last?.value : nil)).map { Int($0.rounded()) }
            }
        }
        guard let value else { throw NOOPReadError.noData }
        return .result(value: value, dialog: "Your sleep score is \(value) out of 100.")
    }
}

/// Surfaces NOOP's intents to Siri, Spotlight, and the Shortcuts gallery without any user setup.
struct NOOPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MarkMomentIntent(),
                    phrases: ["Mark a moment in \(.applicationName)"],
                    shortTitle: "Mark a Moment",
                    systemImageName: "mappin.and.ellipse")
        AppShortcut(intent: BuzzStrapIntent(),
                    phrases: ["Buzz my \(.applicationName) strap"],
                    shortTitle: "Buzz Strap",
                    systemImageName: "waveform.path")
        AppShortcut(intent: GetRecoveryIntent(),
                    phrases: ["Get my \(.applicationName) recovery"],
                    shortTitle: "Get Recovery",
                    systemImageName: "heart.fill")
        AppShortcut(intent: GetStrainIntent(),
                    phrases: ["Get my \(.applicationName) strain"],
                    shortTitle: "Get Strain",
                    systemImageName: "flame.fill")
        AppShortcut(intent: GetHRVIntent(),
                    phrases: ["Get my \(.applicationName) HRV"],
                    shortTitle: "Get HRV",
                    systemImageName: "waveform.path.ecg")
        AppShortcut(intent: GetSleepScoreIntent(),
                    phrases: ["Get my \(.applicationName) sleep score"],
                    shortTitle: "Get Sleep Score",
                    systemImageName: "bed.double.fill")
    }
}
#endif
