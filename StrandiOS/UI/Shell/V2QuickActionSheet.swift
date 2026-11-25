#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - V2QuickAction — the actions the centre "+" can open
//
// `Identifiable` so it drives `.sheet(item:)` / `.fullScreenCover(item:)` in the shell. The shell
// decides the presentation style per case (v2 IA: Live + Breathe are full-screen covers; workout,
// journal, hydration and caffeine logs are sheets).

enum V2QuickAction: String, Identifiable, Hashable {
    case live
    case workout
    case journal
    case breathe
    case hydration
    case caffeine

    var id: String { rawValue }
}

// MARK: - V2QuickActionSheet — the restyled quick-action menu
//
// A `V2SheetHeader` + a single `V2List` of rows. Picking a row calls `onPick`; the shell buffers the
// choice, dismisses this sheet, then presents the real target in the sheet's `onDismiss` (never nest
// a cover inside the live sheet — the v1 flicker fix). Presented at a medium detent by the host.

struct V2QuickActionSheet: View {
    /// Called with the picked action. The host routes it after this sheet dismisses.
    var onPick: (V2QuickAction) -> Void
    /// Dismisses the sheet without picking anything (the header "Done").
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            V2SheetHeader("Quick actions", onDone: onDone)

            ScrollView {
                VStack(spacing: V2.Space.lg) {
                    V2List {
                        V2ListRow(title: "Live HR",
                                  subtitle: "Real-time heart rate",
                                  trailingSymbol: "waveform.path.ecg",
                                  chevron: false,
                                  action: { onPick(.live) })
                        V2ListRow(title: "Start workout",
                                  subtitle: "Track effort live",
                                  trailingSymbol: "figure.run",
                                  chevron: false,
                                  action: { onPick(.workout) })
                        V2ListRow(title: "Log journal",
                                  subtitle: "Note how you feel",
                                  trailingSymbol: "square.and.pencil",
                                  chevron: false,
                                  action: { onPick(.journal) })
                        V2ListRow(title: "Breathe",
                                  subtitle: "Guided session",
                                  trailingSymbol: "wind",
                                  chevron: false,
                                  action: { onPick(.breathe) })
                    }

                    VStack(alignment: .leading, spacing: V2.Space.sm) {
                        Text("Quick logs")
                            .font(V2Font.overline)
                            .tracking(V2Font.overlineTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(V2.Color.textTertiary)
                            .padding(.horizontal, V2.Space.xs)
                        V2List {
                            V2ListRow(title: "Log hydration",
                                      trailingSymbol: "drop.fill",
                                      chevron: false,
                                      action: { onPick(.hydration) })
                            V2ListRow(title: "Log caffeine",
                                      trailingSymbol: "cup.and.saucer.fill",
                                      chevron: false,
                                      action: { onPick(.caffeine) })
                        }
                    }
                }
                .padding(.horizontal, V2.Space.gutter)
                .padding(.top, V2.Space.sm)
                .padding(.bottom, V2.Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(V2.Color.surface0.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    ZStack {
        V2.Color.surface0.ignoresSafeArea()
        V2QuickActionSheet(onPick: { _ in }, onDone: {})
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
