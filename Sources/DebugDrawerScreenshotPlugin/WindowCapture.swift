#if DEBUG
    #if os(macOS)
        import AppKit

        /// Draws the app's own views into an image, in process: no screen capture, so no Screen
        /// Recording permission. Content drawn outside the view tree (Metal layers, video) may
        /// come out blank.
        @MainActor
        enum WindowCapture {
            /// The view as a bitmap at `scale` pixels per point, or nil when it has no area.
            static func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
                let bounds = view.bounds
                guard bounds.width > 0, bounds.height > 0,
                      let bitmap = NSBitmapImageRep(
                          bitmapDataPlanes: nil,
                          pixelsWide: Int((bounds.width * scale).rounded()),
                          pixelsHigh: Int((bounds.height * scale).rounded()),
                          bitsPerSample: 8,
                          samplesPerPixel: 4,
                          hasAlpha: true,
                          isPlanar: false,
                          colorSpaceName: .deviceRGB,
                          bytesPerRow: 0,
                          bitsPerPixel: 0
                      )
                else { return nil }
                // Sizing the rep in points makes cacheDisplay draw at `scale`.
                bitmap.size = bounds.size
                view.cacheDisplay(in: bounds, to: bitmap)
                return bitmap
            }

            /// The window's content, at the window's backing scale.
            static func bitmap(of window: NSWindow) -> NSBitmapImageRep? {
                guard let view = window.contentView else { return nil }
                return bitmap(of: view, scale: window.backingScaleFactor)
            }
        }
    #elseif os(iOS)
        import UIKit

        /// Draws the app's own window into an image, in process.
        @MainActor
        enum WindowCapture {
            /// The whole window, so sheets, alerts and anything else presented in it are
            /// included, not only the root view controller's view.
            static func image(of window: UIWindow) -> UIImage {
                UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
            }
        }
    #endif
#endif
