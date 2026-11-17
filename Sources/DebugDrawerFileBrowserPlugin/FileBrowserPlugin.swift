#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The app's folders, its bundle and its app groups' containers: each folder's files with
    /// their sizes and dates, folder totals, previews, and imports, renames and deletes outside
    /// the bundle.
    public struct FileBrowserPlugin: DebugDrawerPlugin {
        public var id: String {
            "FileBrowserPlugin"
        }

        public var title = "File Browser"
        public var category = "Storage"
        public var icon = "folder"

        let model: FileBrowserModel

        init(model: FileBrowserModel) {
            self.model = model
        }

        public var body: some View {
            FileBrowserPluginView(model: model)
        }

        /// The root being browsed, so where the browser is shows while the plugin is closed.
        public var headerAccessory: some View {
            FileBrowserHeaderAccessory(model: model)
        }
    }

    /// "Documents" while a folder or file under Documents is shown; nothing at the list of roots.
    struct FileBrowserHeaderAccessory: View {
        @ObservedObject var model: FileBrowserModel

        var body: some View {
            if let root = model.request.place.root {
                Text(root.title)
            }
        }
    }
#endif
