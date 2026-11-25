import SwiftUI

// MARK: - V2SheetHeader — the top of every v2 sheet
//
// A grab-handle affordance, a mono title, and an optional trailing "Done" that calls a closure.
// Cross-platform by design: it takes an `onDone` closure rather than touching any iOS-only
// dismiss API, so the caller owns dismissal (`@Environment(\.dismiss)` at the call site, etc.).

public struct V2SheetHeader: View {
    private let title: String
    private let onDone: (() -> Void)?

    public init(_ title: String, onDone: (() -> Void)? = nil) {
        self.title = title
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: V2.Space.md) {
            Capsule()
                .fill(V2.Color.hairlineHeavy)
                .frame(width: 36, height: 5)
                .padding(.top, V2.Space.sm)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(V2Font.title)
                    .foregroundStyle(V2.Color.textPrimary)
                Spacer(minLength: V2.Space.sm)
                if let onDone {
                    Button(action: onDone) {
                        Text("Done")
                            .font(V2Font.body)
                            .foregroundStyle(V2.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
        .padding(.bottom, V2.Space.md)
    }
}

#if DEBUG
#Preview {
    ZStack(alignment: .top) {
        V2.Color.surface0.ignoresSafeArea()
        VStack(spacing: 0) {
            V2SheetHeader("Edit workout", onDone: {})
            Rectangle().fill(V2.Color.hairline).frame(height: V2.Stroke.hairline)
            Spacer()
        }
    }
}
#endif
