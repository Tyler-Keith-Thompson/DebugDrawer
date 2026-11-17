#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The app's stores, each open to its tables or entities, a table's rows paged and searched in
    /// a grid, and a read-only query editor.
    public struct DatabaseBrowserPlugin: DebugDrawerPlugin {
        public var id: String {
            "DatabaseBrowserPlugin"
        }

        public var title = "Databases"
        public var category = "Storage"
        public var icon = "cylinder.split.1x2"

        let model: DatabaseBrowserModel

        init(model: DatabaseBrowserModel) {
            self.model = model
        }

        public var body: some View {
            DatabaseBrowserPluginView(model: model)
        }

        /// How many stores were found, so the count shows while the plugin is closed.
        public var headerAccessory: some View {
            DatabaseBrowserHeaderAccessory(model: model)
        }

        /// Refresh, found by "SQLite", "Core Data" and "SwiftData" too.
        public var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Refresh databases", keywords: ["database", "SQLite", "Core Data", "SwiftData", "store"]) { [model] in
                    Task { await model.refresh() }
                }
            ]
        }
    }

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
