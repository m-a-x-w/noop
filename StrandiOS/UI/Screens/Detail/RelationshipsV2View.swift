#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - RelationshipsV2View
//
// The v2 "what actually moves YOUR numbers" screen. ONE surface that merges the three v1
// insight engines — the lag-aware EffectRanker (ranked drivers), CorrelationEngine (the
// per-driver r / slope / p point-biserial), and DoseResponseEngine (the personal, prior-shrunk
// dose curve) — behind a single outcome picker with progressive disclosure.
//
// Flow: pick an outcome (Charge / HRV / Rest / RHR) → see its DRIVERS ranked by honest effect
// size, each a tap-to-expand row → the expansion reveals the sign-aware sentence, the
// with/without means, the effect size + significance, the correlation stats, and — when the
// (behaviour, outcome) pair has a documented dose prior (alcohol→Charge, caffeine→HRV) — the
// personal dose-response curve. Everything is association on the user's own logged days, never
// a cause: the calm "needs more data" state is shown until a behaviour has days both with and
// without it. Dark-only, mono, hairline. Self-contained: owns its own load/derive, reads the
// Repository via @EnvironmentObject, edits nothing central.

struct RelationshipsV2View: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var model = RelationshipsV2Model()

    /// The selected outcome the drivers are ranked against (default Charge).
    @State private var outcome: RelationshipsV2Model.Outcome = .recovery

    init() {}

    private var pickerOptions: [(RelationshipsV2Model.Outcome, String)] {
        RelationshipsV2Model.Outcome.allCases.map { ($0, $0.short) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Relationships",
                               subtitle: "Patterns in your own data — association, not cause.")

                V2Segmented(selection: $outcome, options: pickerOptions)
                    .padding(.horizontal, V2.Space.gutter)

                content
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .onChange(of: outcome) { _, newValue in model.select(newValue) }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !model.loaded {
            infoCard("Reading your journal and outcomes…")
        } else if model.drivers.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: V2.Space.md) {
                V2SectionHeader("Drivers of \(outcome.short)")
                    .padding(.horizontal, V2.Space.gutter)

                V2Card(domain: outcome.domain) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.drivers.enumerated()), id: \.element.id) { index, driver in
                            if index > 0 {
                                Divider().overlay(V2.Color.hairline)
                            }
                            DriverRow(driver: driver, outcome: outcome)
                        }
                    }
                }
                .padding(.horizontal, V2.Space.gutter)

                methodNote
                    .padding(.horizontal, V2.Space.gutter)
            }
        }
    }

    private var emptyState: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                Text("Needs more data")
                    .font(V2Font.heading)
                    .foregroundStyle(V2.Color.textPrimary)
                Text("Not enough overlap between your journal answers and \(outcome.short.lowercased()) yet. Each behaviour needs days both with and without it before NOOP can read its effect. Keep logging.")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    private func infoCard(_ text: String) -> some View {
        V2Card {
            Text(text)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    private var methodNote: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                Text("How to read this")
                    .font(V2Font.overline)
                    .tracking(V2Font.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(V2.Color.textTertiary)
                Text("Each row is a pattern in your own logged days — an effect size and confidence, never a cause or a diagnosis. \u{201C}Typical\u{201D} figures are population patterns and are always overridden by your own data once you have enough of it. Approximations, not a medical device.")
                    .font(V2Font.proseSmall)
                    .foregroundStyle(V2.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Driver row (tap to expand)

private struct DriverRow: View {
    let driver: RelationshipsV2Model.Driver
    let outcome: RelationshipsV2Model.Outcome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var e: BehaviorEffect { driver.ranked.effect }

    /// Did this behaviour move the outcome the GOOD way (accounting for RHR being lower-is-better)?
    private var movedGood: Bool? {
        e.delta == 0 ? nil : (e.delta > 0) == outcome.higherIsBetter
    }

    private var tint: Color {
        guard let good = movedGood else { return V2.Color.textTertiary }
        guard e.significant else { return V2.Color.textSecondary }
        return good ? V2.Color.positive : V2.Color.negative
    }

    private var sigTone: V2Tone {
        guard e.significant, let good = movedGood else { return .neutral }
        return good ? .positive : .negative
    }

    private var effectText: String {
        let arrow = e.delta > 0 ? "\u{2191}" : (e.delta < 0 ? "\u{2193}" : "\u{2192}")
        if let pct = e.pctChange {
            return "\(arrow) \(Int(abs(pct).rounded()))%"
        }
        return "\(arrow) \(String(format: "%.1f", abs(e.delta)))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                detail
                    .padding(.top, V2.Space.sm)
                    .padding(.bottom, V2.Space.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: V2.Space.md) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(driver.behavior)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: V2.Space.sm)
            Text(effectText)
                .font(V2Font.body)
                .foregroundStyle(tint)
            V2Chip(e.significant ? "p < .05" : "n.s.", tone: sigTone)
            Image(systemName: "chevron.down")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.vertical, V2.Space.sm)
        .contentShape(Rectangle())
    }

    // MARK: Expanded detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            Text(driver.ranked.sentence())
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: V2.Space.sm) {
                V2Chip(driver.ranked.leadLagText, tone: .neutral)
                V2Chip(Self.confidenceWord(driver.ranked.confidence),
                       tone: Self.confidenceTone(driver.ranked.confidence))
            }

            Divider().overlay(V2.Color.hairline)

            V2StatRow(title: "With", value: outcome.format(e.meanWith), unit: "n=\(e.nWith)")
            V2StatRow(title: "Without", value: outcome.format(e.meanWithout), unit: "n=\(e.nWithout)")
            V2StatRow(title: "Effect size",
                      value: String(format: "d %.2f", e.cohensD),
                      unit: Self.magnitudeWord(e.cohensD))
            V2StatRow(title: "Significance", value: String(format: "p %.3f", e.pApprox))

            if let c = driver.correlation {
                V2StatRow(title: "Correlation r", value: String(format: "%+.2f", c.r), unit: "n=\(c.n)")
                V2StatRow(title: "Slope", value: String(format: "%+.2f", c.slope), unit: "/log")
            }

            if let dose = driver.dose {
                doseSection(dose)
            }
        }
    }

    @ViewBuilder
    private func doseSection(_ dose: DoseResponse) -> some View {
        let suffix = dose.outcome == "HRV" ? " ms" : "%"
        Divider().overlay(V2.Color.hairline)

        VStack(alignment: .leading, spacing: V2.Space.sm) {
            Text("Dose-response")
                .font(V2Font.overline)
                .tracking(V2Font.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(V2.Color.textTertiary)

            Text(dose.sentence())
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DoseCurveMini(points: dose.curve, accent: outcome.domain.accent)
                .frame(height: 96)

            V2StatRow(title: "Per extra unit",
                      value: Self.signed(dose.perUnit, suffix: suffix),
                      unit: dose.priorDominated ? "typical" : "your data")
        }
    }

    // MARK: Formatting helpers

    private static func confidenceWord(_ c: ScoreConfidence) -> String {
        switch c {
        case .solid:       return "Solid"
        case .building:    return "Building"
        case .calibrating: return "Calibrating"
        }
    }

    private static func confidenceTone(_ c: ScoreConfidence) -> V2Tone {
        switch c {
        case .solid:       return .positive
        case .building:    return .caution
        case .calibrating: return .neutral
        }
    }

    private static func magnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2: return "negligible"
        case ..<0.5: return "small"
        case ..<0.8: return "moderate"
        default:     return "large"
        }
    }

    private static func signed(_ v: Double, suffix: String) -> String {
        let mag = (abs(v) * 10).rounded() / 10
        let sign = v < 0 ? "\u{2212}" : (v > 0 ? "+" : "")
        let body = mag == mag.rounded() ? "\(Int(mag))" : String(format: "%.1f", mag)
        return "\(sign)\(body)\(suffix)"
    }
}

// MARK: - Dose curve mini chart
//
// A compact line + area of the prior-shrunk dose curve: dose on x (0…max), the modelled
// outcome DELTA on y, symmetric around a dashed zero baseline so the sign reads honestly.
// Drawn with the house Path idiom in v2 colours (no Swift Charts dependency for a 4-point curve).

private struct DoseCurveMini: View {
    let points: [DoseCurvePoint]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let deltas = points.map(\.outcomeDelta)
            let maxAbs = max(1.0, deltas.map(abs).max() ?? 1.0)
            let yFor: (Double) -> CGFloat = { d in
                let t = (d / maxAbs + 1) / 2
                return h - CGFloat(t) * h
            }
            let n = max(1, points.count - 1)
            let xFor: (Int) -> CGFloat = { i in CGFloat(i) / CGFloat(n) * w }
            let zeroY = yFor(0)

            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: zeroY))
                    p.addLine(to: CGPoint(x: w, y: zeroY))
                }
                .stroke(V2.Color.hairlineHeavy, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                Path { p in
                    guard !points.isEmpty else { return }
                    p.move(to: CGPoint(x: xFor(0), y: zeroY))
                    for (i, pt) in points.enumerated() {
                        p.addLine(to: CGPoint(x: xFor(i), y: yFor(pt.outcomeDelta)))
                    }
                    p.addLine(to: CGPoint(x: xFor(points.count - 1), y: zeroY))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))

                Path { p in
                    for (i, pt) in points.enumerated() {
                        let point = CGPoint(x: xFor(i), y: yFor(pt.outcomeDelta))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .position(x: xFor(i), y: yFor(points[i].outcomeDelta))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - View-model
//
// Self-contained: loads the journal (behaviour → days), dose rows (under the dedicated
// noop-journal-dose source), and the outcome series (imported metricSeries ∪ DailyMetric
// fallback, exactly as the v1 Insights hub), then re-derives the ranked drivers on demand via
// EffectRanker, with each driver's point-biserial correlation (CorrelationEngine) and — where a
// prior exists — its DoseResponse precomputed so expansion is instant. No edits to AppModel.

@MainActor
final class RelationshipsV2Model: ObservableObject {

    // MARK: Outcome

    enum Outcome: String, CaseIterable, Hashable {
        case recovery, hrv, sleep, rhr

        /// Short picker label.
        var short: String {
            switch self {
            case .recovery: return "Charge"
            case .hrv:      return "HRV"
            case .sleep:    return "Rest"
            case .rhr:      return "RHR"
            }
        }
        /// metricSeries key.
        var key: String {
            switch self {
            case .recovery: return "recovery"
            case .hrv:      return "hrv"
            case .sleep:    return "sleep_performance"
            case .rhr:      return "rhr"
            }
        }
        /// The engine's outcome label carried onto each RankedEffect.
        var name: String {
            switch self {
            case .recovery: return "Charge"
            case .hrv:      return "HRV"
            case .sleep:    return "Rest"
            case .rhr:      return "Resting HR"
            }
        }
        var higherIsBetter: Bool { self != .rhr }
        var domain: V2Domain {
            switch self {
            case .recovery:    return .charge
            case .hrv, .sleep: return .rest
            case .rhr:         return .stress
            }
        }
        func format(_ v: Double) -> String {
            switch self {
            case .recovery, .sleep: return "\(Int(v.rounded()))%"
            case .hrv:              return "\(Int(v.rounded())) ms"
            case .rhr:              return "\(Int(v.rounded())) bpm"
            }
        }
    }

    // MARK: Derived row

    struct Driver: Identifiable {
        let behavior: String
        let ranked: RankedEffect
        /// Point-biserial correlation of presence (0/1) vs the outcome at the ranked lag.
        let correlation: Correlation?
        /// Personal, prior-shrunk dose curve when the (behaviour, outcome) pair has a prior.
        let dose: DoseResponse?
        var id: String { behavior }
    }

    // MARK: Published state

    @Published private(set) var loaded = false
    @Published private(set) var drivers: [Driver] = []

    // MARK: Loaded inputs (kept so the outcome picker can re-derive cheaply, no DB)

    private var behaviours: [String: Set<String>] = [:]
    private var outcomeByKey: [String: [String: Double]] = [:]
    private var doseByBehaviour: [DosedBehavior: [String: Int]] = [:]
    private var current: Outcome = .recovery

    /// The source id dose rows are parked under (mirrors the v1 Insights hub).
    static let doseSource = "noop-journal-dose"
    private let outcomeKeys = ["recovery", "hrv", "sleep_performance", "rhr"]

    // MARK: Load

    func load(repo: Repository) async {
        // Journal → behaviour → days (only "yes" answers count as the behaviour occurring).
        let entries = await repo.journalEntries()
        var byBehaviour: [String: Set<String>] = [:]
        for entry in entries where entry.answeredYes {
            byBehaviour[entry.question, default: []].insert(entry.day)
        }

        // Outcome series: imported metricSeries ∪ the DailyMetric column fallback, so a
        // strap-only user still gets effects — the exact contract the v1 hub uses.
        let mergedDays = repo.days
        var byKey: [String: [String: Double]] = [:]
        for key in outcomeKeys {
            let series = await repo.series(key: key, source: "my-whoop")
            var dict: [String: Double] = [:]
            for row in series { dict[row.day] = row.value }
            for day in mergedDays where dict[day.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: day) { dict[day.day] = v }
            }
            byKey[key] = dict
        }

        // Dose rows per dosed behaviour: any logged "yes" day starts at dose 1 (back-compat),
        // any explicit dose row overrides.
        var doseMap: [DosedBehavior: [String: Int]] = [:]
        for behavior in DosedBehavior.allCases {
            let key = Self.doseKey(for: behavior)
            let rows = await repo.series(key: key, source: Self.doseSource)
            var doses: [String: Int] = [:]
            for (question, days) in byBehaviour where Self.matches(behavior, question: question) {
                for day in days { doses[day] = max(doses[day] ?? 0, 1) }
            }
            for row in rows { doses[row.day] = Int(row.value.rounded()) }
            if !doses.isEmpty { doseMap[behavior] = doses }
        }

        self.behaviours = byBehaviour
        self.outcomeByKey = byKey
        self.doseByBehaviour = doseMap
        self.loaded = true
        recompute()
    }

    /// Select a (possibly new) outcome and re-derive the driver list — cheap, no DB.
    func select(_ outcome: Outcome) {
        current = outcome
        guard loaded else { return }
        recompute()
    }

    // MARK: Derivation

    private func recompute() {
        let outcomeDays = outcomeByKey[current.key] ?? [:]
        let ranked = EffectRanker.rank(behaviors: behaviours,
                                       outcomeByDay: outcomeDays,
                                       outcome: current.name)
        drivers = ranked.map { r in
            Driver(behavior: r.behavior,
                   ranked: r,
                   correlation: pointBiserial(behavior: r.behavior, lag: r.lag, outcomeDays: outcomeDays),
                   dose: doseResponse(question: r.behavior, outcomeName: current.name))
        }
    }

    /// Point-biserial r / slope / p: presence (0/1) on day D vs the outcome `lag` days later,
    /// over every day that has an outcome value. Nil when the presence axis has no spread.
    private func pointBiserial(behavior: String, lag: Int,
                               outcomeDays: [String: Double]) -> Correlation? {
        guard let days = behaviours[behavior] else { return nil }
        let outcomeSeries = outcomeDays.map { (day: $0.key, value: $0.value) }
        let presence = outcomeDays.keys.map { (day: $0, value: days.contains($0) ? 1.0 : 0.0) }
        return CorrelationEngine.lagged(x: presence, y: outcomeSeries, lagDays: lag)
    }

    /// The personal dose-response for a journal question that names a dosed behaviour, against
    /// the current outcome. Nil unless the (behaviour, outcome) pair has a documented prior.
    private func doseResponse(question: String, outcomeName: String) -> DoseResponse? {
        for behavior in DosedBehavior.allCases where Self.matches(behavior, question: question) {
            guard let doses = doseByBehaviour[behavior] else { continue }
            let outcomeDays = outcomeByKey[Self.outcomeKey(forEngineName: outcomeName)] ?? [:]
            if let response = DoseResponseEngine.estimate(behavior: behavior,
                                                          outcome: outcomeName,
                                                          doseByDay: doses,
                                                          outcomeByDay: outcomeDays) {
                return response
            }
        }
        return nil
    }

    // MARK: Static shaping helpers (mirror the v1 Insights hub exactly)

    /// The merged DailyMetric column backing an outcome key (strap-only fallback). sleep_performance
    /// has no daily column, so it stays import-only — never seeded here.
    private static func dailyOutcome(key: String, day: DailyMetric) -> Double? {
        switch key {
        case "recovery": return day.recovery
        case "hrv":      return day.avgHrv
        case "rhr":      return day.restingHr.map(Double.init)
        default:         return nil
        }
    }

    /// The metricSeries key a DoseResponsePriors outcome NAME maps to.
    private static func outcomeKey(forEngineName name: String) -> String {
        switch name {
        case "Charge":     return "recovery"
        case "HRV":        return "hrv"
        case "Rest":       return "sleep_performance"
        case "Resting HR": return "rhr"
        default:           return "recovery"
        }
    }

    /// The dose storage key for a behaviour (its raw enum value — the stable, cross-platform key).
    private static func doseKey(for behavior: DosedBehavior) -> String { "dose_\(behavior.rawValue)" }

    /// Whether a journal question is the dosed behaviour (so its yes-days back-fill dose = 1).
    private static func matches(_ behavior: DosedBehavior, question: String) -> Bool {
        let q = question.lowercased()
        switch behavior {
        case .alcohol:  return q.contains("alcohol") || q.contains("drink")
        case .caffeine: return q.contains("caffeine") || q.contains("coffee")
        }
    }
}
#endif
