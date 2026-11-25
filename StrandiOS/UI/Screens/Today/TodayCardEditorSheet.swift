#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - TodayDensityPrefs — the shared density @AppStorage key
//
// The Today feed's layout density is a single `@AppStorage` knob shared LIVE between the host
// (which injects it via `.v2Density`) and this editor (which sets it). One constant so the two
// call sites can never drift.
enum TodayDensityPrefs {
    static let storageKey = "v2.today.density"
}

// MARK: - TodayCardEditorSheet — reorder / hide / density for the Today feed
//
// A `V2SheetHeader` over a native `List`: a density `V2Segmented`, the SHOWN cards (drag to
// reorder via long-press, a minus button to hide) with the hero pinned + non-movable at the top,
// and the HIDDEN cards (a plus button to show). Every change is committed straight to the shared
// `@AppStorage` so the feed behind the sheet updates immediately; "Done" just dismisses.

struct TodayCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The persisted layout (ordered enabled cards). Read + written via `TodayLayout`.
    @AppStorage(TodayLayout.storageKey) private var layoutRaw = ""
    /// Layout density, shared live with the host.
    @AppStorage(TodayDensityPrefs.storageKey) private var density: V2Density = .detailed

    /// Working copy of the SHOWN hideable cards, in order (the hero is implicit + always first).
    @State private var shown: [TodayCard] = []

    /// The hideable cards not currently shown, in canonical order.
    private var hiddenCards: [TodayCard] {
        let shownSet = Set(shown)
        return TodayCard.allCases.filter { $0.isHideable && !shownSet.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                V2SheetHeader("Edit Today") { dismiss() }

                List {
                    densitySection
                    shownSection
                    if !hiddenCards.isEmpty { hiddenSection }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(V2.Color.surface0)
            }
            .background(V2.Color.surface0.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { shown = TodayLayout.decode(layoutRaw).filter { $0.isHideable } }
    }

    // MARK: Sections

    private var densitySection: some View {
        Section {
            V2Segmented(selection: $density,
                        options: [(V2Density.compact, "Compact"), (V2Density.detailed, "Detailed")])
                .listRowInsets(EdgeInsets(top: V2.Space.sm, leading: V2.Space.lg,
                                          bottom: V2.Space.sm, trailing: V2.Space.lg))
                .listRowBackground(V2.Color.surface1)
        } header: {
            sectionHeader("Density")
        }
    }

    private var shownSection: some View {
        Section {
            heroRow
            ForEach(shown) { shownRow($0) }
                .onMove(perform: move)
        } header: {
            sectionHeader("Shown")
        } footer: {
            Text("Drag to reorder. Overview stays pinned at the top.")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
        }
    }

    private var hiddenSection: some View {
        Section {
            ForEach(hiddenCards) { hiddenRow($0) }
        } header: {
            sectionHeader("Hidden")
        }
    }

    // MARK: Rows

    private var heroRow: some View {
        rowShell(icon: TodayCard.hero.icon, title: TodayCard.hero.title, dim: false) {
            Text("Pinned")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
        }
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    private func shownRow(_ card: TodayCard) -> some View {
        rowShell(icon: card.icon, title: card.title, dim: false) {
            HStack(spacing: V2.Space.md) {
                iconButton("minus.circle.fill", tint: V2.Color.negative,
                           label: "Hide \(card.title)") { hide(card) }
                Image(systemName: "line.3.horizontal")
                    .font(V2Font.caption)
                    .foregroundStyle(V2.Color.textTertiary)
            }
        }
    }

    private func hiddenRow(_ card: TodayCard) -> some View {
        rowShell(icon: card.icon, title: card.title, dim: true) {
            iconButton("plus.circle.fill", tint: V2.Color.positive,
                       label: "Show \(card.title)") { show(card) }
        }
    }

    /// A shared row: leading glyph + title, trailing accessory, on a `surface1` list row.
    private func rowShell<Trailing: View>(icon: String, title: String, dim: Bool,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: V2.Space.md) {
            Image(systemName: icon)
                .font(V2Font.body)
                .foregroundStyle(dim ? V2.Color.textTertiary : V2.Color.textSecondary)
                .frame(width: 24)
            Text(title)
                .font(V2Font.body)
                .foregroundStyle(dim ? V2.Color.textSecondary : V2.Color.textPrimary)
            Spacer(minLength: V2.Space.sm)
            trailing()
        }
        .padding(.vertical, V2.Space.xxs)
        .listRowBackground(V2.Color.surface1)
        .listRowSeparatorTint(V2.Color.hairline)
    }

    private func iconButton(_ symbol: String, tint: Color, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(V2Font.body)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(V2Font.overline)
            .tracking(V2Font.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(V2.Color.textTertiary)
    }

    // MARK: Mutations (each commits straight to @AppStorage)

    private func move(from source: IndexSet, to destination: Int) {
        shown.move(fromOffsets: source, toOffset: destination)
        commit()
    }

    private func hide(_ card: TodayCard) {
        shown.removeAll { $0 == card }
        commit()
    }

    private func show(_ card: TodayCard) {
        guard !shown.contains(card) else { return }
        shown.append(card)
        commit()
    }

    /// Persist `[hero] + shown` through `TodayLayout.encode` (which re-normalises hero-first).
    private func commit() {
        layoutRaw = TodayLayout.encode([.hero] + shown)
    }
}

#if DEBUG
#Preview {
    TodayCardEditorSheet()
        .preferredColorScheme(.dark)
}
#endif
#endif
