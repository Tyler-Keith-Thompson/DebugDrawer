import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// View borders by depth, the alignment grid, click indicators and slowed animations over the
/// app's windows, the key window's view hierarchy and the render counts of the views tracked with
/// `.trackRenders(_:)`.
public struct ViewInspectorPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "ViewInspectorPlugin"
    }

    public var title = "View Inspector"
    public var category = "Interface"
    public var icon = "rectangle.dashed"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: ViewInspectorModel?

        /// The plugin over ``ViewInspectorModel/shared``.
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show and install in place of the shared one.
        init(model: ViewInspectorModel) {
            self.model = model
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            ViewInspectorPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Counts renders with `.trackRenders(_:)` into this plugin's model while `drawer` is the
    /// latest drawer to have installed the plugin, and, on iOS, swaps `UIWindow.sendEvent(_:)` so
    /// the click indicators switch can show touches, as `drawer` adds the plugin. Release builds do
    /// nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            let model = model ?? .shared
            model.install(in: ObjectIdentifier(drawer))
            RenderTracking.install(model.renderTracker, for: ObjectIdentifier(drawer))
        #endif
    }

    /// Stops counting renders into this plugin's model; the drawer that installed the plugin before
    /// `drawer` gets the counts again. Once no drawer holds the plugin, turns the borders, grid,
    /// click indicators, render flashes and slowed animations off, removes the overlay windows,
    /// forgets the render counts and the hierarchy snapshot, and on iOS gives
    /// `UIWindow.sendEvent(_:)` UIKit's implementation back.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            RenderTracking.uninstall(for: ObjectIdentifier(drawer))
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the View Inspector plugin. Its borders, grid and click indicators are drawn in a
    /// window of the drawer's own over each of the app's windows, never in them; the grid shows
    /// only over views under `.debugGrid()`. On iOS it also swaps `UIWindow.sendEvent(_:)` once,
    /// so the click indicators switch can show touches; the swap forwards every event unchanged.
    func installViewInspector() {
        #if DEBUG
            // Adding the plugin installs it, which swaps the touch method on iOS.
            registerGlobal(ViewInspectorPlugin())
        #endif
    }
}

#if !DEBUG
    public extension View {
        /// Returns the view unchanged: release builds draw no grid.
        ///
        /// - Returns: This view.
        func debugGrid() -> some View { self }
    }
#endif
