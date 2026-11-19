import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Captures the app's key window: on macOS to a PNG on the Desktop or to the clipboard, on iOS to
/// the clipboard.
public struct ScreenshotPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "ScreenshotPlugin"
    }

    public var title = "Screenshot"
    public var category = "Interface"
    public var icon = "camera"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one, which is made only once
        /// something reads it.
        private let model: ScreenshotModel?

        /// The plugin over the app's own windows and the user's Desktop.
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show in place of the shared one.
        init(model: ScreenshotModel) {
            self.model = model
        }
    #else
        /// The plugin over the app's own windows and the user's Desktop.
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            ScreenshotPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the last capture, where it
    /// went, and a capture still waiting for a place to be saved. Files already saved stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Screenshot plugin.
    func installScreenshot() {
        #if DEBUG
            registerGlobal(ScreenshotPlugin())
        #endif
    }
}
