#if DEBUG
    import DebugDrawer
    import SwiftUI
    import UniformTypeIdentifiers

    /// The plugin's body: draws ``FileBrowserModel``'s snapshots from its transport through
    /// `FileBrowserView`, and sends the model what the user does. The model reads while the view
    /// is on screen, so leaving the drawer stops the counting of folder totals. The file importer
    /// for Import is presented here, and Share, Copy and Reveal in Finder stay in the views.
    struct FileBrowserPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<FileBrowserSnapshot, FileBrowserCommand>
        @State private var isImporting = false

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<FileBrowserSnapshot, FileBrowserCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            FileBrowserView(
                screen: snapshot.screen,
                folderSizes: snapshot.folderSizes,
                failure: snapshot.failure,
                actions: FileBrowserActions(
                    open: { send(.open($0)) },
                    back: { send(.back) },
                    refresh: { send(.refresh) },
                    importFile: { isImporting = true },
                    rename: { send(.rename($0, to: $1)) },
                    delete: { send(.delete($0)) }
                )
            )
            .onAppear { send(.startReading) }
            .onDisappear { send(.stopReading) }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                if case let .success(url) = result {
                    send(.importFile(url))
                }
            }
        }

        private func send(_ action: FileBrowserCommand.Action) {
            transport.send(FileBrowserCommand(action))
        }
    }
#endif
