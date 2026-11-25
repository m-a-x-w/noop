#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

// MARK: - TodayMetricRowsCard — user-picked extra metrics
//
// A card of extra `V2StatRow`s for the metrics the user pins to Today, each drilling into
// `.metric(key)`. Selection persists as a CSV of `MetricCatalog` keys under
// `@AppStorage("v2.today.metrics")`; when that's unset it SEEDS from the existing v1
// `@AppStorage("today.dashboardCards")` selection so an upgrading user keeps their dashboard. Values
// read the resolved day row (today-first). A header "Edit" affordance opens a lightweight picker.

struct TodayMetricRowsCard: View {
    let ctx: TodayContext

    @AppStorage(TodayExtraMetrics.storageKey) private var enabledCSV = ""
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""
    @State private var showPicker = false

    private var keys: [String] { TodayExtraMetrics.resolve(enabledCSV, dashboardRaw: dashboardCardsRaw) }

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("More metrics") {
                    Button { showPicker = true } label: {
                        Text("Edit")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                if keys.isEmpty {
                    Text("Add metrics to keep an eye on them here.")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(keys.enumerated()), id: \.element) { idx, key in
                            if idx > 0 {
                                Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
                            }
                            row(key)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            TodayMetricPickerSheet(enabledCSV: $enabledCSV,
                                   seeded: TodayExtraMetrics.resolve(enabledCSV, dashboardRaw: dashboardCardsRaw))
        }
    }

    @ViewBuilder
    private func row(_ key: String) -> some View {
        let spec = TodayExtraMetrics.spec(for: key)
        NavigationLink(value: V2DetailRoute.metric(key)) {
            V2StatRow(icon: spec.icon, title: spec.title, value: spec.value(ctx) ?? "—")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extra-metric registry

/// The metrics Today can pin as extra rows: each maps a `MetricCatalog` key to a title/icon and a pure
/// value read off the resolved day. Only DailyMetric-backed metrics are offered (so a row always has a
/// value or a clean "—"), keyed to the same `MetricCatalog.key` the `.metric` route resolves.
enum TodayExtraMetrics {
    static let storageKey = "v2.today.metrics"

    struct Spec {
        let key: String
        let title: String
        let icon: String
        let value: (TodayContext) -> String?
    }

    /// The offerable set, in a sensible display order.
    static let all: [Spec] = [
        Spec(key: "spo2", title: "Blood Oxygen", icon: "drop") { c in
            c.spo2.map { "\(Int($0.rounded()))%" } },
        Spec(key: "steps", title: "Steps", icon: "figure.walk") { c in
            c.day?.steps.map { grouped($0) } },
        Spec(key: "active_kcal", title: "Active Energy", icon: "flame.fill") { c in
            c.day?.activeKcalEst.map { "\(Int($0.rounded())) kcal" } },
        Spec(key: "sleep_total_min", title: "Asleep Time", icon: "moon.zzz") { c in
            TodayFormat.hmm(c.day?.totalSleepMin) },
        Spec(key: "hrv", title: "HRV", icon: "waveform.path.ecg") { c in
            c.hrv.map { "\(Int($0.rounded())) ms" } },
        Spec(key: "rhr", title: "Resting HR", icon: "heart.fill") { c in
            c.rhr.map { "\($0) bpm" } },
        Spec(key: "resp_rate", title: "Respiratory", icon: "lungs") { c in
            c.resp.map { String(format: "%.1f rpm", $0) } },
        Spec(key: "skin_temp", title: "Skin Temperature", icon: "thermometer.medium") { c in
            c.skinTempDevC.map {
                VitalBands.isAbsoluteSkinTemp($0)
                    ? UnitFormatter.temperatureFromCelsius($0, unit: c.temperatureUnit, decimals: 1)
                    : UnitFormatter.temperatureDeltaFromCelsius($0, unit: c.temperatureUnit, decimals: 1)
            } },
    ]

    static func spec(for key: String) -> Spec {
        all.first { $0.key == key }
            ?? Spec(key: key, title: key, icon: "circle") { _ in nil }
    }

    /// The keys to show: the stored CSV if set, else a seed derived from the v1 dashboard selection,
    /// else a sensible default. Filtered to the offerable set + de-duped, order preserved.
    static func resolve(_ csv: String, dashboardRaw: String) -> [String] {
        let stored = parse(csv)
        if !stored.isEmpty { return stored }
        let seeded = seedFromDashboard(dashboardRaw)
        return seeded.isEmpty ? ["spo2", "steps", "active_kcal"] : seeded
    }

    private static func parse(_ csv: String) -> [String] {
        var seen = Set<String>()
        return csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { key in !key.isEmpty && all.contains { s in s.key == key } && seen.insert(key).inserted }
    }

    /// Map the v1 `DashboardCard` ids to the DailyMetric-backed metric keys we can render.
    private static func seedFromDashboard(_ raw: String) -> [String] {
        let map: [String: String] = [
            "hrv": "hrv", "restingHr": "rhr", "respiratory": "resp_rate", "steps": "steps",
            "bloodOxygen": "spo2", "skinTemp": "skin_temp", "sleep": "sleep_total_min",
            "calories": "active_kcal",
        ]
        var seen = Set<String>()
        return DashboardCardPrefs.decodeEnabled(raw)
            .compactMap { map[$0.rawValue] }
            .filter { seen.insert($0).inserted }
    }

    static func encode(_ keys: [String]) -> String { keys.joined(separator: ",") }

    private static func grouped(_ v: Int) -> String {
        Self.groupedFmt.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    private static let groupedFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
}

// MARK: - Metric picker sheet

private struct TodayMetricPickerSheet: View {
    @Binding var enabledCSV: String
    let seeded: [String]
    @Environment(\.dismiss) private var dismiss

    /// Local working set (initialised from the resolved seed so the sheet reflects what's showing).
    @State private var selected: Set<String>

    init(enabledCSV: Binding<String>, seeded: [String]) {
        _enabledCSV = enabledCSV
        self.seeded = seeded
        _selected = State(initialValue: Set(seeded))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V2.Space.lg) {
                    V2SheetHeader("Pin metrics") { commit(); dismiss() }
                    V2List {
                        ForEach(TodayExtraMetrics.all, id: \.key) { spec in
                            V2ListRow(title: spec.title,
                                      trailingSymbol: selected.contains(spec.key) ? "checkmark.circle.fill" : "circle",
                                      chevron: false) {
                                toggle(spec.key)
                            }
                        }
                    }
                    .padding(.horizontal, V2.Space.gutter)
                }
                .padding(.top, V2.Space.md)
                .padding(.bottom, V2.Space.xxl)
            }
            .background(V2.Color.surface0.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ key: String) {
        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
    }

    /// Persist in the registry's canonical order so the stored CSV is stable.
    private func commit() {
        let ordered = TodayExtraMetrics.all.map(\.key).filter { selected.contains($0) }
        enabledCSV = TodayExtraMetrics.encode(ordered)
    }
}
#endif
