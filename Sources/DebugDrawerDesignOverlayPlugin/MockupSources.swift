#if DEBUG
    import Foundation

    /// What the plugin's pickers hand a picked image to.
    struct MockupSources {
        /// Opens an image's data, as a photo from Photos.
        let open: (Data) -> Void
        /// Opens the image file the file importer picked.
        let openFile: (URL) -> Void
        /// Opens the image on the pasteboard (macOS).
        let paste: () -> Void
        /// Says why a pick failed.
        let fail: (MockupFailure) -> Void

        /// Sources that do nothing, for a view shown without a model.
        static var none: MockupSources {
            MockupSources(open: { _ in }, openFile: { _ in }, paste: {}, fail: { _ in })
        }
    }
#endif
