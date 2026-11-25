#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - SettingsV2View — the v2 top-level settings list
//
// A restyled settings home for the v2 (version 10) dark-only UI. It does NOT rebuild any of the
// underlying sub-screens — it RE-HOSTS them: each row pushes the existing v1 screen
// (`DevicesView`, `StorageView`, …) via a `NavigationLink`, or, for the two modal-styled explainer
// screens that own their own close button (`ScoringGuideView`, `HowNoopWorksView`), presents them
// as a `.sheet` with an `onClose` that dismisses.
//
// The only genuinely-new controls here are the Units pickers, which write the SAME `UnitPrefs`
// `@AppStorage` keys the v1 settings screen uses, so the two never drift. Everything is dark-only,
// mono, hairline-ruled, laid out on `V2List` panels grouped by `V2SectionHeader`.
//
// Deliberately excluded (v2 is dark-only): the Appearance (Light/Dark) picker and the chart-style
// (Titanium/Classic) picker have no meaning in a single-theme UI.
//
// Presented inside a `NavigationStack` by the v2 shell, so `NavigationLink` push + the pushed v1
// screens' own navigation bars provide back navigation.

struct SettingsV2View: View {

    init() {}

    // MARK: Units preferences (display-only; shares the exact keys v1 SettingsView writes so the
    // formatter and both screens read one source of truth — no drift).
    /// Length + mass system. Temperature has its own override below.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    /// Temperature override. Empty string = "match the length/mass system".
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    /// Effort display scale — NOOP's native 0–100 axis or WHOOP's 0–21 Day Strain axis.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    // MARK: Sheet presentation for the two modal-styled explainer screens (they render their own
    // close button and take an `onClose`, so a push would leave that chrome stranded — present them).
    @State private var showScoringGuide = false
    @State private var showHowNoopWorks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V2.Space.xl) {
                V2ScreenHeader("Settings", subtitle: "Your strap, your data, and how NOOP works.")

                devicesAndDataSection
                unitsSection
                automationSection
                helpSection
            }
            .padding(.top, V2.Space.md)
            .padding(.bottom, V2.Space.xxl)
        }
        .background(V2.Color.surface0.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showScoringGuide) {
            ScoringGuideView(onClose: { showScoringGuide = false })
        }
        .sheet(isPresented: $showHowNoopWorks) {
            HowNoopWorksView(onClose: { showHowNoopWorks = false })
        }
    }

    // MARK: - Devices & data

    private var devicesAndDataSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            V2SectionHeader("Devices & Data")
            V2List {
                pushRow(title: "Devices",
                        subtitle: "WHOOP strap pairing and battery") { DevicesView() }
                pushRow(title: "Data Sources",
                        subtitle: "Imports, HR broadcast and integrations") { DataSourcesView() }
                pushRow(title: "Apple Health",
                        subtitle: "Sync workouts, sleep and vitals") { AppleHealthView() }
                pushRow(title: "Backup & Sync",
                        subtitle: "Export and restore your database") { BackupSyncView() }
                pushRow(title: "Storage",
                        subtitle: "On-device data and cache") { StorageView() }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: - Units (the one genuinely-new control set; display-only)

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            V2SectionHeader("Units")
            V2List {
                unitPicker(title: "Measurement system",
                           selection: $unitSystemRaw,
                           options: [(UnitSystem.metric.rawValue, "Metric"),
                                     (UnitSystem.imperial.rawValue, "Imperial")])
                unitPicker(title: "Temperature",
                           selection: $temperatureRaw,
                           options: [("", "Match"),
                                     (TemperatureUnit.celsius.rawValue, "°C"),
                                     (TemperatureUnit.fahrenheit.rawValue, "°F")])
                unitPicker(title: "Effort scale",
                           selection: $effortScaleRaw,
                           options: [(EffortScale.hundred.rawValue, "0–100"),
                                     (EffortScale.whoop.rawValue, "0–21")])
            }
            Text("Display only. Your data is always stored the same way — this just changes how it's shown.")
                .font(V2Font.caption)
                .foregroundStyle(V2.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, V2.Space.xs)
                .padding(.top, V2.Space.xxs)
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: - Automation

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            V2SectionHeader("Automation")
            V2List {
                pushRow(title: "Automations",
                        subtitle: "Nudges, reminders and rules") { AutomationsView() }
                pushRow(title: "Smart Alarm",
                        subtitle: "Wake in your lightest sleep") { SmartAlarmView() }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: - Help & diagnostics

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            V2SectionHeader("Help & Diagnostics")
            V2List {
                // Modal-styled explainers (own close button) → present as a sheet.
                V2ListRow(title: "How NOOP Works",
                          subtitle: "Sleep sorting, scoring and provenance") { showHowNoopWorks = true }
                V2ListRow(title: "Scoring Guide",
                          subtitle: "How Charge, Effort and Rest are built") { showScoringGuide = true }
                // Pushable screens.
                pushRow(title: "Test Centre",
                        subtitle: "Strap logs, probes and diagnostics") { TestCentreView() }
                pushRow(title: "Support",
                        subtitle: "Contact and troubleshooting") { SupportView() }
            }
        }
        .padding(.horizontal, V2.Space.gutter)
    }

    // MARK: - Row builders

    /// A nav row that pushes an existing sub-screen. Wraps a `V2ListRow` (with its trailing chevron)
    /// in a `NavigationLink` so the whole row is tappable and the pushed v1 screen supplies its own
    /// navigation bar / back button.
    @ViewBuilder
    private func pushRow<Destination: View>(title: String,
                                            subtitle: String? = nil,
                                            @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            V2ListRow(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    /// A units row: a label above a hairline `V2Segmented` control, laid out on the list panel with
    /// the same horizontal inset as `V2ListRow`.
    @ViewBuilder
    private func unitPicker(title: String,
                            selection: Binding<String>,
                            options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: V2.Space.sm) {
            Text(title)
                .font(V2Font.body)
                .foregroundStyle(V2.Color.textPrimary)
            V2Segmented(selection: selection, options: options)
        }
        .padding(.horizontal, V2.Space.lg)
        .padding(.vertical, V2.Space.md)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SettingsV2View()
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
