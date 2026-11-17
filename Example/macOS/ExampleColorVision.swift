import DebugDrawer
import DebugDrawerColorVisionPlugin
import Foundation
import SwiftUI

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's color vision simulation: the plugin installed, on request in a simulation named
/// at launch, and a row of colors to simulate.
enum ExampleColorVision {
    /// Launched with this argument and a simulation's name (`-ColorVision protanopia`), the app
    /// starts in that simulation, with the plugin pinned to the HUD. The argument domain puts it
    /// in the standard defaults.
    static let launchArgument = "ColorVision"

    /// Installs the plugin, in the simulation the launch arguments name. It compiles in release
    /// too, where it does nothing.
    @MainActor
    static func install() {
        let named = UserDefaults.standard.string(forKey: launchArgument).flatMap(ColorVision.Simulation.init(rawValue:))
        ColorVision.install(simulating: named)
        #if DEBUG
            let pluginID = "ColorVisionPlugin"
            if named != nil, !DebugDrawer.shared.hudLayout.pinned.contains(pluginID) {
                DebugDrawer.shared.toggleHUD(forPlugin: pluginID)
            }
        #endif
    }
}

/// Swatches of the system's colors, and a pass and a fail told apart by color alone, for the
/// Color Vision plugin to simulate.
struct ExampleColorSwatches: View {
    private let colors: [(String, Color)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow), ("Green", .green),
        ("Mint", .mint), ("Teal", .teal), ("Blue", .blue), ("Purple", .purple), ("Pink", .pink)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(colors, id: \.0) { name, color in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(height: 36)
                        .accessibilityLabel(name)
                }
            }
            HStack(spacing: 16) {
                Label("Passed", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                Label("Failed", systemImage: "circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
