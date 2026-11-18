import DebugDrawerViewInspectorPlugin
import Foundation

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The View Inspector's overlays, turned on from the launch arguments.
enum ExampleViewInspector {
    /// Launched with -ViewInspectorBorders, -ViewInspectorGrid or -ViewInspectorClickIndicators,
    /// the View Inspector starts with that overlay on, so it can be checked without a hand.
    @MainActor
    static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        let controller = ViewBorderController.shared
        controller.isBordersEnabled = arguments.contains("-ViewInspectorBorders")
        controller.isGridEnabled = arguments.contains("-ViewInspectorGrid")
        controller.isClickIndicatorEnabled = arguments.contains("-ViewInspectorClickIndicators")
    }
}
