// iOS, and Mac Catalyst, whose scenes are UIKit's too (DrawerSceneWindow).
#if DEBUG && os(iOS)
    import UIKit

    // The drawer's windows take touches only where they draw something, but UIKit draws a context
    // menu, and a sheet or popover a hosted view presents, in views it adds to the source view's
    // window beside its content: the menu or sheet itself, past what the window draws, and a
    // full-screen backdrop that closes it on a tap anywhere else in the window. While those are in
    // the window it must take every touch, or a tap beside the menu reaches the app's window below
    // and the menu stays open. The content is found by identity, as the window's subview that is
    // or holds it (UIKit puts a root view controller's view in a transition view of its own),
    // rather than by UIKit's private class names (_UIContextMenuContainerView), which change.
    extension UIWindow {
        /// Whether UIKit has added views of its own to the window beside `content`, as it does while
        /// a context menu, sheet or popover from a view in it shows.
        ///
        /// - Parameter content: The view the window hosts its own content in.
        /// - Returns: `true` while the window holds a subview that neither is `content` nor holds it.
        func hasSubviews(besides content: UIView?) -> Bool {
            subviews.contains { subview in content?.isDescendant(of: subview) != true }
        }
    }
#endif
