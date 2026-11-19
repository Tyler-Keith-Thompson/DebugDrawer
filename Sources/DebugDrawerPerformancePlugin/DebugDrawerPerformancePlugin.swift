import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that samples and registers nothing.

/// The frame rate, dropped frames, memory footprint with its peak and CPU use per thread, as
/// they change.
public struct PerformancePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "PerformancePlugin"
    }

    public var title = "Performance"
    public var category = "Performance"
    public var icon = "gauge.with.dots.needle.33percent"

    #if DEBUG
        /// The model the plugin shows and samples with, or `nil` for ``PerformanceModel/shared``,
        /// which is made only once something reads it.
        private let model: PerformanceModel?

        public init() {
            model = nil
        }

        /// - Parameter model: The model to show and sample with in place of the shared one.
        init(model: PerformanceModel) {
            self.model = model
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            PerformancePluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// The frame rate and memory, for the floating HUD; none in release builds.
    public var hud: PerformanceHUD? {
        #if DEBUG
            PerformanceHUD(transport: .direct(to: model ?? .shared))
        #else
            nil
        #endif
    }

    /// Starts sampling the frame rate, memory and threads: the plugin's view or its HUD readout is
    /// on screen in `drawer`. Release builds sample nothing.
    @MainActor public func didBecomeVisible(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).addViewer()
        #endif
    }

    /// Stops the sampling ``didBecomeVisible(in:)`` started, once no drawer shows the plugin.
    @MainActor public func didBecomeHidden(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).removeViewer()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is sampled until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, stops any sampling still running and
    /// drops the frame, memory and thread history, so a later install starts from nothing.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Performance plugin. It samples only while its view or its HUD readout is on
    /// screen.
    func installPerformance() {
        #if DEBUG
            registerGlobal(PerformancePlugin())
        #endif
    }
}
