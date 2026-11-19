#if DEBUG
    import Foundation

    /// A window drawn into an image, encoded: what a ``ScreenshotCapturer`` hands the model.
    struct ScreenshotImage: Codable, Equatable, Sendable {
        /// The image as PNG.
        var png: Data
        /// Its width in pixels.
        var pixelWidth: Int
        /// Its height in pixels.
        var pixelHeight: Int
        /// Pixels per point: the window's backing scale.
        var scale: Double
    }
#endif
