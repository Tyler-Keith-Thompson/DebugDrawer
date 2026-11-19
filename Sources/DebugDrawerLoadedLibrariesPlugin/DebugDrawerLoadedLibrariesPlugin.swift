import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Every image loaded into the process, grouped as App, Third-Party and System, each with its
/// path, UUID, load address and, for a framework, its version.
public struct LoadedLibrariesPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "LoadedLibrariesPlugin"
    }

    public var title = "Loaded Libraries"
    public var category = "App"
    public var icon = "books.vertical"

    #if DEBUG
        /// The model the plugin shows, or `nil` for the shared one.
        private let model: LoadedLibrariesModel?

        /// The plugin over the process's own loaded images.
        public init() {
            model = nil
        }

        /// - Parameter model: The model to show in place of the shared one.
        init(model: LoadedLibrariesModel) {
            self.model = model
        }
    #else
        /// The plugin over the process's own loaded images.
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            LoadedLibrariesPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is read until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the list of images it read.
    /// The plugin starts no work, so there is nothing to stop.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Loaded Libraries plugin, which reads the loaded images when its view appears.
    func installLoadedLibraries() {
        #if DEBUG
            registerGlobal(LoadedLibrariesPlugin())
        #endif
    }
}
