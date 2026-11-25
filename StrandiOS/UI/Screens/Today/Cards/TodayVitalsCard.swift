#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics

// MARK: - TodayVitalsCard — HRV · RHR · Respiration · Skin temp (2×2)
//
// A 2×2 grid of compact vertical mini-stats (label row over a big mono value + unit, with a signed
// baseline delta beneath). Vertical stacking keeps the mono numerals + unit + delta each on their own
// line so nothing wraps in a half-width cell. Every cell is a `NavigationLink` into that metric's
// detail (`.metric(key)`).

struct TodayVitalsCard: View {
    let ctx: TodayContext

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: V2.Space.sm) {
                V2SectionHeader("Vitals")
                Grid(horizontalSpacing: V2.Space.lg, verticalSpacing: V2.Space.md) {
                    GridRow {
                        hrvCell
                        rhrCell
                    }
                    Divider().overlay(V2.Color.hairline).gridCellColumns(2)
                    GridRow {
                        respCell
                        skinCell
                    }
                }
            }
        }
    }

    // MARK: Cells

    private var hrvCell: some View {
        cell("hrv", icon: "waveform.path.ecg", title: "HRV",
             value: ctx.hrv.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms",
             delta: delta(value: ctx.hrv, cfg: Baselines.hrvCfg, values: ctx.days.map(\.avgHrv), decimals: 0))
    }

    private var rhrCell: some View {
        cell("rhr", icon: "heart.fill", title: "RHR",
             value: ctx.rhr.map(String.init) ?? "—", unit: "bpm",
             delta: delta(value: ctx.rhr.map(Double.init), cfg: Baselines.restingHRCfg,
                          values: ctx.days.map { $0.restingHr.map(Double.init) }, decimals: 0))
    }

    private var respCell: some View {
        cell("resp_rate", icon: "lungs.fill", title: "Resp",
             value: ctx.resp.map { String(format: "%.1f", $0) } ?? "—", unit: "rpm",
             delta: delta(value: ctx.resp, cfg: Baselines.respCfg, values: ctx.days.map(\.respRateBpm), decimals: 1))
    }

    private var skinCell: some View {
        cell("skin_temp", icon: "thermometer.medium", title: "Skin",
             value: skinValue, unit: nil, delta: skinDelta)
    }

    /// One compact vertical mini-stat, tappable into the metric detail.
    private func cell(_ key: String, icon: String, title: LocalizedStringKey,
                      value: String, unit: String?, delta: V2Delta?) -> some View {
        NavigationLink(value: V2DetailRoute.metric(key)) {
            VStack(alignment: .leading, spacing: V2.Space.xs) {
                HStack(spacing: V2.Space.xs) {
                    Image(systemName: icon)
                        .font(V2Font.caption)
                        .foregroundStyle(V2.Color.textTertiary)
                    Text(title)
                        .font(V2Font.overline)
                        .tracking(V2Font.overlineTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(V2.Color.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(V2Font.numeral(22))
                        .foregroundStyle(V2.Color.textPrimary)
                    if let unit {
                        Text(unit)
                            .font(V2Font.caption)
                            .foregroundStyle(V2.Color.textTertiary)
                    }
                    if let delta { deltaLabel(delta) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A small signed delta glyph + magnitude beside the value (up=positive, down=negative, flat=muted).
    private func deltaLabel(_ d: V2Delta) -> some View {
        let tone: Color = {
            switch d.direction {
            case .up:   return V2.Color.positive
            case .down: return V2.Color.negative
            case .flat: return V2.Color.textTertiary
            }
        }()
        let symbol: String = {
            switch d.direction {
            case .up:   return "arrow.up"
            case .down: return "arrow.down"
            case .flat: return "minus"
            }
        }()
        return HStack(spacing: 1) {
            Image(systemName: symbol)
            Text(d.value)
        }
        .font(V2Font.caption)
        .foregroundStyle(tone)
        .padding(.leading, 2)
    }

    // MARK: Delta derivation

    /// Baseline delta for a metric: fold the history, compare the current value, return a literal-
    /// direction `V2Delta` (nil when there's no value or the baseline isn't usable yet).
    private func delta(value: Double?, cfg: MetricCfg, values: [Double?], decimals: Int) -> V2Delta? {
        guard let v = value else { return nil }
        let state = Baselines.foldHistory(values, cfg: cfg)
        guard state.usable else { return nil }
        let d = v - state.baseline
        let mag = decimals == 0 ? "\(Int(abs(d).rounded()))" : String(format: "%.\(decimals)f", abs(d))
        let dir: V2Delta.Direction = abs(d) < (decimals == 0 ? 0.5 : 0.05) ? .flat : (d > 0 ? .up : .down)
        return V2Delta(value: mag, direction: dir)
    }

    private var skinValue: String {
        guard let dev = ctx.skinTempDevC else { return "—" }
        if VitalBands.isAbsoluteSkinTemp(dev) {
            return UnitFormatter.temperatureFromCelsius(dev, unit: ctx.temperatureUnit, decimals: 1)
        }
        return UnitFormatter.temperatureDeltaFromCelsius(dev, unit: ctx.temperatureUnit, decimals: 1)
    }

    /// Skin temp is already a deviation from baseline: direction is the sign of the deviation itself.
    private var skinDelta: V2Delta? {
        guard let dev = ctx.skinTempDevC, !VitalBands.isAbsoluteSkinTemp(dev) else { return nil }
        let mag = UnitFormatter.temperatureDeltaFromCelsius(abs(dev), unit: ctx.temperatureUnit, decimals: 1)
        let dir: V2Delta.Direction = abs(dev) < 0.05 ? .flat : (dev > 0 ? .up : .down)
        return V2Delta(value: mag, direction: dir)
    }
}
#endif
