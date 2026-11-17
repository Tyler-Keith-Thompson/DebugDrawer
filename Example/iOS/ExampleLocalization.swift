import DebugDrawerColorVisionPlugin
import DebugDrawerLocalizationPlugin
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's localization: Resources/<language>.lproj holds English and German tables, the
/// German one deliberately missing three keys, which the Localization plugin lists.
enum ExampleLocalization {
    /// Launched with this argument, the app starts pseudo-localized, so the plugin can be checked
    /// without a hand.
    static let pseudoLocalizeArgument = "-PseudoLocalize"
    /// Launched with this argument, the app starts showing its strings' keys.
    static let showKeysArgument = "-ShowLocalizationKeys"

    /// Installs the Localization plugin, in the mode the launch arguments ask for. It compiles in
    /// release too, where it does nothing.
    @MainActor
    static func install() {
        let arguments = ProcessInfo.processInfo.arguments
        let mode: Localization.Mode = if arguments.contains(pseudoLocalizeArgument) {
            .pseudoLocalized
        } else if arguments.contains(showKeysArgument) {
            .showingKeys
        } else {
            .standard
        }
        Localization.install(mode: mode)
    }
}

/// Text from the app's own tables, looked up through NSLocalizedString, which the plugin's modes
/// rewrite: a greeting, a plural with a stepper, a format, two strings German lacks, and one no
/// table has yet; then two SwiftUI looks up itself, which only the next launch's settings reach.
struct ExampleLocalizedSection: View {
    @State private var orders = 1

    private var ordersText: String {
        String.localizedStringWithFormat(NSLocalizedString("orders.count", comment: "How many orders are in progress"), orders)
    }

    var body: some View {
        Section(NSLocalizedString("localization.section", comment: "The section's title")) {
            // Under the Color Vision simulation, all but the stepper's control, which UIKit
            // draws: a shader can't, so it would show SwiftUI's placeholder.
            Group {
                Text(NSLocalizedString("welcome.title", comment: "A greeting"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(NSLocalizedString("welcome.subtitle", comment: "Below the greeting"))
            }
            .debugColorVision()
            Stepper(value: $orders, in: 0 ... 10) {
                Text(ordersText)
                    .debugColorVision()
            }
            .accessibilityLabel(ordersText)
            Group {
                Text(String(format: NSLocalizedString("checkout.delivery", comment: "The delivery day"), "Friday"))
                Text(NSLocalizedString("checkout.promo", comment: "Asks for a promo code"))
                Text(NSLocalizedString("settings.privacy", comment: "A link to the privacy policy"))
                // SwiftUI looks these up itself, past the live modes; Whole App on Next Launch reaches them.
                Text("swiftui.text")
                Text(String(localized: "swiftui.resource"))
                // In no table yet: the plugin lists it as looked up.
                Text(NSLocalizedString("banner.new", value: "New: faster checkout", comment: "A banner"))
            }
            .debugColorVision()
        }
    }
}
