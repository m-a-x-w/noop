#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

// MARK: - Today v2 shared model
//
// The value types + tiny pure helpers the Today feed's cards share: the resolved-day context
// each card reads from, the persisted card layout (order / hidden / density) the editor writes,
// and a handful of format helpers (sleep h:mm, sport glyph, status words). No view code here —
// every card takes a `TodayContext` and reads the environment objects it needs for the rest.

// MARK: TodayCard — the feed's card identities

/// One card in the Today feed. `rawValue` is the stable persisted id used in the layout JSON.
/// `hero` is always first and can never be hidden; every other card is reorderable + hideable.
enum TodayCard: String, CaseIterable, Identifiable, Codable {
    case hero
    case vitals
    case sleep
    case workouts
    case stress
    case insight
    case metrics
    case journal

    var id: String { rawValue }

    /// Whether the user may hide/reorder this card. The hero is pinned first, always visible.
    var isHideable: Bool { self != .hero }

    /// Human label shown in the card editor.
    var title: String {
        switch self {
        case .hero:     return String(localized: "Overview")
        case .vitals:   return String(localized: "Vitals")
        case .sleep:    return String(localized: "Sleep")
        case .workouts: return String(localized: "Workouts")
        case .stress:   return String(localized: "Stress")
        case .insight:  return String(localized: "Insight")
        case .metrics:  return String(localized: "More metrics")
        case .journal:  return String(localized: "Journal")
        }
    }

    /// SF Symbol for the editor row.
    var icon: String {
        switch self {
        case .hero:     return "square.grid.2x2"
        case .vitals:   return "waveform.path.ecg"
        case .sleep:    return "bed.double.fill"
        case .workouts: return "figure.run"
        case .stress:   return "bolt.heart"
        case .insight:  return "lightbulb"
        case .metrics:  return "list.bullet"
        case .journal:  return "square.and.pencil"
        }
    }
}

// MARK: TodayLayout — persisted order + hidden set (@AppStorage JSON)

/// The persisted Today feed layout: an ordered list of the ENABLED cards. A card absent from the
/// list is hidden. Stored as a JSON `[String]` of `TodayCard.rawValue`s under
/// `@AppStorage("v2.today.cards")`. Hero is force-kept-first regardless of the stored value.
enum TodayLayout {
    static let storageKey = "v2.today.cards"

    /// The default feed order (matches the packet spec, top → bottom).
    static let defaultOrder: [TodayCard] = [
        .hero, .vitals, .sleep, .workouts, .stress, .insight, .metrics, .journal,
    ]

    static func encode(_ cards: [TodayCard]) -> String {
        let ids = normalized(cards).map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return ids.joined(separator: ",")
    }

    /// Decode the stored string into the ordered enabled cards. Empty/unset yields the default order.
    /// Hero is always re-inserted first so it can never be lost or moved out of the lead position.
    static func decode(_ raw: String) -> [TodayCard] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultOrder }
        let ids: [String]
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids = decoded
        } else {
            ids = trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        var seen = Set<TodayCard>()
        var result: [TodayCard] = []
        for token in ids {
            if let c = TodayCard(rawValue: token), seen.insert(c).inserted { result.append(c) }
        }
        return normalized(result.isEmpty ? defaultOrder : result)
    }

    /// Force the hero to the front (and present exactly once).
    static func normalized(_ cards: [TodayCard]) -> [TodayCard] {
        var rest = cards.filter { $0 != .hero }
        // De-dupe defensively.
        var seen = Set<TodayCard>()
        rest = rest.filter { seen.insert($0).inserted }
        return [.hero] + rest
    }

    /// The hideable cards NOT currently enabled, in canonical order (for the editor's "hidden" list).
    static func hidden(from enabled: [TodayCard]) -> [TodayCard] {
        let enabledSet = Set(enabled)
        return TodayCard.allCases.filter { $0.isHideable && !enabledSet.contains($0) }
    }
}

// MARK: TodayContext — the resolved read snapshot passed into every card

/// Everything a Today card needs about the currently-selected day, resolved once by the host so
/// each card renders from plain values (no repeated store reads). Cards still reach the environment
/// for async loads (workouts) and logging (journal).
struct TodayContext {
    /// The selected calendar day (normalised to start-of-day).
    let date: Date
    /// `yyyy-MM-dd` key for the selected day.
    let dayKey: String
    /// True when the selected day is today.
    let isToday: Bool
    /// The selected day's metric row (today-first when it's today).
    let day: DailyMetric?
    /// Freshest on-or-before day carrying overnight vitals, for the today-first field fallback.
    let vitalsDay: DailyMetric?
    /// All days, oldest → newest (for sparklines / baselines / debt ledger).
    let days: [DailyMetric]
    let effortScale: EffortScale
    let temperatureUnit: TemperatureUnit
    let unitSystem: UnitSystem

    // Per-field today-first reads (mirror the v1 `displayDay?.f ?? vitalsDay?.f` pattern).
    var hrv: Double? { day?.avgHrv ?? vitalsDay?.avgHrv }
    var rhr: Int? { day?.restingHr ?? vitalsDay?.restingHr }
    var resp: Double? { day?.respRateBpm ?? vitalsDay?.respRateBpm }
    var skinTempDevC: Double? { day?.skinTempDevC ?? vitalsDay?.skinTempDevC }
    var spo2: Double? { day?.spo2Pct ?? vitalsDay?.spo2Pct }

    /// Trailing up-to-7 values of a metric on-or-before the selected day (for hero sparklines).
    func trailing(_ keyPath: KeyPath<DailyMetric, Double?>, count: Int = 7) -> [Double] {
        days.filter { $0.day <= dayKey }
            .suffix(count)
            .compactMap { $0[keyPath: keyPath] }
    }
}

// MARK: - Pure format + status helpers

enum TodayFormat {

    /// Minutes → "h:mm" (e.g. 408 → "6:48"). nil / non-positive → "—".
    static func hmm(_ minutes: Double?) -> String {
        guard let m = minutes, m > 0 else { return "—" }
        let total = Int(m.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// A signed-magnitude "h:mm" for a debt/surplus balance (unsigned; caller supplies the word).
    static func hmmMagnitude(_ minutes: Double) -> String {
        let total = Int(abs(minutes).rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Charge status word for a 0–100 score (never a verdict, just a band read).
    static func chargeWord(_ score: Double?) -> String {
        guard let s = score else { return String(localized: "No reading") }
        switch s {
        case ..<34:  return String(localized: "Depleted")
        case ..<67:  return String(localized: "Moderate")
        default:     return String(localized: "Primed")
        }
    }

    /// Effort status word for a 0–100 strain value.
    static func effortWord(_ strain: Double?) -> String {
        guard let s = strain else { return String(localized: "No load yet") }
        switch s {
        case ..<25:  return String(localized: "Light day")
        case ..<50:  return String(localized: "Moderate")
        case ..<75:  return String(localized: "Strenuous")
        default:     return String(localized: "All-out")
        }
    }

    /// A relative tone for a charge/rest score band (drives caption/chip tone, not verdicts).
    static func scoreTone(_ score: Double?) -> V2Tone {
        guard let s = score else { return .neutral }
        switch s {
        case ..<34:  return .negative
        case ..<67:  return .caution
        default:     return .positive
        }
    }

    /// A best-effort SF Symbol for a sport name (SF Symbols only — never a Nerd Font glyph).
    static func sportIcon(_ sport: String) -> String {
        switch sport.lowercased() {
        case let s where s.contains("run") || s.contains("treadmill run"): return "figure.run"
        case let s where s.contains("walk"):        return "figure.walk"
        case let s where s.contains("hik"):         return "figure.hiking"
        case let s where s.contains("cycl") || s.contains("bike"): return "figure.outdoor.cycle"
        case let s where s.contains("swim"):        return "figure.pool.swim"
        case let s where s.contains("row"):         return "figure.rower"
        case let s where s.contains("elliptical"):  return "figure.elliptical"
        case let s where s.contains("strength") || s.contains("weight") || s.contains("bodybuild"):
            return "dumbbell.fill"
        case let s where s.contains("hiit"):        return "figure.highintensity.intervaltraining"
        case let s where s.contains("yoga"):        return "figure.yoga"
        case let s where s.contains("pilates"):     return "figure.pilates"
        case let s where s.contains("box"):         return "figure.boxing"
        case let s where s.contains("basketball"):  return "figure.basketball"
        case let s where s.contains("soccer"):      return "figure.soccer"
        case let s where s.contains("tennis") || s.contains("padel") || s.contains("pickle")
            || s.contains("squash") || s.contains("racquet") || s.contains("badminton"):
            return "figure.tennis"
        case let s where s.contains("climb"):       return "figure.climbing"
        case let s where s.contains("ski"):         return "figure.skiing.downhill"
        case let s where s.contains("snowboard"):   return "figure.snowboarding"
        case let s where s.contains("dance") || s.contains("dancing"): return "figure.dance"
        case let s where s.contains("golf"):        return "figure.golf"
        case let s where s.contains("stretch"):     return "figure.flexibility"
        default:                                    return "figure.mixed.cardio"
        }
    }
}
#endif
