import SwiftUI

// MARK: - V2 Ring (custom Canvas)
//
// ONE flat gauge that replaces the v1 RecoveryRing / StrainGauge / BevelGauge / GlowRing zoo:
// a 2.5pt hairline track plus a 2.5pt accent arc sweeping clockwise from the top, with an
// optional centred value + label. NO bevel, NO glow, NO shadow — just two strokes and mono text.
//
// The arc is a custom `Canvas`/`Path`; the centred readout is a plain SwiftUI overlay so it stays
// crisp text (not rasterised). The value is rendered with `V2Font.numeral` (a FROZEN, tabular
// point size) so it can't overflow the ring and never reflows on value change.
//
// NOTE: the packet sketch shows a `V2BigNumber` in the centre, but that primitive is owned by a
// different packet, is absent from this target, and its real signature differs from the sketch.
// To keep V2Ring compilable against ONLY this packet's declared deps (V2 tokens / V2Domain /
// V2ChartScale / V2Font), the centred number is rendered directly here with `V2Font`.
//
// Canvas is available on the whole floor (macOS 12 / iOS 15 / watchOS 8) — no availability gate.

public struct V2Ring: View {

    private let progress: Double
    private let domain: V2Domain
    private let size: CGFloat
    private let label: String?
    private let value: String?

    private let lineWidth: CGFloat = 2.5

    public init(
        progress: Double,
        domain: V2Domain,
        size: CGFloat = 120,
        label: String? = nil,
        value: String? = nil
    ) {
        self.progress = progress
        self.domain = domain
        self.size = size
        self.label = label
        self.value = value
    }

    private var clamped: Double { min(max(progress, 0), 1) }

    public var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = (min(canvasSize.width, canvasSize.height) - lineWidth) / 2
                guard radius > 0 else { return }

                // Hairline track (full circle).
                let track = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                context.stroke(track,
                               with: .color(V2.Color.hairlineHeavy),
                               style: StrokeStyle(lineWidth: lineWidth))

                // Accent arc — clockwise from the top (−90°) for `clamped` of the circle.
                if clamped > 0 {
                    var arc = Path()
                    arc.addArc(center: center,
                               radius: radius,
                               startAngle: .degrees(-90),
                               endAngle: .degrees(-90 + 360 * clamped),
                               clockwise: false)
                    context.stroke(arc,
                                   with: .color(domain.accent),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

            if value != nil || label != nil {
                VStack(spacing: 2) {
                    if let value {
                        Text(value)
                            .font(V2Font.numeral(size * 0.26))
                            .foregroundStyle(V2.Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let label {
                        Text(label.uppercased())
                            .font(V2Font.overline)
                            .tracking(V2Font.overlineTracking)
                            .foregroundStyle(V2.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(.horizontal, lineWidth + 6)
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
#Preview("V2Ring") {
    HStack(spacing: 20) {
        V2Ring(progress: 0.72, domain: .charge, label: "Charge", value: "72")
        V2Ring(progress: 0.44, domain: .effort, size: 96, label: "Effort", value: "8.6")
        V2Ring(progress: 0.9, domain: .rest, size: 72)
    }
    .padding(24)
    .background(V2.Color.surface0)
    .preferredColorScheme(.dark)
}
#endif
