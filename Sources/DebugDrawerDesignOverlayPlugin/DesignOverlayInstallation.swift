#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `DesignOverlay.install(mockup:)` does in debug builds.
    @MainActor
    enum DesignOverlayInstallation {
        /// Reads what `model` saved, shows `mockup` in place of the saved one, and registers the
        /// plugin over `model`, replacing one installed before.
        ///
        /// - Precondition: `mockup` is `nil` or the data of an image.
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(mockup: Data?, model: DesignOverlayModel = .shared) -> DesignOverlayModel {
            model.load()
            if let mockup {
                do {
                    model.show(try Mockup(data: mockup), isSaved: false)
                } catch {
                    // A programmer's error: the app handed install bytes of its own that aren't an
                    // image, which no one can fix at runtime.
                    preconditionFailure("DesignOverlay.install(mockup:) takes the data of an image")
                }
            }
            let plugin = DesignOverlayPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
