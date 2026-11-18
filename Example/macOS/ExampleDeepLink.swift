import DebugDrawer
import DebugDrawerDeepLinkPlugin
import Foundation
import SwiftUI

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The app's deep-link routing: the URL or activity it took last and what handed it over, shown
/// in the app's window.
@MainActor
final class ExampleDeepLinks: ObservableObject {
    static let shared = ExampleDeepLinks()

    /// The scheme Info.plist declares under CFBundleURLTypes.
    static let scheme = "debugdrawer-example"

    /// "openURL: debugdrawer-example://orders/42", or nil before the first.
    @Published private(set) var summary: String?

    /// Takes `url` when it is of the app's own scheme, through `route`, and says whether it did.
    @discardableResult
    func route(_ url: URL, via route: String) -> Bool {
        guard url.scheme?.lowercased() == Self.scheme else { return false }
        summary = "\(route): \(url.absoluteString)"
        return true
    }

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

/// The example's Deep Link Tester: a SwiftUI app, so it passes the plugin its own handlers, and
/// the presets are the scheme Info.plist declares.
enum ExampleDeepLink {
    @MainActor
    static func install() {
        DebugDrawer.shared.installDeepLink(
            continueUserActivity: { ExampleDeepLinks.shared.record($0, via: "continueUserActivity") },
            openURL: { ExampleDeepLinks.shared.route($0, via: "openURL") }
        )
    }
}

/// The last deep link the app took, from the plugin or from the system itself.
struct ExampleDeepLinkRow: View {
    @ObservedObject private var deepLinks = ExampleDeepLinks.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last Deep Link")
            Text(deepLinks.summary ?? "None")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // A URL of the app's scheme the system itself opens, such as one typed in Safari.
        .onOpenURL { deepLinks.route($0, via: "onOpenURL") }
        // A universal link the system itself continues, such as one tapped in Mail.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
            deepLinks.record($0, via: "onContinueUserActivity")
        }
    }
}
