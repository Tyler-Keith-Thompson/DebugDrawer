import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The app's stores, each open to its tables or entities, a table's rows paged and searched in
/// a grid, and a read-only query editor.
public struct DatabaseBrowserPlugin: DebugDrawerPlugin {
    public var id: String {
        "DatabaseBrowserPlugin"
    }

    public var title = "Databases"
    public var category = "Storage"
    public var icon = "cylinder.split.1x2"

    #if DEBUG
        let model: DatabaseBrowserModel

        init(model: DatabaseBrowserModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            DatabaseBrowserPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Looks for the app's stores once the first drawer holds the plugin, so their count shows
    /// before it is opened. Release builds look for nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, drops the stores found, their
    /// schemas and the reader of each, and any read still running. The databases are untouched.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// How many stores were found, so the count shows while the plugin is closed.
    public var headerAccessory: some View {
        #if DEBUG
            DatabaseBrowserHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Refresh, found by "SQLite", "Core Data" and "SwiftData" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Refresh databases", keywords: ["database", "SQLite", "Core Data", "SwiftData", "store"]) { [model] in
                    Task { await model.refresh() }
                }
            ]
        #else
            []
        #endif
    }
}

#if DEBUG
    /// "3 stores" once any is found; nothing otherwise.
    struct DatabaseBrowserHeaderAccessory: View {
        @ObservedObject var model: DatabaseBrowserModel

        var body: some View {
            let count = model.listings.count
            if count > 0 {
                Text(count == 1 ? "1 store" : "\(count.formatted()) stores")
            }
        }
    }
#endif
