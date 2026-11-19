#if DEBUG
    /// Draws the app's key window into an image.
    ///
    /// The Screenshot model asks it for each capture; `_ScreenshotCapturer` hides the drawer and
    /// draws the window in process, and a test passes one of its own.
    @MainActor
    protocol ScreenshotCapturer {
        /// The app's key window as it looks now, encoded as PNG.
        ///
        /// - Parameter hidingDrawer: Whether the drawer hides while the window is drawn; the HUD
        ///   always does.
        /// - Returns: The window's image.
        /// - Throws: ``ScreenshotFailure/noWindow`` with no key window, and
        ///   ``ScreenshotFailure/encodingFailed`` when it doesn't draw into a PNG.
        func capture(hidingDrawer: Bool) async throws(ScreenshotFailure) -> ScreenshotImage
    }
#endif
