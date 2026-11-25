#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - TodayWorkoutsCard — the selected day's activities
//
// Loads the workout history once per data refresh and shows the sessions that fall on the selected
// day: sport glyph, Effort value, duration. Each row drills into `.workoutDetail(id)` (id = the
// natural key `"<startTs>|<sport>"`). With no sessions the card offers a ghost "Start workout" row
// that raises the shell's quick-action sheet.

struct TodayWorkoutsCard: View {
    let ctx: TodayContext

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter

    @State private var allRows: [WorkoutRow] = []

    private var dayRows: [WorkoutRow] {
        allRows
            .filter { Repository.localDayKey(Date(timeIntervalSince1970: Double($0.startTs))) == ctx.dayKey }
            .sorted { $0.startTs > $1.startTs }
    }

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("Workouts") {
                    NavigationLink(value: V2DetailRoute.workouts) {
                        Text("History")
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                if dayRows.isEmpty {
                    emptyRow
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dayRows.enumerated()), id: \.offset) { idx, row in
                            if idx > 0 {
                                Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
                            }
                            workoutRow(row)
                        }
                    }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            allRows = await repo.workoutRows()
        }
    }

    private func workoutRow(_ row: WorkoutRow) -> some View {
        NavigationLink(value: V2DetailRoute.workoutDetail("\(row.startTs)|\(row.sport)")) {
            HStack(spacing: V2.Space.md) {
                Image(systemName: TodayFormat.sportIcon(row.sport))
                    .font(V2Font.body)
                    .foregroundStyle(V2Domain.effort.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: V2.Space.xxs) {
                    Text(WorkoutSource.displaySport(row.sport))
                        .font(V2Font.body)
                        .foregroundStyle(V2.Color.textPrimary)
                    Text(durationText(row))
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textSecondary)
                }
                Spacer(minLength: V2.Space.sm)
                if let strain = row.strain {
                    VStack(alignment: .trailing, spacing: V2.Space.xxs) {
                        Text(UnitFormatter.effortDisplay(strain, scale: ctx.effortScale))
                            .font(V2Font.numeral(16))
                            .foregroundStyle(V2.Color.textPrimary)
                        Text("Effort")
                            .font(V2Font.overline)
                            .tracking(V2Font.overlineTracking)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
            .padding(.vertical, V2.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyRow: some View {
        Button {
            router.requestQuickActions()
        } label: {
            HStack(spacing: V2.Space.md) {
                Image(systemName: "plus.circle")
                    .font(V2Font.body)
                    .foregroundStyle(V2Domain.effort.accent)
                    .frame(width: 22)
                Text(ctx.isToday ? "Start workout" : "No workouts this day")
                    .font(V2Font.body)
                    .foregroundStyle(ctx.isToday ? V2.Color.textPrimary : V2.Color.textSecondary)
                Spacer(minLength: 0)
                if ctx.isToday {
                    Image(systemName: "chevron.right")
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                }
            }
            .padding(.vertical, V2.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ctx.isToday)
    }

    private func durationText(_ row: WorkoutRow) -> String {
        let secs = row.durationS ?? Double(max(0, row.endTs - row.startTs))
        guard secs > 0 else { return "—" }
        let totalMin = Int(secs.rounded()) / 60
        let h = totalMin / 60, m = totalMin % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
#endif
