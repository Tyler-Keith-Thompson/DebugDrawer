#if DEBUG && (os(macOS) || os(iOS))
    import CoreGraphics
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif

    /// Where one of the app's views is, as a value: its frame in an overlay's coordinates and how
    /// deep it sits in its window, read without keeping or changing the view.
    struct ViewOutline: Equatable {
        /// The view's bounds in the overlay's content, in points from its top-leading corner.
        var frame: CGRect
        /// How many superviews the view has below the root that was read.
        var depth: Int

        #if os(macOS)
            /// The outlines of `root` and every view under it that is shown and has an area, root
            /// first, each placed by `place` from the view's bounds in its window's coordinates.
            ///
            /// - Parameters:
            ///   - root: A window's content view.
            ///   - place: Converts a rectangle in the window's base coordinates to the overlay's.
            /// - Returns: The outlines, depth first.
            @MainActor
            static func read(from root: NSView, placing place: (CGRect) -> CGRect) -> [ViewOutline] {
                var outlines: [ViewOutline] = []
                root.appendOutlines(depth: 0, to: &outlines, placing: place)
                return outlines
            }
        #else
            /// The outlines of `window` and every view under it that is shown and has an area,
            /// window first, in `overlay`'s coordinates.
            ///
            /// - Parameters:
            ///   - window: One of the app's windows.
            ///   - overlay: The window whose coordinates the outlines are in.
            /// - Returns: The outlines, depth first.
            @MainActor
            static func read(from window: UIWindow, in overlay: UIWindow) -> [ViewOutline] {
                // The caller picked the window, so it is outlined whether or not it is hidden (one
                // made in code is until it is shown); its views are outlined while they show.
                let place = { (rect: CGRect) in window.convert(rect, to: overlay) }
                var outlines = window.bounds.isEmpty ? [] : [ViewOutline(frame: place(window.bounds), depth: 0)]
                for subview in window.subviews {
                    subview.appendOutlines(depth: 1, to: &outlines, placing: place)
                }
                return outlines
            }
        #endif
    }

    #if os(macOS)
        extension NSView {
            // The grid's probe is the plugin's, so it is no view of the app's to outline.
            @MainActor
            fileprivate func appendOutlines(depth: Int, to outlines: inout [ViewOutline], placing place: (CGRect) -> CGRect) {
                guard !isHidden, alphaValue > 0, !(self is GridProbeView) else { return }
                if bounds.width > 0, bounds.height > 0 {
                    outlines.append(ViewOutline(frame: place(convert(bounds, to: nil)), depth: depth))
                }
                for subview in subviews {
                    subview.appendOutlines(depth: depth + 1, to: &outlines, placing: place)
                }
            }
        }
    #else
        extension UIView {
            @MainActor
            fileprivate func appendOutlines(depth: Int, to outlines: inout [ViewOutline], placing place: (CGRect) -> CGRect) {
                guard !isHidden, alpha > 0, !(self is GridProbeView) else { return }
                if bounds.width > 0, bounds.height > 0 {
                    outlines.append(ViewOutline(frame: place(convert(bounds, to: nil)), depth: depth))
                }
                for subview in subviews {
                    subview.appendOutlines(depth: depth + 1, to: &outlines, placing: place)
                }
            }
        }
    #endif
#endif
