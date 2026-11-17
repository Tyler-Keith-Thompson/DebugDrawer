import DebugDrawer
import DebugDrawerDeepLinkPlugin
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code. The UIKit example (Example/iOSUIKit) shows the plugin with no handler.

/// The activity the app continued last and what handed it over, shown in the app's list.
@MainActor
final class ExampleContinuedActivity: ObservableObject {
    static let shared = ExampleContinuedActivity()

    /// "Handler: https://example.com/orders/42", or nil before the first.
    @Published private(set) var summary: String?

    /// Records `activity` as continued through `route`.
    func record(_ activity: NSUserActivity, via route: String) {
        let userInfo = (activity.userInfo ?? [:])
            .map { ("\($0.key)", "\($0.value)") }
            .sorted { $0.0 < $1.0 }
            .map { "\($0) = \($1)" }
            .joined(separator: ", ")
        let detail = activity.webpageURL?.absoluteString ?? "\(activity.activityType) {\(userInfo)}"
        summary = "\(route): \(detail)"
    }
}

/// The example's Deep Link Tester: a SwiftUI app, so it passes the plugin a handler.
enum ExampleDeepLink {
    @MainActor
    static func install() {
        DebugDrawer.shared.installDeepLink { ExampleContinuedActivity.shared.record($0, via: "Handler") }
    }
}

/// The last continued activity, and the system's own continuations of a universal link.
struct ExampleContinuedActivityRow: View {
    @ObservedObject private var continued = ExampleContinuedActivity.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last Continued Activity")
            Text(continued.summary ?? "None")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        // A universal link the system itself continues, such as one tapped in Notes.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
            continued.record($0, via: "onContinueUserActivity")
        }
    }
}
