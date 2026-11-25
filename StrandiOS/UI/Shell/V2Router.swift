#if os(iOS)
import SwiftUI
import Combine

// MARK: - V2 shell state + cross-cutting deep-link adapter
//
// `V2ShellState` is the single source of truth for the v2 shell's TOP-LEVEL chrome: which tab is
// selected and which shell-owned modal is up (the quick-action sheet, the Settings stack, the
// Devices manager, a routed v5-pillar sheet, and the Live / Breathe full-screen covers). It is
// NOT a per-screen push router — each tab owns its own `NavigationStack` and its own
// `navigationDestination`s. This object only carries the things the shell itself presents.
//
// The one cross-cutting job here is the deep-link adapter: the shared `NavRouter` (widgets, App
// Intents, in-app "open X" affordances) publishes a `Destination`, and `handle(_:)` maps each case
// to a shell action. `V2RootView` observes `NavRouter` and forwards to these methods, then clears
// the `NavRouter` request — exactly the clear/reset semantics v1 `RootTabView` uses so the same tap
// can fire again later.

/// The two top-level tabs of the v2 shell.
public enum V2Tab: Hashable {
    case today
    case explore
}

@MainActor
final class V2ShellState: ObservableObject {

    // MARK: Tab selection

    /// The active tab. Defaults to Today. In DEBUG, `--v2-tab explore` selects Explore at launch so the
    /// screenshot/verification loop can capture either tab deterministically.
    @Published var selectedTab: V2Tab = {
        #if DEBUG
        if CommandLine.arguments.contains("--v2-tab"),
           let i = CommandLine.arguments.firstIndex(of: "--v2-tab"),
           i + 1 < CommandLine.arguments.count,
           CommandLine.arguments[i + 1] == "explore" {
            return .explore
        }
        #endif
        return .today
    }()

    // MARK: Shell-owned presentation

    /// The centre "+" quick-action sheet.
    @Published var quickActionsPresented = false
    /// The Settings stack (present the existing `SettingsView` for now; D1 swaps in `SettingsV2View`).
    @Published var settingsPresented = false
    /// The Devices manager (pair / switch bands), raised by a `NavRouter` request or a device chip.
    @Published var devicesPresented = false
    /// A routed v5-pillar screen presented as a sheet in the Explore tab (Insights hub / Lab Book /
    /// fused record / Rhythm / Trends). `nil` = closed. These dissolve into native Explore surfaces
    /// in the C-wave; until then the shell re-hosts the existing screens.
    @Published var routedPillar: NavRouter.Destination?
    /// A quick-action target presented as a `.sheet` (workout / journal / hydration / caffeine).
    @Published var sheetTarget: V2QuickAction?
    /// A quick-action target presented as a `.fullScreenCover` (live / breathe), matching the v2 IA
    /// convention (Live + Breathe are covers, everything else is a sheet).
    @Published var coverTarget: V2QuickAction?

    /// Buffered pick from the quick-action sheet. The sheet is dismissed first, then this is routed in
    /// its `onDismiss` — never nest a `fullScreenCover` inside the live sheet (the v1 flicker fix).
    private var pendingQuickAction: V2QuickAction?

    // MARK: Quick-action flow (flicker-safe present-then-route)

    /// Called by the quick-action sheet when the user picks a row: buffer the choice and dismiss the
    /// sheet. `routePendingQuickAction()` (the sheet's `onDismiss`) then presents the real target, so a
    /// cover is never mounted while the sheet is still on screen.
    func pickQuickAction(_ action: V2QuickAction) {
        pendingQuickAction = action
        quickActionsPresented = false
    }

    /// Presents the buffered quick-action target. Wired to the quick-action sheet's `onDismiss` so the
    /// sheet is fully gone before the next presentation mounts.
    func routePendingQuickAction() {
        guard let action = pendingQuickAction else { return }
        pendingQuickAction = nil
        switch action {
        case .live, .breathe:
            coverTarget = action
        case .workout, .journal, .hydration, .caffeine:
            sheetTarget = action
        }
    }

    /// Opens the quick-action sheet (the centre "+", or a screen's `NavRouter.requestQuickActions()`).
    func openQuickActions() { quickActionsPresented = true }

    /// Presents the Settings stack (profile affordance in a tab header).
    func openSettings() { settingsPresented = true }

    // MARK: NavRouter deep-link adapter

    /// Map a `NavRouter.Destination` to a shell action. `V2RootView` calls this from its
    /// `onChange(of: router.requestedDestination)` and then clears the request, mirroring v1.
    func handle(_ destination: NavRouter.Destination) {
        switch destination {
        case .devices:
            devicesPresented = true
        case .insightsHub, .labBook, .fusedRecord, .rhythm, .trends:
            // These live under Explore in v2. Switch to Explore and present the existing screen as a
            // sheet for now (C-wave dissolves them into native Explore surfaces).
            selectedTab = .explore
            routedPillar = destination
        case .activeWorkout:
            // Present Live as a cover; `NavRouter.presentActiveWorkout` is left set so `LiveView`
            // consumes it on appear (`consumeActiveWorkoutRequest()`) and opens the in-exercise screen.
            coverTarget = .live
        case .liveSession:
            // Live Sessions deep-links land on the Live surface too (the v1 Today entry owns the real
            // cover; this keeps deep-link parity until C-wave gives Today its own entry).
            coverTarget = .live
        }
    }
}
#endif
