#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - V2TabBar — the full-width bottom bar
//
// A minimal, non-floating bottom bar: a single hairline top edge over a `surface0` fill, two mono
// overline tab labels (TODAY / EXPLORE) flanking a centre circular "+" quick-action button. The
// selected label reads in `textPrimary`, the unselected in `textTertiary`; the "+" is a ~44pt tap
// target tinted with the neutral accent. The bar respects the safe-area bottom inset itself so the
// host can pin it flush to the screen edge.

struct V2TabBar: View {
    @Binding var selection: V2Tab
    /// Fires when the centre "+" is tapped — the host opens the quick-action sheet.
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab("Today", tab: .today)
            plusButton
            tab("Explore", tab: .explore)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, V2.Space.md)
        .padding(.bottom, V2.Space.xs)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                V2.Color.surface0
                Rectangle()
                    .fill(V2.Color.hairline)
                    .frame(height: V2.Stroke.hairline)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Tab label

    private func tab(_ title: String, tab: V2Tab) -> some View {
        let active = selection == tab
        return Button {
            guard selection != tab else { return }
            withAnimation(V2Motion.snap) { selection = tab }
        } label: {
            Text(title)
                .font(V2Font.overline)
                .tracking(V2Font.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(active ? V2.Color.textPrimary : V2.Color.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Centre "+"

    private var plusButton: some View {
        Button(action: onPlus) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(V2.Color.accent)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(V2.Color.surface2)
                        .overlay(Circle().strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick actions")
        .padding(.horizontal, V2.Space.lg)
    }
}

#if DEBUG
private struct V2TabBarPreview: View {
    @State private var tab: V2Tab = .today
    var body: some View {
        ZStack(alignment: .bottom) {
            V2.Color.surface0.ignoresSafeArea()
            V2TabBar(selection: $tab, onPlus: {})
        }
        .preferredColorScheme(.dark)
    }
}
#Preview { V2TabBarPreview() }
#endif
#endif
