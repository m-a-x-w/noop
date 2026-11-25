import WidgetKit
import SwiftUI
import StrandDesign

/// The widget extension entry point. Bundles the glanceable widget and the live-HR Live Activity.
@main
struct NOOPWidgetBundle: WidgetBundle {
    /// Register the bundled 0xProto Nerd Font Mono faces in the widget process too — the extension
    /// runs in its own process and the app's `registerFonts()` doesn't carry over, so v2 widget
    /// surfaces would otherwise fall back to a system face. Idempotent + cheap at bundle init.
    init() { V2Font.registerFonts() }

    var body: some Widget {
        NOOPWidget()
        NOOPLiveActivity()
    }
}
