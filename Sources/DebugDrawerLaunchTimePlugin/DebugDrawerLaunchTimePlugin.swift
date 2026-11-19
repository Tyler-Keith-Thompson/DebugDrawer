import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that measures and registers nothing.

/// How long the app took to launch: from the process's start to `installLaunchTime()`
/// (pre-main), from there to the first frame, and the total.
public struct LaunchTimePlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "LaunchTimePlugin"
    }

    public var title = "Launch Time"
    public var category = "Performance"
    public var icon = "timer"

    #if DEBUG
        /// The model the plugin shows and measures with, or `nil` for the shared one.
        private let model: LaunchTimeModel?

        public init() {
            model = nil
        }

        /// - Parameter model: The model to show and measure with in place of the shared one.
        init(model: LaunchTimeModel) {
            self.model = model
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            LaunchTimePluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Waits for the first frame: the first time the main run loop goes idle from now on, unless
    /// one is already recorded. Release builds measure nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer has the plugin, stops waiting for the first frame if it hasn't come yet,
    /// removing the run-loop observer. The times already measured stay: a launch happens once.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Install the launch time plugin. Call it as early as you can (your `App.init` or
    /// `application(_:didFinishLaunchingWithOptions:)`): app init is measured here, and
    /// the first frame is the first time the main run loop goes idle afterwards.
    func installLaunchTime() {
        #if DEBUG
            // Made now, so app init is measured here; the plugin's install waits for the first
            // frame.
            _ = LaunchTimeModel.shared
            registerGlobal(LaunchTimePlugin())
        #endif
    }
}
