#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import DebugDrawer

    /// Hides the drawer (when asked) and the HUD, then draws the app's key window in process: no
    /// screen capture, so no Screen Recording permission.
    @MainActor
    struct _ScreenshotCapturer: ScreenshotCapturer {
        func capture(hidingDrawer: Bool) async throws(ScreenshotFailure) -> ScreenshotImage {
            // The drawer runs the capture once the hiding has rendered and shows itself again after.
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<ScreenshotImage, ScreenshotFailure>, Never>) in
                DebugDrawer.shared.performWhileHidden(drawer: hidingDrawer) {
                    continuation.resume(returning: Self.captureKeyWindow())
                }
            }
            return try result.get()
        }

        #if os(macOS)
            /// The app's key window, not the drawer's panel when its search field has focus.
            private static func captureKeyWindow() -> Result<ScreenshotImage, ScreenshotFailure> {
                guard let window = debugDrawerAppKeyWindow else { return .failure(.noWindow) }
                guard let bitmap = WindowCapture.bitmap(of: window),
                      let png = bitmap.representation(using: .png, properties: [:])
                else { return .failure(.encodingFailed) }
                return .success(ScreenshotImage(
                    png: png, pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh,
                    scale: Double(window.backingScaleFactor)
                ))
            }
        #elseif os(iOS)
            /// The app's key window, not the drawer's when its search field has focus.
            private static func captureKeyWindow() -> Result<ScreenshotImage, ScreenshotFailure> {
                guard let window = debugDrawerAppKeyWindow else { return .failure(.noWindow) }
                let image = WindowCapture.image(of: window)
                guard let png = image.pngData() else { return .failure(.encodingFailed) }
                return .success(ScreenshotImage(
                    png: png,
                    pixelWidth: Int((image.size.width * image.scale).rounded()),
                    pixelHeight: Int((image.size.height * image.scale).rounded()),
                    scale: Double(image.scale)
                ))
            }
        #endif
    }
#endif
