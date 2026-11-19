import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// The App Info plugin: the build (version, commit, branch, CI build), the process, the device,
/// the provisioning profile and the entitlements.
public struct AppInfoPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "AppInfoPlugin"
    }

    public var title = "App Info"
    public var category = "App"
    public var icon = "info.circle"

    let buildMetadata: AppInfoBuildMetadata

    #if DEBUG
        /// The model the plugin shows and refreshes, or `nil` for ``AppInfoModel/shared``, which
        /// is made only once something reads it.
        let model: AppInfoModel?

        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        @MainActor public init(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            self.buildMetadata = buildMetadata
            model = nil
        }

        /// - Parameters:
        ///   - buildMetadata: The commit, branch and CI build to show.
        ///   - model: The model to show and refresh in place of the shared one.
        init(buildMetadata: AppInfoBuildMetadata, model: AppInfoModel) {
            self.buildMetadata = buildMetadata
            self.model = model
        }
    #else
        /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
        ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
        @MainActor public init(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
            self.buildMetadata = buildMetadata
        }
    #endif

    public var body: some View {
        #if DEBUG
            AppInfoPluginView(transport: .direct(to: model ?? .shared))
        #else
            EmptyView()
        #endif
    }

    /// Reads the facts, the memory footprint and uptime among them, now and every 2 seconds
    /// after: the plugin's view is on screen in `drawer`. Release builds read nothing.
    @MainActor public func didBecomeVisible(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).addViewer()
        #endif
    }

    /// Stops the refreshing ``didBecomeVisible(in:)`` started, once no drawer shows the plugin.
    @MainActor public func didBecomeHidden(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).removeViewer()
        #endif
    }

    /// Starts watching the network's reachability, for the Network fact, the bug report and Copy
    /// Info, once the first drawer holds the plugin. Release builds watch nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).install(in: ObjectIdentifier(drawer), buildMetadata: buildMetadata)
        #endif
    }

    /// Stops watching the network once the last drawer that held the plugin removes it, and
    /// forgets the status it read. The build, signing and process facts are read again when
    /// shown, and nothing is kept on disk.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            (model ?? .shared).uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Adds the App Info plugin, replacing one added before.
    ///
    /// Only the network's reachability is watched from here on; the rest is read when the plugin
    /// is shown or a report is made.
    ///
    /// - Parameter buildMetadata: The commit, branch and CI build to show; each one `nil` is
    ///   read from the main bundle's Info.plist (``AppInfoBuildMetadata``).
    func installAppInfo(buildMetadata: AppInfoBuildMetadata = AppInfoBuildMetadata()) {
        #if DEBUG
            let plugin = AppInfoPlugin(buildMetadata: buildMetadata)
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        #endif
    }
}
