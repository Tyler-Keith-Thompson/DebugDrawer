#if DEBUG
    import SwiftUI
    import UniformTypeIdentifiers

    /// Reads the model and hands what it shows to `FileBrowserView`. It loads each place the
    /// model shows, and presents the file importer for Import.
    struct FileBrowserPluginView: View {
        @ObservedObject var model: FileBrowserModel
        @State private var isImporting = false

        var body: some View {
            FileBrowserView(
                screen: model.screen,
                folderSizes: model.folderSizes,
                failure: model.failure,
                actions: FileBrowserActions(
                    open: model.show,
                    back: model.back,
                    refresh: model.refresh,
                    importFile: { isImporting = true },
                    rename: { item, name in Task { await model.rename(item, to: name) } },
                    delete: { item in Task { await model.delete(item) } }
                )
            )
            // Cancelled and started again for every place shown, so leaving a folder stops
            // counting its totals.
            .task(id: model.request) { await model.load(model.request) }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                if case let .success(url) = result {
                    Task { await model.importFile(from: url) }
                }
            }
        }
    }
#endif
