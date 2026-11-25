#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - ExploreV2Host — the Explore tab root
//
// The Explore hub: a single scroll of hairline-separated V2 lists that reach EVERY analysis,
// history and metric surface in the app via the shared `V2DetailRoute` push contract. Structure,
// top → bottom: a fuzzy metric search, a pinned quick-access strip, the metric catalog by category
// (inline expand), then Analysis · Experiments · Insights · History sections. Every row navigates by
// pushing a `V2DetailRoute` value; the hub attaches the single `navigationDestination` that resolves
// them through `v2DetailDestination(_:)`. Dark-only, calm, mono labels — no per-row colour.

struct ExploreV2Host: View {
    /// Opens the Settings stack (the shell presents it). Wired to the header's profile button.
    var onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
    }

    /// CSV of `MetricDescriptor.key`s pinned to the quick-access strip. Empty by default; a future
    /// pin affordance writes here. Read-only in this hub.
    @AppStorage("v2.explore.pinned") private var pinnedCSV = ""

    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = []

    /// Anchor "today" for day-scoped routes. Captured once per host instance.
    private let today = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Explore", subtitle: "All your metrics") {
                    profileButton
                }

                searchField
                    .padding(.horizontal, V2.Space.gutter)

                if searchText.isEmpty {
                    hubSections
                } else {
                    searchResults
                        .padding(.horizontal, V2.Space.gutter)
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: V2DetailRoute.self) { v2DetailDestination($0) }
    }

    // MARK: Hub (no active search)

    private var hubSections: some View {
        VStack(alignment: .leading, spacing: V2.Space.xl) {
            pinnedSection
            metricsSection
            analysisSection
            experimentsSection
            insightsSection
            historySection
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Pinned strip

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Pinned")
            if pinnedMetrics.isEmpty {
                V2Card {
                    Text("Pin metrics for quick access.")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: V2.Space.md) {
                        ForEach(pinnedMetrics) { m in
                            NavigationLink(value: V2DetailRoute.metric(m.key)) {
                                pinnedCell(m)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, V2.Space.xxs)
                }
            }
        }
    }

    private func pinnedCell(_ m: MetricDescriptor) -> some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.xs) {
                Image(systemName: m.icon)
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
                Text(m.title)
                    .font(V2Font.label)
                    .foregroundStyle(V2.Color.textPrimary)
                    .lineLimit(2)
            }
            .frame(width: 116, alignment: .leading)
        }
    }

    // MARK: Metrics by category

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Metrics")
            VStack(spacing: V2.Space.sm) {
                ForEach(MetricCatalog.categories, id: \.self) { category in
                    categoryPanel(category)
                }
            }
        }
    }

    private func categoryPanel(_ category: String) -> some View {
        let metrics = dedupedMetrics(in: category)
        let expanded = expandedCategories.contains(category)
        return V2List {
            V2ListRow(title: MetricCatalog.categoryDisplayName(category),
                      trailingText: "\(metrics.count)",
                      trailingSymbol: expanded ? "chevron.up" : "chevron.down",
                      chevron: false) {
                toggle(category)
            }
            if expanded {
                ForEach(metrics) { m in
                    NavigationLink(value: V2DetailRoute.metric(m.key)) {
                        V2ListRow(title: m.title,
                                  subtitle: m.source == "my-whoop" ? nil : m.sourceLabel,
                                  trailingText: m.unit.isEmpty ? nil : m.unit,
                                  chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Analysis

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Analysis")
            V2List {
                linkRow("Trends", subtitle: "Metrics over time", .trends(nil))
                // No dedicated Compare route yet — land on a metric detail as a placeholder (the
                // Compare packet replaces this with a real two-metric surface).
                linkRow("Compare", subtitle: "Two metrics side by side", .metric("recovery"))
                linkRow("Relationships", subtitle: "What moves your scores", .relationships)
                linkRow("Rhythm", subtitle: "Beat-to-beat visualization", .rhythm)
                linkRow("Full day", subtitle: "Every vital, one record", .vitalsDay(today))
            }
        }
    }

    // MARK: Experiments

    private var experimentsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Experiments")
            V2List {
                linkRow("Lab Book", subtitle: "Run your own experiments", .labBook)
            }
        }
    }

    // MARK: Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("Insights")
            V2List {
                linkRow("Insights", subtitle: "Your personalised feed", .insights)
                linkRow("Coach", subtitle: "Ask about your data", .coach)
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            V2SectionHeader("History")
            V2List {
                linkRow("Workouts", subtitle: "Every logged session", .workouts)
                linkRow("Sleep", subtitle: "Last night and before", .sleep(today))
                linkRow("HRV", subtitle: "Heart rate variability", .metric("hrv"))
                linkRow("Skin temperature", subtitle: "Nightly deviation", .metric("skin_temp"))
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: V2.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textTertiary)
            TextField("", text: $searchText, prompt: Text("Search metrics")
                .foregroundColor(V2.Color.textTertiary))
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textPrimary)
                .tint(V2.Color.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, V2.Space.md)
        .padding(.vertical, V2.Space.sm)
        .background(V2.Color.surface2, in: RoundedRectangle(cornerRadius: V2.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: V2.Radius.md, style: .continuous)
                .strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline)
        )
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = searchMatches
        if results.isEmpty {
            V2Card {
                Text("No metrics match “\(searchText)”.")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
            }
        } else {
            V2List {
                ForEach(results) { m in
                    NavigationLink(value: V2DetailRoute.metric(m.key)) {
                        V2ListRow(title: m.title,
                                  subtitle: MetricCatalog.categoryDisplayName(m.category)
                                    + (m.source == "my-whoop" ? "" : " · \(m.sourceLabel)"),
                                  trailingText: m.unit.isEmpty ? nil : m.unit,
                                  chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Derivations

    /// Catalog metrics with a given category, deduped by `key` (the catalog carries the same key for
    /// several sources — e.g. WHOOP + Mi Band `avg_hr`; the metric route is keyed by `key` only).
    private func dedupedMetrics(in category: String) -> [MetricDescriptor] {
        dedupeByKey(MetricCatalog.inCategory(category))
    }

    /// Fuzzy search over the whole catalog (deduped by key), ranked best-first, capped for calm.
    private var searchMatches: [MetricDescriptor] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let scored: [(MetricDescriptor, Int)] = dedupeByKey(MetricCatalog.all).compactMap { m in
            guard let score = fuzzyScore(query: q, target: m.title.lowercased(), key: m.key.lowercased())
            else { return nil }
            return (m, score)
        }
        return scored.sorted { $0.1 < $1.1 }.map(\.0).prefix(40).map { $0 }
    }

    private var pinnedMetrics: [MetricDescriptor] {
        let resolved = pinnedCSV.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { key in MetricCatalog.all.first { $0.key == key } }
        return dedupeByKey(resolved)
    }

    private func dedupeByKey(_ metrics: [MetricDescriptor]) -> [MetricDescriptor] {
        var seen = Set<String>()
        return metrics.filter { seen.insert($0.key).inserted }
    }

    private func toggle(_ category: String) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    /// A subsequence fuzzy match. Returns a rank (lower = better): exact/prefix hits beat scattered
    /// subsequence hits; `nil` when the query isn't a subsequence of the title or key.
    private func fuzzyScore(query: String, target: String, key: String) -> Int? {
        if target.hasPrefix(query) { return 0 }
        if target.contains(query) { return 1 }
        if key.contains(query) { return 2 }
        if isSubsequence(query, of: target) { return 3 }
        if isSubsequence(query, of: key) { return 4 }
        return nil
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() {
                if h == ch { found = true; break }
            }
            if !found { return false }
        }
        return true
    }

    // MARK: Row builder

    private func linkRow(_ title: String, subtitle: String? = nil, _ route: V2DetailRoute) -> some View {
        NavigationLink(value: route) {
            V2ListRow(title: title, subtitle: subtitle, chevron: true)
        }
        .buttonStyle(.plain)
    }

    private var profileButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "person.crop.circle")
                .font(V2Font.title)
                .foregroundStyle(V2.Color.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ExploreV2Host(onOpenSettings: {})
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
