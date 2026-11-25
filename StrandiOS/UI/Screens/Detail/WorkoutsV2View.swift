#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - WorkoutsV2View — the v2 workouts history list
//
// Reads the same store `WorkoutsView` reads (`repo.workoutRows`, WHOOP + Apple + lifting sources,
// already de-duped) and lays the sessions out as a sleek, dark, mono list grouped by recency. A
// range V2Segmented filters the loaded window; each row is a sport glyph + title + date/duration +
// Effort value + an intensity V2Chip, and pushes `.workoutDetail(id)` via the shared detail route.
//
// The workout id is the app-wide natural key `"<startTs>|<sport>"` (same key `RouteStore` and the v1
// selection use), so `WorkoutDetailV2View` can resolve the row back from the store.

struct WorkoutsV2View: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    @State private var rows: [WorkoutRow] = []
    @State private var loaded = false
    @State private var range: RangeFilter = .days90

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2BackButton { dismiss() }

                V2ScreenHeader("Workouts",
                               subtitle: subtitleText)

                V2Segmented(selection: $range, options: RangeFilter.segmentOptions)
                    .padding(.horizontal, V2.Space.gutter)

                content
                    .padding(.horizontal, V2.Space.gutter)
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) {
            rows = await repo.workoutRows()
            loaded = true
        }
    }

    // MARK: Derived data

    private var filtered: [WorkoutRow] {
        let sorted = rows.sorted { $0.startTs > $1.startTs }
        guard let cutoff = range.cutoffTs else { return sorted }
        return sorted.filter { $0.startTs >= cutoff }
    }

    private var subtitleText: String {
        guard loaded else { return "Loading…" }
        let n = filtered.count
        return n == 1 ? "1 session" : "\(n) sessions"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let groups = WorkoutGrouping.grouped(filtered)
        if !loaded {
            V2Card { placeholder("Loading your sessions…") }
        } else if groups.isEmpty {
            V2Card(domain: .effort) {
                VStack(alignment: .leading, spacing: V2.Space.xs) {
                    Text("No workouts in range")
                        .font(V2Font.heading)
                        .foregroundStyle(V2.Color.textPrimary)
                    Text("Nothing recorded for this window. Widen the range or log a session.")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: V2.Space.sm) {
                        V2SectionHeader(group.title) {
                            Text("\(group.rows.count)")
                                .font(V2Font.caption)
                                .foregroundStyle(V2.Color.textTertiary)
                        }
                        V2Surface {
                            VStack(spacing: 0) {
                                ForEach(Array(group.rows.enumerated()), id: \.offset) { idx, row in
                                    NavigationLink(value: V2DetailRoute.workoutDetail(workoutID(row))) {
                                        WorkoutListRow(row: row, effortScale: effortScale)
                                    }
                                    .buttonStyle(.plain)
                                    if idx != group.rows.count - 1 {
                                        Rectangle()
                                            .fill(V2.Color.hairline)
                                            .frame(height: V2.Stroke.hairline)
                                            .padding(.leading, V2.Space.lg)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(V2Font.body)
            .foregroundStyle(V2.Color.textSecondary)
    }

    private func workoutID(_ row: WorkoutRow) -> String { "\(row.startTs)|\(row.sport)" }
}

// MARK: - Range filter

private enum RangeFilter: Hashable, CaseIterable {
    case days7, days30, days90, year1, all

    var label: String {
        switch self {
        case .days7:  return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        case .year1:  return "1Y"
        case .all:    return "All"
        }
    }

    /// The oldest `startTs` (unix seconds) still included, or nil for "all".
    var cutoffTs: Int? {
        let now = Int(Date().timeIntervalSince1970)
        switch self {
        case .days7:  return now - 7 * 86_400
        case .days30: return now - 30 * 86_400
        case .days90: return now - 90 * 86_400
        case .year1:  return now - 365 * 86_400
        case .all:    return nil
        }
    }

    static var segmentOptions: [(RangeFilter, String)] { allCases.map { ($0, $0.label) } }
}

// MARK: - Recency grouping

private struct WorkoutGroup: Identifiable {
    let title: String
    let rows: [WorkoutRow]
    var id: String { title }
}

private enum WorkoutGrouping {
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Bucket label for one session's start time (rows must arrive newest-first, so consecutive
    /// runs of the same label group cleanly without a dictionary reorder).
    private static func bucket(_ startTs: Int) -> String {
        let now = Date()
        let date = Date(timeIntervalSince1970: Double(startTs))
        let days = now.timeIntervalSince(date) / 86_400
        if days <= 7 { return "This Week" }
        if days <= 30 { return "This Month" }
        return monthFmt.string(from: date)
    }

    static func grouped(_ rows: [WorkoutRow]) -> [WorkoutGroup] {
        var out: [WorkoutGroup] = []
        var currentTitle: String?
        var current: [WorkoutRow] = []
        for row in rows {
            let title = bucket(row.startTs)
            if title != currentTitle {
                if let t = currentTitle, !current.isEmpty { out.append(WorkoutGroup(title: t, rows: current)) }
                currentTitle = title
                current = [row]
            } else {
                current.append(row)
            }
        }
        if let t = currentTitle, !current.isEmpty { out.append(WorkoutGroup(title: t, rows: current)) }
        return out
    }
}

// MARK: - One list row

private struct WorkoutListRow: View {
    let row: WorkoutRow
    let effortScale: EffortScale

    var body: some View {
        HStack(spacing: V2.Space.md) {
            Image(systemName: sportSymbol(row.sport))
                .font(V2Font.body)
                .foregroundStyle(V2Domain.effort.accent)
                .frame(width: 34, height: 34)
                .background(V2Domain.effort.trace,
                            in: RoundedRectangle(cornerRadius: V2.Radius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: V2.Space.xxs) {
                Text(WorkoutSource.displaySport(row.sport))
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textPrimary)
                    .lineLimit(1)
                Text("\(WorkoutFormat.date(row.startTs)) · \(WorkoutFormat.duration(row.durationS, start: row.startTs, end: row.endTs))")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: V2.Space.sm)

            VStack(alignment: .trailing, spacing: V2.Space.xxs) {
                if let strain = row.strain {
                    HStack(alignment: .firstTextBaseline, spacing: V2.Space.xxs) {
                        Text(UnitFormatter.effortDisplay(strain, scale: effortScale))
                            .font(V2Font.body)
                            .foregroundStyle(V2.Color.textPrimary)
                        Text("Effort")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                    if let intensity = WorkoutIntensity.chip(for: strain) {
                        V2Chip(intensity.0, tone: intensity.1)
                    }
                } else {
                    Text("—")
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textTertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
        }
        .padding(.horizontal, V2.Space.lg)
        .padding(.vertical, V2.Space.md)
        .contentShape(Rectangle())
    }
}

// MARK: - Intensity chip

private enum WorkoutIntensity {
    /// A short intensity word + tone for a 0–100 Effort value (nil when there's no Effort score).
    static func chip(for strain: Double) -> (String, V2Tone)? {
        switch strain {
        case ..<30:  return ("Light", .neutral)
        case ..<50:  return ("Moderate", .positive)
        case ..<70:  return ("Hard", .caution)
        default:     return ("All Out", .negative)
        }
    }
}

// MARK: - Shared formatting (file-scoped; duplicated in the detail file to keep the packet's two files self-contained)

private enum WorkoutFormat {
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ ts: Int) -> String {
        dateFmt.string(from: Date(timeIntervalSince1970: Double(ts)))
    }

    /// Human duration ("1h 12m" / "45m"), falling back to the timestamp span when `durationS` is nil.
    static func duration(_ durationS: Double?, start: Int, end: Int) -> String {
        let secs = durationS ?? Double(max(0, end - start))
        guard secs > 0 else { return "—" }
        let totalMin = Int(secs.rounded()) / 60
        let h = totalMin / 60, m = totalMin % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Back affordance (navbar is hidden on v2 detail surfaces)

private struct V2BackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: V2.Space.xxs) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(V2Font.label)
            .foregroundStyle(V2.Color.textSecondary)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, V2.Space.gutter)
        .accessibilityLabel("Back")
    }
}

#endif
