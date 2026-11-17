#if DEBUG
    import Foundation

    /// Where the mockup and its settings are kept between launches.
    protocol MockupStorage: Sendable {
        /// The saved mockup's data, or `nil` when none is saved.
        func loadMockup() -> Data?
        /// Saves `data` as the mockup, replacing the one saved before.
        ///
        /// - Throws: `MockupFailure.notSaved` when it can't be written.
        func saveMockup(_ data: Data) throws(MockupFailure)
        /// Removes the saved mockup; none saved is no error.
        func removeMockup()
        /// The saved settings, or `nil` when none are saved or they can't be read.
        func loadSettings() -> DesignOverlaySettings?
        /// Saves `settings`, replacing those saved before; a failure is ignored, since the
        /// settings still apply until the app quits.
        func saveSettings(_ settings: DesignOverlaySettings)
    }
#endif
