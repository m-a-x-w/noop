#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - TodayStressCard — day autonomic-load gauge + Breathe check-in
//
// Reuses the shipped `StressModel` (stored "stress" series, else a personal-baseline derivation) to
// resolve the selected day's 0–3 stress score, drawn as a horizontal ramp gauge. The gauge area
// drills into the full Stress detail; a secondary "Breathe" button presents the paced-breathing
// check-in inline.

struct TodayStressCard: View {
    let ctx: TodayContext

    @EnvironmentObject private var repo: Repository
    @State private var stored: [(day: String, value: Double)] = []
    @State private var loaded = false
    @State private var showBreathe = false

    private var slicedDays: [DailyMetric] { ctx.days.filter { $0.day <= ctx.dayKey } }
    private var model: StressModel? { StressModel(days: slicedDays, stored: stored) }

    var body: some View {
        V2Card(domain: .stress) {
            VStack(alignment: .leading, spacing: V2.Space.md) {
                HStack {
                    Text("Stress")
                        .font(V2Font.overline)
                        .tracking(V2Font.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(V2.Color.textTertiary)
                    Spacer()
                    if let m = model {
                        V2Chip(StressBand(score: m.score).title, tone: tone(StressBand(score: m.score)))
                    }
                }

                NavigationLink(value: V2DetailRoute.stress(ctx.date)) {
                    VStack(alignment: .leading, spacing: V2.Space.sm) {
                        if let m = model {
                            HStack(alignment: .firstTextBaseline, spacing: V2.Space.xs) {
                                Text(String(format: "%.1f", m.score))
                                    .font(V2Font.numeral(30))
                                    .foregroundStyle(V2.Color.textPrimary)
                                Text("of 3")
                                    .font(V2Font.caption)
                                    .foregroundStyle(V2.Color.textSecondary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(V2Font.caption)
                                    .foregroundStyle(V2.Color.textTertiary)
                            }
                            gauge(m.score)
                        } else {
                            Text(loaded ? "No stress signal for this day yet." : "Reading the day…")
                                .font(V2Font.caption)
                                .foregroundStyle(V2.Color.textTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button("Breathe") { showBreathe = true }
                    .v2Secondary()
            }
        }
        .task(id: "\(ctx.dayKey)|\(repo.refreshSeq)") {
            stored = await repo.series(key: "stress", source: "my-whoop")
            loaded = true
        }
        .sheet(isPresented: $showBreathe) {
            NavigationStack {
                BreathingView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showBreathe = false }
                    } }
            }
        }
    }

    private func gauge(_ score: Double) -> some View {
        let frac = min(max(score / 3.0, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(V2.Color.surface2)
                Capsule()
                    .fill(LinearGradient(
                        colors: [V2ChartScale.stress(0.05), V2ChartScale.stress(0.5), V2ChartScale.stress(0.95)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * frac))
            }
        }
        .frame(height: 8)
    }

    private func tone(_ band: StressBand) -> V2Tone {
        switch band {
        case .low:    return .positive
        case .medium: return .caution
        case .high:   return .negative
        }
    }
}
#endif
