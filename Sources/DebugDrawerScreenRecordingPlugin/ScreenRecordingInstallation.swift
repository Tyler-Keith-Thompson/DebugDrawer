#if DEBUG
    import DebugDrawer

    /// What `ScreenRecording.install(capacity:)` does in debug builds.
    @MainActor
    enum ScreenRecordingInstallation {
        /// The model the installed plugin shows: one per process, so installing again keeps a
        /// recording in progress.
        private static var model: ScreenRecordingModel?

        /// Registers the plugin over the recordings in `RecordingFolder.standard`, kept to
        /// `capacity`, and lists the recordings already saved. Installed before, the plugin stays
        /// registered: it shows the same model, so a recording in progress goes on.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(capacity: Int) -> ScreenRecordingModel {
            let model = model ?? ScreenRecordingModel(
                folder: .standard,
                capacity: capacity,
                frameSource: DisplayLinkFrameSource(),
                makeWriter: { AssetMovieWriter(url: $0) }
            )
            model.capacity = capacity
            self.model = model
            // Not removed first: that would uninstall it, stopping a recording in progress. A
            // plugin over the same model already registered makes this register nothing.
            DebugDrawer.shared.registerGlobal(ScreenRecordingPlugin(model: model))
            Task { await model.load() }
            return model
        }
    }
#endif
