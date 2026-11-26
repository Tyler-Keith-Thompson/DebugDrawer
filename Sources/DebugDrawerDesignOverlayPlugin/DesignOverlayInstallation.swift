#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `DesignOverlay.install()` and `install(mockup:)` do in debug builds.
    @MainActor
    enum DesignOverlayInstallation {
        /// Removes a plugin installed before, reads what `model` saved, and registers the plugin
        /// over `model`.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(model: DesignOverlayModel = .shared) -> DesignOverlayModel {
            install(showing: nil, model: model)
        }

        /// Removes a plugin installed before, reads what `model` saved, shows `mockup` in place of
        /// the saved one, and registers the plugin over `model`.
        ///
        /// - Returns: The plugin's model.
        /// - Throws: `DesignOverlay.NotAnImage` when `mockup` isn't the data of an image, before
        ///   anything changes.
        @discardableResult
        static func install(mockup: Data, model: DesignOverlayModel = .shared) throws(DesignOverlay.NotAnImage) -> DesignOverlayModel {
            // Decoded first, so data that isn't an image leaves the plugin installed before as it was.
            let decoded: Mockup
            do throws(MockupFailure) {
                decoded = try Mockup(data: mockup)
            } catch {
                throw DesignOverlay.NotAnImage()
            }
            return install(showing: decoded, model: model)
        }

        private static func install(showing mockup: Mockup?, model: DesignOverlayModel) -> DesignOverlayModel {
            let plugin = DesignOverlayPlugin(model: model)
            // First, so the old plugin's uninstall can't take away the mockup loaded here.
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            model.load()
            if let mockup {
                model.show(mockup, isSaved: false)
            }
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
