#if DEBUG
    import Foundation

    /// The last capture the plugin took: the image, when it was taken and the name it is saved
    /// under.
    struct ScreenshotCapture: Codable, Equatable, Sendable {
        /// The window as it was drawn.
        var image: ScreenshotImage
        /// When it was taken.
        var date: Date
        /// The file name it is saved under: the app's name and the time it was taken.
        var filename: String
    }
#endif
