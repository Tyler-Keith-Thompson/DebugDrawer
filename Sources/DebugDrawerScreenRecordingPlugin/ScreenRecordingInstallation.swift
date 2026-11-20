#if DEBUG
    import DebugDrawer

    /// What `ScreenRecording.install(capacity:in:)` does in debug builds.
    @MainActor
    enum ScreenRecordingInstallation {
        /// Registers the plugin with `drawer` over the drawer's own model: the recordings in
        /// `RecordingFolder.standard`, kept to `capacity`, with Show Touches remembered in the
        /// drawer's defaults. Lists the recordings already saved. Installed in `drawer` before, the
        /// plugin stays registered: it shows the same model, so a recording in progress goes on.
        ///
        /// The model is the drawer's (`DebugDrawer.installerState(_:)`), so a drawer made for a
        /// test records, lists and counts apart from `DebugDrawer.shared`.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(capacity: Int, in drawer: DebugDrawer) -> ScreenRecordingModel {
            let model = drawer.installerState {
                ScreenRecordingModel(
                    folder: .standard,
                    capacity: capacity,
                    frameSource: DisplayLinkFrameSource(),
                    makeWriter: { AssetMovieWriter(url: $0) },
                    defaults: drawer.defaults
                )
            }
            model.capacity = capacity
            // Not removed first: that would uninstall it, stopping a recording in progress. A
            // plugin over the same model already registered makes this register nothing.
            drawer.registerGlobal(ScreenRecordingPlugin(model: model))
            Task { await model.load() }
            return model
        }
    }
#endif
