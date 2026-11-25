#if os(iOS)
import SwiftUI
import StrandDesign

/// Root of the NOOP v2 UI (version 10). Two tabs — **Today** and **Explore** — plus a centre "+"
/// quick action. This is the B1 shell: a custom (TabView-free) layout of `activeTabContent` over a
/// full-width `V2TabBar`, each tab wrapped in its OWN `NavigationStack` so the tabs own their push
/// destinations independently. Top-level chrome (quick-action sheet, Settings, Devices, the Live /
/// Breathe covers, and routed v5-pillar sheets) is driven by `V2ShellState`; cross-cutting deep
/// links from the shared `NavRouter` are adapted into shell actions via `V2ShellState.handle(_:)`.
///
/// Lives under `StrandiOS/UI/` so it compiles into the `NOOPiOS` target ONLY — macOS and watch keep
/// using the legacy `Strand/Screens/*` views untouched.
///
/// Selected from `StrandiOSApp.iOSRootView` behind the `noop.uiV2Enabled` flag (default off during
/// migration; `--ui-v2` launch arg forces it on for the screenshot loop).
struct V2RootView: View {
    @StateObject private var shell = V2ShellState()
    @EnvironmentObject private var router: NavRouter
    /// Today tab nav path. In DEBUG it can be seeded from `--v2-detail <route>` so the screenshot loop can
    /// capture a pushed detail screen deterministically (e.g. `--v2-detail charge` / `metric:hrv`).
    @State private var todayPath: [V2DetailRoute] = []

    #if DEBUG
    static func debugSeedPath() -> [V2DetailRoute] {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--v2-detail"), i + 1 < args.count else { return [] }
        let spec = args[i + 1]
        let today = Calendar.current.startOfDay(for: Date())
        switch spec {
        case "charge":        return [.charge(today)]
        case "sleep":         return [.sleep(today)]
        case "stress":        return [.stress(today)]
        case "vitals":        return [.vitalsDay(today)]
        case "workouts":      return [.workouts]
        case "trends":        return [.trends(nil)]
        case "relationships": return [.relationships]
        default:
            if spec.hasPrefix("metric:") { return [.metric(String(spec.dropFirst("metric:".count)))] }
            if spec.hasPrefix("trends:") { return [.trends(String(spec.dropFirst("trends:".count)))] }
            return []
        }
    }
    #else
    static func debugSeedPath() -> [V2DetailRoute] { [] }
    #endif

    var body: some View {
        ZStack {
            V2.Color.surface0.ignoresSafeArea()

            VStack(spacing: 0) {
                activeTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                V2TabBar(selection: $shell.selectedTab, onPlus: { shell.openQuickActions() })
            }
        }
        .preferredColorScheme(.dark)
        // The centre "+" (and any screen's NavRouter.requestQuickActions()). Dismiss-then-route in
        // `onDismiss` so a fullScreenCover is never mounted while this sheet is still on screen.
        .sheet(isPresented: $shell.quickActionsPresented, onDismiss: { shell.routePendingQuickAction() }) {
            V2QuickActionSheet(onPick: { shell.pickQuickAction($0) },
                               onDone: { shell.quickActionsPresented = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
        // Quick-action + deep-link targets presented as sheets (workout / journal / hydration / caffeine).
        .sheet(item: $shell.sheetTarget) { action in
            hostedSheet { sheetScreen(action) } onDone: { shell.sheetTarget = nil }
        }
        // Live / Breathe are full-screen covers (v2 IA convention).
        .fullScreenCover(item: $shell.coverTarget) { action in
            coverScreen(action)
        }
        // Settings stack (D1 SettingsV2View).
        .sheet(isPresented: $shell.settingsPresented) {
            hostedSheet { SettingsV2View() } onDone: { shell.settingsPresented = false }
        }
        // Devices manager (pair / switch bands).
        .sheet(isPresented: $shell.devicesPresented) {
            hostedSheet { DevicesView() } onDone: { shell.devicesPresented = false }
        }
        // Routed v5-pillar sheet (Insights hub / Lab Book / fused record / Rhythm / Trends).
        .sheet(item: $shell.routedPillar) { dest in
            hostedSheet { pillarScreen(dest) } onDone: { shell.routedPillar = nil }
        }
        // NavRouter deep links → shell actions, cleared after handling (v1 RootTabView semantics).
        .onChange(of: router.requestedDestination) { _, dest in
            guard let dest else { return }
            shell.handle(dest)
            router.requestedDestination = nil
        }
        // A screen's top-bar "+" (NavRouter.requestQuickActions()) opens the quick-action sheet.
        .onChange(of: router.quickActionsRequested) { _, req in
            guard req else { return }
            shell.openQuickActions()
            router.quickActionsRequested = false
        }
        #if DEBUG
        // Seed a pushed detail from `--v2-detail <route>` AFTER first render, so the Today tab's
        // navigationDestination is registered before the path is applied (a cold-init seed can be
        // dropped by NavigationStack). Screenshot-loop only; no-op without the argument.
        .task {
            let seed = Self.debugSeedPath()
            if !seed.isEmpty { shell.selectedTab = .today; todayPath = seed }
        }
        #endif
    }

    // MARK: - Tab content (each tab owns its own NavigationStack)

    @ViewBuilder
    private var activeTabContent: some View {
        switch shell.selectedTab {
        case .today:
            NavigationStack(path: $todayPath) {
                TodayV2Host(onOpenSettings: { shell.openSettings() })
            }
        case .explore:
            NavigationStack {
                ExploreV2Host(onOpenSettings: { shell.openSettings() })
            }
        }
    }

    // MARK: - Presented-screen hosts

    /// Wraps a shell-presented screen in its own `NavigationStack` with the v2 surface and a Done
    /// button that runs `onDone`. Matches the v1 idiom of hosting the existing screens in a nav stack.
    private func hostedSheet<Content: View>(@ViewBuilder _ content: () -> Content,
                                            onDone: @escaping () -> Void) -> some View {
        NavigationStack {
            content()
                .background(V2.Color.surface0.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: onDone)
                            .foregroundStyle(V2.Color.accent)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    /// The existing screen a sheet quick-action target opens.
    @ViewBuilder
    private func sheetScreen(_ action: V2QuickAction) -> some View {
        switch action {
        case .workout:   WorkoutsView()
        case .journal:   InsightsView()
        case .hydration: HydrationView()
        case .caffeine:  CaffeineLogCard()
        // Cover-only actions never reach here; keep the switch exhaustive.
        case .live, .breathe: EmptyView()
        }
    }

    /// The existing screen a cover quick-action target opens (Live / Breathe). `LiveView` reads and
    /// clears `NavRouter.presentActiveWorkout` itself on appear, so the active-workout deep link is
    /// honoured by simply presenting Live.
    @ViewBuilder
    private func coverScreen(_ action: V2QuickAction) -> some View {
        Group {
            switch action {
            case .live:    LiveView()
            case .breathe: BreathingView()
            // Sheet-only actions never reach here; keep the switch exhaustive.
            case .workout, .journal, .hydration, .caffeine: EmptyView()
            }
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Done") { shell.coverTarget = nil }
                .foregroundStyle(V2.Color.accent)
                .padding(V2.Space.gutter)
        }
        .preferredColorScheme(.dark)
    }

    /// A routed v5-pillar screen (dissolves into native Explore surfaces in the C-wave).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        switch dest {
        case .insightsHub:  InsightsHubView()
        case .labBook:      LabBookView()
        case .fusedRecord:  FusedRecordHost()
        case .rhythm:       RhythmHost(onClose: { shell.routedPillar = nil })
        case .trends:       TrendsView()
        // Non-pillar destinations are handled elsewhere; fall back rather than crash if one arrives.
        case .devices:        DevicesView()
        case .activeWorkout:  LiveView()
        case .liveSession:    LiveView()
        }
    }
}

#if DEBUG
#Preview {
    V2RootView()
        .environmentObject(NavRouter())
}
#endif
#endif
