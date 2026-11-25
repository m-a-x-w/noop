#if os(iOS)
import SwiftUI

// MARK: - V2DetailRoute — the SHARED detail-routing contract for the v2 UI
//
// Every drill-in reachable from Today or Explore is a value of this enum. Both `TodayV2Host` and
// `ExploreV2Host` attach a single `.navigationDestination(for: V2DetailRoute.self)` that resolves
// each case through `v2DetailDestination(_:)` below, so screens navigate purely by pushing a value
// (`NavigationLink(value: V2DetailRoute.charge(date))`) and never construct a destination view
// themselves. The v2 detail packets OWN their view files (init signatures are frozen here); the
// v1-hosted cases re-use the existing screens until they dissolve into native v2 surfaces.

public enum V2DetailRoute: Hashable {
    /// Charge (recovery) breakdown for a day.
    case charge(Date)
    /// Sleep detail for a day (hypnogram, stages, debt).
    case sleep(Date)
    /// Day-stress detail for a day.
    case stress(Date)
    /// Full-day vitals + health record for a day.
    case vitalsDay(Date)
    /// A single catalog metric's detail, keyed by `MetricDescriptor.key`.
    case metric(String)
    /// The workouts history list.
    case workouts
    /// A single workout, keyed by its row id.
    case workoutDetail(String)
    /// Trends report, optionally focused on one metric key (nil = the multi-metric overview).
    case trends(String?)
    /// Behaviour → outcome relationships (correlations / dose-response).
    case relationships
    /// v1 Lab Book (experiments).
    case labBook
    /// v1 Rhythm (beat-to-beat visualization) — resolved via its self-contained host.
    case rhythm
    /// v1 AI Coach.
    case coach
    /// v1 Insights feed.
    case insights
}

/// Resolve a `V2DetailRoute` to its destination view. Attached once per tab host via
/// `.navigationDestination(for: V2DetailRoute.self) { v2DetailDestination($0) }`. The v2 cases map
/// to the packet-owned detail views (frozen init signatures); the v1 cases re-host the existing
/// screens (`RhythmHost` is the self-contained wrapper that feeds `RhythmView` its engine results).
@ViewBuilder
func v2DetailDestination(_ route: V2DetailRoute) -> some View {
    switch route {
    case .charge(let date):        ChargeDetailV2View(date: date)
    case .sleep(let date):         SleepV2View(date: date)
    case .stress(let date):        StressV2View(date: date)
    case .vitalsDay(let date):     VitalsHealthV2View(date: date)
    case .metric(let key):         MetricDetailV2View(metricKey: key)
    case .workouts:                WorkoutsV2View()
    case .workoutDetail(let id):   WorkoutDetailV2View(workoutID: id)
    case .trends(let key):         TrendsV2View(metricKey: key)
    case .relationships:           RelationshipsV2View()
    case .labBook:                 LabBookView()
    case .rhythm:                  RhythmHost()
    case .coach:                   CoachView()
    case .insights:                InsightsView()
    }
}
#endif
