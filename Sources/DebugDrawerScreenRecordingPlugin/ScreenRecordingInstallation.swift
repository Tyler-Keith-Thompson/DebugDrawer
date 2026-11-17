#if DEBUG
    import DebugDrawer

    /// What `ScreenRecording.install(capacity:)` does in debug builds.
    @MainActor
    enum ScreenRecordingInstallation {
        /// The model the installed plugin shows: one per process, so installing again keeps a
        /// recording in progress.
        private static var model: ScreenRecordingModel?

        /// Registers the plugin over the recordings in `RecordingFolder.standard`, kept to
        /// `capacity`, replacing one installed before, and lists the recordings already saved.
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
            let plugin = ScreenRecordingPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            Task { await model.load() }
            return model
        }
    }
#endif
