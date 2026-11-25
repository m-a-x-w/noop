import SwiftUI

// MARK: - V2ScreenHeader — the large title block at the top of a screen
//
// A large mono title, an optional subtitle, optional trailing content (a settings button, a
// segmented control), and an OPTIONAL date-stepper row: prev/next chevrons around a centred
// date label, driven by a `Binding<Date>` for the label plus `onPrev` / `onNext` closures for
// the stepping (the ◀ older / ▶ newer idea ported fresh from v1 `DayNavBar`, with ▶ disabled
// when `canGoNext` is false so a future day can't be reached). No nav-bar API — this is a plain
// view the screen lays out itself.

public struct V2ScreenHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let date: Binding<Date>?
    private let canGoNext: Bool
    private let onPrev: (() -> Void)?
    private let onNext: (() -> Void)?
    private let trailing: Trailing

    public init(_ title: String,
                subtitle: String? = nil,
                date: Binding<Date>? = nil,
                canGoNext: Bool = true,
                onPrev: (() -> Void)? = nil,
                onNext: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.canGoNext = canGoNext
        self.onPrev = onPrev
        self.onNext = onNext
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: V2.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: V2.Space.sm) {
                VStack(alignment: .leading, spacing: V2.Space.xxs) {
                    Text(title)
                        .font(V2Font.title)
                        .foregroundStyle(V2.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(V2Font.label)
                            .foregroundStyle(V2.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: V2.Space.sm)
                trailing
            }
            if let date {
                dateStepper(date.wrappedValue)
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    @ViewBuilder
    private func dateStepper(_ day: Date) -> some View {
        HStack(spacing: V2.Space.sm) {
            Button { onPrev?() } label: {
                Image(systemName: "chevron.left")
                    .font(V2Font.body)
                    .foregroundStyle(V2.Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            Spacer(minLength: 0)
            Text(v2ScreenHeaderDateFmt.string(from: day))
                .font(V2Font.label)
                .foregroundStyle(V2.Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)

            Button { if canGoNext { onNext?() } } label: {
                Image(systemName: "chevron.right")
                    .font(V2Font.body)
                    .foregroundStyle(canGoNext ? V2.Color.textSecondary : V2.Color.textDisabled)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoNext)
            .accessibilityLabel("Next day")
        }
        .background(V2.Color.surface1, in: Capsule())
        .overlay(Capsule().strokeBorder(V2.Color.hairline, lineWidth: V2.Stroke.hairline))
    }
}

// File-scoped because `static let` isn't allowed on a generic type (`V2ScreenHeader<Trailing>`).
private let v2ScreenHeaderDateFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

public extension V2ScreenHeader where Trailing == EmptyView {
    /// Screen header with no trailing content.
    init(_ title: String,
         subtitle: String? = nil,
         date: Binding<Date>? = nil,
         canGoNext: Bool = true,
         onPrev: (() -> Void)? = nil,
         onNext: (() -> Void)? = nil) {
        self.init(title,
                  subtitle: subtitle,
                  date: date,
                  canGoNext: canGoNext,
                  onPrev: onPrev,
                  onNext: onNext) { EmptyView() }
    }
}

#if DEBUG
private struct V2ScreenHeaderPreview: View {
    @State private var day = Date()
    var body: some View {
        ZStack(alignment: .top) {
            V2.Color.surface0.ignoresSafeArea()
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Today", subtitle: "Sunday") {
                    Image(systemName: "gearshape")
                        .font(V2Font.title)
                        .foregroundStyle(V2.Color.textSecondary)
                }
                V2ScreenHeader("History",
                               date: $day,
                               canGoNext: false,
                               onPrev: { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day },
                               onNext: { day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day })
            }
            .padding(.vertical, V2.Space.xl)
        }
    }
}

#Preview {
    V2ScreenHeaderPreview()
}
#endif
