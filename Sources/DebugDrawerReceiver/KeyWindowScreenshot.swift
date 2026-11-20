import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit) && !os(watchOS)
    import UIKit
#endif

// A bug report's screenshot: the app draws its own key window into an image, in process, so no
// screen capture and no Screen Recording permission, and nothing of another app or the system's
// UI. Content drawn outside the view tree (Metal layers, video) may come out blank. AppKit and
// UIKit rather than SwiftUI's ImageRenderer, which draws one view, not a window with its sheets
// and alerts. The Screenshot plugin has the same few lines, but it is debug-only and a release
// build doesn't link it; these are duplicated rather than shared (the charter's N4).
//
// A window drawn at its own scale that doesn't fit the bound is drawn again at one pixel per
// point, which is a quarter of the bytes on a 2x display, before it is left out.

/// Draws the app's key window as PNG.
@MainActor
enum KeyWindowScreenshot {
    /// The key window as PNG of at most `maximumBytes`, or why there is none.
    static func capture(maximumBytes: Int) -> DebugDrawerBugReports.Screenshot {
        #if os(macOS)
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return .unavailable }
            return capture(window, maximumBytes: maximumBytes)
        #elseif canImport(UIKit) && !os(watchOS)
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            guard let window = windows.first(where: \.isKeyWindow) else { return .unavailable }
            return capture(window, maximumBytes: maximumBytes)
        #else
            return .unavailable
        #endif
    }

    #if os(macOS)
        /// `window`'s content as PNG of at most `maximumBytes`, at its backing scale or else at one
        /// pixel per point.
        static func capture(_ window: NSWindow, maximumBytes: Int) -> DebugDrawerBugReports.Screenshot {
            guard let view = window.contentView else { return .unavailable }
            return fitting(maximumBytes, scales: [window.backingScaleFactor, 1]) { png(of: view, scale: $0) }
        }
    #elseif canImport(UIKit) && !os(watchOS)
        /// `window` as PNG of at most `maximumBytes`, at its display scale or else at one pixel per
        /// point.
        static func capture(_ window: UIWindow, maximumBytes: Int) -> DebugDrawerBugReports.Screenshot {
            fitting(maximumBytes, scales: [window.traitCollection.displayScale, 1]) { png(of: window, scale: $0) }
        }
    #endif

    /// The first drawing, at each of `scales` in turn, that fits `maximumBytes`.
    private static func fitting(_ maximumBytes: Int, scales: [CGFloat], draw: (CGFloat) -> Data?) -> DebugDrawerBugReports.Screenshot {
        var largest = 0
        for scale in scales where scale > 0 {
            guard let data = draw(scale) else { return .unavailable }
            if data.count <= maximumBytes {
                return .png(data)
            }
            largest = data.count
        }
        return largest > 0 ? .tooLarge(byteCount: largest) : .unavailable
    }

    #if os(macOS)
        /// The view as PNG at `scale` pixels per point, or `nil` when it has no area.
        private static func png(of view: NSView, scale: CGFloat) -> Data? {
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
            return bitmap.representation(using: .png, properties: [:])
        }
    #elseif canImport(UIKit) && !os(watchOS)
        /// The whole window as PNG at `scale` pixels per point, so sheets and alerts presented in it
        /// are included; `nil` when it has no area.
        private static func png(of window: UIWindow, scale: CGFloat) -> Data? {
            guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
            let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
            format.scale = scale
            return UIGraphicsImageRenderer(bounds: window.bounds, format: format).pngData { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
    #endif
}
