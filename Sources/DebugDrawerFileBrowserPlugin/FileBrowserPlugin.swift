import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` does not,
// so release builds get an empty view.

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

    #if DEBUG
        let model: FileBrowserModel

        init(model: FileBrowserModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            FileBrowserPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is read until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, goes back to the list of roots and
    /// drops the listings, previews and folder totals it read. No file is touched.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// The root being browsed, so where the browser is shows while the plugin is closed.
    public var headerAccessory: some View {
        #if DEBUG
            FileBrowserHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
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
