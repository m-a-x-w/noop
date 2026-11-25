#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - WorkoutDetailV2View — a single workout, v2 dark/mono
//
// Resolves one `WorkoutRow` from the store by its natural-key id (`"<startTs>|<sport>"`, the same key
// the list pushes) and lays it out as: an Effort ring (domain .effort), a stat card (duration / avg &
// max HR / energy / distance), an HR-zone distribution (from the imported `zonesJSON` via
// `WorkoutZones`, coloured with `V2ChartScale.hrZones`), an on-device GPS-route note when one exists
// (`RouteStore`), and any session notes. Everything reads the existing data layer; nothing is mutated.

struct WorkoutDetailV2View: View {
    let workoutID: String

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var row: WorkoutRow?
    @State private var loaded = false

    init(workoutID: String) { self.workoutID = workoutID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                WDBackButton { dismiss() }

                if let row {
                    header(row)
                    effortCard(row)
                    statsCard(row)
                    zonesSection(row)
                    routeSection(row)
                    notesSection(row)
                } else if loaded {
                    notFound
                } else {
                    V2ScreenHeader("Workout")
                    V2Card { placeholder("Loading…") }
                        .padding(.horizontal, V2.Space.gutter)
                }
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: repo.refreshSeq) {
            let rows = await repo.workoutRows()
            row = rows.first { "\($0.startTs)|\($0.sport)" == workoutID }
            loaded = true
        }
    }

    // MARK: Header

    private func header(_ row: WorkoutRow) -> some View {
        V2ScreenHeader(WorkoutSource.displaySport(row.sport),
                       subtitle: "\(WDFormat.date(row.startTs)) · \(WDFormat.timeRange(row.startTs, row.endTs))") {
            HStack(spacing: V2.Space.sm) {
                Image(systemName: sportSymbol(row.sport))
                    .font(V2Font.title)
                    .foregroundStyle(V2Domain.effort.accent)
            }
        }
    }

    // MARK: Effort ring

    private func effortCard(_ row: WorkoutRow) -> some View {
        V2Card(domain: .effort) {
            HStack(spacing: V2.Space.xl) {
                V2Ring(progress: (row.strain ?? 0) / 100.0,
                       domain: .effort,
                       size: 120,
                       label: "Effort",
                       value: row.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—")
                VStack(alignment: .leading, spacing: V2.Space.sm) {
                    if let strain = row.strain, let chip = WDIntensity.chip(for: strain) {
                        V2Chip(chip.0, tone: chip.1)
                    }
                    Text("Day-strain equivalent on a 0–\(UnitFormatter.effortScaleMax(effortScale)) scale.")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: Stats

    private func statsCard(_ row: WorkoutRow) -> some View {
        V2Card {
            VStack(spacing: 0) {
                V2StatRow(icon: "clock", title: "Duration",
                          value: WDFormat.duration(row.durationS, start: row.startTs, end: row.endTs))
                divider
                V2StatRow(icon: "heart.fill", title: "Avg HR",
                          value: row.avgHr.map(String.init) ?? "—",
                          unit: row.avgHr != nil ? "bpm" : nil)
                divider
                V2StatRow(icon: "waveform.path.ecg", title: "Max HR",
                          value: row.maxHr.map(String.init) ?? "—",
                          unit: row.maxHr != nil ? "bpm" : nil)
                divider
                V2StatRow(icon: "flame.fill", title: "Energy",
                          value: row.energyKcal.map { WDFormat.grouped($0) } ?? "—",
                          unit: row.energyKcal != nil ? "kcal" : nil)
                if let dist = row.distanceM {
                    divider
                    V2StatRow(icon: "point.topleft.down.to.point.bottomright.curvepath",
                              title: "Distance",
                              value: UnitFormatter.distanceFromMeters(dist, system: unitSystem))
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    private var divider: some View {
        Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
    }

    // MARK: HR zones

    @ViewBuilder
    private func zonesSection(_ row: WorkoutRow) -> some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            V2SectionHeader("Heart-rate zones")
            V2Card {
                if let percents = WorkoutZones.percents(row.zonesJSON) {
                    let durMin = ((row.durationS ?? Double(max(0, row.endTs - row.startTs))) / 60.0)
                    VStack(alignment: .leading, spacing: V2.Space.md) {
                        WDZoneBar(percents: percents)
                        VStack(spacing: V2.Space.sm) {
                            ForEach(0..<5, id: \.self) { i in
                                if percents[i] > 0 {
                                    WDZoneLegendRow(index: i,
                                                    percent: percents[i],
                                                    minutes: durMin * percents[i] / 100.0)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: V2.Space.xs) {
                        Text("No zone data")
                            .font(V2Font.body)
                            .foregroundStyle(V2.Color.textPrimary)
                        Text("This session was imported without a heart-rate zone breakdown.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: GPS route

    @ViewBuilder
    private func routeSection(_ row: WorkoutRow) -> some View {
        if let route = RouteStore.load(startTs: row.startTs, sport: row.sport),
           !route.polyline.isEmpty {
            let points = RouteMath.decode(route.polyline)
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("Route")
                V2Card(domain: .effort) {
                    VStack(alignment: .leading, spacing: V2.Space.sm) {
                        HStack(spacing: V2.Space.sm) {
                            Image(systemName: "map")
                                .font(V2Font.body)
                                .foregroundStyle(V2Domain.effort.accent)
                            Text("GPS route recorded on device")
                                .font(V2Font.body)
                                .foregroundStyle(V2.Color.textPrimary)
                        }
                        HStack(spacing: V2.Space.lg) {
                            metric("Distance", UnitFormatter.distanceFromMeters(route.distanceM, system: unitSystem))
                            metric("Points", "\(points.count)")
                        }
                        Text("Your route is stored only on this device — nothing leaves your phone.")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: V2.Space.xxs) {
            Text(label.uppercased())
                .font(V2Font.overline)
                .tracking(V2Font.overlineTracking)
                .foregroundStyle(V2.Color.textTertiary)
            Text(value)
                .font(V2Font.numeral(18))
                .foregroundStyle(V2.Color.textPrimary)
        }
    }

    // MARK: Notes

    @ViewBuilder
    private func notesSection(_ row: WorkoutRow) -> some View {
        if let notes = row.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("Notes")
                V2Card {
                    Text(notes)
                        .font(V2Font.prose)
                        .foregroundStyle(V2.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    // MARK: Empty / loading

    private var notFound: some View {
        VStack(alignment: .leading, spacing: V2.Space.xl) {
            V2ScreenHeader("Workout")
            V2Card(domain: .effort) {
                VStack(alignment: .leading, spacing: V2.Space.xs) {
                    Text("Workout not found")
                        .font(V2Font.heading)
                        .foregroundStyle(V2.Color.textPrimary)
                    Text("This session is no longer in your history.")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
            }
            .padding(.horizontal, V2.Space.gutter)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(V2Font.body)
            .foregroundStyle(V2.Color.textSecondary)
    }
}

// MARK: - Intensity chip

private enum WDIntensity {
    static func chip(for strain: Double) -> (String, V2Tone)? {
        switch strain {
        case ..<30:  return ("Light", .neutral)
        case ..<50:  return ("Moderate", .positive)
        case ..<70:  return ("Hard", .caution)
        default:     return ("All Out", .negative)
        }
    }
}

// MARK: - HR-zone distribution bar

private struct WDZoneBar: View {
    let percents: [Double]   // Z1…Z5, 0–100 (may sum < 100)

    var body: some View {
        GeometryReader { geo in
            let total = max(percents.reduce(0, +), 0.0001)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    V2ChartScale.hrZones[i]
                        .frame(width: max(0, geo.size.width * percents[i] / total))
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

private struct WDZoneLegendRow: View {
    let index: Int
    let percent: Double
    let minutes: Double

    var body: some View {
        HStack(spacing: V2.Space.sm) {
            Circle()
                .fill(V2ChartScale.hrZones[index])
                .frame(width: 8, height: 8)
            Text("Zone \(index + 1)")
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textPrimary)
            Spacer(minLength: V2.Space.sm)
            Text("\(Int(minutes.rounded()))m")
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textSecondary)
            Text("\(Int(percent.rounded()))%")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Shared formatting (file-scoped; mirrors the list file so the packet's two files stay self-contained)

private enum WDFormat {
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ ts: Int) -> String {
        dateFmt.string(from: Date(timeIntervalSince1970: Double(ts)))
    }

    static func timeRange(_ start: Int, _ end: Int) -> String {
        let s = timeFmt.string(from: Date(timeIntervalSince1970: Double(start)))
        let e = timeFmt.string(from: Date(timeIntervalSince1970: Double(end)))
        return "\(s) – \(e)"
    }

    static func duration(_ durationS: Double?, start: Int, end: Int) -> String {
        let secs = durationS ?? Double(max(0, end - start))
        guard secs > 0 else { return "—" }
        let totalMin = Int(secs.rounded()) / 60
        let h = totalMin / 60, m = totalMin % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Thousands-grouped integer ("1,240").
    static func grouped(_ v: Double) -> String {
        let n = NSNumber(value: Int(v.rounded()))
        return groupedFmt.string(from: n) ?? "\(Int(v.rounded()))"
    }

    private static let groupedFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
}

// MARK: - Back affordance (navbar is hidden on v2 detail surfaces)

private struct WDBackButton: View {
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
