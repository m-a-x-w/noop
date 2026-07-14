#if os(iOS)
import Foundation
import AppIntents

// The ACTION intents live here in the shared folder — not in StrandiOS/System — because interactive
// widget/Live Activity buttons fire them from the widget-extension process, so BOTH NOOPiOS and
// NOOPiOSWidgets must compile them. Public to mirror WidgetSnapshot's access style. NOOPShortcuts
// (the AppShortcutsProvider) deliberately stays in the app target (StrandiOS/System/NOOPAppIntents.swift):
// a provider compiled into the widget extension too would double-register the Siri phrases.

/// Queue of actions requested by an App Intent while the app may be suspended. Intents can't reach
/// into the running `AppModel` directly (BLE only lives in the foreground app), so they enqueue here
/// and the app drains the queue when it next becomes active.
public enum PendingIntents {
    public enum Action: String { case markMoment, buzz }

    private static let key = "noop.pendingIntents"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.suiteName) }

    /// Optional `at` is the invocation time, captured now and consumed on drain. Encoded into the
    /// stored string as "rawValue:epochSeconds" so the array stays a plain [String] (no schema
    /// migration; a legacy bare "markMoment" still decodes with a nil date).
    public static func append(_ action: Action, at date: Date? = nil) {
        guard let d = defaults else { return }
        var list = d.stringArray(forKey: key) ?? []
        if let date { list.append("\(action.rawValue):\(date.timeIntervalSince1970)") }
        else { list.append(action.rawValue) }
        d.set(list, forKey: key)
    }

    public static func drain() -> [(action: Action, date: Date?)] {
        guard let d = defaults else { return [] }
        let raw = d.stringArray(forKey: key) ?? []
        d.removeObject(forKey: key)
        return raw.compactMap { entry in
            // Guard `parts.first` rather than subscripting `parts[0]`: split(omittingEmptySubsequences:
            // true by default) returns an EMPTY array for an empty or ":"-leading entry, and indexing
            // [0] there is a fatal trap. This value comes from shared App Group defaults read untrusted,
            // so a corrupt/foreign entry must be skipped, not crash the app on foreground.
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let first = parts.first, let action = Action(rawValue: String(first)) else { return nil }
            let date = parts.count == 2 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil
            return (action, date)
        }
    }
}

/// Record a timestamped "moment" — the iOS analogue of the strap double-tap "mark a moment" action.
public struct MarkMomentIntent: AppIntent {
    public static var title: LocalizedStringResource = "Mark a Moment"
    public static var description = IntentDescription("Record a timestamped moment in NOOP.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.append(.markMoment, at: Date())
        return .result(dialog: "Moment marked.")
    }
}

/// Send a confirming haptic buzz to the strap. Opens the app so the live BLE link can deliver it.
public struct BuzzStrapIntent: AppIntent {
    public static var title: LocalizedStringResource = "Buzz Strap"
    public static var description = IntentDescription("Send a haptic buzz to your WHOOP strap.")
    public static var openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        PendingIntents.append(.buzz)
        return .result()
    }
}
#endif
